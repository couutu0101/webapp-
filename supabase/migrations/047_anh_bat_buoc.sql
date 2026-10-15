-- =====================================================================
-- 047: Ảnh / file bắt buộc ở các bước + CVDV nghiệm thu KCS (anh Thuận yêu cầu 15/10 15:09)
--  1. Tiếp nhận: 6 ảnh có tên – 4 quanh xe (nx_truoc, nx_sau, nx_trai, nx_phai) + 2 nội thất
--     (nt_truoc: táp lô, nt_sau: hàng ghế sau). Ảnh tải sau khi tạo hồ sơ, nên máy chủ kiểm ở bước kế tiếp:
--     lập báo giá (xe thường) và lập lệnh sửa chữa (cả hồ sơ bảo hành).
--  2. Báo giá: MỖI lần lưu (cả bổ sung) phải có ảnh / PDF báo giá (bước 'bao_gia') tải lên sau lần lưu báo giá trước
--     (ho_so.bao_gia_luc).
--  3. Duyệt giá xe bảo hiểm: phải có ảnh / file duyệt giá (bước 'duyet_gia') tải lên sau lần báo giá gần nhất.
--  4. KCS đạt: tối thiểu 6 ảnh KCS (tổng các lần) + sau lần chưa đạt có ít nhất 1 ảnh mới (giữ quy định 043).
--  5. CVDV được ký KCS (cùng quản lý chung, giám đốc).
-- Tương thích ngược: chỉ hồ sơ tạo từ giao diện mới (gửi bat_buoc_anh) mới bị bắt (ho_so.bat_buoc_anh); hồ sơ do giao diện
-- cũ (bản thật đang chạy) tạo vẫn như trước. Không đổi tham số hàm nào.
-- =====================================================================

alter table public.ho_so add column if not exists bat_buoc_anh boolean not null default false;
alter table public.ho_so add column if not exists bao_gia_luc timestamptz;

-- Tên 6 ảnh nhận xe (dùng chung cho thông báo)
create or replace function app.anh_nhan_xe_thieu(p_ho_so bigint) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(t.ten order by t.thu_tu), '{}')
  from (values (1, 'nx_truoc', 'phía trước'), (2, 'nx_sau', 'phía sau'), (3, 'nx_trai', 'bên trái'), (4, 'nx_phai', 'bên phải'),
               (5, 'nt_truoc', 'nội thất phía trước'), (6, 'nt_sau', 'nội thất phía sau')) as t(thu_tu, buoc, ten)
  where not exists (select 1 from public.ho_so_tep f where f.ho_so_id = p_ho_so and f.buoc = t.buoc)
$$;
revoke all on function app.anh_nhan_xe_thieu(bigint) from public, anon;

create or replace function app.yeu_cau_anh_nhan_xe(p_ho_so bigint) returns void
language plpgsql stable security definer set search_path = public as $$
declare v text[] := app.anh_nhan_xe_thieu(p_ho_so);
begin
  if cardinality(v) > 0 then
    raise exception 'Chưa đủ 6 ảnh nhận xe – còn thiếu: %. Chụp bổ sung ở mục "Ảnh nhận xe" của hồ sơ.', array_to_string(v, ', ');
  end if;
end $$;
revoke all on function app.yeu_cau_anh_nhan_xe(bigint) from public, anon;

-- them_tep: thêm bước bao_gia và 6 ảnh nhận xe
CREATE OR REPLACE FUNCTION public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.ho_so; v_id bigint; v_goc text;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  v_goc := h.chi_nhanh_id || '/' || h.ma || '/';
  if p_duong_dan is null or left(p_duong_dan, length(v_goc)) <> v_goc or position('..' in p_duong_dan) > 0 then
    raise exception 'Tệp không thuộc thư mục của hồ sơ % – tải lại ảnh từ trang hồ sơ.', h.ma;
  end if;
  if p_buoc not in ('tiep_nhan','duyet_gia','phat_sinh','kcs','giao_xe','ho_so_bh','khac',
                    'bao_gia','nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau') then
    raise exception 'Bước của tệp không hợp lệ.';
  end if;
  if coalesce(p_loai, 'anh') not in ('anh','bien_ban') then raise exception 'Loại tệp không hợp lệ.'; end if;
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, coalesce(p_loai, 'anh'), p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $function$;

-- tiep_nhan_xe: ghi cờ bat_buoc_anh
CREATE OR REPLACE FUNCTION public.tiep_nhan_xe(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
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

  -- 041: hai người tiếp nhận cùng SĐT / cùng xe / cùng lúc → người sau chờ người trước ghi xong (không lỗi trùng khóa)
  perform pg_advisory_xact_lock(hashtext('khach_' || v_dt));
  if v_bs is not null then perform pg_advisory_xact_lock(hashtext('xe_' || v_bs)); end if;

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
  perform pg_advisory_xact_lock(hashtext('ma_ho_so_' || v_goc));
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
  -- 047: giao diện mới gửi bat_buoc_anh → hồ sơ này bắt 6 ảnh nhận xe, file báo giá / duyệt giá, 6 ảnh KCS
  if coalesce((p->>'bat_buoc_anh')::boolean, false) then
    update public.ho_so set bat_buoc_anh = true where id = v_id;
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'chi_nhanh_id', v_cn);
end $function$;

-- lap_bao_gia
CREATE OR REPLACE FUNCTION public.lap_bao_gia(p_ho_so bigint, dong jsonb, p_vat numeric)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare
  h public.ho_so; v_lan int; d jsonb;
  v_khach boolean; v_nguoi text; v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if jsonb_typeof(dong) <> 'array' or jsonb_array_length(dong) = 0 then
    raise exception 'Báo giá phải có ít nhất một dòng.'; end if;
  if p_vat is null or p_vat not in (0.08, 0.10, 0.12) then
    raise exception 'VAT chỉ chọn 8%%, 10%% hoặc 12%%.'; end if;

  -- 047: hồ sơ bắt ảnh → đủ 6 ảnh nhận xe và mỗi lần lưu báo giá phải có ảnh / file báo giá mới tải lên
  if h.bat_buoc_anh then
    perform app.yeu_cau_anh_nhan_xe(p_ho_so);
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'bao_gia'
                   and tai_luc > coalesce(h.bao_gia_luc, '-infinity'::timestamptz)) then
      raise exception 'Chưa có ảnh hoặc file báo giá – đính kèm ảnh / PDF báo giá rồi lưu.'; end if;
  end if;

  v_khach := h.nguon_tt = 'khach';
  v_nguoi := case when v_khach then 'khach' else 'bao_hiem' end;

  if h.trang_thai in ('tiep_nhan','bao_gia') then
    v_lan := 0;
  elsif h.trang_thai in ('da_duyet','dang_sua','cho_kcs') then
    select coalesce(max(lan_bao_gia), 0) + 1 into v_lan from public.hang_muc where ho_so_id = p_ho_so;
  else
    raise exception 'Hồ sơ đang ở bước "%", không lập báo giá được.', h.trang_thai;
  end if;
  -- Khách ngoài bảo hiểm: duyệt luôn hôm nay, nên tháng hiện tại phải còn mở sổ
  if v_khach then perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_ngay); end if;

  for d in select * from jsonb_array_elements(dong) loop
    if nullif(trim(d->>'ten'),'') is null then raise exception 'Dòng báo giá thiếu nội dung sửa chữa.'; end if;
    if (d->>'gia_bao') is null or (d->>'gia_bao')::numeric < 0 then raise exception 'Dòng "%" thiếu giá.', d->>'ten'; end if;
    insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd, ty_le_vat,
                                 trang_thai, gia_duyet, ngay_duyet)
    values (p_ho_so, v_lan, trim(d->>'ten'), coalesce(d->>'nhom', 'dong_son'), v_nguoi, (d->>'gia_bao')::numeric, true, p_vat,
            case when v_khach then 'duyet' else 'cho_duyet' end,
            case when v_khach then (d->>'gia_bao')::numeric end,
            case when v_khach then v_ngay end);
  end loop;

  if h.trang_thai in ('tiep_nhan','bao_gia') then
    if v_khach and not exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'cho_duyet') then
      perform app.doi_trang_thai(p_ho_so, 'da_duyet', 'Báo giá khách ngoài bảo hiểm – không qua duyệt giá');
    elsif h.trang_thai = 'tiep_nhan' then
      perform app.doi_trang_thai(p_ho_so, 'bao_gia', 'Lập báo giá');
    else
      perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Thêm dòng báo giá');
    end if;
  else
    update public.phat_sinh set da_xu_ly = true where ho_so_id = p_ho_so and not da_xu_ly;
    if h.trang_thai = 'cho_kcs' then
      perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Báo giá bổ sung lần ' || v_lan);
    else
      perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo giá bổ sung lần ' || v_lan);
    end if;
  end if;
  update public.ho_so set bao_gia_luc = now() where id = p_ho_so;
  return v_lan;
end $function$;

-- duyet_gia
CREATE OR REPLACE FUNCTION public.duyet_gia(p_ho_so bigint, p_ngay date, ket_qua jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
  if h.nguon_tt <> 'khach' and h.gdv_id is null then
    raise exception 'Chưa có giám định viên. Bấm "Sửa" ở mục Thông tin xe và khách để ghi GDV trước khi nhập kết quả duyệt giá.'; end if;
  -- 047: xe bảo hiểm của hồ sơ bắt ảnh → phải có ảnh / file duyệt giá của bảo hiểm tải lên sau lần báo giá gần nhất
  if h.bat_buoc_anh and h.nguon_tt <> 'khach'
     and not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'duyet_gia'
                     and tai_luc > coalesce(h.bao_gia_luc, '-infinity'::timestamptz)) then
    raise exception 'Chưa có ảnh hoặc file duyệt giá của bảo hiểm – đính kèm bản duyệt giá rồi lưu.'; end if;
  if p_ngay is null then raise exception 'Thiếu ngày duyệt.'; end if;
  if p_ngay > current_date then raise exception 'Ngày duyệt không được sau hôm nay.'; end if;
  if p_ngay < (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date then
    raise exception 'Ngày duyệt % trước ngày nhận xe % – kiểm tra lại ngày (dd/mm/yyyy).',
      to_char(p_ngay, 'DD/MM/YYYY'), to_char(h.ngay_vao at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY'); end if;
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
end $function$;

-- lap_lenh_sua_chua
CREATE OR REPLACE FUNCTION public.lap_lenh_sua_chua(p_ho_so bigint, p_hen_giao timestamp with time zone, phan_cong jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('da_duyet','dang_sua') then
    raise exception 'Chưa duyệt giá thì chưa lập được lệnh sửa chữa.'; end if;
  if h.bat_buoc_anh then perform app.yeu_cau_anh_nhan_xe(p_ho_so); end if;   -- 047 (cả hồ sơ bảo hành)
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
end $function$;

-- kcs
CREATE OR REPLACE FUNCTION public.kcs(p_ho_so bigint, p_dat boolean, p_loi text DEFAULT NULL::text, p_lam_lai bigint[] DEFAULT NULL::bigint[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare h public.ho_so; v_truot timestamptz; v_so_anh int;
begin
  perform app.yeu_cau('quan_ly','giam_doc','cvdv');   -- 047: CVDV cũng nghiệm thu KCS
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'cho_kcs' then raise exception 'Xe chưa sửa xong, chưa KCS được.'; end if;
  if p_dat then
    if exists (select 1 from public.phat_sinh where ho_so_id = p_ho_so and not da_xu_ly) then
      raise exception 'Còn hư hỏng phát sinh chưa xử lý – CVDV lập báo giá bổ sung hoặc ghi "Không cần làm thêm" trước khi KCS đạt.'; end if;
    select max(luc) into v_truot from public.kcs where ho_so_id = p_ho_so and not dat;
    -- 047: hồ sơ bắt ảnh → tối thiểu 6 ảnh KCS (cộng cả các lần), sau lần chưa đạt thêm ít nhất 1 ảnh mới (kiểm ngay dưới)
    if h.bat_buoc_anh then
      select count(*) into v_so_anh from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'kcs' and coalesce(loai, 'anh') = 'anh';
      if v_so_anh < 6 then
        raise exception 'KCS cần tối thiểu 6 ảnh sau sửa (mới có %). Chụp thêm rồi ký đạt.', v_so_anh; end if;
    end if;
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'kcs' and (v_truot is null or tai_luc > v_truot)) then
      if v_truot is null then raise exception 'Chưa có ảnh sau sửa. Chụp ảnh trước khi ký KCS.';
      else raise exception 'Chưa có ảnh sau khi làm lại (lần KCS chưa đạt lúc %). Chụp ảnh mới ở bước "Sau sửa" trước khi ký KCS đạt.',
        to_char(v_truot, 'HH24:MI DD/MM'); end if;
    end if;
  end if;
  insert into public.kcs (ho_so_id, dat, loi, boi) values (p_ho_so, p_dat, nullif(trim(p_loi),''), auth.uid());
  if p_dat then
    perform app.doi_trang_thai(p_ho_so, 'dat_kcs', 'Đạt KCS');
  else
    if nullif(trim(p_loi),'') is null then raise exception 'Ghi lỗi cần làm lại.'; end if;
    if p_lam_lai is null or cardinality(p_lam_lai) = 0 then raise exception 'Chọn hạng mục phải làm lại.'; end if;
    update public.hang_muc set trang_thai = 'dang_lam', xong_luc = null
    where ho_so_id = p_ho_so and id = any(p_lam_lai) and trang_thai = 'xong';
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Chưa đạt KCS: ' || trim(p_loi));
  end if;
end $function$;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';
