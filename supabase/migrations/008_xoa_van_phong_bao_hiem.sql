-- =====================================================================
-- 008 (12/10/2026): XÓA HẲN "Văn phòng bảo hiểm" (anh Thuận chọn xóa hẳn, không lấy lại được).
--   CHỈ CHẠY TRÊN SUPABASE SAU KHI BẢN THẬT ĐÃ CẬP NHẬT GIAO DIỆN MỚI ("OK, đưa lên"),
--   vì giao diện cũ của bản thật còn đọc bảng van_phong_bao_hiem.
--   - Bỏ văn phòng khỏi các hàm tiếp nhận, sửa thông tin, tra cứu xe và bảng xem v_ho_so.
--   - Xóa cột ho_so.van_phong_bh_id và bảng van_phong_bao_hiem.
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
    hang_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), auth.uid())
  returning id into v_id;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', 'Tiếp nhận xe');
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

create or replace function public.sua_thong_tin_ho_so(p_id bigint, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_dt text; v_gdv public.giam_dinh_vien;
begin
  perform app.yeu_cau('cvdv','ke_toan','quan_ly','giam_doc');
  h := app.lay_ho_so(p_id);
  if p ? 'ten_khach' or p ? 'dien_thoai' then
    v_dt := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
    if p ? 'dien_thoai' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số.'; end if;
    update public.khach_hang set
      ten = coalesce(nullif(trim(p->>'ten_khach'),''), ten),
      dien_thoai = case when p ? 'dien_thoai' then v_dt else dien_thoai end
    where id = h.khach_hang_id;
  end if;
  if p ? 'gdv_id' then
    select * into v_gdv from public.giam_dinh_vien where id = (p->>'gdv_id')::bigint;
    if v_gdv.la_cho_them and nullif(trim(p->>'gdv_ten_tam'),'') is null then
      raise exception 'Chọn "GDV mới – chờ thêm" thì phải ghi tên giám định viên.'; end if;
  end if;
  update public.ho_so set
    hang_bh_id      = case when p ? 'hang_bh_id' then (p->>'hang_bh_id')::bigint else hang_bh_id end,
    gdv_id          = case when p ? 'gdv_id' then (p->>'gdv_id')::bigint else gdv_id end,
    gdv_ten_tam     = case when p ? 'gdv_id' then case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end else gdv_ten_tam end,
    han_bao_hiem    = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end,
    han_bh_than_vo  = case when p ? 'han_bh_than_vo' then (p->>'han_bh_than_vo')::date else han_bh_than_vo end,
    tinh_trang_xe   = coalesce(nullif(trim(p->>'tinh_trang_xe'),''), tinh_trang_xe),
    tu_van          = coalesce(nullif(trim(p->>'tu_van'),''), tu_van),
    hen_giao        = case when p ? 'hen_giao' then (p->>'hen_giao')::timestamptz else hen_giao end,
    cap_nhat_luc    = now()
  where id = p_id;
  update public.xe set
    dong_xe_id   = case when p ? 'dong_xe_id' then (p->>'dong_xe_id')::bigint else dong_xe_id end,
    mau          = case when p ? 'mau' then nullif(trim(p->>'mau'),'') else mau end,
    han_bao_hiem = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end,
    han_bh_than_vo = case when p ? 'han_bh_than_vo' then (p->>'han_bh_than_vo')::date else han_bh_than_vo end
  where id = h.xe_id;
  perform app.ghi_nhat_ky(p_id, h.trang_thai, h.trang_thai, 'Sửa thông tin: ' || (select string_agg(k, ', ') from jsonb_object_keys(p) k));
end $$;

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
