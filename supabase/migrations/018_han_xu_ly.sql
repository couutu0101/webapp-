-- =====================================================================
-- 018 (13/10/2026): HẠN XỬ LÝ TỪNG VIỆC – trang "Việc hôm nay" tô vàng việc quá hạn
--   Mỗi người đăng nhập chỉ thấy việc của mình (bước hồ sơ được giao, phiếu kho / đề nghị chi
--   đang chờ đúng vai trò mình). Hạn tính ở phần mềm theo các cài đặt dưới đây (giám đốc sửa ở Cài đặt).
--   Tương thích ngược: chỉ thêm dòng cài đặt.
-- =====================================================================
insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('so_gio_lap_bao_gia',   '24', 'Lập báo giá trong số giờ này kể từ khi tiếp nhận xe'),
  ('so_gio_lap_lenh',      '24', 'Lập lệnh sửa chữa trong số giờ này kể từ khi duyệt giá'),
  ('so_gio_kcs',           '4',  'KCS trong số giờ này kể từ khi tổ báo xong (nếu chưa tới giờ hẹn giao)'),
  ('so_gio_xuat_vat_tu',   '4',  'Kho xuất vật tư trong số giờ này kể từ khi có đề xuất'),
  ('so_gio_duyet_mua',     '24', 'Duyệt đề nghị mua trong số giờ này kể từ khi lập'),
  ('so_gio_khop_hoa_don',  '48', 'Kế toán khớp hóa đơn phiếu nhập trong số giờ này kể từ khi nhập kho'),
  ('so_gio_duyet_chi',     '24', 'Duyệt đề nghị chi trong số giờ này kể từ khi lập')
on conflict (khoa) do nothing;
