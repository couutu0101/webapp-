-- =====================================================================
-- 014 (13/10/2026): DATA KHÁCH HÀNG – xuất 1 trang, nạp ngược lại (xóa hết rồi nạp)
--   - File "Data khách hàng": mỗi lần vào xưởng 1 dòng (thông tin xe – khách lặp lại ở từng dòng);
--     xe chưa vào xưởng lần nào: 1 dòng, các cột lần vào để trống.
--   - Nạp lại (Claude nạp từ file anh gửi): XÓA HẾT khách hàng, xe, hồ sơ rồi nạp lại từ file.
--     Mỗi dòng thành một hồ sơ "Chuyển từ Excel" (không tính doanh thu).
--     Cột "Khách còn nợ" / "BH còn nợ" > 0 → thành NỢ CŨ: hồ sơ ở trạng thái Đã giao / Đã gửi HS BH,
--     hiện trong công nợ, kế toán lập phiếu thu trừ dần; thu đủ thì hồ sơ tự đóng.
--   - Bản thử dùng chung CSDL: chỉ thêm cột/bảng/hàm; hàm xuất trả thêm khóa 'data'.
-- =====================================================================

alter table public.ho_so add column if not exists gia_tri_cu numeric(14,0);
alter table public.ho_so add column if not exists ghi_chu_cu text;
comment on column public.ho_so.gia_tri_cu is 'Giá trị sửa chữa ghi trong file Excel cũ (hồ sơ chuyển từ Excel, chỉ để xem)';
comment on column public.ho_so.ghi_chu_cu is 'Ghi chú ghi trong file Excel cũ';

-- ---------------------------------------------------------------------
-- Xuất: thêm 'data' = mỗi lần vào xưởng 1 dòng; công nợ tính cả nợ cũ chuyển từ Excel
-- ---------------------------------------------------------------------
create or replace function public.xuat_du_lieu_khach() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_xe jsonb; v_no jsonb; v_data jsonb; v_hn date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  perform app.yeu_cau('giam_doc');
  drop table if exists _hs;
  create temp table _hs on commit drop as
  select v.id, v.ma, v.chi_nhanh_id, v.xe_id, (v.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date as ngay_vao,
    (v.giao_luc at time zone 'Asia/Ho_Chi_Minh')::date as ngay_giao, v.trang_thai, v.tu_excel,
    v.bien_so_hien_thi, v.ten_khach, v.dien_thoai, v.nguon_tt,
    case when v.nguon_tt = 'khach' then null else v.hang_bh end as hang_bh, v.gdv,
    v.tinh_trang_xe, v.tu_van, v.cam_nhan_khach, v.cham_soc_ket_qua,
    case when v.tu_excel then h.gia_tri_cu else v.bh_duyet + v.khach_duyet end as gia_tri, h.ghi_chu_cu,
    v.phai_thu_khach, v.da_thu_khach, v.con_no_khach, v.phai_thu_bh, v.da_thu_bh, v.con_no_bh
  from public.v_ho_so v join public.ho_so h on h.id = v.id
  where app.duoc_xem_chi_nhanh(v.chi_nhanh_id) and v.trang_thai <> 'huy';

  -- Công nợ: xe đã giao (kể cả nợ cũ chuyển từ Excel) còn nợ khách hoặc nợ bảo hiểm
  select coalesce(jsonb_agg(jsonb_build_object(
      'ma', n.ma, 'chi_nhanh', n.chi_nhanh_id, 'ngay_vao', n.ngay_vao, 'ngay_giao', n.ngay_giao,
      'so_ngay', v_hn - coalesce(n.ngay_giao, n.ngay_vao),
      'bien_so', n.bien_so_hien_thi, 'khach', n.ten_khach, 'dien_thoai', n.dien_thoai, 'hang_bh', n.hang_bh,
      'phai_thu_khach', n.phai_thu_khach, 'da_thu_khach', n.da_thu_khach, 'con_no_khach', n.con_no_khach,
      'phai_thu_bh', n.phai_thu_bh, 'da_thu_bh', n.da_thu_bh, 'con_no_bh', n.con_no_bh)
      order by coalesce(n.ngay_giao, n.ngay_vao), n.ma), '[]'::jsonb)
    into v_no
  from _hs n
  where n.trang_thai in ('da_giao','da_gui_hs','dong') and (round(n.con_no_khach) <> 0 or round(n.con_no_bh) <> 0);

  -- Data khách hàng: mỗi lần vào xưởng 1 dòng + xe chưa có lần vào nào
  select coalesce(jsonb_agg(d order by d->>'bien_so_gon', d->>'ngay_vao' nulls first, d->>'ma'), '[]'::jsonb) into v_data
  from (
    select jsonb_build_object(
      'bien_so_gon', x.bien_so, 'bien_so', public.bien_so_hien_thi(x.bien_so), 'khach', k.ten, 'dien_thoai', k.dien_thoai,
      'hang_xe', hx.ten, 'dong_xe', dx.ten, 'mau', x.mau, 'han_than_vo', x.han_bh_than_vo, 'han_tnds', x.han_bao_hiem,
      'ma', n.ma, 'ngay_vao', n.ngay_vao, 'ngay_giao', n.ngay_giao, 'trang_thai', n.trang_thai, 'tu_excel', n.tu_excel,
      'nguon', n.nguon_tt, 'hang_bh', n.hang_bh, 'gdv', n.gdv,
      -- câu giữ chỗ của dữ liệu chuyển từ Excel thì để trống
      'tinh_trang', case when n.tinh_trang_xe ~ '^\d{2}/\d{2}/\d{4}: \((Chuyển từ Excel|Excel không ghi tình trạng)\)$' then null else n.tinh_trang_xe end,
      'tu_van', case when n.tu_van ~ '^\d{2}/\d{2}/\d{4}: \((Chuyển từ Excel|Excel không ghi tình trạng)\)$' then null else n.tu_van end,
      'phan_hoi', nullif(concat_ws(' | ', nullif(n.cam_nhan_khach, ''), nullif(n.cham_soc_ket_qua, '')), ''),
      'gia_tri', n.gia_tri, 'con_no_khach', n.con_no_khach, 'con_no_bh', n.con_no_bh, 'ghi_chu', n.ghi_chu_cu) as d
    from public.xe x
    left join public.khach_hang k on k.id = x.khach_hang_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    left join _hs n on n.xe_id = x.id
    where n.id is not null or not exists (select 1 from public.ho_so h where h.xe_id = x.id)
  ) t;

  -- Khách – xe (giữ cho giao diện cũ)
  select coalesce(jsonb_agg(jsonb_build_object(
      'bien_so', public.bien_so_hien_thi(x.bien_so), 'khach', k.ten, 'dien_thoai', k.dien_thoai,
      'xe', nullif(concat_ws(' ', hx.ten, dx.ten), ''), 'mau', x.mau, 'hang_bh', bh.hang_bh,
      'han_than_vo', x.han_bh_than_vo, 'han_tnds', x.han_bao_hiem,
      'so_lan_vao', coalesce(hs.so_lan, 0), 'lan_vao_cuoi', hs.lan_cuoi,
      'con_no_khach', coalesce(hs.khach, 0), 'con_no_bh', coalesce(hs.bh, 0))
      order by hs.lan_cuoi desc nulls last, x.bien_so), '[]'::jsonb)
    into v_xe
  from public.xe x
  left join public.khach_hang k on k.id = x.khach_hang_id
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.hang_xe hx on hx.id = dx.hang_xe_id
  left join lateral (select count(*) as so_lan, max(n.ngay_vao) as lan_cuoi,
                       sum(n.con_no_khach) filter (where n.trang_thai in ('da_giao','da_gui_hs','dong')) as khach,
                       sum(n.con_no_bh) filter (where n.trang_thai in ('da_giao','da_gui_hs','dong')) as bh
                     from _hs n where n.xe_id = x.id) hs on true
  left join lateral (select n.hang_bh from _hs n where n.xe_id = x.id and n.hang_bh is not null
                     order by n.ngay_vao desc, n.id desc limit 1) bh on true
  where hs.so_lan > 0 or not exists (select 1 from public.ho_so h where h.xe_id = x.id);

  insert into public.nhat_ky_xuat_file (nguoi, loai, chi_nhanh_id, so_dong)
  values (auth.uid(), 'khach_hang', app.chi_nhanh(), jsonb_array_length(v_data));
  return jsonb_build_object('luc', now(), 'data', v_data, 'xe', v_xe, 'cong_no', v_no);
end $$;
revoke execute on function public.xuat_du_lieu_khach() from public, anon;
grant execute on function public.xuat_du_lieu_khach() to authenticated;

-- ---------------------------------------------------------------------
-- Nạp: dữ liệu dán vào app.nap_tam theo từng phần (mỗi phần một mảng dòng), rồi gọi app.nap_data_khach()
-- ---------------------------------------------------------------------
create table if not exists app.nap_tam (
  id      bigint generated always as identity primary key,
  loai    text not null default 'khach_hang',
  phan    int not null,
  dong    jsonb not null,
  luc     timestamptz not null default now()
);
revoke all on app.nap_tam from public, anon, authenticated;

-- Dòng (jsonb): bien_so, khach, dien_thoai, hang_xe, dong_xe, mau, han_than_vo, han_tnds,
--   ma, ngay_vao, ngay_giao, nguon ('bao_hiem'|'khach'), hang_bh, gdv, tinh_trang, tu_van, phan_hoi,
--   gia_tri, con_no_khach, con_no_bh, ghi_chu
create or replace function app.nap_data_khach(p_xoa_het boolean default true, p_chi_nhanh text default 'TK') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb; v_hang bigint; v_dong bigint; v_kh bigint; v_xe bigint; v_bh bigint; v_gdv bigint; v_id bigint;
  v_bs text; v_dt text; v_ngay date; v_giao date; v_ma text; v_n int; v_tt text; v_nk numeric; v_nb numeric;
  so_xe int := 0; so_kh int := 0; so_hs int := 0; so_no int := 0; tong_nk numeric := 0; tong_nb numeric := 0;
  v_canh jsonb := '[]'::jsonb; v_lien_quan text;
begin
  if not exists (select 1 from app.nap_tam where loai = 'khach_hang') then raise exception 'Chưa có dữ liệu trong app.nap_tam.'; end if;

  if p_xoa_het then
    -- Không xóa khi đã có chứng từ thật gắn với hồ sơ (phiếu thu chi, đề nghị chi, kho)
    select concat_ws(', ',
      nullif((select count(*) from public.phan_bo)::text, '0') || ' dòng phân bổ phiếu thu',
      nullif((select count(*) from public.de_nghi_chi where ho_so_id is not null)::text, '0') || ' đề nghị chi',
      nullif((select count(*) from public.de_xuat_vat_tu)::text, '0') || ' đề xuất vật tư',
      nullif((select count(*) from public.phieu_xuat where ho_so_id is not null)::text, '0') || ' phiếu xuất cho xe',
      nullif((select count(*) from public.phieu_nhap where ho_so_id is not null)::text, '0') || ' phiếu nhập cho xe',
      nullif((select count(*) from public.de_nghi_mua where ho_so_id is not null)::text, '0') || ' đề nghị mua cho xe')
    into v_lien_quan;
    if v_lien_quan <> '' then
      raise exception 'Chưa xóa được: còn % gắn với hồ sơ. Xóa các chứng từ thử đó trước.', v_lien_quan;
    end if;
    update public.ho_so set ho_so_goc_id = null where ho_so_goc_id is not null;
    delete from public.ho_so;
    delete from public.xe;
    delete from public.khach_hang;
  end if;

  for d in select x from app.nap_tam t, jsonb_array_elements(t.dong) x where t.loai = 'khach_hang'
           order by x->>'bien_so', x->>'ngay_vao' nulls first loop
    v_bs := upper(regexp_replace(coalesce(d->>'bien_so', ''), '[^0-9A-Za-z]', '', 'g'));
    if v_bs = '' then v_canh := v_canh || to_jsonb('Bỏ dòng không có biển số: ' || coalesce(d->>'khach', '')); continue; end if;
    v_dt := regexp_replace(coalesce(d->>'dien_thoai', ''), '[^0-9]', '', 'g');
    if v_dt !~ '^0[0-9]{9}$' then v_dt := null; end if;

    -- Hãng xe, dòng xe
    v_dong := null;
    if nullif(trim(d->>'hang_xe'), '') is not null then
      insert into public.hang_xe (ten) values (trim(d->>'hang_xe')) on conflict (ten) do nothing;
      select id into v_hang from public.hang_xe where ten = trim(d->>'hang_xe');
      if nullif(trim(d->>'dong_xe'), '') is not null then
        insert into public.dong_xe (hang_xe_id, ten) values (v_hang, trim(d->>'dong_xe')) on conflict (hang_xe_id, ten) do nothing;
        select id into v_dong from public.dong_xe where hang_xe_id = v_hang and ten = trim(d->>'dong_xe');
      end if;
    end if;

    -- Khách: theo số điện thoại; không có số thì theo xe
    v_kh := null;
    if v_dt is not null then select id into v_kh from public.khach_hang where dien_thoai = v_dt; end if;
    select id into v_xe from public.xe where bien_so = v_bs;
    if v_kh is null and v_xe is not null then select khach_hang_id into v_kh from public.xe where id = v_xe; end if;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(d->>'khach'), ''), 'Chưa có tên'), v_dt) returning id into v_kh;
      so_kh := so_kh + 1;
    elsif nullif(trim(d->>'khach'), '') is not null then
      update public.khach_hang set ten = trim(d->>'khach'), dien_thoai = coalesce(dien_thoai, v_dt) where id = v_kh;
    end if;

    -- Xe: dòng sau (lần vào mới hơn) ghi đè thông tin xe
    if v_xe is null then
      insert into public.xe (bien_so, dong_xe_id, mau, khach_hang_id, han_bao_hiem, han_bh_than_vo)
      values (v_bs, v_dong, nullif(trim(d->>'mau'), ''), v_kh, (d->>'han_tnds')::date, (d->>'han_than_vo')::date) returning id into v_xe;
      so_xe := so_xe + 1;
    else
      update public.xe set dong_xe_id = coalesce(v_dong, dong_xe_id), mau = coalesce(nullif(trim(d->>'mau'), ''), mau), khach_hang_id = v_kh,
        han_bao_hiem = coalesce((d->>'han_tnds')::date, han_bao_hiem), han_bh_than_vo = coalesce((d->>'han_than_vo')::date, han_bh_than_vo)
      where id = v_xe;
    end if;

    -- Lần vào xưởng → hồ sơ "Chuyển từ Excel"
    v_ngay := (d->>'ngay_vao')::date;
    continue when v_ngay is null;
    v_giao := coalesce((d->>'ngay_giao')::date, v_ngay);
    v_bh := null;
    if coalesce(d->>'nguon', 'bao_hiem') <> 'khach' and nullif(trim(d->>'hang_bh'), '') is not null then
      select id into v_bh from public.hang_bao_hiem where lower(ten) = lower(trim(d->>'hang_bh'));
      if v_bh is null then v_canh := v_canh || to_jsonb('Hãng BH "' || trim(d->>'hang_bh') || '" chưa có trong danh mục (xe ' || v_bs || ') – để trống'); end if;
    end if;
    v_gdv := null;
    if nullif(trim(d->>'gdv'), '') is not null then
      select g.id into v_gdv from public.giam_dinh_vien g where lower(g.ten) = lower(trim(d->>'gdv')) and not g.la_cho_them
        order by (g.hang_id is not distinct from v_bh) desc, g.hang_id nulls last limit 1;
    end if;
    v_ma := nullif(trim(d->>'ma'), '');
    if v_ma is null or exists (select 1 from public.ho_so where ma = v_ma) then
      v_ma := p_chi_nhanh || '-' || to_char(v_ngay, 'YYMM') || '-' || v_bs; v_n := 1;
      while exists (select 1 from public.ho_so where ma = v_ma) loop
        v_n := v_n + 1; v_ma := p_chi_nhanh || '-' || to_char(v_ngay, 'YYMM') || '-' || v_bs || '-' || v_n;
      end loop;
    end if;
    v_nk := greatest(coalesce((d->>'con_no_khach')::numeric, 0), 0);
    v_nb := greatest(coalesce((d->>'con_no_bh')::numeric, 0), 0);
    v_tt := case when v_nb > 0 then 'da_gui_hs' when v_nk > 0 then 'da_giao' else 'dong' end;
    insert into public.ho_so (ma, chi_nhanh_id, loai, xe_id, khach_hang_id, ngay_vao, nguon_tt, hang_bh_id, gdv_id, gdv_ten_tam,
        han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, trang_thai, giao_luc, gui_hs_ngay, cham_soc_luc, cam_nhan_khach,
        gia_tri_cu, ghi_chu_cu, tu_excel)
    values (v_ma, p_chi_nhanh, 'sua_chua', v_xe, v_kh, (v_ngay + time '08:00') at time zone 'Asia/Ho_Chi_Minh',
        case when d->>'nguon' = 'khach' then 'khach' else 'bao_hiem' end, v_bh, v_gdv,
        case when v_gdv is null then nullif(trim(d->>'gdv'), '') end,
        (d->>'han_tnds')::date, (d->>'han_than_vo')::date,
        coalesce(nullif(trim(d->>'tinh_trang'), ''), to_char(v_ngay, 'DD/MM/YYYY') || ': (Excel không ghi tình trạng)'),
        coalesce(nullif(trim(d->>'tu_van'), ''), to_char(v_ngay, 'DD/MM/YYYY') || ': (Chuyển từ Excel)'),
        v_tt, (v_giao + time '17:00') at time zone 'Asia/Ho_Chi_Minh', case when v_nb > 0 then v_giao end,
        (v_giao + time '17:00') at time zone 'Asia/Ho_Chi_Minh', nullif(trim(d->>'phan_hoi'), ''),
        nullif((d->>'gia_tri')::numeric, 0), nullif(trim(d->>'ghi_chu'), ''), true)
    returning id into v_id;
    -- Nợ cũ: một dòng hạng mục cho phần khách nợ, một dòng cho phần bảo hiểm nợ (VAT 0 – số đã gồm VAT)
    if v_nk > 0 then
      insert into public.hang_muc (ho_so_id, ten, nhom, nguoi_tra, gia_bao, gia_duyet, xuat_hd, ty_le_vat, ngay_duyet, trang_thai)
      values (v_id, 'Nợ cũ chuyển từ Excel', 'dong_son', 'khach', v_nk, v_nk, false, 0, v_giao, 'xong');
      tong_nk := tong_nk + v_nk;
    end if;
    if v_nb > 0 then
      insert into public.hang_muc (ho_so_id, ten, nhom, nguoi_tra, gia_bao, gia_duyet, xuat_hd, ty_le_vat, ngay_duyet, trang_thai)
      values (v_id, 'Nợ cũ chuyển từ Excel', 'dong_son', 'bao_hiem', v_nb, v_nb, true, 0, v_giao, 'xong');
      tong_nb := tong_nb + v_nb;
    end if;
    if v_nk > 0 or v_nb > 0 then so_no := so_no + 1; end if;
    insert into public.ho_so_nhat_ky (ho_so_id, tu_trang_thai, sang_trang_thai, ghi_chu)
    values (v_id, null, v_tt, 'Nạp từ file Data khách hàng' || case when v_nk + v_nb > 0
      then ' – nợ cũ: khách ' || app.vnd(v_nk) || ' đ, BH ' || app.vnd(v_nb) || ' đ' else '' end);
    so_hs := so_hs + 1;
  end loop;

  delete from app.nap_tam where loai = 'khach_hang';
  return jsonb_build_object('xe_moi', so_xe, 'khach_moi', so_kh, 'ho_so', so_hs, 'ho_so_con_no', so_no,
    'tong_no_khach', tong_nk, 'tong_no_bh', tong_nb, 'canh_bao', v_canh,
    'tong_xe', (select count(*) from public.xe), 'tong_khach', (select count(*) from public.khach_hang));
end $$;
revoke execute on function app.nap_data_khach(boolean, text) from public, anon, authenticated;
