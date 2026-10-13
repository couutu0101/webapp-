-- =====================================================================
-- 017 (13/10/2026): GIÁM ĐỐC TẠO TÀI KHOẢN NHÂN VIÊN – không cần gửi email mời
--   - Tên đăng nhập = tên + bộ phận (vd duy.cvdv, tien.ketoan, han.dongson). Đăng nhập gõ tên đăng nhập,
--     phần mềm tự ghép thành địa chỉ nội bộ <tên>@nv.autohoangson.com. Giám đốc vẫn đăng nhập bằng email.
--   - Giám đốc: tạo tài khoản + cấp quyền một lần, đặt lại mật khẩu cho mọi tài khoản.
--   - Tài khoản mới / vừa được đặt lại mật khẩu: lần đăng nhập đầu BẮT ĐỔI mật khẩu riêng.
--   Tương thích ngược: thêm cột và hàm mới.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

alter table public.nhan_vien add column if not exists ten_dang_nhap text;
alter table public.nhan_vien add column if not exists phai_doi_mat_khau boolean not null default false;
create unique index if not exists nhan_vien_ten_dang_nhap_key on public.nhan_vien (lower(ten_dang_nhap)) where ten_dang_nhap is not null;

create or replace function app.email_noi_bo(p_ten text) returns text language sql immutable as $$
  select lower(trim(p_ten)) || '@nv.autohoangson.com'
$$;

create or replace function app.kiem_mat_khau(p_mk text) returns void language plpgsql as $$
begin
  if p_mk is null or length(p_mk) < 6 then raise exception 'Mật khẩu cần ít nhất 6 ký tự.'; end if;
end $$;

-- Tạo tài khoản. p: {ho_ten, ten_dang_nhap, mat_khau, chi_nhanh_id, vai_tro: [...], to_id}
create or replace function public.tao_tai_khoan_nhan_vien(p jsonb) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid := gen_random_uuid(); v_ten text := lower(trim(coalesce(p->>'ten_dang_nhap', ''))); v_email text;
  v_vt text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(p->'vai_tro') x), '{}');
begin
  perform app.yeu_cau('giam_doc');
  if nullif(trim(p->>'ho_ten'), '') is null then raise exception 'Nhập họ tên nhân viên.'; end if;
  if v_ten !~ '^[a-z0-9][a-z0-9._-]{1,39}$' then
    raise exception 'Tên đăng nhập chỉ gồm chữ không dấu, số, dấu chấm hoặc gạch (vd: duy.cvdv).'; end if;
  perform app.kiem_mat_khau(p->>'mat_khau');
  if cardinality(v_vt) = 0 then raise exception 'Chọn ít nhất một bộ phận / vai trò.'; end if;
  if 'truong_nhom' = any(v_vt) and nullif(p->>'to_id', '') is null then raise exception 'Trưởng nhóm phải chọn tổ.'; end if;
  if 'co_dong' = any(v_vt) and cardinality(v_vt) > 1 then raise exception 'Tài khoản cổ đông chỉ có một vai trò cổ đông.'; end if;
  v_email := app.email_noi_bo(v_ten);
  if exists (select 1 from auth.users where lower(email) = v_email)
     or exists (select 1 from public.nhan_vien where lower(ten_dang_nhap) = v_ten) then
    raise exception 'Tên đăng nhập "%" đã có người dùng.', v_ten; end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
      crypt(p->>'mat_khau', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('ho_ten', trim(p->>'ho_ten')), now(), now(),
      '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text, 'email',
      jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true), null, now(), now());

  -- nhan_vien đã được trigger tao_nhan_vien_moi tạo; cấp quyền luôn
  update public.nhan_vien set ho_ten = trim(p->>'ho_ten'), ten_dang_nhap = v_ten,
    chi_nhanh_id = coalesce(nullif(p->>'chi_nhanh_id', ''), app.chi_nhanh()), vai_tro = v_vt,
    to_id = nullif(p->>'to_id', ''), hoat_dong = true, phai_doi_mat_khau = true
  where id = v_id;
  return v_id;
end $$;

-- Giám đốc đặt lại mật khẩu cho bất kỳ tài khoản nào (của người khác: lần đăng nhập sau bắt đổi)
create or replace function public.dat_lai_mat_khau(p_id uuid, p_mat_khau text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform app.yeu_cau('giam_doc');
  perform app.kiem_mat_khau(p_mat_khau);
  update auth.users set encrypted_password = crypt(p_mat_khau, gen_salt('bf')), updated_at = now() where id = p_id;
  if not found then raise exception 'Không tìm thấy tài khoản.'; end if;
  update public.nhan_vien set phai_doi_mat_khau = (p_id <> auth.uid()) where id = p_id;
  -- đăng xuất các máy đang dùng tài khoản đó
  if p_id <> auth.uid() and to_regclass('auth.sessions') is not null then
    execute 'delete from auth.sessions where user_id = $1' using p_id;
  end if;
end $$;

-- Nhân viên đã tự đổi mật khẩu (sau lần đăng nhập đầu)
create or replace function public.da_doi_mat_khau() returns void
language sql security definer set search_path = public as $$
  update public.nhan_vien set phai_doi_mat_khau = false where id = auth.uid()
$$;

revoke execute on function public.tao_tai_khoan_nhan_vien(jsonb) from public, anon;
revoke execute on function public.dat_lai_mat_khau(uuid, text) from public, anon;
revoke execute on function public.da_doi_mat_khau() from public, anon;
grant execute on function public.tao_tai_khoan_nhan_vien(jsonb) to authenticated;
grant execute on function public.dat_lai_mat_khau(uuid, text) to authenticated;
grant execute on function public.da_doi_mat_khau() to authenticated;
revoke execute on function app.email_noi_bo(text) from public, anon;
revoke execute on function app.kiem_mat_khau(text) from public, anon;
