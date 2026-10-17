-- =====================================================================
-- 055: KHÓA ẢNH THEO BƯỚC (anh Thuận yêu cầu 17/10 20:01: "Khi qua bước nào thì ảnh bước trước khóa lại không chỉnh sửa nữa")
--  Anh chọn: khóa MỌI ảnh theo bước; ảnh đã khóa chỉ QUẢN LÝ CHUNG hoặc GIÁM ĐỐC tải thay / bổ sung, phải ghi lý do
--  (lưu ở ho_so_tep.ly_do_mo_khoa + nhật ký hồ sơ).
--  Bước tệp được thêm khi hồ sơ đang ở các trạng thái sau (ngoài khoảng đó là ĐÃ KHÓA):
--    nx_* / nt_* (6 ảnh nhận xe) : tiep_nhan; ô CHƯA CÓ ẢNH thì bổ sung được mọi lúc (trừ hồ sơ hủy) – khóa là không THAY ảnh đã có
--    tiep_nhan (ảnh nhận xe kiểu cũ): tiep_nhan; hồ sơ chưa có ảnh nhận xe nào (cả 6 ô) thì bổ sung được
--    bao_gia, duyet_gia          : tiep_nhan → cho_kcs (còn lập báo giá / duyệt giá bổ sung được)
--    phat_sinh                   : dang_sua, cho_detailing, cho_kcs
--    lenh_sua_chua (056, ảnh lệnh): da_duyet → cho_kcs (giao thêm cho tổ cũng chụp lệnh)
--    kcs (ảnh sau sửa)           : dang_sua, cho_detailing, cho_kcs – khóa khi KCS đạt
--    giao_xe                     : dat_kcs; và trong NGÀY giao xe (giao xong chụp bổ sung trong ngày)
--    huy_vat_tu                  : da_duyet → da_gui_hs (như 051)
--    ho_so_bh                    : dat_kcs, da_giao, da_gui_hs
--    giay_to_xe, khac            : không khóa (giấy tờ xe, tệp khác) – trừ hồ sơ hủy
--  Hồ sơ hủy: chỉ quản lý chung / giám đốc (có lý do).
--  TƯƠNG THÍCH: them_tep thêm tham số p_ly_do (mặc định null) – giao diện cũ gọi 4 tham số vẫn chạy; tải ảnh
--  vào bước đã khóa từ giao diện cũ sẽ bị chặn với lời báo tiếng Việt (đúng ý khóa).
-- =====================================================================

alter table public.ho_so_tep add column if not exists ly_do_mo_khoa text;
comment on column public.ho_so_tep.ly_do_mo_khoa is '055: tệp tải vào bước đã khóa (quản lý chung / giám đốc) – lý do';

-- Bước tệp còn mở với hồ sơ này không (không xét vai trò). p_co_san: bước đã có tệp (dùng cho 6 ô ảnh nhận xe).
create or replace function app.buoc_tep_mo(p_tt text, p_buoc text, p_co_san boolean, p_giao_luc timestamptz) returns boolean
language sql stable set search_path = public as $$
  select case
    when p_tt = 'huy' then false
    when p_buoc in ('giay_to_xe', 'khac') then true
    when p_buoc in ('nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau') then p_tt = 'tiep_nhan' or not p_co_san
    when p_buoc = 'tiep_nhan' then p_tt = 'tiep_nhan' or not p_co_san
    when p_buoc in ('bao_gia', 'duyet_gia') then p_tt in ('tiep_nhan','bao_gia','da_duyet','dang_sua','cho_detailing','cho_kcs')
    when p_buoc = 'phat_sinh' then p_tt in ('dang_sua','cho_detailing','cho_kcs')
    when p_buoc = 'lenh_sua_chua' then p_tt in ('da_duyet','dang_sua','cho_detailing','cho_kcs')
    when p_buoc = 'kcs' then p_tt in ('dang_sua','cho_detailing','cho_kcs')
    when p_buoc = 'giao_xe' then p_tt = 'dat_kcs'
      or (p_giao_luc is not null and timezone('Asia/Ho_Chi_Minh', p_giao_luc)::date = timezone('Asia/Ho_Chi_Minh', now())::date)
    when p_buoc = 'huy_vat_tu' then p_tt in ('da_duyet','dang_sua','cho_detailing','cho_kcs','dat_kcs','da_giao','da_gui_hs')
    when p_buoc = 'ho_so_bh' then p_tt in ('dat_kcs','da_giao','da_gui_hs')
    else false
  end
$$;

drop function if exists public.them_tep(bigint, text, text, text);
create or replace function public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text, p_ly_do text default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_id bigint; v_goc text; v_mo boolean; v_ly_do text := nullif(trim(p_ly_do), '');
  v_ten text := case p_buoc
    when 'nx_truoc' then 'nhận xe – phía trước' when 'nx_sau' then 'nhận xe – phía sau' when 'nx_trai' then 'nhận xe – bên trái'
    when 'nx_phai' then 'nhận xe – bên phải' when 'nt_truoc' then 'nội thất phía trước' when 'nt_sau' then 'nội thất phía sau'
    when 'tiep_nhan' then 'nhận xe' when 'bao_gia' then 'báo giá' when 'duyet_gia' then 'duyệt giá' when 'phat_sinh' then 'phát sinh'
    when 'kcs' then 'KCS' when 'lenh_sua_chua' then 'lệnh sửa chữa' when 'giao_xe' then 'giao xe' when 'huy_vat_tu' then 'hủy vật tư' when 'ho_so_bh' then 'hồ sơ bảo hiểm'
    else p_buoc end;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  v_goc := h.chi_nhanh_id || '/' || h.ma || '/';
  if p_duong_dan is null or left(p_duong_dan, length(v_goc)) <> v_goc or position('..' in p_duong_dan) > 0 then
    raise exception 'Tệp không thuộc thư mục của hồ sơ % – tải lại ảnh từ trang hồ sơ.', h.ma;
  end if;
  if p_buoc not in ('tiep_nhan','duyet_gia','phat_sinh','kcs','giao_xe','ho_so_bh','khac',
                    'bao_gia','nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau','huy_vat_tu','giay_to_xe','lenh_sua_chua') then
    raise exception 'Bước của tệp không hợp lệ.';
  end if;
  if coalesce(p_loai, 'anh') not in ('anh','bien_ban') then raise exception 'Loại tệp không hợp lệ.'; end if;
  v_mo := app.buoc_tep_mo(h.trang_thai, p_buoc,
    exists (select 1 from public.ho_so_tep t where t.ho_so_id = p_ho_so
      and (t.buoc = p_buoc or (p_buoc = 'tiep_nhan' and t.buoc in ('nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau')))), h.giao_luc);
  if v_mo then
    v_ly_do := null;
  else
    if not app.co_vai_tro('quan_ly', 'giam_doc') then
      raise exception 'Ảnh % đã khóa vì hồ sơ đã qua bước này – nhờ quản lý chung hoặc giám đốc nếu cần thay.', v_ten
        using errcode = '42501';
    end if;
    if v_ly_do is null then
      raise exception 'Ảnh % đã khóa – ghi lý do để tải thay / bổ sung.', v_ten;
    end if;
  end if;
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi, ly_do_mo_khoa)
  values (p_ho_so, p_buoc, coalesce(p_loai, 'anh'), p_duong_dan, auth.uid(), v_ly_do) returning id into v_id;
  if v_ly_do is not null then
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai, 'Tải ảnh ' || v_ten || ' khi đã khóa – lý do: ' || v_ly_do);
  end if;
  return v_id;
end $$;
revoke all on function public.them_tep(bigint, text, text, text, text) from public, anon;
grant execute on function public.them_tep(bigint, text, text, text, text) to authenticated;
revoke all on function app.buoc_tep_mo(text, text, boolean, timestamptz) from public, anon;
grant execute on function app.buoc_tep_mo(text, text, boolean, timestamptz) to authenticated;

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
