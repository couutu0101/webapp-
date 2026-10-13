-- =====================================================================
-- 021 (13/10/2026): Kế toán cũng xem được Bảng việc xưởng ở Việc hôm nay (biết xe sắp xong để chuẩn bị thu tiền).
--   Tương thích ngược: chỉ nới quyền gọi hàm.
-- =====================================================================
create or replace function public.bang_viec_to() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to text; v_cn text;
begin
  if not app.co_vai_tro('truong_nhom','cvdv','ke_toan','quan_ly','giam_doc') then
    raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  select to_id, chi_nhanh_id into v_to, v_cn from public.nhan_vien where id = auth.uid();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'ho_so_id', h.id, 'ma', h.ma, 'bien_so', public.bien_so_hien_thi(x.bien_so),
      'xe', concat_ws(' ', hx.ten, dx.ten, x.mau), 'hen_giao', h.hen_giao, 'trang_thai', h.trang_thai,
      'tinh_trang_xe', h.tinh_trang_xe,
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
      and (v_to is null or not app.co_vai_tro('truong_nhom') or exists (
            select 1 from public.hang_muc m where m.ho_so_id = h.id and m.to_id = v_to and m.trang_thai in ('dang_lam','xong')))
  ), '[]'::jsonb);
end $$;

