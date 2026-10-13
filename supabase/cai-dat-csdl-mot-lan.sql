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

-- ===================== 006_han_bh_than_vo.sql =====================
-- =====================================================================
-- 006 (12/10/2026): Hai ngày hết hạn bảo hiểm của xe
--   han_bao_hiem   = hạn bảo hiểm TNDS (bắt buộc)   – cột cũ, giữ nguyên
--   han_bh_than_vo = hạn bảo hiểm thân vỏ            – cột mới
-- Chỉ THÊM cột và nhận thêm khóa mới: giao diện cũ vẫn chạy bình thường.
-- Chạy một lần trong Supabase > SQL Editor.
-- =====================================================================

alter table public.xe    add column if not exists han_bh_than_vo date;
alter table public.ho_so add column if not exists han_bh_than_vo date;
comment on column public.xe.han_bao_hiem is 'Hạn bảo hiểm TNDS';
comment on column public.xe.han_bh_than_vo is 'Hạn bảo hiểm thân vỏ';
comment on column public.ho_so.han_bao_hiem is 'Hạn bảo hiểm TNDS tại lúc nhận xe';
comment on column public.ho_so.han_bh_than_vo is 'Hạn bảo hiểm thân vỏ tại lúc nhận xe';

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
    if (p->>'han_bao_hiem') is null then raise exception 'Thiếu ngày hết hạn bảo hiểm TNDS.'; end if;
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
    hang_bh_id, van_phong_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'van_phong_bh_id')::bigint end,
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
    van_phong_bh_id = case when p ? 'van_phong_bh_id' then (p->>'van_phong_bh_id')::bigint else van_phong_bh_id end,
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
                         'van_phong_bh_id', h.van_phong_bh_id, 'gdv_id', h.gdv_id)
                       from public.ho_so h where h.xe_id = x.id order by h.id desc limit 1))
  into r
  from public.xe x
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.khach_hang k on k.id = x.khach_hang_id
  where x.bien_so = v_bs;
  return r;
end $$;

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
  t.bh_duyet, t.khach_duyet, t.phai_thu_bh, t.phai_thu_khach, t.da_thu_bh, t.da_thu_khach, t.con_no_bh, t.con_no_khach,
  h.han_bh_than_vo
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.van_phong_bao_hiem vp on vp.id = h.van_phong_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
cross join lateral public.tien_ho_so(h.id) t;

-- =====================================================================
-- 007 (12/10/2026): Nới hai quy định bắt buộc
--   1. Ảnh nhận xe không bắt buộc: bỏ kiểm tra "phải có ảnh nhận xe mới lập được báo giá" (luu_bao_gia).
--   2. Xe bảo hiểm có thể không có BH thân vỏ / TNDS: bỏ bắt buộc ngày hết hạn TNDS (tiep_nhan_xe).
--      Phần mềm vẫn bắt nhập ngày, trừ khi CVDV tích "Không có BH thân vỏ" / "Không có BH TNDS".
--   Phần còn lại của hai hàm giữ nguyên.
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
    hang_bh_id, van_phong_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'van_phong_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), auth.uid())
  returning id into v_id;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', 'Tiếp nhận xe');
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

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

-- =====================================================================
-- 010 (12/10/2026): Người thực hiện và người làm bước tiếp theo
--   - Người thực hiện: tự ghi người đăng nhập (đã có trong ho_so_nhat_ky.boi).
--   - Người làm bước tiếp theo: ho_so.nguoi_tiep_theo. Mỗi lần hồ sơ chuyển bước, phần mềm tự giao
--     theo gợi ý (app.goi_y_nguoi_tiep_theo); ở các hộp thoại tiếp nhận, báo giá, duyệt giá người làm
--     chọn lại được (giao_viec ngay sau khi lưu bước đó).
--   - Đổi người giữa chừng: chỉ quản lý chung và giám đốc.
--   - Bước sửa chữa giao theo tổ (trưởng nhóm của tổ được giao từng hạng mục) nên để trống người.
--   Tương thích ngược: chỉ thêm cột, trigger, hàm, bảng xem mới; v_ho_so giữ nguyên.
-- =====================================================================
alter table public.ho_so add column if not exists nguoi_tiep_theo uuid references public.nhan_vien(id);
alter table public.ho_so add column if not exists giao_viec_luc timestamptz;
comment on column public.ho_so.nguoi_tiep_theo is 'Nhân viên được giao làm bước tiếp theo';
create index if not exists ho_so_nguoi_tiep_theo_idx on public.ho_so (nguoi_tiep_theo) where nguoi_tiep_theo is not null;

-- Nhân viên đầu tiên (theo tên) có vai trò này ở chi nhánh của hồ sơ.
-- Chưa có ai đúng vai trò thì giao cho giám đốc – bước nào cũng phải có người cụ thể.
create or replace function app.nhan_vien_dau(p_vai_tro text, p_chi_nhanh text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.nhan_vien
  where hoat_dong and (p_vai_tro = any(vai_tro) or 'giam_doc' = any(vai_tro))
    and (chi_nhanh_id = p_chi_nhanh or chi_nhanh_id is null)
  order by (p_vai_tro = any(vai_tro)) desc, (chi_nhanh_id is null), ho_ten limit 1
$$;

-- Gợi ý người làm bước tiếp theo theo bước hiện tại của hồ sơ
create or replace function app.goi_y_nguoi_tiep_theo(h public.ho_so) returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if h.tu_excel then return null; end if;
  case h.trang_thai
    -- Báo giá, nhập duyệt giá, lập lệnh: CVDV đang làm (người bấm), không thì CVDV tiếp nhận
    when 'tiep_nhan', 'bao_gia', 'da_duyet' then
      return case when app.co_vai_tro('cvdv') then auth.uid()
                  else coalesce((select id from public.nhan_vien where id = h.tao_boi and hoat_dong),
                                app.nhan_vien_dau('cvdv', h.chi_nhanh_id)) end;
    when 'dang_sua' then return null;                                           -- các tổ được giao
    when 'cho_kcs' then return app.nhan_vien_dau('quan_ly', h.chi_nhanh_id);     -- KCS
    when 'dat_kcs' then return app.nhan_vien_dau('ke_toan', h.chi_nhanh_id);     -- thu tiền, giao xe
    when 'da_giao' then
      if h.nguon_tt <> 'khach' and h.gui_hs_ngay is null then
        return app.nhan_vien_dau('ke_toan', h.chi_nhanh_id);                     -- gửi hồ sơ bảo hiểm
      end if;
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;
    when 'da_gui_hs', 'dong' then
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;  -- chăm sóc
    else return null;
  end case;
end $$;

-- Tự giao khi hồ sơ mới tạo, chuyển bước, gửi hồ sơ BH hoặc đã gọi chăm sóc
create or replace function app.tu_giao_viec() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT'
     or new.trang_thai is distinct from old.trang_thai
     or new.gui_hs_ngay is distinct from old.gui_hs_ngay
     or new.cham_soc_luc is distinct from old.cham_soc_luc then
    new.nguoi_tiep_theo := app.goi_y_nguoi_tiep_theo(new);
    new.giao_viec_luc := now();
  end if;
  return new;
end $$;

drop trigger if exists tu_giao_viec on public.ho_so;
create trigger tu_giao_viec before insert or update of trang_thai, gui_hs_ngay, cham_soc_luc on public.ho_so
  for each row execute function app.tu_giao_viec();

-- Giao (hoặc đổi) người làm bước tiếp theo.
--   Quản lý chung, giám đốc: đổi lúc nào cũng được.
--   Người khác: chỉ ngay sau khi chính mình vừa làm một bước của hồ sơ này (trong 15 phút).
create or replace function public.giao_viec(p_ho_so bigint, p_nguoi uuid) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_ten text; v_cuoi public.ho_so_nhat_ky;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai in ('huy') then raise exception 'Hồ sơ đã hủy.'; end if;
  if not app.co_vai_tro('quan_ly','giam_doc') then
    select * into v_cuoi from public.ho_so_nhat_ky where ho_so_id = p_ho_so order by id desc limit 1;
    if v_cuoi.boi is distinct from auth.uid() or v_cuoi.luc < now() - interval '15 minutes' then
      raise exception 'Chỉ quản lý chung hoặc giám đốc được đổi người làm bước tiếp theo.' using errcode = '42501';
    end if;
  end if;
  if p_nguoi is not null then
    select ho_ten into v_ten from public.nhan_vien where id = p_nguoi and hoat_dong;
    if v_ten is null then raise exception 'Nhân viên không tồn tại hoặc đã nghỉ.'; end if;
  end if;
  if h.nguoi_tiep_theo is not distinct from p_nguoi then return; end if;
  update public.ho_so set nguoi_tiep_theo = p_nguoi, giao_viec_luc = now() where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
    case when p_nguoi is null then 'Bỏ giao bước tiếp theo' else 'Giao bước tiếp theo cho ' || v_ten end);
end $$;

revoke execute on function public.giao_viec(bigint, uuid) from public, anon;
grant execute on function public.giao_viec(bigint, uuid) to authenticated;
revoke execute on function app.nhan_vien_dau(text, text), app.goi_y_nguoi_tiep_theo(public.ho_so), app.tu_giao_viec() from public, anon;

-- Ai đang được giao bước tiếp theo của từng hồ sơ (theo quyền xem hồ sơ của người đăng nhập).
-- Đang sửa: tên trưởng nhóm của các tổ đang làm, ví dụ "Đặng Thanh Hận (tổ DS)".
create or replace view public.v_viec_ho_so with (security_invoker = true) as
select h.id as ho_so_id, h.trang_thai, h.nguon_tt, h.nguoi_tiep_theo,
  case when h.trang_thai = 'dang_sua' then (
         select string_agg(distinct coalesce(tn.ho_ten || ' (tổ ' || m.to_id || ')', 'Tổ ' || m.to_id), ', ')
         from public.hang_muc m
         left join lateral (select t.ho_ten from public.nhan_vien t
                            where t.hoat_dong and 'truong_nhom' = any(t.vai_tro) and t.to_id = m.to_id
                            order by t.ho_ten limit 1) tn on true
         where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam') and m.to_id is not null)
       else nv.ho_ten end as nguoi_tiep_theo_ten,
  h.giao_viec_luc
from public.ho_so h
left join public.nhan_vien nv on nv.id = h.nguoi_tiep_theo;
grant select on public.v_viec_ho_so to authenticated;
revoke all on public.v_viec_ho_so from anon;

-- Giao sẵn cho các hồ sơ đang mở (hồ sơ chuyển từ Excel thì không)
update public.ho_so h set nguoi_tiep_theo = app.goi_y_nguoi_tiep_theo(h), giao_viec_luc = now()
where not h.tu_excel and h.trang_thai <> 'huy' and h.nguoi_tiep_theo is null;

-- =====================================================================
-- 011 (12/10/2026): Nhóm hạng mục báo giá mới: Đồng, Sơn, Phụ tùng, Detailing
--   Tách "Đồng sơn" thành "Đồng" và "Sơn". Nhóm cũ (dong_son, dmg) vẫn hợp lệ cho các dòng đã có.
--   Tương thích ngược: chỉ nới ràng buộc.
-- =====================================================================
alter table public.hang_muc drop constraint if exists hang_muc_nhom_check;
alter table public.hang_muc add constraint hang_muc_nhom_check
  check (nhom in ('dong','son','phu_tung','detailing','dong_son','dmg'));

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

-- ======================= 013_xuat_excel.sql =======================
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
