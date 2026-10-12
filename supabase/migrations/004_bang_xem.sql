-- =====================================================================
-- 004: Bảng xem (view) cho giao diện
-- security_invoker = true: view tuân theo phân quyền của người đang xem.
-- =====================================================================

-- Danh sách hồ sơ kèm tiền
create or replace view public.v_ho_so with (security_invoker = true) as
select
  h.id, h.ma, h.chi_nhanh_id, h.loai, h.ho_so_goc_id, h.trang_thai, h.ngay_vao, h.hen_giao, h.giao_luc,
  h.nguon_tt, h.tinh_trang_xe, h.tu_van, h.han_bao_hiem, h.khau_tru_giam_tru, h.giam_gia,
  h.so_hd_bao_hiem, h.so_hd_khach, h.cam_nhan_khach, h.gui_hs_ngay, h.hoa_hong_gdv, h.hoa_hong_ghi_chu,
  h.cham_soc_luc, h.cham_soc_ket_qua, h.hen_bao_duong, h.ly_do_huy, h.cho_giao_no_boi, h.tu_excel,
  h.xe_id, h.khach_hang_id, h.hang_bh_id, h.van_phong_bh_id, h.gdv_id,
  x.bien_so, public.bien_so_hien_thi(x.bien_so) as bien_so_hien_thi, x.dong_xe_id, x.mau,
  concat_ws(' ', hx.ten, dx.ten) as xe,
  k.ten as ten_khach, k.dien_thoai,
  b.ten as hang_bh, vp.ten as van_phong_bh,
  coalesce(h.gdv_ten_tam, g.ten) as gdv, coalesce(g.la_cho_them, false) as gdv_cho_them,
  (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) as ngay_duyet_dau,
  exists (select 1 from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai = 'cho_duyet') as co_dong_cho_duyet,
  exists (select 1 from public.phat_sinh p where p.ho_so_id = h.id and not p.da_xu_ly) as co_phat_sinh,
  t.bh_duyet, t.khach_duyet, t.phai_thu_bh, t.phai_thu_khach, t.da_thu_bh, t.da_thu_khach, t.con_no_bh, t.con_no_khach
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.van_phong_bao_hiem vp on vp.id = h.van_phong_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
cross join lateral public.tien_ho_so(h.id) t;

-- Số dư từng tài khoản quỹ
create or replace view public.v_so_du_quy with (security_invoker = true) as
select tk.id, tk.chi_nhanh_id, tk.ten, tk.hoat_dong, tk.so_du_dau_ky, tk.ngay_dau_ky,
  tk.so_du_dau_ky + coalesce((
    select sum(case
      when p.loai = 'thu' and p.tai_khoan_id = tk.id then p.so_tien
      when p.loai = 'chi' and p.tai_khoan_id = tk.id then -p.so_tien
      when p.loai = 'chuyen' and p.tai_khoan_id = tk.id then -p.so_tien
      when p.loai = 'chuyen' and p.tai_khoan_den_id = tk.id then p.so_tien
      else 0 end)
    from public.phieu_thu_chi p
    where p.trang_thai = 'hieu_luc' and p.ngay >= tk.ngay_dau_ky
      and (p.tai_khoan_id = tk.id or p.tai_khoan_den_id = tk.id)), 0) as so_du
from public.tai_khoan_quy tk;

-- Sổ thu chi
create or replace view public.v_phieu_thu_chi with (security_invoker = true) as
select p.id, p.chi_nhanh_id, p.ngay, p.loai, p.so_tien, p.vat_dau_vao, p.noi_dung, p.trang_thai, p.ly_do_huy, p.tao_luc,
  p.tai_khoan_id, tk.ten as tai_khoan, p.tai_khoan_den_id, tk2.ten as tai_khoan_den,
  p.muc_id, m.ten as muc, m.tinh_chat, m.nhom,
  b.ten as hang_bh, ncc.ten as nha_cung_cap, g.ten as gdv, dv.ten as don_vi_lien_quan,
  p.de_nghi_chi_id, nv.ho_ten as nguoi_lap,
  coalesce((select sum(pb.so_tien) from public.phan_bo pb where pb.phieu_id = p.id), 0) as da_phan_bo,
  (select string_agg(h.ma, ', ') from public.phan_bo pb join public.ho_so h on h.id = pb.ho_so_id where pb.phieu_id = p.id) as ho_so
from public.phieu_thu_chi p
join public.tai_khoan_quy tk on tk.id = p.tai_khoan_id
left join public.tai_khoan_quy tk2 on tk2.id = p.tai_khoan_den_id
left join public.muc_thu_chi m on m.id = p.muc_id
left join public.hang_bao_hiem b on b.id = p.hang_bh_id
left join public.nha_cung_cap ncc on ncc.id = p.nha_cung_cap_id
left join public.giam_dinh_vien g on g.id = p.gdv_id
left join public.don_vi_lien_quan dv on dv.id = p.don_vi_lien_quan_id
left join public.nhan_vien nv on nv.id = p.tao_boi;

-- Đề nghị chi
create or replace view public.v_de_nghi_chi with (security_invoker = true) as
select d.*, m.ten as muc, m.tinh_chat, nv.ho_ten as nguoi_de_nghi_ten, nd.ho_ten as nguoi_duyet_ten,
  h.ma as ho_so_ma, ncc.ten as nha_cung_cap, g.ten as gdv, dv.ten as don_vi_lien_quan,
  d.so_tien > app.cai_dat_so('han_muc_chi_quan_ly', 2000000) as can_giam_doc,
  -- dấu hiệu tách nhỏ phiếu: cùng người, cùng mục, cùng ngày, mỗi phiếu dưới mức nhưng cộng lại vượt mức
  (select count(*) > 1 and sum(d2.so_tien) > app.cai_dat_so('han_muc_chi_quan_ly', 2000000)
     from public.de_nghi_chi d2
     where d2.nguoi_de_nghi = d.nguoi_de_nghi and d2.muc_id = d.muc_id and d2.ngay = d.ngay
       and d2.trang_thai <> 'huy' and d2.so_tien <= app.cai_dat_so('han_muc_chi_quan_ly', 2000000)) as nghi_tach_phieu
from public.de_nghi_chi d
join public.muc_thu_chi m on m.id = d.muc_id
left join public.nhan_vien nv on nv.id = d.nguoi_de_nghi
left join public.nhan_vien nd on nd.id = d.duyet_boi
left join public.ho_so h on h.id = d.ho_so_id
left join public.nha_cung_cap ncc on ncc.id = d.nha_cung_cap_id
left join public.giam_dinh_vien g on g.id = d.gdv_id
left join public.don_vi_lien_quan dv on dv.id = d.don_vi_lien_quan_id;

-- Dịch vụ nhanh kèm số đã thu
create or replace view public.v_dich_vu_nhanh with (security_invoker = true) as
select d.*, public.bien_so_hien_thi(d.bien_so) as bien_so_hien_thi,
  coalesce((select sum(pb.so_tien) from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
            where pb.dich_vu_nhanh_id = d.id and p.trang_thai = 'hieu_luc'), 0) as da_thu
from public.dich_vu_nhanh d;

-- Doanh thu theo ngày (thay file BC DOANH THU THEO NGÀY). Tính sau VAT.
create or replace view public.v_doanh_thu with (security_invoker = true) as
select h.chi_nhanh_id, m.ngay_duyet as ngay, h.id as ho_so_id, h.ma, public.bien_so_hien_thi(x.bien_so) as bien_so,
  m.nguoi_tra as nguon, m.nhom, public.tien_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet) as so_tien,
  case when m.xuat_hd then public.tien_co_vat(m.gia_duyet, true, m.ngay_duyet) - m.gia_duyet else 0 end as vat_ra
from public.hang_muc m
join public.ho_so h on h.id = m.ho_so_id
join public.xe x on x.id = h.xe_id
where m.trang_thai in ('duyet','dang_lam','xong') and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
union all
select d.chi_nhanh_id, d.ngay, null, null, public.bien_so_hien_thi(d.bien_so), 'dich_vu_nhanh', 'detailing',
  d.so_tien, case when d.xuat_hd then d.so_tien - round(d.so_tien / (1 + public.vat_ty_le(d.ngay))) else 0 end
from public.dich_vu_nhanh d where d.trang_thai = 'hieu_luc'
union all
select h.chi_nhanh_id, h.giam_gia_ngay, h.id, h.ma, null, 'giam_gia', null, -h.giam_gia, 0
from public.ho_so h where h.giam_gia > 0 and h.trang_thai <> 'huy' and not h.tu_excel;

-- Việc cần xử lý (cảnh báo). Các mốc ngày lấy trong bảng cai_dat.
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

grant select on public.v_ho_so, public.v_so_du_quy, public.v_phieu_thu_chi, public.v_de_nghi_chi,
  public.v_dich_vu_nhanh, public.v_doanh_thu, public.v_canh_bao to authenticated;
revoke all on public.v_ho_so, public.v_so_du_quy, public.v_phieu_thu_chi, public.v_de_nghi_chi,
  public.v_dich_vu_nhanh, public.v_doanh_thu, public.v_canh_bao from anon;
