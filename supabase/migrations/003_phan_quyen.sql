-- =====================================================================
-- 003: Phân quyền (Row Level Security)
-- Nguyên tắc: mọi bảng bật RLS. Người dùng chỉ ĐỌC trực tiếp theo quyền;
-- GHI dữ liệu nghiệp vụ chỉ qua các hàm ở file 002.
-- Riêng danh mục và cài đặt: giám đốc / kế toán sửa trực tiếp trên màn hình Danh mục.
-- Cổ đông: không đọc được bảng nghiệp vụ nào (trang báo cáo cổ đông làm ở đợt 2).
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'chi_nhanh','nhan_vien','cai_dat','thue_suat_vat','hang_bao_hiem','van_phong_bao_hiem','giam_dinh_vien',
    'hang_xe','dong_xe','to_thuc_hien','tai_khoan_quy','muc_thu_chi','nha_cung_cap','don_vi_lien_quan',
    'khach_hang','xe','ho_so','hang_muc','ho_so_nhat_ky','ho_so_tep','phat_sinh','kcs','dich_vu_nhanh',
    'de_nghi_chi','phieu_thu_chi','phan_bo','kiem_quy','bang_luong_thang','chot_thang']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- Hàm nghiệp vụ: chỉ người đã đăng nhập được gọi
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke all on schema app from public;
grant usage on schema app to authenticated;
revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated;

-- ---------------------------------------------------------------------
-- Ai đọc được gì
-- ---------------------------------------------------------------------
create policy doc on public.chi_nhanh for select to authenticated using (true);

create policy doc on public.nhan_vien for select to authenticated
  using (id = auth.uid() or app.la_nhan_vien());

-- Danh mục, cài đặt: mọi nhân viên (kể cả trưởng nhóm) đọc được
do $$
declare t text;
begin
  foreach t in array array['cai_dat','thue_suat_vat','hang_bao_hiem','van_phong_bao_hiem','giam_dinh_vien',
    'hang_xe','dong_xe','to_thuc_hien','muc_thu_chi','nha_cung_cap','don_vi_lien_quan']
  loop
    execute format($f$create policy doc on public.%I for select to authenticated
      using (app.la_nhan_vien() or app.co_vai_tro('truong_nhom'))$f$, t);
  end loop;
end $$;

-- Danh mục: giám đốc và kế toán thêm / sửa trực tiếp (không xóa, chỉ tắt "hoạt động")
do $$
declare t text;
begin
  foreach t in array array['hang_bao_hiem','van_phong_bao_hiem','giam_dinh_vien','hang_xe','dong_xe',
    'muc_thu_chi','nha_cung_cap','don_vi_lien_quan','tai_khoan_quy']
  loop
    execute format('grant insert, update on public.%I to authenticated', t);
    execute format($f$create policy them on public.%I for insert to authenticated
      with check (app.co_vai_tro('giam_doc','ke_toan'))$f$, t);
    execute format($f$create policy sua on public.%I for update to authenticated
      using (app.co_vai_tro('giam_doc','ke_toan')) with check (app.co_vai_tro('giam_doc','ke_toan'))$f$, t);
  end loop;
end $$;

-- Cài đặt, thuế suất: chỉ giám đốc
grant insert, update on public.cai_dat, public.thue_suat_vat to authenticated;
create policy them on public.cai_dat for insert to authenticated with check (app.co_vai_tro('giam_doc'));
create policy sua on public.cai_dat for update to authenticated using (app.co_vai_tro('giam_doc')) with check (app.co_vai_tro('giam_doc'));
create policy them on public.thue_suat_vat for insert to authenticated with check (app.co_vai_tro('giam_doc'));
create policy sua on public.thue_suat_vat for update to authenticated using (app.co_vai_tro('giam_doc')) with check (app.co_vai_tro('giam_doc'));

-- Tài khoản quỹ: kế toán, giám đốc, quản lý chung xem; đúng chi nhánh
create policy doc on public.tai_khoan_quy for select to authenticated
  using (app.co_vai_tro('giam_doc','ke_toan','quan_ly') and app.duoc_xem_chi_nhanh(chi_nhanh_id));

-- Khách hàng, xe: nhân viên văn phòng (trưởng nhóm không thấy SĐT khách)
create policy doc on public.khach_hang for select to authenticated using (app.la_nhan_vien());
create policy doc on public.xe for select to authenticated using (app.la_nhan_vien());

-- Hồ sơ và các bảng con: nhân viên văn phòng, đúng chi nhánh
create policy doc on public.ho_so for select to authenticated
  using (app.la_nhan_vien() and app.duoc_xem_chi_nhanh(chi_nhanh_id));
do $$
declare t text;
begin
  foreach t in array array['hang_muc','ho_so_nhat_ky','ho_so_tep','phat_sinh','kcs']
  loop
    execute format($f$create policy doc on public.%I for select to authenticated
      using (app.la_nhan_vien() and exists (select 1 from public.ho_so h where h.id = ho_so_id
             and app.duoc_xem_chi_nhanh(h.chi_nhanh_id)))$f$, t);
  end loop;
end $$;

create policy doc on public.dich_vu_nhanh for select to authenticated
  using (app.duoc_xem_chi_nhanh(chi_nhanh_id) and (app.la_nhan_vien() or tao_boi = auth.uid()));

-- Đề nghị chi: người duyệt và kế toán xem hết; người khác xem đề nghị của mình
create policy doc on public.de_nghi_chi for select to authenticated
  using (app.duoc_xem_chi_nhanh(chi_nhanh_id)
         and (app.co_vai_tro('giam_doc','quan_ly','ke_toan') or nguoi_de_nghi = auth.uid()));

-- Sổ quỹ: giám đốc, quản lý chung, kế toán
create policy doc on public.phieu_thu_chi for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.phan_bo for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan')
         and exists (select 1 from public.phieu_thu_chi p where p.id = phieu_id and app.duoc_xem_chi_nhanh(p.chi_nhanh_id)));

create policy doc on public.kiem_quy for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.bang_luong_thang for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.chot_thang for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));

-- ---------------------------------------------------------------------
-- Kho lưu ảnh, biên bản: 'ho-so-xe' (riêng tư)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('ho-so-xe', 'ho-so-xe', false)
on conflict (id) do nothing;

create policy "ho-so-xe doc" on storage.objects for select to authenticated
  using (bucket_id = 'ho-so-xe' and (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')));
create policy "ho-so-xe tai len" on storage.objects for insert to authenticated
  with check (bucket_id = 'ho-so-xe' and (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')));
