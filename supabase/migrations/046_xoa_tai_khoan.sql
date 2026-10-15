-- =====================================================================
-- 046: Giám đốc xóa tài khoản nhân viên
--  - Chỉ xóa được tài khoản CHƯA có dữ liệu nào trong phần mềm (tạo nhầm, chưa dùng):
--    kiểm mọi cột uuid của các bảng public (người tạo, người duyệt, người làm bước
--    tiếp theo, nhật ký…). Đã có dữ liệu → báo khóa tài khoản (bỏ "Đang làm") để giữ
--    lịch sử ai làm gì.
--  - Không xóa chính mình, không xóa tài khoản giám đốc.
--  - Xóa auth.users → nhan_vien, auth.identities, auth.sessions xóa theo (on delete cascade).
-- Tương thích ngược: chỉ thêm hàm mới.
-- =====================================================================

create or replace function public.xoa_tai_khoan_nhan_vien(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  nv public.nhan_vien;
  c record;
  v_co boolean;
  v_noi text[] := '{}';
begin
  if not app.co_vai_tro('giam_doc') then
    raise exception 'Chỉ giám đốc được xóa tài khoản.' using errcode = '42501';
  end if;
  if p_id = auth.uid() then
    raise exception 'Không tự xóa tài khoản của chính mình được.';
  end if;
  select * into nv from public.nhan_vien where id = p_id for update;
  if not found then
    raise exception 'Không tìm thấy tài khoản.';
  end if;
  if 'giam_doc' = any(nv.vai_tro) then
    raise exception 'Không xóa tài khoản giám đốc được.';
  end if;

  for c in
    select col.table_name, col.column_name
    from information_schema.columns col
    join information_schema.tables t on t.table_schema = col.table_schema and t.table_name = col.table_name
    where col.table_schema = 'public' and t.table_type = 'BASE TABLE' and col.data_type = 'uuid'
      and not (col.table_name = 'nhan_vien' and col.column_name = 'id')
  loop
    execute format('select exists (select 1 from public.%I where %I = $1)', c.table_name, c.column_name)
      into v_co using p_id;
    if v_co then v_noi := v_noi || c.table_name; end if;
  end loop;

  if cardinality(v_noi) > 0 then
    raise exception 'Tài khoản % đã có dữ liệu trong phần mềm nên không xóa được (để giữ lịch sử ai làm gì). Muốn ngừng cho đăng nhập: bấm "Sửa quyền", bỏ chọn "Đang làm" để khóa tài khoản.',
      nv.ho_ten using detail = array_to_string(array(select distinct unnest(v_noi)), ', ');
  end if;

  delete from public.nhan_vien where id = p_id;
  delete from auth.users where id = p_id;
  return jsonb_build_object('id', p_id, 'ho_ten', nv.ho_ten);
end $$;

revoke all on function public.xoa_tai_khoan_nhan_vien(uuid) from public, anon;
grant execute on function public.xoa_tai_khoan_nhan_vien(uuid) to authenticated;

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
