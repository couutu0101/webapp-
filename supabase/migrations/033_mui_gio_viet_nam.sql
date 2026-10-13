-- =====================================================================
-- 033 (14/10/2026): MÚI GIỜ VIỆT NAM CHO CƠ SỞ DỮ LIỆU
--  Lỗi: Supabase mặc định giờ UTC → từ 0h đến 7h sáng (giờ Việt Nam) "hôm nay" của máy chủ vẫn là hôm qua,
--  nên ghi dịch vụ nhanh, phiếu thu, phiếu nhập… với ngày hôm nay bị báo "Ngày không được sau hôm nay",
--  hạn kiểm tra, ngày lập… tính lệch một ngày.
--  Sửa: đặt múi giờ Asia/Ho_Chi_Minh cho cả cơ sở dữ liệu và các vai trò API (PostgREST áp theo vai trò),
--  và gắn múi giờ thẳng vào mọi hàm có dùng ngày giờ hiện tại (chạy đúng kể cả kết nối cũ chưa nhận cài đặt mới).
--  Tương thích ngược: chỉ đổi cách tính "hôm nay" cho đúng giờ Việt Nam.
-- =====================================================================

do $$ begin
  execute format('alter database %I set timezone to %L', current_database(), 'Asia/Ho_Chi_Minh');
exception when others then raise notice 'Không đặt được múi giờ cho cơ sở dữ liệu: %', sqlerrm;
end $$;

do $$ declare r text; begin
  foreach r in array array['authenticated', 'anon', 'authenticator', 'service_role'] loop
    begin
      if exists (select 1 from pg_roles where rolname = r) then
        execute format('alter role %I set timezone to %L', r, 'Asia/Ho_Chi_Minh');
      end if;
    exception when others then raise notice 'Không đặt được múi giờ cho vai trò %: %', r, sqlerrm;
    end;
  end loop;
end $$;

-- Mọi hàm của ứng dụng có dùng ngày giờ hiện tại: chạy theo giờ Việt Nam
do $$ declare f record; begin
  for f in
    select p.oid::regprocedure as ham
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prokind = 'f'
      and (p.prosrc ilike '%current_date%' or p.prosrc ilike '%now()%' or p.prosrc ilike '%localtimestamp%' or p.prosrc ilike '%current_timestamp%')
  loop
    execute format('alter function %s set timezone to %L', f.ham, 'Asia/Ho_Chi_Minh');
  end loop;
end $$;

set timezone to 'Asia/Ho_Chi_Minh';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';
