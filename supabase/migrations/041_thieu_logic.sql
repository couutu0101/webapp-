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
