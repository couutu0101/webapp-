-- =====================================================================
-- 008 (12/10/2026): XÓA HẲN "Văn phòng bảo hiểm" (anh Thuận chọn xóa hẳn, không lấy lại được).
--   CHỈ CHẠY TRÊN SUPABASE SAU KHI BẢN THẬT ĐÃ CẬP NHẬT GIAO DIỆN MỚI ("OK, đưa lên"),
--   vì giao diện cũ của bản thật còn đọc bảng van_phong_bao_hiem.
--   - Bỏ văn phòng khỏi hàm tra cứu xe và bảng xem v_ho_so (tiếp nhận, sửa thông tin: đã ở 031).
--   - Xóa cột ho_so.van_phong_bh_id và bảng van_phong_bao_hiem.
-- =====================================================================
-- (public.tiep_nhan_xe: bản bỏ văn phòng BH nằm ở 031 – chạy được cả trước và sau 008, nên 008 không tạo lại hàm này)

-- (public.sua_thong_tin_ho_so: bản bỏ văn phòng BH nằm ở 031 – chạy được cả trước và sau 008, nên 008 không tạo lại hàm này)

create or replace function public.tra_cuu_xe(p_bien_so text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_bs text := public.bien_so_gon(p_bien_so); r jsonb;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if v_bs is null then return null; end if;
  select jsonb_build_object(
    'xe_id', x.id, 'bien_so', public.bien_so_hien_thi(x.bien_so), 'dong_xe_id', x.dong_xe_id,
    'hang_xe_id', dx.hang_xe_id, 'mau', x.mau, 'han_bao_hiem', x.han_bao_hiem, 'han_bh_than_vo', x.han_bh_than_vo,
    'ten_khach', k.ten, 'dien_thoai', k.dien_thoai,
    'so_lan_vao', (select count(*) from public.ho_so h where h.xe_id = x.id),
    'ho_so_mo', (select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'trang_thai', h.trang_thai))
                 from public.ho_so h where h.xe_id = x.id and h.trang_thai not in ('dong','huy')),
    'ho_so_gan_nhat', (select jsonb_build_object('id', h.id, 'ma', h.ma, 'nguon_tt', h.nguon_tt, 'hang_bh_id', h.hang_bh_id,
                         'gdv_id', h.gdv_id)
                       from public.ho_so h where h.xe_id = x.id order by h.id desc limit 1))
  into r
  from public.xe x
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.khach_hang k on k.id = x.khach_hang_id
  where x.bien_so = v_bs;
  return r;
end $$;

-- v_canh_bao dựa trên v_ho_so: xóa cả hai rồi tạo lại (v_canh_bao giữ nguyên như tệp 004)
drop view public.v_canh_bao;
drop view public.v_ho_so;
create view public.v_ho_so with (security_invoker = true) as
select
  h.id, h.ma, h.chi_nhanh_id, h.loai, h.ho_so_goc_id, h.trang_thai, h.ngay_vao, h.hen_giao, h.giao_luc,
  h.nguon_tt, h.tinh_trang_xe, h.tu_van, h.han_bao_hiem, h.khau_tru_giam_tru, h.giam_gia,
  h.so_hd_bao_hiem, h.so_hd_khach, h.cam_nhan_khach, h.gui_hs_ngay, h.hoa_hong_gdv, h.hoa_hong_ghi_chu,
  h.cham_soc_luc, h.cham_soc_ket_qua, h.hen_bao_duong, h.ly_do_huy, h.cho_giao_no_boi, h.tu_excel,
  h.xe_id, h.khach_hang_id, h.hang_bh_id, h.gdv_id,
  x.bien_so, public.bien_so_hien_thi(x.bien_so) as bien_so_hien_thi, x.dong_xe_id, x.mau,
  concat_ws(' ', hx.ten, dx.ten) as xe,
  k.ten as ten_khach, k.dien_thoai,
  b.ten as hang_bh,
  coalesce(h.gdv_ten_tam, g.ten) as gdv, coalesce(g.la_cho_them, false) as gdv_cho_them,
  (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) as ngay_duyet_dau,
  exists (select 1 from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai = 'cho_duyet') as co_dong_cho_duyet,
  exists (select 1 from public.phat_sinh p where p.ho_so_id = h.id and not p.da_xu_ly) as co_phat_sinh,
  t.bh_duyet, t.khach_duyet, t.phai_thu_bh, t.phai_thu_khach, t.da_thu_bh, t.da_thu_khach, t.con_no_bh, t.con_no_khach,
  h.han_bh_than_vo
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
cross join lateral public.tien_ho_so(h.id) t;

create view public.v_canh_bao with (security_invoker = true) as
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

grant select on public.v_ho_so, public.v_canh_bao to authenticated;
revoke all on public.v_ho_so, public.v_canh_bao from anon;

alter table public.ho_so drop column van_phong_bh_id;
drop table public.van_phong_bao_hiem;
