-- 037 – Hiệu năng (rà soát lần 2, 14/10/2026)
-- Đo với 5.000 hồ sơ / 25.000 hạng mục / 10.000 phiếu: bảng phiếu thu chi 1 tháng mất 36 giây,
-- danh sách hồ sơ 4–6 giây, cảnh báo Việc hôm nay 11 giây. Nguyên nhân:
--   1. Chính sách phân quyền (RLS) gọi app.vai_tro() → đọc bảng nhan_vien cho TỪNG DÒNG.
--      Bọc (select …) để Postgres tính một lần cho cả câu lệnh (khuyến nghị của Supabase).
--   2. Thiếu chỉ mục ở các cột hay nối/lọc.
--   3. v_ho_so gọi hàm tien_ho_so(h.id) cho từng hồ sơ → tính theo tập (group by) một lần.
-- Tương thích ngược: không đổi tên/cột nào đang dùng; v_ho_so thêm cột so_km ở cuối.

-- ---------------------------------------------------------------------
-- 1. Bọc (select …) quanh các hàm vai trò trong mọi policy
-- ---------------------------------------------------------------------
create or replace function app.boc_select(bt text) returns text
language sql immutable as $$
  select case when bt is null then null else
    replace(replace(
      regexp_replace(
      regexp_replace(
      regexp_replace(
      regexp_replace(
      regexp_replace(bt,
        'app\.duoc_xem_chi_nhanh\(([^()]*)\)', '(__GD__ OR (\1 = __CN__))', 'g'),
        'app\.co_vai_tro\(([^()]*)\)', '(select app.co_vai_tro(\1))', 'g'),
        'app\.(la_nhan_vien|xem_nhu_nhan_vien|la_co_dong|chi_nhanh|to_cua_toi)\(\)', '(select app.\1())', 'g'),
        'auth\.uid\(\)', '(select auth.uid())', 'g'),
        '\(select \(select ', '((select ', 'g'),
      '__GD__', '(select app.co_vai_tro(''giam_doc''))'),
      '__CN__', '(select app.chi_nhanh())')
  end
$$;

do $$
declare r record; v_using text; v_check text; v_sql text; n int := 0;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where (schemaname = 'public' or (schemaname = 'storage' and tablename = 'objects' and policyname like 'ho-so-xe%'))
      and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(app\.(co_vai_tro|la_nhan_vien|xem_nhu_nhan_vien|la_co_dong|chi_nhanh|duoc_xem_chi_nhanh|to_cua_toi)|auth\.uid)\('
      and (coalesce(qual, '') || coalesce(with_check, '')) !~ '\(select (app|auth)\.'
  loop
    v_using := app.boc_select(r.qual);
    v_check := app.boc_select(r.with_check);
    v_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if v_using is not null then v_sql := v_sql || ' using (' || v_using || ')'; end if;
    if v_check is not null then v_sql := v_sql || ' with check (' || v_check || ')'; end if;
    execute v_sql;
    n := n + 1;
  end loop;
  raise notice '037: đã bọc (select …) cho % policy', n;
end $$;

-- ---------------------------------------------------------------------
-- 2. Chỉ mục còn thiếu
-- ---------------------------------------------------------------------
create index if not exists phan_bo_phieu_idx on public.phan_bo (phieu_id);
create index if not exists phan_bo_dvn_idx on public.phan_bo (dich_vu_nhanh_id) where dich_vu_nhanh_id is not null;
create index if not exists lo_kho_hang_all_idx on public.lo_kho (hang_id);
create index if not exists ho_so_ngay_vao_idx on public.ho_so (ngay_vao desc);
create index if not exists ho_so_khach_idx on public.ho_so (khach_hang_id);
create index if not exists ho_so_nhat_ky_hs_idx on public.ho_so_nhat_ky (ho_so_id);
create index if not exists ho_so_tep_hs_idx on public.ho_so_tep (ho_so_id);
create index if not exists phat_sinh_hs_idx on public.phat_sinh (ho_so_id);
create index if not exists kcs_hs_idx on public.kcs (ho_so_id);
create index if not exists phieu_xuat_dong_phieu_idx on public.phieu_xuat_dong (phieu_id);
create index if not exists phieu_nhap_dong_phieu_idx on public.phieu_nhap_dong (phieu_id);
create index if not exists phieu_nhap_dong_hang_idx on public.phieu_nhap_dong (hang_id);
create index if not exists phieu_nhap_ncc_idx on public.phieu_nhap (nha_cung_cap_id, chi_nhanh_id, trang_thai);
create index if not exists phieu_thu_chi_ncc_idx on public.phieu_thu_chi (nha_cung_cap_id) where nha_cung_cap_id is not null;
create index if not exists phieu_thu_chi_muc_idx on public.phieu_thu_chi (muc_id);
create index if not exists hang_muc_ngay_duyet_idx on public.hang_muc (ngay_duyet);
create index if not exists dich_vu_nhanh_cn_ngay_idx on public.dich_vu_nhanh (chi_nhanh_id, ngay);
create index if not exists xuat_lo_lo_idx on public.xuat_lo (lo_id);

-- Hàm tiền một hồ sơ: báo cho Postgres biết chỉ trả 1 dòng (mặc định đoán 1000 → kế hoạch sai)
alter function app.tien_ho_so(bigint) rows 1;
alter function public.tien_ho_so(bigint) rows 1;

-- ---------------------------------------------------------------------
-- 3. v_ho_so: tiền tính theo tập, một lần cho cả danh sách
--    (hai hàm security definer thay cho tien_ho_so từng dòng; tự kiểm quyền như RLS của bảng)
-- ---------------------------------------------------------------------
create or replace function app.duyet_theo_ho_so()
returns table (ho_so_id bigint, bh numeric, kh numeric, ngay_duyet_dau date, co_dong_cho_duyet boolean)
language sql stable security definer set search_path = public rows 5000 as $$
  select m.ho_so_id,
    coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat))
      filter (where m.nguoi_tra = 'bao_hiem' and m.trang_thai in ('duyet','dang_lam','xong')), 0),
    coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat))
      filter (where m.nguoi_tra = 'khach' and m.trang_thai in ('duyet','dang_lam','xong')), 0),
    min(m.ngay_duyet) filter (where m.trang_thai in ('duyet','dang_lam','xong')),
    bool_or(m.trang_thai = 'cho_duyet')
  from public.hang_muc m
  join public.ho_so h on h.id = m.ho_so_id
  where (select app.xem_nhu_nhan_vien())
    and ((select app.co_vai_tro('giam_doc')) or h.chi_nhanh_id = (select app.chi_nhanh()))
  group by m.ho_so_id
$$;

create or replace function app.da_thu_theo_ho_so()
returns table (ho_so_id bigint, bh numeric, kh numeric)
language sql stable security definer set search_path = public rows 5000 as $$
  select pb.ho_so_id,
    coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0),
    coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0)
  from public.phan_bo pb
  join public.phieu_thu_chi p on p.id = pb.phieu_id
  where pb.ho_so_id is not null and p.trang_thai = 'hieu_luc'
    and (select app.xem_nhu_nhan_vien())
    and ((select app.co_vai_tro('giam_doc')) or p.chi_nhanh_id = (select app.chi_nhanh()))
  group by pb.ho_so_id
$$;

revoke execute on function app.duyet_theo_ho_so(), app.da_thu_theo_ho_so() from public, anon;
grant execute on function app.duyet_theo_ho_so(), app.da_thu_theo_ho_so() to authenticated;

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
  h.so_km
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

analyze;
notify pgrst, 'reload schema';
