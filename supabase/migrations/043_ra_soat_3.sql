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
