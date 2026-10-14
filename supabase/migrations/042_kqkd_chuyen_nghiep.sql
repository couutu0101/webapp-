-- =====================================================================
-- 042 (14/10/2026): RÀ SOÁT LẦN 2 – nhóm C: BÁO CÁO KẾT QUẢ KINH DOANH CHUYÊN NGHIỆP (anh Thuận chọn làm)
--  1. Đủ khoản: HAO HỤT / THỪA KIỂM KÊ vào giá vốn; THU NHẬP KHÁC (mục thu có tích "vào lãi lỗ": trạm sạc, thu khác…);
--     dòng tổng giá vốn, tổng chi phí hoạt động.
--  2. THUẾ GTGT (ước): VAT đầu vào gồm cả hàng nhập kho (phiếu nhập) + chi phí; VAT phải nộp = đầu ra − đầu vào
--     (để chuẩn bị tiền nộp thuế tháng). LÃI KHÔNG GỒM VAT (trước thuế TNDN) tính theo dồn tích:
--     lãi trước thuế (số gồm VAT) − VAT đầu ra + VAT nằm trong giá vốn vật tư ĐÃ XUẤT + VAT trong chi phí
--     (không lấy VAT của hàng mới nhập còn nằm trong kho). Giảm giá giảm cả VAT đầu ra (ước).
--  3. Tháng ĐÃ CHỐT hiện SỐ LÚC CHỐT; số hiện tại khác số chốt thì báo "lệch" (cần mở lại, chốt lại).
--     Chốt LẦN LƯỢT từng tháng; mở lại từ tháng sau cùng; mở lại lưu LỊCH SỬ (ai, lúc nào, lý do, số cũ).
--     Lúc chốt lưu kèm TIỀN – CÔNG NỢ – TỒN KHO cuối tháng (quỹ, phải thu khách / BH, phải trả NCC, tồn kho).
--  4. Xem chi tiết từng ô (chi_tiet_kqkd: cả VAT đầu ra, VAT trong giá vốn, danh sách xe), chi phí theo mục,
--     lãi gộp theo tổ, doanh thu theo tháng tính ở máy chủ.
--  5. Số xe tính theo tháng duyệt giá đầu tiên (không đếm trùng khi lũy kế); thêm lượt dịch vụ nhanh.
--  Tương thích ngược: ket_qua_kinh_doanh giữ đủ các cột cũ (cùng tên, cùng thứ tự) và thêm cột mới ở cuối;
--  v_doanh_thu thêm cột to_id ở cuối. Giao diện cũ của bản thật vẫn đọc được.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Mục thu tính vào "Thu nhập khác" của lãi lỗ
-- ---------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'muc_thu_chi' and column_name = 'vao_lai_lo') then
    alter table public.muc_thu_chi add column vao_lai_lo boolean not null default false;
    -- Mặc định: trạm sạc, thu khác… là thu nhập của gara; tiền bo (của thợ) và phí bảo hiểm thu hộ thì không
    alter table public.muc_thu_chi disable trigger muc_thu_chi_chan_doi;
    update public.muc_thu_chi set vao_lai_lo = true
     where loai = 'thu' and tinh_chat = 'thu_khac' and he_thong is distinct from 'tien_bo'
       and ten not in ('Tiền bo của khách', 'Khách mua bảo hiểm');
    alter table public.muc_thu_chi enable trigger muc_thu_chi_chan_doi;
  end if;
end $$;
comment on column public.muc_thu_chi.vao_lai_lo is
  'Mục thu "thu khác" tính vào Thu nhập khác của kết quả kinh doanh (trạm sạc, thu khác). Tiền bo của thợ, phí bảo hiểm thu hộ: không tích.';

-- Mục đã có phiếu trong tháng chốt: thêm "vao_lai_lo" vào các trường không đổi được
create or replace function app.chan_doi_muc_da_chot() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.loai, new.tinh_chat, new.nhom, new.vao_lai_lo) is distinct from (old.loai, old.tinh_chat, old.nhom, old.vao_lai_lo)
     and exists (select 1 from public.phieu_thu_chi p
                 join public.chot_thang c on c.chi_nhanh_id = p.chi_nhanh_id
                  and c.thang = date_trunc('month', coalesce(p.ky_chi_phi, p.ngay))::date
                 where p.muc_id = old.id and p.trang_thai = 'hieu_luc') then
    raise exception 'Mục "%" đã có phiếu trong tháng đã chốt sổ: không đổi loại, tính chất, nhóm hay "vào lãi lỗ" được (lãi lỗ đã chốt sẽ lệch). Tạo mục mới cho các phiếu sau.', old.ten;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 2. v_doanh_thu: thêm tổ làm (to_id, cột cuối); giảm giá giảm cả VAT đầu ra theo tỷ lệ VAT của hồ sơ (ước)
-- ---------------------------------------------------------------------
create or replace view public.v_doanh_thu with (security_invoker = true) as
 SELECT h.chi_nhanh_id,
    m.ngay_duyet AS ngay,
    h.id AS ho_so_id,
    h.ma,
    public.bien_so_hien_thi(x.bien_so) AS bien_so,
    m.nguoi_tra AS nguon,
    m.nhom,
    public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat) AS so_tien,
    CASE WHEN m.xuat_hd THEN public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet ELSE 0::numeric END AS vat_ra,
    coalesce(m.to_id, CASE m.nhom WHEN 'dmg' THEN 'DMG' WHEN 'detailing' THEN 'DT' ELSE 'DS' END) AS to_id
   FROM public.hang_muc m
     JOIN public.ho_so h ON h.id = m.ho_so_id
     JOIN public.xe x ON x.id = h.xe_id
  WHERE m.trang_thai = ANY (ARRAY['duyet'::text, 'dang_lam'::text, 'xong'::text]) AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel AND h.loai <> 'bao_hanh'::text
UNION ALL
 SELECT d.chi_nhanh_id,
    d.ngay,
    NULL::bigint AS ho_so_id,
    NULL::text AS ma,
    public.bien_so_hien_thi(d.bien_so) AS bien_so,
    'dich_vu_nhanh'::text AS nguon,
    CASE d.to_id WHEN 'DMG'::text THEN 'dmg'::text ELSE 'detailing'::text END AS nhom,
    d.so_tien,
    CASE WHEN d.xuat_hd THEN d.so_tien - round(d.so_tien / (1::numeric + public.vat_ty_le(d.ngay))) ELSE 0::numeric END AS vat_ra,
    coalesce(d.to_id, 'DT') AS to_id
   FROM public.dich_vu_nhanh d
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
    - round(h.giam_gia * coalesce(v.ty_le, 0)) AS vat_ra,
    NULL::text AS to_id
   FROM public.ho_so h
   LEFT JOIN LATERAL (
     SELECT sum(CASE WHEN m.xuat_hd THEN public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet ELSE 0 END)
            / nullif(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)), 0) AS ty_le
     FROM public.hang_muc m WHERE m.ho_so_id = h.id AND m.trang_thai IN ('duyet','dang_lam','xong')) v ON true
  WHERE h.giam_gia > 0::numeric AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel;
grant select on public.v_doanh_thu to authenticated;
revoke all on public.v_doanh_thu from anon;

-- Doanh thu gộp theo tháng (thẻ Doanh thu – xem "từ trước đến nay" không tải từng dòng về máy). Quyền như v_doanh_thu.
create or replace function public.doanh_thu_theo_thang()
returns table (thang date, bao_hiem numeric, khach numeric, dich_vu_nhanh numeric, giam_gia numeric, tong numeric, vat_ra numeric,
  dong_son numeric, phu_tung numeric, dmg numeric, detailing numeric, so_xe bigint, so_luot_dvn bigint)
language sql stable security invoker set search_path = public as $$
  select date_trunc('month', d.ngay)::date,
    coalesce(sum(d.so_tien) filter (where d.nguon = 'bao_hiem'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'khach'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'giam_gia'), 0),
    coalesce(sum(d.so_tien), 0), coalesce(sum(d.vat_ra), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom in ('dong','son','dong_son')), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'phu_tung'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'dmg'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'detailing'), 0),
    count(distinct d.ho_so_id) filter (where d.nguon in ('bao_hiem','khach')),
    count(*) filter (where d.nguon = 'dich_vu_nhanh')
  from public.v_doanh_thu d
  group by 1 order by 1
$$;
revoke execute on function public.doanh_thu_theo_thang() from public, anon;
grant execute on function public.doanh_thu_theo_thang() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Tiền – công nợ – tồn kho tại một ngày (cuối tháng): lưu vào số chốt, hiện ở báo cáo
-- ---------------------------------------------------------------------
create or replace function app.so_du_cuoi_thang(p_cn text, p_ngay date) returns jsonb
language sql stable security definer set search_path = public as $$
  with quy as (
    select coalesce(sum(tk.so_du_dau_ky) filter (where tk.ngay_dau_ky <= p_ngay), 0)
      + coalesce((select sum(case when p.loai = 'thu' then p.so_tien when p.loai = 'chi' then -p.so_tien else 0 end)
                  from public.phieu_thu_chi p join public.tai_khoan_quy t2 on t2.id = p.tai_khoan_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and p.ngay >= t2.ngay_dau_ky), 0) as so_du
    from public.tai_khoan_quy tk where tk.chi_nhanh_id = p_cn),
  kho as (
    select coalesce(sum(l.so_luong * l.don_gia_von), 0)
      - coalesce((select sum(pd.gia_von) from public.phieu_xuat_dong pd join public.phieu_xuat px on px.id = pd.phieu_id
                  where px.chi_nhanh_id = p_cn and px.trang_thai = 'hieu_luc' and px.ngay <= p_ngay), 0) as ton
    from public.lo_kho l where l.chi_nhanh_id = p_cn and l.ngay <= p_ngay),
  hs as (
    select h.id, h.khau_tru_giam_tru, h.giam_gia, h.giam_gia_ngay,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'khach'), 0) as kh,
      count(*) as so_dong
    from public.ho_so h join public.hang_muc m on m.ho_so_id = h.id
    where h.chi_nhanh_id = p_cn and h.trang_thai <> 'huy' and h.loai <> 'bao_hanh'
      and m.trang_thai in ('duyet','dang_lam','xong') and m.ngay_duyet <= p_ngay
    group by h.id),
  tra as (
    select pb.ho_so_id,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0) as kh
    from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and pb.ho_so_id is not null
    group by pb.ho_so_id),
  -- cả hồ sơ chưa duyệt giá mà đã thu cọc (hoặc đã hủy còn giữ cọc): nợ khách âm = phải trả lại khách
  no as (
    select coalesce(hs.bh, 0) - coalesce(hs.khau_tru_giam_tru, 0) - coalesce(tra.bh, 0) as no_bh,
      coalesce(hs.kh, 0) + coalesce(hs.khau_tru_giam_tru, 0) - case when hs.giam_gia_ngay <= p_ngay then hs.giam_gia else 0 end - coalesce(tra.kh, 0) as no_kh
    from hs full join tra on tra.ho_so_id = hs.id),
  ncc as (
    select coalesce((select sum(pn.tong_tien) from public.phieu_nhap pn
                     where pn.chi_nhanh_id = p_cn and pn.trang_thai <> 'huy' and pn.ngay <= p_ngay), 0)
      - coalesce((select sum(p.so_tien) from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat = 'tra_ncc'
                    and p.nha_cung_cap_id is not null and p.ngay <= p_ngay), 0) as phai_tra)
  select jsonb_build_object(
    'ngay', p_ngay,
    'so_du_quy', (select round(so_du) from quy),
    'ton_kho', (select round(ton) from kho),
    'phai_thu_khach', (select round(coalesce(sum(greatest(no_kh, 0)), 0)) from no),
    'phai_thu_bh', (select round(coalesce(sum(greatest(no_bh, 0)), 0)) from no),
    'khach_tra_du', (select round(coalesce(sum(greatest(-no_kh, 0)), 0)) from no),
    'phai_tra_ncc', (select round(phai_tra) from ncc))
$$;
revoke execute on function app.so_du_cuoi_thang(text, date) from public, anon;

create or replace function public.so_du_cuoi_thang(p_thang date, p_chi_nhanh text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_ngay date := (date_trunc('month', p_thang) + interval '1 month - 1 day')::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return app.so_du_cuoi_thang(v_cn, least(v_ngay, current_date));
end $$;
revoke execute on function public.so_du_cuoi_thang(date, text) from public, anon;
grant execute on function public.so_du_cuoi_thang(date, text) to authenticated;

-- Số đã chốt nếu có, không thì số hiện tại
create or replace function app.so_chot(p_so_lieu jsonb, p_khoa text, p_song numeric) returns numeric
language sql immutable as $$
  select case when p_so_lieu is not null and p_so_lieu ? p_khoa and jsonb_typeof(p_so_lieu->p_khoa) = 'number'
              then (p_so_lieu->>p_khoa)::numeric else p_song end
$$;

-- ---------------------------------------------------------------------
-- 4. Kết quả kinh doanh (giữ cột cũ, thêm cột mới ở cuối)
-- ---------------------------------------------------------------------
drop function if exists public.ket_qua_kinh_doanh(text);
create function public.ket_qua_kinh_doanh(p_chi_nhanh text default null)
returns table (
  thang date, ngay_cuoi date, trang_thai text,
  doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric,
  gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric,
  luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric, so_xe bigint,
  luong_da_nhap boolean, thieu_dinh_ky text[], de_nghi_cho_chi bigint, da_chot boolean, chot_luc timestamptz,
  -- 042
  hao_hut numeric, tong_gia_von numeric, tong_chi_phi numeric, thu_khac numeric,
  vat_vao_hang numeric, vat_vao_chi_phi numeric, vat_trong_gia_von numeric, vat_phai_nop numeric, lai_sau_vat numeric,
  so_luot_dvn bigint, lech_chot boolean, lai_truoc_thue_song numeric)
language plpgsql stable security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_dau date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select least(
    (select min(date_trunc('month', d.ngay))::date from public.v_doanh_thu d where d.chi_nhanh_id = v_cn),
    (select min(date_trunc('month', px.ngay))::date from public.phieu_xuat px where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc'),
    (select min(coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date)) from public.phieu_thu_chi p where p.chi_nhanh_id = v_cn and p.trang_thai = 'hieu_luc'),
    (select min(date_trunc('month', pn.ngay))::date from public.phieu_nhap pn where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy'),
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
      sum(d.vat_ra) as vat, count(*) filter (where d.nguon = 'dich_vu_nhanh') as luot_dvn
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn group by 1),
  -- Số xe: tính ở tháng duyệt giá đầu tiên của hồ sơ (lũy kế không đếm trùng)
  thang_xe as (
    select date_trunc('month', x.dau)::date as th, count(*) as xe
    from (select min(m.ngay_duyet) as dau from public.hang_muc m join public.ho_so h on h.id = m.ho_so_id
          where h.chi_nhanh_id = v_cn and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
            and m.trang_thai in ('duyet','dang_lam','xong') group by m.ho_so_id) x
    group by 1),
  thang_kho as (
    select date_trunc('month', px.ngay)::date as th,
      sum(pd.gia_von) filter (where px.loai = 'cho_xe') as xe, sum(pd.gia_von) filter (where px.loai = 'dung_chung') as dc,
      sum(pd.gia_von) filter (where px.loai = 'kiem_ke') as kk_thieu
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' group by 1),
  -- Kiểm kê thừa: lô thêm vào kho → giảm hao hụt của tháng
  thang_thua as (
    select date_trunc('month', l.ngay)::date as th, round(sum(l.so_luong * l.don_gia_von)) as thua
    from public.lo_kho l where l.chi_nhanh_id = v_cn and l.kiem_ke_id is not null group by 1),
  thang_chi as (
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_thu_khac as (
    select date_trunc('month', p.ngay)::date as th, sum(p.so_tien) as tk
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'thu' and p.trang_thai = 'hieu_luc' and m.vao_lai_lo group by 1),
  thang_vat_nhap as (
    select date_trunc('month', pn.ngay)::date as th, sum(pn.tien_vat) as vat
    from public.phieu_nhap pn where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy' group by 1),
  -- VAT nằm trong giá vốn vật tư đã xuất (lô của phiếu nhập có VAT), làm tròn theo từng phiếu xuất như chi_tiet_kqkd
  thang_vat_gv as (
    select date_trunc('month', v.ngay)::date as th, sum(v.vat) as vat
    from (select px.ngay, round(sum(xl.so_luong * xl.don_gia_von * pnd.ty_le_vat / (1 + pnd.ty_le_vat))) as vat
          from public.phieu_xuat px
          join public.phieu_xuat_dong pd on pd.phieu_id = px.id
          join public.xuat_lo xl on xl.phieu_xuat_dong_id = pd.id
          join public.lo_kho l on l.id = xl.lo_id
          join public.phieu_nhap_dong pnd on pnd.id = l.phieu_nhap_dong_id
          where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and pnd.ty_le_vat > 0
          group by px.id, px.ngay) v
    group by 1),
  thang_hh as (
    select date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel group by 1),
  song as (
    select t.th,
      coalesce(dt.bh,0) as dt_bh, coalesce(dt.kh,0) as dt_kh, coalesce(dt.dvn,0) as dt_dvn, coalesce(dt.gg,0) as gg,
      coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) as dthu, coalesce(dt.vat,0) as vat_ra,
      coalesce(k.xe,0) as gv_xe, coalesce(k.dc,0) as gv_dc, coalesce(c.gv,0) as chi_gv,
      coalesce(k.kk_thieu,0) - coalesce(tt.thua,0) as hao,
      coalesce(bl.tong_luong,0) as luong, coalesce(hh.hh,0) as hh, coalesce(c.vh,0) as vh, coalesce(c.cd,0) as cd,
      coalesce(tk.tk,0) as thu_khac,
      coalesce(vn.vat,0) as vat_hang, coalesce(c.vat_vao,0) as vat_cp, coalesce(vg.vat,0) as vat_gv,
      coalesce(x.xe,0) as so_xe, coalesce(dt.luot_dvn,0) as luot_dvn,
      bl.thang is not null as co_luong, ct.thang is not null as da_chot, ct.chot_luc, ct.so_lieu
    from cac_thang t
    left join thang_dt dt on dt.th = t.th
    left join thang_xe x on x.th = t.th
    left join thang_kho k on k.th = t.th
    left join thang_thua tt on tt.th = t.th
    left join thang_chi c on c.th = t.th
    left join thang_thu_khac tk on tk.th = t.th
    left join thang_vat_nhap vn on vn.th = t.th
    left join thang_vat_gv vg on vg.th = t.th
    left join thang_hh hh on hh.th = t.th
    left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
    left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th),
  tinh as (
    select s.*,
      s.gv_xe + s.gv_dc + s.hao + s.chi_gv as tong_gv,
      s.luong + s.hh + s.vh + s.cd as tong_cp
    from song s),
  tinh2 as (
    select t.*, t.dthu - t.tong_gv as lai_gop, t.dthu - t.tong_gv - t.tong_cp + t.thu_khac as lai_tt,
      t.vat_ra - t.vat_hang - t.vat_cp as vat_nop,
      -- lãi không gồm VAT (dồn tích): bỏ VAT khỏi doanh thu, khỏi giá vốn đã xuất và khỏi chi phí
      t.dthu - t.tong_gv - t.tong_cp + t.thu_khac - t.vat_ra + t.vat_gv + t.vat_cp as lai_kv
    from tinh t)
  select t.th, (t.th + interval '1 month' - interval '1 day')::date,
    case when t.da_chot then 'da_chot' when t.th >= date_trunc('month', current_date)::date then 'dang_mo' else 'cho_chot' end,
    app.so_chot(t.so_lieu, 'doanh_thu_bh', t.dt_bh), app.so_chot(t.so_lieu, 'doanh_thu_khach', t.dt_kh),
    app.so_chot(t.so_lieu, 'doanh_thu_dvn', t.dt_dvn), app.so_chot(t.so_lieu, 'giam_gia', t.gg),
    app.so_chot(t.so_lieu, 'doanh_thu', t.dthu), app.so_chot(t.so_lieu, 'vat_ra', t.vat_ra),
    app.so_chot(t.so_lieu, 'gia_von_xe', t.gv_xe), app.so_chot(t.so_lieu, 'gia_von_dung_chung', t.gv_dc),
    app.so_chot(t.so_lieu, 'chi_gia_von', t.chi_gv), app.so_chot(t.so_lieu, 'lai_gop', t.lai_gop),
    app.so_chot(t.so_lieu, 'luong', t.luong), app.so_chot(t.so_lieu, 'hoa_hong', t.hh),
    app.so_chot(t.so_lieu, 'chi_van_hanh', t.vh), app.so_chot(t.so_lieu, 'chi_co_dinh', t.cd),
    app.so_chot(t.so_lieu, 'lai_truoc_thue', t.lai_tt), app.so_chot(t.so_lieu, 'vat_vao', t.vat_hang + t.vat_cp),
    app.so_chot(t.so_lieu, 'so_xe', t.so_xe)::bigint,
    t.co_luong,
    coalesce((select array_agg(m.ten order by m.ten) from public.muc_thu_chi m
      where m.loai = 'chi' and m.dinh_ky and m.hoat_dong
        and not exists (select 1 from public.phieu_thu_chi p where p.muc_id = m.id and p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'
                          and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = t.th)
        and not exists (select 1 from public.de_nghi_chi d where d.muc_id = m.id and d.chi_nhanh_id = v_cn and d.trang_thai not in ('huy','tu_choi')
                          and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th)), '{}'::text[]),
    (select count(*) from public.de_nghi_chi d where d.chi_nhanh_id = v_cn and d.trang_thai in ('cho_duyet','da_duyet')
       and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th),
    t.da_chot, t.chot_luc,
    app.so_chot(t.so_lieu, 'hao_hut', t.hao), app.so_chot(t.so_lieu, 'tong_gia_von', t.tong_gv),
    app.so_chot(t.so_lieu, 'tong_chi_phi', t.tong_cp), app.so_chot(t.so_lieu, 'thu_khac', t.thu_khac),
    app.so_chot(t.so_lieu, 'vat_vao_hang', t.vat_hang), app.so_chot(t.so_lieu, 'vat_vao_chi_phi', t.vat_cp),
    app.so_chot(t.so_lieu, 'vat_trong_gia_von', t.vat_gv),
    app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop), app.so_chot(t.so_lieu, 'lai_sau_vat', t.lai_kv),
    app.so_chot(t.so_lieu, 'so_luot_dvn', t.luot_dvn)::bigint,
    -- Tháng đã chốt: số hiện tại khác số lúc chốt (hoặc chốt theo cách tính cũ) → cần mở lại, chốt lại
    t.da_chot and (not coalesce(t.so_lieu ? 'phien_ban', false)
      or abs(t.dthu - app.so_chot(t.so_lieu, 'doanh_thu', t.dthu)) >= 1
      or abs(t.lai_gop - app.so_chot(t.so_lieu, 'lai_gop', t.lai_gop)) >= 1
      or abs(t.lai_tt - app.so_chot(t.so_lieu, 'lai_truoc_thue', t.lai_tt)) >= 1
      or abs(t.vat_nop - app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop)) >= 1
      or abs(t.lai_kv - app.so_chot(t.so_lieu, 'lai_sau_vat', t.lai_kv)) >= 1),
    t.lai_tt
  from tinh2 t
  order by t.th;
end $$;
revoke execute on function public.ket_qua_kinh_doanh(text) from public, anon;
grant execute on function public.ket_qua_kinh_doanh(text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Chốt tháng lần lượt; lưu số dư cuối tháng; mở lại có lịch sử
-- ---------------------------------------------------------------------
create table if not exists public.chot_thang_lich_su (
  id           bigint generated always as identity primary key,
  chi_nhanh_id text not null references public.chi_nhanh(id),
  thang        date not null,
  so_lieu      jsonb,
  chot_boi     uuid,
  chot_luc     timestamptz,
  mo_lai_boi   uuid,
  mo_lai_luc   timestamptz not null default now(),
  ly_do        text not null
);
create index if not exists chot_thang_lich_su_thang_idx on public.chot_thang_lich_su (chi_nhanh_id, thang);
alter table public.chot_thang_lich_su enable row level security;
revoke all on public.chot_thang_lich_su from anon;
revoke insert, update, delete, truncate on public.chot_thang_lich_su from authenticated;
grant select on public.chot_thang_lich_su to authenticated;
drop policy if exists doc on public.chot_thang_lich_su;
create policy doc on public.chot_thang_lich_su for select to authenticated
  using ((select app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong'))
         and ((select app.co_vai_tro('giam_doc')) or chi_nhanh_id = (select app.chi_nhanh())));

create or replace function public.chot_thang(p_thang date, p_bo_qua_canh_bao boolean default false, p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; k record;
  v_thieu text[] := '{}'; v_truoc date; v_so jsonb;
begin
  perform app.yeu_cau('giam_doc');
  if v_thang >= date_trunc('month', current_date)::date then raise exception 'Chỉ chốt được tháng đã qua (kỳ khóa ở ngày cuối tháng).'; end if;
  if app.thang_da_chot(v_cn, v_thang) then raise exception 'Tháng này đã chốt rồi.'; end if;
  -- Chốt lần lượt: tháng trước có số liệu mà chưa chốt thì chốt trước (lũy kế báo cáo cổ đông không bị thủng)
  select min(x.thang) into v_truoc from public.ket_qua_kinh_doanh(v_cn) x
   where x.thang < v_thang and x.trang_thai = 'cho_chot'
     and (x.doanh_thu <> 0 or x.tong_gia_von <> 0 or x.tong_chi_phi <> 0 or x.thu_khac <> 0 or x.luong_da_nhap);
  if v_truoc is not null then
    raise exception 'Chốt tháng % trước (chốt lần lượt từng tháng).', to_char(v_truoc, 'MM/YYYY'); end if;
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
  v_so := to_jsonb(k) - 'da_chot' - 'chot_luc' - 'trang_thai' - 'lech_chot' - 'lai_truoc_thue_song'
    || jsonb_build_object('phien_ban', 2, 'so_du', app.so_du_cuoi_thang(v_cn, k.ngay_cuoi));
  insert into public.chot_thang (chi_nhanh_id, thang, chot_boi, so_lieu) values (v_cn, v_thang, auth.uid(), v_so);
  return v_so;
end $$;

create or replace function public.mo_lai_thang(p_thang date, p_ly_do text, p_chi_nhanh text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; c public.chot_thang; v_sau date;
begin
  perform app.yeu_cau('giam_doc');
  if nullif(trim(p_ly_do), '') is null then raise exception 'Ghi lý do mở lại tháng.'; end if;
  select * into c from public.chot_thang where chi_nhanh_id = v_cn and thang = v_thang for update;
  if not found then raise exception 'Tháng này chưa chốt.'; end if;
  -- Mở lại từ tháng sau cùng trở về (tháng sau còn chốt thì số lũy kế đã chốt dựa trên tháng này)
  select min(thang) into v_sau from public.chot_thang where chi_nhanh_id = v_cn and thang > v_thang;
  if v_sau is not null then raise exception 'Tháng % đã chốt – mở lại tháng đó trước.', to_char(v_sau, 'MM/YYYY'); end if;
  insert into public.chot_thang_lich_su (chi_nhanh_id, thang, so_lieu, chot_boi, chot_luc, mo_lai_boi, ly_do)
  values (c.chi_nhanh_id, c.thang, c.so_lieu, c.chot_boi, c.chot_luc, auth.uid(), trim(p_ly_do));
  delete from public.chot_thang where chi_nhanh_id = v_cn and thang = v_thang;
end $$;

-- ---------------------------------------------------------------------
-- 6. Chi tiết một ô của báo cáo (bấm vào số): từng phiếu / hồ sơ tạo nên số đó
-- ---------------------------------------------------------------------
create or replace function public.chi_tiet_kqkd(p_thang date, p_khoan text, p_chi_nhanh text default null)
returns table (nhom text, ten text, ngay date, so_tien numeric, ho_so_id bigint, ma text)
language plpgsql stable security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_tu date := date_trunc('month', p_thang)::date;
  v_den date := (date_trunc('month', p_thang) + interval '1 month - 1 day')::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  if p_khoan in ('doanh_thu_bh','doanh_thu_khach','giam_gia') then
    return query
      select coalesce(t.ten, case when p_khoan = 'giam_gia' then 'Giảm giá cho khách' else 'Khác' end),
        coalesce(d.bien_so_hs || ' · ', '') || d.ma, min(d.ngay), sum(d.so_tien), d.ho_so_id, d.ma
      from (select v.*, coalesce(v.bien_so, (select public.bien_so_hien_thi(x.bien_so) from public.ho_so h join public.xe x on x.id = h.xe_id where h.id = v.ho_so_id)) as bien_so_hs
            from public.v_doanh_thu v
            where v.chi_nhanh_id = v_cn and v.ngay between v_tu and v_den
              and v.nguon = case p_khoan when 'doanh_thu_bh' then 'bao_hiem' when 'doanh_thu_khach' then 'khach' else 'giam_gia' end) d
      left join public.to_thuc_hien t on t.id = d.to_id
      group by t.ten, d.bien_so_hs, d.ma, d.ho_so_id order by 4 desc;
  elsif p_khoan = 'doanh_thu_dvn' then
    return query
      select coalesce(t.ten, 'Detailing'), d.dich_vu || coalesce(' · ' || public.bien_so_hien_thi(d.bien_so), ''), d.ngay, d.so_tien, null::bigint, null::text
      from public.dich_vu_nhanh d left join public.to_thuc_hien t on t.id = d.to_id
      where d.chi_nhanh_id = v_cn and d.trang_thai = 'hieu_luc' and d.ngay between v_tu and v_den order by d.ngay, d.id;
  elsif p_khoan in ('gia_von_xe','gia_von_dung_chung','hao_hut') then
    return query
      select case px.loai when 'cho_xe' then coalesce(t.ten, 'Không qua đề xuất (xuất ngay, xuất lẻ)') when 'dung_chung' then 'Dùng chung xưởng' else 'Kiểm kê thiếu' end,
        px.ma || coalesce(' · ' || h.ma, '') || coalesce(' · ' || nullif(px.ghi_chu, ''), ''), px.ngay, sum(pd.gia_von), px.ho_so_id, h.ma
      from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
      left join public.ho_so h on h.id = px.ho_so_id
      left join public.de_xuat_vat_tu dx on dx.id = px.de_xuat_id
      left join public.to_thuc_hien t on t.id = dx.to_id
      where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and v_den
        and px.loai = case p_khoan when 'gia_von_xe' then 'cho_xe' when 'gia_von_dung_chung' then 'dung_chung' else 'kiem_ke' end
      group by px.loai, t.ten, px.ma, h.ma, px.ghi_chu, px.ngay, px.ho_so_id
      union all
      select 'Kiểm kê thừa (giảm hao hụt)', kk.ma || ' · ' || hk.ma || ' ' || hk.ten, l.ngay, -round(l.so_luong * l.don_gia_von), null::bigint, null::text
      from public.lo_kho l join public.kiem_ke kk on kk.id = l.kiem_ke_id join public.hang_kho hk on hk.id = l.hang_id
      where p_khoan = 'hao_hut' and l.chi_nhanh_id = v_cn and l.ngay between v_tu and v_den
      order by 1, 3;
  elsif p_khoan in ('chi_gia_von','chi_van_hanh','chi_co_dinh') then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.so_tien, dn.ho_so_id, h.ma
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      left join public.de_nghi_chi dn on dn.id = p.de_nghi_chi_id
      left join public.ho_so h on h.id = dn.ho_so_id
      where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
        and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = v_tu
        and case p_khoan when 'chi_gia_von' then m.nhom = 'gia_von' when 'chi_co_dinh' then m.nhom = 'co_dinh'
                         else coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh') end
      order by m.ten, p.ngay;
  elsif p_khoan = 'thu_khac' then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.so_tien, null::bigint, null::text
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      where p.chi_nhanh_id = v_cn and p.loai = 'thu' and p.trang_thai = 'hieu_luc' and m.vao_lai_lo and p.ngay between v_tu and v_den
      order by m.ten, p.ngay;
  elsif p_khoan = 'hoa_hong' then
    return query
      select coalesce(g.ten, h.gdv_ten_tam, 'GDV'), public.bien_so_hien_thi(x.bien_so) || ' · ' || h.ma, d.dau, h.hoa_hong_gdv, h.id, h.ma
      from public.ho_so h join public.xe x on x.id = h.xe_id
      left join public.giam_dinh_vien g on g.id = h.gdv_id
      join lateral (select min(m.ngay_duyet) as dau from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) d on true
      where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel
        and date_trunc('month', d.dau)::date = v_tu
      order by 1, 3;
  elsif p_khoan = 'luong' then
    return query
      select 'Bảng lương tháng'::text, 'Tổng lương tháng ' || to_char(v_tu, 'MM/YYYY'), v_den, bl.tong_luong, null::bigint, null::text
      from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn and bl.thang = v_tu;
  elsif p_khoan in ('vat_vao_hang') then
    return query
      select coalesce(n.ten, 'Nhà cung cấp'), pn.ma || coalesce(' · HĐ ' || pn.so_hoa_don, ''), pn.ngay, pn.tien_vat, pn.ho_so_id, null::text
      from public.phieu_nhap pn left join public.nha_cung_cap n on n.id = pn.nha_cung_cap_id
      where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy' and pn.ngay between v_tu and v_den and pn.tien_vat <> 0
      order by 1, 3;
  elsif p_khoan in ('vat_vao_chi_phi') then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.vat_dau_vao, null::bigint, null::text
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
        and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = v_tu and p.vat_dau_vao <> 0
      order by 1, 3;
  elsif p_khoan = 'vat_trong_gia_von' then
    -- VAT nằm trong giá vốn vật tư đã xuất: theo từng phiếu xuất (lô của phiếu nhập có VAT)
    return query
      select case px.loai when 'cho_xe' then 'Xuất cho xe' when 'dung_chung' then 'Dùng chung xưởng' else 'Kiểm kê thiếu' end,
        px.ma || coalesce(' · ' || h.ma, ''), px.ngay,
        round(sum(xl.so_luong * xl.don_gia_von * pnd.ty_le_vat / (1 + pnd.ty_le_vat))), px.ho_so_id, h.ma
      from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
      join public.xuat_lo xl on xl.phieu_xuat_dong_id = pd.id
      join public.lo_kho l on l.id = xl.lo_id
      join public.phieu_nhap_dong pnd on pnd.id = l.phieu_nhap_dong_id
      left join public.ho_so h on h.id = px.ho_so_id
      where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and v_den and pnd.ty_le_vat > 0
      group by px.id, px.loai, px.ma, h.ma, px.ngay, px.ho_so_id
      order by 1, 3;
  elsif p_khoan = 'vat_ra' then
    return query
      select case d.nguon when 'dich_vu_nhanh' then 'Dịch vụ nhanh' when 'giam_gia' then 'Giảm giá (giảm VAT đầu ra)' else 'Hồ sơ xe' end,
        concat_ws(' · ', d.bien_so_hs, d.ma), min(d.ngay), sum(d.vat_ra), d.ho_so_id, d.ma
      from (select v.*, coalesce(v.bien_so, (select public.bien_so_hien_thi(x.bien_so) from public.ho_so h join public.xe x on x.id = h.xe_id where h.id = v.ho_so_id)) as bien_so_hs
            from public.v_doanh_thu v
            where v.chi_nhanh_id = v_cn and v.ngay between v_tu and v_den and v.vat_ra <> 0) d
      group by d.nguon, d.bien_so_hs, d.ma, d.ho_so_id order by 1, 4 desc;
  elsif p_khoan = 'so_xe' then
    -- Xe tính vào tháng duyệt giá đầu tiên; số tiền = tổng giá đã duyệt (gồm VAT) của hồ sơ
    return query
      select case h.nguon_tt when 'khach' then 'Khách ngoài bảo hiểm' else coalesce(b.ten, 'Bảo hiểm') end,
        public.bien_so_hien_thi(x.bien_so) || ' · ' || h.ma, d.dau, d.tong, h.id, h.ma
      from public.ho_so h join public.xe x on x.id = h.xe_id
      left join public.hang_bao_hiem b on b.id = h.hang_bh_id
      join lateral (select min(m.ngay_duyet) as dau,
                      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)), 0) as tong
                    from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) d on true
      where h.chi_nhanh_id = v_cn and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
        and date_trunc('month', d.dau)::date = v_tu
      order by 1, 3;
  else
    raise exception 'Khoản "%" không có chi tiết.', p_khoan;
  end if;
end $$;
revoke execute on function public.chi_tiet_kqkd(date, text, text) from public, anon;
grant execute on function public.chi_tiet_kqkd(date, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Chi phí theo mục và lãi gộp theo tổ (theo tháng, trong khoảng) – bảng phân tích, xuất Excel
-- ---------------------------------------------------------------------
create or replace function public.chi_phi_theo_muc(p_tu date, p_den date, p_chi_nhanh text default null)
returns table (thang date, nhom text, muc text, so_tien numeric, so_phieu bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh());
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return query
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date), coalesce(m.nhom, 'van_hanh'), m.ten, sum(p.so_tien), count(*)
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
      and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) between date_trunc('month', p_tu)::date and p_den
    group by 1, 2, 3 order by 1, 2, 3;
end $$;
revoke execute on function public.chi_phi_theo_muc(date, date, text) from public, anon;
grant execute on function public.chi_phi_theo_muc(date, date, text) to authenticated;

-- Lãi gộp theo tổ: doanh thu theo tổ làm (dòng chưa giao tổ: theo nhóm), vật tư xuất theo tổ đề xuất.
-- Dòng "CHUNG": giảm giá, vật tư dùng chung, xuất không qua đề xuất, hao hụt kiểm kê, chi phí nhóm giá vốn
-- → cộng các dòng đúng bằng lãi gộp của báo cáo.
create or replace function public.lai_gop_theo_to(p_tu date, p_den date, p_chi_nhanh text default null)
returns table (thang date, to_id text, ten_to text, doanh_thu numeric, gia_von numeric, so_xe bigint, so_luot_dvn bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_tu date := date_trunc('month', p_tu)::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return query
  with dt as (
    select date_trunc('month', d.ngay)::date as th, coalesce(d.to_id, 'CHUNG') as to_id, sum(d.so_tien) as dthu,
      count(distinct d.ho_so_id) as xe, count(*) filter (where d.nguon = 'dich_vu_nhanh') as dvn
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn and d.ngay between v_tu and p_den group by 1, 2),
  gv as (
    select date_trunc('month', px.ngay)::date as th,
      case when px.loai = 'cho_xe' and dx.to_id is not null then dx.to_id else 'CHUNG' end as to_id, sum(pd.gia_von) as gv
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    left join public.de_xuat_vat_tu dx on dx.id = px.de_xuat_id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and p_den group by 1, 2
    union all
    select date_trunc('month', l.ngay)::date, 'CHUNG', -round(sum(l.so_luong * l.don_gia_von))
    from public.lo_kho l where l.chi_nhanh_id = v_cn and l.kiem_ke_id is not null and l.ngay between v_tu and p_den group by 1
    union all
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date), 'CHUNG', sum(p.so_tien)
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' and m.nhom = 'gia_von'
      and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) between v_tu and p_den group by 1),
  gv2 as (select g.th, g.to_id, sum(g.gv) as gv from gv g group by 1, 2),
  khoa as (select th, to_id from dt union select th, to_id from gv2)
  select k.th, k.to_id, case when k.to_id = 'CHUNG' then 'Chung (giảm giá, dùng chung, hao hụt, thuê ngoài…)' else coalesce(t.ten, k.to_id) end,
    coalesce(dt.dthu, 0), coalesce(gv2.gv, 0), coalesce(dt.xe, 0), coalesce(dt.dvn, 0)
  from khoa k
  left join dt on dt.th = k.th and dt.to_id = k.to_id
  left join gv2 on gv2.th = k.th and gv2.to_id = k.to_id
  left join public.to_thuc_hien t on t.id = k.to_id
  order by k.th, (k.to_id = 'CHUNG'), k.to_id;
end $$;
revoke execute on function public.lai_gop_theo_to(date, date, text) from public, anon;
grant execute on function public.lai_gop_theo_to(date, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- Múi giờ Việt Nam cho hàm mới có dùng ngày giờ hiện tại
-- ---------------------------------------------------------------------
do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%' or p.prosrc ilike '%localtimestamp%' or p.prosrc ilike '%current_timestamp%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';
