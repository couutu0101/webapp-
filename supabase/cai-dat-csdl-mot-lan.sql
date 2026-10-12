-- Gara Hoàng Sơn – cài đặt cơ sở dữ liệu một lần (gộp 001 → 005). Dán toàn bộ vào Supabase > SQL Editor rồi bấm Run.

-- ===================== 001_bang_du_lieu.sql =====================
-- =====================================================================
-- PHẦN MỀM QUẢN LÝ GARA HOÀNG SƠN – ĐỢT 1
-- 001: Các bảng dữ liệu
-- Chạy lần lượt 001 → 005 trong Supabase > SQL Editor.
-- Tiền lưu bằng số nguyên VND (numeric(14,0)).
-- =====================================================================

create schema if not exists app;   -- hàm nội bộ, không lộ ra API

-- ---------------------------------------------------------------------
-- Chi nhánh, nhân viên, cài đặt
-- ---------------------------------------------------------------------
create table public.chi_nhanh (
  id          text primary key,                 -- 'TK'
  ten         text not null,
  dia_chi     text,
  hoat_dong   boolean not null default true
);

-- Mỗi tài khoản đăng nhập (auth.users) có một hồ sơ nhân viên.
-- vai_tro là mảng vì một người có thể kiêm nhiều việc (anh Duy: cvdv + kho).
create table public.nhan_vien (
  id          uuid primary key references auth.users(id) on delete cascade,
  ho_ten      text not null default '',
  email       text,
  chi_nhanh_id text references public.chi_nhanh(id),
  vai_tro     text[] not null default '{}',
  to_id       text,                              -- tổ của trưởng nhóm: 'DS','DMG','DT'
  hoat_dong   boolean not null default true,
  tao_luc     timestamptz not null default now(),
  constraint vai_tro_hop_le check (vai_tro <@ array['giam_doc','quan_ly','ke_toan','cvdv','kho','truong_nhom','co_dong']::text[])
);

create table public.cai_dat (
  khoa        text primary key,
  gia_tri     jsonb not null,
  mo_ta       text
);

create table public.thue_suat_vat (
  ap_dung_tu  date primary key,
  ty_le       numeric(5,4) not null check (ty_le >= 0 and ty_le < 1)
);

-- ---------------------------------------------------------------------
-- Danh mục
-- ---------------------------------------------------------------------
create table public.hang_bao_hiem (
  id          bigint generated always as identity primary key,
  ten         text not null unique,
  hoat_dong   boolean not null default true
);

create table public.van_phong_bao_hiem (
  id          bigint generated always as identity primary key,
  hang_id     bigint not null references public.hang_bao_hiem(id),
  ten         text not null,
  hoat_dong   boolean not null default true,
  unique (hang_id, ten)
);

create table public.giam_dinh_vien (
  id          bigint generated always as identity primary key,
  ten         text not null,
  hang_id     bigint references public.hang_bao_hiem(id),
  dien_thoai  text,
  la_cho_them boolean not null default false,    -- dòng "GDV mới – chờ thêm"
  hoat_dong   boolean not null default true
);

create table public.hang_xe (
  id          bigint generated always as identity primary key,
  ten         text not null unique
);

create table public.dong_xe (
  id          bigint generated always as identity primary key,
  hang_xe_id  bigint not null references public.hang_xe(id),
  ten         text not null,
  unique (hang_xe_id, ten)
);

create table public.to_thuc_hien (
  id          text primary key,                  -- 'DS','DMG','DT'
  ten         text not null
);

create table public.tai_khoan_quy (
  id          bigint generated always as identity primary key,
  chi_nhanh_id text not null references public.chi_nhanh(id),
  ten         text not null,
  so_du_dau_ky numeric(14,0) not null default 0,
  ngay_dau_ky date not null default current_date,
  hoat_dong   boolean not null default true,     -- TK cá nhân đã khóa: false
  unique (chi_nhanh_id, ten)
);

-- Mục thu / mục chi. tinh_chat quyết định khoản đó có vào lãi lỗ hay không.
create table public.muc_thu_chi (
  id          bigint generated always as identity primary key,
  loai        text not null check (loai in ('thu','chi')),
  ten         text not null,
  nhom        text,                               -- chi: 'gia_von','co_dinh','van_hanh'
  tinh_chat   text not null check (tinh_chat in (
                 -- thu
                 'thu_khach','thu_bao_hiem','thu_coc','thu_dich_vu_nhanh','thu_khac','thu_noi_bo',
                 -- chi
                 'chi_phi','tra_ncc','tra_hoa_hong','tra_luong','tam_ung','tra_noi_bo','tra_coc','nop_thue')),
  can_ho_so   boolean not null default false,     -- bắt buộc gắn hồ sơ xe
  hoat_dong   boolean not null default true,
  unique (loai, ten)
);

create table public.nha_cung_cap (
  id          bigint generated always as identity primary key,
  ten         text not null unique,
  hoat_dong   boolean not null default true
);

create table public.don_vi_lien_quan (
  id          bigint generated always as identity primary key,
  ten         text not null unique                -- PHI, DTM, GI
);

-- ---------------------------------------------------------------------
-- Khách hàng và xe (tầng dùng chung cho mọi chi nhánh)
-- ---------------------------------------------------------------------
create table public.khach_hang (
  id          bigint generated always as identity primary key,
  ten         text not null,
  dien_thoai  text unique check (dien_thoai ~ '^0[0-9]{9}$'),
  tao_luc     timestamptz not null default now()
);

create table public.xe (
  id          bigint generated always as identity primary key,
  bien_so     text unique,                        -- dạng gọn: 50H92361 (null nếu chưa có biển)
  dong_xe_id  bigint references public.dong_xe(id),
  mau         text,
  khach_hang_id bigint references public.khach_hang(id),
  han_bao_hiem date,
  tao_luc     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Hồ sơ xe (lệnh sửa chữa)
-- ---------------------------------------------------------------------
create table public.ho_so (
  id              bigint generated always as identity primary key,
  ma              text not null unique,           -- TK-2610-50H92361
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  loai            text not null default 'sua_chua' check (loai in ('sua_chua','bao_hanh')),
  ho_so_goc_id    bigint references public.ho_so(id),   -- hồ sơ bảo hành trỏ về hồ sơ cũ
  xe_id           bigint not null references public.xe(id),
  khach_hang_id   bigint not null references public.khach_hang(id),
  ngay_vao        timestamptz not null default now(),
  nguon_tt        text not null check (nguon_tt in ('bao_hiem','khach','bao_hiem_khach')),
  hang_bh_id      bigint references public.hang_bao_hiem(id),
  van_phong_bh_id bigint references public.van_phong_bao_hiem(id),
  gdv_id          bigint references public.giam_dinh_vien(id),
  gdv_ten_tam     text,                           -- tên GDV khi chọn "GDV mới – chờ thêm"
  han_bao_hiem    date,
  tinh_trang_xe   text not null,
  tu_van          text not null,
  trang_thai      text not null default 'tiep_nhan' check (trang_thai in (
                    'tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs',
                    'da_giao','da_gui_hs','dong','huy')),
  hen_giao        timestamptz,
  khau_tru_giam_tru numeric(14,0) not null default 0 check (khau_tru_giam_tru >= 0),
  giam_gia        numeric(14,0) not null default 0 check (giam_gia >= 0),
  giam_gia_ngay   date,
  giam_gia_duyet_boi uuid references auth.users(id),
  so_hd_bao_hiem  text,
  so_hd_khach     text,
  cho_giao_no_boi uuid references auth.users(id), -- người duyệt giao xe khi khách còn nợ
  giao_luc        timestamptz,
  cam_nhan_khach  text,
  gui_hs_ngay     date,
  hoa_hong_gdv    numeric(14,0) check (hoa_hong_gdv >= 0),   -- kế toán tính tay rồi nhập
  hoa_hong_ghi_chu text,
  cham_soc_luc    timestamptz,
  cham_soc_ket_qua text,
  hen_bao_duong   date,
  ly_do_huy       text,
  tu_excel        boolean not null default false, -- hồ sơ chuyển từ Excel: không tính lại doanh thu
  tao_boi         uuid references auth.users(id),
  tao_luc         timestamptz not null default now(),
  cap_nhat_luc    timestamptz not null default now()
);
create index on public.ho_so (chi_nhanh_id, trang_thai);
create index on public.ho_so (xe_id);

-- Dòng hạng mục của báo giá. lan_bao_gia: 0 = gốc, 1,2… = bổ sung (phát sinh)
create table public.hang_muc (
  id              bigint generated always as identity primary key,
  ho_so_id        bigint not null references public.ho_so(id) on delete cascade,
  lan_bao_gia     int not null default 0,
  ten             text not null,
  nhom            text not null check (nhom in ('dong_son','phu_tung','dmg','detailing')),
  nguoi_tra       text not null check (nguoi_tra in ('bao_hiem','khach')),
  gia_bao         numeric(14,0) not null check (gia_bao >= 0),     -- chưa VAT
  gia_duyet       numeric(14,0) check (gia_duyet >= 0),             -- chưa VAT
  xuat_hd         boolean not null default true,  -- dòng có xuất hóa đơn (BH luôn true)
  ngay_duyet      date,                           -- quyết định tháng ghi doanh thu
  trang_thai      text not null default 'cho_duyet' check (trang_thai in ('cho_duyet','duyet','tu_choi','dang_lam','xong')),
  to_id           text references public.to_thuc_hien(id),
  nguoi_lam       text,
  xong_luc        timestamptz
);
create index on public.hang_muc (ho_so_id);

create table public.ho_so_nhat_ky (
  id          bigint generated always as identity primary key,
  ho_so_id    bigint not null references public.ho_so(id) on delete cascade,
  luc         timestamptz not null default now(),
  boi         uuid,
  tu_trang_thai text,
  sang_trang_thai text,
  ghi_chu     text
);

create table public.ho_so_tep (
  id          bigint generated always as identity primary key,
  ho_so_id    bigint not null references public.ho_so(id) on delete cascade,
  buoc        text not null,                      -- 'tiep_nhan','duyet_gia','kcs','giao_xe','ho_so_bh',...
  loai        text,                               -- 'anh','bien_ban','bao_gia',...
  duong_dan   text not null,                      -- đường dẫn trong kho lưu trữ 'ho-so-xe'
  tai_boi     uuid,
  tai_luc     timestamptz not null default now()
);

-- Trưởng nhóm báo hư hỏng phát sinh; CVDV lập báo giá bổ sung rồi đánh dấu đã xử lý
create table public.phat_sinh (
  id          bigint generated always as identity primary key,
  ho_so_id    bigint not null references public.ho_so(id) on delete cascade,
  mo_ta       text not null,
  boi         uuid,
  luc         timestamptz not null default now(),
  da_xu_ly    boolean not null default false
);

create table public.kcs (
  id          bigint generated always as identity primary key,
  ho_so_id    bigint not null references public.ho_so(id) on delete cascade,
  dat         boolean not null,
  loi         text,
  boi         uuid,
  luc         timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Dịch vụ nhanh (rửa xe, vá lốp…): không đi qua 10 bước
-- ---------------------------------------------------------------------
create table public.dich_vu_nhanh (
  id          bigint generated always as identity primary key,
  chi_nhanh_id text not null references public.chi_nhanh(id),
  ngay        date not null default current_date,
  bien_so     text,
  dich_vu     text not null,
  nguoi_lam   text,
  so_tien     numeric(14,0) not null check (so_tien > 0),   -- tiền khách trả
  xuat_hd     boolean not null default false,
  trang_thai  text not null default 'hieu_luc' check (trang_thai in ('hieu_luc','huy')),
  tao_boi     uuid,
  tao_luc     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Thu chi
-- ---------------------------------------------------------------------
create table public.de_nghi_chi (
  id          bigint generated always as identity primary key,
  chi_nhanh_id text not null references public.chi_nhanh(id),
  ngay        date not null default current_date,
  nguoi_de_nghi uuid not null references auth.users(id),
  muc_id      bigint not null references public.muc_thu_chi(id),
  so_tien     numeric(14,0) not null check (so_tien > 0),
  vat_dau_vao numeric(14,0) not null default 0 check (vat_dau_vao >= 0),  -- VAT trong hóa đơn mua (đã gồm trong số tiền)
  noi_dung    text not null,
  nguoi_nhan  text,
  ho_so_id    bigint references public.ho_so(id),
  nha_cung_cap_id bigint references public.nha_cung_cap(id),
  gdv_id      bigint references public.giam_dinh_vien(id),
  don_vi_lien_quan_id bigint references public.don_vi_lien_quan(id),
  trang_thai  text not null default 'cho_duyet' check (trang_thai in ('cho_duyet','da_duyet','tu_choi','da_chi','huy')),
  duyet_boi   uuid references auth.users(id),
  duyet_luc   timestamptz,
  ly_do_tu_choi text,
  tao_luc     timestamptz not null default now()
);

create table public.phieu_thu_chi (
  id          bigint generated always as identity primary key,
  chi_nhanh_id text not null references public.chi_nhanh(id),
  ngay        date not null default current_date,
  loai        text not null check (loai in ('thu','chi','chuyen')),
  tai_khoan_id bigint not null references public.tai_khoan_quy(id),
  tai_khoan_den_id bigint references public.tai_khoan_quy(id),   -- chỉ cho 'chuyen'
  muc_id      bigint references public.muc_thu_chi(id),           -- null cho 'chuyen'
  so_tien     numeric(14,0) not null check (so_tien > 0),
  vat_dau_vao numeric(14,0) not null default 0 check (vat_dau_vao >= 0),
  noi_dung    text,
  hang_bh_id  bigint references public.hang_bao_hiem(id),
  nha_cung_cap_id bigint references public.nha_cung_cap(id),
  gdv_id      bigint references public.giam_dinh_vien(id),
  don_vi_lien_quan_id bigint references public.don_vi_lien_quan(id),
  de_nghi_chi_id bigint unique references public.de_nghi_chi(id),
  trang_thai  text not null default 'hieu_luc' check (trang_thai in ('hieu_luc','huy')),
  ly_do_huy   text,
  tao_boi     uuid,
  tao_luc     timestamptz not null default now(),
  constraint chuyen_hop_le check (
    (loai = 'chuyen' and tai_khoan_den_id is not null and tai_khoan_den_id <> tai_khoan_id and muc_id is null)
    or (loai <> 'chuyen' and tai_khoan_den_id is null and muc_id is not null))
);
create index on public.phieu_thu_chi (chi_nhanh_id, ngay);

-- Phân bổ tiền vào từng hồ sơ / dịch vụ nhanh.
-- Phiếu thu: phân bổ làm giảm nợ. Phiếu chi trả cọc: phân bổ âm vào phần khách.
create table public.phan_bo (
  id          bigint generated always as identity primary key,
  phieu_id    bigint not null references public.phieu_thu_chi(id) on delete cascade,
  ho_so_id    bigint references public.ho_so(id),
  dich_vu_nhanh_id bigint references public.dich_vu_nhanh(id),
  nguoi_tra   text not null check (nguoi_tra in ('bao_hiem','khach')),
  so_tien     numeric(14,0) not null check (so_tien > 0),
  constraint mot_dich check ((ho_so_id is null) <> (dich_vu_nhanh_id is null))
);
create index on public.phan_bo (ho_so_id);

-- Kiểm quỹ cuối ngày: số đếm thực tế so với số trên sổ
create table public.kiem_quy (
  id          bigint generated always as identity primary key,
  chi_nhanh_id text not null references public.chi_nhanh(id),
  tai_khoan_id bigint not null references public.tai_khoan_quy(id),
  ngay        date not null default current_date,
  so_dem      numeric(14,0) not null,
  so_tren_so  numeric(14,0) not null,
  chenh_lech  numeric(14,0) generated always as (so_dem - so_tren_so) stored,
  ghi_chu     text,
  boi         uuid,
  luc         timestamptz not null default now()
);

-- Tổng bảng lương tháng đã duyệt (lương vẫn làm trên Excel)
create table public.bang_luong_thang (
  chi_nhanh_id text not null references public.chi_nhanh(id),
  thang       date not null check (extract(day from thang) = 1),
  tong_luong  numeric(14,0) not null check (tong_luong >= 0),
  nhap_boi    uuid,
  nhap_luc    timestamptz not null default now(),
  primary key (chi_nhanh_id, thang)
);

-- Khóa sổ tháng
create table public.chot_thang (
  chi_nhanh_id text not null references public.chi_nhanh(id),
  thang       date not null check (extract(day from thang) = 1),
  chot_boi    uuid,
  chot_luc    timestamptz not null default now(),
  so_lieu     jsonb,                              -- ảnh chụp số liệu lúc chốt (dùng cho cổ đông)
  primary key (chi_nhanh_id, thang)
);

-- ===================== 002_ham_nghiep_vu.sql =====================
-- =====================================================================
-- 002: Hàm nghiệp vụ
-- Mọi thao tác ghi dữ liệu nghiệp vụ đi qua các hàm này (security definer),
-- nên quy tắc khóa bước, phân quyền và khóa sổ luôn được kiểm tra ở máy chủ,
-- không phụ thuộc giao diện.
-- Lỗi trả về bằng tiếng Việt. Lỗi bắt đầu bằng "CANH_BAO:" là cảnh báo:
-- giao diện hỏi lại người dùng, đồng ý thì gửi lại với bo_qua_canh_bao = true.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Hàm nội bộ
-- ---------------------------------------------------------------------
create or replace function app.vai_tro() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce((select vai_tro from public.nhan_vien where id = auth.uid() and hoat_dong), '{}'::text[])
$$;

create or replace function app.co_vai_tro(variadic ds text[]) returns boolean
language sql stable as $$ select app.vai_tro() && ds $$;

create or replace function app.la_nhan_vien() returns boolean
language sql stable as $$
  select app.vai_tro() && array['giam_doc','quan_ly','ke_toan','cvdv','kho']
$$;

create or replace function app.chi_nhanh() returns text
language sql stable security definer set search_path = public as $$
  select chi_nhanh_id from public.nhan_vien where id = auth.uid() and hoat_dong
$$;

create or replace function app.duoc_xem_chi_nhanh(cn text) returns boolean
language sql stable as $$
  select app.co_vai_tro('giam_doc') or cn = app.chi_nhanh()
$$;

create or replace function app.yeu_cau(variadic ds text[]) returns void
language plpgsql stable as $$
begin
  if auth.uid() is null then
    raise exception 'Bạn chưa đăng nhập.' using errcode = '42501';
  end if;
  if not (app.vai_tro() && ds) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501';
  end if;
end $$;

create or replace function app.yeu_cau_chi_nhanh(cn text) returns void
language plpgsql stable as $$
begin
  if not app.duoc_xem_chi_nhanh(cn) then
    raise exception 'Bạn không thuộc chi nhánh %.', cn using errcode = '42501';
  end if;
end $$;

create or replace function app.cai_dat_so(k text, mac_dinh numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (gia_tri #>> '{}')::numeric from public.cai_dat where khoa = k), mac_dinh)
$$;

create or replace function app.thang_da_chot(cn text, d date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chot_thang
                 where chi_nhanh_id = cn and thang = date_trunc('month', d)::date)
$$;

create or replace function app.yeu_cau_thang_mo(cn text, d date) returns void
language plpgsql stable as $$
begin
  if app.thang_da_chot(cn, d) then
    raise exception 'Tháng %/% đã chốt sổ, không ghi hay sửa được. Hãy ghi điều chỉnh vào tháng đang mở.',
      extract(month from d), extract(year from d);
  end if;
end $$;

create or replace function public.vat_ty_le(d date) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select ty_le from public.thue_suat_vat where ap_dung_tu <= d
                   order by ap_dung_tu desc limit 1), 0)
$$;

-- Tiền có VAT của một dòng (chỉ dòng xuất hóa đơn mới cộng VAT)
create or replace function public.tien_co_vat(so_tien numeric, xuat_hd boolean, ngay date) returns numeric
language sql stable as $$
  select case when so_tien is null then 0
              when xuat_hd then round(so_tien * (1 + public.vat_ty_le(coalesce(ngay, current_date))))
              else so_tien end
$$;

-- Biển số: '50h - 923.61' -> '50H92361'
create or replace function public.bien_so_gon(bs text) returns text
language sql immutable as $$
  select nullif(regexp_replace(upper(coalesce(bs,'')), '[^0-9A-Z]', '', 'g'), '')
$$;

-- '50H92361' -> '50H-923.61' ; '51B12345' -> '51B-123.45' ; '51D1234' -> '51D-1234'
create or replace function public.bien_so_hien_thi(bs text) returns text
language plpgsql immutable as $$
declare m text[];
begin
  if bs is null then return null; end if;
  -- ưu tiên dạng xe ô tô: 2 số + 1–2 chữ + 4–5 số (50H-923.61); sau đó dạng có số trong sê-ri (59X1-123.45)
  m := regexp_match(bs, '^([0-9]{2}[A-Z]{1,2})([0-9]{4,5})$');
  if m is null then m := regexp_match(bs, '^([0-9]{2}[A-Z]{1,2}[0-9])([0-9]{4,5})$'); end if;
  if m is null then return bs; end if;
  if length(m[2]) = 5 then
    return m[1] || '-' || substr(m[2],1,3) || '.' || substr(m[2],4,2);
  end if;
  return m[1] || '-' || m[2];
end $$;

-- 1234567 -> '1.234.567'
create or replace function app.vnd(n numeric) returns text
language sql immutable as $$ select replace(to_char(coalesce(n,0), 'FM999G999G999G990'), ',', '.') $$;

create or replace function app.ghi_nhat_ky(p_ho_so bigint, p_tu text, p_sang text, p_ghi_chu text) returns void
language sql security definer set search_path = public as $$
  insert into public.ho_so_nhat_ky (ho_so_id, boi, tu_trang_thai, sang_trang_thai, ghi_chu)
  values (p_ho_so, auth.uid(), p_tu, p_sang, p_ghi_chu)
$$;

create or replace function app.doi_trang_thai(p_ho_so bigint, p_sang text, p_ghi_chu text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_tu text;
begin
  select trang_thai into v_tu from public.ho_so where id = p_ho_so for update;
  if v_tu is distinct from p_sang then
    update public.ho_so set trang_thai = p_sang, cap_nhat_luc = now() where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, v_tu, p_sang, p_ghi_chu);
  end if;
end $$;

-- Lấy hồ sơ, khóa dòng, kiểm tra chi nhánh
create or replace function app.lay_ho_so(p_id bigint) returns public.ho_so
language plpgsql security definer set search_path = public as $$
declare r public.ho_so;
begin
  select * into r from public.ho_so where id = p_id for update;
  if not found then raise exception 'Không tìm thấy hồ sơ.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Tiền của một hồ sơ
-- ---------------------------------------------------------------------
create or replace function app.tien_ho_so(p_id bigint)
returns table (
  bh_duyet numeric, khach_duyet numeric, phai_thu_bh numeric, phai_thu_khach numeric,
  da_thu_bh numeric, da_thu_khach numeric, con_no_bh numeric, con_no_khach numeric)
language sql stable security definer set search_path = public as $$
  with d as (
    select
      coalesce(sum(public.tien_co_vat(gia_duyet, true, ngay_duyet)) filter (where nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(public.tien_co_vat(gia_duyet, xuat_hd, ngay_duyet)) filter (where nguoi_tra = 'khach'), 0) as kh
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

-- Bản dùng cho giao diện: chỉ nhân viên văn phòng xem được tiền
create or replace function public.tien_ho_so(p_id bigint)
returns table (
  bh_duyet numeric, khach_duyet numeric, phai_thu_bh numeric, phai_thu_khach numeric,
  da_thu_bh numeric, da_thu_khach numeric, con_no_bh numeric, con_no_khach numeric)
language sql stable security definer set search_path = public as $$
  select * from app.tien_ho_so(p_id) where app.la_nhan_vien()
$$;

-- Tự đóng hồ sơ khi đã giao và hết nợ; tự mở lại nếu phát sinh nợ (ví dụ hủy phiếu thu)
create or replace function app.cap_nhat_dong(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; co_bh boolean;
begin
  select * into h from public.ho_so where id = p_id;
  if h.trang_thai not in ('da_giao','da_gui_hs','dong') then return; end if;
  select * into t from app.tien_ho_so(p_id);
  co_bh := t.phai_thu_bh > 0;
  if t.con_no_bh <= 0 and t.con_no_khach <= 0 and (not co_bh or h.gui_hs_ngay is not null) then
    perform app.doi_trang_thai(p_id, 'dong', 'Tự đóng: đã giao xe và hết công nợ');
  elsif h.trang_thai = 'dong' then
    perform app.doi_trang_thai(p_id,
      case when h.gui_hs_ngay is not null then 'da_gui_hs' else 'da_giao' end,
      'Mở lại: phát sinh công nợ');
  end if;
end $$;

-- =====================================================================
-- BƯỚC 1. TIẾP NHẬN XE
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
    if (p->>'han_bao_hiem') is null then raise exception 'Thiếu ngày hết hạn bảo hiểm.'; end if;
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
        han_bao_hiem = coalesce((p->>'han_bao_hiem')::date, han_bao_hiem)
      where id = v_xe;
    end if;
  end if;
  if v_xe is null then
    insert into public.xe (bien_so, dong_xe_id, mau, khach_hang_id, han_bao_hiem)
    values (v_bs, (p->>'dong_xe_id')::bigint, nullif(trim(p->>'mau'),''), v_kh, (p->>'han_bao_hiem')::date)
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
    hang_bh_id, van_phong_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, tinh_trang_xe, tu_van, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'van_phong_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), auth.uid())
  returning id into v_id;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', 'Tiếp nhận xe');
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

-- Sửa thông tin khách / xe / bảo hiểm trên hồ sơ (CVDV, kế toán, quản lý chung)
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
    van_phong_bh_id = case when p ? 'van_phong_bh_id' then (p->>'van_phong_bh_id')::bigint else van_phong_bh_id end,
    gdv_id          = case when p ? 'gdv_id' then (p->>'gdv_id')::bigint else gdv_id end,
    gdv_ten_tam     = case when p ? 'gdv_id' then case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end else gdv_ten_tam end,
    han_bao_hiem    = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end,
    tinh_trang_xe   = coalesce(nullif(trim(p->>'tinh_trang_xe'),''), tinh_trang_xe),
    tu_van          = coalesce(nullif(trim(p->>'tu_van'),''), tu_van),
    hen_giao        = case when p ? 'hen_giao' then (p->>'hen_giao')::timestamptz else hen_giao end,
    cap_nhat_luc    = now()
  where id = p_id;
  update public.xe set
    dong_xe_id   = case when p ? 'dong_xe_id' then (p->>'dong_xe_id')::bigint else dong_xe_id end,
    mau          = case when p ? 'mau' then nullif(trim(p->>'mau'),'') else mau end,
    han_bao_hiem = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end
  where id = h.xe_id;
  perform app.ghi_nhat_ky(p_id, h.trang_thai, h.trang_thai, 'Sửa thông tin: ' || (select string_agg(k, ', ') from jsonb_object_keys(p) k));
end $$;

-- Ghi nhận tệp (ảnh, biên bản) đã tải lên kho 'ho-so-xe'
create or replace function public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text) returns bigint
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_id bigint;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, p_loai, p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $$;

-- =====================================================================
-- BƯỚC 2. BÁO GIÁ (và báo giá bổ sung khi phát sinh)
-- dong: [{ten, nhom, nguoi_tra, gia_bao, xuat_hd}]
-- =====================================================================
create or replace function public.luu_bao_gia(p_ho_so bigint, dong jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_lan int; d jsonb; v_nguoi text; v_xuat boolean;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if jsonb_typeof(dong) <> 'array' or jsonb_array_length(dong) = 0 then
    raise exception 'Báo giá phải có ít nhất một dòng.'; end if;

  if h.trang_thai in ('tiep_nhan','bao_gia') then
    v_lan := 0;
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'tiep_nhan') then
      raise exception 'Chưa có ảnh nhận xe. Chụp ảnh nhận xe trước khi lập báo giá.';
    end if;
  elsif h.trang_thai in ('da_duyet','dang_sua','cho_kcs') then
    select coalesce(max(lan_bao_gia), 0) + 1 into v_lan from public.hang_muc where ho_so_id = p_ho_so;
  else
    raise exception 'Hồ sơ đang ở bước "%", không lập báo giá được.', h.trang_thai;
  end if;

  for d in select * from jsonb_array_elements(dong) loop
    v_nguoi := coalesce(d->>'nguoi_tra', case when h.nguon_tt = 'khach' then 'khach' else 'bao_hiem' end);
    if h.nguon_tt = 'khach' and v_nguoi = 'bao_hiem' then
      raise exception 'Xe khách lẻ không có dòng bảo hiểm trả.'; end if;
    if nullif(trim(d->>'ten'),'') is null then raise exception 'Dòng báo giá thiếu tên hạng mục.'; end if;
    if (d->>'gia_bao') is null or (d->>'gia_bao')::numeric < 0 then raise exception 'Dòng "%" thiếu giá.', d->>'ten'; end if;
    v_xuat := case when v_nguoi = 'bao_hiem' then true else coalesce((d->>'xuat_hd')::boolean, false) end;
    insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd)
    values (p_ho_so, v_lan, trim(d->>'ten'), d->>'nhom', v_nguoi, (d->>'gia_bao')::numeric, v_xuat);
  end loop;

  if h.trang_thai = 'tiep_nhan' then
    perform app.doi_trang_thai(p_ho_so, 'bao_gia', 'Lập báo giá');
  elsif v_lan > 0 then
    update public.phat_sinh set da_xu_ly = true where ho_so_id = p_ho_so and not da_xu_ly;
    if h.trang_thai = 'cho_kcs' then
      perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Báo giá bổ sung lần ' || v_lan);
    else
      perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo giá bổ sung lần ' || v_lan);
    end if;
  end if;
  return v_lan;
end $$;

create or replace function public.xoa_hang_muc(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  select * into r from public.hang_muc where id = p_id;
  perform app.lay_ho_so(r.ho_so_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Chỉ xóa được dòng chưa duyệt.'; end if;
  delete from public.hang_muc where id = p_id;
end $$;

-- =====================================================================
-- BƯỚC 3. DUYỆT GIÁ
-- ket_qua: [{id, dong_y: true/false, gia_duyet}]
-- =====================================================================
create or replace function public.duyet_gia(p_ho_so bigint, p_ngay date, ket_qua jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
  if p_ngay is null then raise exception 'Thiếu ngày duyệt.'; end if;
  if p_ngay > current_date then raise exception 'Ngày duyệt không được sau hôm nay.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, p_ngay);

  for d in select * from jsonb_array_elements(ket_qua) loop
    select * into r from public.hang_muc where id = (d->>'id')::bigint and ho_so_id = p_ho_so for update;
    if not found then raise exception 'Dòng báo giá không thuộc hồ sơ này.'; end if;
    if r.trang_thai <> 'cho_duyet' then raise exception 'Dòng "%" đã được xử lý trước đó.', r.ten; end if;
    if coalesce((d->>'dong_y')::boolean, false) then
      if (d->>'gia_duyet') is null or (d->>'gia_duyet')::numeric < 0 then
        raise exception 'Dòng "%" thiếu giá duyệt.', r.ten; end if;
      update public.hang_muc set trang_thai = 'duyet', gia_duyet = (d->>'gia_duyet')::numeric, ngay_duyet = p_ngay
      where id = r.id;
    else
      update public.hang_muc set trang_thai = 'tu_choi', gia_duyet = null, ngay_duyet = p_ngay where id = r.id;
    end if;
  end loop;

  if h.trang_thai = 'bao_gia'
     and not exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'cho_duyet')
     and exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'duyet') then
    perform app.doi_trang_thai(p_ho_so, 'da_duyet', 'Đã duyệt giá ngày ' || to_char(p_ngay, 'DD/MM/YYYY'));
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Duyệt giá ngày ' || to_char(p_ngay, 'DD/MM/YYYY'));
  end if;
end $$;

-- =====================================================================
-- BƯỚC 4. LỆNH SỬA CHỮA
-- phan_cong: [{id, to_id, nguoi_lam}]
-- =====================================================================
create or replace function public.lap_lenh_sua_chua(p_ho_so bigint, p_hen_giao timestamptz, phan_cong jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('da_duyet','dang_sua') then
    raise exception 'Chưa duyệt giá thì chưa lập được lệnh sửa chữa.'; end if;
  if p_hen_giao is null and h.hen_giao is null then raise exception 'Thiếu giờ hẹn giao xe.'; end if;
  if jsonb_typeof(phan_cong) <> 'array' or jsonb_array_length(phan_cong) = 0 then
    raise exception 'Chưa giao hạng mục nào cho tổ.'; end if;

  for d in select * from jsonb_array_elements(phan_cong) loop
    select * into r from public.hang_muc where id = (d->>'id')::bigint and ho_so_id = p_ho_so for update;
    if not found then raise exception 'Dòng không thuộc hồ sơ này.'; end if;
    if r.trang_thai <> 'duyet' then raise exception 'Dòng "%" chưa được duyệt hoặc đã giao.', r.ten; end if;
    if (d->>'to_id') is null then raise exception 'Dòng "%" chưa chọn tổ.', r.ten; end if;
    update public.hang_muc set trang_thai = 'dang_lam', to_id = d->>'to_id', nguoi_lam = nullif(trim(d->>'nguoi_lam'),'')
    where id = r.id;
  end loop;

  update public.ho_so set hen_giao = coalesce(p_hen_giao, hen_giao) where id = p_ho_so;
  if h.trang_thai = 'da_duyet' then
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Lập lệnh sửa chữa');
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Giao thêm hạng mục cho tổ');
  end if;
end $$;

-- =====================================================================
-- BƯỚC 6. SỬA CHỮA: báo xong từng hạng mục, báo phát sinh
-- =====================================================================
create or replace function public.bao_xong_hang_muc(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.hang_muc; h public.ho_so; v_to text;
begin
  select * into r from public.hang_muc where id = p_id for update;
  if not found then raise exception 'Không tìm thấy hạng mục.'; end if;
  if app.co_vai_tro('cvdv','quan_ly','giam_doc') then
    null;
  elsif app.co_vai_tro('truong_nhom') then
    select to_id into v_to from public.nhan_vien where id = auth.uid();
    if r.to_id is distinct from v_to then raise exception 'Hạng mục này không thuộc tổ của bạn.' using errcode = '42501'; end if;
  else
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501';
  end if;
  h := app.lay_ho_so(r.ho_so_id);
  if r.trang_thai <> 'dang_lam' then raise exception 'Hạng mục "%" không ở trạng thái đang làm.', r.ten; end if;
  update public.hang_muc set trang_thai = 'xong', xong_luc = now() where id = p_id;

  if h.trang_thai = 'dang_sua' and not exists (
      select 1 from public.hang_muc where ho_so_id = r.ho_so_id and trang_thai in ('cho_duyet','duyet','dang_lam')) then
    perform app.doi_trang_thai(r.ho_so_id, 'cho_kcs', 'Xong các hạng mục, chờ KCS');
  end if;
end $$;

create or replace function public.bao_phat_sinh(p_ho_so bigint, p_mo_ta text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  if not (app.co_vai_tro('truong_nhom','cvdv','quan_ly','giam_doc')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('dang_sua','cho_kcs') then raise exception 'Xe không ở bước sửa chữa.'; end if;
  if nullif(trim(p_mo_ta),'') is null then raise exception 'Mô tả hư hỏng phát sinh.'; end if;
  insert into public.phat_sinh (ho_so_id, mo_ta, boi) values (p_ho_so, trim(p_mo_ta), auth.uid());
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Báo phát sinh: ' || trim(p_mo_ta));
end $$;

-- Bảng việc cho trưởng nhóm: chỉ xe và hạng mục của tổ mình, không có tiền và SĐT
create or replace function public.bang_viec_to() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select to_id, chi_nhanh_id into v_to, v_cn from public.nhan_vien where id = auth.uid();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ho_so_id', h.id, 'ma', h.ma, 'bien_so', public.bien_so_hien_thi(x.bien_so),
      'xe', concat_ws(' ', hx.ten, dx.ten, x.mau), 'hen_giao', h.hen_giao, 'trang_thai', h.trang_thai,
      'tinh_trang_xe', h.tinh_trang_xe,
      'hang_muc', (select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'nhom', m.nhom, 'to_id', m.to_id,
                     'nguoi_lam', m.nguoi_lam, 'trang_thai', m.trang_thai) order by m.id)
                   from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('dang_lam','xong')
                     and (v_to is null or m.to_id = v_to)))
      order by h.hen_giao nulls last)
    from public.ho_so h
    join public.xe x on x.id = h.xe_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    where h.trang_thai in ('dang_sua','cho_kcs')
      and (app.co_vai_tro('giam_doc') or h.chi_nhanh_id = v_cn)
      and (v_to is null or not app.co_vai_tro('truong_nhom') or exists (
            select 1 from public.hang_muc m where m.ho_so_id = h.id and m.to_id = v_to and m.trang_thai in ('dang_lam','xong')))
  ), '[]'::jsonb);
end $$;

-- =====================================================================
-- BƯỚC 7. KCS
-- =====================================================================
create or replace function public.kcs(p_ho_so bigint, p_dat boolean, p_loi text default null, p_lam_lai bigint[] default null) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'cho_kcs' then raise exception 'Xe chưa sửa xong, chưa KCS được.'; end if;
  insert into public.kcs (ho_so_id, dat, loi, boi) values (p_ho_so, p_dat, nullif(trim(p_loi),''), auth.uid());
  if p_dat then
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'kcs') then
      raise exception 'Chưa có ảnh sau sửa. Chụp ảnh trước khi ký KCS.'; end if;
    perform app.doi_trang_thai(p_ho_so, 'dat_kcs', 'Đạt KCS');
  else
    if nullif(trim(p_loi),'') is null then raise exception 'Ghi lỗi cần làm lại.'; end if;
    if p_lam_lai is null or cardinality(p_lam_lai) = 0 then raise exception 'Chọn hạng mục phải làm lại.'; end if;
    update public.hang_muc set trang_thai = 'dang_lam', xong_luc = null
    where ho_so_id = p_ho_so and id = any(p_lam_lai) and trang_thai = 'xong';
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Chưa đạt KCS: ' || trim(p_loi));
  end if;
end $$;

-- =====================================================================
-- BƯỚC 8. THANH TOÁN, GIAO XE
-- =====================================================================
create or replace function public.duyet_giam_gia(p_ho_so bigint, p_so_tien numeric, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai in ('dong','huy') then raise exception 'Hồ sơ đã đóng.'; end if;
  if p_so_tien < 0 then raise exception 'Số tiền giảm giá không hợp lệ.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do giảm giá.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  if h.giam_gia_ngay is not null then perform app.yeu_cau_thang_mo(h.chi_nhanh_id, h.giam_gia_ngay); end if;
  update public.ho_so set giam_gia = p_so_tien, giam_gia_ngay = current_date, giam_gia_duyet_boi = auth.uid()
  where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Duyệt giảm giá ' || p_so_tien || ' đ: ' || trim(p_ly_do));
end $$;

create or replace function public.duyet_giao_xe_con_no(p_ho_so bigint) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  update public.ho_so set cho_giao_no_boi = auth.uid() where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Duyệt cho giao xe khi khách còn nợ');
end $$;

-- p: {khau_tru_giam_tru, so_hd_bao_hiem, so_hd_khach, cam_nhan_khach}
create or replace function public.giao_xe(p_ho_so bigint, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record;
begin
  perform app.yeu_cau('ke_toan','cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'dat_kcs' then raise exception 'Xe chưa đạt KCS thì không giao được.'; end if;
  if h.nguon_tt = 'khach' and coalesce((p->>'khau_tru_giam_tru')::numeric, 0) > 0 then
    raise exception 'Xe khách lẻ không có khấu trừ – giảm trừ.'; end if;

  update public.ho_so set
    khau_tru_giam_tru = coalesce((p->>'khau_tru_giam_tru')::numeric, khau_tru_giam_tru),
    so_hd_bao_hiem = coalesce(nullif(trim(p->>'so_hd_bao_hiem'),''), so_hd_bao_hiem),
    so_hd_khach = coalesce(nullif(trim(p->>'so_hd_khach'),''), so_hd_khach),
    cam_nhan_khach = coalesce(nullif(trim(p->>'cam_nhan_khach'),''), cam_nhan_khach)
  where id = p_ho_so;

  select * into t from app.tien_ho_so(p_ho_so);
  if t.phai_thu_bh < 0 then raise exception 'Khấu trừ – giảm trừ lớn hơn phần bảo hiểm duyệt.'; end if;
  if t.con_no_khach > 0 and h.cho_giao_no_boi is null then
    raise exception 'Khách còn nợ % đ. Cần giám đốc hoặc quản lý chung duyệt giao xe khi còn nợ.',
      app.vnd(t.con_no_khach);
  end if;

  update public.ho_so set giao_luc = now() where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'da_giao', 'Giao xe');
  perform app.cap_nhat_dong(p_ho_so);
end $$;

-- =====================================================================
-- BƯỚC 9. HỒ SƠ BẢO HIỂM, HOA HỒNG GDV
-- =====================================================================
create or replace function public.gui_ho_so_bh(p_ho_so bigint, p_ngay date) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then raise exception 'Xe khách lẻ không có hồ sơ bảo hiểm.'; end if;
  if h.trang_thai <> 'da_giao' then raise exception 'Chỉ gửi hồ sơ bảo hiểm sau khi đã giao xe.'; end if;
  if p_ngay is null or p_ngay > current_date then raise exception 'Ngày gửi không hợp lệ.'; end if;
  update public.ho_so set gui_hs_ngay = p_ngay where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'da_gui_hs', 'Gửi hồ sơ bảo hiểm ngày ' || to_char(p_ngay, 'DD/MM/YYYY'));
  perform app.cap_nhat_dong(p_ho_so);
end $$;

create or replace function public.nhap_hoa_hong_gdv(p_ho_so bigint, p_so_tien numeric, p_ghi_chu text default null,
  p_bo_qua_canh_bao boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; v_tl numeric := app.cai_dat_so('hoa_hong_canh_bao_ty_le', 0.15);
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.gdv_id is null then raise exception 'Hồ sơ không có giám định viên.'; end if;
  if p_so_tien is null or p_so_tien < 0 then raise exception 'Số tiền hoa hồng không hợp lệ.'; end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.bh_duyet > 0 and p_so_tien > t.bh_duyet * v_tl and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Hoa hồng % đ lớn hơn % giá duyệt bảo hiểm. Kiểm tra lại có gõ thừa số 0 không?',
      app.vnd(p_so_tien), round(v_tl * 100)::text || '%';
  end if;
  update public.ho_so set hoa_hong_gdv = p_so_tien, hoa_hong_ghi_chu = nullif(trim(p_ghi_chu),'') where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Nhập hoa hồng GDV ' || p_so_tien || ' đ');
end $$;

-- =====================================================================
-- BƯỚC 10. CHĂM SÓC SAU GIAO
-- =====================================================================
create or replace function public.ghi_cham_soc(p_ho_so bigint, p_ket_qua text, p_hen_bao_duong date default null) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.giao_luc is null then raise exception 'Xe chưa giao.'; end if;
  if nullif(trim(p_ket_qua),'') is null then raise exception 'Ghi kết quả cuộc gọi.'; end if;
  update public.ho_so set cham_soc_luc = now(), cham_soc_ket_qua = trim(p_ket_qua),
    hen_bao_duong = p_hen_bao_duong where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Gọi chăm sóc: ' || trim(p_ket_qua));
end $$;

-- =====================================================================
-- HỦY HỒ SƠ
-- =====================================================================
create or replace function public.huy_ho_so(p_ho_so bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_ngay date;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('tiep_nhan','bao_gia','da_duyet') then
    raise exception 'Xe đã vào sửa thì không hủy hồ sơ được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  for v_ngay in select distinct ngay_duyet from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'duyet' loop
    perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_ngay);
  end loop;
  update public.hang_muc set trang_thai = 'tu_choi' where ho_so_id = p_ho_so and trang_thai in ('cho_duyet','duyet');
  update public.ho_so set ly_do_huy = trim(p_ly_do) where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'huy', 'Hủy: ' || trim(p_ly_do));
end $$;

-- =====================================================================
-- DỊCH VỤ NHANH
-- =====================================================================
create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi)
  values (v_cn, v_ngay, public.bien_so_gon(p->>'bien_so'), trim(p->>'dich_vu'), nullif(trim(p->>'nguoi_lam'),''),
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.huy_dich_vu_nhanh(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.dich_vu_nhanh;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.dich_vu_nhanh where id = p_id for update;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if exists (select 1 from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
             where pb.dich_vu_nhanh_id = p_id and p.trang_thai = 'hieu_luc') then
    raise exception 'Dịch vụ đã thu tiền. Hủy phiếu thu trước.'; end if;
  update public.dich_vu_nhanh set trang_thai = 'huy' where id = p_id;
end $$;

-- =====================================================================
-- THU CHI
-- =====================================================================
create or replace function app.kiem_tra_tai_khoan(p_tk bigint, p_cn text) returns void
language plpgsql stable security definer set search_path = public as $$
declare r public.tai_khoan_quy;
begin
  select * into r from public.tai_khoan_quy where id = p_tk;
  if not found or r.chi_nhanh_id <> p_cn then raise exception 'Tài khoản quỹ không hợp lệ.'; end if;
  if not r.hoat_dong then raise exception 'Tài khoản "%" đã khóa, không ghi thêm được.', r.ten; end if;
end $$;

-- Phân bổ một phiếu vào các hồ sơ / dịch vụ nhanh, có kiểm tra vượt nợ
create or replace function app.phan_bo_phieu(p_phieu bigint, p_ds jsonb, p_tinh_chat text) returns void
language plpgsql security definer set search_path = public as $$
declare d jsonb; v_ho_so bigint; v_dvn bigint; v_nguoi text; v_tien numeric; t record; v_tong numeric; v_phieu public.phieu_thu_chi;
  v_ds_ho_so bigint[] := '{}';
begin
  select * into v_phieu from public.phieu_thu_chi where id = p_phieu;
  for d in select * from jsonb_array_elements(coalesce(p_ds, '[]'::jsonb)) loop
    v_ho_so := (d->>'ho_so_id')::bigint; v_dvn := (d->>'dich_vu_nhanh_id')::bigint;
    v_tien := (d->>'so_tien')::numeric;
    if v_tien is null or v_tien <= 0 then raise exception 'Số tiền phân bổ phải lớn hơn 0.'; end if;
    if v_ho_so is not null then
      perform app.lay_ho_so(v_ho_so);
      v_nguoi := case p_tinh_chat when 'thu_bao_hiem' then 'bao_hiem' else 'khach' end;
      if p_tinh_chat in ('thu_bao_hiem','thu_khach') then
        select * into t from app.tien_ho_so(v_ho_so);
        if v_nguoi = 'bao_hiem' and v_tien > t.con_no_bh then
          raise exception 'Phân bổ % đ vượt số bảo hiểm còn nợ % đ của hồ sơ.',
            app.vnd(v_tien), app.vnd(t.con_no_bh); end if;
        if v_nguoi = 'khach' and v_tien > t.con_no_khach then
          raise exception 'Thu % đ vượt số khách còn nợ % đ của hồ sơ. Nếu là tiền cọc, chọn mục "Thu cọc".',
            app.vnd(v_tien), app.vnd(t.con_no_khach); end if;
      end if;
      insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (p_phieu, v_ho_so, v_nguoi, v_tien);
      v_ds_ho_so := v_ds_ho_so || v_ho_so;
    elsif v_dvn is not null then
      insert into public.phan_bo (phieu_id, dich_vu_nhanh_id, nguoi_tra, so_tien) values (p_phieu, v_dvn, 'khach', v_tien);
    else
      raise exception 'Dòng phân bổ thiếu hồ sơ.';
    end if;
  end loop;
  select coalesce(sum(so_tien),0) into v_tong from public.phan_bo where phieu_id = p_phieu;
  if v_tong > v_phieu.so_tien then raise exception 'Tổng phân bổ lớn hơn số tiền của phiếu.'; end if;
  perform app.cap_nhat_dong(x) from unnest(v_ds_ho_so) x;
end $$;

-- p: {ngay, tai_khoan_id, muc_id, so_tien, noi_dung, hang_bh_id, don_vi_lien_quan_id, phan_bo:[{ho_so_id|dich_vu_nhanh_id, so_tien}]}
create or replace function public.lap_phieu_thu(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  m public.muc_thu_chi; v_id bigint; v_tong numeric;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'thu' then raise exception 'Chưa chọn mục thu.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if m.tinh_chat = 'thu_bao_hiem' and (p->>'hang_bh_id') is null then raise exception 'Chọn hãng bảo hiểm chuyển tiền.'; end if;
  if m.tinh_chat = 'thu_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;

  select coalesce(sum((x->>'so_tien')::numeric), 0) into v_tong from jsonb_array_elements(coalesce(p->'phan_bo','[]'::jsonb)) x;
  if m.tinh_chat in ('thu_khach','thu_coc','thu_dich_vu_nhanh') and v_tong <> (p->>'so_tien')::numeric then
    raise exception 'Tiền khách trả phải gắn đủ vào hồ sơ xe hoặc dịch vụ (đang gắn % / % đ).',
      app.vnd(v_tong), app.vnd((p->>'so_tien')::numeric);
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung,
    hang_bh_id, don_vi_lien_quan_id, tao_boi)
  values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, m.id, (p->>'so_tien')::numeric, nullif(trim(p->>'noi_dung'),''),
    (p->>'hang_bh_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, auth.uid())
  returning id into v_id;
  perform app.phan_bo_phieu(v_id, p->'phan_bo', m.tinh_chat);
  return v_id;
end $$;

-- Chia tiếp phần chưa phân bổ của phiếu thu bảo hiểm (khi có bảng kê)
create or replace function public.phan_bo_them(p_phieu bigint, p_ds jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; m public.muc_thu_chi;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_phieu for update;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.loai <> 'thu' or r.trang_thai <> 'hieu_luc' then raise exception 'Phiếu không hợp lệ.'; end if;
  select * into m from public.muc_thu_chi where id = r.muc_id;
  perform app.phan_bo_phieu(p_phieu, p_ds, m.tinh_chat);
end $$;

create or replace function public.lap_phieu_chuyen(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_den_id')::bigint, v_cn);
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, tai_khoan_den_id, so_tien, noi_dung, tao_boi)
  values (v_cn, v_ngay, 'chuyen', (p->>'tai_khoan_id')::bigint, (p->>'tai_khoan_den_id')::bigint,
          (p->>'so_tien')::numeric, nullif(trim(p->>'noi_dung'),''), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.huy_phieu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; x bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai = 'huy' then raise exception 'Phiếu đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) where id = p_id;
  if r.de_nghi_chi_id is not null then
    update public.de_nghi_chi set trang_thai = 'da_duyet' where id = r.de_nghi_chi_id;
  end if;
  for x in select distinct ho_so_id from public.phan_bo where phieu_id = p_id and ho_so_id is not null loop
    perform app.cap_nhat_dong(x);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Đề nghị chi → duyệt → chi
-- ---------------------------------------------------------------------
create or replace function public.lap_de_nghi_chi(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); m public.muc_thu_chi; v_id bigint;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'chi' then raise exception 'Chưa chọn mục chi.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if nullif(trim(p->>'noi_dung'),'') is null then raise exception 'Ghi nội dung chi.'; end if;
  if (m.can_ho_so or m.tinh_chat in ('tra_hoa_hong','tra_coc')) and (p->>'ho_so_id') is null then
    raise exception 'Mục "%" phải gắn hồ sơ xe.', m.ten; end if;
  if m.tinh_chat = 'tra_hoa_hong' and (p->>'gdv_id') is null then raise exception 'Chọn giám định viên nhận hoa hồng.'; end if;
  if m.tinh_chat = 'tra_ncc' and (p->>'nha_cung_cap_id') is null then raise exception 'Chọn nhà cung cấp.'; end if;
  if m.tinh_chat = 'tra_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;
  if coalesce((p->>'vat_dau_vao')::numeric, 0) > (p->>'so_tien')::numeric then raise exception 'VAT đầu vào lớn hơn số tiền.'; end if;

  insert into public.de_nghi_chi (chi_nhanh_id, ngay, nguoi_de_nghi, muc_id, so_tien, vat_dau_vao, noi_dung, nguoi_nhan,
    ho_so_id, nha_cung_cap_id, gdv_id, don_vi_lien_quan_id)
  values (v_cn, coalesce((p->>'ngay')::date, current_date), auth.uid(), m.id, (p->>'so_tien')::numeric,
    coalesce((p->>'vat_dau_vao')::numeric, 0), trim(p->>'noi_dung'), nullif(trim(p->>'nguoi_nhan'),''),
    (p->>'ho_so_id')::bigint, (p->>'nha_cung_cap_id')::bigint, (p->>'gdv_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint)
  returning id into v_id;
  return v_id;
end $$;

-- Quản lý chung duyệt đến hạn mức (mặc định 2 triệu), trên mức chỉ giám đốc. Không tự duyệt phiếu mình lập.
create or replace function public.duyet_de_nghi_chi(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; v_muc numeric := app.cai_dat_so('han_muc_chi_quan_ly', 2000000);
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị này đã được xử lý.'; end if;
  if r.nguoi_de_nghi = auth.uid() then raise exception 'Không được tự duyệt đề nghị do mình lập.'; end if;
  if r.so_tien > v_muc and not app.co_vai_tro('giam_doc') then
    raise exception 'Khoản trên % đ chỉ giám đốc được duyệt.', app.vnd(v_muc) using errcode = '42501';
  end if;
  if not p_dong_y and nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.'; end if;
  update public.de_nghi_chi set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
end $$;

create or replace function public.huy_de_nghi_chi(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi;
begin
  select * into r from public.de_nghi_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  if r.nguoi_de_nghi <> auth.uid() and not app.co_vai_tro('giam_doc','ke_toan') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if r.trang_thai not in ('cho_duyet','da_duyet') then raise exception 'Đề nghị đã chi hoặc đã bị từ chối.'; end if;
  update public.de_nghi_chi set trang_thai = 'huy' where id = p_id;
end $$;

create or replace function public.chi_tien(p_de_nghi bigint, p_tai_khoan bigint, p_ngay date default current_date) returns bigint
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; m public.muc_thu_chi; v_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.de_nghi_chi where id = p_de_nghi for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'da_duyet' then raise exception 'Đề nghị chưa được duyệt thì chưa chi được.'; end if;
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, p_ngay);
  if p_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan(p_tai_khoan, r.chi_nhanh_id);
  select * into m from public.muc_thu_chi where id = r.muc_id;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, vat_dau_vao, noi_dung,
    nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, de_nghi_chi_id, tao_boi)
  values (r.chi_nhanh_id, p_ngay, 'chi', p_tai_khoan, r.muc_id, r.so_tien, r.vat_dau_vao,
    concat_ws(' – ', r.noi_dung, r.nguoi_nhan), r.nha_cung_cap_id, r.gdv_id, r.don_vi_lien_quan_id, r.id, auth.uid())
  returning id into v_id;

  if m.tinh_chat = 'tra_coc' then   -- trả lại cọc cho khách: giảm phần khách đã trả
    insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (v_id, r.ho_so_id, 'khach', r.so_tien);
    perform app.cap_nhat_dong(r.ho_so_id);
  end if;
  update public.de_nghi_chi set trang_thai = 'da_chi' where id = p_de_nghi;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Nhân viên, bảng lương
-- ---------------------------------------------------------------------
-- Tạo hồ sơ nhân viên trống khi có tài khoản đăng nhập mới
create or replace function app.tao_nhan_vien_moi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.nhan_vien (id, email, ho_ten)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'ho_ten', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists tao_nhan_vien_moi on auth.users;
create trigger tao_nhan_vien_moi after insert on auth.users for each row execute function app.tao_nhan_vien_moi();

create or replace function public.luu_nhan_vien(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_vt text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(p->'vai_tro') x), '{}');
begin
  perform app.yeu_cau('giam_doc');
  if p_id = auth.uid() and not ('giam_doc' = any(v_vt)) then
    raise exception 'Không tự bỏ quyền giám đốc của chính mình được.'; end if;
  if 'truong_nhom' = any(v_vt) and (p->>'to_id') is null then raise exception 'Trưởng nhóm phải chọn tổ.'; end if;
  if 'co_dong' = any(v_vt) and cardinality(v_vt) > 1 then
    raise exception 'Tài khoản cổ đông chỉ có một vai trò cổ đông.'; end if;
  update public.nhan_vien set
    ho_ten = coalesce(nullif(trim(p->>'ho_ten'),''), ho_ten),
    chi_nhanh_id = p->>'chi_nhanh_id',
    vai_tro = v_vt,
    to_id = p->>'to_id',
    hoat_dong = coalesce((p->>'hoat_dong')::boolean, true)
  where id = p_id;
  if not found then raise exception 'Không tìm thấy tài khoản.'; end if;
end $$;

create or replace function public.nhap_bang_luong(p_thang date, p_tong numeric, p_chi_nhanh text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_thang);
  insert into public.bang_luong_thang (chi_nhanh_id, thang, tong_luong, nhap_boi) values (v_cn, v_thang, p_tong, auth.uid())
  on conflict (chi_nhanh_id, thang) do update set tong_luong = excluded.tong_luong, nhap_boi = excluded.nhap_boi, nhap_luc = now();
end $$;

-- ---------------------------------------------------------------------
-- Tra cứu xe theo biển số khi tiếp nhận: tự điền khách, loại xe; báo hồ sơ đang mở
-- ---------------------------------------------------------------------
create or replace function public.tra_cuu_xe(p_bien_so text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_bs text := public.bien_so_gon(p_bien_so); r jsonb;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if v_bs is null then return null; end if;
  select jsonb_build_object(
    'xe_id', x.id, 'bien_so', public.bien_so_hien_thi(x.bien_so), 'dong_xe_id', x.dong_xe_id,
    'hang_xe_id', dx.hang_xe_id, 'mau', x.mau, 'han_bao_hiem', x.han_bao_hiem,
    'ten_khach', k.ten, 'dien_thoai', k.dien_thoai,
    'so_lan_vao', (select count(*) from public.ho_so h where h.xe_id = x.id),
    'ho_so_mo', (select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'trang_thai', h.trang_thai))
                 from public.ho_so h where h.xe_id = x.id and h.trang_thai not in ('dong','huy')),
    'ho_so_gan_nhat', (select jsonb_build_object('id', h.id, 'ma', h.ma, 'nguon_tt', h.nguon_tt, 'hang_bh_id', h.hang_bh_id,
                         'van_phong_bh_id', h.van_phong_bh_id, 'gdv_id', h.gdv_id)
                       from public.ho_so h where h.xe_id = x.id order by h.id desc limit 1))
  into r
  from public.xe x
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.khach_hang k on k.id = x.khach_hang_id
  where x.bien_so = v_bs;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Kiểm quỹ cuối ngày
-- ---------------------------------------------------------------------
create or replace function public.ghi_kiem_quy(p_tai_khoan bigint, p_so_dem numeric, p_ghi_chu text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare tk public.tai_khoan_quy; v_so numeric; v_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into tk from public.tai_khoan_quy where id = p_tai_khoan;
  if not found then raise exception 'Tài khoản quỹ không hợp lệ.'; end if;
  perform app.yeu_cau_chi_nhanh(tk.chi_nhanh_id);
  if p_so_dem is null or p_so_dem < 0 then raise exception 'Nhập số tiền đếm được.'; end if;
  select so_du into v_so from public.v_so_du_quy where id = p_tai_khoan;
  if p_so_dem <> v_so and nullif(trim(p_ghi_chu),'') is null then
    raise exception 'Lệch % đ so với sổ. Ghi lý do chênh lệch.', app.vnd(p_so_dem - v_so); end if;
  insert into public.kiem_quy (chi_nhanh_id, tai_khoan_id, so_dem, so_tren_so, ghi_chu, boi)
  values (tk.chi_nhanh_id, p_tai_khoan, p_so_dem, v_so, nullif(trim(p_ghi_chu),''), auth.uid()) returning id into v_id;
  return jsonb_build_object('id', v_id, 'so_tren_so', v_so, 'chenh_lech', p_so_dem - v_so);
end $$;

-- ===================== 003_phan_quyen.sql =====================
-- =====================================================================
-- 003: Phân quyền (Row Level Security)
-- Nguyên tắc: mọi bảng bật RLS. Người dùng chỉ ĐỌC trực tiếp theo quyền;
-- GHI dữ liệu nghiệp vụ chỉ qua các hàm ở file 002.
-- Riêng danh mục và cài đặt: giám đốc / kế toán sửa trực tiếp trên màn hình Danh mục.
-- Cổ đông: không đọc được bảng nghiệp vụ nào (trang báo cáo cổ đông làm ở đợt 2).
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'chi_nhanh','nhan_vien','cai_dat','thue_suat_vat','hang_bao_hiem','van_phong_bao_hiem','giam_dinh_vien',
    'hang_xe','dong_xe','to_thuc_hien','tai_khoan_quy','muc_thu_chi','nha_cung_cap','don_vi_lien_quan',
    'khach_hang','xe','ho_so','hang_muc','ho_so_nhat_ky','ho_so_tep','phat_sinh','kcs','dich_vu_nhanh',
    'de_nghi_chi','phieu_thu_chi','phan_bo','kiem_quy','bang_luong_thang','chot_thang']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- Hàm nghiệp vụ: chỉ người đã đăng nhập được gọi
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke all on schema app from public;
grant usage on schema app to authenticated;
revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated;

-- ---------------------------------------------------------------------
-- Ai đọc được gì
-- ---------------------------------------------------------------------
create policy doc on public.chi_nhanh for select to authenticated using (true);

create policy doc on public.nhan_vien for select to authenticated
  using (id = auth.uid() or app.la_nhan_vien());

-- Danh mục, cài đặt: mọi nhân viên (kể cả trưởng nhóm) đọc được
do $$
declare t text;
begin
  foreach t in array array['cai_dat','thue_suat_vat','hang_bao_hiem','van_phong_bao_hiem','giam_dinh_vien',
    'hang_xe','dong_xe','to_thuc_hien','muc_thu_chi','nha_cung_cap','don_vi_lien_quan']
  loop
    execute format($f$create policy doc on public.%I for select to authenticated
      using (app.la_nhan_vien() or app.co_vai_tro('truong_nhom'))$f$, t);
  end loop;
end $$;

-- Danh mục: giám đốc và kế toán thêm / sửa trực tiếp (không xóa, chỉ tắt "hoạt động")
do $$
declare t text;
begin
  foreach t in array array['hang_bao_hiem','van_phong_bao_hiem','giam_dinh_vien','hang_xe','dong_xe',
    'muc_thu_chi','nha_cung_cap','don_vi_lien_quan','tai_khoan_quy']
  loop
    execute format('grant insert, update on public.%I to authenticated', t);
    execute format($f$create policy them on public.%I for insert to authenticated
      with check (app.co_vai_tro('giam_doc','ke_toan'))$f$, t);
    execute format($f$create policy sua on public.%I for update to authenticated
      using (app.co_vai_tro('giam_doc','ke_toan')) with check (app.co_vai_tro('giam_doc','ke_toan'))$f$, t);
  end loop;
end $$;

-- Cài đặt, thuế suất: chỉ giám đốc
grant insert, update on public.cai_dat, public.thue_suat_vat to authenticated;
create policy them on public.cai_dat for insert to authenticated with check (app.co_vai_tro('giam_doc'));
create policy sua on public.cai_dat for update to authenticated using (app.co_vai_tro('giam_doc')) with check (app.co_vai_tro('giam_doc'));
create policy them on public.thue_suat_vat for insert to authenticated with check (app.co_vai_tro('giam_doc'));
create policy sua on public.thue_suat_vat for update to authenticated using (app.co_vai_tro('giam_doc')) with check (app.co_vai_tro('giam_doc'));

-- Tài khoản quỹ: kế toán, giám đốc, quản lý chung xem; đúng chi nhánh
create policy doc on public.tai_khoan_quy for select to authenticated
  using (app.co_vai_tro('giam_doc','ke_toan','quan_ly') and app.duoc_xem_chi_nhanh(chi_nhanh_id));

-- Khách hàng, xe: nhân viên văn phòng (trưởng nhóm không thấy SĐT khách)
create policy doc on public.khach_hang for select to authenticated using (app.la_nhan_vien());
create policy doc on public.xe for select to authenticated using (app.la_nhan_vien());

-- Hồ sơ và các bảng con: nhân viên văn phòng, đúng chi nhánh
create policy doc on public.ho_so for select to authenticated
  using (app.la_nhan_vien() and app.duoc_xem_chi_nhanh(chi_nhanh_id));
do $$
declare t text;
begin
  foreach t in array array['hang_muc','ho_so_nhat_ky','ho_so_tep','phat_sinh','kcs']
  loop
    execute format($f$create policy doc on public.%I for select to authenticated
      using (app.la_nhan_vien() and exists (select 1 from public.ho_so h where h.id = ho_so_id
             and app.duoc_xem_chi_nhanh(h.chi_nhanh_id)))$f$, t);
  end loop;
end $$;

create policy doc on public.dich_vu_nhanh for select to authenticated
  using (app.duoc_xem_chi_nhanh(chi_nhanh_id) and (app.la_nhan_vien() or tao_boi = auth.uid()));

-- Đề nghị chi: người duyệt và kế toán xem hết; người khác xem đề nghị của mình
create policy doc on public.de_nghi_chi for select to authenticated
  using (app.duoc_xem_chi_nhanh(chi_nhanh_id)
         and (app.co_vai_tro('giam_doc','quan_ly','ke_toan') or nguoi_de_nghi = auth.uid()));

-- Sổ quỹ: giám đốc, quản lý chung, kế toán
create policy doc on public.phieu_thu_chi for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.phan_bo for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan')
         and exists (select 1 from public.phieu_thu_chi p where p.id = phieu_id and app.duoc_xem_chi_nhanh(p.chi_nhanh_id)));

create policy doc on public.kiem_quy for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.bang_luong_thang for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));
create policy doc on public.chot_thang for select to authenticated
  using (app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(chi_nhanh_id));

-- ---------------------------------------------------------------------
-- Kho lưu ảnh, biên bản: 'ho-so-xe' (riêng tư)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('ho-so-xe', 'ho-so-xe', false)
on conflict (id) do nothing;

create policy "ho-so-xe doc" on storage.objects for select to authenticated
  using (bucket_id = 'ho-so-xe' and (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')));
create policy "ho-so-xe tai len" on storage.objects for insert to authenticated
  with check (bucket_id = 'ho-so-xe' and (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')));

-- ===================== 004_bang_xem.sql =====================
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

-- ===================== 005_danh_muc_ban_dau.sql =====================
-- =====================================================================
-- 005: Danh mục ban đầu (gom từ các file Excel của Tô Ký, tháng 7–10/2026)
-- Sau khi chạy, giám đốc / kế toán sửa tiếp trên màn hình Danh mục.
-- =====================================================================

insert into public.chi_nhanh (id, ten, dia_chi) values
  ('TK', 'Gara Hoàng Sơn – CN Tô Ký', '331 Tô Ký, xã Hóc Môn, TP.HCM')
on conflict (id) do nothing;

insert into public.to_thuc_hien (id, ten) values
  ('DS', 'Đồng sơn'), ('DMG', 'Điện – máy – gầm'), ('DT', 'Detailing')
on conflict (id) do nothing;

insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('han_muc_chi_quan_ly',     '2000000', 'Quản lý chung duyệt phiếu chi đến mức này; trên mức chỉ giám đốc duyệt'),
  ('muc_can_3_bao_gia',       '5000000', 'Đơn mua từ mức này phải đính kèm 3 báo giá (đợt 2)'),
  ('so_ngay_cho_duyet',       '3',       'Xe bảo hiểm chờ duyệt giá quá số ngày này thì báo giám đốc'),
  ('so_ngay_gui_ho_so',       '3',       'Gửi hồ sơ bảo hiểm trong số ngày này sau khi giao xe'),
  ('so_ngay_nhac_no',         '15',      'Bảo hiểm chưa trả sau số ngày này thì nhắc nợ'),
  ('so_ngay_no_giam_doc',     '30',      'Bảo hiểm chưa trả sau số ngày này thì giám đốc làm việc trực tiếp'),
  ('so_ngay_goi_cham_soc',    '3',       'Gọi hỏi thăm khách sau số ngày này kể từ khi giao xe'),
  ('hoa_hong_canh_bao_ty_le', '0.15',    'Cảnh báo khi hoa hồng GDV lớn hơn tỷ lệ này của giá duyệt bảo hiểm'),
  ('chenh_lech_kiem_ke',      '0.05',    'Chênh lệch kiểm kê trên tỷ lệ này phải lập biên bản (đợt 2)')
on conflict (khoa) do nothing;

-- Thuế suất VAT theo ngày hiệu lực. 8% là mức giảm có thời hạn:
-- khi trở lại 10%, thêm một dòng mới (ví dụ ('2027-01-01', 0.10)), KHÔNG sửa dòng cũ.
insert into public.thue_suat_vat (ap_dung_tu, ty_le) values ('2024-01-01', 0.08)
on conflict do nothing;

insert into public.hang_bao_hiem (ten) values
  ('Tasco'), ('DBV'), ('Bảo Minh'), ('Bảo Việt'), ('BSH'), ('BIC'), ('PTI'), ('PJICO'), ('MIC'), ('PVI'),
  ('VNI'), ('Bảo Long'), ('AAA'), ('Cathay'), ('Hùng Vương')
on conflict (ten) do nothing;

insert into public.van_phong_bao_hiem (hang_id, ten)
select h.id, v.ten from (values
  ('Bảo Minh','BT'), ('Bảo Minh','BN'),
  ('BSH','BT'), ('BSH','MN'), ('BSH','SG'),
  ('AAA','TSN'), ('AAA','TĐ'),
  ('VNI','BT'), ('PJICO','BD')
) v(hang, ten) join public.hang_bao_hiem h on h.ten = v.hang
on conflict do nothing;

insert into public.giam_dinh_vien (ten, hang_id, la_cho_them)
select v.ten, h.id, v.cho from (values
  ('GDV mới – chờ thêm', null, true),
  ('Hảo', 'Tasco', false), ('Sang', 'Tasco', false), ('Hiếu', 'Tasco', false),
  ('Hiếu', 'DBV', false), ('Tín', 'DBV', false), ('Nguyên', 'Cathay', false),
  ('Diệu', null, false), ('Nghĩa', null, false), ('Công Khanh', null, false), ('Hoàng', null, false),
  ('Đức', null, false), ('Cơ', null, false), ('Cường', null, false), ('Thành', null, false),
  ('Quang', null, false), ('Nam', null, false), ('Tâm', null, false), ('Trung Đức', null, false),
  ('Đôn', null, false), ('Luân', null, false)
) v(ten, hang, cho) left join public.hang_bao_hiem h on h.ten = v.hang;

insert into public.hang_xe (ten) values
  ('VinFast'), ('Mitsubishi'), ('Toyota'), ('Mazda'), ('Kia'), ('Hyundai'), ('Mercedes'), ('Ford'),
  ('Isuzu'), ('Thaco'), ('Honda'), ('Khác')
on conflict (ten) do nothing;

insert into public.dong_xe (hang_xe_id, ten)
select h.id, v.ten from (values
  ('VinFast','VF3'), ('VinFast','VF5'), ('VinFast','VF5 Plus'), ('VinFast','VF6'), ('VinFast','VF6 Plus'),
  ('VinFast','VF7'), ('VinFast','VF8'), ('VinFast','VF9'), ('VinFast','VF e34'), ('VinFast','Limo Green'),
  ('VinFast','EC Van'), ('VinFast','Herio'),
  ('Mitsubishi','Xpander'), ('Mitsubishi','Triton'),
  ('Toyota','Innova'), ('Toyota','Fortuner'), ('Toyota','Veloz'), ('Toyota','Vios'),
  ('Mazda','Mazda 2'), ('Mazda','Mazda 3'), ('Mazda','CX-5'),
  ('Kia','Morning'), ('Kia','Seltos'), ('Kia','Carnival'),
  ('Hyundai','Accent'), ('Hyundai','Tucson'),
  ('Mercedes','C-Class'), ('Ford','Ranger'), ('Ford','Everest'), ('Isuzu','D-Max'),
  ('Thaco','Tải Van'), ('Honda','CR-V'), ('Khác','Khác')
) v(hang, ten) join public.hang_xe h on h.ten = v.hang
on conflict do nothing;

insert into public.tai_khoan_quy (chi_nhanh_id, ten, hoat_dong) values
  ('TK', 'Tiền mặt', true),
  ('TK', 'TK công ty (331 331 331 68)', true),
  ('TK', 'LP Bank', true),
  ('TK', 'VCB TK Tiên (đã khóa – chỉ chốt số dư)', false)
on conflict do nothing;

insert into public.muc_thu_chi (loai, ten, nhom, tinh_chat, can_ho_so) values
  -- THU
  ('thu', 'Thu cọc sửa chữa',          null, 'thu_coc',          true),
  ('thu', 'Khách thanh toán sửa chữa', null, 'thu_khach',        true),
  ('thu', 'Bảo hiểm thanh toán',       null, 'thu_bao_hiem',     false),
  ('thu', 'Thu dịch vụ nhanh',         null, 'thu_dich_vu_nhanh',false),
  ('thu', 'Khách mua bảo hiểm',        null, 'thu_khac',         false),
  ('thu', 'Trạm sạc',                  null, 'thu_khac',         false),
  ('thu', 'Thu nội bộ (PHI, DTM, GI)', null, 'thu_noi_bo',       false),
  ('thu', 'Thu khác',                  null, 'thu_khac',         false),
  -- CHI – giá vốn (mua hàng: trả nợ nhà cung cấp; từ đợt 2 giá vốn ghi khi xuất kho)
  ('chi', 'Trả NCC – Phụ tùng VinFast', 'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Phụ tùng ngoài',   'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Vật tư sơn',       'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Vật tư ĐMG',       'gia_von', 'tra_ncc',      false),
  ('chi', 'Trả NCC – Vật tư CSX',       'gia_von', 'tra_ncc',      false),
  ('chi', 'Sửa chữa ngoài',             'gia_von', 'chi_phi',      true),
  ('chi', 'Giao nhận – kéo xe',         'gia_von', 'chi_phi',      false),
  ('chi', 'Hoa hồng bảo hiểm (GDV)',    'gia_von', 'tra_hoa_hong', true),
  -- CHI – cố định
  ('chi', 'Mặt bằng',                       'co_dinh', 'chi_phi',   false),
  ('chi', 'Bảo vệ',                         'co_dinh', 'chi_phi',   false),
  ('chi', 'Trả lương + thưởng',             'co_dinh', 'tra_luong', false),
  ('chi', 'BHXH',                           'co_dinh', 'chi_phi',   false),
  ('chi', 'Điện',                           'co_dinh', 'chi_phi',   false),
  ('chi', 'Internet – quảng cáo – hotline', 'co_dinh', 'chi_phi',   false),
  -- CHI – vận hành
  ('chi', 'Nước',                'van_hanh', 'chi_phi',  false),
  ('chi', 'Rác',                 'van_hanh', 'chi_phi',  false),
  ('chi', 'Cơm',                 'van_hanh', 'chi_phi',  false),
  ('chi', 'Văn phòng phẩm',      'van_hanh', 'chi_phi',  false),
  ('chi', 'Xăng',                'van_hanh', 'chi_phi',  false),
  ('chi', 'Dụng cụ – đồ nghề',   'van_hanh', 'chi_phi',  false),
  ('chi', 'Tiếp khách',          'van_hanh', 'chi_phi',  false),
  ('chi', 'Xây dựng',            'van_hanh', 'chi_phi',  false),
  ('chi', 'Nộp thuế',            'van_hanh', 'nop_thue', false),
  ('chi', 'Chi khác',            'van_hanh', 'chi_phi',  false),
  -- CHI – không vào lãi lỗ
  ('chi', 'Tạm ứng lương',                 null, 'tam_ung',    false),
  ('chi', 'Trả nội bộ (PHI, DTM, GI)',     null, 'tra_noi_bo', false),
  ('chi', 'Trả lại cọc cho khách',         null, 'tra_coc',    true)
on conflict (loai, ten) do nothing;

insert into public.nha_cung_cap (ten) values
  ('Phụ tùng VinFast'), ('Vật tư sơn VTN'), ('VTS Kim Anh'), ('An Việt'), ('Đại Dương'), ('Wurth'),
  ('Sơn Tuyết'), ('Masuma'), ('Huvi'), ('Kính ô tô'), ('Ghế da'), ('Ngôi Sao'), ('OTOTA'), ('BF'),
  ('Kéo xe'), ('Xe độ'), ('Chăm sóc xe'), ('Phụ tùng ngoài')
on conflict (ten) do nothing;

insert into public.don_vi_lien_quan (ten) values ('PHI'), ('DTM'), ('GI')
on conflict (ten) do nothing;
