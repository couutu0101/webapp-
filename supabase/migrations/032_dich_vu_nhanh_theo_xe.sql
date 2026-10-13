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
