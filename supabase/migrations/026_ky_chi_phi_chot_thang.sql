-- =====================================================================
-- 026 (13/10/2026): KỲ CHI PHÍ, CHECKLIST TRƯỚC KHI CHỐT, KẾT QUẢ KINH DOANH THEO THÁNG ĐẦY ĐỦ
--   Chốt với giám đốc: kỳ báo cáo khóa ở ngày cuối tháng; tiền điện, tiền lương... nhập SAU ngày đó nhưng vẫn tính
--   vào tháng đó. Vì vậy:
--   - Đề nghị chi / phiếu chi có "kỳ chi phí" (ky_chi_phi = ngày đầu tháng): chi phí tính vào tháng này dù chi tiền
--     tháng sau. Mặc định = tháng của ngày lập; chọn được tháng trước. Kỳ đã chốt thì không lập / chi được nữa.
--   - Mục chi "định kỳ" (điện, nước, mặt bằng...): trước khi chốt, phần mềm liệt kê mục định kỳ chưa có trong kỳ.
--   - Kết quả kinh doanh: mọi tháng từ tháng đầu có số liệu đến tháng hiện tại (sang tháng mới tự có cột mới),
--     kèm trạng thái Đang mở / Chờ chốt / Đã chốt, lương đã nhập chưa, chi phí định kỳ còn thiếu, đề nghị chi chưa chi.
--   - Chốt tháng: còn thiếu thì cảnh báo (CANH_BAO) – giám đốc xác nhận mới chốt.
--   Tương thích ngược: thêm cột, hàm kết quả kinh doanh đổi cột trả về (tạo lại).
-- =====================================================================
alter table public.de_nghi_chi add column if not exists ky_chi_phi date;
alter table public.phieu_thu_chi add column if not exists ky_chi_phi date;
comment on column public.de_nghi_chi.ky_chi_phi is 'Chi phí tính vào tháng này (ngày đầu tháng); trống = tháng của ngày lập';
comment on column public.phieu_thu_chi.ky_chi_phi is 'Chi phí tính vào tháng này (ngày đầu tháng); trống = tháng của ngày chi';
alter table public.muc_thu_chi add column if not exists dinh_ky boolean not null default false;
comment on column public.muc_thu_chi.dinh_ky is 'Chi phí phát sinh đều mỗi tháng: trước khi chốt tháng nhắc nếu chưa có';
update public.muc_thu_chi set dinh_ky = true
where loai = 'chi' and tinh_chat = 'chi_phi' and ten in ('Mặt bằng', 'Bảo vệ', 'BHXH', 'Điện', 'Internet – quảng cáo – hotline', 'Nước', 'Rác');

-- Kỳ chi phí hợp lệ: ngày đầu tháng, không sau tháng hiện tại, không quá 3 tháng trước, tháng chưa chốt
create or replace function app.kiem_ky_chi_phi(p_cn text, p_ky date) returns date
language plpgsql stable as $$
begin
  if p_ky is null then return null; end if;
  p_ky := date_trunc('month', p_ky)::date;
  if p_ky > date_trunc('month', current_date)::date then raise exception 'Kỳ chi phí không được sau tháng hiện tại.'; end if;
  if p_ky < (date_trunc('month', current_date) - interval '3 months')::date then raise exception 'Kỳ chi phí quá xa (tối đa 3 tháng trước).'; end if;
  perform app.yeu_cau_thang_mo(p_cn, p_ky);
  return p_ky;
end $$;

create or replace function public.lap_de_nghi_chi(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); m public.muc_thu_chi; v_id bigint;
  v_ngay date := coalesce((p->>'ngay')::date, current_date); v_ky date; v_noi_dung text;
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
  -- Kỳ chi phí: chỉ với khoản tính vào lãi lỗ; khác tháng lập thì ghi rõ vào nội dung để ai cũng thấy
  v_noi_dung := trim(p->>'noi_dung');
  if m.tinh_chat = 'chi_phi' then
    v_ky := app.kiem_ky_chi_phi(v_cn, coalesce((p->>'ky_chi_phi')::date, v_ngay));
    if v_ky <> date_trunc('month', v_ngay)::date then
      v_noi_dung := v_noi_dung || ' (chi phí tháng ' || to_char(v_ky, 'MM/YYYY') || ')'; end if;
  end if;

  insert into public.de_nghi_chi (chi_nhanh_id, ngay, nguoi_de_nghi, muc_id, so_tien, vat_dau_vao, noi_dung, nguoi_nhan,
    ho_so_id, nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, ky_chi_phi)
  values (v_cn, v_ngay, auth.uid(), m.id, (p->>'so_tien')::numeric,
    coalesce((p->>'vat_dau_vao')::numeric, 0), v_noi_dung, nullif(trim(p->>'nguoi_nhan'),''),
    (p->>'ho_so_id')::bigint, (p->>'nha_cung_cap_id')::bigint, (p->>'gdv_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, v_ky)
  returning id into v_id;
  return v_id;
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
  if r.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ky_chi_phi); end if;
  if p_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan(p_tai_khoan, r.chi_nhanh_id);
  select * into m from public.muc_thu_chi where id = r.muc_id;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, vat_dau_vao, noi_dung,
    nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, de_nghi_chi_id, tao_boi, ky_chi_phi)
  values (r.chi_nhanh_id, p_ngay, 'chi', p_tai_khoan, r.muc_id, r.so_tien, r.vat_dau_vao,
    concat_ws(' – ', r.noi_dung, r.nguoi_nhan), r.nha_cung_cap_id, r.gdv_id, r.don_vi_lien_quan_id, r.id, auth.uid(), r.ky_chi_phi)
  returning id into v_id;

  if m.tinh_chat = 'tra_coc' then   -- trả lại cọc cho khách: giảm phần khách đã trả
    insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (v_id, r.ho_so_id, 'khach', r.so_tien);
    perform app.cap_nhat_dong(r.ho_so_id);
  end if;
  update public.de_nghi_chi set trang_thai = 'da_chi' where id = p_de_nghi;
  return v_id;
end $$;

-- Kết quả kinh doanh: mọi tháng từ tháng đầu có số liệu đến tháng hiện tại, kèm trạng thái và checklist chốt
drop function if exists public.ket_qua_kinh_doanh(text);
create or replace function public.ket_qua_kinh_doanh(p_chi_nhanh text default null) returns table (
  thang date, ngay_cuoi date, trang_thai text,
  doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric,
  gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric,
  luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric,
  so_xe bigint, luong_da_nhap boolean, thieu_dinh_ky text[], de_nghi_cho_chi bigint, da_chot boolean, chot_luc timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_dau date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select least(
    (select min(date_trunc('month', d.ngay))::date from public.v_doanh_thu d where d.chi_nhanh_id = v_cn),
    (select min(date_trunc('month', px.ngay))::date from public.phieu_xuat px where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc'),
    (select min(coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date)) from public.phieu_thu_chi p where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'),
    (select min(bl.thang) from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn),
    (select min(ct.thang) from public.chot_thang ct where ct.chi_nhanh_id = v_cn),
    date_trunc('month', current_date)::date) into v_dau;
  return query
  with cac_thang as (
    select g::date as th from generate_series(v_dau, date_trunc('month', current_date)::date, interval '1 month') g),
  thang_dt as (
    select date_trunc('month', d.ngay)::date as th,
      sum(d.so_tien) filter (where d.nguon = 'bao_hiem') as bh,
      sum(d.so_tien) filter (where d.nguon = 'khach') as kh,
      sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh') as dvn,
      sum(d.so_tien) filter (where d.nguon = 'giam_gia') as gg,
      sum(d.vat_ra) as vat, count(distinct d.ho_so_id) as xe
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn group by 1),
  thang_kho as (
    select date_trunc('month', px.ngay)::date as th,
      sum(pd.gia_von) filter (where px.loai = 'cho_xe') as xe, sum(pd.gia_von) filter (where px.loai = 'dung_chung') as dc
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' group by 1),
  thang_chi as (
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_hh as (
    select date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' group by 1)
  select t.th, (t.th + interval '1 month' - interval '1 day')::date,
    case when ct.thang is not null then 'da_chot' when t.th >= date_trunc('month', current_date)::date then 'dang_mo' else 'cho_chot' end,
    coalesce(dt.bh,0), coalesce(dt.kh,0), coalesce(dt.dvn,0), coalesce(dt.gg,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0), coalesce(dt.vat,0),
    coalesce(k.xe,0), coalesce(k.dc,0), coalesce(c.gv,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0),
    coalesce(bl.tong_luong,0), coalesce(hh.hh,0), coalesce(c.vh,0), coalesce(c.cd,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0)
      - coalesce(bl.tong_luong,0) - coalesce(hh.hh,0) - coalesce(c.vh,0) - coalesce(c.cd,0),
    coalesce(c.vat_vao,0), coalesce(dt.xe,0),
    bl.thang is not null,
    coalesce((select array_agg(m.ten order by m.ten) from public.muc_thu_chi m
      where m.loai = 'chi' and m.dinh_ky and m.hoat_dong
        and not exists (select 1 from public.phieu_thu_chi p where p.muc_id = m.id and p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'
                          and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = t.th)
        and not exists (select 1 from public.de_nghi_chi d where d.muc_id = m.id and d.chi_nhanh_id = v_cn and d.trang_thai not in ('huy','tu_choi')
                          and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th)), '{}'::text[]),
    (select count(*) from public.de_nghi_chi d where d.chi_nhanh_id = v_cn and d.trang_thai in ('cho_duyet','da_duyet')
       and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th),
    ct.thang is not null, ct.chot_luc
  from cac_thang t
  left join thang_dt dt on dt.th = t.th
  left join thang_kho k on k.th = t.th
  left join thang_chi c on c.th = t.th
  left join thang_hh hh on hh.th = t.th
  left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
  left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th
  order by t.th;
end $$;

-- Chốt tháng: còn thiếu lương / chi phí định kỳ / đề nghị chi chưa chi thì cảnh báo, giám đốc xác nhận mới chốt
drop function if exists public.chot_thang(date, text);
create or replace function public.chot_thang(p_thang date, p_bo_qua_canh_bao boolean default false, p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; k record; v_thieu text[] := '{}';
begin
  perform app.yeu_cau('giam_doc');
  if v_thang >= date_trunc('month', current_date)::date then raise exception 'Chỉ chốt được tháng đã qua (kỳ khóa ở ngày cuối tháng).'; end if;
  if app.thang_da_chot(v_cn, v_thang) then raise exception 'Tháng này đã chốt rồi.'; end if;
  select * into k from public.ket_qua_kinh_doanh(v_cn) x where x.thang = v_thang;
  if k.thang is null then raise exception 'Tháng này chưa có số liệu.'; end if;
  if not p_bo_qua_canh_bao then
    if not k.luong_da_nhap then v_thieu := v_thieu || 'chưa nhập bảng lương'; end if;
    if cardinality(k.thieu_dinh_ky) > 0 then v_thieu := v_thieu || ('chưa có chi phí định kỳ: ' || array_to_string(k.thieu_dinh_ky, ', ')); end if;
    if k.de_nghi_cho_chi > 0 then v_thieu := v_thieu || (k.de_nghi_cho_chi || ' đề nghị chi của kỳ chưa chi'); end if;
    if cardinality(v_thieu) > 0 then
      raise exception 'CANH_BAO: Tháng % còn thiếu: %. Chốt xong sẽ không nhập thêm được vào tháng này. Vẫn chốt?',
        to_char(v_thang, 'MM/YYYY'), array_to_string(v_thieu, '; ');
    end if;
  end if;
  insert into public.chot_thang (chi_nhanh_id, thang, chot_boi, so_lieu)
  values (v_cn, v_thang, auth.uid(), to_jsonb(k) - 'da_chot' - 'chot_luc' - 'trang_thai');
  return to_jsonb(k);
end $$;

revoke execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, boolean, text), app.kiem_ky_chi_phi(text, date) from public, anon;
grant execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, boolean, text) to authenticated;
