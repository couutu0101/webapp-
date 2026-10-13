-- =====================================================================
-- 030 (14/10/2026): TÀI KHOẢN CỔ ĐÔNG – XEM ĐƯỢC TẤT CẢ SỐ LIỆU, KHÔNG SỬA ĐƯỢC GÌ
--  - Trước: cổ đông chỉ xem Báo cáo cổ đông (tháng đã chốt).
--  - Nay: đọc được như giám đốc trong chi nhánh của mình (hồ sơ xe, ảnh, dịch vụ nhanh, thu chi, đề nghị chi,
--    kho, thiết bị đồ nghề, doanh thu, công nợ, kết quả kinh doanh mọi tháng, danh mục, danh sách nhân viên).
--  - KHÔNG ghi: mọi hàm ghi vẫn đòi vai trò làm việc (cổ đông không có, và cổ đông không được kiêm vai trò khác);
--    app.la_nhan_vien() GIỮ NGUYÊN (dùng cho quyền ghi) – chỉ chính sách ĐỌC đổi sang app.xem_nhu_nhan_vien().
--    Nhật ký xuất file và xuất Excel vẫn chỉ giám đốc.
--  - Tệp này sinh tự động từ CSDL (chính sách SELECT có la_nhan_vien() hoặc mảng vai trò có kế toán → thêm cổ đông).
--  Tương thích ngược: chỉ mở rộng quyền đọc cho vai trò co_dong.
-- =====================================================================

create or replace function app.la_co_dong() returns boolean
language sql stable as $$ select app.vai_tro() && array['co_dong'] $$;

-- Quyền ĐỌC: nhân viên văn phòng + cổ đông (KHÔNG dùng cho quyền ghi)
create or replace function app.xem_nhu_nhan_vien() returns boolean
language sql stable as $$ select app.vai_tro() && array['giam_doc','quan_ly','ke_toan','cvdv','kho','co_dong'] $$;

revoke execute on function app.la_co_dong(), app.xem_nhu_nhan_vien() from public, anon;
grant execute on function app.la_co_dong(), app.xem_nhu_nhan_vien() to authenticated;

alter policy "doc" on public.bang_luong_thang using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.cai_dat using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.chot_thang using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.de_nghi_chi using ((app.duoc_xem_chi_nhanh(chi_nhanh_id) AND (app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) OR (nguoi_de_nghi = auth.uid()))));

alter policy "doc" on public.de_nghi_mua using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.de_nghi_mua_dong using ((EXISTS ( SELECT 1
   FROM de_nghi_mua d
  WHERE ((d.id = de_nghi_mua_dong.de_nghi_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.de_xuat_dong using ((EXISTS ( SELECT 1
   FROM de_xuat_vat_tu d
  WHERE ((d.id = de_xuat_dong.de_xuat_id) AND (app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.de_xuat_vat_tu using (((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.dich_vu_nhanh using ((app.duoc_xem_chi_nhanh(chi_nhanh_id) AND (app.xem_nhu_nhan_vien() OR (tao_boi = auth.uid()))));

alter policy "doc" on public.don_vi_lien_quan using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.dong_xe using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.giam_dinh_vien using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.hang_bao_hiem using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.hang_kho using (((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.hang_muc using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = hang_muc.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.hang_xe using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.ho_so using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.ho_so_nhat_ky using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = ho_so_nhat_ky.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.ho_so_tep using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = ho_so_tep.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.kcs using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = kcs.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.khach_hang using (app.xem_nhu_nhan_vien());

alter policy "doc" on public.kho_tep using (app.xem_nhu_nhan_vien());

alter policy "doc" on public.kiem_ke using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.kiem_ke_dong using ((EXISTS ( SELECT 1
   FROM kiem_ke d
  WHERE ((d.id = kiem_ke_dong.kiem_ke_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.kiem_quy using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.lo_kho using (((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.muc_thu_chi using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.nha_cung_cap using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.nhan_vien using (((id = auth.uid()) OR app.xem_nhu_nhan_vien()));

alter policy "doc" on public.nhom_tai_san using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.phan_bo using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND (EXISTS ( SELECT 1
   FROM phieu_thu_chi p
  WHERE ((p.id = phan_bo.phieu_id) AND app.duoc_xem_chi_nhanh(p.chi_nhanh_id))))));

alter policy "doc" on public.phat_sinh using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = phat_sinh.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.phieu_nhap using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.phieu_nhap_dong using ((EXISTS ( SELECT 1
   FROM phieu_nhap d
  WHERE ((d.id = phieu_nhap_dong.phieu_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.phieu_thu_chi using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.phieu_xuat using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.phieu_xuat_dong using ((EXISTS ( SELECT 1
   FROM phieu_xuat d
  WHERE ((d.id = phieu_xuat_dong.phieu_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.tai_khoan_quy using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'ke_toan'::text, 'quan_ly'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.thue_suat_vat using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.to_thuc_hien using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.xe using (app.xem_nhu_nhan_vien());

alter policy "doc" on public.xuat_lo using (app.xem_nhu_nhan_vien());

alter policy "ho-so-xe doc" on storage.objects using (((bucket_id = 'ho-so-xe'::text) AND (app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text]))));

create or replace view public.v_cong_no_ncc with (security_invoker=true) as
 SELECT n.id AS nha_cung_cap_id,
    n.ten,
    c.chi_nhanh_id,
    COALESCE(( SELECT sum(p.tong_tien) AS sum
           FROM phieu_nhap p
          WHERE p.nha_cung_cap_id = n.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.trang_thai = 'da_khop'::text), 0::numeric) AS da_nhap,
    COALESCE(( SELECT sum(p.tong_tien) AS sum
           FROM phieu_nhap p
          WHERE p.nha_cung_cap_id = n.id AND p.chi_nhanh_id = c.chi_nhanh_id AND (p.trang_thai = ANY (ARRAY['cho_khop'::text, 'treo'::text]))), 0::numeric) AS cho_khop,
    COALESCE(( SELECT sum(t.so_tien) AS sum
           FROM phieu_thu_chi t
             JOIN muc_thu_chi m ON m.id = t.muc_id
          WHERE t.nha_cung_cap_id = n.id AND t.chi_nhanh_id = c.chi_nhanh_id AND t.loai = 'chi'::text AND t.trang_thai = 'hieu_luc'::text AND m.tinh_chat = 'tra_ncc'::text), 0::numeric) AS da_tra
   FROM nha_cung_cap n
     CROSS JOIN ( SELECT chi_nhanh.id AS chi_nhanh_id
           FROM chi_nhanh) c
  WHERE app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'kho'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(c.chi_nhanh_id);

create or replace view public.v_cong_no_noi_bo with (security_invoker=true) as
 SELECT id,
    ten,
    loai,
    hoat_dong,
    so_du_dau_ky,
    ngay_dau_ky,
    chi_nhanh_id,
    da_chi,
    da_thu,
    ngay_cuoi,
    so_du_dau_ky + da_chi - da_thu AS con_lai
   FROM ( SELECT dv.id,
            dv.ten,
            dv.loai,
            dv.hoat_dong,
            dv.so_du_dau_ky,
            dv.ngay_dau_ky,
            c.chi_nhanh_id,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'chi'::text AND p.trang_thai = 'hieu_luc'::text), 0::numeric) AS da_chi,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'thu'::text AND p.trang_thai = 'hieu_luc'::text), 0::numeric) AS da_thu,
            ( SELECT max(p.ngay) AS max
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.trang_thai = 'hieu_luc'::text) AS ngay_cuoi
           FROM don_vi_lien_quan dv
             CROSS JOIN ( SELECT chi_nhanh.id AS chi_nhanh_id
                   FROM chi_nhanh) c
          WHERE app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(c.chi_nhanh_id)) x;

create or replace view public.v_de_xuat as
 SELECT d.id,
    d.chi_nhanh_id,
    d.ma,
    d.ho_so_id,
    d.to_id,
    d.ghi_chu,
    d.trang_thai,
    d.nguoi_lap,
    d.tao_luc,
    h.ma AS ma_ho_so,
    bien_so_hien_thi(x.bien_so) AS bien_so,
    h.trang_thai AS trang_thai_ho_so,
    nv.ho_ten AS nguoi_lap_ten,
    ( SELECT count(*) AS count
           FROM de_xuat_dong dd
          WHERE dd.de_xuat_id = d.id) AS so_dong,
    ( SELECT count(*) AS count
           FROM de_xuat_dong dd
          WHERE dd.de_xuat_id = d.id AND dd.cho_mua) AS so_dong_cho_mua
   FROM de_xuat_vat_tu d
     JOIN ho_so h ON h.id = d.ho_so_id
     JOIN xe x ON x.id = h.xe_id
     LEFT JOIN nhan_vien nv ON nv.id = d.nguoi_lap
  WHERE app.duoc_xem_chi_nhanh(d.chi_nhanh_id) AND (app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text]));

CREATE OR REPLACE FUNCTION public.tien_ho_so(p_id bigint)
 RETURNS TABLE(bh_duyet numeric, khach_duyet numeric, phai_thu_bh numeric, phai_thu_khach numeric, da_thu_bh numeric, da_thu_khach numeric, con_no_bh numeric, con_no_khach numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from app.tien_ho_so(p_id) where app.xem_nhu_nhan_vien()
$function$;

CREATE OR REPLACE FUNCTION app.xem_nhom_tai_san(cn text, nhom text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select app.duoc_xem_chi_nhanh(cn) and (
    app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong')
    or (app.co_vai_tro('truong_nhom') and exists (
      select 1 from public.nhom_tai_san n where n.id = nhom and n.to_id is not null and n.to_id = app.to_cua_toi())))
$function$;

CREATE OR REPLACE FUNCTION public.ket_qua_kinh_doanh(p_chi_nhanh text DEFAULT NULL::text)
 RETURNS TABLE(thang date, ngay_cuoi date, trang_thai text, doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric, gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric, luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric, so_xe bigint, luong_da_nhap boolean, thieu_dinh_ky text[], de_nghi_cho_chi bigint, da_chot boolean, chot_luc timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_dau date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
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
end $function$;
