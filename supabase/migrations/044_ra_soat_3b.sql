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
