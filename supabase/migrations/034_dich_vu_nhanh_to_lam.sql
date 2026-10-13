-- =====================================================================
-- 034 (14/10/2026): DỊCH VỤ NHANH – NGƯỜI LÀM CHỈ CHỌN TỔ ĐIỆN – MÁY – GẦM HOẶC DETAILING
--  - dich_vu_nhanh.to_id ('DMG' | 'DT'); nguoi_lam ghi tên tổ. Giao diện mới bắt buộc chọn tổ.
--  - Doanh thu dịch vụ nhanh tính vào đúng tổ (trước đây luôn tính Detailing; dòng cũ không có tổ vẫn tính Detailing).
--  Tương thích ngược: thêm cột cho phép trống; giao diện cũ (không gửi to_id) vẫn ghi được như trước.
-- =====================================================================

alter table public.dich_vu_nhanh add column if not exists to_id text references public.to_thuc_hien(id);

create or replace view public.v_doanh_thu with (security_invoker = true) as
 SELECT h.chi_nhanh_id,
    m.ngay_duyet AS ngay,
    h.id AS ho_so_id,
    h.ma,
    bien_so_hien_thi(x.bien_so) AS bien_so,
    m.nguoi_tra AS nguon,
    m.nhom,
    tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat) AS so_tien,
        CASE
            WHEN m.xuat_hd THEN tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet
            ELSE 0::numeric
        END AS vat_ra
   FROM hang_muc m
     JOIN ho_so h ON h.id = m.ho_so_id
     JOIN xe x ON x.id = h.xe_id
  WHERE (m.trang_thai = ANY (ARRAY['duyet'::text, 'dang_lam'::text, 'xong'::text])) AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel AND h.loai <> 'bao_hanh'::text
UNION ALL
 SELECT d.chi_nhanh_id,
    d.ngay,
    NULL::bigint AS ho_so_id,
    NULL::text AS ma,
    bien_so_hien_thi(d.bien_so) AS bien_so,
    'dich_vu_nhanh'::text AS nguon,
        CASE d.to_id
            WHEN 'DMG'::text THEN 'dmg'::text
            ELSE 'detailing'::text
        END AS nhom,
    d.so_tien,
        CASE
            WHEN d.xuat_hd THEN d.so_tien - round(d.so_tien / (1::numeric + vat_ty_le(d.ngay)))
            ELSE 0::numeric
        END AS vat_ra
   FROM dich_vu_nhanh d
  WHERE d.trang_thai = 'hieu_luc'::text
UNION ALL
 SELECT h.chi_nhanh_id,
    h.giam_gia_ngay AS ngay,
    h.id AS ho_so_id,
    h.ma,
    NULL::text AS bien_so,
    'giam_gia'::text AS nguon,
    NULL::text AS nhom,
    - h.giam_gia AS so_tien,
    0 AS vat_ra
   FROM ho_so h
  WHERE h.giam_gia > 0::numeric AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel;

create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public set timezone to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint; v_to text := nullif(p->>'to_id', ''); v_nguoi text := nullif(trim(p->>'nguoi_lam'),'');
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODO) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODO) không đúng.'; end if;
  -- Người làm: chỉ tổ Điện – máy – gầm hoặc Detailing (034); tên tổ ghi vào nguoi_lam
  if v_to is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Chọn tổ làm: Điện – máy – gầm hoặc Detailing.'; end if;
  if v_to is not null then
    if v_to not in ('DMG', 'DT') then raise exception 'Dịch vụ nhanh chỉ do tổ Điện – máy – gầm hoặc Detailing làm.'; end if;
    select ten into v_nguoi from public.to_thuc_hien where id = v_to;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;

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
  return v_id;
end $$;
