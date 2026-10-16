-- =====================================================================
-- 052: Tối ưu tốc độ (anh Thuận báo phần mềm chậm, 17/10)
--  1. public.tien_dong_co_vat: bỏ cài đặt múi giờ trong hàm → Postgres "ép" thẳng công thức vào câu lệnh gọi (inline) thay vì
--     gọi hàm từng dòng. Công thức và kết quả giữ nguyên; dùng giờ Việt Nam ghi rõ trong công thức.
--     Hàm này nằm trong mọi phép cộng tiền của v_ho_so / v_canh_bao / báo cáo; đo với 5.000 hồ sơ thì hai view đó nhanh hơn khoảng 18–28%.
--  2. public.khoi_dong(): MỘT lượt gọi trả người đăng nhập + toàn bộ danh mục (trước đây 2 đợt nối tiếp, ~12 lượt đọc riêng).
--  3. public.viec_hom_nay() + public.canh_bao_hom_nay(): hai lượt gọi trả mọi thứ trang "Việc hôm nay" cần (trước đây 12 lượt đọc,
--     đọc v_ho_so 4 lần). v_ho_so đọc một lần; các danh sách lọc theo đúng vai trò như giao diện vẫn làm.
--  Tương thích ngược: chỉ thêm hàm mới và thay công thức tính tiền bằng công thức giống hệt; giao diện cũ không gọi hàm mới.
--  Cả hai hàm mới chạy bằng quyền người gọi (RLS áp dụng y hệt các lượt đọc riêng lẻ).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tiền có VAT: hàm SQL thuần, không cài đặt riêng → được inline
--    (không dùng chữ "now()" / "current_date" trong thân hàm để đợt gắn múi giờ cuối các migration không gắn lại cài đặt)
-- ---------------------------------------------------------------------
create or replace function public.tien_dong_co_vat(so_tien numeric, xuat_hd boolean, ngay date, ty_le numeric)
returns numeric
language sql stable as $$
  select case when so_tien is null then 0
              when xuat_hd then round(so_tien * (1 + coalesce(ty_le, public.vat_ty_le(coalesce(ngay, timezone('Asia/Ho_Chi_Minh', transaction_timestamp())::date)))))
              else so_tien end
$$;

-- ---------------------------------------------------------------------
-- 2. Đọc một bảng danh mục cho khoi_dong(): đủ cột, xếp theo cột khóa, lỗi (thiếu quyền…) thì coi như rỗng
--    (đúng như giao diện cũ: .catch(() => [])). Chạy bằng quyền người gọi.
-- ---------------------------------------------------------------------
create or replace function app.doc_bang(p_bang text, p_cot_sap text default 'id')
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare v jsonb;
begin
  if p_bang not in ('chi_nhanh','hang_bao_hiem','giam_dinh_vien','hang_xe','dong_xe','to_thuc_hien','muc_thu_chi',
                    'nha_cung_cap','don_vi_lien_quan','v_don_vi_lien_quan','cai_dat','tai_khoan_quy','nhan_vien') then
    raise exception 'Bảng % không thuộc danh mục khởi động.', p_bang;
  end if;
  begin
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.%I), %L::jsonb) from public.%I t', p_cot_sap, '[]', p_bang) into v;
  exception when others then
    v := '[]'::jsonb;
  end;
  return v;
end $$;
revoke execute on function app.doc_bang(text, text) from public, anon;
grant execute on function app.doc_bang(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Khởi động ứng dụng: người đăng nhập + danh mục, một lượt
--    toi       = dòng nhan_vien của người gọi (null nếu chưa có hồ sơ nhân viên)
--    danh_muc  = null khi chưa được cấp vai trò / đã khóa / đang phải đổi mật khẩu (giao diện hiện màn hình riêng cho các trường hợp này),
--                ngược lại là { tên_bảng: [dòng…] }. Bảng nào người gọi không được xem thì không có khóa đó (như giao diện cũ).
-- ---------------------------------------------------------------------
create or replace function public.khoi_dong()
returns jsonb
language plpgsql stable
set search_path = public
as $$
declare
  v_toi public.nhan_vien;
  v_dm jsonb;
begin
  select * into v_toi from public.nhan_vien where id = (select auth.uid());
  if not found then
    return jsonb_build_object('toi', null, 'danh_muc', null);
  end if;
  if not v_toi.hoat_dong or coalesce(cardinality(v_toi.vai_tro), 0) = 0 or coalesce(v_toi.phai_doi_mat_khau, false) then
    return jsonb_build_object('toi', to_jsonb(v_toi), 'danh_muc', null);
  end if;
  v_dm := jsonb_build_object(
    'chi_nhanh', app.doc_bang('chi_nhanh'),
    'hang_bao_hiem', app.doc_bang('hang_bao_hiem'),
    'giam_dinh_vien', app.doc_bang('giam_dinh_vien'),
    'hang_xe', app.doc_bang('hang_xe'),
    'dong_xe', app.doc_bang('dong_xe'),
    'to_thuc_hien', app.doc_bang('to_thuc_hien'),
    'muc_thu_chi', app.doc_bang('muc_thu_chi'),
    'nha_cung_cap', app.doc_bang('nha_cung_cap'),
    -- nợ đầu kỳ nội bộ chỉ giám đốc / kế toán / quản lý chung / cổ đông đọc; vai khác đọc tên đơn vị qua view (043)
    'don_vi_lien_quan', app.doc_bang(case when v_toi.vai_tro && array['giam_doc','ke_toan','quan_ly','co_dong']
                                          then 'don_vi_lien_quan' else 'v_don_vi_lien_quan' end),
    -- bảng cài đặt khóa theo "khoa", không có cột id (trước đây giao diện xếp theo id nên đọc lỗi và luôn dùng giá trị mặc định)
    'cai_dat', app.doc_bang('cai_dat', 'khoa'));
  if v_toi.vai_tro && array['giam_doc','ke_toan','quan_ly','co_dong'] then
    v_dm := v_dm || jsonb_build_object('tai_khoan_quy', app.doc_bang('tai_khoan_quy'));
  end if;
  if v_toi.vai_tro && array['giam_doc','quan_ly','ke_toan','cvdv','kho','co_dong'] then
    v_dm := v_dm || jsonb_build_object('nhan_vien', app.doc_bang('nhan_vien'));
  end if;
  return jsonb_build_object('toi', to_jsonb(v_toi), 'danh_muc', v_dm);
end $$;
revoke execute on function public.khoi_dong() from public, anon;
grant execute on function public.khoi_dong() to authenticated;

-- ---------------------------------------------------------------------
-- 4. Trang "Việc hôm nay": mọi danh sách một lượt (khớp từng danh sách giao diện cũ tải riêng, cùng bộ lọc theo vai trò)
--    ho_so           xe chưa đóng / hủy                                            (nhân viên văn phòng)
--    cham_soc_dong   xe đã giao, đã đóng, chưa gọi chăm sóc (mới nhất 300)         (quản lý chung, giám đốc)
--    hoa_hong_dong   xe đã giao, đã đóng, có GDV, chưa nhập hoa hồng (mới nhất 300) (kế toán, giám đốc)
--    bang_viec       bảng việc xưởng (bang_viec_to; giám đốc: giao diện lọc tiếp theo chi nhánh đang chọn)
--    de_xuat / mua / nhap / chi / dvn / thieu / tai_san   các phiếu và việc kho, thu chi, đồ nghề
--    Giám đốc xem được mọi chi nhánh nhưng màn hình chỉ hiện chi nhánh đang chọn (045): lọc theo chi nhánh của nhan_vien.
--    v_ho_so chỉ tính MỘT lần (các phép cộng tiền theo cả lịch sử là phần tốn nhất) rồi chia thành các danh sách.
--    Danh sách "việc cần xử lý" (v_canh_bao, cũng tính trên mọi hồ sơ) tách riêng thành canh_bao_hom_nay() để giao diện gọi
--    SONG SONG với hàm này: hai phần nặng chạy cùng lúc trên máy chủ thay vì nối tiếp.
-- ---------------------------------------------------------------------
create or replace function public.viec_hom_nay()
returns json
language plpgsql stable
set search_path = public
as $$
declare
  v_vp boolean := app.la_nhan_vien();
  v_quan_ly boolean := app.co_vai_tro('quan_ly', 'giam_doc');
  v_ke_toan boolean := app.co_vai_tro('ke_toan', 'giam_doc');
  v_kho boolean := app.co_vai_tro('kho', 'giam_doc', 'quan_ly');
  v_gd boolean := app.co_vai_tro('giam_doc');
  v_cn text := app.chi_nhanh();
  v_loc text;                                         -- chi nhánh cần lọc (chỉ giám đốc)
  o_ho_so json := '[]'; o_cham_soc json := '[]'; o_hoa_hong json := '[]';
  o_bang_viec json := '[]'; o_de_xuat json := '[]'; o_mua json := '[]'; o_nhap json := '[]'; o_chi json := '[]';
  o_dvn json := '[]'; o_thieu json := '[]'; o_tai_san json := '[]';
begin
  v_loc := case when v_gd then v_cn end;

  if v_vp then
    -- Chỉ lấy mã hồ sơ cần dùng, rồi tính v_ho_so một lần cho các mã đó
    with can as (
      select h.id from public.ho_so h
      where h.trang_thai not in ('dong', 'huy') and (v_loc is null or h.chi_nhanh_id = v_loc)
      union
      (select h.id from public.ho_so h
        where v_quan_ly and h.trang_thai = 'dong' and h.giao_luc is not null and not h.tu_excel and h.cham_soc_luc is null
          and (v_loc is null or h.chi_nhanh_id = v_loc)
        order by h.giao_luc desc limit 300)
      union
      (select h.id from public.ho_so h
        where v_ke_toan and h.trang_thai = 'dong' and h.giao_luc is not null and not h.tu_excel
          and h.gdv_id is not null and h.hoa_hong_gdv is null and (v_loc is null or h.chi_nhanh_id = v_loc)
        order by h.giao_luc desc limit 300)
    ), hs as materialized (
      select v.* from public.v_ho_so v where v.id in (select id from can)
    )
    select
      coalesce((select json_agg(a) from hs a where a.trang_thai not in ('dong', 'huy')), '[]'),
      coalesce((select json_agg(b) from (
          select * from hs where v_quan_ly and trang_thai = 'dong' and giao_luc is not null and not tu_excel and cham_soc_luc is null
          order by giao_luc desc limit 300) b), '[]'),
      coalesce((select json_agg(c) from (
          select * from hs where v_ke_toan and trang_thai = 'dong' and giao_luc is not null and not tu_excel
            and gdv_id is not null and hoa_hong_gdv is null
          order by giao_luc desc limit 300) c), '[]')
    into o_ho_so, o_cham_soc, o_hoa_hong;

    if v_kho then
      o_de_xuat := coalesce((select json_agg(x order by x.id) from public.v_de_xuat x
                             where x.trang_thai = 'cho_xuat' and (v_loc is null or x.chi_nhanh_id = v_loc)), '[]');
      o_thieu := coalesce((select json_agg(json_build_object('id', t.id)) from public.v_ton_kho t
                           where t.duoi_toi_thieu and t.hoat_dong and (v_loc is null or t.chi_nhanh_id = v_loc)), '[]');
    end if;
    if app.co_vai_tro('quan_ly', 'giam_doc', 'kho') then
      o_mua := coalesce((select json_agg(m order by m.id) from public.v_de_nghi_mua m
                         where m.trang_thai in ('cho_duyet', 'da_duyet') and (v_loc is null or m.chi_nhanh_id = v_loc)), '[]');
    end if;
    if v_ke_toan then
      o_nhap := coalesce((select json_agg(p order by p.id) from public.v_phieu_nhap p
                          where p.trang_thai in ('cho_khop', 'treo') and (v_loc is null or p.chi_nhanh_id = v_loc)), '[]');
      -- 043: lượt dịch vụ nhanh còn phải thu, không giới hạn theo ngày
      o_dvn := coalesce((select json_agg(d order by d.ngay) from (
                           select * from public.v_dich_vu_nhanh
                           where trang_thai = 'hieu_luc' and con_thu > 0 and (v_loc is null or chi_nhanh_id = v_loc)
                           order by ngay limit 200) d), '[]');
    end if;
    if app.co_vai_tro('quan_ly', 'giam_doc', 'ke_toan') then
      o_chi := coalesce((select json_agg(n order by n.id) from public.v_de_nghi_chi n
                         where n.trang_thai in ('cho_duyet', 'da_duyet') and (v_loc is null or n.chi_nhanh_id = v_loc)), '[]');
    end if;
  end if;

  if app.co_vai_tro('truong_nhom', 'quan_ly', 'cvdv', 'ke_toan', 'giam_doc') then
    o_bang_viec := public.bang_viec_to()::json;
  end if;

  -- Đồ nghề (028): hàng việc theo chi nhánh của người gọi; giao diện lọc tiếp theo vai trò / tổ
  if (v_vp or app.co_vai_tro('truong_nhom')) and app.co_vai_tro('giam_doc', 'quan_ly', 'ke_toan', 'kho', 'truong_nhom') then
    o_tai_san := coalesce((select json_agg(s) from public.v_viec_tai_san s where s.chi_nhanh_id = v_cn), '[]');
  end if;

  return json_build_object(
    'ho_so', o_ho_so, 'cham_soc_dong', o_cham_soc, 'hoa_hong_dong', o_hoa_hong,
    'bang_viec', o_bang_viec, 'de_xuat', o_de_xuat, 'mua', o_mua, 'nhap', o_nhap, 'chi', o_chi,
    'dvn', o_dvn, 'thieu', o_thieu, 'tai_san', o_tai_san);
end $$;
revoke execute on function public.viec_hom_nay() from public, anon;
grant execute on function public.viec_hom_nay() to authenticated;

-- ---------------------------------------------------------------------
-- 5. Việc cần xử lý (v_canh_bao) cho trang "Việc hôm nay": bỏ nhắc "thiếu GDV" (048: trùng việc chờ duyệt giá), giám đốc chỉ thấy chi nhánh đang chọn.
--    Nhân viên văn phòng mới có (như giao diện cũ); vai khác nhận danh sách rỗng.
-- ---------------------------------------------------------------------
create or replace function public.canh_bao_hom_nay()
returns json
language plpgsql stable
set search_path = public
as $$
declare v_loc text := case when app.co_vai_tro('giam_doc') then app.chi_nhanh() end;
begin
  if not app.la_nhan_vien() then return '[]'::json; end if;
  return coalesce((select json_agg(c) from public.v_canh_bao c
                   where c.loai <> 'thieu_gdv' and (v_loc is null or c.chi_nhanh_id = v_loc)), '[]'::json);
end $$;
revoke execute on function public.canh_bao_hom_nay() from public, anon;
grant execute on function public.canh_bao_hom_nay() to authenticated;

notify pgrst, 'reload schema';
