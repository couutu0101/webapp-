-- =====================================================================
-- 050: Bước DETAILING (rửa xe, đánh bóng) giữa "Cấp phụ tùng – Sửa chữa" và KCS (anh Thuận yêu cầu 16/10 16:34)
--  - Trạng thái mới cho_detailing ("Chờ Detailing"). Sửa xong hết hạng mục → Chờ Detailing (nếu hồ sơ có bước này)
--    → Detailing đạt → Chờ KCS. Detailing chưa đạt → ghi lỗi + chọn hạng mục làm lại → về Đang sửa (giống KCS chưa đạt).
--    KCS chưa đạt → sửa lại xong → qua Detailing lần nữa.
--  - Ai làm: trưởng nhóm tổ Detailing (DT), quản lý chung, giám đốc. Không bắt buộc ảnh.
--  - Cờ ho_so.qua_detailing: giao diện mới gửi khi tiếp nhận (CVDV tích "Không qua Detailing" thì không có bước này);
--    đổi được sau bằng dat_qua_detailing() trước khi sang KCS. Giao diện cũ không gửi → hồ sơ đi thẳng KCS như trước.
--  - Mọi chỗ sửa xong chuyển "Chờ KCS" đi qua app.doi_trang_thai → đổi ở đó sang "Chờ Detailing" khi hồ sơ có cờ.
--  - Các hàm cho phép làm việc ở bước sửa chữa / chờ KCS (cấp phụ tùng, báo phát sinh, báo giá bổ sung, duyệt giá,
--    hạng mục bảo hành, bảng việc tổ) nhận thêm cho_detailing. Bảng việc tổ: trưởng nhóm Detailing thấy xe chờ Detailing.
-- =====================================================================

alter table public.ho_so add column if not exists qua_detailing boolean not null default false;
alter table public.ho_so drop constraint if exists ho_so_trang_thai_check;
alter table public.ho_so add constraint ho_so_trang_thai_check check (trang_thai in (
  'tiep_nhan','bao_gia','da_duyet','dang_sua','cho_detailing','cho_kcs','dat_kcs','da_giao','da_gui_hs','dong','huy'));

-- Kết quả từng lần Detailing (như bảng kcs)
create table if not exists public.ket_qua_detailing (
  id        bigint generated always as identity primary key,
  ho_so_id  bigint not null references public.ho_so(id) on delete cascade,
  dat       boolean not null,
  loi       text,
  boi       uuid references auth.users(id),
  luc       timestamptz not null default now()
);
create index if not exists ket_qua_detailing_hs_idx on public.ket_qua_detailing (ho_so_id);
alter table public.ket_qua_detailing enable row level security;
drop policy if exists doc on public.ket_qua_detailing;
create policy doc on public.ket_qua_detailing for select to authenticated using (
  (select app.xem_nhu_nhan_vien()) and exists (select 1 from public.ho_so h where h.id = ket_qua_detailing.ho_so_id
    and ((select app.co_vai_tro('giam_doc')) or h.chi_nhanh_id = (select app.chi_nhanh()))));
revoke all on public.ket_qua_detailing from anon, authenticated;
grant select on public.ket_qua_detailing to authenticated;

insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('so_gio_detailing', '3', 'Detailing (rửa xe, đánh bóng) trong số giờ này kể từ khi tổ báo xong (nếu chưa tới giờ hẹn giao)')
on conflict do nothing;

-- Đổi trạng thái: sửa xong mà hồ sơ có bước Detailing thì sang "Chờ Detailing" thay vì "Chờ KCS"
CREATE OR REPLACE FUNCTION app.doi_trang_thai(p_ho_so bigint, p_sang text, p_ghi_chu text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare v_tu text; v_qua boolean;
begin
  select trang_thai, qua_detailing into v_tu, v_qua from public.ho_so where id = p_ho_so for update;
  if p_sang = 'cho_kcs' and v_tu = 'dang_sua' and v_qua then
    p_sang := 'cho_detailing';
    p_ghi_chu := replace(coalesce(p_ghi_chu, 'Xong các hạng mục'), 'chờ KCS', 'chờ Detailing');
  end if;
  if v_tu is distinct from p_sang then
    update public.ho_so set trang_thai = p_sang, cap_nhat_luc = now() where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, v_tu, p_sang, p_ghi_chu);
  end if;
end $function$;

-- Trưởng nhóm của một tổ ở chi nhánh (người nhận việc Detailing)
create or replace function app.truong_nhom_to(p_to text, p_cn text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.nhan_vien
  where hoat_dong and 'truong_nhom' = any(vai_tro) and to_id = p_to and (chi_nhanh_id = p_cn or chi_nhanh_id is null)
  order by (chi_nhanh_id is not distinct from p_cn) desc, ho_ten limit 1
$$;
revoke all on function app.truong_nhom_to(text, text) from public, anon;

-- Gợi ý người làm bước tiếp theo: Chờ Detailing → trưởng nhóm Detailing (không có thì quản lý chung)
CREATE OR REPLACE FUNCTION app.goi_y_nguoi_tiep_theo(h ho_so)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if h.tu_excel then return null; end if;
  case h.trang_thai
    -- Báo giá, nhập duyệt giá, lập lệnh: CVDV đang làm (người bấm), không thì CVDV tiếp nhận
    when 'tiep_nhan', 'bao_gia', 'da_duyet' then
      return case when app.co_vai_tro('cvdv') then auth.uid()
                  else coalesce((select id from public.nhan_vien where id = h.tao_boi and hoat_dong),
                                app.nhan_vien_dau('cvdv', h.chi_nhanh_id)) end;
    when 'dang_sua' then return null;                                           -- các tổ được giao
    when 'cho_detailing' then                                                   -- 050: Detailing
      return coalesce(app.truong_nhom_to('DT', h.chi_nhanh_id), app.nhan_vien_dau('quan_ly', h.chi_nhanh_id));
    when 'cho_kcs' then return app.nhan_vien_dau('quan_ly', h.chi_nhanh_id);     -- KCS
    when 'dat_kcs' then return app.nhan_vien_dau('ke_toan', h.chi_nhanh_id);     -- thu tiền, giao xe
    when 'da_giao' then
      if h.nguon_tt <> 'khach' and h.gui_hs_ngay is null and h.loai <> 'bao_hanh'
         and coalesce((select sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat)) from public.hang_muc m
                        where m.ho_so_id = h.id and m.nguoi_tra = 'bao_hiem' and m.trang_thai in ('duyet','dang_lam','xong')), 0)
            - h.khau_tru_giam_tru > 0 then
        return app.nhan_vien_dau('ke_toan', h.chi_nhanh_id);                     -- gửi hồ sơ bảo hiểm
      end if;
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;
    when 'da_gui_hs', 'dong' then
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;  -- chăm sóc
    else return null;
  end case;
end $function$;

-- Detailing nghiệm thu: đạt → Chờ KCS; chưa đạt → ghi lỗi, chọn hạng mục làm lại → Đang sửa
create or replace function public.detailing(p_ho_so bigint, p_dat boolean, p_loi text default null, p_lam_lai bigint[] default null) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so;
begin
  if not (app.co_vai_tro('quan_ly','giam_doc')
          or (app.co_vai_tro('truong_nhom') and (select to_id from public.nhan_vien where id = auth.uid()) = 'DT')) then
    raise exception 'Chỉ tổ Detailing, quản lý chung hoặc giám đốc làm bước Detailing.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'cho_detailing' then raise exception 'Xe không ở bước chờ Detailing.'; end if;
  if p_dat then
    if exists (select 1 from public.phat_sinh where ho_so_id = p_ho_so and not da_xu_ly) then
      raise exception 'Còn hư hỏng phát sinh chưa xử lý – CVDV lập báo giá bổ sung hoặc ghi "Không cần làm thêm" trước.'; end if;
    insert into public.ket_qua_detailing (ho_so_id, dat, loi, boi) values (p_ho_so, true, nullif(trim(p_loi),''), auth.uid());
    perform app.doi_trang_thai(p_ho_so, 'cho_kcs', 'Detailing xong (rửa xe, đánh bóng) – chờ KCS');
  else
    if nullif(trim(p_loi),'') is null then raise exception 'Ghi lỗi cần sửa lại.'; end if;
    if p_lam_lai is null or cardinality(p_lam_lai) = 0 then raise exception 'Chọn hạng mục phải sửa lại.'; end if;
    insert into public.ket_qua_detailing (ho_so_id, dat, loi, boi) values (p_ho_so, false, trim(p_loi), auth.uid());
    update public.hang_muc set trang_thai = 'dang_lam', xong_luc = null
    where ho_so_id = p_ho_so and id = any(p_lam_lai) and trang_thai = 'xong';
    if not found then raise exception 'Hạng mục chọn không thuộc xe này hoặc chưa xong.'; end if;
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Detailing trả về sửa lại: ' || trim(p_loi));
  end if;
end $$;
revoke all on function public.detailing(bigint, boolean, text, bigint[]) from public, anon;
grant execute on function public.detailing(bigint, boolean, text, bigint[]) to authenticated;

-- CVDV / quản lý / giám đốc bật – tắt bước Detailing của hồ sơ (trước khi sang KCS).
-- Tắt khi xe đang chờ Detailing → sang Chờ KCS luôn.
create or replace function public.dat_qua_detailing(p_ho_so bigint, p_qua boolean) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.qua_detailing is not distinct from coalesce(p_qua, false) then return; end if;
  if h.trang_thai not in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_detailing') then
    raise exception 'Xe đã qua bước sửa chữa – không đổi bước Detailing được nữa.'; end if;
  update public.ho_so set qua_detailing = coalesce(p_qua, false), cap_nhat_luc = now() where id = p_ho_so;
  if coalesce(p_qua, false) then
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Thêm bước Detailing trước KCS');
  elsif h.trang_thai = 'cho_detailing' then
    perform app.doi_trang_thai(p_ho_so, 'cho_kcs', 'Không qua Detailing – chờ KCS');
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Không qua Detailing');
  end if;
end $$;
revoke all on function public.dat_qua_detailing(bigint, boolean) from public, anon;
grant execute on function public.dat_qua_detailing(bigint, boolean) to authenticated;

-- tiep_nhan_xe (bản 048 + cờ qua_detailing)
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
    -- 048: giao diện mới chọn hãng BH / GDV lúc nhập kết quả duyệt giá (gửi bh_khi_duyet); giao diện cũ vẫn bắt chọn hãng ở đây
    if (p->>'hang_bh_id') is null and not coalesce((p->>'bh_khi_duyet')::boolean, false) then raise exception 'Chưa chọn hãng bảo hiểm.'; end if;
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
  -- 050: giao diện mới gửi qua_detailing (mặc định có; CVDV tích "Không qua Detailing" thì gửi false)
  if coalesce((p->>'qua_detailing')::boolean, false) then
    update public.ho_so set qua_detailing = true where id = v_id;
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'chi_nhanh_id', v_cn);
end $function$;

-- Các hàm làm việc ở bước sửa chữa / chờ KCS: nhận thêm cho_detailing (bản đang chạy, chỉ thêm trạng thái)
-- app.yeu_cau_co_lenh
CREATE OR REPLACE FUNCTION app.yeu_cau_co_lenh(h ho_so)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
begin
  if h.trang_thai not in ('dang_sua','cho_detailing','cho_kcs') then
    raise exception 'Xe % chưa có lệnh sửa chữa (hoặc đã qua KCS) – chưa cấp phụ tùng được.', h.ma;
  end if;
end $function$;

-- public.bao_phat_sinh
CREATE OR REPLACE FUNCTION public.bao_phat_sinh(p_ho_so bigint, p_mo_ta text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.ho_so;
begin
  if not (app.co_vai_tro('truong_nhom','cvdv','quan_ly','giam_doc')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('dang_sua','cho_detailing','cho_kcs') then raise exception 'Xe không ở bước sửa chữa.'; end if;
  if nullif(trim(p_mo_ta),'') is null then raise exception 'Mô tả hư hỏng phát sinh.'; end if;
  insert into public.phat_sinh (ho_so_id, mo_ta, boi) values (p_ho_so, trim(p_mo_ta), auth.uid());
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo phát sinh: ' || trim(p_mo_ta));
end $function$;

-- public.duyet_gia
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
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_detailing','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
  -- 048: xe bảo hiểm phải có hãng bảo hiểm và giám định viên (chọn trong hộp nhập kết quả duyệt giá)
  if h.nguon_tt <> 'khach' and h.hang_bh_id is null then
    raise exception 'Chưa chọn hãng bảo hiểm – chọn ở hộp nhập kết quả duyệt giá (hoặc nút "Sửa" ở Thông tin xe và khách).'; end if;
  if h.nguon_tt <> 'khach' and h.gdv_id is null then
    raise exception 'Chưa có giám định viên – chọn ở hộp nhập kết quả duyệt giá (hoặc nút "Sửa" ở Thông tin xe và khách).'; end if;
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

-- public.lap_bao_gia
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
  elsif h.trang_thai in ('da_duyet','dang_sua','cho_detailing','cho_kcs') then
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
    if h.trang_thai in ('cho_detailing','cho_kcs') then
      perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Báo giá bổ sung lần ' || v_lan);
    else
      perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo giá bổ sung lần ' || v_lan);
    end if;
  end if;
  update public.ho_so set bao_gia_luc = now() where id = p_ho_so;
  return v_lan;
end $function$;

-- public.luu_bao_gia
CREATE OR REPLACE FUNCTION public.luu_bao_gia(p_ho_so bigint, dong jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.ho_so; v_lan int; d jsonb; v_nguoi text; v_xuat boolean;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if jsonb_typeof(dong) <> 'array' or jsonb_array_length(dong) = 0 then
    raise exception 'Báo giá phải có ít nhất một dòng.'; end if;

  if h.trang_thai in ('tiep_nhan','bao_gia') then
    v_lan := 0;
  elsif h.trang_thai in ('da_duyet','dang_sua','cho_detailing','cho_kcs') then
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
    if h.trang_thai in ('cho_detailing','cho_kcs') then
      perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Báo giá bổ sung lần ' || v_lan);
    else
      perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo giá bổ sung lần ' || v_lan);
    end if;
  end if;
  return v_lan;
end $function$;

-- public.them_hang_muc_bao_hanh
CREATE OR REPLACE FUNCTION public.them_hang_muc_bao_hanh(p_ho_so bigint, p_dong jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare h public.ho_so; d jsonb; v_lan int; v_n int := 0;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.loai <> 'bao_hanh' then
    raise exception 'Chỉ hồ sơ bảo hành thêm hạng mục miễn phí; hồ sơ sửa chữa lập báo giá bổ sung.'; end if;
  if h.trang_thai not in ('da_duyet','dang_sua','cho_detailing','cho_kcs') then raise exception 'Hồ sơ không ở bước sửa chữa.'; end if;
  if jsonb_typeof(p_dong) <> 'array' then raise exception 'Ghi ít nhất một hạng mục.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  select coalesce(max(lan_bao_gia), 0) + 1 into v_lan from public.hang_muc where ho_so_id = p_ho_so;
  for d in select * from jsonb_array_elements(p_dong) loop
    if nullif(trim(d->>'ten'),'') is null then continue; end if;
    insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd, trang_thai, gia_duyet, ngay_duyet)
    values (p_ho_so, v_lan, trim(d->>'ten'), coalesce(nullif(d->>'nhom',''), 'dong'), 'khach', 0, false, 'duyet', 0, current_date);
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Ghi ít nhất một hạng mục.'; end if;
  update public.phat_sinh set da_xu_ly = true, xu_ly_ghi_chu = 'Thêm ' || v_n || ' hạng mục bảo hành', xu_ly_boi = auth.uid(), xu_ly_luc = now()
  where ho_so_id = p_ho_so and not da_xu_ly;
  if h.trang_thai in ('cho_detailing','cho_kcs') then
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Thêm ' || v_n || ' hạng mục bảo hành – làm tiếp');
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Thêm ' || v_n || ' hạng mục bảo hành');
  end if;
  return v_n;
end $function$;

-- public.bang_viec_to
CREATE OR REPLACE FUNCTION public.bang_viec_to()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','ke_toan','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select to_id, chi_nhanh_id into v_to, v_cn from public.nhan_vien where id = auth.uid();
  -- chỉ trưởng nhóm (không kiêm văn phòng) mới xem theo tổ của mình
  if not app.co_vai_tro('truong_nhom') or app.la_nhan_vien() then v_to := null; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ho_so_id', h.id, 'ma', h.ma, 'bien_so', public.bien_so_hien_thi(x.bien_so),
      'xe', concat_ws(' ', hx.ten, dx.ten, x.mau), 'hen_giao', h.hen_giao, 'trang_thai', h.trang_thai,
      'tinh_trang_xe', h.tinh_trang_xe,
      'nguon_tt', h.nguon_tt, 'loai', h.loai, 'chi_nhanh_id', h.chi_nhanh_id, 'qua_detailing', h.qua_detailing,
      'hang_muc', (select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'nhom', m.nhom, 'to_id', m.to_id,
                     'nguoi_lam', m.nguoi_lam, 'trang_thai', m.trang_thai) order by m.id)
                   from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('dang_lam','xong')
                     and (v_to is null or m.to_id = v_to or (v_to = 'DT' and h.trang_thai = 'cho_detailing'))))
      order by h.hen_giao nulls last)
    from public.ho_so h
    join public.xe x on x.id = h.xe_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    where h.trang_thai in ('dang_sua','cho_detailing','cho_kcs')
      and (app.co_vai_tro('giam_doc') or h.chi_nhanh_id = v_cn)
      and (v_to is null or exists (
            select 1 from public.hang_muc m where m.ho_so_id = h.id and m.to_id = v_to and m.trang_thai in ('dang_lam','xong'))
            or (v_to = 'DT' and h.trang_thai = 'cho_detailing'))
  ), '[]'::jsonb);
end $function$;

-- v_ho_so: thêm cột cuối qua_detailing (thanh tiến độ: bước Detailing "Không áp dụng" khi không có cờ)
create or replace view public.v_ho_so with (security_invoker = true) as
select
  h.id, h.ma, h.chi_nhanh_id, h.loai, h.ho_so_goc_id, h.trang_thai, h.ngay_vao, h.hen_giao, h.giao_luc,
  h.nguon_tt, h.tinh_trang_xe, h.tu_van, h.han_bao_hiem, h.khau_tru_giam_tru, h.giam_gia,
  h.so_hd_bao_hiem, h.so_hd_khach, h.cam_nhan_khach, h.gui_hs_ngay, h.hoa_hong_gdv, h.hoa_hong_ghi_chu,
  h.cham_soc_luc, h.cham_soc_ket_qua, h.hen_bao_duong, h.ly_do_huy, h.cho_giao_no_boi, h.tu_excel,
  h.xe_id, h.khach_hang_id, h.hang_bh_id, h.gdv_id,
  x.bien_so, public.bien_so_hien_thi(x.bien_so) as bien_so_hien_thi, x.dong_xe_id, x.mau,
  concat_ws(' ', hx.ten, dx.ten) as xe, k.ten as ten_khach, k.dien_thoai, b.ten as hang_bh,
  coalesce(h.gdv_ten_tam, g.ten) as gdv, coalesce(g.la_cho_them, false) as gdv_cho_them,
  d.ngay_duyet_dau,
  coalesce(d.co_dong_cho_duyet, false) as co_dong_cho_duyet,
  coalesce(ps.co_phat_sinh, false) as co_phat_sinh,
  coalesce(d.bh, 0) as bh_duyet,
  coalesce(d.kh, 0) as khach_duyet,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru as phai_thu_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia as phai_thu_khach,
  coalesce(t.bh, 0) as da_thu_bh,
  coalesce(t.kh, 0) as da_thu_khach,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru - coalesce(t.bh, 0) as con_no_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia - coalesce(t.kh, 0) as con_no_khach,
  h.han_bh_than_vo,
  h.so_km,
  h.nguoi_tiep_theo,
  h.giao_viec_luc,
  h.hoa_hong_ky,
  h.qua_detailing
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
left join app.duyet_theo_ho_so() d on d.ho_so_id = h.id
left join (select p.ho_so_id, bool_or(not p.da_xu_ly) as co_phat_sinh from public.phat_sinh p group by p.ho_so_id) ps on ps.ho_so_id = h.id
left join app.da_thu_theo_ho_so() t on t.ho_so_id = h.id;
grant select on public.v_ho_so to authenticated;
revoke all on public.v_ho_so from anon;

-- v_canh_bao: xe chờ Detailing tính như đang ở xưởng (thiếu GDV, quá hẹn giao)
create or replace view public.v_canh_bao with (security_invoker = true) as
with tat as (select * from public.v_ho_so),           -- đọc hồ sơ một lần cho mọi nhánh
hs as (select * from tat where trang_thai not in ('huy')),
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
where hs.nguon_tt <> 'khach' and hs.trang_thai = 'da_giao' and not hs.tu_excel and hs.loai <> 'bao_hanh' and hs.phai_thu_bh > 0
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
select 'khach_tra_du', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  hs.ten_khach || ' trả dư ' || app.vnd(-hs.con_no_khach) || ' đ – lập đề nghị chi "Trả lại cọc cho khách" hoặc ghi tiền bo', hs.chi_nhanh_id
from hs where hs.giao_luc is not null and hs.con_no_khach < 0 and not hs.tu_excel
union all
select 'bh_tra_du', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  coalesce(hs.hang_bh, 'Bảo hiểm') || ' đã trả dư ' || app.vnd(-hs.con_no_bh) || ' đ so với phần bảo hiểm chi trả – kiểm tra chia công nợ hoặc chia phiếu bảo hiểm', hs.chi_nhanh_id
from hs where hs.con_no_bh < 0 and not hs.tu_excel
union all
-- 041/043: hồ sơ đã HỦY còn giữ tiền khách đã trả (cọc) → nhắc trả lại; đã trả lại nhiều hơn số thu → báo kiểm tra
select case when c.da_thu_khach > 0 then 'coc_treo' else 'tra_lai_thua' end, 'cao', c.id, c.ma, c.bien_so_hien_thi,
  case when c.da_thu_khach > 0
       then 'Hồ sơ đã hủy còn giữ ' || app.vnd(c.da_thu_khach) || ' đ tiền cọc của ' || c.ten_khach || ' – lập đề nghị chi "Trả lại cọc cho khách"'
       else 'Hồ sơ đã hủy đã trả lại khách nhiều hơn số đã thu ' || app.vnd(-c.da_thu_khach) || ' đ – kiểm tra phiếu chi trả lại' end,
  c.chi_nhanh_id
from tat c where c.trang_thai = 'huy' and c.da_thu_khach <> 0 and not c.tu_excel
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
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_detailing','cho_kcs','dat_kcs')
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
from hs where hs.hen_giao < now() and hs.trang_thai in ('dang_sua','cho_detailing','cho_kcs','dat_kcs')
union all
select 'thu_chua_phan_bo', 'vua', null, null, null,
  'Phiếu thu ' || to_char(p.ngay, 'DD/MM/YYYY') || ' của ' || coalesce(p.hang_bh, p.muc) || ' còn '
    || app.vnd(p.con_chua_chia) || ' đ chưa chia vào xe', p.chi_nhanh_id
from public.v_phieu_thu_chi p
where p.con_chua_chia > 0
union all
select 'de_nghi_cho_duyet', case when d.nghi_tach_phieu then 'cao' else 'vua' end, d.ho_so_id, d.ho_so_ma, null,
  'Đề nghị chi ' || app.vnd(d.so_tien) || ' đ – ' || d.noi_dung || ' (' || coalesce(d.nguoi_de_nghi_ten,'') || ')'
    || case when d.can_giam_doc then ' – cần giám đốc duyệt' else '' end
    || case when d.nghi_tach_phieu then ' – nghi tách nhỏ phiếu, giám đốc duyệt' else '' end,
  d.chi_nhanh_id
from public.v_de_nghi_chi d
where d.trang_thai = 'cho_duyet' and (select app.co_vai_tro('giam_doc','quan_ly'))
  and d.nguoi_de_nghi <> (select auth.uid()) and (not d.can_giam_doc or (select app.co_vai_tro('giam_doc')))
union all
select 'nhap_ngoai_de_nghi', 'vua', null, pn.ma, null,
  'Phiếu nhập ' || pn.ma || ' ' || app.vnd(pn.tong_tien) || ' đ – ' || coalesce(n.ten, 'nhà cung cấp') || ' không theo đề nghị mua đã duyệt (từ '
    || app.vnd(app.cai_dat_so('nguong_3_bao_gia', 5000000)) || ' đ cần 3 báo giá) – giám đốc kiểm tra', pn.chi_nhanh_id
from public.phieu_nhap pn left join public.nha_cung_cap n on n.id = pn.nha_cung_cap_id
where (select app.co_vai_tro('giam_doc')) and pn.de_nghi_mua_id is null and pn.trang_thai <> 'huy'
  and pn.tong_tien >= app.cai_dat_so('nguong_3_bao_gia', 5000000) and pn.tao_luc > now() - interval '7 days';
grant select on public.v_canh_bao to authenticated;
revoke all on public.v_canh_bao from anon;

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
