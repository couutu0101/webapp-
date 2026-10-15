-- =====================================================================
-- 045: Chi nhánh Phan Huy Ích (PHI) + giám đốc chuyển chi nhánh làm việc
--  - Thêm chi nhánh PHI (hạch toán độc lập như Tô Ký: hồ sơ, thu chi, kho,
--    lương, chốt tháng… đều theo chi_nhanh_id; mã chứng từ tự có tiền tố PHI-).
--  - Một tài khoản quỹ "Tiền mặt" (mặc định) để PHI ghi được phiếu ngay;
--    kế toán PHI thêm tài khoản ngân hàng ở Danh mục.
--  - Giám đốc có nút chọn chi nhánh: public.doi_chi_nhanh_lam_viec(p_cn) đổi
--    nhan_vien.chi_nhanh_id của chính giám đốc → app.chi_nhanh() (mặc định của
--    mọi lệnh ghi và báo cáo) theo chi nhánh đang chọn. Nhân viên khác và cổ đông
--    vẫn gắn cố định một chi nhánh.
--  - app.nhan_vien_dau: giám đốc là người dự phòng của MỌI chi nhánh (trước đây
--    chỉ chi nhánh giám đốc đang gắn → PHI không có ai nhận việc khi giám đốc
--    đang chọn Tô Ký). Với một chi nhánh như hiện nay kết quả không đổi.
-- Tương thích ngược: chỉ thêm dữ liệu / hàm mới; giao diện cũ không gọi hàm mới.
-- =====================================================================

insert into public.chi_nhanh (id, ten, dia_chi) values
  ('PHI', 'Gara Hoàng Sơn – CN Phan Huy Ích', '332 Phan Huy Ích, Phường An Hội Tây, TP.HCM')
on conflict (id) do nothing;

insert into public.tai_khoan_quy (chi_nhanh_id, ten, mac_dinh)
select 'PHI', 'Tiền mặt', true
where not exists (select 1 from public.tai_khoan_quy where chi_nhanh_id = 'PHI');

create or replace function app.nhan_vien_dau(p_vai_tro text, p_chi_nhanh text)
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.nhan_vien
  where hoat_dong and (p_vai_tro = any(vai_tro) or 'giam_doc' = any(vai_tro))
    and (chi_nhanh_id = p_chi_nhanh or chi_nhanh_id is null or 'giam_doc' = any(vai_tro))
  order by (p_vai_tro = any(vai_tro)) desc, (chi_nhanh_id is not distinct from p_chi_nhanh) desc,
           (chi_nhanh_id is null), ho_ten limit 1
$$;

create or replace function public.doi_chi_nhanh_lam_viec(p_cn text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.chi_nhanh;
begin
  if not app.co_vai_tro('giam_doc') then
    raise exception 'Chỉ giám đốc được chuyển chi nhánh làm việc.';
  end if;
  select * into r from public.chi_nhanh where id = p_cn;
  if not found or not r.hoat_dong then
    raise exception 'Chi nhánh không hợp lệ.';
  end if;
  update public.nhan_vien set chi_nhanh_id = p_cn where id = auth.uid();
  return jsonb_build_object('chi_nhanh_id', r.id, 'ten', r.ten);
end $$;

revoke all on function public.doi_chi_nhanh_lam_viec(text) from public, anon;
grant execute on function public.doi_chi_nhanh_lam_viec(text) to authenticated;

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
