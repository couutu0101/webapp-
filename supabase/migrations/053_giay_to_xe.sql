-- =====================================================================
-- 053: Ảnh, giấy tờ xe ngay trong hộp "Lập báo giá" (anh Thuận yêu cầu 17/10 11:34)
--  - them_tep nhận thêm bước 'giay_to_xe' (ảnh xe, đăng ký, đăng kiểm, bảo hiểm xe, CCCD chủ xe… tải lúc lập báo giá).
--    Không bắt buộc. Chỉ thêm một giá trị được phép, không đổi tham số, quyền hay cách kiểm đường dẫn;
--    giao diện cũ không gửi bước này nên vẫn chạy bình thường.
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
                    'bao_gia','nx_truoc','nx_sau','nx_trai','nx_phai','nt_truoc','nt_sau','huy_vat_tu','giay_to_xe') then
    raise exception 'Bước của tệp không hợp lệ.';
  end if;
  if coalesce(p_loai, 'anh') not in ('anh','bien_ban') then raise exception 'Loại tệp không hợp lệ.'; end if;
  insert into public.ho_so_tep (ho_so_id, buoc, loai, duong_dan, tai_boi)
  values (p_ho_so, p_buoc, coalesce(p_loai, 'anh'), p_duong_dan, auth.uid()) returning id into v_id;
  return v_id;
end $function$;

notify pgrst, 'reload schema';
