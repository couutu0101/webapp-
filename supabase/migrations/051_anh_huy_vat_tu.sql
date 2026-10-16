-- =====================================================================
-- 051: Ảnh hủy vật tư cho xe bảo hiểm (anh Thuận yêu cầu 16/10 17:19)
--  - them_tep nhận thêm bước 'huy_vat_tu' (ảnh / PDF lúc hủy phụ tùng, vật tư thay ra – gửi kèm hồ sơ bảo hiểm).
--    Không bắt buộc. Chỉ thêm giá trị được phép, không đổi tham số; giao diện cũ không gửi bước này.
-- (Cùng đợt, giao diện: ô ảnh không mở thẳng camera nữa – chọn ảnh có sẵn trong máy; không đổi CSDL.)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.them_tep(p_ho_so bigint, p_buoc text, p_loai text, p_duong_dan text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.ho_so; v_id bigint; v_goc text;
begin
  if not (app.la_nhan_vien() or app.co_vai_tro('truong_nhom')) then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  v_goc := h.chi_nhanh_id || '/' || h.ma || '/';
  if p_duong_dan is null or left(p_duong_dan, length(v_goc)) <> v_goc or position('..' in p_duong_dan) > 0 then
    raise exception 'Tệp không thuộc thư mục của hồ sơ % – tải lại ảnh từ trang hồ sơ.', h.ma;
  end if;
  if p_buoc not in ('tiep_nhan','duyet_gia','phat_sinh','kcs','giao_xe','ho_so_bh','khac',
                    'bao_gia','nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau','huy_vat_tu') then
    raise exception 'Bước của tệp không hợp lệ.';
  end if;
  if coalesce(p_loai, 'anh') not in ('anh','bien_ban') then raise exception 'Loại tệp không hợp lệ.'; end if;
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, coalesce(p_loai, 'anh'), p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $function$;

notify pgrst, 'reload schema';
