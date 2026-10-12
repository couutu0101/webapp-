// Mọi lệnh gọi cơ sở dữ liệu nằm ở đây. Trang giao diện chỉ gọi các hàm trong file này.
import { sb } from './supabase.js';
import { taoAnhNho, duongDanAnhNho } from './ui.js';

function loi(error) {
  const e = new Error(error?.message || 'Lỗi không xác định');
  e.code = error?.code;
  return e;
}
export async function rpc(ten, thamSo = {}) {
  const { data, error } = await sb.rpc(ten, thamSo);
  if (error) throw loi(error);
  return data;
}
// doc('v_ho_so', q => q.eq('id', 5).single())
export async function doc(bang, tuyChinh = (q) => q, cot = '*') {
  const { data, error } = await tuyChinh(sb.from(bang).select(cot));
  if (error) throw loi(error);
  return data;
}
export async function them(bang, dong) {
  const { data, error } = await sb.from(bang).insert(dong).select();
  if (error) throw loi(error);
  return data;
}
export async function sua(bang, id, giaTri, khoa = 'id') {
  const { data, error } = await sb.from(bang).update(giaTri).eq(khoa, id).select();
  if (error) throw loi(error);
  if (!data || !data.length) throw new Error('Không lưu được (có thể bạn không có quyền sửa mục này).');
  return data;
}

// ---------- Đăng nhập ----------
export const dangNhap = async (email, matKhau) => {
  const { data, error } = await sb.auth.signInWithPassword({ email, password: matKhau });
  if (error) throw new Error(error.message === 'Invalid login credentials' ? 'Sai email hoặc mật khẩu.' : error.message);
  return data;
};
export const dangXuat = () => sb.auth.signOut();
export const layPhien = async () => (await sb.auth.getSession()).data.session;
export const khiDoiPhien = (cb) => sb.auth.onAuthStateChange(cb);
export const guiQuenMatKhau = async (email) => {
  const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
  if (error) throw loi(error);
};
export const datMatKhau = async (matKhau) => {
  const { error } = await sb.auth.updateUser({ password: matKhau });
  if (error) throw loi(error);
};

// ---------- Người đang dùng và danh mục (tải một lần) ----------
export const dm = {};
export let toi = null;

export async function taiToi(userId) {
  const ds = await doc('nhan_vien', (q) => q.eq('id', userId));
  toi = ds[0] || null;
  return toi;
}
export const coVaiTro = (...ds) => !!toi && toi.hoat_dong && ds.some((v) => toi.vai_tro.includes(v));
export const laNhanVien = () => coVaiTro('giam_doc', 'quan_ly', 'ke_toan', 'cvdv', 'kho');

export async function taiDanhMuc() {
  const bangs = ['chi_nhanh', 'hang_bao_hiem', 'giam_dinh_vien', 'hang_xe', 'dong_xe',
    'to_thuc_hien', 'muc_thu_chi', 'nha_cung_cap', 'don_vi_lien_quan', 'cai_dat'];
  if (coVaiTro('giam_doc', 'ke_toan', 'quan_ly')) bangs.push('tai_khoan_quy');
  if (laNhanVien()) bangs.push('nhan_vien');
  const kq = await Promise.all(bangs.map((b) => doc(b, (q) => q.order('id', { ascending: true })).catch(() => [])));
  bangs.forEach((b, i) => { dm[b] = kq[i]; });
  dm.ten = (bang, id) => (dm[bang] || []).find((x) => String(x.id) === String(id))?.ten ?? '';
  return dm;
}
export const caiDat = (khoa, macDinh) => {
  const r = (dm.cai_dat || []).find((x) => x.khoa === khoa);
  return r ? Number(r.gia_tri) : macDinh;
};

// ---------- Hồ sơ xe ----------
export const tiepNhanXe = (p) => rpc('tiep_nhan_xe', { p });
export const traCuuXe = (bienSo) => rpc('tra_cuu_xe', { p_bien_so: bienSo });
export const suaThongTin = (id, p) => rpc('sua_thong_tin_ho_so', { p_id: id, p });
export const luuBaoGia = (id, dong) => rpc('luu_bao_gia', { p_ho_so: id, dong });
// Báo giá theo nguồn (009): xe bảo hiểm chờ duyệt; khách ngoài bảo hiểm duyệt luôn. vat: 0.08 / 0.10 / 0.12
export const lapBaoGia = (id, dong, vat) => rpc('lap_bao_gia', { p_ho_so: id, dong, p_vat: vat });
// Giao / đổi người làm bước tiếp theo (010)
export const giaoViec = (id, nguoi) => rpc('giao_viec', { p_ho_so: id, p_nguoi: nguoi });
export const xoaHangMuc = (id) => rpc('xoa_hang_muc', { p_id: id });
export const duyetGia = (id, ngay, ketQua) => rpc('duyet_gia', { p_ho_so: id, p_ngay: ngay, ket_qua: ketQua });
export const lapLenh = (id, henGiao, phanCong) => rpc('lap_lenh_sua_chua', { p_ho_so: id, p_hen_giao: henGiao, phan_cong: phanCong });
export const baoXong = (hangMucId) => rpc('bao_xong_hang_muc', { p_id: hangMucId });
export const baoPhatSinh = (id, moTa) => rpc('bao_phat_sinh', { p_ho_so: id, p_mo_ta: moTa });
export const bangViecTo = () => rpc('bang_viec_to');
export const kcs = (id, dat, loi, lamLai) => rpc('kcs', { p_ho_so: id, p_dat: dat, p_loi: loi, p_lam_lai: lamLai });
export const duyetGiamGia = (id, soTien, lyDo) => rpc('duyet_giam_gia', { p_ho_so: id, p_so_tien: soTien, p_ly_do: lyDo });
export const duyetGiaoConNo = (id) => rpc('duyet_giao_xe_con_no', { p_ho_so: id });
export const giaoXe = (id, p) => rpc('giao_xe', { p_ho_so: id, p });
export const guiHoSoBH = (id, ngay) => rpc('gui_ho_so_bh', { p_ho_so: id, p_ngay: ngay });
export const nhapHoaHong = (id, soTien, ghiChu, boQua) =>
  rpc('nhap_hoa_hong_gdv', { p_ho_so: id, p_so_tien: soTien, p_ghi_chu: ghiChu, p_bo_qua_canh_bao: boQua });
export const ghiChamSoc = (id, ketQua, henBD) => rpc('ghi_cham_soc', { p_ho_so: id, p_ket_qua: ketQua, p_hen_bao_duong: henBD });
export const huyHoSo = (id, lyDo) => rpc('huy_ho_so', { p_ho_so: id, p_ly_do: lyDo });

export const layHoSo = async (id) => (await doc('v_ho_so', (q) => q.eq('id', id)))[0];
export const layHangMuc = (id) => doc('hang_muc', (q) => q.eq('ho_so_id', id).order('lan_bao_gia').order('id'));
export const layNhatKy = (id) => doc('ho_so_nhat_ky', (q) => q.eq('ho_so_id', id).order('luc', { ascending: false }));
export const layTep = (id) => doc('ho_so_tep', (q) => q.eq('ho_so_id', id).order('tai_luc'));
export const layPhatSinh = (id) => doc('phat_sinh', (q) => q.eq('ho_so_id', id).order('luc', { ascending: false }));
export const layKcs = (id) => doc('kcs', (q) => q.eq('ho_so_id', id).order('luc', { ascending: false }));

// Ảnh và biên bản: tải lên kho 'ho-so-xe' rồi ghi nhận vào hồ sơ
export async function taiTep(hoSo, buoc, file, loai = 'anh') {
  const ten = file.name.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^\w.-]+/g, '-');
  const duongDan = `${hoSo.chi_nhanh_id}/${hoSo.ma}/${buoc}-${Date.now()}-${ten}`;
  const { error } = await sb.storage.from('ho-so-xe').upload(duongDan, file, { upsert: false });
  if (error) throw loi(error);
  // Ảnh thu nhỏ: lỗi thì bỏ qua, hồ sơ sẽ dùng ảnh lớn thay thế
  const nho = await taoAnhNho(file);
  if (nho) {
    try { await sb.storage.from('ho-so-xe').upload(duongDanAnhNho(duongDan), nho, { upsert: false, contentType: 'image/jpeg' }); }
    catch { /* bỏ qua */ }
  }
  return rpc('them_tep', { p_ho_so: hoSo.id, p_buoc: buoc, p_loai: loai, p_duong_dan: duongDan });
}
export async function linkTep(duongDan) {
  const { data, error } = await sb.storage.from('ho-so-xe').createSignedUrl(duongDan, 3600);
  if (error) throw loi(error);
  return data.signedUrl;
}
// Lấy link cho nhiều tệp một lần: { duong_dan: { lon, nho } }. Ảnh cũ chưa có bản nhỏ thì nho = lon.
export async function linkTepNhieu(dsDuongDan) {
  if (!dsDuongDan.length) return {};
  const tatCa = dsDuongDan.flatMap((d) => [d, duongDanAnhNho(d)]);
  const { data, error } = await sb.storage.from('ho-so-xe').createSignedUrls(tatCa, 3600);
  if (error) throw loi(error);
  const theoDuong = Object.fromEntries((data || []).filter((x) => x.signedUrl && !x.error).map((x) => [x.path, x.signedUrl]));
  return Object.fromEntries(dsDuongDan.map((d) => [d, { lon: theoDuong[d], nho: theoDuong[duongDanAnhNho(d)] || theoDuong[d] }]));
}

// Gợi ý xe khi gõ biển số (hoặc 4 số trở lên của SĐT khách): tối đa 8 xe
export async function goiYXe(chu) {
  const gon = String(chu || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
  if (gon.length < 2) return [];
  let xe = await doc('xe', (q) => q.ilike('bien_so', `%${gon}%`).order('bien_so').limit(8), 'id,bien_so,mau,dong_xe_id,khach_hang_id');
  if (/^\d{4,}$/.test(gon) && xe.length < 8) {
    const khTheoSdt = await doc('khach_hang', (q) => q.ilike('dien_thoai', `%${gon}%`).limit(8), 'id');
    if (khTheoSdt.length) {
      const them = await doc('xe', (q) => q.in('khach_hang_id', khTheoSdt.map((k) => k.id)).limit(8), 'id,bien_so,mau,dong_xe_id,khach_hang_id');
      for (const x of them) if (!xe.some((y) => y.id === x.id)) xe.push(x);
      xe = xe.slice(0, 8);
    }
  }
  const idKh = [...new Set(xe.map((x) => x.khach_hang_id).filter(Boolean))];
  const kh = idKh.length ? await doc('khach_hang', (q) => q.in('id', idKh), 'id,ten,dien_thoai') : [];
  const theoId = Object.fromEntries(kh.map((k) => [k.id, k]));
  return xe.filter((x) => x.bien_so).map((x) => ({ ...x, khach: theoId[x.khach_hang_id] || null }));
}

// ---------- Dịch vụ nhanh ----------
export const ghiDichVuNhanh = (p) => rpc('ghi_dich_vu_nhanh', { p });
export const huyDichVuNhanh = (id, lyDo) => rpc('huy_dich_vu_nhanh', { p_id: id, p_ly_do: lyDo });

// ---------- Thu chi ----------
export const lapPhieuThu = (p) => rpc('lap_phieu_thu', { p });
export const phanBoThem = (phieu, ds) => rpc('phan_bo_them', { p_phieu: phieu, p_ds: ds });
export const lapPhieuChuyen = (p) => rpc('lap_phieu_chuyen', { p });
export const huyPhieu = (id, lyDo) => rpc('huy_phieu', { p_id: id, p_ly_do: lyDo });
export const lapDeNghiChi = (p) => rpc('lap_de_nghi_chi', { p });
export const duyetDeNghi = (id, dongY, lyDo) => rpc('duyet_de_nghi_chi', { p_id: id, p_dong_y: dongY, p_ly_do: lyDo });
export const huyDeNghi = (id) => rpc('huy_de_nghi_chi', { p_id: id });
export const chiTien = (id, taiKhoan, ngay) => rpc('chi_tien', { p_de_nghi: id, p_tai_khoan: taiKhoan, p_ngay: ngay });

// ---------- Nhân viên ----------
export const luuNhanVien = (id, p) => rpc('luu_nhan_vien', { p_id: id, p });
export const nhapBangLuong = (thang, tong) => rpc('nhap_bang_luong', { p_thang: thang, p_tong: tong });
export const ghiKiemQuy = (taiKhoan, soDem, ghiChu) => rpc('ghi_kiem_quy', { p_tai_khoan: taiKhoan, p_so_dem: soDem, p_ghi_chu: ghiChu });
