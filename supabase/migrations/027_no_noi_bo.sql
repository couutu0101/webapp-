-- 027: Nợ nội bộ & cá nhân – công ty mượn tiền giám đốc / cổ đông, cổ đông mượn tiền công ty, chi hộ.
--  Quy ước: mọi phiếu CHI gắn đơn vị liên quan làm họ nợ công ty thêm (hoặc giảm nợ công ty với họ);
--  mọi phiếu THU gắn đơn vị làm ngược lại. Còn lại = đầu kỳ + đã chi − đã thu: dương = họ nợ công ty, âm = công ty nợ họ.
--  Không khoản nào vào lãi lỗ (tính chất thu_noi_bo / tra_noi_bo).

alter table public.don_vi_lien_quan add column if not exists loai text not null default 'cong_ty';
alter table public.don_vi_lien_quan drop constraint if exists don_vi_lien_quan_loai_check;
alter table public.don_vi_lien_quan add constraint don_vi_lien_quan_loai_check check (loai in ('cong_ty','ca_nhan'));
alter table public.don_vi_lien_quan add column if not exists so_du_dau_ky numeric(14,0) not null default 0;
alter table public.don_vi_lien_quan add column if not exists ngay_dau_ky date;
alter table public.don_vi_lien_quan add column if not exists hoat_dong boolean not null default true;
comment on column public.don_vi_lien_quan.loai is 'cong_ty: công ty cùng hệ thống (PHI, DTM, GI); ca_nhan: giám đốc, cổ đông, cá nhân';
comment on column public.don_vi_lien_quan.so_du_dau_ky is 'Nợ tính đến ngày đầu kỳ: dương = họ nợ công ty, âm = công ty nợ họ';

-- Mục thu chi "hệ thống": phần mềm tìm theo mã, tên đổi tự do
alter table public.muc_thu_chi add column if not exists he_thong text;
create unique index if not exists muc_thu_chi_he_thong_uq on public.muc_thu_chi (he_thong) where he_thong is not null;
insert into public.muc_thu_chi (loai, ten, nhom, tinh_chat, can_ho_so) values
  ('thu', 'Công ty mượn tiền giám đốc / cổ đông', null, 'thu_noi_bo', false),
  ('thu', 'Cổ đông / cá nhân trả tiền mượn',      null, 'thu_noi_bo', false),
  ('chi', 'Cho cổ đông / cá nhân mượn',           null, 'tra_noi_bo', false),
  ('chi', 'Trả tiền mượn giám đốc / cổ đông',    null, 'tra_noi_bo', false)
on conflict (loai, ten) do nothing;
update public.muc_thu_chi set he_thong = 'muon_ca_nhan' where loai = 'thu' and ten = 'Công ty mượn tiền giám đốc / cổ đông' and he_thong is null;

-- Chi hộ: phiếu chi được một người/đơn vị trả thay (tiền không qua quỹ) → ghi cặp phiếu thu "công ty mượn" + phiếu chi cùng tài khoản
alter table public.phieu_thu_chi add column if not exists chi_ho_boi bigint references public.don_vi_lien_quan(id);
alter table public.phieu_thu_chi add column if not exists phieu_doi_ung_id bigint references public.phieu_thu_chi(id);
comment on column public.phieu_thu_chi.chi_ho_boi is 'Phiếu chi do đơn vị/cá nhân này trả thay; phiếu thu đối ứng ở phieu_doi_ung_id';
comment on column public.phieu_thu_chi.phieu_doi_ung_id is 'Phiếu thu/chi đi cặp (chi hộ): hủy một phiếu thì phiếu kia hủy theo';

-- Công nợ nội bộ từng đơn vị / cá nhân theo chi nhánh
create or replace view public.v_cong_no_noi_bo with (security_invoker = true) as
select x.*, (x.so_du_dau_ky + x.da_chi - x.da_thu) as con_lai
from (
  select dv.id, dv.ten, dv.loai, dv.hoat_dong, dv.so_du_dau_ky, dv.ngay_dau_ky, c.chi_nhanh_id,
    coalesce((select sum(p.so_tien) from public.phieu_thu_chi p
              where p.don_vi_lien_quan_id = dv.id and p.chi_nhanh_id = c.chi_nhanh_id and p.loai = 'chi' and p.trang_thai = 'hieu_luc'), 0) as da_chi,
    coalesce((select sum(p.so_tien) from public.phieu_thu_chi p
              where p.don_vi_lien_quan_id = dv.id and p.chi_nhanh_id = c.chi_nhanh_id and p.loai = 'thu' and p.trang_thai = 'hieu_luc'), 0) as da_thu,
    (select max(p.ngay) from public.phieu_thu_chi p
      where p.don_vi_lien_quan_id = dv.id and p.chi_nhanh_id = c.chi_nhanh_id and p.trang_thai = 'hieu_luc') as ngay_cuoi
  from public.don_vi_lien_quan dv
  cross join (select id as chi_nhanh_id from public.chi_nhanh) c
  where app.co_vai_tro('giam_doc','quan_ly','ke_toan') and app.duoc_xem_chi_nhanh(c.chi_nhanh_id)
) x;
grant select on public.v_cong_no_noi_bo to authenticated;

-- Chi tiền cho đề nghị chi, thêm tùy chọn chi hộ
drop function if exists public.chi_tien(bigint, bigint, date);
create or replace function public.chi_tien(p_de_nghi bigint, p_tai_khoan bigint, p_ngay date default current_date, p_chi_ho_boi bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare r public.de_nghi_chi; m public.muc_thu_chi; dv public.don_vi_lien_quan; v_id bigint; v_thu bigint; v_muc_muon bigint;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.de_nghi_chi where id = p_de_nghi for update;
  if not found then raise exception 'Không tìm thấy đề nghị.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  if r.trang_thai <> 'da_duyet' then raise exception 'Đề nghị chưa được duyệt thì chưa chi được.'; end if;
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, p_ngay);
  if r.ky_chi_phi is not null then perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ky_chi_phi); end if;
  if p_ngay > current_date then raise exception 'Ngày không được sau hôm nay.'; end if;
  perform app.kiem_tra_tai_khoan(p_tai_khoan, r.chi_nhanh_id);
  select * into m from public.muc_thu_chi where id = r.muc_id;
  if p_chi_ho_boi is not null then
    select * into dv from public.don_vi_lien_quan where id = p_chi_ho_boi;
    if not found then raise exception 'Không tìm thấy người chi hộ (Danh mục → Đơn vị liên quan).'; end if;
    if m.tinh_chat = 'tra_noi_bo' then raise exception 'Khoản trả nội bộ / cho mượn không chi hộ được.'; end if;
    select id into v_muc_muon from public.muc_thu_chi where he_thong = 'muon_ca_nhan' and hoat_dong;
    if v_muc_muon is null then raise exception 'Chưa có mục thu "Công ty mượn tiền giám đốc / cổ đông" (Danh mục → Mục thu chi).'; end if;
  end if;

  insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, vat_dau_vao, noi_dung,
    nha_cung_cap_id, gdv_id, don_vi_lien_quan_id, de_nghi_chi_id, tao_boi, ky_chi_phi, chi_ho_boi)
  values (r.chi_nhanh_id, p_ngay, 'chi', p_tai_khoan, r.muc_id, r.so_tien, r.vat_dau_vao,
    concat_ws(' – ', r.noi_dung, r.nguoi_nhan) || case when p_chi_ho_boi is null then '' else ' (' || dv.ten || ' chi hộ)' end,
    r.nha_cung_cap_id, r.gdv_id, r.don_vi_lien_quan_id, r.id, auth.uid(), r.ky_chi_phi, p_chi_ho_boi)
  returning id into v_id;

  if p_chi_ho_boi is not null then   -- tiền do người đó bỏ ra: công ty mượn họ đúng số tiền, cùng tài khoản để quỹ không đổi
    insert into public.phieu_thu_chi (chi_nhanh_id, ngay, loai, tai_khoan_id, muc_id, so_tien, noi_dung, don_vi_lien_quan_id, tao_boi, phieu_doi_ung_id)
    values (r.chi_nhanh_id, p_ngay, 'thu', p_tai_khoan, v_muc_muon, r.so_tien,
      'Chi hộ – ' || dv.ten || ' trả thay: ' || r.noi_dung, p_chi_ho_boi, auth.uid(), v_id)
    returning id into v_thu;
    update public.phieu_thu_chi set phieu_doi_ung_id = v_thu where id = v_id;
  end if;

  if m.tinh_chat = 'tra_coc' then   -- trả lại cọc cho khách: giảm phần khách đã trả
    insert into public.phan_bo (phieu_id, ho_so_id, nguoi_tra, so_tien) values (v_id, r.ho_so_id, 'khach', r.so_tien);
    perform app.cap_nhat_dong(r.ho_so_id);
  end if;
  update public.de_nghi_chi set trang_thai = 'da_chi' where id = p_de_nghi;
  return v_id;
end $$;

-- Hủy phiếu: phiếu đối ứng (chi hộ) hủy theo
create or replace function public.huy_phieu(p_id bigint, p_ly_do text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.phieu_thu_chi; x bigint; d public.phieu_thu_chi;
begin
  perform app.yeu_cau('ke_toan','giam_doc');
  select * into r from public.phieu_thu_chi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  perform app.yeu_cau_chi_nhanh(r.chi_nhanh_id);
  perform app.yeu_cau_thang_mo(r.chi_nhanh_id, r.ngay);
  if r.trang_thai = 'huy' then raise exception 'Phiếu đã hủy.'; end if;
  if nullif(trim(p_ly_do),'') is null then raise exception 'Ghi lý do hủy.'; end if;
  update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) where id = p_id;
  if r.de_nghi_chi_id is not null then
    update public.de_nghi_chi set trang_thai = 'da_duyet' where id = r.de_nghi_chi_id;
  end if;
  for x in select distinct ho_so_id from public.phan_bo where phieu_id = p_id and ho_so_id is not null loop
    perform app.cap_nhat_dong(x);
  end loop;
  if r.phieu_doi_ung_id is not null then
    select * into d from public.phieu_thu_chi where id = r.phieu_doi_ung_id for update;
    if found and d.trang_thai = 'hieu_luc' then
      update public.phieu_thu_chi set trang_thai = 'huy', ly_do_huy = trim(p_ly_do) || ' (hủy cùng phiếu chi hộ đối ứng)' where id = d.id;
      if d.de_nghi_chi_id is not null then
        update public.de_nghi_chi set trang_thai = 'da_duyet' where id = d.de_nghi_chi_id;
      end if;
    end if;
  end if;
end $$;

revoke execute on function public.chi_tien(bigint, bigint, date, bigint), public.huy_phieu(bigint, text) from public, anon;
grant execute on function public.chi_tien(bigint, bigint, date, bigint), public.huy_phieu(bigint, text) to authenticated;
