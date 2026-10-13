-- =====================================================================
-- 022 (13/10/2026): Giờ hẹn giao xe mặc định khi lập lệnh sửa chữa = sau N ngày, 17:00 (người lập sửa lại nếu khác)
-- =====================================================================
insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('so_ngay_hen_giao', '3', 'Lập lệnh sửa chữa: giờ hẹn giao xe mặc định sau số ngày này (17:00), người lập sửa lại được')
on conflict (khoa) do nothing;
