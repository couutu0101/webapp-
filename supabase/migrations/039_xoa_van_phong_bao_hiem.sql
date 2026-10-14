-- =====================================================================
-- 039 (trước là 008, 12/10/2026): XÓA HẲN "Văn phòng bảo hiểm" (anh Thuận chọn xóa hẳn, không lấy lại được).
--   CHỈ CHẠY TRÊN SUPABASE SAU KHI BẢN THẬT ĐÃ CẬP NHẬT GIAO DIỆN MỚI ("OK, đưa lên"),
--   vì giao diện cũ của bản thật còn đọc bảng van_phong_bao_hiem.
--   Đổi số 008 → 039 (14/10) để luôn chạy SAU các migration khác: 037 đã tạo lại v_ho_so không còn
--   cột văn phòng, 038 đã tạo lại tra_cuu_xe; tiep_nhan_xe / sua_thong_tin_ho_so (031, 035) chỉ ghi
--   van_phong_bh_id khi cột còn tồn tại → xóa cột và bảng là đủ.
-- =====================================================================
alter table public.ho_so drop column if exists van_phong_bh_id;
drop table if exists public.van_phong_bao_hiem;
notify pgrst, 'reload schema';
