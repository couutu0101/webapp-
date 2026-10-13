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
