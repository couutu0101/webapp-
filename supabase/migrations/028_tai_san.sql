-- =====================================================================
-- 028 (14/10/2026): TÀI SẢN – DỤNG CỤ, MÁY MÓC, TRANG THIẾT BỊ GIAO CHO CÁC NHÓM
--  - Nhóm: các tổ (Đồng sơn, Điện – máy – gầm, Detailing…) + Dùng chung xưởng + Văn phòng.
--  - Hai loại: máy móc / thiết bị (từng cái, mã riêng, serial, bảo dưỡng) và dụng cụ (theo bộ / số lượng).
--  - Giám đốc, quản lý chung, kho: thêm, sửa, giao, chuyển nhóm, thanh lý. Người nhận (trưởng nhóm / người phụ trách) xác nhận đã nhận.
--  - Kiểm tra chống mất mỗi tuần: trưởng nhóm (tổ), quản lý chung (dùng chung xưởng), kế toán (văn phòng).
--  - Kiểm kê mỗi tháng: quản lý chung hoặc kế toán cùng người phụ trách nhóm, có biên bản.
--  - Thiếu / hỏng → sự cố chờ xử lý: giám đốc, quản lý chung xử lý; người chịu + tiền bồi thường chỉ giám đốc ghi.
--  - Bảo dưỡng theo thời gian: mỗi máy một hoặc nhiều việc, chu kỳ ngày; tới hạn báo ở Việc hôm nay.
--  - Mua sắm vẫn tính chi phí tháng mua (đề nghị chi) – mục này chỉ để quản lý, không vào lãi lỗ.
--  Tương thích ngược: chỉ thêm bảng / hàm mới.
-- =====================================================================

create table if not exists public.nhom_tai_san (
  id            text primary key,                         -- trùng mã tổ (DS, DMG, DT) hoặc CHUNG, VP
  ten           text not null,
  to_id         text references public.to_thuc_hien(id),  -- nhóm của tổ: trưởng nhóm tổ đó phụ trách
  vai_phu_trach text[] not null default '{}',             -- nhóm không thuộc tổ: vai trò phụ trách kiểm tra hằng tuần
  thu_tu        int not null default 0
);
insert into public.nhom_tai_san (id, ten, to_id, vai_phu_trach, thu_tu)
select t.id, t.ten, t.id, '{}', row_number() over (order by t.id) from public.to_thuc_hien t
on conflict (id) do nothing;
insert into public.nhom_tai_san (id, ten, to_id, vai_phu_trach, thu_tu) values
  ('CHUNG', 'Dùng chung xưởng', null, '{quan_ly}', 90),
  ('VP', 'Văn phòng', null, '{ke_toan}', 91)
on conflict (id) do nothing;
-- Tổ mới thêm sau này tự có nhóm tài sản
create or replace function app.them_nhom_tai_san_cho_to() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.nhom_tai_san (id, ten, to_id, thu_tu) values (new.id, new.ten, new.id, 50) on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists them_nhom_tai_san on public.to_thuc_hien;
create trigger them_nhom_tai_san after insert on public.to_thuc_hien for each row execute function app.them_nhom_tai_san_cho_to();

create table if not exists public.tai_san (
  id            bigint generated always as identity primary key,
  chi_nhanh_id  text not null references public.chi_nhanh(id),
  ma            text not null,                            -- TS-DS-001 (giữ nguyên khi chuyển nhóm)
  ten           text not null,
  loai          text not null check (loai in ('may_moc','dung_cu')),
  nhom_id       text not null references public.nhom_tai_san(id),
  so_luong      int not null default 1 check (so_luong >= 0),
  don_vi        text not null default 'Cái',
  hang_model    text,
  so_serial     text,
  gia_mua       numeric(14,0) not null default 0 check (gia_mua >= 0),   -- đơn giá một cái / một bộ
  ngay_mua      date,
  bao_hanh_den  date,
  nha_cung_cap_id bigint references public.nha_cung_cap(id),
  vi_tri        text,
  ghi_chu       text,
  anh           text,                                     -- đường dẫn ảnh trong kho 'ho-so-xe'
  tinh_trang    text not null default 'tot' check (tinh_trang in ('tot','hong','dang_sua','mat','thanh_ly')),
  cho_nhan      boolean not null default true,            -- mới giao / chuyển nhóm: chờ người phụ trách xác nhận đã nhận
  nhan_boi      uuid,
  nhan_luc      timestamptz,
  tao_boi       uuid,
  tao_luc       timestamptz not null default now(),
  unique (chi_nhanh_id, ma),
  constraint may_moc_mot_cai check (loai = 'dung_cu' or so_luong <= 1)
);
create index if not exists tai_san_nhom_idx on public.tai_san (chi_nhanh_id, nhom_id);

create table if not exists public.tai_san_lich_su (
  id          bigint generated always as identity primary key,
  tai_san_id  bigint not null references public.tai_san(id) on delete cascade,
  luc         timestamptz not null default now(),
  loai        text not null,      -- tao, sua, giao, xac_nhan, kiem_tra, su_co, xu_ly, bao_duong, sua_chua, thanh_ly
  noi_dung    text,
  tu_nhom     text,
  den_nhom    text,
  boi         uuid,
  boi_ten     text
);
create index if not exists tai_san_lich_su_idx on public.tai_san_lich_su (tai_san_id, luc desc);

create table if not exists public.kiem_tra_tai_san (
  id            bigint generated always as identity primary key,
  chi_nhanh_id  text not null references public.chi_nhanh(id),
  nhom_id       text not null references public.nhom_tai_san(id),
  loai          text not null check (loai in ('kiem_tra','kiem_ke')),   -- kiểm tra tuần / kiểm kê tháng
  ngay          date not null default current_date,
  nguoi_kiem    uuid not null,
  nguoi_kiem_ten text,                                    -- lưu tên để trưởng nhóm (không xem danh sách nhân viên) vẫn thấy
  cung_kiem     text,                                     -- kiểm kê: người cùng kiểm (trưởng nhóm / người phụ trách)
  ghi_chu       text,
  so_dong       int not null default 0,
  so_thieu      int not null default 0,
  so_hong       int not null default 0,
  tao_luc       timestamptz not null default now()
);
create index if not exists kiem_tra_tai_san_idx on public.kiem_tra_tai_san (chi_nhanh_id, nhom_id, ngay desc);

create table if not exists public.kiem_tra_tai_san_dong (
  id            bigint generated always as identity primary key,
  kiem_tra_id   bigint not null references public.kiem_tra_tai_san(id) on delete cascade,
  tai_san_id    bigint not null references public.tai_san(id),
  so_luong_so   int not null,                             -- trên sổ
  so_luong_thuc int not null check (so_luong_thuc >= 0),  -- đếm được (kể cả cái hỏng)
  so_hong       int not null default 0 check (so_hong >= 0),
  ket_qua       text not null check (ket_qua in ('du','thieu','hong','thieu_hong','du_thua')),
  ghi_chu       text
);
create index if not exists kiem_tra_tai_san_dong_idx on public.kiem_tra_tai_san_dong (tai_san_id);

create table if not exists public.su_co_tai_san (
  id            bigint generated always as identity primary key,
  chi_nhanh_id  text not null references public.chi_nhanh(id),
  tai_san_id    bigint not null references public.tai_san(id),
  kiem_tra_id   bigint references public.kiem_tra_tai_san(id),
  loai          text not null check (loai in ('mat','hong')),
  so_luong      int not null check (so_luong > 0),
  mo_ta         text,
  anh           text,
  phat_hien_boi uuid,
  phat_hien_luc timestamptz not null default now(),
  trang_thai    text not null default 'cho_xu_ly' check (trang_thai in ('cho_xu_ly','da_xu_ly')),
  ket_qua       text check (ket_qua in ('tim_thay','ghi_mat','dua_sua','da_sua','thanh_ly')),
  ghi_chu_xu_ly text,
  xu_ly_boi     uuid,
  xu_ly_luc     timestamptz,
  nguoi_chiu    uuid references public.nhan_vien(id),
  nguoi_chiu_ten text,
  boi_thuong    numeric(14,0) not null default 0 check (boi_thuong >= 0),
  da_tru        boolean not null default false,          -- bồi thường đã trừ lương / đã thu
  da_tru_luc    timestamptz,
  da_tru_boi    uuid
);
create index if not exists su_co_tai_san_idx on public.su_co_tai_san (chi_nhanh_id, trang_thai);

create table if not exists public.lich_bao_duong (
  id          bigint generated always as identity primary key,
  tai_san_id  bigint not null references public.tai_san(id) on delete cascade,
  ten_viec    text not null,                              -- Thay dầu, xả nước bình; Kiểm định cầu nâng…
  chu_ky_ngay int not null check (chu_ky_ngay between 1 and 3660),
  bat_dau     date not null default current_date,         -- chưa làm lần nào: hạn = bắt đầu + chu kỳ
  lan_cuoi    date,
  hoat_dong   boolean not null default true,
  tao_boi     uuid,
  tao_luc     timestamptz not null default now()
);

create table if not exists public.bao_duong_tai_san (
  id            bigint generated always as identity primary key,
  tai_san_id    bigint not null references public.tai_san(id) on delete cascade,
  lich_id       bigint references public.lich_bao_duong(id) on delete set null,
  loai          text not null check (loai in ('bao_duong','sua_chua')),
  ngay          date not null default current_date,
  noi_dung      text not null,
  nguoi_lam     text,
  chi_phi       numeric(14,0) not null default 0 check (chi_phi >= 0),
  thue_ngoai    boolean not null default false,
  tao_boi       uuid,
  tao_luc       timestamptz not null default now()
);
create index if not exists bao_duong_tai_san_idx on public.bao_duong_tai_san (tai_san_id, ngay desc);

insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('so_ngay_kiem_tra_tai_san', '7', 'Tài sản: người phụ trách nhóm kiểm tra chống mất sau mỗi số ngày này'),
  ('so_ngay_bao_truoc_bao_duong', '3', 'Tài sản: báo lịch bảo dưỡng máy móc trước số ngày này')
on conflict (khoa) do nothing;
insert into public.muc_thu_chi (loai, ten, nhom, tinh_chat, can_ho_so) values
  ('chi', 'Bảo dưỡng – sửa chữa máy móc', 'van_hanh', 'chi_phi', false)
on conflict (loai, ten) do nothing;

-- ---------------------------------------------------------------------
-- Quyền
-- ---------------------------------------------------------------------
create or replace function app.to_cua_toi() returns text
language sql stable security definer set search_path = public as $$
  select to_id from public.nhan_vien where id = auth.uid() and hoat_dong
$$;
-- Ai xem được tài sản của một nhóm: giám đốc, quản lý chung, kế toán, kho (cả chi nhánh); trưởng nhóm: nhóm của tổ mình
create or replace function app.xem_nhom_tai_san(cn text, nhom text) returns boolean
language sql stable security definer set search_path = public as $$
  select app.duoc_xem_chi_nhanh(cn) and (
    app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho')
    or (app.co_vai_tro('truong_nhom') and exists (
      select 1 from public.nhom_tai_san n where n.id = nhom and n.to_id is not null and n.to_id = app.to_cua_toi())))
$$;
-- Người phụ trách nhóm (kiểm tra tuần, xác nhận nhận, ghi bảo dưỡng): giám đốc, quản lý chung, trưởng nhóm của tổ, vai trò phụ trách
create or replace function app.phu_trach_nhom(nhom text) returns boolean
language sql stable security definer set search_path = public as $$
  select app.co_vai_tro('giam_doc','quan_ly') or exists (
    select 1 from public.nhom_tai_san n where n.id = nhom and (
      (n.to_id is not null and app.co_vai_tro('truong_nhom') and n.to_id = app.to_cua_toi())
      or (app.vai_tro() && n.vai_phu_trach)))
$$;
create or replace function app.yeu_cau_quan_ly_tai_san() returns void
language plpgsql stable as $$
begin
  perform app.yeu_cau('giam_doc','quan_ly','kho');
end $$;

do $$
declare t text;
begin
  foreach t in array array['nhom_tai_san','tai_san','tai_san_lich_su','kiem_tra_tai_san','kiem_tra_tai_san_dong','su_co_tai_san','lich_bao_duong','bao_duong_tai_san']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;
drop policy if exists doc on public.nhom_tai_san;
create policy doc on public.nhom_tai_san for select to authenticated using (app.la_nhan_vien() or app.co_vai_tro('truong_nhom'));
drop policy if exists doc on public.tai_san;
create policy doc on public.tai_san for select to authenticated using (app.xem_nhom_tai_san(chi_nhanh_id, nhom_id));
drop policy if exists doc on public.kiem_tra_tai_san;
create policy doc on public.kiem_tra_tai_san for select to authenticated using (app.xem_nhom_tai_san(chi_nhanh_id, nhom_id));
drop policy if exists doc on public.su_co_tai_san;
create policy doc on public.su_co_tai_san for select to authenticated
  using (exists (select 1 from public.tai_san t where t.id = tai_san_id and app.xem_nhom_tai_san(t.chi_nhanh_id, t.nhom_id)));
do $$
declare t text;
begin
  foreach t in array array['tai_san_lich_su','lich_bao_duong','bao_duong_tai_san']
  loop
    execute format('drop policy if exists doc on public.%I', t);
    execute format($f$create policy doc on public.%I for select to authenticated
      using (exists (select 1 from public.tai_san t where t.id = tai_san_id and app.xem_nhom_tai_san(t.chi_nhanh_id, t.nhom_id)))$f$, t);
  end loop;
end $$;
drop policy if exists doc on public.kiem_tra_tai_san_dong;
create policy doc on public.kiem_tra_tai_san_dong for select to authenticated
  using (exists (select 1 from public.kiem_tra_tai_san k where k.id = kiem_tra_id and app.xem_nhom_tai_san(k.chi_nhanh_id, k.nhom_id)));

-- ---------------------------------------------------------------------
-- Bảng xem
-- ---------------------------------------------------------------------
create or replace view public.v_tai_san with (security_invoker = true) as
select t.*, n.ten as nhom_ten, n.to_id,
  (t.gia_mua * t.so_luong) as gia_tri,
  (t.tinh_trang not in ('mat','thanh_ly') and t.so_luong > 0) as dang_dung,
  (select min(coalesce(l.lan_cuoi, l.bat_dau) + l.chu_ky_ngay) from public.lich_bao_duong l where l.tai_san_id = t.id and l.hoat_dong) as han_bao_duong,
  (select count(*) from public.su_co_tai_san s where s.tai_san_id = t.id and s.trang_thai = 'cho_xu_ly') as su_co_mo,
  (select max(k.ngay) from public.kiem_tra_tai_san_dong d join public.kiem_tra_tai_san k on k.id = d.kiem_tra_id where d.tai_san_id = t.id) as kiem_tra_cuoi
from public.tai_san t join public.nhom_tai_san n on n.id = t.nhom_id;

create or replace view public.v_nhom_tai_san with (security_invoker = true) as
select x.*,
  case when x.so_tai_san > 0 then coalesce(x.kiem_tra_cuoi, x.ngay_dau) + app.cai_dat_so('so_ngay_kiem_tra_tai_san', 7)::int end as han_kiem_tra,
  case when x.so_tai_san > 0 then (date_trunc('month', coalesce(x.kiem_ke_cuoi, x.ngay_dau))
    + case when x.kiem_ke_cuoi is null then interval '1 month' else interval '2 month' end - interval '1 day')::date end as han_kiem_ke
from (
  select c.id as chi_nhanh_id, n.id as nhom_id, n.ten, n.to_id, n.vai_phu_trach, n.thu_tu,
    (select count(*) from public.tai_san t where t.chi_nhanh_id = c.id and t.nhom_id = n.id and t.tinh_trang not in ('mat','thanh_ly') and t.so_luong > 0) as so_tai_san,
    (select coalesce(sum(t.gia_mua * t.so_luong), 0) from public.tai_san t where t.chi_nhanh_id = c.id and t.nhom_id = n.id and t.tinh_trang not in ('mat','thanh_ly')) as gia_tri,
    (select min(t.tao_luc)::date from public.tai_san t where t.chi_nhanh_id = c.id and t.nhom_id = n.id and t.tinh_trang not in ('mat','thanh_ly')) as ngay_dau,
    (select max(k.ngay) from public.kiem_tra_tai_san k where k.chi_nhanh_id = c.id and k.nhom_id = n.id) as kiem_tra_cuoi,
    (select max(k.ngay) from public.kiem_tra_tai_san k where k.chi_nhanh_id = c.id and k.nhom_id = n.id and k.loai = 'kiem_ke') as kiem_ke_cuoi,
    (select count(*) from public.tai_san t where t.chi_nhanh_id = c.id and t.nhom_id = n.id and t.cho_nhan and t.tinh_trang not in ('mat','thanh_ly')) as so_cho_nhan,
    (select count(*) from public.su_co_tai_san s join public.tai_san t on t.id = s.tai_san_id
      where t.chi_nhanh_id = c.id and t.nhom_id = n.id and s.trang_thai = 'cho_xu_ly') as so_su_co,
    (select count(*) from public.lich_bao_duong l join public.tai_san t on t.id = l.tai_san_id
      where t.chi_nhanh_id = c.id and t.nhom_id = n.id and l.hoat_dong and t.tinh_trang not in ('mat','thanh_ly')
        and coalesce(l.lan_cuoi, l.bat_dau) + l.chu_ky_ngay <= current_date + app.cai_dat_so('so_ngay_bao_truoc_bao_duong', 3)::int) as so_bao_duong_toi_han
  from public.chi_nhanh c cross join public.nhom_tai_san n
  where app.xem_nhom_tai_san(c.id, n.id)
) x;

-- Việc cần làm về tài sản (Việc hôm nay): vai = vai trò làm việc đó; to_id: chỉ trưởng nhóm của tổ này
create or replace view public.v_viec_tai_san with (security_invoker = true) as
select g.chi_nhanh_id, g.nhom_id, g.ten as nhom_ten, g.to_id, 'kiem_tra'::text as loai,
  case when g.to_id is not null then '{truong_nhom}'::text[] else g.vai_phu_trach end as vai,
  'Kiểm tra tài sản tuần – ' || g.ten as tieu_de, g.so_tai_san || ' tài sản' as chi_tiet, g.han_kiem_tra as han, g.so_tai_san as so, null::bigint as tai_san_id
from public.v_nhom_tai_san g where g.so_tai_san > 0 and g.han_kiem_tra <= current_date + 1
union all
select g.chi_nhanh_id, g.nhom_id, g.ten, g.to_id, 'kiem_ke', '{quan_ly,ke_toan}'::text[],
  'Kiểm kê tài sản tháng – ' || g.ten, g.so_tai_san || ' tài sản', g.han_kiem_ke, g.so_tai_san, null
from public.v_nhom_tai_san g where g.so_tai_san > 0 and g.han_kiem_ke <= current_date + 6
union all
select g.chi_nhanh_id, g.nhom_id, g.ten, g.to_id, 'xac_nhan',
  case when g.to_id is not null then '{truong_nhom}'::text[] else g.vai_phu_trach end,
  'Xác nhận đã nhận tài sản – ' || g.ten, g.so_cho_nhan || ' món mới giao', null::date, g.so_cho_nhan, null
from public.v_nhom_tai_san g where g.so_cho_nhan > 0
union all
select g.chi_nhanh_id, g.nhom_id, g.ten, g.to_id, 'su_co', '{giam_doc,quan_ly}'::text[],
  'Xử lý tài sản thiếu / hỏng – ' || g.ten, g.so_su_co || ' việc chờ xử lý', null::date, g.so_su_co, null
from public.v_nhom_tai_san g where g.so_su_co > 0
union all
select t.chi_nhanh_id, t.nhom_id, n.ten, n.to_id, 'bao_duong',
  case when n.to_id is not null then '{truong_nhom}'::text[] else n.vai_phu_trach end,
  'Bảo dưỡng ' || t.ten || ': ' || l.ten_viec, t.ma, coalesce(l.lan_cuoi, l.bat_dau) + l.chu_ky_ngay, 1, t.id
from public.lich_bao_duong l join public.tai_san t on t.id = l.tai_san_id join public.nhom_tai_san n on n.id = t.nhom_id
where l.hoat_dong and t.tinh_trang not in ('mat','thanh_ly')
  and coalesce(l.lan_cuoi, l.bat_dau) + l.chu_ky_ngay <= current_date + app.cai_dat_so('so_ngay_bao_truoc_bao_duong', 3)::int;

grant select on public.v_tai_san, public.v_nhom_tai_san, public.v_viec_tai_san to authenticated;
revoke all on public.v_tai_san, public.v_nhom_tai_san, public.v_viec_tai_san from anon;

-- ---------------------------------------------------------------------
-- Ghi dữ liệu
-- ---------------------------------------------------------------------
create or replace function app.ghi_ls_tai_san(p_ts bigint, p_loai text, p_noi_dung text, p_tu text default null, p_den text default null) returns void
language sql security definer set search_path = public as $$
  insert into public.tai_san_lich_su (tai_san_id, loai, noi_dung, tu_nhom, den_nhom, boi, boi_ten)
  values (p_ts, p_loai, p_noi_dung, p_tu, p_den, auth.uid(), (select ho_ten from public.nhan_vien where id = auth.uid()))
$$;

-- Thêm / sửa tài sản. p: {id?, ten, loai, nhom_id, so_luong, don_vi, hang_model, so_serial, gia_mua, ngay_mua, bao_hanh_den, nha_cung_cap_id, vi_tri, ghi_chu}
create or replace function public.luu_tai_san(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); r public.tai_san; v_id bigint; v_ma text; v_so int; v_loai text; v_nhom text;
begin
  perform app.yeu_cau_quan_ly_tai_san();
  perform app.yeu_cau_chi_nhanh(v_cn);
  if nullif(trim(p->>'ten'),'') is null then raise exception 'Ghi tên tài sản.'; end if;
  v_loai := coalesce(p->>'loai', 'dung_cu');
  if v_loai not in ('may_moc','dung_cu') then raise exception 'Loại tài sản không đúng.'; end if;
  v_so := case when v_loai = 'may_moc' then 1 else coalesce((p->>'so_luong')::int, 1) end;
  if v_so < 1 then raise exception 'Số lượng phải từ 1 trở lên.'; end if;
  if coalesce((p->>'gia_mua')::numeric, 0) < 0 then raise exception 'Giá mua không đúng.'; end if;
  if (p->>'id') is null then
    v_nhom := p->>'nhom_id';
    if not exists (select 1 from public.nhom_tai_san where id = v_nhom) then raise exception 'Chọn nhóm nhận tài sản.'; end if;
    perform pg_advisory_xact_lock(hashtext('ma_tai_san_' || v_cn || v_nhom));
    select 'TS-' || v_nhom || '-' || lpad((coalesce(max(substring(ma from '(\d+)$')::int), 0) + 1)::text, 3, '0') into v_ma
    from public.tai_san where chi_nhanh_id = v_cn and ma like 'TS-' || v_nhom || '-%';
    insert into public.tai_san (chi_nhanh_id, ma, ten, loai, nhom_id, so_luong, don_vi, hang_model, so_serial, gia_mua, ngay_mua, bao_hanh_den,
      nha_cung_cap_id, vi_tri, ghi_chu, tao_boi)
    values (v_cn, v_ma, trim(p->>'ten'), v_loai, v_nhom, v_so, coalesce(nullif(trim(p->>'don_vi'),''), 'Cái'),
      nullif(trim(p->>'hang_model'),''), nullif(trim(p->>'so_serial'),''), coalesce((p->>'gia_mua')::numeric, 0),
      (p->>'ngay_mua')::date, (p->>'bao_hanh_den')::date, (p->>'nha_cung_cap_id')::bigint, nullif(trim(p->>'vi_tri'),''), nullif(trim(p->>'ghi_chu'),''), auth.uid())
    returning id into v_id;
    perform app.ghi_ls_tai_san(v_id, 'tao', format('Thêm %s %s %s, giao cho nhóm %s', v_so, coalesce(nullif(trim(p->>'don_vi'),''), 'Cái'), trim(p->>'ten'),
      (select ten from public.nhom_tai_san where id = v_nhom)), null, v_nhom);
    return v_id;
  end if;
  select * into r from public.tai_san where id = (p->>'id')::bigint for update;
  if not found then raise exception 'Không tìm thấy tài sản.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.tinh_trang in ('mat','thanh_ly') then raise exception 'Tài sản đã mất / thanh lý, không sửa được.'; end if;
  if r.loai <> v_loai then raise exception 'Không đổi loại tài sản được (thêm tài sản mới nếu cần).'; end if;
  update public.tai_san set ten = trim(p->>'ten'), so_luong = v_so, don_vi = coalesce(nullif(trim(p->>'don_vi'),''), r.don_vi),
    hang_model = nullif(trim(p->>'hang_model'),''), so_serial = nullif(trim(p->>'so_serial'),''), gia_mua = coalesce((p->>'gia_mua')::numeric, 0),
    ngay_mua = (p->>'ngay_mua')::date, bao_hanh_den = (p->>'bao_hanh_den')::date, nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint,
    vi_tri = nullif(trim(p->>'vi_tri'),''), ghi_chu = nullif(trim(p->>'ghi_chu'),'')
  where id = r.id;
  perform app.ghi_ls_tai_san(r.id, 'sua', case when v_so <> r.so_luong then format('Sửa thông tin; số lượng %s → %s', r.so_luong, v_so) else 'Sửa thông tin' end);
  return r.id;
end $$;

create or replace function public.chuyen_nhom_tai_san(p_id bigint, p_nhom text, p_ghi_chu text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.tai_san;
begin
  perform app.yeu_cau_quan_ly_tai_san();
  select * into r from public.tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy tài sản.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.tinh_trang in ('mat','thanh_ly') then raise exception 'Tài sản đã mất / thanh lý.'; end if;
  if not exists (select 1 from public.nhom_tai_san where id = p_nhom) then raise exception 'Chọn nhóm nhận.'; end if;
  if p_nhom = r.nhom_id then raise exception 'Tài sản đang ở nhóm này rồi.'; end if;
  update public.tai_san set nhom_id = p_nhom, cho_nhan = true, nhan_boi = null, nhan_luc = null where id = p_id;
  perform app.ghi_ls_tai_san(p_id, 'giao', concat_ws(' – ', format('Chuyển từ %s sang %s', (select ten from public.nhom_tai_san where id = r.nhom_id),
    (select ten from public.nhom_tai_san where id = p_nhom)), nullif(trim(p_ghi_chu),'')), r.nhom_id, p_nhom);
end $$;

-- Người phụ trách nhóm xác nhận đã nhận các tài sản mới giao
create or replace function public.xac_nhan_nhan_tai_san(p_ids jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r public.tai_san; v_so int := 0;
begin
  if jsonb_typeof(p_ids) <> 'array' then raise exception 'Chưa chọn tài sản.'; end if;
  for r in select * from public.tai_san where id in (select (e #>> '{}')::bigint from jsonb_array_elements(p_ids) e) and cho_nhan for update loop
    perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
    if not app.phu_trach_nhom(r.nhom_id) then raise exception 'Chỉ người phụ trách nhóm % xác nhận được.', (select ten from public.nhom_tai_san where id = r.nhom_id) using errcode = '42501'; end if;
    update public.tai_san set cho_nhan = false, nhan_boi = auth.uid(), nhan_luc = now() where id = r.id;
    perform app.ghi_ls_tai_san(r.id, 'xac_nhan', 'Đã nhận tài sản');
    v_so := v_so + 1;
  end loop;
  return v_so;
end $$;

-- Kiểm tra tuần / kiểm kê tháng.
-- p: {nhom_id, loai: kiem_tra|kiem_ke, cung_kiem, ghi_chu, dong: [{tai_san_id, so_thuc, so_hong, ghi_chu}]}
--   Mọi tài sản đang dùng của nhóm (trừ máy đang đi sửa) phải có dòng. Thiếu / hỏng → sự cố chờ xử lý; máy hỏng → tình trạng Hỏng.
create or replace function public.luu_kiem_tra_tai_san(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_nhom text := p->>'nhom_id'; v_loai text := coalesce(p->>'loai', 'kiem_tra');
  v_id bigint; d jsonb; t public.tai_san; v_thuc int; v_hong int; v_kq text; v_thieu int := 0; v_so_hong int := 0; v_dong int := 0; v_thieu_tai_san text;
  v_da_bao int;
begin
  perform app.yeu_cau_chi_nhanh(v_cn);
  if v_loai not in ('kiem_tra','kiem_ke') then raise exception 'Loại kiểm tra không đúng.'; end if;
  if not exists (select 1 from public.nhom_tai_san where id = v_nhom) then raise exception 'Chọn nhóm.'; end if;
  if v_loai = 'kiem_tra' and not app.phu_trach_nhom(v_nhom) then
    raise exception 'Chỉ người phụ trách nhóm kiểm tra tuần được.' using errcode = '42501'; end if;
  if v_loai = 'kiem_ke' then
    perform app.yeu_cau('giam_doc','quan_ly','ke_toan');
    if nullif(trim(p->>'cung_kiem'),'') is null then raise exception 'Kiểm kê: ghi tên người cùng kiểm (trưởng nhóm / người phụ trách nhóm).'; end if;
  end if;
  if jsonb_typeof(p->'dong') <> 'array' or jsonb_array_length(p->'dong') = 0 then raise exception 'Chưa có dòng nào.'; end if;
  -- đủ dòng cho mọi tài sản đang dùng của nhóm
  select string_agg(x.ten, ', ') into v_thieu_tai_san from public.tai_san x
  where x.chi_nhanh_id = v_cn and x.nhom_id = v_nhom and x.tinh_trang not in ('mat','thanh_ly','dang_sua') and x.so_luong > 0
    and not exists (select 1 from jsonb_array_elements(p->'dong') e where (e->>'tai_san_id')::bigint = x.id);
  if v_thieu_tai_san is not null then raise exception 'Còn tài sản chưa kiểm: %', v_thieu_tai_san; end if;

  insert into public.kiem_tra_tai_san (chi_nhanh_id, nhom_id, loai, nguoi_kiem, nguoi_kiem_ten, cung_kiem, ghi_chu)
  values (v_cn, v_nhom, v_loai, auth.uid(), (select ho_ten from public.nhan_vien where id = auth.uid()), nullif(trim(p->>'cung_kiem'),''), nullif(trim(p->>'ghi_chu'),'')) returning id into v_id;
  for d in select * from jsonb_array_elements(p->'dong') loop
    select * into t from public.tai_san where id = (d->>'tai_san_id')::bigint for update;
    if not found or t.chi_nhanh_id <> v_cn or t.nhom_id <> v_nhom then raise exception 'Tài sản không thuộc nhóm này.'; end if;
    v_thuc := coalesce((d->>'so_thuc')::int, -1);
    v_hong := coalesce((d->>'so_hong')::int, 0);
    if v_thuc < 0 then raise exception 'Chưa nhập số đếm được cho %.', t.ten; end if;
    if v_hong < 0 or v_hong > v_thuc then raise exception 'Số hỏng của % không đúng.', t.ten; end if;
    if v_thuc < t.so_luong and nullif(trim(d->>'ghi_chu'),'') is null and v_loai = 'kiem_ke' then
      raise exception 'Kiểm kê: % thiếu, ghi lý do / nơi để.', t.ten; end if;
    v_kq := case when v_thuc < t.so_luong and v_hong > 0 then 'thieu_hong' when v_thuc < t.so_luong then 'thieu'
                 when v_hong > 0 then 'hong' when v_thuc > t.so_luong then 'du_thua' else 'du' end;
    insert into public.kiem_tra_tai_san_dong (kiem_tra_id, tai_san_id, so_luong_so, so_luong_thuc, so_hong, ket_qua, ghi_chu)
    values (v_id, t.id, t.so_luong, v_thuc, v_hong, v_kq, nullif(trim(d->>'ghi_chu'),''));
    v_dong := v_dong + 1;
    -- Thiếu / hỏng: chỉ báo phần MỚI so với các sự cố đang chờ xử lý của món đó (không báo trùng giữa các lần kiểm)
    if v_thuc < t.so_luong then
      select coalesce(sum(so_luong), 0) into v_da_bao from public.su_co_tai_san where tai_san_id = t.id and loai = 'mat' and trang_thai = 'cho_xu_ly';
      if t.so_luong - v_thuc > v_da_bao then
        insert into public.su_co_tai_san (chi_nhanh_id, tai_san_id, kiem_tra_id, loai, so_luong, mo_ta, phat_hien_boi)
        values (v_cn, t.id, v_id, 'mat', t.so_luong - v_thuc - v_da_bao,
          coalesce(nullif(trim(d->>'ghi_chu'),''), case when v_loai = 'kiem_ke' then 'Thiếu khi kiểm kê' else 'Thiếu khi kiểm tra tuần' end)
            || case when v_da_bao > 0 then format(' (thiếu thêm, đã báo trước %s)', v_da_bao) else '' end, auth.uid());
      end if;
      v_thieu := v_thieu + 1;
    end if;
    if v_hong > 0 then
      select coalesce(sum(so_luong), 0) into v_da_bao from public.su_co_tai_san where tai_san_id = t.id and loai = 'hong' and trang_thai = 'cho_xu_ly';
      if v_hong > v_da_bao then
        insert into public.su_co_tai_san (chi_nhanh_id, tai_san_id, kiem_tra_id, loai, so_luong, mo_ta, phat_hien_boi)
        values (v_cn, t.id, v_id, 'hong', v_hong - v_da_bao, coalesce(nullif(trim(d->>'ghi_chu'),''), 'Hỏng khi kiểm tra')
          || case when v_da_bao > 0 then format(' (hỏng thêm, đã báo trước %s)', v_da_bao) else '' end, auth.uid());
      end if;
      if t.loai = 'may_moc' then update public.tai_san set tinh_trang = 'hong' where id = t.id; end if;
      v_so_hong := v_so_hong + 1;
    end if;
    -- đếm thấy là đã nhận
    if t.cho_nhan and v_thuc > 0 then update public.tai_san set cho_nhan = false, nhan_boi = auth.uid(), nhan_luc = now() where id = t.id; end if;
    perform app.ghi_ls_tai_san(t.id, 'kiem_tra', format('%s: đếm %s/%s%s', case when v_loai = 'kiem_ke' then 'Kiểm kê tháng' else 'Kiểm tra tuần' end,
      v_thuc, t.so_luong, case when v_hong > 0 then format(', hỏng %s', v_hong) else '' end));
  end loop;
  update public.kiem_tra_tai_san set so_dong = v_dong, so_thieu = v_thieu, so_hong = v_so_hong where id = v_id;
  return v_id;
end $$;

-- Báo mất / hỏng ngoài lúc kiểm tra. p: {tai_san_id, loai: mat|hong, so_luong, mo_ta}
create or replace function public.bao_su_co_tai_san(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.tai_san; v_id bigint; v_so int := coalesce((p->>'so_luong')::int, 1);
begin
  select * into t from public.tai_san where id = (p->>'tai_san_id')::bigint for update;
  if not found then raise exception 'Không tìm thấy tài sản.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if (p->>'loai') not in ('mat','hong') then raise exception 'Chọn mất hay hỏng.'; end if;
  if t.tinh_trang in ('mat','thanh_ly') then raise exception 'Tài sản đã mất / thanh lý.'; end if;
  if v_so < 1 or v_so > t.so_luong then raise exception 'Số lượng không đúng (đang có %).', t.so_luong; end if;
  if nullif(trim(p->>'mo_ta'),'') is null then raise exception 'Ghi mô tả: mất khi nào, hỏng thế nào.'; end if;
  insert into public.su_co_tai_san (chi_nhanh_id, tai_san_id, loai, so_luong, mo_ta, phat_hien_boi)
  values (t.chi_nhanh_id, t.id, p->>'loai', v_so, trim(p->>'mo_ta'), auth.uid()) returning id into v_id;
  if p->>'loai' = 'hong' and t.loai = 'may_moc' then update public.tai_san set tinh_trang = 'hong' where id = t.id; end if;
  perform app.ghi_ls_tai_san(t.id, 'su_co', format('Báo %s %s: %s', case when p->>'loai' = 'mat' then 'mất' else 'hỏng' end, v_so, trim(p->>'mo_ta')));
  return v_id;
end $$;

-- Xử lý sự cố. p: {id, ket_qua: tim_thay|ghi_mat|dua_sua|da_sua|thanh_ly, ghi_chu, nguoi_chiu, nguoi_chiu_ten, boi_thuong}
--   Người chịu + tiền bồi thường: chỉ giám đốc ghi.
create or replace function public.xu_ly_su_co_tai_san(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare s public.su_co_tai_san; t public.tai_san; v_kq text := p->>'ket_qua'; v_bt numeric := coalesce((p->>'boi_thuong')::numeric, 0);
  v_nguoi uuid := nullif(p->>'nguoi_chiu','')::uuid; v_ten text := nullif(trim(p->>'nguoi_chiu_ten'),'');
begin
  perform app.yeu_cau('giam_doc','quan_ly');
  select * into s from public.su_co_tai_san where id = (p->>'id')::bigint for update;
  if not found then raise exception 'Không tìm thấy sự cố.'; end if;
  perform app.yeu_cau_chi_nhanh(s.chi_nhanh_id);
  if s.trang_thai <> 'cho_xu_ly' then raise exception 'Sự cố đã xử lý.'; end if;
  select * into t from public.tai_san where id = s.tai_san_id for update;
  if s.loai = 'mat' and v_kq not in ('tim_thay','ghi_mat') then raise exception 'Mất: chọn Tìm thấy hoặc Ghi mất.'; end if;
  if s.loai = 'hong' and v_kq not in ('dua_sua','da_sua','thanh_ly') then raise exception 'Hỏng: chọn Đưa đi sửa, Đã sửa xong hoặc Thanh lý.'; end if;
  if v_bt < 0 then raise exception 'Tiền bồi thường không đúng.'; end if;
  if (v_bt > 0 or v_nguoi is not null or v_ten is not null) and not app.co_vai_tro('giam_doc') then
    raise exception 'Chỉ giám đốc ghi người chịu và tiền bồi thường.' using errcode = '42501'; end if;
  if v_bt > 0 and v_nguoi is null and v_ten is null then raise exception 'Có tiền bồi thường thì chọn người chịu.'; end if;
  if v_kq = 'ghi_mat' then
    update public.tai_san set so_luong = greatest(0, so_luong - s.so_luong),
      tinh_trang = case when loai = 'may_moc' or so_luong - s.so_luong <= 0 then 'mat' else tinh_trang end where id = t.id;
  elsif v_kq = 'thanh_ly' then
    update public.tai_san set so_luong = case when loai = 'may_moc' then so_luong else greatest(0, so_luong - s.so_luong) end,
      tinh_trang = case when loai = 'may_moc' or so_luong - s.so_luong <= 0 then 'thanh_ly' else tinh_trang end where id = t.id;
  elsif v_kq = 'dua_sua' then
    if t.loai = 'may_moc' then update public.tai_san set tinh_trang = 'dang_sua' where id = t.id; end if;
  elsif v_kq = 'da_sua' then
    if t.loai = 'may_moc' then update public.tai_san set tinh_trang = 'tot' where id = t.id; end if;
  end if;
  update public.su_co_tai_san set trang_thai = 'da_xu_ly', ket_qua = v_kq, ghi_chu_xu_ly = nullif(trim(p->>'ghi_chu'),''),
    xu_ly_boi = auth.uid(), xu_ly_luc = now(), nguoi_chiu = v_nguoi,
    nguoi_chiu_ten = coalesce(v_ten, (select ho_ten from public.nhan_vien where id = v_nguoi)), boi_thuong = v_bt
  where id = s.id;
  perform app.ghi_ls_tai_san(t.id, 'xu_ly', concat_ws(' – ',
    case v_kq when 'tim_thay' then 'Đã tìm thấy' when 'ghi_mat' then format('Ghi mất %s', s.so_luong) when 'dua_sua' then 'Đưa đi sửa'
              when 'da_sua' then 'Đã sửa xong' else format('Thanh lý %s', s.so_luong) end,
    case when v_bt > 0 then format('bồi thường %s đ (%s)', to_char(v_bt, 'FM999G999G999G999'), coalesce(v_ten, (select ho_ten from public.nhan_vien where id = v_nguoi))) end,
    nullif(trim(p->>'ghi_chu'),'')));
end $$;

-- Bồi thường đã trừ lương / đã thu: giám đốc, kế toán
create or replace function public.danh_dau_boi_thuong(p_id bigint, p_da_tru boolean) returns void
language plpgsql security definer set search_path = public as $$
declare s public.su_co_tai_san;
begin
  perform app.yeu_cau('giam_doc','ke_toan');
  select * into s from public.su_co_tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy.'; end if;
  perform app.yeu_cau_chi_nhanh(s.chi_nhanh_id);
  if s.boi_thuong <= 0 then raise exception 'Sự cố này không có tiền bồi thường.'; end if;
  update public.su_co_tai_san set da_tru = p_da_tru, da_tru_luc = case when p_da_tru then now() end, da_tru_boi = case when p_da_tru then auth.uid() end where id = p_id;
end $$;

create or replace function public.thanh_ly_tai_san(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.tai_san;
begin
  perform app.yeu_cau_quan_ly_tai_san();
  select * into r from public.tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy tài sản.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.tinh_trang in ('mat','thanh_ly') then raise exception 'Tài sản đã mất / thanh lý.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do thanh lý.'; end if;
  update public.tai_san set tinh_trang = 'thanh_ly', cho_nhan = false where id = p_id;
  update public.lich_bao_duong set hoat_dong = false where tai_san_id = p_id;
  perform app.ghi_ls_tai_san(p_id, 'thanh_ly', 'Thanh lý: ' || trim(p_ly_do));
end $$;

-- Lịch bảo dưỡng. p: {id?, tai_san_id, ten_viec, chu_ky_ngay, bat_dau, lan_cuoi, hoat_dong}
create or replace function public.luu_lich_bao_duong(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.tai_san; l public.lich_bao_duong; v_id bigint; v_ck int := (p->>'chu_ky_ngay')::int;
begin
  if (p->>'id') is not null then
    select * into l from public.lich_bao_duong where id = (p->>'id')::bigint for update;
    if not found then raise exception 'Không tìm thấy lịch.'; end if;
    select * into t from public.tai_san where id = l.tai_san_id;
  else
    select * into t from public.tai_san where id = (p->>'tai_san_id')::bigint;
    if not found then raise exception 'Không tìm thấy tài sản.'; end if;
  end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if nullif(trim(p->>'ten_viec'),'') is null then raise exception 'Ghi việc bảo dưỡng.'; end if;
  if v_ck is null or v_ck < 1 or v_ck > 3660 then raise exception 'Chu kỳ bảo dưỡng không đúng.'; end if;
  if (p->>'id') is not null then
    update public.lich_bao_duong set ten_viec = trim(p->>'ten_viec'), chu_ky_ngay = v_ck, bat_dau = coalesce((p->>'bat_dau')::date, bat_dau),
      lan_cuoi = (p->>'lan_cuoi')::date, hoat_dong = coalesce((p->>'hoat_dong')::boolean, true) where id = l.id;
    return l.id;
  end if;
  insert into public.lich_bao_duong (tai_san_id, ten_viec, chu_ky_ngay, bat_dau, lan_cuoi, tao_boi)
  values (t.id, trim(p->>'ten_viec'), v_ck, coalesce((p->>'bat_dau')::date, current_date), (p->>'lan_cuoi')::date, auth.uid()) returning id into v_id;
  perform app.ghi_ls_tai_san(t.id, 'bao_duong', format('Lịch bảo dưỡng: %s, mỗi %s ngày', trim(p->>'ten_viec'), v_ck));
  return v_id;
end $$;

-- Ghi lần bảo dưỡng / sửa chữa. p: {tai_san_id, lich_id?, loai, ngay, noi_dung, nguoi_lam, chi_phi, thue_ngoai, xong (sửa xong → tình trạng Tốt)}
create or replace function public.ghi_bao_duong(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.tai_san; v_id bigint; v_ngay date := coalesce((p->>'ngay')::date, current_date); v_loai text := coalesce(p->>'loai', 'bao_duong');
begin
  select * into t from public.tai_san where id = (p->>'tai_san_id')::bigint for update;
  if not found then raise exception 'Không tìm thấy tài sản.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if v_loai not in ('bao_duong','sua_chua') then raise exception 'Loại không đúng.'; end if;
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'noi_dung'),'') is null then raise exception 'Ghi nội dung đã làm.'; end if;
  if (p->>'lich_id') is not null and not exists (select 1 from public.lich_bao_duong where id = (p->>'lich_id')::bigint and tai_san_id = t.id) then
    raise exception 'Lịch bảo dưỡng không thuộc tài sản này.'; end if;
  insert into public.bao_duong_tai_san (tai_san_id, lich_id, loai, ngay, noi_dung, nguoi_lam, chi_phi, thue_ngoai, tao_boi)
  values (t.id, (p->>'lich_id')::bigint, v_loai, v_ngay, trim(p->>'noi_dung'), nullif(trim(p->>'nguoi_lam'),''),
    coalesce((p->>'chi_phi')::numeric, 0), coalesce((p->>'thue_ngoai')::boolean, false), auth.uid()) returning id into v_id;
  if (p->>'lich_id') is not null then
    update public.lich_bao_duong set lan_cuoi = greatest(coalesce(lan_cuoi, v_ngay), v_ngay) where id = (p->>'lich_id')::bigint;
  end if;
  if coalesce((p->>'xong')::boolean, false) and t.tinh_trang in ('hong','dang_sua') then
    update public.tai_san set tinh_trang = 'tot' where id = t.id;
    update public.su_co_tai_san set trang_thai = 'da_xu_ly', ket_qua = 'da_sua', xu_ly_boi = auth.uid(), xu_ly_luc = now(),
      ghi_chu_xu_ly = 'Sửa xong: ' || trim(p->>'noi_dung')
    where tai_san_id = t.id and loai = 'hong' and trang_thai = 'cho_xu_ly';
  end if;
  perform app.ghi_ls_tai_san(t.id, v_loai, concat_ws(' – ', trim(p->>'noi_dung'),
    case when coalesce((p->>'chi_phi')::numeric, 0) > 0 then format('chi phí %s đ', to_char((p->>'chi_phi')::numeric, 'FM999G999G999G999')) end,
    case when coalesce((p->>'xong')::boolean, false) then 'đã dùng lại được' end));
  return v_id;
end $$;

create or replace function public.anh_tai_san(p_id bigint, p_duong_dan text) returns void
language plpgsql security definer set search_path = public as $$
declare t public.tai_san;
begin
  select * into t from public.tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy tài sản.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if p_duong_dan is null or p_duong_dan not like t.chi_nhanh_id || '/tai-san/%' then raise exception 'Đường dẫn ảnh không đúng.'; end if;
  update public.tai_san set anh = p_duong_dan where id = p_id;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.luu_tai_san(jsonb)', 'public.chuyen_nhom_tai_san(bigint, text, text)', 'public.xac_nhan_nhan_tai_san(jsonb)',
    'public.luu_kiem_tra_tai_san(jsonb)', 'public.bao_su_co_tai_san(jsonb)', 'public.xu_ly_su_co_tai_san(jsonb)',
    'public.danh_dau_boi_thuong(bigint, boolean)', 'public.thanh_ly_tai_san(bigint, text)', 'public.luu_lich_bao_duong(jsonb)',
    'public.ghi_bao_duong(jsonb)', 'public.anh_tai_san(bigint, text)',
    'app.to_cua_toi()', 'app.xem_nhom_tai_san(text, text)', 'app.phu_trach_nhom(text)', 'app.yeu_cau_quan_ly_tai_san()']
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
-- Hàm nội bộ: chỉ gọi từ trong các hàm trên
revoke execute on function app.ghi_ls_tai_san(bigint, text, text, text, text), app.them_nhom_tai_san_cho_to() from public, anon, authenticated;

-- Xuất Excel tài sản (chỉ giám đốc, ghi nhật ký xuất file)
alter table public.nhat_ky_xuat_file drop constraint if exists nhat_ky_xuat_file_loai_check;
alter table public.nhat_ky_xuat_file add constraint nhat_ky_xuat_file_loai_check check (loai in ('kho','khach_hang','tai_san'));
create or replace function public.xuat_du_lieu_tai_san(p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_ts jsonb; v_sc jsonb;
begin
  perform app.yeu_cau('giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  select coalesce(jsonb_agg(jsonb_build_object(
      'ma', t.ma, 'ten', t.ten, 'loai', t.loai, 'nhom', n.ten, 'thu_tu', n.thu_tu, 'so_luong', t.so_luong, 'don_vi', t.don_vi,
      'hang_model', t.hang_model, 'so_serial', t.so_serial, 'gia_mua', t.gia_mua, 'gia_tri', t.gia_mua * t.so_luong,
      'ngay_mua', t.ngay_mua, 'bao_hanh_den', t.bao_hanh_den, 'vi_tri', t.vi_tri, 'tinh_trang', t.tinh_trang,
      'han_bao_duong', (select min(coalesce(l.lan_cuoi, l.bat_dau) + l.chu_ky_ngay) from public.lich_bao_duong l where l.tai_san_id = t.id and l.hoat_dong),
      'kiem_tra_cuoi', (select max(k.ngay) from public.kiem_tra_tai_san_dong d join public.kiem_tra_tai_san k on k.id = d.kiem_tra_id where d.tai_san_id = t.id),
      'ghi_chu', t.ghi_chu) order by n.thu_tu, t.ma), '[]'::jsonb)
    into v_ts
  from public.tai_san t join public.nhom_tai_san n on n.id = t.nhom_id
  where t.chi_nhanh_id = v_cn;
  select coalesce(jsonb_agg(jsonb_build_object(
      'ngay', s.phat_hien_luc, 'ma', t.ma, 'ten', t.ten, 'nhom', n.ten, 'loai', s.loai, 'so_luong', s.so_luong, 'mo_ta', s.mo_ta,
      'trang_thai', s.trang_thai, 'ket_qua', s.ket_qua, 'nguoi_chiu', s.nguoi_chiu_ten, 'boi_thuong', s.boi_thuong, 'da_tru', s.da_tru)
      order by s.phat_hien_luc desc), '[]'::jsonb)
    into v_sc
  from public.su_co_tai_san s join public.tai_san t on t.id = s.tai_san_id join public.nhom_tai_san n on n.id = t.nhom_id
  where s.chi_nhanh_id = v_cn;
  insert into public.nhat_ky_xuat_file (nguoi, loai, chi_nhanh_id, so_dong) values (auth.uid(), 'tai_san', v_cn, jsonb_array_length(v_ts));
  return jsonb_build_object('chi_nhanh', (select ten from public.chi_nhanh where id = v_cn), 'luc', now(), 'tai_san', v_ts, 'su_co', v_sc);
end $$;
revoke execute on function public.xuat_du_lieu_tai_san(text) from public, anon;
grant execute on function public.xuat_du_lieu_tai_san(text) to authenticated;
