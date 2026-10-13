-- =====================================================================
-- 016 (13/10/2026): Giám đốc được tự duyệt đề nghị chi do mình lập
--   (giống đề nghị mua – 015). Người khác vẫn không tự duyệt phiếu mình lập.
-- =====================================================================
create or replace function public.duyet_de_nghi_chi(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; v_muc numeric := app.cai_dat_so('han_muc_chi_quan_ly', 2000000);
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
  if not p_dong_y and nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.'; end if;
  update public.de_nghi_chi set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
end $$;
