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
