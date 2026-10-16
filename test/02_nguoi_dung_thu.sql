-- Tài khoản thử cho kiểm thử giao diện
insert into auth.users (email, raw_user_meta_data) values
  ('thuan@gara.vn', '{"ho_ten":"Lê Ngọc Thuận"}'), ('long@gara.vn', '{"ho_ten":"Trần Tử Long"}'),
  ('tien@gara.vn', '{"ho_ten":"Võ Thị Mỹ Tiên"}'), ('duy@gara.vn', '{"ho_ten":"Nguyễn Trọng Duy"}'),
  ('han@gara.vn', '{"ho_ten":"Đặng Thanh Hận"}'), ('codong@gara.vn', '{"ho_ten":"Cổ đông A"}'), ('moi@gara.vn', '{"ho_ten":"Nhân viên mới"}'),
  ('giang@gara.vn', '{"ho_ten":"Trần Thị Giang"}');
update public.nhan_vien set chi_nhanh_id = 'TK', vai_tro = case email
  when 'thuan@gara.vn' then '{giam_doc}'::text[] when 'long@gara.vn' then '{quan_ly}' when 'tien@gara.vn' then '{ke_toan}'
  when 'duy@gara.vn' then '{cvdv,kho}' when 'han@gara.vn' then '{truong_nhom}' when 'giang@gara.vn' then '{truong_nhom}' when 'codong@gara.vn' then '{co_dong}' else '{}' end,
  to_id = case when email = 'han@gara.vn' then 'DS' when email = 'giang@gara.vn' then 'DT' end;   -- giang: trưởng nhóm Detailing (050)
update public.tai_khoan_quy set so_du_dau_ky = 5000000, ngay_dau_ky = current_date - 10 where ten = 'Tiền mặt' and chi_nhanh_id = 'TK';
