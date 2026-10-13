-- =====================================================================
-- 023 (13/10/2026): Tài khoản quỹ mặc định nhận tiền khi lập phiếu thu (tài khoản công ty).
--   Sửa ở Danh mục → Tài khoản quỹ (tích "Mặc định nhận tiền"). Tương thích ngược: chỉ thêm cột.
-- =====================================================================
alter table public.tai_khoan_quy add column if not exists mac_dinh boolean not null default false;
update public.tai_khoan_quy set mac_dinh = true
where hoat_dong and ten ilike '%công ty%'
  and not exists (select 1 from public.tai_khoan_quy t2 where t2.chi_nhanh_id = tai_khoan_quy.chi_nhanh_id and t2.mac_dinh);
