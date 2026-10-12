-- =====================================================================
-- 002: Hàm nghiệp vụ
-- Mọi thao tác ghi dữ liệu nghiệp vụ đi qua các hàm này (security definer),
-- nên quy tắc khóa bước, phân quyền và khóa sổ luôn được kiểm tra ở máy chủ,
-- không phụ thuộc giao diện.
-- Lỗi trả về bằng tiếng Việt. Lỗi bắt đầu bằng "CANH_BAO:" là cảnh báo:
-- giao diện hỏi lại người dùng, đồng ý thì gửi lại với bo_qua_canh_bao = true.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Hàm nội bộ
-- ---------------------------------------------------------------------
create or replace function app.vai_tro() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce((select vai_tro from public.nhan_vien where id = auth.uid() and hoat_dong), '{}'::text[])
$$;

create or replace function app.co_vai_tro(variadic ds text[]) returns boolean
language sql stable as $$ select app.vai_tro() && ds $$;

create or replace function app.la_nhan_vien() returns boolean
language sql stable as $$
  select app.vai_tro() && array['giam_doc','quan_ly','ke_toan','cvdv','kho']
$$;

create or replace function app.chi_nhanh() returns text
language sql stable security definer set search_path = public as $$
  select chi_nhanh_id from public.nhan_vien where id = auth.uid() and hoat_dong
$$;

create or replace function app.duoc_xem_chi_nhanh(cn text) returns boolean
language sql stable as $$
  select app.co_vai_tro('giam_doc') or cn = app.chi_nhanh()
$$;

create or replace function app.yeu_cau(variadic ds text[]) returns void
language plpgsql stable as $$
begin
  if auth.uid() is null then
    raise exception 'Bạn chưa đăng nhập.' using errcode = '42501';
  end if;
  if not (app.vai_tro() && ds) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501';
  end if;
end $$;

create or replace function app.yeu_cau_chi_nhanh(cn text) returns void
language plpgsql stable as $$
begin
  if not app.duoc_xem_chi_nhanh(cn) then
    raise exception 'Bạn không thuộc chi nhánh %.', cn using errcode = '42501';
  end if;
end $$;

create or replace function app.cai_dat_so(k text, mac_dinh numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (gia_tri #>> '{}')::numeric from public.cai_dat where khoa = k), mac_dinh)
$$;

create or replace function app.thang_da_chot(cn text, d date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chot_thang
                 where chi_nhanh_id = cn and thang = date_trunc('month', d)::date)
$$;

create or replace function app.yeu_cau_thang_mo(cn text, d date) returns void
language plpgsql stable as $$
begin
  if app.thang_da_chot(cn, d) then
    raise exception 'Tháng %/% đã chốt sổ, không ghi hay sửa được. Hãy ghi điều chỉnh vào tháng đang mở.',
      extract(month from d), extract(year from d);
  end if;
end $$;

create or replace function public.vat_ty_le(d date) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select ty_le from public.thue_suat_vat where ap_dung_tu <= d
                   order by ap_dung_tu desc limit 1), 0)
$$;

-- Tiền có VAT của một dòng (chỉ dòng xuất hóa đơn mới cộng VAT)
create or replace function public.tien_co_vat(so_tien numeric, xuat_hd boolean, ngay date) returns numeric
language sql stable as $$
  select case when so_tien is null then 0
              when xuat_hd then round(so_tien * (1 + public.vat_ty_le(coalesce(ngay, current_date))))
              else so_tien end
$$;

-- Biển số: '50h - 923.61' -> '50H92361'
create or replace function public.bien_so_gon(bs text) returns text
language sql immutable as $$
  select nullif(regexp_replace(upper(coalesce(bs,'')), '[^0-9A-Z]', '', 'g'), '')
$$;

-- '50H92361' -> '50H-923.61' ; '51B12345' -> '51B-123.45' ; '51D1234' -> '51D-1234'
create or replace function public.bien_so_hien_thi(bs text) returns text
language plpgsql immutable as $$
declare m text[];
begin
  if bs is null then return null; end if;
  -- ưu tiên dạng xe ô tô: 2 số + 1–2 chữ + 4–5 số (50H-923.61); sau đó dạng có số trong sê-ri (59X1-123.45)
  m := regexp_match(bs, '^([0-9]{2}[A-Z]{1,2})([0-9]{4,5})$');
  if m is null then m := regexp_match(bs, '^([0-9]{2}[A-Z]{1,2}[0-9])([0-9]{4,5})$'); end if;
  if m is null then return bs; end if;
  if length(m[2]) = 5 then
    return m[1] || '-' || substr(m[2],1,3) || '.' || substr(m[2],4,2);
  end if;
  return m[1] || '-' || m[2];
end $$;

-- 1234567 -> '1.234.567'
create or replace function app.vnd(n numeric) returns text
language sql immutable as $$ select replace(to_char(coalesce(n,0), 'FM999G999G999G990'), ',', '.') $$;

create or replace function app.ghi_nhat_ky(p_ho_so bigint, p_tu text, p_sang text, p_ghi_chu text) returns void
language sql security definer set search_path = public as $$
  insert into public.ho_so_nhat_ky (ho_so_id, boi, tu_trang_thai, sang_trang_thai, ghi_chu)
  values (p_ho_so, auth.uid(), p_tu, p_sang, p_ghi_chu)
$$;

create or replace function app.doi_trang_thai(p_ho_so bigint, p_sang text, p_ghi_chu text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_tu text;
begin
  select trang_thai into v_tu from public.ho_so where id = p_ho_so for update;
  if v_tu is distinct from p_sang then
    update public.ho_so set trang_thai = p_sang, cap_nhat_luc = now() where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, v_tu, p_sang, p_ghi_chu);
  end if;
end $$;

-- Lấy hồ sơ, khóa dòng, kiểm tra chi nhánh
create or replace function app.lay_ho_so(p_id bigint) returns public.ho_so
language plpgsql security definer set search_path = public as $$
declare r public.ho_so;
begin
  select * into r from public.ho_so where id = p_id for update;
  if not found then raise exception 'Không tìm thấy hồ sơ.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Tiền của một hồ sơ
-- ---------------------------------------------------------------------
create or replace function app.tien_ho_so(p_id bigint)
returns table (
  bh_duyet numeric, khach_duyet numeric, phai_thu_bh numeric, phai_thu_khach numeric,
  da_thu_bh numeric, da_thu_khach numeric, con_no_bh numeric, con_no_khach numeric)
language sql stable security definer set search_path = public as $$
  with d as (
    select
      coalesce(sum(public.tien_co_vat(gia_duyet, true, ngay_duyet)) filter (where nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(public.tien_co_vat(gia_duyet, xuat_hd, ngay_duyet)) filter (where nguoi_tra = 'khach'), 0) as kh
    from public.hang_muc
    where ho_so_id = p_id and trang_thai in ('duyet','dang_lam','xong')
  ), t as (
    select
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0) as kh
    from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
    where pb.ho_so_id = p_id and p.trang_thai = 'hieu_luc'
  )
  select d.bh, d.kh,
         d.bh - h.khau_tru_giam_tru,
         d.kh + h.khau_tru_giam_tru - h.giam_gia,
         t.bh, t.kh,
         d.bh - h.khau_tru_giam_tru - t.bh,
         d.kh + h.khau_tru_giam_tru - h.giam_gia - t.kh
  from d, t, public.ho_so h where h.id = p_id
$$;

-- Bản dùng cho giao diện: chỉ nhân viên văn phòng xem được tiền
create or replace function public.tien_ho_so(p_id bigint)
returns table (
  bh_duyet numeric, khach_duyet numeric, phai_thu_bh numeric, phai_thu_khach numeric,
  da_thu_bh numeric, da_thu_khach numeric, con_no_bh numeric, con_no_khach numeric)
language sql stable security definer set search_path = public as $$
  select * from app.tien_ho_so(p_id) where app.la_nhan_vien()
$$;

-- Tự đóng hồ sơ khi đã giao và hết nợ; tự mở lại nếu phát sinh nợ (ví dụ hủy phiếu thu)
create or replace function app.cap_nhat_dong(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; co_bh boolean;
begin
  select * into h from public.ho_so where id = p_id;
  if h.trang_thai not in ('da_giao','da_gui_hs','dong') then return; end if;
  select * into t from app.tien_ho_so(p_id);
  co_bh := t.phai_thu_bh > 0;
  if t.con_no_bh <= 0 and t.con_no_khach <= 0 and (not co_bh or h.gui_hs_ngay is not null) then
    perform app.doi_trang_thai(p_id, 'dong', 'Tự đóng: đã giao xe và hết công nợ');
  elsif h.trang_thai = 'dong' then
    perform app.doi_trang_thai(p_id,
      case when h.gui_hs_ngay is not null then 'da_gui_hs' else 'da_giao' end,
      'Mở lại: phát sinh công nợ');
  end if;
end $$;

-- =====================================================================
-- BƯỚC 1. TIẾP NHẬN XE
-- =====================================================================
create or replace function public.tiep_nhan_xe(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ngay timestamptz := coalesce((p->>'ngay_vao')::timestamptz, now());
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_nguon text := p->>'nguon_tt';
  v_gdv public.giam_dinh_vien;
  v_kh bigint; v_xe bigint; v_ma text; v_goc text; v_n int; v_id bigint; v_mo text;
  v_loai text := coalesce(p->>'loai', 'sua_chua');
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  if v_cn is null then raise exception 'Tài khoản chưa gắn chi nhánh.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);

  -- 10 thông tin bắt buộc
  if nullif(trim(p->>'ten_khach'),'') is null then raise exception 'Thiếu tên khách.'; end if;
  if v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if (p->>'dong_xe_id') is null then raise exception 'Chưa chọn loại xe.'; end if;
  if v_nguon not in ('bao_hiem','khach','bao_hiem_khach') or v_nguon is null then
    raise exception 'Chưa chọn bảo hiểm nào hay khách lẻ.'; end if;
  if nullif(trim(p->>'tinh_trang_xe'),'') is null then raise exception 'Thiếu tình trạng chung của xe.'; end if;
  if nullif(trim(p->>'tu_van'),'') is null then raise exception 'Thiếu mục những gì có thể tư vấn (ghi "Không" nếu không có).'; end if;
  if v_nguon <> 'khach' then
    if (p->>'hang_bh_id') is null then raise exception 'Chưa chọn hãng bảo hiểm.'; end if;
    if (p->>'gdv_id') is null then raise exception 'Chưa chọn giám định viên.'; end if;
    if (p->>'han_bao_hiem') is null then raise exception 'Thiếu ngày hết hạn bảo hiểm.'; end if;
    select * into v_gdv from public.giam_dinh_vien where id = (p->>'gdv_id')::bigint;
    if v_gdv.la_cho_them and nullif(trim(p->>'gdv_ten_tam'),'') is null then
      raise exception 'Chọn "GDV mới – chờ thêm" thì phải ghi tên giám định viên.';
    end if;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so';
  end if;
  if v_loai = 'bao_hanh' and (p->>'ho_so_goc_id') is null then
    raise exception 'Hồ sơ bảo hành phải chọn hồ sơ cũ.'; end if;

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
        han_bao_hiem = coalesce((p->>'han_bao_hiem')::date, han_bao_hiem)
      where id = v_xe;
    end if;
  end if;
  if v_xe is null then
    insert into public.xe (bien_so, dong_xe_id, mau, khach_hang_id, han_bao_hiem)
    values (v_bs, (p->>'dong_xe_id')::bigint, nullif(trim(p->>'mau'),''), v_kh, (p->>'han_bao_hiem')::date)
    returning id into v_xe;
  end if;

  if v_loai = 'bao_hanh' and not exists (select 1 from public.ho_so where id = (p->>'ho_so_goc_id')::bigint and xe_id = v_xe) then
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
    hang_bh_id, van_phong_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, tinh_trang_xe, tu_van, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'van_phong_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), auth.uid())
  returning id into v_id;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', 'Tiếp nhận xe');
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

-- Sửa thông tin khách / xe / bảo hiểm trên hồ sơ (CVDV, kế toán, quản lý chung)
create or replace function public.sua_thong_tin_ho_so(p_id bigint, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_dt text; v_gdv public.giam_dinh_vien;
begin
  perform app.yeu_cau('cvdv','ke_toan','quan_ly','giam_doc');
  h := app.lay_ho_so(p_id);
  if p ? 'ten_khach' or p ? 'dien_thoai' then
    v_dt := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
    if p ? 'dien_thoai' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số.'; end if;
    update public.khach_hang set
      ten = coalesce(nullif(trim(p->>'ten_khach'),''), ten),
      dien_thoai = case when p ? 'dien_thoai' then v_dt else dien_thoai end
    where id = h.khach_hang_id;
  end if;
  if p ? 'gdv_id' then
    select * into v_gdv from public.giam_dinh_vien where id = (p->>'gdv_id')::bigint;
    if v_gdv.la_cho_them and nullif(trim(p->>'gdv_ten_tam'),'') is null then
      raise exception 'Chọn "GDV mới – chờ thêm" thì phải ghi tên giám định viên.'; end if;
  end if;
  update public.ho_so set
    hang_bh_id      = case when p ? 'hang_bh_id' then (p->>'hang_bh_id')::bigint else hang_bh_id end,
    van_phong_bh_id = case when p ? 'van_phong_bh_id' then (p->>'van_phong_bh_id')::bigint else van_phong_bh_id end,
    gdv_id          = case when p ? 'gdv_id' then (p->>'gdv_id')::bigint else gdv_id end,
    gdv_ten_tam     = case when p ? 'gdv_id' then case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end else gdv_ten_tam end,
    han_bao_hiem    = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end,
    tinh_trang_xe   = coalesce(nullif(trim(p->>'tinh_trang_xe'),''), tinh_trang_xe),
    tu_van          = coalesce(nullif(trim(p->>'tu_van'),''), tu_van),
    hen_giao        = case when p ? 'hen_giao' then (p->>'hen_giao')::timestamptz else hen_giao end,
    cap_nhat_luc    = now()
  where id = p_id;
  update public.xe set
    dong_xe_id   = case when p ? 'dong_xe_id' then (p->>'dong_xe_id')::bigint else dong_xe_id end,
    mau          = case when p ? 'mau' then nullif(trim(p->>'mau'),'') else mau end,
    han_bao_hiem = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end
  where id = h.xe_id;
  perform app.ghi_nhat_ky(p_id, h.trang_thai, h.trang_thai, 'Sửa thông tin: ' || (select string_agg(k, ', ') from jsonb_object_keys(p) k));
end $$;

-- Ghi nhận tệp (ảnh, biên bản) đã tải lên kho 'ho-so-xe'
create or replace function public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text) returns bigint
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_id bigint;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, p_loai, p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $$;

-- =====================================================================
-- BƯỚC 2. BÁO GIÁ (và báo giá bổ sung khi phát sinh)
-- dong: [{ten, nhom, nguoi_tra, gia_bao, xuat_hd}]
-- =====================================================================
create or replace function public.luu_bao_gia(p_ho_so bigint, dong jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_lan int; d jsonb; v_nguoi text; v_xuat boolean;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if jsonb_typeof(dong) <> 'array' or jsonb_array_length(dong) = 0 then
    raise exception 'Báo giá phải có ít nhất một dòng.'; end if;

  if h.trang_thai in ('tiep_nhan','bao_gia') then
    v_lan := 0;
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'tiep_nhan') then
      raise exception 'Chưa có ảnh nhận xe. Chụp ảnh nhận xe trước khi lập báo giá.';
    end if;
  elsif h.trang_thai in ('da_duyet','dang_sua','cho_kcs') then
    select coalesce(max(lan_bao_gia), 0) + 1 into v_lan from public.hang_muc where ho_so_id = p_ho_so;
  else
    raise exception 'Hồ sơ đang ở bước "%", không lập báo giá được.', h.trang_thai;
  end if;

  for d in select * from jsonb_array_elements(dong) loop
    v_nguoi := coalesce(d->>'nguoi_tra', case when h.nguon_tt = 'khach' then 'khach' else 'bao_hiem' end);
    if h.nguon_tt = 'khach' and v_nguoi = 'bao_hiem' then
      raise exception 'Xe khách lẻ không có dòng bảo hiểm trả.'; end if;
    if nullif(trim(d->>'ten'),'') is null then raise exception 'Dòng báo giá thiếu tên hạng mục.'; end if;
    if (d->>'gia_bao') is null or (d->>'gia_bao')::numeric < 0 then raise exception 'Dòng "%" thiếu giá.', d->>'ten'; end if;
    v_xuat := case when v_nguoi = 'bao_hiem' then true else coalesce((d->>'xuat_hd')::boolean, false) end;
    insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd)
    values (p_ho_so, v_lan, trim(d->>'ten'), d->>'nhom', v_nguoi, (d->>'gia_bao')::numeric, v_xuat);
  end loop;

  if h.trang_thai = 'tiep_nhan' then
    perform app.doi_trang_thai(p_ho_so, 'bao_gia', 'Lập báo giá');
  elsif v_lan > 0 then
    update public.phat_sinh set da_xu_ly = true where ho_so_id = p_ho_so and not da_xu_ly;
    if h.trang_thai = 'cho_kcs' then
      perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Báo giá bổ sung lần ' || v_lan);
    else
      perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo giá bổ sung lần ' || v_lan);
    end if;
  end if;
  return v_lan;
end $$;

create or replace function public.xoa_hang_muc(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  select * into r from public.hang_muc where id = p_id;
  perform app.lay_ho_so(r.ho_so_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Chỉ xóa được dòng chưa duyệt.'; end if;
  delete from public.hang_muc where id = p_id;
end $$;

-- =====================================================================
-- BƯỚC 3. DUYỆT GIÁ
-- ket_qua: [{id, dong_y: true/false, gia_duyet}]
-- =====================================================================
create or replace function public.duyet_gia(p_ho_so bigint, p_ngay date, ket_qua jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
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

-- =====================================================================
-- BƯỚC 4. LỆNH SỬA CHỮA
-- phan_cong: [{id, to_id, nguoi_lam}]
-- =====================================================================
create or replace function public.lap_lenh_sua_chua(p_ho_so bigint, p_hen_giao timestamptz, phan_cong jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('da_duyet','dang_sua') then
    raise exception 'Chưa duyệt giá thì chưa lập được lệnh sửa chữa.'; end if;
  if p_hen_giao is null and h.hen_giao is null then raise exception 'Thiếu giờ hẹn giao xe.'; end if;
  if jsonb_typeof(phan_cong) <> 'array' or jsonb_array_length(phan_cong) = 0 then
    raise exception 'Chưa giao hạng mục nào cho tổ.'; end if;

  for d in select * from jsonb_array_elements(phan_cong) loop
    select * into r from public.hang_muc where id = (d->>'id')::bigint and ho_so_id = p_ho_so for update;
    if not found then raise exception 'Dòng không thuộc hồ sơ này.'; end if;
    if r.trang_thai <> 'duyet' then raise exception 'Dòng "%" chưa được duyệt hoặc đã giao.', r.ten; end if;
    if (d->>'to_id') is null then raise exception 'Dòng "%" chưa chọn tổ.', r.ten; end if;
    update public.hang_muc set trang_thai = 'dang_lam', to_id = d->>'to_id', nguoi_lam = nullif(trim(d->>'nguoi_lam'),'')
    where id = r.id;
  end loop;

  update public.ho_so set hen_giao = coalesce(p_hen_giao, hen_giao) where id = p_ho_so;
  if h.trang_thai = 'da_duyet' then
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Lập lệnh sửa chữa');
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Giao thêm hạng mục cho tổ');
  end if;
end $$;

-- =====================================================================
-- BƯỚC 6. SỬA CHỮA: báo xong từng hạng mục, báo phát sinh
-- =====================================================================
create or replace function public.bao_xong_hang_muc(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hang_muc; h public.ho_so; v_to text;
begin
  select * into r from public.hang_muc where id = p_id for update;
  if not found then raise exception 'Không tìm thấy hạng mục.'; end if;
  if app.co_vai_tro('cvdv','quan_ly','giam_doc') then
    null;
  elsif app.co_vai_tro('truong_nhom') then
    select to_id into v_to from public.nhan_vien where id = auth.uid();
    if r.to_id is distinct from v_to then raise exception 'Hạng mục này không thuộc tổ của bạn.' using errcode = '42501'; end if;
  else
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501';
  end if;
  h := app.lay_ho_so(r.ho_so_id);
  if r.trang_thai <> 'dang_lam' then raise exception 'Hạng mục "%" không ở trạng thái đang làm.', r.ten; end if;
  update public.hang_muc set trang_thai = 'xong', xong_luc = now() where id = p_id;

  if h.trang_thai = 'dang_sua' and not exists (
      select 1 from public.hang_muc where ho_so_id = r.ho_so_id and trang_thai in ('cho_duyet','duyet','dang_lam')) then
    perform app.doi_trang_thai(r.ho_so_id, 'cho_kcs', 'Xong các hạng mục, chờ KCS');
  end if;
end $$;

create or replace function public.bao_phat_sinh(p_ho_so bigint, p_mo_ta text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  if not (app.co_vai_tro('truong_nhom','cvdv','quan_ly','giam_doc')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('dang_sua','cho_kcs') then raise exception 'Xe không ở bước sửa chữa.'; end if;
  if nullif(trim(p_mo_ta),'') is null then raise exception 'Mô tả hư hỏng phát sinh.'; end if;
  insert into public.phat_sinh (ho_so_id, mo_ta, boi) values (p_ho_so, trim(p_mo_ta), auth.uid());
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo phát sinh: ' || trim(p_mo_ta));
end $$;

-- Bảng việc cho trưởng nhóm: chỉ xe và hạng mục của tổ mình, không có tiền và SĐT
create or replace function public.bang_viec_to() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select to_id, chi_nhanh_id into v_to, v_cn from public.nhan_vien where id = auth.uid();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ho_so_id', h.id, 'ma', h.ma, 'bien_so', public.bien_so_hien_thi(x.bien_so),
      'xe', concat_ws(' ', hx.ten, dx.ten, x.mau), 'hen_giao', h.hen_giao, 'trang_thai', h.trang_thai,
      'tinh_trang_xe', h.tinh_trang_xe,
      'hang_muc', (select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'nhom', m.nhom, 'to_id', m.to_id,
                     'nguoi_lam', m.nguoi_lam, 'trang_thai', m.trang_thai) order by m.id)
                   from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('dang_lam','xong')
                     and (v_to is null or m.to_id = v_to)))
      order by h.hen_giao nulls last)
    from public.ho_so h
    join public.xe x on x.id = h.xe_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    where h.trang_thai in ('dang_sua','cho_kcs')
      and (app.co_vai_tro('giam_doc') or h.chi_nhanh_id = v_cn)
      and (v_to is null or not app.co_vai_tro('truong_nhom') or exists (
            select 1 from public.hang_muc m where m.ho_so_id = h.id and m.to_id = v_to and m.trang_thai in ('dang_lam','xong')))
  ), '[]'::jsonb);
end $$;

-- =====================================================================
-- BƯỚC 7. KCS
-- =====================================================================
create or replace function public.kcs(p_ho_so bigint, p_dat boolean, p_loi text default null, p_lam_lai bigint[] default null) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'cho_kcs' then raise exception 'Xe chưa sửa xong, chưa KCS được.'; end if;
  insert into public.kcs (ho_so_id, dat, loi, boi) values (p_ho_so, p_dat, nullif(trim(p_loi),''), auth.uid());
  if p_dat then
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'kcs') then
      raise exception 'Chưa có ảnh sau sửa. Chụp ảnh trước khi ký KCS.'; end if;
    perform app.doi_trang_thai(p_ho_so, 'dat_kcs', 'Đạt KCS');
  else
    if nullif(trim(p_loi),'') is null then raise exception 'Ghi lỗi cần làm lại.'; end if;
    if p_lam_lai is null or cardinality(p_lam_lai) = 0 then raise exception 'Chọn hạng mục phải làm lại.'; end if;
    update public.hang_muc set trang_thai = 'dang_lam', xong_luc = null
    where ho_so_id = p_ho_so and id = any(p_lam_lai) and trang_thai = 'xong';
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Chưa đạt KCS: ' || trim(p_loi));
  end if;
end $$;

-- =====================================================================
-- BƯỚC 8. THANH TOÁN, GIAO XE
-- =====================================================================
create or replace function public.duyet_giam_gia(p_ho_so bigint, p_so_tien numeric, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai in ('dong','huy') then raise exception 'Hồ sơ đã đóng.'; end if;
  if p_so_tien < 0 then raise exception 'Số tiền giảm giá không hợp lệ.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do giảm giá.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  if h.giam_gia_ngay is not null then perform app.yeu_cau_thang_mo(h.chi_nhanh_id, h.giam_gia_ngay); end if;
  update public.ho_so set giam_gia = p_so_tien, giam_gia_ngay = current_date, giam_gia_duyet_boi = auth.uid()
  where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Duyệt giảm giá ' || p_so_tien || ' đ: ' || trim(p_ly_do));
end $$;

create or replace function public.duyet_giao_xe_con_no(p_ho_so bigint) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  update public.ho_so set cho_giao_no_boi = auth.uid() where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Duyệt cho giao xe khi khách còn nợ');
end $$;

-- p: {khau_tru_giam_tru, so_hd_bao_hiem, so_hd_khach, cam_nhan_khach}
create or replace function public.giao_xe(p_ho_so bigint, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record;
begin
  perform app.yeu_cau('ke_toan','cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'dat_kcs' then raise exception 'Xe chưa đạt KCS thì không giao được.'; end if;
  if h.nguon_tt = 'khach' and coalesce((p->>'khau_tru_giam_tru')::numeric, 0) > 0 then
    raise exception 'Xe khách lẻ không có khấu trừ – giảm trừ.'; end if;

  update public.ho_so set
    khau_tru_giam_tru = coalesce((p->>'khau_tru_giam_tru')::numeric, khau_tru_giam_tru),
    so_hd_bao_hiem = coalesce(nullif(trim(p->>'so_hd_bao_hiem'),''), so_hd_bao_hiem),
    so_hd_khach = coalesce(nullif(trim(p->>'so_hd_khach'),''), so_hd_khach),
    cam_nhan_khach = coalesce(nullif(trim(p->>'cam_nhan_khach'),''), cam_nhan_khach)
  where id = p_ho_so;

  select * into t from app.tien_ho_so(p_ho_so);
  if t.phai_thu_bh < 0 then raise exception 'Khấu trừ – giảm trừ lớn hơn phần bảo hiểm duyệt.'; end if;
  if t.con_no_khach > 0 and h.cho_giao_no_boi is null then
    raise exception 'Khách còn nợ % đ. Cần giám đốc hoặc quản lý chung duyệt giao xe khi còn nợ.',
      app.vnd(t.con_no_khach);
  end if;

  update public.ho_so set giao_luc = now() where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'da_giao', 'Giao xe');
  perform app.cap_nhat_dong(p_ho_so);
end $$;

-- =====================================================================
-- BƯỚC 9. HỒ SƠ BẢO HIỂM, HOA HỒNG GDV
-- =====================================================================
create or replace function public.gui_ho_so_bh(p_ho_so bigint, p_ngay date) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then raise exception 'Xe khách lẻ không có hồ sơ bảo hiểm.'; end if;
  if h.trang_thai <> 'da_giao' then raise exception 'Chỉ gửi hồ sơ bảo hiểm sau khi đã giao xe.'; end if;
  if p_ngay is null or p_ngay > current_date then raise exception 'Ngày gửi không hợp lệ.'; end if;
  update public.ho_so set gui_hs_ngay = p_ngay where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'da_gui_hs', 'Gửi hồ sơ bảo hiểm ngày ' || to_char(p_ngay, 'DD/MM/YYYY'));
  perform app.cap_nhat_dong(p_ho_so);
end $$;

create or replace function public.nhap_hoa_hong_gdv(p_ho_so bigint, p_so_tien numeric, p_ghi_chu text default null,
  p_bo_qua_canh_bao boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; v_tl numeric := app.cai_dat_so('hoa_hong_canh_bao_ty_le', 0.15);
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.gdv_id is null then raise exception 'Hồ sơ không có giám định viên.'; end if;
  if p_so_tien is null or p_so_tien < 0 then raise exception 'Số tiền hoa hồng không hợp lệ.'; end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.bh_duyet > 0 and p_so_tien > t.bh_duyet * v_tl and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Hoa hồng % đ lớn hơn % giá duyệt bảo hiểm. Kiểm tra lại có gõ thừa số 0 không?',
      app.vnd(p_so_tien), round(v_tl * 100)::text || '%';
  end if;
  update public.ho_so set hoa_hong_gdv = p_so_tien, hoa_hong_ghi_chu = nullif(trim(p_ghi_chu),'') where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Nhập hoa hồng GDV ' || p_so_tien || ' đ');
end $$;

-- =====================================================================
-- BƯỚC 10. CHĂM SÓC SAU GIAO
-- =====================================================================
create or replace function public.ghi_cham_soc(p_ho_so bigint, p_ket_qua text, p_hen_bao_duong date default null) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.giao_luc is null then raise exception 'Xe chưa giao.'; end if;
  if nullif(trim(p_ket_qua),'') is null then raise exception 'Ghi kết quả cuộc gọi.'; end if;
  update public.ho_so set cham_soc_luc = now(), cham_soc_ket_qua = trim(p_ket_qua),
    hen_bao_duong = p_hen_bao_duong where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Gọi chăm sóc: ' || trim(p_ket_qua));
end $$;

-- =====================================================================
-- HỦY HỒ SƠ
-- =====================================================================
create or replace function public.huy_ho_so(p_ho_so bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_ngay date;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('tiep_nhan','bao_gia','da_duyet') then
    raise exception 'Xe đã vào sửa thì không hủy hồ sơ được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  for v_ngay in select distinct ngay_duyet from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'duyet' loop
    perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_ngay);
  end loop;
  update public.hang_muc set trang_thai = 'tu_choi' where ho_so_id = p_ho_so and trang_thai in ('cho_duyet','duyet');
  update public.ho_so set ly_do_huy = trim(p_ly_do) where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'huy', 'Hủy: ' || trim(p_ly_do));
end $$;

-- =====================================================================
-- DỊCH VỤ NHANH
-- =====================================================================
create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi)
  values (v_cn, v_ngay, public.bien_so_gon(p->>'bien_so'), trim(p->>'dich_vu'), nullif(trim(p->>'nguoi_lam'),''),
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.huy_dich_vu_nhanh(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.dich_vu_nhanh;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.dich_vu_nhanh where id = p_id for update;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if exists (select 1 from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
             where pb.dich_vu_nhanh_id = p_id and p.trang_thai = 'hieu_luc') then
    raise exception 'Dịch vụ đã thu tiền. Hủy phiếu thu trước.'; end if;
  update public.dich_vu_nhanh set trang_thai = 'huy' where id = p_id;
end $$;

-- =====================================================================
-- THU CHI
-- =====================================================================
create or replace function app.kiem_tra_tai_khoan(p_tk bigint, p_cn text) returns void
language plpgsql stable security definer set search_path = public as $$
declare r public.tai_khoan_quy;
begin
  select * into r from public.tai_khoan_quy where id = p_tk;
  if not found or r.chi_nhanh_id <> p_cn then raise exception 'Tài khoản quỹ không hợp lệ.'; end if;
  if not r.hoat_dong then raise exception 'Tài khoản "%" đã khóa, không ghi thêm được.', r.ten; end if;
end $$;

-- Phân bổ một phiếu vào các hồ sơ / dịch vụ nhanh, có kiểm tra vượt nợ
create or replace function app.phan_bo_phieu(p_phieu bigint, p_ds jsonb, p_tinh_chat text) returns void
language plpgsql security definer set search_path = public as $$
declare d jsonb; v_ho_so bigint; v_dvn bigint; v_nguoi text; v_tien numeric; t record; v_tong numeric; v_phieu public.phieu_thu_chi;
  v_ds_ho_so bigint[] := '{}';
begin
  select * into v_phieu from public.phieu_thu_chi where id = p_phieu;
  for d in select * from jsonb_array_elements(coalesce(p_ds, '[]'::jsonb)) loop
    v_ho_so := (d->>'ho_so_id')::bigint; v_dvn := (d->>'dich_vu_nhanh_id')::bigint;
    v_tien := (d->>'so_tien')::numeric;
    if v_tien is null or v_tien <= 0 then raise exception 'Số tiền phân bổ phải lớn hơn 0.'; end if;
    if v_ho_so is not null then
      perform app.lay_ho_so(v_ho_so);
      v_nguoi := case p_tinh_chat when 'thu_bao_hiem' then 'bao_hiem' else 'khach' end;
      if p_tinh_chat in ('thu_bao_hiem','thu_khach') then
        select * into t from app.tien_ho_so(v_ho_so);
        if v_nguoi = 'bao_hiem' and v_tien > t.con_no_bh then
          raise exception 'Phân bổ % đ vượt số bảo hiểm còn nợ % đ của hồ sơ.',
            app.vnd(v_tien), app.vnd(t.con_no_bh); end if;
        if v_nguoi = 'khach' and v_tien > t.con_no_khach then
          raise exception 'Thu % đ vượt số khách còn nợ % đ của hồ sơ. Nếu là tiền cọc, chọn mục "Thu cọc".',
            app.vnd(v_tien), app.vnd(t.con_no_khach); end if;
      end if;
      insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (p_phieu, v_ho_so, v_nguoi, v_tien);
      v_ds_ho_so := v_ds_ho_so || v_ho_so;
    elsif v_dvn is not null then
      insert into public.phan_bo (phieu_id, dich_vu_nhanh_id, nguoi_tra, so_tien) values (p_phieu, v_dvn, 'khach', v_tien);
    else
      raise exception 'Dòng phân bổ thiếu hồ sơ.';
    end if;
  end loop;
  select coalesce(sum(so_tien),0) into v_tong from public.phan_bo where phieu_id = p_phieu;
  if v_tong > v_phieu.so_tien then raise exception 'Tổng phân bổ lớn hơn số tiền của phiếu.'; end if;
  perform app.cap_nhat_dong(x) from unnest(v_ds_ho_so) x;
end $$;

-- p: {ngay, tai_khoan_id, muc_id, so_tien, noi_dung, hang_bh_id, don_vi_lien_quan_id, phan_bo:[{ho_so_id|dich_vu_nhanh_id, so_tien}]}
create or replace function public.lap_phieu_thu(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  m public.muc_thu_chi; v_id bigint; v_tong numeric;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'thu' then raise exception 'Chưa chọn mục thu.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if m.tinh_chat = 'thu_bao_hiem' and (p->>'hang_bh_id') is null then raise exception 'Chọn hãng bảo hiểm chuyển tiền.'; end if;
  if m.tinh_chat = 'thu_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;

  select coalesce(sum((x->>'so_tien')::numeric), 0) into v_tong from jsonb_array_elements(coalesce(p->'phan_bo','[]'::jsonb)) x;
  if m.tinh_chat in ('thu_khach','thu_coc','thu_dich_vu_nhanh') and v_tong <> (p->>'so_tien')::numeric then
    raise exception 'Tiền khách trả phải gắn đủ vào hồ sơ xe hoặc dịch vụ (đang gắn % / % đ).',
      app.vnd(v_tong), app.vnd((p->>'so_tien')::numeric);
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung,
    hang_bh_id, don_vi_lien_quan_id, tao_boi)
  values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, m.id, (p->>'so_tien')::numeric, nullif(trim(p->>'noi_dung'),''),
    (p->>'hang_bh_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, auth.uid())
  returning id into v_id;
  perform app.phan_bo_phieu(v_id, p->'phan_bo', m.tinh_chat);
  return v_id;
end $$;

-- Chia tiếp phần chưa phân bổ của phiếu thu bảo hiểm (khi có bảng kê)
create or replace function public.phan_bo_them(p_phieu bigint, p_ds jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; m public.muc_thu_chi;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_phieu for update;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.loai <> 'thu' or r.trang_thai <> 'hieu_luc' then raise exception 'Phiếu không hợp lệ.'; end if;
  select * into m from public.muc_thu_chi where id = r.muc_id;
  perform app.phan_bo_phieu(p_phieu, p_ds, m.tinh_chat);
end $$;

create or replace function public.lap_phieu_chuyen(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_den_id')::bigint, v_cn);
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, tai_khoan_den_id, so_tien, noi_dung, tao_boi)
  values (v_cn, v_ngay, 'chuyen', (p->>'tai_khoan_id')::bigint, (p->>'tai_khoan_den_id')::bigint,
          (p->>'so_tien')::numeric, nullif(trim(p->>'noi_dung'),''), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.huy_phieu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; x bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai = 'huy' then raise exception 'Phiếu đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) where id = p_id;
  if r.de_nghi_chi_id is not null then
    update public.de_nghi_chi set trang_thai = 'da_duyet' where id = r.de_nghi_chi_id;
  end if;
  for x in select distinct ho_so_id from public.phan_bo where phieu_id = p_id and ho_so_id is not null loop
    perform app.cap_nhat_dong(x);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Đề nghị chi → duyệt → chi
-- ---------------------------------------------------------------------
create or replace function public.lap_de_nghi_chi(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); m public.muc_thu_chi; v_id bigint;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'chi' then raise exception 'Chưa chọn mục chi.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if nullif(trim(p->>'noi_dung'),'') is null then raise exception 'Ghi nội dung chi.'; end if;
  if (m.can_ho_so or m.tinh_chat in ('tra_hoa_hong','tra_coc')) and (p->>'ho_so_id') is null then
    raise exception 'Mục "%" phải gắn hồ sơ xe.', m.ten; end if;
  if m.tinh_chat = 'tra_hoa_hong' and (p->>'gdv_id') is null then raise exception 'Chọn giám định viên nhận hoa hồng.'; end if;
  if m.tinh_chat = 'tra_ncc' and (p->>'nha_cung_cap_id') is null then raise exception 'Chọn nhà cung cấp.'; end if;
  if m.tinh_chat = 'tra_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;
  if coalesce((p->>'vat_dau_vao')::numeric, 0) > (p->>'so_tien')::numeric then raise exception 'VAT đầu vào lớn hơn số tiền.'; end if;

  insert into public.de_nghi_chi (chi_nhanh_id, ngay, nguoi_de_nghi, muc_id, so_tien, vat_dau_vao, noi_dung, nguoi_nhan,
    ho_so_id, nha_cung_cap_id, gdv_id, don_vi_lien_quan_id)
  values (v_cn, coalesce((p->>'ngay')::date, current_date), auth.uid(), m.id, (p->>'so_tien')::numeric,
    coalesce((p->>'vat_dau_vao')::numeric, 0), trim(p->>'noi_dung'), nullif(trim(p->>'nguoi_nhan'),''),
    (p->>'ho_so_id')::bigint, (p->>'nha_cung_cap_id')::bigint, (p->>'gdv_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint)
  returning id into v_id;
  return v_id;
end $$;

-- Quản lý chung duyệt đến hạn mức (mặc định 2 triệu), trên mức chỉ giám đốc. Không tự duyệt phiếu mình lập.
create or replace function public.duyet_de_nghi_chi(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; v_muc numeric := app.cai_dat_so('han_muc_chi_quan_ly', 2000000);
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị này đã được xử lý.'; end if;
  if r.nguoi_de_nghi = auth.uid() then raise exception 'Không được tự duyệt đề nghị do mình lập.'; end if;
  if r.so_tien > v_muc and not app.co_vai_tro('giam_doc') then
    raise exception 'Khoản trên % đ chỉ giám đốc được duyệt.', app.vnd(v_muc) using errcode = '42501';
  end if;
  if not p_dong_y and nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.'; end if;
  update public.de_nghi_chi set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
end $$;

create or replace function public.huy_de_nghi_chi(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi;
begin
  select * into r from public.de_nghi_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  if r.nguoi_de_nghi <> auth.uid() and not app.co_vai_tro('giam_doc','ke_toan') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if r.trang_thai not in ('cho_duyet','da_duyet') then raise exception 'Đề nghị đã chi hoặc đã bị từ chối.'; end if;
  update public.de_nghi_chi set trang_thai = 'huy' where id = p_id;
end $$;

create or replace function public.chi_tien(p_de_nghi bigint, p_tai_khoan bigint, p_ngay date default current_date) returns bigint
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; m public.muc_thu_chi; v_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.de_nghi_chi where id = p_de_nghi for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'da_duyet' then raise exception 'Đề nghị chưa được duyệt thì chưa chi được.'; end if;
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, p_ngay);
  if p_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan(p_tai_khoan, r.chi_nhanh_id);
  select * into m from public.muc_thu_chi where id = r.muc_id;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, vat_dau_vao, noi_dung,
    nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, de_nghi_chi_id, tao_boi)
  values (r.chi_nhanh_id, p_ngay, 'chi', p_tai_khoan, r.muc_id, r.so_tien, r.vat_dau_vao,
    concat_ws(' – ', r.noi_dung, r.nguoi_nhan), r.nha_cung_cap_id, r.gdv_id, r.don_vi_lien_quan_id, r.id, auth.uid())
  returning id into v_id;

  if m.tinh_chat = 'tra_coc' then   -- trả lại cọc cho khách: giảm phần khách đã trả
    insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (v_id, r.ho_so_id, 'khach', r.so_tien);
    perform app.cap_nhat_dong(r.ho_so_id);
  end if;
  update public.de_nghi_chi set trang_thai = 'da_chi' where id = p_de_nghi;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Nhân viên, bảng lương
-- ---------------------------------------------------------------------
-- Tạo hồ sơ nhân viên trống khi có tài khoản đăng nhập mới
create or replace function app.tao_nhan_vien_moi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.nhan_vien (id, email, ho_ten)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'ho_ten', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists tao_nhan_vien_moi on auth.users;
create trigger tao_nhan_vien_moi after insert on auth.users for each row execute function app.tao_nhan_vien_moi();

create or replace function public.luu_nhan_vien(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_vt text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(p->'vai_tro') x), '{}');
begin
  perform app.yeu_cau('giam_doc');
  if p_id = auth.uid() and not ('giam_doc' = any(v_vt)) then
    raise exception 'Không tự bỏ quyền giám đốc của chính mình được.'; end if;
  if 'truong_nhom' = any(v_vt) and (p->>'to_id') is null then raise exception 'Trưởng nhóm phải chọn tổ.'; end if;
  if 'co_dong' = any(v_vt) and cardinality(v_vt) > 1 then
    raise exception 'Tài khoản cổ đông chỉ có một vai trò cổ đông.'; end if;
  update public.nhan_vien set
    ho_ten = coalesce(nullif(trim(p->>'ho_ten'),''), ho_ten),
    chi_nhanh_id = p->>'chi_nhanh_id',
    vai_tro = v_vt,
    to_id = p->>'to_id',
    hoat_dong = coalesce((p->>'hoat_dong')::boolean, true)
  where id = p_id;
  if not found then raise exception 'Không tìm thấy tài khoản.'; end if;
end $$;

create or replace function public.nhap_bang_luong(p_thang date, p_tong numeric, p_chi_nhanh text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_thang);
  insert into public.bang_luong_thang (chi_nhanh_id, thang, tong_luong, nhap_boi) values (v_cn, v_thang, p_tong, auth.uid())
  on conflict (chi_nhanh_id, thang) do update set tong_luong = excluded.tong_luong, nhap_boi = excluded.nhap_boi, nhap_luc = now();
end $$;

-- ---------------------------------------------------------------------
-- Tra cứu xe theo biển số khi tiếp nhận: tự điền khách, loại xe; báo hồ sơ đang mở
-- ---------------------------------------------------------------------
create or replace function public.tra_cuu_xe(p_bien_so text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_bs text := public.bien_so_gon(p_bien_so); r jsonb;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if v_bs is null then return null; end if;
  select jsonb_build_object(
    'xe_id', x.id, 'bien_so', public.bien_so_hien_thi(x.bien_so), 'dong_xe_id', x.dong_xe_id,
    'hang_xe_id', dx.hang_xe_id, 'mau', x.mau, 'han_bao_hiem', x.han_bao_hiem,
    'ten_khach', k.ten, 'dien_thoai', k.dien_thoai,
    'so_lan_vao', (select count(*) from public.ho_so h where h.xe_id = x.id),
    'ho_so_mo', (select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'trang_thai', h.trang_thai))
                 from public.ho_so h where h.xe_id = x.id and h.trang_thai not in ('dong','huy')),
    'ho_so_gan_nhat', (select jsonb_build_object('id', h.id, 'ma', h.ma, 'nguon_tt', h.nguon_tt, 'hang_bh_id', h.hang_bh_id,
                         'van_phong_bh_id', h.van_phong_bh_id, 'gdv_id', h.gdv_id)
                       from public.ho_so h where h.xe_id = x.id order by h.id desc limit 1))
  into r
  from public.xe x
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.khach_hang k on k.id = x.khach_hang_id
  where x.bien_so = v_bs;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Kiểm quỹ cuối ngày
-- ---------------------------------------------------------------------
create or replace function public.ghi_kiem_quy(p_tai_khoan bigint, p_so_dem numeric, p_ghi_chu text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare tk public.tai_khoan_quy; v_so numeric; v_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into tk from public.tai_khoan_quy where id = p_tai_khoan;
  if not found then raise exception 'Tài khoản quỹ không hợp lệ.'; end if;
  perform app.yeu_cau_chi_nhanh(tk.chi_nhanh_id);
  if p_so_dem is null or p_so_dem < 0 then raise exception 'Nhập số tiền đếm được.'; end if;
  select so_du into v_so from public.v_so_du_quy where id = p_tai_khoan;
  if p_so_dem <> v_so and nullif(trim(p_ghi_chu),'') is null then
    raise exception 'Lệch % đ so với sổ. Ghi lý do chênh lệch.', app.vnd(p_so_dem - v_so); end if;
  insert into public.kiem_quy (chi_nhanh_id, tai_khoan_id, so_dem, so_tren_so, ghi_chu, boi)
  values (tk.chi_nhanh_id, p_tai_khoan, p_so_dem, v_so, nullif(trim(p_ghi_chu),''), auth.uid()) returning id into v_id;
  return jsonb_build_object('id', v_id, 'so_tren_so', v_so, 'chenh_lech', p_so_dem - v_so);
end $$;
