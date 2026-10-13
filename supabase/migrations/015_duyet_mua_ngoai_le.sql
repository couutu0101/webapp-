-- =====================================================================
-- 015 (13/10/2026): DUYỆT MUA NGOẠI LỆ – thiếu báo giá cạnh tranh
--   - Đề nghị mua từ ngưỡng (5 triệu) mà chưa đủ 3 báo giá: giám đốc hoặc quản lý chung được
--     "Duyệt ngoại lệ", BẮT BUỘC ghi lý do; phiếu đánh dấu ngoai_le + lý do + người duyệt.
--   - Giám đốc được tự duyệt đề nghị mua do chính mình lập (người khác vẫn không).
--   Tương thích ngược: thêm cột, hàm mới; hàm duyệt cũ giữ tên và tham số.
-- =====================================================================

alter table public.de_nghi_mua add column if not exists ngoai_le boolean not null default false;
alter table public.de_nghi_mua add column if not exists ly_do_ngoai_le text;
comment on column public.de_nghi_mua.ngoai_le is 'Duyệt ngoại lệ khi thiếu báo giá cạnh tranh';

-- Duyệt / từ chối thường: giám đốc được tự duyệt phiếu mình lập
create or replace function public.duyet_de_nghi_mua(p_id bigint, p_dong_y boolean, p_ly_do text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_mua; v_nguong numeric := app.cai_dat_so('nguong_3_bao_gia', 5000000); v_so_bg int;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_mua where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị mua.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị mua này đã được xử lý.'; end if;
  if r.nguoi_lap = auth.uid() and not app.co_vai_tro('giam_doc') then raise exception 'Không được tự duyệt đề nghị mua do mình lập.'; end if;
  if p_dong_y then
    select count(*) into v_so_bg from public.kho_tep where loai = 'de_nghi_mua' and doi_tuong_id = p_id;
    if r.tong_tien >= v_nguong and v_so_bg < 3 then
      raise exception 'Đơn từ % đ phải đính kèm 3 báo giá (đang có %). Thiếu báo giá thì bấm "Duyệt ngoại lệ" và ghi lý do.', app.vnd(v_nguong), v_so_bg;
    end if;
  elsif nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do từ chối.';
  end if;
  update public.de_nghi_mua set trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    duyet_boi = auth.uid(), duyet_luc = now(), ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end
  where id = p_id;
  if not p_dong_y then
    update public.de_xuat_dong set cho_mua = false
    where id in (select de_xuat_dong_id from public.de_nghi_mua_dong where de_nghi_id = p_id and de_xuat_dong_id is not null);
  end if;
end $$;

-- Duyệt ngoại lệ khi thiếu báo giá cạnh tranh
create or replace function public.duyet_mua_ngoai_le(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_mua; v_nguong numeric := app.cai_dat_so('nguong_3_bao_gia', 5000000); v_so_bg int;
begin
  perform app.yeu_cau('quan_ly','giam_doc');
  select * into r from public.de_nghi_mua where id = p_id for update;
  if not found then raise exception 'Không tìm thấy đề nghị mua.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'cho_duyet' then raise exception 'Đề nghị mua này đã được xử lý.'; end if;
  if r.nguoi_lap = auth.uid() and not app.co_vai_tro('giam_doc') then raise exception 'Không được tự duyệt đề nghị mua do mình lập.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do duyệt khi thiếu báo giá cạnh tranh.'; end if;
  select count(*) into v_so_bg from public.kho_tep where loai = 'de_nghi_mua' and doi_tuong_id = p_id;
  if r.tong_tien < v_nguong or v_so_bg >= 3 then
    raise exception 'Đề nghị này không thiếu báo giá – bấm "Duyệt" bình thường.';
  end if;
  update public.de_nghi_mua set trang_thai = 'da_duyet', duyet_boi = auth.uid(), duyet_luc = now(),
    ngoai_le = true, ly_do_ngoai_le = trim(p_ly_do) || ' (có ' || v_so_bg || '/3 báo giá)'
  where id = p_id;
end $$;
revoke execute on function public.duyet_mua_ngoai_le(bigint, text) from public, anon;
grant execute on function public.duyet_mua_ngoai_le(bigint, text) to authenticated;

-- Bảng xem thêm 2 cột mới (d.* phải tạo lại)
drop view if exists public.v_de_nghi_mua;
create view public.v_de_nghi_mua with (security_invoker = true) as
select d.*, n.ten as nha_cung_cap, h.ma as ma_ho_so, nv.ho_ten as nguoi_lap_ten, nd.ho_ten as duyet_boi_ten,
  (select count(*) from public.kho_tep t where t.loai = 'de_nghi_mua' and t.doi_tuong_id = d.id) as so_bao_gia,
  d.tong_tien >= app.cai_dat_so('nguong_3_bao_gia', 5000000) as can_3_bao_gia
from public.de_nghi_mua d
join public.nha_cung_cap n on n.id = d.nha_cung_cap_id
left join public.ho_so h on h.id = d.ho_so_id
left join public.nhan_vien nv on nv.id = d.nguoi_lap
left join public.nhan_vien nd on nd.id = d.duyet_boi;
grant select on public.v_de_nghi_mua to authenticated;
revoke all on public.v_de_nghi_mua from anon;
