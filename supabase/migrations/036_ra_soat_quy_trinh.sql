-- =====================================================================
-- 036 (14/10/2026): RÀ SOÁT QUY TRÌNH – anh Thuận chọn các mục 5, 7, 8, 9, 10, 12 (sáng 14/10)
--  5. Giám định viên KHÔNG bắt buộc lúc tiếp nhận (hãng bảo hiểm thường cử GDV sau 1–2 ngày);
--     BẮT BUỘC trước khi nhập kết quả duyệt giá (duyet_gia chặn). Việc cần xử lý có dòng "chưa có GDV".
--  7. Hồ sơ BẢO HÀNH (xe quay lại vì lỗi cũ): không báo giá, không duyệt giá, không hãng BH / GDV.
--     Tiếp nhận chọn hạng mục làm lại (p.hang_muc, giá 0) → hồ sơ sang "Đã duyệt giá", lập lệnh sửa chữa ngay.
--     Giao diện cũ không gửi hang_muc thì chạy như trước.
--  9. THU TIỀN & GIAO XE một lần (thu_tien_giao_xe): phiếu thu + giao xe trong MỘT giao dịch – giao không được
--     thì phiếu thu cũng không ghi.
-- 10. DỊCH VỤ NHANH THU TIỀN NGAY: ghi_dich_vu_nhanh nhận thu_ngay + tai_khoan_id (chỉ kế toán / giám đốc)
--     → tự lập phiếu thu gắn lượt dịch vụ.
-- 12. Khấu trừ – giảm trừ chỉ sửa qua "Chia công nợ" (sua_chia_cong_no); giao diện mới không gửi khấu trừ khi giao xe
--     (giao_xe vẫn nhận khau_tru_giam_tru cho giao diện cũ của bản thật).
--  Tương thích ngược: hàm cũ giữ tên và tham số; chỉ thêm hàm mới, điều kiện mới.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5 + 7. Tiếp nhận xe: GDV không bắt buộc; hồ sơ bảo hành vào thẳng "Đã duyệt giá"
-- ---------------------------------------------------------------------
create or replace function public.tiep_nhan_xe(p jsonb) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare
  v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ngay timestamptz := coalesce((p->>'ngay_vao')::timestamptz, now());
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_nguon text := p->>'nguon_tt';
  v_gdv public.giam_dinh_vien;
  v_kh bigint; v_xe bigint; v_ma text; v_goc text; v_n int; v_id bigint; v_mo text;
  v_loai text := coalesce(p->>'loai', 'sua_chua');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_bao_hanh boolean := v_loai = 'bao_hanh';
  v_hm jsonb := case when jsonb_typeof(p->'hang_muc') = 'array' then p->'hang_muc' else '[]'::jsonb end;
  d jsonb; v_so_hm int := 0;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  if v_cn is null then raise exception 'Tài khoản chưa gắn chi nhánh.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  -- Bảo hành: làm lại miễn phí, không liên quan bảo hiểm → luôn là nguồn "khách", không hãng BH, không GDV
  if v_bao_hanh then v_nguon := 'khach'; end if;

  if nullif(trim(p->>'ten_khach'),'') is null then raise exception 'Thiếu tên khách.'; end if;
  if v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if (p->>'dong_xe_id') is null then raise exception 'Chưa chọn loại xe.'; end if;
  if v_nguon not in ('bao_hiem','khach','bao_hiem_khach') or v_nguon is null then
    raise exception 'Chưa chọn bảo hiểm nào hay khách lẻ.'; end if;
  if nullif(trim(p->>'tinh_trang_xe'),'') is null then raise exception 'Ghi yêu cầu của khách hàng.'; end if;
  if nullif(trim(p->>'tu_van'),'') is null then raise exception 'Thiếu mục những gì có thể tư vấn (ghi "Không" nếu không có).'; end if;
  if v_nguon <> 'khach' then
    if (p->>'hang_bh_id') is null then raise exception 'Chưa chọn hãng bảo hiểm.'; end if;
    -- 036: giám định viên để trống được (hãng cử sau); bắt buộc trước khi nhập kết quả duyệt giá
    if (p->>'gdv_id') is not null then
      select * into v_gdv from public.giam_dinh_vien where id = (p->>'gdv_id')::bigint;
      if v_gdv.la_cho_them and nullif(trim(p->>'gdv_ten_tam'),'') is null then
        raise exception 'Chọn "GDV mới – chờ thêm" thì phải ghi tên giám định viên.';
      end if;
    end if;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so';
  end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_bao_hanh and (p->>'ho_so_goc_id') is null then
    raise exception 'Hồ sơ bảo hành phải chọn hồ sơ cũ.'; end if;
  if v_bao_hanh then
    for d in select * from jsonb_array_elements(v_hm) loop
      if nullif(trim(d->>'ten'),'') is null then raise exception 'Hạng mục bảo hành thiếu nội dung.'; end if;
      v_so_hm := v_so_hm + 1;
    end loop;
    if v_so_hm > 0 then perform app.yeu_cau_thang_mo(v_cn, current_date); end if;
  end if;

  -- Khách: tìm theo SĐT
  select id into v_kh from public.khach_hang where dien_thoai = v_dt;
  if v_kh is null then
    insert into public.khach_hang (ten, dien_thoai) values (trim(p->>'ten_khach'), v_dt) returning id into v_kh;
  else
    update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
  end if;

  -- Xe: tìm theo biển số
  if v_bs is not null then
    select id into v_xe from public.xe where bien_so = v_bs;
    if v_xe is not null then
      select ma into v_mo from public.ho_so
        where xe_id = v_xe and trang_thai not in ('dong','huy') order by id desc limit 1;
      if v_mo is not null and not coalesce((p->>'bo_qua_canh_bao')::boolean, false) then
        raise exception 'CANH_BAO: Xe % đang có hồ sơ % chưa đóng. Vẫn tạo hồ sơ mới?',
          public.bien_so_hien_thi(v_bs), v_mo;
      end if;
      update public.xe set dong_xe_id = (p->>'dong_xe_id')::bigint,
        mau = coalesce(nullif(trim(p->>'mau'),''), mau), khach_hang_id = v_kh,
        han_bao_hiem = coalesce((p->>'han_bao_hiem')::date, han_bao_hiem),
        han_bh_than_vo = coalesce((p->>'han_bh_than_vo')::date, han_bh_than_vo)
      where id = v_xe;
    end if;
  end if;
  if v_xe is null then
    insert into public.xe (bien_so, dong_xe_id, mau, khach_hang_id, han_bao_hiem, han_bh_than_vo)
    values (v_bs, (p->>'dong_xe_id')::bigint, nullif(trim(p->>'mau'),''), v_kh, (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date)
    returning id into v_xe;
  end if;

  if v_bao_hanh and not exists (select 1 from public.ho_so where id = (p->>'ho_so_goc_id')::bigint and xe_id = v_xe) then
    raise exception 'Hồ sơ cũ không phải của xe này.';
  end if;

  -- Mã hồ sơ: TK-2610-50H92361, trùng trong tháng thì thêm -2, -3…; chưa có biển: TK-2610-KBS01
  v_goc := v_cn || '-' || to_char(v_ngay at time zone 'Asia/Ho_Chi_Minh', 'YYMM') || '-';
  if v_bs is not null then
    v_ma := v_goc || v_bs; v_n := 1;
    while exists (select 1 from public.ho_so where ma = v_ma) loop
      v_n := v_n + 1; v_ma := v_goc || v_bs || '-' || v_n;
    end loop;
  else
    select count(*) + 1 into v_n from public.ho_so where ma like v_goc || 'KBS%';
    v_ma := v_goc || 'KBS' || lpad(v_n::text, 2, '0');
    while exists (select 1 from public.ho_so where ma = v_ma) loop
      v_n := v_n + 1; v_ma := v_goc || 'KBS' || lpad(v_n::text, 2, '0');
    end loop;
  end if;

  insert into public.ho_so (ma, chi_nhanh_id, loai, ho_so_goc_id, xe_id, khach_hang_id, ngay_vao, nguon_tt,
    hang_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, so_km, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), v_km::int, auth.uid())
  returning id into v_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, v_id;
  end if;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', case when v_bao_hanh then 'Tiếp nhận xe bảo hành' else 'Tiếp nhận xe' end);

  -- Bảo hành (036): hạng mục làm lại miễn phí, coi như đã duyệt → lập lệnh sửa chữa được ngay
  if v_bao_hanh and v_so_hm > 0 then
    for d in select * from jsonb_array_elements(v_hm) loop
      insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd, trang_thai, gia_duyet, ngay_duyet)
      values (v_id, 0, trim(d->>'ten'), coalesce(nullif(d->>'nhom',''), 'dong_son'), 'khach', 0, false, 'duyet', 0, current_date);
    end loop;
    perform app.doi_trang_thai(v_id, 'da_duyet', 'Bảo hành ' || v_so_hm || ' hạng mục – không báo giá, không duyệt giá');
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

-- ---------------------------------------------------------------------
-- 5. Duyệt giá: xe bảo hiểm phải có giám định viên (cũng áp dụng cho báo giá bổ sung; duyet_gia_chia gọi hàm này)
-- ---------------------------------------------------------------------
create or replace function public.duyet_gia(p_ho_so bigint, p_ngay date, ket_qua jsonb) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
  if h.nguon_tt <> 'khach' and h.gdv_id is null then
    raise exception 'Chưa có giám định viên. Bấm "Sửa" ở mục Thông tin xe và khách để ghi GDV trước khi nhập kết quả duyệt giá.'; end if;
  if p_ngay is null then raise exception 'Thiếu ngày duyệt.'; end if;
  if p_ngay > current_date then raise exception 'Ngày duyệt không được sau hôm nay.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, p_ngay);

  for d in select * from jsonb_array_elements(ket_qua) loop
    select * into r from public.hang_muc where id = (d->>'id')::bigint and ho_so_id = p_ho_so for update;
    if not found then raise exception 'Dòng báo giá không thuộc hồ sơ này.'; end if;
    if r.trang_thai <> 'cho_duyet' then raise exception 'Dòng "%" đã được xử lý trước đó.', r.ten; end if;
    if coalesce((d->>'dong_y')::boolean, false) then
      if (d->>'gia_duyet') is null or (d->>'gia_duyet')::numeric < 0 then
        raise exception 'Dòng "%" thiếu giá duyệt.', r.ten; end if;
      update public.hang_muc set trang_thai = 'duyet', gia_duyet = (d->>'gia_duyet')::numeric, ngay_duyet = p_ngay
      where id = r.id;
    else
      update public.hang_muc set trang_thai = 'tu_choi', gia_duyet = null, ngay_duyet = p_ngay where id = r.id;
    end if;
  end loop;

  if h.trang_thai = 'bao_gia'
     and not exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'cho_duyet')
     and exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'duyet') then
    perform app.doi_trang_thai(p_ho_so, 'da_duyet', 'Đã duyệt giá ngày ' || to_char(p_ngay, 'DD/MM/YYYY'));
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Duyệt giá ngày ' || to_char(p_ngay, 'DD/MM/YYYY'));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 12. Chia công nợ bảo hiểm / khách: dùng chung cho duyệt giá và sửa sau này
-- ---------------------------------------------------------------------
create or replace function app.chia_cong_no(p_ho_so bigint, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_tong numeric; v_khach_dong numeric; v_khau_tru numeric;
begin
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then
    return jsonb_build_object('tong', (select coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)), 0)
      from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong')), 'bao_hiem', 0, 'khach', null);
  end if;
  select coalesce(sum(public.tien_dong_co_vat(gia_duyet, true, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'bao_hiem'), 0)
       + coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0),
       coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0)
    into v_tong, v_khach_dong
  from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong');
  if p_khach_tra is null then p_khach_tra := v_khach_dong + h.khau_tru_giam_tru; end if;
  if p_khach_tra < v_khach_dong then
    raise exception 'Khách chi trả ít nhất % đ (các dòng khách tự trả).', app.vnd(v_khach_dong); end if;
  if p_khach_tra > v_tong then
    raise exception 'Khách chi trả không được vượt tổng giá duyệt % đ.', app.vnd(v_tong); end if;
  v_khau_tru := round(p_khach_tra - v_khach_dong);
  if v_khau_tru <> h.khau_tru_giam_tru then
    update public.ho_so set khau_tru_giam_tru = v_khau_tru where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
      'Chia công nợ: bảo hiểm chi trả ' || app.vnd(v_tong - p_khach_tra) || ' đ, khách chi trả ' || app.vnd(p_khach_tra)
      || ' đ (khấu trừ – giảm trừ ' || app.vnd(v_khau_tru) || ' đ)');
    perform app.cap_nhat_dong(p_ho_so);
  end if;
  return jsonb_build_object('tong', v_tong, 'bao_hiem', v_tong - p_khach_tra, 'khach', p_khach_tra, 'khau_tru', v_khau_tru);
end $$;

create or replace function public.duyet_gia_chia(p_ho_so bigint, p_ngay date, ket_qua jsonb, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.duyet_gia(p_ho_so, p_ngay, ket_qua);
  return app.chia_cong_no(p_ho_so, p_khach_tra);
end $$;

-- Sửa lại cách chia công nợ sau khi đã duyệt (xe bảo hiểm): CVDV, kế toán, quản lý chung, giám đốc
create or replace function public.sua_chia_cong_no(p_ho_so bigint, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('cvdv','ke_toan','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then raise exception 'Xe khách ngoài bảo hiểm không chia công nợ.'; end if;
  if h.trang_thai in ('huy') then raise exception 'Hồ sơ đã hủy.'; end if;
  if not exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong')) then
    raise exception 'Hồ sơ chưa có hạng mục được duyệt.'; end if;
  if p_khach_tra is null or p_khach_tra < 0 then raise exception 'Nhập số tiền khách chi trả.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  return app.chia_cong_no(p_ho_so, p_khach_tra);
end $$;

-- ---------------------------------------------------------------------
-- 9. Thu tiền & giao xe một lần (kế toán, giám đốc)
-- p: {so_tien, tai_khoan_id, ngay?, noi_dung?, duyet_con_no?, so_hd_bao_hiem?, so_hd_khach?, cam_nhan_khach?}
-- ---------------------------------------------------------------------
create or replace function public.thu_tien_giao_xe(p_ho_so bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; t record; v_tien numeric := coalesce((p->>'so_tien')::numeric, 0); m public.muc_thu_chi;
  v_phieu bigint; x public.xe; k public.khach_hang;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'dat_kcs' then raise exception 'Xe chưa đạt KCS thì không giao được.'; end if;
  if v_tien < 0 then raise exception 'Số tiền không hợp lệ.'; end if;
  if v_tien > 0 then
    if (p->>'tai_khoan_id') is null then raise exception 'Chọn tài khoản nhận tiền.'; end if;
    select * into t from app.tien_ho_so(p_ho_so);
    if v_tien > t.con_no_khach then
      raise exception 'Khách trả % đ nhiều hơn số còn nợ % đ. Thu đúng số nợ ở đây; phần dư (tiền bo, trả dư) lập ở Thu chi → Phiếu thu.',
        app.vnd(v_tien), app.vnd(t.con_no_khach);
    end if;
    select * into m from public.muc_thu_chi where loai = 'thu' and tinh_chat = 'thu_khach' and hoat_dong order by id limit 1;
    if not found then raise exception 'Chưa có mục thu "Thu của khách (gắn xe)" trong Danh mục.'; end if;
    select * into x from public.xe where id = h.xe_id;
    select * into k from public.khach_hang where id = h.khach_hang_id;
    v_phieu := public.lap_phieu_thu(jsonb_build_object(
      'tai_khoan_id', (p->>'tai_khoan_id')::bigint, 'muc_id', m.id, 'so_tien', v_tien,
      'ngay', coalesce((p->>'ngay')::date, current_date),
      'noi_dung', coalesce(nullif(trim(p->>'noi_dung'),''), 'Khách trả sửa xe ' || coalesce(public.bien_so_hien_thi(x.bien_so), h.ma) || ' – ' || k.ten || ' (giao xe)'),
      'phan_bo', jsonb_build_array(jsonb_build_object('ho_so_id', p_ho_so, 'so_tien', v_tien))));
  end if;
  -- Quản lý chung / giám đốc tích "duyệt giao khi còn nợ" ngay trong hộp thoại
  if coalesce((p->>'duyet_con_no')::boolean, false) and h.cho_giao_no_boi is null and app.co_vai_tro('quan_ly','giam_doc') then
    perform public.duyet_giao_xe_con_no(p_ho_so);
  end if;
  -- Giao xe: không nhận khấu trừ ở bước này (chỉ sửa qua Chia công nợ)
  perform public.giao_xe(p_ho_so, (p - 'so_tien' - 'tai_khoan_id' - 'ngay' - 'noi_dung' - 'duyet_con_no' - 'khau_tru_giam_tru'));
  select * into t from app.tien_ho_so(p_ho_so);
  return jsonb_build_object('phieu_id', v_phieu, 'da_thu', v_tien, 'con_no_khach', t.con_no_khach, 'con_no_bh', t.con_no_bh);
end $$;

-- ---------------------------------------------------------------------
-- 10. Dịch vụ nhanh: thu tiền ngay (kế toán / giám đốc gửi thu_ngay + tai_khoan_id)
-- ---------------------------------------------------------------------
create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint; v_to text := nullif(p->>'to_id', ''); v_nguoi text := nullif(trim(p->>'nguoi_lam'),'');
  v_thu_ngay boolean := coalesce((p->>'thu_ngay')::boolean, false); m public.muc_thu_chi;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_to is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Chọn tổ làm: Điện – máy – gầm hoặc Detailing.'; end if;
  if v_to is not null then
    if v_to not in ('DMG', 'DT') then raise exception 'Dịch vụ nhanh chỉ do tổ Điện – máy – gầm hoặc Detailing làm.'; end if;
    select ten into v_nguoi from public.to_thuc_hien where id = v_to;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if v_thu_ngay then
    if not app.co_vai_tro('ke_toan','giam_doc') then raise exception 'Chỉ kế toán hoặc giám đốc thu tiền ngay; người khác ghi dịch vụ rồi kế toán thu ở Thu chi.' using errcode = '42501'; end if;
    if (p->>'tai_khoan_id') is null then raise exception 'Chọn tài khoản nhận tiền.'; end if;
    select * into m from public.muc_thu_chi where loai = 'thu' and tinh_chat = 'thu_dich_vu_nhanh' and hoat_dong order by id limit 1;
    if not found then raise exception 'Chưa có mục thu "Thu dịch vụ nhanh" trong Danh mục.'; end if;
  end if;

  -- Khách: tìm theo SĐT (như tiếp nhận); có tên mới thì cập nhật
  if v_dt <> '' then
    select id into v_kh from public.khach_hang where dien_thoai = v_dt;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(p->>'ten_khach'),''), 'Chưa có tên'), v_dt) returning id into v_kh;
    elsif nullif(trim(p->>'ten_khach'),'') is not null then
      update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
    end if;
  end if;
  -- Xe: tìm theo biển số; chưa có thì tạo (loại xe để trống, lần tiếp nhận sau bổ sung)
  if v_bs is not null then
    select id, khach_hang_id into v_xe, v_kh_xe from public.xe where bien_so = v_bs;
    if v_xe is not null and v_kh is null then v_kh := v_kh_xe; end if;
    if v_xe is null then
      insert into public.xe (bien_so, khach_hang_id) values (v_bs, v_kh) returning id into v_xe;
    elsif v_dt <> '' then
      update public.xe set khach_hang_id = v_kh where id = v_xe;
    end if;
  end if;

  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi, xe_id, khach_hang_id, so_km, to_id)
  values (v_cn, v_ngay, v_bs, trim(p->>'dich_vu'), v_nguoi,
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid(), v_xe, v_kh, v_km::int, v_to)
  returning id into v_id;

  -- Thu tiền ngay: phiếu thu gắn lượt dịch vụ, cùng giao dịch (lỗi thì cả lượt dịch vụ không ghi)
  if v_thu_ngay then
    perform public.lap_phieu_thu(jsonb_build_object(
      'tai_khoan_id', (p->>'tai_khoan_id')::bigint, 'muc_id', m.id, 'so_tien', (p->>'so_tien')::numeric, 'ngay', v_ngay,
      'noi_dung', 'Dịch vụ nhanh: ' || trim(p->>'dich_vu') || coalesce(' – ' || public.bien_so_hien_thi(v_bs), ''),
      'phan_bo', jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id', v_id, 'so_tien', (p->>'so_tien')::numeric))));
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. Việc cần xử lý: xe bảo hiểm chưa có giám định viên
-- (v_canh_bao giữ nguyên các dòng cũ – 004; 008 chạy sau cũng đã có dòng này)
-- ---------------------------------------------------------------------
create or replace view public.v_canh_bao with (security_invoker = true) as
with hs as (select * from public.v_ho_so where trang_thai not in ('huy')),
homnay as (select (now() at time zone 'Asia/Ho_Chi_Minh')::date as d)
select 'cho_duyet_qua_han' as loai, 'cao' as muc_do, hs.id as ho_so_id, hs.ma, hs.bien_so_hien_thi as bien_so,
  'Xe bảo hiểm chờ duyệt giá ' || (homnay.d - hs.ngay_vao::date) || ' ngày – báo giám đốc' as noi_dung, hs.chi_nhanh_id
from hs, homnay
where hs.nguon_tt <> 'khach' and hs.trang_thai in ('tiep_nhan','bao_gia')
  and homnay.d - hs.ngay_vao::date > app.cai_dat_so('so_ngay_cho_duyet', 3)
union all
select 'chua_gui_ho_so', 'cao', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Đã giao xe ' || (homnay.d - hs.giao_luc::date) || ' ngày, chưa gửi hồ sơ bảo hiểm', hs.chi_nhanh_id
from hs, homnay
where hs.nguon_tt <> 'khach' and hs.trang_thai = 'da_giao'
  and homnay.d - hs.giao_luc::date > app.cai_dat_so('so_ngay_gui_ho_so', 3)
union all
select case when homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_no_giam_doc', 30) then 'no_bh_30' else 'no_bh_15' end,
  case when homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_no_giam_doc', 30) then 'cao' else 'vua' end,
  hs.id, hs.ma, hs.bien_so_hien_thi,
  coalesce(hs.hang_bh, 'Bảo hiểm') || ' còn nợ ' || app.vnd(hs.con_no_bh) || ' đ, đã gửi hồ sơ '
    || (homnay.d - hs.gui_hs_ngay) || ' ngày'
    || case when homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_no_giam_doc', 30) then ' – giám đốc làm việc với bảo hiểm' else ' – nhắc nợ' end,
  hs.chi_nhanh_id
from hs, homnay
where hs.trang_thai = 'da_gui_hs' and hs.con_no_bh > 0
  and homnay.d - hs.gui_hs_ngay > app.cai_dat_so('so_ngay_nhac_no', 15)
union all
select 'khach_no', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  hs.ten_khach || ' còn nợ ' || app.vnd(hs.con_no_khach) || ' đ', hs.chi_nhanh_id
from hs where hs.giao_luc is not null and hs.con_no_khach > 0
union all
select 'thieu_hoa_hong', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Chưa nhập hoa hồng cho GDV ' || coalesce(hs.gdv, ''), hs.chi_nhanh_id
from hs where hs.gdv_id is not null and hs.giao_luc is not null and hs.hoa_hong_gdv is null and not hs.tu_excel
union all
select 'gdv_cho_them', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'GDV "' || coalesce(hs.gdv, '') || '" chưa có trong danh sách – kế toán thêm vào Cài đặt rồi gắn lại', hs.chi_nhanh_id
from hs where hs.gdv_cho_them
union all
select 'thieu_gdv', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Xe bảo hiểm chưa có giám định viên – ghi GDV (Sửa ở Thông tin xe và khách) trước khi nhập kết quả duyệt giá', hs.chi_nhanh_id
from hs where hs.nguon_tt <> 'khach' and hs.gdv_id is null and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs')
union all
select 'can_goi_cham_soc', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Gọi hỏi thăm ' || hs.ten_khach || ' (giao xe ' || to_char(hs.giao_luc, 'DD/MM') || ')', hs.chi_nhanh_id
from hs, homnay
where hs.giao_luc is not null and hs.cham_soc_luc is null
  and homnay.d - hs.giao_luc::date >= app.cai_dat_so('so_ngay_goi_cham_soc', 3)
union all
select 'phat_sinh', 'cao', hs.id, hs.ma, hs.bien_so_hien_thi, 'Có hư hỏng phát sinh chờ lập báo giá bổ sung', hs.chi_nhanh_id
from hs where hs.co_phat_sinh
union all
select 'tre_hen', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Quá giờ hẹn giao ' || to_char(hs.hen_giao at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), hs.chi_nhanh_id
from hs where hs.hen_giao < now() and hs.trang_thai in ('dang_sua','cho_kcs','dat_kcs')
union all
select 'thu_chua_phan_bo', 'vua', null, null, null,
  'Phiếu thu ' || to_char(p.ngay, 'DD/MM') || ' của ' || coalesce(p.hang_bh, p.muc) || ' còn '
    || app.vnd(p.so_tien - p.da_phan_bo) || ' đ chưa chia vào xe', p.chi_nhanh_id
from public.v_phieu_thu_chi p
where p.loai = 'thu' and p.trang_thai = 'hieu_luc' and p.tinh_chat = 'thu_bao_hiem' and p.da_phan_bo < p.so_tien
union all
select 'de_nghi_cho_duyet', case when d.nghi_tach_phieu then 'cao' else 'vua' end, d.ho_so_id, d.ho_so_ma, null,
  'Đề nghị chi ' || app.vnd(d.so_tien) || ' đ – ' || d.noi_dung || ' (' || coalesce(d.nguoi_de_nghi_ten,'') || ')'
    || case when d.can_giam_doc then ' – cần giám đốc duyệt' else '' end
    || case when d.nghi_tach_phieu then ' – nghi tách nhỏ phiếu' else '' end,
  d.chi_nhanh_id
from public.v_de_nghi_chi d
where d.trang_thai = 'cho_duyet' and app.co_vai_tro('giam_doc','quan_ly')
  and d.nguoi_de_nghi <> auth.uid() and (not d.can_giam_doc or app.co_vai_tro('giam_doc'));

grant select on public.v_canh_bao to authenticated;
revoke all on public.v_canh_bao from anon;

-- Quyền gọi hàm
revoke execute on function public.thu_tien_giao_xe(bigint, jsonb), public.sua_chia_cong_no(bigint, numeric), app.chia_cong_no(bigint, numeric) from public, anon;
grant execute on function public.thu_tien_giao_xe(bigint, jsonb), public.sua_chia_cong_no(bigint, numeric) to authenticated;

notify pgrst, 'reload schema';
