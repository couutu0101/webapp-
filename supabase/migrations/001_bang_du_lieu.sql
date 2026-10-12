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
