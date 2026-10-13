-- =====================================================================
-- 025 (13/10/2026): KẾT QUẢ KINH DOANH THÁNG + CHỐT THÁNG + BÁO CÁO CỔ ĐÔNG
--   Theo chốt với giám đốc 13/10:
--     Doanh thu (sau VAT, theo ngày duyệt giá) − Giá vốn (vật tư xuất kho cho xe theo tháng xuất, vật tư dùng chung,
--     phiếu chi nhóm "Giá vốn") = Lãi gộp − Lương (bảng lương tháng) − Hoa hồng GDV (theo tháng duyệt giá của xe)
--     − Chi phí vận hành − Chi phí cố định (phiếu chi tính chất "chi_phi") = Lãi trước thuế.
--   Chốt tháng: giám đốc khóa sổ tháng đã qua, lưu ảnh số liệu; cổ đông chỉ xem tháng đã chốt.
--   Tương thích ngược: thêm hàm mới.
-- =====================================================================

-- Số liệu từng tháng của một chi nhánh (giám đốc, quản lý chung, kế toán)
create or replace function public.ket_qua_kinh_doanh(p_chi_nhanh text default null) returns table (
  thang date, doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric,
  gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric,
  luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric,
  so_xe bigint, da_chot boolean, chot_luc timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh());
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return query
  with thang_dt as (
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
    select date_trunc('month', p.ngay)::date as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_hh as (
    select date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' group by 1),
  cac_thang as (
    select th from thang_dt union select th from thang_kho union select th from thang_chi union select th from thang_hh
    union select bl.thang from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn)
  select t.th,
    coalesce(dt.bh,0), coalesce(dt.kh,0), coalesce(dt.dvn,0), coalesce(dt.gg,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0), coalesce(dt.vat,0),
    coalesce(k.xe,0), coalesce(k.dc,0), coalesce(c.gv,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0),
    coalesce(bl.tong_luong,0), coalesce(hh.hh,0), coalesce(c.vh,0), coalesce(c.cd,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0)
      - coalesce(bl.tong_luong,0) - coalesce(hh.hh,0) - coalesce(c.vh,0) - coalesce(c.cd,0),
    coalesce(c.vat_vao,0), coalesce(dt.xe,0), ct.thang is not null, ct.chot_luc
  from cac_thang t
  left join thang_dt dt on dt.th = t.th
  left join thang_kho k on k.th = t.th
  left join thang_chi c on c.th = t.th
  left join thang_hh hh on hh.th = t.th
  left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
  left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th
  where t.th is not null
  order by t.th desc;
end $$;

-- Giám đốc chốt tháng đã qua: khóa sổ (không ghi / sửa phiếu, hồ sơ của tháng đó), lưu ảnh số liệu cho cổ đông
create or replace function public.chot_thang(p_thang date, p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; v_so jsonb;
begin
  perform app.yeu_cau('giam_doc');
  if v_thang >= date_trunc('month', current_date)::date then raise exception 'Chỉ chốt được tháng đã qua.'; end if;
  if app.thang_da_chot(v_cn, v_thang) then raise exception 'Tháng này đã chốt rồi.'; end if;
  select to_jsonb(k) into v_so from public.ket_qua_kinh_doanh(v_cn) k where k.thang = v_thang;
  if v_so is null then raise exception 'Tháng này chưa có số liệu.'; end if;
  insert into public.chot_thang (chi_nhanh_id, thang, chot_boi, so_lieu) values (v_cn, v_thang, auth.uid(), v_so - 'da_chot' - 'chot_luc');
  return v_so;
end $$;

-- Mở lại tháng đã chốt (giám đốc, có lý do) – ghi lại vào so_lieu cũ không cần, chỉ xóa khóa
create or replace function public.mo_lai_thang(p_thang date, p_ly_do text, p_chi_nhanh text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date;
begin
  perform app.yeu_cau('giam_doc');
  if nullif(trim(p_ly_do), '') is null then raise exception 'Ghi lý do mở lại tháng.'; end if;
  delete from public.chot_thang where chi_nhanh_id = v_cn and thang = v_thang;
  if not found then raise exception 'Tháng này chưa chốt.'; end if;
end $$;

-- Cổ đông (và giám đốc): số tổng của các tháng đã chốt
create or replace function public.bao_cao_co_dong() returns table (chi_nhanh_id text, thang date, so_lieu jsonb, chot_luc timestamptz)
language sql stable security definer set search_path = public as $$
  select ct.chi_nhanh_id, ct.thang, ct.so_lieu, ct.chot_luc from public.chot_thang ct
  where app.co_vai_tro('co_dong', 'giam_doc') order by ct.thang desc
$$;

revoke execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, text), public.mo_lai_thang(date, text, text), public.bao_cao_co_dong() from public, anon;
grant execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, text), public.mo_lai_thang(date, text, text), public.bao_cao_co_dong() to authenticated;
