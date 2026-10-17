-- =====================================================================
-- 056 (anh Thuận yêu cầu 17/10 22:52, chạy bản thử trước):
--  1. GIÁM ĐỐC HỦY HỒ SƠ Ở BẤT KỲ BƯỚC NÀO, ghi lý do, hồ sơ vẫn nằm trong dữ liệu. Anh chọn: doanh thu tính theo GIÁ THƯƠNG
--     LƯỢNG với khách (giám đốc nhập), vật tư đã dùng là chi phí, vật tư chưa dùng trả về kho.
--       - Doanh thu thương lượng = 0  → hồ sơ "Đã hủy" như trước (không doanh thu; tiền khách đã trả → phải trả lại).
--       - Doanh thu thương lượng > 0  → hạng mục chưa làm thôi tính; khách trả toàn bộ (phần bảo hiểm chuyển sang khách);
--         thêm dòng "Thu theo thỏa thuận khi hủy" để tổng phải thu = đúng số thương lượng (ghi doanh thu ngày hủy);
--         hồ sơ sang "Đã giao" (xe trả khách), cờ huy_thoa_thuan; thu đủ tự đóng như thường.
--       - Vật tư: giám đốc nhập số lượng CHƯA DÙNG của từng dòng đã xuất cho xe → trả về đúng lô (giá vốn của xe giảm theo);
--         phần còn lại vẫn là giá vốn. Phiếu đề xuất còn chờ xuất thì hủy.
--  2. DUYỆT GIÁ XE BẢO HIỂM CHỈ NHẬP 2 SỐ: Bảo hiểm thanh toán + Khách hàng thanh toán (tổng = doanh thu của xe).
--     Mọi dòng chờ duyệt được duyệt; giá duyệt từng dòng chia theo tỷ lệ giá báo (báo cáo theo nhóm vẫn đúng).
--     public.duyet_gia_tong(p_ho_so, p_ngay, p_bao_hiem, p_khach) – hai số là của CẢ XE (gồm các lần duyệt trước).
--  3. LỆNH SỬA CHỮA: hạng mục có thêm nguoi_lam_id (tài khoản người thực hiện) → thông báo "việc mới cho tổ" gửi đúng
--     người đó; ảnh lệnh sửa chữa bắt buộc (bước tệp 'lenh_sua_chua', tải sau lần lưu báo giá gần nhất) khi giao diện
--     mới gửi p_bat_buoc_anh = true (giao diện cũ không gửi → chạy như trước).
--  4. PHIẾU THU LỆCH CÔNG NỢ: phân bổ có lech = true + lý do → ghi đủ số thực thu vào xe (kể cả vượt nợ) và tạo đề nghị
--     chỉnh công nợ chờ quản lý chung / giám đốc duyệt; duyệt → thêm dòng "Điều chỉnh theo thực thu" (doanh thu tăng / giảm
--     đúng phần lệch, ngày duyệt) để công nợ bên đó về 0 → xe đã giao thì tự đóng. Anh chọn: thiếu và dư đều chỉnh doanh thu.
--  Dòng điều chỉnh / thỏa thuận: hang_muc.loai_dong ('dieu_chinh' | 'thoa_thuan_huy'), trạng thái 'xong', VAT 0, không xuất HĐ,
--  được phép âm. Mọi công thức tiền / doanh thu / công nợ đang cộng hạng mục nên tự đúng, không phải sửa từng báo cáo.
--  Tương thích ngược: chỉ thêm cột, bảng, hàm; lap_lenh_sua_chua thêm tham số có mặc định; app.phan_bo_phieu giữ nguyên
--  cách làm khi không có lech.
-- =====================================================================

alter table public.hang_muc add column if not exists loai_dong text;
alter table public.hang_muc add column if not exists nguoi_lam_id uuid references public.nhan_vien(id) on delete set null;
alter table public.hang_muc drop constraint if exists hang_muc_loai_dong_check;
alter table public.hang_muc add constraint hang_muc_loai_dong_check check (loai_dong is null or loai_dong in ('dieu_chinh','thoa_thuan_huy'));
alter table public.hang_muc drop constraint if exists hang_muc_gia_duyet_check;
alter table public.hang_muc add constraint hang_muc_gia_duyet_check check (gia_duyet >= 0 or loai_dong is not null);
comment on column public.hang_muc.loai_dong is '056: dòng tiền không phải việc sửa – dieu_chinh (thu lệch đã duyệt), thoa_thuan_huy (giám đốc hủy có thu)';

alter table public.ho_so add column if not exists huy_thoa_thuan boolean not null default false;
alter table public.ho_so add column if not exists huy_luc timestamptz;
alter table public.ho_so add column if not exists huy_boi uuid;

create table if not exists public.de_nghi_dieu_chinh (
  id              bigint generated always as identity primary key,
  chi_nhanh_id    text not null references public.chi_nhanh(id),
  ho_so_id        bigint not null references public.ho_so(id) on delete cascade,
  phieu_id        bigint references public.phieu_thu_chi(id),
  nguoi_tra       text not null check (nguoi_tra in ('khach','bao_hiem')),
  cong_no         numeric(14,0) not null,          -- còn nợ của bên đó lúc thu
  thuc_thu        numeric(14,0) not null,          -- số thực thu gắn vào xe
  ly_do           text not null,
  trang_thai      text not null default 'cho_duyet' check (trang_thai in ('cho_duyet','da_duyet','tu_choi','huy')),
  nguoi_lap       uuid,
  tao_luc         timestamptz not null default now(),
  duyet_boi       uuid,
  duyet_luc       timestamptz,
  ly_do_tu_choi   text,
  so_tien_dieu_chinh numeric(14,0),                -- số đã chỉnh vào doanh thu lúc duyệt (+ tăng, − giảm)
  hang_muc_id     bigint references public.hang_muc(id) on delete set null
);
create index if not exists de_nghi_dieu_chinh_hs_idx on public.de_nghi_dieu_chinh (ho_so_id);
create index if not exists de_nghi_dieu_chinh_cho_idx on public.de_nghi_dieu_chinh (chi_nhanh_id) where trang_thai = 'cho_duyet';
alter table public.de_nghi_dieu_chinh enable row level security;
drop policy if exists doc on public.de_nghi_dieu_chinh;
create policy doc on public.de_nghi_dieu_chinh for select to authenticated
  using ((select app.xem_nhu_nhan_vien()) and ((select app.co_vai_tro('giam_doc')) or chi_nhanh_id = (select app.chi_nhanh())));
revoke insert, update, delete on public.de_nghi_dieu_chinh from authenticated, anon;
grant select on public.de_nghi_dieu_chinh to authenticated;

-- ---------------------------------------------------------------------
-- Dòng tiền (điều chỉnh / thỏa thuận): trạng thái xong, VAT 0, ngày hôm nay, nhóm = nhóm có giá trị lớn nhất của xe
-- ---------------------------------------------------------------------
create or replace function app.them_dong_tien(p_ho_so bigint, p_nguoi_tra text, p_so_tien numeric, p_ten text, p_loai text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_nhom text; v_lan int; v_id bigint;
begin
  select m.nhom into v_nhom from public.hang_muc m
  where m.ho_so_id = p_ho_so and m.loai_dong is null and m.trang_thai in ('duyet','dang_lam','xong','tu_choi','cho_duyet')
  group by m.nhom order by sum(coalesce(m.gia_duyet, m.gia_bao)) desc nulls last limit 1;
  select coalesce(max(lan_bao_gia), 0) into v_lan from public.hang_muc where ho_so_id = p_ho_so;
  insert into public.hang_muc (ho_so_id, lan_bao_gia, ten, nhom, nguoi_tra, gia_bao, gia_duyet, xuat_hd, ngay_duyet, trang_thai, xong_luc, ty_le_vat, loai_dong)
  values (p_ho_so, v_lan, p_ten, coalesce(v_nhom, 'dong_son'), p_nguoi_tra, 0, round(p_so_tien), false, current_date, 'xong', now(), 0, p_loai)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Trả vật tư CHƯA DÙNG về kho: bớt số lượng của một dòng phiếu xuất cho xe, hàng về đúng lô (lô xuất sau trả trước)
-- ---------------------------------------------------------------------
create or replace function app.tra_vat_tu_ve_kho(p_dong bigint, p_so_luong numeric, p_ho_so bigint) returns void
language plpgsql security definer set search_path = public as $$
declare d public.phieu_xuat_dong; px public.phieu_xuat; x record; v_con numeric := p_so_luong; v_lay numeric; v_ten text;
begin
  if p_so_luong is null or p_so_luong <= 0 then return; end if;
  select * into d from public.phieu_xuat_dong where id = p_dong for update;
  if not found then raise exception 'Không tìm thấy dòng vật tư đã xuất.'; end if;
  select * into px from public.phieu_xuat where id = d.phieu_id for update;
  select h.ten into v_ten from public.hang_kho h where h.id = d.hang_id;
  if px.ho_so_id is distinct from p_ho_so or px.loai <> 'cho_xe' or px.trang_thai <> 'hieu_luc' then
    raise exception 'Dòng vật tư "%" không phải hàng đã xuất cho xe này.', v_ten; end if;
  if p_so_luong > d.so_luong then
    raise exception 'Vật tư "%": trả về % nhưng chỉ xuất %.', v_ten, trim_scale(p_so_luong), trim_scale(d.so_luong); end if;
  perform app.yeu_cau_thang_mo(px.chi_nhanh_id, px.ngay);
  for x in select xl.*, l.id as lo from public.xuat_lo xl join public.lo_kho l on l.id = xl.lo_id
           where xl.phieu_xuat_dong_id = d.id order by xl.id desc for update of xl loop
    exit when v_con <= 0;
    v_lay := least(v_con, x.so_luong);
    update public.lo_kho set con_lai = con_lai + v_lay where id = x.lo;
    if v_lay = x.so_luong then delete from public.xuat_lo where id = x.id;
    else update public.xuat_lo set so_luong = so_luong - v_lay where id = x.id; end if;
    v_con := v_con - v_lay;
  end loop;
  if d.so_luong - p_so_luong <= 0 then
    delete from public.phieu_xuat_dong where id = d.id;
  else
    update public.phieu_xuat_dong set so_luong = so_luong - p_so_luong,
      gia_von = coalesce((select round(sum(xl.so_luong * xl.don_gia_von)) from public.xuat_lo xl where xl.phieu_xuat_dong_id = d.id), 0)
    where id = d.id;
  end if;
  if not exists (select 1 from public.phieu_xuat_dong where phieu_id = px.id) then
    update public.phieu_xuat set trang_thai = 'huy', ly_do_huy = 'Hủy hồ sơ – trả hết vật tư về kho' where id = px.id;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. Giám đốc hủy hồ sơ ở mọi bước
--   p_tra_kho: [{ "dong_id": id dòng phiếu xuất, "so_luong": số chưa dùng trả về kho }]
-- ---------------------------------------------------------------------
create or replace function public.huy_ho_so_giam_doc(p_ho_so bigint, p_ly_do text, p_doanh_thu numeric default 0,
  p_tra_kho jsonb default '[]'::jsonb, p_bo_qua_canh_bao boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; t record; d jsonb; v_ngay date; v_dt numeric := round(coalesce(p_doanh_thu, 0)); v_ly_do text := nullif(trim(p_ly_do), '');
  v_bh numeric; v_chenh numeric; v_tra int := 0;
begin
  perform app.yeu_cau('giam_doc');
  h := app.lay_ho_so(p_ho_so);
  perform app.yeu_cau_chi_nhanh(h.chi_nhanh_id);
  if h.trang_thai in ('huy','dong') then raise exception 'Hồ sơ đã đóng hoặc đã hủy.'; end if;
  if h.tu_excel then raise exception 'Hồ sơ chuyển từ Excel không hủy ở đây được.'; end if;
  if v_ly_do is null then raise exception 'Ghi lý do hủy.'; end if;
  if v_dt < 0 then raise exception 'Doanh thu thương lượng không được âm.'; end if;
  select * into t from app.tien_ho_so(p_ho_so);
  if t.da_thu_bh > 0 then
    raise exception 'Bảo hiểm đã trả % đ cho xe này – không hủy được (chuyển phần chia tiền bảo hiểm sang xe khác trước).', app.vnd(t.da_thu_bh); end if;
  if v_dt = 0 and t.da_thu_khach > 0 and p_bo_qua_canh_bao is not null and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Khách đã trả % đ cho hồ sơ này, doanh thu thương lượng 0 đ → phải trả lại khách (lập đề nghị chi "Trả lại cọc cho khách"). Vẫn hủy?',
      app.vnd(t.da_thu_khach);
  end if;
  if v_dt > 0 and t.da_thu_khach > v_dt and p_bo_qua_canh_bao is not null and not p_bo_qua_canh_bao then
    raise exception 'CANH_BAO: Khách đã trả % đ, nhiều hơn doanh thu thương lượng % đ → phần dư % đ phải trả lại khách. Vẫn hủy?',
      app.vnd(t.da_thu_khach), app.vnd(v_dt), app.vnd(t.da_thu_khach - v_dt);
  end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  -- Tháng của các dòng sẽ thôi tính doanh thu phải còn mở
  for v_ngay in select distinct ngay_duyet from public.hang_muc
                where ho_so_id = p_ho_so and ngay_duyet is not null
                  and (trang_thai in ('duyet','dang_lam') or (v_dt = 0 and trang_thai = 'xong'))
                union select distinct ngay from public.giam_gia_lan where ho_so_id = p_ho_so and v_dt = 0 loop
    perform app.yeu_cau_thang_mo(h.chi_nhanh_id, v_ngay);
  end loop;

  -- Vật tư chưa dùng trả về kho; đề xuất vật tư còn chờ xuất thì hủy
  for d in select * from jsonb_array_elements(coalesce(p_tra_kho, '[]'::jsonb)) loop
    if coalesce((d->>'so_luong')::numeric, 0) > 0 then
      perform app.tra_vat_tu_ve_kho((d->>'dong_id')::bigint, (d->>'so_luong')::numeric, p_ho_so);
      v_tra := v_tra + 1;
    end if;
  end loop;
  update public.de_xuat_vat_tu set trang_thai = 'huy' where ho_so_id = p_ho_so and trang_thai = 'cho_xuat';

  if v_dt = 0 then
    -- như hủy cũ: hồ sơ hủy không doanh thu, không công nợ (tiền khách đã trả → phải trả lại)
    perform app.doi_trang_thai(p_ho_so, 'huy', 'Giám đốc hủy: ' || v_ly_do || case when v_tra > 0 then ' · trả ' || v_tra || ' dòng vật tư về kho' else '' end);
    update public.hang_muc set trang_thai = 'tu_choi' where ho_so_id = p_ho_so and trang_thai in ('cho_duyet','duyet','dang_lam');
    update public.ho_so set ly_do_huy = v_ly_do, khau_tru_giam_tru = 0, giam_gia = 0, huy_luc = now(), huy_boi = auth.uid(),
      nguoi_tiep_theo = null where id = p_ho_so;
    return jsonb_build_object('trang_thai', 'huy', 'doanh_thu', 0);
  end if;

  -- Có thu theo thỏa thuận: việc chưa làm thôi tính; khách trả toàn bộ; dòng thỏa thuận cho tổng phải thu = v_dt
  update public.hang_muc set trang_thai = 'tu_choi' where ho_so_id = p_ho_so and trang_thai in ('cho_duyet','duyet','dang_lam');
  select h2.* into h from public.ho_so h2 where h2.id = p_ho_so;
  if h.giam_gia <> 0 then
    insert into public.giam_gia_lan (ho_so_id, ngay, so_tien, ly_do, duyet_boi)
    values (p_ho_so, current_date, -h.giam_gia, 'Hủy hồ sơ – thu theo thỏa thuận', auth.uid());
  end if;
  select coalesce(sum(public.tien_dong_co_vat(gia_duyet, true, ngay_duyet, ty_le_vat)), 0) into v_bh
  from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong') and nguoi_tra = 'bao_hiem';
  update public.ho_so set khau_tru_giam_tru = v_bh, giam_gia = 0 where id = p_ho_so;
  select * into t from app.tien_ho_so(p_ho_so);
  v_chenh := v_dt - t.phai_thu_khach;
  if v_chenh <> 0 then
    perform app.them_dong_tien(p_ho_so, 'khach', v_chenh, 'Thu theo thỏa thuận khi hủy: ' || v_ly_do, 'thoa_thuan_huy');
  end if;
  update public.ho_so set ly_do_huy = v_ly_do, huy_thoa_thuan = true, huy_luc = now(), huy_boi = auth.uid(),
    giao_luc = coalesce(giao_luc, now()), cham_soc_luc = coalesce(cham_soc_luc, now()),
    cham_soc_ket_qua = coalesce(cham_soc_ket_qua, 'Không gọi – hồ sơ hủy'), nguoi_tiep_theo = null
  where id = p_ho_so;
  if h.trang_thai not in ('da_giao','da_gui_hs') then
    perform app.doi_trang_thai(p_ho_so, 'da_giao', 'Giám đốc hủy, thu theo thỏa thuận ' || app.vnd(v_dt) || ' đ: ' || v_ly_do
      || case when v_tra > 0 then ' · trả ' || v_tra || ' dòng vật tư về kho' else '' end);
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Giám đốc hủy, thu theo thỏa thuận ' || app.vnd(v_dt) || ' đ: ' || v_ly_do);
  end if;
  perform app.cap_nhat_dong(p_ho_so);
  return jsonb_build_object('trang_thai', (select trang_thai from public.ho_so where id = p_ho_so), 'doanh_thu', v_dt);
end $$;

-- ---------------------------------------------------------------------
-- 2. Duyệt giá xe bảo hiểm bằng 2 số (của cả xe): bảo hiểm thanh toán + khách thanh toán
-- ---------------------------------------------------------------------
create or replace function public.duyet_gia_tong(p_ho_so bigint, p_ngay date, p_bao_hiem numeric, p_khach numeric) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare h public.ho_so; v_tong numeric; v_cu numeric; v_moi numeric; v_goc numeric; f numeric; r record; kq jsonb := '[]'::jsonb;
  v_lon bigint; v_lon_ty numeric; v_thuc numeric; v_vat numeric;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.nguon_tt = 'khach' then raise exception 'Xe khách ngoài bảo hiểm không qua duyệt giá.'; end if;
  if p_bao_hiem is null or p_khach is null or p_bao_hiem < 0 or p_khach < 0 then
    raise exception 'Nhập số tiền bảo hiểm thanh toán và khách hàng thanh toán (0 nếu không có).'; end if;
  if p_ngay is null then raise exception 'Thiếu ngày duyệt.'; end if;
  v_tong := round(p_bao_hiem) + round(p_khach);
  if not exists (select 1 from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'cho_duyet') then
    raise exception 'Không có dòng báo giá nào chờ duyệt.'; end if;
  -- đã duyệt các lần trước (gồm VAT)
  select coalesce(sum(public.tien_dong_co_vat(gia_duyet, case when nguoi_tra = 'bao_hiem' then true else xuat_hd end, ngay_duyet, ty_le_vat)), 0)
    into v_cu from public.hang_muc where ho_so_id = p_ho_so and trang_thai in ('duyet','dang_lam','xong');
  v_moi := v_tong - v_cu;
  if v_moi < 0 then
    raise exception 'Tổng % đ nhỏ hơn phần đã duyệt các lần trước (% đ) – hai số là của CẢ XE.', app.vnd(v_tong), app.vnd(v_cu); end if;
  select coalesce(sum(public.tien_dong_co_vat(gia_bao, case when nguoi_tra = 'bao_hiem' then true else xuat_hd end, p_ngay, ty_le_vat)), 0)
    into v_goc from public.hang_muc where ho_so_id = p_ho_so and trang_thai = 'cho_duyet';
  if v_goc <= 0 and v_moi > 0 then raise exception 'Các dòng chờ duyệt có giá báo 0 đ – không chia được số tiền.'; end if;
  f := case when v_goc > 0 then v_moi / v_goc else 0 end;
  -- giá duyệt (chưa VAT) từng dòng = giá báo × f; dòng lớn nhất nhận phần làm tròn
  for r in select id, gia_bao, nguoi_tra, xuat_hd, ty_le_vat from public.hang_muc
           where ho_so_id = p_ho_so and trang_thai = 'cho_duyet' order by gia_bao desc, id loop
    if v_lon is null then
      v_lon := r.id;
      v_lon_ty := case when r.nguoi_tra = 'bao_hiem' or r.xuat_hd then coalesce(r.ty_le_vat, public.vat_ty_le(p_ngay)) else 0 end;
    end if;
    kq := kq || jsonb_build_object('id', r.id, 'dong_y', true, 'gia_duyet', round(r.gia_bao * f));
  end loop;
  select coalesce(sum(public.tien_dong_co_vat((e->>'gia_duyet')::numeric, case when m.nguoi_tra = 'bao_hiem' then true else m.xuat_hd end, p_ngay, m.ty_le_vat)), 0)
    into v_thuc from jsonb_array_elements(kq) e join public.hang_muc m on m.id = (e->>'id')::bigint;
  if v_thuc <> v_moi then
    v_vat := 1 + v_lon_ty;
    kq := (select jsonb_agg(case when (e->>'id')::bigint = v_lon
              then jsonb_set(e, '{gia_duyet}', to_jsonb(greatest(0, (e->>'gia_duyet')::numeric + round((v_moi - v_thuc) / v_vat)))) else e end)
           from jsonb_array_elements(kq) e);
  end if;
  return public.duyet_gia_chia(p_ho_so, p_ngay, kq, round(p_khach)) || jsonb_build_object('tong_yeu_cau', v_tong);
end $$;

-- ---------------------------------------------------------------------
-- 3. Lệnh sửa chữa: người thực hiện = tài khoản (nguoi_lam_id); ảnh lệnh bắt buộc khi giao diện mới gửi p_bat_buoc_anh
-- ---------------------------------------------------------------------
drop function if exists public.lap_lenh_sua_chua(bigint, timestamptz, jsonb);
create or replace function public.lap_lenh_sua_chua(p_ho_so bigint, p_hen_giao timestamptz, phan_cong jsonb, p_bat_buoc_anh boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare h public.ho_so; d jsonb; r public.hang_muc; v_nv public.nhan_vien; v_id uuid;
begin
  perform app.yeu_cau('cvdv','quan_ly','giam_doc');
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai not in ('da_duyet','dang_sua') then
    raise exception 'Chưa duyệt giá thì chưa lập được lệnh sửa chữa.'; end if;
  if h.bat_buoc_anh then perform app.yeu_cau_anh_nhan_xe(p_ho_so); end if;   -- 047 (cả hồ sơ bảo hành)
  if coalesce(p_bat_buoc_anh, false)
     and not exists (select 1 from public.ho_so_tep where ho_so_id = p_ho_so and buoc = 'lenh_sua_chua'
                     and tai_luc > coalesce(h.bao_gia_luc, h.ngay_vao, '-infinity'::timestamptz)) then
    raise exception 'Chưa có ảnh lệnh sửa chữa – chụp lệnh sửa chữa rồi giao việc.'; end if;
  if p_hen_giao is null and h.hen_giao is null then raise exception 'Thiếu giờ hẹn giao xe.'; end if;
  if jsonb_typeof(phan_cong) <> 'array' or jsonb_array_length(phan_cong) = 0 then
    raise exception 'Chưa giao hạng mục nào cho tổ.'; end if;

  for d in select * from jsonb_array_elements(phan_cong) loop
    select * into r from public.hang_muc where id = (d->>'id')::bigint and ho_so_id = p_ho_so for update;
    if not found then raise exception 'Dòng không thuộc hồ sơ này.'; end if;
    if r.trang_thai <> 'duyet' then raise exception 'Dòng "%" chưa được duyệt hoặc đã giao.', r.ten; end if;
    if (d->>'to_id') is null then raise exception 'Dòng "%" chưa chọn tổ.', r.ten; end if;
    v_id := nullif(d->>'nguoi_lam_id', '')::uuid;
    if v_id is not null then
      select * into v_nv from public.nhan_vien where id = v_id;
      if not found or not v_nv.hoat_dong then raise exception 'Người thực hiện của dòng "%" không còn làm việc.', r.ten; end if;
      if v_nv.chi_nhanh_id is not null and v_nv.chi_nhanh_id <> h.chi_nhanh_id then
        raise exception '% không thuộc chi nhánh của hồ sơ.', v_nv.ho_ten; end if;
    end if;
    update public.hang_muc set trang_thai = 'dang_lam', to_id = d->>'to_id', nguoi_lam_id = v_id,
      nguoi_lam = coalesce(nullif(trim(d->>'nguoi_lam'),''), case when v_id is not null then v_nv.ho_ten end)
    where id = r.id;
  end loop;

  update public.ho_so set hen_giao = coalesce(p_hen_giao, hen_giao) where id = p_ho_so;
  if h.trang_thai = 'da_duyet' then
    perform app.doi_trang_thai(p_ho_so, 'dang_sua', 'Lập lệnh sửa chữa');
  else
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Giao thêm hạng mục cho tổ');
  end if;
end $$;
revoke all on function public.lap_lenh_sua_chua(bigint, timestamptz, jsonb, boolean) from public, anon;
grant execute on function public.lap_lenh_sua_chua(bigint, timestamptz, jsonb, boolean) to authenticated;

-- Thông báo "việc mới cho tổ": hạng mục có người thực hiện (tài khoản) → gửi đúng người đó; không có thì như 054
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
    if new.nguoi_lam_id is not null and exists (select 1 from public.nhan_vien n where n.id = new.nguoi_lam_id and n.hoat_dong) then
      perform app.gui_thong_bao(new.nguoi_lam_id, 'to', v_khoa, v_tieu, array[v_dong], 'ho_so', hs.id, hs.chi_nhanh_id, v_nd);
    else
      for r in select * from app.nguoi_nhan_to(new.to_id, hs.chi_nhanh_id) loop
        perform app.gui_thong_bao(r.id, 'to', v_khoa,
          v_tieu || case when r.du_phong then ' (tổ ' || v_ten_to || ' chưa có trưởng nhóm đăng nhập)' else '' end,
          array[v_dong], 'ho_so', hs.id, hs.chi_nhanh_id, v_nd);
      end loop;
    end if;
  exception when others then
    raise warning 'Thông báo (giao tổ) lỗi, bỏ qua: %', sqlerrm;
  end;
  return null;
end $$;

-- Người thực hiện (tài khoản) thấy hạng mục được giao trong bảng việc tổ và tự báo xong được, kể cả khi không thuộc tổ đó
CREATE OR REPLACE FUNCTION public.bang_viec_to()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      'nguon_tt', h.nguon_tt, 'loai', h.loai, 'chi_nhanh_id', h.chi_nhanh_id, 'qua_detailing', h.qua_detailing,
      'hang_muc', (select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'nhom', m.nhom, 'to_id', m.to_id,
                     'nguoi_lam', m.nguoi_lam, 'nguoi_lam_id', m.nguoi_lam_id, 'trang_thai', m.trang_thai) order by m.id)
                   from public.hang_muc m where m.ho_so_id = h.id and m.trang_thai in ('dang_lam','xong')
                     and (v_to is null or m.to_id = v_to or m.nguoi_lam_id = auth.uid() or (v_to = 'DT' and h.trang_thai = 'cho_detailing'))))
      order by h.hen_giao nulls last)
    from public.ho_so h
    join public.xe x on x.id = h.xe_id
    left join public.dong_xe dx on dx.id = x.dong_xe_id
    left join public.hang_xe hx on hx.id = dx.hang_xe_id
    where h.trang_thai in ('dang_sua','cho_detailing','cho_kcs')
      and (app.co_vai_tro('giam_doc') or h.chi_nhanh_id = v_cn)
      and (v_to is null or exists (
            select 1 from public.hang_muc m where m.ho_so_id = h.id and (m.to_id = v_to or m.nguoi_lam_id = auth.uid()) and m.trang_thai in ('dang_lam','xong'))
            or (v_to = 'DT' and h.trang_thai = 'cho_detailing'))
  ), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.bao_xong_hang_muc(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET "TimeZone" TO 'Asia/Ho_Chi_Minh'
AS $function$
declare r public.hang_muc; h public.ho_so; v_to text;
begin
  select * into r from public.hang_muc where id = p_id for update;
  if not found then raise exception 'Không tìm thấy hạng mục.'; end if;
  if app.co_vai_tro('cvdv','quan_ly','giam_doc') then
    null;
  elsif app.co_vai_tro('truong_nhom') then
    select to_id into v_to from public.nhan_vien where id = auth.uid();
    if r.to_id is distinct from v_to and r.nguoi_lam_id is distinct from auth.uid() then raise exception 'Hạng mục này không thuộc tổ của bạn.' using errcode = '42501'; end if;
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
end $function$;

-- ---------------------------------------------------------------------
-- 4. Phiếu thu lệch công nợ. Phân bổ: { ho_so_id, so_tien, lech: true, ly_do } → ghi đủ số thực thu, tạo đề nghị chỉnh.
-- ---------------------------------------------------------------------
create or replace function app.phan_bo_phieu(p_phieu bigint, p_ds jsonb, p_tinh_chat text) returns void
language plpgsql security definer set search_path = public as $$
declare d jsonb; v_ho_so bigint; v_dvn bigint; v_nguoi text; v_tien numeric; t record; v_tong numeric; v_phieu public.phieu_thu_chi;
  v_ds_ho_so bigint[] := '{}'; h public.ho_so; dv public.dich_vu_nhanh; v_da numeric; v_lech boolean; v_con numeric; v_dn bigint; v_nguoi_duyet uuid;
begin
  select * into v_phieu from public.phieu_thu_chi where id = p_phieu;
  for d in select * from jsonb_array_elements(coalesce(p_ds, '[]'::jsonb)) loop
    v_ho_so := (d->>'ho_so_id')::bigint; v_dvn := (d->>'dich_vu_nhanh_id')::bigint;
    v_tien := (d->>'so_tien')::numeric;
    v_lech := coalesce((d->>'lech')::boolean, false) and p_tinh_chat in ('thu_khach','thu_bao_hiem');
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
        v_con := case when v_nguoi = 'bao_hiem' then t.con_no_bh else t.con_no_khach end;
        if v_lech then
          if nullif(trim(d->>'ly_do'), '') is null then
            raise exception 'Xe %: thu % đ khác công nợ % đ – ghi lý do lệch.', h.ma, app.vnd(v_tien), app.vnd(v_con); end if;
          if h.trang_thai = 'huy' then raise exception 'Hồ sơ % đã hủy.', h.ma; end if;
        else
          if v_nguoi = 'bao_hiem' and v_tien > t.con_no_bh then
            raise exception 'Phân bổ % đ vượt số bảo hiểm còn nợ % đ của hồ sơ.',
              app.vnd(v_tien), app.vnd(t.con_no_bh); end if;
          if v_nguoi = 'khach' and v_tien > t.con_no_khach then
            raise exception 'Thu % đ vượt số khách còn nợ % đ của hồ sơ. Nếu là tiền cọc, chọn mục "Thu cọc".',
              app.vnd(v_tien), app.vnd(t.con_no_khach); end if;
        end if;
      end if;
      insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (p_phieu, v_ho_so, v_nguoi, v_tien);
      if v_lech and v_tien <> v_con then
        insert into public.de_nghi_dieu_chinh (chi_nhanh_id, ho_so_id, phieu_id, nguoi_tra, cong_no, thuc_thu, ly_do, nguoi_lap)
        values (h.chi_nhanh_id, v_ho_so, p_phieu, v_nguoi, v_con, v_tien, trim(d->>'ly_do'), auth.uid()) returning id into v_dn;
        perform app.ghi_nhat_ky(v_ho_so, h.trang_thai, h.trang_thai,
          'Thu ' || app.vnd(v_tien) || ' đ (' || case when v_nguoi = 'bao_hiem' then 'bảo hiểm' else 'khách' end || ' còn nợ ' || app.vnd(v_con)
          || ' đ) – lệch ' || app.vnd(v_tien - v_con) || ' đ, chờ duyệt chỉnh công nợ: ' || trim(d->>'ly_do'));
        begin
          for v_nguoi_duyet in select * from app.nguoi_duyet(array['quan_ly','giam_doc'], h.chi_nhanh_id, auth.uid()) loop
            perform app.gui_thong_bao(v_nguoi_duyet, 'tien', 'tien:dieu_chinh:' || v_dn,
              'Thu lệch công nợ – xe ' || app.nhan_xe_thong_bao(h.id),
              array['Công nợ ' || app.vnd(v_con) || ' đ, thực thu ' || app.vnd(v_tien) || ' đ (lệch ' || app.vnd(v_tien - v_con) || ' đ)',
                    'Lý do: ' || trim(d->>'ly_do')],
              'ho_so', h.id, h.chi_nhanh_id, 'Duyệt để chỉnh công nợ về số thực thu');
          end loop;
        exception when others then raise warning 'Thông báo (thu lệch) lỗi, bỏ qua: %', sqlerrm;
        end;
      end if;
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

-- Quản lý chung / giám đốc duyệt (hoặc từ chối) đề nghị chỉnh công nợ về số thực thu
create or replace function public.duyet_dieu_chinh_cong_no(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns jsonb
language plpgsql security definer set search_path = public set "TimeZone" to 'Asia/Ho_Chi_Minh' as $$
declare dn public.de_nghi_dieu_chinh; h public.ho_so; t record; v_con numeric; v_hm bigint; v_chinh numeric;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into dn from public.de_nghi_dieu_chinh where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị chỉnh công nợ.'; end if;
  perform app.yeu_cau_chi_nhanh(dn.chi_nhanh_id);
  if dn.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị này đã được xử lý.'; end if;
  h := app.lay_ho_so(dn.ho_so_id);
  if not coalesce(p_dong_y, false) then
    if nullif(trim(p_ly_do), '') is null then raise exception 'Ghi lý do không duyệt.'; end if;
    update public.de_nghi_dieu_chinh set trang_thai = 'tu_choi', duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = trim(p_ly_do) where id = p_id;
    perform app.ghi_nhat_ky(h.id, h.trang_thai, h.trang_thai, 'Không duyệt chỉnh công nợ theo thực thu: ' || trim(p_ly_do));
    return jsonb_build_object('trang_thai', 'tu_choi');
  end if;
  if dn.phieu_id is not null and exists (select 1 from public.phieu_thu_chi where id = dn.phieu_id and trang_thai <> 'hieu_luc') then
    update public.de_nghi_dieu_chinh set trang_thai = 'huy', duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = 'Phiếu thu đã hủy' where id = p_id;
    raise exception 'Phiếu thu của đề nghị này đã hủy – không chỉnh nữa.';
  end if;
  if h.trang_thai = 'huy' then raise exception 'Hồ sơ đã hủy.'; end if;
  perform app.yeu_cau_thang_mo(h.chi_nhanh_id, current_date);
  select * into t from app.tien_ho_so(h.id);
  v_con := case when dn.nguoi_tra = 'bao_hiem' then t.con_no_bh else t.con_no_khach end;
  v_chinh := -v_con;     -- công nợ bên đó về 0: còn nợ → giảm doanh thu; trả dư (nợ âm) → tăng doanh thu
  if v_chinh <> 0 then
    v_hm := app.them_dong_tien(h.id, dn.nguoi_tra, v_chinh,
      'Điều chỉnh theo thực thu' || case when dn.phieu_id is not null then ' (phiếu #' || dn.phieu_id || ')' else '' end || ': ' || dn.ly_do, 'dieu_chinh');
  end if;
  update public.de_nghi_dieu_chinh set trang_thai = 'da_duyet', duyet_boi = auth.uid(), duyet_luc = now(),
    so_tien_dieu_chinh = v_chinh, hang_muc_id = v_hm where id = p_id;
  perform app.ghi_nhat_ky(h.id, h.trang_thai, h.trang_thai,
    'Duyệt chỉnh công nợ ' || case when dn.nguoi_tra = 'bao_hiem' then 'bảo hiểm' else 'khách' end || ' theo thực thu: doanh thu '
    || case when v_chinh >= 0 then '+' else '' end || app.vnd(v_chinh) || ' đ');
  perform app.cap_nhat_dong(h.id);
  return jsonb_build_object('trang_thai', 'da_duyet', 'dieu_chinh', v_chinh,
    'ho_so_trang_thai', (select trang_thai from public.ho_so where id = h.id));
end $$;

-- Hủy phiếu thu: đề nghị chỉnh còn chờ của phiếu đó thôi hiệu lực
create or replace function app.huy_de_nghi_dieu_chinh_theo_phieu() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.trang_thai = 'huy' and old.trang_thai is distinct from 'huy' then
    update public.de_nghi_dieu_chinh set trang_thai = 'huy', duyet_luc = now(), ly_do_tu_choi = 'Phiếu thu đã hủy'
    where phieu_id = new.id and trang_thai = 'cho_duyet';
  end if;
  return null;
end $$;
drop trigger if exists de_nghi_dieu_chinh_huy_phieu on public.phieu_thu_chi;
create trigger de_nghi_dieu_chinh_huy_phieu after update of trang_thai on public.phieu_thu_chi
  for each row execute function app.huy_de_nghi_dieu_chinh_theo_phieu();

-- Bảng xem: đề nghị chỉnh kèm biển số, người lập / duyệt
create or replace view public.v_de_nghi_dieu_chinh with (security_invoker = true) as
select d.*, h.ma as ma_ho_so, public.bien_so_hien_thi(x.bien_so) as bien_so, h.trang_thai as trang_thai_ho_so,
  nl.ho_ten as nguoi_lap_ten, nd.ho_ten as duyet_boi_ten
from public.de_nghi_dieu_chinh d
join public.ho_so h on h.id = d.ho_so_id
join public.xe x on x.id = h.xe_id
left join public.nhan_vien nl on nl.id = d.nguoi_lap
left join public.nhan_vien nd on nd.id = d.duyet_boi;
grant select on public.v_de_nghi_dieu_chinh to authenticated;
revoke all on public.v_de_nghi_dieu_chinh from anon;

do $$ declare f text; begin
  foreach f in array array['public.huy_ho_so_giam_doc(bigint,text,numeric,jsonb,boolean)', 'public.duyet_gia_tong(bigint,date,numeric,numeric)',
    'public.duyet_dieu_chinh_cong_no(bigint,boolean,text)', 'app.them_dong_tien(bigint,text,numeric,text,text)',
    'app.tra_vat_tu_ve_kho(bigint,numeric,bigint)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c ilike 'timezone=%')
      and p.proname <> 'buoc_tep_mo'
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

notify pgrst, 'reload schema';
