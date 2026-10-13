-- =====================================================================
-- 013 (13/10/2026): XUẤT EXCEL – chỉ giám đốc
--   - xuat_du_lieu_kho(): tồn kho hiện tại từng mã (giao diện chia mỗi nhóm một trang).
--   - xuat_du_lieu_khach(): khách – xe (kèm đơn vị bảo hiểm lần gần nhất) và công nợ (xe đã giao còn nợ; nợ khách, nợ bảo hiểm tách riêng).
--   - Mỗi lần xuất ghi vào nhat_ky_xuat_file (ai, lúc nào, xuất gì, bao nhiêu dòng).
--   Tương thích ngược: chỉ thêm bảng và hàm mới.
-- =====================================================================

create table if not exists public.nhat_ky_xuat_file (
  id            bigint generated always as identity primary key,
  nguoi         uuid,
  luc           timestamptz not null default now(),
  loai          text not null check (loai in ('kho','khach_hang')),
  chi_nhanh_id  text,
  so_dong       int
);
alter table public.nhat_ky_xuat_file enable row level security;
drop policy if exists xem on public.nhat_ky_xuat_file;
create policy xem on public.nhat_ky_xuat_file for select to authenticated using (app.co_vai_tro('giam_doc'));
revoke all on public.nhat_ky_xuat_file from anon;
grant select on public.nhat_ky_xuat_file to authenticated;

-- Tồn kho hiện tại của một chi nhánh
create or replace function public.xuat_du_lieu_kho(p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_hang jsonb;
begin
  perform app.yeu_cau('giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  select coalesce(jsonb_agg(jsonb_build_object(
      'ma', t.ma, 'ten', t.ten, 'nhom', t.nhom, 'dvt', t.dvt, 'dvt_nhap', t.dvt_nhap, 'he_so', t.he_so,
      'ton', t.ton, 'gia_tri', t.gia_tri,
      'don_gia', case when t.ton > 0 then round(t.gia_tri / t.ton, 2) end,
      'ton_toi_thieu', t.ton_toi_thieu, 'duoi_toi_thieu', t.duoi_toi_thieu,
      'nha_cung_cap', t.nha_cung_cap, 'gia_nhap_gan_nhat', t.gia_nhap_gan_nhat, 'ghi_chu', t.ghi_chu)
      order by t.nhom, t.ma), '[]'::jsonb)
    into v_hang
  from public.v_ton_kho t
  where t.chi_nhanh_id = v_cn and t.hoat_dong;
  insert into public.nhat_ky_xuat_file (nguoi, loai, chi_nhanh_id, so_dong) values (auth.uid(), 'kho', v_cn, jsonb_array_length(v_hang));
  return jsonb_build_object('chi_nhanh', (select ten from public.chi_nhanh where id = v_cn), 'luc', now(), 'hang', v_hang);
end $$;

-- Khách – xe và công nợ
create or replace function public.xuat_du_lieu_khach() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_xe jsonb; v_no jsonb; v_hn date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  perform app.yeu_cau('giam_doc');
  -- Công nợ: hồ sơ đã giao xe (không tính hồ sơ chuyển từ Excel, hồ sơ hủy) còn nợ khách hoặc nợ bảo hiểm
  drop table if exists _no;
  create temp table _no on commit drop as
  select v.id, v.ma, v.chi_nhanh_id, v.xe_id, v.ngay_vao, (v.giao_luc at time zone 'Asia/Ho_Chi_Minh')::date as ngay_giao,
    v.bien_so_hien_thi, v.ten_khach, v.dien_thoai, v.hang_bh, v.nguon_tt, v.trang_thai,
    v.phai_thu_khach, v.da_thu_khach, v.con_no_khach, v.phai_thu_bh, v.da_thu_bh, v.con_no_bh
  from public.v_ho_so v
  where app.duoc_xem_chi_nhanh(v.chi_nhanh_id) and not v.tu_excel and v.trang_thai in ('da_giao','da_gui_hs','dong')
    and (round(v.con_no_khach) <> 0 or round(v.con_no_bh) <> 0);

  select coalesce(jsonb_agg(jsonb_build_object(
      'ma', n.ma, 'chi_nhanh', n.chi_nhanh_id, 'ngay_vao', n.ngay_vao, 'ngay_giao', n.ngay_giao,
      'so_ngay', v_hn - coalesce(n.ngay_giao, n.ngay_vao),
      'bien_so', n.bien_so_hien_thi, 'khach', n.ten_khach, 'dien_thoai', n.dien_thoai,
      'hang_bh', case when n.nguon_tt = 'khach' then null else n.hang_bh end,
      'phai_thu_khach', n.phai_thu_khach, 'da_thu_khach', n.da_thu_khach, 'con_no_khach', n.con_no_khach,
      'phai_thu_bh', n.phai_thu_bh, 'da_thu_bh', n.da_thu_bh, 'con_no_bh', n.con_no_bh)
      order by coalesce(n.ngay_giao, n.ngay_vao), n.ma), '[]'::jsonb)
    into v_no from _no n;

  select coalesce(jsonb_agg(jsonb_build_object(
      'bien_so', public.bien_so_hien_thi(x.bien_so), 'khach', k.ten, 'dien_thoai', k.dien_thoai,
      'xe', nullif(concat_ws(' ', hx.ten, dx.ten), ''), 'mau', x.mau, 'hang_bh', bh.ten,
      'han_than_vo', x.han_bh_than_vo, 'han_tnds', x.han_bao_hiem,
      'so_lan_vao', coalesce(hs.so_lan, 0), 'lan_vao_cuoi', hs.lan_cuoi,
      'con_no_khach', coalesce(no.khach, 0), 'con_no_bh', coalesce(no.bh, 0))
      order by hs.lan_cuoi desc nulls last, x.bien_so), '[]'::jsonb)
    into v_xe
  from public.xe x
  left join public.khach_hang k on k.id = x.khach_hang_id
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.hang_xe hx on hx.id = dx.hang_xe_id
  left join lateral (select count(*) as so_lan, max(h.ngay_vao) as lan_cuoi from public.ho_so h
                     where h.xe_id = x.id and h.trang_thai <> 'huy') hs on true
  left join lateral (select sum(n.con_no_khach) as khach, sum(n.con_no_bh) as bh from _no n where n.xe_id = x.id) no on true
  -- Đơn vị bảo hiểm: hãng BH của lần vào xưởng gần nhất có bảo hiểm
  left join lateral (select b.ten from public.ho_so h join public.hang_bao_hiem b on b.id = h.hang_bh_id
                     where h.xe_id = x.id and h.trang_thai <> 'huy' and h.nguon_tt <> 'khach'
                     order by h.ngay_vao desc, h.id desc limit 1) bh on true
  where exists (select 1 from public.ho_so h where h.xe_id = x.id and app.duoc_xem_chi_nhanh(h.chi_nhanh_id))
     or not exists (select 1 from public.ho_so h where h.xe_id = x.id);

  insert into public.nhat_ky_xuat_file (nguoi, loai, chi_nhanh_id, so_dong)
  values (auth.uid(), 'khach_hang', app.chi_nhanh(), jsonb_array_length(v_xe) + jsonb_array_length(v_no));
  return jsonb_build_object('luc', now(), 'xe', v_xe, 'cong_no', v_no);
end $$;

revoke execute on function public.xuat_du_lieu_kho(text) from public, anon;
revoke execute on function public.xuat_du_lieu_khach() from public, anon;
grant execute on function public.xuat_du_lieu_kho(text) to authenticated;
grant execute on function public.xuat_du_lieu_khach() to authenticated;
