-- Kiểm thử nghiệp vụ trên Postgres cục bộ. Chạy sau 00_supabase_stub.sql và các file migrations.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
\o /dev/null

create schema if not exists kt;
create or replace function kt.dong_vai(p_email text) returns void language plpgsql as $$
declare v uuid;
begin
  execute 'reset role';
  if p_email is null then
    perform set_config('request.jwt.claims', '', false);
    execute 'reset role';
    return;
  end if;
  select id into v from auth.users where email = p_email;
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, false);
  execute 'set role authenticated';
end $$;
grant usage on schema kt to authenticated;
grant execute on all functions in schema kt to authenticated;

create table kt.ket_qua (stt serial, ten text, dat boolean, chi_tiet text);
grant all on kt.ket_qua to authenticated; grant usage, select on sequence kt.ket_qua_stt_seq to authenticated;

create or replace function kt.ghi(p_ten text, p_dat boolean, p_ct text default null) returns void
language sql security definer as $$ insert into kt.ket_qua (ten, dat, chi_tiet) values (p_ten, p_dat, p_ct) $$;
-- Chạy một lệnh và mong đợi lỗi chứa đoạn chữ
create or replace function kt.mong_loi(p_ten text, p_sql text, p_chua text) returns void
language plpgsql as $$
begin
  execute p_sql;
  perform kt.ghi(p_ten, false, 'Không báo lỗi');
exception when others then
  perform kt.ghi(p_ten, position(p_chua in sqlerrm) > 0, sqlerrm);
end $$;
grant execute on all functions in schema kt to authenticated;

-- ---------------------------------------------------------------------
-- Tài khoản
-- ---------------------------------------------------------------------
insert into auth.users (email, raw_user_meta_data) values
  ('thuan@gara.vn', '{"ho_ten":"Lê Ngọc Thuận"}'), ('long@gara.vn', '{"ho_ten":"Trần Tử Long"}'),
  ('tien@gara.vn', '{"ho_ten":"Võ Thị Mỹ Tiên"}'), ('duy@gara.vn', '{"ho_ten":"Nguyễn Trọng Duy"}'),
  ('han@gara.vn', '{"ho_ten":"Đặng Thanh Hận"}'), ('codong@gara.vn', '{"ho_ten":"Cổ đông A"}'),
  ('vinh@gara.vn', '{"ho_ten":"Phún Chí Vinh"}');
-- Giám đốc đầu tiên: gán bằng SQL (giống hướng dẫn triển khai)
update public.nhan_vien set vai_tro = '{giam_doc}', chi_nhanh_id = 'TK' where email = 'thuan@gara.vn';

select kt.dong_vai('thuan@gara.vn');
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["quan_ly"]}') from public.nhan_vien where email='long@gara.vn';
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["ke_toan"]}') from public.nhan_vien where email='tien@gara.vn';
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["cvdv","kho"]}') from public.nhan_vien where email='duy@gara.vn';
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["truong_nhom"],"to_id":"DS"}') from public.nhan_vien where email='han@gara.vn';
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["truong_nhom"],"to_id":"DMG"}') from public.nhan_vien where email='vinh@gara.vn';
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["co_dong"]}') from public.nhan_vien where email='codong@gara.vn';
select kt.mong_loi('GĐ không tự bỏ quyền GĐ',
  $$select public.luu_nhan_vien(auth.uid(), '{"chi_nhanh_id":"TK","vai_tro":["quan_ly"]}')$$, 'Không tự bỏ quyền');
select kt.mong_loi('Cổ đông chỉ một vai trò',
  $$select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["co_dong","ke_toan"]}') from public.nhan_vien where email='codong@gara.vn'$$, 'cổ đông chỉ có');

-- ---------------------------------------------------------------------
-- Bước 1: tiếp nhận
-- ---------------------------------------------------------------------
select kt.dong_vai('duy@gara.vn');
create temp table ctx (k text primary key, v text);
grant all on ctx to authenticated;

select kt.mong_loi('Thiếu SĐT bị chặn', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50h - 923.61','ten_khach','Anh Liêm','dien_thoai','09123','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'han_bao_hiem','2027-03-01',
  'tinh_trang_xe','Móp cửa trước trái','tu_van','Bảo dưỡng 20.000 km'))$$, 'Số điện thoại');

select kt.mong_loi('Xe BH thiếu GDV bị chặn', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50H92361','ten_khach','Anh Liêm','dien_thoai','0567248565','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'han_bao_hiem','2027-03-01',
  'tinh_trang_xe','Móp cửa','tu_van','Không'))$$, 'giám định viên');

select kt.mong_loi('GDV chờ thêm phải ghi tên', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50H92361','ten_khach','Anh Liêm','dien_thoai','0567248565','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'han_bao_hiem','2027-03-01',
  'gdv_id',(select id from public.giam_dinh_vien where la_cho_them),
  'tinh_trang_xe','Móp cửa','tu_van','Không'))$$, 'ghi tên giám định viên');

insert into ctx select 'hs1', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50h - 923.61','ten_khach','Anh Liêm','dien_thoai','0567 248 565','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'mau','Trắng','nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'han_bao_hiem','2027-03-01','han_bh_than_vo','2027-05-20',
  'tinh_trang_xe','Móp cửa trước trái','tu_van','Bảo dưỡng 20.000 km')))->>'id';
select kt.ghi('Lưu hạn BH thân vỏ vào hồ sơ và xe',
  (select h.han_bh_than_vo = '2027-05-20' and x.han_bh_than_vo = '2027-05-20' and h.han_bao_hiem = '2027-03-01'
     from public.ho_so h join public.xe x on x.id = h.xe_id where h.id = (select v::bigint from ctx where k='hs1')));
select kt.ghi('Tra cứu xe trả về hạn BH thân vỏ', (public.tra_cuu_xe('50H92361')->>'han_bh_than_vo') = '2027-05-20');
select kt.ghi('Bảng xem hồ sơ có hạn BH thân vỏ', (select han_bh_than_vo from public.v_ho_so where id = (select v::bigint from ctx where k='hs1')) = '2027-05-20');
select kt.ghi('Mã hồ sơ theo biển số',
  (select ma from public.ho_so where id = (select v::bigint from ctx where k='hs1')) = 'TK-' || to_char(now(),'YYMM') || '-50H92361',
  (select ma from public.ho_so where id = (select v::bigint from ctx where k='hs1')));

select kt.mong_loi('Xe đang có hồ sơ mở thì cảnh báo', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50H92361','ten_khach','Anh Liêm','dien_thoai','0567248565','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','khach','tinh_trang_xe','Thay gạt mưa','tu_van','Không'))$$, 'CANH_BAO:');
insert into ctx select 'hs2', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50H92361','ten_khach','Anh Liêm','dien_thoai','0567248565','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','khach','tinh_trang_xe','Thay gạt mưa','tu_van','Không','bo_qua_canh_bao',true)))->>'id';
select kt.ghi('Lần hai trong tháng thêm đuôi -2',
  (select ma from public.ho_so where id = (select v::bigint from ctx where k='hs2')) like '%-50H92361-2',
  (select ma from public.ho_so where id = (select v::bigint from ctx where k='hs2')));
insert into ctx select 'hs3', (public.tiep_nhan_xe(jsonb_build_object(
  'ten_khach','Khách mới','dien_thoai','0909000111','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Xe mới chưa biển','tu_van','Dán phim')))->>'id';
-- Xe bảo hiểm không có BH thân vỏ và TNDS (CVDV tích "Không có") vẫn tiếp nhận được; chạy thử rồi bỏ để không ảnh hưởng bài sau
do $t$ declare r jsonb; begin
  begin
    r := public.tiep_nhan_xe(jsonb_build_object(
      'bien_so','51K-111.22','ten_khach','Khách thử','dien_thoai','0909000222','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
      'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
      'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),
      'tinh_trang_xe','Trầy cản','tu_van','Tư vấn mua BH'));
    raise exception 'DA_LUU %', r->>'ma';
  exception when others then
    perform kt.ghi('Xe bảo hiểm không có ngày BH thân vỏ/TNDS vẫn tiếp nhận được', sqlerrm like 'DA_LUU%', sqlerrm);
  end;
end $t$;
select kt.ghi('Xe chưa có biển dùng KBS',
  (select ma from public.ho_so where id = (select v::bigint from ctx where k='hs3')) like '%-KBS01',
  (select ma from public.ho_so where id = (select v::bigint from ctx where k='hs3')));
select kt.ghi('Không tạo trùng khách theo SĐT', (select count(*) from public.khach_hang where dien_thoai='0567248565') = 1);

-- ---------------------------------------------------------------------
-- Bước 2–3: báo giá, duyệt giá
-- ---------------------------------------------------------------------
select public.luu_bao_gia((select v::bigint from ctx where k='hs1'), '[
  {"ten":"Gò sơn cửa trước trái","nhom":"dong_son","gia_bao":3000000},
  {"ten":"Thay tay nắm cửa","nhom":"phu_tung","gia_bao":2000000},
  {"ten":"Phủ ceramic (khách làm thêm)","nhom":"detailing","nguoi_tra":"khach","gia_bao":500000,"xuat_hd":false}]');
select kt.ghi('Chưa có ảnh nhận xe vẫn lập được báo giá → trạng thái báo giá',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'bao_gia'
  and not exists (select 1 from public.ho_so_tep where ho_so_id=(select v::bigint from ctx where k='hs1')));
select public.them_tep((select v::bigint from ctx where k='hs1'), 'tiep_nhan', 'anh', 'TK/hs1/nhan-xe-1.jpg');

select kt.mong_loi('Chưa duyệt thì chưa lập lệnh', format($$select public.lap_lenh_sua_chua(%s, now() + interval '2 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=%s))$$,
  (select v from ctx where k='hs1'), (select v from ctx where k='hs1')), 'Chưa duyệt giá');

select kt.mong_loi('Ngày duyệt sau hôm nay bị chặn', format($$select public.duyet_gia(%s, current_date + 1, '[]')$$, (select v from ctx where k='hs1')), 'sau hôm nay');

select public.duyet_gia((select v::bigint from ctx where k='hs1'), current_date, (
  select jsonb_agg(jsonb_build_object('id', id, 'dong_y', true,
    'gia_duyet', case nhom when 'dong_son' then 2800000 when 'phu_tung' then 1900000 else 500000 end))
  from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs1')));
select kt.ghi('Duyệt hết → đã duyệt', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'da_duyet');

-- BH: (2.800.000 + 1.900.000) × 1,08 = 5.076.000 ; khách: 500.000 không hóa đơn
select kt.ghi('Tiền bảo hiểm có VAT 8%', (select bh_duyet from public.tien_ho_so((select v::bigint from ctx where k='hs1'))) = 5076000,
  (select bh_duyet::text from public.tien_ho_so((select v::bigint from ctx where k='hs1'))));
select kt.ghi('Dòng khách không hóa đơn không cộng VAT', (select khach_duyet from public.tien_ho_so((select v::bigint from ctx where k='hs1'))) = 500000);
-- 020: chia công nợ ngay khi duyệt: khách chi trả 1.000.000 = 500.000 dòng khách + 500.000 khấu trừ
select kt.ghi('020 Chia công nợ: trả về BH / khách', (select public.duyet_gia_chia((select v::bigint from ctx where k='hs1'), current_date, '[]', 1000000))
  = '{"tong": 5576000, "bao_hiem": 4576000, "khach": 1000000, "khau_tru": 500000}'::jsonb,
  (select public.duyet_gia_chia((select v::bigint from ctx where k='hs1'), current_date, '[]', 1000000)::text));
select kt.ghi('020 Nợ BH = 4.576.000, nợ khách = 1.000.000', (select con_no_bh = 4576000 and con_no_khach = 1000000 from public.tien_ho_so((select v::bigint from ctx where k='hs1'))));
select kt.mong_loi('020 Khách trả ít hơn dòng khách bị chặn', format('select public.duyet_gia_chia(%s, current_date, ''[]'', 100000)', (select v from ctx where k='hs1')), 'ít nhất');
select kt.mong_loi('020 Khách trả vượt tổng bị chặn', format('select public.duyet_gia_chia(%s, current_date, ''[]'', 9000000)', (select v from ctx where k='hs1')), 'vượt tổng');
select public.duyet_gia_chia((select v::bigint from ctx where k='hs1'), current_date, '[]', 500000);  -- trả lại như cũ cho các bài sau
select kt.ghi('020 Đặt lại khách trả = dòng khách → khấu trừ 0', (select khau_tru_giam_tru from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 0);

-- ---------------------------------------------------------------------
-- Bước 4–6: lệnh sửa chữa, trưởng nhóm, phát sinh
-- ---------------------------------------------------------------------
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs1'), now() + interval '2 day', (
  select jsonb_agg(jsonb_build_object('id', id, 'to_id', case nhom when 'detailing' then 'DT' else 'DS' end, 'nguoi_lam', 'Lương'))
  from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs1')));
select kt.ghi('Lập lệnh → đang sửa', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'dang_sua');

select kt.dong_vai('han@gara.vn');
select kt.ghi('Trưởng nhóm không đọc được bảng hồ sơ', (select count(*) from public.ho_so) = 0);
select kt.ghi('Trưởng nhóm không đọc được SĐT khách', (select count(*) from public.khach_hang) = 0);
select kt.ghi('Trưởng nhóm không xem được tiền', (select count(*) from public.tien_ho_so((select v::bigint from ctx where k='hs1'))) = 0);
select kt.ghi('Bảng việc tổ có xe', jsonb_array_length(public.bang_viec_to()) = 1, public.bang_viec_to()::text);
select kt.dong_vai(null);
insert into ctx select 'dong_dt', id::text from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs1') and to_id='DT';
insert into ctx select 'dong_ds1', min(id)::text from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs1') and to_id='DS';
insert into ctx select 'dong_ds2', max(id)::text from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs1') and to_id='DS';
select kt.dong_vai('han@gara.vn');
select kt.mong_loi('Trưởng nhóm ĐS không báo xong dòng Detailing', format($$select public.bao_xong_hang_muc(%s)$$,
  (select v from ctx where k='dong_dt')), 'không thuộc tổ');
select public.bao_xong_hang_muc((select v::bigint from ctx where k='dong_ds1'));
select public.bao_phat_sinh((select v::bigint from ctx where k='hs1'), 'Phát hiện nứt đèn pha trái');

select kt.dong_vai('duy@gara.vn');
select kt.ghi('Cảnh báo phát sinh hiện ra', exists (select 1 from public.v_canh_bao where loai='phat_sinh'));
select kt.ghi('Báo giá bổ sung là lần 1', public.luu_bao_gia((select v::bigint from ctx where k='hs1'),
  '[{"ten":"Thay đèn pha trái","nhom":"phu_tung","gia_bao":4000000}]') = 1);
select kt.ghi('Phát sinh đã xử lý', not exists (select 1 from public.v_canh_bao where loai='phat_sinh'));
select public.bao_xong_hang_muc((select v::bigint from ctx where k='dong_ds2'));
select public.bao_xong_hang_muc((select v::bigint from ctx where k='dong_dt'));
select kt.ghi('Còn dòng phát sinh chờ duyệt thì chưa sang KCS', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'dang_sua');
select public.duyet_gia((select v::bigint from ctx where k='hs1'), current_date, (
  select jsonb_agg(jsonb_build_object('id', id, 'dong_y', true, 'gia_duyet', 3500000))
  from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs1') and trang_thai='cho_duyet'));
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs1'), null, (
  select jsonb_agg(jsonb_build_object('id', id, 'to_id', 'DS'))
  from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs1') and trang_thai='duyet'));
select public.bao_xong_hang_muc(id) from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs1') and trang_thai='dang_lam';
select kt.ghi('Xong hết → chờ KCS', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'cho_kcs');

-- ---------------------------------------------------------------------
-- Bước 7–8: KCS, giao xe
-- ---------------------------------------------------------------------
select kt.mong_loi('CVDV không được ký KCS', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs1')), 'không có quyền');
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('KCS đạt phải có ảnh sau sửa', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs1')), 'ảnh sau sửa');
select public.kcs((select v::bigint from ctx where k='hs1'), false, 'Sơn chảy cửa trái', array[(select v::bigint from ctx where k='dong_ds1')]);
select kt.ghi('KCS chưa đạt → về đang sửa', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'dang_sua');
select public.bao_xong_hang_muc((select v::bigint from ctx where k='dong_ds1'));
select public.them_tep((select v::bigint from ctx where k='hs1'), 'kcs', 'anh', 'TK/hs1/sau-sua-1.jpg');
select public.kcs((select v::bigint from ctx where k='hs1'), true);
select kt.ghi('KCS đạt', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'dat_kcs');

select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('Khách còn nợ thì chưa giao nếu chưa duyệt', format($$select public.giao_xe(%s, '{"khau_tru_giam_tru":500000,"so_hd_bao_hiem":"HD0001"}')$$,
  (select v from ctx where k='hs1')), 'còn nợ');
select kt.ghi('Lỗi giao xe không ghi khấu trừ (giao dịch đã quay lui)',
  (select khau_tru_giam_tru from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 0);
select kt.dong_vai('long@gara.vn');
select public.duyet_giao_xe_con_no((select v::bigint from ctx where k='hs1'));
select kt.dong_vai('tien@gara.vn');
select public.giao_xe((select v::bigint from ctx where k='hs1'), '{"khau_tru_giam_tru":500000,"so_hd_bao_hiem":"HD0001","cam_nhan_khach":"Hài lòng"}');
-- BH: 5.076.000 + 3.500.000×1,08 = 8.856.000 ; trừ khấu trừ 500.000 → 8.356.000. Khách: 500.000 + 500.000 = 1.000.000
select kt.ghi('Phải thu BH sau khấu trừ', (select phai_thu_bh from public.tien_ho_so((select v::bigint from ctx where k='hs1'))) = 8356000,
  (select phai_thu_bh::text from public.tien_ho_so((select v::bigint from ctx where k='hs1'))));
select kt.ghi('Phải thu khách gồm khấu trừ', (select phai_thu_khach from public.tien_ho_so((select v::bigint from ctx where k='hs1'))) = 1000000);
select kt.ghi('Đã giao', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'da_giao');

-- ---------------------------------------------------------------------
-- Thu tiền, hồ sơ bảo hiểm, tự đóng hồ sơ
-- ---------------------------------------------------------------------
select kt.mong_loi('Thu khách vượt nợ bị chặn', format($$select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1500000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1500000))))$$, (select v from ctx where k='hs1')), 'vượt số khách còn nợ');
select kt.mong_loi('TK cá nhân đã khóa không ghi được', format($$select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten like 'VCB%%'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1000000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1000000))))$$, (select v from ctx where k='hs1')), 'đã khóa');
select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1000000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs1'),'so_tien',1000000))));
select kt.ghi('Khách trả đủ nhưng chưa gửi hồ sơ BH thì chưa đóng', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'da_giao');
select public.gui_ho_so_bh((select v::bigint from ctx where k='hs1'), current_date);
-- Bảo hiểm chuyển gộp 10.000.000, mới có bảng kê cho 5.000.000
insert into ctx select 'pt_bh', public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten like 'TK công ty%'),'muc_id',(select id from public.muc_thu_chi where ten='Bảo hiểm thanh toán'),
  'hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'so_tien',10000000,
  'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs1'),'so_tien',5000000))))::text;
select kt.ghi('Cảnh báo tiền BH chưa chia', exists (select 1 from public.v_canh_bao where loai='thu_chua_phan_bo'));
select kt.mong_loi('Chia vượt nợ BH bị chặn', format($$select public.phan_bo_them(%s, jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',4000000)))$$,
  (select v from ctx where k='pt_bh'), (select v from ctx where k='hs1')), 'vượt số bảo hiểm còn nợ');
select public.phan_bo_them((select v::bigint from ctx where k='pt_bh'), jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs1'),'so_tien',3356000)));
select kt.ghi('Hết nợ → tự đóng hồ sơ', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'dong');
select kt.mong_loi('Chia vượt số tiền phiếu bị chặn', format($$select public.phan_bo_them(%s, jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1700000)))$$,
  (select v from ctx where k='pt_bh'), (select v from ctx where k='hs2')), 'vượt');
select public.huy_phieu((select v::bigint from ctx where k='pt_bh'), 'Nhập nhầm tài khoản');
select kt.ghi('Hủy phiếu thu → hồ sơ mở lại', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'da_gui_hs');

select kt.mong_loi('Hoa hồng quá lớn thì cảnh báo', format($$select public.nhap_hoa_hong_gdv(%s, 5000000)$$, (select v from ctx where k='hs1')), 'CANH_BAO:');
select public.nhap_hoa_hong_gdv((select v::bigint from ctx where k='hs1'), 450000, '5% + 200.000');
select kt.ghi('Nhập hoa hồng', (select hoa_hong_gdv from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 450000);

-- ---------------------------------------------------------------------
-- Đề nghị chi, duyệt theo hạn mức
-- ---------------------------------------------------------------------
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'dn1', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Điện'),
  'so_tien',2500000,'vat_dau_vao',227273,'noi_dung','Tiền điện tháng 10'))::text;
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('QL không duyệt khoản trên 2 triệu', format($$select public.duyet_de_nghi_chi(%s, true)$$, (select v from ctx where k='dn1')), 'chỉ giám đốc');
insert into ctx select 'dn2', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Cơm'),
  'so_tien',300000,'noi_dung','Cơm khách'))::text;
select kt.mong_loi('Không tự duyệt phiếu mình lập', format($$select public.duyet_de_nghi_chi(%s, true)$$, (select v from ctx where k='dn2')), 'tự duyệt');
select kt.dong_vai('thuan@gara.vn');
insert into ctx select 'dn_gd', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Cơm'),
  'so_tien',150000,'noi_dung','Nước uống khách'))::text;
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_gd'), true);
select kt.ghi('Giám đốc tự duyệt đề nghị chi do mình lập', (select trang_thai from public.de_nghi_chi where id=(select v::bigint from ctx where k='dn_gd')) = 'da_duyet');
select public.huy_de_nghi_chi((select v::bigint from ctx where k='dn_gd'));
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('Chưa duyệt thì kế toán chưa chi', format($$select public.chi_tien(%s, (select id from public.tai_khoan_quy where ten='Tiền mặt'))$$,
  (select v from ctx where k='dn1')), 'chưa được duyệt');
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn1'), true);
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn2'), true);
select kt.dong_vai('tien@gara.vn');
select public.chi_tien((select v::bigint from ctx where k='dn1'), (select id from public.tai_khoan_quy where ten='Tiền mặt'));
select kt.ghi('Đề nghị đã chi', (select trang_thai from public.de_nghi_chi where id=(select v::bigint from ctx where k='dn1')) = 'da_chi');
select kt.ghi('Số dư tiền mặt = 1.000.000 − 2.500.000',
  (select so_du from public.v_so_du_quy where ten='Tiền mặt') = -1500000, (select so_du::text from public.v_so_du_quy where ten='Tiền mặt'));

-- Tách nhỏ phiếu
select kt.dong_vai('duy@gara.vn');
select public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Dụng cụ – đồ nghề'),'so_tien',1500000,'noi_dung','Mua cờ lê'));
select public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Dụng cụ – đồ nghề'),'so_tien',1500000,'noi_dung','Mua tua vít'));
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('Phát hiện tách nhỏ phiếu', exists (select 1 from public.v_canh_bao where loai='de_nghi_cho_duyet' and noi_dung like '%tách nhỏ%'));

-- ---------------------------------------------------------------------
-- Khóa sổ tháng, dịch vụ nhanh, cổ đông
-- ---------------------------------------------------------------------
select kt.dong_vai(null);
insert into public.chot_thang (chi_nhanh_id, thang) values ('TK', date_trunc('month', current_date - interval '1 month')::date);
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('Tháng đã chốt không ghi được', $$select public.lap_phieu_chuyen(jsonb_build_object('ngay', (date_trunc('month', current_date) - interval '1 day')::date,
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='TK công ty (331 331 331 68)'),'tai_khoan_den_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'so_tien',5000000))$$, 'đã chốt sổ');
select public.lap_phieu_chuyen(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='TK công ty (331 331 331 68)'),'tai_khoan_den_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'so_tien',5000000));
select kt.ghi('Chuyển quỹ cộng vào tiền mặt', (select so_du from public.v_so_du_quy where ten='Tiền mặt') = 3500000);

select kt.dong_vai('han@gara.vn');
insert into ctx select 'dvn', public.ghi_dich_vu_nhanh('{"bien_so":"51b70458","dich_vu":"Rửa xe","nguoi_lam":"Quỳnh","so_tien":80000}')::text;
select kt.dong_vai('tien@gara.vn');
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),
  'muc_id',(select id from public.muc_thu_chi where ten='Thu dịch vụ nhanh'),'so_tien',80000,
  'phan_bo',jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id',(select v::bigint from ctx where k='dvn'),'so_tien',80000))));
select kt.ghi('Dịch vụ nhanh đã thu', (select da_thu from public.v_dich_vu_nhanh where id=(select v::bigint from ctx where k='dvn')) = 80000);
select kt.ghi('Doanh thu hôm nay có dịch vụ nhanh', exists (select 1 from public.v_doanh_thu where nguon='dich_vu_nhanh' and so_tien=80000));

select kt.dong_vai('codong@gara.vn');
select kt.ghi('Cổ đông không thấy hồ sơ', (select count(*) from public.v_ho_so) = 0);
select kt.ghi('Cổ đông không thấy sổ quỹ', (select count(*) from public.v_phieu_thu_chi) = 0);
select kt.mong_loi('Cổ đông không tiếp nhận xe được', $$select public.tiep_nhan_xe('{}')$$, 'không có quyền');

select kt.dong_vai('duy@gara.vn');
select public.huy_ho_so((select v::bigint from ctx where k='hs3'), 'Khách không sửa');
select kt.ghi('Hủy hồ sơ', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs3')) = 'huy');
select kt.ghi('Biển số hiển thị đúng', public.bien_so_hien_thi('50H92361') = '50H-923.61' and public.bien_so_hien_thi('51D1234') = '51D-1234' and public.bien_so_hien_thi('59X112345') = '59X1-123.45', public.bien_so_hien_thi('50H92361'));
select kt.ghi('Duy thấy cảnh báo', true, (select string_agg(loai || ': ' || noi_dung, ' | ') from public.v_canh_bao));

select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('Kiểm quỹ lệch phải ghi lý do', $$select public.ghi_kiem_quy((select id from public.tai_khoan_quy where ten='Tiền mặt'), 3400000)$$, 'Lệch');
select kt.ghi('Kiểm quỹ khớp', (public.ghi_kiem_quy((select id from public.tai_khoan_quy where ten='Tiền mặt'), 3580000)->>'chenh_lech')::numeric = 0);
-- ---------------------------------------------------------------------
-- 009: Báo giá theo nguồn + VAT riêng từng báo giá
-- ---------------------------------------------------------------------
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs_k', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-222.33','ten_khach','Khách lẻ','dien_thoai','0909000333','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Trầy cản','tu_van','Không')))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_k'),
  '[{"ten":"Sơn cản sau","nhom":"dong_son","gia_bao":1000000},{"ten":"Phủ ceramic","nhom":"detailing","gia_bao":500000}]', 0.10);
select kt.ghi('Khách ngoài BH: lưu báo giá là Đã duyệt giá, không qua duyệt',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_k')) = 'da_duyet'
  and not exists (select 1 from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_k') and trang_thai <> 'duyet'));
select kt.ghi('Khách ngoài BH: VAT 10% → phải thu 1.650.000',
  (select phai_thu_khach from public.tien_ho_so((select v::bigint from ctx where k='hs_k'))) = 1650000,
  (select phai_thu_khach::text from public.tien_ho_so((select v::bigint from ctx where k='hs_k'))));
select kt.ghi('Doanh thu ghi ngày lưu báo giá, theo VAT 10%',
  (select sum(so_tien) from public.v_doanh_thu where ho_so_id=(select v::bigint from ctx where k='hs_k')) = 1650000
  and (select sum(vat_ra) from public.v_doanh_thu where ho_so_id=(select v::bigint from ctx where k='hs_k')) = 150000);
select public.lap_bao_gia((select v::bigint from ctx where k='hs_k'), '[{"ten":"Thay gạt mưa","nhom":"phu_tung","gia_bao":200000}]', 0.08);
select kt.ghi('Khách ngoài BH: báo giá bổ sung cũng tự duyệt, VAT riêng 8%',
  (select trang_thai = 'duyet' and lan_bao_gia = 1 and ty_le_vat = 0.08 from public.hang_muc
    where ho_so_id=(select v::bigint from ctx where k='hs_k') and ten='Thay gạt mưa')
  and (select phai_thu_khach from public.tien_ho_so((select v::bigint from ctx where k='hs_k'))) = 1866000);
select kt.mong_loi('VAT ngoài 8/10/12% bị chặn', format($$select public.lap_bao_gia(%s, '[{"ten":"X","gia_bao":1}]', 0.09)$$,
  (select v from ctx where k='hs_k')), 'VAT chỉ chọn');
insert into ctx select 'hs_b', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-444.55','ten_khach','Khách BH','dien_thoai','0909000444','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'tinh_trang_xe','Móp cửa','tu_van','Không')))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_b'), '[{"ten":"Gò cửa","nhom":"dong_son","gia_bao":2000000}]', 0.12);
select kt.ghi('Xe BH: báo giá chờ duyệt, dòng do bảo hiểm trả, VAT 12%',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b')) = 'bao_gia'
  and (select bool_and(trang_thai = 'cho_duyet' and nguoi_tra = 'bao_hiem' and ty_le_vat = 0.12) from public.hang_muc
       where ho_so_id=(select v::bigint from ctx where k='hs_b')));
select public.duyet_gia((select v::bigint from ctx where k='hs_b'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',1800000)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b')));
select kt.ghi('Xe BH: duyệt 1.800.000, VAT 12% → BH duyệt 2.016.000',
  (select bh_duyet from public.tien_ho_so((select v::bigint from ctx where k='hs_b'))) = 2016000,
  (select bh_duyet::text from public.tien_ho_so((select v::bigint from ctx where k='hs_b'))));
-- ---------------------------------------------------------------------
-- 010: Người làm bước tiếp theo
-- ---------------------------------------------------------------------
select kt.ghi('Tiếp nhận xong: bước báo giá tự giao cho CVDV tiếp nhận (Duy)',
  (select nguoi_tiep_theo from public.ho_so where id=(select v::bigint from ctx where k='hs_b')) = (select id from public.nhan_vien where email='duy@gara.vn'));
select kt.ghi('Bảng xem việc hiện tên người được giao',
  (select nguoi_tiep_theo_ten from public.v_viec_ho_so where ho_so_id=(select v::bigint from ctx where k='hs_b')) = (select ho_ten from public.nhan_vien where email='duy@gara.vn'));
select public.giao_viec((select v::bigint from ctx where k='hs_b'), (select id from public.nhan_vien where email='thuan@gara.vn'));
select kt.ghi('Người vừa làm bước được chọn người làm bước tiếp theo',
  (select nguoi_tiep_theo from public.ho_so where id=(select v::bigint from ctx where k='hs_b')) = (select id from public.nhan_vien where email='thuan@gara.vn')
  and exists (select 1 from public.ho_so_nhat_ky where ho_so_id=(select v::bigint from ctx where k='hs_b') and ghi_chu like 'Giao bước tiếp theo cho %'));
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('Kế toán không đổi được người của hồ sơ mình không làm', format($$select public.giao_viec(%s, null)$$,
  (select v from ctx where k='hs_b')), 'Chỉ quản lý chung hoặc giám đốc');
select kt.dong_vai('long@gara.vn');
select public.giao_viec((select v::bigint from ctx where k='hs_b'), (select id from public.nhan_vien where email='duy@gara.vn'));
select kt.ghi('Quản lý chung đổi người được giao',
  (select nguoi_tiep_theo from public.ho_so where id=(select v::bigint from ctx where k='hs_b')) = (select id from public.nhan_vien where email='duy@gara.vn'));
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_b'), now() + interval '1 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b')));
select kt.ghi('Đang sửa: giao theo tổ, không giao một người',
  (select trang_thai = 'dang_sua' and nguoi_tiep_theo is null from public.ho_so where id=(select v::bigint from ctx where k='hs_b')));
select kt.ghi('Đang sửa: bảng xem hiện tên trưởng nhóm của tổ',
  (select nguoi_tiep_theo_ten from public.v_viec_ho_so where ho_so_id=(select v::bigint from ctx where k='hs_b')) = 'Đặng Thanh Hận (tổ DS)',
  (select nguoi_tiep_theo_ten from public.v_viec_ho_so where ho_so_id=(select v::bigint from ctx where k='hs_b')));
select kt.dong_vai(null);  -- chuyển bước trực tiếp để thử gợi ý (bỏ qua KCS thật)
update public.ho_so set trang_thai = 'cho_kcs' where id=(select v::bigint from ctx where k='hs_b');
select kt.ghi('Chờ KCS: tự giao quản lý chung',
  (select nguoi_tiep_theo from public.ho_so where id=(select v::bigint from ctx where k='hs_b')) = (select id from public.nhan_vien where email='long@gara.vn'));
update public.ho_so set trang_thai = 'dat_kcs' where id=(select v::bigint from ctx where k='hs_b');
select kt.ghi('Đạt KCS: tự giao kế toán',
  (select nguoi_tiep_theo from public.ho_so where id=(select v::bigint from ctx where k='hs_b')) = (select id from public.nhan_vien where email='tien@gara.vn'));
update public.nhan_vien set hoat_dong = false where email = 'tien@gara.vn';
select kt.ghi('Chưa có kế toán thì giao cho giám đốc', app.nhan_vien_dau('ke_toan', 'TK') = (select id from public.nhan_vien where email='thuan@gara.vn'));
update public.nhan_vien set hoat_dong = true where email = 'tien@gara.vn';
select kt.ghi('Hồ sơ từ Excel không giao ai', not exists (select 1 from public.ho_so where tu_excel and nguoi_tiep_theo is not null));
-- ---------------------------------------------------------------------
-- 012: KHO
-- ---------------------------------------------------------------------
select kt.dong_vai('duy@gara.vn');   -- CVDV kiêm kho
-- Xe có lệnh sửa chữa để cấp phụ tùng
insert into ctx select 'hs_kho', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-777.88','ten_khach','Khách kho','dien_thoai','0909000777','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'tinh_trang_xe','Móp cửa','tu_van','Không')))->>'id';
insert into ctx select 'hang_son', public.luu_hang_kho('{"ma":"son-trang 01","ten":"Sơn trắng 2K","nhom":"Sơn","dvt":"Lít","dvt_nhap":"Can 4L","he_so":4,"ton_toi_thieu":2}')::text;
insert into ctx select 'hang_guong', public.luu_hang_kho('{"ma":"PT-GUONG","ten":"Gương chiếu hậu trái VF3","nhom":"Phụ tùng","dvt":"Cái"}')::text;
select kt.ghi('Mã hàng tự viết hoa, bỏ khoảng trắng', (select ma from public.hang_kho where id=(select v::bigint from ctx where k='hang_son')) = 'SON-TRANG01');
select kt.mong_loi('Không trùng mã hàng', $$select public.luu_hang_kho('{"ma":"PT-GUONG","ten":"X","dvt":"Cái"}')$$, 'đã có trong kho');
select kt.mong_loi('Xe chưa có lệnh sửa chữa thì chưa đề xuất vật tư', format($$select public.lap_de_xuat_vat_tu(jsonb_build_object('ho_so_id',%s,
  'dong',jsonb_build_array(jsonb_build_object('hang_id',%s,'so_luong',1))))$$, (select v from ctx where k='hs_kho'), (select v from ctx where k='hang_son')), 'chưa có lệnh sửa chữa');
select public.lap_bao_gia((select v::bigint from ctx where k='hs_kho'), '[{"ten":"Sơn cửa","nhom":"son","gia_bao":3000000}]', 0.08);
select public.duyet_gia((select v::bigint from ctx where k='hs_kho'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_kho')));
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_kho'), now() + interval '2 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_kho')));

-- Nhập 2 lần sơn: 2 can × 1.000.000 rồi 1 can × 1.200.000 (VAT 8%) → 8 lít giá 270.000/lít, 4 lít giá 324.000/lít
insert into ctx select 'pn1', (public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Vật tư sơn VTN'),
  'so_hoa_don','HD-01','dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_son'),'so_luong',2,'don_gia',1000000,'ty_le_vat',0.08)))))->>'id';
insert into ctx select 'pn2', (public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Vật tư sơn VTN'),
  'so_hoa_don','HD-02','dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_son'),'so_luong',1,'don_gia',1200000,'ty_le_vat',0.08)))))->>'id';
select kt.ghi('Nhập theo can, tồn theo lít (hệ số 4): tồn 12 lít, giá trị 3.456.000',
  (select ton = 12 and gia_tri = 3456000 from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_son')),
  (select ton || ' / ' || gia_tri from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_son')));
select kt.ghi('Mã phiếu nhập theo chi nhánh – tháng', (select ma from public.phieu_nhap where id=(select v::bigint from ctx where k='pn1')) like 'TK-PN____-001');

-- Trưởng nhóm đề xuất 10 lít sơn + 1 gương
select kt.dong_vai('han@gara.vn');
insert into ctx select 'dx1', (public.lap_de_xuat_vat_tu(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_kho'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_son'),'so_luong',10),
                           jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_guong'),'so_luong',1)))))->>'id';
select kt.ghi('Trưởng nhóm lập đề xuất, tự ghi tổ của mình', (select to_id from public.de_xuat_vat_tu where id=(select v::bigint from ctx where k='dx1')) = 'DS');
select kt.mong_loi('Trưởng nhóm không tự xuất kho', format($$select public.xuat_kho_de_xuat(%s)$$, (select v from ctx where k='dx1')), 'không có quyền');

-- Kho xuất: sơn đủ (nhập trước xuất trước), gương hết hàng
select kt.dong_vai('duy@gara.vn');
select public.xuat_kho_de_xuat((select v::bigint from ctx where k='dx1'));
select kt.ghi('Xuất 10 lít theo nhập trước xuất trước: 8×270.000 + 2×324.000 = 2.808.000',
  (select gia_von from public.v_gia_von_ho_so where ho_so_id=(select v::bigint from ctx where k='hs_kho')) = 2808000,
  (select gia_von::text from public.v_gia_von_ho_so where ho_so_id=(select v::bigint from ctx where k='hs_kho')));
select kt.ghi('Gương hết hàng: phiếu đề xuất vẫn chờ xuất',
  (select trang_thai from public.de_xuat_vat_tu where id=(select v::bigint from ctx where k='dx1')) = 'cho_xuat');
select kt.mong_loi('Không xuất quá tồn', format($$select public.xuat_kho_de_xuat(%s, jsonb_build_array(jsonb_build_object('dong_id',%s,'so_luong',1)))$$,
  (select v from ctx where k='dx1'), (select id from public.de_xuat_dong where de_xuat_id=(select v::bigint from ctx where k='dx1') and hang_id=(select v::bigint from ctx where k='hang_guong'))), 'Không đủ hàng');

-- Chuyển mua gương 6.000.000 (+8% = 6.480.000 ≥ 5 triệu → cần 3 báo giá)
insert into ctx select 'dm1', (public.chuyen_mua((select v::bigint from ctx where k='dx1'), jsonb_build_object(
  'nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'dong',jsonb_build_array(jsonb_build_object('dong_id',(select id from public.de_xuat_dong where de_xuat_id=(select v::bigint from ctx where k='dx1') and hang_id=(select v::bigint from ctx where k='hang_guong')),
    'so_luong',1,'don_gia',6000000,'ty_le_vat',0.08)))))->>'id';
select kt.ghi('Chuyển mua: xe hiện "Chờ phụ tùng"', exists (select 1 from public.v_cho_phu_tung where ho_so_id=(select v::bigint from ctx where k='hs_kho')));
select kt.ghi('Đề nghị mua tính tổng sau VAT, đánh dấu cần 3 báo giá',
  (select tong_tien = 6480000 and can_3_bao_gia from public.v_de_nghi_mua where id=(select v::bigint from ctx where k='dm1')));
select kt.mong_loi('Kho không tự duyệt đề nghị mua', format($$select public.duyet_de_nghi_mua(%s, true)$$, (select v from ctx where k='dm1')), 'không có quyền');
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('Từ 5 triệu phải đủ 3 báo giá', format($$select public.duyet_de_nghi_mua(%s, true)$$, (select v from ctx where k='dm1')), '3 báo giá');
select kt.dong_vai('duy@gara.vn');
select public.them_tep_kho('de_nghi_mua', (select v::bigint from ctx where k='dm1'), 'TK/kho/bg' || g || '.jpg', 'Báo giá ' || g) from generate_series(1,3) g;
select kt.dong_vai('long@gara.vn');
select public.duyet_de_nghi_mua((select v::bigint from ctx where k='dm1'), true);
select kt.ghi('Đủ 3 báo giá thì quản lý chung duyệt được', (select trang_thai from public.de_nghi_mua where id=(select v::bigint from ctx where k='dm1')) = 'da_duyet');

-- 015: duyệt ngoại lệ khi thiếu báo giá cạnh tranh; giám đốc tự duyệt phiếu mình lập
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'dm_nl', (public.lap_de_nghi_mua(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_guong'),'so_luong',1,'don_gia',5500000,'ty_le_vat',0.08)))))->>'id';
select public.them_tep_kho('de_nghi_mua', (select v::bigint from ctx where k='dm_nl'), 'TK/kho/nl1.jpg', 'Báo giá đại lý');
select kt.mong_loi('Kho không duyệt ngoại lệ', format($$select public.duyet_mua_ngoai_le(%s, 'gấp')$$, (select v from ctx where k='dm_nl')), 'không có quyền');
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('Duyệt thường khi thiếu báo giá: nhắc dùng Duyệt ngoại lệ', format($$select public.duyet_de_nghi_mua(%s, true)$$, (select v from ctx where k='dm_nl')), 'Duyệt ngoại lệ');
select kt.mong_loi('Duyệt ngoại lệ phải ghi lý do', format($$select public.duyet_mua_ngoai_le(%s, '  ')$$, (select v from ctx where k='dm_nl')), 'Ghi lý do');
select public.duyet_mua_ngoai_le((select v::bigint from ctx where k='dm_nl'), 'Gương chính hãng chỉ đại lý VinFast bán');
select kt.ghi('Quản lý chung duyệt ngoại lệ: đã duyệt, đánh dấu ngoại lệ kèm lý do và số báo giá',
  (select trang_thai = 'da_duyet' and ngoai_le and ly_do_ngoai_le like 'Gương chính hãng%(có 1/3 báo giá)' from public.v_de_nghi_mua where id=(select v::bigint from ctx where k='dm_nl')));
select kt.dong_vai('thuan@gara.vn');
insert into ctx select 'dm_gd', (public.lap_de_nghi_mua(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_guong'),'so_luong',1,'don_gia',100000,'ty_le_vat',0.08)))))->>'id';
select public.duyet_de_nghi_mua((select v::bigint from ctx where k='dm_gd'), true);
select kt.ghi('Giám đốc tự duyệt đề nghị mua do mình lập', (select trang_thai from public.de_nghi_mua where id=(select v::bigint from ctx where k='dm_gd')) = 'da_duyet');
select public.huy_de_nghi_mua((select v::bigint from ctx where k='dm_gd'));
select public.huy_de_nghi_mua((select v::bigint from ctx where k='dm_nl'));
select kt.dong_vai('long@gara.vn');

-- Hàng về: nhập theo đề nghị mua → xe hết chờ phụ tùng → xuất gương
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'pn3', (public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'de_nghi_mua_id',(select v::bigint from ctx where k='dm1'),'so_hoa_don','VF-123',
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_guong'),'so_luong',1,'don_gia',6000000,'ty_le_vat',0.08)))))->>'id';
select kt.ghi('Nhập theo đề nghị mua: đề nghị "đã nhập", xe hết chờ phụ tùng',
  (select trang_thai from public.de_nghi_mua where id=(select v::bigint from ctx where k='dm1')) = 'da_nhap'
  and not exists (select 1 from public.v_cho_phu_tung where ho_so_id=(select v::bigint from ctx where k='hs_kho')));
select public.xuat_kho_de_xuat((select v::bigint from ctx where k='dx1'));
select kt.ghi('Xuất nốt gương: đề xuất xong, giá vốn xe 9.288.000',
  (select trang_thai from public.de_xuat_vat_tu where id=(select v::bigint from ctx where k='dx1')) = 'da_xuat'
  and (select gia_von from public.v_gia_von_ho_so where ho_so_id=(select v::bigint from ctx where k='hs_kho')) = 9288000);
select kt.mong_loi('Không hủy phiếu nhập khi hàng đã xuất', format($$select public.huy_phieu_nhap(%s, 'nhầm')$$, (select v from ctx where k='pn1')), 'đã xuất');

-- Kế toán khớp hóa đơn → công nợ NCC
select kt.dong_vai('tien@gara.vn');
select public.khop_phieu_nhap((select v::bigint from ctx where k='pn1'), true);
select kt.mong_loi('Treo phiếu phải ghi chỗ lệch', format($$select public.khop_phieu_nhap(%s, false, '')$$, (select v from ctx where k='pn2')), 'Ghi chỗ lệch');
select public.khop_phieu_nhap((select v::bigint from ctx where k='pn2'), false, 'Hóa đơn ghi 1.250.000');
select kt.ghi('Công nợ NCC chỉ tính phiếu đã khớp; phiếu treo nằm ở "chờ khớp"',
  (select da_nhap = 2160000 and cho_khop = 1296000 from public.v_cong_no_ncc
   where ten = 'Vật tư sơn VTN' and chi_nhanh_id = 'TK'),
  (select da_nhap || ' / ' || cho_khop from public.v_cong_no_ncc where ten = 'Vật tư sơn VTN' and chi_nhanh_id = 'TK'));

-- Phụ tùng mua riêng cho xe: nhập rồi xuất ngay
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hang_den', public.luu_hang_kho('{"ma":"PT-DEN","ten":"Đèn hậu VF3","nhom":"Phụ tùng","dvt":"Cái"}')::text;
select public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'ho_so_id',(select v::bigint from ctx where k='hs_kho'),'xuat_cho_xe',true,
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_den'),'so_luong',1,'don_gia',1000000,'ty_le_vat',0.08))));
select kt.ghi('Mua riêng cho xe: tồn về 0, giá vốn xe cộng 1.080.000',
  (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_den')) = 0
  and (select gia_von from public.v_gia_von_ho_so where ho_so_id=(select v::bigint from ctx where k='hs_kho')) = 10368000);

-- Xuất dùng chung 1 lít, rồi kiểm kê sơn: sổ sách 1 lít, đếm 0,5 → chênh 50% phải có biên bản
insert into ctx select 'px_chung', (public.xuat_dung_chung(('{"ghi_chu":"Sơn dặm xưởng","dong":[{"hang_id":' || (select v from ctx where k='hang_son') || ',"so_luong":1}]}')::jsonb))->>'id';
insert into ctx select 'kk1', (public.tao_kiem_ke('{"pham_vi":"son_nham"}'))->>'id';
select kt.ghi('Kiểm kê sơn – nhám chỉ lấy nhóm Sơn, Nhám', (select count(*) from public.kiem_ke_dong where kiem_ke_id=(select v::bigint from ctx where k='kk1')) = 1);
select public.luu_dem_kiem_ke((select v::bigint from ctx where k='kk1'),
  (select jsonb_agg(jsonb_build_object('dong_id',id,'ton_thuc_te',0.5)) from public.kiem_ke_dong where kiem_ke_id=(select v::bigint from ctx where k='kk1')));
select kt.mong_loi('Chênh trên 5% phải ghi biên bản', format($$select public.chot_kiem_ke(%s)$$, (select v from ctx where k='kk1')), 'biên bản');
select public.chot_kiem_ke((select v::bigint from ctx where k='kk1'), 'Đổ vỡ 0,5 lít khi pha');
select kt.ghi('Chốt kiểm kê: tồn sơn còn 0,5 lít', (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_son')) = 0.5);
select public.huy_phieu_xuat((select v::bigint from ctx where k='px_chung'), 'Xuất nhầm');
select kt.ghi('Hủy phiếu xuất dùng chung: hàng về lại kho (1,5 lít)', (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_son')) = 1.5);
select kt.ghi('Thẻ kho cộng đúng tồn', (select sum(so_luong) from public.v_the_kho where hang_id=(select v::bigint from ctx where k='hang_son')) = 1.5);
select kt.dong_vai('codong@gara.vn');
select kt.ghi('Cổ đông không thấy kho', (select count(*) from public.v_ton_kho) = 0 and (select count(*) from public.phieu_nhap) = 0);

-- ---------------- 013: xuất Excel – chỉ giám đốc ----------------
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('Quản lý chung không xuất được file kho', 'select public.xuat_du_lieu_kho()', 'quyền');
select kt.mong_loi('Quản lý chung không xuất được file khách hàng', 'select public.xuat_du_lieu_khach()', 'quyền');
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('Kế toán không xuất được file khách hàng', 'select public.xuat_du_lieu_khach()', 'quyền');
select kt.dong_vai('thuan@gara.vn');
insert into ctx select 'xk', public.xuat_du_lieu_kho()::text;
select kt.ghi('Giám đốc xuất file kho: đủ mã, có giá trị tồn và đơn giá',
  jsonb_array_length((select v::jsonb from ctx where k='xk')->'hang') = (select count(*) from public.hang_kho where chi_nhanh_id='TK' and hoat_dong)
  and exists (select 1 from jsonb_array_elements((select v::jsonb from ctx where k='xk')->'hang') x where x->>'ma'='SON-TRANG01' and (x->>'ton')::numeric = 1.5 and (x->>'don_gia') is not null),
  (select v from ctx where k='xk'));
insert into ctx select 'xkh', public.xuat_du_lieu_khach()::text;
select kt.ghi('Giám đốc xuất file khách hàng: có danh sách xe và công nợ',
  jsonb_array_length((select v::jsonb from ctx where k='xkh')->'xe') > 0 and jsonb_typeof((select v::jsonb from ctx where k='xkh')->'cong_no') = 'array');
select kt.ghi('File khách hàng có đơn vị bảo hiểm của lần vào gần nhất',
  exists (select 1 from jsonb_array_elements((select v::jsonb from ctx where k='xkh')->'xe') x where coalesce(x->>'hang_bh','') <> ''),
  (select v::jsonb->'xe'->0 from ctx where k='xkh')::text);
select kt.ghi('Công nợ trong file khớp v_ho_so (xe đã giao còn nợ)',
  coalesce((select sum((x->>'con_no_khach')::numeric + (x->>'con_no_bh')::numeric) from jsonb_array_elements((select v::jsonb from ctx where k='xkh')->'cong_no') x), 0)
  = coalesce((select sum(con_no_khach + con_no_bh) from public.v_ho_so where not tu_excel and trang_thai in ('da_giao','da_gui_hs','dong')
              and (round(con_no_khach) <> 0 or round(con_no_bh) <> 0)), 0));
select kt.ghi('Mỗi lần xuất đều ghi nhật ký (2 lần)', (select count(*) from public.nhat_ky_xuat_file) = 2);
select kt.ghi('File Data khách hàng: mỗi lần vào xưởng 1 dòng',
  jsonb_array_length((select v::jsonb from ctx where k='xkh')->'data') >= (select count(*) from public.ho_so where trang_thai <> 'huy'));

-- ---------------- 017: giám đốc tạo tài khoản nhân viên, đặt lại mật khẩu ----------------
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('Quản lý chung không tạo được tài khoản', $$select public.tao_tai_khoan_nhan_vien('{"ho_ten":"A","ten_dang_nhap":"a.kho","mat_khau":"123456","vai_tro":["kho"]}')$$, 'quyền');
select kt.dong_vai('thuan@gara.vn');
select kt.mong_loi('Tên đăng nhập có dấu bị chặn', $$select public.tao_tai_khoan_nhan_vien('{"ho_ten":"Bảo","ten_dang_nhap":"bảo.kho","mat_khau":"123456","vai_tro":["kho"]}')$$, 'không dấu');
select kt.mong_loi('Mật khẩu ngắn bị chặn', $$select public.tao_tai_khoan_nhan_vien('{"ho_ten":"Bảo","ten_dang_nhap":"bao.kho","mat_khau":"123","vai_tro":["kho"]}')$$, '6 ký tự');
insert into ctx select 'tk_bao', public.tao_tai_khoan_nhan_vien('{"ho_ten":"Trần Văn Bảo","ten_dang_nhap":"Bao.Kho","mat_khau":"hs1234","vai_tro":["kho"],"chi_nhanh_id":"TK"}')::text;
select kt.dong_vai(null);
select kt.ghi('Tạo tài khoản: có đăng nhập nội bộ, mật khẩu mã hóa, đã cấp quyền, bắt đổi mật khẩu lần đầu',
  (select u.email = 'bao.kho@nv.autohoangson.com' and u.encrypted_password = extensions.crypt('hs1234', u.encrypted_password)
     and nv.ten_dang_nhap = 'bao.kho' and nv.vai_tro = '{kho}' and nv.phai_doi_mat_khau and nv.chi_nhanh_id = 'TK'
   from auth.users u join public.nhan_vien nv on nv.id = u.id where u.id = (select v::uuid from ctx where k='tk_bao'))
  and exists (select 1 from auth.identities where user_id = (select v::uuid from ctx where k='tk_bao') and provider = 'email'));
select kt.dong_vai('thuan@gara.vn');
select kt.mong_loi('Không trùng tên đăng nhập', $$select public.tao_tai_khoan_nhan_vien('{"ho_ten":"Bảo 2","ten_dang_nhap":"bao.kho","mat_khau":"123456","vai_tro":["kho"]}')$$, 'đã có người dùng');
select kt.dong_vai('bao.kho@nv.autohoangson.com');
select public.da_doi_mat_khau();
select kt.ghi('Nhân viên đổi mật khẩu xong thì hết bị bắt đổi', not (select phai_doi_mat_khau from public.nhan_vien where id = (select v::uuid from ctx where k='tk_bao')));
select kt.mong_loi('Nhân viên không đặt lại mật khẩu người khác', format($$select public.dat_lai_mat_khau('%s', 'abcdef')$$, (select v from ctx where k='tk_bao')), 'quyền');
select kt.dong_vai('thuan@gara.vn');
select public.dat_lai_mat_khau((select v::uuid from ctx where k='tk_bao'), 'moi999');
select kt.dong_vai(null);
select kt.ghi('Giám đốc đặt lại mật khẩu: mật khẩu mới dùng được, lại bắt đổi lần đầu',
  (select u.encrypted_password = extensions.crypt('moi999', u.encrypted_password) and nv.phai_doi_mat_khau
   from auth.users u join public.nhan_vien nv on nv.id = u.id where u.id = (select v::uuid from ctx where k='tk_bao')));
select kt.dong_vai('thuan@gara.vn');
select public.luu_nhan_vien((select v::uuid from ctx where k='tk_bao'), '{"ho_ten":"Trần Văn Bảo","chi_nhanh_id":"TK","vai_tro":["kho","cvdv"],"hoat_dong":true}');
select kt.ghi('Giám đốc đổi quyền tài khoản mới tạo', (select vai_tro from public.nhan_vien where id = (select v::uuid from ctx where k='tk_bao')) = '{kho,cvdv}');

-- ---------------- 014: nạp Data khách hàng (xóa hết rồi nạp lại) ----------------
select kt.dong_vai(null);
insert into app.nap_tam (phan, dong) values (1, $j$[
  {"bien_so":"51K-999.01","khach":"Khách nợ cũ","dien_thoai":"0911000001","hang_xe":"Kia","dong_xe":"Morning","mau":"Trắng",
   "ngay_vao":"2026-09-02","ngay_giao":"2026-09-05","nguon":"khach","tinh_trang":"02/09/2026: Trầy cản","gia_tri":3000000,"con_no_khach":1200000},
  {"bien_so":"51K99901","khach":"Khách nợ cũ","dien_thoai":"0911000001","ngay_vao":"2026-06-01","nguon":"bao_hiem","hang_bh":"tasco","gdv":"X"},
  {"bien_so":"51K-999.02","khach":"Khách BH nợ","dien_thoai":"","ngay_vao":"2026-09-10","ngay_giao":"2026-09-15","nguon":"bao_hiem",
   "hang_bh":"Hãng Lạ","con_no_bh":2500000},
  {"bien_so":"51K-999.03","khach":"Xe chưa vào lần nào","dien_thoai":"0911000003"}
]$j$::jsonb);
select kt.mong_loi('Xóa hết khi đã có phiếu thu gắn hồ sơ thì dừng, báo rõ', 'select app.nap_data_khach(true)', 'phân bổ phiếu thu');
insert into ctx select 'nap', app.nap_data_khach(false)::text;
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('Nạp: 3 xe mới, 3 hồ sơ, 2 hồ sơ còn nợ; hãng lạ báo cảnh báo',
  ((select v::jsonb from ctx where k='nap')->>'xe_moi')::int = 3 and ((select v::jsonb from ctx where k='nap')->>'ho_so')::int = 3
  and ((select v::jsonb from ctx where k='nap')->>'ho_so_con_no')::int = 2
  and (select v from ctx where k='nap') like '%Hãng Lạ%', (select v from ctx where k='nap'));
select kt.ghi('Nợ cũ khách 1.200.000: hồ sơ Đã giao xe, không tính doanh thu',
  (select con_no_khach = 1200000 and trang_thai = 'da_giao' and tu_excel from public.v_ho_so where bien_so = '51K99901' and con_no_khach > 0)
  and not exists (select 1 from public.v_doanh_thu where bien_so = '51K-999.01'));
select kt.ghi('Hãng BH không phân biệt hoa thường (tasco → Tasco); xe lấy thông tin lần vào mới nhất',
  (select hang_bh = 'Tasco' from public.v_ho_so where bien_so = '51K99901' and ngay_vao::date = '2026-06-01')
  and (select mau = 'Trắng' from public.xe where bien_so = '51K99901'));
select kt.ghi('Nợ cũ BH 2.500.000: Đã gửi hồ sơ BH, hiện trong công nợ',
  (select con_no_bh = 2500000 and trang_thai = 'da_gui_hs' from public.v_ho_so where bien_so = '51K99902'));
select kt.dong_vai('tien@gara.vn');
select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1200000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select id from public.ho_so where ma like 'TK-2609-51K99901%'),'so_tien',1200000))));
select kt.ghi('Thu đủ nợ cũ của khách → hồ sơ tự đóng', (select trang_thai from public.ho_so where ma like 'TK-2609-51K99901%') = 'dong');
select kt.dong_vai(null);
select kt.dong_vai('long@gara.vn');
select kt.ghi('Người khác không xem được nhật ký xuất file', (select count(*) from public.nhat_ky_xuat_file) = 0);
select kt.dong_vai(null);

-- ---------- 019: xóa dòng danh mục ----------
select kt.dong_vai('thuan@gara.vn');
insert into public.giam_dinh_vien (ten, hang_id) values ('GDV tạm', (select id from public.hang_bao_hiem order by id limit 1));
select public.xoa_danh_muc('giam_dinh_vien', (select id::text from public.giam_dinh_vien where ten = 'GDV tạm'));
select kt.ghi('019 Giám đốc xóa được GDV chưa dùng', not exists (select 1 from public.giam_dinh_vien where ten = 'GDV tạm'));
select kt.mong_loi('019 Không xóa được hãng BH đang có hồ sơ dùng',
  format('select public.xoa_danh_muc(%L, %L)', 'hang_bao_hiem', (select hang_bh_id::text from public.ho_so where hang_bh_id is not null limit 1)), 'đang được dùng');
select kt.mong_loi('019 Không xóa cài đặt', 'select public.xoa_danh_muc(''cai_dat'', ''so_gio_kcs'')', 'Không xóa được');
select kt.dong_vai(null);
select kt.dong_vai('duy@gara.vn');
select kt.mong_loi('019 CVDV không được xóa danh mục',
  format('select public.xoa_danh_muc(%L, %L)', 'hang_xe', (select id::text from public.hang_xe limit 1)), 'quyền');
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
select kt.ghi('021 Kế toán gọi được bảng việc xưởng', jsonb_typeof(public.bang_viec_to()) = 'array');
select kt.dong_vai(null);

-- ---------- 024: khách trả dư ----------
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('024 Thu vượt nợ khách không cờ trả dư bị chặn', format($$select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1000))))$$, (select v from ctx where k='hs1')), 'vượt');
select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1000,'cho_tra_du',true,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs1'),'so_tien',1000))));
select kt.ghi('024 Có cờ trả dư: nợ khách âm 1.000 (khách trả dư)', (select con_no_khach from public.tien_ho_so((select v::bigint from ctx where k='hs1'))) = -1000);
select kt.ghi('024 Có mục thu Tiền bo của khách', exists (select 1 from public.muc_thu_chi where ten = 'Tiền bo của khách' and tinh_chat = 'thu_khac'));
select kt.dong_vai(null);

-- ---------- 025 + 026: kết quả kinh doanh, kỳ chi phí, chốt tháng ----------
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('025 Kết quả kinh doanh có tháng hiện tại, doanh thu = tổng v_doanh_thu',
  (select doanh_thu from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  = (select coalesce(sum(so_tien),0) from public.v_doanh_thu where ngay >= date_trunc('month', current_date)::date),
  (select doanh_thu::text || ' / ' || gia_von_xe::text || ' / ' || lai_truoc_thue::text from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date));
select kt.ghi('025 Lãi gộp = doanh thu − giá vốn', (select bool_and(lai_gop = doanh_thu - gia_von_xe - gia_von_dung_chung - chi_gia_von) from public.ket_qua_kinh_doanh()));
select kt.ghi('026 Có đủ các tháng liên tục đến tháng hiện tại, tháng hiện tại = Đang mở',
  (select trang_thai from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date) = 'dang_mo'
  and (select count(*) from public.ket_qua_kinh_doanh()) = (select (extract(year from age(date_trunc('month', current_date), min(thang))) * 12 + extract(month from age(date_trunc('month', current_date), min(thang))) + 1) from public.ket_qua_kinh_doanh()));
select kt.mong_loi('025 Không chốt được tháng hiện tại', 'select public.chot_thang(current_date)', 'đã qua');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '1 month')::date, 'Mở lại tháng đã khóa ở bài thử trước');
select kt.ghi('025 Mở lại tháng đã chốt (giám đốc, có lý do)', (select count(*) from public.chot_thang) = 0);
select kt.ghi('026 Tháng chưa có gì thì chưa có trong báo cáo', not exists (select 1 from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date));
select public.nhap_bang_luong((date_trunc('month', current_date) - interval '1 month')::date, 30000000);
select kt.ghi('026 Nhập lương tháng trước → tháng trước = Chờ chốt, lương đã nhập, còn thiếu chi phí định kỳ (Điện...)',
  (select trang_thai = 'cho_chot' and luong_da_nhap and 'Điện' = any(thieu_dinh_ky) from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date),
  (select array_to_string(thieu_dinh_ky, ', ') from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date));
select kt.mong_loi('026 Chốt khi còn thiếu → cảnh báo CANH_BAO', format('select public.chot_thang(%L)', (date_trunc('month', current_date) - interval '1 month')::date), 'CANH_BAO');
select kt.dong_vai(null);
-- Tiền điện tháng trước, lập đề nghị chi trong tháng này với kỳ chi phí = tháng trước
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'dn_dien', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Điện'),
  'so_tien',1500000,'noi_dung','Tiền điện','ky_chi_phi',(date_trunc('month', current_date) - interval '1 month')::date))::text;
select kt.ghi('026 Đề nghị chi ghi rõ kỳ vào nội dung', (select noi_dung like '%chi phí tháng %' from public.de_nghi_chi where id = (select v::bigint from ctx where k='dn_dien')),
  (select noi_dung from public.de_nghi_chi where id = (select v::bigint from ctx where k='dn_dien')));
select kt.mong_loi('026 Kỳ chi phí sau tháng hiện tại bị chặn', format($$select public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Điện'),'so_tien',1,'noi_dung','x','ky_chi_phi',%L))$$, (date_trunc('month', current_date) + interval '1 month')::date), 'sau tháng');
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('026 Có đề nghị Điện → hết thiếu Điện, kỳ có 1 đề nghị chưa chi',
  (select not ('Điện' = any(thieu_dinh_ky)) and de_nghi_cho_chi = 1 from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date));
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_dien'), true);
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
select public.chi_tien((select v::bigint from ctx where k='dn_dien'), (select id from public.tai_khoan_quy where ten='Tiền mặt'));
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('026 Chi tiền tháng này nhưng tính vào chi phí cố định tháng trước',
  (select chi_co_dinh from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date) = 1500000
  and (select ky_chi_phi from public.phieu_thu_chi where de_nghi_chi_id = (select v::bigint from ctx where k='dn_dien')) = (date_trunc('month', current_date) - interval '1 month')::date);
select kt.ghi('025 Chốt tháng trước (bỏ qua cảnh báo), có số liệu lương', (select (public.chot_thang((date_trunc('month', current_date) - interval '1 month')::date, true)->>'luong')::numeric) = 30000000);
select kt.mong_loi('025 Tháng đã chốt không ghi được phiếu', format($$select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'muc_id',(select id from public.muc_thu_chi where ten='Thu khác'),'so_tien',1000,'ngay',%L))$$, (date_trunc('month', current_date) - interval '1 day')::date), 'đã chốt');
select kt.mong_loi('026 Kỳ chi phí đã chốt không lập đề nghị được', format($$select public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Nước'),'so_tien',1,'noi_dung','x','ky_chi_phi',%L))$$, (date_trunc('month', current_date) - interval '1 month')::date), 'đã chốt');
select kt.ghi('025 Cổ đông xem được tháng đã chốt', (select count(*) from public.bao_cao_co_dong()) = 1);
select kt.mong_loi('025 Mở lại tháng phải có lý do', 'select public.mo_lai_thang(current_date - 31, null)', 'lý do');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '1 month')::date, 'Thử');
select kt.ghi('025 Mở lại xong hết chốt', (select count(*) from public.chot_thang) = 0);
select kt.dong_vai(null);
select kt.dong_vai('duy@gara.vn');
select kt.mong_loi('025 CVDV không xem được kết quả kinh doanh', 'select * from public.ket_qua_kinh_doanh()', 'quyền');
select kt.dong_vai(null);

-- ---------- 027: nợ nội bộ & cá nhân, chi hộ ----------
select kt.dong_vai(null);
insert into public.don_vi_lien_quan (ten, loai, so_du_dau_ky, ngay_dau_ky) values ('Anh Thuận (cá nhân)', 'ca_nhan', -10000000, current_date - 30), ('Cổ đông A', 'ca_nhan', 0, null);
insert into ctx values ('dv_thuan', (select id from public.don_vi_lien_quan where ten='Anh Thuận (cá nhân)')::text), ('dv_codong', (select id from public.don_vi_lien_quan where ten='Cổ đông A')::text);
insert into ctx values ('quy_truoc', (select so_du::text from public.v_so_du_quy where ten='Tiền mặt'));
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('027 Đầu kỳ: công ty nợ giám đốc 10 triệu', (select con_lai from public.v_cong_no_noi_bo where id = (select v::bigint from ctx where k='dv_thuan')) = -10000000);
select kt.ghi('027 Có đủ 4 mục thu chi nội bộ / cá nhân, mục hệ thống muon_ca_nhan', (select count(*) from public.muc_thu_chi where ten in ('Công ty mượn tiền giám đốc / cổ đông','Cổ đông / cá nhân trả tiền mượn','Cho cổ đông / cá nhân mượn','Trả tiền mượn giám đốc / cổ đông')) = 4
  and (select he_thong from public.muc_thu_chi where ten='Công ty mượn tiền giám đốc / cổ đông') = 'muon_ca_nhan');
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
-- Giám đốc cho công ty mượn thêm 5 triệu (phiếu thu) → công ty nợ 15 triệu
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt'),'muc_id',(select id from public.muc_thu_chi where ten='Công ty mượn tiền giám đốc / cổ đông'),
  'so_tien',5000000,'noi_dung','Mượn thêm','don_vi_lien_quan_id',(select v::bigint from ctx where k='dv_thuan')));
select kt.ghi('027 Phiếu thu mượn thêm → công ty nợ 15 triệu', (select con_lai from public.v_cong_no_noi_bo where id = (select v::bigint from ctx where k='dv_thuan')) = -15000000);
-- Cổ đông mượn 3 triệu: đề nghị chi (trả nội bộ) → duyệt → chi
insert into ctx select 'dn_codong', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Cho cổ đông / cá nhân mượn'),'so_tien',3000000,'noi_dung','Cổ đông A mượn','don_vi_lien_quan_id',(select v::bigint from ctx where k='dv_codong')))::text;
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_codong'), true);
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('027 Khoản cho mượn không chi hộ được', format('select public.chi_tien(%s, (select id from public.tai_khoan_quy where ten=''Tiền mặt''), current_date, %s)', (select v from ctx where k='dn_codong'), (select v from ctx where k='dv_thuan')), 'không chi hộ');
select public.chi_tien((select v::bigint from ctx where k='dn_codong'), (select id from public.tai_khoan_quy where ten='Tiền mặt'));
select kt.ghi('027 Cổ đông mượn 3 triệu → cổ đông nợ công ty 3 triệu', (select con_lai from public.v_cong_no_noi_bo where id = (select v::bigint from ctx where k='dv_codong')) = 3000000);
-- Chi hộ: giám đốc trả tiền điện 2 triệu bằng tiền túi → phiếu chi + phiếu thu đối ứng, quỹ không đổi, chi phí vẫn tính, công ty nợ thêm
insert into ctx select 'dn_dien2', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Điện'),'so_tien',2000000,'noi_dung','Tiền điện tháng này'))::text;
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_dien2'), true);
insert into ctx values ('quy_truoc_chi_ho', (select so_du::text from public.v_so_du_quy where ten='Tiền mặt'));
insert into ctx values ('cp_truoc', (select chi_co_dinh::text from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date));
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'pc_chi_ho', public.chi_tien((select v::bigint from ctx where k='dn_dien2'), (select id from public.tai_khoan_quy where ten='Tiền mặt'), current_date, (select v::bigint from ctx where k='dv_thuan'))::text;
select kt.ghi('027 Chi hộ: có phiếu thu đối ứng cùng số tiền, gắn người chi hộ',
  (select count(*) from public.phieu_thu_chi t where t.phieu_doi_ung_id = (select v::bigint from ctx where k='pc_chi_ho') and t.loai='thu' and t.so_tien=2000000 and t.don_vi_lien_quan_id = (select v::bigint from ctx where k='dv_thuan') and t.trang_thai='hieu_luc') = 1
  and (select chi_ho_boi from public.phieu_thu_chi where id = (select v::bigint from ctx where k='pc_chi_ho')) = (select v::bigint from ctx where k='dv_thuan'));
select kt.ghi('027 Chi hộ: số dư quỹ không đổi', (select so_du::text from public.v_so_du_quy where ten='Tiền mặt') = (select v from ctx where k='quy_truoc_chi_ho'));
select kt.ghi('027 Chi hộ: công ty nợ giám đốc thêm 2 triệu = 17 triệu', (select con_lai from public.v_cong_no_noi_bo where id = (select v::bigint from ctx where k='dv_thuan')) = -17000000);
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('027 Chi hộ: chi phí cố định tháng này vẫn tính thêm 2 triệu',
  (select chi_co_dinh from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date) = (select v::numeric from ctx where k='cp_truoc') + 2000000);
select kt.ghi('027 Tổng phải thu / phải trả nội bộ', (select sum(case when con_lai > 0 then con_lai else 0 end) from public.v_cong_no_noi_bo) = 3000000
  and (select sum(case when con_lai < 0 then -con_lai else 0 end) from public.v_cong_no_noi_bo) = 17000000);
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
-- Hủy phiếu thu đối ứng → phiếu chi hủy theo, đề nghị về đã duyệt, nợ về 15 triệu
select public.huy_phieu((select id from public.phieu_thu_chi where phieu_doi_ung_id = (select v::bigint from ctx where k='pc_chi_ho') and loai='thu'), 'Ghi nhầm');
select kt.ghi('027 Hủy một phiếu chi hộ → phiếu kia hủy theo, đề nghị về Đã duyệt, nợ về 15 triệu',
  (select trang_thai from public.phieu_thu_chi where id = (select v::bigint from ctx where k='pc_chi_ho')) = 'huy'
  and (select trang_thai from public.de_nghi_chi where id = (select v::bigint from ctx where k='dn_dien2')) = 'da_duyet'
  and (select con_lai from public.v_cong_no_noi_bo where id = (select v::bigint from ctx where k='dv_thuan')) = -15000000);
select kt.dong_vai(null);
select kt.dong_vai('duy@gara.vn');
select kt.ghi('027 CVDV không thấy công nợ nội bộ', (select count(*) from public.v_cong_no_noi_bo) = 0);
select kt.dong_vai(null);
\o
\echo '======== KẾT QUẢ ========'
select stt, case when dat then 'ĐẠT ' else 'LỖI ' end as kq, ten, left(coalesce(chi_tiet,''), 140) as chi_tiet from kt.ket_qua order by stt;
select count(*) filter (where dat) as dat, count(*) filter (where not dat) as loi from kt.ket_qua;
