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

-- Bản thật đang dùng v_ho_so của 006 (còn 2 cột văn phòng bảo hiểm đã bỏ) → phải drop rồi tạo lại,
-- kéo theo v_canh_bao (phụ thuộc v_ho_so) tạo lại y nguyên bản 036. Giao diện bản thật chỉ hiển thị
-- van_phong_bh nếu có nên không lỗi khi thiếu cột.
drop view if exists public.v_canh_bao;
drop view if exists public.v_ho_so;

create view public.v_ho_so with (security_invoker = true) as
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
revoke all on public.v_ho_so from anon;

-- v_canh_bao: tạo lại y nguyên bản 036
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
where hs.nguon_tt <> 'khach' and hs.trang_thai = 'da_giao'
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
where d.trang_thai = 'cho_duyet' and app.co_vai_tro('giam_doc','quan_ly')
  and d.nguoi_de_nghi <> auth.uid() and (not d.can_giam_doc or app.co_vai_tro('giam_doc'));

grant select on public.v_canh_bao to authenticated;
revoke all on public.v_canh_bao from anon;

analyze;
notify pgrst, 'reload schema';
