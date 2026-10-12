-- =====================================================================
-- 011 (12/10/2026): Nhóm hạng mục báo giá mới: Đồng, Sơn, Phụ tùng, Detailing
--   Tách "Đồng sơn" thành "Đồng" và "Sơn". Nhóm cũ (dong_son, dmg) vẫn hợp lệ cho các dòng đã có.
--   Tương thích ngược: chỉ nới ràng buộc.
-- =====================================================================
alter table public.hang_muc drop constraint if exists hang_muc_nhom_check;
alter table public.hang_muc add constraint hang_muc_nhom_check
  check (nhom in ('dong','son','phu_tung','detailing','dong_son','dmg'));
