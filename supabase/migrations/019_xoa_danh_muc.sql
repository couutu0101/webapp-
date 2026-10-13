-- =====================================================================
-- 019 (13/10/2026): XÓA DÒNG DANH MỤC
--   Giám đốc, kế toán xóa được dòng danh mục (hãng BH, GDV, hãng xe, dòng xe, mục thu chi, NCC, đơn vị liên quan,
--   tài khoản quỹ, thuế suất VAT) khi dòng đó CHƯA được dùng ở đâu. Đã dùng (có hồ sơ, phiếu… trỏ tới) thì báo
--   và hướng dẫn bỏ chọn "Đang dùng". Cài đặt không xóa.
--   Tương thích ngược: chỉ thêm hàm.
-- =====================================================================
create or replace function public.xoa_danh_muc(p_bang text, p_khoa text) returns void
language plpgsql security definer set search_path = public as $$
declare v_cot text; v_so bigint;
begin
  perform app.yeu_cau('giam_doc', 'ke_toan');
  if p_bang not in ('hang_bao_hiem','giam_dinh_vien','hang_xe','dong_xe','muc_thu_chi','nha_cung_cap',
                    'don_vi_lien_quan','tai_khoan_quy','thue_suat_vat') then
    raise exception 'Không xóa được mục "%".', p_bang;
  end if;
  v_cot := case when p_bang = 'thue_suat_vat' then 'ap_dung_tu' else 'id' end;
  if p_bang = 'thue_suat_vat' and (select count(*) from public.thue_suat_vat) <= 1 then
    raise exception 'Phải còn ít nhất một dòng thuế suất.';
  end if;
  begin
    execute format('delete from public.%I where %I::text = $1', p_bang, v_cot) using p_khoa;
    get diagnostics v_so = row_count;
  exception when foreign_key_violation then
    raise exception 'Mục này đang được dùng (có hồ sơ, phiếu hoặc danh mục khác trỏ tới) nên không xóa được. Bỏ chọn "Đang dùng" để ẩn đi.';
  end;
  if v_so = 0 then raise exception 'Không tìm thấy dòng cần xóa.'; end if;
end $$;
revoke execute on function public.xoa_danh_muc(text, text) from public, anon;
grant execute on function public.xoa_danh_muc(text, text) to authenticated;
