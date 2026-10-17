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
language sql security definer as $$ insert into kt.ket_qua (ten, dat, chi_tiet) values (p_ten, coalesce(p_dat, false), p_ct) $$;
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

-- 036: giám định viên không bắt buộc lúc tiếp nhận (hãng cử sau); bắt buộc trước khi nhập kết quả duyệt giá
insert into ctx select 'hs_nogdv', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-333.44','ten_khach','Khách chờ GDV','dien_thoai','0909000334','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'han_bao_hiem','2027-03-01',
  'tinh_trang_xe','Móp cửa','tu_van','Không')))->>'id';
select kt.ghi('036 Xe BH chưa có GDV vẫn tiếp nhận được; Việc cần xử lý báo thiếu GDV',
  (select gdv_id is null and trang_thai = 'tiep_nhan' from public.ho_so where id=(select v::bigint from ctx where k='hs_nogdv'))
  and exists (select 1 from public.v_canh_bao where loai='thieu_gdv' and ho_so_id=(select v::bigint from ctx where k='hs_nogdv')));
select public.lap_bao_gia((select v::bigint from ctx where k='hs_nogdv'), '[{"ten":"Gò cửa","nhom":"dong","gia_bao":1000000}]', 0.08);
select kt.mong_loi('036 Chưa có GDV thì chưa nhập kết quả duyệt giá được', format($$select public.duyet_gia_chia(%s, current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',1000000)) from public.hang_muc where ho_so_id=%s), null)$$,
  (select v from ctx where k='hs_nogdv'), (select v from ctx where k='hs_nogdv')), 'giám định viên');
select public.sua_thong_tin_ho_so((select v::bigint from ctx where k='hs_nogdv'), jsonb_build_object('gdv_id',(select id from public.giam_dinh_vien where ten='Hảo')));
select public.duyet_gia((select v::bigint from ctx where k='hs_nogdv'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',1000000)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_nogdv')));
select kt.ghi('036 Ghi GDV ở Sửa thông tin → duyệt giá được, hết cảnh báo thiếu GDV',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_nogdv')) = 'da_duyet'
  and not exists (select 1 from public.v_canh_bao where loai='thieu_gdv' and ho_so_id=(select v::bigint from ctx where k='hs_nogdv')));

select kt.mong_loi('GDV chờ thêm phải ghi tên', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50H92361','ten_khach','Anh Liêm','dien_thoai','0567248565','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'han_bao_hiem','2027-03-01',
  'gdv_id',(select id from public.giam_dinh_vien where la_cho_them),
  'tinh_trang_xe','Móp cửa','tu_van','Không'))$$, 'ghi tên giám định viên');

insert into ctx select 'hs1', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','50h - 923.61','ten_khach','Anh Liêm','dien_thoai','0567 248 565','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'mau','Trắng','nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'han_bao_hiem','2027-03-01','han_bh_than_vo','2027-05-20',
  'tinh_trang_xe','Móp cửa trước trái','tu_van','Bảo dưỡng 20.000 km','so_km',45230)))->>'id';
select kt.ghi('031 Lưu số km (ODO) khi tiếp nhận', (select so_km from public.ho_so where id = (select v::bigint from ctx where k='hs1')) = 45230);
select kt.mong_loi('031 Số km quá lớn bị chặn', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51A-111.11','ten_khach','Khách Thử','dien_thoai','0901111111','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','khach','tinh_trang_xe','Thay dầu','tu_van','Không','so_km','123456789'))$$, 'Số km');
select kt.mong_loi('035 Tiếp nhận (giao diện mới) thiếu số km bị chặn', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51A-111.11','ten_khach','Khách Thử','dien_thoai','0901111111','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','khach','tinh_trang_xe','Thay dầu','tu_van','Không','bat_buoc_km',true))$$, 'số km (ODD)');
select kt.mong_loi('031 Thiếu yêu cầu khách hàng bị chặn', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51A-111.11','ten_khach','Khách Thử','dien_thoai','0901111111','dong_xe_id',(select id from public.dong_xe where ten='VF6 Plus'),
  'nguon_tt','khach','tinh_trang_xe','','tu_van','Không'))$$, 'yêu cầu của khách hàng');
select public.sua_thong_tin_ho_so((select v::bigint from ctx where k='hs1'), '{"so_km": 45320}');
select public.sua_thong_tin_ho_so((select v::bigint from ctx where k='hs1'), '{"mau":"Trắng"}');
select kt.ghi('031 Sửa số km ở Sửa thông tin; không gửi so_km thì giữ nguyên', (select so_km from public.ho_so where id = (select v::bigint from ctx where k='hs1')) = 45320);
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
select public.them_tep((select v::bigint from ctx where k='hs1'), 'tiep_nhan', 'anh', 'TK/' || (select ma from public.ho_so where id=(select v::bigint from ctx where k='hs1')) || '/tiep_nhan-nhan-xe-1.jpg');

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
select kt.mong_loi('047 CVDV được ký KCS (qua kiểm quyền, chỉ còn thiếu ảnh sau sửa)', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs1')), 'Chưa có ảnh sau sửa');
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('KCS đạt phải có ảnh sau sửa', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs1')), 'ảnh sau sửa');
select public.kcs((select v::bigint from ctx where k='hs1'), false, 'Sơn chảy cửa trái', array[(select v::bigint from ctx where k='dong_ds1')]);
select kt.ghi('KCS chưa đạt → về đang sửa', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs1')) = 'dang_sua');
select public.bao_xong_hang_muc((select v::bigint from ctx where k='dong_ds1'));
select public.them_tep((select v::bigint from ctx where k='hs1'), 'kcs', 'anh', 'TK/' || (select ma from public.ho_so where id=(select v::bigint from ctx where k='hs1')) || '/kcs-sau-sua-1.jpg');
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
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1500000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1500000))))$$, (select v from ctx where k='hs1')), 'vượt số khách còn nợ');
select kt.mong_loi('TK cá nhân đã khóa không ghi được', format($$select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten like 'VCB%%'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1000000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1000000))))$$, (select v from ctx where k='hs1')), 'đã khóa');
select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
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
select kt.mong_loi('043 Chia tiền bảo hiểm Tasco vào xe không phải của Tasco bị chặn', format($$select public.phan_bo_them(%s, jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1700000)))$$,
  (select v from ctx where k='pt_bh'), (select v from ctx where k='hs2')), 'không chia tiền bảo hiểm này');
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
select kt.mong_loi('Chưa duyệt thì kế toán chưa chi', format($$select public.chi_tien(%s, (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'))$$,
  (select v from ctx where k='dn1')), 'chưa được duyệt');
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn1'), true);
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn2'), true);
select kt.dong_vai('tien@gara.vn');
select public.chi_tien((select v::bigint from ctx where k='dn1'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.ghi('Đề nghị đã chi', (select trang_thai from public.de_nghi_chi where id=(select v::bigint from ctx where k='dn1')) = 'da_chi');
select kt.ghi('Số dư tiền mặt = 1.000.000 − 2.500.000',
  (select so_du from public.v_so_du_quy where ten='Tiền mặt' and chi_nhanh_id='TK') = -1500000, (select so_du::text from public.v_so_du_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));

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
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='TK công ty (331 331 331 68)'),'tai_khoan_den_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'so_tien',5000000))$$, 'đã chốt sổ');
select public.lap_phieu_chuyen(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='TK công ty (331 331 331 68)'),'tai_khoan_den_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'so_tien',5000000));
select kt.ghi('Chuyển quỹ cộng vào tiền mặt', (select so_du from public.v_so_du_quy where ten='Tiền mặt' and chi_nhanh_id='TK') = 3500000);

select kt.dong_vai('han@gara.vn');
insert into ctx select 'dvn', public.ghi_dich_vu_nhanh('{"bien_so":"51b70458","dich_vu":"Rửa xe","nguoi_lam":"Quỳnh","so_tien":80000}')::text;
-- 032: dịch vụ nhanh gắn xe – khách, số km bắt buộc (giao diện mới gửi bat_buoc_km)
select kt.mong_loi('032 Dịch vụ nhanh thiếu số km bị chặn', $$select public.ghi_dich_vu_nhanh('{"bien_so":"50H92361","dich_vu":"Rửa xe","so_tien":80000,"bat_buoc_km":true}')$$, 'số km');
select kt.ghi('032 Trưởng nhóm tra xe cũ theo đuôi biển số: có khách, số km lần trước (hồ sơ 45.320)',
  (select (x->>'ten_khach') = 'Anh Liêm' and (x->'km_truoc'->>'so')::int = 45320 and (x->'lan_cuoi'->>'loai') = 'ho_so'
   from jsonb_array_elements(public.tra_cuu_xe_nhanh('92361')) x where x->>'bien_so' = '50H-923.61'));
insert into ctx select 'dvn2', public.ghi_dich_vu_nhanh('{"bien_so":"50H-923.61","dich_vu":"Thay bóng đèn","so_tien":150000,"so_km":46100,"to_id":"DT","bat_buoc_km":true}')::text;
select kt.dong_vai(null);
select kt.ghi('032 Dịch vụ nhanh xe cũ gắn đúng xe – khách, lưu số km',
  (select d.xe_id = h.xe_id and d.khach_hang_id = h.khach_hang_id and d.so_km = 46100
   from public.dich_vu_nhanh d, public.ho_so h where d.id = (select v::bigint from ctx where k='dvn2') and h.id = (select v::bigint from ctx where k='hs1')));
select kt.dong_vai('han@gara.vn');
select kt.ghi('032 Tra lại: số km lần trước lấy lượt dịch vụ nhanh mới nhất',
  (select (x->'km_truoc'->>'so')::int = 46100 and (x->'lan_cuoi'->>'loai') = 'dich_vu_nhanh' from jsonb_array_elements(public.tra_cuu_xe_nhanh('50H92361')) x limit 1));
insert into ctx select 'dvn3', public.ghi_dich_vu_nhanh('{"bien_so":"59C-123.45","ten_khach":"Chị Hoa","dien_thoai":"0909 555 666","dich_vu":"Vá lốp","so_tien":50000,"so_km":12000,"to_id":"DT","bat_buoc_km":true}')::text;
select kt.dong_vai(null);
select kt.ghi('032 Xe mới + SĐT mới: tự tạo xe và khách, tra bằng SĐT ra được',
  (select x.bien_so = '59C12345' and k.ten = 'Chị Hoa' and k.dien_thoai = '0909555666' and x.khach_hang_id = k.id
   from public.dich_vu_nhanh d join public.xe x on x.id = d.xe_id join public.khach_hang k on k.id = d.khach_hang_id where d.id = (select v::bigint from ctx where k='dvn3'))
  and (select count(*) from public.xe where bien_so = '59C12345') = 1);
select kt.dong_vai('han@gara.vn');
select kt.ghi('041 Trưởng nhóm không tra được xe theo SĐT khách (không lộ SĐT)', jsonb_array_length(public.tra_cuu_xe_nhanh('0909555')) = 0);
select kt.ghi('041 Trưởng nhóm tra theo biển số: thấy tên khách, không thấy SĐT',
  (select x->>'ten_khach' = 'Chị Hoa' and x->>'dien_thoai' is null from jsonb_array_elements(public.tra_cuu_xe_nhanh('59C12345')) x));
select kt.dong_vai('duy@gara.vn');
select kt.ghi('032 Tra bằng SĐT ra xe mới tạo (nhân viên văn phòng)', jsonb_array_length(public.tra_cuu_xe_nhanh('0909555')) = 1);
select kt.dong_vai('han@gara.vn');
insert into ctx select 'dvn4', public.ghi_dich_vu_nhanh('{"bien_so":"59C-123.45","dich_vu":"Thay bóng đèn","so_tien":120000,"so_km":12100,"to_id":"DMG","bat_buoc_km":true}')::text;
select kt.mong_loi('034 Dịch vụ nhanh phải chọn tổ (giao diện mới)', $$select public.ghi_dich_vu_nhanh('{"dich_vu":"Rửa xe","so_tien":50000,"so_km":1,"bat_buoc_km":true}')$$, 'Chọn tổ');
select kt.mong_loi('034 Chỉ tổ ĐMG hoặc Detailing', $$select public.ghi_dich_vu_nhanh('{"dich_vu":"Rửa xe","so_tien":50000,"so_km":1,"to_id":"DS"}')$$, 'chỉ do tổ');
select kt.dong_vai(null);
select kt.ghi('034 Tổ làm ghi tên tổ; doanh thu dịch vụ nhanh tính vào tổ ĐMG', (select nguoi_lam = 'Điện – máy – gầm' and to_id = 'DMG' from public.dich_vu_nhanh where id = (select v::bigint from ctx where k='dvn4'))
  and exists (select 1 from public.v_doanh_thu where nguon = 'dich_vu_nhanh' and nhom = 'dmg' and so_tien = 120000)
  and exists (select 1 from public.v_doanh_thu where nguon = 'dich_vu_nhanh' and nhom = 'detailing' and so_tien = 80000));
select kt.dong_vai('han@gara.vn');
select kt.mong_loi('032 SĐT sai bị chặn', $$select public.ghi_dich_vu_nhanh('{"dien_thoai":"12345","dich_vu":"Rửa xe","so_tien":50000,"so_km":1}')$$, '10 số');
select kt.dong_vai('tien@gara.vn');
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'muc_id',(select id from public.muc_thu_chi where ten='Thu dịch vụ nhanh'),'so_tien',80000,
  'phan_bo',jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id',(select v::bigint from ctx where k='dvn'),'so_tien',80000))));
select kt.ghi('Dịch vụ nhanh đã thu', (select da_thu from public.v_dich_vu_nhanh where id=(select v::bigint from ctx where k='dvn')) = 80000);
select kt.ghi('Doanh thu hôm nay có dịch vụ nhanh', exists (select 1 from public.v_doanh_thu where nguon='dich_vu_nhanh' and so_tien=80000));

select kt.dong_vai(null);
insert into ctx select 'so_hs', (select count(*) from public.ho_so where chi_nhanh_id = 'TK')::text;
insert into ctx select 'so_phieu', (select count(*) from public.phieu_thu_chi where chi_nhanh_id = 'TK')::text;
select kt.dong_vai('codong@gara.vn');
select kt.ghi('030 Cổ đông xem được mọi hồ sơ, tiền hồ sơ (v_ho_so)', (select count(*) from public.ho_so) = (select v::int from ctx where k='so_hs')
  and (select count(*) from public.v_ho_so) > 0 and (select count(*) from public.v_ho_so where phai_thu_khach is not null) > 0);
select kt.ghi('030 Cổ đông xem được phiếu thu chi, sổ quỹ', (select count(*) from public.v_phieu_thu_chi) = (select v::int from ctx where k='so_phieu')
  and (select v::int from ctx where k='so_phieu') > 0 and (select count(*) from public.v_so_du_quy) > 0);
select kt.ghi('030 Cổ đông xem được dịch vụ nhanh, khách hàng, xe', (select count(*) from public.v_dich_vu_nhanh) > 0
  and (select count(*) from public.khach_hang) > 0 and (select count(*) from public.xe) > 0);
select kt.mong_loi('Cổ đông không tiếp nhận xe được', $$select public.tiep_nhan_xe('{}')$$, 'không có quyền');
select kt.mong_loi('030 Cổ đông không lập đề nghị chi được', $$select public.lap_de_nghi_chi('{"so_tien":1000,"noi_dung":"thử"}')$$, 'không có quyền');
select kt.mong_loi('030 Cổ đông không ghi dịch vụ nhanh được', $$select public.ghi_dich_vu_nhanh('{"dich_vu":"Rửa xe","so_tien":50000}')$$, 'không có quyền');
select kt.mong_loi('030 Cổ đông không sửa danh mục được (thêm hãng xe)', $$insert into public.hang_xe (ten) values ('Thử cổ đông')$$, 'row-level security');
select kt.mong_loi('030 Cổ đông không giao việc được', format('select public.giao_viec(%s, %L::uuid)', (select min(id) from public.ho_so), (select id from public.nhan_vien where email='duy@gara.vn')), 'không có quyền');

select kt.dong_vai('duy@gara.vn');
select public.huy_ho_so((select v::bigint from ctx where k='hs3'), 'Khách không sửa');
select kt.ghi('Hủy hồ sơ', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs3')) = 'huy');
select kt.ghi('Biển số hiển thị đúng', public.bien_so_hien_thi('50H92361') = '50H-923.61' and public.bien_so_hien_thi('51D1234') = '51D-1234' and public.bien_so_hien_thi('59X112345') = '59X1-123.45', public.bien_so_hien_thi('50H92361'));
select kt.ghi('Duy thấy cảnh báo', true, (select string_agg(loai || ': ' || noi_dung, ' | ') from public.v_canh_bao));

select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('Kiểm quỹ lệch phải ghi lý do', $$select public.ghi_kiem_quy((select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'), 3400000)$$, 'Lệch');
select kt.ghi('Kiểm quỹ khớp', (public.ghi_kiem_quy((select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'), 3580000)->>'chenh_lech')::numeric = 0);
-- 036: kế toán ghi dịch vụ nhanh thu tiền ngay → phiếu thu gắn lượt dịch vụ; trưởng nhóm không thu ngay được
insert into ctx select 'dvn5', public.ghi_dich_vu_nhanh(jsonb_build_object('bien_so','59C-123.45','dich_vu','Rửa xe','so_tien',70000,'so_km',12200,'to_id','DT','bat_buoc_km',true,
  'thu_ngay',true,'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK')))::text;
select kt.ghi('036 Dịch vụ nhanh thu tiền ngay: đã thu đủ, phiếu thu mục Thu dịch vụ nhanh, tiền mặt tăng 70.000',
  (select da_thu from public.v_dich_vu_nhanh where id=(select v::bigint from ctx where k='dvn5')) = 70000
  and exists (select 1 from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id join public.muc_thu_chi m on m.id = p.muc_id
              where pb.dich_vu_nhanh_id = (select v::bigint from ctx where k='dvn5') and m.tinh_chat = 'thu_dich_vu_nhanh' and p.trang_thai = 'hieu_luc')
  and (select so_du from public.v_so_du_quy where ten='Tiền mặt' and chi_nhanh_id='TK') = 3650000);
select kt.dong_vai('han@gara.vn');
select kt.mong_loi('036 Trưởng nhóm không thu tiền ngay được (kế toán thu ở Thu chi)', $$select public.ghi_dich_vu_nhanh('{"dich_vu":"Rửa xe","so_tien":50000,"so_km":1,"to_id":"DT","thu_ngay":true}')$$, 'kế toán');
select kt.dong_vai('tien@gara.vn');
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
-- 036: chia lại công nợ sau duyệt; thu tiền & giao xe một lần; hồ sơ bảo hành
-- ---------------------------------------------------------------------
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'chia_b', public.sua_chia_cong_no((select v::bigint from ctx where k='hs_b'), 216000)::text;
select kt.ghi('036 Sửa chia công nợ sau duyệt: khách chi trả 216.000 → BH 1.800.000, khách 216.000',
  ((select v from ctx where k='chia_b')::jsonb->>'bao_hiem')::numeric = 1800000
  and (select con_no_khach = 216000 and con_no_bh = 1800000 from public.tien_ho_so((select v::bigint from ctx where k='hs_b'))),
  (select v from ctx where k='chia_b'));
select kt.mong_loi('036 Thu & giao: thu ít hơn nợ mà chưa duyệt giao còn nợ thì chặn', format($$select public.thu_tien_giao_xe(%s, jsonb_build_object('so_tien',100000,'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK')))$$,
  (select v from ctx where k='hs_b')), 'còn nợ');
select kt.ghi('036 Giao lỗi thì phiếu thu cũng không ghi (cùng một giao dịch)',
  not exists (select 1 from public.phan_bo pb join public.phieu_thu_chi p on p.id=pb.phieu_id where pb.ho_so_id=(select v::bigint from ctx where k='hs_b') and p.trang_thai='hieu_luc')
  and (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b')) = 'dat_kcs');
select kt.mong_loi('036 Thu & giao: thu nhiều hơn nợ bị chặn, nhắc lập ở Thu chi', format($$select public.thu_tien_giao_xe(%s, jsonb_build_object('so_tien',300000,'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK')))$$,
  (select v from ctx where k='hs_b')), 'nhiều hơn số còn nợ');
insert into ctx select 'tg_b', public.thu_tien_giao_xe((select v::bigint from ctx where k='hs_b'), jsonb_build_object('so_tien',216000,'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'so_hd_bao_hiem','HD0002','khau_tru_giam_tru',999))::text;
select kt.ghi('036 Thu đủ & giao xe một lần: đã giao, khách hết nợ, có phiếu thu, số HĐ lưu, khấu trừ không đổi theo giao xe',
  (select trang_thai = 'da_giao' and so_hd_bao_hiem = 'HD0002' and khau_tru_giam_tru = 216000 from public.ho_so where id=(select v::bigint from ctx where k='hs_b'))
  and ((select v from ctx where k='tg_b')::jsonb->>'con_no_khach')::numeric = 0 and ((select v from ctx where k='tg_b')::jsonb->>'phieu_id') is not null,
  (select v from ctx where k='tg_b'));
select kt.dong_vai('han@gara.vn');
select kt.mong_loi('036 Trưởng nhóm không thu & giao xe được', format($$select public.thu_tien_giao_xe(%s, '{}')$$, (select v from ctx where k='hs_b')), 'quyền');
-- Hồ sơ bảo hành: không báo giá, không duyệt giá, không hãng BH / GDV; hạng mục giá 0 đã duyệt → lập lệnh ngay
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs_bh', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-444.55','ten_khach','Khách BH','dien_thoai','0909000444','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','loai','bao_hanh','ho_so_goc_id',(select v::bigint from ctx where k='hs_b'),
  'tinh_trang_xe','Sơn cửa bị rộp','tu_van','Không','so_km',30000,'bat_buoc_km',true,'bo_qua_canh_bao',true,
  'hang_muc',jsonb_build_array(jsonb_build_object('ten','Sơn lại cửa (bảo hành)','nhom','son')))))->>'id';
select kt.ghi('036 Bảo hành: nguồn khách, không hãng BH / GDV, hạng mục giá 0 đã duyệt, hồ sơ Đã duyệt giá, không doanh thu, không nợ',
  (select nguon_tt = 'khach' and hang_bh_id is null and gdv_id is null and trang_thai = 'da_duyet' and loai = 'bao_hanh' from public.ho_so where id=(select v::bigint from ctx where k='hs_bh'))
  and (select bool_and(trang_thai = 'duyet' and gia_duyet = 0 and nguoi_tra = 'khach') from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_bh'))
  and not exists (select 1 from public.v_doanh_thu where ho_so_id=(select v::bigint from ctx where k='hs_bh'))
  and (select phai_thu_khach = 0 from public.tien_ho_so((select v::bigint from ctx where k='hs_bh'))));
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_bh'), now() + interval '1 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_bh')));
select kt.ghi('036 Bảo hành lập lệnh sửa chữa được ngay', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_bh')) = 'dang_sua');
select kt.mong_loi('036 Bảo hành: hạng mục thiếu nội dung bị chặn', format($$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-444.55','ten_khach','Khách BH','dien_thoai','0909000444','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'loai','bao_hanh','ho_so_goc_id',%s,'tinh_trang_xe','x','tu_van','Không','bo_qua_canh_bao',true,'hang_muc',jsonb_build_array(jsonb_build_object('ten',''))))$$,
  (select v from ctx where k='hs_b')), 'thiếu nội dung');
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
select kt.mong_loi('043 Tệp báo giá ngoài thư mục của chứng từ bị chặn', format($$select public.them_tep_kho('de_nghi_mua', %s, 'TK/kho/bg1.jpg', 'Báo giá')$$, (select v from ctx where k='dm1')), 'không thuộc thư mục');
select public.them_tep_kho('de_nghi_mua', (select v::bigint from ctx where k='dm1'), 'TK/kho/' || (select ma from public.de_nghi_mua where id=(select v::bigint from ctx where k='dm1')) || '/bg' || g || '.jpg', 'Báo giá ' || g) from generate_series(1,3) g;
select kt.dong_vai('long@gara.vn');
select public.duyet_de_nghi_mua((select v::bigint from ctx where k='dm1'), true);
select kt.ghi('Đủ 3 báo giá thì quản lý chung duyệt được', (select trang_thai from public.de_nghi_mua where id=(select v::bigint from ctx where k='dm1')) = 'da_duyet');

-- 015: duyệt ngoại lệ khi thiếu báo giá cạnh tranh; giám đốc tự duyệt phiếu mình lập
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'dm_nl', (public.lap_de_nghi_mua(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_guong'),'so_luong',1,'don_gia',5500000,'ty_le_vat',0.08)))))->>'id';
select public.them_tep_kho('de_nghi_mua', (select v::bigint from ctx where k='dm_nl'), 'TK/kho/' || (select ma from public.de_nghi_mua where id=(select v::bigint from ctx where k='dm_nl')) || '/nl1.jpg', 'Báo giá đại lý');
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
select kt.ghi('043 Lưu số đếm thì ghi luôn tồn sổ sách lúc đếm (1 lít)',
  (select ton_so_sach = 1 and dem_luc is not null from public.kiem_ke_dong where kiem_ke_id=(select v::bigint from ctx where k='kk1')));
select kt.mong_loi('043 Có chênh lệch thì kho không tự chốt (quản lý chung / giám đốc chốt)', format($$select public.chot_kiem_ke(%s, 'thử')$$, (select v from ctx where k='kk1')), 'quản lý chung');
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('Chênh trên 5% phải ghi biên bản', format($$select public.chot_kiem_ke(%s)$$, (select v from ctx where k='kk1')), 'biên bản');
select public.chot_kiem_ke((select v::bigint from ctx where k='kk1'), 'Đổ vỡ 0,5 lít khi pha');
select kt.dong_vai('duy@gara.vn');
select kt.ghi('Chốt kiểm kê: tồn sơn còn 0,5 lít', (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_son')) = 0.5);
select public.huy_phieu_xuat((select v::bigint from ctx where k='px_chung'), 'Xuất nhầm');
select kt.ghi('Hủy phiếu xuất dùng chung: hàng về lại kho (1,5 lít)', (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_son')) = 1.5);
select kt.ghi('Thẻ kho cộng đúng tồn', (select sum(so_luong) from public.v_the_kho where hang_id=(select v::bigint from ctx where k='hang_son')) = 1.5);
select kt.dong_vai(null);
insert into ctx select 'so_hang', (select count(*) from public.hang_kho where chi_nhanh_id = 'TK')::text;
insert into ctx select 'so_pn', (select count(*) from public.phieu_nhap where chi_nhanh_id = 'TK')::text;
select kt.dong_vai('codong@gara.vn');
select kt.ghi('030 Cổ đông xem được kho: tồn, phiếu nhập, thẻ kho, công nợ NCC', (select count(*) from public.v_ton_kho) = (select v::int from ctx where k='so_hang')
  and (select count(*) from public.phieu_nhap) = (select v::int from ctx where k='so_pn') and (select v::int from ctx where k='so_pn') > 0
  and (select count(*) from public.v_the_kho) > 0 and (select count(*) from public.v_de_xuat) > 0);
select kt.mong_loi('030 Cổ đông không xuất dùng chung được', format($f$select public.xuat_dung_chung('{"dung_vao":"thử","dong":[{"hang_id":%s,"so_luong":1}]}')$f$, (select v from ctx where k='hang_son')), 'quyền');

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
   "ngay_vao":"2026-09-02","ngay_giao":"2026-09-05","nguon":"khach","tinh_trang":"02/09/2026: Trầy cản","gia_tri":3000000,"con_no_khach":1200000,"so_km":61500},
  {"bien_so":"51K99901","khach":"Khách nợ cũ","dien_thoai":"0911000001","ngay_vao":"2026-06-01","nguon":"bao_hiem","hang_bh":"tasco","gdv":"X"},
  {"bien_so":"51K-999.02","khach":"Khách BH nợ","dien_thoai":"","ngay_vao":"2026-09-10","ngay_giao":"2026-09-15","nguon":"bao_hiem",
   "hang_bh":"Hãng Lạ","con_no_bh":2500000},
  {"bien_so":"51K-999.03","khach":"Xe chưa vào lần nào","dien_thoai":"0911000003"}
]$j$::jsonb);
select kt.mong_loi('Xóa hết khi đã có phiếu thu gắn hồ sơ thì dừng, báo rõ', 'select app.nap_data_khach(true)', 'phân bổ phiếu thu');
insert into ctx select 'nap', app.nap_data_khach(false)::text;
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('031 Nạp Data khách hàng có số km', exists (select 1 from public.ho_so where tu_excel and so_km = 61500));
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
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
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
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
  'so_tien',1000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',1000))))$$, (select v from ctx where k='hs1')), 'vượt');
select public.lap_phieu_thu(jsonb_build_object(
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where ten='Khách thanh toán sửa chữa'),
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
select kt.ghi('042 Lãi gộp = doanh thu − tổng giá vốn (vật tư xe + dùng chung + hao hụt kiểm kê + chi phí nhóm giá vốn)',
  (select bool_and(lai_gop = doanh_thu - tong_gia_von and tong_gia_von = gia_von_xe + gia_von_dung_chung + hao_hut + chi_gia_von) from public.ket_qua_kinh_doanh()));
select kt.ghi('042 Lãi trước thuế = lãi gộp − tổng chi phí hoạt động + thu nhập khác; lãi không gồm VAT = lãi trước thuế − VAT đầu ra + VAT trong giá vốn đã xuất + VAT trong chi phí',
  (select bool_and(lai_truoc_thue = lai_gop - tong_chi_phi + thu_khac and tong_chi_phi = luong + hoa_hong + chi_van_hanh + chi_co_dinh
     and vat_phai_nop = vat_ra - vat_vao_hang - vat_vao_chi_phi and vat_vao = vat_vao_hang + vat_vao_chi_phi
     and lai_sau_vat = lai_truoc_thue - vat_ra + vat_trong_gia_von + vat_vao_chi_phi)
   from public.ket_qua_kinh_doanh()));
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
select public.chi_tien((select v::bigint from ctx where k='dn_dien'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('026 Chi tiền tháng này nhưng tính vào chi phí cố định tháng trước',
  (select chi_co_dinh from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date) = 1500000
  and (select ky_chi_phi from public.phieu_thu_chi where de_nghi_chi_id = (select v::bigint from ctx where k='dn_dien')) = (date_trunc('month', current_date) - interval '1 month')::date);
select kt.ghi('025 Chốt tháng trước (bỏ qua cảnh báo), có số liệu lương', (select (public.chot_thang((date_trunc('month', current_date) - interval '1 month')::date, true)->>'luong')::numeric) = 30000000);
select kt.mong_loi('025 Tháng đã chốt không ghi được phiếu', format($$select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where ten='Thu khác'),'so_tien',1000,'ngay',%L))$$, (date_trunc('month', current_date) - interval '1 day')::date), 'đã chốt');
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
insert into ctx values ('quy_truoc', (select so_du::text from public.v_so_du_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('027 Đầu kỳ: công ty nợ giám đốc 10 triệu', (select con_lai from public.v_cong_no_noi_bo where chi_nhanh_id = 'TK' and id = (select v::bigint from ctx where k='dv_thuan')) = -10000000);
select kt.ghi('027 Có đủ 4 mục thu chi nội bộ / cá nhân, mục hệ thống muon_ca_nhan', (select count(*) from public.muc_thu_chi where ten in ('Công ty mượn tiền giám đốc / cổ đông','Cổ đông / cá nhân trả tiền mượn','Cho cổ đông / cá nhân mượn','Trả tiền mượn giám đốc / cổ đông')) = 4
  and (select he_thong from public.muc_thu_chi where ten='Công ty mượn tiền giám đốc / cổ đông') = 'muon_ca_nhan');
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
-- Giám đốc cho công ty mượn thêm 5 triệu (phiếu thu) → công ty nợ 15 triệu
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where ten='Công ty mượn tiền giám đốc / cổ đông'),
  'so_tien',5000000,'noi_dung','Mượn thêm','don_vi_lien_quan_id',(select v::bigint from ctx where k='dv_thuan')));
select kt.ghi('027 Phiếu thu mượn thêm → công ty nợ 15 triệu', (select con_lai from public.v_cong_no_noi_bo where chi_nhanh_id = 'TK' and id = (select v::bigint from ctx where k='dv_thuan')) = -15000000);
-- Cổ đông mượn 3 triệu: đề nghị chi (trả nội bộ) → duyệt → chi
insert into ctx select 'dn_codong', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Cho cổ đông / cá nhân mượn'),'so_tien',3000000,'noi_dung','Cổ đông A mượn','don_vi_lien_quan_id',(select v::bigint from ctx where k='dv_codong')))::text;
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_codong'), true);
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('027 Khoản cho mượn không chi hộ được', format('select public.chi_tien(%s, (select id from public.tai_khoan_quy where ten=''Tiền mặt'' and chi_nhanh_id=''TK''), current_date, %s)', (select v from ctx where k='dn_codong'), (select v from ctx where k='dv_thuan')), 'không chi hộ');
select public.chi_tien((select v::bigint from ctx where k='dn_codong'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.ghi('027 Cổ đông mượn 3 triệu → cổ đông nợ công ty 3 triệu', (select con_lai from public.v_cong_no_noi_bo where chi_nhanh_id = 'TK' and id = (select v::bigint from ctx where k='dv_codong')) = 3000000);
-- Chi hộ: giám đốc trả tiền điện 2 triệu bằng tiền túi → phiếu chi + phiếu thu đối ứng, quỹ không đổi, chi phí vẫn tính, công ty nợ thêm
insert into ctx select 'dn_dien2', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Điện'),'so_tien',2000000,'noi_dung','Tiền điện tháng này'))::text;
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_dien2'), true);
insert into ctx values ('quy_truoc_chi_ho', (select so_du::text from public.v_so_du_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
insert into ctx values ('cp_truoc', (select chi_co_dinh::text from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date));
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'pc_chi_ho', public.chi_tien((select v::bigint from ctx where k='dn_dien2'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'), current_date, (select v::bigint from ctx where k='dv_thuan'))::text;
select kt.ghi('027 Chi hộ: có phiếu thu đối ứng cùng số tiền, gắn người chi hộ',
  (select count(*) from public.phieu_thu_chi t where t.phieu_doi_ung_id = (select v::bigint from ctx where k='pc_chi_ho') and t.loai='thu' and t.so_tien=2000000 and t.don_vi_lien_quan_id = (select v::bigint from ctx where k='dv_thuan') and t.trang_thai='hieu_luc') = 1
  and (select chi_ho_boi from public.phieu_thu_chi where id = (select v::bigint from ctx where k='pc_chi_ho')) = (select v::bigint from ctx where k='dv_thuan'));
select kt.ghi('027 Chi hộ: số dư quỹ không đổi', (select so_du::text from public.v_so_du_quy where ten='Tiền mặt' and chi_nhanh_id='TK') = (select v from ctx where k='quy_truoc_chi_ho'));
select kt.ghi('027 Chi hộ: công ty nợ giám đốc thêm 2 triệu = 17 triệu', (select con_lai from public.v_cong_no_noi_bo where chi_nhanh_id = 'TK' and id = (select v::bigint from ctx where k='dv_thuan')) = -17000000);
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('027 Chi hộ: chi phí cố định tháng này vẫn tính thêm 2 triệu',
  (select chi_co_dinh from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date) = (select v::numeric from ctx where k='cp_truoc') + 2000000);
select kt.ghi('027 Tổng phải thu / phải trả nội bộ', (select sum(case when con_lai > 0 then con_lai else 0 end) from public.v_cong_no_noi_bo where chi_nhanh_id = 'TK') = 3000000
  and (select sum(case when con_lai < 0 then -con_lai else 0 end) from public.v_cong_no_noi_bo where chi_nhanh_id = 'TK') = 17000000);
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
-- Hủy phiếu thu đối ứng → phiếu chi hủy theo, đề nghị về đã duyệt, nợ về 15 triệu
select public.huy_phieu((select id from public.phieu_thu_chi where phieu_doi_ung_id = (select v::bigint from ctx where k='pc_chi_ho') and loai='thu'), 'Ghi nhầm');
select kt.ghi('027 Hủy một phiếu chi hộ → phiếu kia hủy theo, đề nghị về Đã duyệt, nợ về 15 triệu',
  (select trang_thai from public.phieu_thu_chi where id = (select v::bigint from ctx where k='pc_chi_ho')) = 'huy'
  and (select trang_thai from public.de_nghi_chi where id = (select v::bigint from ctx where k='dn_dien2')) = 'da_duyet'
  and (select con_lai from public.v_cong_no_noi_bo where chi_nhanh_id = 'TK' and id = (select v::bigint from ctx where k='dv_thuan')) = -15000000);
select kt.dong_vai(null);
select kt.dong_vai('duy@gara.vn');
select kt.ghi('027 CVDV không thấy công nợ nội bộ', (select count(*) from public.v_cong_no_noi_bo) = 0);
select kt.dong_vai(null);

-- ---------- 028: tài sản – dụng cụ, máy móc của các nhóm ----------
select kt.dong_vai(null);
select kt.ghi('028 Có 5 nhóm tài sản: 3 tổ + Dùng chung xưởng + Văn phòng', (select count(*) from public.nhom_tai_san) = 5
  and (select vai_phu_trach from public.nhom_tai_san where id = 'VP') = '{ke_toan}');
select kt.dong_vai('duy@gara.vn');   -- CVDV + kho: được thêm tài sản
insert into ctx select 'ts_may', public.luu_tai_san('{"ten":"Máy nén khí 50L","loai":"may_moc","nhom_id":"CHUNG","gia_mua":12000000,"so_serial":"MNK-01"}')::text;
insert into ctx select 'ts_tuyp', public.luu_tai_san('{"ten":"Bộ tuýp 1/2 24 chi tiết","loai":"dung_cu","nhom_id":"DS","so_luong":2,"don_vi":"Bộ","gia_mua":850000}')::text;
insert into ctx select 'ts_bua', public.luu_tai_san('{"ten":"Búa gò","loai":"dung_cu","nhom_id":"DS","so_luong":3,"gia_mua":120000}')::text;
insert into ctx select 'ts_may_ds', public.luu_tai_san('{"ten":"Máy đánh bóng","loai":"may_moc","nhom_id":"DS","gia_mua":4500000}')::text;
select kt.ghi('028/029 Mã tự sinh theo nhóm: TB-CHUNG-001, TB-DS-001, TB-DS-002',
  (select ma from public.tai_san where id = (select v::bigint from ctx where k='ts_may')) = 'TB-CHUNG-001'
  and (select ma from public.tai_san where id = (select v::bigint from ctx where k='ts_tuyp')) = 'TB-DS-001'
  and (select ma from public.tai_san where id = (select v::bigint from ctx where k='ts_bua')) = 'TB-DS-002');
select kt.mong_loi('028 Dụng cụ số lượng 0 bị chặn',
  $$select public.luu_tai_san('{"ten":"Kìm","loai":"dung_cu","nhom_id":"DS","so_luong":0}')$$, 'từ 1');
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('028 Kế toán không thêm tài sản được', $$select public.luu_tai_san('{"ten":"Máy in","loai":"may_moc","nhom_id":"VP"}')$$, 'quyền');
select kt.dong_vai(null);
select kt.dong_vai('han@gara.vn');   -- trưởng nhóm tổ DS
select kt.ghi('028 Trưởng nhóm DS chỉ thấy tài sản tổ mình (3 món), không thấy Dùng chung', (select count(*) from public.v_tai_san) = 3
  and (select count(*) from public.v_nhom_tai_san) = 1 and (select nhom_id from public.v_nhom_tai_san) = 'DS');
select kt.ghi('028 Trưởng nhóm có việc: xác nhận nhận 3 món (029: tên việc "Xác nhận đã nhận đồ nghề – Đồng sơn")',
  exists (select 1 from public.v_viec_tai_san where loai = 'xac_nhan' and nhom_id = 'DS' and so = 3 and tieu_de = 'Xác nhận đã nhận đồ nghề – Đồng sơn'));
select kt.mong_loi('028 Trưởng nhóm DS không xác nhận tài sản nhóm khác', format('select public.xac_nhan_nhan_tai_san(''[%s]''::jsonb)', (select v from ctx where k='ts_may')), '');
select kt.ghi('028 Trưởng nhóm DS xác nhận nhận 2 món', public.xac_nhan_nhan_tai_san(jsonb_build_array((select v::bigint from ctx where k='ts_tuyp'), (select v::bigint from ctx where k='ts_bua'))) = 2);
select kt.mong_loi('028 Kiểm tra tuần phải đủ mọi tài sản của nhóm',
  format($$select public.luu_kiem_tra_tai_san('{"nhom_id":"DS","loai":"kiem_tra","dong":[{"tai_san_id":%s,"so_thuc":2}]}')$$, (select v from ctx where k='ts_tuyp')), 'chưa kiểm');
insert into ctx select 'kt_ds', public.luu_kiem_tra_tai_san(jsonb_build_object('nhom_id','DS','loai','kiem_tra','dong', jsonb_build_array(
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_tuyp'), 'so_thuc', 2, 'so_hong', 0),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_bua'), 'so_thuc', 2, 'so_hong', 0, 'ghi_chu', 'Không thấy 1 cái'),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_may_ds'), 'so_thuc', 1, 'so_hong', 1, 'ghi_chu', 'Không lên nguồn'))))::text;
select kt.ghi('028 Kiểm tra tuần: 1 thiếu, 1 hỏng → 2 sự cố chờ xử lý, máy hỏng chuyển tình trạng Hỏng, máy đếm thấy coi như đã nhận',
  (select so_thieu = 1 and so_hong = 1 and so_dong = 3 from public.kiem_tra_tai_san where id = (select v::bigint from ctx where k='kt_ds'))
  and (select count(*) from public.su_co_tai_san where kiem_tra_id = (select v::bigint from ctx where k='kt_ds')) = 2
  and (select tinh_trang = 'hong' and not cho_nhan from public.tai_san where id = (select v::bigint from ctx where k='ts_may_ds')));
select kt.ghi('028 Hạn kiểm tra tuần tiếp theo = hôm nay + 7, hết việc kiểm tra và xác nhận', (select han_kiem_tra from public.v_nhom_tai_san where nhom_id = 'DS') = current_date + 7
  and not exists (select 1 from public.v_viec_tai_san where nhom_id = 'DS' and loai in ('kiem_tra','xac_nhan')));
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('028 Kế toán không kiểm tra tuần nhóm DS (không phụ trách)', $$select public.luu_kiem_tra_tai_san('{"nhom_id":"DS","loai":"kiem_tra","dong":[{"tai_san_id":1,"so_thuc":1}]}')$$, 'phụ trách');
select kt.mong_loi('028 Kiểm kê phải ghi người cùng kiểm', $$select public.luu_kiem_tra_tai_san('{"nhom_id":"DS","loai":"kiem_ke","dong":[{"tai_san_id":1,"so_thuc":1}]}')$$, 'cùng kiểm');
select kt.dong_vai(null);
select kt.dong_vai('long@gara.vn');
select kt.ghi('028 Quản lý chung có việc xử lý 2 sự cố của DS và kiểm tra tuần nhóm Dùng chung', exists (select 1 from public.v_viec_tai_san where loai = 'su_co' and nhom_id = 'DS' and so = 2)
  and exists (select 1 from public.v_viec_tai_san where loai = 'xac_nhan' and nhom_id = 'CHUNG'));
select kt.mong_loi('028 Quản lý chung không ghi tiền bồi thường', format($$select public.xu_ly_su_co_tai_san('{"id":%s,"ket_qua":"ghi_mat","boi_thuong":100000,"nguoi_chiu_ten":"Hận"}')$$,
  (select id from public.su_co_tai_san where loai = 'mat' and kiem_tra_id = (select v::bigint from ctx where k='kt_ds'))), 'giám đốc');
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select public.xu_ly_su_co_tai_san(jsonb_build_object('id', (select id from public.su_co_tai_san where loai = 'mat' and kiem_tra_id = (select v::bigint from ctx where k='kt_ds')),
  'ket_qua', 'ghi_mat', 'boi_thuong', 120000, 'nguoi_chiu', (select id from public.nhan_vien where email = 'han@gara.vn'), 'ghi_chu', 'Làm mất ngoài bãi'));
select kt.ghi('028 Giám đốc ghi mất + bồi thường 120.000 (Đặng Thanh Hận) → búa còn 2, sự cố đã xử lý',
  (select so_luong from public.tai_san where id = (select v::bigint from ctx where k='ts_bua')) = 2
  and (select trang_thai = 'da_xu_ly' and boi_thuong = 120000 and nguoi_chiu_ten = 'Đặng Thanh Hận' and not da_tru from public.su_co_tai_san where loai = 'mat' and kiem_tra_id = (select v::bigint from ctx where k='kt_ds')));
select kt.dong_vai(null);
select kt.dong_vai('tien@gara.vn');
select public.danh_dau_boi_thuong((select id from public.su_co_tai_san where loai = 'mat' and kiem_tra_id = (select v::bigint from ctx where k='kt_ds')), true);
select kt.ghi('028 Kế toán đánh dấu bồi thường đã trừ lương', (select da_tru from public.su_co_tai_san where loai = 'mat' and kiem_tra_id = (select v::bigint from ctx where k='kt_ds')));
-- Kiểm kê tháng nhóm DS do kế toán làm cùng trưởng nhóm
insert into ctx select 'kk_ds', public.luu_kiem_tra_tai_san(jsonb_build_object('nhom_id','DS','loai','kiem_ke','cung_kiem','Đặng Thanh Hận','dong', jsonb_build_array(
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_tuyp'), 'so_thuc', 2),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_bua'), 'so_thuc', 2),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_may_ds'), 'so_thuc', 1, 'so_hong', 1, 'ghi_chu', 'Vẫn hỏng'))))::text;
select kt.ghi('028 Kiểm kê tháng xong → hạn kiểm kê tiếp theo là cuối tháng sau', (select han_kiem_ke from public.v_nhom_tai_san where nhom_id = 'DS')
  = (date_trunc('month', current_date) + interval '2 month' - interval '1 day')::date);
select kt.ghi('028 Kiểm kê thấy máy vẫn hỏng (đang chờ xử lý) → không báo trùng sự cố', (select count(*) from public.su_co_tai_san where kiem_tra_id = (select v::bigint from ctx where k='kk_ds')) = 0
  and (select count(*) from public.su_co_tai_san where tai_san_id = (select v::bigint from ctx where k='ts_may_ds') and trang_thai = 'cho_xu_ly') = 1
  and (select so_hong = 1 from public.kiem_tra_tai_san where id = (select v::bigint from ctx where k='kk_ds')));
select kt.dong_vai(null);
select kt.dong_vai('han@gara.vn');
insert into ctx select 'kt_ds2', public.luu_kiem_tra_tai_san(jsonb_build_object('nhom_id','DS','loai','kiem_tra','dong', jsonb_build_array(
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_tuyp'), 'so_thuc', 0, 'ghi_chu', 'Không thấy cả 2 bộ'),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_bua'), 'so_thuc', 2),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_may_ds'), 'so_thuc', 1, 'so_hong', 1))))::text;
insert into ctx select 'kt_ds3', public.luu_kiem_tra_tai_san(jsonb_build_object('nhom_id','DS','loai','kiem_tra','dong', jsonb_build_array(
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_tuyp'), 'so_thuc', 1),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_bua'), 'so_thuc', 2),
  jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_may_ds'), 'so_thuc', 1, 'so_hong', 1))))::text;
select kt.ghi('028 Tuần sau vẫn thiếu như cũ → không báo lại; thiếu thêm chỉ báo phần thêm',
  (select count(*) from public.su_co_tai_san where kiem_tra_id = (select v::bigint from ctx where k='kt_ds2')) = 1
  and (select count(*) from public.su_co_tai_san where kiem_tra_id = (select v::bigint from ctx where k='kt_ds3')) = 0
  and (select sum(so_luong) from public.su_co_tai_san where tai_san_id = (select v::bigint from ctx where k='ts_tuyp') and trang_thai = 'cho_xu_ly') = 2);
select kt.dong_vai(null);
select kt.dong_vai('thuan@gara.vn');
select public.xu_ly_su_co_tai_san(jsonb_build_object('id', (select id from public.su_co_tai_san where kiem_tra_id = (select v::bigint from ctx where k='kt_ds2')), 'ket_qua', 'tim_thay', 'ghi_chu', 'Tổ ĐMG mượn, đã trả'));
select kt.ghi('028 Tìm thấy → giữ nguyên số lượng, hết sự cố chờ', (select so_luong from public.tai_san where id = (select v::bigint from ctx where k='ts_tuyp')) = 2
  and not exists (select 1 from public.su_co_tai_san where tai_san_id = (select v::bigint from ctx where k='ts_tuyp') and trang_thai = 'cho_xu_ly'));
select kt.dong_vai(null);
-- Bảo dưỡng máy nén khí: chu kỳ 90 ngày, bắt đầu 100 ngày trước → quá hạn; ghi bảo dưỡng → hết việc
select kt.dong_vai('long@gara.vn');
insert into ctx select 'lich_mnk', public.luu_lich_bao_duong(jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_may'), 'ten_viec', 'Thay dầu, xả nước bình', 'chu_ky_ngay', 90, 'bat_dau', current_date - 100))::text;
select kt.ghi('028 Lịch bảo dưỡng quá hạn hiện thành việc của quản lý chung (nhóm Dùng chung)',
  exists (select 1 from public.v_viec_tai_san where loai = 'bao_duong' and tai_san_id = (select v::bigint from ctx where k='ts_may') and han = current_date - 10 and vai @> '{quan_ly}'));
select public.ghi_bao_duong(jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_may'), 'lich_id', (select v::bigint from ctx where k='lich_mnk'),
  'loai', 'bao_duong', 'noi_dung', 'Thay 1 lít dầu, xả nước', 'nguoi_lam', 'Vinh', 'chi_phi', 150000));
select kt.ghi('028 Ghi bảo dưỡng → hạn tiếp theo sau 90 ngày, hết việc', (select han_bao_duong from public.v_tai_san where id = (select v::bigint from ctx where k='ts_may')) = current_date + 90
  and not exists (select 1 from public.v_viec_tai_san where loai = 'bao_duong' and tai_san_id = (select v::bigint from ctx where k='ts_may')));
-- Máy hỏng: đưa đi sửa → sửa xong qua ghi sửa chữa
select public.xu_ly_su_co_tai_san(jsonb_build_object('id', (select id from public.su_co_tai_san where loai = 'hong' and kiem_tra_id = (select v::bigint from ctx where k='kt_ds')), 'ket_qua', 'dua_sua'));
select kt.ghi('028 Đưa máy đi sửa → Đang sửa', (select tinh_trang from public.tai_san where id = (select v::bigint from ctx where k='ts_may_ds')) = 'dang_sua');
select public.ghi_bao_duong(jsonb_build_object('tai_san_id', (select v::bigint from ctx where k='ts_may_ds'), 'loai', 'sua_chua', 'noi_dung', 'Thay chổi than', 'chi_phi', 300000, 'thue_ngoai', true, 'xong', true));
select kt.ghi('028 Ghi sửa chữa xong → máy Tốt, có lịch sử', (select tinh_trang from public.tai_san where id = (select v::bigint from ctx where k='ts_may_ds')) = 'tot'
  and exists (select 1 from public.tai_san_lich_su where tai_san_id = (select v::bigint from ctx where k='ts_may_ds') and loai = 'sua_chua'));
select kt.dong_vai(null);
select kt.dong_vai('duy@gara.vn');
select public.chuyen_nhom_tai_san((select v::bigint from ctx where k='ts_bua'), 'DMG', 'Tổ ĐMG mượn hẳn');
select public.thanh_ly_tai_san((select v::bigint from ctx where k='ts_tuyp'), 'Mòn, gãy');
select kt.ghi('028 Chuyển nhóm → chờ nhóm mới xác nhận; thanh lý → không còn tính', (select nhom_id = 'DMG' and cho_nhan from public.tai_san where id = (select v::bigint from ctx where k='ts_bua'))
  and (select so_tai_san from public.v_nhom_tai_san where nhom_id = 'DS') = 1);
select kt.dong_vai(null);
select kt.dong_vai(null);
insert into ctx select 'so_ts', (select count(*) from public.tai_san where chi_nhanh_id = 'TK')::text;
select kt.dong_vai('codong@gara.vn');
select kt.ghi('030 Cổ đông xem được thiết bị đồ nghề mọi nhóm, sự cố, kiểm tra', (select count(*) from public.v_tai_san) = (select v::int from ctx where k='so_ts')
  and (select count(*) from public.v_nhom_tai_san) = 5 and (select count(*) from public.su_co_tai_san) > 0 and (select count(*) from public.kiem_tra_tai_san) > 0);
select kt.mong_loi('030 Cổ đông không thêm thiết bị được', $$select public.luu_tai_san('{"ten":"Máy thử","loai":"may_moc","nhom_id":"VP"}')$$, 'quyền');
select kt.ghi('030 Cổ đông xem được kết quả kinh doanh mọi tháng (cả tháng chưa chốt), công nợ, nợ nội bộ, lương',
  exists (select 1 from public.ket_qua_kinh_doanh(null) where thang = date_trunc('month', current_date)::date) and (select count(*) from public.v_cong_no_noi_bo) > 0
  and (select count(*) from public.bang_luong_thang) > 0 and (select count(*) from public.nhan_vien) > 1);
select kt.mong_loi('030 Cổ đông không chốt tháng được', $$select public.chot_thang(date_trunc('month', current_date - interval '1 month')::date, true, null)$$, 'quyền');
select kt.mong_loi('030 Cổ đông không lập phiếu thu được', $$select public.lap_phieu_thu('{"so_tien":1000}')$$, 'quyền');
select kt.ghi('030 Cổ đông không xem nhật ký xuất file', (select count(*) from public.nhat_ky_xuat_file) = 0);
select kt.dong_vai(null);

-- ---------------------------------------------------------------------
-- 038: rà soát lần 2 – nhóm A (lỗi số liệu / kẹt việc)
-- ---------------------------------------------------------------------
select kt.dong_vai('thuan@gara.vn');
-- A2: hủy phiếu chi rồi chi lại cùng đề nghị
insert into ctx select 'dn_a2', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Nước'),'so_tien',200000,'noi_dung','Nước tháng này'))::text;
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_a2'), true);
insert into ctx select 'pc_a2', public.chi_tien((select v::bigint from ctx where k='dn_a2'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'))::text;
select public.huy_phieu((select v::bigint from ctx where k='pc_a2'), 'Chi nhầm tài khoản');
insert into ctx select 'pc_a2b', public.chi_tien((select v::bigint from ctx where k='dn_a2'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'))::text;
select kt.ghi('038 Hủy phiếu chi rồi chi lại cùng đề nghị: được, đề nghị về Đã chi, chỉ 1 phiếu hiệu lực',
  (select trang_thai from public.de_nghi_chi where id=(select v::bigint from ctx where k='dn_a2')) = 'da_chi'
  and (select count(*) filter (where trang_thai='hieu_luc') = 1 and count(*) = 2 from public.phieu_thu_chi where de_nghi_chi_id=(select v::bigint from ctx where k='dn_a2')));
-- A3: hoa hồng GDV sau chốt tháng; hủy phiếu có kỳ chi phí đã chốt
insert into ctx select 'hs_a3', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-038.03','ten_khach','Khách A3','dien_thoai','0909038003','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),
  'tinh_trang_xe','Trầy cản','tu_van','Không','so_km',1000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_a3'), '[{"ten":"Sơn cản","nhom":"son","gia_bao":2000000}]', 0.08);
select kt.mong_loi('043 Ngày duyệt giá trước ngày nhận xe bị chặn', format($$select public.duyet_gia(%s, (date_trunc('month', current_date) - interval '1 day')::date, '[]')$$,
  (select v from ctx where k='hs_a3')), 'trước ngày nhận xe');
select kt.dong_vai(null);
update public.ho_so set ngay_vao = date_trunc('month', current_date) - interval '5 days' where id = (select v::bigint from ctx where k='hs_a3');
select kt.dong_vai('thuan@gara.vn');
select public.duyet_gia((select v::bigint from ctx where k='hs_a3'), (date_trunc('month', current_date) - interval '1 day')::date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a3')));
select public.chot_thang((date_trunc('month', current_date) - interval '1 month')::date, true);
-- 043: tháng duyệt giá đã chốt → hoa hồng ghi vào tháng đang mở (trước đây bị chặn, nhắc treo mãi)
insert into ctx select 'hh_a3_truoc', (select hoa_hong from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)::text;
select public.nhap_hoa_hong_gdv((select v::bigint from ctx where k='hs_a3'), 120000);
select kt.ghi('043 Hoa hồng GDV của xe duyệt giá tháng đã chốt: ghi vào tháng đang mở, tháng đã chốt giữ nguyên',
  (select hoa_hong_ky from public.ho_so where id=(select v::bigint from ctx where k='hs_a3')) = date_trunc('month', current_date)::date
  and (select hoa_hong from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date) = (select v::numeric from ctx where k='hh_a3_truoc') + 120000
  and (select not lech_chot from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date)
  and (select count(*) from public.chi_tiet_kqkd(current_date, 'hoa_hong') where ho_so_id = (select v::bigint from ctx where k='hs_a3')) = 1);
select kt.mong_loi('043 Tháng trước tháng đã chốt (tháng trống) cũng khóa sổ', $$select public.lap_phieu_chuyen(jsonb_build_object('ngay', (date_trunc('month', current_date) - interval '2 month')::date,
  'tai_khoan_id',(select id from public.tai_khoan_quy where ten='TK công ty (331 331 331 68)'),'tai_khoan_den_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'so_tien',1000))$$, 'khóa sổ');
select kt.ghi('043 Báo cáo: tháng trống trước tháng đã chốt hiện "đã khóa"',
  not exists (select 1 from public.ket_qua_kinh_doanh() where thang < (date_trunc('month', current_date) - interval '1 month')::date and trang_thai not in ('da_khoa','da_chot')));
select kt.mong_loi('038 Hủy phiếu chi có kỳ chi phí thuộc tháng đã chốt bị chặn', format($$select public.huy_phieu(%s, 'thử')$$,
  (select id from public.phieu_thu_chi where de_nghi_chi_id=(select v::bigint from ctx where k='dn_dien') and trang_thai='hieu_luc')), 'đã chốt');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '1 month')::date, 'Thử 038');
select public.nhap_hoa_hong_gdv((select v::bigint from ctx where k='hs_a3'), 100000);
select kt.ghi('038 Mở lại tháng thì nhập hoa hồng được (về lại tháng duyệt giá)', (select hoa_hong_gdv = 100000 and hoa_hong_ky is null from public.ho_so where id=(select v::bigint from ctx where k='hs_a3')));
-- A4: phát sinh bị từ chối hết khi xe đang sửa → tự sang Chờ KCS
insert into ctx select 'hs_a4', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-038.04','ten_khach','Khách A4','dien_thoai','0909038004','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),
  'tinh_trang_xe','Móp hông','tu_van','Không','so_km',2000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_a4'), '[{"ten":"Gò hông","nhom":"dong_son","gia_bao":1000000},{"ten":"Sơn hông","nhom":"son","gia_bao":1500000}]', 0.08);
select public.duyet_gia((select v::bigint from ctx where k='hs_a4'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a4')));
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_a4'), now() + interval '2 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a4')));
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a4') and ten='Gò hông'));
select public.bao_phat_sinh((select v::bigint from ctx where k='hs_a4'), 'Nứt đèn');
select public.lap_bao_gia((select v::bigint from ctx where k='hs_a4'), '[{"ten":"Thay đèn","nhom":"phu_tung","gia_bao":3000000}]', 0.08);
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a4') and ten='Sơn hông'));
select kt.ghi('038 Còn dòng phát sinh chờ duyệt thì xe vẫn Đang sửa', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_a4')) = 'dang_sua');
select public.duyet_gia((select v::bigint from ctx where k='hs_a4'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',false)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a4') and trang_thai='cho_duyet'));
select kt.ghi('038 Hãng từ chối hết phát sinh → xe tự sang Chờ KCS (không kẹt Đang sửa)',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_a4')) = 'cho_kcs'
  and exists (select 1 from public.ho_so_nhat_ky where ho_so_id=(select v::bigint from ctx where k='hs_a4') and ghi_chu like 'Hết hạng mục còn làm%'));
-- A5: thủ kho xem công nợ NCC thấy "đã trả"
insert into ctx select 'dn_a5', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Trả NCC – Vật tư sơn'),'so_tien',500000,'noi_dung','Trả VTN đợt 1',
  'nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Vật tư sơn VTN')))::text;
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_a5'), true);
select public.chi_tien((select v::bigint from ctx where k='dn_a5'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.dong_vai('duy@gara.vn');
select kt.ghi('038 Vai kho xem công nợ NCC: đã trả 500.000 (trước đây = 0 vì không đọc được phiếu chi)',
  (select da_tra from public.v_cong_no_ncc where ten='Vật tư sơn VTN' and chi_nhanh_id='TK') = 500000,
  (select da_tra::text from public.v_cong_no_ncc where ten='Vật tư sơn VTN' and chi_nhanh_id='TK'));
-- A7: hủy phiếu nhập sau khi phiếu xuất lấy hàng của lô đã hủy; chặn khi còn phiếu xuất hiệu lực
insert into ctx select 'pn_a7', (public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_den'),'so_luong',2,'don_gia',900000,'ty_le_vat',0.08)))))->>'id';
insert into ctx select 'px_a7', (public.xuat_dung_chung(('{"ghi_chu":"Thử","dong":[{"hang_id":' || (select v from ctx where k='hang_den') || ',"so_luong":1}]}')::jsonb))->>'id';
select kt.mong_loi('038 Hủy phiếu nhập khi phiếu xuất còn hiệu lực: báo rõ mã phiếu xuất', format($$select public.huy_phieu_nhap(%s, 'nhầm')$$, (select v from ctx where k='pn_a7')), 'hủy phiếu xuất đó trước');
select public.huy_phieu_xuat((select v::bigint from ctx where k='px_a7'), 'Xuất nhầm');
select public.huy_phieu_nhap((select v::bigint from ctx where k='pn_a7'), 'Nhập nhầm');
select kt.ghi('038 Hủy phiếu xuất rồi hủy phiếu nhập: được (trước đây lỗi khóa ngoại), tồn đèn về 0',
  (select trang_thai from public.phieu_nhap where id=(select v::bigint from ctx where k='pn_a7')) = 'huy'
  and (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_den')) = 0);
-- A6: tiền bo tách phiếu trong một giao dịch; khách trả dư không tự đóng hồ sơ, có cảnh báo
select kt.dong_vai('thuan@gara.vn');
insert into ctx select 'hs_a6', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-038.06','ten_khach','Khách A6','dien_thoai','0909038006','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Rửa sơn','tu_van','Không','so_km',3000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_a6'), '[{"ten":"Đánh bóng","nhom":"detailing","gia_bao":1000000}]', 0.08);
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_a6'), now() + interval '1 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DT')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a6')));
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_a6')));
select public.them_tep((select v::bigint from ctx where k='hs_a6'), 'kcs', 'anh', 'TK/' || (select ma from public.ho_so where id=(select v::bigint from ctx where k='hs_a6')) || '/kcs-sau-sua.jpg');
select public.kcs((select v::bigint from ctx where k='hs_a6'), true);
select kt.mong_loi('038 Tiền bo lớn hơn hoặc bằng số tiền phiếu bị chặn', format($$select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_khach'),'so_tien',1000000,'tien_bo',1000000,'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',%s,'so_tien',0))))$$, (select v from ctx where k='hs_a6')), 'Tiền bo không hợp lệ');
insert into ctx select 'pt_a6', public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_khach'),
  'so_tien',1130000,'tien_bo',50000,'noi_dung','Khách trả xe A6','phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_a6'),'so_tien',1080000))))::text;
select kt.ghi('038 Tiền bo: một lần gọi → 2 phiếu thu (1.080.000 vào xe + 50.000 mục Tiền bo), xe hết nợ',
  (select so_tien from public.phieu_thu_chi where id=(select v::bigint from ctx where k='pt_a6')) = 1080000
  and exists (select 1 from public.phieu_thu_chi p join public.muc_thu_chi m on m.id=p.muc_id where p.so_tien=50000 and m.he_thong='tien_bo' and p.noi_dung like 'Tiền bo của khách%' and p.trang_thai='hieu_luc')
  and (select con_no_khach from public.tien_ho_so((select v::bigint from ctx where k='hs_a6'))) = 0);
select public.giao_xe((select v::bigint from ctx where k='hs_a6'), '{"cam_nhan_khach":"Tốt"}');
select kt.ghi('038 Giao xe khách lẻ hết nợ → tự đóng', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_a6')) = 'dong');
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_khach'),
  'so_tien',100000,'cho_tra_du',true,'noi_dung','Khách đưa dư','phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_a6'),'so_tien',100000))));
select kt.ghi('038 Khách trả dư sau giao: hồ sơ mở lại (không tự đóng), Việc hôm nay cảnh báo "trả dư"',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_a6')) = 'da_giao'
  and exists (select 1 from public.v_canh_bao where loai='khach_tra_du' and ho_so_id=(select v::bigint from ctx where k='hs_a6') and noi_dung like '%trả dư 100.000 đ%'));
-- Trả lại khách qua đề nghị chi "Trả lại cọc" → hết nợ → tự đóng
insert into ctx select 'dn_a6', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where tinh_chat='tra_coc'),'so_tien',100000,'noi_dung','Trả lại tiền dư','ho_so_id',(select v::bigint from ctx where k='hs_a6')))::text;
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_a6'), true);
select public.chi_tien((select v::bigint from ctx where k='dn_a6'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.ghi('038 Trả lại tiền dư → hết nợ → hồ sơ tự đóng, hết cảnh báo',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_a6')) = 'dong'
  and not exists (select 1 from public.v_canh_bao where loai='khach_tra_du' and ho_so_id=(select v::bigint from ctx where k='hs_a6')));
-- A8: số lần vào gara không đếm hồ sơ hủy
insert into ctx select 'hs_a8', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-038.08','ten_khach','Khách A8','dien_thoai','0909038008','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Thử','tu_van','Không','so_km',100,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.huy_ho_so((select v::bigint from ctx where k='hs_a8'), 'Khách đổi ý');
select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-038.08','ten_khach','Khách A8','dien_thoai','0909038008','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Thử 2','tu_van','Không','so_km',200,'bat_buoc_km',true,'bo_qua_canh_bao',true));
select kt.ghi('038 Tra cứu xe: số lần vào gara không đếm hồ sơ hủy (1, không phải 2)',
  (public.tra_cuu_xe('51G-038.08')->>'so_lan_vao')::int = 1 and (public.tra_cuu_xe('51G-038.08')->'ho_so_gan_nhat'->>'id')::bigint <> (select v::bigint from ctx where k='hs_a8'));
-- ===================== 040: tối ưu giao diện =====================
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('040 v_ho_so có nguoi_tiep_theo, giao_viec_luc khớp bảng hồ sơ (Việc hôm nay đọc một lần)',
  not exists (select 1 from public.v_ho_so v join public.ho_so h on h.id = v.id
              where v.nguoi_tiep_theo is distinct from h.nguoi_tiep_theo or v.giao_viec_luc is distinct from h.giao_viec_luc)
  and exists (select 1 from public.v_ho_so where nguoi_tiep_theo is not null));
select kt.ghi('040 Bảng việc tổ trả thêm nguồn, loại hồ sơ, chi nhánh (thanh 9 bước nhỏ bỏ đúng bước)',
  (select bool_and(x ? 'nguon_tt' and x ? 'loai' and x ? 'chi_nhanh_id') from jsonb_array_elements(public.bang_viec_to()) x)
  and jsonb_array_length(public.bang_viec_to()) > 0);
select kt.ghi('040 Nhập – xuất – tồn tính ở máy chủ khớp thẻ kho từng mã (tháng này)',
  not exists (
    with k as (select date_trunc('month', current_date)::date as tu),
    tay as (select t.hang_id,
              sum(t.so_luong) filter (where t.ngay < k.tu) as dau,
              sum(t.so_luong) filter (where t.ngay >= k.tu and t.so_luong > 0) as nhap,
              -sum(t.so_luong) filter (where t.ngay >= k.tu and t.so_luong <= 0) as xuat,
              sum(t.gia_tri) filter (where t.ngay >= k.tu and t.so_luong <= 0) as gtx
            from public.v_the_kho t, k where t.ngay <= current_date group by t.hang_id)
    select 1 from tay full join public.nhap_xuat_ton(to_char(current_date, 'YYYY-MM')) m on m.hang_id = tay.hang_id
    where coalesce(tay.dau,0) <> coalesce(m.dau,0) or coalesce(tay.nhap,0) <> coalesce(m.nhap,0)
       or coalesce(tay.xuat,0) <> coalesce(m.xuat,0) or coalesce(-tay.gtx,0) <> coalesce(m.gt_xuat,0))
  and (select count(*) from public.nhap_xuat_ton(to_char(current_date, 'YYYY-MM'))) > 0);
select kt.mong_loi('040 Gắn ảnh: đường dẫn thuộc hồ sơ khác bị chặn',
  format($$select public.them_tep(%s, 'kcs', 'anh', 'TK/TK-0000-KHAC/kcs-1.jpg')$$, (select v from ctx where k='hs1')), 'không thuộc thư mục');
select kt.mong_loi('040 Gắn ảnh: bước không hợp lệ bị chặn',
  format($$select public.them_tep(%1$s, 'bat_ky', 'anh', 'TK/' || (select ma from public.ho_so where id=%1$s) || '/x.jpg')$$, (select v from ctx where k='hs1')), 'Bước của tệp');
select kt.dong_vai('duy@gara.vn');
select kt.ghi('040 Vai kho (Duy: CVDV + kho) gọi nhập – xuất – tồn được (quyền như thẻ kho)',
  (select count(*) from public.nhap_xuat_ton(to_char(current_date, 'YYYY-MM'))) > 0);
-- ===================== 041: thiếu logic nghiệp vụ =====================
select kt.dong_vai('thuan@gara.vn');
-- B9: giảm giá sau khi giao xe → hết nợ → tự đóng; không giảm quá phần khách phải trả
insert into ctx select 'tn_b9', public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-041.09','ten_khach','Khách B9','dien_thoai','0909041009','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Rửa sơn','tu_van','Không','so_km',3000,'bat_buoc_km',true,'bo_qua_canh_bao',true))::text;
insert into ctx select 'hs_b9', (select v::jsonb->>'id' from ctx where k='tn_b9');
select kt.ghi('041 Tiếp nhận trả về chi nhánh của hồ sơ (ảnh lưu đúng thư mục)', (select v::jsonb->>'chi_nhanh_id' from ctx where k='tn_b9') = 'TK');
select public.lap_bao_gia((select v::bigint from ctx where k='hs_b9'), '[{"ten":"Đánh bóng","nhom":"detailing","gia_bao":1000000}]', 0.08);
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_b9'), now() + interval '1 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DT')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b9')));
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b9')));
select public.them_tep((select v::bigint from ctx where k='hs_b9'), 'kcs', 'anh', 'TK/' || (select ma from public.ho_so where id=(select v::bigint from ctx where k='hs_b9')) || '/kcs-1.jpg');
select public.kcs((select v::bigint from ctx where k='hs_b9'), true);
select public.duyet_giao_xe_con_no((select v::bigint from ctx where k='hs_b9'));
select public.giao_xe((select v::bigint from ctx where k='hs_b9'), '{"cam_nhan_khach":"Tốt"}');
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_khach'),
  'so_tien',1000000,'noi_dung','Khách B9 trả một phần','phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_b9'),'so_tien',1000000))));
select kt.mong_loi('041 Giảm giá lớn hơn phần khách phải trả bị chặn', format($$select public.duyet_giam_gia(%s, 2000000, 'thử')$$, (select v from ctx where k='hs_b9')), 'lớn hơn phần khách phải trả');
select public.duyet_giam_gia((select v::bigint from ctx where k='hs_b9'), 80000, 'Bớt phần lẻ cho khách quen');
select kt.ghi('041 Giảm giá sau giao xe được, hết nợ → hồ sơ tự đóng',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b9')) = 'dong'
  and (select con_no_khach from public.tien_ho_so((select v::bigint from ctx where k='hs_b9'))) = 0);
-- Gửi hồ sơ BH không trước ngày giao xe
insert into ctx select 'hs_b9bh', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-041.19','ten_khach','Khách B9 BH','dien_thoai','0909041019','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),
  'tinh_trang_xe','Trầy cửa','tu_van','Không','so_km',5000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_b9bh'), '[{"ten":"Sơn cửa","nhom":"son","gia_bao":1500000}]', 0.08);
select public.duyet_gia((select v::bigint from ctx where k='hs_b9bh'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b9bh')));
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_b9bh'), now() + interval '1 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b9bh')));
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b9bh')));
select public.them_tep((select v::bigint from ctx where k='hs_b9bh'), 'kcs', 'anh', 'TK/' || (select ma from public.ho_so where id=(select v::bigint from ctx where k='hs_b9bh')) || '/kcs-1.jpg');
select public.kcs((select v::bigint from ctx where k='hs_b9bh'), true);
select public.giao_xe((select v::bigint from ctx where k='hs_b9bh'), '{"cam_nhan_khach":"Tốt"}');
select kt.mong_loi('041 Ngày gửi hồ sơ BH trước ngày giao xe bị chặn', format($$select public.gui_ho_so_bh(%s, current_date - 3)$$, (select v from ctx where k='hs_b9bh')), 'trước ngày giao xe');
-- B10: hồ sơ bảo hành – phát sinh thêm hạng mục miễn phí; phát sinh không cần làm thêm
insert into ctx select 'hs_b10', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-038.06','ten_khach','Khách A6','dien_thoai','0909038006','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Đánh bóng bị loang','tu_van','Không','so_km',3100,'bat_buoc_km',true,'bo_qua_canh_bao',true,
  'loai','bao_hanh','ho_so_goc_id',(select v::bigint from ctx where k='hs_a6'),'hang_muc',jsonb_build_array(jsonb_build_object('ten','Đánh bóng lại','nhom','detailing')))))->>'id';
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_b10'), now() + interval '1 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DT')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b10')));
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b10')));
select public.bao_phat_sinh((select v::bigint from ctx where k='hs_b10'), 'Trầy thêm cửa sau');
select kt.mong_loi('041 Hồ sơ sửa chữa không thêm hạng mục bảo hành được', format($$select public.them_hang_muc_bao_hanh(%s, '[{"ten":"x"}]')$$, (select v from ctx where k='hs_b9bh')), 'Chỉ hồ sơ bảo hành');
insert into ctx select 'n_b10', public.them_hang_muc_bao_hanh((select v::bigint from ctx where k='hs_b10'), '[{"ten":"Đánh bóng cửa sau","nhom":"detailing"}]')::text;
select kt.ghi('041 Bảo hành: thêm hạng mục miễn phí (giá 0, đã duyệt), phát sinh đã xử lý, xe từ Chờ KCS về Đang sửa',
  (select v from ctx where k='n_b10') = '1'
  and (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b10')) = 'dang_sua'
  and exists (select 1 from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b10') and ten='Đánh bóng cửa sau' and trang_thai='duyet' and gia_duyet=0 and lan_bao_gia=1)
  and not exists (select 1 from public.phat_sinh where ho_so_id=(select v::bigint from ctx where k='hs_b10') and not da_xu_ly));
select public.bao_phat_sinh((select v::bigint from ctx where k='hs_b10'), 'Kiểm tra đèn');
select public.xu_ly_phat_sinh((select v::bigint from ctx where k='hs_b10'), 'Đèn không lỗi – không cần làm thêm');
select kt.ghi('041 Phát sinh không cần làm thêm: đánh dấu đã xử lý (ghi lý do), hết cảnh báo phát sinh',
  not exists (select 1 from public.phat_sinh where ho_so_id=(select v::bigint from ctx where k='hs_b10') and not da_xu_ly)
  and exists (select 1 from public.phat_sinh where ho_so_id=(select v::bigint from ctx where k='hs_b10') and xu_ly_ghi_chu like 'Đèn không lỗi%')
  and not exists (select 1 from public.v_canh_bao where loai='phat_sinh' and ho_so_id=(select v::bigint from ctx where k='hs_b10')));
-- Nhập "xuất ngay cho xe": giá vốn xe = giá lô vừa nhập, lô cũ còn nguyên
insert into ctx select 'hang_b5', public.luu_hang_kho('{"ma":"PT-B5","ten":"Ốp gương thử","nhom":"Phụ tùng","dvt":"Cái"}')::text;
select public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng ngoài'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_b5'),'so_luong',1,'don_gia',100000,'ty_le_vat',0))));
insert into ctx select 'pn_b5', public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng ngoài'),
  'ho_so_id',(select v::bigint from ctx where k='hs_b10'),'xuat_cho_xe',true,
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_b5'),'so_luong',1,'don_gia',150000,'ty_le_vat',0))))::text;
select kt.ghi('041 Nhập xuất ngay cho xe: giá vốn xe 150.000 (lô vừa nhập), lô cũ 100.000 còn trong kho',
  (select gia_von from public.v_phieu_xuat where id = ((select v::jsonb from ctx where k='pn_b5')->'phieu_xuat'->>'id')::bigint) = 150000
  and (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_b5')) = 1
  and (select gia_tri from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_b5')) = 100000);
select kt.mong_loi('041 Hủy phiếu nhập đã xuất ngay cho xe bị chặn', format($$select public.huy_phieu_nhap(%s, 'thử')$$, (select v::jsonb->>'id' from ctx where k='pn_b5')), 'hủy phiếu xuất đó trước');
-- B11: trưởng nhóm – không đọc giá vốn lô kho; tồn chỉ số lượng; đề xuất chỉ của tổ mình; không đổi tên khách
insert into ctx select 'dx_b11', (public.lap_de_xuat_vat_tu(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_b10'),'to_id','DT',
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_b5'),'so_luong',1)))))->>'id';
select kt.ghi('041 Giám đốc thấy giá trị tồn và đề xuất của mọi tổ',
  (select gia_tri from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_b5')) = 100000
  and exists (select 1 from public.v_de_xuat where id=(select v::bigint from ctx where k='dx_b11')));
select kt.dong_vai('han@gara.vn');
select kt.ghi('041 Trưởng nhóm không đọc được lô kho (giá vốn), tồn vẫn có số lượng, giá trị = 0',
  (select count(*) from public.lo_kho) = 0
  and (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_b5')) = 1
  and (select gia_tri from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_b5')) = 0);
select kt.ghi('041 Trưởng nhóm tổ DS không thấy đề xuất của tổ DT', not exists (select 1 from public.v_de_xuat where id=(select v::bigint from ctx where k='dx_b11'))
  and not exists (select 1 from public.v_de_xuat where to_id <> 'DS' and nguoi_lap <> (select id from public.nhan_vien where email='han@gara.vn')));
select public.ghi_dich_vu_nhanh('{"bien_so":"59C-123.45","ten_khach":"Tên Khác","dien_thoai":"0909555666","dich_vu":"Rửa xe","so_tien":50000,"so_km":12300,"to_id":"DT","bat_buoc_km":true}');
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('041 Trưởng nhóm ghi dịch vụ nhanh không đổi được tên khách', (select ten from public.khach_hang where dien_thoai='0909555666') = 'Chị Hoa');
-- B12: giám đốc không tự khóa mình; hủy hồ sơ đã thu cọc thì hỏi lại, Việc hôm nay nhắc trả cọc
select kt.mong_loi('041 Giám đốc không tự khóa tài khoản của mình', format($$select public.luu_nhan_vien(%L, '{"chi_nhanh_id":"TK","vai_tro":["giam_doc"],"hoat_dong":false}')$$,
  (select id from public.nhan_vien where email='thuan@gara.vn')), 'Không tự khóa');
insert into ctx select 'hs_b12', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-041.12','ten_khach','Khách B12','dien_thoai','0909041012','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Thay lốp','tu_van','Không','so_km',8000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_coc'),
  'so_tien',500000,'noi_dung','Cọc B12','phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_b12'),'so_tien',500000))));
select kt.mong_loi('041 Hủy hồ sơ đã thu cọc: hỏi lại (CANH_BAO)', format($$select public.huy_ho_so(%s, 'Khách đổi ý', false)$$, (select v from ctx where k='hs_b12')), 'CANH_BAO');
select public.huy_ho_so((select v::bigint from ctx where k='hs_b12'), 'Khách đổi ý', true);
select kt.ghi('041 Hủy xong: Việc hôm nay nhắc trả 500.000 đ tiền cọc',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b12')) = 'huy'
  and exists (select 1 from public.v_canh_bao where loai='coc_treo' and ho_so_id=(select v::bigint from ctx where k='hs_b12') and noi_dung like '%500.000 đ tiền cọc%'));
insert into ctx select 'hs_b12b', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-041.13','ten_khach','Khách B12b','dien_thoai','0909041013','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Thay lốp','tu_van','Không','so_km',8000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_coc'),
  'so_tien',200000,'noi_dung','Cọc B12b','phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_b12b'),'so_tien',200000))));
select public.huy_ho_so((select v::bigint from ctx where k='hs_b12b'), 'Giao diện cũ gọi 2 tham số');
select kt.ghi('041 Giao diện cũ (2 tham số) hủy được như trước', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b12b')) = 'huy');
insert into ctx select 'dn_b12', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where tinh_chat='tra_coc'),'so_tien',500000,'noi_dung','Trả cọc B12','ho_so_id',(select v::bigint from ctx where k='hs_b12')))::text;
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_b12'), true);
select public.chi_tien((select v::bigint from ctx where k='dn_b12'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.ghi('041 Trả lại cọc xong thì hết nhắc', not exists (select 1 from public.v_canh_bao where loai='coc_treo' and ho_so_id=(select v::bigint from ctx where k='hs_b12')));
-- Hủy dịch vụ nhanh lưu lý do
insert into ctx select 'dvn_b', public.ghi_dich_vu_nhanh('{"bien_so":"59C-123.45","dich_vu":"Bơm lốp","so_tien":30000,"so_km":12400,"to_id":"DMG","bat_buoc_km":true}')::text;
select kt.mong_loi('041 Hủy dịch vụ nhanh phải ghi lý do', format($$select public.huy_dich_vu_nhanh(%s, '  ')$$, (select v from ctx where k='dvn_b')), 'Ghi lý do');
select public.huy_dich_vu_nhanh((select v::bigint from ctx where k='dvn_b'), 'Ghi nhầm xe');
select kt.ghi('041 Hủy dịch vụ nhanh lưu lý do, người hủy, lúc hủy',
  (select ly_do_huy = 'Ghi nhầm xe' and huy_boi is not null and huy_luc is not null from public.dich_vu_nhanh where id=(select v::bigint from ctx where k='dvn_b'))
  and (select ly_do_huy from public.v_dich_vu_nhanh where id=(select v::bigint from ctx where k='dvn_b')) = 'Ghi nhầm xe');
select kt.mong_loi('041 Hủy lại lượt đã hủy bị chặn', format($$select public.huy_dich_vu_nhanh(%s, 'lần 2')$$, (select v from ctx where k='dvn_b')), 'đã hủy');
-- Đồ nghề: báo sự cố không trùng quá số; kiểm tra tuần bỏ qua món chưa nhận
insert into ctx select 'ts_b8', public.luu_tai_san('{"ten":"Kìm cắt B8","loai":"dung_cu","nhom_id":"DS","so_luong":2,"gia_mua":50000}')::text;
select kt.dong_vai('han@gara.vn');
select public.bao_su_co_tai_san(jsonb_build_object('tai_san_id',(select v::bigint from ctx where k='ts_b8'),'loai','mat','so_luong',1,'mo_ta','Không thấy'));
select public.bao_su_co_tai_san(jsonb_build_object('tai_san_id',(select v::bigint from ctx where k='ts_b8'),'loai','mat','so_luong',1,'mo_ta','Không thấy cái thứ hai'));
select kt.mong_loi('041 Báo mất quá số đang có (tính cả sự cố đang chờ) bị chặn',
  format($$select public.bao_su_co_tai_san(jsonb_build_object('tai_san_id',%s,'loai','mat','so_luong',1,'mo_ta','Báo lại'))$$, (select v from ctx where k='ts_b8')), 'đang chờ xử lý');
select kt.dong_vai('thuan@gara.vn');
insert into ctx select 'ts_b13', public.luu_tai_san('{"ten":"Máy mài B13","loai":"may_moc","nhom_id":"DS","gia_mua":900000}')::text;
select kt.ghi('041 Món mới giao đang chờ nhóm nhận', (select cho_nhan from public.tai_san where id=(select v::bigint from ctx where k='ts_b13')));
select kt.dong_vai('han@gara.vn');
insert into ctx select 'kt_b13', public.luu_kiem_tra_tai_san(jsonb_build_object('nhom_id','DS','loai','kiem_tra','dong',
  (select jsonb_agg(jsonb_build_object('tai_san_id', id, 'so_thuc', so_luong, 'so_hong', 0)) from public.tai_san
   where chi_nhanh_id='TK' and nhom_id='DS' and tinh_trang not in ('mat','thanh_ly','dang_sua') and so_luong > 0 and not cho_nhan)))::text;
select kt.ghi('041 Kiểm tra tuần không bắt kiểm món chưa nhận, không sinh sự cố "mất" cho món đó',
  (select v from ctx where k='kt_b13') is not null
  and not exists (select 1 from public.su_co_tai_san where tai_san_id=(select v::bigint from ctx where k='ts_b13')));
select kt.dong_vai('thuan@gara.vn');
-- Phiếu không ghi trước ngày đầu kỳ; danh mục đã dùng trong tháng chốt không đổi được; một tài khoản mặc định
select kt.dong_vai(null);
insert into public.tai_khoan_quy (chi_nhanh_id, ten, so_du_dau_ky, ngay_dau_ky) values ('TK', 'Quỹ thử 041', 0, date_trunc('month', current_date - interval '1 month')::date);
select kt.dong_vai('thuan@gara.vn');
select kt.mong_loi('041 Phiếu thu ghi trước ngày đầu kỳ của tài khoản bị chặn',
  $$select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Quỹ thử 041'),'muc_id',(select id from public.muc_thu_chi where ten='Thu khác'),
    'so_tien',10000,'ngay',(date_trunc('month', current_date - interval '1 month') - interval '1 day')::date,'noi_dung','Ghi lùi'))$$, 'trước ngày đầu kỳ');
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Quỹ thử 041'),'muc_id',(select id from public.muc_thu_chi where ten='Thu khác'),
  'so_tien',10000,'ngay',(date_trunc('month', current_date - interval '1 month') + interval '14 day')::date,'noi_dung','Thu khác tháng trước'));
select public.chot_thang((date_trunc('month', current_date) - interval '1 month')::date, true);
select kt.mong_loi('041 Mục thu chi đã có phiếu tháng chốt: không đổi nhóm/tính chất', $$update public.muc_thu_chi set tinh_chat = 'thu_noi_bo' where ten = 'Thu khác'$$, 'tháng đã chốt');
select kt.mong_loi('041 Tài khoản có phiếu tháng chốt: không đổi số dư đầu kỳ', $$update public.tai_khoan_quy set so_du_dau_ky = 1000 where ten = 'Quỹ thử 041'$$, 'tháng đã chốt');
select kt.mong_loi('041 Thuế suất áp dụng lùi vào tháng đã chốt bị chặn', $$insert into public.thue_suat_vat values ((date_trunc('month', current_date - interval '1 month') + interval '3 day')::date, 0.1)$$, 'tháng chốt');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '1 month')::date, 'Thử 041');
update public.tai_khoan_quy set mac_dinh = true where ten = 'Quỹ thử 041';
select kt.ghi('041 Đặt tài khoản mặc định mới → tài khoản mặc định cũ tự bỏ (mỗi chi nhánh một)',
  (select count(*) from public.tai_khoan_quy where chi_nhanh_id='TK' and mac_dinh) = 1
  and (select mac_dinh from public.tai_khoan_quy where ten='Quỹ thử 041'));
update public.tai_khoan_quy set mac_dinh = true where ten = 'Tiền mặt' and chi_nhanh_id = 'TK';
-- ===================== 042: kết quả kinh doanh chuyên nghiệp =====================
select kt.dong_vai('thuan@gara.vn');
-- Thu nhập khác: trạm sạc vào lãi lỗ, tiền bo của thợ thì không
select kt.ghi('042 Mặc định: Trạm sạc / Thu khác tính vào lãi lỗ; Tiền bo, Khách mua bảo hiểm thì không',
  (select bool_and(vao_lai_lo) from public.muc_thu_chi where loai='thu' and ten in ('Trạm sạc','Thu khác'))
  and not (select bool_or(vao_lai_lo) from public.muc_thu_chi where loai='thu' and ten in ('Tiền bo của khách','Khách mua bảo hiểm')));
insert into ctx select 'tk_042_truoc', (select thu_khac from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)::text;
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where loai='thu' and ten='Trạm sạc'),
  'so_tien',300000,'noi_dung','Trạm sạc tuần 2'));
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where loai='thu' and ten='Tiền bo của khách'),
  'so_tien',40000,'noi_dung','Khách bo thợ'));
select kt.ghi('042 Thu nhập khác tháng này tăng đúng 300.000 (trạm sạc), tiền bo không tính',
  (select thu_khac from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date) = (select v::numeric from ctx where k='tk_042_truoc') + 300000);
-- Hao hụt kiểm kê, VAT đầu vào hàng nhập
select kt.ghi('042 Hao hụt kiểm kê = giá vốn phiếu xuất kiểm kê thiếu − giá trị lô kiểm kê thừa của tháng',
  (select hao_hut from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  = coalesce((select sum(pd.gia_von) from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
              where px.loai = 'kiem_ke' and px.trang_thai = 'hieu_luc' and px.ngay >= date_trunc('month', current_date)), 0)
    - coalesce((select round(sum(so_luong * don_gia_von)) from public.lo_kho where kiem_ke_id is not null and ngay >= date_trunc('month', current_date)), 0));
select kt.ghi('042 VAT đầu vào gồm VAT hàng nhập kho (phiếu nhập) của tháng',
  (select vat_vao_hang from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  = (select coalesce(sum(tien_vat), 0) from public.phieu_nhap where trang_thai <> 'huy' and ngay >= date_trunc('month', current_date))
  and (select vat_vao_hang from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date) > 0);
select kt.ghi('042 Giảm giá giảm cả VAT đầu ra (theo tỷ lệ VAT của hồ sơ)',
  (select vat_ra from public.v_doanh_thu where nguon='giam_gia' and ho_so_id=(select v::bigint from ctx where k='hs_b9')) = -round(80000 * 80000.0 / 1080000));
-- Chi tiết từng ô khớp số báo cáo
select kt.ghi('042 Chi tiết ô (chi phí cố định, doanh thu khách, hao hụt, thu khác) cộng lại đúng số báo cáo',
  (select coalesce(sum(so_tien),0) from public.chi_tiet_kqkd(current_date, 'chi_co_dinh')) = (select chi_co_dinh from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  and (select coalesce(sum(so_tien),0) from public.chi_tiet_kqkd(current_date, 'doanh_thu_khach')) = (select doanh_thu_khach from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  and (select coalesce(sum(so_tien),0) from public.chi_tiet_kqkd(current_date, 'hao_hut')) = (select hao_hut from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  and (select coalesce(sum(so_tien),0) from public.chi_tiet_kqkd(current_date, 'thu_khac')) = (select thu_khac from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date));
select kt.ghi('042 VAT trong giá vốn = VAT của các lô (phiếu nhập có VAT) đã xuất trong tháng; chi tiết VAT đầu ra, VAT trong giá vốn, danh sách xe khớp báo cáo',
  (select vat_trong_gia_von from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
    = (select coalesce(sum(so_tien),0) from public.chi_tiet_kqkd(current_date, 'vat_trong_gia_von'))
  and (select vat_trong_gia_von from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date) > 0
  and abs((select vat_trong_gia_von from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
          - (select round(sum(xl.so_luong * xl.don_gia_von * pnd.ty_le_vat / (1 + pnd.ty_le_vat)))
             from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id join public.xuat_lo xl on xl.phieu_xuat_dong_id = pd.id
             join public.lo_kho l on l.id = xl.lo_id join public.phieu_nhap_dong pnd on pnd.id = l.phieu_nhap_dong_id
             where px.trang_thai = 'hieu_luc' and px.ngay >= date_trunc('month', current_date))) <= 5
  and (select coalesce(sum(so_tien),0) from public.chi_tiet_kqkd(current_date, 'vat_ra')) = (select vat_ra from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  and (select count(*) from public.chi_tiet_kqkd(current_date, 'so_xe')) = (select so_xe from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date),
  (select vat_trong_gia_von::text || ' / ' || vat_ra::text || ' / ' || so_xe::text from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date));
select kt.ghi('042 Lãi gộp theo tổ cộng lại đúng lãi gộp tháng; chi phí theo mục cộng lại đúng tổng chi phí',
  (select sum(doanh_thu - gia_von) from public.lai_gop_theo_to(date_trunc('month', current_date)::date, current_date)) = (select lai_gop from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  and (select sum(so_tien) from public.chi_phi_theo_muc(date_trunc('month', current_date)::date, current_date))
      = (select chi_gia_von + chi_van_hanh + chi_co_dinh from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date));
select kt.ghi('042 Doanh thu theo tháng (máy chủ cộng) khớp doanh thu báo cáo',
  (select tong from public.doanh_thu_theo_thang() where thang = date_trunc('month', current_date)::date) = (select doanh_thu from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date));
select kt.ghi('042 Tiền – công nợ – tồn kho hôm nay khớp sổ quỹ, tồn kho, công nợ hồ sơ',
  ((public.so_du_cuoi_thang(current_date))->>'ton_kho')::numeric = (select sum(gia_tri) from public.v_ton_kho where chi_nhanh_id='TK')
  and ((public.so_du_cuoi_thang(current_date))->>'so_du_quy')::numeric = (select sum(so_du) from public.v_so_du_quy where chi_nhanh_id='TK')
  and ((public.so_du_cuoi_thang(current_date))->>'phai_thu_khach')::numeric = (select sum(greatest(con_no_khach, 0)) from public.v_ho_so where chi_nhanh_id='TK' and trang_thai <> 'huy')
  and ((public.so_du_cuoi_thang(current_date))->>'phai_thu_bh')::numeric = (select sum(greatest(con_no_bh, 0)) from public.v_ho_so where chi_nhanh_id='TK' and trang_thai <> 'huy'),
  (public.so_du_cuoi_thang(current_date))::text);
-- Chốt lần lượt, mở lại từ tháng sau cùng, lịch sử mở lại, số chốt cố định
insert into ctx select 'dn_042', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Rác'),'so_tien',150000,
  'noi_dung','Rác 2 tháng trước','ky_chi_phi',(date_trunc('month', current_date) - interval '2 month')::date))::text;
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_042'), true);
select public.chi_tien((select v::bigint from ctx where k='dn_042'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.mong_loi('042 Chốt tháng trước khi tháng trước đó (có số liệu) chưa chốt bị chặn',
  $$select public.chot_thang((date_trunc('month', current_date) - interval '1 month')::date, true)$$, 'trước');
select public.chot_thang((date_trunc('month', current_date) - interval '2 month')::date, true);
insert into ctx select 'chot_042', public.chot_thang((date_trunc('month', current_date) - interval '1 month')::date, true)::text;
select kt.ghi('042 Số chốt có phiên bản 2 và tiền – công nợ – tồn kho cuối tháng',
  (select v::jsonb->>'phien_ban' from ctx where k='chot_042') = '2' and (select v::jsonb->'so_du' ? 'ton_kho' from ctx where k='chot_042'));
select kt.ghi('042 Vừa chốt: báo cáo hiện số chốt, không lệch',
  (select not lech_chot and trang_thai = 'da_chot' from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date));
select kt.dong_vai(null);
update public.bang_luong_thang set tong_luong = tong_luong + 1000 where thang = (date_trunc('month', current_date) - interval '1 month')::date;
insert into public.bang_luong_thang (chi_nhanh_id, thang, tong_luong)
select 'TK', (date_trunc('month', current_date) - interval '1 month')::date, 1000
where not exists (select 1 from public.bang_luong_thang where thang = (date_trunc('month', current_date) - interval '1 month')::date);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('042 Số liệu tháng đã chốt bị đổi (sửa thẳng CSDL): báo cáo vẫn hiện số chốt và báo lệch',
  (select lech_chot and lai_truoc_thue_song <> lai_truoc_thue from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date));
select kt.mong_loi('042 Mở lại tháng trước khi mở tháng sau bị chặn',
  $$select public.mo_lai_thang((date_trunc('month', current_date) - interval '2 month')::date, 'thử')$$, 'mở lại tháng đó trước');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '1 month')::date, 'Sửa lương');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '2 month')::date, 'Thử 042');
select kt.ghi('042 Mở lại lưu lịch sử (ai, lý do, số cũ)',
  (select count(*) from public.chot_thang_lich_su where ly_do in ('Sửa lương','Thử 042') and mo_lai_boi is not null and so_lieu is not null) = 2);
-- ===================== 043: rà soát lần 3 =====================
select kt.dong_vai('thuan@gara.vn');
-- A1: chốt tháng chưa nhập lương → hỏi lại (trước đây lỗi "malformed array literal")
select kt.mong_loi('043 Chốt tháng chưa nhập lương: hỏi lại "chưa nhập bảng lương" (không còn lỗi mảng)',
  format('select public.chot_thang(%L)', (date_trunc('month', current_date) - interval '2 month')::date), 'chưa nhập bảng lương');
select kt.ghi('043 Báo cáo tắt JIT (dữ liệu lớn không chậm vài giây)',
  (select bool_and(coalesce(proconfig, '{}') @> '{jit=off}') from pg_proc where proname in ('ket_qua_kinh_doanh','chot_thang','chi_tiet_kqkd','lai_gop_theo_to','so_du_cuoi_thang','doanh_thu_theo_thang')));

-- A2 + A6: hồ sơ BH có khấu trừ 2.000.000, cọc 1.000.000, hủy → khấu trừ về 0, nhắc trả đủ 1.000.000; trả lại không vượt số đang giữ
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs_r3a', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51G-043.01','ten_khach','Khách R3A','dien_thoai','0909043001','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),
  'tinh_trang_xe','Móp cửa','tu_van','Không','so_km',1000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_r3a'), '[{"ten":"Gò cửa","nhom":"dong","gia_bao":10000000}]', 0.08);
select public.duyet_gia_chia((select v::bigint from ctx where k='hs_r3a'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_r3a')), 2000000);
select kt.dong_vai('tien@gara.vn');
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_coc'),
  'so_tien',1000000,'noi_dung','Cọc R3A','phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_r3a'),'so_tien',1000000))));
select kt.dong_vai('duy@gara.vn');
select public.huy_ho_so((select v::bigint from ctx where k='hs_r3a'), 'Khách không sửa', true);
select kt.ghi('043 Hủy hồ sơ: khấu trừ về 0, hồ sơ giữ đúng 1.000.000 tiền cọc, Việc hôm nay nhắc đủ số',
  (select khau_tru_giam_tru = 0 and con_no_khach = -1000000 from public.v_ho_so where id=(select v::bigint from ctx where k='hs_r3a'))
  and exists (select 1 from public.v_canh_bao where loai='coc_treo' and ho_so_id=(select v::bigint from ctx where k='hs_r3a') and noi_dung like '%1.000.000 đ tiền cọc%'));
select kt.ghi('043 Số trả lại khách tối đa = số đang giữ',
  (select public.so_tien_tra_lai_khach((select v::bigint from ctx where k='hs_r3a'))->>'toi_da')::numeric = 1000000);
insert into ctx select 'dn_r3a1', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where tinh_chat='tra_coc'),'so_tien',600000,
  'noi_dung','Trả cọc R3A lần 1','ho_so_id',(select v::bigint from ctx where k='hs_r3a')))::text;
select kt.mong_loi('043 Đề nghị trả lại vượt số đang giữ (trừ đề nghị đang chờ) bị chặn', format($$select public.lap_de_nghi_chi(jsonb_build_object('muc_id',
  (select id from public.muc_thu_chi where tinh_chat='tra_coc'),'so_tien',600000,'noi_dung','Trả cọc lần 2','ho_so_id',%s))$$, (select v from ctx where k='hs_r3a')), 'tối đa 400.000');
insert into ctx select 'dn_r3a2', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where tinh_chat='tra_coc'),'so_tien',400000,
  'noi_dung','Trả cọc R3A lần 2','ho_so_id',(select v::bigint from ctx where k='hs_r3a')))::text;
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_r3a1'), true);
select public.duyet_de_nghi_chi((select v::bigint from ctx where k='dn_r3a2'), true);
select kt.dong_vai('tien@gara.vn');
select public.chi_tien((select v::bigint from ctx where k='dn_r3a1'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select public.chi_tien((select v::bigint from ctx where k='dn_r3a2'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'));
select kt.ghi('043 Trả lại đủ cọc: hết nhắc, hồ sơ hủy không còn giữ tiền',
  not exists (select 1 from public.v_canh_bao where ho_so_id=(select v::bigint from ctx where k='hs_r3a') and loai in ('coc_treo','tra_lai_thua'))
  and (select da_thu_khach from public.v_ho_so where id=(select v::bigint from ctx where k='hs_r3a')) = 0);
-- đề nghị cũ (lập trước 043) vượt số đang giữ: chi tiền bị chặn
select kt.dong_vai(null);
with x as (insert into public.de_nghi_chi (chi_nhanh_id, ngay, nguoi_de_nghi, muc_id, so_tien, noi_dung, ho_so_id, trang_thai)
  values ('TK', current_date, (select id from public.nhan_vien where email='duy@gara.vn'), (select id from public.muc_thu_chi where tinh_chat='tra_coc'), 500000,
          'Đề nghị cũ trả trùng', (select v::bigint from ctx where k='hs_r3a'), 'da_duyet') returning id)
insert into ctx select 'dn_r3a3', id::text from x;
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('043 Chi trả lại cọc khi hồ sơ không còn giữ tiền bị chặn', format($$select public.chi_tien(%s, (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'))$$,
  (select v from ctx where k='dn_r3a3')), 'chỉ còn giữ 0');

-- A3: đề nghị trả NCC vượt số còn nợ → hỏi lại; kho thấy đề nghị trả NCC của người khác
insert into ctx select 'no_vf', (select greatest(da_nhap + cho_khop - da_tra - dang_de_nghi, 0) from public.v_cong_no_ncc where ten='Phụ tùng VinFast' and chi_nhanh_id='TK')::text;
select kt.mong_loi('043 Đề nghị trả NCC vượt số còn nợ: hỏi lại (CANH_BAO)', format($$select public.lap_de_nghi_chi(jsonb_build_object('muc_id',
  (select id from public.muc_thu_chi where ten='Trả NCC – Phụ tùng VinFast'),'nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),
  'so_tien',%s,'noi_dung','Trả VinFast','bo_qua_canh_bao',false))$$, (select v::numeric + 1000000 from ctx where k='no_vf')), 'CANH_BAO');
select public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Trả NCC – Phụ tùng VinFast'),
  'nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Phụ tùng VinFast'),'so_tien',300000,'noi_dung','Trả VinFast một phần','bo_qua_canh_bao',true));
select kt.dong_vai('duy@gara.vn');
select kt.ghi('043 Vai kho thấy đề nghị chi trả NCC do kế toán lập (cột "đang đề nghị")',
  (select dang_de_nghi from public.v_cong_no_ncc where ten='Phụ tùng VinFast' and chi_nhanh_id='TK') >= 300000);

-- A4 + C14: dịch vụ nhanh – thu vượt / thu vào lượt đã hủy bị chặn; ghi trùng thì hỏi lại; có "còn phải thu"
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'dvn_r3', public.ghi_dich_vu_nhanh('{"bien_so":"59C-043.01","dich_vu":"Rửa xe","so_tien":80000,"so_km":5000,"to_id":"DT","bat_buoc_km":true}')::text;
select kt.mong_loi('043 Ghi dịch vụ nhanh trùng (cùng xe, ngày, dịch vụ): hỏi lại', $$select public.ghi_dich_vu_nhanh('{"bien_so":"59C-043.01","dich_vu":"rửa xe","so_tien":80000,"so_km":5000,"to_id":"DT","bat_buoc_km":true,"bo_qua_canh_bao":false}')$$, 'CANH_BAO');
select kt.ghi('043 Dịch vụ nhanh có cột "còn phải thu"', (select con_thu from public.v_dich_vu_nhanh where id=(select v::bigint from ctx where k='dvn_r3')) = 80000);
select kt.mong_loi('043 Thu dịch vụ nhanh vượt số còn phải thu bị chặn', format($$select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_dich_vu_nhanh'),'so_tien',800000,'phan_bo',jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id',%s,'so_tien',800000))))$$,
  (select v from ctx where k='dvn_r3')), 'vượt số còn phải thu');
select public.huy_dich_vu_nhanh((select v::bigint from ctx where k='dvn_r3'), 'Thử 043');
select kt.mong_loi('043 Thu tiền vào lượt dịch vụ đã hủy bị chặn', format($$select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_dich_vu_nhanh'),'so_tien',80000,'phan_bo',jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id',%s,'so_tien',80000))))$$,
  (select v from ctx where k='dvn_r3')), 'đã hủy');

-- F: chuyển quỹ cùng tài khoản / ngày tương lai; tiền bo đi cặp với phiếu khách trả
select kt.mong_loi('043 Chuyển quỹ cùng một tài khoản: báo tiếng Việt', $$select public.lap_phieu_chuyen(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'tai_khoan_den_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),'so_tien',1000))$$, 'phải khác nhau');
select kt.mong_loi('043 Chuyển quỹ ngày tương lai bị chặn', $$select public.lap_phieu_chuyen(jsonb_build_object('ngay', current_date + 3, 'tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'tai_khoan_den_id',(select id from public.tai_khoan_quy where ten like 'TK công ty%'),'so_tien',1000))$$, 'sau hôm nay');

-- B1: sửa khách trên hồ sơ không ghi đè khách dùng chung; sửa về SĐT đã có thì gắn sang khách đó
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs_b1a', (public.tiep_nhan_xe(jsonb_build_object('bien_so','51G-043.11','ten_khach','Ông A','dien_thoai','0909043011',
  'dong_xe_id',(select id from public.dong_xe where ten='VF3'),'nguon_tt','khach','tinh_trang_xe','Bảo dưỡng','tu_van','Không','so_km',2000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
insert into ctx select 'hs_b1b', (public.tiep_nhan_xe(jsonb_build_object('bien_so','51G-043.12','ten_khach','Ông A','dien_thoai','0909043011',
  'dong_xe_id',(select id from public.dong_xe where ten='VF3'),'nguon_tt','khach','tinh_trang_xe','Bảo dưỡng','tu_van','Không','so_km',3000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.sua_thong_tin_ho_so((select v::bigint from ctx where k='hs_b1b'), '{"ten_khach":"Bà B (chủ mới)","dien_thoai":"0909043012"}');
select kt.ghi('043 Đổi chủ trên hồ sơ xe 2: hồ sơ xe 1 vẫn là Ông A, xe 2 sang khách mới',
  (select ten_khach = 'Ông A' and dien_thoai = '0909043011' from public.v_ho_so where id=(select v::bigint from ctx where k='hs_b1a'))
  and (select ten_khach = 'Bà B (chủ mới)' and dien_thoai = '0909043012' from public.v_ho_so where id=(select v::bigint from ctx where k='hs_b1b'))
  and (select khach_hang_id from public.xe where bien_so='51G04312') = (select khach_hang_id from public.ho_so where id=(select v::bigint from ctx where k='hs_b1b')));
select public.sua_thong_tin_ho_so((select v::bigint from ctx where k='hs_b1b'), '{"dien_thoai":"0909043011"}');
select kt.ghi('043 Sửa về SĐT đã có của khách khác: hồ sơ gắn sang khách đó, không lỗi trùng',
  (select khach_hang_id from public.ho_so where id=(select v::bigint from ctx where k='hs_b1b')) = (select khach_hang_id from public.ho_so where id=(select v::bigint from ctx where k='hs_b1a')));

-- E12: giảm giá theo từng lần
select public.lap_bao_gia((select v::bigint from ctx where k='hs_b1a'), '[{"ten":"Bảo dưỡng","nhom":"phu_tung","gia_bao":2000000}]', 0.08);
select kt.dong_vai('long@gara.vn');
select public.duyet_giam_gia((select v::bigint from ctx where k='hs_b1a'), 100000, 'Khách quen');
select public.duyet_giam_gia((select v::bigint from ctx where k='hs_b1a'), 150000, 'Thêm do chờ lâu');
select kt.ghi('043 Giảm giá hai lần: lưu từng lần (100.000 + 50.000), doanh thu trừ đủ 150.000, tổng ở hồ sơ 150.000',
  (select count(*) = 2 and sum(so_tien) = 150000 and min(so_tien) = 50000 from public.giam_gia_lan where ho_so_id=(select v::bigint from ctx where k='hs_b1a'))
  and (select sum(so_tien) from public.v_doanh_thu where nguon='giam_gia' and ho_so_id=(select v::bigint from ctx where k='hs_b1a')) = -150000
  and (select giam_gia from public.ho_so where id=(select v::bigint from ctx where k='hs_b1a')) = 150000);
-- F: tiền bo đi cặp với phiếu khách trả: hủy phiếu chính thì phiếu tiền bo hủy theo
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'pt_bo', public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_khach' order by id limit 1),'so_tien',1000000,'tien_bo',100000,'noi_dung','Khách A trả + bo',
  'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_b1a'),'so_tien',900000))))::text;
select public.huy_phieu((select v::bigint from ctx where k='pt_bo'), 'Nhầm xe');
select kt.ghi('043 Hủy phiếu khách trả: phiếu tiền bo đi cặp hủy theo',
  (select trang_thai from public.phieu_thu_chi where phieu_doi_ung_id=(select v::bigint from ctx where k='pt_bo')) = 'huy');

-- B2 + B-nhỏ + C5: phát sinh chưa xử lý không sang KCS; KCS đạt cần ảnh chụp sau lần chưa đạt; đóng phần còn lại của đề xuất
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs_b2', (public.tiep_nhan_xe(jsonb_build_object('bien_so','51G-043.21','ten_khach','Khách B2','dien_thoai','0909043021',
  'dong_xe_id',(select id from public.dong_xe where ten='VF3'),'nguon_tt','khach','tinh_trang_xe','Sơn cản','tu_van','Không','so_km',4000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_b2'), '[{"ten":"Sơn cản sau","nhom":"son","gia_bao":1500000}]', 0.08);
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs_b2'), now() + interval '1 day',
  (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b2')));
select public.them_tep((select v::bigint from ctx where k='hs_b2'), 'kcs', 'anh', 'TK/' || (select ma from public.ho_so where id=(select v::bigint from ctx where k='hs_b2')) || '/kcs-1.jpg');
insert into ctx select 'dx_r3', (public.lap_de_xuat_vat_tu(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_b2'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_guong'),'so_luong',3)))))->>'id';
select public.bao_phat_sinh((select v::bigint from ctx where k='hs_b2'), 'Nứt đèn hậu');
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b2')));
select kt.ghi('043 Báo xong hạng mục cuối khi còn phát sinh chờ xử lý: chưa sang Chờ KCS',
  (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b2')) = 'dang_sua');
select public.xu_ly_phat_sinh((select v::bigint from ctx where k='hs_b2'), 'Đèn chỉ trầy, không cần thay');
select kt.ghi('043 Xử lý phát sinh xong (không làm thêm): sang Chờ KCS', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b2')) = 'cho_kcs');
select public.bao_phat_sinh((select v::bigint from ctx where k='hs_b2'), 'Phát hiện thêm vết trầy');
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('043 KCS đạt khi còn phát sinh chờ xử lý bị chặn', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs_b2')), 'phát sinh');
select kt.dong_vai('duy@gara.vn');
select public.xu_ly_phat_sinh((select v::bigint from ctx where k='hs_b2'), 'Đã đánh bóng trong hạng mục cũ');
select kt.dong_vai('long@gara.vn');
select public.kcs((select v::bigint from ctx where k='hs_b2'), false, 'Còn vết xoáy', array[(select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b2'))]);
select kt.dong_vai('duy@gara.vn');
select public.bao_xong_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b2')));
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('043 KCS đạt dùng lại ảnh chụp trước lần chưa đạt bị chặn', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs_b2')), 'sau khi làm lại');
select public.them_tep((select v::bigint from ctx where k='hs_b2'), 'kcs', 'anh', 'TK/' || (select ma from public.ho_so where id=(select v::bigint from ctx where k='hs_b2')) || '/kcs-2.jpg');
select public.kcs((select v::bigint from ctx where k='hs_b2'), true);
select kt.ghi('043 Có ảnh mới sau khi làm lại: KCS đạt', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b2')) = 'dat_kcs');
select kt.dong_vai('duy@gara.vn');
select public.dong_de_xuat_vat_tu((select v::bigint from ctx where k='dx_r3'), 'Xe đã KCS, không cần nữa');
select kt.ghi('043 Đóng phần còn lại của đề xuất: hết "chờ xuất", lưu lý do',
  (select trang_thai = 'da_xuat' and ly_do_dong is not null from public.v_de_xuat where id=(select v::bigint from ctx where k='dx_r3')));

-- B6: xóa dòng chờ duyệt cuối khi đã có dòng được duyệt → Đã duyệt giá (trước đây kẹt Chờ duyệt giá)
insert into ctx select 'hs_b6', (public.tiep_nhan_xe(jsonb_build_object('bien_so','51G-043.31','ten_khach','Khách B6','dien_thoai','0909043031',
  'dong_xe_id',(select id from public.dong_xe where ten='VF3'),'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'tinh_trang_xe','Móp','tu_van','Không','so_km',5000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_b6'), '[{"ten":"Gò cánh cửa","nhom":"dong","gia_bao":3000000},{"ten":"Sơn cánh cửa","nhom":"son","gia_bao":2000000}]', 0.08);
select public.duyet_gia((select v::bigint from ctx where k='hs_b6'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b6') and ten='Gò cánh cửa'));
select public.xoa_hang_muc((select id from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b6') and ten='Sơn cánh cửa'));
select kt.ghi('043 Xóa dòng chờ duyệt cuối: hồ sơ sang Đã duyệt giá', (select trang_thai from public.ho_so where id=(select v::bigint from ctx where k='hs_b6')) = 'da_duyet');

-- B4: xe bảo hiểm mà phần bảo hiểm 0 đ (khách chi trả toàn bộ): không có bước gửi hồ sơ BH
insert into ctx select 'hs_b4', (public.tiep_nhan_xe(jsonb_build_object('bien_so','51G-043.41','ten_khach','Khách B4','dien_thoai','0909043041',
  'dong_xe_id',(select id from public.dong_xe where ten='VF3'),'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'tinh_trang_xe','Trầy','tu_van','Không','so_km',6000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs_b4'), '[{"ten":"Đánh bóng","nhom":"son","gia_bao":1000000}]', 0.08);
select public.duyet_gia_chia((select v::bigint from ctx where k='hs_b4'), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs_b4')), 1080000);
select kt.dong_vai(null);
update public.ho_so set trang_thai = 'da_giao', giao_luc = now() - interval '6 days' where id = (select v::bigint from ctx where k='hs_b4');
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('043 BH chi trả 0 đ: giao xe xong không giao kế toán gửi hồ sơ BH, không nhắc "chưa gửi hồ sơ"',
  (select nguoi_tiep_theo is distinct from (select id from public.nhan_vien where email='tien@gara.vn') from public.ho_so where id=(select v::bigint from ctx where k='hs_b4'))
  and not exists (select 1 from public.v_canh_bao where loai='chua_gui_ho_so' and ho_so_id=(select v::bigint from ctx where k='hs_b4')));

-- Chuyển phần chia của phiếu BH sang đúng xe (cả khi tháng của phiếu đã chốt); B3 chia lại công nợ không dưới số BH đã trả
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs_c1', (public.tiep_nhan_xe(jsonb_build_object('bien_so','51G-043.51','ten_khach','Khách C1','dien_thoai','0909043051',
  'dong_xe_id',(select id from public.dong_xe where ten='VF3'),'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'tinh_trang_xe','Móp','tu_van','Không','so_km',7000,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
insert into ctx select 'hs_c2', (public.tiep_nhan_xe(jsonb_build_object('bien_so','51G-043.52','ten_khach','Khách C2','dien_thoai','0909043052',
  'dong_xe_id',(select id from public.dong_xe where ten='VF3'),'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'tinh_trang_xe','Móp','tu_van','Không','so_km',7100,'bat_buoc_km',true,'bo_qua_canh_bao',true)))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k=x), '[{"ten":"Gò","nhom":"dong","gia_bao":2000000}]', 0.08) from unnest(array['hs_c1','hs_c2']) x;
select public.duyet_gia((select v::bigint from ctx where k=x), current_date,
  (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k=x))) from unnest(array['hs_c1','hs_c2']) x;
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'pt_c', public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'muc_id',(select id from public.muc_thu_chi where ten='Bảo hiểm thanh toán'),'hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'so_tien',1500000,
  'phan_bo',jsonb_build_array(jsonb_build_object('ho_so_id',(select v::bigint from ctx where k='hs_c1'),'so_tien',1000000))))::text;
select kt.ghi('043 Tiền BH đã về chưa chia: số dư cuối tháng tách riêng, Việc hôm nay ghi đủ ngày tháng năm',
  ((public.so_du_cuoi_thang(current_date))->>'bh_chua_chia')::numeric = (select sum(con_chua_chia) from public.v_phieu_thu_chi where chi_nhanh_id='TK')
  and ((public.so_du_cuoi_thang(current_date))->>'bh_chua_chia')::numeric >= 500000
  and exists (select 1 from public.v_canh_bao where loai='thu_chua_phan_bo' and noi_dung like '%' || to_char(current_date, 'DD/MM/YYYY') || '%'));
select kt.dong_vai(null);
update public.phieu_thu_chi set ngay = (date_trunc('month', current_date) - interval '1 day')::date where id = (select v::bigint from ctx where k='pt_c');

-- A5 + F: chi hộ (phiếu chi kỳ tháng trước, phiếu thu đối ứng hôm nay); chi phí kỳ đã chốt ghi vào tháng đang mở
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'dn_r3n1', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Nước'),'so_tien',300000,
  'noi_dung','Nước tháng trước (043)','ky_chi_phi',(date_trunc('month', current_date) - interval '1 month')::date))::text;
insert into ctx select 'dn_r3n2', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Nước'),'so_tien',200000,
  'noi_dung','Nước tháng trước – hóa đơn 2 (043)','ky_chi_phi',(date_trunc('month', current_date) - interval '1 month')::date))::text;
select kt.dong_vai('thuan@gara.vn');
select public.duyet_de_nghi_chi((select v::bigint from ctx where k=x), true) from unnest(array['dn_r3n1','dn_r3n2']) x;
select kt.dong_vai('tien@gara.vn');
insert into ctx select 'pc_r3', public.chi_tien((select v::bigint from ctx where k='dn_r3n1'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'), current_date,
  (select id from public.don_vi_lien_quan where ten='PHI'))::text;
select kt.dong_vai('thuan@gara.vn');
select public.chot_thang((date_trunc('month', current_date) - interval '2 month')::date, true);
select public.chot_thang((date_trunc('month', current_date) - interval '1 month')::date, true);
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('043 Hủy phiếu thu đối ứng (hôm nay) khi phiếu chi hộ đi cặp thuộc kỳ đã chốt bị chặn', format($$select public.huy_phieu(%s, 'thử')$$,
  (select phieu_doi_ung_id from public.phieu_thu_chi where id=(select v::bigint from ctx where k='pc_r3'))), 'đã chốt sổ');
insert into ctx select 'pc_r3b', public.chi_tien((select v::bigint from ctx where k='dn_r3n2'), (select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'))::text;
select kt.ghi('043 Chi đề nghị có kỳ chi phí đã chốt: ghi vào tháng đang mở, nội dung ghi rõ',
  (select ky_chi_phi = date_trunc('month', current_date)::date and noi_dung like '%đã chốt sổ%' from public.phieu_thu_chi where id=(select v::bigint from ctx where k='pc_r3b'))
  and (select not lech_chot from public.ket_qua_kinh_doanh() where thang = (date_trunc('month', current_date) - interval '1 month')::date));
select public.chuyen_phan_bo((select v::bigint from ctx where k='pt_c'), (select v::bigint from ctx where k='hs_c1'), (select v::bigint from ctx where k='hs_c2'), 1000000, 'Chia nhầm xe');
select kt.ghi('043 Phiếu BH tháng đã chốt chia nhầm xe: chuyển sang đúng xe được, tiền phiếu không đổi',
  (select da_thu_bh from public.v_ho_so where id=(select v::bigint from ctx where k='hs_c1')) = 0
  and (select da_thu_bh from public.v_ho_so where id=(select v::bigint from ctx where k='hs_c2')) = 1000000
  and (select so_tien from public.phieu_thu_chi where id=(select v::bigint from ctx where k='pt_c')) = 1500000);
select kt.mong_loi('043 Chia lại công nợ làm phần BH nhỏ hơn số BH đã trả bị chặn', format($$select public.sua_chia_cong_no(%s, 1700000)$$, (select v from ctx where k='hs_c2')), 'Bảo hiểm đã trả');
select kt.dong_vai('thuan@gara.vn');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '1 month')::date, 'Thử 043');
select public.mo_lai_thang((date_trunc('month', current_date) - interval '2 month')::date, 'Thử 043');

-- F: quản lý chung duyệt đề nghị tách nhỏ (cùng người, cùng mục, 3 ngày, cộng vượt hạn mức) bị chặn
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'dn_tach1', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Văn phòng phẩm'),'so_tien',1500000,'noi_dung','Giấy in'))::text;
insert into ctx select 'dn_tach2', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Văn phòng phẩm'),'so_tien',1500000,'noi_dung','Mực in','ngay','2027-05-01'))::text;
select kt.ghi('043 Ngày đề nghị lấy hôm nay ở máy chủ (ô Ngày gửi lên bị bỏ qua)', (select ngay from public.de_nghi_chi where id=(select v::bigint from ctx where k='dn_tach2')) = current_date);
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('043 Quản lý chung duyệt đề nghị nghi tách nhỏ bị chặn (giám đốc duyệt)', format($$select public.duyet_de_nghi_chi(%s, true)$$, (select v from ctx where k='dn_tach1')), 'tách nhỏ');
-- F: đề nghị chi hoa hồng GDV khi hồ sơ chưa ghi hoa hồng → hỏi lại
select kt.dong_vai('tien@gara.vn');
select kt.mong_loi('043 Đề nghị chi hoa hồng khi hồ sơ chưa ghi hoa hồng: hỏi lại', format($$select public.lap_de_nghi_chi(jsonb_build_object('muc_id',
  (select id from public.muc_thu_chi where tinh_chat='tra_hoa_hong' order by id limit 1),'so_tien',200000,'noi_dung','HH','ho_so_id',%s,
  'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),'bo_qua_canh_bao',false))$$, (select v from ctx where k='hs_c2')), 'chưa ghi hoa hồng');

-- A8 + F: nợ nội bộ chỉ tính từ ngày đầu kỳ của đơn vị; phiếu trước ngày đầu kỳ bị chặn; tài khoản quỹ không dời ngày đầu kỳ qua phiếu, có lịch sử
select kt.dong_vai('thuan@gara.vn');
select kt.mong_loi('044 Dời ngày đầu kỳ đơn vị liên quan qua phiếu đã ghi bị chặn', $$update public.don_vi_lien_quan set ngay_dau_ky = current_date + 1 where ten = 'PHI'$$, 'không dời');
select kt.dong_vai(null);
alter table public.don_vi_lien_quan disable trigger don_vi_lien_quan_chan_doi;
update public.don_vi_lien_quan set ngay_dau_ky = current_date + 1 where ten = 'PHI';
alter table public.don_vi_lien_quan enable trigger don_vi_lien_quan_chan_doi;
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('043 Nợ nội bộ: phiếu trước ngày đầu kỳ của đơn vị không cộng nữa',
  (select da_chi = 0 and da_thu = 0 from public.v_cong_no_noi_bo where ten = 'PHI' and chi_nhanh_id = 'TK'));
select kt.mong_loi('043 Phiếu gắn đơn vị trước ngày đầu kỳ của đơn vị bị chặn', $$select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Tiền mặt' and chi_nhanh_id='TK'),
  'muc_id',(select id from public.muc_thu_chi where tinh_chat='thu_noi_bo' order by id limit 1),'so_tien',1000,'don_vi_lien_quan_id',(select id from public.don_vi_lien_quan where ten='PHI')))$$, 'ngày đầu kỳ');
update public.don_vi_lien_quan set ngay_dau_ky = null where ten = 'PHI';
-- 044: nợ đầu kỳ thuộc một chi nhánh – chi nhánh khác không cộng lặp; kỳ chi phí theo ô Ngày của giao diện cũ
update public.don_vi_lien_quan set so_du_dau_ky = 7000000 where ten = 'PHI';
select kt.dong_vai(null);
update public.don_vi_lien_quan set chi_nhanh_id = 'TK' where chi_nhanh_id is null;   -- đơn vị tạo bằng SQL trực tiếp
insert into public.chi_nhanh (id, ten) values ('B44', 'Chi nhánh thử 044') on conflict do nothing;
select kt.ghi('044 Nợ đầu kỳ nội bộ chỉ tính ở chi nhánh giữ nợ',
  ((app.so_du_cuoi_thang('B44', current_date))->>'no_noi_bo_rong')::numeric = 0
  and ((app.so_du_cuoi_thang('TK', current_date))->>'no_noi_bo_rong')::numeric <> 0);
delete from public.chi_nhanh where id = 'B44';
select kt.dong_vai('thuan@gara.vn');
update public.don_vi_lien_quan set so_du_dau_ky = 0 where ten = 'PHI';
insert into ctx select 'dn_044', public.lap_de_nghi_chi(jsonb_build_object('muc_id',(select id from public.muc_thu_chi where ten='Nước'),'so_tien',10000,
  'noi_dung','Nước – giao diện cũ gửi ngày','ngay',(date_trunc('month', current_date) - interval '1 day')::date))::text;
select kt.ghi('044 Giao diện cũ gửi ô Ngày tháng trước: kỳ chi phí = tháng trước, ngày đề nghị = hôm nay',
  (select ky_chi_phi = (date_trunc('month', current_date) - interval '1 month')::date and ngay = current_date from public.de_nghi_chi where id = (select v::bigint from ctx where k='dn_044')));
insert into public.tai_khoan_quy (chi_nhanh_id, ten, so_du_dau_ky, ngay_dau_ky) values ('TK', 'Quỹ thử 043', 0, current_date - 10);
select public.lap_phieu_thu(jsonb_build_object('tai_khoan_id',(select id from public.tai_khoan_quy where ten='Quỹ thử 043'),'ngay',current_date - 5,
  'muc_id',(select id from public.muc_thu_chi where ten='Trạm sạc'),'so_tien',50000,'noi_dung','Thử 043'));
select kt.mong_loi('043 Dời ngày đầu kỳ tài khoản qua ngày của phiếu đã ghi bị chặn', $$update public.tai_khoan_quy set ngay_dau_ky = current_date where ten = 'Quỹ thử 043'$$, 'không dời');
update public.tai_khoan_quy set so_du_dau_ky = 20000 where ten = 'Quỹ thử 043';
select kt.ghi('043 Tài khoản quỹ: lưu lịch sử đổi số dư đầu kỳ (người, lúc, cũ → mới)',
  exists (select 1 from public.tai_khoan_quy_lich_su l join public.tai_khoan_quy t on t.id = l.tai_khoan_id
          where t.ten = 'Quỹ thử 043' and l.so_du_cu = 0 and l.so_du_moi = 20000 and l.sua_boi is not null));
update public.tai_khoan_quy set hoat_dong = false where ten = 'Quỹ thử 043';

-- E1: "vào lãi lỗ" chỉ cho mục thu "thu khác"
update public.muc_thu_chi set vao_lai_lo = true where ten = 'Bảo hiểm thanh toán';
select kt.ghi('043 Tích "vào lãi lỗ" cho mục bảo hiểm trả: tự bỏ (tránh doanh thu tính hai lần)',
  not (select vao_lai_lo from public.muc_thu_chi where ten = 'Bảo hiểm thanh toán'));
-- E2: VAT còn được khấu trừ chuyển sang tháng sau
select kt.ghi('043 VAT: phải nộp sau khấu trừ không âm; khấu trừ chuyển kỳ khớp từng tháng',
  not exists (select 1 from public.ket_qua_kinh_doanh() where vat_nop_sau_khau_tru < 0 or vat_khau_tru_ky_truoc < 0)
  and not exists (select 1 from (select thang, vat_phai_nop, vat_khau_tru_ky_truoc, vat_nop_sau_khau_tru,
                                       lead(vat_khau_tru_ky_truoc) over (order by thang) as tiep from public.ket_qua_kinh_doanh()) x
                  where tiep is not null and vat_nop_sau_khau_tru - vat_phai_nop + vat_khau_tru_ky_truoc <> tiep));
-- E7: bình quân một xe: tử số = giá duyệt của chính các xe tính trong tháng
select kt.ghi('043 Giá trị xe mới của tháng = tổng giá duyệt các xe đếm trong tháng',
  (select gia_tri_xe_moi from public.ket_qua_kinh_doanh() where thang = date_trunc('month', current_date)::date)
  = (select coalesce(sum(so_tien), 0) from public.chi_tiet_kqkd(current_date, 'so_xe')));
-- E9: vật tư "xuất ngay" cho xe tính vào tổ làm xe đó, không dồn vào "Chung"
select kt.dong_vai(null);
select kt.ghi('043 Phiếu xuất ngay cho xe (không qua đề xuất) có tổ',
  (select bool_and(app.to_cua_phieu_xuat(px.id) is not null) from public.phieu_xuat px where px.loai = 'cho_xe' and px.de_xuat_id is null and px.trang_thai = 'hieu_luc'));

-- C: kho
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hang_r3', public.luu_hang_kho('{"ma":"VT-043","ten":"Băng keo 043","nhom":"Vật tư phụ","dvt":"Cuộn"}')::text;
insert into ctx select 'pn_r3', (public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Wurth'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_r3'),'so_luong',10,'don_gia',100000,'ty_le_vat',0.08)))))->>'id';
insert into ctx select 'px_r3', (public.xuat_dung_chung(('{"ghi_chu":"Dán xưởng","dong":[{"hang_id":' || (select v from ctx where k='hang_r3') || ',"so_luong":2}]}')::jsonb))->>'id';
select kt.dong_vai('tien@gara.vn');
select public.dieu_chinh_phieu_nhap((select v::bigint from ctx where k='pn_r3'),
  jsonb_build_array(jsonb_build_object('dong_id',(select id from public.phieu_nhap_dong where phieu_id=(select v::bigint from ctx where k='pn_r3')),'don_gia',110000)), 'Hóa đơn ghi 110.000');
select kt.ghi('043 Điều chỉnh giá phiếu nhập chưa khớp: tổng phiếu, lô trong kho, giá vốn phần đã xuất cập nhật theo',
  (select tong_tien from public.phieu_nhap where id=(select v::bigint from ctx where k='pn_r3')) = 1188000
  and (select sum(gia_von) from public.phieu_xuat_dong where phieu_id=(select v::bigint from ctx where k='px_r3')) = 237600
  and (select gia_tri from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_r3')) = 950400);
select kt.dong_vai('duy@gara.vn');
-- C1: đếm 8 (đúng sổ lúc đếm), sau đó xuất thêm 1 rồi mới chốt → tồn 7 (trước đây tự thêm lô "thừa 1")
insert into ctx select 'kk_r3', (public.tao_kiem_ke(jsonb_build_object('pham_vi','chon','hang_ids',jsonb_build_array((select v::bigint from ctx where k='hang_r3')))))->>'id';
select public.luu_dem_kiem_ke((select v::bigint from ctx where k='kk_r3'),
  (select jsonb_agg(jsonb_build_object('dong_id',id,'ton_thuc_te',8)) from public.kiem_ke_dong where kiem_ke_id=(select v::bigint from ctx where k='kk_r3')));
select public.xuat_dung_chung(('{"ghi_chu":"Dán xưởng 2","dong":[{"hang_id":' || (select v from ctx where k='hang_r3') || ',"so_luong":1}]}')::jsonb);
select public.chot_kiem_ke((select v::bigint from ctx where k='kk_r3'));
select kt.ghi('043 Kiểm kê: xuất sau lúc đếm không thành "thừa" – tồn đúng 7, không có lô kiểm kê',
  (select ton from public.v_ton_kho where id=(select v::bigint from ctx where k='hang_r3')) = 7
  and not exists (select 1 from public.lo_kho where kiem_ke_id=(select v::bigint from ctx where k='kk_r3')));
-- C17: mã còn tồn không ngừng dùng được
select kt.mong_loi('043 Mã còn tồn không tắt "Đang dùng" được', format($$select public.luu_hang_kho(jsonb_build_object('id',%s,'ma','VT-043','ten','Băng keo 043','dvt','Cuộn','hoat_dong',false))$$,
  (select v from ctx where k='hang_r3')), 'còn tồn');
-- C3: phiếu nhập theo đề nghị mua: cùng nhà cung cấp, không vượt số lượng đã duyệt; C2: đề nghị từ đề xuất không "xuất ngay"
insert into ctx select 'dm_r3', (public.lap_de_nghi_mua(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Masuma'),
  'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_r3'),'so_luong',2,'don_gia',100000,'ty_le_vat',0.08)))))->>'id';
select kt.dong_vai(null);
update public.de_nghi_mua_dong set de_xuat_dong_id = (select id from public.de_xuat_dong where de_xuat_id=(select v::bigint from ctx where k='dx_r3') limit 1)
where de_nghi_id = (select v::bigint from ctx where k='dm_r3');
update public.de_xuat_vat_tu set trang_thai = 'cho_xuat' where id = (select v::bigint from ctx where k='dx_r3');
select kt.dong_vai('long@gara.vn');
select public.duyet_de_nghi_mua((select v::bigint from ctx where k='dm_r3'), true);
select kt.dong_vai('duy@gara.vn');
select kt.mong_loi('043 Phiếu nhập theo đề nghị mua khác nhà cung cấp bị chặn', format($$select public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Wurth'),
  'de_nghi_mua_id',%s,'dong',jsonb_build_array(jsonb_build_object('hang_id',%s,'so_luong',2,'don_gia',100000,'ty_le_vat',0.08))))$$, (select v from ctx where k='dm_r3'), (select v from ctx where k='hang_r3')), 'cùng nhà cung cấp');
select kt.mong_loi('043 Phiếu nhập vượt số lượng đề nghị đã duyệt bị chặn', format($$select public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Masuma'),
  'de_nghi_mua_id',%s,'dong',jsonb_build_array(jsonb_build_object('hang_id',%s,'so_luong',20,'don_gia',100000,'ty_le_vat',0.08))))$$, (select v from ctx where k='dm_r3'), (select v from ctx where k='hang_r3')), 'vượt số đã duyệt');
select kt.mong_loi('043 Đề nghị mua lập từ đề xuất: không "xuất ngay" cho xe', format($$select public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Masuma'),
  'de_nghi_mua_id',%s,'ho_so_id',%s,'xuat_cho_xe',true,'dong',jsonb_build_array(jsonb_build_object('hang_id',%s,'so_luong',2,'don_gia',100000,'ty_le_vat',0.08))))$$,
  (select v from ctx where k='dm_r3'), (select v from ctx where k='hs_b2'), (select v from ctx where k='hang_r3')), 'lập từ phiếu đề xuất');
insert into ctx select 'pn_r3b', (public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Masuma'),
  'de_nghi_mua_id',(select v::bigint from ctx where k='dm_r3'),'dong',jsonb_build_array(jsonb_build_object('hang_id',(select v::bigint from ctx where k='hang_r3'),'so_luong',2,'don_gia',100000,'ty_le_vat',0.08)))))->>'id';
select public.huy_phieu_nhap((select v::bigint from ctx where k='pn_r3b'), 'Thử 043');
select kt.ghi('043 Hủy phiếu nhập theo đề nghị sinh từ đề xuất: dòng đề xuất trở lại "chờ mua"',
  (select bool_and(cho_mua) from public.de_xuat_dong where id in (select de_xuat_dong_id from public.de_nghi_mua_dong where de_nghi_id=(select v::bigint from ctx where k='dm_r3'))));
select kt.mong_loi('043 Phiếu nhập từ 5 triệu không theo đề nghị mua: hỏi lại', format($$select public.lap_phieu_nhap(jsonb_build_object('nha_cung_cap_id',(select id from public.nha_cung_cap where ten='Wurth'),
  'bo_qua_canh_bao',false,'dong',jsonb_build_array(jsonb_build_object('hang_id',%s,'so_luong',60,'don_gia',100000,'ty_le_vat',0.08))))$$, (select v from ctx where k='hang_r3')), 'CANH_BAO');
-- C6: thiết bị – thanh lý đóng sự cố chờ; món đã thanh lý không "sửa xong" được; ghi sửa chữa không tự đóng sự cố hỏng
select kt.dong_vai('thuan@gara.vn');
insert into ctx select 'ts_r3', public.luu_tai_san('{"ten":"Máy hàn 043","loai":"may_moc","nhom_id":"DS","gia_mua":3000000}')::text;
insert into ctx select 'ts_r3b', public.luu_tai_san('{"ten":"Máy mài 043","loai":"may_moc","nhom_id":"DS","gia_mua":2000000}')::text;
select kt.dong_vai(null);
insert into public.su_co_tai_san (chi_nhanh_id, tai_san_id, loai, so_luong, mo_ta) select 'TK', (select v::bigint from ctx where k=x), 'hong', 1, 'Hỏng 043' from unnest(array['ts_r3','ts_r3b']) x;
update public.tai_san set tinh_trang = 'hong' where id in ((select v::bigint from ctx where k='ts_r3'), (select v::bigint from ctx where k='ts_r3b'));
select kt.dong_vai('thuan@gara.vn');
select public.thanh_ly_tai_san((select v::bigint from ctx where k='ts_r3'), 'Hỏng không sửa được');
select kt.ghi('043 Thanh lý: sự cố chờ xử lý của món đó tự đóng',
  not exists (select 1 from public.su_co_tai_san where tai_san_id=(select v::bigint from ctx where k='ts_r3') and trang_thai='cho_xu_ly'));
select kt.dong_vai(null);
with x as (insert into public.su_co_tai_san (chi_nhanh_id, tai_san_id, loai, so_luong, mo_ta)
  values ('TK', (select v::bigint from ctx where k='ts_r3'), 'hong', 1, 'Sự cố cũ') returning id)
insert into ctx select 'sc_r3', id::text from x;
select kt.dong_vai('thuan@gara.vn');
select kt.mong_loi('043 Món đã thanh lý không ghi "Đã sửa xong" được', format($$select public.xu_ly_su_co_tai_san(jsonb_build_object('id',%s,'ket_qua','da_sua'))$$, (select v from ctx where k='sc_r3')), 'thanh lý');
select public.ghi_bao_duong(jsonb_build_object('tai_san_id',(select v::bigint from ctx where k='ts_r3b'),'loai','sua_chua','noi_dung','Thay chổi than','xong',true));
select kt.ghi('043 Ghi sửa chữa xong: máy dùng lại được, sự cố hỏng vẫn chờ giám đốc / quản lý chung xử lý',
  (select tinh_trang from public.tai_san where id=(select v::bigint from ctx where k='ts_r3b')) = 'tot'
  and exists (select 1 from public.su_co_tai_san where tai_san_id=(select v::bigint from ctx where k='ts_r3b') and trang_thai='cho_xu_ly'));
-- C20: tổ chỉ gắn cho trưởng nhóm
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["ke_toan"],"to_id":"DS"}') from public.nhan_vien where email='tien@gara.vn';
select kt.ghi('043 Tài khoản không phải trưởng nhóm không giữ tổ', (select to_id from public.nhan_vien where email='tien@gara.vn') is null);

-- D: phân quyền
select kt.dong_vai('duy@gara.vn');
select kt.ghi('043 CVDV/kho không đọc được nợ đầu kỳ nội bộ; vẫn có tên đơn vị để chọn',
  (select count(*) from public.don_vi_lien_quan) = 0 and (select count(*) from public.v_don_vi_lien_quan) > 0
  and not exists (select 1 from information_schema.columns where table_name = 'v_don_vi_lien_quan' and column_name = 'so_du_dau_ky'));
select kt.dong_vai(null);
insert into storage.buckets (id, name) values ('ho-so-xe', 'ho-so-xe') on conflict do nothing;
insert into storage.objects (bucket_id, name) values ('ho-so-xe', 'TK/tai-san/TB-043/a.jpg'), ('ho-so-xe', 'TK/kho/PN-043/hoa-don.jpg'), ('ho-so-xe', 'TK/TK-2610-043/tiep_nhan-cccd.jpg');
select kt.dong_vai('han@gara.vn');
select kt.ghi('043 Trưởng nhóm chỉ đọc ảnh thiết bị (thư mục tai-san), không đọc hóa đơn NCC, giấy tờ khách',
  (select count(*) from storage.objects where name like '%043%') = 1 and exists (select 1 from storage.objects where name = 'TK/tai-san/TB-043/a.jpg'));
select kt.ghi('043 Trưởng nhóm đọc bảng đề xuất gốc: chỉ phiếu của tổ mình hoặc mình lập',
  exists (select 1 from public.de_xuat_vat_tu where to_id = 'DS')
  and not exists (select 1 from public.de_xuat_vat_tu where to_id is distinct from 'DS' and nguoi_lap <> (select id from public.nhan_vien where email='han@gara.vn'))
  and not exists (select 1 from public.de_xuat_dong dd join public.de_xuat_vat_tu d on d.id = dd.de_xuat_id where d.to_id is distinct from 'DS'));
select kt.dong_vai(null);
insert into public.chi_nhanh (id, ten) values ('BT', 'Bình Thạnh (thử 043)') on conflict do nothing;
insert into public.chot_thang (chi_nhanh_id, thang, so_lieu) values ('BT', date_trunc('month', current_date - interval '3 month')::date, '{"doanh_thu": 1}');
select kt.dong_vai('codong@gara.vn');
select kt.ghi('043 Báo cáo cổ đông chỉ trả chi nhánh người xem được xem', not exists (select 1 from public.bao_cao_co_dong() where chi_nhanh_id = 'BT'));
select kt.dong_vai(null);
delete from public.chot_thang where chi_nhanh_id = 'BT';
delete from public.chi_nhanh where id = 'BT';
select kt.ghi('043 Không ai ghi thẳng nhật ký xuất file', not has_table_privilege('authenticated', 'public.nhat_ky_xuat_file', 'INSERT')
  and not has_table_privilege('anon', 'public.v_cong_no_noi_bo', 'SELECT'));
select kt.dong_vai(null);

-- ---------------------------------------------------------------------
-- 045: chi nhánh Phan Huy Ích + giám đốc chuyển chi nhánh làm việc
-- ---------------------------------------------------------------------
select kt.ghi('045 Có chi nhánh PHI (đang hoạt động) và tài khoản Tiền mặt mặc định của PHI',
  exists (select 1 from public.chi_nhanh where id = 'PHI' and hoat_dong and dia_chi like '332 Phan Huy Ích%')
  and exists (select 1 from public.tai_khoan_quy where chi_nhanh_id = 'PHI' and ten = 'Tiền mặt' and mac_dinh and hoat_dong));
select kt.ghi('045 Hàm chuyển chi nhánh không mở cho khách chưa đăng nhập',
  not has_function_privilege('anon', 'public.doi_chi_nhanh_lam_viec(text)', 'EXECUTE'));
select kt.dong_vai('duy@gara.vn');
select kt.mong_loi('045 Nhân viên không tự chuyển chi nhánh', $$select public.doi_chi_nhanh_lam_viec('PHI')$$, 'Chỉ giám đốc');
select kt.dong_vai('codong@gara.vn');
select kt.mong_loi('045 Cổ đông không tự chuyển chi nhánh', $$select public.doi_chi_nhanh_lam_viec('PHI')$$, 'Chỉ giám đốc');
select kt.dong_vai('thuan@gara.vn');
select kt.mong_loi('045 Chi nhánh không có bị từ chối', $$select public.doi_chi_nhanh_lam_viec('XYZ')$$, 'không hợp lệ');
select public.doi_chi_nhanh_lam_viec('PHI');
select kt.ghi('045 Giám đốc chọn PHI: mặc định của mọi lệnh ghi (app.chi_nhanh) là PHI', app.chi_nhanh() = 'PHI');
insert into ctx select 'hs_phi', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-045.45','ten_khach','Khách PHI','dien_thoai','0909045045','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Trầy cản','tu_van','Không')))->>'id';
select kt.ghi('045 Tiếp nhận khi đang chọn PHI: hồ sơ thuộc PHI, mã có tiền tố PHI-',
  (select chi_nhanh_id = 'PHI' and ma like 'PHI-%' from public.ho_so where id = (select v::bigint from ctx where k='hs_phi')));
insert into ctx select 'dvn_phi', public.ghi_dich_vu_nhanh('{"bien_so":"51K04545","dich_vu":"Rửa xe","nguoi_lam":"Thợ PHI","so_tien":70000}')::text;
select kt.ghi('045 Dịch vụ nhanh ghi khi đang chọn PHI thuộc PHI',
  exists (select 1 from public.dich_vu_nhanh where chi_nhanh_id = 'PHI' and bien_so ilike '%04545%'));
select kt.dong_vai(null);
select kt.ghi('045 Người nhận việc của PHI (chưa có nhân viên PHI) là giám đốc',
  app.nhan_vien_dau('ke_toan', 'PHI') = (select id from public.nhan_vien where email = 'thuan@gara.vn'));
select kt.dong_vai('thuan@gara.vn');
select public.doi_chi_nhanh_lam_viec('TK');
select kt.ghi('045 Giám đốc quay về Tô Ký', app.chi_nhanh() = 'TK');
select kt.dong_vai(null);
select kt.ghi('045 Giám đốc đang ở Tô Ký: PHI vẫn có người nhận việc (giám đốc); Tô Ký vẫn ưu tiên kế toán Tô Ký',
  app.nhan_vien_dau('ke_toan', 'PHI') = (select id from public.nhan_vien where email = 'thuan@gara.vn')
  and app.nhan_vien_dau('ke_toan', 'TK') = (select id from public.nhan_vien where email = 'tien@gara.vn'));
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('045 Giám đốc ở Tô Ký vẫn mở được hồ sơ PHI (quyền xem mọi chi nhánh)',
  exists (select 1 from public.v_ho_so where id = (select v::bigint from ctx where k='hs_phi')));
select kt.dong_vai('duy@gara.vn');
select kt.ghi('045 Nhân viên Tô Ký không thấy hồ sơ, dịch vụ nhanh của PHI',
  not exists (select 1 from public.v_ho_so where chi_nhanh_id = 'PHI')
  and not exists (select 1 from public.v_dich_vu_nhanh where chi_nhanh_id = 'PHI'));
select kt.dong_vai('tien@gara.vn');
select kt.ghi('045 Kế toán Tô Ký không thấy tài khoản quỹ của PHI',
  not exists (select 1 from public.tai_khoan_quy where chi_nhanh_id = 'PHI'));
select kt.dong_vai(null);

-- ---------------------------------------------------------------------
-- 046: giám đốc xóa tài khoản chưa có dữ liệu
-- ---------------------------------------------------------------------
select kt.ghi('046 Hàm xóa tài khoản không mở cho khách chưa đăng nhập',
  not has_function_privilege('anon', 'public.xoa_tai_khoan_nhan_vien(uuid)', 'EXECUTE'));
select kt.dong_vai('thuan@gara.vn');
insert into ctx select 'tk_xoa', public.tao_tai_khoan_nhan_vien('{"ho_ten":"Tạo nhầm","ten_dang_nhap":"nham.cvdv","mat_khau":"hs0046","vai_tro":["cvdv"],"chi_nhanh_id":"PHI"}')::text;
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('046 Quản lý chung không xóa được tài khoản', format($$select public.xoa_tai_khoan_nhan_vien('%s')$$, (select v from ctx where k='tk_xoa')), 'Chỉ giám đốc');
select kt.dong_vai('thuan@gara.vn');
select kt.mong_loi('046 Giám đốc không tự xóa mình', format($$select public.xoa_tai_khoan_nhan_vien('%s')$$, (select id from public.nhan_vien where email = 'thuan@gara.vn')), 'chính mình');
select kt.mong_loi('046 Tài khoản đã có dữ liệu (Duy) không xóa được, nhắc khóa ở Sửa quyền',
  format($$select public.xoa_tai_khoan_nhan_vien('%s')$$, (select id from public.nhan_vien where email = 'duy@gara.vn')), 'bỏ chọn "Đang làm"');
select public.xoa_tai_khoan_nhan_vien((select v::uuid from ctx where k='tk_xoa'));
select kt.dong_vai(null);
select kt.ghi('046 Xóa tài khoản chưa dùng: mất cả nhân viên, đăng nhập, identities; Duy vẫn còn',
  not exists (select 1 from public.nhan_vien where id = (select v::uuid from ctx where k='tk_xoa'))
  and not exists (select 1 from auth.users where id = (select v::uuid from ctx where k='tk_xoa'))
  and not exists (select 1 from auth.identities where user_id = (select v::uuid from ctx where k='tk_xoa'))
  and exists (select 1 from public.nhan_vien where email = 'duy@gara.vn'));

-- ---------------------------------------------------------------------
-- 047: ảnh / file bắt buộc ở tiếp nhận, báo giá, duyệt giá, KCS; CVDV ký KCS
-- ---------------------------------------------------------------------
create or replace function kt.tep(p_hs text, p_buoc text, p_so int default 1, p_loai text default 'anh') returns void language plpgsql as $$
declare i int; v_ma text;
begin
  select ma into v_ma from public.ho_so where id = p_hs::bigint;
  for i in 1..p_so loop
    perform public.them_tep(p_hs::bigint, p_buoc, p_loai, 'TK/' || v_ma || '/' || p_buoc || '-' || i || '-' || clock_timestamp()::text || '.jpg');
  end loop;
end $$;
grant execute on function kt.tep(text, text, int, text) to authenticated;
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs47', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-047.47','ten_khach','Khách 047','dien_thoai','0909047047','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','hang_bh_id',(select id from public.hang_bao_hiem where ten='Tasco'),'gdv_id',(select id from public.giam_dinh_vien where ten='Hảo'),
  'han_bao_hiem','2027-03-01','tinh_trang_xe','Móp cản','tu_van','Không','bat_buoc_anh',true)))->>'id';
select kt.ghi('047 Hồ sơ tạo từ giao diện mới có cờ bắt ảnh', (select bat_buoc_anh from public.ho_so where id = (select v::bigint from ctx where k='hs47')));
select kt.tep((select v from ctx where k='hs47'), 'nx_truoc'); select kt.tep((select v from ctx where k='hs47'), 'nx_sau');
select kt.tep((select v from ctx where k='hs47'), 'nx_trai'); select kt.tep((select v from ctx where k='hs47'), 'nx_phai');
select kt.tep((select v from ctx where k='hs47'), 'nt_truoc');
select kt.tep((select v from ctx where k='hs47'), 'bao_gia');
select kt.mong_loi('047 Thiếu ảnh nhận xe (nội thất phía sau) thì chưa lập báo giá', format($$select public.lap_bao_gia(%s, '[{"ten":"Gò cản","nhom":"dong","gia_bao":1000000}]', 0.08)$$, (select v from ctx where k='hs47')), 'nội thất phía sau');
select kt.tep((select v from ctx where k='hs47'), 'nt_sau');
select public.lap_bao_gia((select v::bigint from ctx where k='hs47'), '[{"ten":"Gò cản","nhom":"dong","gia_bao":1000000}]', 0.08);
select kt.ghi('047 Đủ 6 ảnh nhận xe + file báo giá → lưu báo giá được', (select trang_thai = 'bao_gia' and bao_gia_luc is not null from public.ho_so where id = (select v::bigint from ctx where k='hs47')));
select kt.mong_loi('047 Lưu thêm báo giá lần nữa phải đính kèm file báo giá mới', format($$select public.lap_bao_gia(%s, '[{"ten":"Sơn cản","nhom":"son","gia_bao":800000}]', 0.08)$$, (select v from ctx where k='hs47')), 'file báo giá');
select kt.mong_loi('047 Chưa có file duyệt giá của bảo hiểm thì chưa nhập kết quả duyệt', format($$select public.duyet_gia_chia(%s, current_date, (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=%s), 0)$$, (select v from ctx where k='hs47'), (select v from ctx where k='hs47')), 'duyệt giá của bảo hiểm');
select kt.tep((select v from ctx where k='hs47'), 'duyet_gia', 1, 'bien_ban');
select public.duyet_gia_chia((select v::bigint from ctx where k='hs47'), current_date, (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs47')), 0);
select kt.ghi('047 Có file duyệt giá (PDF) → nhập kết quả duyệt được', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs47')) = 'da_duyet');
select kt.mong_loi('047 Báo giá bổ sung cũng phải có file báo giá mới', format($$select public.lap_bao_gia(%s, '[{"ten":"Thay đèn","nhom":"phu_tung","gia_bao":500000}]', 0.08)$$, (select v from ctx where k='hs47')), 'file báo giá');
select kt.tep((select v from ctx where k='hs47'), 'bao_gia');
select kt.mong_loi('047 Báo giá bổ sung xong, duyệt bổ sung cần file duyệt mới', format($$select public.lap_bao_gia(%s, '[{"ten":"Thay đèn","nhom":"phu_tung","gia_bao":500000}]', 0.08); select public.duyet_gia_chia(%s, current_date, (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=%s and trang_thai='cho_duyet'), 0)$$,
  (select v from ctx where k='hs47'), (select v from ctx where k='hs47'), (select v from ctx where k='hs47')), 'duyệt giá của bảo hiểm');
-- KCS: hồ sơ khách ngoài bảo hiểm có cờ bắt ảnh
insert into ctx select 'hs47k', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-047.48','ten_khach','Khách 047 K','dien_thoai','0909047048','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Trầy','tu_van','Không','bat_buoc_anh',true)))->>'id';
select kt.tep((select v from ctx where k='hs47k'), b) from unnest(array['nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau','bao_gia']) b;
select public.lap_bao_gia((select v::bigint from ctx where k='hs47k'), '[{"ten":"Đánh bóng","nhom":"detailing","gia_bao":600000}]', 0.08);
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs47k'), now() + interval '1 day', (select jsonb_agg(jsonb_build_object('id',id,'to_id','DT')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs47k')));
select kt.dong_vai('thuan@gara.vn');
select public.bao_xong_hang_muc(id) from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs47k');
select kt.dong_vai('duy@gara.vn');
select kt.ghi('047 Xe khách 047 đã sửa xong → chờ KCS', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs47k')) = 'cho_kcs');
select kt.tep((select v from ctx where k='hs47k'), 'kcs', 5);
select kt.mong_loi('047 KCS mới 5 ảnh thì chưa ký đạt (CVDV ký)', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs47k')), 'tối thiểu 6 ảnh');
select kt.tep((select v from ctx where k='hs47k'), 'kcs', 1);
select public.kcs((select v::bigint from ctx where k='hs47k'), false, 'Còn vết xước', (select array_agg(id) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs47k')));
select kt.dong_vai('thuan@gara.vn');
select public.bao_xong_hang_muc(id) from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs47k');
select kt.dong_vai('duy@gara.vn');
select kt.mong_loi('047 Sau lần chưa đạt: đủ 6 ảnh cũ nhưng chưa có ảnh mới thì chưa ký đạt', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs47k')), 'sau khi làm lại');
select kt.tep((select v from ctx where k='hs47k'), 'kcs', 1);
select public.kcs((select v::bigint from ctx where k='hs47k'), true);
select kt.ghi('047 CVDV ký KCS đạt (6 ảnh tổng + 1 ảnh mới sau lần chưa đạt)', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs47k')) = 'dat_kcs');
-- giao diện cũ (không gửi bat_buoc_anh): như trước
insert into ctx select 'hs47c', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-047.49','ten_khach','Khách 047 C','dien_thoai','0909047049','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Trầy','tu_van','Không')))->>'id';
select public.lap_bao_gia((select v::bigint from ctx where k='hs47c'), '[{"ten":"Đánh bóng","nhom":"detailing","gia_bao":600000}]', 0.08);
select kt.ghi('047 Hồ sơ từ giao diện cũ: không ảnh, không file vẫn báo giá như trước',
  (select not bat_buoc_anh and trang_thai = 'da_duyet' from public.ho_so where id = (select v::bigint from ctx where k='hs47c')));
select kt.dong_vai('han@gara.vn');
select kt.mong_loi('047 Trưởng nhóm không ký KCS', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs47k')), 'quyền');
select kt.dong_vai(null);

-- ---------------------------------------------------------------------
-- 048: hãng bảo hiểm + giám định viên chọn lúc nhập kết quả duyệt giá
-- ---------------------------------------------------------------------
select kt.dong_vai('duy@gara.vn');
select kt.mong_loi('048 Giao diện cũ (không gửi bh_khi_duyet): xe bảo hiểm vẫn bắt chọn hãng lúc tiếp nhận', $$select public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-048.01','ten_khach','Khách 048','dien_thoai','0909048001','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','han_bao_hiem','2027-03-01','tinh_trang_xe','Móp','tu_van','Không'))$$, 'Chưa chọn hãng bảo hiểm');
insert into ctx select 'hs48', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-048.02','ten_khach','Khách 048','dien_thoai','0909048002','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','bao_hiem','han_bao_hiem','2027-03-01','tinh_trang_xe','Móp','tu_van','Không','bh_khi_duyet',true)))->>'id';
select kt.ghi('048 Giao diện mới: tiếp nhận xe bảo hiểm không cần hãng / GDV',
  (select nguon_tt <> 'khach' and hang_bh_id is null and gdv_id is null from public.ho_so where id = (select v::bigint from ctx where k='hs48')));
select public.lap_bao_gia((select v::bigint from ctx where k='hs48'), '[{"ten":"Gò","nhom":"dong","gia_bao":1000000}]', 0.08);
select kt.mong_loi('048 Duyệt giá khi chưa có hãng bảo hiểm bị chặn', format($$select public.duyet_gia_chia(%s, current_date, (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=%s), 0)$$,
  (select v from ctx where k='hs48'), (select v from ctx where k='hs48')), 'Chưa chọn hãng bảo hiểm');
select public.sua_thong_tin_ho_so((select v::bigint from ctx where k='hs48'), jsonb_build_object('hang_bh_id', (select id from public.hang_bao_hiem where ten='Tasco')));
select kt.mong_loi('048 Có hãng mà chưa có GDV vẫn bị chặn', format($$select public.duyet_gia_chia(%s, current_date, (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=%s), 0)$$,
  (select v from ctx where k='hs48'), (select v from ctx where k='hs48')), 'Chưa có giám định viên');
select public.sua_thong_tin_ho_so((select v::bigint from ctx where k='hs48'), jsonb_build_object('gdv_id', (select id from public.giam_dinh_vien where ten='Hảo')));
select public.duyet_gia_chia((select v::bigint from ctx where k='hs48'), current_date, (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs48')), 0);
select kt.ghi('048 Chọn hãng + GDV (lưu vào hồ sơ) rồi duyệt giá được; hãng / GDV có trong hồ sơ',
  (select trang_thai = 'da_duyet' and hang_bh_id is not null and gdv_id is not null from public.ho_so where id = (select v::bigint from ctx where k='hs48')));
select kt.dong_vai(null);

-- ---------------------------------------------------------------------
-- 049: danh mục hãng xe / dòng xe đầy đủ (chỉ thêm, giữ id cũ)
-- ---------------------------------------------------------------------
select kt.ghi('049 Có đủ hãng xe (≥ 45) và dòng xe (≥ 450)',
  (select count(*) from public.hang_xe) >= 45 and (select count(*) from public.dong_xe) >= 450,
  (select count(*) from public.hang_xe)::text || ' hãng, ' || (select count(*) from public.dong_xe)::text || ' dòng');
select kt.ghi('049 Hãng / dòng cũ giữ nguyên id (thêm sau cùng), không trùng tên trong một hãng',
  (select max(id) from public.hang_xe where ten in ('VinFast','Mitsubishi','Toyota','Mazda','Kia','Hyundai','Mercedes','Ford','Isuzu','Thaco','Honda','Khác'))
    < (select min(id) from public.hang_xe where ten not in ('VinFast','Mitsubishi','Toyota','Mazda','Kia','Hyundai','Mercedes','Ford','Isuzu','Thaco','Honda','Khác'))
  and (select d.id from public.dong_xe d join public.hang_xe h on h.id = d.hang_xe_id where h.ten = 'Khác' and d.ten = 'Khác') < (select min(d.id) from public.dong_xe d join public.hang_xe h on h.id = d.hang_xe_id where h.ten = 'Toyota' and d.ten = 'Wigo')
  and not exists (select 1 from public.dong_xe group by hang_xe_id, lower(ten) having count(*) > 1));
select kt.ghi('049 Hãng nào cũng có dòng "Khác"; MPV 7 không bị thêm trùng kiểu "VF MPV 7"',
  not exists (select 1 from public.hang_xe h where not exists (select 1 from public.dong_xe d where d.hang_xe_id = h.id and d.ten = 'Khác'))
  and not exists (select 1 from public.dong_xe where ten = 'VF MPV 7'));
select kt.ghi('049 Có các dòng hay gặp: Toyota Vios, Hyundai Accent, Kia K3, Honda City, VinFast Limo Green, BYD Atto 3',
  (select count(*) from public.dong_xe d join public.hang_xe h on h.id = d.hang_xe_id
    where (h.ten, d.ten) in (('Toyota','Vios'),('Hyundai','Accent'),('Kia','K3'),('Honda','City'),('VinFast','Limo Green'),('BYD','Atto 3'))) = 6);

-- ---------------------------------------------------------------------
-- 050: bước Detailing giữa sửa chữa và KCS
-- ---------------------------------------------------------------------
insert into auth.users (email, raw_user_meta_data) values ('giang@gara.vn', '{"ho_ten":"Trần Thị Giang"}');
select kt.dong_vai('thuan@gara.vn');
select public.luu_nhan_vien(id, '{"chi_nhanh_id":"TK","vai_tro":["truong_nhom"],"to_id":"DT"}') from public.nhan_vien where email='giang@gara.vn';
select kt.dong_vai('duy@gara.vn');
insert into ctx select 'hs50', (public.tiep_nhan_xe(jsonb_build_object(
  'bien_so','51K-050.01','ten_khach','Khách 050','dien_thoai','0909050001','dong_xe_id',(select id from public.dong_xe where ten='VF3'),
  'nguon_tt','khach','tinh_trang_xe','Móp cửa','tu_van','Không','qua_detailing',true)))->>'id';
select kt.ghi('050 Giao diện mới gửi qua_detailing → hồ sơ có bước Detailing', (select qua_detailing from public.ho_so where id = (select v::bigint from ctx where k='hs50')));
select public.lap_bao_gia((select v::bigint from ctx where k='hs50'), '[{"ten":"Gò cửa","nhom":"dong","gia_bao":900000},{"ten":"Đánh bóng","nhom":"detailing","gia_bao":500000}]', 0.08);
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs50'), now() + interval '1 day', (select jsonb_agg(jsonb_build_object('id',id,'to_id',case when nhom='detailing' then 'DT' else 'DS' end)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs50')));
insert into ctx select 'hm50_ds', id from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs50') and nhom = 'dong';
select kt.dong_vai('thuan@gara.vn');
select public.bao_xong_hang_muc(id) from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs50');
select kt.ghi('050 Sửa xong hết hạng mục → Chờ Detailing, giao trưởng nhóm Detailing',
  (select h.trang_thai = 'cho_detailing' and h.nguoi_tiep_theo = (select id from public.nhan_vien where email='giang@gara.vn')
   from public.ho_so h where h.id = (select v::bigint from ctx where k='hs50')));
select kt.ghi('050 Nhật ký ghi "chờ Detailing"', exists (select 1 from public.ho_so_nhat_ky where ho_so_id = (select v::bigint from ctx where k='hs50')
  and sang_trang_thai = 'cho_detailing' and ghi_chu ilike '%chờ Detailing%'));
select kt.dong_vai('long@gara.vn');
select kt.mong_loi('050 Chờ Detailing thì chưa KCS được', format($$select public.kcs(%s, true)$$, (select v from ctx where k='hs50')), 'chưa sửa xong');
select kt.dong_vai('giang@gara.vn');
select kt.ghi('050 Bảng việc tổ Detailing có xe chờ Detailing với đủ hạng mục (cả hạng mục tổ khác)',
  (select jsonb_array_length(x->'hang_muc') = 2 and (x->>'qua_detailing')::boolean from jsonb_array_elements(public.bang_viec_to()) x
   where (x->>'ho_so_id')::bigint = (select v::bigint from ctx where k='hs50')));
select kt.dong_vai('han@gara.vn');
select kt.mong_loi('050 Trưởng nhóm Đồng sơn không làm bước Detailing', format($$select public.detailing(%s, true)$$, (select v from ctx where k='hs50')), 'Chỉ tổ Detailing');
select kt.dong_vai('giang@gara.vn');
select kt.mong_loi('050 Detailing chưa đạt phải ghi lỗi', format($$select public.detailing(%s, false, '', array[%s]::bigint[])$$, (select v from ctx where k='hs50'), (select v from ctx where k='hm50_ds')), 'Ghi lỗi');
select kt.mong_loi('050 Detailing chưa đạt phải chọn hạng mục làm lại', format($$select public.detailing(%s, false, 'Cửa còn gợn', null)$$, (select v from ctx where k='hs50')), 'Chọn hạng mục');
select public.detailing((select v::bigint from ctx where k='hs50'), false, 'Cửa còn gợn sóng', array[(select v::bigint from ctx where k='hm50_ds')]);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('050 Detailing trả về: xe về Đang sửa, hạng mục Đồng sơn làm lại, có kết quả chưa đạt',
  (select trang_thai = 'dang_sua' from public.ho_so where id = (select v::bigint from ctx where k='hs50'))
  and (select trang_thai = 'dang_lam' from public.hang_muc where id = (select v::bigint from ctx where k='hm50_ds'))
  and exists (select 1 from public.ket_qua_detailing where ho_so_id = (select v::bigint from ctx where k='hs50') and not dat and loi = 'Cửa còn gợn sóng'));
select kt.dong_vai('han@gara.vn');
select public.bao_xong_hang_muc((select v::bigint from ctx where k='hm50_ds'));
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('050 Sửa lại xong → quay lại Chờ Detailing', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs50')) = 'cho_detailing');
select kt.dong_vai('giang@gara.vn');
select public.bao_phat_sinh((select v::bigint from ctx where k='hs50'), 'Trầy cản sau');
select kt.mong_loi('050 Còn phát sinh chưa xử lý thì Detailing chưa đạt được', format($$select public.detailing(%s, true)$$, (select v from ctx where k='hs50')), 'phát sinh');
select kt.dong_vai('duy@gara.vn');
select public.xu_ly_phat_sinh((select v::bigint from ctx where k='hs50'), 'Không cần làm thêm');
select kt.ghi('050 Xử lý phát sinh lúc chờ Detailing: vẫn ở Chờ Detailing', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs50')) = 'cho_detailing');
select kt.dong_vai('giang@gara.vn');
select public.detailing((select v::bigint from ctx where k='hs50'), true);
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('050 Detailing đạt → Chờ KCS, giao quản lý chung',
  (select h.trang_thai = 'cho_kcs' and h.nguoi_tiep_theo = (select id from public.nhan_vien where email='long@gara.vn')
   from public.ho_so h where h.id = (select v::bigint from ctx where k='hs50')));
select kt.dong_vai('long@gara.vn');
select kt.tep((select v from ctx where k='hs50'), 'kcs', 1);
select public.kcs((select v::bigint from ctx where k='hs50'), false, 'Khe cửa lệch', array[(select v::bigint from ctx where k='hm50_ds')]);
select kt.dong_vai('han@gara.vn');
select public.bao_xong_hang_muc((select v::bigint from ctx where k='hm50_ds'));
select kt.dong_vai('thuan@gara.vn');
select kt.ghi('050 KCS chưa đạt, sửa lại xong → qua Detailing lần nữa', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs50')) = 'cho_detailing');
select kt.dong_vai('giang@gara.vn');
select kt.mong_loi('050 Trưởng nhóm không bật / tắt bước Detailing', format($$select public.dat_qua_detailing(%s, false)$$, (select v from ctx where k='hs50')), 'quyền');
select kt.dong_vai('duy@gara.vn');
select public.lap_bao_gia((select v::bigint from ctx where k='hs50'), '[{"ten":"Thay ốp gương","nhom":"phu_tung","gia_bao":300000}]', 0.08);
select kt.ghi('050 Báo giá bổ sung lúc chờ Detailing → về Đang sửa', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs50')) = 'dang_sua');
select public.dat_qua_detailing((select v::bigint from ctx where k='hs50'), false);
select kt.ghi('050 CVDV bỏ bước Detailing: tắt cờ, ghi nhật ký', (select not qua_detailing from public.ho_so where id = (select v::bigint from ctx where k='hs50'))
  and exists (select 1 from public.ho_so_nhat_ky where ho_so_id = (select v::bigint from ctx where k='hs50') and ghi_chu = 'Không qua Detailing'));
select public.dat_qua_detailing((select v::bigint from ctx where k='hs50'), true);
select kt.dong_vai('thuan@gara.vn');
select public.duyet_gia_chia((select v::bigint from ctx where k='hs50'), current_date, (select jsonb_agg(jsonb_build_object('id',id,'dong_y',true,'gia_duyet',gia_bao)) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs50') and trang_thai='cho_duyet'), null);
select public.lap_lenh_sua_chua((select v::bigint from ctx where k='hs50'), null, (select jsonb_agg(jsonb_build_object('id',id,'to_id','DS')) from public.hang_muc where ho_so_id=(select v::bigint from ctx where k='hs50') and trang_thai='duyet'));
select public.bao_xong_hang_muc(id) from public.hang_muc where ho_so_id = (select v::bigint from ctx where k='hs50') and trang_thai = 'dang_lam';
select kt.ghi('050 Bật lại bước Detailing → sửa xong vào Chờ Detailing', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs50')) = 'cho_detailing');
select kt.dong_vai('duy@gara.vn');
select public.dat_qua_detailing((select v::bigint from ctx where k='hs50'), false);
select kt.ghi('050 Tắt bước Detailing khi xe đang chờ Detailing → sang Chờ KCS ngay', (select trang_thai from public.ho_so where id = (select v::bigint from ctx where k='hs50')) = 'cho_kcs');
select kt.mong_loi('050 Xe đã sang KCS thì không bật lại bước Detailing', format($$select public.dat_qua_detailing(%s, true)$$, (select v from ctx where k='hs50')), 'không đổi bước Detailing');
select kt.ghi('050 Hồ sơ giao diện cũ (không gửi qua_detailing) không có bước Detailing',
  (select not qua_detailing from public.ho_so where id = (select v::bigint from ctx where k='hs47k')));
select kt.dong_vai('codong@gara.vn');
select kt.ghi('050 Cổ đông đọc được kết quả Detailing (chỉ xem)', (select count(*) from public.ket_qua_detailing) >= 2);
select kt.dong_vai(null);

-- ---------------------------------------------------------------------
-- 051: ảnh hủy vật tư (xe bảo hiểm)
-- ---------------------------------------------------------------------
select kt.dong_vai('duy@gara.vn');
select kt.tep((select v from ctx where k='hs47'), 'huy_vat_tu', 2);
select kt.ghi('051 Tải được ảnh bước "huy_vat_tu"', (select count(*) from public.ho_so_tep where ho_so_id = (select v::bigint from ctx where k='hs47') and buoc = 'huy_vat_tu') = 2);
select kt.mong_loi('051 Bước tệp lạ vẫn bị chặn', format($$select public.them_tep(%s, 'linh_tinh', 'anh', 'TK/' || (select ma from public.ho_so where id = %s) || '/y.jpg')$$, (select v from ctx where k='hs47'), (select v from ctx where k='hs47')), 'không hợp lệ');
select kt.dong_vai(null);
-- ---------------------------------------------------------------------
-- 053: ảnh, giấy tờ xe tải ngay trong hộp "Lập báo giá" (bước tệp 'giay_to_xe', không bắt buộc)
-- ---------------------------------------------------------------------
select kt.dong_vai('duy@gara.vn');
select kt.tep((select v from ctx where k='hs47'), 'giay_to_xe', 2);
select kt.tep((select v from ctx where k='hs47'), 'giay_to_xe', 1, 'bien_ban');
select kt.ghi('053 CVDV tải được ảnh và PDF bước "giay_to_xe" (3 tệp, 1 PDF)',
  (select count(*) from public.ho_so_tep where ho_so_id = (select v::bigint from ctx where k='hs47') and buoc = 'giay_to_xe') = 3
  and (select count(*) from public.ho_so_tep where ho_so_id = (select v::bigint from ctx where k='hs47') and buoc = 'giay_to_xe' and loai = 'bien_ban') = 1);
select kt.ghi('053 Tệp giấy tờ xe không làm đổi việc khác: bước "huy_vat_tu" (051) vẫn còn 2 tệp',
  (select count(*) from public.ho_so_tep where ho_so_id = (select v::bigint from ctx where k='hs47') and buoc = 'huy_vat_tu') = 2);
select kt.mong_loi('053 Bước "giay_to_xe": đường dẫn ngoài thư mục của hồ sơ vẫn bị chặn',
  format($$select public.them_tep(%s, 'giay_to_xe', 'anh', 'TK/TK-0000-KHAC/giay_to_xe-1.jpg')$$, (select v from ctx where k='hs47')), 'không thuộc thư mục');
select kt.mong_loi('053 Bước "giay_to_xe": đường dẫn có ".." vẫn bị chặn',
  format($$select public.them_tep(%s, 'giay_to_xe', 'anh', 'TK/' || (select ma from public.ho_so where id = %s) || '/../x.jpg')$$, (select v from ctx where k='hs47'), (select v from ctx where k='hs47')), 'không thuộc thư mục');
select kt.mong_loi('053 Bước tệp lạ vẫn bị chặn sau khi thêm "giay_to_xe"',
  format($$select public.them_tep(%s, 'giay_to_xe_2', 'anh', 'TK/' || (select ma from public.ho_so where id = %s) || '/z.jpg')$$, (select v from ctx where k='hs47'), (select v from ctx where k='hs47')), 'không hợp lệ');
select kt.mong_loi('053 Loại tệp lạ vẫn bị chặn với bước "giay_to_xe"',
  format($$select public.them_tep(%s, 'giay_to_xe', 'video', 'TK/' || (select ma from public.ho_so where id = %s) || '/v.mp4')$$, (select v from ctx where k='hs47'), (select v from ctx where k='hs47')), 'không hợp lệ');
select kt.dong_vai('codong@gara.vn');
select kt.mong_loi('053 Cổ đông (chỉ xem) không tải được tệp "giay_to_xe"',
  format($$select public.them_tep(%s, 'giay_to_xe', 'anh', 'TK/' || (select ma from public.ho_so where id = %s) || '/c.jpg')$$, (select v from ctx where k='hs47'), (select v from ctx where k='hs47')), 'không có quyền');
select kt.dong_vai(null);
-- ---------------------------------------------------------------------
-- 052: tối ưu tốc độ – hàm tính tiền nhẹ hơn, khởi động một lượt, Việc hôm nay một lượt
-- ---------------------------------------------------------------------
select kt.dong_vai(null);
select kt.ghi('052 tien_dong_co_vat không cài múi giờ riêng (Postgres ép thẳng công thức vào câu lệnh gọi)',
  (select proconfig is null from pg_proc where oid = 'public.tien_dong_co_vat(numeric,boolean,date,numeric)'::regprocedure));
select kt.ghi('052 tien_dong_co_vat giữ đúng công thức: không VAT, có VAT theo tỷ lệ cho trước, thiếu số tiền = 0, tỷ lệ theo ngày',
  public.tien_dong_co_vat(1000000, false, current_date, 0.08) = 1000000
  and public.tien_dong_co_vat(1000000, true, current_date, 0.08) = 1080000
  and public.tien_dong_co_vat(1000000, true, current_date, 0.1) = 1100000
  and public.tien_dong_co_vat(1234567, true, current_date, 0.08) = 1333332
  and public.tien_dong_co_vat(null, true, current_date, 0.08) = 0
  and public.tien_dong_co_vat(1000000, true, current_date, null) = round(1000000 * (1 + public.vat_ty_le(current_date)))
  and public.tien_dong_co_vat(1000000, true, null, null) = round(1000000 * (1 + public.vat_ty_le((now() at time zone 'Asia/Ho_Chi_Minh')::date))));
select kt.ghi('052 Các hàm mới không bị gắn múi giờ riêng (múi giờ đã đặt cho cả vai trò API – 033)',
  not exists (select 1 from pg_proc p where p.proname in ('khoi_dong', 'viec_hom_nay', 'canh_bao_hom_nay', 'doc_bang', 'tien_dong_co_vat')
              and p.pronamespace in ('public'::regnamespace, 'app'::regnamespace) and coalesce(p.proconfig::text, '') ilike '%timezone%'));
select kt.ghi('052 Hàm mới: chỉ người đã đăng nhập gọi được (khách ẩn danh không gọi được)',
  not has_function_privilege('anon', 'public.khoi_dong()', 'execute') and not has_function_privilege('anon', 'public.viec_hom_nay()', 'execute')
  and not has_function_privilege('anon', 'public.canh_bao_hom_nay()', 'execute')
  and has_function_privilege('authenticated', 'public.khoi_dong()', 'execute') and has_function_privilege('authenticated', 'public.viec_hom_nay()', 'execute')
  and has_function_privilege('authenticated', 'public.canh_bao_hom_nay()', 'execute'));

-- 052: so khớp hàm một lượt với các lượt đọc riêng lẻ mà giao diện cũ gọi, theo từng vai trò
create or replace function kt.cung_tap(a jsonb, b jsonb) returns boolean language sql immutable as $$
  select coalesce((select jsonb_agg(x order by x::text) from jsonb_array_elements(coalesce(a, '[]'::jsonb)) x), '[]'::jsonb)
       = coalesce((select jsonb_agg(x order by x::text) from jsonb_array_elements(coalesce(b, '[]'::jsonb)) x), '[]'::jsonb) $$;

create or replace function kt.so_viec_hom_nay(p_ten text) returns void language plpgsql as $$
declare
  n public.nhan_vien; vt text[]; r jsonb; e jsonb; sai text := ''; dem text := '';
  vp boolean; ql boolean; ktoan boolean; kh boolean; gd boolean; cn text;
begin
  select * into n from public.nhan_vien where id = auth.uid();
  vt := case when n.hoat_dong then n.vai_tro else '{}'::text[] end;     -- tài khoản khóa: không có vai trò nào
  r := public.viec_hom_nay()::jsonb;
  vp := vt && array['giam_doc','quan_ly','ke_toan','cvdv','kho'];
  ql := vt && array['quan_ly','giam_doc']; ktoan := vt && array['ke_toan','giam_doc']; kh := vt && array['kho','giam_doc','quan_ly'];
  gd := vt && array['giam_doc']; cn := case when gd then n.chi_nhanh_id end;

  e := case when vp then (select jsonb_agg(to_jsonb(v)) from public.v_ho_so v where v.trang_thai not in ('dong','huy') and (cn is null or v.chi_nhanh_id = cn)) end;
  if not kt.cung_tap(r->'ho_so', e) then sai := sai || ' ho_so'; end if;
  dem := dem || 'ho_so=' || jsonb_array_length(r->'ho_so');

  e := case when vp and ql then (select jsonb_agg(to_jsonb(x)) from (select * from public.v_ho_so v where (cn is null or v.chi_nhanh_id = cn)
         and v.trang_thai = 'dong' and v.giao_luc is not null and not v.tu_excel and v.cham_soc_luc is null order by v.giao_luc desc limit 300) x) end;
  if not kt.cung_tap(r->'cham_soc_dong', e) then sai := sai || ' cham_soc_dong'; end if;
  dem := dem || ' cs=' || jsonb_array_length(r->'cham_soc_dong');

  e := case when vp and ktoan then (select jsonb_agg(to_jsonb(x)) from (select * from public.v_ho_so v where (cn is null or v.chi_nhanh_id = cn)
         and v.trang_thai = 'dong' and v.giao_luc is not null and not v.tu_excel and v.gdv_id is not null and v.hoa_hong_gdv is null order by v.giao_luc desc limit 300) x) end;
  if not kt.cung_tap(r->'hoa_hong_dong', e) then sai := sai || ' hoa_hong_dong'; end if;
  dem := dem || ' hh=' || jsonb_array_length(r->'hoa_hong_dong');

  e := case when vp then (select jsonb_agg(to_jsonb(c)) from public.v_canh_bao c where c.loai <> 'thieu_gdv' and (cn is null or c.chi_nhanh_id = cn)) end;
  if not kt.cung_tap(public.canh_bao_hom_nay()::jsonb, e) then sai := sai || ' canh_bao'; end if;
  dem := dem || ' cb=' || jsonb_array_length(public.canh_bao_hom_nay()::jsonb);

  e := case when vt && array['truong_nhom','quan_ly','cvdv','ke_toan','giam_doc'] then public.bang_viec_to() end;
  if not kt.cung_tap(r->'bang_viec', e) then sai := sai || ' bang_viec'; end if;
  dem := dem || ' bv=' || jsonb_array_length(r->'bang_viec');

  e := case when vp and kh then (select jsonb_agg(to_jsonb(x)) from public.v_de_xuat x where x.trang_thai = 'cho_xuat' and (cn is null or x.chi_nhanh_id = cn)) end;
  if not kt.cung_tap(r->'de_xuat', e) then sai := sai || ' de_xuat'; end if;
  dem := dem || ' dx=' || jsonb_array_length(r->'de_xuat');

  e := case when vp and vt && array['quan_ly','giam_doc','kho'] then (select jsonb_agg(to_jsonb(x)) from public.v_de_nghi_mua x
         where x.trang_thai in ('cho_duyet','da_duyet') and (cn is null or x.chi_nhanh_id = cn)) end;
  if not kt.cung_tap(r->'mua', e) then sai := sai || ' mua'; end if;
  dem := dem || ' mua=' || jsonb_array_length(r->'mua');

  e := case when vp and ktoan then (select jsonb_agg(to_jsonb(x)) from public.v_phieu_nhap x
         where x.trang_thai in ('cho_khop','treo') and (cn is null or x.chi_nhanh_id = cn)) end;
  if not kt.cung_tap(r->'nhap', e) then sai := sai || ' nhap'; end if;
  dem := dem || ' nhap=' || jsonb_array_length(r->'nhap');

  e := case when vp and vt && array['quan_ly','giam_doc','ke_toan'] then (select jsonb_agg(to_jsonb(x)) from public.v_de_nghi_chi x
         where x.trang_thai in ('cho_duyet','da_duyet') and (cn is null or x.chi_nhanh_id = cn)) end;
  if not kt.cung_tap(r->'chi', e) then sai := sai || ' chi'; end if;
  dem := dem || ' chi=' || jsonb_array_length(r->'chi');

  e := case when vp and ktoan then (select jsonb_agg(to_jsonb(x)) from (select * from public.v_dich_vu_nhanh d where d.trang_thai = 'hieu_luc'
         and d.con_thu > 0 and (cn is null or d.chi_nhanh_id = cn) order by d.ngay limit 200) x) end;
  if not kt.cung_tap(r->'dvn', e) then sai := sai || ' dvn'; end if;
  dem := dem || ' dvn=' || jsonb_array_length(r->'dvn');

  e := case when vp and kh then (select jsonb_agg(jsonb_build_object('id', t.id)) from public.v_ton_kho t
         where t.duoi_toi_thieu and t.hoat_dong and (cn is null or t.chi_nhanh_id = cn)) end;
  if not kt.cung_tap(r->'thieu', e) then sai := sai || ' thieu'; end if;
  dem := dem || ' thieu=' || jsonb_array_length(r->'thieu');

  e := case when (vp or vt && array['truong_nhom']) and vt && array['giam_doc','quan_ly','ke_toan','kho','truong_nhom']
         then (select jsonb_agg(to_jsonb(s)) from public.v_viec_tai_san s where s.chi_nhanh_id = n.chi_nhanh_id) end;
  if not kt.cung_tap(r->'tai_san', e) then sai := sai || ' tai_san'; end if;
  dem := dem || ' ts=' || jsonb_array_length(r->'tai_san');

  perform kt.ghi('052 Việc hôm nay một lượt = các lượt đọc riêng – ' || p_ten, sai = '', coalesce(nullif(sai, ''), dem));
end $$;

create or replace function kt.so_khoi_dong(p_ten text) returns void language plpgsql as $$
declare
  n public.nhan_vien; r jsonb; sai text := ''; b text; e jsonb; dm jsonb; so int := 0;
  co_quyen boolean;
begin
  select * into n from public.nhan_vien where id = auth.uid();
  r := public.khoi_dong();
  if (r->'toi') is distinct from coalesce(to_jsonb(n), 'null'::jsonb) then sai := sai || ' toi'; end if;
  co_quyen := found and n.hoat_dong and cardinality(n.vai_tro) > 0 and not coalesce(n.phai_doi_mat_khau, false);
  dm := r->'danh_muc';
  if not co_quyen then
    if dm is distinct from 'null'::jsonb then sai := sai || ' danh_muc_phai_rong'; end if;
  else
    foreach b in array array['chi_nhanh','hang_bao_hiem','giam_dinh_vien','hang_xe','dong_xe','to_thuc_hien','muc_thu_chi','nha_cung_cap','don_vi_lien_quan','cai_dat','tai_khoan_quy','nhan_vien'] loop
      -- Bảng nào vai trò này không được tải thì không có khóa; còn lại khớp đúng lượt đọc riêng (xếp theo id, cai_dat theo khoa)
      if b = 'tai_khoan_quy' and not (n.vai_tro && array['giam_doc','ke_toan','quan_ly','co_dong']) then
        if dm ? b then sai := sai || ' thua_' || b; end if; continue;
      end if;
      if b = 'nhan_vien' and not (n.vai_tro && array['giam_doc','quan_ly','ke_toan','cvdv','kho','co_dong']) then
        if dm ? b then sai := sai || ' thua_' || b; end if; continue;
      end if;
      execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.%I), %L::jsonb) from public.%I t', case when b = 'cai_dat' then 'khoa' else 'id' end, '[]',
        case when b = 'don_vi_lien_quan' and not (n.vai_tro && array['giam_doc','ke_toan','quan_ly','co_dong']) then 'v_don_vi_lien_quan' else b end) into e;
      if (dm -> b) is distinct from e then sai := sai || ' ' || b; end if;
      so := so + jsonb_array_length(e);
    end loop;
  end if;
  perform kt.ghi('052 Khởi động một lượt = người dùng + danh mục đọc riêng – ' || p_ten, sai = '', coalesce(nullif(sai, ''), so || ' dòng danh mục'));
end $$;

grant execute on all functions in schema kt to authenticated;

insert into auth.users (email, raw_user_meta_data) values ('moi052@gara.vn', '{"ho_ten":"Người mới 052"}');
select kt.dong_vai('thuan@gara.vn');  select kt.so_viec_hom_nay('giám đốc');           select kt.so_khoi_dong('giám đốc');
select kt.ghi('052 Khởi động trả đủ danh mục: giám đốc thấy quỹ + nhân viên + cài đặt đúng khóa',
  (select (r->'danh_muc') ? 'tai_khoan_quy' and (r->'danh_muc') ? 'nhan_vien'
          and exists (select 1 from jsonb_array_elements(r->'danh_muc'->'cai_dat') c where c->>'khoa' = 'so_ngay_goi_cham_soc')
   from (select public.khoi_dong() as r) x));
select kt.dong_vai('long@gara.vn');   select kt.so_viec_hom_nay('quản lý chung');       select kt.so_khoi_dong('quản lý chung');
select kt.dong_vai('tien@gara.vn');   select kt.so_viec_hom_nay('kế toán');             select kt.so_khoi_dong('kế toán');
select kt.dong_vai('duy@gara.vn');    select kt.so_viec_hom_nay('CVDV kiêm kho');       select kt.so_khoi_dong('CVDV kiêm kho');
select kt.ghi('052 Khởi động: CVDV không có danh sách tài khoản quỹ (như giao diện cũ)',
  (select not ((r->'danh_muc') ? 'tai_khoan_quy') and (r->'danh_muc') ? 'nhan_vien' from (select public.khoi_dong() as r) x));
select kt.dong_vai('han@gara.vn');    select kt.so_viec_hom_nay('trưởng nhóm DS');      select kt.so_khoi_dong('trưởng nhóm DS');
select kt.ghi('052 Khởi động: trưởng nhóm không có danh sách nhân viên, quỹ; đơn vị liên quan chỉ qua view tên (043)',
  (select not ((r->'danh_muc') ? 'tai_khoan_quy') and not ((r->'danh_muc') ? 'nhan_vien')
          and not exists (select 1 from jsonb_array_elements(r->'danh_muc'->'don_vi_lien_quan') d where d ? 'so_du_dau_ky')
   from (select public.khoi_dong() as r) x));
select kt.dong_vai('vinh@gara.vn');   select kt.so_viec_hom_nay('trưởng nhóm DMG');     select kt.so_khoi_dong('trưởng nhóm DMG');
select kt.dong_vai('codong@gara.vn'); select kt.so_viec_hom_nay('cổ đông');             select kt.so_khoi_dong('cổ đông');
select kt.ghi('052 Việc hôm nay: cổ đông nhận danh sách rỗng',
  (select jsonb_array_length(r->'ho_so') = 0 and jsonb_array_length(r->'bang_viec') = 0 and jsonb_array_length(r->'tai_san') = 0
   from (select public.viec_hom_nay()::jsonb as r) x) is not distinct from true);
select kt.dong_vai('moi052@gara.vn'); select kt.so_viec_hom_nay('chưa có vai trò');     select kt.so_khoi_dong('chưa có vai trò');
select kt.ghi('052 Khởi động: tài khoản chưa có vai trò → có toi, danh_muc = null',
  (select (r->'toi'->>'email') = 'moi052@gara.vn' and (r->'danh_muc') = 'null'::jsonb from (select public.khoi_dong() as r) x));
select kt.dong_vai(null);
-- Tài khoản đã khóa / đang phải đổi mật khẩu: giao diện hiện màn hình riêng, không tải danh mục
insert into auth.users (email, raw_user_meta_data) values ('khoa052@gara.vn', '{"ho_ten":"Đã khóa 052"}'), ('doimk052@gara.vn', '{"ho_ten":"Đổi mật khẩu 052"}');
update public.nhan_vien set vai_tro = '{cvdv}', chi_nhanh_id = 'TK', hoat_dong = false where email = 'khoa052@gara.vn';
update public.nhan_vien set vai_tro = '{cvdv}', chi_nhanh_id = 'TK', phai_doi_mat_khau = true where email = 'doimk052@gara.vn';
select kt.dong_vai('khoa052@gara.vn');   select kt.so_viec_hom_nay('tài khoản đã khóa');         select kt.so_khoi_dong('tài khoản đã khóa');
select kt.ghi('052 Khởi động: tài khoản đã khóa → danh_muc = null',
  (select (r->'danh_muc') = 'null'::jsonb from (select public.khoi_dong() as r) x));
select kt.dong_vai('doimk052@gara.vn');  select kt.so_viec_hom_nay('đang phải đổi mật khẩu');    select kt.so_khoi_dong('đang phải đổi mật khẩu');
select kt.ghi('052 Khởi động: tài khoản đang phải đổi mật khẩu → danh_muc = null',
  (select (r->'danh_muc') = 'null'::jsonb and (r->'toi'->>'phai_doi_mat_khau')::boolean from (select public.khoi_dong() as r) x));
select kt.dong_vai(null);
\o
\echo '======== KẾT QUẢ ========'
select stt, case when dat then 'ĐẠT ' else 'LỖI ' end as kq, ten, left(coalesce(chi_tiet,''), 140) as chi_tiet from kt.ket_qua order by stt;
select count(*) filter (where dat) as dat, count(*) filter (where not dat) as loi from kt.ket_qua;
