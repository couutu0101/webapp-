-- =====================================================================
-- 009 (12/10/2026): Báo giá chia theo nguồn lúc nhận xe + VAT riêng từng báo giá
--   - Xe bảo hiểm: dòng nào cũng do bảo hiểm trả, vẫn qua bước duyệt giá.
--   - Xe khách ngoài bảo hiểm: lưu báo giá là duyệt luôn (giá duyệt = giá báo, ngày duyệt = hôm nay),
--     hồ sơ sang "Đã duyệt giá"; doanh thu ghi vào ngày lưu báo giá.
--   - Mỗi lần báo giá chọn VAT 8% / 10% / 12% (lưu vào từng dòng: hang_muc.ty_le_vat).
--     Dòng cũ chưa có ty_le_vat thì vẫn tính theo bảng thue_suat_vat như trước.
--   Tương thích ngược: hàm luu_bao_gia cũ giữ nguyên; giao diện mới gọi lap_bao_gia.
-- =====================================================================
alter table public.hang_muc add column if not exists ty_le_vat numeric(5,4)
  check (ty_le_vat is null or (ty_le_vat >= 0 and ty_le_vat < 1));
comment on column public.hang_muc.ty_le_vat is 'VAT chọn lúc lập báo giá (0.08/0.10/0.12). Trống = theo bảng thue_suat_vat';

-- Tiền có VAT của một dòng báo giá: ưu tiên VAT đã chọn trên dòng
create or replace function public.tien_dong_co_vat(so_tien numeric, xuat_hd boolean, ngay date, ty_le numeric) returns numeric
language sql stable as $$
  select case when so_tien is null then 0
              when xuat_hd then round(so_tien * (1 + coalesce(ty_le, public.vat_ty_le(coalesce(ngay, current_date)))))
              else so_tien end
$$;

create or replace function app.tien_ho_so(p_id bigint)
returns table (
  bh_duyet numeric, khach_duyet numeric, phai_thu_bh numeric, phai_thu_khach numeric,
  da_thu_bh numeric, da_thu_khach numeric, con_no_bh numeric, con_no_khach numeric)
language sql stable security definer set search_path = public as $$
  with d as (
    select
      coalesce(sum(public.tien_dong_co_vat(gia_duyet, true, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0) as kh
    from public.hang_muc
    where ho_so_id = p_id and trang_thai in ('duyet','dang_lam','xong')
  ), t as (
    select
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0) as kh
    from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
    where pb.ho_so_id = p_id and p.trang_thai = 'hieu_luc'
  )
  select d.bh, d.kh,
         d.bh - h.khau_tru_giam_tru,
         d.kh + h.khau_tru_giam_tru - h.giam_gia,
         t.bh, t.kh,
         d.bh - h.khau_tru_giam_tru - t.bh,
         d.kh + h.khau_tru_giam_tru - h.giam_gia - t.kh
  from d, t, public.ho_so h where h.id = p_id
$$;

-- Doanh thu theo ngày: dùng VAT của từng dòng (cột giữ nguyên như cũ)
create or replace view public.v_doanh_thu with (security_invoker = true) as
select h.chi_nhanh_id, m.ngay_duyet as ngay, h.id as ho_so_id, h.ma, public.bien_so_hien_thi(x.bien_so) as bien_so,
  m.nguoi_tra as nguon, m.nhom, public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat) as so_tien,
  case when m.xuat_hd then public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet else 0 end as vat_ra
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

-- =====================================================================
-- Lập báo giá theo nguồn của hồ sơ
-- dong: [{ten, nhom, gia_bao}]  (gia_bao = giá trước VAT); p_vat: 0.08 / 0.10 / 0.12
-- =====================================================================
create or replace function public.lap_bao_gia(p_ho_so bigint, dong jsonb, p_vat numeric) returns int
language plpgsql security definer set search_path = public as $$
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

  v_khach := h.nguon_tt = 'khach';
  v_nguoi := case when v_khach then 'khach' else 'bao_hiem' end;

  if h.trang_thai in ('tiep_nhan','bao_gia') then
    v_lan := 0;
  elsif h.trang_thai in ('da_duyet','dang_sua','cho_kcs') then
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
    if h.trang_thai = 'cho_kcs' then
      perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Báo giá bổ sung lần ' || v_lan);
    else
      perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo giá bổ sung lần ' || v_lan);
    end if;
  end if;
  return v_lan;
end $$;

revoke execute on function public.lap_bao_gia(bigint, jsonb, numeric) from public, anon;
grant execute on function public.lap_bao_gia(bigint, jsonb, numeric) to authenticated;
revoke execute on function public.tien_dong_co_vat(numeric, boolean, date, numeric) from public, anon;
grant execute on function public.tien_dong_co_vat(numeric, boolean, date, numeric) to authenticated;
