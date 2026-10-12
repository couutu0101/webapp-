-- =====================================================================
-- 005: Danh mục ban đầu (gom từ các file Excel của Tô Ký, tháng 7–10/2026)
-- Sau khi chạy, giám đốc / kế toán sửa tiếp trên màn hình Danh mục.
-- =====================================================================

insert into public.chi_nhanh (id, ten, dia_chi) values
  ('TK', 'Gara Hoàng Sơn – CN Tô Ký', '331 Tô Ký, xã Hóc Môn, TP.HCM')
on conflict (id) do nothing;

insert into public.to_thuc_hien (id, ten) values
  ('DS', 'Đồng sơn'), ('DMG', 'Điện – máy – gầm'), ('DT', 'Detailing')
on conflict (id) do nothing;

insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('han_muc_chi_quan_ly',     '2000000', 'Quản lý chung duyệt phiếu chi đến mức này; trên mức chỉ giám đốc duyệt'),
  ('muc_can_3_bao_gia',       '5000000', 'Đơn mua từ mức này phải đính kèm 3 báo giá (đợt 2)'),
  ('so_ngay_cho_duyet',       '3',       'Xe bảo hiểm chờ duyệt giá quá số ngày này thì báo giám đốc'),
  ('so_ngay_gui_ho_so',       '3',       'Gửi hồ sơ bảo hiểm trong số ngày này sau khi giao xe'),
  ('so_ngay_nhac_no',         '15',      'Bảo hiểm chưa trả sau số ngày này thì nhắc nợ'),
  ('so_ngay_no_giam_doc',     '30',      'Bảo hiểm chưa trả sau số ngày này thì giám đốc làm việc trực tiếp'),
  ('so_ngay_goi_cham_soc',    '3',       'Gọi hỏi thăm khách sau số ngày này kể từ khi giao xe'),
  ('hoa_hong_canh_bao_ty_le', '0.15',    'Cảnh báo khi hoa hồng GDV lớn hơn tỷ lệ này của giá duyệt bảo hiểm'),
  ('chenh_lech_kiem_ke',      '0.05',    'Chênh lệch kiểm kê trên tỷ lệ này phải lập biên bản (đợt 2)')
on conflict (khoa) do nothing;

-- Thuế suất VAT theo ngày hiệu lực. 8% là mức giảm có thời hạn:
-- khi trở lại 10%, thêm một dòng mới (ví dụ ('2027-01-01', 0.10)), KHÔNG sửa dòng cũ.
insert into public.thue_suat_vat (ap_dung_tu, ty_le) values ('2024-01-01', 0.08)
on conflict do nothing;

insert into public.hang_bao_hiem (ten) values
  ('Tasco'), ('DBV'), ('Bảo Minh'), ('Bảo Việt'), ('BSH'), ('BIC'), ('PTI'), ('PJICO'), ('MIC'), ('PVI'),
  ('VNI'), ('Bảo Long'), ('AAA'), ('Cathay'), ('Hùng Vương')
on conflict (ten) do nothing;

insert into public.van_phong_bao_hiem (hang_id, ten)
select h.id, v.ten from (values
  ('Bảo Minh','BT'), ('Bảo Minh','BN'),
  ('BSH','BT'), ('BSH','MN'), ('BSH','SG'),
  ('AAA','TSN'), ('AAA','TĐ'),
  ('VNI','BT'), ('PJICO','BD')
) v(hang, ten) join public.hang_bao_hiem h on h.ten = v.hang
on conflict do nothing;

insert into public.giam_dinh_vien (ten, hang_id, la_cho_them)
select v.ten, h.id, v.cho from (values
  ('GDV mới – chờ thêm', null, true),
  ('Hảo', 'Tasco', false), ('Sang', 'Tasco', false), ('Hiếu', 'Tasco', false),
  ('Hiếu', 'DBV', false), ('Tín', 'DBV', false), ('Nguyên', 'Cathay', false),
  ('Diệu', null, false), ('Nghĩa', null, false), ('Công Khanh', null, false), ('Hoàng', null, false),
  ('Đức', null, false), ('Cơ', null, false), ('Cường', null, false), ('Thành', null, false),
  ('Quang', null, false), ('Nam', null, false), ('Tâm', null, false), ('Trung Đức', null, false),
  ('Đôn', null, false), ('Luân', null, false)
) v(ten, hang, cho) left join public.hang_bao_hiem h on h.ten = v.hang;

insert into public.hang_xe (ten) values
  ('VinFast'), ('Mitsubishi'), ('Toyota'), ('Mazda'), ('Kia'), ('Hyundai'), ('Mercedes'), ('Ford'),
  ('Isuzu'), ('Thaco'), ('Honda'), ('Khác')
on conflict (ten) do nothing;

insert into public.dong_xe (hang_xe_id, ten)
select h.id, v.ten from (values
  ('VinFast','VF3'), ('VinFast','VF5'), ('VinFast','VF5 Plus'), ('VinFast','VF6'), ('VinFast','VF6 Plus'),
  ('VinFast','VF7'), ('VinFast','VF8'), ('VinFast','VF9'), ('VinFast','VF e34'), ('VinFast','Limo Green'),
  ('VinFast','EC Van'), ('VinFast','Herio'),
  ('Mitsubishi','Xpander'), ('Mitsubishi','Triton'),
  ('Toyota','Innova'), ('Toyota','Fortuner'), ('Toyota','Veloz'), ('Toyota','Vios'),
  ('Mazda','Mazda 2'), ('Mazda','Mazda 3'), ('Mazda','CX-5'),
  ('Kia','Morning'), ('Kia','Seltos'), ('Kia','Carnival'),
  ('Hyundai','Accent'), ('Hyundai','Tucson'),
  ('Mercedes','C-Class'), ('Ford','Ranger'), ('Ford','Everest'), ('Isuzu','D-Max'),
  ('Thaco','Tải Van'), ('Honda','CR-V'), ('Khác','Khác')
) v(hang, ten) join public.hang_xe h on h.ten = v.hang
on conflict do nothing;

insert into public.tai_khoan_quy (chi_nhanh_id, ten, hoat_dong) values
  ('TK', 'Tiền mặt', true),
  ('TK', 'TK công ty (331 331 331 68)', true),
  ('TK', 'LP Bank', true),
  ('TK', 'VCB TK Tiên (đã khóa – chỉ chốt số dư)', false)
on conflict do nothing;

insert into public.muc_thu_chi (loai, ten, nhom, tinh_chat, can_ho_so) values
  -- THU
  ('thu', 'Thu cọc sửa chữa',          null, 'thu_coc',          true),
  ('thu', 'Khách thanh toán sửa chữa', null, 'thu_khach',        true),
  ('thu', 'Bảo hiểm thanh toán',       null, 'thu_bao_hiem',     false),
  ('thu', 'Thu dịch vụ nhanh',         null, 'thu_dich_vu_nhanh',false),
  ('thu', 'Khách mua bảo hiểm',        null, 'thu_khac',         false),
  ('thu', 'Trạm sạc',                  null, 'thu_khac',         false),
  ('thu', 'Thu nội bộ (PHI, DTM, GI)', null, 'thu_noi_bo',       false),
  ('thu', 'Thu khác',                  null, 'thu_khac',         false),
  -- CHI – giá vốn (mua hàng: trả nợ nhà cung cấp; từ đợt 2 giá vốn ghi khi xuất kho)
  ('chi', 'Trả NCC – Phụ tùng VinFast', 'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Phụ tùng ngoài',   'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Vật tư sơn',       'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Vật tư ĐMG',       'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Vật tư CSX',       'gia_von', 'tra_ncc',      false),
  ('chi', 'Sửa chữa ngoài',             'gia_von', 'chi_phi',      true),
  ('chi', 'Giao nhận – kéo xe',         'gia_von', 'chi_phi',      false),
  ('chi', 'Hoa hồng bảo hiểm (GDV)',    'gia_von', 'tra_hoa_hong', true),
  -- CHI – cố định
  ('chi', 'Mặt bằng',                       'co_dinh', 'chi_phi',   false),
  ('chi', 'Bảo vệ',                         'co_dinh', 'chi_phi',   false),
  ('chi', 'Trả lương + thưởng',             'co_dinh', 'tra_luong', false),
  ('chi', 'BHXH',                           'co_dinh', 'chi_phi',   false),
  ('chi', 'Điện',                           'co_dinh', 'chi_phi',   false),
  ('chi', 'Internet – quảng cáo – hotline', 'co_dinh', 'chi_phi',   false),
  -- CHI – vận hành
  ('chi', 'Nước',                'van_hanh', 'chi_phi',  false),
  ('chi', 'Rác',                 'van_hanh', 'chi_phi',  false),
  ('chi', 'Cơm',                 'van_hanh', 'chi_phi',  false),
  ('chi', 'Văn phòng phẩm',      'van_hanh', 'chi_phi',  false),
  ('chi', 'Xăng',                'van_hanh', 'chi_phi',  false),
  ('chi', 'Dụng cụ – đồ nghề',   'van_hanh', 'chi_phi',  false),
  ('chi', 'Tiếp khách',          'van_hanh', 'chi_phi',  false),
  ('chi', 'Xây dựng',            'van_hanh', 'chi_phi',  false),
  ('chi', 'Nộp thuế',            'van_hanh', 'nop_thue', false),
  ('chi', 'Chi khác',            'van_hanh', 'chi_phi',  false),
  -- CHI – không vào lãi lỗ
  ('chi', 'Tạm ứng lương',                 null, 'tam_ung',    false),
  ('chi', 'Trả nội bộ (PHI, DTM, GI)',     null, 'tra_noi_bo', false),
  ('chi', 'Trả lại cọc cho khách',         null, 'tra_coc',    true)
on conflict (loai, ten) do nothing;

insert into public.nha_cung_cap (ten) values
  ('Phụ tùng VinFast'), ('Vật tư sơn VTN'), ('VTS Kim Anh'), ('An Việt'), ('Đại Dương'), ('Wurth'),
  ('Sơn Tuyết'), ('Masuma'), ('Huvi'), ('Kính ô tô'), ('Ghế da'), ('Ngôi Sao'), ('OTOTA'), ('BF'),
  ('Kéo xe'), ('Xe độ'), ('Chăm sóc xe'), ('Phụ tùng ngoài')
on conflict (ten) do nothing;

insert into public.don_vi_lien_quan (ten) values ('PHI'), ('DTM'), ('GI')
on conflict (ten) do nothing;
