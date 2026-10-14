-- =====================================================================
-- 040 (14/10/2026): RÀ SOÁT LẦN 2 – nhóm D (phần giao diện): bớt lượt tải, chặn ghi trùng
--  1. v_ho_so thêm 2 cột ở cuối: nguoi_tiep_theo, giao_viec_luc → "Việc hôm nay" đọc hồ sơ MỘT lần
--     (trước đây đọc v_ho_so 4 lần + v_viec_ho_so 2 lần, nối tiếp nhau).
--  2. bang_viec_to trả thêm nguon_tt, loai, chi_nhanh_id: thanh 9 bước nhỏ ở bảng việc bỏ đúng bước
--     (xe khách không có bước hồ sơ BH; bảo hành không báo giá/duyệt giá) và ảnh phát sinh lưu đúng thư mục.
--  3. nhap_xuat_ton(tháng): cộng nhập – xuất – tồn ở máy chủ (trước đây tải cả lịch sử thẻ kho về trình duyệt).
--  4. them_tep: chỉ nhận đường dẫn thuộc đúng thư mục của hồ sơ và bước hợp lệ (không gắn nhầm ảnh hồ sơ khác).
--  5. Sinh mã chứng từ kho (PN, PX, DX, DM, KK): khóa theo tiền tố mã trong giao dịch → hai người lập
--     cùng lúc không còn lỗi "duplicate key".
--  Tương thích ngược: chỉ THÊM cột/khóa JSON, không đổi tên hay tham số hàm nào.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. v_ho_so: thêm nguoi_tiep_theo, giao_viec_luc (giữ nguyên các cột cũ, đúng thứ tự)
-- ---------------------------------------------------------------------
create or replace view public.v_ho_so with (security_invoker = true) as
select
  h.id, h.ma, h.chi_nhanh_id, h.loai, h.ho_so_goc_id, h.trang_thai, h.ngay_vao, h.hen_giao, h.giao_luc,
  h.nguon_tt, h.tinh_trang_xe, h.tu_van, h.han_bao_hiem, h.khau_tru_giam_tru, h.giam_gia,
  h.so_hd_bao_hiem, h.so_hd_khach, h.cam_nhan_khach, h.gui_hs_ngay, h.hoa_hong_gdv, h.hoa_hong_ghi_chu,
  h.cham_soc_luc, h.cham_soc_ket_qua, h.hen_bao_duong, h.ly_do_huy, h.cho_giao_no_boi, h.tu_excel,
  h.xe_id, h.khach_hang_id, h.hang_bh_id, h.gdv_id,
  x.bien_so, public.bien_so_hien_thi(x.bien_so) as bien_so_hien_thi, x.dong_xe_id, x.mau,
  concat_ws(' ', hx.ten, dx.ten) as xe, k.ten as ten_khach, k.dien_thoai, b.ten as hang_bh,
  coalesce(h.gdv_ten_tam, g.ten) as gdv, coalesce(g.la_cho_them, false) as gdv_cho_them,
  d.ngay_duyet_dau,
  coalesce(d.co_dong_cho_duyet, false) as co_dong_cho_duyet,
  coalesce(ps.co_phat_sinh, false) as co_phat_sinh,
  coalesce(d.bh, 0) as bh_duyet,
  coalesce(d.kh, 0) as khach_duyet,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru as phai_thu_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia as phai_thu_khach,
  coalesce(t.bh, 0) as da_thu_bh,
  coalesce(t.kh, 0) as da_thu_khach,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru - coalesce(t.bh, 0) as con_no_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia - coalesce(t.kh, 0) as con_no_khach,
  h.han_bh_than_vo,
  h.so_km,
  h.nguoi_tiep_theo,
  h.giao_viec_luc
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
left join app.duyet_theo_ho_so() d on d.ho_so_id = h.id
left join (select p.ho_so_id, bool_or(not p.da_xu_ly) as co_phat_sinh from public.phat_sinh p group by p.ho_so_id) ps on ps.ho_so_id = h.id
left join app.da_thu_theo_ho_so() t on t.ho_so_id = h.id;

grant select on public.v_ho_so to authenticated;
revoke all on public.v_ho_so from anon;

create index if not exists ho_so_nguoi_tiep_idx on public.ho_so (nguoi_tiep_theo) where nguoi_tiep_theo is not null;
create index if not exists ho_so_giao_luc_idx on public.ho_so (giao_luc) where giao_luc is not null;

-- ---------------------------------------------------------------------
-- 2. Bảng việc tổ: thêm nguồn, loại hồ sơ, chi nhánh
-- ---------------------------------------------------------------------
create or replace function public.bang_viec_to() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','ke_toan','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select to_id, chi_nhanh_id into v_to, v_cn from public.nhan_vien where id = auth.uid();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ho_so_id', h.id, 'ma', h.ma, 'bien_so', public.bien_so_hien_thi(x.bien_so),
      'xe', concat_ws(' ', hx.ten, dx.ten, x.mau), 'hen_giao', h.hen_giao, 'trang_thai', h.trang_thai,
      'tinh_trang_xe', h.tinh_trang_xe,
      'nguon_tt', h.nguon_tt, 'loai', h.loai, 'chi_nhanh_id', h.chi_nhanh_id,
      'hang_muc', (select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'nhom', m.nhom, 'to_id', m.to_id,
                     'nguoi_lam', m.nguoi_lam, 'trang_thai', m.trang_thai) order by m.id)
                   from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('dang_lam','xong')
                     and (v_to is null or m.to_id = v_to)))
      order by h.hen_giao nulls last)
    from public.ho_so h
    join public.xe x on x.id = h.xe_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    where h.trang_thai in ('dang_sua','cho_kcs')
      and (app.co_vai_tro('giam_doc') or h.chi_nhanh_id = v_cn)
      and (v_to is null or not app.co_vai_tro('truong_nhom') or exists (
            select 1 from public.hang_muc m where m.ho_so_id = h.id and m.to_id = v_to and m.trang_thai in ('dang_lam','xong')))
  ), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 3. Nhập – xuất – tồn theo tháng ('YYYY-MM'), tính ở máy chủ, quyền đọc như thẻ kho (RLS người gọi)
-- ---------------------------------------------------------------------
create or replace function public.nhap_xuat_ton(p_thang text)
returns table (hang_id bigint, dau numeric, gt_dau numeric, nhap numeric, gt_nhap numeric, xuat numeric, gt_xuat numeric)
language sql stable security invoker set search_path = public as $$
  with k as (select to_date(p_thang || '-01', 'YYYY-MM-DD') as tu)
  select t.hang_id,
    coalesce(sum(t.so_luong) filter (where t.ngay < k.tu), 0),
    coalesce(sum(t.gia_tri)  filter (where t.ngay < k.tu), 0),
    coalesce(sum(t.so_luong) filter (where t.ngay >= k.tu and t.so_luong > 0), 0),
    coalesce(sum(t.gia_tri)  filter (where t.ngay >= k.tu and t.so_luong > 0), 0),
    coalesce(-sum(t.so_luong) filter (where t.ngay >= k.tu and t.so_luong <= 0), 0),
    coalesce(-sum(t.gia_tri)  filter (where t.ngay >= k.tu and t.so_luong <= 0), 0)
  from public.v_the_kho t, k
  where t.ngay < (k.tu + interval '1 month')::date
  group by t.hang_id
$$;
revoke execute on function public.nhap_xuat_ton(text) from public, anon;
grant execute on function public.nhap_xuat_ton(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. them_tep: đường dẫn phải nằm trong thư mục "<chi nhánh>/<mã hồ sơ>/" và bước hợp lệ
-- ---------------------------------------------------------------------
create or replace function public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text) returns bigint
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_id bigint; v_goc text;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  v_goc := h.chi_nhanh_id || '/' || h.ma || '/';
  if p_duong_dan is null or left(p_duong_dan, length(v_goc)) <> v_goc or position('..' in p_duong_dan) > 0 then
    raise exception 'Tệp không thuộc thư mục của hồ sơ % – tải lại ảnh từ trang hồ sơ.', h.ma;
  end if;
  if p_buoc not in ('tiep_nhan','duyet_gia','phat_sinh','kcs','giao_xe','ho_so_bh','khac') then
    raise exception 'Bước của tệp không hợp lệ.';
  end if;
  if coalesce(p_loai, 'anh') not in ('anh','bien_ban') then raise exception 'Loại tệp không hợp lệ.'; end if;
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, coalesce(p_loai, 'anh'), p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. Mã chứng từ kho: khóa theo tiền tố trong giao dịch (người sau chờ người trước ghi xong rồi lấy số kế tiếp)
-- ---------------------------------------------------------------------
create or replace function app.ma_chung_tu(p_loai text, p_cn text, p_ngay date, p_bang text) returns text
language plpgsql security definer set search_path = public as $$
declare v_goc text := p_cn || '-' || p_loai || to_char(p_ngay, 'YYMM') || '-'; v_n int; v_ma text; v_co boolean;
begin
  perform pg_advisory_xact_lock(hashtext('ma_chung_tu_' || p_bang || '_' || v_goc));
  execute format('select count(*) + 1 from public.%I where ma like $1', p_bang) into v_n using v_goc || '%';
  loop
    v_ma := v_goc || lpad(v_n::text, 3, '0');
    execute format('select exists (select 1 from public.%I where ma = $1)', p_bang) into v_co using v_ma;
    exit when not v_co;
    v_n := v_n + 1;
  end loop;
  return v_ma;
end $$;

notify pgrst, 'reload schema';
