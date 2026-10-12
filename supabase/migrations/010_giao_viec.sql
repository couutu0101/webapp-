-- =====================================================================
-- 010 (12/10/2026): Người thực hiện và người làm bước tiếp theo
--   - Người thực hiện: tự ghi người đăng nhập (đã có trong ho_so_nhat_ky.boi).
--   - Người làm bước tiếp theo: ho_so.nguoi_tiep_theo. Mỗi lần hồ sơ chuyển bước, phần mềm tự giao
--     theo gợi ý (app.goi_y_nguoi_tiep_theo); ở các hộp thoại tiếp nhận, báo giá, duyệt giá người làm
--     chọn lại được (giao_viec ngay sau khi lưu bước đó).
--   - Đổi người giữa chừng: chỉ quản lý chung và giám đốc.
--   - Bước sửa chữa giao theo tổ (trưởng nhóm của tổ được giao từng hạng mục) nên để trống người.
--   Tương thích ngược: chỉ thêm cột, trigger, hàm, bảng xem mới; v_ho_so giữ nguyên.
-- =====================================================================
alter table public.ho_so add column if not exists nguoi_tiep_theo uuid references public.nhan_vien(id);
alter table public.ho_so add column if not exists giao_viec_luc timestamptz;
comment on column public.ho_so.nguoi_tiep_theo is 'Nhân viên được giao làm bước tiếp theo';
create index if not exists ho_so_nguoi_tiep_theo_idx on public.ho_so (nguoi_tiep_theo) where nguoi_tiep_theo is not null;

-- Nhân viên đầu tiên (theo tên) có vai trò này ở chi nhánh của hồ sơ
create or replace function app.nhan_vien_dau(p_vai_tro text, p_chi_nhanh text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.nhan_vien
  where hoat_dong and p_vai_tro = any(vai_tro) and (chi_nhanh_id = p_chi_nhanh or chi_nhanh_id is null)
  order by (chi_nhanh_id is null), ho_ten limit 1
$$;

-- Gợi ý người làm bước tiếp theo theo bước hiện tại của hồ sơ
create or replace function app.goi_y_nguoi_tiep_theo(h public.ho_so) returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if h.tu_excel then return null; end if;
  case h.trang_thai
    -- Báo giá, nhập duyệt giá, lập lệnh: CVDV đang làm (người bấm), không thì CVDV tiếp nhận
    when 'tiep_nhan', 'bao_gia', 'da_duyet' then
      return case when app.co_vai_tro('cvdv') then auth.uid()
                  else coalesce(h.tao_boi, app.nhan_vien_dau('cvdv', h.chi_nhanh_id)) end;
    when 'dang_sua' then return null;                                           -- các tổ được giao
    when 'cho_kcs' then return app.nhan_vien_dau('quan_ly', h.chi_nhanh_id);     -- KCS
    when 'dat_kcs' then return app.nhan_vien_dau('ke_toan', h.chi_nhanh_id);     -- thu tiền, giao xe
    when 'da_giao' then
      if h.nguon_tt <> 'khach' and h.gui_hs_ngay is null then
        return app.nhan_vien_dau('ke_toan', h.chi_nhanh_id);                     -- gửi hồ sơ bảo hiểm
      end if;
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;
    when 'da_gui_hs', 'dong' then
      return case when h.cham_soc_luc is null then app.nhan_vien_dau('quan_ly', h.chi_nhanh_id) end;  -- chăm sóc
    else return null;
  end case;
end $$;

-- Tự giao khi hồ sơ mới tạo, chuyển bước, gửi hồ sơ BH hoặc đã gọi chăm sóc
create or replace function app.tu_giao_viec() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT'
     or new.trang_thai is distinct from old.trang_thai
     or new.gui_hs_ngay is distinct from old.gui_hs_ngay
     or new.cham_soc_luc is distinct from old.cham_soc_luc then
    new.nguoi_tiep_theo := app.goi_y_nguoi_tiep_theo(new);
    new.giao_viec_luc := now();
  end if;
  return new;
end $$;

drop trigger if exists tu_giao_viec on public.ho_so;
create trigger tu_giao_viec before insert or update of trang_thai, gui_hs_ngay, cham_soc_luc on public.ho_so
  for each row execute function app.tu_giao_viec();

-- Giao (hoặc đổi) người làm bước tiếp theo.
--   Quản lý chung, giám đốc: đổi lúc nào cũng được.
--   Người khác: chỉ ngay sau khi chính mình vừa làm một bước của hồ sơ này (trong 15 phút).
create or replace function public.giao_viec(p_ho_so bigint, p_nguoi uuid) returns void
language plpgsql security definer set search_path = public as $$
declare h public.ho_so; v_ten text; v_cuoi public.ho_so_nhat_ky;
begin
  if not app.la_nhan_vien() then raise exception 'Bạn không có quyền làm việc này.' using errcode = '42501'; end if;
  h := app.lay_ho_so(p_ho_so);
  if h.trang_thai in ('huy') then raise exception 'Hồ sơ đã hủy.'; end if;
  if not app.co_vai_tro('quan_ly','giam_doc') then
    select * into v_cuoi from public.ho_so_nhat_ky where ho_so_id = p_ho_so order by id desc limit 1;
    if v_cuoi.boi is distinct from auth.uid() or v_cuoi.luc < now() - interval '15 minutes' then
      raise exception 'Chỉ quản lý chung hoặc giám đốc được đổi người làm bước tiếp theo.' using errcode = '42501';
    end if;
  end if;
  if p_nguoi is not null then
    select ho_ten into v_ten from public.nhan_vien where id = p_nguoi and hoat_dong;
    if v_ten is null then raise exception 'Nhân viên không tồn tại hoặc đã nghỉ.'; end if;
  end if;
  if h.nguoi_tiep_theo is not distinct from p_nguoi then return; end if;
  update public.ho_so set nguoi_tiep_theo = p_nguoi, giao_viec_luc = now() where id = p_ho_so;
  perform app.ghi_nhat_ky(p_ho_so, h.trang_thai, h.trang_thai,
    case when p_nguoi is null then 'Bỏ giao bước tiếp theo' else 'Giao bước tiếp theo cho ' || v_ten end);
end $$;

revoke execute on function public.giao_viec(bigint, uuid) from public, anon;
grant execute on function public.giao_viec(bigint, uuid) to authenticated;
revoke execute on function app.nhan_vien_dau(text, text), app.goi_y_nguoi_tiep_theo(public.ho_so), app.tu_giao_viec() from public, anon;

-- Ai đang được giao bước tiếp theo của từng hồ sơ (theo quyền xem hồ sơ của người đăng nhập)
create or replace view public.v_viec_ho_so with (security_invoker = true) as
select h.id as ho_so_id, h.trang_thai, h.nguon_tt, h.nguoi_tiep_theo, nv.ho_ten as nguoi_tiep_theo_ten, h.giao_viec_luc
from public.ho_so h
left join public.nhan_vien nv on nv.id = h.nguoi_tiep_theo;
grant select on public.v_viec_ho_so to authenticated;
revoke all on public.v_viec_ho_so from anon;

-- Giao sẵn cho các hồ sơ đang mở (hồ sơ chuyển từ Excel thì không)
update public.ho_so h set nguoi_tiep_theo = app.goi_y_nguoi_tiep_theo(h), giao_viec_luc = now()
where not h.tu_excel and h.trang_thai <> 'huy' and h.nguoi_tiep_theo is null;
