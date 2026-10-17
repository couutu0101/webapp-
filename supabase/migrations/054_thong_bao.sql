-- =====================================================================
-- 054: Thông báo hiện lên màn hình người đảm nhận tiếp theo (anh Thuận yêu cầu 17/10 13:27)
--  Phạm vi anh chọn: trong phần mềm (thông báo đẩy khi tắt app để sau); báo cho
--    - Tổ sửa chữa: lập lệnh sửa chữa → trưởng nhóm tổ nhận việc; KCS / Detailing trả về làm lại; xe đến lượt Detailing;
--      tổ báo hư hỏng phát sinh → CVDV
--    - Kho và tiền: đề xuất vật tư → kho; đề nghị mua → người duyệt (không phải người lập; chỉ còn người lập thì giám đốc), rồi → kho/người lập; phiếu nhập → kế toán khớp hóa đơn;
--      đề nghị chi → người duyệt, rồi → kế toán chi tiền; bị từ chối → người lập
--    - Nhắc quá hạn: tính ngay trên máy từ danh sách "Việc hôm nay" (không lưu ở đây)
--  Hiện khung to giữa màn hình, người nhận phải bấm "Đã nhận"; hồ sơ ghi ai nhận lúc nào.
--  Không báo cho chính người vừa làm việc đó; không báo hồ sơ chuyển từ Excel.
--  Tương thích ngược: chỉ thêm bảng, hàm, trigger. Mọi trigger bắt lỗi của chính nó – có lỗi thì bỏ qua thông báo,
--  KHÔNG BAO GIỜ làm hỏng việc chính (lập lệnh, KCS, duyệt chi…). Giao diện cũ (bản thật) không đọc bảng này nên không đổi.
--  Đổi hàm xoa_tai_khoan_nhan_vien (046): thông báo tự sinh không tính là "dữ liệu" của tài khoản (xóa tài khoản tạo nhầm vẫn được).
-- =====================================================================

create table if not exists public.thong_bao (
  id            bigint generated always as identity primary key,
  nguoi_nhan    uuid not null references public.nhan_vien(id) on delete cascade,
  chi_nhanh_id  text,
  loai          text not null check (loai in ('to', 'kho', 'tien')),     -- tổ sửa chữa / kho / tiền (sau này thêm loại: sửa ràng buộc này)
  khoa          text not null,                                           -- gộp: cùng người + cùng khóa + chưa nhận → thêm dòng vào thông báo cũ
  tieu_de       text not null,
  noi_dung      text,
  chi_tiet      text[] not null default '{}',
  dich          text,                                                    -- nơi mở khi bấm: ho_so | kho_de_xuat | kho_mua | kho_nhap | de_nghi
  ho_so_id      bigint references public.ho_so(id) on delete cascade,
  tao_boi       uuid,                                                    -- người vừa làm việc gây ra thông báo
  tao_luc       timestamptz not null default now(),
  cap_nhat_luc  timestamptz not null default now(),
  so_lan        integer not null default 1,
  da_nhan_luc   timestamptz                                              -- lúc người nhận bấm "Đã nhận"
);
comment on table public.thong_bao is 'Thông báo trong phần mềm (054): mỗi dòng là một thông báo gửi đúng một người; da_nhan_luc = lúc bấm Đã nhận';
create unique index if not exists thong_bao_chua_nhan_uk on public.thong_bao (nguoi_nhan, khoa) where da_nhan_luc is null;
create index if not exists thong_bao_nguoi_idx on public.thong_bao (nguoi_nhan, cap_nhat_luc desc);
create index if not exists thong_bao_ho_so_idx on public.thong_bao (ho_so_id) where ho_so_id is not null;

alter table public.thong_bao enable row level security;
drop policy if exists doc on public.thong_bao;
create policy doc on public.thong_bao for select to authenticated using (nguoi_nhan = (select auth.uid()));
revoke all on public.thong_bao from anon, authenticated;
grant select on public.thong_bao to authenticated;

-- ---------------------------------------------------------------------
-- Người nhận
-- ---------------------------------------------------------------------
-- Những người có một trong các vai trò ở chi nhánh (giám đốc phụ trách mọi chi nhánh); không có ai thì mọi giám đốc đang làm
create or replace function app.nguoi_theo_vai(p_vai text[], p_cn text) returns setof uuid
language sql stable security definer set search_path = public as $$
  select n.id from public.nhan_vien n
  where n.hoat_dong and n.vai_tro && p_vai
    and (n.chi_nhanh_id = p_cn or n.chi_nhanh_id is null or 'giam_doc' = any(n.vai_tro))
  union
  select g.id from public.nhan_vien g
  where g.hoat_dong and 'giam_doc' = any(g.vai_tro)
    and not exists (select 1 from public.nhan_vien n
                    where n.hoat_dong and n.vai_tro && p_vai
                      and (n.chi_nhanh_id = p_cn or n.chi_nhanh_id is null or 'giam_doc' = any(n.vai_tro)))
$$;

-- Trưởng nhóm của tổ ở chi nhánh; tổ chưa có trưởng nhóm đăng nhập thì quản lý chung nhận thay (du_phong = true)
create or replace function app.nguoi_nhan_to(p_to text, p_cn text) returns table (id uuid, du_phong boolean)
language sql stable security definer set search_path = public as $$
  with tn as (
    select n.id from public.nhan_vien n
    where n.hoat_dong and 'truong_nhom' = any(n.vai_tro) and n.to_id = p_to and (n.chi_nhanh_id = p_cn or n.chi_nhanh_id is null))
  select tn.id, false from tn
  union all
  select q.id, true from app.nguoi_theo_vai(array['quan_ly'], p_cn) q(id) where not exists (select 1 from tn)
$$;

-- Người duyệt một phiếu: những người có vai trò đó, trừ người lập (không tự duyệt phiếu mình lập); không còn ai thì giám đốc
create or replace function app.nguoi_duyet(p_vai text[], p_cn text, p_nguoi_lap uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  with ds as (select u.id from app.nguoi_theo_vai(p_vai, p_cn) as u(id) where u.id is distinct from p_nguoi_lap)
  select ds.id from ds
  union
  select g.id from public.nhan_vien g
  where g.hoat_dong and 'giam_doc' = any(g.vai_tro) and not exists (select 1 from ds)
$$;

-- Biển số hiển thị (50H-923.61) của hồ sơ; chưa có biển thì mã hồ sơ
create or replace function app.nhan_xe_thong_bao(p_ho_so bigint) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(public.bien_so_hien_thi(x.bien_so), h.ma)
  from public.ho_so h left join public.xe x on x.id = h.xe_id where h.id = p_ho_so
$$;

-- ---------------------------------------------------------------------
-- Gửi một thông báo. Cùng người + cùng khóa + chưa nhận → gộp thêm dòng vào thông báo đang chờ (không chồng nhiều khung).
-- ---------------------------------------------------------------------
create or replace function app.gui_thong_bao(
  p_nguoi uuid, p_loai text, p_khoa text, p_tieu_de text, p_chi_tiet text[], p_dich text,
  p_ho_so bigint, p_cn text, p_noi_dung text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_nguoi is null or p_nguoi is not distinct from auth.uid() then return; end if;      -- người vừa làm việc đó đã biết rồi
  if not exists (select 1 from public.nhan_vien n
                 where n.id = p_nguoi and n.hoat_dong and cardinality(n.vai_tro) > 0 and not ('co_dong' = any(n.vai_tro))) then return; end if;
  insert into public.thong_bao as t (nguoi_nhan, chi_nhanh_id, loai, khoa, tieu_de, noi_dung, chi_tiet, dich, ho_so_id, tao_boi)
  values (p_nguoi, p_cn, p_loai, p_khoa, left(p_tieu_de, 300), left(p_noi_dung, 600), coalesce(p_chi_tiet, '{}'), p_dich, p_ho_so, auth.uid())
  on conflict (nguoi_nhan, khoa) where da_nhan_luc is null do update
    set chi_tiet = t.chi_tiet || coalesce((select array_agg(u.e order by u.n) from unnest(excluded.chi_tiet) with ordinality u(e, n)
                                           where u.e <> all (t.chi_tiet)), '{}'),
        so_lan = t.so_lan + 1,
        cap_nhat_luc = now(),
        tieu_de = excluded.tieu_de,
        noi_dung = coalesce(excluded.noi_dung, t.noi_dung);
end $$;

-- ---------------------------------------------------------------------
-- 1. TỔ SỬA CHỮA
-- ---------------------------------------------------------------------
-- 1a. Hạng mục vừa giao cho tổ (lập lệnh sửa chữa, giao thêm) hoặc bị trả về làm lại (KCS / Detailing chưa đạt)
create or replace function app.tb_hang_muc_giao_to() returns trigger
language plpgsql security definer set search_path = public as $$
declare hs public.ho_so; r record; v_xe text; v_ten_to text; v_loi text; v_khoa text; v_tieu text; v_nd text; v_dong text; v_ai text;
  v_lam_lai boolean := (old.trang_thai = 'xong');
begin
  begin
    if new.to_id is null then return null; end if;
    select * into hs from public.ho_so where id = new.ho_so_id;
    if not found or hs.tu_excel or hs.trang_thai = 'huy' then return null; end if;
    v_xe := app.nhan_xe_thong_bao(hs.id);
    select t.ten into v_ten_to from public.to_thuc_hien t where t.id = new.to_id;
    v_ten_to := coalesce(v_ten_to, new.to_id);
    select n.ho_ten into v_ai from public.nhan_vien n where n.id = auth.uid();
    v_dong := new.ten || case when nullif(trim(new.nguoi_lam), '') is not null then ' (' || trim(new.nguoi_lam) || ')' else '' end;
    if v_lam_lai then
      select x.loi into v_loi from (
        select k.loi, k.luc, k.id from public.kcs k where k.ho_so_id = hs.id and not k.dat
        union all
        select d.loi, d.luc, d.id from public.ket_qua_detailing d where d.ho_so_id = hs.id and not d.dat) x
      order by x.luc desc, x.id desc limit 1;
      v_tieu := 'Làm lại ' || (case when hs.trang_thai = 'cho_detailing' then '(Detailing trả về)' else '(KCS chưa đạt)' end) || ' – xe ' || v_xe;
      v_nd := concat_ws(' · ', case when v_loi is not null then 'Lỗi cần sửa: ' || v_loi end, case when v_ai is not null then v_ai || ' trả về' end);
      v_khoa := 'to:lam_lai:' || hs.id || ':' || new.to_id || ':' || (case when hs.trang_thai = 'cho_detailing' then 'det' else 'kcs' end);
    else
      v_tieu := 'Việc mới cho tổ ' || v_ten_to || ' – xe ' || v_xe;
      v_nd := case when v_ai is not null then v_ai || ' giao việc' end;
      v_khoa := 'to:moi:' || hs.id || ':' || new.to_id;
    end if;
    for r in select * from app.nguoi_nhan_to(new.to_id, hs.chi_nhanh_id) loop
      perform app.gui_thong_bao(r.id, 'to', v_khoa,
        v_tieu || case when r.du_phong then ' (tổ ' || v_ten_to || ' chưa có trưởng nhóm đăng nhập)' else '' end,
        array[v_dong], 'ho_so', hs.id, hs.chi_nhanh_id, v_nd);
    end loop;
  exception when others then
    raise warning 'Thông báo (giao tổ) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_hang_muc_giao_to on public.hang_muc;
create trigger thong_bao_hang_muc_giao_to after update of trang_thai on public.hang_muc
  for each row when (new.trang_thai = 'dang_lam' and old.trang_thai is distinct from 'dang_lam')
  execute function app.tb_hang_muc_giao_to();

-- 1b. Xe đến lượt Detailing (tổ Detailing – hồ sơ có bước này)
create or replace function app.tb_ho_so_cho_detailing() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; v_xe text;
begin
  begin
    if new.tu_excel then return null; end if;
    v_xe := app.nhan_xe_thong_bao(new.id);
    for r in select * from app.nguoi_nhan_to('DT', new.chi_nhanh_id) loop
      perform app.gui_thong_bao(r.id, 'to', 'to:detailing:' || new.id,
        'Xe ' || v_xe || ' đến lượt Detailing' || case when r.du_phong then ' (tổ Detailing chưa có trưởng nhóm đăng nhập)' else '' end,
        '{}', 'ho_so', new.id, new.chi_nhanh_id, 'Rửa xe, đánh bóng rồi bấm "Detailing xong – chuyển KCS".');
    end loop;
  exception when others then
    raise warning 'Thông báo (Detailing) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_ho_so_cho_detailing on public.ho_so;
create trigger thong_bao_ho_so_cho_detailing after update of trang_thai on public.ho_so
  for each row when (new.trang_thai = 'cho_detailing' and old.trang_thai is distinct from 'cho_detailing')
  execute function app.tb_ho_so_cho_detailing();

-- 1c. Tổ báo hư hỏng phát sinh → CVDV phụ trách hồ sơ (người tiếp nhận; không còn làm thì CVDV đầu tiên của chi nhánh)
create or replace function app.tb_phat_sinh() returns trigger
language plpgsql security definer set search_path = public as $$
declare hs public.ho_so; v_nguoi uuid; v_ten text;
begin
  begin
    select * into hs from public.ho_so where id = new.ho_so_id;
    if not found or hs.tu_excel then return null; end if;
    v_nguoi := coalesce((select n.id from public.nhan_vien n where n.id = hs.tao_boi and n.hoat_dong), app.nhan_vien_dau('cvdv', hs.chi_nhanh_id));
    select n.ho_ten into v_ten from public.nhan_vien n where n.id = new.boi;
    perform app.gui_thong_bao(v_nguoi, 'to', 'to:phat_sinh:' || hs.id, 'Hư hỏng phát sinh – xe ' || app.nhan_xe_thong_bao(hs.id),
      array[left(new.mo_ta, 240)], 'ho_so', hs.id, hs.chi_nhanh_id,
      coalesce(v_ten || ' báo. ', '') || 'Lập báo giá bổ sung hoặc ghi "Không cần làm thêm".');
  exception when others then
    raise warning 'Thông báo (phát sinh) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_phat_sinh on public.phat_sinh;
create trigger thong_bao_phat_sinh after insert on public.phat_sinh
  for each row execute function app.tb_phat_sinh();

-- ---------------------------------------------------------------------
-- 2. KHO VÀ TIỀN
--    Phiếu có dòng (đề xuất vật tư, đề nghị mua, phiếu nhập) dùng trigger "chốt cuối giao dịch" (deferrable initially deferred):
--    lúc đó các dòng và tổng tiền đã đủ nên thông báo ghi đúng số dòng, số tiền.
-- ---------------------------------------------------------------------
-- Danh sách dòng hàng gọn: tối đa 8 dòng, còn lại gộp "… và n mặt hàng khác"
create or replace function app.dong_hang_gon(p_dong text[]) returns text[]
language sql immutable as $$
  select case when coalesce(cardinality(p_dong), 0) <= 8 then coalesce(p_dong, '{}')
              else p_dong[1:8] || ('… và ' || (cardinality(p_dong) - 8) || ' mặt hàng khác') end
$$;

-- 2a. Đề xuất vật tư mới → kho xuất
create or replace function app.tb_de_xuat_vat_tu() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.de_xuat_vat_tu; v_xe text; v_to text; v_ten text; v_dong text[]; v_nguoi uuid;
begin
  begin
    select * into r from public.de_xuat_vat_tu x where x.id = new.id;
    if not found or r.trang_thai <> 'cho_xuat' then return null; end if;
    if r.ho_so_id is not null then v_xe := app.nhan_xe_thong_bao(r.ho_so_id); end if;
    select t.ten into v_to from public.to_thuc_hien t where t.id = r.to_id;
    select n.ho_ten into v_ten from public.nhan_vien n where n.id = r.nguoi_lap;
    select array_agg(h.ten || ' × ' || trim_scale(d.so_luong)::text || coalesce(' ' || h.dvt, '') order by d.id) into v_dong
    from public.de_xuat_dong d join public.hang_kho h on h.id = d.hang_id where d.de_xuat_id = r.id;
    for v_nguoi in select app.nguoi_theo_vai(array['kho'], r.chi_nhanh_id) loop
      perform app.gui_thong_bao(v_nguoi, 'kho', 'kho:de_xuat:' || r.id,
        'Đề xuất vật tư ' || r.ma || coalesce(' – xe ' || v_xe, '') || ' chờ xuất kho',
        app.dong_hang_gon(v_dong), 'kho_de_xuat', r.ho_so_id, r.chi_nhanh_id,
        concat_ws(' · ', case when v_to is not null then 'Tổ ' || v_to end, case when v_ten is not null then v_ten || ' đề xuất' end));
    end loop;
  exception when others then
    raise warning 'Thông báo (đề xuất vật tư) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_de_xuat_vat_tu on public.de_xuat_vat_tu;
create constraint trigger thong_bao_de_xuat_vat_tu after insert on public.de_xuat_vat_tu
  deferrable initially deferred for each row execute function app.tb_de_xuat_vat_tu();

-- 2b. Đề nghị mua mới → người duyệt (quản lý; chi nhánh chưa có quản lý thì giám đốc)
create or replace function app.tb_de_nghi_mua_moi() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_mua; v_ncc text; v_ten text; v_dong text[]; v_nguoi uuid;
begin
  begin
    select * into r from public.de_nghi_mua x where x.id = new.id;
    if not found or r.trang_thai <> 'cho_duyet' then return null; end if;
    select c.ten into v_ncc from public.nha_cung_cap c where c.id = r.nha_cung_cap_id;
    select n.ho_ten into v_ten from public.nhan_vien n where n.id = r.nguoi_lap;
    select array_agg(h.ten || ' × ' || trim_scale(d.so_luong)::text || coalesce(' ' || h.dvt_nhap, coalesce(' ' || h.dvt, '')) order by d.id) into v_dong
    from public.de_nghi_mua_dong d join public.hang_kho h on h.id = d.hang_id where d.de_nghi_id = r.id;
    for v_nguoi in select app.nguoi_duyet(array['quan_ly'], r.chi_nhanh_id, r.nguoi_lap) loop
      perform app.gui_thong_bao(v_nguoi, 'kho', 'kho:mua_cho_duyet:' || r.id,
        'Đề nghị mua ' || r.ma || ' chờ duyệt',
        app.dong_hang_gon(v_dong), 'kho_mua', r.ho_so_id, r.chi_nhanh_id,
        concat_ws(' · ', v_ncc, app.vnd(r.tong_tien) || ' đ', case when v_ten is not null then v_ten || ' lập' end));
    end loop;
  exception when others then
    raise warning 'Thông báo (đề nghị mua) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_de_nghi_mua_moi on public.de_nghi_mua;
create constraint trigger thong_bao_de_nghi_mua_moi after insert on public.de_nghi_mua
  deferrable initially deferred for each row execute function app.tb_de_nghi_mua_moi();

-- 2c. Đề nghị mua được duyệt → kho đi mua / nhập hàng (và người lập); bị từ chối → người lập
create or replace function app.tb_de_nghi_mua_duyet() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ncc text; v_nguoi uuid; v_ten text;
begin
  begin
    select c.ten into v_ncc from public.nha_cung_cap c where c.id = new.nha_cung_cap_id;
    select n.ho_ten into v_ten from public.nhan_vien n where n.id = new.duyet_boi;
    if new.trang_thai = 'da_duyet' then
      for v_nguoi in
        select app.nguoi_theo_vai(array['kho'], new.chi_nhanh_id)
        union select n.id from public.nhan_vien n where n.id = new.nguoi_lap and n.hoat_dong
      loop
        perform app.gui_thong_bao(v_nguoi, 'kho', 'kho:mua_da_duyet:' || new.id,
          'Đề nghị mua ' || new.ma || ' đã duyệt – đi mua / nhập hàng về', '{}', 'kho_mua', new.ho_so_id, new.chi_nhanh_id,
          concat_ws(' · ', v_ncc, app.vnd(new.tong_tien) || ' đ', case when v_ten is not null then v_ten || ' duyệt' end));
      end loop;
    else
      perform app.gui_thong_bao(new.nguoi_lap, 'kho', 'kho:mua_tu_choi:' || new.id,
        'Đề nghị mua ' || new.ma || ' bị từ chối', '{}', 'kho_mua', new.ho_so_id, new.chi_nhanh_id,
        concat_ws(' · ', v_ncc, app.vnd(new.tong_tien) || ' đ', 'Lý do: ' || coalesce(new.ly_do_tu_choi, '—')));
    end if;
  exception when others then
    raise warning 'Thông báo (duyệt đề nghị mua) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_de_nghi_mua_duyet on public.de_nghi_mua;
create trigger thong_bao_de_nghi_mua_duyet after update of trang_thai on public.de_nghi_mua
  for each row when (old.trang_thai = 'cho_duyet' and new.trang_thai in ('da_duyet', 'tu_choi'))
  execute function app.tb_de_nghi_mua_duyet();

-- 2d. Phiếu nhập kho mới → kế toán khớp hóa đơn
create or replace function app.tb_phieu_nhap() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.phieu_nhap; v_ncc text; v_ten text; v_nguoi uuid;
begin
  begin
    select * into r from public.phieu_nhap x where x.id = new.id;
    if not found or r.trang_thai <> 'cho_khop' then return null; end if;
    select c.ten into v_ncc from public.nha_cung_cap c where c.id = r.nha_cung_cap_id;
    select n.ho_ten into v_ten from public.nhan_vien n where n.id = r.tao_boi;
    for v_nguoi in select app.nguoi_theo_vai(array['ke_toan'], r.chi_nhanh_id) loop
      perform app.gui_thong_bao(v_nguoi, 'kho', 'kho:phieu_nhap:' || r.id,
        'Phiếu nhập ' || r.ma || ' cần khớp hóa đơn', array[]::text[], 'kho_nhap', r.ho_so_id, r.chi_nhanh_id,
        concat_ws(' · ', v_ncc, app.vnd(r.tong_tien) || ' đ', case when r.so_hoa_don is not null then 'HĐ ' || r.so_hoa_don end,
                  case when v_ten is not null then v_ten || ' nhập' end));
    end loop;
  exception when others then
    raise warning 'Thông báo (phiếu nhập) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_phieu_nhap on public.phieu_nhap;
create constraint trigger thong_bao_phieu_nhap after insert on public.phieu_nhap
  deferrable initially deferred for each row execute function app.tb_phieu_nhap();

-- 2e. Đề nghị chi mới → người duyệt: khoản trên hạn mức quản lý chỉ giám đốc duyệt, còn lại quản lý chung (chưa có thì giám đốc)
create or replace function app.tb_de_nghi_chi_moi() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_muc text; v_ten text; v_nguoi uuid; v_vai text[];
begin
  begin
    if new.trang_thai <> 'cho_duyet' then return null; end if;
    select m.ten into v_muc from public.muc_thu_chi m where m.id = new.muc_id;
    select n.ho_ten into v_ten from public.nhan_vien n where n.id = new.nguoi_de_nghi;
    v_vai := case when new.so_tien > app.cai_dat_so('han_muc_chi_quan_ly', 2000000) then array['giam_doc'] else array['quan_ly'] end;
    for v_nguoi in select app.nguoi_duyet(v_vai, new.chi_nhanh_id, new.nguoi_de_nghi) loop
      perform app.gui_thong_bao(v_nguoi, 'tien', 'tien:cho_duyet:' || new.id,
        'Đề nghị chi ' || app.vnd(new.so_tien) || ' đ chờ duyệt', array[left(new.noi_dung, 240)], 'de_nghi', new.ho_so_id, new.chi_nhanh_id,
        concat_ws(' · ', v_muc, case when v_ten is not null then v_ten || ' đề nghị' end));
    end loop;
  exception when others then
    raise warning 'Thông báo (đề nghị chi) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_de_nghi_chi_moi on public.de_nghi_chi;
create trigger thong_bao_de_nghi_chi_moi after insert on public.de_nghi_chi
  for each row execute function app.tb_de_nghi_chi_moi();

-- 2f. Đề nghị chi được duyệt → kế toán chi tiền; bị từ chối → người đề nghị
create or replace function app.tb_de_nghi_chi_duyet() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_muc text; v_ten text; v_nguoi uuid;
begin
  begin
    select m.ten into v_muc from public.muc_thu_chi m where m.id = new.muc_id;
    select n.ho_ten into v_ten from public.nhan_vien n where n.id = new.duyet_boi;
    if new.trang_thai = 'da_duyet' then
      for v_nguoi in select app.nguoi_theo_vai(array['ke_toan'], new.chi_nhanh_id) loop
        perform app.gui_thong_bao(v_nguoi, 'tien', 'tien:can_chi:' || new.id,
          'Đề nghị chi ' || app.vnd(new.so_tien) || ' đ đã duyệt – chi tiền', array[left(new.noi_dung, 240)], 'de_nghi', new.ho_so_id, new.chi_nhanh_id,
          concat_ws(' · ', v_muc, case when v_ten is not null then v_ten || ' duyệt' end));
      end loop;
    else
      perform app.gui_thong_bao(new.nguoi_de_nghi, 'tien', 'tien:tu_choi:' || new.id,
        'Đề nghị chi ' || app.vnd(new.so_tien) || ' đ bị từ chối', array[left(new.noi_dung, 240)], 'de_nghi', new.ho_so_id, new.chi_nhanh_id,
        concat_ws(' · ', 'Lý do: ' || coalesce(new.ly_do_tu_choi, '—'), case when v_ten is not null then v_ten || ' từ chối' end));
    end if;
  exception when others then
    raise warning 'Thông báo (duyệt đề nghị chi) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists thong_bao_de_nghi_chi_duyet on public.de_nghi_chi;
create trigger thong_bao_de_nghi_chi_duyet after update of trang_thai on public.de_nghi_chi
  for each row when (old.trang_thai = 'cho_duyet' and new.trang_thai in ('da_duyet', 'tu_choi'))
  execute function app.tb_de_nghi_chi_duyet();

-- ---------------------------------------------------------------------
-- 3. Người nhận bấm "Đã nhận"; hồ sơ xem được ai đã nhận lúc nào
-- ---------------------------------------------------------------------
-- Chỉ đánh dấu đúng những thông báo của mình trong danh sách gửi lên (thông báo mới đến sau khi khung hiện ra thì chưa bị nhận hộ).
-- p_so_lan (không bắt buộc) = "số lần cập nhật" của từng thông báo LÚC MÀN HÌNH HIỆN (cùng thứ tự với p_ids). Nếu giữa chừng thông báo vừa được
-- gộp thêm dòng mới (so_lan đã tăng) thì KHÔNG ghi nhận cái đó – người nhận phải thấy nội dung mới rồi mới bấm "Đã nhận".
-- Trả về danh sách id đã ghi nhận được (id không có trong kết quả = đã nhận từ trước, của người khác, hoặc vừa có nội dung mới).
create or replace function public.nhan_thong_bao(p_ids bigint[], p_so_lan integer[] default null) returns bigint[]
language plpgsql security definer set search_path = public as $$
declare v_da bigint[];
begin
  if auth.uid() is null then raise exception 'Chưa đăng nhập.' using errcode = '42501'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then return '{}'::bigint[]; end if;
  if p_so_lan is not null and cardinality(p_so_lan) <> cardinality(p_ids) then
    raise exception 'Danh sách thông báo và số lần cập nhật đã xem không khớp nhau.';
  end if;
  with x as (
    select i.id, s.so_lan
    from unnest(p_ids) with ordinality as i(id, n)
    left join unnest(coalesce(p_so_lan, '{}'::integer[])) with ordinality as s(so_lan, n) on s.n = i.n
  ), u as (
    update public.thong_bao t set da_nhan_luc = now()
    from x
    where t.id = x.id and t.nguoi_nhan = auth.uid() and t.da_nhan_luc is null and (x.so_lan is null or t.so_lan = x.so_lan)
    returning t.id
  )
  select coalesce(array_agg(u.id order by u.id), '{}'::bigint[]) into v_da from u;
  return v_da;
end $$;

-- Thông báo đã gửi về một hồ sơ: ai nhận, nhận lúc nào (nhân viên văn phòng, đúng chi nhánh của hồ sơ)
create or replace function public.thong_bao_ho_so(p_ho_so bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_cn text;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select h.chi_nhanh_id into v_cn from public.ho_so h where h.id = p_ho_so;
  if not found then return '[]'::jsonb; end if;
  perform app.yeu_cau_chi_nhanh(v_cn);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id, 'nguoi_nhan', t.nguoi_nhan, 'ho_ten', n.ho_ten, 'vai_tro', n.vai_tro, 'to_id', n.to_id, 'loai', t.loai,
      'tieu_de', t.tieu_de, 'chi_tiet', t.chi_tiet, 'tao_luc', t.tao_luc, 'cap_nhat_luc', t.cap_nhat_luc, 'da_nhan_luc', t.da_nhan_luc)
      order by t.tao_luc desc, t.id desc)
    from (select * from public.thong_bao x where x.ho_so_id = p_ho_so order by x.tao_luc desc, x.id desc limit 60) t
    join public.nhan_vien n on n.id = t.nguoi_nhan), '[]'::jsonb);
end $$;

revoke execute on function public.nhan_thong_bao(bigint[], integer[]), public.thong_bao_ho_so(bigint) from public, anon;
grant execute on function public.nhan_thong_bao(bigint[], integer[]), public.thong_bao_ho_so(bigint) to authenticated;
revoke execute on function
  app.nguoi_theo_vai(text[], text), app.nguoi_nhan_to(text, text), app.nguoi_duyet(text[], text, uuid), app.nhan_xe_thong_bao(bigint),
  app.gui_thong_bao(uuid, text, text, text, text[], text, bigint, text, text), app.dong_hang_gon(text[]),
  app.tb_hang_muc_giao_to(), app.tb_ho_so_cho_detailing(), app.tb_phat_sinh(), app.tb_de_xuat_vat_tu(), app.tb_de_nghi_mua_moi(),
  app.tb_de_nghi_mua_duyet(), app.tb_phieu_nhap(), app.tb_de_nghi_chi_moi(), app.tb_de_nghi_chi_duyet()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Xóa tài khoản (046): thông báo tự sinh không tính là "dữ liệu" của tài khoản; xóa tài khoản thì thông báo gửi cho nó xóa theo
-- ---------------------------------------------------------------------
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
      and col.table_name <> 'thong_bao'
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
