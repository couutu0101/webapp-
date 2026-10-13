-- =====================================================================
-- 020 (13/10/2026): KẾT QUẢ DUYỆT GIÁ CHIA CÔNG NỢ NGAY – xe bảo hiểm
--   Ở hộp "Kết quả duyệt giá" nhập luôn 3 số: Tổng giá duyệt (có VAT) – Bảo hiểm chi trả – Khách hàng chi trả.
--   Phần khách chi trả = các dòng khách tự trả + khấu trừ / giảm trừ của hãng (ho_so.khau_tru_giam_tru).
--   Lưu xong, công nợ tách thành hai: nợ của hãng bảo hiểm và nợ của chủ xe; khi giao xe, phiếu thu hiện nợ khách.
--   Tương thích ngược: hàm duyet_gia cũ giữ nguyên; thêm hàm duyet_gia_chia.
-- =====================================================================
create or replace function public.duyet_gia_chia(p_ho_so bigint, p_ngay date, ket_qua jsonb, p_khach_tra numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_tong numeric; v_khach_dong numeric; v_khau_tru numeric;
begin
  perform public.duyet_gia(p_ho_so, p_ngay, ket_qua);
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
  v_khau_tru := round(p_khach_tra - v_khach_dong);
  if v_khau_tru <> h.khau_tru_giam_tru then
    update public.ho_so set khau_tru_giam_tru = v_khau_tru where id = p_ho_so;
    perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
      'Chia công nợ: bảo hiểm chi trả ' || app.vnd(v_tong - p_khach_tra) || ' đ, khách chi trả ' || app.vnd(p_khach_tra)
      || ' đ (khấu trừ – giảm trừ ' || app.vnd(v_khau_tru) || ' đ)');
  end if;
  return jsonb_build_object('tong', v_tong, 'bao_hiem', v_tong - p_khach_tra, 'khach', p_khach_tra, 'khau_tru', v_khau_tru);
end $$;
revoke execute on function public.duyet_gia_chia(bigint, date, jsonb, numeric) from public, anon;
grant execute on function public.duyet_gia_chia(bigint, date, jsonb, numeric) to authenticated;
