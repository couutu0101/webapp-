-- =====================================================================
-- 012 (13/10/2026): KHO – danh mục hàng, nhập kho, đề xuất vật tư → xuất cho xe,
--                   đề nghị mua, khớp hóa đơn, công nợ nhà cung cấp, kiểm kê.
--   Theo đặc tả đã chốt 11/10/2026 (mục "Phiếu đề xuất vật tư và kho", "Mua hàng và công nợ NCC").
--   - Tồn theo ĐƠN VỊ XUẤT; mỗi mã có đơn vị nhập + hệ số quy đổi (sơn nhập can 4L, xuất lít).
--   - Giá vốn xuất: NHẬP TRƯỚC XUẤT TRƯỚC (theo từng lô nhập), giá đã gồm VAT.
--   - Không xuất cho xe chưa có lệnh sửa chữa (hồ sơ phải ở "Đang sửa" hoặc "Chờ KCS").
--   - Hết hàng → chuyển mua (đề nghị mua) → hồ sơ hiện "Chờ phụ tùng" đến khi hàng về.
--   - Đề nghị mua: giám đốc / quản lý chung duyệt, không tự duyệt; từ 5 triệu phải đủ 3 báo giá.
--   - Phiếu nhập: kho nhập, tồn tăng ngay; kế toán khớp hóa đơn mới ghi công nợ NCC; lệch → treo.
--   - Kiểm kê: chênh lệch trên 5% giá trị phải ghi biên bản; chốt thì tự điều chỉnh tồn.
--   Tương thích ngược: chỉ thêm bảng, hàm, bảng xem mới.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Bảng
-- ---------------------------------------------------------------------
create table if not exists public.hang_kho (
  id              bigint generated always as identity primary key,
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  ma              text not null,
  ten             text not null,
  nhom            text not null default 'Phụ tùng',
  dvt             text not null,                                  -- đơn vị xuất = đơn vị tồn
  dvt_nhap        text,                                           -- trống = như dvt
  he_so           numeric(12,4) not null default 1 check (he_so > 0),  -- 1 đơn vị nhập = he_so đơn vị xuất
  ton_toi_thieu   numeric(14,3) not null default 0 check (ton_toi_thieu >= 0),
  nha_cung_cap_id bigint references public.nha_cung_cap(id),
  ghi_chu         text,
  hoat_dong       boolean not null default true,
  tao_luc         timestamptz not null default now(),
  unique (chi_nhanh_id, ma)
);

create table if not exists public.de_nghi_mua (
  id              bigint generated always as identity primary key,
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  ma              text not null unique,
  ngay            date not null default current_date,
  nha_cung_cap_id bigint not null references public.nha_cung_cap(id),
  ho_so_id        bigint references public.ho_so(id),
  ghi_chu         text,
  tong_tien       numeric(14,0) not null default 0,              -- sau VAT
  trang_thai      text not null default 'cho_duyet' check (trang_thai in ('cho_duyet','da_duyet','tu_choi','da_nhap','huy')),
  nguoi_lap       uuid not null,
  tao_luc         timestamptz not null default now(),
  duyet_boi       uuid,
  duyet_luc       timestamptz,
  ly_do_tu_choi   text
);

create table if not exists public.de_xuat_vat_tu (
  id              bigint generated always as identity primary key,
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  ma              text not null unique,
  ho_so_id        bigint not null references public.ho_so(id),
  to_id           text references public.to_thuc_hien(id),
  ghi_chu         text,
  trang_thai      text not null default 'cho_xuat' check (trang_thai in ('cho_xuat','da_xuat','huy')),
  nguoi_lap       uuid not null,
  tao_luc         timestamptz not null default now()
);

create table if not exists public.de_xuat_dong (
  id              bigint generated always as identity primary key,
  de_xuat_id      bigint not null references public.de_xuat_vat_tu(id) on delete cascade,
  hang_id         bigint not null references public.hang_kho(id),
  so_luong        numeric(14,3) not null check (so_luong > 0),   -- theo đơn vị xuất
  da_xuat         numeric(14,3) not null default 0 check (da_xuat >= 0),
  cho_mua         boolean not null default false                 -- đã chuyển mua, chờ hàng về
);

create table if not exists public.de_nghi_mua_dong (
  id              bigint generated always as identity primary key,
  de_nghi_id      bigint not null references public.de_nghi_mua(id) on delete cascade,
  hang_id         bigint not null references public.hang_kho(id),
  so_luong        numeric(14,3) not null check (so_luong > 0),   -- theo đơn vị nhập
  don_gia         numeric(14,2) not null check (don_gia >= 0),   -- chưa VAT, theo đơn vị nhập
  ty_le_vat       numeric(5,4) not null default 0.08 check (ty_le_vat >= 0 and ty_le_vat < 1),
  de_xuat_dong_id bigint references public.de_xuat_dong(id)
);

create table if not exists public.phieu_nhap (
  id              bigint generated always as identity primary key,
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  ma              text not null unique,
  ngay            date not null default current_date,
  nha_cung_cap_id bigint not null references public.nha_cung_cap(id),
  so_hoa_don      text,
  ho_so_id        bigint references public.ho_so(id),            -- mua riêng cho xe
  de_nghi_mua_id  bigint references public.de_nghi_mua(id),
  tong_tien       numeric(14,0) not null default 0,              -- sau VAT
  tien_vat        numeric(14,0) not null default 0,
  trang_thai      text not null default 'cho_khop' check (trang_thai in ('cho_khop','da_khop','treo','huy')),
  ghi_chu         text,
  ly_do_treo      text,
  tao_boi         uuid,
  tao_luc         timestamptz not null default now(),
  khop_boi        uuid,
  khop_luc        timestamptz
);

create table if not exists public.phieu_nhap_dong (
  id              bigint generated always as identity primary key,
  phieu_id        bigint not null references public.phieu_nhap(id) on delete cascade,
  hang_id         bigint not null references public.hang_kho(id),
  so_luong        numeric(14,3) not null check (so_luong > 0),   -- theo đơn vị nhập
  don_gia         numeric(14,2) not null check (don_gia >= 0),   -- chưa VAT, theo đơn vị nhập
  ty_le_vat       numeric(5,4) not null default 0.08 check (ty_le_vat >= 0 and ty_le_vat < 1),
  thanh_tien      numeric(14,0) not null                         -- sau VAT
);

create table if not exists public.kiem_ke (
  id              bigint generated always as identity primary key,
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  ma              text not null unique,
  ngay            date not null default current_date,
  pham_vi         text not null check (pham_vi in ('son_nham','toan_kho','chon')),
  trang_thai      text not null default 'dang_dem' check (trang_thai in ('dang_dem','da_chot','huy')),
  gia_tri_so_sach numeric(14,0),
  gia_tri_chenh   numeric(14,0),
  bien_ban        text,
  tao_boi         uuid,
  tao_luc         timestamptz not null default now(),
  chot_boi        uuid,
  chot_luc        timestamptz
);

create table if not exists public.kiem_ke_dong (
  id              bigint generated always as identity primary key,
  kiem_ke_id      bigint not null references public.kiem_ke(id) on delete cascade,
  hang_id         bigint not null references public.hang_kho(id),
  ton_so_sach     numeric(14,3),                                 -- ghi lúc chốt
  ton_thuc_te     numeric(14,3) check (ton_thuc_te >= 0),
  don_gia_von     numeric(16,4),
  unique (kiem_ke_id, hang_id)
);

-- Lô nhập (để tính giá vốn nhập trước xuất trước)
create table if not exists public.lo_kho (
  id                  bigint generated always as identity primary key,
  chi_nhanh_id        text not null references public.chi_nhanh(id),
  hang_id             bigint not null references public.hang_kho(id),
  ngay                date not null,
  phieu_nhap_dong_id  bigint references public.phieu_nhap_dong(id) on delete cascade,
  kiem_ke_id          bigint references public.kiem_ke(id),
  so_luong            numeric(14,3) not null check (so_luong > 0),     -- theo đơn vị xuất
  con_lai             numeric(14,3) not null check (con_lai >= 0),
  don_gia_von         numeric(16,4) not null check (don_gia_von >= 0), -- theo đơn vị xuất, đã gồm VAT
  tao_luc             timestamptz not null default now()
);
create index if not exists lo_kho_hang_idx on public.lo_kho (hang_id, ngay, id) where con_lai > 0;

create table if not exists public.phieu_xuat (
  id              bigint generated always as identity primary key,
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  ma              text not null unique,
  ngay            date not null default current_date,
  loai            text not null check (loai in ('cho_xe','dung_chung','kiem_ke')),
  ho_so_id        bigint references public.ho_so(id),
  de_xuat_id      bigint references public.de_xuat_vat_tu(id),
  kiem_ke_id      bigint references public.kiem_ke(id),
  ghi_chu         text,
  trang_thai      text not null default 'hieu_luc' check (trang_thai in ('hieu_luc','huy')),
  ly_do_huy       text,
  tao_boi         uuid,
  tao_luc         timestamptz not null default now(),
  constraint xuat_cho_xe_co_xe check (loai <> 'cho_xe' or ho_so_id is not null)
);

create table if not exists public.phieu_xuat_dong (
  id              bigint generated always as identity primary key,
  phieu_id        bigint not null references public.phieu_xuat(id) on delete cascade,
  hang_id         bigint not null references public.hang_kho(id),
  so_luong        numeric(14,3) not null check (so_luong > 0),
  gia_von         numeric(14,0) not null default 0,
  de_xuat_dong_id bigint references public.de_xuat_dong(id)
);

create table if not exists public.xuat_lo (
  id                  bigint generated always as identity primary key,
  phieu_xuat_dong_id  bigint not null references public.phieu_xuat_dong(id) on delete cascade,
  lo_id               bigint not null references public.lo_kho(id),
  so_luong            numeric(14,3) not null check (so_luong > 0),
  don_gia_von         numeric(16,4) not null
);

-- Ảnh hóa đơn, báo giá nhà cung cấp
create table if not exists public.kho_tep (
  id              bigint generated always as identity primary key,
  loai            text not null check (loai in ('phieu_nhap','de_nghi_mua')),
  doi_tuong_id    bigint not null,
  duong_dan       text not null,
  ten             text,
  tai_boi         uuid,
  tai_luc         timestamptz not null default now()
);
create index if not exists kho_tep_idx on public.kho_tep (loai, doi_tuong_id);

-- ---------------------------------------------------------------------
-- Quyền đọc: nhân viên văn phòng (gồm kho) đọc hết; trưởng nhóm đọc danh mục hàng, tồn, đề xuất
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['hang_kho','de_nghi_mua','de_nghi_mua_dong','de_xuat_vat_tu','de_xuat_dong',
    'phieu_nhap','phieu_nhap_dong','kiem_ke','kiem_ke_dong','lo_kho','phieu_xuat','phieu_xuat_dong','xuat_lo','kho_tep']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists doc on public.%I', t);
  end loop;
end $$;
create policy doc on public.hang_kho for select to authenticated
  using ((app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.lo_kho for select to authenticated
  using ((app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.de_xuat_vat_tu for select to authenticated
  using ((app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.de_xuat_dong for select to authenticated
  using (exists (select 1 from public.de_xuat_vat_tu d where d.id = de_xuat_id
                 and (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) and app.duoc_xem_chi_nhanh(d.chi_nhanh_id)));
do $$
declare t text;
begin
  foreach t in array array['de_nghi_mua','phieu_nhap','kiem_ke','phieu_xuat']
  loop
    execute format($f$create policy doc on public.%I for select to authenticated
      using (app.la_nhan_vien() and app.duoc_xem_chi_nhanh(chi_nhanh_id))$f$, t);
  end loop;
end $$;
create policy doc on public.de_nghi_mua_dong for select to authenticated
  using (exists (select 1 from public.de_nghi_mua d where d.id = de_nghi_id and app.la_nhan_vien() and app.duoc_xem_chi_nhanh(d.chi_nhanh_id)));
create policy doc on public.phieu_nhap_dong for select to authenticated
  using (exists (select 1 from public.phieu_nhap d where d.id = phieu_id and app.la_nhan_vien() and app.duoc_xem_chi_nhanh(d.chi_nhanh_id)));
create policy doc on public.kiem_ke_dong for select to authenticated
  using (exists (select 1 from public.kiem_ke d where d.id = kiem_ke_id and app.la_nhan_vien() and app.duoc_xem_chi_nhanh(d.chi_nhanh_id)));
create policy doc on public.phieu_xuat_dong for select to authenticated
  using (exists (select 1 from public.phieu_xuat d where d.id = phieu_id and app.la_nhan_vien() and app.duoc_xem_chi_nhanh(d.chi_nhanh_id)));
create policy doc on public.xuat_lo for select to authenticated using (app.la_nhan_vien());
create policy doc on public.kho_tep for select to authenticated using (app.la_nhan_vien());

-- ---------------------------------------------------------------------
-- Hàm dùng chung
-- ---------------------------------------------------------------------
-- Mã chứng từ: TK-PN2610-001 (PN nhập, PX xuất, DX đề xuất, DM đề nghị mua, KK kiểm kê)
create or replace function app.ma_chung_tu(p_loai text, p_cn text, p_ngay date, p_bang text) returns text
language plpgsql security definer set search_path = public as $$
declare v_goc text := p_cn || '-' || p_loai || to_char(p_ngay, 'YYMM') || '-'; v_n int; v_ma text; v_co boolean;
begin
  execute format('select count(*) + 1 from public.%I where ma like $1', p_bang) into v_n using v_goc || '%';
  loop
    v_ma := v_goc || lpad(v_n::text, 3, '0');
    execute format('select exists (select 1 from public.%I where ma = $1)', p_bang) into v_co using v_ma;
    exit when not v_co;
    v_n := v_n + 1;
  end loop;
  return v_ma;
end $$;

create or replace function app.hang_cua_chi_nhanh(p_hang bigint, p_cn text) returns public.hang_kho
language plpgsql stable security definer set search_path = public as $$
declare r public.hang_kho;
begin
  select * into r from public.hang_kho where id = p_hang;
  if not found then raise exception 'Không tìm thấy mã hàng.'; end if;
  if r.chi_nhanh_id <> p_cn then raise exception 'Mã hàng % không thuộc kho chi nhánh này.', r.ma; end if;
  return r;
end $$;

-- Tồn hiện tại của một mã (đơn vị xuất)
create or replace function app.ton_hang(p_hang bigint) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(con_lai), 0) from public.lo_kho where hang_id = p_hang
$$;

-- Xuất theo lô nhập trước xuất trước; trả về tiền giá vốn
create or replace function app.xuat_fifo(p_dong bigint, p_hang bigint, p_sl numeric) returns numeric
language plpgsql security definer set search_path = public as $$
declare l record; v_can numeric := p_sl; v_lay numeric; v_tien numeric := 0; v_ton numeric; h public.hang_kho;
begin
  v_ton := app.ton_hang(p_hang);
  if v_ton < p_sl then
    select * into h from public.hang_kho where id = p_hang;
    raise exception 'Không đủ hàng % (%): còn % %, cần % %.', h.ma, h.ten, trim_scale(v_ton), h.dvt, trim_scale(p_sl), h.dvt;
  end if;
  for l in select * from public.lo_kho where hang_id = p_hang and con_lai > 0 order by ngay, id for update loop
    exit when v_can <= 0;
    v_lay := least(l.con_lai, v_can);
    update public.lo_kho set con_lai = con_lai - v_lay where id = l.id;
    insert into public.xuat_lo (phieu_xuat_dong_id, lo_id, so_luong, don_gia_von) values (p_dong, l.id, v_lay, l.don_gia_von);
    v_tien := v_tien + v_lay * l.don_gia_von;
    v_can := v_can - v_lay;
  end loop;
  update public.phieu_xuat_dong set gia_von = round(v_tien) where id = p_dong;
  return round(v_tien);
end $$;

-- Hồ sơ đã có lệnh sửa chữa thì mới cấp phụ tùng
create or replace function app.yeu_cau_co_lenh(h public.ho_so) returns void
language plpgsql stable as $$
begin
  if h.trang_thai not in ('dang_sua','cho_kcs') then
    raise exception 'Xe % chưa có lệnh sửa chữa (hoặc đã qua KCS) – chưa cấp phụ tùng được.', h.ma;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Danh mục hàng kho
-- ---------------------------------------------------------------------
create or replace function public.luu_hang_kho(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint := (p->>'id')::bigint; v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ma text := upper(regexp_replace(trim(coalesce(p->>'ma','')), '\s+', '', 'g')); r public.hang_kho;
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  if v_id is not null then
    select * into r from public.hang_kho where id = v_id;
    if not found then raise exception 'Không tìm thấy mã hàng.'; end if;
    v_cn := r.chi_nhanh_id;
  end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  if v_ma = '' then raise exception 'Nhập mã hàng.'; end if;
  if nullif(trim(p->>'ten'),'') is null then raise exception 'Nhập tên hàng.'; end if;
  if nullif(trim(p->>'dvt'),'') is null then raise exception 'Nhập đơn vị tính (đơn vị xuất).'; end if;
  if coalesce((p->>'he_so')::numeric, 1) <= 0 then raise exception 'Hệ số quy đổi phải lớn hơn 0.'; end if;
  if exists (select 1 from public.hang_kho where chi_nhanh_id = v_cn and ma = v_ma and id is distinct from v_id) then
    raise exception 'Mã % đã có trong kho.', v_ma; end if;
  if v_id is null then
    insert into public.hang_kho (chi_nhanh_id, ma, ten, nhom, dvt, dvt_nhap, he_so, ton_toi_thieu, nha_cung_cap_id, ghi_chu)
    values (v_cn, v_ma, trim(p->>'ten'), coalesce(nullif(trim(p->>'nhom'),''), 'Phụ tùng'), trim(p->>'dvt'),
            nullif(trim(p->>'dvt_nhap'),''), coalesce((p->>'he_so')::numeric, 1), coalesce((p->>'ton_toi_thieu')::numeric, 0),
            (p->>'nha_cung_cap_id')::bigint, nullif(trim(p->>'ghi_chu'),''))
    returning id into v_id;
  else
    -- Đã có nhập/xuất thì không đổi đơn vị và hệ số (sẽ làm sai số tồn)
    if (r.dvt <> trim(p->>'dvt') or r.he_so <> coalesce((p->>'he_so')::numeric, 1))
       and exists (select 1 from public.lo_kho where hang_id = v_id) then
      raise exception 'Mã % đã có nhập xuất, không đổi đơn vị tính hay hệ số quy đổi được. Tạo mã mới nếu cần.', r.ma;
    end if;
    update public.hang_kho set ma = v_ma, ten = trim(p->>'ten'), nhom = coalesce(nullif(trim(p->>'nhom'),''), nhom),
      dvt = trim(p->>'dvt'), dvt_nhap = nullif(trim(p->>'dvt_nhap'),''), he_so = coalesce((p->>'he_so')::numeric, 1),
      ton_toi_thieu = coalesce((p->>'ton_toi_thieu')::numeric, 0), nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint,
      ghi_chu = nullif(trim(p->>'ghi_chu'),''), hoat_dong = coalesce((p->>'hoat_dong')::boolean, hoat_dong)
    where id = v_id;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Đề nghị mua hàng
-- dong: [{hang_id, so_luong (đơn vị nhập), don_gia (chưa VAT), ty_le_vat, de_xuat_dong_id?}]
-- ---------------------------------------------------------------------
create or replace function app.tao_de_nghi_mua(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  v_id bigint; v_ma text; d jsonb; h public.hang_kho; v_tong numeric := 0; v_vat numeric;
begin
  perform app.yeu_cau_chi_nhanh(v_cn);
  if (p->>'nha_cung_cap_id') is null then raise exception 'Chọn nhà cung cấp.'; end if;
  if jsonb_typeof(p->'dong') <> 'array' or jsonb_array_length(p->'dong') = 0 then raise exception 'Đề nghị mua phải có ít nhất một dòng.'; end if;
  if (p->>'ho_so_id') is not null then perform app.lay_ho_so((p->>'ho_so_id')::bigint); end if;
  v_ma := app.ma_chung_tu('DM', v_cn, v_ngay, 'de_nghi_mua');
  insert into public.de_nghi_mua (chi_nhanh_id, ma, ngay, nha_cung_cap_id, ho_so_id, ghi_chu, nguoi_lap)
  values (v_cn, v_ma, v_ngay, (p->>'nha_cung_cap_id')::bigint, (p->>'ho_so_id')::bigint, nullif(trim(p->>'ghi_chu'),''), auth.uid())
  returning id into v_id;
  for d in select * from jsonb_array_elements(p->'dong') loop
    h := app.hang_cua_chi_nhanh((d->>'hang_id')::bigint, v_cn);
    if coalesce((d->>'so_luong')::numeric, 0) <= 0 then raise exception 'Dòng % thiếu số lượng.', h.ma; end if;
    if (d->>'don_gia') is null or (d->>'don_gia')::numeric < 0 then raise exception 'Dòng % thiếu đơn giá.', h.ma; end if;
    v_vat := coalesce((d->>'ty_le_vat')::numeric, 0.08);
    insert into public.de_nghi_mua_dong (de_nghi_id, hang_id, so_luong, don_gia, ty_le_vat, de_xuat_dong_id)
    values (v_id, h.id, (d->>'so_luong')::numeric, (d->>'don_gia')::numeric, v_vat, (d->>'de_xuat_dong_id')::bigint);
    v_tong := v_tong + round((d->>'so_luong')::numeric * (d->>'don_gia')::numeric * (1 + v_vat));
  end loop;
  update public.de_nghi_mua set tong_tien = v_tong where id = v_id;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'tong_tien', v_tong,
    'can_3_bao_gia', v_tong >= app.cai_dat_so('nguong_3_bao_gia', 5000000));
end $$;

create or replace function public.lap_de_nghi_mua(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform app.yeu_cau('kho','cvdv','quan_ly','giam_doc');
  return app.tao_de_nghi_mua(p - 'chi_nhanh_id');
end $$;

create or replace function public.duyet_de_nghi_mua(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_mua; v_nguong numeric := app.cai_dat_so('nguong_3_bao_gia', 5000000); v_so_bg int;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_mua where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị mua.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị mua này đã được xử lý.'; end if;
  if r.nguoi_lap = auth.uid() then raise exception 'Không được tự duyệt đề nghị mua do mình lập.'; end if;
  if p_dong_y then
    select count(*) into v_so_bg from public.kho_tep where loai = 'de_nghi_mua' and doi_tuong_id = p_id;
    if r.tong_tien >= v_nguong and v_so_bg < 3 then
      raise exception 'Đơn từ % đ phải đính kèm 3 báo giá (đang có %).', app.vnd(v_nguong), v_so_bg;
    end if;
  elsif nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.';
  end if;
  update public.de_nghi_mua set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
  -- Từ chối: các dòng đề xuất đang chờ mua trở lại chờ xuất
  if not p_dong_y then
    update public.de_xuat_dong set cho_mua = false
    where id in (select de_xuat_dong_id from public.de_nghi_mua_dong where de_nghi_id = p_id and de_xuat_dong_id is not null);
  end if;
end $$;

create or replace function public.huy_de_nghi_mua(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_mua;
begin
  select * into r from public.de_nghi_mua where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị mua.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.nguoi_lap <> auth.uid() and not app.co_vai_tro('giam_doc','quan_ly') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if r.trang_thai not in ('cho_duyet','da_duyet') then raise exception 'Đề nghị mua đã nhập hàng hoặc đã bị từ chối.'; end if;
  update public.de_nghi_mua set trang_thai = 'huy' where id = p_id;
  update public.de_xuat_dong set cho_mua = false
  where id in (select de_xuat_dong_id from public.de_nghi_mua_dong where de_nghi_id = p_id and de_xuat_dong_id is not null);
end $$;

-- Đính kèm ảnh hóa đơn / báo giá NCC (tệp đã tải lên kho lưu trữ 'ho-so-xe')
create or replace function public.them_tep_kho(p_loai text, p_id bigint, p_duong_dan text, p_ten text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_cn text;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if p_loai = 'phieu_nhap' then select chi_nhanh_id into v_cn from public.phieu_nhap where id = p_id;
  elsif p_loai = 'de_nghi_mua' then select chi_nhanh_id into v_cn from public.de_nghi_mua where id = p_id;
  else raise exception 'Loại tệp không hợp lệ.'; end if;
  if v_cn is null then raise exception 'Không tìm thấy chứng từ.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  insert into public.kho_tep (loai, doi_tuong_id, duong_dan, ten, tai_boi) values (p_loai, p_id, p_duong_dan, p_ten, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Phiếu nhập kho
-- p: {ngay, nha_cung_cap_id, so_hoa_don, ho_so_id?, de_nghi_mua_id?, ghi_chu, xuat_cho_xe?,
--     dong: [{hang_id, so_luong (đơn vị nhập), don_gia (chưa VAT), ty_le_vat}]}
-- ---------------------------------------------------------------------
create or replace function public.lap_phieu_nhap(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := app.chi_nhanh(); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  v_id bigint; v_ma text; d jsonb; h public.hang_kho; v_dong bigint; v_sl numeric; v_vat numeric; v_tien numeric;
  v_tong numeric := 0; v_tong_vat numeric := 0; dm public.de_nghi_mua; hs public.ho_so; v_xuat jsonb := null;
  v_px bigint; v_px_ma text; v_pxd bigint; x record;
begin
  perform app.yeu_cau('kho','giam_doc');
  if v_cn is null then raise exception 'Tài khoản chưa gắn chi nhánh.'; end if;
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày nhập không được sau hôm nay.'; end if;
  if (p->>'nha_cung_cap_id') is null then raise exception 'Chọn nhà cung cấp.'; end if;
  if jsonb_typeof(p->'dong') <> 'array' or jsonb_array_length(p->'dong') = 0 then raise exception 'Phiếu nhập phải có ít nhất một dòng.'; end if;
  if (p->>'de_nghi_mua_id') is not null then
    select * into dm from public.de_nghi_mua where id = (p->>'de_nghi_mua_id')::bigint for update;
    if not found or dm.chi_nhanh_id <> v_cn then raise exception 'Không tìm thấy đề nghị mua.'; end if;
    if dm.trang_thai <> 'da_duyet' then raise exception 'Đề nghị mua % chưa được duyệt (hoặc đã nhập).', dm.ma; end if;
  end if;
  if (p->>'ho_so_id') is not null then
    hs := app.lay_ho_so((p->>'ho_so_id')::bigint);
    if coalesce((p->>'xuat_cho_xe')::boolean, false) then perform app.yeu_cau_co_lenh(hs); end if;
  end if;

  v_ma := app.ma_chung_tu('PN', v_cn, v_ngay, 'phieu_nhap');
  insert into public.phieu_nhap (chi_nhanh_id, ma, ngay, nha_cung_cap_id, so_hoa_don, ho_so_id, de_nghi_mua_id, ghi_chu, tao_boi)
  values (v_cn, v_ma, v_ngay, (p->>'nha_cung_cap_id')::bigint, nullif(trim(p->>'so_hoa_don'),''), (p->>'ho_so_id')::bigint,
          (p->>'de_nghi_mua_id')::bigint, nullif(trim(p->>'ghi_chu'),''), auth.uid())
  returning id into v_id;

  for d in select * from jsonb_array_elements(p->'dong') loop
    h := app.hang_cua_chi_nhanh((d->>'hang_id')::bigint, v_cn);
    v_sl := (d->>'so_luong')::numeric;
    if coalesce(v_sl, 0) <= 0 then raise exception 'Dòng % thiếu số lượng.', h.ma; end if;
    if (d->>'don_gia') is null or (d->>'don_gia')::numeric < 0 then raise exception 'Dòng % thiếu đơn giá.', h.ma; end if;
    v_vat := coalesce((d->>'ty_le_vat')::numeric, 0.08);
    v_tien := round(v_sl * (d->>'don_gia')::numeric * (1 + v_vat));
    insert into public.phieu_nhap_dong (phieu_id, hang_id, so_luong, don_gia, ty_le_vat, thanh_tien)
    values (v_id, h.id, v_sl, (d->>'don_gia')::numeric, v_vat, v_tien) returning id into v_dong;
    insert into public.lo_kho (chi_nhanh_id, hang_id, ngay, phieu_nhap_dong_id, so_luong, con_lai, don_gia_von)
    values (v_cn, h.id, v_ngay, v_dong, v_sl * h.he_so, v_sl * h.he_so, v_tien / (v_sl * h.he_so));
    v_tong := v_tong + v_tien;
    v_tong_vat := v_tong_vat + (v_tien - round(v_sl * (d->>'don_gia')::numeric));
  end loop;
  update public.phieu_nhap set tong_tien = v_tong, tien_vat = v_tong_vat where id = v_id;

  -- Hàng của đề nghị mua đã về: đề nghị chuyển "đã nhập", các dòng đề xuất đang chờ mua trở lại chờ xuất
  if dm.id is not null then
    update public.de_nghi_mua set trang_thai = 'da_nhap' where id = dm.id;
    update public.de_xuat_dong set cho_mua = false
    where id in (select de_xuat_dong_id from public.de_nghi_mua_dong where de_nghi_id = dm.id and de_xuat_dong_id is not null);
  end if;

  -- Phụ tùng mua riêng cho xe: nhập rồi xuất ngay cho xe đó
  if hs.id is not null and coalesce((p->>'xuat_cho_xe')::boolean, false) then
    v_px_ma := app.ma_chung_tu('PX', v_cn, v_ngay, 'phieu_xuat');
    insert into public.phieu_xuat (chi_nhanh_id, ma, ngay, loai, ho_so_id, ghi_chu, tao_boi)
    values (v_cn, v_px_ma, v_ngay, 'cho_xe', hs.id, 'Xuất ngay theo phiếu nhập ' || v_ma, auth.uid()) returning id into v_px;
    for x in select pd.hang_id, pd.so_luong * hk.he_so as sl from public.phieu_nhap_dong pd
             join public.hang_kho hk on hk.id = pd.hang_id where pd.phieu_id = v_id loop
      insert into public.phieu_xuat_dong (phieu_id, hang_id, so_luong) values (v_px, x.hang_id, x.sl) returning id into v_pxd;
      perform app.xuat_fifo(v_pxd, x.hang_id, x.sl);
    end loop;
    perform app.ghi_nhat_ky(hs.id, hs.trang_thai, hs.trang_thai, 'Nhập và xuất ngay phụ tùng cho xe: ' || v_ma || ' → ' || v_px_ma);
    v_xuat := jsonb_build_object('id', v_px, 'ma', v_px_ma);
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'tong_tien', v_tong, 'phieu_xuat', v_xuat);
end $$;

-- Kế toán khớp hóa đơn: khớp → ghi công nợ NCC; lệch → treo (ghi lý do)
create or replace function public.khop_phieu_nhap(p_id bigint, p_khop boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_nhap;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_nhap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu nhập.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai not in ('cho_khop','treo') then raise exception 'Phiếu nhập này đã khớp hoặc đã hủy.'; end if;
  if r.tao_boi = auth.uid() and not app.co_vai_tro('giam_doc') then raise exception 'Người lập phiếu không tự khớp hóa đơn.'; end if;
  if not p_khop and nullif(trim(p_ly_do),'') is null then raise exception 'Ghi chỗ lệch (số lượng, giá, thiếu hóa đơn…).'; end if;
  update public.phieu_nhap set trang_thai = case when p_khop then 'da_khop' else 'treo' end,
    ly_do_treo = case when p_khop then null else trim(p_ly_do) end,
    khop_boi = case when p_khop then auth.uid() end, khop_luc = case when p_khop then now() end
  where id = p_id;
end $$;

-- Hủy phiếu nhập (nhập nhầm): chỉ khi chưa khớp và hàng của phiếu chưa xuất
create or replace function public.huy_phieu_nhap(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_nhap;
begin
  perform app.yeu_cau('kho','giam_doc');
  select * into r from public.phieu_nhap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu nhập.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai not in ('cho_khop','treo') then raise exception 'Phiếu đã khớp hóa đơn hoặc đã hủy – không hủy được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  if exists (select 1 from public.lo_kho l join public.phieu_nhap_dong d on d.id = l.phieu_nhap_dong_id
             where d.phieu_id = p_id and l.con_lai < l.so_luong) then
    raise exception 'Hàng của phiếu này đã xuất một phần – hủy phiếu xuất trước.';
  end if;
  delete from public.lo_kho where phieu_nhap_dong_id in (select id from public.phieu_nhap_dong where phieu_id = p_id);
  update public.phieu_nhap set trang_thai = 'huy', ghi_chu = concat_ws(' · ', ghi_chu, 'Hủy: ' || trim(p_ly_do)) where id = p_id;
  if r.de_nghi_mua_id is not null then
    update public.de_nghi_mua set trang_thai = 'da_duyet' where id = r.de_nghi_mua_id and trang_thai = 'da_nhap';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Phiếu đề xuất vật tư (trưởng nhóm, CVDV, kho) – theo lệnh sửa chữa
-- p: {ho_so_id, to_id?, ghi_chu, dong: [{hang_id, so_luong (đơn vị xuất)}]}
-- ---------------------------------------------------------------------
create or replace function public.lap_de_xuat_vat_tu(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare hs public.ho_so; v_id bigint; v_ma text; d jsonb; h public.hang_kho; v_to text;
begin
  perform app.yeu_cau('truong_nhom','cvdv','kho','quan_ly','giam_doc');
  if (p->>'ho_so_id') is null then raise exception 'Chọn xe.'; end if;
  hs := app.lay_ho_so((p->>'ho_so_id')::bigint);
  perform app.yeu_cau_co_lenh(hs);
  if jsonb_typeof(p->'dong') <> 'array' or jsonb_array_length(p->'dong') = 0 then raise exception 'Phiếu đề xuất phải có ít nhất một dòng.'; end if;
  v_to := coalesce(nullif(p->>'to_id',''), case when app.co_vai_tro('truong_nhom') then (select to_id from public.nhan_vien where id = auth.uid()) end);
  v_ma := app.ma_chung_tu('DX', hs.chi_nhanh_id, current_date, 'de_xuat_vat_tu');
  insert into public.de_xuat_vat_tu (chi_nhanh_id, ma, ho_so_id, to_id, ghi_chu, nguoi_lap)
  values (hs.chi_nhanh_id, v_ma, hs.id, v_to, nullif(trim(p->>'ghi_chu'),''), auth.uid()) returning id into v_id;
  for d in select * from jsonb_array_elements(p->'dong') loop
    h := app.hang_cua_chi_nhanh((d->>'hang_id')::bigint, hs.chi_nhanh_id);
    if coalesce((d->>'so_luong')::numeric, 0) <= 0 then raise exception 'Dòng % thiếu số lượng.', h.ma; end if;
    insert into public.de_xuat_dong (de_xuat_id, hang_id, so_luong) values (v_id, h.id, (d->>'so_luong')::numeric);
  end loop;
  perform app.ghi_nhat_ky(hs.id, hs.trang_thai, hs.trang_thai, 'Đề xuất vật tư ' || v_ma);
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

create or replace function app.cap_nhat_de_xuat(p_id bigint) returns void
language sql security definer set search_path = public as $$
  update public.de_xuat_vat_tu set trang_thai =
    case when not exists (select 1 from public.de_xuat_dong where de_xuat_id = p_id and da_xuat < so_luong) then 'da_xuat' else 'cho_xuat' end
  where id = p_id and trang_thai <> 'huy'
$$;

create or replace function public.huy_de_xuat_vat_tu(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_xuat_vat_tu;
begin
  select * into r from public.de_xuat_vat_tu where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu đề xuất.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.nguoi_lap <> auth.uid() and not app.co_vai_tro('kho','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if r.trang_thai <> 'cho_xuat' then raise exception 'Phiếu đề xuất đã xuất xong hoặc đã hủy.'; end if;
  if exists (select 1 from public.de_xuat_dong where de_xuat_id = p_id and (da_xuat > 0 or cho_mua)) then
    raise exception 'Phiếu đã xuất một phần hoặc đang chờ mua – không hủy được.'; end if;
  update public.de_xuat_vat_tu set trang_thai = 'huy' where id = p_id;
end $$;

-- Kho xuất theo phiếu đề xuất. p_dong: [{dong_id, so_luong}] (để trống = xuất hết phần còn lại đủ tồn)
create or replace function public.xuat_kho_de_xuat(p_de_xuat bigint, p_dong jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.de_xuat_vat_tu; hs public.ho_so; v_px bigint; v_ma text; d record; v_sl numeric; v_pxd bigint;
  v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; v_tien numeric := 0; v_so int := 0;
begin
  perform app.yeu_cau('kho','giam_doc');
  select * into r from public.de_xuat_vat_tu where id = p_de_xuat for update;
  if not found then raise exception 'Không tìm thấy phiếu đề xuất.'; end if;
  if r.trang_thai <> 'cho_xuat' then raise exception 'Phiếu đề xuất đã xuất xong hoặc đã hủy.'; end if;
  hs := app.lay_ho_so(r.ho_so_id);
  perform app.yeu_cau_co_lenh(hs);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, v_ngay);
  v_ma := app.ma_chung_tu('PX', r.chi_nhanh_id, v_ngay, 'phieu_xuat');
  insert into public.phieu_xuat (chi_nhanh_id, ma, ngay, loai, ho_so_id, de_xuat_id, tao_boi)
  values (r.chi_nhanh_id, v_ma, v_ngay, 'cho_xe', hs.id, r.id, auth.uid()) returning id into v_px;
  for d in select dd.*, (select (x->>'so_luong')::numeric from jsonb_array_elements(coalesce(p_dong, '[]'::jsonb)) x
                          where (x->>'dong_id')::bigint = dd.id) as yeu_cau
           from public.de_xuat_dong dd where dd.de_xuat_id = r.id and dd.da_xuat < dd.so_luong order by dd.id for update loop
    v_sl := case when p_dong is null then least(d.so_luong - d.da_xuat, app.ton_hang(d.hang_id)) else coalesce(d.yeu_cau, 0) end;
    continue when v_sl <= 0;
    if v_sl > d.so_luong - d.da_xuat then raise exception 'Xuất quá số lượng đề xuất.'; end if;
    insert into public.phieu_xuat_dong (phieu_id, hang_id, so_luong, de_xuat_dong_id) values (v_px, d.hang_id, v_sl, d.id)
    returning id into v_pxd;
    v_tien := v_tien + app.xuat_fifo(v_pxd, d.hang_id, v_sl);
    update public.de_xuat_dong set da_xuat = da_xuat + v_sl,
      cho_mua = case when da_xuat + v_sl >= so_luong then false else cho_mua end where id = d.id;
    v_so := v_so + 1;
  end loop;
  if v_so = 0 then raise exception 'Không còn hàng để xuất cho phiếu này – chuyển mua phần thiếu.'; end if;
  perform app.cap_nhat_de_xuat(r.id);
  perform app.ghi_nhat_ky(hs.id, hs.trang_thai, hs.trang_thai, 'Xuất kho ' || v_ma || ' theo đề xuất ' || r.ma);
  return jsonb_build_object('id', v_px, 'ma', v_ma, 'gia_von', v_tien);
end $$;

-- Hết hàng: chuyển phần thiếu của phiếu đề xuất thành đề nghị mua (xe vào "Chờ phụ tùng")
-- p: {nha_cung_cap_id, ghi_chu, dong: [{dong_id, so_luong (đơn vị nhập), don_gia, ty_le_vat}]}
create or replace function public.chuyen_mua(p_de_xuat bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.de_xuat_vat_tu; d jsonb; dd public.de_xuat_dong; v_dong jsonb := '[]'::jsonb; v_kq jsonb;
begin
  perform app.yeu_cau('kho','giam_doc');
  select * into r from public.de_xuat_vat_tu where id = p_de_xuat for update;
  if not found then raise exception 'Không tìm thấy phiếu đề xuất.'; end if;
  if r.trang_thai <> 'cho_xuat' then raise exception 'Phiếu đề xuất đã xuất xong hoặc đã hủy.'; end if;
  if jsonb_typeof(p->'dong') <> 'array' or jsonb_array_length(p->'dong') = 0 then raise exception 'Chọn dòng cần mua.'; end if;
  for d in select * from jsonb_array_elements(p->'dong') loop
    select * into dd from public.de_xuat_dong where id = (d->>'dong_id')::bigint and de_xuat_id = r.id for update;
    if not found then raise exception 'Dòng không thuộc phiếu đề xuất này.'; end if;
    if dd.cho_mua then raise exception 'Dòng này đã chuyển mua, đang chờ hàng về.'; end if;
    if dd.da_xuat >= dd.so_luong then raise exception 'Dòng này đã xuất đủ.'; end if;
    update public.de_xuat_dong set cho_mua = true where id = dd.id;
    v_dong := v_dong || jsonb_build_object('hang_id', dd.hang_id, 'so_luong', d->'so_luong', 'don_gia', d->'don_gia',
                                           'ty_le_vat', coalesce(d->'ty_le_vat', '0.08'::jsonb), 'de_xuat_dong_id', dd.id);
  end loop;
  v_kq := app.tao_de_nghi_mua(jsonb_build_object('chi_nhanh_id', r.chi_nhanh_id, 'nha_cung_cap_id', p->'nha_cung_cap_id',
    'ho_so_id', r.ho_so_id, 'ghi_chu', coalesce(nullif(trim(p->>'ghi_chu'),''), 'Hết hàng – theo đề xuất ' || r.ma), 'dong', v_dong));
  perform app.ghi_nhat_ky(r.ho_so_id, (select trang_thai from public.ho_so where id = r.ho_so_id),
    (select trang_thai from public.ho_so where id = r.ho_so_id), 'Chờ phụ tùng: đề nghị mua ' || (v_kq->>'ma'));
  return v_kq;
end $$;

-- Xuất dùng chung xưởng (không theo xe). p: {ngay, ghi_chu, dong: [{hang_id, so_luong}]}
create or replace function public.xuat_dung_chung(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := app.chi_nhanh(); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_px bigint; v_ma text;
  d jsonb; h public.hang_kho; v_pxd bigint; v_tien numeric := 0;
begin
  perform app.yeu_cau('kho','giam_doc');
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if nullif(trim(p->>'ghi_chu'),'') is null then raise exception 'Ghi dùng vào việc gì.'; end if;
  if jsonb_typeof(p->'dong') <> 'array' or jsonb_array_length(p->'dong') = 0 then raise exception 'Phiếu xuất phải có ít nhất một dòng.'; end if;
  v_ma := app.ma_chung_tu('PX', v_cn, v_ngay, 'phieu_xuat');
  insert into public.phieu_xuat (chi_nhanh_id, ma, ngay, loai, ghi_chu, tao_boi)
  values (v_cn, v_ma, v_ngay, 'dung_chung', trim(p->>'ghi_chu'), auth.uid()) returning id into v_px;
  for d in select * from jsonb_array_elements(p->'dong') loop
    h := app.hang_cua_chi_nhanh((d->>'hang_id')::bigint, v_cn);
    if coalesce((d->>'so_luong')::numeric, 0) <= 0 then raise exception 'Dòng % thiếu số lượng.', h.ma; end if;
    insert into public.phieu_xuat_dong (phieu_id, hang_id, so_luong) values (v_px, h.id, (d->>'so_luong')::numeric) returning id into v_pxd;
    v_tien := v_tien + app.xuat_fifo(v_pxd, h.id, (d->>'so_luong')::numeric);
  end loop;
  return jsonb_build_object('id', v_px, 'ma', v_ma, 'gia_von', v_tien);
end $$;

-- Hủy phiếu xuất (xuất nhầm, trả lại kho): hàng về đúng lô cũ
create or replace function public.huy_phieu_xuat(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_xuat; x record;
begin
  perform app.yeu_cau('kho','giam_doc');
  select * into r from public.phieu_xuat where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu xuất.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai <> 'hieu_luc' then raise exception 'Phiếu xuất đã hủy.'; end if;
  if r.loai = 'kiem_ke' then raise exception 'Phiếu điều chỉnh kiểm kê không hủy được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  for x in select xl.lo_id, xl.so_luong from public.xuat_lo xl join public.phieu_xuat_dong d on d.id = xl.phieu_xuat_dong_id
           where d.phieu_id = p_id loop
    update public.lo_kho set con_lai = con_lai + x.so_luong where id = x.lo_id;
  end loop;
  update public.de_xuat_dong dd set da_xuat = greatest(dd.da_xuat - d.so_luong, 0)
  from public.phieu_xuat_dong d where d.phieu_id = p_id and d.de_xuat_dong_id = dd.id;
  update public.phieu_xuat set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) where id = p_id;
  if r.de_xuat_id is not null then perform app.cap_nhat_de_xuat(r.de_xuat_id); end if;
  if r.ho_so_id is not null then
    perform app.ghi_nhat_ky(r.ho_so_id, (select trang_thai from public.ho_so where id = r.ho_so_id),
      (select trang_thai from public.ho_so where id = r.ho_so_id), 'Hủy phiếu xuất ' || r.ma || ': ' || trim(p_ly_do));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Kiểm kê
-- ---------------------------------------------------------------------
-- p: {pham_vi: 'son_nham' | 'toan_kho' | 'chon', hang_ids: [..] (khi chọn), ngay}
create or replace function public.tao_kiem_ke(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := app.chi_nhanh(); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint; v_ma text;
  v_pv text := coalesce(p->>'pham_vi', 'toan_kho');
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  if v_pv not in ('son_nham','toan_kho','chon') then raise exception 'Phạm vi kiểm kê không hợp lệ.'; end if;
  if exists (select 1 from public.kiem_ke where chi_nhanh_id = v_cn and trang_thai = 'dang_dem') then
    raise exception 'Đang có một đợt kiểm kê chưa chốt – chốt hoặc hủy đợt đó trước.'; end if;
  v_ma := app.ma_chung_tu('KK', v_cn, v_ngay, 'kiem_ke');
  insert into public.kiem_ke (chi_nhanh_id, ma, ngay, pham_vi, tao_boi) values (v_cn, v_ma, v_ngay, v_pv, auth.uid()) returning id into v_id;
  insert into public.kiem_ke_dong (kiem_ke_id, hang_id)
  select v_id, h.id from public.hang_kho h
  where h.chi_nhanh_id = v_cn and h.hoat_dong
    and case v_pv when 'son_nham' then h.nhom in ('Sơn','Nhám')
                  when 'chon' then h.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(p->'hang_ids','[]'::jsonb)) x)
                  else true end
  order by h.nhom, h.ma;
  if not exists (select 1 from public.kiem_ke_dong where kiem_ke_id = v_id) then raise exception 'Không có mã hàng nào để kiểm kê.'; end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

-- Lưu số đếm thực tế. p_dong: [{dong_id, ton_thuc_te}]
create or replace function public.luu_dem_kiem_ke(p_id bigint, p_dong jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.kiem_ke; d jsonb;
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  select * into r from public.kiem_ke where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đợt kiểm kê.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'dang_dem' then raise exception 'Đợt kiểm kê đã chốt hoặc đã hủy.'; end if;
  for d in select * from jsonb_array_elements(p_dong) loop
    if (d->>'ton_thuc_te') is not null and (d->>'ton_thuc_te')::numeric < 0 then raise exception 'Số đếm không được âm.'; end if;
    update public.kiem_ke_dong set ton_thuc_te = (d->>'ton_thuc_te')::numeric where id = (d->>'dong_id')::bigint and kiem_ke_id = p_id;
  end loop;
end $$;

-- Chốt kiểm kê: so với tồn sổ sách lúc chốt; chênh trên 5% giá trị phải có biên bản; tự điều chỉnh tồn
create or replace function public.chot_kiem_ke(p_id bigint, p_bien_ban text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.kiem_ke; d record; v_ss numeric; v_gia numeric; v_tong_ss numeric := 0; v_tong_chenh numeric := 0;
  v_px bigint; v_pxd bigint; v_ma text; v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; v_ty_le numeric;
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  select * into r from public.kiem_ke where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đợt kiểm kê.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, v_ngay);
  if r.trang_thai <> 'dang_dem' then raise exception 'Đợt kiểm kê đã chốt hoặc đã hủy.'; end if;
  if exists (select 1 from public.kiem_ke_dong where kiem_ke_id = p_id and ton_thuc_te is null) then
    raise exception 'Còn mã chưa nhập số đếm thực tế.'; end if;
  -- Ghi tồn sổ sách + giá vốn bình quân hiện tại của từng mã
  for d in select * from public.kiem_ke_dong where kiem_ke_id = p_id for update loop
    v_ss := app.ton_hang(d.hang_id);
    select coalesce(sum(con_lai * don_gia_von) / nullif(sum(con_lai), 0),
                    (select don_gia_von from public.lo_kho where hang_id = d.hang_id order by ngay desc, id desc limit 1), 0)
      into v_gia from public.lo_kho where hang_id = d.hang_id and con_lai > 0;
    update public.kiem_ke_dong set ton_so_sach = v_ss, don_gia_von = v_gia where id = d.id;
    v_tong_ss := v_tong_ss + v_ss * v_gia;
    v_tong_chenh := v_tong_chenh + abs(d.ton_thuc_te - v_ss) * v_gia;
  end loop;
  v_ty_le := case when v_tong_ss > 0 then v_tong_chenh / v_tong_ss else case when v_tong_chenh > 0 then 1 else 0 end end;
  if v_ty_le > 0.05 and nullif(trim(p_bien_ban),'') is null then
    raise exception 'Chênh lệch % đ, bằng % phần trăm giá trị kiểm – vượt 5%%, phải ghi biên bản.', app.vnd(round(v_tong_chenh)), round(v_ty_le * 100, 1);
  end if;
  -- Thiếu: xuất điều chỉnh (nhập trước xuất trước). Thừa: thêm lô theo giá vốn hiện tại
  for d in select * from public.kiem_ke_dong where kiem_ke_id = p_id and ton_thuc_te <> ton_so_sach loop
    if d.ton_thuc_te < d.ton_so_sach then
      if v_px is null then
        v_ma := app.ma_chung_tu('PX', r.chi_nhanh_id, v_ngay, 'phieu_xuat');
        insert into public.phieu_xuat (chi_nhanh_id, ma, ngay, loai, kiem_ke_id, ghi_chu, tao_boi)
        values (r.chi_nhanh_id, v_ma, v_ngay, 'kiem_ke', p_id, 'Điều chỉnh thiếu theo kiểm kê ' || r.ma, auth.uid()) returning id into v_px;
      end if;
      insert into public.phieu_xuat_dong (phieu_id, hang_id, so_luong) values (v_px, d.hang_id, d.ton_so_sach - d.ton_thuc_te)
      returning id into v_pxd;
      perform app.xuat_fifo(v_pxd, d.hang_id, d.ton_so_sach - d.ton_thuc_te);
    else
      insert into public.lo_kho (chi_nhanh_id, hang_id, ngay, kiem_ke_id, so_luong, con_lai, don_gia_von)
      values (r.chi_nhanh_id, d.hang_id, v_ngay, p_id, d.ton_thuc_te - d.ton_so_sach, d.ton_thuc_te - d.ton_so_sach, coalesce(d.don_gia_von, 0));
    end if;
  end loop;
  update public.kiem_ke set trang_thai = 'da_chot', chot_boi = auth.uid(), chot_luc = now(),
    gia_tri_so_sach = round(v_tong_ss), gia_tri_chenh = round(v_tong_chenh), bien_ban = nullif(trim(p_bien_ban),'')
  where id = p_id;
  return jsonb_build_object('gia_tri_so_sach', round(v_tong_ss), 'gia_tri_chenh', round(v_tong_chenh), 'ty_le', round(v_ty_le * 100, 1));
end $$;

create or replace function public.huy_kiem_ke(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.kiem_ke;
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  select * into r from public.kiem_ke where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đợt kiểm kê.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'dang_dem' then raise exception 'Đợt kiểm kê đã chốt.'; end if;
  update public.kiem_ke set trang_thai = 'huy' where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- Bảng xem
-- ---------------------------------------------------------------------
-- Tồn kho hiện tại theo mã
create or replace view public.v_ton_kho with (security_invoker = true) as
select h.id, h.chi_nhanh_id, h.ma, h.ten, h.nhom, h.dvt, h.dvt_nhap, h.he_so, h.ton_toi_thieu, h.nha_cung_cap_id,
  n.ten as nha_cung_cap, h.ghi_chu, h.hoat_dong,
  coalesce(t.ton, 0) as ton, coalesce(t.gia_tri, 0) as gia_tri,
  coalesce(t.ton, 0) <= h.ton_toi_thieu and h.ton_toi_thieu > 0 as duoi_toi_thieu,
  (select pd.don_gia from public.phieu_nhap_dong pd join public.phieu_nhap pn on pn.id = pd.phieu_id
   where pd.hang_id = h.id and pn.trang_thai <> 'huy' order by pn.ngay desc, pd.id desc limit 1) as gia_nhap_gan_nhat
from public.hang_kho h
left join public.nha_cung_cap n on n.id = h.nha_cung_cap_id
left join lateral (select sum(l.con_lai) as ton, round(sum(l.con_lai * l.don_gia_von)) as gia_tri
                   from public.lo_kho l where l.hang_id = h.id) t on true;

-- Thẻ kho: mọi lần nhập (+) và xuất (−) để làm báo cáo nhập – xuất – tồn
create or replace view public.v_the_kho with (security_invoker = true) as
select l.chi_nhanh_id, l.ngay, l.hang_id, case when l.kiem_ke_id is not null then 'kiem_ke_thua' else 'nhap' end as loai,
  l.so_luong, round(l.so_luong * l.don_gia_von) as gia_tri,
  coalesce(pn.ma, kk.ma) as chung_tu, pn.ho_so_id, pn.nha_cung_cap_id, l.tao_luc
from public.lo_kho l
left join public.phieu_nhap_dong pd on pd.id = l.phieu_nhap_dong_id
left join public.phieu_nhap pn on pn.id = pd.phieu_id
left join public.kiem_ke kk on kk.id = l.kiem_ke_id
union all
select px.chi_nhanh_id, px.ngay, d.hang_id, case px.loai when 'kiem_ke' then 'kiem_ke_thieu' else 'xuat_' || px.loai end,
  -d.so_luong, -d.gia_von, px.ma, px.ho_so_id, null, px.tao_luc
from public.phieu_xuat_dong d join public.phieu_xuat px on px.id = d.phieu_id
where px.trang_thai = 'hieu_luc';

-- Phiếu đề xuất kèm xe và tình trạng từng phiếu.
-- Trưởng nhóm không đọc được bảng hồ sơ, nên bảng xem này chạy quyền chủ và tự lọc theo quyền người xem.
create or replace view public.v_de_xuat as
select d.*, h.ma as ma_ho_so, public.bien_so_hien_thi(x.bien_so) as bien_so, h.trang_thai as trang_thai_ho_so,
  nv.ho_ten as nguoi_lap_ten,
  (select count(*) from public.de_xuat_dong dd where dd.de_xuat_id = d.id) as so_dong,
  (select count(*) from public.de_xuat_dong dd where dd.de_xuat_id = d.id and dd.cho_mua) as so_dong_cho_mua
from public.de_xuat_vat_tu d
join public.ho_so h on h.id = d.ho_so_id
join public.xe x on x.id = h.xe_id
left join public.nhan_vien nv on nv.id = d.nguoi_lap
where app.duoc_xem_chi_nhanh(d.chi_nhanh_id) and (app.la_nhan_vien() or app.co_vai_tro('truong_nhom'));

create or replace view public.v_de_nghi_mua with (security_invoker = true) as
select d.*, n.ten as nha_cung_cap, h.ma as ma_ho_so, nv.ho_ten as nguoi_lap_ten, nd.ho_ten as duyet_boi_ten,
  (select count(*) from public.kho_tep t where t.loai = 'de_nghi_mua' and t.doi_tuong_id = d.id) as so_bao_gia,
  d.tong_tien >= app.cai_dat_so('nguong_3_bao_gia', 5000000) as can_3_bao_gia
from public.de_nghi_mua d
join public.nha_cung_cap n on n.id = d.nha_cung_cap_id
left join public.ho_so h on h.id = d.ho_so_id
left join public.nhan_vien nv on nv.id = d.nguoi_lap
left join public.nhan_vien nd on nd.id = d.duyet_boi;

create or replace view public.v_phieu_nhap with (security_invoker = true) as
select p.*, n.ten as nha_cung_cap, h.ma as ma_ho_so, dm.ma as ma_de_nghi_mua, nv.ho_ten as tao_boi_ten,
  (select count(*) from public.kho_tep t where t.loai = 'phieu_nhap' and t.doi_tuong_id = p.id) as so_tep
from public.phieu_nhap p
join public.nha_cung_cap n on n.id = p.nha_cung_cap_id
left join public.ho_so h on h.id = p.ho_so_id
left join public.de_nghi_mua dm on dm.id = p.de_nghi_mua_id
left join public.nhan_vien nv on nv.id = p.tao_boi;

create or replace view public.v_phieu_xuat with (security_invoker = true) as
select p.*, h.ma as ma_ho_so, public.bien_so_hien_thi(x.bien_so) as bien_so, dx.ma as ma_de_xuat, nv.ho_ten as tao_boi_ten,
  (select coalesce(sum(d.gia_von), 0) from public.phieu_xuat_dong d where d.phieu_id = p.id) as gia_von
from public.phieu_xuat p
left join public.ho_so h on h.id = p.ho_so_id
left join public.xe x on x.id = h.xe_id
left join public.de_xuat_vat_tu dx on dx.id = p.de_xuat_id
left join public.nhan_vien nv on nv.id = p.tao_boi;

-- Công nợ nhà cung cấp: phiếu nhập đã khớp hóa đơn − tiền đã trả (phiếu chi "trả NCC")
create or replace view public.v_cong_no_ncc with (security_invoker = true) as
select n.id as nha_cung_cap_id, n.ten, c.chi_nhanh_id,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai = 'da_khop'), 0) as da_nhap,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai in ('cho_khop','treo')), 0) as cho_khop,
  coalesce((select sum(t.so_tien) from public.phieu_thu_chi t join public.muc_thu_chi m on m.id = t.muc_id
            where t.nha_cung_cap_id = n.id and t.chi_nhanh_id = c.chi_nhanh_id and t.loai = 'chi' and t.trang_thai = 'hieu_luc'
              and m.tinh_chat = 'tra_ncc'), 0) as da_tra
from public.nha_cung_cap n
cross join (select id as chi_nhanh_id from public.chi_nhanh) c
where app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho') and app.duoc_xem_chi_nhanh(c.chi_nhanh_id);

-- Xe đang chờ phụ tùng: còn dòng đề xuất chờ mua hoặc đề nghị mua cho xe chưa về
create or replace view public.v_cho_phu_tung with (security_invoker = true) as
select ho_so_id, min(tu_ngay) as tu_ngay, (current_date - min(tu_ngay)) as so_ngay
from (
  select m.ho_so_id, m.ngay as tu_ngay from public.de_nghi_mua m where m.ho_so_id is not null and m.trang_thai in ('cho_duyet','da_duyet')
  union all
  select dx.ho_so_id, dx.tao_luc::date from public.de_xuat_dong dd join public.de_xuat_vat_tu dx on dx.id = dd.de_xuat_id
  where dd.cho_mua and dx.trang_thai = 'cho_xuat'
) t
group by ho_so_id;

-- Giá vốn phụ tùng, vật tư đã xuất cho từng xe
create or replace view public.v_gia_von_ho_so with (security_invoker = true) as
select px.ho_so_id, sum(d.gia_von) as gia_von
from public.phieu_xuat px join public.phieu_xuat_dong d on d.phieu_id = px.id
where px.loai = 'cho_xe' and px.trang_thai = 'hieu_luc'
group by px.ho_so_id;

do $$
declare v text;
begin
  foreach v in array array['v_ton_kho','v_the_kho','v_de_xuat','v_de_nghi_mua','v_phieu_nhap','v_phieu_xuat','v_cong_no_ncc','v_cho_phu_tung','v_gia_von_ho_so']
  loop
    execute format('grant select on public.%I to authenticated', v);
    execute format('revoke all on public.%I from anon', v);
  end loop;
end $$;

-- Hàm mới: chỉ người đã đăng nhập
do $$
declare f text;
begin
  foreach f in array array['luu_hang_kho(jsonb)','lap_de_nghi_mua(jsonb)','duyet_de_nghi_mua(bigint,boolean,text)',
    'huy_de_nghi_mua(bigint)','them_tep_kho(text,bigint,text,text)','lap_phieu_nhap(jsonb)','khop_phieu_nhap(bigint,boolean,text)',
    'huy_phieu_nhap(bigint,text)','lap_de_xuat_vat_tu(jsonb)','huy_de_xuat_vat_tu(bigint)','xuat_kho_de_xuat(bigint,jsonb)',
    'chuyen_mua(bigint,jsonb)','xuat_dung_chung(jsonb)','huy_phieu_xuat(bigint,text)','tao_kiem_ke(jsonb)',
    'luu_dem_kiem_ke(bigint,jsonb)','chot_kiem_ke(bigint,text)','huy_kiem_ke(bigint)']
  loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['ma_chung_tu(text,text,date,text)','hang_cua_chi_nhanh(bigint,text)','ton_hang(bigint)',
    'xuat_fifo(bigint,bigint,numeric)','yeu_cau_co_lenh(public.ho_so)','tao_de_nghi_mua(jsonb)','cap_nhat_de_xuat(bigint)']
  loop
    execute format('revoke execute on function app.%s from public, anon', f);
  end loop;
end $$;

-- Ngưỡng phải có 3 báo giá
insert into public.cai_dat (khoa, gia_tri) values ('nguong_3_bao_gia', '5000000') on conflict (khoa) do nothing;
