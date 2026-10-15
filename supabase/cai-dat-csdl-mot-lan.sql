-- Gara Hoàng Sơn – cài đặt cơ sở dữ liệu một lần cho gara mới (gộp 001 → 047, trừ 099 xóa văn phòng bảo hiểm). Dán toàn bộ vào Supabase > SQL Editor rồi bấm Run.

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

-- ======================= 014_data_khach_hang.sql =======================
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
alter table app.nap_tam enable row level security;
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

-- ======================= 015_duyet_mua_ngoai_le.sql =======================
-- =====================================================================
-- 015 (13/10/2026): DUYỆT MUA NGOẠI LỆ – thiếu báo giá cạnh tranh
--   - Đề nghị mua từ ngưỡng (5 triệu) mà chưa đủ 3 báo giá: giám đốc hoặc quản lý chung được
--     "Duyệt ngoại lệ", BẮT BUỘC ghi lý do; phiếu đánh dấu ngoai_le + lý do + người duyệt.
--   - Giám đốc được tự duyệt đề nghị mua do chính mình lập (người khác vẫn không).
--   Tương thích ngược: thêm cột, hàm mới; hàm duyệt cũ giữ tên và tham số.
-- =====================================================================

alter table public.de_nghi_mua add column if not exists ngoai_le boolean not null default false;
alter table public.de_nghi_mua add column if not exists ly_do_ngoai_le text;
comment on column public.de_nghi_mua.ngoai_le is 'Duyệt ngoại lệ khi thiếu báo giá cạnh tranh';

-- Duyệt / từ chối thường: giám đốc được tự duyệt phiếu mình lập
create or replace function public.duyet_de_nghi_mua(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_mua; v_nguong numeric := app.cai_dat_so('nguong_3_bao_gia', 5000000); v_so_bg int;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_mua where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị mua.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị mua này đã được xử lý.'; end if;
  if r.nguoi_lap = auth.uid() and not app.co_vai_tro('giam_doc') then raise exception 'Không được tự duyệt đề nghị mua do mình lập.'; end if;
  if p_dong_y then
    select count(*) into v_so_bg from public.kho_tep where loai = 'de_nghi_mua' and doi_tuong_id = p_id;
    if r.tong_tien >= v_nguong and v_so_bg < 3 then
      raise exception 'Đơn từ % đ phải đính kèm 3 báo giá (đang có %). Thiếu báo giá thì bấm "Duyệt ngoại lệ" và ghi lý do.', app.vnd(v_nguong), v_so_bg;
    end if;
  elsif nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.';
  end if;
  update public.de_nghi_mua set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
  if not p_dong_y then
    update public.de_xuat_dong set cho_mua = false
    where id in (select de_xuat_dong_id from public.de_nghi_mua_dong where de_nghi_id = p_id and de_xuat_dong_id is not null);
  end if;
end $$;

-- Duyệt ngoại lệ khi thiếu báo giá cạnh tranh
create or replace function public.duyet_mua_ngoai_le(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_mua; v_nguong numeric := app.cai_dat_so('nguong_3_bao_gia', 5000000); v_so_bg int;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_mua where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị mua.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị mua này đã được xử lý.'; end if;
  if r.nguoi_lap = auth.uid() and not app.co_vai_tro('giam_doc') then raise exception 'Không được tự duyệt đề nghị mua do mình lập.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do duyệt khi thiếu báo giá cạnh tranh.'; end if;
  select count(*) into v_so_bg from public.kho_tep where loai = 'de_nghi_mua' and doi_tuong_id = p_id;
  if r.tong_tien < v_nguong or v_so_bg >= 3 then
    raise exception 'Đề nghị này không thiếu báo giá – bấm "Duyệt" bình thường.';
  end if;
  update public.de_nghi_mua set trang_thai = 'da_duyet', duyet_boi = auth.uid(), duyet_luc = now(),
    ngoai_le = true, ly_do_ngoai_le = trim(p_ly_do) || ' (có ' || v_so_bg || '/3 báo giá)'
  where id = p_id;
end $$;
revoke execute on function public.duyet_mua_ngoai_le(bigint, text) from public, anon;
grant execute on function public.duyet_mua_ngoai_le(bigint, text) to authenticated;

-- Bảng xem thêm 2 cột mới (d.* phải tạo lại)
drop view if exists public.v_de_nghi_mua;
create view public.v_de_nghi_mua with (security_invoker = true) as
select d.*, n.ten as nha_cung_cap, h.ma as ma_ho_so, nv.ho_ten as nguoi_lap_ten, nd.ho_ten as duyet_boi_ten,
  (select count(*) from public.kho_tep t where t.loai = 'de_nghi_mua' and t.doi_tuong_id = d.id) as so_bao_gia,
  d.tong_tien >= app.cai_dat_so('nguong_3_bao_gia', 5000000) as can_3_bao_gia
from public.de_nghi_mua d
join public.nha_cung_cap n on n.id = d.nha_cung_cap_id
left join public.ho_so h on h.id = d.ho_so_id
left join public.nhan_vien nv on nv.id = d.nguoi_lap
left join public.nhan_vien nd on nd.id = d.duyet_boi;
grant select on public.v_de_nghi_mua to authenticated;
revoke all on public.v_de_nghi_mua from anon;

-- ======================= 016_gd_tu_duyet_chi.sql =======================
-- =====================================================================
-- 016 (13/10/2026): Giám đốc được tự duyệt đề nghị chi do mình lập
--   (giống đề nghị mua – 015). Người khác vẫn không tự duyệt phiếu mình lập.
-- =====================================================================
create or replace function public.duyet_de_nghi_chi(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; v_muc numeric := app.cai_dat_so('han_muc_chi_quan_ly', 2000000);
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị này đã được xử lý.'; end if;
  if r.nguoi_de_nghi = auth.uid() and not app.co_vai_tro('giam_doc') then raise exception 'Không được tự duyệt đề nghị do mình lập.'; end if;
  if r.so_tien > v_muc and not app.co_vai_tro('giam_doc') then
    raise exception 'Khoản trên % đ chỉ giám đốc được duyệt.', app.vnd(v_muc) using errcode = '42501';
  end if;
  if not p_dong_y and nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.'; end if;
  update public.de_nghi_chi set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
end $$;

-- ======================= 017_tai_khoan_nhan_vien.sql =======================
-- =====================================================================
-- 017 (13/10/2026): GIÁM ĐỐC TẠO TÀI KHOẢN NHÂN VIÊN – không cần gửi email mời
--   - Tên đăng nhập = tên + bộ phận (vd duy.cvdv, tien.ketoan, han.dongson). Đăng nhập gõ tên đăng nhập,
--     phần mềm tự ghép thành địa chỉ nội bộ <tên>@nv.autohoangson.com. Giám đốc vẫn đăng nhập bằng email.
--   - Giám đốc: tạo tài khoản + cấp quyền một lần, đặt lại mật khẩu cho mọi tài khoản.
--   - Tài khoản mới / vừa được đặt lại mật khẩu: lần đăng nhập đầu BẮT ĐỔI mật khẩu riêng.
--   Tương thích ngược: thêm cột và hàm mới.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

alter table public.nhan_vien add column if not exists ten_dang_nhap text;
alter table public.nhan_vien add column if not exists phai_doi_mat_khau boolean not null default false;
create unique index if not exists nhan_vien_ten_dang_nhap_key on public.nhan_vien (lower(ten_dang_nhap)) where ten_dang_nhap is not null;

create or replace function app.email_noi_bo(p_ten text) returns text language sql immutable as $$
  select lower(trim(p_ten)) || '@nv.autohoangson.com'
$$;

create or replace function app.kiem_mat_khau(p_mk text) returns void language plpgsql as $$
begin
  if p_mk is null or length(p_mk) < 6 then raise exception 'Mật khẩu cần ít nhất 6 ký tự.'; end if;
end $$;

-- Tạo tài khoản. p: {ho_ten, ten_dang_nhap, mat_khau, chi_nhanh_id, vai_tro: [...], to_id}
create or replace function public.tao_tai_khoan_nhan_vien(p jsonb) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid := gen_random_uuid(); v_ten text := lower(trim(coalesce(p->>'ten_dang_nhap', ''))); v_email text;
  v_vt text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(p->'vai_tro') x), '{}');
begin
  perform app.yeu_cau('giam_doc');
  if nullif(trim(p->>'ho_ten'), '') is null then raise exception 'Nhập họ tên nhân viên.'; end if;
  if v_ten !~ '^[a-z0-9][a-z0-9._-]{1,39}$' then
    raise exception 'Tên đăng nhập chỉ gồm chữ không dấu, số, dấu chấm hoặc gạch (vd: duy.cvdv).'; end if;
  perform app.kiem_mat_khau(p->>'mat_khau');
  if cardinality(v_vt) = 0 then raise exception 'Chọn ít nhất một bộ phận / vai trò.'; end if;
  if 'truong_nhom' = any(v_vt) and nullif(p->>'to_id', '') is null then raise exception 'Trưởng nhóm phải chọn tổ.'; end if;
  if 'co_dong' = any(v_vt) and cardinality(v_vt) > 1 then raise exception 'Tài khoản cổ đông chỉ có một vai trò cổ đông.'; end if;
  v_email := app.email_noi_bo(v_ten);
  if exists (select 1 from auth.users where lower(email) = v_email)
     or exists (select 1 from public.nhan_vien where lower(ten_dang_nhap) = v_ten) then
    raise exception 'Tên đăng nhập "%" đã có người dùng.', v_ten; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
      crypt(p->>'mat_khau', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('ho_ten', trim(p->>'ho_ten')), now(), now(),
      '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text, 'email',
      jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), null, now(), now());

  -- nhan_vien đã được trigger tao_nhan_vien_moi tạo; cấp quyền luôn
  update public.nhan_vien set ho_ten = trim(p->>'ho_ten'), ten_dang_nhap = v_ten,
    chi_nhanh_id = coalesce(nullif(p->>'chi_nhanh_id', ''), app.chi_nhanh()), vai_tro = v_vt,
    to_id = nullif(p->>'to_id', ''), hoat_dong = true, phai_doi_mat_khau = true
  where id = v_id;
  return v_id;
end $$;

-- Giám đốc đặt lại mật khẩu cho bất kỳ tài khoản nào (của người khác: lần đăng nhập sau bắt đổi)
create or replace function public.dat_lai_mat_khau(p_id uuid, p_mat_khau text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform app.yeu_cau('giam_doc');
  perform app.kiem_mat_khau(p_mat_khau);
  update auth.users set encrypted_password = crypt(p_mat_khau, gen_salt('bf')), updated_at = now() where id = p_id;
  if not found then raise exception 'Không tìm thấy tài khoản.'; end if;
  update public.nhan_vien set phai_doi_mat_khau = (p_id <> auth.uid()) where id = p_id;
  -- đăng xuất các máy đang dùng tài khoản đó
  if p_id <> auth.uid() and to_regclass('auth.sessions') is not null then
    execute 'delete from auth.sessions where user_id = $1' using p_id;
  end if;
end $$;

-- Nhân viên đã tự đổi mật khẩu (sau lần đăng nhập đầu)
create or replace function public.da_doi_mat_khau() returns void
language sql security definer set search_path = public as $$
  update public.nhan_vien set phai_doi_mat_khau = false where id = auth.uid()
$$;

revoke execute on function public.tao_tai_khoan_nhan_vien(jsonb) from public, anon;
revoke execute on function public.dat_lai_mat_khau(uuid, text) from public, anon;
revoke execute on function public.da_doi_mat_khau() from public, anon;
grant execute on function public.tao_tai_khoan_nhan_vien(jsonb) to authenticated;
grant execute on function public.dat_lai_mat_khau(uuid, text) to authenticated;
grant execute on function public.da_doi_mat_khau() to authenticated;
revoke execute on function app.email_noi_bo(text) from public, anon;
revoke execute on function app.kiem_mat_khau(text) from public, anon;

-- ======================= 018_han_xu_ly.sql =======================
-- =====================================================================
-- 018 (13/10/2026): HẠN XỬ LÝ TỪNG VIỆC – trang "Việc hôm nay" tô vàng việc quá hạn
--   Mỗi người đăng nhập chỉ thấy việc của mình (bước hồ sơ được giao, phiếu kho / đề nghị chi
--   đang chờ đúng vai trò mình). Hạn tính ở phần mềm theo các cài đặt dưới đây (giám đốc sửa ở Cài đặt).
--   Tương thích ngược: chỉ thêm dòng cài đặt.
-- =====================================================================
insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('so_gio_lap_bao_gia',   '24', 'Lập báo giá trong số giờ này kể từ khi tiếp nhận xe'),
  ('so_gio_lap_lenh',      '24', 'Lập lệnh sửa chữa trong số giờ này kể từ khi duyệt giá'),
  ('so_gio_kcs',           '4',  'KCS trong số giờ này kể từ khi tổ báo xong (nếu chưa tới giờ hẹn giao)'),
  ('so_gio_xuat_vat_tu',   '4',  'Kho xuất vật tư trong số giờ này kể từ khi có đề xuất'),
  ('so_gio_duyet_mua',     '24', 'Duyệt đề nghị mua trong số giờ này kể từ khi lập'),
  ('so_gio_khop_hoa_don',  '48', 'Kế toán khớp hóa đơn phiếu nhập trong số giờ này kể từ khi nhập kho'),
  ('so_gio_duyet_chi',     '24', 'Duyệt đề nghị chi trong số giờ này kể từ khi lập')
on conflict (khoa) do nothing;

-- ======================= 019_xoa_danh_muc.sql =======================
-- =====================================================================
-- 019 (13/10/2026): XÓA DÒNG DANH MỤC
--   Giám đốc, kế toán xóa được dòng danh mục (hãng BH, GDV, hãng xe, dòng xe, mục thu chi, NCC, đơn vị liên quan,
--   tài khoản quỹ, thuế suất VAT) khi dòng đó CHƯA được dùng ở đâu. Đã dùng (có hồ sơ, phiếu… trỏ tới) thì báo
--   và hướng dẫn bỏ chọn "Đang dùng". Cài đặt không xóa.
--   Tương thích ngược: chỉ thêm hàm.
-- =====================================================================
create or replace function public.xoa_danh_muc(p_bang text, p_khoa text) returns void
language plpgsql security definer set search_path = public as $$
declare v_cot text; v_so bigint;
begin
  perform app.yeu_cau('giam_doc', 'ke_toan');
  if p_bang not in ('hang_bao_hiem','giam_dinh_vien','hang_xe','dong_xe','muc_thu_chi','nha_cung_cap',
                    'don_vi_lien_quan','tai_khoan_quy','thue_suat_vat') then
    raise exception 'Không xóa được mục "%".', p_bang;
  end if;
  v_cot := case when p_bang = 'thue_suat_vat' then 'ap_dung_tu' else 'id' end;
  if p_bang = 'thue_suat_vat' and (select count(*) from public.thue_suat_vat) <= 1 then
    raise exception 'Phải còn ít nhất một dòng thuế suất.';
  end if;
  begin
    execute format('delete from public.%I where %I::text = $1', p_bang, v_cot) using p_khoa;
    get diagnostics v_so = row_count;
  exception when foreign_key_violation then
    raise exception 'Mục này đang được dùng (có hồ sơ, phiếu hoặc danh mục khác trỏ tới) nên không xóa được. Bỏ chọn "Đang dùng" để ẩn đi.';
  end;
  if v_so = 0 then raise exception 'Không tìm thấy dòng cần xóa.'; end if;
end $$;
revoke execute on function public.xoa_danh_muc(text, text) from public, anon;
grant execute on function public.xoa_danh_muc(text, text) to authenticated;

-- ======================= 020_duyet_gia_chia_cong_no.sql =======================
-- =====================================================================
-- 020 (13/10/2026): KẾT QUẢ DUYỆT GIÁ CHIA CÔNG NỢ NGAY – xe bảo hiểm
--   Ở hộp "Kết quả duyệt giá" nhập luôn 3 số: Tổng giá duyệt (có VAT) – Bảo hiểm chi trả – Khách hàng chi trả.
--   Phần khách chi trả = các dòng khách tự trả + khấu trừ / giảm trừ của hãng (ho_so.khau_tru_giam_tru).
--   Lưu xong, công nợ tách thành hai: nợ của hãng bảo hiểm và nợ của chủ xe; khi giao xe, phiếu thu hiện nợ khách.
--   Tương thích ngược: hàm duyet_gia cũ giữ nguyên; thêm hàm duyet_gia_chia.
-- =====================================================================
create or replace function public.duyet_gia_chia(p_ho_so bigint, p_ngay date, ket_qua jsonb, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_tong numeric; v_khach_dong numeric; v_khau_tru numeric;
begin
  perform public.duyet_gia(p_ho_so, p_ngay, ket_qua);
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then
    return jsonb_build_object('tong', (select coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)), 0)
      from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong')), 'bao_hiem', 0, 'khach', null);
  end if;
  select coalesce(sum(public.tien_dong_co_vat(gia_duyet, true, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'bao_hiem'), 0)
       + coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0),
       coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0)
    into v_tong, v_khach_dong
  from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong');
  if p_khach_tra is null then p_khach_tra := v_khach_dong + h.khau_tru_giam_tru; end if;
  if p_khach_tra < v_khach_dong then
    raise exception 'Khách chi trả ít nhất % đ (các dòng khách tự trả).', app.vnd(v_khach_dong); end if;
  if p_khach_tra > v_tong then
    raise exception 'Khách chi trả không được vượt tổng giá duyệt % đ.', app.vnd(v_tong); end if;
  v_khau_tru := round(p_khach_tra - v_khach_dong);
  if v_khau_tru <> h.khau_tru_giam_tru then
    update public.ho_so set khau_tru_giam_tru = v_khau_tru where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
      'Chia công nợ: bảo hiểm chi trả ' || app.vnd(v_tong - p_khach_tra) || ' đ, khách chi trả ' || app.vnd(p_khach_tra)
      || ' đ (khấu trừ – giảm trừ ' || app.vnd(v_khau_tru) || ' đ)');
  end if;
  return jsonb_build_object('tong', v_tong, 'bao_hiem', v_tong - p_khach_tra, 'khach', p_khach_tra, 'khau_tru', v_khau_tru);
end $$;
revoke execute on function public.duyet_gia_chia(bigint, date, jsonb, numeric) from public, anon;
grant execute on function public.duyet_gia_chia(bigint, date, jsonb, numeric) to authenticated;

-- ======================= 021_ke_toan_bang_viec.sql =======================
-- =====================================================================
-- 021 (13/10/2026): Kế toán cũng xem được Bảng việc xưởng ở Việc hôm nay (biết xe sắp xong để chuẩn bị thu tiền).
--   Tương thích ngược: chỉ nới quyền gọi hàm.
-- =====================================================================
create or replace function public.bang_viec_to() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','ke_toan','quan_ly','giam_doc') then
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


-- ======================= 022_hen_giao_mac_dinh.sql =======================
-- =====================================================================
-- 022 (13/10/2026): Giờ hẹn giao xe mặc định khi lập lệnh sửa chữa = sau N ngày, 17:00 (người lập sửa lại nếu khác)
-- =====================================================================
insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('so_ngay_hen_giao', '3', 'Lập lệnh sửa chữa: giờ hẹn giao xe mặc định sau số ngày này (17:00), người lập sửa lại được')
on conflict (khoa) do nothing;

-- ======================= 023_tai_khoan_mac_dinh.sql =======================
-- =====================================================================
-- 023 (13/10/2026): Tài khoản quỹ mặc định nhận tiền khi lập phiếu thu (tài khoản công ty).
--   Sửa ở Danh mục → Tài khoản quỹ (tích "Mặc định nhận tiền"). Tương thích ngược: chỉ thêm cột.
-- =====================================================================
alter table public.tai_khoan_quy add column if not exists mac_dinh boolean not null default false;
update public.tai_khoan_quy set mac_dinh = true
where hoat_dong and ten ilike '%công ty%'
  and not exists (select 1 from public.tai_khoan_quy t2 where t2.chi_nhanh_id = tai_khoan_quy.chi_nhanh_id and t2.mac_dinh);

-- ======================= 024_tien_bo.sql =======================
-- =====================================================================
-- 024 (13/10/2026): Khách trả dư / tiền bo.
--   - Mục thu "Tiền bo của khách" (thu khác, không gắn xe) để ghi phần khách cho thêm thợ.
--   - Khách chuyển dư mà không phải tiền bo: phiếu thu gắn đủ vào xe, hồ sơ hiện "Khách trả dư – cần trả lại",
--     kế toán lập đề nghị chi mục "Trả lại cọc cho khách" (gắn xe) để trả lại.
-- =====================================================================
insert into public.muc_thu_chi (loai, ten, nhom, tinh_chat, can_ho_so)
select 'thu', 'Tiền bo của khách', null, 'thu_khac', false
where not exists (select 1 from public.muc_thu_chi where loai = 'thu' and ten = 'Tiền bo của khách');


-- Phiếu thu khách trả dư: p.cho_tra_du = true thì không chặn vượt số còn nợ (phần dư ghi âm vào nợ khách = khách trả dư)
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
  -- Khách trả dư (cho_tra_du = true): gắn đủ vào xe dù vượt số còn nợ → hồ sơ ghi khách trả dư, trả lại sau
  perform app.phan_bo_phieu(v_id, p->'phan_bo', case when m.tinh_chat = 'thu_khach' and coalesce((p->>'cho_tra_du')::boolean, false) then 'thu_khach_du' else m.tinh_chat end);
  return v_id;
end $$;

-- ======================= 025_ket_qua_kinh_doanh.sql =======================
-- =====================================================================
-- 025 (13/10/2026): KẾT QUẢ KINH DOANH THÁNG + CHỐT THÁNG + BÁO CÁO CỔ ĐÔNG
--   Theo chốt với giám đốc 13/10:
--     Doanh thu (sau VAT, theo ngày duyệt giá) − Giá vốn (vật tư xuất kho cho xe theo tháng xuất, vật tư dùng chung,
--     phiếu chi nhóm "Giá vốn") = Lãi gộp − Lương (bảng lương tháng) − Hoa hồng GDV (theo tháng duyệt giá của xe)
--     − Chi phí vận hành − Chi phí cố định (phiếu chi tính chất "chi_phi") = Lãi trước thuế.
--   Chốt tháng: giám đốc khóa sổ tháng đã qua, lưu ảnh số liệu; cổ đông chỉ xem tháng đã chốt.
--   Tương thích ngược: thêm hàm mới.
-- =====================================================================

-- Số liệu từng tháng của một chi nhánh (giám đốc, quản lý chung, kế toán)
create or replace function public.ket_qua_kinh_doanh(p_chi_nhanh text default null) returns table (
  thang date, doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric,
  gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric,
  luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric,
  so_xe bigint, da_chot boolean, chot_luc timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh());
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return query
  with thang_dt as (
    select date_trunc('month', d.ngay)::date as th,
      sum(d.so_tien) filter (where d.nguon = 'bao_hiem') as bh,
      sum(d.so_tien) filter (where d.nguon = 'khach') as kh,
      sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh') as dvn,
      sum(d.so_tien) filter (where d.nguon = 'giam_gia') as gg,
      sum(d.vat_ra) as vat, count(distinct d.ho_so_id) as xe
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn group by 1),
  thang_kho as (
    select date_trunc('month', px.ngay)::date as th,
      sum(pd.gia_von) filter (where px.loai = 'cho_xe') as xe, sum(pd.gia_von) filter (where px.loai = 'dung_chung') as dc
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' group by 1),
  thang_chi as (
    select date_trunc('month', p.ngay)::date as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_hh as (
    select date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' group by 1),
  cac_thang as (
    select th from thang_dt union select th from thang_kho union select th from thang_chi union select th from thang_hh
    union select bl.thang from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn)
  select t.th,
    coalesce(dt.bh,0), coalesce(dt.kh,0), coalesce(dt.dvn,0), coalesce(dt.gg,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0), coalesce(dt.vat,0),
    coalesce(k.xe,0), coalesce(k.dc,0), coalesce(c.gv,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0),
    coalesce(bl.tong_luong,0), coalesce(hh.hh,0), coalesce(c.vh,0), coalesce(c.cd,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0)
      - coalesce(bl.tong_luong,0) - coalesce(hh.hh,0) - coalesce(c.vh,0) - coalesce(c.cd,0),
    coalesce(c.vat_vao,0), coalesce(dt.xe,0), ct.thang is not null, ct.chot_luc
  from cac_thang t
  left join thang_dt dt on dt.th = t.th
  left join thang_kho k on k.th = t.th
  left join thang_chi c on c.th = t.th
  left join thang_hh hh on hh.th = t.th
  left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
  left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th
  where t.th is not null
  order by t.th desc;
end $$;

-- Giám đốc chốt tháng đã qua: khóa sổ (không ghi / sửa phiếu, hồ sơ của tháng đó), lưu ảnh số liệu cho cổ đông
create or replace function public.chot_thang(p_thang date, p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; v_so jsonb;
begin
  perform app.yeu_cau('giam_doc');
  if v_thang >= date_trunc('month', current_date)::date then raise exception 'Chỉ chốt được tháng đã qua.'; end if;
  if app.thang_da_chot(v_cn, v_thang) then raise exception 'Tháng này đã chốt rồi.'; end if;
  select to_jsonb(k) into v_so from public.ket_qua_kinh_doanh(v_cn) k where k.thang = v_thang;
  if v_so is null then raise exception 'Tháng này chưa có số liệu.'; end if;
  insert into public.chot_thang (chi_nhanh_id, thang, chot_boi, so_lieu) values (v_cn, v_thang, auth.uid(), v_so - 'da_chot' - 'chot_luc');
  return v_so;
end $$;

-- Mở lại tháng đã chốt (giám đốc, có lý do) – ghi lại vào so_lieu cũ không cần, chỉ xóa khóa
create or replace function public.mo_lai_thang(p_thang date, p_ly_do text, p_chi_nhanh text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date;
begin
  perform app.yeu_cau('giam_doc');
  if nullif(trim(p_ly_do), '') is null then raise exception 'Ghi lý do mở lại tháng.'; end if;
  delete from public.chot_thang where chi_nhanh_id = v_cn and thang = v_thang;
  if not found then raise exception 'Tháng này chưa chốt.'; end if;
end $$;

-- Cổ đông (và giám đốc): số tổng của các tháng đã chốt
create or replace function public.bao_cao_co_dong() returns table (chi_nhanh_id text, thang date, so_lieu jsonb, chot_luc timestamptz)
language sql stable security definer set search_path = public as $$
  select ct.chi_nhanh_id, ct.thang, ct.so_lieu, ct.chot_luc from public.chot_thang ct
  where app.co_vai_tro('co_dong', 'giam_doc') order by ct.thang desc
$$;

revoke execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, text), public.mo_lai_thang(date, text, text), public.bao_cao_co_dong() from public, anon;
grant execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, text), public.mo_lai_thang(date, text, text), public.bao_cao_co_dong() to authenticated;

-- ======================= 026_ky_chi_phi_chot_thang.sql =======================
-- =====================================================================
-- 026 (13/10/2026): KỲ CHI PHÍ, CHECKLIST TRƯỚC KHI CHỐT, KẾT QUẢ KINH DOANH THEO THÁNG ĐẦY ĐỦ
--   Chốt với giám đốc: kỳ báo cáo khóa ở ngày cuối tháng; tiền điện, tiền lương... nhập SAU ngày đó nhưng vẫn tính
--   vào tháng đó. Vì vậy:
--   - Đề nghị chi / phiếu chi có "kỳ chi phí" (ky_chi_phi = ngày đầu tháng): chi phí tính vào tháng này dù chi tiền
--     tháng sau. Mặc định = tháng của ngày lập; chọn được tháng trước. Kỳ đã chốt thì không lập / chi được nữa.
--   - Mục chi "định kỳ" (điện, nước, mặt bằng...): trước khi chốt, phần mềm liệt kê mục định kỳ chưa có trong kỳ.
--   - Kết quả kinh doanh: mọi tháng từ tháng đầu có số liệu đến tháng hiện tại (sang tháng mới tự có cột mới),
--     kèm trạng thái Đang mở / Chờ chốt / Đã chốt, lương đã nhập chưa, chi phí định kỳ còn thiếu, đề nghị chi chưa chi.
--   - Chốt tháng: còn thiếu thì cảnh báo (CANH_BAO) – giám đốc xác nhận mới chốt.
--   Tương thích ngược: thêm cột, hàm kết quả kinh doanh đổi cột trả về (tạo lại).
-- =====================================================================
alter table public.de_nghi_chi add column if not exists ky_chi_phi date;
alter table public.phieu_thu_chi add column if not exists ky_chi_phi date;
comment on column public.de_nghi_chi.ky_chi_phi is 'Chi phí tính vào tháng này (ngày đầu tháng); trống = tháng của ngày lập';
comment on column public.phieu_thu_chi.ky_chi_phi is 'Chi phí tính vào tháng này (ngày đầu tháng); trống = tháng của ngày chi';
alter table public.muc_thu_chi add column if not exists dinh_ky boolean not null default false;
comment on column public.muc_thu_chi.dinh_ky is 'Chi phí phát sinh đều mỗi tháng: trước khi chốt tháng nhắc nếu chưa có';
update public.muc_thu_chi set dinh_ky = true
where loai = 'chi' and tinh_chat = 'chi_phi' and ten in ('Mặt bằng', 'Bảo vệ', 'BHXH', 'Điện', 'Internet – quảng cáo – hotline', 'Nước', 'Rác');

-- Kỳ chi phí hợp lệ: ngày đầu tháng, không sau tháng hiện tại, không quá 3 tháng trước, tháng chưa chốt
create or replace function app.kiem_ky_chi_phi(p_cn text, p_ky date) returns date
language plpgsql stable as $$
begin
  if p_ky is null then return null; end if;
  p_ky := date_trunc('month', p_ky)::date;
  if p_ky > date_trunc('month', current_date)::date then raise exception 'Kỳ chi phí không được sau tháng hiện tại.'; end if;
  if p_ky < (date_trunc('month', current_date) - interval '3 months')::date then raise exception 'Kỳ chi phí quá xa (tối đa 3 tháng trước).'; end if;
  perform app.yeu_cau_thang_mo(p_cn, p_ky);
  return p_ky;
end $$;

create or replace function public.lap_de_nghi_chi(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); m public.muc_thu_chi; v_id bigint;
  v_ngay date := coalesce((p->>'ngay')::date, current_date); v_ky date; v_noi_dung text;
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
  -- Kỳ chi phí: chỉ với khoản tính vào lãi lỗ; khác tháng lập thì ghi rõ vào nội dung để ai cũng thấy
  v_noi_dung := trim(p->>'noi_dung');
  if m.tinh_chat = 'chi_phi' then
    v_ky := app.kiem_ky_chi_phi(v_cn, coalesce((p->>'ky_chi_phi')::date, v_ngay));
    if v_ky <> date_trunc('month', v_ngay)::date then
      v_noi_dung := v_noi_dung || ' (chi phí tháng ' || to_char(v_ky, 'MM/YYYY') || ')'; end if;
  end if;

  insert into public.de_nghi_chi (chi_nhanh_id, ngay, nguoi_de_nghi, muc_id, so_tien, vat_dau_vao, noi_dung, nguoi_nhan,
    ho_so_id, nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, ky_chi_phi)
  values (v_cn, v_ngay, auth.uid(), m.id, (p->>'so_tien')::numeric,
    coalesce((p->>'vat_dau_vao')::numeric, 0), v_noi_dung, nullif(trim(p->>'nguoi_nhan'),''),
    (p->>'ho_so_id')::bigint, (p->>'nha_cung_cap_id')::bigint, (p->>'gdv_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, v_ky)
  returning id into v_id;
  return v_id;
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
  if r.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ky_chi_phi); end if;
  if p_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan(p_tai_khoan, r.chi_nhanh_id);
  select * into m from public.muc_thu_chi where id = r.muc_id;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, vat_dau_vao, noi_dung,
    nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, de_nghi_chi_id, tao_boi, ky_chi_phi)
  values (r.chi_nhanh_id, p_ngay, 'chi', p_tai_khoan, r.muc_id, r.so_tien, r.vat_dau_vao,
    concat_ws(' – ', r.noi_dung, r.nguoi_nhan), r.nha_cung_cap_id, r.gdv_id, r.don_vi_lien_quan_id, r.id, auth.uid(), r.ky_chi_phi)
  returning id into v_id;

  if m.tinh_chat = 'tra_coc' then   -- trả lại cọc cho khách: giảm phần khách đã trả
    insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (v_id, r.ho_so_id, 'khach', r.so_tien);
    perform app.cap_nhat_dong(r.ho_so_id);
  end if;
  update public.de_nghi_chi set trang_thai = 'da_chi' where id = p_de_nghi;
  return v_id;
end $$;

-- Kết quả kinh doanh: mọi tháng từ tháng đầu có số liệu đến tháng hiện tại, kèm trạng thái và checklist chốt
drop function if exists public.ket_qua_kinh_doanh(text);
create or replace function public.ket_qua_kinh_doanh(p_chi_nhanh text default null) returns table (
  thang date, ngay_cuoi date, trang_thai text,
  doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric,
  gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric,
  luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric,
  so_xe bigint, luong_da_nhap boolean, thieu_dinh_ky text[], de_nghi_cho_chi bigint, da_chot boolean, chot_luc timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_dau date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select least(
    (select min(date_trunc('month', d.ngay))::date from public.v_doanh_thu d where d.chi_nhanh_id = v_cn),
    (select min(date_trunc('month', px.ngay))::date from public.phieu_xuat px where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc'),
    (select min(coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date)) from public.phieu_thu_chi p where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'),
    (select min(bl.thang) from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn),
    (select min(ct.thang) from public.chot_thang ct where ct.chi_nhanh_id = v_cn),
    date_trunc('month', current_date)::date) into v_dau;
  return query
  with cac_thang as (
    select g::date as th from generate_series(v_dau, date_trunc('month', current_date)::date, interval '1 month') g),
  thang_dt as (
    select date_trunc('month', d.ngay)::date as th,
      sum(d.so_tien) filter (where d.nguon = 'bao_hiem') as bh,
      sum(d.so_tien) filter (where d.nguon = 'khach') as kh,
      sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh') as dvn,
      sum(d.so_tien) filter (where d.nguon = 'giam_gia') as gg,
      sum(d.vat_ra) as vat, count(distinct d.ho_so_id) as xe
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn group by 1),
  thang_kho as (
    select date_trunc('month', px.ngay)::date as th,
      sum(pd.gia_von) filter (where px.loai = 'cho_xe') as xe, sum(pd.gia_von) filter (where px.loai = 'dung_chung') as dc
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' group by 1),
  thang_chi as (
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_hh as (
    select date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' group by 1)
  select t.th, (t.th + interval '1 month' - interval '1 day')::date,
    case when ct.thang is not null then 'da_chot' when t.th >= date_trunc('month', current_date)::date then 'dang_mo' else 'cho_chot' end,
    coalesce(dt.bh,0), coalesce(dt.kh,0), coalesce(dt.dvn,0), coalesce(dt.gg,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0), coalesce(dt.vat,0),
    coalesce(k.xe,0), coalesce(k.dc,0), coalesce(c.gv,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0),
    coalesce(bl.tong_luong,0), coalesce(hh.hh,0), coalesce(c.vh,0), coalesce(c.cd,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0)
      - coalesce(bl.tong_luong,0) - coalesce(hh.hh,0) - coalesce(c.vh,0) - coalesce(c.cd,0),
    coalesce(c.vat_vao,0), coalesce(dt.xe,0),
    bl.thang is not null,
    coalesce((select array_agg(m.ten order by m.ten) from public.muc_thu_chi m
      where m.loai = 'chi' and m.dinh_ky and m.hoat_dong
        and not exists (select 1 from public.phieu_thu_chi p where p.muc_id = m.id and p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'
                          and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = t.th)
        and not exists (select 1 from public.de_nghi_chi d where d.muc_id = m.id and d.chi_nhanh_id = v_cn and d.trang_thai not in ('huy','tu_choi')
                          and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th)), '{}'::text[]),
    (select count(*) from public.de_nghi_chi d where d.chi_nhanh_id = v_cn and d.trang_thai in ('cho_duyet','da_duyet')
       and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th),
    ct.thang is not null, ct.chot_luc
  from cac_thang t
  left join thang_dt dt on dt.th = t.th
  left join thang_kho k on k.th = t.th
  left join thang_chi c on c.th = t.th
  left join thang_hh hh on hh.th = t.th
  left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
  left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th
  order by t.th;
end $$;

-- Chốt tháng: còn thiếu lương / chi phí định kỳ / đề nghị chi chưa chi thì cảnh báo, giám đốc xác nhận mới chốt
drop function if exists public.chot_thang(date, text);
create or replace function public.chot_thang(p_thang date, p_bo_qua_canh_bao boolean default false, p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; k record; v_thieu text[] := '{}';
begin
  perform app.yeu_cau('giam_doc');
  if v_thang >= date_trunc('month', current_date)::date then raise exception 'Chỉ chốt được tháng đã qua (kỳ khóa ở ngày cuối tháng).'; end if;
  if app.thang_da_chot(v_cn, v_thang) then raise exception 'Tháng này đã chốt rồi.'; end if;
  select * into k from public.ket_qua_kinh_doanh(v_cn) x where x.thang = v_thang;
  if k.thang is null then raise exception 'Tháng này chưa có số liệu.'; end if;
  if not p_bo_qua_canh_bao then
    if not k.luong_da_nhap then v_thieu := v_thieu || 'chưa nhập bảng lương'; end if;
    if cardinality(k.thieu_dinh_ky) > 0 then v_thieu := v_thieu || ('chưa có chi phí định kỳ: ' || array_to_string(k.thieu_dinh_ky, ', ')); end if;
    if k.de_nghi_cho_chi > 0 then v_thieu := v_thieu || (k.de_nghi_cho_chi || ' đề nghị chi của kỳ chưa chi'); end if;
    if cardinality(v_thieu) > 0 then
      raise exception 'CANH_BAO: Tháng % còn thiếu: %. Chốt xong sẽ không nhập thêm được vào tháng này. Vẫn chốt?',
        to_char(v_thang, 'MM/YYYY'), array_to_string(v_thieu, '; ');
    end if;
  end if;
  insert into public.chot_thang (chi_nhanh_id, thang, chot_boi, so_lieu)
  values (v_cn, v_thang, auth.uid(), to_jsonb(k) - 'da_chot' - 'chot_luc' - 'trang_thai');
  return to_jsonb(k);
end $$;

revoke execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, boolean, text), app.kiem_ky_chi_phi(text, date) from public, anon;
grant execute on function public.ket_qua_kinh_doanh(text), public.chot_thang(date, boolean, text) to authenticated;
-- 027: Nợ nội bộ & cá nhân – công ty mượn tiền giám đốc / cổ đông, cổ đông mượn tiền công ty, chi hộ.
--  Quy ước: mọi phiếu CHI gắn đơn vị liên quan làm họ nợ công ty thêm (hoặc giảm nợ công ty với họ);
--  mọi phiếu THU gắn đơn vị làm ngược lại. Còn lại = đầu kỳ + đã chi − đã thu: dương = họ nợ công ty, âm = công ty nợ họ.
--  Không khoản nào vào lãi lỗ (tính chất thu_noi_bo / tra_noi_bo).

alter table public.don_vi_lien_quan add column if not exists loai text not null default 'cong_ty';
alter table public.don_vi_lien_quan drop constraint if exists don_vi_lien_quan_loai_check;
alter table public.don_vi_lien_quan add constraint don_vi_lien_quan_loai_check check (loai in ('cong_ty','ca_nhan'));
alter table public.don_vi_lien_quan add column if not exists so_du_dau_ky numeric(14,0) not null default 0;
alter table public.don_vi_lien_quan add column if not exists ngay_dau_ky date;
alter table public.don_vi_lien_quan add column if not exists hoat_dong boolean not null default true;
comment on column public.don_vi_lien_quan.loai is 'cong_ty: công ty cùng hệ thống (PHI, DTM, GI); ca_nhan: giám đốc, cổ đông, cá nhân';
comment on column public.don_vi_lien_quan.so_du_dau_ky is 'Nợ tính đến ngày đầu kỳ: dương = họ nợ công ty, âm = công ty nợ họ';

-- Mục thu chi "hệ thống": phần mềm tìm theo mã, tên đổi tự do
alter table public.muc_thu_chi add column if not exists he_thong text;
create unique index if not exists muc_thu_chi_he_thong_uq on public.muc_thu_chi (he_thong) where he_thong is not null;
insert into public.muc_thu_chi (loai, ten, nhom, tinh_chat, can_ho_so) values
  ('thu', 'Công ty mượn tiền giám đốc / cổ đông', null, 'thu_noi_bo', false),
  ('thu', 'Cổ đông / cá nhân trả tiền mượn',      null, 'thu_noi_bo', false),
  ('chi', 'Cho cổ đông / cá nhân mượn',           null, 'tra_noi_bo', false),
  ('chi', 'Trả tiền mượn giám đốc / cổ đông',    null, 'tra_noi_bo', false)
on conflict (loai, ten) do nothing;
update public.muc_thu_chi set he_thong = 'muon_ca_nhan' where loai = 'thu' and ten = 'Công ty mượn tiền giám đốc / cổ đông' and he_thong is null;

-- Chi hộ: phiếu chi được một người/đơn vị trả thay (tiền không qua quỹ) → ghi cặp phiếu thu "công ty mượn" + phiếu chi cùng tài khoản
alter table public.phieu_thu_chi add column if not exists chi_ho_boi bigint references public.don_vi_lien_quan(id);
alter table public.phieu_thu_chi add column if not exists phieu_doi_ung_id bigint references public.phieu_thu_chi(id);
comment on column public.phieu_thu_chi.chi_ho_boi is 'Phiếu chi do đơn vị/cá nhân này trả thay; phiếu thu đối ứng ở phieu_doi_ung_id';
comment on column public.phieu_thu_chi.phieu_doi_ung_id is 'Phiếu thu/chi đi cặp (chi hộ): hủy một phiếu thì phiếu kia hủy theo';

-- Công nợ nội bộ từng đơn vị / cá nhân theo chi nhánh
create or replace view public.v_cong_no_noi_bo with (security_invoker = true) as
select x.*, (x.so_du_dau_ky + x.da_chi - x.da_thu) as con_lai
from (
  select dv.id, dv.ten, dv.loai, dv.hoat_dong, dv.so_du_dau_ky, dv.ngay_dau_ky, c.chi_nhanh_id,
    coalesce((select sum(p.so_tien) from public.phieu_thu_chi p
              where p.don_vi_lien_quan_id = dv.id and p.chi_nhanh_id = c.chi_nhanh_id and p.loai = 'chi' and p.trang_thai = 'hieu_luc'), 0) as da_chi,
    coalesce((select sum(p.so_tien) from public.phieu_thu_chi p
              where p.don_vi_lien_quan_id = dv.id and p.chi_nhanh_id = c.chi_nhanh_id and p.loai = 'thu' and p.trang_thai = 'hieu_luc'), 0) as da_thu,
    (select max(p.ngay) from public.phieu_thu_chi p
      where p.don_vi_lien_quan_id = dv.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai = 'hieu_luc') as ngay_cuoi
  from public.don_vi_lien_quan dv
  cross join (select id as chi_nhanh_id from public.chi_nhanh) c
  where app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(c.chi_nhanh_id)
) x;
grant select on public.v_cong_no_noi_bo to authenticated;

-- Chi tiền cho đề nghị chi, thêm tùy chọn chi hộ
drop function if exists public.chi_tien(bigint, bigint, date);
create or replace function public.chi_tien(p_de_nghi bigint, p_tai_khoan bigint, p_ngay date default current_date, p_chi_ho_boi bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; m public.muc_thu_chi; dv public.don_vi_lien_quan; v_id bigint; v_thu bigint; v_muc_muon bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.de_nghi_chi where id = p_de_nghi for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'da_duyet' then raise exception 'Đề nghị chưa được duyệt thì chưa chi được.'; end if;
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, p_ngay);
  if r.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ky_chi_phi); end if;
  if p_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan(p_tai_khoan, r.chi_nhanh_id);
  select * into m from public.muc_thu_chi where id = r.muc_id;
  if p_chi_ho_boi is not null then
    select * into dv from public.don_vi_lien_quan where id = p_chi_ho_boi;
    if not found then raise exception 'Không tìm thấy người chi hộ (Danh mục → Đơn vị liên quan).'; end if;
    if m.tinh_chat = 'tra_noi_bo' then raise exception 'Khoản trả nội bộ / cho mượn không chi hộ được.'; end if;
    select id into v_muc_muon from public.muc_thu_chi where he_thong = 'muon_ca_nhan' and hoat_dong;
    if v_muc_muon is null then raise exception 'Chưa có mục thu "Công ty mượn tiền giám đốc / cổ đông" (Danh mục → Mục thu chi).'; end if;
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, vat_dau_vao, noi_dung,
    nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, de_nghi_chi_id, tao_boi, ky_chi_phi, chi_ho_boi)
  values (r.chi_nhanh_id, p_ngay, 'chi', p_tai_khoan, r.muc_id, r.so_tien, r.vat_dau_vao,
    concat_ws(' – ', r.noi_dung, r.nguoi_nhan) || case when p_chi_ho_boi is null then '' else ' (' || dv.ten || ' chi hộ)' end,
    r.nha_cung_cap_id, r.gdv_id, r.don_vi_lien_quan_id, r.id, auth.uid(), r.ky_chi_phi, p_chi_ho_boi)
  returning id into v_id;

  if p_chi_ho_boi is not null then   -- tiền do người đó bỏ ra: công ty mượn họ đúng số tiền, cùng tài khoản để quỹ không đổi
    insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung, don_vi_lien_quan_id, tao_boi, phieu_doi_ung_id)
    values (r.chi_nhanh_id, p_ngay, 'thu', p_tai_khoan, v_muc_muon, r.so_tien,
      'Chi hộ – ' || dv.ten || ' trả thay: ' || r.noi_dung, p_chi_ho_boi, auth.uid(), v_id)
    returning id into v_thu;
    update public.phieu_thu_chi set phieu_doi_ung_id = v_thu where id = v_id;
  end if;

  if m.tinh_chat = 'tra_coc' then   -- trả lại cọc cho khách: giảm phần khách đã trả
    insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (v_id, r.ho_so_id, 'khach', r.so_tien);
    perform app.cap_nhat_dong(r.ho_so_id);
  end if;
  update public.de_nghi_chi set trang_thai = 'da_chi' where id = p_de_nghi;
  return v_id;
end $$;

-- Hủy phiếu: phiếu đối ứng (chi hộ) hủy theo
create or replace function public.huy_phieu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; x bigint; d public.phieu_thu_chi;
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
  if r.phieu_doi_ung_id is not null then
    select * into d from public.phieu_thu_chi where id = r.phieu_doi_ung_id for update;
    if found and d.trang_thai = 'hieu_luc' then
      update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) || ' (hủy cùng phiếu chi hộ đối ứng)' where id = d.id;
      if d.de_nghi_chi_id is not null then
        update public.de_nghi_chi set trang_thai = 'da_duyet' where id = d.de_nghi_chi_id;
      end if;
    end if;
  end if;
end $$;

revoke execute on function public.chi_tien(bigint, bigint, date, bigint), public.huy_phieu(bigint, text) from public, anon;
grant execute on function public.chi_tien(bigint, bigint, date, bigint), public.huy_phieu(bigint, text) to authenticated;

-- ======================= 028_tai_san.sql =======================
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

-- ======================= 029_thiet_bi_do_nghe.sql =======================
-- =====================================================================
-- 029 (14/10/2026): ĐỔI TÊN "TÀI SẢN – DỤNG CỤ" THÀNH "THIẾT BỊ ĐỒ NGHỀ", GỘP VÀO TRANG KHO
--  - Giao diện: mục riêng trên menu bỏ, thành thẻ "Thiết bị đồ nghề" trong trang Kho.
--  - Mã mới TB-<nhóm>-001 (thay TS-…); mã cũ (nếu có) đổi sang TB-.
--  - Thông báo lỗi, tên việc ở Việc hôm nay dùng "thiết bị, đồ nghề" / "món" thay "tài sản".
--  - Chỉ thay chữ hiển thị; bảng, cột, quyền giữ nguyên (tên bảng nội bộ vẫn là tai_san…).
--  Tương thích ngược: tạo lại hàm / view cùng chữ ký; quyền thực thi giữ nguyên.
-- =====================================================================

-- v_viec_tai_san
create or replace view public.v_viec_tai_san with (security_invoker = true) as
select g.chi_nhanh_id, g.nhom_id, g.ten as nhom_ten, g.to_id, 'kiem_tra'::text as loai,
  case when g.to_id is not null then '{truong_nhom}'::text[] else g.vai_phu_trach end as vai,
  'Kiểm tra đồ nghề tuần – ' || g.ten as tieu_de, g.so_tai_san || ' món' as chi_tiet, g.han_kiem_tra as han, g.so_tai_san as so, null::bigint as tai_san_id
from public.v_nhom_tai_san g where g.so_tai_san > 0 and g.han_kiem_tra <= current_date + 1
union all
select g.chi_nhanh_id, g.nhom_id, g.ten, g.to_id, 'kiem_ke', '{quan_ly,ke_toan}'::text[],
  'Kiểm kê đồ nghề tháng – ' || g.ten, g.so_tai_san || ' món', g.han_kiem_ke, g.so_tai_san, null
from public.v_nhom_tai_san g where g.so_tai_san > 0 and g.han_kiem_ke <= current_date + 6
union all
select g.chi_nhanh_id, g.nhom_id, g.ten, g.to_id, 'xac_nhan',
  case when g.to_id is not null then '{truong_nhom}'::text[] else g.vai_phu_trach end,
  'Xác nhận đã nhận đồ nghề – ' || g.ten, g.so_cho_nhan || ' món mới giao', null::date, g.so_cho_nhan, null
from public.v_nhom_tai_san g where g.so_cho_nhan > 0
union all
select g.chi_nhanh_id, g.nhom_id, g.ten, g.to_id, 'su_co', '{giam_doc,quan_ly}'::text[],
  'Xử lý đồ nghề thiếu / hỏng – ' || g.ten, g.so_su_co || ' việc chờ xử lý', null::date, g.so_su_co, null
from public.v_nhom_tai_san g where g.so_su_co > 0
union all
select t.chi_nhanh_id, t.nhom_id, n.ten, n.to_id, 'bao_duong',
  case when n.to_id is not null then '{truong_nhom}'::text[] else n.vai_phu_trach end,
  'Bảo dưỡng ' || t.ten || ': ' || l.ten_viec, t.ma, coalesce(l.lan_cuoi, l.bat_dau) + l.chu_ky_ngay, 1, t.id
from public.lich_bao_duong l join public.tai_san t on t.id = l.tai_san_id join public.nhom_tai_san n on n.id = t.nhom_id
where l.hoat_dong and t.tinh_trang not in ('mat','thanh_ly')
  and coalesce(l.lan_cuoi, l.bat_dau) + l.chu_ky_ngay <= current_date + app.cai_dat_so('so_ngay_bao_truoc_bao_duong', 3)::int;

-- luu_tai_san
create or replace function public.luu_tai_san(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); r public.tai_san; v_id bigint; v_ma text; v_so int; v_loai text; v_nhom text;
begin
  perform app.yeu_cau_quan_ly_tai_san();
  perform app.yeu_cau_chi_nhanh(v_cn);
  if nullif(trim(p->>'ten'),'') is null then raise exception 'Ghi tên thiết bị, đồ nghề.'; end if;
  v_loai := coalesce(p->>'loai', 'dung_cu');
  if v_loai not in ('may_moc','dung_cu') then raise exception 'Chọn loại: thiết bị (máy móc) hoặc đồ nghề (dụng cụ).'; end if;
  v_so := case when v_loai = 'may_moc' then 1 else coalesce((p->>'so_luong')::int, 1) end;
  if v_so < 1 then raise exception 'Số lượng phải từ 1 trở lên.'; end if;
  if coalesce((p->>'gia_mua')::numeric, 0) < 0 then raise exception 'Giá mua không đúng.'; end if;
  if (p->>'id') is null then
    v_nhom := p->>'nhom_id';
    if not exists (select 1 from public.nhom_tai_san where id = v_nhom) then raise exception 'Chọn nhóm nhận.'; end if;
    perform pg_advisory_xact_lock(hashtext('ma_tai_san_' || v_cn || v_nhom));
    select 'TB-' || v_nhom || '-' || lpad((coalesce(max(substring(ma from '(\d+)$')::int), 0) + 1)::text, 3, '0') into v_ma
    from public.tai_san where chi_nhanh_id = v_cn and ma like 'TB-' || v_nhom || '-%';
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
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.tinh_trang in ('mat','thanh_ly') then raise exception 'Món này đã mất / thanh lý, không sửa được.'; end if;
  if r.loai <> v_loai then raise exception 'Không đổi loại được (thêm món mới nếu cần).'; end if;
  update public.tai_san set ten = trim(p->>'ten'), so_luong = v_so, don_vi = coalesce(nullif(trim(p->>'don_vi'),''), r.don_vi),
    hang_model = nullif(trim(p->>'hang_model'),''), so_serial = nullif(trim(p->>'so_serial'),''), gia_mua = coalesce((p->>'gia_mua')::numeric, 0),
    ngay_mua = (p->>'ngay_mua')::date, bao_hanh_den = (p->>'bao_hanh_den')::date, nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint,
    vi_tri = nullif(trim(p->>'vi_tri'),''), ghi_chu = nullif(trim(p->>'ghi_chu'),'')
  where id = r.id;
  perform app.ghi_ls_tai_san(r.id, 'sua', case when v_so <> r.so_luong then format('Sửa thông tin; số lượng %s → %s', r.so_luong, v_so) else 'Sửa thông tin' end);
  return r.id;
end $$;

-- chuyen_nhom_tai_san
create or replace function public.chuyen_nhom_tai_san(p_id bigint, p_nhom text, p_ghi_chu text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.tai_san;
begin
  perform app.yeu_cau_quan_ly_tai_san();
  select * into r from public.tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.tinh_trang in ('mat','thanh_ly') then raise exception 'Món này đã mất / thanh lý.'; end if;
  if not exists (select 1 from public.nhom_tai_san where id = p_nhom) then raise exception 'Chọn nhóm nhận.'; end if;
  if p_nhom = r.nhom_id then raise exception 'Món này đang ở nhóm đó rồi.'; end if;
  update public.tai_san set nhom_id = p_nhom, cho_nhan = true, nhan_boi = null, nhan_luc = null where id = p_id;
  perform app.ghi_ls_tai_san(p_id, 'giao', concat_ws(' – ', format('Chuyển từ %s sang %s', (select ten from public.nhom_tai_san where id = r.nhom_id),
    (select ten from public.nhom_tai_san where id = p_nhom)), nullif(trim(p_ghi_chu),'')), r.nhom_id, p_nhom);
end $$;

-- xac_nhan_nhan_tai_san
create or replace function public.xac_nhan_nhan_tai_san(p_ids jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r public.tai_san; v_so int := 0;
begin
  if jsonb_typeof(p_ids) <> 'array' then raise exception 'Chưa chọn món nào.'; end if;
  for r in select * from public.tai_san where id in (select (e #>> '{}')::bigint from jsonb_array_elements(p_ids) e) and cho_nhan for update loop
    perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
    if not app.phu_trach_nhom(r.nhom_id) then raise exception 'Chỉ người phụ trách nhóm % xác nhận được.', (select ten from public.nhom_tai_san where id = r.nhom_id) using errcode = '42501'; end if;
    update public.tai_san set cho_nhan = false, nhan_boi = auth.uid(), nhan_luc = now() where id = r.id;
    perform app.ghi_ls_tai_san(r.id, 'xac_nhan', 'Nhóm đã nhận');
    v_so := v_so + 1;
  end loop;
  return v_so;
end $$;

-- luu_kiem_tra_tai_san
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
  if v_thieu_tai_san is not null then raise exception 'Còn món chưa kiểm: %', v_thieu_tai_san; end if;

  insert into public.kiem_tra_tai_san (chi_nhanh_id, nhom_id, loai, nguoi_kiem, nguoi_kiem_ten, cung_kiem, ghi_chu)
  values (v_cn, v_nhom, v_loai, auth.uid(), (select ho_ten from public.nhan_vien where id = auth.uid()), nullif(trim(p->>'cung_kiem'),''), nullif(trim(p->>'ghi_chu'),'')) returning id into v_id;
  for d in select * from jsonb_array_elements(p->'dong') loop
    select * into t from public.tai_san where id = (d->>'tai_san_id')::bigint for update;
    if not found or t.chi_nhanh_id <> v_cn or t.nhom_id <> v_nhom then raise exception 'Có món không thuộc nhóm này.'; end if;
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

-- bao_su_co_tai_san
create or replace function public.bao_su_co_tai_san(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.tai_san; v_id bigint; v_so int := coalesce((p->>'so_luong')::int, 1);
begin
  select * into t from public.tai_san where id = (p->>'tai_san_id')::bigint for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if (p->>'loai') not in ('mat','hong') then raise exception 'Chọn mất hay hỏng.'; end if;
  if t.tinh_trang in ('mat','thanh_ly') then raise exception 'Món này đã mất / thanh lý.'; end if;
  if v_so < 1 or v_so > t.so_luong then raise exception 'Số lượng không đúng (đang có %).', t.so_luong; end if;
  if nullif(trim(p->>'mo_ta'),'') is null then raise exception 'Ghi mô tả: mất khi nào, hỏng thế nào.'; end if;
  insert into public.su_co_tai_san (chi_nhanh_id, tai_san_id, loai, so_luong, mo_ta, phat_hien_boi)
  values (t.chi_nhanh_id, t.id, p->>'loai', v_so, trim(p->>'mo_ta'), auth.uid()) returning id into v_id;
  if p->>'loai' = 'hong' and t.loai = 'may_moc' then update public.tai_san set tinh_trang = 'hong' where id = t.id; end if;
  perform app.ghi_ls_tai_san(t.id, 'su_co', format('Báo %s %s: %s', case when p->>'loai' = 'mat' then 'mất' else 'hỏng' end, v_so, trim(p->>'mo_ta')));
  return v_id;
end $$;

-- thanh_ly_tai_san
create or replace function public.thanh_ly_tai_san(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.tai_san;
begin
  perform app.yeu_cau_quan_ly_tai_san();
  select * into r from public.tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.tinh_trang in ('mat','thanh_ly') then raise exception 'Món này đã mất / thanh lý.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do thanh lý.'; end if;
  update public.tai_san set tinh_trang = 'thanh_ly', cho_nhan = false where id = p_id;
  update public.lich_bao_duong set hoat_dong = false where tai_san_id = p_id;
  perform app.ghi_ls_tai_san(p_id, 'thanh_ly', 'Thanh lý: ' || trim(p_ly_do));
end $$;

-- luu_lich_bao_duong
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
    if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
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

-- ghi_bao_duong
create or replace function public.ghi_bao_duong(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.tai_san; v_id bigint; v_ngay date := coalesce((p->>'ngay')::date, current_date); v_loai text := coalesce(p->>'loai', 'bao_duong');
begin
  select * into t from public.tai_san where id = (p->>'tai_san_id')::bigint for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if v_loai not in ('bao_duong','sua_chua') then raise exception 'Loại không đúng.'; end if;
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'noi_dung'),'') is null then raise exception 'Ghi nội dung đã làm.'; end if;
  if (p->>'lich_id') is not null and not exists (select 1 from public.lich_bao_duong where id = (p->>'lich_id')::bigint and tai_san_id = t.id) then
    raise exception 'Lịch bảo dưỡng không thuộc máy này.'; end if;
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

-- anh_tai_san
create or replace function public.anh_tai_san(p_id bigint, p_duong_dan text) returns void
language plpgsql security definer set search_path = public as $$
declare t public.tai_san;
begin
  select * into t from public.tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if p_duong_dan is null or p_duong_dan not like t.chi_nhanh_id || '/tai-san/%' then raise exception 'Đường dẫn ảnh không đúng.'; end if;
  update public.tai_san set anh = p_duong_dan where id = p_id;
end $$;

-- Mã cũ TS- → TB- (giữ số thứ tự)
update public.tai_san set ma = 'TB' || substr(ma, 3) where ma like 'TS-%';
update public.cai_dat set mo_ta = 'Thiết bị đồ nghề: người phụ trách nhóm kiểm tra chống mất sau mỗi số ngày này' where khoa = 'so_ngay_kiem_tra_tai_san';
update public.cai_dat set mo_ta = 'Thiết bị đồ nghề: báo lịch bảo dưỡng máy trước số ngày này' where khoa = 'so_ngay_bao_truoc_bao_duong';

-- ======================= 030_co_dong_chi_xem.sql =======================
-- =====================================================================
-- 030 (14/10/2026): TÀI KHOẢN CỔ ĐÔNG – XEM ĐƯỢC TẤT CẢ SỐ LIỆU, KHÔNG SỬA ĐƯỢC GÌ
--  - Trước: cổ đông chỉ xem Báo cáo cổ đông (tháng đã chốt).
--  - Nay: đọc được như giám đốc trong chi nhánh của mình (hồ sơ xe, ảnh, dịch vụ nhanh, thu chi, đề nghị chi,
--    kho, thiết bị đồ nghề, doanh thu, công nợ, kết quả kinh doanh mọi tháng, danh mục, danh sách nhân viên).
--  - KHÔNG ghi: mọi hàm ghi vẫn đòi vai trò làm việc (cổ đông không có, và cổ đông không được kiêm vai trò khác);
--    app.la_nhan_vien() GIỮ NGUYÊN (dùng cho quyền ghi) – chỉ chính sách ĐỌC đổi sang app.xem_nhu_nhan_vien().
--    Nhật ký xuất file và xuất Excel vẫn chỉ giám đốc.
--  - Tệp này sinh tự động từ CSDL (chính sách SELECT có la_nhan_vien() hoặc mảng vai trò có kế toán → thêm cổ đông).
--  Tương thích ngược: chỉ mở rộng quyền đọc cho vai trò co_dong.
-- =====================================================================

create or replace function app.la_co_dong() returns boolean
language sql stable as $$ select app.vai_tro() && array['co_dong'] $$;

-- Quyền ĐỌC: nhân viên văn phòng + cổ đông (KHÔNG dùng cho quyền ghi)
create or replace function app.xem_nhu_nhan_vien() returns boolean
language sql stable as $$ select app.vai_tro() && array['giam_doc','quan_ly','ke_toan','cvdv','kho','co_dong'] $$;

revoke execute on function app.la_co_dong(), app.xem_nhu_nhan_vien() from public, anon;
grant execute on function app.la_co_dong(), app.xem_nhu_nhan_vien() to authenticated;

alter policy "doc" on public.bang_luong_thang using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.cai_dat using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.chot_thang using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.de_nghi_chi using ((app.duoc_xem_chi_nhanh(chi_nhanh_id) AND (app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) OR (nguoi_de_nghi = auth.uid()))));

alter policy "doc" on public.de_nghi_mua using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.de_nghi_mua_dong using ((EXISTS ( SELECT 1
   FROM de_nghi_mua d
  WHERE ((d.id = de_nghi_mua_dong.de_nghi_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.de_xuat_dong using ((EXISTS ( SELECT 1
   FROM de_xuat_vat_tu d
  WHERE ((d.id = de_xuat_dong.de_xuat_id) AND (app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.de_xuat_vat_tu using (((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.dich_vu_nhanh using ((app.duoc_xem_chi_nhanh(chi_nhanh_id) AND (app.xem_nhu_nhan_vien() OR (tao_boi = auth.uid()))));

alter policy "doc" on public.don_vi_lien_quan using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.dong_xe using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.giam_dinh_vien using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.hang_bao_hiem using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.hang_kho using (((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.hang_muc using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = hang_muc.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.hang_xe using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.ho_so using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.ho_so_nhat_ky using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = ho_so_nhat_ky.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.ho_so_tep using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = ho_so_tep.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.kcs using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = kcs.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.khach_hang using (app.xem_nhu_nhan_vien());

alter policy "doc" on public.kho_tep using (app.xem_nhu_nhan_vien());

alter policy "doc" on public.kiem_ke using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.kiem_ke_dong using ((EXISTS ( SELECT 1
   FROM kiem_ke d
  WHERE ((d.id = kiem_ke_dong.kiem_ke_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.kiem_quy using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.lo_kho using (((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.muc_thu_chi using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.nha_cung_cap using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.nhan_vien using (((id = auth.uid()) OR app.xem_nhu_nhan_vien()));

alter policy "doc" on public.nhom_tai_san using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.phan_bo using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND (EXISTS ( SELECT 1
   FROM phieu_thu_chi p
  WHERE ((p.id = phan_bo.phieu_id) AND app.duoc_xem_chi_nhanh(p.chi_nhanh_id))))));

alter policy "doc" on public.phat_sinh using ((app.xem_nhu_nhan_vien() AND (EXISTS ( SELECT 1
   FROM ho_so h
  WHERE ((h.id = phat_sinh.ho_so_id) AND app.duoc_xem_chi_nhanh(h.chi_nhanh_id))))));

alter policy "doc" on public.phieu_nhap using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.phieu_nhap_dong using ((EXISTS ( SELECT 1
   FROM phieu_nhap d
  WHERE ((d.id = phieu_nhap_dong.phieu_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.phieu_thu_chi using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.phieu_xuat using ((app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.phieu_xuat_dong using ((EXISTS ( SELECT 1
   FROM phieu_xuat d
  WHERE ((d.id = phieu_xuat_dong.phieu_id) AND app.xem_nhu_nhan_vien() AND app.duoc_xem_chi_nhanh(d.chi_nhanh_id)))));

alter policy "doc" on public.tai_khoan_quy using ((app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'ke_toan'::text, 'quan_ly'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(chi_nhanh_id)));

alter policy "doc" on public.thue_suat_vat using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.to_thuc_hien using ((app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text])));

alter policy "doc" on public.xe using (app.xem_nhu_nhan_vien());

alter policy "doc" on public.xuat_lo using (app.xem_nhu_nhan_vien());

alter policy "ho-so-xe doc" on storage.objects using (((bucket_id = 'ho-so-xe'::text) AND (app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text]))));

create or replace view public.v_cong_no_ncc with (security_invoker=true) as
 SELECT n.id AS nha_cung_cap_id,
    n.ten,
    c.chi_nhanh_id,
    COALESCE(( SELECT sum(p.tong_tien) AS sum
           FROM phieu_nhap p
          WHERE p.nha_cung_cap_id = n.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.trang_thai = 'da_khop'::text), 0::numeric) AS da_nhap,
    COALESCE(( SELECT sum(p.tong_tien) AS sum
           FROM phieu_nhap p
          WHERE p.nha_cung_cap_id = n.id AND p.chi_nhanh_id = c.chi_nhanh_id AND (p.trang_thai = ANY (ARRAY['cho_khop'::text, 'treo'::text]))), 0::numeric) AS cho_khop,
    COALESCE(( SELECT sum(t.so_tien) AS sum
           FROM phieu_thu_chi t
             JOIN muc_thu_chi m ON m.id = t.muc_id
          WHERE t.nha_cung_cap_id = n.id AND t.chi_nhanh_id = c.chi_nhanh_id AND t.loai = 'chi'::text AND t.trang_thai = 'hieu_luc'::text AND m.tinh_chat = 'tra_ncc'::text), 0::numeric) AS da_tra
   FROM nha_cung_cap n
     CROSS JOIN ( SELECT chi_nhanh.id AS chi_nhanh_id
           FROM chi_nhanh) c
  WHERE app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'kho'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(c.chi_nhanh_id);

create or replace view public.v_cong_no_noi_bo with (security_invoker=true) as
 SELECT id,
    ten,
    loai,
    hoat_dong,
    so_du_dau_ky,
    ngay_dau_ky,
    chi_nhanh_id,
    da_chi,
    da_thu,
    ngay_cuoi,
    so_du_dau_ky + da_chi - da_thu AS con_lai
   FROM ( SELECT dv.id,
            dv.ten,
            dv.loai,
            dv.hoat_dong,
            dv.so_du_dau_ky,
            dv.ngay_dau_ky,
            c.chi_nhanh_id,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'chi'::text AND p.trang_thai = 'hieu_luc'::text), 0::numeric) AS da_chi,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'thu'::text AND p.trang_thai = 'hieu_luc'::text), 0::numeric) AS da_thu,
            ( SELECT max(p.ngay) AS max
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.trang_thai = 'hieu_luc'::text) AS ngay_cuoi
           FROM don_vi_lien_quan dv
             CROSS JOIN ( SELECT chi_nhanh.id AS chi_nhanh_id
                   FROM chi_nhanh) c
          WHERE app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text]) AND app.duoc_xem_chi_nhanh(c.chi_nhanh_id)) x;

create or replace view public.v_de_xuat as
 SELECT d.id,
    d.chi_nhanh_id,
    d.ma,
    d.ho_so_id,
    d.to_id,
    d.ghi_chu,
    d.trang_thai,
    d.nguoi_lap,
    d.tao_luc,
    h.ma AS ma_ho_so,
    bien_so_hien_thi(x.bien_so) AS bien_so,
    h.trang_thai AS trang_thai_ho_so,
    nv.ho_ten AS nguoi_lap_ten,
    ( SELECT count(*) AS count
           FROM de_xuat_dong dd
          WHERE dd.de_xuat_id = d.id) AS so_dong,
    ( SELECT count(*) AS count
           FROM de_xuat_dong dd
          WHERE dd.de_xuat_id = d.id AND dd.cho_mua) AS so_dong_cho_mua
   FROM de_xuat_vat_tu d
     JOIN ho_so h ON h.id = d.ho_so_id
     JOIN xe x ON x.id = h.xe_id
     LEFT JOIN nhan_vien nv ON nv.id = d.nguoi_lap
  WHERE app.duoc_xem_chi_nhanh(d.chi_nhanh_id) AND (app.xem_nhu_nhan_vien() OR app.co_vai_tro(VARIADIC ARRAY['truong_nhom'::text]));

CREATE OR REPLACE FUNCTION public.tien_ho_so(p_id bigint)
 RETURNS TABLE(bh_duyet numeric, khach_duyet numeric, phai_thu_bh numeric, phai_thu_khach numeric, da_thu_bh numeric, da_thu_khach numeric, con_no_bh numeric, con_no_khach numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from app.tien_ho_so(p_id) where app.xem_nhu_nhan_vien()
$function$;

CREATE OR REPLACE FUNCTION app.xem_nhom_tai_san(cn text, nhom text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select app.duoc_xem_chi_nhanh(cn) and (
    app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong')
    or (app.co_vai_tro('truong_nhom') and exists (
      select 1 from public.nhom_tai_san n where n.id = nhom and n.to_id is not null and n.to_id = app.to_cua_toi())))
$function$;

CREATE OR REPLACE FUNCTION public.ket_qua_kinh_doanh(p_chi_nhanh text DEFAULT NULL::text)
 RETURNS TABLE(thang date, ngay_cuoi date, trang_thai text, doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric, gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric, luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric, so_xe bigint, luong_da_nhap boolean, thieu_dinh_ky text[], de_nghi_cho_chi bigint, da_chot boolean, chot_luc timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_dau date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select least(
    (select min(date_trunc('month', d.ngay))::date from public.v_doanh_thu d where d.chi_nhanh_id = v_cn),
    (select min(date_trunc('month', px.ngay))::date from public.phieu_xuat px where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc'),
    (select min(coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date)) from public.phieu_thu_chi p where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'),
    (select min(bl.thang) from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn),
    (select min(ct.thang) from public.chot_thang ct where ct.chi_nhanh_id = v_cn),
    date_trunc('month', current_date)::date) into v_dau;
  return query
  with cac_thang as (
    select g::date as th from generate_series(v_dau, date_trunc('month', current_date)::date, interval '1 month') g),
  thang_dt as (
    select date_trunc('month', d.ngay)::date as th,
      sum(d.so_tien) filter (where d.nguon = 'bao_hiem') as bh,
      sum(d.so_tien) filter (where d.nguon = 'khach') as kh,
      sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh') as dvn,
      sum(d.so_tien) filter (where d.nguon = 'giam_gia') as gg,
      sum(d.vat_ra) as vat, count(distinct d.ho_so_id) as xe
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn group by 1),
  thang_kho as (
    select date_trunc('month', px.ngay)::date as th,
      sum(pd.gia_von) filter (where px.loai = 'cho_xe') as xe, sum(pd.gia_von) filter (where px.loai = 'dung_chung') as dc
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' group by 1),
  thang_chi as (
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_hh as (
    select date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' group by 1)
  select t.th, (t.th + interval '1 month' - interval '1 day')::date,
    case when ct.thang is not null then 'da_chot' when t.th >= date_trunc('month', current_date)::date then 'dang_mo' else 'cho_chot' end,
    coalesce(dt.bh,0), coalesce(dt.kh,0), coalesce(dt.dvn,0), coalesce(dt.gg,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0), coalesce(dt.vat,0),
    coalesce(k.xe,0), coalesce(k.dc,0), coalesce(c.gv,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0),
    coalesce(bl.tong_luong,0), coalesce(hh.hh,0), coalesce(c.vh,0), coalesce(c.cd,0),
    coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) - coalesce(k.xe,0) - coalesce(k.dc,0) - coalesce(c.gv,0)
      - coalesce(bl.tong_luong,0) - coalesce(hh.hh,0) - coalesce(c.vh,0) - coalesce(c.cd,0),
    coalesce(c.vat_vao,0), coalesce(dt.xe,0),
    bl.thang is not null,
    coalesce((select array_agg(m.ten order by m.ten) from public.muc_thu_chi m
      where m.loai = 'chi' and m.dinh_ky and m.hoat_dong
        and not exists (select 1 from public.phieu_thu_chi p where p.muc_id = m.id and p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'
                          and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = t.th)
        and not exists (select 1 from public.de_nghi_chi d where d.muc_id = m.id and d.chi_nhanh_id = v_cn and d.trang_thai not in ('huy','tu_choi')
                          and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th)), '{}'::text[]),
    (select count(*) from public.de_nghi_chi d where d.chi_nhanh_id = v_cn and d.trang_thai in ('cho_duyet','da_duyet')
       and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th),
    ct.thang is not null, ct.chot_luc
  from cac_thang t
  left join thang_dt dt on dt.th = t.th
  left join thang_kho k on k.th = t.th
  left join thang_chi c on c.th = t.th
  left join thang_hh hh on hh.th = t.th
  left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
  left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th
  order by t.th;
end $function$;

-- ======================= 031_so_km_yeu_cau_khach.sql =======================
-- =====================================================================
-- 031 (14/10/2026): SỐ KM (ODO) KHI TIẾP NHẬN XE; "TÌNH TRẠNG CHUNG CỦA XE" ĐỔI TÊN "YÊU CẦU KHÁCH HÀNG"
--  - ho_so.so_km: số trên đồng hồ công tơ mét lúc nhận xe (không bắt buộc), sửa được ở "Sửa thông tin".
--  - Cột tinh_trang_xe giữ nguyên, chỉ đổi tên hiển thị thành "Yêu cầu khách hàng".
--  - tiep_nhan_xe, sua_thong_tin_ho_so: lấy bản 008 + so_km; vẫn lưu van_phong_bh_id nếu cột còn (bản thật chưa chạy 008)
--    → chạy được cả trước và sau 008 (008 đã bỏ phần tạo lại 2 hàm này để không ghi đè).
--  - Xuất / nạp Data khách hàng có cột "Số km".
--  Tương thích ngược: thêm cột cho phép trống; hàm giữ chữ ký.
-- =====================================================================

alter table public.ho_so add column if not exists so_km integer;
alter table public.ho_so drop constraint if exists ho_so_so_km_check;
alter table public.ho_so add constraint ho_so_so_km_check check (so_km is null or so_km between 0 and 9999999);

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
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');   -- số km (ODO), không bắt buộc
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
  if nullif(trim(p->>'tinh_trang_xe'),'') is null then raise exception 'Ghi yêu cầu của khách hàng.'; end if;
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
  if length(v_km) > 7 then raise exception 'Số km (ODO) không đúng.'; end if;
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
    hang_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, so_km, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), v_km::int, auth.uid())
  returning id into v_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, v_id;
  end if;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', 'Tiếp nhận xe');
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

create or replace function public.sua_thong_tin_ho_so(p_id bigint, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_dt text; v_gdv public.giam_dinh_vien;
begin
  perform app.yeu_cau('cvdv','ke_toan','quan_ly','giam_doc');
  h := app.lay_ho_so(p_id);
  if p ? 'so_km' and length(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g')) > 7 then
    raise exception 'Số km (ODO) không đúng.'; end if;
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
    so_km           = case when p ? 'so_km' then nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '')::int else so_km end,
    cap_nhat_luc    = now()
  where id = p_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, p_id;
  end if;
  update public.xe set
    dong_xe_id   = case when p ? 'dong_xe_id' then (p->>'dong_xe_id')::bigint else dong_xe_id end,
    mau          = case when p ? 'mau' then nullif(trim(p->>'mau'),'') else mau end,
    han_bao_hiem = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end,
    han_bh_than_vo = case when p ? 'han_bh_than_vo' then (p->>'han_bh_than_vo')::date else han_bh_than_vo end
  where id = h.xe_id;
  perform app.ghi_nhat_ky(p_id, h.trang_thai, h.trang_thai, 'Sửa thông tin: ' || (select string_agg(k, ', ') from jsonb_object_keys(p) k));
end $$;

CREATE OR REPLACE FUNCTION public.xuat_du_lieu_khach()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    case when v.tu_excel then h.gia_tri_cu else v.bh_duyet + v.khach_duyet end as gia_tri, h.ghi_chu_cu, h.so_km,
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
      'ma', n.ma, 'ngay_vao', n.ngay_vao, 'so_km', n.so_km, 'ngay_giao', n.ngay_giao, 'trang_thai', n.trang_thai, 'tu_excel', n.tu_excel,
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
end $function$;

CREATE OR REPLACE FUNCTION app.nap_data_khach(p_xoa_het boolean DEFAULT true, p_chi_nhanh text DEFAULT 'TK'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        gia_tri_cu, ghi_chu_cu, tu_excel, so_km)
    values (v_ma, p_chi_nhanh, 'sua_chua', v_xe, v_kh, (v_ngay + time '08:00') at time zone 'Asia/Ho_Chi_Minh',
        case when d->>'nguon' = 'khach' then 'khach' else 'bao_hiem' end, v_bh, v_gdv,
        case when v_gdv is null then nullif(trim(d->>'gdv'), '') end,
        (d->>'han_tnds')::date, (d->>'han_than_vo')::date,
        coalesce(nullif(trim(d->>'tinh_trang'), ''), to_char(v_ngay, 'DD/MM/YYYY') || ': (Excel không ghi tình trạng)'),
        coalesce(nullif(trim(d->>'tu_van'), ''), to_char(v_ngay, 'DD/MM/YYYY') || ': (Chuyển từ Excel)'),
        v_tt, (v_giao + time '17:00') at time zone 'Asia/Ho_Chi_Minh', case when v_nb > 0 then v_giao end,
        (v_giao + time '17:00') at time zone 'Asia/Ho_Chi_Minh', nullif(trim(d->>'phan_hoi'), ''),
        nullif((d->>'gia_tri')::numeric, 0), nullif(trim(d->>'ghi_chu'), ''), true,
        nullif(regexp_replace(coalesce(d->>'so_km',''), '[^0-9]', '', 'g'), '')::int)
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
end $function$;

-- ======================= 032_dich_vu_nhanh_theo_xe.sql =======================
-- =====================================================================
-- 032 (14/10/2026): DỊCH VỤ NHANH GẮN VỚI XE – KHÁCH, BẮT BUỘC SỐ KM
--  - Gõ biển số / SĐT ở Dịch vụ nhanh: gợi ý xe cũ, hiện khách, lần vào gần nhất, số km lần trước,
--    hạn bảo hiểm, tư vấn còn ghi (tra_cuu_xe_nhanh – trưởng nhóm cũng dùng được).
--  - Lượt dịch vụ nhanh lưu xe_id, khach_hang_id, so_km (BẮT BUỘC – anh Thuận chốt 14/10).
--    Xe / khách chưa có thì tạo mới (khách tìm theo SĐT như tiếp nhận).
--  - Lịch sử xe hiện cả các lượt dịch vụ nhanh.
--  Tương thích ngược: thêm cột cho phép trống; giao diện cũ không gửi số km thì vẫn lưu (chỉ giao diện mới bắt buộc
--  qua p.bat_buoc_km) – khi đưa lên bản thật, hàm vẫn nhận lời gọi cũ.
-- =====================================================================

alter table public.dich_vu_nhanh add column if not exists xe_id bigint references public.xe(id);
alter table public.dich_vu_nhanh add column if not exists khach_hang_id bigint references public.khach_hang(id);
alter table public.dich_vu_nhanh add column if not exists so_km integer;
alter table public.dich_vu_nhanh drop constraint if exists dich_vu_nhanh_so_km_check;
alter table public.dich_vu_nhanh add constraint dich_vu_nhanh_so_km_check check (so_km is null or so_km between 0 and 9999999);
create index if not exists dich_vu_nhanh_xe_idx on public.dich_vu_nhanh (xe_id, ngay desc);

-- Bảng xem: giữ nguyên các cột cũ, thêm cột mới ở cuối
create or replace view public.v_dich_vu_nhanh with (security_invoker = true) as
select d.id, d.chi_nhanh_id, d.ngay, d.bien_so, d.dich_vu, d.nguoi_lam, d.so_tien, d.xuat_hd, d.trang_thai, d.tao_boi, d.tao_luc,
  public.bien_so_hien_thi(d.bien_so) as bien_so_hien_thi,
  coalesce((select sum(pb.so_tien) from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
            where pb.dich_vu_nhanh_id = d.id and p.trang_thai = 'hieu_luc'), 0) as da_thu,
  d.xe_id, d.khach_hang_id, d.so_km, k.ten as ten_khach, k.dien_thoai
from public.dich_vu_nhanh d
left join public.khach_hang k on k.id = d.khach_hang_id;

create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODO) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODO) không đúng.'; end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;

  -- Khách: tìm theo SĐT (như tiếp nhận); có tên mới thì cập nhật
  if v_dt <> '' then
    select id into v_kh from public.khach_hang where dien_thoai = v_dt;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(p->>'ten_khach'),''), 'Chưa có tên'), v_dt) returning id into v_kh;
    elsif nullif(trim(p->>'ten_khach'),'') is not null then
      update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
    end if;
  end if;
  -- Xe: tìm theo biển số; chưa có thì tạo (loại xe để trống, lần tiếp nhận sau bổ sung)
  if v_bs is not null then
    select id, khach_hang_id into v_xe, v_kh_xe from public.xe where bien_so = v_bs;
    if v_xe is not null and v_kh is null then v_kh := v_kh_xe; end if;
    if v_xe is null then
      insert into public.xe (bien_so, khach_hang_id) values (v_bs, v_kh) returning id into v_xe;
    elsif v_dt <> '' then
      update public.xe set khach_hang_id = v_kh where id = v_xe;
    end if;
  end if;

  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi, xe_id, khach_hang_id, so_km)
  values (v_cn, v_ngay, v_bs, trim(p->>'dich_vu'), nullif(trim(p->>'nguoi_lam'),''),
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid(), v_xe, v_kh, v_km::int)
  returning id into v_id;
  return v_id;
end $$;

-- Gợi ý / tra cứu xe cho Dịch vụ nhanh: theo biển số hoặc SĐT (từ 2 ký tự), tối đa 8 xe.
-- Trả về đủ thông tin để hiện ngay: khách, lần vào gần nhất, số km lần trước, hạn BH, tư vấn còn ghi.
create or replace function public.tra_cuu_xe_nhanh(p_tu text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_gon text := upper(regexp_replace(coalesce(p_tu,''), '[^0-9A-Za-z]', '', 'g')); r jsonb;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if length(v_gon) < 2 then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(t.d order by t.chinh_xac desc, t.bien_so), '[]'::jsonb) into r
  from (
    select x.bien_so, (x.bien_so = v_gon) as chinh_xac, jsonb_build_object(
      'xe_id', x.id, 'bien_so', public.bien_so_hien_thi(x.bien_so), 'mau', x.mau,
      'loai_xe', nullif(concat_ws(' ', hx.ten, dx.ten), ''),
      'ten_khach', nullif(k.ten, 'Chưa có tên'), 'dien_thoai', k.dien_thoai,
      'han_bh_than_vo', x.han_bh_than_vo, 'han_bao_hiem', x.han_bao_hiem,
      'lan_cuoi', (select jsonb_build_object('ngay', l.ngay, 'loai', l.loai, 'noi_dung', l.noi_dung, 'ma', l.ma, 'id', l.id)
                   from (select (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date as ngay, 'ho_so' as loai, h.ma, h.id,
                                left(h.tinh_trang_xe, 200) as noi_dung, h.ngay_vao as luc
                         from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy'
                         union all
                         select d.ngay, 'dich_vu_nhanh', null, d.id, d.dich_vu, d.tao_luc
                         from public.dich_vu_nhanh d where d.xe_id = x.id and d.trang_thai = 'hieu_luc') l
                   order by l.ngay desc, l.luc desc limit 1),
      'km_truoc', (select jsonb_build_object('so', l.so_km, 'ngay', l.ngay)
                   from (select h.so_km, (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date as ngay, h.ngay_vao as luc
                         from public.ho_so h where h.xe_id = x.id and h.so_km is not null and h.trang_thai <> 'huy'
                         union all
                         select d.so_km, d.ngay, d.tao_luc from public.dich_vu_nhanh d
                         where d.xe_id = x.id and d.so_km is not null and d.trang_thai = 'hieu_luc') l
                   order by l.ngay desc, l.luc desc limit 1),
      'tu_van', (select h.tu_van from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy'
                 and nullif(trim(h.tu_van), '') is not null and h.tu_van !~* '^\d{2}/\d{2}/\d{4}: (không|\(chuyển từ excel\))\.?$'
                 order by h.ngay_vao desc limit 1),
      'so_lan_vao', (select count(*) from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy')
                  + (select count(*) from public.dich_vu_nhanh d where d.xe_id = x.id and d.trang_thai = 'hieu_luc')) as d
    from public.xe x
    left join public.khach_hang k on k.id = x.khach_hang_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    where x.bien_so like '%' || v_gon || '%'
       or (v_gon ~ '^[0-9]{4,}$' and k.dien_thoai like '%' || v_gon || '%')
    order by (x.bien_so = v_gon) desc, x.bien_so
    limit 8
  ) t;
  return r;
end $$;

revoke execute on function public.tra_cuu_xe_nhanh(text) from public, anon;
grant execute on function public.tra_cuu_xe_nhanh(text) to authenticated;

-- ======================= 033_mui_gio_viet_nam.sql =======================
-- =====================================================================
-- 033 (14/10/2026): MÚI GIỜ VIỆT NAM CHO CƠ SỞ DỮ LIỆU
--  Lỗi: Supabase mặc định giờ UTC → từ 0h đến 7h sáng (giờ Việt Nam) "hôm nay" của máy chủ vẫn là hôm qua,
--  nên ghi dịch vụ nhanh, phiếu thu, phiếu nhập… với ngày hôm nay bị báo "Ngày không được sau hôm nay",
--  hạn kiểm tra, ngày lập… tính lệch một ngày.
--  Sửa: đặt múi giờ Asia/Ho_Chi_Minh cho cả cơ sở dữ liệu và các vai trò API (PostgREST áp theo vai trò),
--  và gắn múi giờ thẳng vào mọi hàm có dùng ngày giờ hiện tại (chạy đúng kể cả kết nối cũ chưa nhận cài đặt mới).
--  Tương thích ngược: chỉ đổi cách tính "hôm nay" cho đúng giờ Việt Nam.
-- =====================================================================

do $$ begin
  execute format('alter database %I set timezone to %L', current_database(), 'Asia/Ho_Chi_Minh');
exception when others then raise notice 'Không đặt được múi giờ cho cơ sở dữ liệu: %', sqlerrm;
end $$;

do $$ declare r text; begin
  foreach r in array array['authenticated', 'anon', 'authenticator', 'service_role'] loop
    begin
      if exists (select 1 from pg_roles where rolname = r) then
        execute format('alter role %I set timezone to %L', r, 'Asia/Ho_Chi_Minh');
      end if;
    exception when others then raise notice 'Không đặt được múi giờ cho vai trò %: %', r, sqlerrm;
    end;
  end loop;
end $$;

-- Mọi hàm của ứng dụng có dùng ngày giờ hiện tại: chạy theo giờ Việt Nam
do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%' or p.prosrc ilike '%localtimestamp%' or p.prosrc ilike '%current_timestamp%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

set timezone to 'Asia/Ho_Chi_Minh';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';

-- ======================= 034_dich_vu_nhanh_to_lam.sql =======================
-- =====================================================================
-- 034 (14/10/2026): DỊCH VỤ NHANH – NGƯỜI LÀM CHỈ CHỌN TỔ ĐIỆN – MÁY – GẦM HOẶC DETAILING
--  - dich_vu_nhanh.to_id ('DMG' | 'DT'); nguoi_lam ghi tên tổ. Giao diện mới bắt buộc chọn tổ.
--  - Doanh thu dịch vụ nhanh tính vào đúng tổ (trước đây luôn tính Detailing; dòng cũ không có tổ vẫn tính Detailing).
--  Tương thích ngược: thêm cột cho phép trống; giao diện cũ (không gửi to_id) vẫn ghi được như trước.
-- =====================================================================

alter table public.dich_vu_nhanh add column if not exists to_id text references public.to_thuc_hien(id);

create or replace view public.v_doanh_thu with (security_invoker = true) as
 SELECT h.chi_nhanh_id,
    m.ngay_duyet AS ngay,
    h.id AS ho_so_id,
    h.ma,
    bien_so_hien_thi(x.bien_so) AS bien_so,
    m.nguoi_tra AS nguon,
    m.nhom,
    tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat) AS so_tien,
        CASE
            WHEN m.xuat_hd THEN tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet
            ELSE 0::numeric
        END AS vat_ra
   FROM hang_muc m
     JOIN ho_so h ON h.id = m.ho_so_id
     JOIN xe x ON x.id = h.xe_id
  WHERE (m.trang_thai = ANY (ARRAY['duyet'::text, 'dang_lam'::text, 'xong'::text])) AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel AND h.loai <> 'bao_hanh'::text
UNION ALL
 SELECT d.chi_nhanh_id,
    d.ngay,
    NULL::bigint AS ho_so_id,
    NULL::text AS ma,
    bien_so_hien_thi(d.bien_so) AS bien_so,
    'dich_vu_nhanh'::text AS nguon,
        CASE d.to_id
            WHEN 'DMG'::text THEN 'dmg'::text
            ELSE 'detailing'::text
        END AS nhom,
    d.so_tien,
        CASE
            WHEN d.xuat_hd THEN d.so_tien - round(d.so_tien / (1::numeric + vat_ty_le(d.ngay)))
            ELSE 0::numeric
        END AS vat_ra
   FROM dich_vu_nhanh d
  WHERE d.trang_thai = 'hieu_luc'::text
UNION ALL
 SELECT h.chi_nhanh_id,
    h.giam_gia_ngay AS ngay,
    h.id AS ho_so_id,
    h.ma,
    NULL::text AS bien_so,
    'giam_gia'::text AS nguon,
    NULL::text AS nhom,
    - h.giam_gia AS so_tien,
    0 AS vat_ra
   FROM ho_so h
  WHERE h.giam_gia > 0::numeric AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel;

create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public set timezone to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint; v_to text := nullif(p->>'to_id', ''); v_nguoi text := nullif(trim(p->>'nguoi_lam'),'');
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODO) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODO) không đúng.'; end if;
  -- Người làm: chỉ tổ Điện – máy – gầm hoặc Detailing (034); tên tổ ghi vào nguoi_lam
  if v_to is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Chọn tổ làm: Điện – máy – gầm hoặc Detailing.'; end if;
  if v_to is not null then
    if v_to not in ('DMG', 'DT') then raise exception 'Dịch vụ nhanh chỉ do tổ Điện – máy – gầm hoặc Detailing làm.'; end if;
    select ten into v_nguoi from public.to_thuc_hien where id = v_to;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;

  -- Khách: tìm theo SĐT (như tiếp nhận); có tên mới thì cập nhật
  if v_dt <> '' then
    select id into v_kh from public.khach_hang where dien_thoai = v_dt;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(p->>'ten_khach'),''), 'Chưa có tên'), v_dt) returning id into v_kh;
    elsif nullif(trim(p->>'ten_khach'),'') is not null then
      update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
    end if;
  end if;
  -- Xe: tìm theo biển số; chưa có thì tạo (loại xe để trống, lần tiếp nhận sau bổ sung)
  if v_bs is not null then
    select id, khach_hang_id into v_xe, v_kh_xe from public.xe where bien_so = v_bs;
    if v_xe is not null and v_kh is null then v_kh := v_kh_xe; end if;
    if v_xe is null then
      insert into public.xe (bien_so, khach_hang_id) values (v_bs, v_kh) returning id into v_xe;
    elsif v_dt <> '' then
      update public.xe set khach_hang_id = v_kh where id = v_xe;
    end if;
  end if;

  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi, xe_id, khach_hang_id, so_km, to_id)
  values (v_cn, v_ngay, v_bs, trim(p->>'dich_vu'), v_nguoi,
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid(), v_xe, v_kh, v_km::int, v_to)
  returning id into v_id;
  return v_id;
end $$;

-- ======================= 035_so_km_bat_buoc_tiep_nhan.sql =======================
-- =====================================================================
-- 035 (14/10/2026): SỐ KM BẮT BUỘC KHI TIẾP NHẬN XE; TÊN HIỂN THỊ "SỐ KM (ODD)" (anh Thuận chọn chữ ODD)
--  - tiep_nhan_xe: giao diện mới gửi bat_buoc_km → thiếu số km thì chặn (giao diện cũ vẫn chạy).
--  - Thông báo lỗi đổi "(ODO)" thành "(ODD)".
-- =====================================================================

CREATE OR REPLACE FUNCTION public.tiep_nhan_xe(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare
  v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ngay timestamptz := coalesce((p->>'ngay_vao')::timestamptz, now());
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_nguon text := p->>'nguon_tt';
  v_gdv public.giam_dinh_vien;
  v_kh bigint; v_xe bigint; v_ma text; v_goc text; v_n int; v_id bigint; v_mo text;
  v_loai text := coalesce(p->>'loai', 'sua_chua');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');   -- số km (ODD), không bắt buộc
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
  if nullif(trim(p->>'tinh_trang_xe'),'') is null then raise exception 'Ghi yêu cầu của khách hàng.'; end if;
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
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
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
    hang_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, so_km, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), v_km::int, auth.uid())
  returning id into v_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, v_id;
  end if;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', 'Tiếp nhận xe');
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $function$;

CREATE OR REPLACE FUNCTION public.sua_thong_tin_ho_so(p_id bigint, p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare h public.ho_so; v_dt text; v_gdv public.giam_dinh_vien;
begin
  perform app.yeu_cau('cvdv','ke_toan','quan_ly','giam_doc');
  h := app.lay_ho_so(p_id);
  if p ? 'so_km' and length(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g')) > 7 then
    raise exception 'Số km (ODD) không đúng.'; end if;
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
    so_km           = case when p ? 'so_km' then nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '')::int else so_km end,
    cap_nhat_luc    = now()
  where id = p_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, p_id;
  end if;
  update public.xe set
    dong_xe_id   = case when p ? 'dong_xe_id' then (p->>'dong_xe_id')::bigint else dong_xe_id end,
    mau          = case when p ? 'mau' then nullif(trim(p->>'mau'),'') else mau end,
    han_bao_hiem = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end,
    han_bh_than_vo = case when p ? 'han_bh_than_vo' then (p->>'han_bh_than_vo')::date else han_bh_than_vo end
  where id = h.xe_id;
  perform app.ghi_nhat_ky(p_id, h.trang_thai, h.trang_thai, 'Sửa thông tin: ' || (select string_agg(k, ', ') from jsonb_object_keys(p) k));
end $function$;

CREATE OR REPLACE FUNCTION public.ghi_dich_vu_nhanh(p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint; v_to text := nullif(p->>'to_id', ''); v_nguoi text := nullif(trim(p->>'nguoi_lam'),'');
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  -- Người làm: chỉ tổ Điện – máy – gầm hoặc Detailing (034); tên tổ ghi vào nguoi_lam
  if v_to is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Chọn tổ làm: Điện – máy – gầm hoặc Detailing.'; end if;
  if v_to is not null then
    if v_to not in ('DMG', 'DT') then raise exception 'Dịch vụ nhanh chỉ do tổ Điện – máy – gầm hoặc Detailing làm.'; end if;
    select ten into v_nguoi from public.to_thuc_hien where id = v_to;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;

  -- Khách: tìm theo SĐT (như tiếp nhận); có tên mới thì cập nhật
  if v_dt <> '' then
    select id into v_kh from public.khach_hang where dien_thoai = v_dt;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(p->>'ten_khach'),''), 'Chưa có tên'), v_dt) returning id into v_kh;
    elsif nullif(trim(p->>'ten_khach'),'') is not null then
      update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
    end if;
  end if;
  -- Xe: tìm theo biển số; chưa có thì tạo (loại xe để trống, lần tiếp nhận sau bổ sung)
  if v_bs is not null then
    select id, khach_hang_id into v_xe, v_kh_xe from public.xe where bien_so = v_bs;
    if v_xe is not null and v_kh is null then v_kh := v_kh_xe; end if;
    if v_xe is null then
      insert into public.xe (bien_so, khach_hang_id) values (v_bs, v_kh) returning id into v_xe;
    elsif v_dt <> '' then
      update public.xe set khach_hang_id = v_kh where id = v_xe;
    end if;
  end if;

  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi, xe_id, khach_hang_id, so_km, to_id)
  values (v_cn, v_ngay, v_bs, trim(p->>'dich_vu'), v_nguoi,
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid(), v_xe, v_kh, v_km::int, v_to)
  returning id into v_id;
  return v_id;
end $function$;

-- ======================= 036_ra_soat_quy_trinh.sql =======================
-- =====================================================================
-- 036 (14/10/2026): RÀ SOÁT QUY TRÌNH – anh Thuận chọn các mục 5, 7, 8, 9, 10, 12 (sáng 14/10)
--  5. Giám định viên KHÔNG bắt buộc lúc tiếp nhận (hãng bảo hiểm thường cử GDV sau 1–2 ngày);
--     BẮT BUỘC trước khi nhập kết quả duyệt giá (duyet_gia chặn). Việc cần xử lý có dòng "chưa có GDV".
--  7. Hồ sơ BẢO HÀNH (xe quay lại vì lỗi cũ): không báo giá, không duyệt giá, không hãng BH / GDV.
--     Tiếp nhận chọn hạng mục làm lại (p.hang_muc, giá 0) → hồ sơ sang "Đã duyệt giá", lập lệnh sửa chữa ngay.
--     Giao diện cũ không gửi hang_muc thì chạy như trước.
--  9. THU TIỀN & GIAO XE một lần (thu_tien_giao_xe): phiếu thu + giao xe trong MỘT giao dịch – giao không được
--     thì phiếu thu cũng không ghi.
-- 10. DỊCH VỤ NHANH THU TIỀN NGAY: ghi_dich_vu_nhanh nhận thu_ngay + tai_khoan_id (chỉ kế toán / giám đốc)
--     → tự lập phiếu thu gắn lượt dịch vụ.
-- 12. Khấu trừ – giảm trừ chỉ sửa qua "Chia công nợ" (sua_chia_cong_no); giao diện mới không gửi khấu trừ khi giao xe
--     (giao_xe vẫn nhận khau_tru_giam_tru cho giao diện cũ của bản thật).
--  Tương thích ngược: hàm cũ giữ tên và tham số; chỉ thêm hàm mới, điều kiện mới.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5 + 7. Tiếp nhận xe: GDV không bắt buộc; hồ sơ bảo hành vào thẳng "Đã duyệt giá"
-- ---------------------------------------------------------------------
create or replace function public.tiep_nhan_xe(p jsonb) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare
  v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ngay timestamptz := coalesce((p->>'ngay_vao')::timestamptz, now());
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_nguon text := p->>'nguon_tt';
  v_gdv public.giam_dinh_vien;
  v_kh bigint; v_xe bigint; v_ma text; v_goc text; v_n int; v_id bigint; v_mo text;
  v_loai text := coalesce(p->>'loai', 'sua_chua');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_bao_hanh boolean := v_loai = 'bao_hanh';
  v_hm jsonb := case when jsonb_typeof(p->'hang_muc') = 'array' then p->'hang_muc' else '[]'::jsonb end;
  d jsonb; v_so_hm int := 0;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  if v_cn is null then raise exception 'Tài khoản chưa gắn chi nhánh.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  -- Bảo hành: làm lại miễn phí, không liên quan bảo hiểm → luôn là nguồn "khách", không hãng BH, không GDV
  if v_bao_hanh then v_nguon := 'khach'; end if;

  if nullif(trim(p->>'ten_khach'),'') is null then raise exception 'Thiếu tên khách.'; end if;
  if v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if (p->>'dong_xe_id') is null then raise exception 'Chưa chọn loại xe.'; end if;
  if v_nguon not in ('bao_hiem','khach','bao_hiem_khach') or v_nguon is null then
    raise exception 'Chưa chọn bảo hiểm nào hay khách lẻ.'; end if;
  if nullif(trim(p->>'tinh_trang_xe'),'') is null then raise exception 'Ghi yêu cầu của khách hàng.'; end if;
  if nullif(trim(p->>'tu_van'),'') is null then raise exception 'Thiếu mục những gì có thể tư vấn (ghi "Không" nếu không có).'; end if;
  if v_nguon <> 'khach' then
    if (p->>'hang_bh_id') is null then raise exception 'Chưa chọn hãng bảo hiểm.'; end if;
    -- 036: giám định viên để trống được (hãng cử sau); bắt buộc trước khi nhập kết quả duyệt giá
    if (p->>'gdv_id') is not null then
      select * into v_gdv from public.giam_dinh_vien where id = (p->>'gdv_id')::bigint;
      if v_gdv.la_cho_them and nullif(trim(p->>'gdv_ten_tam'),'') is null then
        raise exception 'Chọn "GDV mới – chờ thêm" thì phải ghi tên giám định viên.';
      end if;
    end if;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so';
  end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_bao_hanh and (p->>'ho_so_goc_id') is null then
    raise exception 'Hồ sơ bảo hành phải chọn hồ sơ cũ.'; end if;
  if v_bao_hanh then
    for d in select * from jsonb_array_elements(v_hm) loop
      if nullif(trim(d->>'ten'),'') is null then raise exception 'Hạng mục bảo hành thiếu nội dung.'; end if;
      v_so_hm := v_so_hm + 1;
    end loop;
    if v_so_hm > 0 then perform app.yeu_cau_thang_mo(v_cn, current_date); end if;
  end if;

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

  if v_bao_hanh and not exists (select 1 from public.ho_so where id = (p->>'ho_so_goc_id')::bigint and xe_id = v_xe) then
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
    hang_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, so_km, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), v_km::int, auth.uid())
  returning id into v_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, v_id;
  end if;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', case when v_bao_hanh then 'Tiếp nhận xe bảo hành' else 'Tiếp nhận xe' end);

  -- Bảo hành (036): hạng mục làm lại miễn phí, coi như đã duyệt → lập lệnh sửa chữa được ngay
  if v_bao_hanh and v_so_hm > 0 then
    for d in select * from jsonb_array_elements(v_hm) loop
      insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd, trang_thai, gia_duyet, ngay_duyet)
      values (v_id, 0, trim(d->>'ten'), coalesce(nullif(d->>'nhom',''), 'dong_son'), 'khach', 0, false, 'duyet', 0, current_date);
    end loop;
    perform app.doi_trang_thai(v_id, 'da_duyet', 'Bảo hành ' || v_so_hm || ' hạng mục – không báo giá, không duyệt giá');
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

-- ---------------------------------------------------------------------
-- 5. Duyệt giá: xe bảo hiểm phải có giám định viên (cũng áp dụng cho báo giá bổ sung; duyet_gia_chia gọi hàm này)
-- ---------------------------------------------------------------------
create or replace function public.duyet_gia(p_ho_so bigint, p_ngay date, ket_qua jsonb) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
  if h.nguon_tt <> 'khach' and h.gdv_id is null then
    raise exception 'Chưa có giám định viên. Bấm "Sửa" ở mục Thông tin xe và khách để ghi GDV trước khi nhập kết quả duyệt giá.'; end if;
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

-- ---------------------------------------------------------------------
-- 12. Chia công nợ bảo hiểm / khách: dùng chung cho duyệt giá và sửa sau này
-- ---------------------------------------------------------------------
create or replace function app.chia_cong_no(p_ho_so bigint, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_tong numeric; v_khach_dong numeric; v_khau_tru numeric;
begin
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then
    return jsonb_build_object('tong', (select coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)), 0)
      from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong')), 'bao_hiem', 0, 'khach', null);
  end if;
  select coalesce(sum(public.tien_dong_co_vat(gia_duyet, true, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'bao_hiem'), 0)
       + coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0),
       coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0)
    into v_tong, v_khach_dong
  from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong');
  if p_khach_tra is null then p_khach_tra := v_khach_dong + h.khau_tru_giam_tru; end if;
  if p_khach_tra < v_khach_dong then
    raise exception 'Khách chi trả ít nhất % đ (các dòng khách tự trả).', app.vnd(v_khach_dong); end if;
  if p_khach_tra > v_tong then
    raise exception 'Khách chi trả không được vượt tổng giá duyệt % đ.', app.vnd(v_tong); end if;
  v_khau_tru := round(p_khach_tra - v_khach_dong);
  if v_khau_tru <> h.khau_tru_giam_tru then
    update public.ho_so set khau_tru_giam_tru = v_khau_tru where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
      'Chia công nợ: bảo hiểm chi trả ' || app.vnd(v_tong - p_khach_tra) || ' đ, khách chi trả ' || app.vnd(p_khach_tra)
      || ' đ (khấu trừ – giảm trừ ' || app.vnd(v_khau_tru) || ' đ)');
    perform app.cap_nhat_dong(p_ho_so);
  end if;
  return jsonb_build_object('tong', v_tong, 'bao_hiem', v_tong - p_khach_tra, 'khach', p_khach_tra, 'khau_tru', v_khau_tru);
end $$;

create or replace function public.duyet_gia_chia(p_ho_so bigint, p_ngay date, ket_qua jsonb, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public.duyet_gia(p_ho_so, p_ngay, ket_qua);
  return app.chia_cong_no(p_ho_so, p_khach_tra);
end $$;

-- Sửa lại cách chia công nợ sau khi đã duyệt (xe bảo hiểm): CVDV, kế toán, quản lý chung, giám đốc
create or replace function public.sua_chia_cong_no(p_ho_so bigint, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('cvdv','ke_toan','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then raise exception 'Xe khách ngoài bảo hiểm không chia công nợ.'; end if;
  if h.trang_thai in ('huy') then raise exception 'Hồ sơ đã hủy.'; end if;
  if not exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong')) then
    raise exception 'Hồ sơ chưa có hạng mục được duyệt.'; end if;
  if p_khach_tra is null or p_khach_tra < 0 then raise exception 'Nhập số tiền khách chi trả.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  return app.chia_cong_no(p_ho_so, p_khach_tra);
end $$;

-- ---------------------------------------------------------------------
-- 9. Thu tiền & giao xe một lần (kế toán, giám đốc)
-- p: {so_tien, tai_khoan_id, ngay?, noi_dung?, duyet_con_no?, so_hd_bao_hiem?, so_hd_khach?, cam_nhan_khach?}
-- ---------------------------------------------------------------------
create or replace function public.thu_tien_giao_xe(p_ho_so bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; t record; v_tien numeric := coalesce((p->>'so_tien')::numeric, 0); m public.muc_thu_chi;
  v_phieu bigint; x public.xe; k public.khach_hang;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'dat_kcs' then raise exception 'Xe chưa đạt KCS thì không giao được.'; end if;
  if v_tien < 0 then raise exception 'Số tiền không hợp lệ.'; end if;
  if v_tien > 0 then
    if (p->>'tai_khoan_id') is null then raise exception 'Chọn tài khoản nhận tiền.'; end if;
    select * into t from app.tien_ho_so(p_ho_so);
    if v_tien > t.con_no_khach then
      raise exception 'Khách trả % đ nhiều hơn số còn nợ % đ. Thu đúng số nợ ở đây; phần dư (tiền bo, trả dư) lập ở Thu chi → Phiếu thu.',
        app.vnd(v_tien), app.vnd(t.con_no_khach);
    end if;
    select * into m from public.muc_thu_chi where loai = 'thu' and tinh_chat = 'thu_khach' and hoat_dong order by id limit 1;
    if not found then raise exception 'Chưa có mục thu "Thu của khách (gắn xe)" trong Danh mục.'; end if;
    select * into x from public.xe where id = h.xe_id;
    select * into k from public.khach_hang where id = h.khach_hang_id;
    v_phieu := public.lap_phieu_thu(jsonb_build_object(
      'tai_khoan_id', (p->>'tai_khoan_id')::bigint, 'muc_id', m.id, 'so_tien', v_tien,
      'ngay', coalesce((p->>'ngay')::date, current_date),
      'noi_dung', coalesce(nullif(trim(p->>'noi_dung'),''), 'Khách trả sửa xe ' || coalesce(public.bien_so_hien_thi(x.bien_so), h.ma) || ' – ' || k.ten || ' (giao xe)'),
      'phan_bo', jsonb_build_array(jsonb_build_object('ho_so_id', p_ho_so, 'so_tien', v_tien))));
  end if;
  -- Quản lý chung / giám đốc tích "duyệt giao khi còn nợ" ngay trong hộp thoại
  if coalesce((p->>'duyet_con_no')::boolean, false) and h.cho_giao_no_boi is null and app.co_vai_tro('quan_ly','giam_doc') then
    perform public.duyet_giao_xe_con_no(p_ho_so);
  end if;
  -- Giao xe: không nhận khấu trừ ở bước này (chỉ sửa qua Chia công nợ)
  perform public.giao_xe(p_ho_so, (p - 'so_tien' - 'tai_khoan_id' - 'ngay' - 'noi_dung' - 'duyet_con_no' - 'khau_tru_giam_tru'));
  select * into t from app.tien_ho_so(p_ho_so);
  return jsonb_build_object('phieu_id', v_phieu, 'da_thu', v_tien, 'con_no_khach', t.con_no_khach, 'con_no_bh', t.con_no_bh);
end $$;

-- ---------------------------------------------------------------------
-- 10. Dịch vụ nhanh: thu tiền ngay (kế toán / giám đốc gửi thu_ngay + tai_khoan_id)
-- ---------------------------------------------------------------------
create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint; v_to text := nullif(p->>'to_id', ''); v_nguoi text := nullif(trim(p->>'nguoi_lam'),'');
  v_thu_ngay boolean := coalesce((p->>'thu_ngay')::boolean, false); m public.muc_thu_chi;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_to is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Chọn tổ làm: Điện – máy – gầm hoặc Detailing.'; end if;
  if v_to is not null then
    if v_to not in ('DMG', 'DT') then raise exception 'Dịch vụ nhanh chỉ do tổ Điện – máy – gầm hoặc Detailing làm.'; end if;
    select ten into v_nguoi from public.to_thuc_hien where id = v_to;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if v_thu_ngay then
    if not app.co_vai_tro('ke_toan','giam_doc') then raise exception 'Chỉ kế toán hoặc giám đốc thu tiền ngay; người khác ghi dịch vụ rồi kế toán thu ở Thu chi.' using errcode = '42501'; end if;
    if (p->>'tai_khoan_id') is null then raise exception 'Chọn tài khoản nhận tiền.'; end if;
    select * into m from public.muc_thu_chi where loai = 'thu' and tinh_chat = 'thu_dich_vu_nhanh' and hoat_dong order by id limit 1;
    if not found then raise exception 'Chưa có mục thu "Thu dịch vụ nhanh" trong Danh mục.'; end if;
  end if;

  -- Khách: tìm theo SĐT (như tiếp nhận); có tên mới thì cập nhật
  if v_dt <> '' then
    select id into v_kh from public.khach_hang where dien_thoai = v_dt;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(p->>'ten_khach'),''), 'Chưa có tên'), v_dt) returning id into v_kh;
    elsif nullif(trim(p->>'ten_khach'),'') is not null then
      update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
    end if;
  end if;
  -- Xe: tìm theo biển số; chưa có thì tạo (loại xe để trống, lần tiếp nhận sau bổ sung)
  if v_bs is not null then
    select id, khach_hang_id into v_xe, v_kh_xe from public.xe where bien_so = v_bs;
    if v_xe is not null and v_kh is null then v_kh := v_kh_xe; end if;
    if v_xe is null then
      insert into public.xe (bien_so, khach_hang_id) values (v_bs, v_kh) returning id into v_xe;
    elsif v_dt <> '' then
      update public.xe set khach_hang_id = v_kh where id = v_xe;
    end if;
  end if;

  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi, xe_id, khach_hang_id, so_km, to_id)
  values (v_cn, v_ngay, v_bs, trim(p->>'dich_vu'), v_nguoi,
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid(), v_xe, v_kh, v_km::int, v_to)
  returning id into v_id;

  -- Thu tiền ngay: phiếu thu gắn lượt dịch vụ, cùng giao dịch (lỗi thì cả lượt dịch vụ không ghi)
  if v_thu_ngay then
    perform public.lap_phieu_thu(jsonb_build_object(
      'tai_khoan_id', (p->>'tai_khoan_id')::bigint, 'muc_id', m.id, 'so_tien', (p->>'so_tien')::numeric, 'ngay', v_ngay,
      'noi_dung', 'Dịch vụ nhanh: ' || trim(p->>'dich_vu') || coalesce(' – ' || public.bien_so_hien_thi(v_bs), ''),
      'phan_bo', jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id', v_id, 'so_tien', (p->>'so_tien')::numeric))));
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. Việc cần xử lý: xe bảo hiểm chưa có giám định viên
-- (v_canh_bao giữ nguyên các dòng cũ – 004; 008 chạy sau cũng đã có dòng này)
-- ---------------------------------------------------------------------
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
select 'thieu_gdv', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Xe bảo hiểm chưa có giám định viên – ghi GDV (Sửa ở Thông tin xe và khách) trước khi nhập kết quả duyệt giá', hs.chi_nhanh_id
from hs where hs.nguon_tt <> 'khach' and hs.gdv_id is null and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs')
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

grant select on public.v_canh_bao to authenticated;
revoke all on public.v_canh_bao from anon;

-- Quyền gọi hàm
revoke execute on function public.thu_tien_giao_xe(bigint, jsonb), public.sua_chia_cong_no(bigint, numeric), app.chia_cong_no(bigint, numeric) from public, anon;
grant execute on function public.thu_tien_giao_xe(bigint, jsonb), public.sua_chia_cong_no(bigint, numeric) to authenticated;

notify pgrst, 'reload schema';

-- ======================= 037_hieu_nang.sql =======================
-- 037 – Hiệu năng (rà soát lần 2, 14/10/2026)
-- Đo với 5.000 hồ sơ / 25.000 hạng mục / 10.000 phiếu: bảng phiếu thu chi 1 tháng mất 36 giây,
-- danh sách hồ sơ 4–6 giây, cảnh báo Việc hôm nay 11 giây. Nguyên nhân:
--   1. Chính sách phân quyền (RLS) gọi app.vai_tro() → đọc bảng nhan_vien cho TỪNG DÒNG.
--      Bọc (select …) để Postgres tính một lần cho cả câu lệnh (khuyến nghị của Supabase).
--   2. Thiếu chỉ mục ở các cột hay nối/lọc.
--   3. v_ho_so gọi hàm tien_ho_so(h.id) cho từng hồ sơ → tính theo tập (group by) một lần.
-- Tương thích ngược: không đổi tên/cột nào đang dùng; v_ho_so thêm cột so_km ở cuối.

-- ---------------------------------------------------------------------
-- 1. Bọc (select …) quanh các hàm vai trò trong mọi policy
-- ---------------------------------------------------------------------
create or replace function app.boc_select(bt text) returns text
language sql immutable as $$
  select case when bt is null then null else
    replace(replace(
      regexp_replace(
      regexp_replace(
      regexp_replace(
      regexp_replace(
      regexp_replace(bt,
        'app\.duoc_xem_chi_nhanh\(([^()]*)\)', '(__GD__ OR (\1 = __CN__))', 'g'),
        'app\.co_vai_tro\(([^()]*)\)', '(select app.co_vai_tro(\1))', 'g'),
        'app\.(la_nhan_vien|xem_nhu_nhan_vien|la_co_dong|chi_nhanh|to_cua_toi)\(\)', '(select app.\1())', 'g'),
        'auth\.uid\(\)', '(select auth.uid())', 'g'),
        '\(select \(select ', '((select ', 'g'),
      '__GD__', '(select app.co_vai_tro(''giam_doc''))'),
      '__CN__', '(select app.chi_nhanh())')
  end
$$;

do $$
declare r record; v_using text; v_check text; v_sql text; n int := 0;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where (schemaname = 'public' or (schemaname = 'storage' and tablename = 'objects' and policyname like 'ho-so-xe%'))
      and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(app\.(co_vai_tro|la_nhan_vien|xem_nhu_nhan_vien|la_co_dong|chi_nhanh|duoc_xem_chi_nhanh|to_cua_toi)|auth\.uid)\('
      and (coalesce(qual, '') || coalesce(with_check, '')) !~ '\(select (app|auth)\.'
  loop
    v_using := app.boc_select(r.qual);
    v_check := app.boc_select(r.with_check);
    v_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if v_using is not null then v_sql := v_sql || ' using (' || v_using || ')'; end if;
    if v_check is not null then v_sql := v_sql || ' with check (' || v_check || ')'; end if;
    execute v_sql;
    n := n + 1;
  end loop;
  raise notice '037: đã bọc (select …) cho % policy', n;
end $$;

-- ---------------------------------------------------------------------
-- 2. Chỉ mục còn thiếu
-- ---------------------------------------------------------------------
create index if not exists phan_bo_phieu_idx on public.phan_bo (phieu_id);
create index if not exists phan_bo_dvn_idx on public.phan_bo (dich_vu_nhanh_id) where dich_vu_nhanh_id is not null;
create index if not exists lo_kho_hang_all_idx on public.lo_kho (hang_id);
create index if not exists ho_so_ngay_vao_idx on public.ho_so (ngay_vao desc);
create index if not exists ho_so_khach_idx on public.ho_so (khach_hang_id);
create index if not exists ho_so_nhat_ky_hs_idx on public.ho_so_nhat_ky (ho_so_id);
create index if not exists ho_so_tep_hs_idx on public.ho_so_tep (ho_so_id);
create index if not exists phat_sinh_hs_idx on public.phat_sinh (ho_so_id);
create index if not exists kcs_hs_idx on public.kcs (ho_so_id);
create index if not exists phieu_xuat_dong_phieu_idx on public.phieu_xuat_dong (phieu_id);
create index if not exists phieu_nhap_dong_phieu_idx on public.phieu_nhap_dong (phieu_id);
create index if not exists phieu_nhap_dong_hang_idx on public.phieu_nhap_dong (hang_id);
create index if not exists phieu_nhap_ncc_idx on public.phieu_nhap (nha_cung_cap_id, chi_nhanh_id, trang_thai);
create index if not exists phieu_thu_chi_ncc_idx on public.phieu_thu_chi (nha_cung_cap_id) where nha_cung_cap_id is not null;
create index if not exists phieu_thu_chi_muc_idx on public.phieu_thu_chi (muc_id);
create index if not exists hang_muc_ngay_duyet_idx on public.hang_muc (ngay_duyet);
create index if not exists dich_vu_nhanh_cn_ngay_idx on public.dich_vu_nhanh (chi_nhanh_id, ngay);
create index if not exists xuat_lo_lo_idx on public.xuat_lo (lo_id);

-- Hàm tiền một hồ sơ: báo cho Postgres biết chỉ trả 1 dòng (mặc định đoán 1000 → kế hoạch sai)
alter function app.tien_ho_so(bigint) rows 1;
alter function public.tien_ho_so(bigint) rows 1;

-- ---------------------------------------------------------------------
-- 3. v_ho_so: tiền tính theo tập, một lần cho cả danh sách
--    (hai hàm security definer thay cho tien_ho_so từng dòng; tự kiểm quyền như RLS của bảng)
-- ---------------------------------------------------------------------
create or replace function app.duyet_theo_ho_so()
returns table (ho_so_id bigint, bh numeric, kh numeric, ngay_duyet_dau date, co_dong_cho_duyet boolean)
language sql stable security definer set search_path = public rows 5000 as $$
  select m.ho_so_id,
    coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat))
      filter (where m.nguoi_tra = 'bao_hiem' and m.trang_thai in ('duyet','dang_lam','xong')), 0),
    coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat))
      filter (where m.nguoi_tra = 'khach' and m.trang_thai in ('duyet','dang_lam','xong')), 0),
    min(m.ngay_duyet) filter (where m.trang_thai in ('duyet','dang_lam','xong')),
    bool_or(m.trang_thai = 'cho_duyet')
  from public.hang_muc m
  join public.ho_so h on h.id = m.ho_so_id
  where (select app.xem_nhu_nhan_vien())
    and ((select app.co_vai_tro('giam_doc')) or h.chi_nhanh_id = (select app.chi_nhanh()))
  group by m.ho_so_id
$$;

create or replace function app.da_thu_theo_ho_so()
returns table (ho_so_id bigint, bh numeric, kh numeric)
language sql stable security definer set search_path = public rows 5000 as $$
  select pb.ho_so_id,
    coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0),
    coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0)
  from public.phan_bo pb
  join public.phieu_thu_chi p on p.id = pb.phieu_id
  where pb.ho_so_id is not null and p.trang_thai = 'hieu_luc'
    and (select app.xem_nhu_nhan_vien())
    and ((select app.co_vai_tro('giam_doc')) or p.chi_nhanh_id = (select app.chi_nhanh()))
  group by pb.ho_so_id
$$;

revoke execute on function app.duyet_theo_ho_so(), app.da_thu_theo_ho_so() from public, anon;
grant execute on function app.duyet_theo_ho_so(), app.da_thu_theo_ho_so() to authenticated;

-- Bản thật đang dùng v_ho_so của 006 (còn 2 cột văn phòng bảo hiểm đã bỏ) → phải drop rồi tạo lại,
-- kéo theo v_canh_bao (phụ thuộc v_ho_so) tạo lại y nguyên bản 036. Giao diện bản thật chỉ hiển thị
-- van_phong_bh nếu có nên không lỗi khi thiếu cột.
drop view if exists public.v_canh_bao;
drop view if exists public.v_ho_so;

create view public.v_ho_so with (security_invoker = true) as
select
  h.id, h.ma, h.chi_nhanh_id, h.loai, h.ho_so_goc_id, h.trang_thai, h.ngay_vao, h.hen_giao, h.giao_luc,
  h.nguon_tt, h.tinh_trang_xe, h.tu_van, h.han_bao_hiem, h.khau_tru_giam_tru, h.giam_gia,
  h.so_hd_bao_hiem, h.so_hd_khach, h.cam_nhan_khach, h.gui_hs_ngay, h.hoa_hong_gdv, h.hoa_hong_ghi_chu,
  h.cham_soc_luc, h.cham_soc_ket_qua, h.hen_bao_duong, h.ly_do_huy, h.cho_giao_no_boi, h.tu_excel,
  h.xe_id, h.khach_hang_id, h.hang_bh_id, h.gdv_id,
  x.bien_so, public.bien_so_hien_thi(x.bien_so) as bien_so_hien_thi, x.dong_xe_id, x.mau,
  concat_ws(' ', hx.ten, dx.ten) as xe, k.ten as ten_khach, k.dien_thoai, b.ten as hang_bh,
  coalesce(h.gdv_ten_tam, g.ten) as gdv, coalesce(g.la_cho_them, false) as gdv_cho_them,
  d.ngay_duyet_dau,
  coalesce(d.co_dong_cho_duyet, false) as co_dong_cho_duyet,
  coalesce(ps.co_phat_sinh, false) as co_phat_sinh,
  coalesce(d.bh, 0) as bh_duyet,
  coalesce(d.kh, 0) as khach_duyet,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru as phai_thu_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia as phai_thu_khach,
  coalesce(t.bh, 0) as da_thu_bh,
  coalesce(t.kh, 0) as da_thu_khach,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru - coalesce(t.bh, 0) as con_no_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia - coalesce(t.kh, 0) as con_no_khach,
  h.han_bh_than_vo,
  h.so_km
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
left join app.duyet_theo_ho_so() d on d.ho_so_id = h.id
left join (select p.ho_so_id, bool_or(not p.da_xu_ly) as co_phat_sinh from public.phat_sinh p group by p.ho_so_id) ps on ps.ho_so_id = h.id
left join app.da_thu_theo_ho_so() t on t.ho_so_id = h.id;

grant select on public.v_ho_so to authenticated;
revoke all on public.v_ho_so from anon;

-- v_canh_bao: tạo lại y nguyên bản 036
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
select 'thieu_gdv', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Xe bảo hiểm chưa có giám định viên – ghi GDV (Sửa ở Thông tin xe và khách) trước khi nhập kết quả duyệt giá', hs.chi_nhanh_id
from hs where hs.nguon_tt <> 'khach' and hs.gdv_id is null and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs')
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

grant select on public.v_canh_bao to authenticated;
revoke all on public.v_canh_bao from anon;

analyze;
notify pgrst, 'reload schema';

-- ======================= 038_sua_loi_ra_soat_2.sql =======================
-- =====================================================================
-- 038 (14/10/2026): RÀ SOÁT LẦN 2 – nhóm A: lỗi số liệu / kẹt việc (anh Thuận chọn sửa cả 4 nhóm)
--  A2. Hủy phiếu chi rồi chi lại cùng đề nghị → lỗi "duplicate key": cột de_nghi_chi_id UNIQUE kể cả phiếu hủy
--      → chỉ duy nhất trong các phiếu HIỆU LỰC.
--  A3. Hoa hồng GDV nhập/sửa sau khi tháng (duyệt giá) đã chốt → KQKD sống lệch số chốt → chặn như mọi khoản khác.
--      Hủy phiếu có kỳ chi phí thuộc tháng đã chốt → chặn.
--  A4. Hồ sơ kẹt "Đang sửa": phát sinh bị từ chối hết / xóa dòng cuối → tự sang "Chờ KCS" (trigger hang_muc).
--  A5. Công nợ NCC với vai Kho: "đã trả" = 0 vì RLS không cho kho đọc phiếu chi → tính bằng hàm có quyền.
--  A6. Khách trả dư (nợ âm) sau giao xe: KHÔNG tự đóng hồ sơ (phải trả lại hoặc ghi tiền bo); cảnh báo ở Việc hôm nay.
--      Tiền bo tách 2 phiếu trong MỘT giao dịch (p.tien_bo) thay vì giao diện gọi 2 lần.
--  A7. Hủy phiếu nhập sau khi phiếu xuất (đã hủy) từng lấy hàng của lô → lỗi khóa ngoại xuat_lo → dọn xuat_lo của
--      phiếu xuất đã hủy trước; nếu còn phiếu xuất hiệu lực thì báo tiếng Việt.
--  A8. Tra cứu xe: "số lần vào gara" không đếm hồ sơ hủy; cảnh báo "chưa gửi hồ sơ BH" bỏ hồ sơ chuyển từ Excel.
--  Tương thích ngược: không đổi tên/tham số hàm nào; tra_cuu_xe bỏ văn phòng BH (giao diện cũ chỉ hiển thị nếu có).
-- =====================================================================

-- ---------------------------------------------------------------------
-- A2. Đề nghị chi: duy nhất trong các phiếu hiệu lực
-- ---------------------------------------------------------------------
alter table public.phieu_thu_chi drop constraint if exists phieu_thu_chi_de_nghi_chi_id_key;
create unique index if not exists phieu_thu_chi_de_nghi_hieu_luc_idx
  on public.phieu_thu_chi (de_nghi_chi_id) where de_nghi_chi_id is not null and trang_thai = 'hieu_luc';

-- ---------------------------------------------------------------------
-- A3. Hoa hồng GDV: chặn khi tháng duyệt giá đầu tiên (tháng KQKD ghi hoa hồng) đã chốt
-- ---------------------------------------------------------------------
create or replace function public.nhap_hoa_hong_gdv(p_ho_so bigint, p_so_tien numeric, p_ghi_chu text default null,
  p_bo_qua_canh_bao boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; v_tl numeric := app.cai_dat_so('hoa_hong_canh_bao_ty_le', 0.15); v_thang date;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.gdv_id is null then raise exception 'Hồ sơ không có giám định viên.'; end if;
  if p_so_tien is null or p_so_tien < 0 then raise exception 'Số tiền hoa hồng không hợp lệ.'; end if;
  select min(m.ngay_duyet) into v_thang from public.hang_muc m
   where m.ho_so_id = p_ho_so and m.trang_thai in ('duyet','dang_lam','xong');
  if v_thang is not null then perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_thang); end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.bh_duyet > 0 and p_so_tien > t.bh_duyet * v_tl and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Hoa hồng % đ lớn hơn % giá duyệt bảo hiểm. Kiểm tra lại có gõ thừa số 0 không?',
      app.vnd(p_so_tien), round(v_tl * 100)::text || '%';
  end if;
  update public.ho_so set hoa_hong_gdv = p_so_tien, hoa_hong_ghi_chu = nullif(trim(p_ghi_chu),'') where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Nhập hoa hồng GDV ' || p_so_tien || ' đ');
end $$;

-- Hủy phiếu: thêm kiểm tra kỳ chi phí (phiếu ghi tháng sau nhưng tính vào tháng trước đã chốt)
create or replace function public.huy_phieu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; x bigint; d public.phieu_thu_chi;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ky_chi_phi); end if;
  if r.trang_thai = 'huy' then raise exception 'Phiếu đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) where id = p_id;
  if r.de_nghi_chi_id is not null then
    update public.de_nghi_chi set trang_thai = 'da_duyet' where id = r.de_nghi_chi_id;
  end if;
  for x in select distinct ho_so_id from public.phan_bo where phieu_id = p_id and ho_so_id is not null loop
    perform app.cap_nhat_dong(x);
  end loop;
  if r.phieu_doi_ung_id is not null then
    select * into d from public.phieu_thu_chi where id = r.phieu_doi_ung_id for update;
    if found and d.trang_thai = 'hieu_luc' then
      update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) || ' (hủy cùng phiếu chi hộ đối ứng)' where id = d.id;
      if d.de_nghi_chi_id is not null then
        update public.de_nghi_chi set trang_thai = 'da_duyet' where id = d.de_nghi_chi_id;
      end if;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- A4. Hết hạng mục còn làm (từ chối phát sinh / xóa dòng) khi xe đang sửa → tự sang Chờ KCS
-- ---------------------------------------------------------------------
-- bao_xong đã tự chuyển Chờ KCS khi dòng cuối xong; trigger chỉ xét khi dòng bị TỪ CHỐI hoặc XÓA.
create or replace function app.kiem_tra_xong_sua() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_hs bigint := coalesce(new.ho_so_id, old.ho_so_id);
begin
  if tg_op = 'UPDATE' and new.trang_thai not in ('tu_choi') then return null; end if;
  if exists (select 1 from public.ho_so where id = v_hs and trang_thai = 'dang_sua')
     and not exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai in ('cho_duyet','duyet','dang_lam'))
     and exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai = 'xong') then
    perform app.doi_trang_thai(v_hs, 'cho_kcs', 'Hết hạng mục còn làm (phát sinh bị từ chối / xóa) – chờ KCS');
  end if;
  return null;
end $$;

drop trigger if exists hang_muc_xong_sua on public.hang_muc;
create trigger hang_muc_xong_sua
  after update of trang_thai or delete on public.hang_muc
  for each row
  when (pg_trigger_depth() < 2)
  execute function app.kiem_tra_xong_sua();

-- ---------------------------------------------------------------------
-- A5. Công nợ NCC: "đã trả" tính bằng hàm có quyền (vai kho không đọc được phiếu chi)
-- ---------------------------------------------------------------------
create or replace function app.da_tra_ncc()
returns table (nha_cung_cap_id bigint, chi_nhanh_id text, da_tra numeric)
language sql stable security definer set search_path = public rows 200 as $$
  select t.nha_cung_cap_id, t.chi_nhanh_id, sum(t.so_tien)
  from public.phieu_thu_chi t join public.muc_thu_chi m on m.id = t.muc_id
  where t.nha_cung_cap_id is not null and t.loai = 'chi' and t.trang_thai = 'hieu_luc' and m.tinh_chat = 'tra_ncc'
    and (select app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong'))
    and ((select app.co_vai_tro('giam_doc')) or t.chi_nhanh_id = (select app.chi_nhanh()))
  group by 1, 2
$$;
revoke execute on function app.da_tra_ncc() from public, anon;
grant execute on function app.da_tra_ncc() to authenticated;

create or replace view public.v_cong_no_ncc with (security_invoker = true) as
select n.id as nha_cung_cap_id, n.ten, c.chi_nhanh_id,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p
            where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai = 'da_khop'), 0) as da_nhap,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p
            where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai in ('cho_khop','treo')), 0) as cho_khop,
  coalesce(t.da_tra, 0) as da_tra
from public.nha_cung_cap n
cross join (select id as chi_nhanh_id from public.chi_nhanh) c
left join app.da_tra_ncc() t on t.nha_cung_cap_id = n.id and t.chi_nhanh_id = c.chi_nhanh_id
where (select app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong'))
  and ((select app.co_vai_tro('giam_doc')) or c.chi_nhanh_id = (select app.chi_nhanh()));
grant select on public.v_cong_no_ncc to authenticated;

-- ---------------------------------------------------------------------
-- A6. Khách trả dư: không tự đóng hồ sơ; tiền bo tách phiếu trong một giao dịch
-- ---------------------------------------------------------------------
create or replace function app.cap_nhat_dong(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; co_bh boolean; het_no boolean;
begin
  select * into h from public.ho_so where id = p_id;
  if h.trang_thai not in ('da_giao','da_gui_hs','dong') then return; end if;
  select * into t from app.tien_ho_so(p_id);
  co_bh := t.phai_thu_bh > 0;
  -- Khách trả dư (nợ âm) là tiền phải TRẢ LẠI khách → chưa xong; hồ sơ chuyển từ Excel giữ cách cũ (số liệu cũ có thể lệch)
  het_no := t.con_no_bh <= 0 and (case when h.tu_excel then t.con_no_khach <= 0 else t.con_no_khach = 0 end);
  if het_no and (not co_bh or h.gui_hs_ngay is not null) then
    perform app.doi_trang_thai(p_id, 'dong', 'Tự đóng: đã giao xe và hết công nợ');
  elsif h.trang_thai = 'dong' then
    perform app.doi_trang_thai(p_id,
      case when h.gui_hs_ngay is not null then 'da_gui_hs' else 'da_giao' end,
      case when t.con_no_khach < 0 then 'Mở lại: khách trả dư – cần trả lại hoặc ghi tiền bo' else 'Mở lại: phát sinh công nợ' end);
  end if;
end $$;

update public.muc_thu_chi set he_thong = 'tien_bo' where he_thong is null and loai = 'thu' and ten = 'Tiền bo của khách';

-- lap_phieu_thu: thêm p.tien_bo (phần dư là tiền bo) → 2 phiếu trong một giao dịch; giao diện cũ không gửi thì như trước
create or replace function public.lap_phieu_thu(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  m public.muc_thu_chi; v_id bigint; v_tong numeric; v_bo numeric := coalesce((p->>'tien_bo')::numeric, 0);
  v_so_tien numeric := coalesce((p->>'so_tien')::numeric, 0); v_muc_bo bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'thu' then raise exception 'Chưa chọn mục thu.'; end if;
  if v_so_tien <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_bo < 0 or v_bo >= v_so_tien then raise exception 'Tiền bo không hợp lệ.'; end if;
  if v_bo > 0 then
    if m.tinh_chat <> 'thu_khach' then raise exception 'Tiền bo chỉ tách từ phiếu khách thanh toán sửa chữa.'; end if;
    select id into v_muc_bo from public.muc_thu_chi where loai = 'thu' and hoat_dong and (he_thong = 'tien_bo' or ten = 'Tiền bo của khách')
      order by he_thong nulls last limit 1;
    if v_muc_bo is null then raise exception 'Chưa có mục thu "Tiền bo của khách" (Danh mục → Mục thu chi).'; end if;
  end if;
  if m.tinh_chat = 'thu_bao_hiem' and (p->>'hang_bh_id') is null then raise exception 'Chọn hãng bảo hiểm chuyển tiền.'; end if;
  if m.tinh_chat = 'thu_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;

  select coalesce(sum((x->>'so_tien')::numeric), 0) into v_tong from jsonb_array_elements(coalesce(p->'phan_bo','[]'::jsonb)) x;
  if m.tinh_chat in ('thu_khach','thu_coc','thu_dich_vu_nhanh') and v_tong <> v_so_tien - v_bo then
    raise exception 'Tiền khách trả phải gắn đủ vào hồ sơ xe hoặc dịch vụ (đang gắn % / % đ).',
      app.vnd(v_tong), app.vnd(v_so_tien - v_bo);
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung,
    hang_bh_id, don_vi_lien_quan_id, tao_boi)
  values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, m.id, v_so_tien - v_bo, nullif(trim(p->>'noi_dung'),''),
    (p->>'hang_bh_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, auth.uid())
  returning id into v_id;
  -- Khách trả dư (cho_tra_du = true): gắn đủ vào xe dù vượt số còn nợ → hồ sơ ghi khách trả dư, trả lại sau
  perform app.phan_bo_phieu(v_id, p->'phan_bo', case when m.tinh_chat = 'thu_khach' and coalesce((p->>'cho_tra_du')::boolean, false) then 'thu_khach_du' else m.tinh_chat end);
  if v_bo > 0 then
    insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung, tao_boi)
    values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, v_muc_bo, v_bo,
      'Tiền bo của khách – ' || coalesce(nullif(trim(p->>'noi_dung'),''), 'phiếu thu #' || v_id), auth.uid());
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- A7. Hủy phiếu nhập: dọn xuat_lo của phiếu xuất đã hủy; báo rõ nếu còn phiếu xuất hiệu lực
-- ---------------------------------------------------------------------
create or replace function public.huy_phieu_nhap(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_nhap; v_px text;
begin
  perform app.yeu_cau('kho','giam_doc');
  select * into r from public.phieu_nhap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu nhập.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai not in ('cho_khop','treo') then raise exception 'Phiếu đã khớp hóa đơn hoặc đã hủy – không hủy được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  select string_agg(distinct px.ma, ', ') into v_px
  from public.xuat_lo xl
  join public.phieu_xuat_dong d on d.id = xl.phieu_xuat_dong_id
  join public.phieu_xuat px on px.id = d.phieu_id
  where px.trang_thai = 'hieu_luc'
    and xl.lo_id in (select l.id from public.lo_kho l join public.phieu_nhap_dong nd on nd.id = l.phieu_nhap_dong_id where nd.phieu_id = p_id);
  if v_px is not null then
    raise exception 'Hàng của phiếu nhập này đã xuất ở phiếu % – hủy phiếu xuất đó trước.', v_px;
  end if;
  if exists (select 1 from public.lo_kho l join public.phieu_nhap_dong d on d.id = l.phieu_nhap_dong_id
             where d.phieu_id = p_id and l.con_lai < l.so_luong) then
    raise exception 'Hàng của phiếu này đã xuất một phần (kiểm kê / điều chỉnh) – không hủy được.';
  end if;
  -- phiếu xuất đã hủy vẫn còn dòng xuat_lo trỏ vào lô → xóa trước
  delete from public.xuat_lo xl using public.phieu_xuat_dong d, public.phieu_xuat px
  where d.id = xl.phieu_xuat_dong_id and px.id = d.phieu_id and px.trang_thai = 'huy'
    and xl.lo_id in (select l.id from public.lo_kho l join public.phieu_nhap_dong nd on nd.id = l.phieu_nhap_dong_id where nd.phieu_id = p_id);
  delete from public.lo_kho where phieu_nhap_dong_id in (select id from public.phieu_nhap_dong where phieu_id = p_id);
  update public.phieu_nhap set trang_thai = 'huy', ghi_chu = concat_ws(' · ', ghi_chu, 'Hủy: ' || trim(p_ly_do)) where id = p_id;
  if r.de_nghi_mua_id is not null then
    update public.de_nghi_mua set trang_thai = 'da_duyet' where id = r.de_nghi_mua_id and trang_thai = 'da_nhap';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- A8. Tra cứu xe: số lần vào không đếm hồ sơ hủy (bỏ văn phòng BH – giao diện mới không dùng)
-- ---------------------------------------------------------------------
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
    'so_lan_vao', (select count(*) from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy'),
    'ho_so_mo', (select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'trang_thai', h.trang_thai))
                 from public.ho_so h where h.xe_id = x.id and h.trang_thai not in ('dong','huy')),
    'ho_so_gan_nhat', (select jsonb_build_object('id', h.id, 'ma', h.ma, 'nguon_tt', h.nguon_tt, 'hang_bh_id', h.hang_bh_id,
                         'gdv_id', h.gdv_id)
                       from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy' order by h.id desc limit 1))
  into r
  from public.xe x
  left join public.dong_xe dx on dx.id = x.dong_xe_id
  left join public.khach_hang k on k.id = x.khach_hang_id
  where x.bien_so = v_bs;
  return r;
end $$;

-- v_canh_bao: thêm "khách trả dư"; "chưa gửi hồ sơ BH" bỏ hồ sơ từ Excel
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
where hs.nguon_tt <> 'khach' and hs.trang_thai = 'da_giao' and not hs.tu_excel and hs.loai <> 'bao_hanh'
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
select 'khach_tra_du', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  hs.ten_khach || ' trả dư ' || app.vnd(-hs.con_no_khach) || ' đ – lập đề nghị chi "Trả lại cọc cho khách" hoặc ghi tiền bo', hs.chi_nhanh_id
from hs where hs.giao_luc is not null and hs.con_no_khach < 0 and not hs.tu_excel
union all
select 'thieu_hoa_hong', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Chưa nhập hoa hồng cho GDV ' || coalesce(hs.gdv, ''), hs.chi_nhanh_id
from hs where hs.gdv_id is not null and hs.giao_luc is not null and hs.hoa_hong_gdv is null and not hs.tu_excel
union all
select 'gdv_cho_them', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'GDV "' || coalesce(hs.gdv, '') || '" chưa có trong danh sách – kế toán thêm vào Cài đặt rồi gắn lại', hs.chi_nhanh_id
from hs where hs.gdv_cho_them
union all
select 'thieu_gdv', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Xe bảo hiểm chưa có giám định viên – ghi GDV (Sửa ở Thông tin xe và khách) trước khi nhập kết quả duyệt giá', hs.chi_nhanh_id
from hs where hs.nguon_tt <> 'khach' and hs.gdv_id is null and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs')
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
where d.trang_thai = 'cho_duyet' and (select app.co_vai_tro('giam_doc','quan_ly'))
  and d.nguoi_de_nghi <> (select auth.uid()) and (not d.can_giam_doc or (select app.co_vai_tro('giam_doc')));
grant select on public.v_canh_bao to authenticated;

notify pgrst, 'reload schema';

-- ======================= 040_toi_uu_giao_dien.sql =======================
-- =====================================================================
-- 040 (14/10/2026): RÀ SOÁT LẦN 2 – nhóm D (phần giao diện): bớt lượt tải, chặn ghi trùng
--  1. v_ho_so thêm 2 cột ở cuối: nguoi_tiep_theo, giao_viec_luc → "Việc hôm nay" đọc hồ sơ MỘT lần
--     (trước đây đọc v_ho_so 4 lần + v_viec_ho_so 2 lần, nối tiếp nhau).
--  2. bang_viec_to trả thêm nguon_tt, loai, chi_nhanh_id: thanh 9 bước nhỏ ở bảng việc bỏ đúng bước
--     (xe khách không có bước hồ sơ BH; bảo hành không báo giá/duyệt giá) và ảnh phát sinh lưu đúng thư mục.
--  3. nhap_xuat_ton(tháng): cộng nhập – xuất – tồn ở máy chủ (trước đây tải cả lịch sử thẻ kho về trình duyệt).
--  4. them_tep: chỉ nhận đường dẫn thuộc đúng thư mục của hồ sơ và bước hợp lệ (không gắn nhầm ảnh hồ sơ khác).
--  5. Sinh mã chứng từ kho (PN, PX, DX, DM, KK): khóa theo tiền tố mã trong giao dịch → hai người lập
--     cùng lúc không còn lỗi "duplicate key".
--  Tương thích ngược: chỉ THÊM cột/khóa JSON, không đổi tên hay tham số hàm nào.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. v_ho_so: thêm nguoi_tiep_theo, giao_viec_luc (giữ nguyên các cột cũ, đúng thứ tự)
-- ---------------------------------------------------------------------
create or replace view public.v_ho_so with (security_invoker = true) as
select
  h.id, h.ma, h.chi_nhanh_id, h.loai, h.ho_so_goc_id, h.trang_thai, h.ngay_vao, h.hen_giao, h.giao_luc,
  h.nguon_tt, h.tinh_trang_xe, h.tu_van, h.han_bao_hiem, h.khau_tru_giam_tru, h.giam_gia,
  h.so_hd_bao_hiem, h.so_hd_khach, h.cam_nhan_khach, h.gui_hs_ngay, h.hoa_hong_gdv, h.hoa_hong_ghi_chu,
  h.cham_soc_luc, h.cham_soc_ket_qua, h.hen_bao_duong, h.ly_do_huy, h.cho_giao_no_boi, h.tu_excel,
  h.xe_id, h.khach_hang_id, h.hang_bh_id, h.gdv_id,
  x.bien_so, public.bien_so_hien_thi(x.bien_so) as bien_so_hien_thi, x.dong_xe_id, x.mau,
  concat_ws(' ', hx.ten, dx.ten) as xe, k.ten as ten_khach, k.dien_thoai, b.ten as hang_bh,
  coalesce(h.gdv_ten_tam, g.ten) as gdv, coalesce(g.la_cho_them, false) as gdv_cho_them,
  d.ngay_duyet_dau,
  coalesce(d.co_dong_cho_duyet, false) as co_dong_cho_duyet,
  coalesce(ps.co_phat_sinh, false) as co_phat_sinh,
  coalesce(d.bh, 0) as bh_duyet,
  coalesce(d.kh, 0) as khach_duyet,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru as phai_thu_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia as phai_thu_khach,
  coalesce(t.bh, 0) as da_thu_bh,
  coalesce(t.kh, 0) as da_thu_khach,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru - coalesce(t.bh, 0) as con_no_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia - coalesce(t.kh, 0) as con_no_khach,
  h.han_bh_than_vo,
  h.so_km,
  h.nguoi_tiep_theo,
  h.giao_viec_luc
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
left join app.duyet_theo_ho_so() d on d.ho_so_id = h.id
left join (select p.ho_so_id, bool_or(not p.da_xu_ly) as co_phat_sinh from public.phat_sinh p group by p.ho_so_id) ps on ps.ho_so_id = h.id
left join app.da_thu_theo_ho_so() t on t.ho_so_id = h.id;

grant select on public.v_ho_so to authenticated;
revoke all on public.v_ho_so from anon;

create index if not exists ho_so_nguoi_tiep_idx on public.ho_so (nguoi_tiep_theo) where nguoi_tiep_theo is not null;
create index if not exists ho_so_giao_luc_idx on public.ho_so (giao_luc) where giao_luc is not null;

-- ---------------------------------------------------------------------
-- 2. Bảng việc tổ: thêm nguồn, loại hồ sơ, chi nhánh
-- ---------------------------------------------------------------------
create or replace function public.bang_viec_to() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','ke_toan','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select to_id, chi_nhanh_id into v_to, v_cn from public.nhan_vien where id = auth.uid();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ho_so_id', h.id, 'ma', h.ma, 'bien_so', public.bien_so_hien_thi(x.bien_so),
      'xe', concat_ws(' ', hx.ten, dx.ten, x.mau), 'hen_giao', h.hen_giao, 'trang_thai', h.trang_thai,
      'tinh_trang_xe', h.tinh_trang_xe,
      'nguon_tt', h.nguon_tt, 'loai', h.loai, 'chi_nhanh_id', h.chi_nhanh_id,
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

-- ---------------------------------------------------------------------
-- 3. Nhập – xuất – tồn theo tháng ('YYYY-MM'), tính ở máy chủ, quyền đọc như thẻ kho (RLS người gọi)
-- ---------------------------------------------------------------------
create or replace function public.nhap_xuat_ton(p_thang text)
returns table (hang_id bigint, dau numeric, gt_dau numeric, nhap numeric, gt_nhap numeric, xuat numeric, gt_xuat numeric)
language sql stable security invoker set search_path = public as $$
  with k as (select to_date(p_thang || '-01', 'YYYY-MM-DD') as tu)
  select t.hang_id,
    coalesce(sum(t.so_luong) filter (where t.ngay < k.tu), 0),
    coalesce(sum(t.gia_tri)  filter (where t.ngay < k.tu), 0),
    coalesce(sum(t.so_luong) filter (where t.ngay >= k.tu and t.so_luong > 0), 0),
    coalesce(sum(t.gia_tri)  filter (where t.ngay >= k.tu and t.so_luong > 0), 0),
    coalesce(-sum(t.so_luong) filter (where t.ngay >= k.tu and t.so_luong <= 0), 0),
    coalesce(-sum(t.gia_tri)  filter (where t.ngay >= k.tu and t.so_luong <= 0), 0)
  from public.v_the_kho t, k
  where t.ngay < (k.tu + interval '1 month')::date
  group by t.hang_id
$$;
revoke execute on function public.nhap_xuat_ton(text) from public, anon;
grant execute on function public.nhap_xuat_ton(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. them_tep: đường dẫn phải nằm trong thư mục "<chi nhánh>/<mã hồ sơ>/" và bước hợp lệ
-- ---------------------------------------------------------------------
create or replace function public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text) returns bigint
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_id bigint; v_goc text;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  v_goc := h.chi_nhanh_id || '/' || h.ma || '/';
  if p_duong_dan is null or left(p_duong_dan, length(v_goc)) <> v_goc or position('..' in p_duong_dan) > 0 then
    raise exception 'Tệp không thuộc thư mục của hồ sơ % – tải lại ảnh từ trang hồ sơ.', h.ma;
  end if;
  if p_buoc not in ('tiep_nhan','duyet_gia','phat_sinh','kcs','giao_xe','ho_so_bh','khac') then
    raise exception 'Bước của tệp không hợp lệ.';
  end if;
  if coalesce(p_loai, 'anh') not in ('anh','bien_ban') then raise exception 'Loại tệp không hợp lệ.'; end if;
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, coalesce(p_loai, 'anh'), p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. Mã chứng từ kho: khóa theo tiền tố trong giao dịch (người sau chờ người trước ghi xong rồi lấy số kế tiếp)
-- ---------------------------------------------------------------------
create or replace function app.ma_chung_tu(p_loai text, p_cn text, p_ngay date, p_bang text) returns text
language plpgsql security definer set search_path = public as $$
declare v_goc text := p_cn || '-' || p_loai || to_char(p_ngay, 'YYMM') || '-'; v_n int; v_ma text; v_co boolean;
begin
  perform pg_advisory_xact_lock(hashtext('ma_chung_tu_' || p_bang || '_' || v_goc));
  execute format('select count(*) + 1 from public.%I where ma like $1', p_bang) into v_n using v_goc || '%';
  loop
    v_ma := v_goc || lpad(v_n::text, 3, '0');
    execute format('select exists (select 1 from public.%I where ma = $1)', p_bang) into v_co using v_ma;
    exit when not v_co;
    v_n := v_n + 1;
  end loop;
  return v_ma;
end $$;

notify pgrst, 'reload schema';

-- ======================= 041_thieu_logic.sql =======================
-- =====================================================================
-- 041 (14/10/2026): RÀ SOÁT LẦN 2 – nhóm B: thiếu logic nghiệp vụ (anh Thuận chọn sửa)
--  B9.  Giảm giá cho khách sau khi đã giao xe: được duyệt (giao diện thêm nút), không vượt phần khách phải trả,
--       hết nợ thì hồ sơ tự đóng. Gửi hồ sơ BH không được ghi ngày trước ngày giao xe.
--  B10. Phát sinh của hồ sơ bảo hành xử lý được: thêm hạng mục bảo hành (miễn phí) hoặc đánh dấu "không cần làm thêm";
--       mọi hồ sơ đều có cách đóng một phát sinh không cần báo giá (trước đây cảnh báo treo mãi).
--  B11. Trưởng nhóm: tra cứu xe nhanh không thấy SĐT khách, không tìm theo SĐT, không đổi tên khách hay chủ xe
--       (vẫn thấy tên khách và "có thể tư vấn" để làm dịch vụ nhanh – quyết định 032); không đọc được giá vốn lô kho
--       (tồn chỉ có số lượng); chỉ thấy đề xuất vật tư của tổ mình.
--  B12. Giám đốc không tự khóa tài khoản của chính mình. Hủy hồ sơ đã thu cọc: hỏi lại và Việc hôm nay nhắc trả cọc.
--  B13. Hai người tiếp nhận / ghi dịch vụ nhanh cùng xe, cùng SĐT, cùng lúc: chờ nhau thay vì lỗi trùng khóa tiếng Anh.
--  Thêm (rà soát chi tiết):
--   - Hủy dịch vụ nhanh lưu lý do, người hủy, lúc hủy.
--   - Nhập "xuất ngay cho xe": trừ đúng lô vừa nhập (giá vốn xe = giá mua riêng), không lấy lô cũ.
--   - Phiếu thu/chi không được ghi trước ngày đầu kỳ của tài khoản (số dư quỹ sẽ lệch không giải thích được).
--   - Báo sự cố đồ nghề không trùng quá số đang có; kiểm tra tuần bỏ qua món kho giao nhưng nhóm chưa nhận.
--   - Mục thu chi / tài khoản / thuế suất đã dùng trong tháng chốt: không đổi được phần làm lệch số đã chốt;
--     mỗi chi nhánh chỉ một tài khoản "mặc định nhận tiền".
--  Tương thích ngược: không đổi tên hay bỏ tham số hàm nào (huy_ho_so thêm tham số có mặc định – giao diện cũ gọi như trước).
-- =====================================================================

-- ---------------------------------------------------------------------
-- B9. Giảm giá (cả sau khi giao xe); gửi hồ sơ BH không trước ngày giao
-- ---------------------------------------------------------------------
create or replace function public.duyet_giam_gia(p_ho_so bigint, p_so_tien numeric, p_ly_do text) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; t record;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai in ('dong','huy') then raise exception 'Hồ sơ đã đóng.'; end if;
  if p_so_tien is null or p_so_tien < 0 then raise exception 'Số tiền giảm giá không hợp lệ.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do giảm giá.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  if h.giam_gia_ngay is not null then perform app.yeu_cau_thang_mo(h.chi_nhanh_id, h.giam_gia_ngay); end if;
  -- Tổng giảm giá không vượt phần khách phải trả trước giảm giá (khách duyệt + khấu trừ – giảm trừ)
  select * into t from app.tien_ho_so(p_ho_so);
  if p_so_tien > t.phai_thu_khach + h.giam_gia then
    raise exception 'Giảm giá % đ lớn hơn phần khách phải trả (% đ).', app.vnd(p_so_tien), app.vnd(t.phai_thu_khach + h.giam_gia);
  end if;
  update public.ho_so set giam_gia = p_so_tien, giam_gia_ngay = current_date, giam_gia_duyet_boi = auth.uid()
  where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Duyệt giảm giá ' || p_so_tien || ' đ: ' || trim(p_ly_do));
  perform app.cap_nhat_dong(p_ho_so);   -- đã giao xe, giảm xong hết nợ → tự đóng
end $$;

create or replace function public.gui_ho_so_bh(p_ho_so bigint, p_ngay date) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then raise exception 'Xe khách lẻ không có hồ sơ bảo hiểm.'; end if;
  if h.trang_thai <> 'da_giao' then raise exception 'Chỉ gửi hồ sơ bảo hiểm sau khi đã giao xe.'; end if;
  if p_ngay is null or p_ngay > current_date then raise exception 'Ngày gửi không hợp lệ.'; end if;
  if h.giao_luc is not null and p_ngay < (h.giao_luc at time zone 'Asia/Ho_Chi_Minh')::date then
    raise exception 'Ngày gửi hồ sơ không được trước ngày giao xe (%).', to_char(h.giao_luc at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY');
  end if;
  update public.ho_so set gui_hs_ngay = p_ngay where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'da_gui_hs', 'Gửi hồ sơ bảo hiểm ngày ' || to_char(p_ngay, 'DD/MM/YYYY'));
  perform app.cap_nhat_dong(p_ho_so);
end $$;

-- ---------------------------------------------------------------------
-- B10. Phát sinh: đánh dấu đã xử lý (không cần làm thêm); hồ sơ bảo hành thêm hạng mục miễn phí
-- ---------------------------------------------------------------------
alter table public.phat_sinh add column if not exists xu_ly_ghi_chu text;
alter table public.phat_sinh add column if not exists xu_ly_boi uuid;
alter table public.phat_sinh add column if not exists xu_ly_luc timestamptz;

create or replace function public.xu_ly_phat_sinh(p_ho_so bigint, p_ghi_chu text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if nullif(trim(p_ghi_chu),'') is null then
    raise exception 'Ghi cách xử lý (ví dụ: không cần làm thêm, đã làm trong hạng mục cũ).'; end if;
  update public.phat_sinh set da_xu_ly = true, xu_ly_ghi_chu = trim(p_ghi_chu), xu_ly_boi = auth.uid(), xu_ly_luc = now()
  where ho_so_id = p_ho_so and not da_xu_ly;
  if not found then raise exception 'Hồ sơ không có phát sinh nào đang chờ.'; end if;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Xử lý phát sinh: ' || trim(p_ghi_chu));
end $$;

-- Hồ sơ bảo hành: thêm hạng mục làm lại miễn phí (giá 0, coi như đã duyệt) → giao tổ ở "Giao thêm cho tổ"
create or replace function public.them_hang_muc_bao_hanh(p_ho_so bigint, p_dong jsonb) returns int
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; d jsonb; v_lan int; v_n int := 0;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.loai <> 'bao_hanh' then
    raise exception 'Chỉ hồ sơ bảo hành thêm hạng mục miễn phí; hồ sơ sửa chữa lập báo giá bổ sung.'; end if;
  if h.trang_thai not in ('da_duyet','dang_sua','cho_kcs') then raise exception 'Hồ sơ không ở bước sửa chữa.'; end if;
  if jsonb_typeof(p_dong) <> 'array' then raise exception 'Ghi ít nhất một hạng mục.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  select coalesce(max(lan_bao_gia), 0) + 1 into v_lan from public.hang_muc where ho_so_id = p_ho_so;
  for d in select * from jsonb_array_elements(p_dong) loop
    if nullif(trim(d->>'ten'),'') is null then continue; end if;
    insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd, trang_thai, gia_duyet, ngay_duyet)
    values (p_ho_so, v_lan, trim(d->>'ten'), coalesce(nullif(d->>'nhom',''), 'dong'), 'khach', 0, false, 'duyet', 0, current_date);
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Ghi ít nhất một hạng mục.'; end if;
  update public.phat_sinh set da_xu_ly = true, xu_ly_ghi_chu = 'Thêm ' || v_n || ' hạng mục bảo hành', xu_ly_boi = auth.uid(), xu_ly_luc = now()
  where ho_so_id = p_ho_so and not da_xu_ly;
  if h.trang_thai = 'cho_kcs' then
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Thêm ' || v_n || ' hạng mục bảo hành – làm tiếp');
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Thêm ' || v_n || ' hạng mục bảo hành');
  end if;
  return v_n;
end $$;

revoke execute on function public.xu_ly_phat_sinh(bigint, text), public.them_hang_muc_bao_hanh(bigint, jsonb) from public, anon;
grant execute on function public.xu_ly_phat_sinh(bigint, text), public.them_hang_muc_bao_hanh(bigint, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- B11. Trưởng nhóm: không xem SĐT khách khi tra xe nhanh, không sửa khách; không đọc giá vốn kho;
--      chỉ thấy đề xuất vật tư của tổ mình
-- ---------------------------------------------------------------------
create or replace function public.tra_cuu_xe_nhanh(p_tu text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_gon text := upper(regexp_replace(coalesce(p_tu,''), '[^0-9A-Za-z]', '', 'g')); r jsonb;
  v_tn boolean := app.co_vai_tro('truong_nhom') and not app.la_nhan_vien();   -- 041: trưởng nhóm không xem SĐT khách
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if length(v_gon) < 2 then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(t.d order by t.chinh_xac desc, t.bien_so), '[]'::jsonb) into r
  from (
    select x.bien_so, (x.bien_so = v_gon) as chinh_xac, jsonb_build_object(
      'xe_id', x.id, 'bien_so', public.bien_so_hien_thi(x.bien_so), 'mau', x.mau,
      'loai_xe', nullif(concat_ws(' ', hx.ten, dx.ten), ''),
      'ten_khach', nullif(k.ten, 'Chưa có tên'), 'dien_thoai', case when not v_tn then k.dien_thoai end,
      'han_bh_than_vo', x.han_bh_than_vo, 'han_bao_hiem', x.han_bao_hiem,
      'lan_cuoi', (select jsonb_build_object('ngay', l.ngay, 'loai', l.loai, 'noi_dung', l.noi_dung, 'ma', l.ma, 'id', l.id)
                   from (select (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date as ngay, 'ho_so' as loai, h.ma, h.id,
                                left(h.tinh_trang_xe, 200) as noi_dung, h.ngay_vao as luc
                         from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy'
                         union all
                         select d.ngay, 'dich_vu_nhanh', null, d.id, d.dich_vu, d.tao_luc
                         from public.dich_vu_nhanh d where d.xe_id = x.id and d.trang_thai = 'hieu_luc') l
                   order by l.ngay desc, l.luc desc limit 1),
      'km_truoc', (select jsonb_build_object('so', l.so_km, 'ngay', l.ngay)
                   from (select h.so_km, (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date as ngay, h.ngay_vao as luc
                         from public.ho_so h where h.xe_id = x.id and h.so_km is not null and h.trang_thai <> 'huy'
                         union all
                         select d.so_km, d.ngay, d.tao_luc from public.dich_vu_nhanh d
                         where d.xe_id = x.id and d.so_km is not null and d.trang_thai = 'hieu_luc') l
                   order by l.ngay desc, l.luc desc limit 1),
      'tu_van', (select h.tu_van from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy'
                 and nullif(trim(h.tu_van), '') is not null and h.tu_van !~* '^\d{2}/\d{2}/\d{4}: (không|\(chuyển từ excel\))\.?$'
                 order by h.ngay_vao desc limit 1),
      'so_lan_vao', (select count(*) from public.ho_so h where h.xe_id = x.id and h.trang_thai <> 'huy')
                  + (select count(*) from public.dich_vu_nhanh d where d.xe_id = x.id and d.trang_thai = 'hieu_luc')) as d
    from public.xe x
    left join public.khach_hang k on k.id = x.khach_hang_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    where x.bien_so like '%' || v_gon || '%'
       or (not v_tn and v_gon ~ '^[0-9]{4,}$' and k.dien_thoai like '%' || v_gon || '%')
    order by (x.bien_so = v_gon) desc, x.bien_so
    limit 8
  ) t;
  return r;
end $$;

-- Lô kho (có giá vốn từng lô): chỉ nhân viên văn phòng và cổ đông đọc
alter policy doc on public.lo_kho using (
  (select app.xem_nhu_nhan_vien()) and ((select app.co_vai_tro('giam_doc')) or chi_nhanh_id = (select app.chi_nhanh())));

-- Tồn theo mã hàng: số lượng cho người được xem kho (cả trưởng nhóm để đề xuất vật tư), giá trị chỉ nhân viên văn phòng
create or replace function app.ton_theo_hang()
returns table (hang_id bigint, ton numeric, gia_tri numeric)
language sql stable security definer set search_path = public rows 500 as $$
  select l.hang_id, sum(l.con_lai),
    case when (select app.xem_nhu_nhan_vien()) then round(sum(l.con_lai * l.don_gia_von)) end
  from public.lo_kho l
  where ((select app.xem_nhu_nhan_vien()) or (select app.co_vai_tro('truong_nhom')))
    and ((select app.co_vai_tro('giam_doc')) or l.chi_nhanh_id = (select app.chi_nhanh()))
  group by l.hang_id
$$;
revoke execute on function app.ton_theo_hang() from public, anon;
grant execute on function app.ton_theo_hang() to authenticated;

create or replace view public.v_ton_kho with (security_invoker = true) as
select h.id, h.chi_nhanh_id, h.ma, h.ten, h.nhom, h.dvt, h.dvt_nhap, h.he_so, h.ton_toi_thieu, h.nha_cung_cap_id,
  n.ten as nha_cung_cap, h.ghi_chu, h.hoat_dong,
  coalesce(t.ton, 0) as ton, coalesce(t.gia_tri, 0) as gia_tri,
  coalesce(t.ton, 0) <= h.ton_toi_thieu and h.ton_toi_thieu > 0 as duoi_toi_thieu,
  (select pd.don_gia from public.phieu_nhap_dong pd join public.phieu_nhap pn on pn.id = pd.phieu_id
   where pd.hang_id = h.id and pn.trang_thai <> 'huy' order by pn.ngay desc, pd.id desc limit 1) as gia_nhap_gan_nhat
from public.hang_kho h
left join public.nha_cung_cap n on n.id = h.nha_cung_cap_id
left join app.ton_theo_hang() t on t.hang_id = h.id;
grant select on public.v_ton_kho to authenticated;
revoke all on public.v_ton_kho from anon;

-- Đề xuất vật tư (view chạy quyền chủ để trưởng nhóm thấy biển số xe): trưởng nhóm chỉ thấy phiếu của tổ mình / mình lập
create or replace view public.v_de_xuat as
 SELECT d.id, d.chi_nhanh_id, d.ma, d.ho_so_id, d.to_id, d.ghi_chu, d.trang_thai, d.nguoi_lap, d.tao_luc,
    h.ma AS ma_ho_so,
    public.bien_so_hien_thi(x.bien_so) AS bien_so,
    h.trang_thai AS trang_thai_ho_so,
    nv.ho_ten AS nguoi_lap_ten,
    (SELECT count(*) FROM public.de_xuat_dong dd WHERE dd.de_xuat_id = d.id) AS so_dong,
    (SELECT count(*) FROM public.de_xuat_dong dd WHERE dd.de_xuat_id = d.id AND dd.cho_mua) AS so_dong_cho_mua
   FROM public.de_xuat_vat_tu d
     JOIN public.ho_so h ON h.id = d.ho_so_id
     JOIN public.xe x ON x.id = h.xe_id
     LEFT JOIN public.nhan_vien nv ON nv.id = d.nguoi_lap
  WHERE ((select app.co_vai_tro('giam_doc')) OR d.chi_nhanh_id = (select app.chi_nhanh()))
    AND ((select app.xem_nhu_nhan_vien())
         OR ((select app.co_vai_tro('truong_nhom')) AND (d.to_id = (select app.to_cua_toi()) OR d.nguoi_lap = (select auth.uid()))));
grant select on public.v_de_xuat to authenticated;
revoke all on public.v_de_xuat from anon;

-- ---------------------------------------------------------------------
-- B12. Giám đốc không tự khóa mình; hủy hồ sơ đã thu cọc thì hỏi lại
-- ---------------------------------------------------------------------
create or replace function public.luu_nhan_vien(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_vt text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(p->'vai_tro') x), '{}');
begin
  perform app.yeu_cau('giam_doc');
  if p_id = auth.uid() and not ('giam_doc' = any(v_vt)) then
    raise exception 'Không tự bỏ quyền giám đốc của chính mình được.'; end if;
  if p_id = auth.uid() and not coalesce((p->>'hoat_dong')::boolean, true) then
    raise exception 'Không tự khóa tài khoản của chính mình được (khóa rồi sẽ không ai mở lại được).'; end if;
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

-- Hủy hồ sơ: thêm p_bo_qua_canh_bao (mặc định null = giao diện cũ, không hỏi như trước).
-- Giao diện mới gửi false: hồ sơ đã thu cọc → hỏi lại, nhắc trả cọc (Việc hôm nay cũng nhắc tới khi trả xong).
drop function if exists public.huy_ho_so(bigint, text);
create or replace function public.huy_ho_so(p_ho_so bigint, p_ly_do text, p_bo_qua_canh_bao boolean default null) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_ngay date; t record;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('tiep_nhan','bao_gia','da_duyet') then
    raise exception 'Xe đã vào sửa thì không hủy hồ sơ được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.da_thu_khach > 0 and p_bo_qua_canh_bao is not null and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Khách đã đặt cọc % đ cho hồ sơ này. Hủy xong nhớ lập đề nghị chi "Trả lại cọc cho khách" chọn xe này (Việc hôm nay sẽ nhắc đến khi trả xong). Vẫn hủy?',
      app.vnd(t.da_thu_khach);
  end if;
  for v_ngay in select distinct ngay_duyet from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'duyet' loop
    perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_ngay);
  end loop;
  update public.hang_muc set trang_thai = 'tu_choi' where ho_so_id = p_ho_so and trang_thai in ('cho_duyet','duyet');
  update public.ho_so set ly_do_huy = trim(p_ly_do) where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'huy', 'Hủy: ' || trim(p_ly_do));
end $$;
revoke execute on function public.huy_ho_so(bigint, text, boolean) from public, anon;
grant execute on function public.huy_ho_so(bigint, text, boolean) to authenticated;

create or replace view public.v_canh_bao with (security_invoker = true) as
with tat as (select * from public.v_ho_so),           -- đọc hồ sơ một lần cho mọi nhánh
hs as (select * from tat where trang_thai not in ('huy')),
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
where hs.nguon_tt <> 'khach' and hs.trang_thai = 'da_giao' and not hs.tu_excel and hs.loai <> 'bao_hanh'
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
select 'khach_tra_du', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  hs.ten_khach || ' trả dư ' || app.vnd(-hs.con_no_khach) || ' đ – lập đề nghị chi "Trả lại cọc cho khách" hoặc ghi tiền bo', hs.chi_nhanh_id
from hs where hs.giao_luc is not null and hs.con_no_khach < 0 and not hs.tu_excel
union all
-- 041: hồ sơ đã HỦY nhưng còn giữ tiền cọc của khách → nhắc trả lại (trước đây không ai nhắc)
select 'coc_treo', 'cao', c.id, c.ma, c.bien_so_hien_thi,
  'Hồ sơ đã hủy còn giữ ' || app.vnd(-c.con_no_khach) || ' đ tiền cọc của ' || c.ten_khach || ' – lập đề nghị chi "Trả lại cọc cho khách"', c.chi_nhanh_id
from tat c where c.trang_thai = 'huy' and c.con_no_khach < 0 and not c.tu_excel
union all
select 'thieu_hoa_hong', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Chưa nhập hoa hồng cho GDV ' || coalesce(hs.gdv, ''), hs.chi_nhanh_id
from hs where hs.gdv_id is not null and hs.giao_luc is not null and hs.hoa_hong_gdv is null and not hs.tu_excel
union all
select 'gdv_cho_them', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'GDV "' || coalesce(hs.gdv, '') || '" chưa có trong danh sách – kế toán thêm vào Cài đặt rồi gắn lại', hs.chi_nhanh_id
from hs where hs.gdv_cho_them
union all
select 'thieu_gdv', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Xe bảo hiểm chưa có giám định viên – ghi GDV (Sửa ở Thông tin xe và khách) trước khi nhập kết quả duyệt giá', hs.chi_nhanh_id
from hs where hs.nguon_tt <> 'khach' and hs.gdv_id is null and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs')
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
where d.trang_thai = 'cho_duyet' and (select app.co_vai_tro('giam_doc','quan_ly'))
  and d.nguoi_de_nghi <> (select auth.uid()) and (not d.can_giam_doc or (select app.co_vai_tro('giam_doc')));
grant select on public.v_canh_bao to authenticated;
revoke all on public.v_canh_bao from anon;

-- ---------------------------------------------------------------------
-- B13. Tiếp nhận / dịch vụ nhanh: khóa theo SĐT, biển số, tiền tố mã hồ sơ (hai người cùng lúc không lỗi trùng)
-- ---------------------------------------------------------------------
create or replace function public.tiep_nhan_xe(p jsonb) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare
  v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ngay timestamptz := coalesce((p->>'ngay_vao')::timestamptz, now());
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_nguon text := p->>'nguon_tt';
  v_gdv public.giam_dinh_vien;
  v_kh bigint; v_xe bigint; v_ma text; v_goc text; v_n int; v_id bigint; v_mo text;
  v_loai text := coalesce(p->>'loai', 'sua_chua');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_bao_hanh boolean := v_loai = 'bao_hanh';
  v_hm jsonb := case when jsonb_typeof(p->'hang_muc') = 'array' then p->'hang_muc' else '[]'::jsonb end;
  d jsonb; v_so_hm int := 0;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  if v_cn is null then raise exception 'Tài khoản chưa gắn chi nhánh.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  -- Bảo hành: làm lại miễn phí, không liên quan bảo hiểm → luôn là nguồn "khách", không hãng BH, không GDV
  if v_bao_hanh then v_nguon := 'khach'; end if;

  if nullif(trim(p->>'ten_khach'),'') is null then raise exception 'Thiếu tên khách.'; end if;
  if v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if (p->>'dong_xe_id') is null then raise exception 'Chưa chọn loại xe.'; end if;
  if v_nguon not in ('bao_hiem','khach','bao_hiem_khach') or v_nguon is null then
    raise exception 'Chưa chọn bảo hiểm nào hay khách lẻ.'; end if;
  if nullif(trim(p->>'tinh_trang_xe'),'') is null then raise exception 'Ghi yêu cầu của khách hàng.'; end if;
  if nullif(trim(p->>'tu_van'),'') is null then raise exception 'Thiếu mục những gì có thể tư vấn (ghi "Không" nếu không có).'; end if;
  if v_nguon <> 'khach' then
    if (p->>'hang_bh_id') is null then raise exception 'Chưa chọn hãng bảo hiểm.'; end if;
    -- 036: giám định viên để trống được (hãng cử sau); bắt buộc trước khi nhập kết quả duyệt giá
    if (p->>'gdv_id') is not null then
      select * into v_gdv from public.giam_dinh_vien where id = (p->>'gdv_id')::bigint;
      if v_gdv.la_cho_them and nullif(trim(p->>'gdv_ten_tam'),'') is null then
        raise exception 'Chọn "GDV mới – chờ thêm" thì phải ghi tên giám định viên.';
      end if;
    end if;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so';
  end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_bao_hanh and (p->>'ho_so_goc_id') is null then
    raise exception 'Hồ sơ bảo hành phải chọn hồ sơ cũ.'; end if;
  if v_bao_hanh then
    for d in select * from jsonb_array_elements(v_hm) loop
      if nullif(trim(d->>'ten'),'') is null then raise exception 'Hạng mục bảo hành thiếu nội dung.'; end if;
      v_so_hm := v_so_hm + 1;
    end loop;
    if v_so_hm > 0 then perform app.yeu_cau_thang_mo(v_cn, current_date); end if;
  end if;

  -- 041: hai người tiếp nhận cùng SĐT / cùng xe / cùng lúc → người sau chờ người trước ghi xong (không lỗi trùng khóa)
  perform pg_advisory_xact_lock(hashtext('khach_' || v_dt));
  if v_bs is not null then perform pg_advisory_xact_lock(hashtext('xe_' || v_bs)); end if;

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

  if v_bao_hanh and not exists (select 1 from public.ho_so where id = (p->>'ho_so_goc_id')::bigint and xe_id = v_xe) then
    raise exception 'Hồ sơ cũ không phải của xe này.';
  end if;

  -- Mã hồ sơ: TK-2610-50H92361, trùng trong tháng thì thêm -2, -3…; chưa có biển: TK-2610-KBS01
  v_goc := v_cn || '-' || to_char(v_ngay at time zone 'Asia/Ho_Chi_Minh', 'YYMM') || '-';
  perform pg_advisory_xact_lock(hashtext('ma_ho_so_' || v_goc));
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
    hang_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, so_km, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), v_km::int, auth.uid())
  returning id into v_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, v_id;
  end if;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', case when v_bao_hanh then 'Tiếp nhận xe bảo hành' else 'Tiếp nhận xe' end);

  -- Bảo hành (036): hạng mục làm lại miễn phí, coi như đã duyệt → lập lệnh sửa chữa được ngay
  if v_bao_hanh and v_so_hm > 0 then
    for d in select * from jsonb_array_elements(v_hm) loop
      insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd, trang_thai, gia_duyet, ngay_duyet)
      values (v_id, 0, trim(d->>'ten'), coalesce(nullif(d->>'nhom',''), 'dong_son'), 'khach', 0, false, 'duyet', 0, current_date);
    end loop;
    perform app.doi_trang_thai(v_id, 'da_duyet', 'Bảo hành ' || v_so_hm || ' hạng mục – không báo giá, không duyệt giá');
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'chi_nhanh_id', v_cn);
end $$;

create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint; v_to text := nullif(p->>'to_id', ''); v_nguoi text := nullif(trim(p->>'nguoi_lam'),'');
  v_thu_ngay boolean := coalesce((p->>'thu_ngay')::boolean, false); m public.muc_thu_chi;
  v_tn boolean := app.co_vai_tro('truong_nhom') and not app.la_nhan_vien();   -- 041: trưởng nhóm không sửa thông tin khách
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_to is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Chọn tổ làm: Điện – máy – gầm hoặc Detailing.'; end if;
  if v_to is not null then
    if v_to not in ('DMG', 'DT') then raise exception 'Dịch vụ nhanh chỉ do tổ Điện – máy – gầm hoặc Detailing làm.'; end if;
    select ten into v_nguoi from public.to_thuc_hien where id = v_to;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if v_thu_ngay then
    if not app.co_vai_tro('ke_toan','giam_doc') then raise exception 'Chỉ kế toán hoặc giám đốc thu tiền ngay; người khác ghi dịch vụ rồi kế toán thu ở Thu chi.' using errcode = '42501'; end if;
    if (p->>'tai_khoan_id') is null then raise exception 'Chọn tài khoản nhận tiền.'; end if;
    select * into m from public.muc_thu_chi where loai = 'thu' and tinh_chat = 'thu_dich_vu_nhanh' and hoat_dong order by id limit 1;
    if not found then raise exception 'Chưa có mục thu "Thu dịch vụ nhanh" trong Danh mục.'; end if;
  end if;

  -- Khách: tìm theo SĐT (như tiếp nhận); có tên mới thì cập nhật.
  -- Trưởng nhóm: không sửa khách cũ; xe đã có trong sổ thì giữ chủ xe cũ, bỏ qua SĐT gõ thêm.
  if v_dt <> '' and not (v_tn and v_bs is not null and exists (select 1 from public.xe where bien_so = v_bs)) then
    perform pg_advisory_xact_lock(hashtext('khach_' || v_dt));
    select id into v_kh from public.khach_hang where dien_thoai = v_dt;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(p->>'ten_khach'),''), 'Chưa có tên'), v_dt) returning id into v_kh;
    elsif nullif(trim(p->>'ten_khach'),'') is not null and not v_tn then
      update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
    end if;
  end if;
  -- Xe: tìm theo biển số; chưa có thì tạo (loại xe để trống, lần tiếp nhận sau bổ sung)
  if v_bs is not null then
    perform pg_advisory_xact_lock(hashtext('xe_' || v_bs));
    select id, khach_hang_id into v_xe, v_kh_xe from public.xe where bien_so = v_bs;
    if v_xe is not null and (v_kh is null or v_tn) then v_kh := v_kh_xe; end if;
    if v_xe is null then
      insert into public.xe (bien_so, khach_hang_id) values (v_bs, v_kh) returning id into v_xe;
    elsif v_dt <> '' and not v_tn then
      update public.xe set khach_hang_id = v_kh where id = v_xe;
    end if;
  end if;

  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi, xe_id, khach_hang_id, so_km, to_id)
  values (v_cn, v_ngay, v_bs, trim(p->>'dich_vu'), v_nguoi,
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid(), v_xe, v_kh, v_km::int, v_to)
  returning id into v_id;

  -- Thu tiền ngay: phiếu thu gắn lượt dịch vụ, cùng giao dịch (lỗi thì cả lượt dịch vụ không ghi)
  if v_thu_ngay then
    perform public.lap_phieu_thu(jsonb_build_object(
      'tai_khoan_id', (p->>'tai_khoan_id')::bigint, 'muc_id', m.id, 'so_tien', (p->>'so_tien')::numeric, 'ngay', v_ngay,
      'noi_dung', 'Dịch vụ nhanh: ' || trim(p->>'dich_vu') || coalesce(' – ' || public.bien_so_hien_thi(v_bs), ''),
      'phan_bo', jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id', v_id, 'so_tien', (p->>'so_tien')::numeric))));
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Hủy dịch vụ nhanh: lưu lý do, người hủy, lúc hủy
-- ---------------------------------------------------------------------
alter table public.dich_vu_nhanh add column if not exists ly_do_huy text;
alter table public.dich_vu_nhanh add column if not exists huy_boi uuid;
alter table public.dich_vu_nhanh add column if not exists huy_luc timestamptz;

create or replace function public.huy_dich_vu_nhanh(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.dich_vu_nhanh;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.dich_vu_nhanh where id = p_id for update;
  if not found then raise exception 'Không tìm thấy lượt dịch vụ.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai = 'huy' then raise exception 'Lượt dịch vụ này đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  if exists (select 1 from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
             where pb.dich_vu_nhanh_id = p_id and p.trang_thai = 'hieu_luc') then
    raise exception 'Dịch vụ đã thu tiền. Hủy phiếu thu trước.'; end if;
  update public.dich_vu_nhanh set trang_thai = 'huy', ly_do_huy = trim(p_ly_do), huy_boi = auth.uid(), huy_luc = now() where id = p_id;
end $$;

create or replace view public.v_dich_vu_nhanh with (security_invoker = true) as
select d.id, d.chi_nhanh_id, d.ngay, d.bien_so, d.dich_vu, d.nguoi_lam, d.so_tien, d.xuat_hd, d.trang_thai, d.tao_boi, d.tao_luc,
  public.bien_so_hien_thi(d.bien_so) as bien_so_hien_thi,
  coalesce((select sum(pb.so_tien) from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
            where pb.dich_vu_nhanh_id = d.id and p.trang_thai = 'hieu_luc'), 0) as da_thu,
  d.xe_id, d.khach_hang_id, d.so_km, k.ten as ten_khach, k.dien_thoai,
  d.ly_do_huy
from public.dich_vu_nhanh d
left join public.khach_hang k on k.id = d.khach_hang_id;
grant select on public.v_dich_vu_nhanh to authenticated;
revoke all on public.v_dich_vu_nhanh from anon;

-- ---------------------------------------------------------------------
-- Nhập "xuất ngay cho xe": trừ đúng lô vừa nhập
-- ---------------------------------------------------------------------
create or replace function app.xuat_lo_chi_dinh(p_dong bigint, p_lo bigint, p_sl numeric) returns numeric
language plpgsql security definer set search_path = public as $$
declare l public.lo_kho; v_tien numeric;
begin
  select * into l from public.lo_kho where id = p_lo for update;
  if not found or l.con_lai < p_sl then raise exception 'Lô hàng vừa nhập không đủ để xuất ngay.'; end if;
  update public.lo_kho set con_lai = con_lai - p_sl where id = p_lo;
  insert into public.xuat_lo (phieu_xuat_dong_id, lo_id, so_luong, don_gia_von) values (p_dong, p_lo, p_sl, l.don_gia_von);
  v_tien := round(p_sl * l.don_gia_von);
  update public.phieu_xuat_dong set gia_von = v_tien where id = p_dong;
  return v_tien;
end $$;
revoke execute on function app.xuat_lo_chi_dinh(bigint, bigint, numeric) from public, anon;

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
    -- 041: trừ đúng lô vừa nhập (giá vốn của xe = giá mua riêng cho xe; lô cũ giữ nguyên trong kho)
    for x in select l.id as lo_id, l.hang_id, l.so_luong as sl from public.lo_kho l
             join public.phieu_nhap_dong pd on pd.id = l.phieu_nhap_dong_id where pd.phieu_id = v_id order by pd.id loop
      insert into public.phieu_xuat_dong (phieu_id, hang_id, so_luong) values (v_px, x.hang_id, x.sl) returning id into v_pxd;
      perform app.xuat_lo_chi_dinh(v_pxd, x.lo_id, x.sl);
    end loop;
    perform app.ghi_nhat_ky(hs.id, hs.trang_thai, hs.trang_thai, 'Nhập và xuất ngay phụ tùng cho xe: ' || v_ma || ' → ' || v_px_ma);
    v_xuat := jsonb_build_object('id', v_px, 'ma', v_px_ma);
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'tong_tien', v_tong, 'phieu_xuat', v_xuat);
end $$;

-- ---------------------------------------------------------------------
-- Phiếu thu / chi / chuyển quỹ không ghi trước ngày đầu kỳ của tài khoản
-- (số dư quỹ chỉ cộng phiếu từ ngày đầu kỳ → phiếu ghi lùi làm quỹ lệch mà không ai biết)
-- ---------------------------------------------------------------------
create or replace function app.kiem_ngay_dau_ky() returns trigger
language plpgsql security definer set search_path = public as $$
declare tk record;
begin
  for tk in select id, ten, ngay_dau_ky from public.tai_khoan_quy where id in (new.tai_khoan_id, new.tai_khoan_den_id) loop
    if new.ngay < tk.ngay_dau_ky then
      raise exception 'Ngày phiếu % trước ngày đầu kỳ % của tài khoản "%" – số dư đầu kỳ đã gồm các khoản trước ngày đó. Chọn ngày từ % trở đi (hoặc sửa ngày đầu kỳ ở Danh mục).',
        to_char(new.ngay, 'DD/MM/YYYY'), to_char(tk.ngay_dau_ky, 'DD/MM/YYYY'), tk.ten, to_char(tk.ngay_dau_ky, 'DD/MM/YYYY');
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists phieu_thu_chi_ngay_dau_ky on public.phieu_thu_chi;
create trigger phieu_thu_chi_ngay_dau_ky before insert on public.phieu_thu_chi
  for each row execute function app.kiem_ngay_dau_ky();

-- ---------------------------------------------------------------------
-- Đồ nghề: báo sự cố không trùng quá số; kiểm tra tuần bỏ qua món chưa nhận
-- ---------------------------------------------------------------------
create or replace function public.bao_su_co_tai_san(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.tai_san; v_id bigint; v_so int := coalesce((p->>'so_luong')::int, 1); v_cho int;
begin
  select * into t from public.tai_san where id = (p->>'tai_san_id')::bigint for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if (p->>'loai') not in ('mat','hong') then raise exception 'Chọn mất hay hỏng.'; end if;
  if t.tinh_trang in ('mat','thanh_ly') then raise exception 'Món này đã mất / thanh lý.'; end if;
  if v_so < 1 or v_so > t.so_luong then raise exception 'Số lượng không đúng (đang có %).', t.so_luong; end if;
  if nullif(trim(p->>'mo_ta'),'') is null then raise exception 'Ghi mô tả: mất khi nào, hỏng thế nào.'; end if;
  -- 041: cộng cả sự cố cùng loại đang chờ xử lý (báo lại / bấm hai lần không làm "ghi mất" vượt số đang có)
  select coalesce(sum(so_luong), 0) into v_cho from public.su_co_tai_san
   where tai_san_id = t.id and loai = p->>'loai' and trang_thai = 'cho_xu_ly';
  if v_cho + v_so > t.so_luong then
    raise exception 'Đã báo % % đang chờ xử lý cho món này (đang có %) – không báo thêm quá số đang có. Nếu là báo trùng, chờ quản lý xử lý sự cố đã báo.',
      v_cho, case when p->>'loai' = 'mat' then 'mất' else 'hỏng' end, t.so_luong;
  end if;
  insert into public.su_co_tai_san (chi_nhanh_id, tai_san_id, loai, so_luong, mo_ta, phat_hien_boi)
  values (t.chi_nhanh_id, t.id, p->>'loai', v_so, trim(p->>'mo_ta'), auth.uid()) returning id into v_id;
  if p->>'loai' = 'hong' and t.loai = 'may_moc' then update public.tai_san set tinh_trang = 'hong' where id = t.id; end if;
  perform app.ghi_ls_tai_san(t.id, 'su_co', format('Báo %s %s: %s', case when p->>'loai' = 'mat' then 'mất' else 'hỏng' end, v_so, trim(p->>'mo_ta')));
  return v_id;
end $$;

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
    and not x.cho_nhan   -- 041: món kho đã giao nhưng nhóm chưa nhận thì không bắt kiểm
    and not exists (select 1 from jsonb_array_elements(p->'dong') e where (e->>'tai_san_id')::bigint = x.id);
  if v_thieu_tai_san is not null then raise exception 'Còn món chưa kiểm: %', v_thieu_tai_san; end if;

  insert into public.kiem_tra_tai_san (chi_nhanh_id, nhom_id, loai, nguoi_kiem, nguoi_kiem_ten, cung_kiem, ghi_chu)
  values (v_cn, v_nhom, v_loai, auth.uid(), (select ho_ten from public.nhan_vien where id = auth.uid()), nullif(trim(p->>'cung_kiem'),''), nullif(trim(p->>'ghi_chu'),'')) returning id into v_id;
  for d in select * from jsonb_array_elements(p->'dong') loop
    select * into t from public.tai_san where id = (d->>'tai_san_id')::bigint for update;
    if not found or t.chi_nhanh_id <> v_cn or t.nhom_id <> v_nhom then raise exception 'Có món không thuộc nhóm này.'; end if;
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
    if v_thuc < t.so_luong and not t.cho_nhan then
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

-- ---------------------------------------------------------------------
-- Danh mục đã dùng trong tháng chốt: không đổi phần làm lệch số đã chốt
-- ---------------------------------------------------------------------
-- Mục thu chi: loại / tính chất / nhóm quyết định khoản đó vào lãi lỗ ở dòng nào
create or replace function app.chan_doi_muc_da_chot() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.loai, new.tinh_chat, new.nhom) is distinct from (old.loai, old.tinh_chat, old.nhom)
     and exists (select 1 from public.phieu_thu_chi p
                 join public.chot_thang c on c.chi_nhanh_id = p.chi_nhanh_id
                  and c.thang = date_trunc('month', coalesce(p.ky_chi_phi, p.ngay))::date
                 where p.muc_id = old.id and p.trang_thai = 'hieu_luc') then
    raise exception 'Mục "%" đã có phiếu trong tháng đã chốt sổ: không đổi loại, tính chất hay nhóm được (lãi lỗ đã chốt sẽ lệch). Tạo mục mới cho các phiếu sau.', old.ten;
  end if;
  return new;
end $$;
drop trigger if exists muc_thu_chi_chan_doi on public.muc_thu_chi;
create trigger muc_thu_chi_chan_doi before update on public.muc_thu_chi
  for each row execute function app.chan_doi_muc_da_chot();

-- Tài khoản quỹ: số dư / ngày đầu kỳ không đổi khi đã có phiếu trong tháng chốt; một chi nhánh một tài khoản mặc định
create or replace function app.chan_doi_tai_khoan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.so_du_dau_ky, new.ngay_dau_ky) is distinct from (old.so_du_dau_ky, old.ngay_dau_ky)
     and exists (select 1 from public.phieu_thu_chi p
                 join public.chot_thang c on c.chi_nhanh_id = p.chi_nhanh_id and c.thang = date_trunc('month', p.ngay)::date
                 where (p.tai_khoan_id = old.id or p.tai_khoan_den_id = old.id) and p.trang_thai = 'hieu_luc') then
    raise exception 'Tài khoản "%" đã có phiếu trong tháng đã chốt sổ: không đổi số dư hay ngày đầu kỳ được. Lệch quỹ thì ghi "Kiểm quỹ" hoặc phiếu điều chỉnh.', old.ten;
  end if;
  return new;
end $$;
drop trigger if exists tai_khoan_quy_chan_doi on public.tai_khoan_quy;
create trigger tai_khoan_quy_chan_doi before update on public.tai_khoan_quy
  for each row execute function app.chan_doi_tai_khoan();

create or replace function app.mot_tai_khoan_mac_dinh() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.mac_dinh then
    update public.tai_khoan_quy set mac_dinh = false where chi_nhanh_id = new.chi_nhanh_id and id <> new.id and mac_dinh;
  end if;
  return null;
end $$;
drop trigger if exists tai_khoan_quy_mac_dinh on public.tai_khoan_quy;
create trigger tai_khoan_quy_mac_dinh after insert or update of mac_dinh on public.tai_khoan_quy
  for each row when (new.mac_dinh and pg_trigger_depth() < 1) execute function app.mot_tai_khoan_mac_dinh();

-- Thuế suất VAT: không thêm / sửa / xóa dòng áp dụng từ một tháng đã chốt trở về trước
create or replace function app.chan_doi_thue_suat() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tu date := least(case when tg_op <> 'INSERT' then old.ap_dung_tu end, case when tg_op <> 'DELETE' then new.ap_dung_tu end);
begin
  if exists (select 1 from public.chot_thang where thang >= date_trunc('month', v_tu)::date) then
    raise exception 'Đã có tháng chốt sổ từ %/% trở đi: không đổi thuế suất áp dụng lùi vào tháng đã chốt. Chọn ngày áp dụng trong tháng đang mở.',
      extract(month from v_tu), extract(year from v_tu);
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists thue_suat_vat_chan_doi on public.thue_suat_vat;
create trigger thue_suat_vat_chan_doi before insert or update or delete on public.thue_suat_vat
  for each row execute function app.chan_doi_thue_suat();

revoke execute on function app.kiem_ngay_dau_ky(), app.chan_doi_muc_da_chot(), app.chan_doi_tai_khoan(),
  app.mot_tai_khoan_mac_dinh(), app.chan_doi_thue_suat() from public, anon;

-- ---------------------------------------------------------------------
-- Múi giờ Việt Nam cho mọi hàm có dùng ngày giờ hiện tại (như 033 – áp lại cho hàm tạo mới từ 034 trở đi)
-- ---------------------------------------------------------------------
do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%' or p.prosrc ilike '%localtimestamp%' or p.prosrc ilike '%current_timestamp%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ======================= 042_kqkd_chuyen_nghiep.sql =======================
-- =====================================================================
-- 042 (14/10/2026): RÀ SOÁT LẦN 2 – nhóm C: BÁO CÁO KẾT QUẢ KINH DOANH CHUYÊN NGHIỆP (anh Thuận chọn làm)
--  1. Đủ khoản: HAO HỤT / THỪA KIỂM KÊ vào giá vốn; THU NHẬP KHÁC (mục thu có tích "vào lãi lỗ": trạm sạc, thu khác…);
--     dòng tổng giá vốn, tổng chi phí hoạt động.
--  2. THUẾ GTGT (ước): VAT đầu vào gồm cả hàng nhập kho (phiếu nhập) + chi phí; VAT phải nộp = đầu ra − đầu vào
--     (để chuẩn bị tiền nộp thuế tháng). LÃI KHÔNG GỒM VAT (trước thuế TNDN) tính theo dồn tích:
--     lãi trước thuế (số gồm VAT) − VAT đầu ra + VAT nằm trong giá vốn vật tư ĐÃ XUẤT + VAT trong chi phí
--     (không lấy VAT của hàng mới nhập còn nằm trong kho). Giảm giá giảm cả VAT đầu ra (ước).
--  3. Tháng ĐÃ CHỐT hiện SỐ LÚC CHỐT; số hiện tại khác số chốt thì báo "lệch" (cần mở lại, chốt lại).
--     Chốt LẦN LƯỢT từng tháng; mở lại từ tháng sau cùng; mở lại lưu LỊCH SỬ (ai, lúc nào, lý do, số cũ).
--     Lúc chốt lưu kèm TIỀN – CÔNG NỢ – TỒN KHO cuối tháng (quỹ, phải thu khách / BH, phải trả NCC, tồn kho).
--  4. Xem chi tiết từng ô (chi_tiet_kqkd: cả VAT đầu ra, VAT trong giá vốn, danh sách xe), chi phí theo mục,
--     lãi gộp theo tổ, doanh thu theo tháng tính ở máy chủ.
--  5. Số xe tính theo tháng duyệt giá đầu tiên (không đếm trùng khi lũy kế); thêm lượt dịch vụ nhanh.
--  Tương thích ngược: ket_qua_kinh_doanh giữ đủ các cột cũ (cùng tên, cùng thứ tự) và thêm cột mới ở cuối;
--  v_doanh_thu thêm cột to_id ở cuối. Giao diện cũ của bản thật vẫn đọc được.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Mục thu tính vào "Thu nhập khác" của lãi lỗ
-- ---------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'muc_thu_chi' and column_name = 'vao_lai_lo') then
    alter table public.muc_thu_chi add column vao_lai_lo boolean not null default false;
    -- Mặc định: trạm sạc, thu khác… là thu nhập của gara; tiền bo (của thợ) và phí bảo hiểm thu hộ thì không
    alter table public.muc_thu_chi disable trigger muc_thu_chi_chan_doi;
    update public.muc_thu_chi set vao_lai_lo = true
     where loai = 'thu' and tinh_chat = 'thu_khac' and he_thong is distinct from 'tien_bo'
       and ten not in ('Tiền bo của khách', 'Khách mua bảo hiểm');
    alter table public.muc_thu_chi enable trigger muc_thu_chi_chan_doi;
  end if;
end $$;
comment on column public.muc_thu_chi.vao_lai_lo is
  'Mục thu "thu khác" tính vào Thu nhập khác của kết quả kinh doanh (trạm sạc, thu khác). Tiền bo của thợ, phí bảo hiểm thu hộ: không tích.';

-- Mục đã có phiếu trong tháng chốt: thêm "vao_lai_lo" vào các trường không đổi được
create or replace function app.chan_doi_muc_da_chot() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.loai, new.tinh_chat, new.nhom, new.vao_lai_lo) is distinct from (old.loai, old.tinh_chat, old.nhom, old.vao_lai_lo)
     and exists (select 1 from public.phieu_thu_chi p
                 join public.chot_thang c on c.chi_nhanh_id = p.chi_nhanh_id
                  and c.thang = date_trunc('month', coalesce(p.ky_chi_phi, p.ngay))::date
                 where p.muc_id = old.id and p.trang_thai = 'hieu_luc') then
    raise exception 'Mục "%" đã có phiếu trong tháng đã chốt sổ: không đổi loại, tính chất, nhóm hay "vào lãi lỗ" được (lãi lỗ đã chốt sẽ lệch). Tạo mục mới cho các phiếu sau.', old.ten;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 2. v_doanh_thu: thêm tổ làm (to_id, cột cuối); giảm giá giảm cả VAT đầu ra theo tỷ lệ VAT của hồ sơ (ước)
-- ---------------------------------------------------------------------
create or replace view public.v_doanh_thu with (security_invoker = true) as
 SELECT h.chi_nhanh_id,
    m.ngay_duyet AS ngay,
    h.id AS ho_so_id,
    h.ma,
    public.bien_so_hien_thi(x.bien_so) AS bien_so,
    m.nguoi_tra AS nguon,
    m.nhom,
    public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat) AS so_tien,
    CASE WHEN m.xuat_hd THEN public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet ELSE 0::numeric END AS vat_ra,
    coalesce(m.to_id, CASE m.nhom WHEN 'dmg' THEN 'DMG' WHEN 'detailing' THEN 'DT' ELSE 'DS' END) AS to_id
   FROM public.hang_muc m
     JOIN public.ho_so h ON h.id = m.ho_so_id
     JOIN public.xe x ON x.id = h.xe_id
  WHERE m.trang_thai = ANY (ARRAY['duyet'::text, 'dang_lam'::text, 'xong'::text]) AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel AND h.loai <> 'bao_hanh'::text
UNION ALL
 SELECT d.chi_nhanh_id,
    d.ngay,
    NULL::bigint AS ho_so_id,
    NULL::text AS ma,
    public.bien_so_hien_thi(d.bien_so) AS bien_so,
    'dich_vu_nhanh'::text AS nguon,
    CASE d.to_id WHEN 'DMG'::text THEN 'dmg'::text ELSE 'detailing'::text END AS nhom,
    d.so_tien,
    CASE WHEN d.xuat_hd THEN d.so_tien - round(d.so_tien / (1::numeric + public.vat_ty_le(d.ngay))) ELSE 0::numeric END AS vat_ra,
    coalesce(d.to_id, 'DT') AS to_id
   FROM public.dich_vu_nhanh d
  WHERE d.trang_thai = 'hieu_luc'::text
UNION ALL
 SELECT h.chi_nhanh_id,
    h.giam_gia_ngay AS ngay,
    h.id AS ho_so_id,
    h.ma,
    NULL::text AS bien_so,
    'giam_gia'::text AS nguon,
    NULL::text AS nhom,
    - h.giam_gia AS so_tien,
    - round(h.giam_gia * coalesce(v.ty_le, 0)) AS vat_ra,
    NULL::text AS to_id
   FROM public.ho_so h
   LEFT JOIN LATERAL (
     SELECT sum(CASE WHEN m.xuat_hd THEN public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet ELSE 0 END)
            / nullif(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)), 0) AS ty_le
     FROM public.hang_muc m WHERE m.ho_so_id = h.id AND m.trang_thai IN ('duyet','dang_lam','xong')) v ON true
  WHERE h.giam_gia > 0::numeric AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel;
grant select on public.v_doanh_thu to authenticated;
revoke all on public.v_doanh_thu from anon;

-- Doanh thu gộp theo tháng (thẻ Doanh thu – xem "từ trước đến nay" không tải từng dòng về máy). Quyền như v_doanh_thu.
create or replace function public.doanh_thu_theo_thang()
returns table (thang date, bao_hiem numeric, khach numeric, dich_vu_nhanh numeric, giam_gia numeric, tong numeric, vat_ra numeric,
  dong_son numeric, phu_tung numeric, dmg numeric, detailing numeric, so_xe bigint, so_luot_dvn bigint)
language sql stable security invoker set search_path = public as $$
  select date_trunc('month', d.ngay)::date,
    coalesce(sum(d.so_tien) filter (where d.nguon = 'bao_hiem'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'khach'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'giam_gia'), 0),
    coalesce(sum(d.so_tien), 0), coalesce(sum(d.vat_ra), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom in ('dong','son','dong_son')), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'phu_tung'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'dmg'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'detailing'), 0),
    count(distinct d.ho_so_id) filter (where d.nguon in ('bao_hiem','khach')),
    count(*) filter (where d.nguon = 'dich_vu_nhanh')
  from public.v_doanh_thu d
  group by 1 order by 1
$$;
revoke execute on function public.doanh_thu_theo_thang() from public, anon;
grant execute on function public.doanh_thu_theo_thang() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Tiền – công nợ – tồn kho tại một ngày (cuối tháng): lưu vào số chốt, hiện ở báo cáo
-- ---------------------------------------------------------------------
create or replace function app.so_du_cuoi_thang(p_cn text, p_ngay date) returns jsonb
language sql stable security definer set search_path = public as $$
  with quy as (
    select coalesce(sum(tk.so_du_dau_ky) filter (where tk.ngay_dau_ky <= p_ngay), 0)
      + coalesce((select sum(case when p.loai = 'thu' then p.so_tien when p.loai = 'chi' then -p.so_tien else 0 end)
                  from public.phieu_thu_chi p join public.tai_khoan_quy t2 on t2.id = p.tai_khoan_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and p.ngay >= t2.ngay_dau_ky), 0) as so_du
    from public.tai_khoan_quy tk where tk.chi_nhanh_id = p_cn),
  kho as (
    select coalesce(sum(l.so_luong * l.don_gia_von), 0)
      - coalesce((select sum(pd.gia_von) from public.phieu_xuat_dong pd join public.phieu_xuat px on px.id = pd.phieu_id
                  where px.chi_nhanh_id = p_cn and px.trang_thai = 'hieu_luc' and px.ngay <= p_ngay), 0) as ton
    from public.lo_kho l where l.chi_nhanh_id = p_cn and l.ngay <= p_ngay),
  hs as (
    select h.id, h.khau_tru_giam_tru, h.giam_gia, h.giam_gia_ngay,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'khach'), 0) as kh,
      count(*) as so_dong
    from public.ho_so h join public.hang_muc m on m.ho_so_id = h.id
    where h.chi_nhanh_id = p_cn and h.trang_thai <> 'huy' and h.loai <> 'bao_hanh'
      and m.trang_thai in ('duyet','dang_lam','xong') and m.ngay_duyet <= p_ngay
    group by h.id),
  tra as (
    select pb.ho_so_id,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0) as kh
    from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and pb.ho_so_id is not null
    group by pb.ho_so_id),
  -- cả hồ sơ chưa duyệt giá mà đã thu cọc (hoặc đã hủy còn giữ cọc): nợ khách âm = phải trả lại khách
  no as (
    select coalesce(hs.bh, 0) - coalesce(hs.khau_tru_giam_tru, 0) - coalesce(tra.bh, 0) as no_bh,
      coalesce(hs.kh, 0) + coalesce(hs.khau_tru_giam_tru, 0) - case when hs.giam_gia_ngay <= p_ngay then hs.giam_gia else 0 end - coalesce(tra.kh, 0) as no_kh
    from hs full join tra on tra.ho_so_id = hs.id),
  ncc as (
    select coalesce((select sum(pn.tong_tien) from public.phieu_nhap pn
                     where pn.chi_nhanh_id = p_cn and pn.trang_thai <> 'huy' and pn.ngay <= p_ngay), 0)
      - coalesce((select sum(p.so_tien) from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat = 'tra_ncc'
                    and p.nha_cung_cap_id is not null and p.ngay <= p_ngay), 0) as phai_tra)
  select jsonb_build_object(
    'ngay', p_ngay,
    'so_du_quy', (select round(so_du) from quy),
    'ton_kho', (select round(ton) from kho),
    'phai_thu_khach', (select round(coalesce(sum(greatest(no_kh, 0)), 0)) from no),
    'phai_thu_bh', (select round(coalesce(sum(greatest(no_bh, 0)), 0)) from no),
    'khach_tra_du', (select round(coalesce(sum(greatest(-no_kh, 0)), 0)) from no),
    'phai_tra_ncc', (select round(phai_tra) from ncc))
$$;
revoke execute on function app.so_du_cuoi_thang(text, date) from public, anon;

create or replace function public.so_du_cuoi_thang(p_thang date, p_chi_nhanh text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_ngay date := (date_trunc('month', p_thang) + interval '1 month - 1 day')::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return app.so_du_cuoi_thang(v_cn, least(v_ngay, current_date));
end $$;
revoke execute on function public.so_du_cuoi_thang(date, text) from public, anon;
grant execute on function public.so_du_cuoi_thang(date, text) to authenticated;

-- Số đã chốt nếu có, không thì số hiện tại
create or replace function app.so_chot(p_so_lieu jsonb, p_khoa text, p_song numeric) returns numeric
language sql immutable as $$
  select case when p_so_lieu is not null and p_so_lieu ? p_khoa and jsonb_typeof(p_so_lieu->p_khoa) = 'number'
              then (p_so_lieu->>p_khoa)::numeric else p_song end
$$;

-- ---------------------------------------------------------------------
-- 4. Kết quả kinh doanh (giữ cột cũ, thêm cột mới ở cuối)
-- ---------------------------------------------------------------------
drop function if exists public.ket_qua_kinh_doanh(text);
create function public.ket_qua_kinh_doanh(p_chi_nhanh text default null)
returns table (
  thang date, ngay_cuoi date, trang_thai text,
  doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric,
  gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric,
  luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric, so_xe bigint,
  luong_da_nhap boolean, thieu_dinh_ky text[], de_nghi_cho_chi bigint, da_chot boolean, chot_luc timestamptz,
  -- 042
  hao_hut numeric, tong_gia_von numeric, tong_chi_phi numeric, thu_khac numeric,
  vat_vao_hang numeric, vat_vao_chi_phi numeric, vat_trong_gia_von numeric, vat_phai_nop numeric, lai_sau_vat numeric,
  so_luot_dvn bigint, lech_chot boolean, lai_truoc_thue_song numeric)
language plpgsql stable security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_dau date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select least(
    (select min(date_trunc('month', d.ngay))::date from public.v_doanh_thu d where d.chi_nhanh_id = v_cn),
    (select min(date_trunc('month', px.ngay))::date from public.phieu_xuat px where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc'),
    (select min(coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date)) from public.phieu_thu_chi p where p.chi_nhanh_id = v_cn and p.trang_thai = 'hieu_luc'),
    (select min(date_trunc('month', pn.ngay))::date from public.phieu_nhap pn where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy'),
    (select min(bl.thang) from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn),
    (select min(ct.thang) from public.chot_thang ct where ct.chi_nhanh_id = v_cn),
    date_trunc('month', current_date)::date) into v_dau;
  return query
  with cac_thang as (
    select g::date as th from generate_series(v_dau, date_trunc('month', current_date)::date, interval '1 month') g),
  thang_dt as (
    select date_trunc('month', d.ngay)::date as th,
      sum(d.so_tien) filter (where d.nguon = 'bao_hiem') as bh,
      sum(d.so_tien) filter (where d.nguon = 'khach') as kh,
      sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh') as dvn,
      sum(d.so_tien) filter (where d.nguon = 'giam_gia') as gg,
      sum(d.vat_ra) as vat, count(*) filter (where d.nguon = 'dich_vu_nhanh') as luot_dvn
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn group by 1),
  -- Số xe: tính ở tháng duyệt giá đầu tiên của hồ sơ (lũy kế không đếm trùng)
  thang_xe as (
    select date_trunc('month', x.dau)::date as th, count(*) as xe
    from (select min(m.ngay_duyet) as dau from public.hang_muc m join public.ho_so h on h.id = m.ho_so_id
          where h.chi_nhanh_id = v_cn and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
            and m.trang_thai in ('duyet','dang_lam','xong') group by m.ho_so_id) x
    group by 1),
  thang_kho as (
    select date_trunc('month', px.ngay)::date as th,
      sum(pd.gia_von) filter (where px.loai = 'cho_xe') as xe, sum(pd.gia_von) filter (where px.loai = 'dung_chung') as dc,
      sum(pd.gia_von) filter (where px.loai = 'kiem_ke') as kk_thieu
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' group by 1),
  -- Kiểm kê thừa: lô thêm vào kho → giảm hao hụt của tháng
  thang_thua as (
    select date_trunc('month', l.ngay)::date as th, round(sum(l.so_luong * l.don_gia_von)) as thua
    from public.lo_kho l where l.chi_nhanh_id = v_cn and l.kiem_ke_id is not null group by 1),
  thang_chi as (
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_thu_khac as (
    select date_trunc('month', p.ngay)::date as th, sum(p.so_tien) as tk
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'thu' and p.trang_thai = 'hieu_luc' and m.vao_lai_lo group by 1),
  thang_vat_nhap as (
    select date_trunc('month', pn.ngay)::date as th, sum(pn.tien_vat) as vat
    from public.phieu_nhap pn where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy' group by 1),
  -- VAT nằm trong giá vốn vật tư đã xuất (lô của phiếu nhập có VAT), làm tròn theo từng phiếu xuất như chi_tiet_kqkd
  thang_vat_gv as (
    select date_trunc('month', v.ngay)::date as th, sum(v.vat) as vat
    from (select px.ngay, round(sum(xl.so_luong * xl.don_gia_von * pnd.ty_le_vat / (1 + pnd.ty_le_vat))) as vat
          from public.phieu_xuat px
          join public.phieu_xuat_dong pd on pd.phieu_id = px.id
          join public.xuat_lo xl on xl.phieu_xuat_dong_id = pd.id
          join public.lo_kho l on l.id = xl.lo_id
          join public.phieu_nhap_dong pnd on pnd.id = l.phieu_nhap_dong_id
          where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and pnd.ty_le_vat > 0
          group by px.id, px.ngay) v
    group by 1),
  thang_hh as (
    select date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel group by 1),
  song as (
    select t.th,
      coalesce(dt.bh,0) as dt_bh, coalesce(dt.kh,0) as dt_kh, coalesce(dt.dvn,0) as dt_dvn, coalesce(dt.gg,0) as gg,
      coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) as dthu, coalesce(dt.vat,0) as vat_ra,
      coalesce(k.xe,0) as gv_xe, coalesce(k.dc,0) as gv_dc, coalesce(c.gv,0) as chi_gv,
      coalesce(k.kk_thieu,0) - coalesce(tt.thua,0) as hao,
      coalesce(bl.tong_luong,0) as luong, coalesce(hh.hh,0) as hh, coalesce(c.vh,0) as vh, coalesce(c.cd,0) as cd,
      coalesce(tk.tk,0) as thu_khac,
      coalesce(vn.vat,0) as vat_hang, coalesce(c.vat_vao,0) as vat_cp, coalesce(vg.vat,0) as vat_gv,
      coalesce(x.xe,0) as so_xe, coalesce(dt.luot_dvn,0) as luot_dvn,
      bl.thang is not null as co_luong, ct.thang is not null as da_chot, ct.chot_luc, ct.so_lieu
    from cac_thang t
    left join thang_dt dt on dt.th = t.th
    left join thang_xe x on x.th = t.th
    left join thang_kho k on k.th = t.th
    left join thang_thua tt on tt.th = t.th
    left join thang_chi c on c.th = t.th
    left join thang_thu_khac tk on tk.th = t.th
    left join thang_vat_nhap vn on vn.th = t.th
    left join thang_vat_gv vg on vg.th = t.th
    left join thang_hh hh on hh.th = t.th
    left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
    left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th),
  tinh as (
    select s.*,
      s.gv_xe + s.gv_dc + s.hao + s.chi_gv as tong_gv,
      s.luong + s.hh + s.vh + s.cd as tong_cp
    from song s),
  tinh2 as (
    select t.*, t.dthu - t.tong_gv as lai_gop, t.dthu - t.tong_gv - t.tong_cp + t.thu_khac as lai_tt,
      t.vat_ra - t.vat_hang - t.vat_cp as vat_nop,
      -- lãi không gồm VAT (dồn tích): bỏ VAT khỏi doanh thu, khỏi giá vốn đã xuất và khỏi chi phí
      t.dthu - t.tong_gv - t.tong_cp + t.thu_khac - t.vat_ra + t.vat_gv + t.vat_cp as lai_kv
    from tinh t)
  select t.th, (t.th + interval '1 month' - interval '1 day')::date,
    case when t.da_chot then 'da_chot' when t.th >= date_trunc('month', current_date)::date then 'dang_mo' else 'cho_chot' end,
    app.so_chot(t.so_lieu, 'doanh_thu_bh', t.dt_bh), app.so_chot(t.so_lieu, 'doanh_thu_khach', t.dt_kh),
    app.so_chot(t.so_lieu, 'doanh_thu_dvn', t.dt_dvn), app.so_chot(t.so_lieu, 'giam_gia', t.gg),
    app.so_chot(t.so_lieu, 'doanh_thu', t.dthu), app.so_chot(t.so_lieu, 'vat_ra', t.vat_ra),
    app.so_chot(t.so_lieu, 'gia_von_xe', t.gv_xe), app.so_chot(t.so_lieu, 'gia_von_dung_chung', t.gv_dc),
    app.so_chot(t.so_lieu, 'chi_gia_von', t.chi_gv), app.so_chot(t.so_lieu, 'lai_gop', t.lai_gop),
    app.so_chot(t.so_lieu, 'luong', t.luong), app.so_chot(t.so_lieu, 'hoa_hong', t.hh),
    app.so_chot(t.so_lieu, 'chi_van_hanh', t.vh), app.so_chot(t.so_lieu, 'chi_co_dinh', t.cd),
    app.so_chot(t.so_lieu, 'lai_truoc_thue', t.lai_tt), app.so_chot(t.so_lieu, 'vat_vao', t.vat_hang + t.vat_cp),
    app.so_chot(t.so_lieu, 'so_xe', t.so_xe)::bigint,
    t.co_luong,
    coalesce((select array_agg(m.ten order by m.ten) from public.muc_thu_chi m
      where m.loai = 'chi' and m.dinh_ky and m.hoat_dong
        and not exists (select 1 from public.phieu_thu_chi p where p.muc_id = m.id and p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'
                          and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = t.th)
        and not exists (select 1 from public.de_nghi_chi d where d.muc_id = m.id and d.chi_nhanh_id = v_cn and d.trang_thai not in ('huy','tu_choi')
                          and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th)), '{}'::text[]),
    (select count(*) from public.de_nghi_chi d where d.chi_nhanh_id = v_cn and d.trang_thai in ('cho_duyet','da_duyet')
       and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th),
    t.da_chot, t.chot_luc,
    app.so_chot(t.so_lieu, 'hao_hut', t.hao), app.so_chot(t.so_lieu, 'tong_gia_von', t.tong_gv),
    app.so_chot(t.so_lieu, 'tong_chi_phi', t.tong_cp), app.so_chot(t.so_lieu, 'thu_khac', t.thu_khac),
    app.so_chot(t.so_lieu, 'vat_vao_hang', t.vat_hang), app.so_chot(t.so_lieu, 'vat_vao_chi_phi', t.vat_cp),
    app.so_chot(t.so_lieu, 'vat_trong_gia_von', t.vat_gv),
    app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop), app.so_chot(t.so_lieu, 'lai_sau_vat', t.lai_kv),
    app.so_chot(t.so_lieu, 'so_luot_dvn', t.luot_dvn)::bigint,
    -- Tháng đã chốt: số hiện tại khác số lúc chốt (hoặc chốt theo cách tính cũ) → cần mở lại, chốt lại
    t.da_chot and (not coalesce(t.so_lieu ? 'phien_ban', false)
      or abs(t.dthu - app.so_chot(t.so_lieu, 'doanh_thu', t.dthu)) >= 1
      or abs(t.lai_gop - app.so_chot(t.so_lieu, 'lai_gop', t.lai_gop)) >= 1
      or abs(t.lai_tt - app.so_chot(t.so_lieu, 'lai_truoc_thue', t.lai_tt)) >= 1
      or abs(t.vat_nop - app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop)) >= 1
      or abs(t.lai_kv - app.so_chot(t.so_lieu, 'lai_sau_vat', t.lai_kv)) >= 1),
    t.lai_tt
  from tinh2 t
  order by t.th;
end $$;
revoke execute on function public.ket_qua_kinh_doanh(text) from public, anon;
grant execute on function public.ket_qua_kinh_doanh(text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Chốt tháng lần lượt; lưu số dư cuối tháng; mở lại có lịch sử
-- ---------------------------------------------------------------------
create table if not exists public.chot_thang_lich_su (
  id           bigint generated always as identity primary key,
  chi_nhanh_id text not null references public.chi_nhanh(id),
  thang        date not null,
  so_lieu      jsonb,
  chot_boi     uuid,
  chot_luc     timestamptz,
  mo_lai_boi   uuid,
  mo_lai_luc   timestamptz not null default now(),
  ly_do        text not null
);
create index if not exists chot_thang_lich_su_thang_idx on public.chot_thang_lich_su (chi_nhanh_id, thang);
alter table public.chot_thang_lich_su enable row level security;
revoke all on public.chot_thang_lich_su from anon;
revoke insert, update, delete, truncate on public.chot_thang_lich_su from authenticated;
grant select on public.chot_thang_lich_su to authenticated;
drop policy if exists doc on public.chot_thang_lich_su;
create policy doc on public.chot_thang_lich_su for select to authenticated
  using ((select app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong'))
         and ((select app.co_vai_tro('giam_doc')) or chi_nhanh_id = (select app.chi_nhanh())));

create or replace function public.chot_thang(p_thang date, p_bo_qua_canh_bao boolean default false, p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; k record;
  v_thieu text[] := '{}'; v_truoc date; v_so jsonb;
begin
  perform app.yeu_cau('giam_doc');
  if v_thang >= date_trunc('month', current_date)::date then raise exception 'Chỉ chốt được tháng đã qua (kỳ khóa ở ngày cuối tháng).'; end if;
  if app.thang_da_chot(v_cn, v_thang) then raise exception 'Tháng này đã chốt rồi.'; end if;
  -- Chốt lần lượt: tháng trước có số liệu mà chưa chốt thì chốt trước (lũy kế báo cáo cổ đông không bị thủng)
  select min(x.thang) into v_truoc from public.ket_qua_kinh_doanh(v_cn) x
   where x.thang < v_thang and x.trang_thai = 'cho_chot'
     and (x.doanh_thu <> 0 or x.tong_gia_von <> 0 or x.tong_chi_phi <> 0 or x.thu_khac <> 0 or x.luong_da_nhap);
  if v_truoc is not null then
    raise exception 'Chốt tháng % trước (chốt lần lượt từng tháng).', to_char(v_truoc, 'MM/YYYY'); end if;
  select * into k from public.ket_qua_kinh_doanh(v_cn) x where x.thang = v_thang;
  if k.thang is null then raise exception 'Tháng này chưa có số liệu.'; end if;
  if not p_bo_qua_canh_bao then
    if not k.luong_da_nhap then v_thieu := v_thieu || 'chưa nhập bảng lương'; end if;
    if cardinality(k.thieu_dinh_ky) > 0 then v_thieu := v_thieu || ('chưa có chi phí định kỳ: ' || array_to_string(k.thieu_dinh_ky, ', ')); end if;
    if k.de_nghi_cho_chi > 0 then v_thieu := v_thieu || (k.de_nghi_cho_chi || ' đề nghị chi của kỳ chưa chi'); end if;
    if cardinality(v_thieu) > 0 then
      raise exception 'CANH_BAO: Tháng % còn thiếu: %. Chốt xong sẽ không nhập thêm được vào tháng này. Vẫn chốt?',
        to_char(v_thang, 'MM/YYYY'), array_to_string(v_thieu, '; ');
    end if;
  end if;
  v_so := to_jsonb(k) - 'da_chot' - 'chot_luc' - 'trang_thai' - 'lech_chot' - 'lai_truoc_thue_song'
    || jsonb_build_object('phien_ban', 2, 'so_du', app.so_du_cuoi_thang(v_cn, k.ngay_cuoi));
  insert into public.chot_thang (chi_nhanh_id, thang, chot_boi, so_lieu) values (v_cn, v_thang, auth.uid(), v_so);
  return v_so;
end $$;

create or replace function public.mo_lai_thang(p_thang date, p_ly_do text, p_chi_nhanh text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date; c public.chot_thang; v_sau date;
begin
  perform app.yeu_cau('giam_doc');
  if nullif(trim(p_ly_do), '') is null then raise exception 'Ghi lý do mở lại tháng.'; end if;
  select * into c from public.chot_thang where chi_nhanh_id = v_cn and thang = v_thang for update;
  if not found then raise exception 'Tháng này chưa chốt.'; end if;
  -- Mở lại từ tháng sau cùng trở về (tháng sau còn chốt thì số lũy kế đã chốt dựa trên tháng này)
  select min(thang) into v_sau from public.chot_thang where chi_nhanh_id = v_cn and thang > v_thang;
  if v_sau is not null then raise exception 'Tháng % đã chốt – mở lại tháng đó trước.', to_char(v_sau, 'MM/YYYY'); end if;
  insert into public.chot_thang_lich_su (chi_nhanh_id, thang, so_lieu, chot_boi, chot_luc, mo_lai_boi, ly_do)
  values (c.chi_nhanh_id, c.thang, c.so_lieu, c.chot_boi, c.chot_luc, auth.uid(), trim(p_ly_do));
  delete from public.chot_thang where chi_nhanh_id = v_cn and thang = v_thang;
end $$;

-- ---------------------------------------------------------------------
-- 6. Chi tiết một ô của báo cáo (bấm vào số): từng phiếu / hồ sơ tạo nên số đó
-- ---------------------------------------------------------------------
create or replace function public.chi_tiet_kqkd(p_thang date, p_khoan text, p_chi_nhanh text default null)
returns table (nhom text, ten text, ngay date, so_tien numeric, ho_so_id bigint, ma text)
language plpgsql stable security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_tu date := date_trunc('month', p_thang)::date;
  v_den date := (date_trunc('month', p_thang) + interval '1 month - 1 day')::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  if p_khoan in ('doanh_thu_bh','doanh_thu_khach','giam_gia') then
    return query
      select coalesce(t.ten, case when p_khoan = 'giam_gia' then 'Giảm giá cho khách' else 'Khác' end),
        coalesce(d.bien_so_hs || ' · ', '') || d.ma, min(d.ngay), sum(d.so_tien), d.ho_so_id, d.ma
      from (select v.*, coalesce(v.bien_so, (select public.bien_so_hien_thi(x.bien_so) from public.ho_so h join public.xe x on x.id = h.xe_id where h.id = v.ho_so_id)) as bien_so_hs
            from public.v_doanh_thu v
            where v.chi_nhanh_id = v_cn and v.ngay between v_tu and v_den
              and v.nguon = case p_khoan when 'doanh_thu_bh' then 'bao_hiem' when 'doanh_thu_khach' then 'khach' else 'giam_gia' end) d
      left join public.to_thuc_hien t on t.id = d.to_id
      group by t.ten, d.bien_so_hs, d.ma, d.ho_so_id order by 4 desc;
  elsif p_khoan = 'doanh_thu_dvn' then
    return query
      select coalesce(t.ten, 'Detailing'), d.dich_vu || coalesce(' · ' || public.bien_so_hien_thi(d.bien_so), ''), d.ngay, d.so_tien, null::bigint, null::text
      from public.dich_vu_nhanh d left join public.to_thuc_hien t on t.id = d.to_id
      where d.chi_nhanh_id = v_cn and d.trang_thai = 'hieu_luc' and d.ngay between v_tu and v_den order by d.ngay, d.id;
  elsif p_khoan in ('gia_von_xe','gia_von_dung_chung','hao_hut') then
    return query
      select case px.loai when 'cho_xe' then coalesce(t.ten, 'Không qua đề xuất (xuất ngay, xuất lẻ)') when 'dung_chung' then 'Dùng chung xưởng' else 'Kiểm kê thiếu' end,
        px.ma || coalesce(' · ' || h.ma, '') || coalesce(' · ' || nullif(px.ghi_chu, ''), ''), px.ngay, sum(pd.gia_von), px.ho_so_id, h.ma
      from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
      left join public.ho_so h on h.id = px.ho_so_id
      left join public.de_xuat_vat_tu dx on dx.id = px.de_xuat_id
      left join public.to_thuc_hien t on t.id = dx.to_id
      where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and v_den
        and px.loai = case p_khoan when 'gia_von_xe' then 'cho_xe' when 'gia_von_dung_chung' then 'dung_chung' else 'kiem_ke' end
      group by px.loai, t.ten, px.ma, h.ma, px.ghi_chu, px.ngay, px.ho_so_id
      union all
      select 'Kiểm kê thừa (giảm hao hụt)', kk.ma || ' · ' || hk.ma || ' ' || hk.ten, l.ngay, -round(l.so_luong * l.don_gia_von), null::bigint, null::text
      from public.lo_kho l join public.kiem_ke kk on kk.id = l.kiem_ke_id join public.hang_kho hk on hk.id = l.hang_id
      where p_khoan = 'hao_hut' and l.chi_nhanh_id = v_cn and l.ngay between v_tu and v_den
      order by 1, 3;
  elsif p_khoan in ('chi_gia_von','chi_van_hanh','chi_co_dinh') then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.so_tien, dn.ho_so_id, h.ma
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      left join public.de_nghi_chi dn on dn.id = p.de_nghi_chi_id
      left join public.ho_so h on h.id = dn.ho_so_id
      where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
        and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = v_tu
        and case p_khoan when 'chi_gia_von' then m.nhom = 'gia_von' when 'chi_co_dinh' then m.nhom = 'co_dinh'
                         else coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh') end
      order by m.ten, p.ngay;
  elsif p_khoan = 'thu_khac' then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.so_tien, null::bigint, null::text
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      where p.chi_nhanh_id = v_cn and p.loai = 'thu' and p.trang_thai = 'hieu_luc' and m.vao_lai_lo and p.ngay between v_tu and v_den
      order by m.ten, p.ngay;
  elsif p_khoan = 'hoa_hong' then
    return query
      select coalesce(g.ten, h.gdv_ten_tam, 'GDV'), public.bien_so_hien_thi(x.bien_so) || ' · ' || h.ma, d.dau, h.hoa_hong_gdv, h.id, h.ma
      from public.ho_so h join public.xe x on x.id = h.xe_id
      left join public.giam_dinh_vien g on g.id = h.gdv_id
      join lateral (select min(m.ngay_duyet) as dau from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) d on true
      where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel
        and date_trunc('month', d.dau)::date = v_tu
      order by 1, 3;
  elsif p_khoan = 'luong' then
    return query
      select 'Bảng lương tháng'::text, 'Tổng lương tháng ' || to_char(v_tu, 'MM/YYYY'), v_den, bl.tong_luong, null::bigint, null::text
      from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn and bl.thang = v_tu;
  elsif p_khoan in ('vat_vao_hang') then
    return query
      select coalesce(n.ten, 'Nhà cung cấp'), pn.ma || coalesce(' · HĐ ' || pn.so_hoa_don, ''), pn.ngay, pn.tien_vat, pn.ho_so_id, null::text
      from public.phieu_nhap pn left join public.nha_cung_cap n on n.id = pn.nha_cung_cap_id
      where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy' and pn.ngay between v_tu and v_den and pn.tien_vat <> 0
      order by 1, 3;
  elsif p_khoan in ('vat_vao_chi_phi') then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.vat_dau_vao, null::bigint, null::text
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
        and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = v_tu and p.vat_dau_vao <> 0
      order by 1, 3;
  elsif p_khoan = 'vat_trong_gia_von' then
    -- VAT nằm trong giá vốn vật tư đã xuất: theo từng phiếu xuất (lô của phiếu nhập có VAT)
    return query
      select case px.loai when 'cho_xe' then 'Xuất cho xe' when 'dung_chung' then 'Dùng chung xưởng' else 'Kiểm kê thiếu' end,
        px.ma || coalesce(' · ' || h.ma, ''), px.ngay,
        round(sum(xl.so_luong * xl.don_gia_von * pnd.ty_le_vat / (1 + pnd.ty_le_vat))), px.ho_so_id, h.ma
      from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
      join public.xuat_lo xl on xl.phieu_xuat_dong_id = pd.id
      join public.lo_kho l on l.id = xl.lo_id
      join public.phieu_nhap_dong pnd on pnd.id = l.phieu_nhap_dong_id
      left join public.ho_so h on h.id = px.ho_so_id
      where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and v_den and pnd.ty_le_vat > 0
      group by px.id, px.loai, px.ma, h.ma, px.ngay, px.ho_so_id
      order by 1, 3;
  elsif p_khoan = 'vat_ra' then
    return query
      select case d.nguon when 'dich_vu_nhanh' then 'Dịch vụ nhanh' when 'giam_gia' then 'Giảm giá (giảm VAT đầu ra)' else 'Hồ sơ xe' end,
        concat_ws(' · ', d.bien_so_hs, d.ma), min(d.ngay), sum(d.vat_ra), d.ho_so_id, d.ma
      from (select v.*, coalesce(v.bien_so, (select public.bien_so_hien_thi(x.bien_so) from public.ho_so h join public.xe x on x.id = h.xe_id where h.id = v.ho_so_id)) as bien_so_hs
            from public.v_doanh_thu v
            where v.chi_nhanh_id = v_cn and v.ngay between v_tu and v_den and v.vat_ra <> 0) d
      group by d.nguon, d.bien_so_hs, d.ma, d.ho_so_id order by 1, 4 desc;
  elsif p_khoan = 'so_xe' then
    -- Xe tính vào tháng duyệt giá đầu tiên; số tiền = tổng giá đã duyệt (gồm VAT) của hồ sơ
    return query
      select case h.nguon_tt when 'khach' then 'Khách ngoài bảo hiểm' else coalesce(b.ten, 'Bảo hiểm') end,
        public.bien_so_hien_thi(x.bien_so) || ' · ' || h.ma, d.dau, d.tong, h.id, h.ma
      from public.ho_so h join public.xe x on x.id = h.xe_id
      left join public.hang_bao_hiem b on b.id = h.hang_bh_id
      join lateral (select min(m.ngay_duyet) as dau,
                      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)), 0) as tong
                    from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) d on true
      where h.chi_nhanh_id = v_cn and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
        and date_trunc('month', d.dau)::date = v_tu
      order by 1, 3;
  else
    raise exception 'Khoản "%" không có chi tiết.', p_khoan;
  end if;
end $$;
revoke execute on function public.chi_tiet_kqkd(date, text, text) from public, anon;
grant execute on function public.chi_tiet_kqkd(date, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Chi phí theo mục và lãi gộp theo tổ (theo tháng, trong khoảng) – bảng phân tích, xuất Excel
-- ---------------------------------------------------------------------
create or replace function public.chi_phi_theo_muc(p_tu date, p_den date, p_chi_nhanh text default null)
returns table (thang date, nhom text, muc text, so_tien numeric, so_phieu bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh());
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return query
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date), coalesce(m.nhom, 'van_hanh'), m.ten, sum(p.so_tien), count(*)
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
      and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) between date_trunc('month', p_tu)::date and p_den
    group by 1, 2, 3 order by 1, 2, 3;
end $$;
revoke execute on function public.chi_phi_theo_muc(date, date, text) from public, anon;
grant execute on function public.chi_phi_theo_muc(date, date, text) to authenticated;

-- Lãi gộp theo tổ: doanh thu theo tổ làm (dòng chưa giao tổ: theo nhóm), vật tư xuất theo tổ đề xuất.
-- Dòng "CHUNG": giảm giá, vật tư dùng chung, xuất không qua đề xuất, hao hụt kiểm kê, chi phí nhóm giá vốn
-- → cộng các dòng đúng bằng lãi gộp của báo cáo.
create or replace function public.lai_gop_theo_to(p_tu date, p_den date, p_chi_nhanh text default null)
returns table (thang date, to_id text, ten_to text, doanh_thu numeric, gia_von numeric, so_xe bigint, so_luot_dvn bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_tu date := date_trunc('month', p_tu)::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return query
  with dt as (
    select date_trunc('month', d.ngay)::date as th, coalesce(d.to_id, 'CHUNG') as to_id, sum(d.so_tien) as dthu,
      count(distinct d.ho_so_id) as xe, count(*) filter (where d.nguon = 'dich_vu_nhanh') as dvn
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn and d.ngay between v_tu and p_den group by 1, 2),
  gv as (
    select date_trunc('month', px.ngay)::date as th,
      case when px.loai = 'cho_xe' and dx.to_id is not null then dx.to_id else 'CHUNG' end as to_id, sum(pd.gia_von) as gv
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    left join public.de_xuat_vat_tu dx on dx.id = px.de_xuat_id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and p_den group by 1, 2
    union all
    select date_trunc('month', l.ngay)::date, 'CHUNG', -round(sum(l.so_luong * l.don_gia_von))
    from public.lo_kho l where l.chi_nhanh_id = v_cn and l.kiem_ke_id is not null and l.ngay between v_tu and p_den group by 1
    union all
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date), 'CHUNG', sum(p.so_tien)
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' and m.nhom = 'gia_von'
      and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) between v_tu and p_den group by 1),
  gv2 as (select g.th, g.to_id, sum(g.gv) as gv from gv g group by 1, 2),
  khoa as (select th, to_id from dt union select th, to_id from gv2)
  select k.th, k.to_id, case when k.to_id = 'CHUNG' then 'Chung (giảm giá, dùng chung, hao hụt, thuê ngoài…)' else coalesce(t.ten, k.to_id) end,
    coalesce(dt.dthu, 0), coalesce(gv2.gv, 0), coalesce(dt.xe, 0), coalesce(dt.dvn, 0)
  from khoa k
  left join dt on dt.th = k.th and dt.to_id = k.to_id
  left join gv2 on gv2.th = k.th and gv2.to_id = k.to_id
  left join public.to_thuc_hien t on t.id = k.to_id
  order by k.th, (k.to_id = 'CHUNG'), k.to_id;
end $$;
revoke execute on function public.lai_gop_theo_to(date, date, text) from public, anon;
grant execute on function public.lai_gop_theo_to(date, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- Múi giờ Việt Nam cho hàm mới có dùng ngày giờ hiện tại
-- ---------------------------------------------------------------------
do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%' or p.prosrc ilike '%localtimestamp%' or p.prosrc ilike '%current_timestamp%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ======================= 043_ra_soat_3.sql =======================
-- =====================================================================
-- 043 (15/10/2026): Rà soát lần 3 – sửa các lỗi giám đốc chọn ở cả 6 nhóm
--   A. Tiền & khóa sổ   B. Hồ sơ xe   C. Kho & đồ nghề   D. Phân quyền   E. Báo cáo KQKD   F. Điểm nhỏ
-- Tương thích ngược với giao diện đang chạy (nhánh main – đợt 1, dùng chung CSDL):
--   giữ tên hàm và tham số cũ, chỉ thêm tham số có mặc định; view chỉ thêm cột ở cuối;
--   cảnh báo mới (CANH_BAO) của hàm nhận jsonb chỉ hỏi khi giao diện gửi khóa "bo_qua_canh_bao" (giao diện cũ không gửi → như trước).
-- =====================================================================

-- ---------------------------------------------------------------------
-- A1. KHÓA SỔ THEO THÁNG CHỐT SAU CÙNG
--   Chốt tháng M thì mọi tháng trước M cũng khóa (cả tháng trống bỏ qua khi chốt lần lượt) → không ai ghi lùi
--   vào một tháng trống nằm trước tháng đã chốt làm sai số dư lúc chốt. Mở lại vẫn chỉ mở tháng chốt sau cùng.
-- ---------------------------------------------------------------------
create or replace function app.thang_da_chot(cn text, d date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chot_thang
                 where chi_nhanh_id = cn and thang >= date_trunc('month', d)::date)
$$;

create or replace function app.yeu_cau_thang_mo(cn text, d date) returns void
language plpgsql stable security definer set search_path = public as $$
declare v_khoa date;
begin
  if d is null then return; end if;
  select max(thang) into v_khoa from public.chot_thang where chi_nhanh_id = cn and thang >= date_trunc('month', d)::date;
  if v_khoa is null then return; end if;
  if v_khoa = date_trunc('month', d)::date then
    raise exception 'Tháng %/% đã chốt sổ, không ghi hay sửa được. Hãy ghi điều chỉnh vào tháng đang mở.',
      extract(month from d), extract(year from d);
  end if;
  raise exception 'Tháng %/% đã khóa sổ (sổ đã chốt đến hết tháng %), không ghi hay sửa được. Hãy ghi điều chỉnh vào tháng đang mở.',
    extract(month from d), extract(year from d), to_char(v_khoa, 'MM/YYYY');
end $$;

-- Danh mục đã dùng trong tháng đã khóa sổ: không đổi phần làm lệch số đã chốt (kỳ khóa = tháng chốt sau cùng)
create or replace function app.chan_doi_muc_da_chot() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.loai, new.tinh_chat, new.nhom, new.vao_lai_lo) is distinct from (old.loai, old.tinh_chat, old.nhom, old.vao_lai_lo)
     and exists (select 1 from public.phieu_thu_chi p
                 join public.chot_thang c on c.chi_nhanh_id = p.chi_nhanh_id
                  and c.thang >= date_trunc('month', coalesce(p.ky_chi_phi, p.ngay))::date
                 where p.muc_id = old.id and p.trang_thai = 'hieu_luc') then
    raise exception 'Mục "%" đã có phiếu trong tháng đã chốt sổ: không đổi loại, tính chất, nhóm hay "vào lãi lỗ" được (lãi lỗ đã chốt sẽ lệch). Tạo mục mới cho các phiếu sau.', old.ten;
  end if;
  return new;
end $$;

-- E1. "Vào lãi lỗ" chỉ có nghĩa với mục THU tính chất "thu khác" (trạm sạc, thu khác): mục khác tích nhầm thì tự bỏ
--     (tiền khách / bảo hiểm trả, tiền mượn… mà tích nhầm sẽ thành thu nhập khác, doanh thu tính hai lần)
create or replace function app.chuan_hoa_vao_lai_lo() returns trigger
language plpgsql as $$
begin
  if new.vao_lai_lo and not (new.loai = 'thu' and new.tinh_chat = 'thu_khac') then new.vao_lai_lo := false; end if;
  return new;
end $$;
drop trigger if exists muc_thu_chi_a_vao_lai_lo on public.muc_thu_chi;
create trigger muc_thu_chi_a_vao_lai_lo before insert or update on public.muc_thu_chi
  for each row execute function app.chuan_hoa_vao_lai_lo();
do $$ begin
  if exists (select 1 from public.muc_thu_chi where vao_lai_lo and not (loai = 'thu' and tinh_chat = 'thu_khac')) then
    alter table public.muc_thu_chi disable trigger muc_thu_chi_chan_doi;
    update public.muc_thu_chi set vao_lai_lo = false where vao_lai_lo and not (loai = 'thu' and tinh_chat = 'thu_khac');
    alter table public.muc_thu_chi enable trigger muc_thu_chi_chan_doi;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- F. Tài khoản quỹ: không dời ngày đầu kỳ qua ngày của phiếu đã ghi; mỗi lần đổi số dư / ngày đầu kỳ lưu lịch sử
-- ---------------------------------------------------------------------
create table if not exists public.tai_khoan_quy_lich_su (
  id            bigint generated always as identity primary key,
  tai_khoan_id  bigint not null references public.tai_khoan_quy(id) on delete cascade,
  so_du_cu      numeric(14,0),
  so_du_moi     numeric(14,0),
  ngay_cu       date,
  ngay_moi      date,
  sua_boi       uuid,
  sua_luc       timestamptz not null default now()
);
create index if not exists tai_khoan_quy_lich_su_idx on public.tai_khoan_quy_lich_su (tai_khoan_id, sua_luc);
alter table public.tai_khoan_quy_lich_su enable row level security;
revoke all on public.tai_khoan_quy_lich_su from anon;
revoke insert, update, delete, truncate on public.tai_khoan_quy_lich_su from authenticated;
grant select on public.tai_khoan_quy_lich_su to authenticated;
drop policy if exists doc on public.tai_khoan_quy_lich_su;
create policy doc on public.tai_khoan_quy_lich_su for select to authenticated
  using ((select app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong'))
         and exists (select 1 from public.tai_khoan_quy t where t.id = tai_khoan_id and app.duoc_xem_chi_nhanh(t.chi_nhanh_id)));

create or replace function app.chan_doi_tai_khoan() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ngay date;
begin
  if tg_op = 'UPDATE' and (new.so_du_dau_ky, new.ngay_dau_ky) is distinct from (old.so_du_dau_ky, old.ngay_dau_ky) then
    if exists (select 1 from public.phieu_thu_chi p
               join public.chot_thang c on c.chi_nhanh_id = p.chi_nhanh_id and c.thang >= date_trunc('month', p.ngay)::date
               where (p.tai_khoan_id = old.id or p.tai_khoan_den_id = old.id) and p.trang_thai = 'hieu_luc') then
      raise exception 'Tài khoản "%" đã có phiếu trong tháng đã chốt sổ: không đổi số dư hay ngày đầu kỳ được. Lệch quỹ thì ghi "Kiểm quỹ" hoặc phiếu điều chỉnh.', old.ten;
    end if;
    -- 043: dời ngày đầu kỳ ra sau ngày của phiếu đã ghi → số dư bỏ sót phiếu đó trong khi công nợ vẫn trừ → chặn
    if new.ngay_dau_ky > old.ngay_dau_ky then
      select min(p.ngay) into v_ngay from public.phieu_thu_chi p
      where (p.tai_khoan_id = old.id or p.tai_khoan_den_id = old.id) and p.trang_thai = 'hieu_luc'
        and p.ngay >= old.ngay_dau_ky and p.ngay < new.ngay_dau_ky;
      if v_ngay is not null then
        raise exception 'Tài khoản "%" đã có phiếu ngày % – không dời ngày đầu kỳ sang % được (số dư sẽ bỏ sót phiếu đó). Chọn ngày đầu kỳ từ % trở về trước, hoặc hủy phiếu ghi nhầm.',
          old.ten, to_char(v_ngay, 'DD/MM/YYYY'), to_char(new.ngay_dau_ky, 'DD/MM/YYYY'), to_char(v_ngay, 'DD/MM/YYYY');
      end if;
    end if;
  end if;
  return new;
end $$;

-- Người đang thao tác (sửa thẳng trong Supabase không có phiên đăng nhập → để trống, không lỗi)
create or replace function app.nguoi_dang_lam() returns uuid
language plpgsql stable as $$
begin
  return auth.uid();
exception when others then return null;
end $$;

create or replace function app.ghi_lich_su_tai_khoan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.so_du_dau_ky, new.ngay_dau_ky) is not distinct from (old.so_du_dau_ky, old.ngay_dau_ky) then return null; end if;
  insert into public.tai_khoan_quy_lich_su (tai_khoan_id, so_du_cu, so_du_moi, ngay_cu, ngay_moi, sua_boi)
  values (new.id, case when tg_op = 'UPDATE' then old.so_du_dau_ky end, new.so_du_dau_ky,
          case when tg_op = 'UPDATE' then old.ngay_dau_ky end, new.ngay_dau_ky, app.nguoi_dang_lam());
  return null;
end $$;
drop trigger if exists tai_khoan_quy_lich_su on public.tai_khoan_quy;
create trigger tai_khoan_quy_lich_su after insert or update of so_du_dau_ky, ngay_dau_ky on public.tai_khoan_quy
  for each row execute function app.ghi_lich_su_tai_khoan();

-- A8. Phiếu gắn đơn vị liên quan không ghi trước ngày đầu kỳ của đơn vị (nợ đầu kỳ đã gồm các khoản trước ngày đó)
create or replace function app.kiem_ngay_dau_ky() returns trigger
language plpgsql security definer set search_path = public as $$
declare tk record; dv record;
begin
  for tk in select id, ten, ngay_dau_ky from public.tai_khoan_quy where id in (new.tai_khoan_id, new.tai_khoan_den_id) loop
    if new.ngay < tk.ngay_dau_ky then
      raise exception 'Ngày phiếu % trước ngày đầu kỳ % của tài khoản "%" – số dư đầu kỳ đã gồm các khoản trước ngày đó. Chọn ngày từ % trở đi (hoặc sửa ngày đầu kỳ ở Danh mục).',
        to_char(new.ngay, 'DD/MM/YYYY'), to_char(tk.ngay_dau_ky, 'DD/MM/YYYY'), tk.ten, to_char(tk.ngay_dau_ky, 'DD/MM/YYYY');
    end if;
  end loop;
  if new.don_vi_lien_quan_id is not null then
    select id, ten, ngay_dau_ky into dv from public.don_vi_lien_quan where id = new.don_vi_lien_quan_id;
    if dv.ngay_dau_ky is not null and new.ngay < dv.ngay_dau_ky then
      raise exception 'Ngày phiếu % trước ngày đầu kỳ % của "%" – nợ đầu kỳ đã gồm các khoản trước ngày đó. Chọn ngày từ % trở đi (hoặc sửa ngày đầu kỳ ở Danh mục → Đơn vị liên quan).',
        to_char(new.ngay, 'DD/MM/YYYY'), to_char(dv.ngay_dau_ky, 'DD/MM/YYYY'), dv.ten, to_char(dv.ngay_dau_ky, 'DD/MM/YYYY');
    end if;
  end if;
  return new;
end $$;

-- A8. Nợ nội bộ: chỉ cộng phiếu từ ngày đầu kỳ của đơn vị (trước đây cộng mọi phiếu → khoản trước đầu kỳ tính hai lần)
create or replace view public.v_cong_no_noi_bo with (security_invoker=true) as
 SELECT id,
    ten,
    loai,
    hoat_dong,
    so_du_dau_ky,
    ngay_dau_ky,
    chi_nhanh_id,
    da_chi,
    da_thu,
    ngay_cuoi,
    so_du_dau_ky + da_chi - da_thu AS con_lai
   FROM ( SELECT dv.id,
            dv.ten,
            dv.loai,
            dv.hoat_dong,
            dv.so_du_dau_ky,
            dv.ngay_dau_ky,
            c.chi_nhanh_id,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'chi'::text AND p.trang_thai = 'hieu_luc'::text
                    AND p.ngay >= COALESCE(dv.ngay_dau_ky, '-infinity'::date)), 0::numeric) AS da_chi,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'thu'::text AND p.trang_thai = 'hieu_luc'::text
                    AND p.ngay >= COALESCE(dv.ngay_dau_ky, '-infinity'::date)), 0::numeric) AS da_thu,
            ( SELECT max(p.ngay) AS max
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.trang_thai = 'hieu_luc'::text) AS ngay_cuoi
           FROM don_vi_lien_quan dv
             CROSS JOIN ( SELECT chi_nhanh.id AS chi_nhanh_id
                   FROM chi_nhanh) c
          WHERE (select app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text])) AND app.duoc_xem_chi_nhanh(c.chi_nhanh_id)) x;
revoke all on public.v_cong_no_noi_bo from anon;
grant select on public.v_cong_no_noi_bo to authenticated;

-- ---------------------------------------------------------------------
-- E12. Giảm giá theo TỪNG LẦN duyệt: mỗi lần ghi phần giảm thêm (hoặc bớt) vào ngày duyệt lần đó.
--   ho_so.giam_gia vẫn là TỔNG (giao diện cũ đọc như trước); doanh thu, số dư cuối tháng lấy theo từng lần
--   → giảm thêm cho xe đã giảm ở tháng đã chốt thì phần thêm vào tháng đang mở, tháng cũ giữ nguyên.
-- ---------------------------------------------------------------------
create table if not exists public.giam_gia_lan (
  id          bigint generated always as identity primary key,
  ho_so_id    bigint not null references public.ho_so(id) on delete cascade,
  ngay        date not null,
  so_tien     numeric(14,0) not null,             -- dương: giảm thêm; âm: bớt giảm giá
  ly_do       text,
  duyet_boi   uuid,
  tao_luc     timestamptz not null default now()
);
create index if not exists giam_gia_lan_ho_so_idx on public.giam_gia_lan (ho_so_id);
create index if not exists giam_gia_lan_ngay_idx on public.giam_gia_lan (ngay);
alter table public.giam_gia_lan enable row level security;
revoke all on public.giam_gia_lan from anon;
revoke insert, update, delete, truncate on public.giam_gia_lan from authenticated;
grant select on public.giam_gia_lan to authenticated;
drop policy if exists doc on public.giam_gia_lan;
create policy doc on public.giam_gia_lan for select to authenticated using ((select app.xem_nhu_nhan_vien()));
-- Chuyển số giảm giá đã có (một số, một ngày) thành lần đầu
insert into public.giam_gia_lan (ho_so_id, ngay, so_tien, ly_do, duyet_boi)
select h.id, coalesce(h.giam_gia_ngay, (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date), h.giam_gia, 'Giảm giá đã duyệt trước 043', h.giam_gia_duyet_boi
from public.ho_so h
where h.giam_gia > 0 and not exists (select 1 from public.giam_gia_lan g where g.ho_so_id = h.id);

-- B7/A. Hoa hồng GDV: tháng duyệt giá đã chốt thì ghi vào tháng đang mở (trước đây bị chặn, nhắc treo mãi)
alter table public.ho_so add column if not exists hoa_hong_ky date;
comment on column public.ho_so.hoa_hong_ky is 'Tháng tính hoa hồng GDV vào lãi lỗ khi tháng duyệt giá đầu đã chốt lúc nhập; trống = tháng duyệt giá đầu';

-- v_doanh_thu: phần giảm giá lấy theo từng lần (cột giữ nguyên)
create or replace view public.v_doanh_thu with (security_invoker = true) as
 SELECT h.chi_nhanh_id,
    m.ngay_duyet AS ngay,
    h.id AS ho_so_id,
    h.ma,
    public.bien_so_hien_thi(x.bien_so) AS bien_so,
    m.nguoi_tra AS nguon,
    m.nhom,
    public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat) AS so_tien,
    CASE WHEN m.xuat_hd THEN public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet ELSE 0::numeric END AS vat_ra,
    coalesce(m.to_id, CASE m.nhom WHEN 'dmg' THEN 'DMG' WHEN 'detailing' THEN 'DT' ELSE 'DS' END) AS to_id
   FROM public.hang_muc m
     JOIN public.ho_so h ON h.id = m.ho_so_id
     JOIN public.xe x ON x.id = h.xe_id
  WHERE m.trang_thai = ANY (ARRAY['duyet'::text, 'dang_lam'::text, 'xong'::text]) AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel AND h.loai <> 'bao_hanh'::text
UNION ALL
 SELECT d.chi_nhanh_id,
    d.ngay,
    NULL::bigint AS ho_so_id,
    NULL::text AS ma,
    public.bien_so_hien_thi(d.bien_so) AS bien_so,
    'dich_vu_nhanh'::text AS nguon,
    CASE d.to_id WHEN 'DMG'::text THEN 'dmg'::text ELSE 'detailing'::text END AS nhom,
    d.so_tien,
    CASE WHEN d.xuat_hd THEN d.so_tien - round(d.so_tien / (1::numeric + public.vat_ty_le(d.ngay))) ELSE 0::numeric END AS vat_ra,
    coalesce(d.to_id, 'DT') AS to_id
   FROM public.dich_vu_nhanh d
  WHERE d.trang_thai = 'hieu_luc'::text
UNION ALL
 SELECT h.chi_nhanh_id,
    g.ngay,
    h.id AS ho_so_id,
    h.ma,
    NULL::text AS bien_so,
    'giam_gia'::text AS nguon,
    NULL::text AS nhom,
    - g.so_tien AS so_tien,
    - round(g.so_tien * coalesce(v.ty_le, 0)) AS vat_ra,
    NULL::text AS to_id
   FROM public.giam_gia_lan g
   JOIN public.ho_so h ON h.id = g.ho_so_id
   LEFT JOIN LATERAL (
     SELECT sum(CASE WHEN m.xuat_hd THEN public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat) - m.gia_duyet ELSE 0 END)
            / nullif(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)), 0) AS ty_le
     FROM public.hang_muc m WHERE m.ho_so_id = h.id AND m.trang_thai IN ('duyet','dang_lam','xong')) v ON true
  WHERE g.so_tien <> 0 AND h.trang_thai <> 'huy'::text AND NOT h.tu_excel;
grant select on public.v_doanh_thu to authenticated;
revoke all on public.v_doanh_thu from anon;

-- E10. Doanh thu gộp theo tháng: theo chi nhánh (giám đốc xem mọi chi nhánh không còn bị cộng gộp)
drop function if exists public.doanh_thu_theo_thang();
create or replace function public.doanh_thu_theo_thang(p_chi_nhanh text default null)
returns table (thang date, bao_hiem numeric, khach numeric, dich_vu_nhanh numeric, giam_gia numeric, tong numeric, vat_ra numeric,
  dong_son numeric, phu_tung numeric, dmg numeric, detailing numeric, so_xe bigint, so_luot_dvn bigint)
language sql stable security invoker set search_path = public set jit = off as $$
  select date_trunc('month', d.ngay)::date,
    coalesce(sum(d.so_tien) filter (where d.nguon = 'bao_hiem'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'khach'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon = 'giam_gia'), 0),
    coalesce(sum(d.so_tien), 0), coalesce(sum(d.vat_ra), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom in ('dong','son','dong_son')), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'phu_tung'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'dmg'), 0),
    coalesce(sum(d.so_tien) filter (where d.nguon <> 'giam_gia' and d.nhom = 'detailing'), 0),
    count(distinct d.ho_so_id) filter (where d.nguon in ('bao_hiem','khach')),
    count(*) filter (where d.nguon = 'dich_vu_nhanh')
  from public.v_doanh_thu d
  where d.chi_nhanh_id = coalesce(p_chi_nhanh, app.chi_nhanh())
  group by 1 order by 1
$$;
revoke execute on function public.doanh_thu_theo_thang(text) from public, anon;
grant execute on function public.doanh_thu_theo_thang(text) to authenticated;

-- ---------------------------------------------------------------------
-- A9 + E3. Tiền – công nợ – tồn kho cuối tháng
--   + bh_chua_chia: tiền bảo hiểm đã về (phiếu đến ngày đó) chưa chia vào xe → trừ khỏi phải thu BH (trước đây đếm hai lần)
--   + phai_thu_dvn: dịch vụ nhanh chưa thu
--   + chi_phi_phai_tra: lương tháng chưa trả, hoa hồng GDV chưa chi, chi phí của tháng chi sau ngày cuối tháng
--   + no_noi_bo_rong: nợ với đơn vị liên quan / cá nhân (dương = họ nợ công ty)
--   giảm giá theo từng lần (E12)
-- ---------------------------------------------------------------------
create or replace function app.so_du_cuoi_thang(p_cn text, p_ngay date) returns jsonb
language sql stable security definer set search_path = public set jit = off as $$
  with quy as (
    select coalesce(sum(tk.so_du_dau_ky) filter (where tk.ngay_dau_ky <= p_ngay), 0)
      + coalesce((select sum(case when p.loai = 'thu' then p.so_tien when p.loai = 'chi' then -p.so_tien else 0 end)
                  from public.phieu_thu_chi p join public.tai_khoan_quy t2 on t2.id = p.tai_khoan_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and p.ngay >= t2.ngay_dau_ky), 0) as so_du
    from public.tai_khoan_quy tk where tk.chi_nhanh_id = p_cn),
  kho as (
    select coalesce(sum(l.so_luong * l.don_gia_von), 0)
      - coalesce((select sum(pd.gia_von) from public.phieu_xuat_dong pd join public.phieu_xuat px on px.id = pd.phieu_id
                  where px.chi_nhanh_id = p_cn and px.trang_thai = 'hieu_luc' and px.ngay <= p_ngay), 0) as ton
    from public.lo_kho l where l.chi_nhanh_id = p_cn and l.ngay <= p_ngay),
  hs as (
    select h.id, h.khau_tru_giam_tru,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'khach'), 0) as kh
    from public.ho_so h join public.hang_muc m on m.ho_so_id = h.id
    where h.chi_nhanh_id = p_cn and h.trang_thai <> 'huy' and h.loai <> 'bao_hanh'
      and m.trang_thai in ('duyet','dang_lam','xong') and m.ngay_duyet <= p_ngay
    group by h.id),
  gg as (
    select g.ho_so_id, sum(g.so_tien) as gg
    from public.giam_gia_lan g join public.ho_so h on h.id = g.ho_so_id
    where h.chi_nhanh_id = p_cn and h.trang_thai <> 'huy' and g.ngay <= p_ngay
    group by g.ho_so_id),
  tra as (
    select pb.ho_so_id,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0) as kh
    from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and pb.ho_so_id is not null
    group by pb.ho_so_id),
  -- cả hồ sơ chưa duyệt giá mà đã thu cọc (hoặc đã hủy còn giữ cọc): nợ khách âm = phải trả lại khách
  no as (
    select coalesce(hs.bh, 0) - coalesce(hs.khau_tru_giam_tru, 0) - coalesce(tra.bh, 0) as no_bh,
      coalesce(hs.kh, 0) + coalesce(hs.khau_tru_giam_tru, 0) - coalesce(gg.gg, 0) - coalesce(tra.kh, 0) as no_kh
    from hs full join tra on tra.ho_so_id = hs.id
    left join gg on gg.ho_so_id = coalesce(hs.id, tra.ho_so_id)),
  ncc as (
    select coalesce((select sum(pn.tong_tien) from public.phieu_nhap pn
                     where pn.chi_nhanh_id = p_cn and pn.trang_thai <> 'huy' and pn.ngay <= p_ngay), 0)
      - coalesce((select sum(p.so_tien) from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat = 'tra_ncc'
                    and p.nha_cung_cap_id is not null and p.ngay <= p_ngay), 0) as phai_tra),
  bh_cc as (
    select coalesce(sum(p.so_tien - coalesce((select sum(pb.so_tien) from public.phan_bo pb where pb.phieu_id = p.id), 0)), 0) as tien
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'thu' and m.tinh_chat = 'thu_bao_hiem' and p.ngay <= p_ngay),
  dvn as (
    select coalesce(sum(greatest(d.so_tien - coalesce((select sum(pb.so_tien) from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
                                                       where pb.dich_vu_nhanh_id = d.id and p.trang_thai = 'hieu_luc' and p.loai = 'thu' and p.ngay <= p_ngay), 0), 0)), 0) as tien
    from public.dich_vu_nhanh d where d.chi_nhanh_id = p_cn and d.trang_thai = 'hieu_luc' and d.ngay <= p_ngay),
  -- chi phí đã tính vào lãi lỗ đến tháng này (theo "chi phí của tháng") mà chi sau ngày cuối tháng
  cp_sau as (
    select coalesce(sum(p.so_tien), 0) as tien
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat = 'chi_phi'
      and p.ky_chi_phi is not null and p.ky_chi_phi <= p_ngay and p.ngay > p_ngay),
  -- lương theo bảng lương (đến tháng này) trừ phiếu trả lương (từ tháng có bảng lương đầu tiên)
  luong as (
    select greatest(0,
      coalesce((select sum(bl.tong_luong) from public.bang_luong_thang bl where bl.chi_nhanh_id = p_cn and bl.thang <= p_ngay), 0)
      - coalesce((select sum(p.so_tien) from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat = 'tra_luong' and p.ngay <= p_ngay
                    and p.ngay >= (select min(bl.thang) from public.bang_luong_thang bl where bl.chi_nhanh_id = p_cn)), 0)) as tien),
  -- hoa hồng GDV đã tính vào lãi lỗ (đến tháng này) mà chưa chi
  hh as (
    select coalesce(sum(greatest(h.hoa_hong_gdv - coalesce((
        select sum(p.so_tien) from public.phieu_thu_chi p join public.de_nghi_chi dn on dn.id = p.de_nghi_chi_id
        join public.muc_thu_chi m on m.id = p.muc_id
        where dn.ho_so_id = h.id and m.tinh_chat = 'tra_hoa_hong' and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and p.ngay <= p_ngay), 0), 0)), 0) as tien
    from public.ho_so h
    where h.chi_nhanh_id = p_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel
      and coalesce(h.hoa_hong_ky, (select date_trunc('month', min(m.ngay_duyet))::date from public.hang_muc m
                                   where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong'))) <= p_ngay),
  nb as (
    select coalesce(sum(dv.so_du_dau_ky) filter (where dv.ngay_dau_ky is null or dv.ngay_dau_ky <= p_ngay), 0)
      + coalesce((select sum(case when p.loai = 'chi' then p.so_tien else -p.so_tien end)
                  from public.phieu_thu_chi p join public.don_vi_lien_quan d2 on d2.id = p.don_vi_lien_quan_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai in ('thu','chi') and p.ngay <= p_ngay
                    and p.ngay >= coalesce(d2.ngay_dau_ky, '-infinity'::date)), 0) as tien
    from public.don_vi_lien_quan dv)
  select jsonb_build_object(
    'ngay', p_ngay,
    'so_du_quy', (select round(so_du) from quy),
    'ton_kho', (select round(ton) from kho),
    'phai_thu_khach', (select round(coalesce(sum(greatest(no_kh, 0)), 0)) from no),
    'phai_thu_bh', (select round(coalesce(sum(greatest(no_bh, 0)), 0)) from no),
    'khach_tra_du', (select round(coalesce(sum(greatest(-no_kh, 0)), 0)) from no),
    'phai_tra_ncc', (select round(phai_tra) from ncc),
    'bh_chua_chia', (select round(tien) from bh_cc),
    'phai_thu_dvn', (select round(tien) from dvn),
    'luong_chua_tra', (select round(tien) from luong),
    'hoa_hong_chua_chi', (select round(tien) from hh),
    'chi_phi_chi_sau', (select round(tien) from cp_sau),
    'chi_phi_phai_tra', (select round(tien) from luong) + (select round(tien) from hh) + (select round(tien) from cp_sau),
    'no_noi_bo_rong', (select round(tien) from nb))
$$;
revoke execute on function app.so_du_cuoi_thang(text, date) from public, anon;
alter function public.so_du_cuoi_thang(date, text) set jit = off;

-- ---------------------------------------------------------------------
-- 4. Kết quả kinh doanh (giữ cột cũ, thêm 3 cột cuối)
--   - trang_thai 'da_khoa': tháng trống nằm trước tháng đã chốt (khóa theo, không phải chốt)
--   - thu nhập khác chỉ mục thu "thu khác" có tích vào lãi lỗ (E1)
--   - hoa hồng theo tháng hoa_hong_ky nếu có (tháng duyệt đã chốt lúc nhập)
--   - E2: VAT còn được khấu trừ chuyển sang tháng sau: vat_khau_tru_ky_truoc, vat_nop_sau_khau_tru
--   - E7: gia_tri_xe_moi = tổng giá duyệt của các xe tính vào "xe sửa chữa" của tháng (bình quân một xe)
--   - E11: tắt JIT (dữ liệu lớn dần, kế hoạch ước nhiều dòng → biên dịch JIT mất vài giây)
-- ---------------------------------------------------------------------
drop function if exists public.ket_qua_kinh_doanh(text);
create function public.ket_qua_kinh_doanh(p_chi_nhanh text default null)
returns table (
  thang date, ngay_cuoi date, trang_thai text,
  doanh_thu_bh numeric, doanh_thu_khach numeric, doanh_thu_dvn numeric, giam_gia numeric, doanh_thu numeric, vat_ra numeric,
  gia_von_xe numeric, gia_von_dung_chung numeric, chi_gia_von numeric, lai_gop numeric,
  luong numeric, hoa_hong numeric, chi_van_hanh numeric, chi_co_dinh numeric, lai_truoc_thue numeric, vat_vao numeric, so_xe bigint,
  luong_da_nhap boolean, thieu_dinh_ky text[], de_nghi_cho_chi bigint, da_chot boolean, chot_luc timestamptz,
  -- 042
  hao_hut numeric, tong_gia_von numeric, tong_chi_phi numeric, thu_khac numeric,
  vat_vao_hang numeric, vat_vao_chi_phi numeric, vat_trong_gia_von numeric, vat_phai_nop numeric, lai_sau_vat numeric,
  so_luot_dvn bigint, lech_chot boolean, lai_truoc_thue_song numeric,
  -- 043
  vat_khau_tru_ky_truoc numeric, vat_nop_sau_khau_tru numeric, gia_tri_xe_moi numeric)
language plpgsql stable security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' set jit = off as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_dau date; v_khoa date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select max(ct.thang) into v_khoa from public.chot_thang ct where ct.chi_nhanh_id = v_cn;
  select least(
    (select min(date_trunc('month', d.ngay))::date from public.v_doanh_thu d where d.chi_nhanh_id = v_cn),
    (select min(date_trunc('month', px.ngay))::date from public.phieu_xuat px where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc'),
    (select min(coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date)) from public.phieu_thu_chi p where p.chi_nhanh_id = v_cn and p.trang_thai = 'hieu_luc'),
    (select min(date_trunc('month', pn.ngay))::date from public.phieu_nhap pn where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy'),
    (select min(bl.thang) from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn),
    (select min(ct.thang) from public.chot_thang ct where ct.chi_nhanh_id = v_cn),
    date_trunc('month', current_date)::date) into v_dau;
  return query
  with cac_thang as (
    select g::date as th from generate_series(v_dau, date_trunc('month', current_date)::date, interval '1 month') g),
  thang_dt as (
    select date_trunc('month', d.ngay)::date as th,
      sum(d.so_tien) filter (where d.nguon = 'bao_hiem') as bh,
      sum(d.so_tien) filter (where d.nguon = 'khach') as kh,
      sum(d.so_tien) filter (where d.nguon = 'dich_vu_nhanh') as dvn,
      sum(d.so_tien) filter (where d.nguon = 'giam_gia') as gg,
      sum(d.vat_ra) as vat, count(*) filter (where d.nguon = 'dich_vu_nhanh') as luot_dvn
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn group by 1),
  -- Số xe: tính ở tháng duyệt giá đầu tiên của hồ sơ (lũy kế không đếm trùng); kèm tổng giá đã duyệt của các xe đó
  thang_xe as (
    select date_trunc('month', x.dau)::date as th, count(*) as xe, sum(x.tong) as gt
    from (select min(m.ngay_duyet) as dau, sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)) as tong
          from public.hang_muc m join public.ho_so h on h.id = m.ho_so_id
          where h.chi_nhanh_id = v_cn and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
            and m.trang_thai in ('duyet','dang_lam','xong') group by m.ho_so_id) x
    group by 1),
  thang_kho as (
    select date_trunc('month', px.ngay)::date as th,
      sum(pd.gia_von) filter (where px.loai = 'cho_xe') as xe, sum(pd.gia_von) filter (where px.loai = 'dung_chung') as dc,
      sum(pd.gia_von) filter (where px.loai = 'kiem_ke') as kk_thieu
    from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
    where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' group by 1),
  -- Kiểm kê thừa: lô thêm vào kho → giảm hao hụt của tháng
  thang_thua as (
    select date_trunc('month', l.ngay)::date as th, round(sum(l.so_luong * l.don_gia_von)) as thua
    from public.lo_kho l where l.chi_nhanh_id = v_cn and l.kiem_ke_id is not null group by 1),
  thang_chi as (
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) as th,
      sum(p.so_tien) filter (where m.nhom = 'gia_von') as gv,
      sum(p.so_tien) filter (where m.nhom = 'co_dinh') as cd,
      sum(p.so_tien) filter (where coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh')) as vh,
      sum(p.vat_dau_vao) as vat_vao
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' group by 1),
  thang_thu_khac as (
    select date_trunc('month', p.ngay)::date as th, sum(p.so_tien) as tk
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'thu' and p.trang_thai = 'hieu_luc' and m.vao_lai_lo and m.tinh_chat = 'thu_khac' group by 1),
  thang_vat_nhap as (
    select date_trunc('month', pn.ngay)::date as th, sum(pn.tien_vat) as vat
    from public.phieu_nhap pn where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy' group by 1),
  -- VAT nằm trong giá vốn vật tư đã xuất (lô của phiếu nhập có VAT), làm tròn theo từng phiếu xuất như chi_tiet_kqkd
  thang_vat_gv as (
    select date_trunc('month', v.ngay)::date as th, sum(v.vat) as vat
    from (select px.ngay, round(sum(xl.so_luong * xl.don_gia_von * pnd.ty_le_vat / (1 + pnd.ty_le_vat))) as vat
          from public.phieu_xuat px
          join public.phieu_xuat_dong pd on pd.phieu_id = px.id
          join public.xuat_lo xl on xl.phieu_xuat_dong_id = pd.id
          join public.lo_kho l on l.id = xl.lo_id
          join public.phieu_nhap_dong pnd on pnd.id = l.phieu_nhap_dong_id
          where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and pnd.ty_le_vat > 0
          group by px.id, px.ngay) v
    group by 1),
  thang_hh as (
    select coalesce(h.hoa_hong_ky,
             date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date) as th,
      sum(h.hoa_hong_gdv) as hh
    from public.ho_so h where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel group by 1),
  song as (
    select t.th,
      coalesce(dt.bh,0) as dt_bh, coalesce(dt.kh,0) as dt_kh, coalesce(dt.dvn,0) as dt_dvn, coalesce(dt.gg,0) as gg,
      coalesce(dt.bh,0) + coalesce(dt.kh,0) + coalesce(dt.dvn,0) + coalesce(dt.gg,0) as dthu, coalesce(dt.vat,0) as vat_ra,
      coalesce(k.xe,0) as gv_xe, coalesce(k.dc,0) as gv_dc, coalesce(c.gv,0) as chi_gv,
      coalesce(k.kk_thieu,0) - coalesce(tt.thua,0) as hao,
      coalesce(bl.tong_luong,0) as luong, coalesce(hh.hh,0) as hh, coalesce(c.vh,0) as vh, coalesce(c.cd,0) as cd,
      coalesce(tk.tk,0) as thu_khac,
      coalesce(vn.vat,0) as vat_hang, coalesce(c.vat_vao,0) as vat_cp, coalesce(vg.vat,0) as vat_gv,
      coalesce(x.xe,0) as so_xe, coalesce(x.gt,0) as gt_xe, coalesce(dt.luot_dvn,0) as luot_dvn,
      bl.thang is not null as co_luong, ct.thang is not null as da_chot, ct.chot_luc, ct.so_lieu
    from cac_thang t
    left join thang_dt dt on dt.th = t.th
    left join thang_xe x on x.th = t.th
    left join thang_kho k on k.th = t.th
    left join thang_thua tt on tt.th = t.th
    left join thang_chi c on c.th = t.th
    left join thang_thu_khac tk on tk.th = t.th
    left join thang_vat_nhap vn on vn.th = t.th
    left join thang_vat_gv vg on vg.th = t.th
    left join thang_hh hh on hh.th = t.th
    left join public.bang_luong_thang bl on bl.chi_nhanh_id = v_cn and bl.thang = t.th
    left join public.chot_thang ct on ct.chi_nhanh_id = v_cn and ct.thang = t.th),
  tinh as (
    select s.*,
      s.gv_xe + s.gv_dc + s.hao + s.chi_gv as tong_gv,
      s.luong + s.hh + s.vh + s.cd as tong_cp
    from song s),
  tinh2 as (
    select t.*, t.dthu - t.tong_gv as lai_gop, t.dthu - t.tong_gv - t.tong_cp + t.thu_khac as lai_tt,
      t.vat_ra - t.vat_hang - t.vat_cp as vat_nop,
      -- lãi không gồm VAT (dồn tích): bỏ VAT khỏi doanh thu, khỏi giá vốn đã xuất và khỏi chi phí
      t.dthu - t.tong_gv - t.tong_cp + t.thu_khac - t.vat_ra + t.vat_gv + t.vat_cp as lai_kv
    from tinh t),
  -- E2. VAT khấu trừ chuyển kỳ: lũy kế S của VAT phải nộp từng tháng (tháng đã chốt: số lúc chốt);
  --     còn được khấu trừ cuối tháng = max(0, S lớn nhất đến tháng đó) − S; phải nộp sau khấu trừ = v − đầu + cuối
  vat1 as (
    select t.*, sum(app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop)) over w as luy_ke
    from tinh2 t window w as (order by t.th rows between unbounded preceding and current row)),
  vat2 as (
    select v.*, greatest(0, max(v.luy_ke) over w) - v.luy_ke as kt_cuoi
    from vat1 v window w as (order by v.th rows between unbounded preceding and current row)),
  vat3 as (
    select v.*, coalesce(lag(v.kt_cuoi) over (order by v.th), 0) as kt_dau from vat2 v)
  select t.th, (t.th + interval '1 month' - interval '1 day')::date,
    case when t.da_chot then 'da_chot' when v_khoa is not null and t.th < v_khoa then 'da_khoa'
         when t.th >= date_trunc('month', current_date)::date then 'dang_mo' else 'cho_chot' end,
    app.so_chot(t.so_lieu, 'doanh_thu_bh', t.dt_bh), app.so_chot(t.so_lieu, 'doanh_thu_khach', t.dt_kh),
    app.so_chot(t.so_lieu, 'doanh_thu_dvn', t.dt_dvn), app.so_chot(t.so_lieu, 'giam_gia', t.gg),
    app.so_chot(t.so_lieu, 'doanh_thu', t.dthu), app.so_chot(t.so_lieu, 'vat_ra', t.vat_ra),
    app.so_chot(t.so_lieu, 'gia_von_xe', t.gv_xe), app.so_chot(t.so_lieu, 'gia_von_dung_chung', t.gv_dc),
    app.so_chot(t.so_lieu, 'chi_gia_von', t.chi_gv), app.so_chot(t.so_lieu, 'lai_gop', t.lai_gop),
    app.so_chot(t.so_lieu, 'luong', t.luong), app.so_chot(t.so_lieu, 'hoa_hong', t.hh),
    app.so_chot(t.so_lieu, 'chi_van_hanh', t.vh), app.so_chot(t.so_lieu, 'chi_co_dinh', t.cd),
    app.so_chot(t.so_lieu, 'lai_truoc_thue', t.lai_tt), app.so_chot(t.so_lieu, 'vat_vao', t.vat_hang + t.vat_cp),
    app.so_chot(t.so_lieu, 'so_xe', t.so_xe)::bigint,
    t.co_luong,
    coalesce((select array_agg(m.ten order by m.ten) from public.muc_thu_chi m
      where m.loai = 'chi' and m.dinh_ky and m.hoat_dong
        and not exists (select 1 from public.phieu_thu_chi p where p.muc_id = m.id and p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc'
                          and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = t.th)
        and not exists (select 1 from public.de_nghi_chi d where d.muc_id = m.id and d.chi_nhanh_id = v_cn and d.trang_thai not in ('huy','tu_choi')
                          and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th)), '{}'::text[]),
    (select count(*) from public.de_nghi_chi d where d.chi_nhanh_id = v_cn and d.trang_thai in ('cho_duyet','da_duyet')
       and coalesce(d.ky_chi_phi, date_trunc('month', d.ngay)::date) = t.th),
    t.da_chot, t.chot_luc,
    app.so_chot(t.so_lieu, 'hao_hut', t.hao), app.so_chot(t.so_lieu, 'tong_gia_von', t.tong_gv),
    app.so_chot(t.so_lieu, 'tong_chi_phi', t.tong_cp), app.so_chot(t.so_lieu, 'thu_khac', t.thu_khac),
    app.so_chot(t.so_lieu, 'vat_vao_hang', t.vat_hang), app.so_chot(t.so_lieu, 'vat_vao_chi_phi', t.vat_cp),
    app.so_chot(t.so_lieu, 'vat_trong_gia_von', t.vat_gv),
    app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop), app.so_chot(t.so_lieu, 'lai_sau_vat', t.lai_kv),
    app.so_chot(t.so_lieu, 'so_luot_dvn', t.luot_dvn)::bigint,
    -- Tháng đã chốt: số hiện tại khác số lúc chốt (hoặc chốt theo cách tính cũ) → cần mở lại, chốt lại
    t.da_chot and (not coalesce(t.so_lieu ? 'phien_ban', false)
      or abs(t.dthu - app.so_chot(t.so_lieu, 'doanh_thu', t.dthu)) >= 1
      or abs(t.lai_gop - app.so_chot(t.so_lieu, 'lai_gop', t.lai_gop)) >= 1
      or abs(t.lai_tt - app.so_chot(t.so_lieu, 'lai_truoc_thue', t.lai_tt)) >= 1
      or abs(t.vat_nop - app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop)) >= 1
      or abs(t.lai_kv - app.so_chot(t.so_lieu, 'lai_sau_vat', t.lai_kv)) >= 1),
    t.lai_tt,
    app.so_chot(t.so_lieu, 'vat_khau_tru_ky_truoc', t.kt_dau),
    app.so_chot(t.so_lieu, 'vat_nop_sau_khau_tru', app.so_chot(t.so_lieu, 'vat_phai_nop', t.vat_nop) - t.kt_dau + t.kt_cuoi),
    app.so_chot(t.so_lieu, 'gia_tri_xe_moi', t.gt_xe)
  from vat3 t
  order by t.th;
end $$;
revoke execute on function public.ket_qua_kinh_doanh(text) from public, anon;
grant execute on function public.ket_qua_kinh_doanh(text) to authenticated;

-- ---------------------------------------------------------------------
-- A1. Chốt tháng: lỗi "malformed array literal" khi chưa nhập lương (chuỗi trần bị hiểu là mảng);
--     đọc kết quả kinh doanh MỘT lần (trước đây hai lần); thêm nhắc: tiền BH chưa chia vào xe, xe chưa nhập
--     hoa hồng GDV, đợt kiểm kê đang đếm; tháng trống trước tháng đã chốt là khóa theo, không phải chốt.
-- ---------------------------------------------------------------------
create or replace function public.chot_thang(p_thang date, p_bo_qua_canh_bao boolean default false, p_chi_nhanh text default null) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' set jit = off as $$
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_thang date := date_trunc('month', p_thang)::date;
  v_cuoi date := (date_trunc('month', p_thang) + interval '1 month - 1 day')::date;
  k record; x record; v_co boolean := false; v_thieu text[] := '{}'; v_truoc date; v_so jsonb; v_khoa date; n bigint; v_tien numeric; v_ma text;
begin
  perform app.yeu_cau('giam_doc');
  if v_thang >= date_trunc('month', current_date)::date then raise exception 'Chỉ chốt được tháng đã qua (kỳ khóa ở ngày cuối tháng).'; end if;
  if exists (select 1 from public.chot_thang where chi_nhanh_id = v_cn and thang = v_thang) then raise exception 'Tháng này đã chốt rồi.'; end if;
  select max(thang) into v_khoa from public.chot_thang where chi_nhanh_id = v_cn and thang > v_thang;
  if v_khoa is not null then
    raise exception 'Tháng % nằm trước tháng đã chốt % nên đã khóa sổ theo – không cần chốt riêng.', to_char(v_thang, 'MM/YYYY'), to_char(v_khoa, 'MM/YYYY');
  end if;
  -- Một lần đọc kết quả kinh doanh: tháng cần chốt + tháng trước còn số liệu chưa chốt (chốt lần lượt)
  for x in select * from public.ket_qua_kinh_doanh(v_cn) r where r.thang <= v_thang loop
    if x.thang < v_thang and x.trang_thai = 'cho_chot' and v_truoc is null
       and (x.doanh_thu <> 0 or x.tong_gia_von <> 0 or x.tong_chi_phi <> 0 or x.thu_khac <> 0 or x.luong_da_nhap or x.vat_vao_hang <> 0) then
      v_truoc := x.thang;
    end if;
    if x.thang = v_thang then k := x; v_co := true; end if;
  end loop;
  if v_truoc is not null then
    raise exception 'Chốt tháng % trước (chốt lần lượt từng tháng).', to_char(v_truoc, 'MM/YYYY'); end if;
  if not v_co then raise exception 'Tháng này chưa có số liệu.'; end if;
  if not p_bo_qua_canh_bao then
    if not k.luong_da_nhap then v_thieu := v_thieu || 'chưa nhập bảng lương'::text; end if;
    if cardinality(k.thieu_dinh_ky) > 0 then v_thieu := v_thieu || ('chưa có chi phí định kỳ: ' || array_to_string(k.thieu_dinh_ky, ', ')); end if;
    if k.de_nghi_cho_chi > 0 then v_thieu := v_thieu || (k.de_nghi_cho_chi || ' đề nghị chi của kỳ chưa chi'); end if;
    -- tiền bảo hiểm đã về chưa chia vào xe → công nợ bảo hiểm cuối tháng chưa đúng
    select count(*), coalesce(sum(p.so_tien - coalesce((select sum(pb.so_tien) from public.phan_bo pb where pb.phieu_id = p.id), 0)), 0)
      into n, v_tien
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.trang_thai = 'hieu_luc' and p.loai = 'thu' and m.tinh_chat = 'thu_bao_hiem' and p.ngay <= v_cuoi
      and p.so_tien > coalesce((select sum(pb.so_tien) from public.phan_bo pb where pb.phieu_id = p.id), 0);
    if n > 0 then v_thieu := v_thieu || (n || ' phiếu bảo hiểm trả còn ' || app.vnd(v_tien) || ' đ chưa chia vào xe'); end if;
    -- xe bảo hiểm duyệt giá đầu trong tháng chưa nhập hoa hồng GDV (nhập sau khi chốt sẽ tính vào tháng đang mở)
    select count(*) into n from public.ho_so h
    where h.chi_nhanh_id = v_cn and h.gdv_id is not null and h.hoa_hong_gdv is null and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
      and date_trunc('month', (select min(m.ngay_duyet) from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')))::date = v_thang;
    if n > 0 then v_thieu := v_thieu || (n || ' xe bảo hiểm duyệt giá trong tháng chưa nhập hoa hồng GDV'); end if;
    -- đợt kiểm kê đếm trong tháng chưa chốt → chênh lệch sẽ ghi sang tháng sau
    select string_agg(kk.ma, ', ') into v_ma from public.kiem_ke kk where kk.chi_nhanh_id = v_cn and kk.trang_thai = 'dang_dem' and kk.ngay <= v_cuoi;
    if v_ma is not null then v_thieu := v_thieu || ('đợt kiểm kê ' || v_ma || ' đang đếm, chưa chốt'); end if;
    if cardinality(v_thieu) > 0 then
      raise exception 'CANH_BAO: Tháng % còn thiếu: %. Chốt xong sẽ không nhập thêm được vào tháng này. Vẫn chốt?',
        to_char(v_thang, 'MM/YYYY'), array_to_string(v_thieu, '; ');
    end if;
  end if;
  v_so := to_jsonb(k) - 'da_chot' - 'chot_luc' - 'trang_thai' - 'lech_chot' - 'lai_truoc_thue_song'
    || jsonb_build_object('phien_ban', 2, 'so_du', app.so_du_cuoi_thang(v_cn, k.ngay_cuoi));
  insert into public.chot_thang (chi_nhanh_id, thang, chot_boi, so_lieu) values (v_cn, v_thang, auth.uid(), v_so);
  return v_so;
end $$;

-- ---------------------------------------------------------------------
-- E9. Tổ của phiếu xuất cho xe: theo tổ đề xuất; xuất không qua đề xuất (nhập – xuất ngay, xuất lẻ) mà biết xe
--     thì theo tổ làm dòng phụ tùng của xe đó (không có thì tổ làm dòng giá trị lớn nhất)
-- ---------------------------------------------------------------------
create or replace function app.to_cua_phieu_xuat(p_px bigint) returns text
language sql stable security definer set search_path = public as $$
  select case when px.loai <> 'cho_xe' then null else coalesce(
    (select dx.to_id from public.de_xuat_vat_tu dx where dx.id = px.de_xuat_id),
    (select coalesce(m.to_id, case m.nhom when 'dmg' then 'DMG' when 'detailing' then 'DT' else 'DS' end)
     from public.hang_muc m where m.ho_so_id = px.ho_so_id and m.trang_thai in ('duyet','dang_lam','xong')
     order by (m.nhom = 'phu_tung') desc, coalesce(m.gia_duyet, 0) desc, m.id limit 1)) end
  from public.phieu_xuat px where px.id = p_px
$$;
revoke execute on function app.to_cua_phieu_xuat(bigint) from public, anon;

-- ---------------------------------------------------------------------
-- 6. Chi tiết một ô: thu nhập khác chỉ mục "thu khác"; hoa hồng theo tháng tính; vật tư xuất ngay hiện tổ
-- ---------------------------------------------------------------------
create or replace function public.chi_tiet_kqkd(p_thang date, p_khoan text, p_chi_nhanh text default null)
returns table (nhom text, ten text, ngay date, so_tien numeric, ho_so_id bigint, ma text)
language plpgsql stable security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' set jit = off as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_tu date := date_trunc('month', p_thang)::date;
  v_den date := (date_trunc('month', p_thang) + interval '1 month - 1 day')::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  if p_khoan in ('doanh_thu_bh','doanh_thu_khach','giam_gia') then
    return query
      select coalesce(t.ten, case when p_khoan = 'giam_gia' then 'Giảm giá cho khách' else 'Khác' end),
        coalesce(d.bien_so_hs || ' · ', '') || d.ma, min(d.ngay), sum(d.so_tien), d.ho_so_id, d.ma
      from (select v.*, coalesce(v.bien_so, (select public.bien_so_hien_thi(x.bien_so) from public.ho_so h join public.xe x on x.id = h.xe_id where h.id = v.ho_so_id)) as bien_so_hs
            from public.v_doanh_thu v
            where v.chi_nhanh_id = v_cn and v.ngay between v_tu and v_den
              and v.nguon = case p_khoan when 'doanh_thu_bh' then 'bao_hiem' when 'doanh_thu_khach' then 'khach' else 'giam_gia' end) d
      left join public.to_thuc_hien t on t.id = d.to_id
      group by t.ten, d.bien_so_hs, d.ma, d.ho_so_id order by 4 desc;
  elsif p_khoan = 'doanh_thu_dvn' then
    return query
      select coalesce(t.ten, 'Detailing'), d.dich_vu || coalesce(' · ' || public.bien_so_hien_thi(d.bien_so), ''), d.ngay, d.so_tien, null::bigint, null::text
      from public.dich_vu_nhanh d left join public.to_thuc_hien t on t.id = d.to_id
      where d.chi_nhanh_id = v_cn and d.trang_thai = 'hieu_luc' and d.ngay between v_tu and v_den order by d.ngay, d.id;
  elsif p_khoan in ('gia_von_xe','gia_von_dung_chung','hao_hut') then
    return query
      select case px.loai when 'cho_xe' then case when px.de_xuat_id is not null then coalesce(t.ten, 'Theo đề xuất')
                                                  else coalesce(t.ten || ' – xuất ngay / xuất lẻ', 'Không qua đề xuất (xuất ngay, xuất lẻ)') end
                          when 'dung_chung' then 'Dùng chung xưởng' else 'Kiểm kê thiếu' end,
        px.ma || coalesce(' · ' || h.ma, '') || coalesce(' · ' || nullif(px.ghi_chu, ''), ''), px.ngay, sum(pd.gia_von), px.ho_so_id, h.ma
      from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
      left join public.ho_so h on h.id = px.ho_so_id
      left join public.to_thuc_hien t on t.id = app.to_cua_phieu_xuat(px.id)
      where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and v_den
        and px.loai = case p_khoan when 'gia_von_xe' then 'cho_xe' when 'gia_von_dung_chung' then 'dung_chung' else 'kiem_ke' end
      group by px.id, px.loai, px.de_xuat_id, t.ten, px.ma, h.ma, px.ghi_chu, px.ngay, px.ho_so_id
      union all
      select 'Kiểm kê thừa (giảm hao hụt)', kk.ma || ' · ' || hk.ma || ' ' || hk.ten, l.ngay, -round(l.so_luong * l.don_gia_von), null::bigint, null::text
      from public.lo_kho l join public.kiem_ke kk on kk.id = l.kiem_ke_id join public.hang_kho hk on hk.id = l.hang_id
      where p_khoan = 'hao_hut' and l.chi_nhanh_id = v_cn and l.ngay between v_tu and v_den
      order by 1, 3;
  elsif p_khoan in ('chi_gia_von','chi_van_hanh','chi_co_dinh') then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.so_tien, dn.ho_so_id, h.ma
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      left join public.de_nghi_chi dn on dn.id = p.de_nghi_chi_id
      left join public.ho_so h on h.id = dn.ho_so_id
      where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
        and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = v_tu
        and case p_khoan when 'chi_gia_von' then m.nhom = 'gia_von' when 'chi_co_dinh' then m.nhom = 'co_dinh'
                         else coalesce(m.nhom, 'van_hanh') not in ('gia_von','co_dinh') end
      order by m.ten, p.ngay;
  elsif p_khoan = 'thu_khac' then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.so_tien, null::bigint, null::text
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      where p.chi_nhanh_id = v_cn and p.loai = 'thu' and p.trang_thai = 'hieu_luc' and m.vao_lai_lo and m.tinh_chat = 'thu_khac'
        and p.ngay between v_tu and v_den
      order by m.ten, p.ngay;
  elsif p_khoan = 'hoa_hong' then
    return query
      select coalesce(g.ten, h.gdv_ten_tam, 'GDV'),
        public.bien_so_hien_thi(x.bien_so) || ' · ' || h.ma || case when h.hoa_hong_ky is not null then ' (xe duyệt giá ' || to_char(d.dau, 'MM/YYYY') || ', tháng đó đã chốt)' else '' end,
        d.dau, h.hoa_hong_gdv, h.id, h.ma
      from public.ho_so h join public.xe x on x.id = h.xe_id
      left join public.giam_dinh_vien g on g.id = h.gdv_id
      join lateral (select min(m.ngay_duyet) as dau from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) d on true
      where h.chi_nhanh_id = v_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel
        and coalesce(h.hoa_hong_ky, date_trunc('month', d.dau)::date) = v_tu
      order by 1, 3;
  elsif p_khoan = 'luong' then
    return query
      select 'Bảng lương tháng'::text, 'Tổng lương tháng ' || to_char(v_tu, 'MM/YYYY'), v_den, bl.tong_luong, null::bigint, null::text
      from public.bang_luong_thang bl where bl.chi_nhanh_id = v_cn and bl.thang = v_tu;
  elsif p_khoan in ('vat_vao_hang') then
    return query
      select coalesce(n.ten, 'Nhà cung cấp'), pn.ma || coalesce(' · HĐ ' || pn.so_hoa_don, ''), pn.ngay, pn.tien_vat, pn.ho_so_id, null::text
      from public.phieu_nhap pn left join public.nha_cung_cap n on n.id = pn.nha_cung_cap_id
      where pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy' and pn.ngay between v_tu and v_den and pn.tien_vat <> 0
      order by 1, 3;
  elsif p_khoan in ('vat_vao_chi_phi') then
    return query
      select m.ten, coalesce(p.noi_dung, m.ten), p.ngay, p.vat_dau_vao, null::bigint, null::text
      from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
      where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi'
        and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) = v_tu and p.vat_dau_vao <> 0
      order by 1, 3;
  elsif p_khoan = 'vat_trong_gia_von' then
    -- VAT nằm trong giá vốn vật tư đã xuất: theo từng phiếu xuất (lô của phiếu nhập có VAT)
    return query
      select case px.loai when 'cho_xe' then 'Xuất cho xe' when 'dung_chung' then 'Dùng chung xưởng' else 'Kiểm kê thiếu' end,
        px.ma || coalesce(' · ' || h.ma, ''), px.ngay,
        round(sum(xl.so_luong * xl.don_gia_von * pnd.ty_le_vat / (1 + pnd.ty_le_vat))), px.ho_so_id, h.ma
      from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
      join public.xuat_lo xl on xl.phieu_xuat_dong_id = pd.id
      join public.lo_kho l on l.id = xl.lo_id
      join public.phieu_nhap_dong pnd on pnd.id = l.phieu_nhap_dong_id
      left join public.ho_so h on h.id = px.ho_so_id
      where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and v_den and pnd.ty_le_vat > 0
      group by px.id, px.loai, px.ma, h.ma, px.ngay, px.ho_so_id
      order by 1, 3;
  elsif p_khoan = 'vat_ra' then
    return query
      select case d.nguon when 'dich_vu_nhanh' then 'Dịch vụ nhanh' when 'giam_gia' then 'Giảm giá (giảm VAT đầu ra)' else 'Hồ sơ xe' end,
        concat_ws(' · ', d.bien_so_hs, d.ma), min(d.ngay), sum(d.vat_ra), d.ho_so_id, d.ma
      from (select v.*, coalesce(v.bien_so, (select public.bien_so_hien_thi(x.bien_so) from public.ho_so h join public.xe x on x.id = h.xe_id where h.id = v.ho_so_id)) as bien_so_hs
            from public.v_doanh_thu v
            where v.chi_nhanh_id = v_cn and v.ngay between v_tu and v_den and v.vat_ra <> 0) d
      group by d.nguon, d.bien_so_hs, d.ma, d.ho_so_id order by 1, 4 desc;
  elsif p_khoan = 'so_xe' then
    -- Xe tính vào tháng duyệt giá đầu tiên; số tiền = tổng giá đã duyệt (gồm VAT) của hồ sơ
    return query
      select case h.nguon_tt when 'khach' then 'Khách ngoài bảo hiểm' else coalesce(b.ten, 'Bảo hiểm') end,
        public.bien_so_hien_thi(x.bien_so) || ' · ' || h.ma, d.dau, d.tong, h.id, h.ma
      from public.ho_so h join public.xe x on x.id = h.xe_id
      left join public.hang_bao_hiem b on b.id = h.hang_bh_id
      join lateral (select min(m.ngay_duyet) as dau,
                      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)), 0) as tong
                    from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong')) d on true
      where h.chi_nhanh_id = v_cn and h.trang_thai <> 'huy' and not h.tu_excel and h.loai <> 'bao_hanh'
        and date_trunc('month', d.dau)::date = v_tu
      order by 1, 3;
  else
    raise exception 'Khoản "%" không có chi tiết.', p_khoan;
  end if;
end $$;
revoke execute on function public.chi_tiet_kqkd(date, text, text) from public, anon;
grant execute on function public.chi_tiet_kqkd(date, text, text) to authenticated;

-- Lãi gộp theo tổ: vật tư xuất ngay / xuất lẻ cho xe tính vào tổ làm xe đó (trước đây dồn vào "Chung")
create or replace function public.lai_gop_theo_to(p_tu date, p_den date, p_chi_nhanh text default null)
returns table (thang date, to_id text, ten_to text, doanh_thu numeric, gia_von numeric, so_xe bigint, so_luot_dvn bigint)
language plpgsql stable security definer set search_path = public set jit = off as $$
#variable_conflict use_column
declare v_cn text := coalesce(p_chi_nhanh, app.chi_nhanh()); v_tu date := date_trunc('month', p_tu)::date;
begin
  if not app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong') then
    raise exception 'Bạn không có quyền xem báo cáo này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return query
  with dt as (
    select date_trunc('month', d.ngay)::date as th, coalesce(d.to_id, 'CHUNG') as to_id, sum(d.so_tien) as dthu,
      count(distinct d.ho_so_id) as xe, count(*) filter (where d.nguon = 'dich_vu_nhanh') as dvn
    from public.v_doanh_thu d where d.chi_nhanh_id = v_cn and d.ngay between v_tu and p_den group by 1, 2),
  gv as (
    select date_trunc('month', x.ngay)::date as th, coalesce(app.to_cua_phieu_xuat(x.id), 'CHUNG') as to_id, sum(x.gv) as gv
    from (select px.id, px.ngay, sum(pd.gia_von) as gv
          from public.phieu_xuat px join public.phieu_xuat_dong pd on pd.phieu_id = px.id
          where px.chi_nhanh_id = v_cn and px.trang_thai = 'hieu_luc' and px.ngay between v_tu and p_den group by px.id, px.ngay) x
    group by 1, 2
    union all
    select date_trunc('month', l.ngay)::date, 'CHUNG', -round(sum(l.so_luong * l.don_gia_von))
    from public.lo_kho l where l.chi_nhanh_id = v_cn and l.kiem_ke_id is not null and l.ngay between v_tu and p_den group by 1
    union all
    select coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date), 'CHUNG', sum(p.so_tien)
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = v_cn and p.loai = 'chi' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'chi_phi' and m.nhom = 'gia_von'
      and coalesce(p.ky_chi_phi, date_trunc('month', p.ngay)::date) between v_tu and p_den group by 1),
  gv2 as (select g.th, g.to_id, sum(g.gv) as gv from gv g group by 1, 2),
  khoa as (select th, to_id from dt union select th, to_id from gv2)
  select k.th, k.to_id, case when k.to_id = 'CHUNG' then 'Chung (giảm giá, dùng chung, hao hụt, thuê ngoài…)' else coalesce(t.ten, k.to_id) end,
    coalesce(dt.dthu, 0), coalesce(gv2.gv, 0), coalesce(dt.xe, 0), coalesce(dt.dvn, 0)
  from khoa k
  left join dt on dt.th = k.th and dt.to_id = k.to_id
  left join gv2 on gv2.th = k.th and gv2.to_id = k.to_id
  left join public.to_thuc_hien t on t.id = k.to_id
  order by k.th, (k.to_id = 'CHUNG'), k.to_id;
end $$;
revoke execute on function public.lai_gop_theo_to(date, date, text) from public, anon;
grant execute on function public.lai_gop_theo_to(date, date, text) to authenticated;
alter function public.chi_phi_theo_muc(date, date, text) set jit = off;

-- D4. Báo cáo cổ đông: chỉ chi nhánh người xem được xem (trước đây trả số chốt của mọi chi nhánh)
create or replace function public.bao_cao_co_dong() returns table (chi_nhanh_id text, thang date, so_lieu jsonb, chot_luc timestamptz)
language sql stable security definer set search_path = public as $$
  select ct.chi_nhanh_id, ct.thang, ct.so_lieu, ct.chot_luc from public.chot_thang ct
  where app.co_vai_tro('co_dong', 'giam_doc') and app.duoc_xem_chi_nhanh(ct.chi_nhanh_id) order by ct.thang desc
$$;

-- =====================================================================
-- A. TIỀN
-- =====================================================================
-- Đề nghị trả lại cọc / tiền dư đang chờ duyệt, chờ chi của một hồ sơ; số tiền hồ sơ đang giữ của khách
create or replace function app.dang_de_nghi_tra_coc(p_ho_so bigint) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(d.so_tien), 0) from public.de_nghi_chi d join public.muc_thu_chi m on m.id = d.muc_id
  where d.ho_so_id = p_ho_so and m.tinh_chat = 'tra_coc' and d.trang_thai in ('cho_duyet','da_duyet')
$$;
-- Hồ sơ đang giữ bao nhiêu tiền của khách: đã hủy → số khách đã trả (cọc); còn lại → phần khách trả dư (nợ âm)
create or replace function app.tien_dang_giu(p_ho_so bigint) returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(case when h.trang_thai = 'huy' then t.da_thu_khach else -t.con_no_khach end, 0)
  from public.ho_so h, app.tien_ho_so(h.id) t where h.id = p_ho_so
$$;
revoke execute on function app.dang_de_nghi_tra_coc(bigint), app.tien_dang_giu(bigint) from public, anon;

-- Cho giao diện: điền sẵn / giới hạn số tiền trả lại khách
create or replace function public.so_tien_tra_lai_khach(p_ho_so bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_cn text; v_giu numeric; v_cho numeric;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select chi_nhanh_id into v_cn from public.ho_so where id = p_ho_so;
  if v_cn is null then raise exception 'Không tìm thấy hồ sơ.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  v_giu := app.tien_dang_giu(p_ho_so); v_cho := app.dang_de_nghi_tra_coc(p_ho_so);
  return jsonb_build_object('dang_giu', v_giu, 'dang_de_nghi', v_cho, 'toi_da', greatest(v_giu - v_cho, 0));
end $$;
revoke execute on function public.so_tien_tra_lai_khach(bigint) from public, anon;
grant execute on function public.so_tien_tra_lai_khach(bigint) to authenticated;

-- A3. Đề nghị chi trả NCC đang chờ duyệt / chờ chi (vai kho không đọc được đề nghị của người khác → hàm có quyền)
create or replace function app.dang_de_nghi_tra_ncc()
returns table (nha_cung_cap_id bigint, chi_nhanh_id text, so_tien numeric)
language sql stable security definer set search_path = public rows 200 as $$
  select d.nha_cung_cap_id, d.chi_nhanh_id, sum(d.so_tien)
  from public.de_nghi_chi d join public.muc_thu_chi m on m.id = d.muc_id
  where d.nha_cung_cap_id is not null and m.tinh_chat = 'tra_ncc' and d.trang_thai in ('cho_duyet','da_duyet')
    and (select app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong'))
    and ((select app.co_vai_tro('giam_doc')) or d.chi_nhanh_id = (select app.chi_nhanh()))
  group by 1, 2
$$;
revoke execute on function app.dang_de_nghi_tra_ncc() from public, anon;
grant execute on function app.dang_de_nghi_tra_ncc() to authenticated;

create or replace view public.v_cong_no_ncc with (security_invoker = true) as
select n.id as nha_cung_cap_id, n.ten, c.chi_nhanh_id,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p
            where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai = 'da_khop'), 0) as da_nhap,
  coalesce((select sum(p.tong_tien) from public.phieu_nhap p
            where p.nha_cung_cap_id = n.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai in ('cho_khop','treo')), 0) as cho_khop,
  coalesce(t.da_tra, 0) as da_tra,
  coalesce(dn.so_tien, 0) as dang_de_nghi
from public.nha_cung_cap n
cross join (select id as chi_nhanh_id from public.chi_nhanh) c
left join app.da_tra_ncc() t on t.nha_cung_cap_id = n.id and t.chi_nhanh_id = c.chi_nhanh_id
left join app.dang_de_nghi_tra_ncc() dn on dn.nha_cung_cap_id = n.id and dn.chi_nhanh_id = c.chi_nhanh_id
where (select app.co_vai_tro('giam_doc','quan_ly','ke_toan','kho','co_dong'))
  and ((select app.co_vai_tro('giam_doc')) or c.chi_nhanh_id = (select app.chi_nhanh()));
grant select on public.v_cong_no_ncc to authenticated;
revoke all on public.v_cong_no_ncc from anon;

-- ---------------------------------------------------------------------
-- Lập đề nghị chi
--   F: ngày đề nghị = hôm nay (máy chủ) – ô Ngày ở máy khách dùng để lách hạn mức duyệt
--   A2: trả lại cọc / tiền dư không vượt số hồ sơ đang giữ trừ các đề nghị trả lại khác đang chờ
--   A3: trả NCC vượt số còn nợ (đã nhập − đã trả − đang đề nghị) → hỏi lại
--   F: hoa hồng GDV chưa ghi ở hồ sơ, hoặc vượt số đã ghi → hỏi lại
-- ---------------------------------------------------------------------
create or replace function public.lap_de_nghi_chi(p jsonb) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); m public.muc_thu_chi; v_id bigint;
  v_ngay date := current_date; v_ky date; v_noi_dung text; v_tien numeric := coalesce((p->>'so_tien')::numeric, 0);
  v_hoi boolean := p ? 'bo_qua_canh_bao' and not coalesce((p->>'bo_qua_canh_bao')::boolean, false);
  h public.ho_so; v_giu numeric; v_cho numeric; v_nhap numeric; v_tra numeric; v_ncc text;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'chi' then raise exception 'Chưa chọn mục chi.'; end if;
  if v_tien <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if nullif(trim(p->>'noi_dung'),'') is null then raise exception 'Ghi nội dung chi.'; end if;
  if (m.can_ho_so or m.tinh_chat in ('tra_hoa_hong','tra_coc')) and (p->>'ho_so_id') is null then
    raise exception 'Mục "%" phải gắn hồ sơ xe.', m.ten; end if;
  if m.tinh_chat = 'tra_hoa_hong' and (p->>'gdv_id') is null then raise exception 'Chọn giám định viên nhận hoa hồng.'; end if;
  if m.tinh_chat = 'tra_ncc' and (p->>'nha_cung_cap_id') is null then raise exception 'Chọn nhà cung cấp.'; end if;
  if m.tinh_chat = 'tra_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;
  if coalesce((p->>'vat_dau_vao')::numeric, 0) > v_tien then raise exception 'VAT đầu vào lớn hơn số tiền.'; end if;

  if m.tinh_chat = 'tra_coc' then
    h := app.lay_ho_so((p->>'ho_so_id')::bigint);          -- khóa hồ sơ: hai người cùng lập không vượt được
    v_giu := app.tien_dang_giu(h.id); v_cho := app.dang_de_nghi_tra_coc(h.id);
    if v_tien > v_giu - v_cho then
      raise exception 'Hồ sơ % đang giữ % đ của khách%: chỉ lập đề nghị trả lại tối đa % đ.', h.ma, app.vnd(v_giu),
        case when v_cho > 0 then format(' (đã có đề nghị trả lại %s đ chờ duyệt / chờ chi)', app.vnd(v_cho)) else '' end,
        app.vnd(greatest(v_giu - v_cho, 0));
    end if;
  end if;

  if m.tinh_chat = 'tra_ncc' and v_hoi then
    perform pg_advisory_xact_lock(hashtext('tra_ncc_' || v_cn || '_' || (p->>'nha_cung_cap_id')));
    select ten into v_ncc from public.nha_cung_cap where id = (p->>'nha_cung_cap_id')::bigint;
    select coalesce(sum(pn.tong_tien), 0) into v_nhap from public.phieu_nhap pn
    where pn.nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint and pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy';
    select coalesce(sum(pt.so_tien), 0) into v_tra from public.phieu_thu_chi pt join public.muc_thu_chi m2 on m2.id = pt.muc_id
    where pt.nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint and pt.chi_nhanh_id = v_cn and pt.loai = 'chi' and pt.trang_thai = 'hieu_luc' and m2.tinh_chat = 'tra_ncc';
    select coalesce(sum(d.so_tien), 0) into v_cho from public.de_nghi_chi d join public.muc_thu_chi m2 on m2.id = d.muc_id
    where d.nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint and d.chi_nhanh_id = v_cn and m2.tinh_chat = 'tra_ncc' and d.trang_thai in ('cho_duyet','da_duyet');
    if v_tien > v_nhap - v_tra - v_cho then
      raise exception 'CANH_BAO: %: hàng đã nhập % đ, đã trả % đ, đang đề nghị chi % đ → còn nợ % đ. Đề nghị % đ vượt số còn nợ (trả trước, hoặc đã có người lập rồi?). Vẫn lập?',
        coalesce(v_ncc, 'Nhà cung cấp'), app.vnd(v_nhap), app.vnd(v_tra), app.vnd(v_cho), app.vnd(v_nhap - v_tra - v_cho), app.vnd(v_tien);
    end if;
  end if;

  if m.tinh_chat = 'tra_hoa_hong' and v_hoi then
    select * into h from public.ho_so where id = (p->>'ho_so_id')::bigint;
    select coalesce(sum(d.so_tien), 0) into v_cho from public.de_nghi_chi d join public.muc_thu_chi m2 on m2.id = d.muc_id
    where d.ho_so_id = h.id and m2.tinh_chat = 'tra_hoa_hong' and d.trang_thai in ('cho_duyet','da_duyet','da_chi');
    if h.hoa_hong_gdv is null then
      raise exception 'CANH_BAO: Hồ sơ % chưa ghi hoa hồng GDV (kế toán nhập ở mục 8 của hồ sơ để tính vào lãi lỗ). Vẫn lập đề nghị chi?', h.ma;
    elsif v_tien + v_cho > h.hoa_hong_gdv then
      raise exception 'CANH_BAO: Hoa hồng ghi ở hồ sơ % là % đ, đã chi / đã đề nghị % đ – đề nghị này % đ làm vượt số đã ghi. Vẫn lập?',
        h.ma, app.vnd(h.hoa_hong_gdv), app.vnd(v_cho), app.vnd(v_tien);
    end if;
  end if;

  -- Kỳ chi phí: chỉ với khoản tính vào lãi lỗ; khác tháng lập thì ghi rõ vào nội dung để ai cũng thấy
  v_noi_dung := trim(p->>'noi_dung');
  if m.tinh_chat = 'chi_phi' then
    v_ky := app.kiem_ky_chi_phi(v_cn, coalesce((p->>'ky_chi_phi')::date, v_ngay));
    if v_ky <> date_trunc('month', v_ngay)::date then
      v_noi_dung := v_noi_dung || ' (chi phí tháng ' || to_char(v_ky, 'MM/YYYY') || ')'; end if;
  end if;

  insert into public.de_nghi_chi (chi_nhanh_id, ngay, nguoi_de_nghi, muc_id, so_tien, vat_dau_vao, noi_dung, nguoi_nhan,
    ho_so_id, nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, ky_chi_phi)
  values (v_cn, v_ngay, auth.uid(), m.id, v_tien,
    coalesce((p->>'vat_dau_vao')::numeric, 0), v_noi_dung, nullif(trim(p->>'nguoi_nhan'),''),
    (p->>'ho_so_id')::bigint, (p->>'nha_cung_cap_id')::bigint, (p->>'gdv_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, v_ky)
  returning id into v_id;
  return v_id;
end $$;

-- F: quản lý chung duyệt – các đề nghị cùng người, cùng mục trong 3 ngày (mỗi khoản dưới hạn mức) cộng lại vượt hạn mức
--    → nghi tách nhỏ, chuyển giám đốc duyệt (trước đây chỉ cảnh báo, đổi ô Ngày là lách được)
create or replace function public.duyet_de_nghi_chi(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; v_muc numeric := app.cai_dat_so('han_muc_chi_quan_ly', 2000000); v_so bigint; v_tong numeric;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị này đã được xử lý.'; end if;
  if r.nguoi_de_nghi = auth.uid() and not app.co_vai_tro('giam_doc') then raise exception 'Không được tự duyệt đề nghị do mình lập.'; end if;
  if r.so_tien > v_muc and not app.co_vai_tro('giam_doc') then
    raise exception 'Khoản trên % đ chỉ giám đốc được duyệt.', app.vnd(v_muc) using errcode = '42501';
  end if;
  if p_dong_y and not app.co_vai_tro('giam_doc') then
    select count(*), coalesce(sum(d.so_tien), 0) into v_so, v_tong from public.de_nghi_chi d
    where d.nguoi_de_nghi = r.nguoi_de_nghi and d.muc_id = r.muc_id and d.chi_nhanh_id = r.chi_nhanh_id
      and d.tao_luc between r.tao_luc - interval '3 days' and r.tao_luc + interval '3 days'
      and d.trang_thai not in ('huy','tu_choi') and d.so_tien <= v_muc;
    if v_so > 1 and v_tong > v_muc then
      raise exception 'Nghi tách nhỏ phiếu: % đề nghị cùng người, cùng mục trong 3 ngày cộng lại % đ (trên % đ) – chỉ giám đốc được duyệt.',
        v_so, app.vnd(v_tong), app.vnd(v_muc) using errcode = '42501';
    end if;
  end if;
  if not p_dong_y and nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.'; end if;
  update public.de_nghi_chi set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
end $$;

-- v_de_nghi_chi: nghi tách phiếu theo lúc lập (±3 ngày), bỏ đề nghị bị từ chối; tên đơn vị liên quan đọc qua view tên (D1)
-- (cột giữ nguyên – giao diện cũ đọc như trước)

-- ---------------------------------------------------------------------
-- Chi tiền
--   A2: trả lại cọc / tiền dư không vượt số hồ sơ đang giữ (đề nghị trùng bị chặn ở đây)
--   F: chi phí của tháng đã chốt (đề nghị lập trước khi chốt) → ghi vào tháng chi, ghi rõ ở nội dung
-- ---------------------------------------------------------------------
create or replace function public.chi_tien(p_de_nghi bigint, p_tai_khoan bigint, p_ngay date default current_date, p_chi_ho_boi bigint default null) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare r public.de_nghi_chi; m public.muc_thu_chi; dv public.don_vi_lien_quan; v_id bigint; v_thu bigint; v_muc_muon bigint;
  v_ky date; v_nd text; h public.ho_so; v_giu numeric;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.de_nghi_chi where id = p_de_nghi for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'da_duyet' then raise exception 'Đề nghị chưa được duyệt thì chưa chi được.'; end if;
  if p_ngay is null then p_ngay := current_date; end if;
  if p_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, p_ngay);
  perform app.kiem_tra_tai_khoan(p_tai_khoan, r.chi_nhanh_id);
  select * into m from public.muc_thu_chi where id = r.muc_id;
  v_ky := r.ky_chi_phi;
  v_nd := concat_ws(' – ', r.noi_dung, r.nguoi_nhan);
  if v_ky is not null and app.thang_da_chot(r.chi_nhanh_id, v_ky) then
    v_nd := v_nd || ' (chi phí tháng ' || to_char(v_ky, 'MM/YYYY') || ' đã chốt sổ – ghi vào tháng ' || to_char(p_ngay, 'MM/YYYY') || ')';
    v_ky := date_trunc('month', p_ngay)::date;
  end if;
  if m.tinh_chat = 'tra_coc' then
    h := app.lay_ho_so(r.ho_so_id);
    v_giu := app.tien_dang_giu(h.id);
    if r.so_tien > v_giu then
      raise exception 'Hồ sơ % chỉ còn giữ % đ của khách – không chi trả lại % đ được (có thể đã trả ở phiếu khác). Hủy đề nghị này, lập lại đúng số tiền.',
        h.ma, app.vnd(v_giu), app.vnd(r.so_tien);
    end if;
  end if;
  if p_chi_ho_boi is not null then
    select * into dv from public.don_vi_lien_quan where id = p_chi_ho_boi;
    if not found then raise exception 'Không tìm thấy người chi hộ (Danh mục → Đơn vị liên quan).'; end if;
    if m.tinh_chat = 'tra_noi_bo' then raise exception 'Khoản trả nội bộ / cho mượn không chi hộ được.'; end if;
    select id into v_muc_muon from public.muc_thu_chi where he_thong = 'muon_ca_nhan' and hoat_dong;
    if v_muc_muon is null then raise exception 'Chưa có mục thu "Công ty mượn tiền giám đốc / cổ đông" (Danh mục → Mục thu chi).'; end if;
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, vat_dau_vao, noi_dung,
    nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, de_nghi_chi_id, tao_boi, ky_chi_phi, chi_ho_boi)
  values (r.chi_nhanh_id, p_ngay, 'chi', p_tai_khoan, r.muc_id, r.so_tien, r.vat_dau_vao,
    v_nd || case when p_chi_ho_boi is null then '' else ' (' || dv.ten || ' chi hộ)' end,
    r.nha_cung_cap_id, r.gdv_id, r.don_vi_lien_quan_id, r.id, auth.uid(), v_ky, p_chi_ho_boi)
  returning id into v_id;

  if p_chi_ho_boi is not null then   -- tiền do người đó bỏ ra: công ty mượn họ đúng số tiền, cùng tài khoản để quỹ không đổi
    insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung, don_vi_lien_quan_id, tao_boi, phieu_doi_ung_id)
    values (r.chi_nhanh_id, p_ngay, 'thu', p_tai_khoan, v_muc_muon, r.so_tien,
      'Chi hộ – ' || dv.ten || ' trả thay: ' || r.noi_dung, p_chi_ho_boi, auth.uid(), v_id)
    returning id into v_thu;
    update public.phieu_thu_chi set phieu_doi_ung_id = v_thu where id = v_id;
  end if;

  if m.tinh_chat = 'tra_coc' then   -- trả lại cọc cho khách: giảm phần khách đã trả
    insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (v_id, r.ho_so_id, 'khach', r.so_tien);
    perform app.cap_nhat_dong(r.ho_so_id);
  end if;
  update public.de_nghi_chi set trang_thai = 'da_chi' where id = p_de_nghi;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- A5 + F: hủy phiếu – phiếu đi cặp (chi hộ; tiền bo tách từ phiếu khách trả) hủy theo, và tháng của phiếu kia
--   cũng phải còn mở (trước đây chỉ kiểm phiếu được bấm → phiếu chi kỳ đã chốt bị hủy qua phiếu thu đối ứng)
-- ---------------------------------------------------------------------
create or replace function public.huy_phieu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; x bigint; d public.phieu_thu_chi;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ky_chi_phi); end if;
  if r.trang_thai = 'huy' then raise exception 'Phiếu đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  if r.phieu_doi_ung_id is not null then
    select * into d from public.phieu_thu_chi where id = r.phieu_doi_ung_id for update;
    if found and d.trang_thai = 'hieu_luc' then
      perform app.yeu_cau_thang_mo(d.chi_nhanh_id, d.ngay);
      if d.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(d.chi_nhanh_id, d.ky_chi_phi); end if;
    end if;
  end if;
  update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) where id = p_id;
  if r.de_nghi_chi_id is not null then
    update public.de_nghi_chi set trang_thai = 'da_duyet' where id = r.de_nghi_chi_id;
  end if;
  for x in select distinct ho_so_id from public.phan_bo where phieu_id = p_id and ho_so_id is not null loop
    perform app.cap_nhat_dong(x);
  end loop;
  if d.id is not null and d.trang_thai = 'hieu_luc' then
    update public.phieu_thu_chi set trang_thai = 'huy',
      ly_do_huy = trim(p_ly_do) || case when coalesce(r.chi_ho_boi, d.chi_ho_boi) is not null then ' (hủy cùng phiếu chi hộ đối ứng)'
                                        else ' (hủy cùng phiếu đi cặp – khách trả / tiền bo)' end
    where id = d.id;
    if d.de_nghi_chi_id is not null then
      update public.de_nghi_chi set trang_thai = 'da_duyet' where id = d.de_nghi_chi_id;
    end if;
    for x in select distinct ho_so_id from public.phan_bo where phieu_id = d.id and ho_so_id is not null loop
      perform app.cap_nhat_dong(x);
    end loop;
  end if;
end $$;

-- F: phiếu tiền bo nối với phiếu khách trả bằng phieu_doi_ung_id (hủy một phiếu thì phiếu kia hủy theo)
create or replace function public.lap_phieu_thu(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  m public.muc_thu_chi; v_id bigint; v_tong numeric; v_bo numeric := coalesce((p->>'tien_bo')::numeric, 0);
  v_so_tien numeric := coalesce((p->>'so_tien')::numeric, 0); v_muc_bo bigint; v_bo_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'thu' then raise exception 'Chưa chọn mục thu.'; end if;
  if v_so_tien <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_bo < 0 or v_bo >= v_so_tien then raise exception 'Tiền bo không hợp lệ.'; end if;
  if v_bo > 0 then
    if m.tinh_chat <> 'thu_khach' then raise exception 'Tiền bo chỉ tách từ phiếu khách thanh toán sửa chữa.'; end if;
    select id into v_muc_bo from public.muc_thu_chi where loai = 'thu' and hoat_dong and (he_thong = 'tien_bo' or ten = 'Tiền bo của khách')
      order by he_thong nulls last limit 1;
    if v_muc_bo is null then raise exception 'Chưa có mục thu "Tiền bo của khách" (Danh mục → Mục thu chi).'; end if;
  end if;
  if m.tinh_chat = 'thu_bao_hiem' and (p->>'hang_bh_id') is null then raise exception 'Chọn hãng bảo hiểm chuyển tiền.'; end if;
  if m.tinh_chat = 'thu_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;

  select coalesce(sum((x->>'so_tien')::numeric), 0) into v_tong from jsonb_array_elements(coalesce(p->'phan_bo','[]'::jsonb)) x;
  if m.tinh_chat in ('thu_khach','thu_coc','thu_dich_vu_nhanh') and v_tong <> v_so_tien - v_bo then
    raise exception 'Tiền khách trả phải gắn đủ vào hồ sơ xe hoặc dịch vụ (đang gắn % / % đ).',
      app.vnd(v_tong), app.vnd(v_so_tien - v_bo);
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung,
    hang_bh_id, don_vi_lien_quan_id, tao_boi)
  values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, m.id, v_so_tien - v_bo, nullif(trim(p->>'noi_dung'),''),
    (p->>'hang_bh_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, auth.uid())
  returning id into v_id;
  -- Khách trả dư (cho_tra_du = true): gắn đủ vào xe dù vượt số còn nợ → hồ sơ ghi khách trả dư, trả lại sau
  perform app.phan_bo_phieu(v_id, p->'phan_bo', case when m.tinh_chat = 'thu_khach' and coalesce((p->>'cho_tra_du')::boolean, false) then 'thu_khach_du' else m.tinh_chat end);
  if v_bo > 0 then
    insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung, tao_boi, phieu_doi_ung_id)
    values (v_cn, v_ngay, 'thu', (p->>'tai_khoan_id')::bigint, v_muc_bo, v_bo,
      'Tiền bo của khách – ' || coalesce(nullif(trim(p->>'noi_dung'),''), 'phiếu thu #' || v_id), auth.uid(), v_id)
    returning id into v_bo_id;
    update public.phieu_thu_chi set phieu_doi_ung_id = v_bo_id where id = v_id;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- A4 + F: chia tiền phiếu thu vào hồ sơ / dịch vụ nhanh
--   dịch vụ nhanh: khóa lượt, không thu vào lượt đã hủy, không vượt số còn phải thu, đúng chi nhánh
--   bảo hiểm trả: hồ sơ phải là xe của đúng hãng đã trả phiếu
-- ---------------------------------------------------------------------
create or replace function app.phan_bo_phieu(p_phieu bigint, p_ds jsonb, p_tinh_chat text) returns void
language plpgsql security definer set search_path = public as $$
declare d jsonb; v_ho_so bigint; v_dvn bigint; v_nguoi text; v_tien numeric; t record; v_tong numeric; v_phieu public.phieu_thu_chi;
  v_ds_ho_so bigint[] := '{}'; h public.ho_so; dv public.dich_vu_nhanh; v_da numeric;
begin
  select * into v_phieu from public.phieu_thu_chi where id = p_phieu;
  for d in select * from jsonb_array_elements(coalesce(p_ds, '[]'::jsonb)) loop
    v_ho_so := (d->>'ho_so_id')::bigint; v_dvn := (d->>'dich_vu_nhanh_id')::bigint;
    v_tien := (d->>'so_tien')::numeric;
    if v_tien is null or v_tien <= 0 then raise exception 'Số tiền phân bổ phải lớn hơn 0.'; end if;
    if v_ho_so is not null then
      h := app.lay_ho_so(v_ho_so);
      if h.chi_nhanh_id <> v_phieu.chi_nhanh_id then raise exception 'Hồ sơ % không thuộc chi nhánh của phiếu.', h.ma; end if;
      v_nguoi := case p_tinh_chat when 'thu_bao_hiem' then 'bao_hiem' else 'khach' end;
      if p_tinh_chat = 'thu_bao_hiem' and v_phieu.hang_bh_id is not null and h.hang_bh_id is distinct from v_phieu.hang_bh_id then
        raise exception 'Xe % là hồ sơ của %, không phải của % – không chia tiền bảo hiểm này vào được.', h.ma,
          coalesce((select ten from public.hang_bao_hiem where id = h.hang_bh_id), 'khách ngoài bảo hiểm'),
          coalesce((select ten from public.hang_bao_hiem where id = v_phieu.hang_bh_id), 'hãng đã trả');
      end if;
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
      select * into dv from public.dich_vu_nhanh where id = v_dvn for update;
      if not found then raise exception 'Không tìm thấy lượt dịch vụ nhanh.'; end if;
      if dv.chi_nhanh_id <> v_phieu.chi_nhanh_id then raise exception 'Lượt dịch vụ nhanh không thuộc chi nhánh của phiếu.'; end if;
      if dv.trang_thai <> 'hieu_luc' then
        raise exception 'Lượt dịch vụ "%" ngày % đã hủy – không thu tiền vào được.', dv.dich_vu, to_char(dv.ngay, 'DD/MM/YYYY'); end if;
      select coalesce(sum(pb.so_tien), 0) into v_da from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
      where pb.dich_vu_nhanh_id = v_dvn and p.trang_thai = 'hieu_luc' and p.loai = 'thu';
      if v_tien > dv.so_tien - v_da then
        raise exception 'Thu % đ vượt số còn phải thu % đ của lượt dịch vụ "%"%.', app.vnd(v_tien), app.vnd(greatest(dv.so_tien - v_da, 0)),
          dv.dich_vu, coalesce(' – ' || public.bien_so_hien_thi(dv.bien_so), '');
      end if;
      insert into public.phan_bo (phieu_id, dich_vu_nhanh_id, nguoi_tra, so_tien) values (p_phieu, v_dvn, 'khach', v_tien);
    else
      raise exception 'Dòng phân bổ thiếu hồ sơ.';
    end if;
  end loop;
  select coalesce(sum(so_tien),0) into v_tong from public.phan_bo where phieu_id = p_phieu;
  if v_tong > v_phieu.so_tien then raise exception 'Tổng phân bổ lớn hơn số tiền của phiếu.'; end if;
  perform app.cap_nhat_dong(x) from unnest(v_ds_ho_so) x;
end $$;

-- A (tháng đã chốt): chuyển phần đã chia của một phiếu thu từ hồ sơ này sang hồ sơ khác (chia nhầm xe).
--   Tiền phiếu, ngày phiếu, doanh thu không đổi → làm được cả khi tháng của phiếu đã chốt; ghi nhật ký hai hồ sơ.
create or replace function public.chuyen_phan_bo(p_phieu bigint, p_tu_ho_so bigint, p_den_ho_so bigint, p_so_tien numeric, p_ly_do text) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare r public.phieu_thu_chi; m public.muc_thu_chi; a public.ho_so; b public.ho_so; v_nguoi text; v_da numeric; t record;
  pb record; v_con numeric;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_phieu for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.loai <> 'thu' or r.trang_thai <> 'hieu_luc' then raise exception 'Chỉ chuyển phần chia của phiếu thu còn hiệu lực.'; end if;
  select * into m from public.muc_thu_chi where id = r.muc_id;
  if m.tinh_chat not in ('thu_bao_hiem','thu_khach','thu_coc') then raise exception 'Phiếu này không chia vào xe.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do (ví dụ: chia nhầm xe).'; end if;
  if p_so_tien is null or p_so_tien <= 0 then raise exception 'Số tiền chuyển phải lớn hơn 0.'; end if;
  if p_tu_ho_so is null or p_den_ho_so is null or p_tu_ho_so = p_den_ho_so then raise exception 'Chọn xe nhận khác xe chuyển đi.'; end if;
  -- khóa hai hồ sơ theo thứ tự id: hai người làm cùng lúc không chờ nhau mãi
  if p_tu_ho_so < p_den_ho_so then a := app.lay_ho_so(p_tu_ho_so); b := app.lay_ho_so(p_den_ho_so);
  else b := app.lay_ho_so(p_den_ho_so); a := app.lay_ho_so(p_tu_ho_so); end if;
  v_nguoi := case when m.tinh_chat = 'thu_bao_hiem' then 'bao_hiem' else 'khach' end;
  select coalesce(sum(so_tien), 0) into v_da from public.phan_bo where phieu_id = p_phieu and ho_so_id = a.id and nguoi_tra = v_nguoi;
  if p_so_tien > v_da then raise exception 'Phiếu chỉ chia % đ vào hồ sơ % – không chuyển % đ được.', app.vnd(v_da), a.ma, app.vnd(p_so_tien); end if;
  if b.trang_thai = 'huy' then raise exception 'Hồ sơ % đã hủy.', b.ma; end if;
  if b.chi_nhanh_id <> r.chi_nhanh_id then raise exception 'Hồ sơ % không thuộc chi nhánh của phiếu.', b.ma; end if;
  if v_nguoi = 'bao_hiem' and b.hang_bh_id is distinct from r.hang_bh_id then
    raise exception 'Hồ sơ % không phải xe của hãng bảo hiểm đã trả phiếu này.', b.ma; end if;
  select * into t from app.tien_ho_so(b.id);
  if v_nguoi = 'bao_hiem' and p_so_tien > t.con_no_bh then
    raise exception 'Hồ sơ % chỉ còn bảo hiểm nợ % đ.', b.ma, app.vnd(greatest(t.con_no_bh, 0)); end if;
  if m.tinh_chat = 'thu_khach' and p_so_tien > t.con_no_khach then
    raise exception 'Hồ sơ % chỉ còn khách nợ % đ.', b.ma, app.vnd(greatest(t.con_no_khach, 0)); end if;
  v_con := p_so_tien;
  for pb in select id, so_tien from public.phan_bo where phieu_id = p_phieu and ho_so_id = a.id and nguoi_tra = v_nguoi order by id desc for update loop
    exit when v_con <= 0;
    if pb.so_tien <= v_con then delete from public.phan_bo where id = pb.id; v_con := v_con - pb.so_tien;
    else update public.phan_bo set so_tien = so_tien - v_con where id = pb.id; v_con := 0; end if;
  end loop;
  insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (p_phieu, b.id, v_nguoi, p_so_tien);
  perform app.ghi_nhat_ky(a.id, a.trang_thai, a.trang_thai, format('Chuyển %s đ của phiếu thu ngày %s sang hồ sơ %s: %s',
    app.vnd(p_so_tien), to_char(r.ngay, 'DD/MM/YYYY'), b.ma, trim(p_ly_do)));
  perform app.ghi_nhat_ky(b.id, b.trang_thai, b.trang_thai, format('Nhận %s đ của phiếu thu ngày %s chuyển từ hồ sơ %s: %s',
    app.vnd(p_so_tien), to_char(r.ngay, 'DD/MM/YYYY'), a.ma, trim(p_ly_do)));
  perform app.cap_nhat_dong(a.id);
  perform app.cap_nhat_dong(b.id);
end $$;
revoke execute on function public.chuyen_phan_bo(bigint, bigint, bigint, numeric, text) from public, anon;
grant execute on function public.chuyen_phan_bo(bigint, bigint, bigint, numeric, text) to authenticated;

-- F: chuyển quỹ – hai tài khoản phải khác nhau (trước đây báo lỗi tiếng Anh), không ghi ngày tương lai
create or replace function public.lap_phieu_chuyen(p jsonb) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  perform app.yeu_cau_chi_nhanh(v_cn);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_id')::bigint, v_cn);
  perform app.kiem_tra_tai_khoan((p->>'tai_khoan_den_id')::bigint, v_cn);
  if (p->>'tai_khoan_id')::bigint = (p->>'tai_khoan_den_id')::bigint then
    raise exception 'Tài khoản chuyển đi và tài khoản nhận phải khác nhau.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, tai_khoan_den_id, so_tien, noi_dung, tao_boi)
  values (v_cn, v_ngay, 'chuyen', (p->>'tai_khoan_id')::bigint, (p->>'tai_khoan_den_id')::bigint,
          (p->>'so_tien')::numeric, nullif(trim(p->>'noi_dung'),''), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- A6. Hủy hồ sơ: khấu trừ – giảm trừ, giảm giá về 0 (trước đây còn nguyên → che tiền cọc, báo khách còn nợ);
--     tháng của các lần giảm giá cũng phải còn mở
-- ---------------------------------------------------------------------
create or replace function public.huy_ho_so(p_ho_so bigint, p_ly_do text, p_bo_qua_canh_bao boolean default null) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_ngay date; t record;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('tiep_nhan','bao_gia','da_duyet') then
    raise exception 'Xe đã vào sửa thì không hủy hồ sơ được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.da_thu_khach > 0 and p_bo_qua_canh_bao is not null and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Khách đã đặt cọc % đ cho hồ sơ này. Hủy xong nhớ lập đề nghị chi "Trả lại cọc cho khách" chọn xe này (Việc hôm nay sẽ nhắc đến khi trả xong). Vẫn hủy?',
      app.vnd(t.da_thu_khach);
  end if;
  for v_ngay in select distinct ngay_duyet from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'duyet'
                union select distinct ngay from public.giam_gia_lan where ho_so_id = p_ho_so loop
    perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_ngay);
  end loop;
  update public.hang_muc set trang_thai = 'tu_choi' where ho_so_id = p_ho_so and trang_thai in ('cho_duyet','duyet');
  update public.ho_so set ly_do_huy = trim(p_ly_do), khau_tru_giam_tru = 0, giam_gia = 0 where id = p_ho_so;
  perform app.doi_trang_thai(p_ho_so, 'huy', 'Hủy: ' || trim(p_ly_do));
end $$;

-- ---------------------------------------------------------------------
-- B7 / A: hoa hồng GDV – tháng duyệt giá đã chốt thì ghi vào tháng đang mở (cột hoa_hong_ky);
--   sửa số đã ghi chỉ khi tháng đã tính còn mở
-- ---------------------------------------------------------------------
create or replace function public.nhap_hoa_hong_gdv(p_ho_so bigint, p_so_tien numeric, p_ghi_chu text default null,
  p_bo_qua_canh_bao boolean default false) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; t record; v_tl numeric := app.cai_dat_so('hoa_hong_canh_bao_ty_le', 0.15); v_dau date; v_ky date;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.gdv_id is null then raise exception 'Hồ sơ không có giám định viên.'; end if;
  if p_so_tien is null or p_so_tien < 0 then raise exception 'Số tiền hoa hồng không hợp lệ.'; end if;
  select min(m.ngay_duyet) into v_dau from public.hang_muc m
   where m.ho_so_id = p_ho_so and m.trang_thai in ('duyet','dang_lam','xong');
  -- số đã ghi trước đó tính vào tháng nào thì tháng đó phải còn mở mới sửa được
  if h.hoa_hong_gdv is not null then perform app.yeu_cau_thang_mo(h.chi_nhanh_id, coalesce(h.hoa_hong_ky, v_dau)); end if;
  if v_dau is not null and app.thang_da_chot(h.chi_nhanh_id, v_dau) then
    v_ky := date_trunc('month', current_date)::date;
    perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.bh_duyet > 0 and p_so_tien > t.bh_duyet * v_tl and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Hoa hồng % đ lớn hơn % giá duyệt bảo hiểm. Kiểm tra lại có gõ thừa số 0 không?',
      app.vnd(p_so_tien), round(v_tl * 100)::text || '%';
  end if;
  update public.ho_so set hoa_hong_gdv = p_so_tien, hoa_hong_ghi_chu = nullif(trim(p_ghi_chu),''), hoa_hong_ky = v_ky where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Nhập hoa hồng GDV ' || p_so_tien || ' đ'
    || case when v_ky is not null then ' – tính vào tháng ' || to_char(v_ky, 'MM/YYYY') || ' (tháng duyệt giá ' || to_char(v_dau, 'MM/YYYY') || ' đã chốt sổ)' else '' end);
end $$;

-- E12: duyệt giảm giá – số nhập vẫn là TỔNG giảm giá; phần chênh so với tổng cũ ghi thành một lần vào hôm nay
create or replace function public.duyet_giam_gia(p_ho_so bigint, p_so_tien numeric, p_ly_do text) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; t record; v_them numeric;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai in ('dong','huy') then raise exception 'Hồ sơ đã đóng.'; end if;
  if p_so_tien is null or p_so_tien < 0 then raise exception 'Số tiền giảm giá không hợp lệ.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do giảm giá.'; end if;
  v_them := p_so_tien - h.giam_gia;
  if v_them = 0 then return; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  -- Tổng giảm giá không vượt phần khách phải trả trước giảm giá (khách duyệt + khấu trừ – giảm trừ)
  select * into t from app.tien_ho_so(p_ho_so);
  if p_so_tien > t.phai_thu_khach + h.giam_gia then
    raise exception 'Giảm giá % đ lớn hơn phần khách phải trả (% đ).', app.vnd(p_so_tien), app.vnd(t.phai_thu_khach + h.giam_gia);
  end if;
  insert into public.giam_gia_lan (ho_so_id, ngay, so_tien, ly_do, duyet_boi) values (p_ho_so, current_date, v_them, trim(p_ly_do), auth.uid());
  update public.ho_so set giam_gia = p_so_tien, giam_gia_ngay = current_date, giam_gia_duyet_boi = auth.uid() where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
    case when h.giam_gia = 0 then 'Duyệt giảm giá ' || p_so_tien || ' đ'
         else 'Đổi tổng giảm giá ' || h.giam_gia || ' → ' || p_so_tien || ' đ (' || case when v_them > 0 then 'giảm thêm ' else 'bớt ' end || abs(v_them) || ' đ)' end
    || ': ' || trim(p_ly_do));
  perform app.cap_nhat_dong(p_ho_so);   -- đã giao xe, giảm xong hết nợ → tự đóng
end $$;

-- =====================================================================
-- D. PHÂN QUYỀN
-- =====================================================================
-- D1. Đơn vị liên quan: nợ đầu kỳ (công ty nợ giám đốc / cổ đông) chỉ giám đốc, quản lý chung, kế toán, cổ đông đọc được.
--     Nhân viên khác cần tên (chọn đơn vị, xem tên trên đề nghị) đọc qua view chỉ có tên.
alter policy "doc" on public.don_vi_lien_quan using ((select app.co_vai_tro('giam_doc','quan_ly','ke_toan','co_dong')));
create or replace view public.v_don_vi_lien_quan as
select dv.id, dv.ten, dv.loai, dv.hoat_dong from public.don_vi_lien_quan dv
where (select app.xem_nhu_nhan_vien()) or (select app.co_vai_tro('truong_nhom'));
grant select on public.v_don_vi_lien_quan to authenticated;
revoke all on public.v_don_vi_lien_quan from anon;

-- D2. Kho lưu trữ: trưởng nhóm chỉ đọc ảnh thiết bị, đồ nghề (thư mục tai-san) – không đọc ảnh hóa đơn NCC (giá nhập),
--     giấy tờ của khách
alter policy "ho-so-xe doc" on storage.objects using (
  bucket_id = 'ho-so-xe'::text
  and ((select app.xem_nhu_nhan_vien())
       or ((select app.co_vai_tro('truong_nhom')) and (storage.foldername(name))[2] = 'tai-san')));

-- D3. Phiếu đề xuất vật tư: trưởng nhóm chỉ đọc phiếu của tổ mình (hoặc mình lập) – cả bảng gốc, không chỉ view
alter policy "doc" on public.de_xuat_vat_tu using (
  ((select app.xem_nhu_nhan_vien())
   or ((select app.co_vai_tro('truong_nhom')) and (to_id = (select app.to_cua_toi()) or nguoi_lap = (select auth.uid()))))
  and app.duoc_xem_chi_nhanh(chi_nhanh_id));
alter policy "doc" on public.de_xuat_dong using ((exists (select 1 from public.de_xuat_vat_tu d
  where d.id = de_xuat_dong.de_xuat_id
    and ((select app.xem_nhu_nhan_vien())
         or ((select app.co_vai_tro('truong_nhom')) and (d.to_id = (select app.to_cua_toi()) or d.nguoi_lap = (select auth.uid()))))
    and app.duoc_xem_chi_nhanh(d.chi_nhanh_id))));

-- Quyền thừa: anon trên view nợ nội bộ (đã revoke ở trên); ghi thẳng nhật ký xuất file
revoke insert, update, delete, truncate on public.nhat_ky_xuat_file from authenticated;

-- =====================================================================
-- VIEW dùng ở giao diện (chỉ thêm cột cuối)
-- =====================================================================
-- v_ho_so: thêm tháng tính hoa hồng (khi tháng duyệt giá đã chốt lúc nhập)
create or replace view public.v_ho_so with (security_invoker = true) as
select
  h.id, h.ma, h.chi_nhanh_id, h.loai, h.ho_so_goc_id, h.trang_thai, h.ngay_vao, h.hen_giao, h.giao_luc,
  h.nguon_tt, h.tinh_trang_xe, h.tu_van, h.han_bao_hiem, h.khau_tru_giam_tru, h.giam_gia,
  h.so_hd_bao_hiem, h.so_hd_khach, h.cam_nhan_khach, h.gui_hs_ngay, h.hoa_hong_gdv, h.hoa_hong_ghi_chu,
  h.cham_soc_luc, h.cham_soc_ket_qua, h.hen_bao_duong, h.ly_do_huy, h.cho_giao_no_boi, h.tu_excel,
  h.xe_id, h.khach_hang_id, h.hang_bh_id, h.gdv_id,
  x.bien_so, public.bien_so_hien_thi(x.bien_so) as bien_so_hien_thi, x.dong_xe_id, x.mau,
  concat_ws(' ', hx.ten, dx.ten) as xe, k.ten as ten_khach, k.dien_thoai, b.ten as hang_bh,
  coalesce(h.gdv_ten_tam, g.ten) as gdv, coalesce(g.la_cho_them, false) as gdv_cho_them,
  d.ngay_duyet_dau,
  coalesce(d.co_dong_cho_duyet, false) as co_dong_cho_duyet,
  coalesce(ps.co_phat_sinh, false) as co_phat_sinh,
  coalesce(d.bh, 0) as bh_duyet,
  coalesce(d.kh, 0) as khach_duyet,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru as phai_thu_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia as phai_thu_khach,
  coalesce(t.bh, 0) as da_thu_bh,
  coalesce(t.kh, 0) as da_thu_khach,
  coalesce(d.bh, 0) - h.khau_tru_giam_tru - coalesce(t.bh, 0) as con_no_bh,
  coalesce(d.kh, 0) + h.khau_tru_giam_tru - h.giam_gia - coalesce(t.kh, 0) as con_no_khach,
  h.han_bh_than_vo,
  h.so_km,
  h.nguoi_tiep_theo,
  h.giao_viec_luc,
  h.hoa_hong_ky
from public.ho_so h
join public.xe x on x.id = h.xe_id
join public.khach_hang k on k.id = h.khach_hang_id
left join public.dong_xe dx on dx.id = x.dong_xe_id
left join public.hang_xe hx on hx.id = dx.hang_xe_id
left join public.hang_bao_hiem b on b.id = h.hang_bh_id
left join public.giam_dinh_vien g on g.id = h.gdv_id
left join app.duyet_theo_ho_so() d on d.ho_so_id = h.id
left join (select p.ho_so_id, bool_or(not p.da_xu_ly) as co_phat_sinh from public.phat_sinh p group by p.ho_so_id) ps on ps.ho_so_id = h.id
left join app.da_thu_theo_ho_so() t on t.ho_so_id = h.id;
grant select on public.v_ho_so to authenticated;
revoke all on public.v_ho_so from anon;

-- v_dich_vu_nhanh: thêm con_thu (còn phải thu) để lọc lượt chưa thu ở máy chủ (trước đây lấy 200 lượt rồi mới lọc)
create or replace view public.v_dich_vu_nhanh with (security_invoker = true) as
select d.id, d.chi_nhanh_id, d.ngay, d.bien_so, d.dich_vu, d.nguoi_lam, d.so_tien, d.xuat_hd, d.trang_thai, d.tao_boi, d.tao_luc,
  public.bien_so_hien_thi(d.bien_so) as bien_so_hien_thi,
  coalesce(t.da_thu, 0) as da_thu,
  d.xe_id, d.khach_hang_id, d.so_km, k.ten as ten_khach, k.dien_thoai,
  d.ly_do_huy,
  case when d.trang_thai = 'hieu_luc' then d.so_tien - coalesce(t.da_thu, 0) else 0 end as con_thu
from public.dich_vu_nhanh d
left join public.khach_hang k on k.id = d.khach_hang_id
left join lateral (select sum(pb.so_tien) as da_thu from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
                   where pb.dich_vu_nhanh_id = d.id and p.trang_thai = 'hieu_luc') t on true;
grant select on public.v_dich_vu_nhanh to authenticated;
revoke all on public.v_dich_vu_nhanh from anon;

-- v_phieu_thu_chi: thêm con_chua_chia (phiếu thu bảo hiểm còn bao nhiêu chưa chia vào xe – lọc ở máy chủ, mọi tháng)
create or replace view public.v_phieu_thu_chi with (security_invoker = true) as
select p.id, p.chi_nhanh_id, p.ngay, p.loai, p.so_tien, p.vat_dau_vao, p.noi_dung, p.trang_thai, p.ly_do_huy, p.tao_luc,
  p.tai_khoan_id, tk.ten as tai_khoan, p.tai_khoan_den_id, tk2.ten as tai_khoan_den,
  p.muc_id, m.ten as muc, m.tinh_chat, m.nhom,
  b.ten as hang_bh, ncc.ten as nha_cung_cap, g.ten as gdv, dv.ten as don_vi_lien_quan,
  p.de_nghi_chi_id, nv.ho_ten as nguoi_lap,
  coalesce(pb.da, 0) as da_phan_bo,
  (select string_agg(h.ma, ', ') from public.phan_bo pb2 join public.ho_so h on h.id = pb2.ho_so_id where pb2.phieu_id = p.id) as ho_so,
  case when p.loai = 'thu' and p.trang_thai = 'hieu_luc' and m.tinh_chat = 'thu_bao_hiem' then p.so_tien - coalesce(pb.da, 0) else 0 end as con_chua_chia,
  p.hang_bh_id
from public.phieu_thu_chi p
join public.tai_khoan_quy tk on tk.id = p.tai_khoan_id
left join public.tai_khoan_quy tk2 on tk2.id = p.tai_khoan_den_id
left join public.muc_thu_chi m on m.id = p.muc_id
left join public.hang_bao_hiem b on b.id = p.hang_bh_id
left join public.nha_cung_cap ncc on ncc.id = p.nha_cung_cap_id
left join public.giam_dinh_vien g on g.id = p.gdv_id
left join public.v_don_vi_lien_quan dv on dv.id = p.don_vi_lien_quan_id
left join public.nhan_vien nv on nv.id = p.tao_boi
left join lateral (select sum(x.so_tien) as da from public.phan_bo x where x.phieu_id = p.id) pb on true;
grant select on public.v_phieu_thu_chi to authenticated;
revoke all on public.v_phieu_thu_chi from anon;

-- v_de_nghi_chi: nghi tách phiếu theo lúc lập (±3 ngày, trước đây theo ô Ngày sửa được), bỏ đề nghị bị từ chối;
--   tên đơn vị liên quan qua view tên (D1). Cột cũ giữ nguyên, thêm kỳ chi phí ở cuối.
create or replace view public.v_de_nghi_chi with (security_invoker = true) as
select d.id, d.chi_nhanh_id, d.ngay, d.nguoi_de_nghi, d.muc_id, d.so_tien, d.vat_dau_vao, d.noi_dung, d.nguoi_nhan, d.ho_so_id,
  d.nha_cung_cap_id, d.gdv_id, d.don_vi_lien_quan_id, d.trang_thai, d.duyet_boi, d.duyet_luc, d.ly_do_tu_choi, d.tao_luc,
  m.ten as muc, m.tinh_chat, nv.ho_ten as nguoi_de_nghi_ten, nd.ho_ten as nguoi_duyet_ten,
  h.ma as ho_so_ma, ncc.ten as nha_cung_cap, g.ten as gdv, dv.ten as don_vi_lien_quan,
  d.so_tien > app.cai_dat_so('han_muc_chi_quan_ly', 2000000) as can_giam_doc,
  (select count(*) > 1 and sum(d2.so_tien) > app.cai_dat_so('han_muc_chi_quan_ly', 2000000)
     from public.de_nghi_chi d2
     where d2.nguoi_de_nghi = d.nguoi_de_nghi and d2.muc_id = d.muc_id and d2.chi_nhanh_id = d.chi_nhanh_id
       and d2.tao_luc between d.tao_luc - interval '3 days' and d.tao_luc + interval '3 days'
       and d2.trang_thai not in ('huy','tu_choi') and d2.so_tien <= app.cai_dat_so('han_muc_chi_quan_ly', 2000000)) as nghi_tach_phieu,
  d.ky_chi_phi
from public.de_nghi_chi d
join public.muc_thu_chi m on m.id = d.muc_id
left join public.nhan_vien nv on nv.id = d.nguoi_de_nghi
left join public.nhan_vien nd on nd.id = d.duyet_boi
left join public.ho_so h on h.id = d.ho_so_id
left join public.nha_cung_cap ncc on ncc.id = d.nha_cung_cap_id
left join public.giam_dinh_vien g on g.id = d.gdv_id
left join public.v_don_vi_lien_quan dv on dv.id = d.don_vi_lien_quan_id;
grant select on public.v_de_nghi_chi to authenticated;
revoke all on public.v_de_nghi_chi from anon;

-- ---------------------------------------------------------------------
-- v_canh_bao (Việc cần xử lý)
--   chua_gui_ho_so: chỉ xe bảo hiểm còn phần bảo hiểm phải trả (BH 0 đ – khách chi trả toàn bộ – không có bước hồ sơ BH)
--   coc_treo: hồ sơ hủy theo số khách đã trả (khấu trừ cũ không che cọc); hủy mà đã trả lại thừa → báo
--   bh_tra_du: bảo hiểm trả nhiều hơn phần bảo hiểm phải trả
--   thu_chua_phan_bo: ghi đủ ngày/tháng/năm (giao diện mở danh sách phiếu chưa chia của mọi tháng)
--   nhap_ngoai_de_nghi (giám đốc): phiếu nhập từ ngưỡng 3 báo giá không theo đề nghị mua, 7 ngày gần nhất
-- ---------------------------------------------------------------------
create or replace view public.v_canh_bao with (security_invoker = true) as
with tat as (select * from public.v_ho_so),           -- đọc hồ sơ một lần cho mọi nhánh
hs as (select * from tat where trang_thai not in ('huy')),
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
where hs.nguon_tt <> 'khach' and hs.trang_thai = 'da_giao' and not hs.tu_excel and hs.loai <> 'bao_hanh' and hs.phai_thu_bh > 0
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
select 'khach_tra_du', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  hs.ten_khach || ' trả dư ' || app.vnd(-hs.con_no_khach) || ' đ – lập đề nghị chi "Trả lại cọc cho khách" hoặc ghi tiền bo', hs.chi_nhanh_id
from hs where hs.giao_luc is not null and hs.con_no_khach < 0 and not hs.tu_excel
union all
select 'bh_tra_du', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  coalesce(hs.hang_bh, 'Bảo hiểm') || ' đã trả dư ' || app.vnd(-hs.con_no_bh) || ' đ so với phần bảo hiểm chi trả – kiểm tra chia công nợ hoặc chia phiếu bảo hiểm', hs.chi_nhanh_id
from hs where hs.con_no_bh < 0 and not hs.tu_excel
union all
-- 041/043: hồ sơ đã HỦY còn giữ tiền khách đã trả (cọc) → nhắc trả lại; đã trả lại nhiều hơn số thu → báo kiểm tra
select case when c.da_thu_khach > 0 then 'coc_treo' else 'tra_lai_thua' end, 'cao', c.id, c.ma, c.bien_so_hien_thi,
  case when c.da_thu_khach > 0
       then 'Hồ sơ đã hủy còn giữ ' || app.vnd(c.da_thu_khach) || ' đ tiền cọc của ' || c.ten_khach || ' – lập đề nghị chi "Trả lại cọc cho khách"'
       else 'Hồ sơ đã hủy đã trả lại khách nhiều hơn số đã thu ' || app.vnd(-c.da_thu_khach) || ' đ – kiểm tra phiếu chi trả lại' end,
  c.chi_nhanh_id
from tat c where c.trang_thai = 'huy' and c.da_thu_khach <> 0 and not c.tu_excel
union all
select 'thieu_hoa_hong', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Chưa nhập hoa hồng cho GDV ' || coalesce(hs.gdv, ''), hs.chi_nhanh_id
from hs where hs.gdv_id is not null and hs.giao_luc is not null and hs.hoa_hong_gdv is null and not hs.tu_excel
union all
select 'gdv_cho_them', 'thap', hs.id, hs.ma, hs.bien_so_hien_thi,
  'GDV "' || coalesce(hs.gdv, '') || '" chưa có trong danh sách – kế toán thêm vào Cài đặt rồi gắn lại', hs.chi_nhanh_id
from hs where hs.gdv_cho_them
union all
select 'thieu_gdv', 'vua', hs.id, hs.ma, hs.bien_so_hien_thi,
  'Xe bảo hiểm chưa có giám định viên – ghi GDV (Sửa ở Thông tin xe và khách) trước khi nhập kết quả duyệt giá', hs.chi_nhanh_id
from hs where hs.nguon_tt <> 'khach' and hs.gdv_id is null and not hs.tu_excel and hs.loai <> 'bao_hanh'
  and hs.trang_thai in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_kcs','dat_kcs')
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
  'Phiếu thu ' || to_char(p.ngay, 'DD/MM/YYYY') || ' của ' || coalesce(p.hang_bh, p.muc) || ' còn '
    || app.vnd(p.con_chua_chia) || ' đ chưa chia vào xe', p.chi_nhanh_id
from public.v_phieu_thu_chi p
where p.con_chua_chia > 0
union all
select 'de_nghi_cho_duyet', case when d.nghi_tach_phieu then 'cao' else 'vua' end, d.ho_so_id, d.ho_so_ma, null,
  'Đề nghị chi ' || app.vnd(d.so_tien) || ' đ – ' || d.noi_dung || ' (' || coalesce(d.nguoi_de_nghi_ten,'') || ')'
    || case when d.can_giam_doc then ' – cần giám đốc duyệt' else '' end
    || case when d.nghi_tach_phieu then ' – nghi tách nhỏ phiếu, giám đốc duyệt' else '' end,
  d.chi_nhanh_id
from public.v_de_nghi_chi d
where d.trang_thai = 'cho_duyet' and (select app.co_vai_tro('giam_doc','quan_ly'))
  and d.nguoi_de_nghi <> (select auth.uid()) and (not d.can_giam_doc or (select app.co_vai_tro('giam_doc')))
union all
select 'nhap_ngoai_de_nghi', 'vua', null, pn.ma, null,
  'Phiếu nhập ' || pn.ma || ' ' || app.vnd(pn.tong_tien) || ' đ – ' || coalesce(n.ten, 'nhà cung cấp') || ' không theo đề nghị mua đã duyệt (từ '
    || app.vnd(app.cai_dat_so('nguong_3_bao_gia', 5000000)) || ' đ cần 3 báo giá) – giám đốc kiểm tra', pn.chi_nhanh_id
from public.phieu_nhap pn left join public.nha_cung_cap n on n.id = pn.nha_cung_cap_id
where (select app.co_vai_tro('giam_doc')) and pn.de_nghi_mua_id is null and pn.trang_thai <> 'huy'
  and pn.tong_tien >= app.cai_dat_so('nguong_3_bao_gia', 5000000) and pn.tao_luc > now() - interval '7 days';
grant select on public.v_canh_bao to authenticated;
revoke all on public.v_canh_bao from anon;

-- =====================================================================
-- B. HỒ SƠ XE
-- =====================================================================
-- B1. Sửa thông tin khách trên một hồ sơ không ghi đè khách dùng chung:
--   - SĐT mới đã là của khách khác → gắn hồ sơ (và xe) sang khách đó
--   - khách cũ còn hồ sơ / xe / dịch vụ khác → tạo khách mới cho hồ sơ này
--   - chỉ khách riêng của hồ sơ này mới sửa tại chỗ; chỉ đổi tên (cùng SĐT) thì sửa tên khách đó
create or replace function public.sua_thong_tin_ho_so(p_id bigint, p jsonb) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; v_dt text; v_gdv public.giam_dinh_vien; k public.khach_hang; v_kh bigint; v_ten text; v_chung boolean;
  v_ghi text := '';
begin
  perform app.yeu_cau('cvdv','ke_toan','quan_ly','giam_doc');
  h := app.lay_ho_so(p_id);
  if p ? 'so_km' and length(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g')) > 7 then
    raise exception 'Số km (ODD) không đúng.'; end if;
  if p ? 'ten_khach' or p ? 'dien_thoai' then
    select * into k from public.khach_hang where id = h.khach_hang_id for update;
    v_ten := coalesce(nullif(trim(p->>'ten_khach'),''), k.ten);
    v_dt := case when p ? 'dien_thoai' then regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g') else k.dien_thoai end;
    if p ? 'dien_thoai' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số.'; end if;
    if v_dt is distinct from k.dien_thoai then
      perform pg_advisory_xact_lock(hashtext('khach_' || v_dt));
      select id into v_kh from public.khach_hang where dien_thoai = v_dt;
      v_chung := exists (select 1 from public.ho_so where khach_hang_id = k.id and id <> h.id)
              or exists (select 1 from public.xe where khach_hang_id = k.id and id <> h.xe_id)
              or exists (select 1 from public.dich_vu_nhanh where khach_hang_id = k.id);
      if v_kh is not null then
        if nullif(trim(p->>'ten_khach'),'') is not null then update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh; end if;
        v_ghi := format('; gắn sang khách có sẵn SĐT %s', v_dt);
      elsif v_chung then
        insert into public.khach_hang (ten, dien_thoai) values (v_ten, v_dt) returning id into v_kh;
        v_ghi := format('; tạo khách mới %s – %s (khách cũ %s – %s còn hồ sơ / xe khác, giữ nguyên)', v_ten, v_dt, k.ten, coalesce(k.dien_thoai, ''));
      else
        update public.khach_hang set ten = v_ten, dien_thoai = v_dt where id = k.id;
        v_kh := k.id;
      end if;
      if v_kh <> k.id then
        update public.ho_so set khach_hang_id = v_kh where id = h.id;
        update public.xe set khach_hang_id = v_kh where id = h.xe_id;
      end if;
    elsif v_ten is distinct from k.ten then
      update public.khach_hang set ten = v_ten where id = k.id;    -- cùng SĐT = cùng người: sửa tên chung
    end if;
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
    so_km           = case when p ? 'so_km' then nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '')::int else so_km end,
    cap_nhat_luc    = now()
  where id = p_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, p_id;
  end if;
  update public.xe set
    dong_xe_id   = case when p ? 'dong_xe_id' then (p->>'dong_xe_id')::bigint else dong_xe_id end,
    mau          = case when p ? 'mau' then nullif(trim(p->>'mau'),'') else mau end,
    han_bao_hiem = case when p ? 'han_bao_hiem' then (p->>'han_bao_hiem')::date else han_bao_hiem end,
    han_bh_than_vo = case when p ? 'han_bh_than_vo' then (p->>'han_bh_than_vo')::date else han_bh_than_vo end
  where id = h.xe_id;
  perform app.ghi_nhat_ky(p_id, h.trang_thai, h.trang_thai, 'Sửa thông tin: ' || (select string_agg(x, ', ') from jsonb_object_keys(p) x) || v_ghi);
exception when unique_violation then
  raise exception 'Số điện thoại hoặc biển số đã có ở khách / xe khác – kiểm tra lại (gõ đúng SĐT của khách đã có thì hồ sơ tự gắn sang khách đó).';
end $$;

-- B2. Phát sinh chưa xử lý: báo xong hạng mục cuối không sang Chờ KCS; KCS không đạt được; xử lý xong phát sinh
--     (không cần làm thêm) mà các hạng mục đã xong thì sang Chờ KCS
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
    if exists (select 1 from public.phat_sinh where ho_so_id = r.ho_so_id and not da_xu_ly) then
      perform app.ghi_nhat_ky(r.ho_so_id, h.trang_thai, h.trang_thai,
        'Xong các hạng mục – còn hư hỏng phát sinh chờ CVDV lập báo giá bổ sung hoặc ghi "không cần làm thêm" rồi mới sang KCS');
    else
      perform app.doi_trang_thai(r.ho_so_id, 'cho_kcs', 'Xong các hạng mục, chờ KCS');
    end if;
  end if;
end $$;

create or replace function public.xu_ly_phat_sinh(p_ho_so bigint, p_ghi_chu text) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if nullif(trim(p_ghi_chu),'') is null then
    raise exception 'Ghi cách xử lý (ví dụ: không cần làm thêm, đã làm trong hạng mục cũ).'; end if;
  update public.phat_sinh set da_xu_ly = true, xu_ly_ghi_chu = trim(p_ghi_chu), xu_ly_boi = auth.uid(), xu_ly_luc = now()
  where ho_so_id = p_ho_so and not da_xu_ly;
  if not found then raise exception 'Hồ sơ không có phát sinh nào đang chờ.'; end if;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Xử lý phát sinh: ' || trim(p_ghi_chu));
  if h.trang_thai = 'dang_sua'
     and not exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('cho_duyet','duyet','dang_lam'))
     and exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'xong') then
    perform app.doi_trang_thai(p_ho_so, 'cho_kcs', 'Xong các hạng mục, phát sinh đã xử lý – chờ KCS');
  end if;
end $$;

-- B2 + B-nhỏ: KCS đạt cần không còn phát sinh chờ xử lý, và có ảnh sau sửa chụp SAU lần KCS chưa đạt gần nhất
create or replace function public.kcs(p_ho_so bigint, p_dat boolean, p_loi text default null, p_lam_lai bigint[] default null) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; v_truot timestamptz;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'cho_kcs' then raise exception 'Xe chưa sửa xong, chưa KCS được.'; end if;
  if p_dat then
    if exists (select 1 from public.phat_sinh where ho_so_id = p_ho_so and not da_xu_ly) then
      raise exception 'Còn hư hỏng phát sinh chưa xử lý – CVDV lập báo giá bổ sung hoặc ghi "Không cần làm thêm" trước khi KCS đạt.'; end if;
    select max(luc) into v_truot from public.kcs where ho_so_id = p_ho_so and not dat;
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'kcs' and (v_truot is null or tai_luc > v_truot)) then
      if v_truot is null then raise exception 'Chưa có ảnh sau sửa. Chụp ảnh trước khi ký KCS.';
      else raise exception 'Chưa có ảnh sau khi làm lại (lần KCS chưa đạt lúc %). Chụp ảnh mới ở bước "Sau sửa" trước khi ký KCS đạt.',
        to_char(v_truot, 'HH24:MI DD/MM'); end if;
    end if;
  end if;
  insert into public.kcs (ho_so_id, dat, loi, boi) values (p_ho_so, p_dat, nullif(trim(p_loi),''), auth.uid());
  if p_dat then
    perform app.doi_trang_thai(p_ho_so, 'dat_kcs', 'Đạt KCS');
  else
    if nullif(trim(p_loi),'') is null then raise exception 'Ghi lỗi cần làm lại.'; end if;
    if p_lam_lai is null or cardinality(p_lam_lai) = 0 then raise exception 'Chọn hạng mục phải làm lại.'; end if;
    update public.hang_muc set trang_thai = 'dang_lam', xong_luc = null
    where ho_so_id = p_ho_so and id = any(p_lam_lai) and trang_thai = 'xong';
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Chưa đạt KCS: ' || trim(p_loi));
  end if;
end $$;

-- B6 + B2: trigger hạng mục
--   - xóa dòng chờ duyệt cuối khi hồ sơ đang Chờ duyệt giá mà đã có dòng được duyệt → Đã duyệt giá (trước đây kẹt)
--   - hết hạng mục còn làm khi xe đang sửa → Chờ KCS (nếu không còn phát sinh chờ xử lý)
create or replace function app.kiem_tra_xong_sua() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_hs bigint := coalesce(new.ho_so_id, old.ho_so_id);
begin
  if tg_op = 'UPDATE' and new.trang_thai not in ('tu_choi') then return null; end if;
  if tg_op = 'DELETE'
     and exists (select 1 from public.ho_so where id = v_hs and trang_thai = 'bao_gia')
     and not exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai = 'cho_duyet')
     and exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai = 'duyet') then
    perform app.doi_trang_thai(v_hs, 'da_duyet', 'Hết dòng chờ duyệt (dòng chờ bị xóa) – đã duyệt giá, lập lệnh sửa chữa được');
  end if;
  if exists (select 1 from public.ho_so where id = v_hs and trang_thai = 'dang_sua')
     and not exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai in ('cho_duyet','duyet','dang_lam'))
     and exists (select 1 from public.hang_muc where ho_so_id = v_hs and trang_thai = 'xong')
     and not exists (select 1 from public.phat_sinh where ho_so_id = v_hs and not da_xu_ly) then
    perform app.doi_trang_thai(v_hs, 'cho_kcs', 'Hết hạng mục còn làm (phát sinh bị từ chối / xóa) – chờ KCS');
  end if;
  return null;
end $$;

-- B-nhỏ: ngày duyệt giá không trước ngày nhận xe (doanh thu sang tháng khác)
create or replace function public.duyet_gia(p_ho_so bigint, p_ngay date, ket_qua jsonb) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
  if h.nguon_tt <> 'khach' and h.gdv_id is null then
    raise exception 'Chưa có giám định viên. Bấm "Sửa" ở mục Thông tin xe và khách để ghi GDV trước khi nhập kết quả duyệt giá.'; end if;
  if p_ngay is null then raise exception 'Thiếu ngày duyệt.'; end if;
  if p_ngay > current_date then raise exception 'Ngày duyệt không được sau hôm nay.'; end if;
  if p_ngay < (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date then
    raise exception 'Ngày duyệt % trước ngày nhận xe % – kiểm tra lại ngày (dd/mm/yyyy).',
      to_char(p_ngay, 'DD/MM/YYYY'), to_char(h.ngay_vao at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY'); end if;
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

-- B3. Chia lại công nợ: phần bảo hiểm không nhỏ hơn số bảo hiểm đã trả; phần khách không nhỏ hơn giảm giá đã duyệt
create or replace function app.chia_cong_no(p_ho_so bigint, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_tong numeric; v_khach_dong numeric; v_khau_tru numeric; t record;
begin
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then
    return jsonb_build_object('tong', (select coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)), 0)
      from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong')), 'bao_hiem', 0, 'khach', null);
  end if;
  select coalesce(sum(public.tien_dong_co_vat(gia_duyet, true, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'bao_hiem'), 0)
       + coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0),
       coalesce(sum(public.tien_dong_co_vat(gia_duyet, xuat_hd, ngay_duyet, ty_le_vat)) filter (where nguoi_tra = 'khach'), 0)
    into v_tong, v_khach_dong
  from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong');
  if p_khach_tra is null then p_khach_tra := v_khach_dong + h.khau_tru_giam_tru; end if;
  if p_khach_tra < v_khach_dong then
    raise exception 'Khách chi trả ít nhất % đ (các dòng khách tự trả).', app.vnd(v_khach_dong); end if;
  if p_khach_tra > v_tong then
    raise exception 'Khách chi trả không được vượt tổng giá duyệt % đ.', app.vnd(v_tong); end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if v_tong - p_khach_tra < t.da_thu_bh then
    raise exception 'Bảo hiểm đã trả % đ cho xe này – phần bảo hiểm chi trả không được nhỏ hơn số đó (khách chi trả tối đa % đ).',
      app.vnd(t.da_thu_bh), app.vnd(v_tong - t.da_thu_bh); end if;
  if p_khach_tra < h.giam_gia then
    raise exception 'Xe đã giảm giá % đ cho khách – phần khách chi trả không được nhỏ hơn số giảm giá.', app.vnd(h.giam_gia); end if;
  v_khau_tru := round(p_khach_tra - v_khach_dong);
  if v_khau_tru <> h.khau_tru_giam_tru then
    update public.ho_so set khau_tru_giam_tru = v_khau_tru where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
      'Chia công nợ: bảo hiểm chi trả ' || app.vnd(v_tong - p_khach_tra) || ' đ, khách chi trả ' || app.vnd(p_khach_tra)
      || ' đ (khấu trừ – giảm trừ ' || app.vnd(v_khau_tru) || ' đ)');
    perform app.cap_nhat_dong(p_ho_so);
  end if;
  return jsonb_build_object('tong', v_tong, 'bao_hiem', v_tong - p_khach_tra, 'khach', p_khach_tra, 'khau_tru', v_khau_tru);
end $$;

-- B4. Người làm bước tiếp theo: xe bảo hiểm mà phần bảo hiểm chi trả 0 đ (khách chi trả toàn bộ) không có bước gửi hồ sơ BH
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
      if h.nguon_tt <> 'khach' and h.gui_hs_ngay is null and h.loai <> 'bao_hanh'
         and coalesce((select sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat)) from public.hang_muc m
                        where m.ho_so_id = h.id and m.nguoi_tra = 'bao_hiem' and m.trang_thai in ('duyet','dang_lam','xong')), 0)
            - h.khau_tru_giam_tru > 0 then
        return app.nhan_vien_dau('ke_toan', h.chi_nhanh_id);                     -- gửi hồ sơ bảo hiểm
      end if;
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;
    when 'da_gui_hs', 'dong' then
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;  -- chăm sóc
    else return null;
  end case;
end $$;

-- =====================================================================
-- C. KHO & ĐỒ NGHỀ
-- =====================================================================
-- C1. Kiểm kê: lưu tồn sổ sách LÚC NHẬP SỐ ĐẾM; chốt điều chỉnh theo (đếm − tồn lúc đếm) nên xuất / nhập trong lúc
--     đếm không làm sai tồn; ghi điều chỉnh vào ngày kiểm nếu tháng đó còn mở; có chênh thì quản lý chung / giám đốc chốt;
--     biên bản khi chênh trên 5% giá trị cả đợt HOẶC một mã chênh trên 5% giá trị của mã (từ mức tối thiểu cài đặt)
alter table public.kiem_ke_dong add column if not exists dem_luc timestamptz;
comment on column public.kiem_ke_dong.ton_so_sach is 'Tồn sổ sách lúc nhập số đếm (043; trước đó: lúc chốt)';
insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('kiem_ke_bien_ban_toi_thieu', '500000', 'Kiểm kê: một mã chênh trên 5% giá trị của mã và từ số tiền này trở lên thì phải ghi biên bản')
on conflict (khoa) do nothing;

create or replace function public.luu_dem_kiem_ke(p_id bigint, p_dong jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.kiem_ke; d jsonb; v_dem numeric;
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  select * into r from public.kiem_ke where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đợt kiểm kê.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'dang_dem' then raise exception 'Đợt kiểm kê đã chốt hoặc đã hủy.'; end if;
  for d in select * from jsonb_array_elements(p_dong) loop
    v_dem := (d->>'ton_thuc_te')::numeric;
    if v_dem is not null and v_dem < 0 then raise exception 'Số đếm không được âm.'; end if;
    -- số đếm đổi thì ghi lại tồn sổ sách ngay lúc đó (đếm xong mới xuất / nhập thì không tính vào chênh lệch)
    update public.kiem_ke_dong kd set
      ton_so_sach = case when v_dem is null then null
                         when kd.ton_thuc_te is distinct from v_dem or kd.ton_so_sach is null then app.ton_hang(kd.hang_id)
                         else kd.ton_so_sach end,
      dem_luc = case when v_dem is null then null when kd.ton_thuc_te is distinct from v_dem or kd.dem_luc is null then now() else kd.dem_luc end,
      ton_thuc_te = v_dem
    where kd.id = (d->>'dong_id')::bigint and kd.kiem_ke_id = p_id;
  end loop;
end $$;

create or replace function public.chot_kiem_ke(p_id bigint, p_bien_ban text default null) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare r public.kiem_ke; d record; v_ss numeric; v_gia numeric; v_tong_ss numeric := 0; v_tong_chenh numeric := 0;
  v_px bigint; v_pxd bigint; v_ma text; v_ngay date; v_ty_le numeric; v_so_chenh int := 0; v_ma_lon text[] := '{}';
  v_toi_thieu numeric := app.cai_dat_so('kiem_ke_bien_ban_toi_thieu', 500000); v_ton numeric; h public.hang_kho;
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  select * into r from public.kiem_ke where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đợt kiểm kê.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'dang_dem' then raise exception 'Đợt kiểm kê đã chốt hoặc đã hủy.'; end if;
  -- ngày điều chỉnh = ngày kiểm nếu tháng đó còn mở (kiểm cuối tháng, sáng hôm sau mới chốt vẫn vào đúng tháng)
  v_ngay := case when app.thang_da_chot(r.chi_nhanh_id, r.ngay) then current_date else least(r.ngay, current_date) end;
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, v_ngay);
  if exists (select 1 from public.kiem_ke_dong where kiem_ke_id = p_id and ton_thuc_te is null) then
    raise exception 'Còn mã chưa nhập số đếm thực tế.'; end if;
  -- Tồn sổ sách lúc đếm (dòng cũ chưa có thì lấy tồn hiện tại) + giá vốn bình quân hiện tại của từng mã
  for d in select * from public.kiem_ke_dong where kiem_ke_id = p_id for update loop
    v_ss := coalesce(d.ton_so_sach, app.ton_hang(d.hang_id));
    select coalesce(sum(con_lai * don_gia_von) / nullif(sum(con_lai), 0),
                    (select don_gia_von from public.lo_kho where hang_id = d.hang_id order by ngay desc, id desc limit 1), 0)
      into v_gia from public.lo_kho where hang_id = d.hang_id and con_lai > 0;
    update public.kiem_ke_dong set ton_so_sach = v_ss, don_gia_von = v_gia where id = d.id;
    v_tong_ss := v_tong_ss + v_ss * v_gia;
    v_tong_chenh := v_tong_chenh + abs(d.ton_thuc_te - v_ss) * v_gia;
    if d.ton_thuc_te <> v_ss then
      v_so_chenh := v_so_chenh + 1;
      if abs(d.ton_thuc_te - v_ss) * v_gia >= v_toi_thieu
         and (v_ss * v_gia = 0 or abs(d.ton_thuc_te - v_ss) * v_gia > 0.05 * v_ss * v_gia) then
        v_ma_lon := v_ma_lon || (select ma from public.hang_kho where id = d.hang_id);
      end if;
    end if;
  end loop;
  -- C4: có chênh thì người khác người đếm duyệt: quản lý chung / giám đốc chốt
  if v_so_chenh > 0 and not app.co_vai_tro('quan_ly','giam_doc') then
    raise exception 'Đợt kiểm kê có % mã chênh lệch – quản lý chung hoặc giám đốc chốt (kho lưu số đếm rồi báo quản lý).', v_so_chenh
      using errcode = '42501';
  end if;
  v_ty_le := case when v_tong_ss > 0 then v_tong_chenh / v_tong_ss else case when v_tong_chenh > 0 then 1 else 0 end end;
  if nullif(trim(p_bien_ban),'') is null then
    if v_ty_le > 0.05 then
      raise exception 'Chênh lệch % đ, bằng % phần trăm giá trị kiểm – vượt 5%%, phải ghi biên bản.', app.vnd(round(v_tong_chenh)), round(v_ty_le * 100, 1);
    end if;
    if cardinality(v_ma_lon) > 0 then
      raise exception 'Mã % chênh trên 5%% giá trị của mã (từ % đ) – phải ghi biên bản.', array_to_string(v_ma_lon, ', '), app.vnd(v_toi_thieu);
    end if;
  end if;
  -- Thiếu: xuất điều chỉnh (nhập trước xuất trước). Thừa: thêm lô theo giá vốn hiện tại. Theo chênh lúc đếm.
  for d in select * from public.kiem_ke_dong where kiem_ke_id = p_id and ton_thuc_te <> ton_so_sach loop
    if d.ton_thuc_te < d.ton_so_sach then
      v_ton := app.ton_hang(d.hang_id);
      if v_ton < d.ton_so_sach - d.ton_thuc_te then
        select * into h from public.hang_kho where id = d.hang_id;
        raise exception 'Mã % (%): kiểm kê thiếu % % nhưng tồn hiện chỉ còn % – từ lúc đếm đã xuất quá số đếm được. Kiểm tra phiếu xuất sau lúc đếm rồi đếm lại mã này.',
          h.ma, h.ten, trim_scale(d.ton_so_sach - d.ton_thuc_te), h.dvt, trim_scale(v_ton);
      end if;
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
  return jsonb_build_object('gia_tri_so_sach', round(v_tong_ss), 'gia_tri_chenh', round(v_tong_chenh), 'ty_le', round(v_ty_le * 100, 1),
    'ngay_dieu_chinh', v_ngay);
end $$;

-- C2 + C3. Phiếu nhập:
--   - theo đề nghị mua: cùng nhà cung cấp; mỗi mã phải có trong đề nghị, số lượng không vượt số đã duyệt;
--     tổng tiền không vượt tổng đã duyệt quá 5% (cài đặt nhap_vuot_de_nghi_ty_le)
--   - đề nghị mua lập từ phiếu đề xuất vật tư: không "xuất ngay" (xuất theo phiếu đề xuất, tránh xe nhận hai lần)
--   - không theo đề nghị mua mà từ ngưỡng 3 báo giá: hỏi lại (giám đốc thấy trong Việc cần xử lý)
insert into public.cai_dat (khoa, gia_tri, mo_ta) values
  ('nhap_vuot_de_nghi_ty_le', '0.05', 'Phiếu nhập theo đề nghị mua được vượt tổng tiền đã duyệt tối đa (0,05 = 5%)')
on conflict (khoa) do nothing;

create or replace function public.lap_phieu_nhap(p jsonb) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := app.chi_nhanh(); v_ngay date := coalesce((p->>'ngay')::date, current_date);
  v_id bigint; v_ma text; d jsonb; h public.hang_kho; v_dong bigint; v_sl numeric; v_vat numeric; v_tien numeric;
  v_tong numeric := 0; v_tong_vat numeric := 0; dm public.de_nghi_mua; hs public.ho_so; v_xuat jsonb := null;
  v_px bigint; v_px_ma text; v_pxd bigint; x record; v_sl_dn numeric; v_nguong numeric := app.cai_dat_so('nguong_3_bao_gia', 5000000);
  v_hoi boolean := p ? 'bo_qua_canh_bao' and not coalesce((p->>'bo_qua_canh_bao')::boolean, false);
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
    if dm.nha_cung_cap_id <> (p->>'nha_cung_cap_id')::bigint then
      raise exception 'Phiếu nhập theo đề nghị mua % phải cùng nhà cung cấp % (đổi nhà cung cấp thì lập đề nghị mua mới).',
        dm.ma, (select ten from public.nha_cung_cap where id = dm.nha_cung_cap_id);
    end if;
    if coalesce((p->>'xuat_cho_xe')::boolean, false)
       and exists (select 1 from public.de_nghi_mua_dong where de_nghi_id = dm.id and de_xuat_dong_id is not null) then
      raise exception 'Đề nghị mua % lập từ phiếu đề xuất vật tư – hàng về thì xuất theo phiếu đề xuất (Kho → Đề xuất vật tư → Xuất kho), không "xuất ngay" (tránh xe nhận hai lần).', dm.ma;
    end if;
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

  if dm.id is not null then
    -- đối chiếu với đề nghị đã duyệt: đúng mã, không quá số lượng, tổng tiền không vượt quá tỷ lệ cho phép
    for x in select pd.hang_id, sum(pd.so_luong) as sl from public.phieu_nhap_dong pd where pd.phieu_id = v_id group by pd.hang_id loop
      select sum(so_luong) into v_sl_dn from public.de_nghi_mua_dong where de_nghi_id = dm.id and hang_id = x.hang_id;
      select * into h from public.hang_kho where id = x.hang_id;
      if v_sl_dn is null then
        raise exception 'Mã % (%) không có trong đề nghị mua % – nhập riêng hoặc lập đề nghị mua bổ sung.', h.ma, h.ten, dm.ma; end if;
      if x.sl > v_sl_dn then
        raise exception 'Mã %: nhập % % vượt số đã duyệt % % trong đề nghị mua %.', h.ma, trim_scale(x.sl), coalesce(h.dvt_nhap, h.dvt),
          trim_scale(v_sl_dn), coalesce(h.dvt_nhap, h.dvt), dm.ma; end if;
    end loop;
    if v_tong > dm.tong_tien * (1 + app.cai_dat_so('nhap_vuot_de_nghi_ty_le', 0.05)) + 1 then
      raise exception 'Tổng phiếu nhập % đ vượt tổng đề nghị mua đã duyệt % đ quá % phần trăm – lập đề nghị mua bổ sung (hoặc sửa giá theo hóa đơn).',
        app.vnd(v_tong), app.vnd(dm.tong_tien), round(app.cai_dat_so('nhap_vuot_de_nghi_ty_le', 0.05) * 100);
    end if;
    -- Hàng của đề nghị mua đã về: đề nghị chuyển "đã nhập", các dòng đề xuất đang chờ mua trở lại chờ xuất
    update public.de_nghi_mua set trang_thai = 'da_nhap' where id = dm.id;
    update public.de_xuat_dong set cho_mua = false
    where id in (select de_xuat_dong_id from public.de_nghi_mua_dong where de_nghi_id = dm.id and de_xuat_dong_id is not null);
  elsif v_tong >= v_nguong and v_hoi and not app.co_vai_tro('giam_doc') then
    raise exception 'CANH_BAO: Phiếu nhập % đ (từ % đ) không theo đề nghị mua đã duyệt – mua từ mức này cần 3 báo giá và duyệt trước. Vẫn nhập? (giám đốc sẽ thấy phiếu này trong Việc cần xử lý)',
      app.vnd(v_tong), app.vnd(v_nguong);
  end if;

  -- Phụ tùng mua riêng cho xe: nhập rồi xuất ngay cho xe đó
  if hs.id is not null and coalesce((p->>'xuat_cho_xe')::boolean, false) then
    v_px_ma := app.ma_chung_tu('PX', v_cn, v_ngay, 'phieu_xuat');
    insert into public.phieu_xuat (chi_nhanh_id, ma, ngay, loai, ho_so_id, ghi_chu, tao_boi)
    values (v_cn, v_px_ma, v_ngay, 'cho_xe', hs.id, 'Xuất ngay theo phiếu nhập ' || v_ma, auth.uid()) returning id into v_px;
    -- 041: trừ đúng lô vừa nhập (giá vốn của xe = giá mua riêng cho xe; lô cũ giữ nguyên trong kho)
    for x in select l.id as lo_id, l.hang_id, l.so_luong as sl from public.lo_kho l
             join public.phieu_nhap_dong pd on pd.id = l.phieu_nhap_dong_id where pd.phieu_id = v_id order by pd.id loop
      insert into public.phieu_xuat_dong (phieu_id, hang_id, so_luong) values (v_px, x.hang_id, x.sl) returning id into v_pxd;
      perform app.xuat_lo_chi_dinh(v_pxd, x.lo_id, x.sl);
    end loop;
    perform app.ghi_nhat_ky(hs.id, hs.trang_thai, hs.trang_thai, 'Nhập và xuất ngay phụ tùng cho xe: ' || v_ma || ' → ' || v_px_ma);
    v_xuat := jsonb_build_object('id', v_px, 'ma', v_px_ma);
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'tong_tien', v_tong, 'phieu_xuat', v_xuat);
end $$;

-- C(12). Điều chỉnh giá phiếu nhập chưa khớp (kế toán / giám đốc): sửa đơn giá, VAT theo hóa đơn; lô trong kho và
--   phần đã xuất cập nhật giá vốn theo (tháng của các phiếu xuất đó phải còn mở); phiếu về "chờ khớp"
create or replace function public.dieu_chinh_phieu_nhap(p_id bigint, p_dong jsonb, p_ly_do text) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare r public.phieu_nhap; d jsonb; pd public.phieu_nhap_dong; v_gia numeric; v_vat numeric; v_tien numeric;
  v_tong numeric; v_tvat numeric; x record; v_so int := 0; v_ghi text := '';
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_nhap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu nhập.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai not in ('cho_khop','treo') then raise exception 'Chỉ điều chỉnh phiếu nhập chưa khớp hóa đơn (chờ khớp / treo).'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do điều chỉnh (ví dụ: giá trên hóa đơn 1.050.000).'; end if;
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  for d in select * from jsonb_array_elements(coalesce(p_dong, '[]'::jsonb)) loop
    select * into pd from public.phieu_nhap_dong where id = (d->>'dong_id')::bigint and phieu_id = p_id for update;
    if not found then raise exception 'Dòng không thuộc phiếu nhập này.'; end if;
    v_gia := coalesce((d->>'don_gia')::numeric, pd.don_gia);
    v_vat := coalesce((d->>'ty_le_vat')::numeric, pd.ty_le_vat);
    if v_gia < 0 or v_vat < 0 or v_vat >= 1 then raise exception 'Đơn giá / VAT không hợp lệ.'; end if;
    continue when v_gia = pd.don_gia and v_vat = pd.ty_le_vat;
    for x in select distinct px.chi_nhanh_id, px.ngay from public.xuat_lo xl join public.lo_kho l on l.id = xl.lo_id
             join public.phieu_xuat_dong xd on xd.id = xl.phieu_xuat_dong_id join public.phieu_xuat px on px.id = xd.phieu_id
             where l.phieu_nhap_dong_id = pd.id and px.trang_thai = 'hieu_luc' loop
      perform app.yeu_cau_thang_mo(x.chi_nhanh_id, x.ngay);
    end loop;
    v_tien := round(pd.so_luong * v_gia * (1 + v_vat));
    update public.phieu_nhap_dong set don_gia = v_gia, ty_le_vat = v_vat, thanh_tien = v_tien where id = pd.id;
    update public.lo_kho set don_gia_von = v_tien / so_luong where phieu_nhap_dong_id = pd.id;
    update public.xuat_lo xl set don_gia_von = l.don_gia_von from public.lo_kho l where l.id = xl.lo_id and l.phieu_nhap_dong_id = pd.id;
    update public.phieu_xuat_dong xd set gia_von = (select round(sum(xl2.so_luong * xl2.don_gia_von)) from public.xuat_lo xl2 where xl2.phieu_xuat_dong_id = xd.id)
    where xd.id in (select xl.phieu_xuat_dong_id from public.xuat_lo xl join public.lo_kho l on l.id = xl.lo_id where l.phieu_nhap_dong_id = pd.id);
    v_ghi := v_ghi || format('%s%s: %s → %s', case when v_so > 0 then '; ' else '' end,
      (select ma from public.hang_kho where id = pd.hang_id), app.vnd(pd.thanh_tien), app.vnd(v_tien));
    v_so := v_so + 1;
  end loop;
  if v_so = 0 then raise exception 'Không có dòng nào thay đổi.'; end if;
  select coalesce(sum(thanh_tien), 0), coalesce(sum(thanh_tien - round(so_luong * don_gia)), 0) into v_tong, v_tvat
  from public.phieu_nhap_dong where phieu_id = p_id;
  update public.phieu_nhap set tong_tien = v_tong, tien_vat = v_tvat, trang_thai = 'cho_khop',
    ghi_chu = concat_ws(' · ', ghi_chu, 'Điều chỉnh giá (' || v_ghi || '): ' || trim(p_ly_do))
  where id = p_id;
  return jsonb_build_object('tong_tien', v_tong, 'tien_vat', v_tvat);
end $$;
revoke execute on function public.dieu_chinh_phieu_nhap(bigint, jsonb, text) from public, anon;
grant execute on function public.dieu_chinh_phieu_nhap(bigint, jsonb, text) to authenticated;

-- C(16). Hủy phiếu nhập theo đề nghị mua sinh từ đề xuất: các dòng đề xuất chưa xuất đủ trở lại "chờ mua"
--        (trước đây về "chờ xuất" mà không có hàng → chuyển mua lần hai thành hai đề nghị cho cùng phần thiếu)
create or replace function public.huy_phieu_nhap(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_nhap; v_px text;
begin
  perform app.yeu_cau('kho','giam_doc');
  select * into r from public.phieu_nhap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu nhập.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai not in ('cho_khop','treo') then raise exception 'Phiếu đã khớp hóa đơn hoặc đã hủy – không hủy được.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  select string_agg(distinct px.ma, ', ') into v_px
  from public.xuat_lo xl
  join public.phieu_xuat_dong d on d.id = xl.phieu_xuat_dong_id
  join public.phieu_xuat px on px.id = d.phieu_id
  where px.trang_thai = 'hieu_luc'
    and xl.lo_id in (select l.id from public.lo_kho l join public.phieu_nhap_dong nd on nd.id = l.phieu_nhap_dong_id where nd.phieu_id = p_id);
  if v_px is not null then
    raise exception 'Hàng của phiếu nhập này đã xuất ở phiếu % – hủy phiếu xuất đó trước.', v_px;
  end if;
  if exists (select 1 from public.lo_kho l join public.phieu_nhap_dong d on d.id = l.phieu_nhap_dong_id
             where d.phieu_id = p_id and l.con_lai < l.so_luong) then
    raise exception 'Hàng của phiếu này đã xuất một phần (kiểm kê / điều chỉnh) – không hủy được.';
  end if;
  -- phiếu xuất đã hủy vẫn còn dòng xuat_lo trỏ vào lô → xóa trước
  delete from public.xuat_lo xl using public.phieu_xuat_dong d, public.phieu_xuat px
  where d.id = xl.phieu_xuat_dong_id and px.id = d.phieu_id and px.trang_thai = 'huy'
    and xl.lo_id in (select l.id from public.lo_kho l join public.phieu_nhap_dong nd on nd.id = l.phieu_nhap_dong_id where nd.phieu_id = p_id);
  delete from public.lo_kho where phieu_nhap_dong_id in (select id from public.phieu_nhap_dong where phieu_id = p_id);
  update public.phieu_nhap set trang_thai = 'huy', ghi_chu = concat_ws(' · ', ghi_chu, 'Hủy: ' || trim(p_ly_do)) where id = p_id;
  if r.de_nghi_mua_id is not null then
    update public.de_nghi_mua set trang_thai = 'da_duyet' where id = r.de_nghi_mua_id and trang_thai = 'da_nhap';
    update public.de_xuat_dong dd set cho_mua = true
    from public.de_nghi_mua_dong md, public.de_xuat_vat_tu dx
    where md.de_nghi_id = r.de_nghi_mua_id and md.de_xuat_dong_id = dd.id and dx.id = dd.de_xuat_id
      and dx.trang_thai = 'cho_xuat' and dd.da_xuat < dd.so_luong;
  end if;
end $$;

-- C5. Phiếu đề xuất đã xuất một phần mà xe đã qua KCS (hoặc không cần nữa): đóng phần còn lại, ghi lý do
alter table public.de_xuat_vat_tu add column if not exists ly_do_dong text;
alter table public.de_xuat_vat_tu add column if not exists dong_boi uuid;
alter table public.de_xuat_vat_tu add column if not exists dong_luc timestamptz;
create or replace function public.dong_de_xuat_vat_tu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare r public.de_xuat_vat_tu; v_tt text;
begin
  perform app.yeu_cau('kho','quan_ly','giam_doc');
  select * into r from public.de_xuat_vat_tu where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu đề xuất.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_xuat' then raise exception 'Phiếu đề xuất đã xuất xong hoặc đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do đóng phần còn lại (ví dụ: xe đã giao, không cần nữa).'; end if;
  update public.de_xuat_dong set cho_mua = false where de_xuat_id = p_id;
  update public.de_xuat_vat_tu set trang_thai = 'da_xuat', ly_do_dong = trim(p_ly_do), dong_boi = auth.uid(), dong_luc = now() where id = p_id;
  select trang_thai into v_tt from public.ho_so where id = r.ho_so_id;
  perform app.ghi_nhat_ky(r.ho_so_id, v_tt, v_tt, 'Đóng phần chưa xuất của đề xuất ' || r.ma || ': ' || trim(p_ly_do));
end $$;
revoke execute on function public.dong_de_xuat_vat_tu(bigint, text) from public, anon;
grant execute on function public.dong_de_xuat_vat_tu(bigint, text) to authenticated;

-- v_de_xuat: thêm lý do đóng phần còn lại (cột cuối)
create or replace view public.v_de_xuat as
 SELECT d.id, d.chi_nhanh_id, d.ma, d.ho_so_id, d.to_id, d.ghi_chu, d.trang_thai, d.nguoi_lap, d.tao_luc,
    h.ma AS ma_ho_so,
    public.bien_so_hien_thi(x.bien_so) AS bien_so,
    h.trang_thai AS trang_thai_ho_so,
    nv.ho_ten AS nguoi_lap_ten,
    (SELECT count(*) FROM public.de_xuat_dong dd WHERE dd.de_xuat_id = d.id) AS so_dong,
    (SELECT count(*) FROM public.de_xuat_dong dd WHERE dd.de_xuat_id = d.id AND dd.cho_mua) AS so_dong_cho_mua,
    d.ly_do_dong
   FROM public.de_xuat_vat_tu d
     JOIN public.ho_so h ON h.id = d.ho_so_id
     JOIN public.xe x ON x.id = h.xe_id
     LEFT JOIN public.nhan_vien nv ON nv.id = d.nguoi_lap
  WHERE ((select app.co_vai_tro('giam_doc')) OR d.chi_nhanh_id = (select app.chi_nhanh()))
    AND ((select app.xem_nhu_nhan_vien())
         OR ((select app.co_vai_tro('truong_nhom')) AND (d.to_id = (select app.to_cua_toi()) OR d.nguoi_lap = (select auth.uid()))));
grant select on public.v_de_xuat to authenticated;
revoke all on public.v_de_xuat from anon;

-- C(17). Mã hàng còn tồn không tắt "Đang dùng" được (biến mất khỏi Excel tồn kho, đợt kiểm kê)
create or replace function public.luu_hang_kho(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint := (p->>'id')::bigint; v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ma text := upper(regexp_replace(trim(coalesce(p->>'ma','')), '\s+', '', 'g')); r public.hang_kho; v_ton numeric;
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
    if r.hoat_dong and not coalesce((p->>'hoat_dong')::boolean, r.hoat_dong) then
      v_ton := app.ton_hang(v_id);
      if v_ton > 0 then
        raise exception 'Mã % còn tồn % % – xuất hết hoặc kiểm kê về 0 rồi mới ngừng dùng được.', r.ma, trim_scale(v_ton), r.dvt; end if;
    end if;
    update public.hang_kho set ma = v_ma, ten = trim(p->>'ten'), nhom = coalesce(nullif(trim(p->>'nhom'),''), nhom),
      dvt = trim(p->>'dvt'), dvt_nhap = nullif(trim(p->>'dvt_nhap'),''), he_so = coalesce((p->>'he_so')::numeric, 1),
      ton_toi_thieu = coalesce((p->>'ton_toi_thieu')::numeric, 0), nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint,
      ghi_chu = nullif(trim(p->>'ghi_chu'),''), hoat_dong = coalesce((p->>'hoat_dong')::boolean, hoat_dong)
    where id = v_id;
  end if;
  return v_id;
end $$;

-- C(19). Tệp hóa đơn / báo giá NCC: đường dẫn phải nằm trong thư mục kho của đúng chứng từ (như them_tep của hồ sơ)
create or replace function public.them_tep_kho(p_loai text, p_id bigint, p_duong_dan text, p_ten text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_cn text; v_ma text; v_goc text;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  if p_loai = 'phieu_nhap' then select chi_nhanh_id, ma into v_cn, v_ma from public.phieu_nhap where id = p_id;
  elsif p_loai = 'de_nghi_mua' then select chi_nhanh_id, ma into v_cn, v_ma from public.de_nghi_mua where id = p_id;
  else raise exception 'Loại tệp không hợp lệ.'; end if;
  if v_cn is null then raise exception 'Không tìm thấy chứng từ.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  v_goc := v_cn || '/kho/' || v_ma || '/';
  if p_duong_dan is null or left(p_duong_dan, length(v_goc)) <> v_goc or position('..' in p_duong_dan) > 0 then
    raise exception 'Tệp không thuộc thư mục của chứng từ % – tải lại từ trang chứng từ.', v_ma;
  end if;
  insert into public.kho_tep (loai, doi_tuong_id, duong_dan, ten, tai_boi) values (p_loai, p_id, p_duong_dan, p_ten, auth.uid())
  returning id into v_id;
  return v_id;
end $$;

-- C6. Thiết bị, đồ nghề
--   - thanh lý: đóng các sự cố chờ xử lý của món đó (không treo ở Việc hôm nay)
--   - xử lý sự cố: món đã thanh lý / mất thì không xử lý "sửa xong / đưa đi sửa" được (làm món đã thanh lý sống lại)
--   - ghi bảo dưỡng / sửa chữa xong: chỉ đổi tình trạng máy; sự cố hỏng vẫn chờ giám đốc / quản lý chung xử lý
--     (để ghi người chịu, bồi thường)
create or replace function public.thanh_ly_tai_san(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.tai_san;
begin
  perform app.yeu_cau_quan_ly_tai_san();
  select * into r from public.tai_san where id = p_id for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.tinh_trang in ('mat','thanh_ly') then raise exception 'Món này đã mất / thanh lý.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do thanh lý.'; end if;
  update public.tai_san set tinh_trang = 'thanh_ly', cho_nhan = false where id = p_id;
  update public.lich_bao_duong set hoat_dong = false where tai_san_id = p_id;
  update public.su_co_tai_san set trang_thai = 'da_xu_ly', ket_qua = 'thanh_ly', xu_ly_boi = auth.uid(), xu_ly_luc = now(),
    ghi_chu_xu_ly = 'Đóng theo thanh lý: ' || trim(p_ly_do)
  where tai_san_id = p_id and trang_thai = 'cho_xu_ly';
  perform app.ghi_ls_tai_san(p_id, 'thanh_ly', 'Thanh lý: ' || trim(p_ly_do));
end $$;

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
  if t.tinh_trang in ('thanh_ly','mat') and v_kq in ('dua_sua','da_sua','tim_thay') then
    raise exception 'Món % đã % – không ghi "%" được.', t.ma, case t.tinh_trang when 'mat' then 'ghi mất' else 'thanh lý' end,
      case v_kq when 'dua_sua' then 'Đưa đi sửa' when 'da_sua' then 'Đã sửa xong' else 'Đã tìm thấy' end;
  end if;
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

create or replace function public.ghi_bao_duong(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.tai_san; v_id bigint; v_ngay date := coalesce((p->>'ngay')::date, current_date); v_loai text := coalesce(p->>'loai', 'bao_duong');
begin
  select * into t from public.tai_san where id = (p->>'tai_san_id')::bigint for update;
  if not found then raise exception 'Không tìm thấy thiết bị, đồ nghề này.'; end if;
  perform app.yeu_cau_chi_nhanh(t.chi_nhanh_id);
  if not (app.phu_trach_nhom(t.nhom_id) or app.co_vai_tro('kho')) then raise exception 'Bạn không phụ trách nhóm này.' using errcode = '42501'; end if;
  if t.tinh_trang in ('mat','thanh_ly') then raise exception 'Món này đã mất / thanh lý.'; end if;
  if v_loai not in ('bao_duong','sua_chua') then raise exception 'Loại không đúng.'; end if;
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'noi_dung'),'') is null then raise exception 'Ghi nội dung đã làm.'; end if;
  if (p->>'lich_id') is not null and not exists (select 1 from public.lich_bao_duong where id = (p->>'lich_id')::bigint and tai_san_id = t.id) then
    raise exception 'Lịch bảo dưỡng không thuộc máy này.'; end if;
  insert into public.bao_duong_tai_san (tai_san_id, lich_id, loai, ngay, noi_dung, nguoi_lam, chi_phi, thue_ngoai, tao_boi)
  values (t.id, (p->>'lich_id')::bigint, v_loai, v_ngay, trim(p->>'noi_dung'), nullif(trim(p->>'nguoi_lam'),''),
    coalesce((p->>'chi_phi')::numeric, 0), coalesce((p->>'thue_ngoai')::boolean, false), auth.uid()) returning id into v_id;
  if (p->>'lich_id') is not null then
    update public.lich_bao_duong set lan_cuoi = greatest(coalesce(lan_cuoi, v_ngay), v_ngay) where id = (p->>'lich_id')::bigint;
  end if;
  -- máy sửa xong: dùng lại được; sự cố hỏng (nếu có) vẫn chờ giám đốc / quản lý chung xử lý
  if coalesce((p->>'xong')::boolean, false) and t.tinh_trang in ('hong','dang_sua') then
    update public.tai_san set tinh_trang = 'tot' where id = t.id;
  end if;
  perform app.ghi_ls_tai_san(t.id, v_loai, concat_ws(' – ', trim(p->>'noi_dung'),
    case when coalesce((p->>'chi_phi')::numeric, 0) > 0 then format('chi phí %s đ', to_char((p->>'chi_phi')::numeric, 'FM999G999G999G999')) end,
    case when coalesce((p->>'xong')::boolean, false) then 'đã dùng lại được' end));
  return v_id;
end $$;

-- C(20). Tổ chỉ gắn cho trưởng nhóm (tài khoản khác còn tổ cũ thì Bảng việc xưởng bị lọc theo tổ đó)
create or replace function app.bo_to_khong_phai_truong_nhom() returns trigger
language plpgsql as $$
begin
  if new.to_id is not null and not ('truong_nhom' = any(coalesce(new.vai_tro, '{}'))) then new.to_id := null; end if;
  return new;
end $$;
drop trigger if exists nhan_vien_bo_to on public.nhan_vien;
create trigger nhan_vien_bo_to before insert or update of to_id, vai_tro on public.nhan_vien
  for each row execute function app.bo_to_khong_phai_truong_nhom();
update public.nhan_vien set to_id = null where to_id is not null and not ('truong_nhom' = any(coalesce(vai_tro, '{}')));

create or replace function public.bang_viec_to() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','ke_toan','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select to_id, chi_nhanh_id into v_to, v_cn from public.nhan_vien where id = auth.uid();
  -- chỉ trưởng nhóm (không kiêm văn phòng) mới xem theo tổ của mình
  if not app.co_vai_tro('truong_nhom') or app.la_nhan_vien() then v_to := null; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ho_so_id', h.id, 'ma', h.ma, 'bien_so', public.bien_so_hien_thi(x.bien_so),
      'xe', concat_ws(' ', hx.ten, dx.ten, x.mau), 'hen_giao', h.hen_giao, 'trang_thai', h.trang_thai,
      'tinh_trang_xe', h.tinh_trang_xe,
      'nguon_tt', h.nguon_tt, 'loai', h.loai, 'chi_nhanh_id', h.chi_nhanh_id,
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
      and (v_to is null or exists (
            select 1 from public.hang_muc m where m.ho_so_id = h.id and m.to_id = v_to and m.trang_thai in ('dang_lam','xong')))
  ), '[]'::jsonb);
end $$;

-- C(14). Dịch vụ nhanh trùng: cùng xe, cùng ngày, cùng dịch vụ → hỏi lại (chỉ khi giao diện gửi bo_qua_canh_bao)
create or replace function public.ghi_dich_vu_nhanh(p jsonb) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); v_ngay date := coalesce((p->>'ngay')::date, current_date); v_id bigint;
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_kh bigint; v_xe bigint; v_kh_xe bigint; v_to text := nullif(p->>'to_id', ''); v_nguoi text := nullif(trim(p->>'nguoi_lam'),'');
  v_thu_ngay boolean := coalesce((p->>'thu_ngay')::boolean, false); m public.muc_thu_chi;
  v_tn boolean := app.co_vai_tro('truong_nhom') and not app.la_nhan_vien();   -- 041: trưởng nhóm không sửa thông tin khách
  v_cu public.dich_vu_nhanh;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  perform app.yeu_cau_thang_mo(v_cn, v_ngay);
  if v_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  if nullif(trim(p->>'dich_vu'),'') is null then raise exception 'Ghi dịch vụ đã làm.'; end if;
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_to is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Chọn tổ làm: Điện – máy – gầm hoặc Detailing.'; end if;
  if v_to is not null then
    if v_to not in ('DMG', 'DT') then raise exception 'Dịch vụ nhanh chỉ do tổ Điện – máy – gầm hoặc Detailing làm.'; end if;
    select ten into v_nguoi from public.to_thuc_hien where id = v_to;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so'; end if;
  if v_dt <> '' and v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if v_thu_ngay then
    if not app.co_vai_tro('ke_toan','giam_doc') then raise exception 'Chỉ kế toán hoặc giám đốc thu tiền ngay; người khác ghi dịch vụ rồi kế toán thu ở Thu chi.' using errcode = '42501'; end if;
    if (p->>'tai_khoan_id') is null then raise exception 'Chọn tài khoản nhận tiền.'; end if;
    select * into m from public.muc_thu_chi where loai = 'thu' and tinh_chat = 'thu_dich_vu_nhanh' and hoat_dong order by id limit 1;
    if not found then raise exception 'Chưa có mục thu "Thu dịch vụ nhanh" trong Danh mục.'; end if;
  end if;

  -- Khách: tìm theo SĐT (như tiếp nhận); có tên mới thì cập nhật.
  -- Trưởng nhóm: không sửa khách cũ; xe đã có trong sổ thì giữ chủ xe cũ, bỏ qua SĐT gõ thêm.
  if v_dt <> '' and not (v_tn and v_bs is not null and exists (select 1 from public.xe where bien_so = v_bs)) then
    perform pg_advisory_xact_lock(hashtext('khach_' || v_dt));
    select id into v_kh from public.khach_hang where dien_thoai = v_dt;
    if v_kh is null then
      insert into public.khach_hang (ten, dien_thoai) values (coalesce(nullif(trim(p->>'ten_khach'),''), 'Chưa có tên'), v_dt) returning id into v_kh;
    elsif nullif(trim(p->>'ten_khach'),'') is not null and not v_tn then
      update public.khach_hang set ten = trim(p->>'ten_khach') where id = v_kh;
    end if;
  end if;
  -- Xe: tìm theo biển số; chưa có thì tạo (loại xe để trống, lần tiếp nhận sau bổ sung)
  if v_bs is not null then
    perform pg_advisory_xact_lock(hashtext('xe_' || v_bs));
    select id, khach_hang_id into v_xe, v_kh_xe from public.xe where bien_so = v_bs;
    if v_xe is not null and (v_kh is null or v_tn) then v_kh := v_kh_xe; end if;
    if v_xe is null then
      insert into public.xe (bien_so, khach_hang_id) values (v_bs, v_kh) returning id into v_xe;
    elsif v_dt <> '' and not v_tn then
      update public.xe set khach_hang_id = v_kh where id = v_xe;
    end if;
    -- 043: cùng xe, cùng ngày, cùng dịch vụ đã có lượt → hỏi lại (ghi trùng: doanh thu tính hai lần, một lượt mãi "chưa thu")
    if p ? 'bo_qua_canh_bao' and not coalesce((p->>'bo_qua_canh_bao')::boolean, false) then
      select * into v_cu from public.dich_vu_nhanh d0
      where d0.chi_nhanh_id = v_cn and d0.bien_so = v_bs and d0.ngay = v_ngay and d0.trang_thai = 'hieu_luc'
        and lower(trim(d0.dich_vu)) = lower(trim(p->>'dich_vu')) limit 1;
      if found then
        raise exception 'CANH_BAO: Xe % đã có lượt "%" ngày % (% đ). Ghi thêm một lượt nữa? (Thu tiền lượt đã có thì vào Thu chi → Phiếu thu, mục Thu dịch vụ nhanh)',
          public.bien_so_hien_thi(v_bs), v_cu.dich_vu, to_char(v_ngay, 'DD/MM/YYYY'), app.vnd(v_cu.so_tien);
      end if;
    end if;
  end if;

  insert into public.dich_vu_nhanh (chi_nhanh_id, ngay, bien_so, dich_vu, nguoi_lam, so_tien, xuat_hd, tao_boi, xe_id, khach_hang_id, so_km, to_id)
  values (v_cn, v_ngay, v_bs, trim(p->>'dich_vu'), v_nguoi,
          (p->>'so_tien')::numeric, coalesce((p->>'xuat_hd')::boolean, false), auth.uid(), v_xe, v_kh, v_km::int, v_to)
  returning id into v_id;

  -- Thu tiền ngay: phiếu thu gắn lượt dịch vụ, cùng giao dịch (lỗi thì cả lượt dịch vụ không ghi)
  if v_thu_ngay then
    perform public.lap_phieu_thu(jsonb_build_object(
      'tai_khoan_id', (p->>'tai_khoan_id')::bigint, 'muc_id', m.id, 'so_tien', (p->>'so_tien')::numeric, 'ngay', v_ngay,
      'noi_dung', 'Dịch vụ nhanh: ' || trim(p->>'dich_vu') || coalesce(' – ' || public.bien_so_hien_thi(v_bs), ''),
      'phan_bo', jsonb_build_array(jsonb_build_object('dich_vu_nhanh_id', v_id, 'so_tien', (p->>'so_tien')::numeric))));
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Quyền gọi hàm nội bộ mới; múi giờ Việt Nam cho hàm mới có dùng ngày giờ hiện tại
-- ---------------------------------------------------------------------
revoke execute on function app.chuan_hoa_vao_lai_lo(), app.ghi_lich_su_tai_khoan(), app.bo_to_khong_phai_truong_nhom(), app.nguoi_dang_lam()
  from public, anon;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%' or p.prosrc ilike '%localtimestamp%' or p.prosrc ilike '%current_timestamp%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ======================= 044_ra_soat_3b.sql =======================
-- =====================================================================
-- 044 (15/10/2026): sửa thêm sau khi rà lại 043 (tương thích ngược với bản thật)
--  1. lap_de_nghi_chi: giao diện cũ chỉ gửi "ngay" → kỳ chi phí lấy theo ngày đó (043 lỡ tính vào tháng hiện tại)
--  2. Nợ đầu kỳ nội bộ thuộc một chi nhánh (don_vi_lien_quan.chi_nhanh_id) – không cộng lặp ở mọi chi nhánh
--  3. Đơn vị liên quan: không dời ngày đầu kỳ qua phiếu đã ghi, không đổi nợ / ngày đầu kỳ khi đã có phiếu ở tháng chốt
--  4. Trả lại quyền đọc don_vi_lien_quan cho nhân viên như trước 043 (bản thật dùng bảng này cho ô chọn đơn vị);
--     việc ẩn nợ đầu kỳ với CVDV / kho chuyển sang 099 (chạy khi đưa lên)
--  5. Lương chưa trả cuối tháng trừ cả tạm ứng lương
--  6. giam_gia_lan chỉ đọc hồ sơ của chi nhánh được xem
--  7. chuyen_phan_bo: phiếu BH cũ chưa ghi hãng vẫn chuyển được
-- =====================================================================
alter table public.don_vi_lien_quan add column if not exists chi_nhanh_id text references public.chi_nhanh(id);
-- mặc định chi nhánh của người tạo (lỗi đọc phiên – vd chạy SQL trực tiếp – thì để trống: tính ở mọi chi nhánh như trước)
create or replace function app.chi_nhanh_mac_dinh() returns text
language plpgsql stable security definer set search_path = public as $$
begin
  return app.chi_nhanh();
exception when others then return null;
end $$;
revoke execute on function app.chi_nhanh_mac_dinh() from public, anon;
grant execute on function app.chi_nhanh_mac_dinh() to authenticated;
alter table public.don_vi_lien_quan alter column chi_nhanh_id set default app.chi_nhanh_mac_dinh();
update public.don_vi_lien_quan set chi_nhanh_id = coalesce((select id from public.chi_nhanh where id = 'TK'), (select min(id) from public.chi_nhanh))
where chi_nhanh_id is null;
comment on column public.don_vi_lien_quan.chi_nhanh_id is 'Chi nhánh giữ nợ đầu kỳ của đơn vị (044)';

create or replace function app.chan_doi_don_vi() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ngay date;
begin
  if (new.so_du_dau_ky, new.ngay_dau_ky) is not distinct from (old.so_du_dau_ky, old.ngay_dau_ky) then return new; end if;
  if exists (select 1 from public.phieu_thu_chi p
             join public.chot_thang c on c.chi_nhanh_id = p.chi_nhanh_id and c.thang >= date_trunc('month', p.ngay)::date
             where p.don_vi_lien_quan_id = old.id and p.trang_thai = 'hieu_luc') then
    raise exception '"%" đã có phiếu trong tháng đã chốt sổ: không đổi nợ đầu kỳ hay ngày đầu kỳ được. Ghi phiếu điều chỉnh ở tháng đang mở.', old.ten;
  end if;
  if new.ngay_dau_ky is not null and new.ngay_dau_ky > coalesce(old.ngay_dau_ky, '-infinity'::date) then
    select min(p.ngay) into v_ngay from public.phieu_thu_chi p
    where p.don_vi_lien_quan_id = old.id and p.trang_thai = 'hieu_luc' and p.ngay < new.ngay_dau_ky
      and p.ngay >= coalesce(old.ngay_dau_ky, '-infinity'::date);
    if v_ngay is not null then
      raise exception '"%" đã có phiếu ngày % – không dời ngày đầu kỳ sang % được (nợ sẽ bỏ sót phiếu đó). Chọn ngày đầu kỳ từ % trở về trước.',
        old.ten, to_char(v_ngay, 'DD/MM/YYYY'), to_char(new.ngay_dau_ky, 'DD/MM/YYYY'), to_char(v_ngay, 'DD/MM/YYYY');
    end if;
  end if;
  return new;
end $$;
revoke execute on function app.chan_doi_don_vi() from public, anon;
drop trigger if exists don_vi_lien_quan_chan_doi on public.don_vi_lien_quan;
create trigger don_vi_lien_quan_chan_doi before update of so_du_dau_ky, ngay_dau_ky on public.don_vi_lien_quan
  for each row execute function app.chan_doi_don_vi();

-- 4. Quyền đọc như trước 043 (030): mọi nhân viên + cổ đông + trưởng nhóm
alter policy "doc" on public.don_vi_lien_quan using ((select app.xem_nhu_nhan_vien()) or (select app.co_vai_tro('truong_nhom')));

-- 6.
drop policy if exists doc on public.giam_gia_lan;
create policy doc on public.giam_gia_lan for select to authenticated
  using ((select app.xem_nhu_nhan_vien())
         and exists (select 1 from public.ho_so h where h.id = ho_so_id and app.duoc_xem_chi_nhanh(h.chi_nhanh_id)));

create or replace view public.v_cong_no_noi_bo with (security_invoker=true) as
 SELECT id,
    ten,
    loai,
    hoat_dong,
    so_du_dau_ky,
    ngay_dau_ky,
    chi_nhanh_id,
    da_chi,
    da_thu,
    ngay_cuoi,
    so_du_dau_ky + da_chi - da_thu AS con_lai
   FROM ( SELECT dv.id,
            dv.ten,
            dv.loai,
            dv.hoat_dong,
            CASE WHEN coalesce(dv.chi_nhanh_id, c.chi_nhanh_id) = c.chi_nhanh_id THEN dv.so_du_dau_ky ELSE 0::numeric(14,0) END::numeric(14,0) AS so_du_dau_ky,
            dv.ngay_dau_ky,
            c.chi_nhanh_id,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'chi'::text AND p.trang_thai = 'hieu_luc'::text
                    AND p.ngay >= COALESCE(dv.ngay_dau_ky, '-infinity'::date)), 0::numeric) AS da_chi,
            COALESCE(( SELECT sum(p.so_tien) AS sum
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.loai = 'thu'::text AND p.trang_thai = 'hieu_luc'::text
                    AND p.ngay >= COALESCE(dv.ngay_dau_ky, '-infinity'::date)), 0::numeric) AS da_thu,
            ( SELECT max(p.ngay) AS max
                   FROM phieu_thu_chi p
                  WHERE p.don_vi_lien_quan_id = dv.id AND p.chi_nhanh_id = c.chi_nhanh_id AND p.trang_thai = 'hieu_luc'::text) AS ngay_cuoi
           FROM don_vi_lien_quan dv
             CROSS JOIN ( SELECT chi_nhanh.id AS chi_nhanh_id
                   FROM chi_nhanh) c
          WHERE (select app.co_vai_tro(VARIADIC ARRAY['giam_doc'::text, 'quan_ly'::text, 'ke_toan'::text, 'co_dong'::text])) AND app.duoc_xem_chi_nhanh(c.chi_nhanh_id)) x;
revoke all on public.v_cong_no_noi_bo from anon;
grant select on public.v_cong_no_noi_bo to authenticated;

create or replace function app.so_du_cuoi_thang(p_cn text, p_ngay date) returns jsonb
language sql stable security definer set search_path = public set jit = off as $$
  with quy as (
    select coalesce(sum(tk.so_du_dau_ky) filter (where tk.ngay_dau_ky <= p_ngay), 0)
      + coalesce((select sum(case when p.loai = 'thu' then p.so_tien when p.loai = 'chi' then -p.so_tien else 0 end)
                  from public.phieu_thu_chi p join public.tai_khoan_quy t2 on t2.id = p.tai_khoan_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and p.ngay >= t2.ngay_dau_ky), 0) as so_du
    from public.tai_khoan_quy tk where tk.chi_nhanh_id = p_cn),
  kho as (
    select coalesce(sum(l.so_luong * l.don_gia_von), 0)
      - coalesce((select sum(pd.gia_von) from public.phieu_xuat_dong pd join public.phieu_xuat px on px.id = pd.phieu_id
                  where px.chi_nhanh_id = p_cn and px.trang_thai = 'hieu_luc' and px.ngay <= p_ngay), 0) as ton
    from public.lo_kho l where l.chi_nhanh_id = p_cn and l.ngay <= p_ngay),
  hs as (
    select h.id, h.khau_tru_giam_tru,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, true, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(public.tien_dong_co_vat(m.gia_duyet, m.xuat_hd, m.ngay_duyet, m.ty_le_vat)) filter (where m.nguoi_tra = 'khach'), 0) as kh
    from public.ho_so h join public.hang_muc m on m.ho_so_id = h.id
    where h.chi_nhanh_id = p_cn and h.trang_thai <> 'huy' and h.loai <> 'bao_hanh'
      and m.trang_thai in ('duyet','dang_lam','xong') and m.ngay_duyet <= p_ngay
    group by h.id),
  gg as (
    select g.ho_so_id, sum(g.so_tien) as gg
    from public.giam_gia_lan g join public.ho_so h on h.id = g.ho_so_id
    where h.chi_nhanh_id = p_cn and h.trang_thai <> 'huy' and g.ngay <= p_ngay
    group by g.ho_so_id),
  tra as (
    select pb.ho_so_id,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'bao_hiem'), 0) as bh,
      coalesce(sum(case when p.loai = 'thu' then pb.so_tien else -pb.so_tien end) filter (where pb.nguoi_tra = 'khach'), 0) as kh
    from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.ngay <= p_ngay and pb.ho_so_id is not null
    group by pb.ho_so_id),
  -- cả hồ sơ chưa duyệt giá mà đã thu cọc (hoặc đã hủy còn giữ cọc): nợ khách âm = phải trả lại khách
  no as (
    select coalesce(hs.bh, 0) - coalesce(hs.khau_tru_giam_tru, 0) - coalesce(tra.bh, 0) as no_bh,
      coalesce(hs.kh, 0) + coalesce(hs.khau_tru_giam_tru, 0) - coalesce(gg.gg, 0) - coalesce(tra.kh, 0) as no_kh
    from hs full join tra on tra.ho_so_id = hs.id
    left join gg on gg.ho_so_id = coalesce(hs.id, tra.ho_so_id)),
  ncc as (
    select coalesce((select sum(pn.tong_tien) from public.phieu_nhap pn
                     where pn.chi_nhanh_id = p_cn and pn.trang_thai <> 'huy' and pn.ngay <= p_ngay), 0)
      - coalesce((select sum(p.so_tien) from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat = 'tra_ncc'
                    and p.nha_cung_cap_id is not null and p.ngay <= p_ngay), 0) as phai_tra),
  bh_cc as (
    select coalesce(sum(p.so_tien - coalesce((select sum(pb.so_tien) from public.phan_bo pb where pb.phieu_id = p.id), 0)), 0) as tien
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'thu' and m.tinh_chat = 'thu_bao_hiem' and p.ngay <= p_ngay),
  dvn as (
    select coalesce(sum(greatest(d.so_tien - coalesce((select sum(pb.so_tien) from public.phan_bo pb join public.phieu_thu_chi p on p.id = pb.phieu_id
                                                       where pb.dich_vu_nhanh_id = d.id and p.trang_thai = 'hieu_luc' and p.loai = 'thu' and p.ngay <= p_ngay), 0), 0)), 0) as tien
    from public.dich_vu_nhanh d where d.chi_nhanh_id = p_cn and d.trang_thai = 'hieu_luc' and d.ngay <= p_ngay),
  -- chi phí đã tính vào lãi lỗ đến tháng này (theo "chi phí của tháng") mà chi sau ngày cuối tháng
  cp_sau as (
    select coalesce(sum(p.so_tien), 0) as tien
    from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
    where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat = 'chi_phi'
      and p.ky_chi_phi is not null and p.ky_chi_phi <= p_ngay and p.ngay > p_ngay),
  -- lương theo bảng lương (đến tháng này) trừ phiếu trả lương (từ tháng có bảng lương đầu tiên)
  luong as (
    select greatest(0,
      coalesce((select sum(bl.tong_luong) from public.bang_luong_thang bl where bl.chi_nhanh_id = p_cn and bl.thang <= p_ngay), 0)
      - coalesce((select sum(p.so_tien) from public.phieu_thu_chi p join public.muc_thu_chi m on m.id = p.muc_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and m.tinh_chat in ('tra_luong','tam_ung') and p.ngay <= p_ngay
                    and p.ngay >= (select min(bl.thang) from public.bang_luong_thang bl where bl.chi_nhanh_id = p_cn)), 0)) as tien),
  -- hoa hồng GDV đã tính vào lãi lỗ (đến tháng này) mà chưa chi
  hh as (
    select coalesce(sum(greatest(h.hoa_hong_gdv - coalesce((
        select sum(p.so_tien) from public.phieu_thu_chi p join public.de_nghi_chi dn on dn.id = p.de_nghi_chi_id
        join public.muc_thu_chi m on m.id = p.muc_id
        where dn.ho_so_id = h.id and m.tinh_chat = 'tra_hoa_hong' and p.trang_thai = 'hieu_luc' and p.loai = 'chi' and p.ngay <= p_ngay), 0), 0)), 0) as tien
    from public.ho_so h
    where h.chi_nhanh_id = p_cn and h.hoa_hong_gdv is not null and h.trang_thai <> 'huy' and not h.tu_excel
      and coalesce(h.hoa_hong_ky, (select date_trunc('month', min(m.ngay_duyet))::date from public.hang_muc m
                                   where m.ho_so_id = h.id and m.trang_thai in ('duyet','dang_lam','xong'))) <= p_ngay),
  nb as (
    select coalesce(sum(dv.so_du_dau_ky) filter (where dv.ngay_dau_ky is null or dv.ngay_dau_ky <= p_ngay), 0)
      + coalesce((select sum(case when p.loai = 'chi' then p.so_tien else -p.so_tien end)
                  from public.phieu_thu_chi p join public.don_vi_lien_quan d2 on d2.id = p.don_vi_lien_quan_id
                  where p.chi_nhanh_id = p_cn and p.trang_thai = 'hieu_luc' and p.loai in ('thu','chi') and p.ngay <= p_ngay
                    and p.ngay >= coalesce(d2.ngay_dau_ky, '-infinity'::date)), 0) as tien
    from public.don_vi_lien_quan dv where coalesce(dv.chi_nhanh_id, p_cn) = p_cn)   -- 044: nợ đầu kỳ thuộc một chi nhánh
  select jsonb_build_object(
    'ngay', p_ngay,
    'so_du_quy', (select round(so_du) from quy),
    'ton_kho', (select round(ton) from kho),
    'phai_thu_khach', (select round(coalesce(sum(greatest(no_kh, 0)), 0)) from no),
    'phai_thu_bh', (select round(coalesce(sum(greatest(no_bh, 0)), 0)) from no),
    'khach_tra_du', (select round(coalesce(sum(greatest(-no_kh, 0)), 0)) from no),
    'phai_tra_ncc', (select round(phai_tra) from ncc),
    'bh_chua_chia', (select round(tien) from bh_cc),
    'phai_thu_dvn', (select round(tien) from dvn),
    'luong_chua_tra', (select round(tien) from luong),
    'hoa_hong_chua_chi', (select round(tien) from hh),
    'chi_phi_chi_sau', (select round(tien) from cp_sau),
    'chi_phi_phai_tra', (select round(tien) from luong) + (select round(tien) from hh) + (select round(tien) from cp_sau),
    'no_noi_bo_rong', (select round(tien) from nb))
$$;
revoke execute on function app.so_du_cuoi_thang(text, date) from public, anon;

create or replace function public.lap_de_nghi_chi(p jsonb) returns bigint
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh()); m public.muc_thu_chi; v_id bigint;
  v_ngay date := current_date; v_ky date; v_noi_dung text; v_tien numeric := coalesce((p->>'so_tien')::numeric, 0);
  v_hoi boolean := p ? 'bo_qua_canh_bao' and not coalesce((p->>'bo_qua_canh_bao')::boolean, false);
  h public.ho_so; v_giu numeric; v_cho numeric; v_nhap numeric; v_tra numeric; v_ncc text;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  select * into m from public.muc_thu_chi where id = (p->>'muc_id')::bigint;
  if not found or m.loai <> 'chi' then raise exception 'Chưa chọn mục chi.'; end if;
  if v_tien <= 0 then raise exception 'Thiếu số tiền.'; end if;
  if nullif(trim(p->>'noi_dung'),'') is null then raise exception 'Ghi nội dung chi.'; end if;
  if (m.can_ho_so or m.tinh_chat in ('tra_hoa_hong','tra_coc')) and (p->>'ho_so_id') is null then
    raise exception 'Mục "%" phải gắn hồ sơ xe.', m.ten; end if;
  if m.tinh_chat = 'tra_hoa_hong' and (p->>'gdv_id') is null then raise exception 'Chọn giám định viên nhận hoa hồng.'; end if;
  if m.tinh_chat = 'tra_ncc' and (p->>'nha_cung_cap_id') is null then raise exception 'Chọn nhà cung cấp.'; end if;
  if m.tinh_chat = 'tra_noi_bo' and (p->>'don_vi_lien_quan_id') is null then raise exception 'Chọn đơn vị liên quan.'; end if;
  if coalesce((p->>'vat_dau_vao')::numeric, 0) > v_tien then raise exception 'VAT đầu vào lớn hơn số tiền.'; end if;

  if m.tinh_chat = 'tra_coc' then
    h := app.lay_ho_so((p->>'ho_so_id')::bigint);          -- khóa hồ sơ: hai người cùng lập không vượt được
    v_giu := app.tien_dang_giu(h.id); v_cho := app.dang_de_nghi_tra_coc(h.id);
    if v_tien > v_giu - v_cho then
      raise exception 'Hồ sơ % đang giữ % đ của khách%: chỉ lập đề nghị trả lại tối đa % đ.', h.ma, app.vnd(v_giu),
        case when v_cho > 0 then format(' (đã có đề nghị trả lại %s đ chờ duyệt / chờ chi)', app.vnd(v_cho)) else '' end,
        app.vnd(greatest(v_giu - v_cho, 0));
    end if;
  end if;

  if m.tinh_chat = 'tra_ncc' and v_hoi then
    perform pg_advisory_xact_lock(hashtext('tra_ncc_' || v_cn || '_' || (p->>'nha_cung_cap_id')));
    select ten into v_ncc from public.nha_cung_cap where id = (p->>'nha_cung_cap_id')::bigint;
    select coalesce(sum(pn.tong_tien), 0) into v_nhap from public.phieu_nhap pn
    where pn.nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint and pn.chi_nhanh_id = v_cn and pn.trang_thai <> 'huy';
    select coalesce(sum(pt.so_tien), 0) into v_tra from public.phieu_thu_chi pt join public.muc_thu_chi m2 on m2.id = pt.muc_id
    where pt.nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint and pt.chi_nhanh_id = v_cn and pt.loai = 'chi' and pt.trang_thai = 'hieu_luc' and m2.tinh_chat = 'tra_ncc';
    select coalesce(sum(d.so_tien), 0) into v_cho from public.de_nghi_chi d join public.muc_thu_chi m2 on m2.id = d.muc_id
    where d.nha_cung_cap_id = (p->>'nha_cung_cap_id')::bigint and d.chi_nhanh_id = v_cn and m2.tinh_chat = 'tra_ncc' and d.trang_thai in ('cho_duyet','da_duyet');
    if v_tien > v_nhap - v_tra - v_cho then
      raise exception 'CANH_BAO: %: hàng đã nhập % đ, đã trả % đ, đang đề nghị chi % đ → còn nợ % đ. Đề nghị % đ vượt số còn nợ (trả trước, hoặc đã có người lập rồi?). Vẫn lập?',
        coalesce(v_ncc, 'Nhà cung cấp'), app.vnd(v_nhap), app.vnd(v_tra), app.vnd(v_cho), app.vnd(v_nhap - v_tra - v_cho), app.vnd(v_tien);
    end if;
  end if;

  if m.tinh_chat = 'tra_hoa_hong' and v_hoi then
    select * into h from public.ho_so where id = (p->>'ho_so_id')::bigint;
    select coalesce(sum(d.so_tien), 0) into v_cho from public.de_nghi_chi d join public.muc_thu_chi m2 on m2.id = d.muc_id
    where d.ho_so_id = h.id and m2.tinh_chat = 'tra_hoa_hong' and d.trang_thai in ('cho_duyet','da_duyet','da_chi');
    if h.hoa_hong_gdv is null then
      raise exception 'CANH_BAO: Hồ sơ % chưa ghi hoa hồng GDV (kế toán nhập ở mục 8 của hồ sơ để tính vào lãi lỗ). Vẫn lập đề nghị chi?', h.ma;
    elsif v_tien + v_cho > h.hoa_hong_gdv then
      raise exception 'CANH_BAO: Hoa hồng ghi ở hồ sơ % là % đ, đã chi / đã đề nghị % đ – đề nghị này % đ làm vượt số đã ghi. Vẫn lập?',
        h.ma, app.vnd(h.hoa_hong_gdv), app.vnd(v_cho), app.vnd(v_tien);
    end if;
  end if;

  -- Kỳ chi phí: chỉ với khoản tính vào lãi lỗ; khác tháng lập thì ghi rõ vào nội dung để ai cũng thấy
  v_noi_dung := trim(p->>'noi_dung');
  if m.tinh_chat = 'chi_phi' then
    -- 044: giao diện cũ (bản thật) chỉ gửi ô Ngày → dùng ngày đó làm kỳ chi phí như trước 043 (ngày đề nghị vẫn là hôm nay)
    v_ky := app.kiem_ky_chi_phi(v_cn, coalesce((p->>'ky_chi_phi')::date, case when (p->>'ngay')::date <= v_ngay then (p->>'ngay')::date end, v_ngay));
    if v_ky <> date_trunc('month', v_ngay)::date then
      v_noi_dung := v_noi_dung || ' (chi phí tháng ' || to_char(v_ky, 'MM/YYYY') || ')'; end if;
  end if;

  insert into public.de_nghi_chi (chi_nhanh_id, ngay, nguoi_de_nghi, muc_id, so_tien, vat_dau_vao, noi_dung, nguoi_nhan,
    ho_so_id, nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, ky_chi_phi)
  values (v_cn, v_ngay, auth.uid(), m.id, v_tien,
    coalesce((p->>'vat_dau_vao')::numeric, 0), v_noi_dung, nullif(trim(p->>'nguoi_nhan'),''),
    (p->>'ho_so_id')::bigint, (p->>'nha_cung_cap_id')::bigint, (p->>'gdv_id')::bigint, (p->>'don_vi_lien_quan_id')::bigint, v_ky)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.chuyen_phan_bo(p_phieu bigint, p_tu_ho_so bigint, p_den_ho_so bigint, p_so_tien numeric, p_ly_do text) returns void
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare r public.phieu_thu_chi; m public.muc_thu_chi; a public.ho_so; b public.ho_so; v_nguoi text; v_da numeric; t record;
  pb record; v_con numeric;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_phieu for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.loai <> 'thu' or r.trang_thai <> 'hieu_luc' then raise exception 'Chỉ chuyển phần chia của phiếu thu còn hiệu lực.'; end if;
  select * into m from public.muc_thu_chi where id = r.muc_id;
  if m.tinh_chat not in ('thu_bao_hiem','thu_khach','thu_coc') then raise exception 'Phiếu này không chia vào xe.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do (ví dụ: chia nhầm xe).'; end if;
  if p_so_tien is null or p_so_tien <= 0 then raise exception 'Số tiền chuyển phải lớn hơn 0.'; end if;
  if p_tu_ho_so is null or p_den_ho_so is null or p_tu_ho_so = p_den_ho_so then raise exception 'Chọn xe nhận khác xe chuyển đi.'; end if;
  -- khóa hai hồ sơ theo thứ tự id: hai người làm cùng lúc không chờ nhau mãi
  if p_tu_ho_so < p_den_ho_so then a := app.lay_ho_so(p_tu_ho_so); b := app.lay_ho_so(p_den_ho_so);
  else b := app.lay_ho_so(p_den_ho_so); a := app.lay_ho_so(p_tu_ho_so); end if;
  v_nguoi := case when m.tinh_chat = 'thu_bao_hiem' then 'bao_hiem' else 'khach' end;
  select coalesce(sum(so_tien), 0) into v_da from public.phan_bo where phieu_id = p_phieu and ho_so_id = a.id and nguoi_tra = v_nguoi;
  if p_so_tien > v_da then raise exception 'Phiếu chỉ chia % đ vào hồ sơ % – không chuyển % đ được.', app.vnd(v_da), a.ma, app.vnd(p_so_tien); end if;
  if b.trang_thai = 'huy' then raise exception 'Hồ sơ % đã hủy.', b.ma; end if;
  if b.chi_nhanh_id <> r.chi_nhanh_id then raise exception 'Hồ sơ % không thuộc chi nhánh của phiếu.', b.ma; end if;
  if v_nguoi = 'bao_hiem' and r.hang_bh_id is not null and b.hang_bh_id is distinct from r.hang_bh_id then   -- 044: phiếu cũ chưa ghi hãng thì không kiểm hãng (như phan_bo_phieu)
    raise exception 'Hồ sơ % không phải xe của hãng bảo hiểm đã trả phiếu này.', b.ma; end if;
  select * into t from app.tien_ho_so(b.id);
  if v_nguoi = 'bao_hiem' and p_so_tien > t.con_no_bh then
    raise exception 'Hồ sơ % chỉ còn bảo hiểm nợ % đ.', b.ma, app.vnd(greatest(t.con_no_bh, 0)); end if;
  if m.tinh_chat = 'thu_khach' and p_so_tien > t.con_no_khach then
    raise exception 'Hồ sơ % chỉ còn khách nợ % đ.', b.ma, app.vnd(greatest(t.con_no_khach, 0)); end if;
  v_con := p_so_tien;
  for pb in select id, so_tien from public.phan_bo where phieu_id = p_phieu and ho_so_id = a.id and nguoi_tra = v_nguoi order by id desc for update loop
    exit when v_con <= 0;
    if pb.so_tien <= v_con then delete from public.phan_bo where id = pb.id; v_con := v_con - pb.so_tien;
    else update public.phan_bo set so_tien = so_tien - v_con where id = pb.id; v_con := 0; end if;
  end loop;
  insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (p_phieu, b.id, v_nguoi, p_so_tien);
  perform app.ghi_nhat_ky(a.id, a.trang_thai, a.trang_thai, format('Chuyển %s đ của phiếu thu ngày %s sang hồ sơ %s: %s',
    app.vnd(p_so_tien), to_char(r.ngay, 'DD/MM/YYYY'), b.ma, trim(p_ly_do)));
  perform app.ghi_nhat_ky(b.id, b.trang_thai, b.trang_thai, format('Nhận %s đ của phiếu thu ngày %s chuyển từ hồ sơ %s: %s',
    app.vnd(p_so_tien), to_char(r.ngay, 'DD/MM/YYYY'), a.ma, trim(p_ly_do)));
  perform app.cap_nhat_dong(a.id);
  perform app.cap_nhat_dong(b.id);
end $$;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ======================= 045_chi_nhanh_phi.sql (phần hàm) =======================
-- =====================================================================
-- 045: Chi nhánh Phan Huy Ích (PHI) + giám đốc chuyển chi nhánh làm việc
--  - Thêm chi nhánh PHI (hạch toán độc lập như Tô Ký: hồ sơ, thu chi, kho,
--    lương, chốt tháng… đều theo chi_nhanh_id; mã chứng từ tự có tiền tố PHI-).
--  - Một tài khoản quỹ "Tiền mặt" (mặc định) để PHI ghi được phiếu ngay;
--    kế toán PHI thêm tài khoản ngân hàng ở Danh mục.
--  - Giám đốc có nút chọn chi nhánh: public.doi_chi_nhanh_lam_viec(p_cn) đổi
--    nhan_vien.chi_nhanh_id của chính giám đốc → app.chi_nhanh() (mặc định của
--    mọi lệnh ghi và báo cáo) theo chi nhánh đang chọn. Nhân viên khác và cổ đông
--    vẫn gắn cố định một chi nhánh.
--  - app.nhan_vien_dau: giám đốc là người dự phòng của MỌI chi nhánh (trước đây
--    chỉ chi nhánh giám đốc đang gắn → PHI không có ai nhận việc khi giám đốc
--    đang chọn Tô Ký). Với một chi nhánh như hiện nay kết quả không đổi.
-- Tương thích ngược: chỉ thêm dữ liệu / hàm mới; giao diện cũ không gọi hàm mới.
-- =====================================================================

-- (Tệp cài đặt cho gara mới: KHÔNG thêm chi nhánh PHI / tài khoản quỹ của PHI – chỉ lấy phần hàm.)

create or replace function app.nhan_vien_dau(p_vai_tro text, p_chi_nhanh text)
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.nhan_vien
  where hoat_dong and (p_vai_tro = any(vai_tro) or 'giam_doc' = any(vai_tro))
    and (chi_nhanh_id = p_chi_nhanh or chi_nhanh_id is null or 'giam_doc' = any(vai_tro))
  order by (p_vai_tro = any(vai_tro)) desc, (chi_nhanh_id is not distinct from p_chi_nhanh) desc,
           (chi_nhanh_id is null), ho_ten limit 1
$$;

create or replace function public.doi_chi_nhanh_lam_viec(p_cn text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.chi_nhanh;
begin
  if not app.co_vai_tro('giam_doc') then
    raise exception 'Chỉ giám đốc được chuyển chi nhánh làm việc.';
  end if;
  select * into r from public.chi_nhanh where id = p_cn;
  if not found or not r.hoat_dong then
    raise exception 'Chi nhánh không hợp lệ.';
  end if;
  update public.nhan_vien set chi_nhanh_id = p_cn where id = auth.uid();
  return jsonb_build_object('chi_nhanh_id', r.id, 'ten', r.ten);
end $$;

revoke all on function public.doi_chi_nhanh_lam_viec(text) from public, anon;
grant execute on function public.doi_chi_nhanh_lam_viec(text) to authenticated;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ======================= 046_xoa_tai_khoan.sql =======================
-- =====================================================================
-- 046: Giám đốc xóa tài khoản nhân viên
--  - Chỉ xóa được tài khoản CHƯA có dữ liệu nào trong phần mềm (tạo nhầm, chưa dùng):
--    kiểm mọi cột uuid của các bảng public (người tạo, người duyệt, người làm bước
--    tiếp theo, nhật ký…). Đã có dữ liệu → báo khóa tài khoản (bỏ "Đang làm") để giữ
--    lịch sử ai làm gì.
--  - Không xóa chính mình, không xóa tài khoản giám đốc.
--  - Xóa auth.users → nhan_vien, auth.identities, auth.sessions xóa theo (on delete cascade).
-- Tương thích ngược: chỉ thêm hàm mới.
-- =====================================================================

create or replace function public.xoa_tai_khoan_nhan_vien(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  nv public.nhan_vien;
  c record;
  v_co boolean;
  v_noi text[] := '{}';
begin
  if not app.co_vai_tro('giam_doc') then
    raise exception 'Chỉ giám đốc được xóa tài khoản.' using errcode = '42501';
  end if;
  if p_id = auth.uid() then
    raise exception 'Không tự xóa tài khoản của chính mình được.';
  end if;
  select * into nv from public.nhan_vien where id = p_id for update;
  if not found then
    raise exception 'Không tìm thấy tài khoản.';
  end if;
  if 'giam_doc' = any(nv.vai_tro) then
    raise exception 'Không xóa tài khoản giám đốc được.';
  end if;

  for c in
    select col.table_name, col.column_name
    from information_schema.columns col
    join information_schema.tables t on t.table_schema = col.table_schema and t.table_name = col.table_name
    where col.table_schema = 'public' and t.table_type = 'BASE TABLE' and col.data_type = 'uuid'
      and not (col.table_name = 'nhan_vien' and col.column_name = 'id')
  loop
    execute format('select exists (select 1 from public.%I where %I = $1)', c.table_name, c.column_name)
      into v_co using p_id;
    if v_co then v_noi := v_noi || c.table_name; end if;
  end loop;

  if cardinality(v_noi) > 0 then
    raise exception 'Tài khoản % đã có dữ liệu trong phần mềm nên không xóa được (để giữ lịch sử ai làm gì). Muốn ngừng cho đăng nhập: bấm "Sửa quyền", bỏ chọn "Đang làm" để khóa tài khoản.',
      nv.ho_ten using detail = array_to_string(array(select distinct unnest(v_noi)), ', ');
  end if;

  delete from public.nhan_vien where id = p_id;
  delete from auth.users where id = p_id;
  return jsonb_build_object('id', p_id, 'ho_ten', nv.ho_ten);
end $$;

revoke all on function public.xoa_tai_khoan_nhan_vien(uuid) from public, anon;
grant execute on function public.xoa_tai_khoan_nhan_vien(uuid) to authenticated;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';

-- ======================= 047_anh_bat_buoc.sql =======================
-- =====================================================================
-- 047: Ảnh / file bắt buộc ở các bước + CVDV nghiệm thu KCS (anh Thuận yêu cầu 15/10 15:09)
--  1. Tiếp nhận: 6 ảnh có tên – 4 quanh xe (nx_truoc, nx_sau, nx_trai, nx_phai) + 2 nội thất
--     (nt_truoc: táp lô, nt_sau: hàng ghế sau). Ảnh tải sau khi tạo hồ sơ, nên máy chủ kiểm ở bước kế tiếp:
--     lập báo giá (xe thường) và lập lệnh sửa chữa (cả hồ sơ bảo hành).
--  2. Báo giá: MỖI lần lưu (cả bổ sung) phải có ảnh / PDF báo giá (bước 'bao_gia') tải lên sau lần lưu báo giá trước
--     (ho_so.bao_gia_luc).
--  3. Duyệt giá xe bảo hiểm: phải có ảnh / file duyệt giá (bước 'duyet_gia') tải lên sau lần báo giá gần nhất.
--  4. KCS đạt: tối thiểu 6 ảnh KCS (tổng các lần) + sau lần chưa đạt có ít nhất 1 ảnh mới (giữ quy định 043).
--  5. CVDV được ký KCS (cùng quản lý chung, giám đốc).
-- Tương thích ngược: chỉ hồ sơ tạo từ giao diện mới (gửi bat_buoc_anh) mới bị bắt (ho_so.bat_buoc_anh); hồ sơ do giao diện
-- cũ (bản thật đang chạy) tạo vẫn như trước. Không đổi tham số hàm nào.
-- =====================================================================

alter table public.ho_so add column if not exists bat_buoc_anh boolean not null default false;
alter table public.ho_so add column if not exists bao_gia_luc timestamptz;

-- Tên 6 ảnh nhận xe (dùng chung cho thông báo)
create or replace function app.anh_nhan_xe_thieu(p_ho_so bigint) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(t.ten order by t.thu_tu), '{}')
  from (values (1, 'nx_truoc', 'phía trước'), (2, 'nx_sau', 'phía sau'), (3, 'nx_trai', 'bên trái'), (4, 'nx_phai', 'bên phải'),
               (5, 'nt_truoc', 'nội thất phía trước'), (6, 'nt_sau', 'nội thất phía sau')) as t(thu_tu, buoc, ten)
  where not exists (select 1 from public.ho_so_tep f where f.ho_so_id = p_ho_so and f.buoc = t.buoc)
$$;
revoke all on function app.anh_nhan_xe_thieu(bigint) from public, anon;

create or replace function app.yeu_cau_anh_nhan_xe(p_ho_so bigint) returns void
language plpgsql stable security definer set search_path = public as $$
declare v text[] := app.anh_nhan_xe_thieu(p_ho_so);
begin
  if cardinality(v) > 0 then
    raise exception 'Chưa đủ 6 ảnh nhận xe – còn thiếu: %. Chụp bổ sung ở mục "Ảnh nhận xe" của hồ sơ.', array_to_string(v, ', ');
  end if;
end $$;
revoke all on function app.yeu_cau_anh_nhan_xe(bigint) from public, anon;

-- them_tep: thêm bước bao_gia và 6 ảnh nhận xe
CREATE OR REPLACE FUNCTION public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.ho_so; v_id bigint; v_goc text;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  v_goc := h.chi_nhanh_id || '/' || h.ma || '/';
  if p_duong_dan is null or left(p_duong_dan, length(v_goc)) <> v_goc or position('..' in p_duong_dan) > 0 then
    raise exception 'Tệp không thuộc thư mục của hồ sơ % – tải lại ảnh từ trang hồ sơ.', h.ma;
  end if;
  if p_buoc not in ('tiep_nhan','duyet_gia','phat_sinh','kcs','giao_xe','ho_so_bh','khac',
                    'bao_gia','nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau') then
    raise exception 'Bước của tệp không hợp lệ.';
  end if;
  if coalesce(p_loai, 'anh') not in ('anh','bien_ban') then raise exception 'Loại tệp không hợp lệ.'; end if;
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, coalesce(p_loai, 'anh'), p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $function$;

-- tiep_nhan_xe: ghi cờ bat_buoc_anh
CREATE OR REPLACE FUNCTION public.tiep_nhan_xe(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare
  v_cn text := coalesce(p->>'chi_nhanh_id', app.chi_nhanh());
  v_ngay timestamptz := coalesce((p->>'ngay_vao')::timestamptz, now());
  v_bs text := public.bien_so_gon(p->>'bien_so');
  v_dt text := regexp_replace(coalesce(p->>'dien_thoai',''), '[^0-9]', '', 'g');
  v_nguon text := p->>'nguon_tt';
  v_gdv public.giam_dinh_vien;
  v_kh bigint; v_xe bigint; v_ma text; v_goc text; v_n int; v_id bigint; v_mo text;
  v_loai text := coalesce(p->>'loai', 'sua_chua');
  v_km text := nullif(regexp_replace(coalesce(p->>'so_km',''), '[^0-9]', '', 'g'), '');
  v_bao_hanh boolean := v_loai = 'bao_hanh';
  v_hm jsonb := case when jsonb_typeof(p->'hang_muc') = 'array' then p->'hang_muc' else '[]'::jsonb end;
  d jsonb; v_so_hm int := 0;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  if v_cn is null then raise exception 'Tài khoản chưa gắn chi nhánh.'; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  -- Bảo hành: làm lại miễn phí, không liên quan bảo hiểm → luôn là nguồn "khách", không hãng BH, không GDV
  if v_bao_hanh then v_nguon := 'khach'; end if;

  if nullif(trim(p->>'ten_khach'),'') is null then raise exception 'Thiếu tên khách.'; end if;
  if v_dt !~ '^0[0-9]{9}$' then raise exception 'Số điện thoại phải đủ 10 số, bắt đầu bằng 0.'; end if;
  if (p->>'dong_xe_id') is null then raise exception 'Chưa chọn loại xe.'; end if;
  if v_nguon not in ('bao_hiem','khach','bao_hiem_khach') or v_nguon is null then
    raise exception 'Chưa chọn bảo hiểm nào hay khách lẻ.'; end if;
  if nullif(trim(p->>'tinh_trang_xe'),'') is null then raise exception 'Ghi yêu cầu của khách hàng.'; end if;
  if nullif(trim(p->>'tu_van'),'') is null then raise exception 'Thiếu mục những gì có thể tư vấn (ghi "Không" nếu không có).'; end if;
  if v_nguon <> 'khach' then
    if (p->>'hang_bh_id') is null then raise exception 'Chưa chọn hãng bảo hiểm.'; end if;
    -- 036: giám định viên để trống được (hãng cử sau); bắt buộc trước khi nhập kết quả duyệt giá
    if (p->>'gdv_id') is not null then
      select * into v_gdv from public.giam_dinh_vien where id = (p->>'gdv_id')::bigint;
      if v_gdv.la_cho_them and nullif(trim(p->>'gdv_ten_tam'),'') is null then
        raise exception 'Chọn "GDV mới – chờ thêm" thì phải ghi tên giám định viên.';
      end if;
    end if;
  end if;
  if v_bs is not null and v_bs !~ '^[0-9]{2}[A-Z]{1,2}[0-9]?[0-9]{4,5}$' then
    raise exception 'Biển số "%" không đúng dạng (ví dụ 50H-923.61).', p->>'bien_so';
  end if;
  if v_km is null and coalesce((p->>'bat_buoc_km')::boolean, false) then raise exception 'Ghi số km (ODD) của xe.'; end if;
  if length(v_km) > 7 then raise exception 'Số km (ODD) không đúng.'; end if;
  if v_bao_hanh and (p->>'ho_so_goc_id') is null then
    raise exception 'Hồ sơ bảo hành phải chọn hồ sơ cũ.'; end if;
  if v_bao_hanh then
    for d in select * from jsonb_array_elements(v_hm) loop
      if nullif(trim(d->>'ten'),'') is null then raise exception 'Hạng mục bảo hành thiếu nội dung.'; end if;
      v_so_hm := v_so_hm + 1;
    end loop;
    if v_so_hm > 0 then perform app.yeu_cau_thang_mo(v_cn, current_date); end if;
  end if;

  -- 041: hai người tiếp nhận cùng SĐT / cùng xe / cùng lúc → người sau chờ người trước ghi xong (không lỗi trùng khóa)
  perform pg_advisory_xact_lock(hashtext('khach_' || v_dt));
  if v_bs is not null then perform pg_advisory_xact_lock(hashtext('xe_' || v_bs)); end if;

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

  if v_bao_hanh and not exists (select 1 from public.ho_so where id = (p->>'ho_so_goc_id')::bigint and xe_id = v_xe) then
    raise exception 'Hồ sơ cũ không phải của xe này.';
  end if;

  -- Mã hồ sơ: TK-2610-50H92361, trùng trong tháng thì thêm -2, -3…; chưa có biển: TK-2610-KBS01
  v_goc := v_cn || '-' || to_char(v_ngay at time zone 'Asia/Ho_Chi_Minh', 'YYMM') || '-';
  perform pg_advisory_xact_lock(hashtext('ma_ho_so_' || v_goc));
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
    hang_bh_id, gdv_id, gdv_ten_tam, han_bao_hiem, han_bh_than_vo, tinh_trang_xe, tu_van, so_km, tao_boi)
  values (v_ma, v_cn, v_loai, (p->>'ho_so_goc_id')::bigint, v_xe, v_kh, v_ngay, v_nguon,
    case when v_nguon <> 'khach' then (p->>'hang_bh_id')::bigint end,
    case when v_nguon <> 'khach' then (p->>'gdv_id')::bigint end,
    case when v_gdv.la_cho_them then trim(p->>'gdv_ten_tam') end,
    (p->>'han_bao_hiem')::date, (p->>'han_bh_than_vo')::date, trim(p->>'tinh_trang_xe'), trim(p->>'tu_van'), v_km::int, auth.uid())
  returning id into v_id;

  -- Bản thật chưa chạy 008 còn cột van_phong_bh_id: giao diện cũ gửi lên thì vẫn lưu (008 xóa cột thì bỏ qua)
  if p ? 'van_phong_bh_id' and exists (select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'ho_so' and column_name = 'van_phong_bh_id') then
    execute 'update public.ho_so set van_phong_bh_id = $1 where id = $2' using (p->>'van_phong_bh_id')::bigint, v_id;
  end if;

  perform app.ghi_nhat_ky(v_id, null, 'tiep_nhan', case when v_bao_hanh then 'Tiếp nhận xe bảo hành' else 'Tiếp nhận xe' end);

  -- Bảo hành (036): hạng mục làm lại miễn phí, coi như đã duyệt → lập lệnh sửa chữa được ngay
  if v_bao_hanh and v_so_hm > 0 then
    for d in select * from jsonb_array_elements(v_hm) loop
      insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, xuat_hd, trang_thai, gia_duyet, ngay_duyet)
      values (v_id, 0, trim(d->>'ten'), coalesce(nullif(d->>'nhom',''), 'dong_son'), 'khach', 0, false, 'duyet', 0, current_date);
    end loop;
    perform app.doi_trang_thai(v_id, 'da_duyet', 'Bảo hành ' || v_so_hm || ' hạng mục – không báo giá, không duyệt giá');
  end if;
  -- 047: giao diện mới gửi bat_buoc_anh → hồ sơ này bắt 6 ảnh nhận xe, file báo giá / duyệt giá, 6 ảnh KCS
  if coalesce((p->>'bat_buoc_anh')::boolean, false) then
    update public.ho_so set bat_buoc_anh = true where id = v_id;
  end if;
  return jsonb_build_object('id', v_id, 'ma', v_ma, 'chi_nhanh_id', v_cn);
end $function$;

-- lap_bao_gia
CREATE OR REPLACE FUNCTION public.lap_bao_gia(p_ho_so bigint, dong jsonb, p_vat numeric)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
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

  -- 047: hồ sơ bắt ảnh → đủ 6 ảnh nhận xe và mỗi lần lưu báo giá phải có ảnh / file báo giá mới tải lên
  if h.bat_buoc_anh then
    perform app.yeu_cau_anh_nhan_xe(p_ho_so);
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'bao_gia'
                   and tai_luc > coalesce(h.bao_gia_luc, '-infinity'::timestamptz)) then
      raise exception 'Chưa có ảnh hoặc file báo giá – đính kèm ảnh / PDF báo giá rồi lưu.'; end if;
  end if;

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
  update public.ho_so set bao_gia_luc = now() where id = p_ho_so;
  return v_lan;
end $function$;

-- duyet_gia
CREATE OR REPLACE FUNCTION public.duyet_gia(p_ho_so bigint, p_ngay date, ket_qua jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('bao_gia','da_duyet','dang_sua','cho_kcs') then
    raise exception 'Hồ sơ đang ở bước "%", không duyệt giá được.', h.trang_thai; end if;
  if h.nguon_tt <> 'khach' and h.gdv_id is null then
    raise exception 'Chưa có giám định viên. Bấm "Sửa" ở mục Thông tin xe và khách để ghi GDV trước khi nhập kết quả duyệt giá.'; end if;
  -- 047: xe bảo hiểm của hồ sơ bắt ảnh → phải có ảnh / file duyệt giá của bảo hiểm tải lên sau lần báo giá gần nhất
  if h.bat_buoc_anh and h.nguon_tt <> 'khach'
     and not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'duyet_gia'
                     and tai_luc > coalesce(h.bao_gia_luc, '-infinity'::timestamptz)) then
    raise exception 'Chưa có ảnh hoặc file duyệt giá của bảo hiểm – đính kèm bản duyệt giá rồi lưu.'; end if;
  if p_ngay is null then raise exception 'Thiếu ngày duyệt.'; end if;
  if p_ngay > current_date then raise exception 'Ngày duyệt không được sau hôm nay.'; end if;
  if p_ngay < (h.ngay_vao at time zone 'Asia/Ho_Chi_Minh')::date then
    raise exception 'Ngày duyệt % trước ngày nhận xe % – kiểm tra lại ngày (dd/mm/yyyy).',
      to_char(p_ngay, 'DD/MM/YYYY'), to_char(h.ngay_vao at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY'); end if;
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
end $function$;

-- lap_lenh_sua_chua
CREATE OR REPLACE FUNCTION public.lap_lenh_sua_chua(p_ho_so bigint, p_hen_giao timestamp with time zone, phan_cong jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.ho_so; d jsonb; r public.hang_muc;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('da_duyet','dang_sua') then
    raise exception 'Chưa duyệt giá thì chưa lập được lệnh sửa chữa.'; end if;
  if h.bat_buoc_anh then perform app.yeu_cau_anh_nhan_xe(p_ho_so); end if;   -- 047 (cả hồ sơ bảo hành)
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
end $function$;

-- kcs
CREATE OR REPLACE FUNCTION public.kcs(p_ho_so bigint, p_dat boolean, p_loi text DEFAULT NULL::text, p_lam_lai bigint[] DEFAULT NULL::bigint[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare h public.ho_so; v_truot timestamptz; v_so_anh int;
begin
  perform app.yeu_cau('quan_ly','giam_doc','cvdv');   -- 047: CVDV cũng nghiệm thu KCS
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai <> 'cho_kcs' then raise exception 'Xe chưa sửa xong, chưa KCS được.'; end if;
  if p_dat then
    if exists (select 1 from public.phat_sinh where ho_so_id = p_ho_so and not da_xu_ly) then
      raise exception 'Còn hư hỏng phát sinh chưa xử lý – CVDV lập báo giá bổ sung hoặc ghi "Không cần làm thêm" trước khi KCS đạt.'; end if;
    select max(luc) into v_truot from public.kcs where ho_so_id = p_ho_so and not dat;
    -- 047: hồ sơ bắt ảnh → tối thiểu 6 ảnh KCS (cộng cả các lần), sau lần chưa đạt thêm ít nhất 1 ảnh mới (kiểm ngay dưới)
    if h.bat_buoc_anh then
      select count(*) into v_so_anh from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'kcs' and coalesce(loai, 'anh') = 'anh';
      if v_so_anh < 6 then
        raise exception 'KCS cần tối thiểu 6 ảnh sau sửa (mới có %). Chụp thêm rồi ký đạt.', v_so_anh; end if;
    end if;
    if not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'kcs' and (v_truot is null or tai_luc > v_truot)) then
      if v_truot is null then raise exception 'Chưa có ảnh sau sửa. Chụp ảnh trước khi ký KCS.';
      else raise exception 'Chưa có ảnh sau khi làm lại (lần KCS chưa đạt lúc %). Chụp ảnh mới ở bước "Sau sửa" trước khi ký KCS đạt.',
        to_char(v_truot, 'HH24:MI DD/MM'); end if;
    end if;
  end if;
  insert into public.kcs (ho_so_id, dat, loi, boi) values (p_ho_so, p_dat, nullif(trim(p_loi),''), auth.uid());
  if p_dat then
    perform app.doi_trang_thai(p_ho_so, 'dat_kcs', 'Đạt KCS');
  else
    if nullif(trim(p_loi),'') is null then raise exception 'Ghi lỗi cần làm lại.'; end if;
    if p_lam_lai is null or cardinality(p_lam_lai) = 0 then raise exception 'Chọn hạng mục phải làm lại.'; end if;
    update public.hang_muc set trang_thai = 'dang_lam', xong_luc = null
    where ho_so_id = p_ho_so and id = any(p_lam_lai) and trang_thai = 'xong';
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Chưa đạt KCS: ' || trim(p_loi));
  end if;
end $function$;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';
