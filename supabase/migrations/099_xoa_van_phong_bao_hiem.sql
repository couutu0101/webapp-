-- =====================================================================
-- 099 (trước là 008 → 039, 12/10/2026): XÓA HẲN "Văn phòng bảo hiểm" (anh Thuận chọn xóa hẳn, không lấy lại được).
--   CHỈ CHẠY TRÊN SUPABASE SAU KHI BẢN THẬT ĐÃ CẬP NHẬT GIAO DIỆN MỚI ("OK, đưa lên"),
--   vì giao diện cũ của bản thật còn đọc bảng van_phong_bao_hiem.
--   Đổi số 008 → 039 → 099 (14/10) để luôn chạy SAU mọi migration khác: 037 đã tạo lại v_ho_so không còn
--   cột văn phòng, 038 đã tạo lại tra_cuu_xe; tiep_nhan_xe / sua_thong_tin_ho_so (031, 035) chỉ ghi
--   van_phong_bh_id khi cột còn tồn tại → xóa cột và bảng là đủ.
-- =====================================================================
alter table public.ho_so drop column if exists van_phong_bh_id;
drop table if exists public.van_phong_bao_hiem;
-- 043 D1 (dời sang 099 ở 044 vì giao diện cũ của bản thật đọc bảng này cho ô chọn đơn vị): nợ đầu kỳ nội bộ chỉ
-- giám đốc, quản lý chung, kế toán, cổ đông đọc; vai khác đọc tên qua v_don_vi_lien_quan (giao diện mới đã dùng view này)
alter policy "doc" on public.don_vi_lien_quan using ((select app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong')));
notify pgrst, 'reload schema';
