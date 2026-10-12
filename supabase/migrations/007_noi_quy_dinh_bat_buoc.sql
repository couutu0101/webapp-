-- =====================================================================
-- 007 (12/10/2026): Nới hai quy định bắt buộc
--   1. Ảnh nhận xe không bắt buộc: bỏ kiểm tra "phải có ảnh nhận xe mới lập được báo giá" (luu_bao_gia).
--   2. Xe bảo hiểm có thể không có BH thân vỏ / TNDS: bỏ bắt buộc ngày hết hạn TNDS (tiep_nhan_xe).
--      Phần mềm vẫn bắt nhập ngày, trừ khi CVDV tích "Không có BH thân vỏ" / "Không có BH TNDS".
--   Phần còn lại của hai hàm giữ nguyên.
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
    hang_bh_id, van_phong_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'van_phong_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), auth.uid())
  returning id into v_id;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', 'Tiếp nhận xe');
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

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
