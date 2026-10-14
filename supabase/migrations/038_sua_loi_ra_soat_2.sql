-- =====================================================================
-- 038 (14/10/2026): RÀ SOÁT LẦN 2 – nhóm A: lỗi số liệu / kẹt việc (anh Thuận chọn sửa cả 4 nhóm)
--  A2. Hủy phiếu chi rồi chi lại cùng đề nghị → lỗi "duplicate key": cột de_nghi_chi_id UNIQUE kể cả phiếu hủy
--      → chỉ duy nhất trong các phiếu HIỆU LỰC.
--  A3. Hoa hồng GDV nhập/sửa sau khi tháng (duyệt giá) đã chốt → KQKD sống lệch số chốt → chặn như mọi khoản khác.
--      Hủy phiếu có kỳ chi phí thuộc tháng đã chốt → chặn.
--  A4. Hồ sơ kẹt "Đang sửa": phát sinh bị từ chối hết / xóa dòng cuối → tự sang "Chờ KCS" (trigger hang_muc).
--  A5. Công nợ NCC với vai Kho: "đã trả" = 0 vì RLS không cho kho đọc phiếu chi → tính bằng hàm có quyền.
--  A6. Khách trả dư (nợ âm) sau giao xe: KHÔNG tự đóng hồ sơ (phải trả lại hoặc ghi tiền bo); cảnh báo ở Việc hôm nay.
--      Tiền bo tách 2 phiếu trong MỘT giao dịch (p.tien_bo) thay vì giao diện gọi 2 lần.
--  A7. Hủy phiếu nhập sau khi phiếu xuất (đã hủy) từng lấy hàng của lô → lỗi khóa ngoại xuat_lo → dọn xuat_lo của
--      phiếu xuất đã hủy trước; nếu còn phiếu xuất hiệu lực thì báo tiếng Việt.
--  A8. Tra cứu xe: "số lần vào gara" không đếm hồ sơ hủy; cảnh báo "chưa gửi hồ sơ BH" bỏ hồ sơ chuyển từ Excel.
--  Tương thích ngược: không đổi tên/tham số hàm nào; tra_cuu_xe bỏ văn phòng BH (giao diện cũ chỉ hiển thị nếu có).
-- =====================================================================

-- ---------------------------------------------------------------------
-- A2. Đề nghị chi: duy nhất trong các phiếu hiệu lực
-- ---------------------------------------------------------------------
alter table public.phieu_thu_chi drop constraint if exists phieu_thu_chi_de_nghi_chi_id_key;
create unique index if not exists phieu_thu_chi_de_nghi_hieu_luc_idx
  on public.phieu_thu_chi (de_nghi_chi_id) where de_nghi_chi_id is not null and trang_thai = 'hieu_luc';

-- ---------------------------------------------------------------------
-- A3. Hoa hồng GDV: chặn khi tháng duyệt giá đầu tiên (tháng KQKD ghi hoa hồng) đã chốt
-- ---------------------------------------------------------------------
create or replace function public.nhap_hoa_hong_gdv(p_ho_so bigint, p_so_tien numeric, p_ghi_chu text default null,
  p_bo_qua_canh_bao boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; v_tl numeric := app.cai_dat_so('hoa_hong_canh_bao_ty_le', 0.15); v_thang date;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.gdv_id is null then raise exception 'Hồ sơ không có giám định viên.'; end if;
  if p_so_tien is null or p_so_tien < 0 then raise exception 'Số tiền hoa hồng không hợp lệ.'; end if;
  select min(m.ngay_duyet) into v_thang from public.hang_muc m
   where m.ho_so_id = p_ho_so and m.trang_thai in ('duyet','dang_lam','xong');
  if v_thang is not null then perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_thang); end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.bh_duyet > 0 and p_so_tien > t.bh_duyet * v_tl and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Hoa hồng % đ lớn hơn % giá duyệt bảo hiểm. Kiểm tra lại có gõ thừa số 0 không?',
      app.vnd(p_so_tien), round(v_tl * 100)::text || '%';
  end if;
  update public.ho_so set hoa_hong_gdv = p_so_tien, hoa_hong_ghi_chu = nullif(trim(p_ghi_chu),'') where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Nhập hoa hồng GDV ' || p_so_tien || ' đ');
end $$;

-- Hủy phiếu: thêm kiểm tra kỳ chi phí (phiếu ghi tháng sau nhưng tính vào tháng trước đã chốt)
create or replace function public.huy_phieu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; x bigint; d public.phieu_thu_chi;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ky_chi_phi); end if;
  if r.trang_thai = 'huy' then raise exception 'Phiếu đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) where id = p_id;
  if r.de_nghi_chi_id is not null then
    update public.de_nghi_chi set trang_thai = 'da_duyet' where id = r.de_nghi_chi_id;
  end if;
  for x in select distinct ho_so_id from public.phan_bo where phieu_id = p_id and ho_so_id is not null loop
    perform app.cap_nhat_dong(x);
  end loop;
  if r.phieu_doi_ung_id is not null then
    select * into d from public.phieu_thu_chi where id = r.phieu_doi_ung_id for update;
    if found and d.trang_thai = 'hieu_luc' then
      update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) || ' (hủy cùng phiếu chi hộ đối ứng)' where id = d.id;
      if d.de_nghi_chi_id is not null then
        update public.de_nghi_chi set trang_thai = 'da_duyet' where id = d.de_nghi_chi_id;
      end if;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- A4. Hết hạng mục còn làm (từ chối phát sinh / xóa dòng) khi xe đang sửa → tự sang Chờ KCS
-- ---------------------------------------------------------------------
-- bao_xong đã tự chuyển Chờ KCS khi dòng cuối xong; trigger chỉ xét khi dòng bị TỪ CHỐI hoặc XÓA.
create or replace function app.kiem_tra_xong_sua() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_hs bigint := coalesce(new.ho_so_id, old.ho_so_id);
begin
  if tg_op = 'UPDATE' and new.trang_thai not in ('tu_choi') then return null; end if;
  if exists (select 1 from public.ho_so where id = v_hs and trang_thai = 'dang_sua')
     and not exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai in ('cho_duyet','duyet','dang_lam'))
     and exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai = 'xong') then
    perform app.doi_trang_thai(v_hs, 'cho_kcs', 'Hết hạng mục còn làm (phát sinh bị từ chối / xóa) – chờ KCS');
  end if;
  return null;
end $$;

drop trigger if exists hang_muc_xong_sua on public.hang_muc;
create trigger hang_muc_xong_sua
  after update of trang_thai or delete on public.hang_muc
  for each row
  when (pg_trigger_depth() < 2)
  execute function app.kiem_tra_xong_sua();

-- ---------------------------------------------------------------------
-- A5. Công nợ NCC: "đã trả" tính bằng hàm có quyền (vai kho không đọc được phiếu chi)
-- ---------------------------------------------------------------------
create or replace function app.da_tra_ncc()
returns table (nha_cung_cap_id bigint, chi_nhanh_id text, da_tra numeric)
language sql stable security definer set search_path = public rows 200 as $$
  select t.nha_cung_cap_id, t.chi_nhanh_id, sum(t.so_tien)
  from public.phieu_thu_chi t join public.muc_thu_chi m on m.id = t.muc_id
  where t.nha_cung_cap_id is not null and t.loai = 'chi' and t.trang_thai = 'hieu_luc' and m.tinh_chat = 'tra_ncc'
    and (select app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong'))
    and ((select app.co_vai_tro('giam_doc')) or t.chi_nhanh_id = (select app.chi_nhanh()))
  group by 1, 2
$$;
revoke execute on function app.da_tra_ncc() from public, anon;
grant execute on function app.da_tra_ncc() to authenticated;

create or replace view public.v_cong_no_ncc with (security_invoker = true) as
select n.id as nha_cung_cap_id, n.ten, c.chi_nhanh_id,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p
            where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai = 'da_khop'), 0) as da_nhap,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p
            where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai in ('cho_khop','treo')), 0) as cho_khop,
  coalesce(t.da_tra, 0) as da_tra
from public.nha_cung_cap n
cross join (select id as chi_nhanh_id from public.chi_nhanh) c
left join app.da_tra_ncc() t on t.nha_cung_cap_id = n.id and t.chi_nhanh_id = c.chi_nhanh_id
where (select app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong'))
  and ((select app.co_vai_tro('giam_doc')) or c.chi_nhanh_id = (select app.chi_nhanh()));
grant select on public.v_cong_no_ncc to authenticated;

-- ---------------------------------------------------------------------
-- A6. Khách trả dư: không tự đóng hồ sơ; tiền bo tách phiếu trong một giao dịch
-- ---------------------------------------------------------------------
create or replace function app.cap_nhat_dong(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; co_bh boolean; het_no boolean;
begin
  select * into h from public.ho_so where id = p_id;
  if h.trang_thai not in ('da_giao','da_gui_hs','dong') then return; end if;
  select * into t from app.tien_ho_so(p_id);
  co_bh := t.phai_thu_bh > 0;
  -- Khách trả dư (nợ âm) là tiền phải TRẢ LẠI khách → chưa xong; hồ sơ chuyển từ Excel giữ cách cũ (số liệu cũ có thể lệch)
  het_no := t.con_no_bh <= 0 and (case when h.tu_excel then t.con_no_khach <= 0 else t.con_no_khach = 0 end);
  if het_no and (not co_bh or h.gui_hs_ngay is not null) then
    perform app.doi_trang_thai(p_id, 'dong', 'Tự đóng: đã giao xe và hết công nợ');
  elsif h.trang_thai = 'dong' then
    perform app.doi_trang_thai(p_id,
      case when h.gui_hs_ngay is not null then 'da_gui_hs' else 'da_giao' end,
      case when t.con_no_khach < 0 then 'Mở lại: khách trả dư – cần trả lại hoặc ghi tiền bo' else 'Mở lại: phát sinh công nợ' end);
  end if;
end $$;

update public.muc_thu_chi set he_thong = 'tien_bo' where he_thong is null and loai = 'thu' and ten = 'Tiền bo của khách';

-- lap_phieu_thu: thêm p.tien_bo (phần dư là tiền bo) → 2 phiếu trong một giao dịch; giao diện cũ không gửi thì như trước
create or replace function public.lap_phieu_thu(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  m public.muc_thu_chi; v_id bigint; v_tong numeric; v_bo numeric := coalesce((p->>'tien_bo')::numeric, 0);
  v_so_tien numeric := coalesce((p->>'so_tien')::numeric, 0); v_muc_bo bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'thu' then raise exception 'Chưa chọn mục thu.'; end if;
  if v_so_tien <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_bo < 0 or v_bo >= v_so_tien then raise exception 'Tiền bo không hợp lệ.'; end if;
  if v_bo > 0 then
    if m.tinh_chat <> 'thu_khach' then raise exception 'Tiền bo chỉ tách từ phiếu khách thanh toán sửa chữa.'; end if;
    select id into v_muc_bo from public.muc_thu_chi where loai = 'thu' and hoat_dong and (he_thong = 'tien_bo' or ten = 'Tiền bo của khách')
      order by he_thong nulls last limit 1;
    if v_muc_bo is null then raise exception 'Chưa có mục thu "Tiền bo của khách" (Danh mục → Mục thu chi).'; end if;
  end if;
  if m.tinh_chat = 'thu_bao_hiem' and (p->>'hang_bh_id') is null then raise exception 'Chọn hãng bảo hiểm chuyển tiền.'; end if;
  if m.tinh_chat = 'thu_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;

  select coalesce(sum((x->>'so_tien')::numeric), 0) into v_tong from jsonb_array_elements(coalesce(p->'phan_bo','[]'::jsonb)) x;
  if m.tinh_chat in ('thu_khach','thu_coc','thu_dich_vu_nhanh') and v_tong <> v_so_tien - v_bo then
    raise exception 'Tiền khách trả phải gắn đủ vào hồ sơ xe hoặc dịch vụ (đang gắn % / % đ).',
      app.vnd(v_tong), app.vnd(v_so_tien - v_bo);
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung,
    hang_bh_id, don_vi_lien_quan_id, tao_boi)
  values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, m.id, v_so_tien - v_bo, nullif(trim(p->>'noi_dung'),''),
    (p->>'hang_bh_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, auth.uid())
  returning id into v_id;
  -- Khách trả dư (cho_tra_du = true): gắn đủ vào xe dù vượt số còn nợ → hồ sơ ghi khách trả dư, trả lại sau
  perform app.phan_bo_phieu(v_id, p->'phan_bo', case when m.tinh_chat = 'thu_khach' and coalesce((p->>'cho_tra_du')::boolean, false) then 'thu_khach_du' else m.tinh_chat end);
  if v_bo > 0 then
    insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung, tao_boi)
    values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, v_muc_bo, v_bo,
      'Tiền bo của khách – ' || coalesce(nullif(trim(p->>'noi_dung'),''), 'phiếu thu #' || v_id), auth.uid());
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- A7. Hủy phiếu nhập: dọn xuat_lo của phiếu xuất đã hủy; báo rõ nếu còn phiếu xuất hiệu lực
-- ---------------------------------------------------------------------
create or replace function public.huy_phieu_nhap(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_nhap; v_px text;
begin
  perform app.yeu_cau('kho','giam_doc');
  select * into r from public.phieu_nhap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu nhập.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai not in ('cho_khop','treo') then raise exception 'Phiếu đã khớp hóa đơn hoặc đã hủy – không hủy được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  select string_agg(distinct px.ma, ', ') into v_px
  from public.xuat_lo xl
  join public.phieu_xuat_dong d on d.id = xl.phieu_xuat_dong_id
  join public.phieu_xuat px on px.id = d.phieu_id
  where px.trang_thai = 'hieu_luc'
    and xl.lo_id in (select l.id from public.lo_kho l join public.phieu_nhap_dong nd on nd.id = l.phieu_nhap_dong_id where nd.phieu_id = p_id);
  if v_px is not null then
    raise exception 'Hàng của phiếu nhập này đã xuất ở phiếu % – hủy phiếu xuất đó trước.', v_px;
  end if;
  if exists (select 1 from public.lo_kho l join public.phieu_nhap_dong d on d.id = l.phieu_nhap_dong_id
             where d.phieu_id = p_id and l.con_lai < l.so_luong) then
    raise exception 'Hàng của phiếu này đã xuất một phần (kiểm kê / điều chỉnh) – không hủy được.';
  end if;
  -- phiếu xuất đã hủy vẫn còn dòng xuat_lo trỏ vào lô → xóa trước
  delete from public.xuat_lo xl using public.phieu_xuat_dong d, public.phieu_xuat px
  where d.id = xl.phieu_xuat_dong_id and px.id = d.phieu_id and px.trang_thai = 'huy'
    and xl.lo_id in (select l.id from public.lo_kho l join public.phieu_nhap_dong nd on nd.id = l.phieu_nhap_dong_id where nd.phieu_id = p_id);
  delete from public.lo_kho where phieu_nhap_dong_id in (select id from public.phieu_nhap_dong where phieu_id = p_id);
  update public.phieu_nhap set trang_thai = 'huy', ghi_chu = concat_ws(' · ', ghi_chu, 'Hủy: ' || trim(p_ly_do)) where id = p_id;
  if r.de_nghi_mua_id is not null then
    update public.de_nghi_mua set trang_thai = 'da_duyet' where id = r.de_nghi_mua_id and trang_thai = 'da_nhap';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- A8. Tra cứu xe: số lần vào không đếm hồ sơ hủy (bỏ văn phòng BH – giao diện mới không dùng)
-- ---------------------------------------------------------------------
create or replace function public.tra_cuu_xe(p_bien_so text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_bs text := public.bien_so_gon(p_bien_so); r jsonb;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if v_bs is null then return null; end if;
  select jsonb_build_object(
    'xe_id', x.id, 'bien_so', public.bien_so_hien_thi(x.bien_so), 'dong_xe_id', x.dong_xe_id,
    'hang_xe_id', dx.hang_xe_id, 'mau', x.mau, 'han_bao_hiem', x.han_bao_hiem, 'han_bh_than_vo', x.han_bh_than_vo,
    'ten_khach', k.ten, 'dien_thoai', k.dien_thoai,
    'so_lan_vao', (select count(*) from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy'),
    'ho_so_mo', (select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'trang_thai', h.trang_thai))
                 from public.ho_so h where h.xe_id = x.id and h.trang_thai not in ('dong','huy')),
    'ho_so_gan_nhat', (select jsonb_build_object('id', h.id, 'ma', h.ma, 'nguon_tt', h.nguon_tt, 'hang_bh_id', h.hang_bh_id,
                         'gdv_id', h.gdv_id)
                       from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy' order by h.id desc limit 1))
  into r
  from public.xe x
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.khach_hang k on k.id = x.khach_hang_id
  where x.bien_so = v_bs;
  return r;
end $$;

-- v_canh_bao: thêm "khách trả dư"; "chưa gửi hồ sơ BH" bỏ hồ sơ từ Excel
create or replace view public.v_canh_bao with (security_invoker = true) as
with hs as (select * from public.v_ho_so where trang_thai not in ('huy')),
homnay as (select (now() at time zone 'Asia/Ho_Chi_Minh')::date as d)
select 'cho_duyet_qua_han' as loai, 'cao' as muc_do, hs.id as ho_so_id, hs.ma, hs.bien_so_hien_thi as bien_so,
  'Xe bảo hiểm chờ duyệt giá ' || (homnay.d - hs.ngay_vao::date) || ' ngày – báo giám đốc' as noi_dung, hs.chi_nhanh_id
from hs, homnay
where hs.nguon_tt <> 'khach' and hs.trang_thai in ('tiep_nhan','bao_gia')
  and homnay.d - hs.ngay_vao::date > app.cai_dat_so('so_ngay_cho_duyet', 3)
union all
select 'chua_gui_ho_so', 'cao', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Đã giao xe ' || (homnay.d - hs.giao_luc::date) || ' ngày, chưa gửi hồ sơ bảo hiểm', hs.chi_nhanh_id
from hs, homnay
where hs.nguon_tt <> 'khach' and hs.trang_thai = 'da_giao' and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and homnay.d - hs.giao_luc::date > app.cai_dat_so('so_ngay_gui_ho_so', 3)
union all
select case when homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_no_giam_doc', 30) then 'no_bh_30' else 'no_bh_15' end,
  case when homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_no_giam_doc', 30) then 'cao' else 'vua' end,
  hs.id, hs.ma, hs.bien_so_hien_thi,
  coalesce(hs.hang_bh, 'Bảo hiểm') || ' còn nợ ' || app.vnd(hs.con_no_bh) || ' đ, đã gửi hồ sơ '
    || (homnay.d - hs.gui_hs_ngay) || ' ngày'
    || case when homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_no_giam_doc', 30) then ' – giám đốc làm việc với bảo hiểm' else ' – nhắc nợ' end,
  hs.chi_nhanh_id
from hs, homnay
where hs.trang_thai = 'da_gui_hs' and hs.con_no_bh > 0
  and homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_nhac_no', 15)
union all
select 'khach_no', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  hs.ten_khach || ' còn nợ ' || app.vnd(hs.con_no_khach) || ' đ', hs.chi_nhanh_id
from hs where hs.giao_luc is not null and hs.con_no_khach > 0
union all
select 'khach_tra_du', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  hs.ten_khach || ' trả dư ' || app.vnd(-hs.con_no_khach) || ' đ – lập đề nghị chi "Trả lại cọc cho khách" hoặc ghi tiền bo', hs.chi_nhanh_id
from hs where hs.giao_luc is not null and hs.con_no_khach < 0 and not hs.tu_excel
union all
select 'thieu_hoa_hong', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Chưa nhập hoa hồng cho GDV ' || coalesce(hs.gdv, ''), hs.chi_nhanh_id
from hs where hs.gdv_id is not null and hs.giao_luc is not null and hs.hoa_hong_gdv is null and not hs.tu_excel
union all
select 'gdv_cho_them', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'GDV "' || coalesce(hs.gdv, '') || '" chưa có trong danh sách – kế toán thêm vào Cài đặt rồi gắn lại', hs.chi_nhanh_id
from hs where hs.gdv_cho_them
union all
select 'thieu_gdv', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Xe bảo hiểm chưa có giám định viên – ghi GDV (Sửa ở Thông tin xe và khách) trước khi nhập kết quả duyệt giá', hs.chi_nhanh_id
from hs where hs.nguon_tt <> 'khach' and hs.gdv_id is null and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs')
union all
select 'can_goi_cham_soc', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Gọi hỏi thăm ' || hs.ten_khach || ' (giao xe ' || to_char(hs.giao_luc, 'DD/MM') || ')', hs.chi_nhanh_id
from hs, homnay
where hs.giao_luc is not null and hs.cham_soc_luc is null
  and homnay.d - hs.giao_luc::date >= app.cai_dat_so('so_ngay_goi_cham_soc', 3)
union all
select 'phat_sinh', 'cao', hs.id, hs.ma, hs.bien_so_hien_thi, 'Có hư hỏng phát sinh chờ lập báo giá bổ sung', hs.chi_nhanh_id
from hs where hs.co_phat_sinh
union all
select 'tre_hen', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Quá giờ hẹn giao ' || to_char(hs.hen_giao at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), hs.chi_nhanh_id
from hs where hs.hen_giao < now() and hs.trang_thai in ('dang_sua','cho_kcs','dat_kcs')
union all
select 'thu_chua_phan_bo', 'vua', null, null, null,
  'Phiếu thu ' || to_char(p.ngay, 'DD/MM') || ' của ' || coalesce(p.hang_bh, p.muc) || ' còn '
    || app.vnd(p.so_tien - p.da_phan_bo) || ' đ chưa chia vào xe', p.chi_nhanh_id
from public.v_phieu_thu_chi p
where p.loai = 'thu' and p.trang_thai = 'hieu_luc' and p.tinh_chat = 'thu_bao_hiem' and p.da_phan_bo < p.so_tien
union all
select 'de_nghi_cho_duyet', case when d.nghi_tach_phieu then 'cao' else 'vua' end, d.ho_so_id, d.ho_so_ma, null,
  'Đề nghị chi ' || app.vnd(d.so_tien) || ' đ – ' || d.noi_dung || ' (' || coalesce(d.nguoi_de_nghi_ten,'') || ')'
    || case when d.can_giam_doc then ' – cần giám đốc duyệt' else '' end
    || case when d.nghi_tach_phieu then ' – nghi tách nhỏ phiếu' else '' end,
  d.chi_nhanh_id
from public.v_de_nghi_chi d
where d.trang_thai = 'cho_duyet' and (select app.co_vai_tro('giam_doc','quan_ly'))
  and d.nguoi_de_nghi <> (select auth.uid()) and (not d.can_giam_doc or (select app.co_vai_tro('giam_doc')));
grant select on public.v_canh_bao to authenticated;

notify pgrst, 'reload schema';
