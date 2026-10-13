// Người xử lý tiếp theo và hạn xử lý của từng loại việc (018_han_xu_ly.sql)
//  - Phiếu kho / đề nghị chi: người xử lý tiếp theo = những người có đúng vai trò ở chi nhánh đó.
//  - Hạn: tính từ lúc giao / lập theo cài đặt (giờ), hoặc giờ hẹn giao xe. Quá hạn thì tô vàng ở "Việc hôm nay".
import * as api from './api.js';
import { VAI_TRO } from './ui.js';
import { viecTiepTheo } from './trang/giao-viec.js';

const GIO = 36e5;
const cong = (luc, gio) => (luc ? new Date(new Date(luc).getTime() + gio * GIO) : null);
const gioCaiDat = (khoa, macDinh) => api.caiDat(khoa, macDinh);
const ngayCaiDat = (khoa, macDinh) => api.caiDat(khoa, macDinh) * 24;

// Bước tiếp theo của phiếu kho / đề nghị chi: { ten, vaiTro } hoặc null khi đã xong
export function buocTiepPhieu(loai, r) {
  switch (loai) {
    case 'de_xuat': return r.trang_thai === 'cho_xuat' ? { ten: 'Kho xuất', vaiTro: ['kho'] } : null;
    case 'mua':
      if (r.trang_thai === 'cho_duyet') return { ten: 'Duyệt mua', vaiTro: ['quan_ly', 'giam_doc'] };
      if (r.trang_thai === 'da_duyet') return { ten: 'Kho nhập hàng về', vaiTro: ['kho'] };
      return null;
    case 'nhap': return ['cho_khop', 'treo'].includes(r.trang_thai) ? { ten: 'Kế toán khớp hóa đơn', vaiTro: ['ke_toan'] } : null;
    case 'de_nghi_chi':
      if (r.trang_thai === 'cho_duyet') return { ten: r.can_giam_doc ? 'Giám đốc duyệt' : 'Duyệt chi', vaiTro: r.can_giam_doc ? ['giam_doc'] : ['quan_ly', 'giam_doc'] };
      if (r.trang_thai === 'da_duyet') return { ten: 'Kế toán chi tiền', vaiTro: ['ke_toan'] };
      return null;
    default: return null;
  }
}

// Tên những người có vai trò đó ở chi nhánh (tối đa 3), không có ai thì giám đốc; trưởng nhóm không xem được danh sách → trống
export function tenNguoiVai(vaiTro, chiNhanh) {
  const ds = (api.dm.nhan_vien || []).filter((n) => n.hoat_dong && (!chiNhanh || !n.chi_nhanh_id || n.chi_nhanh_id === chiNhanh));
  let nguoi = ds.filter((n) => n.vai_tro.some((v) => vaiTro.includes(v)));
  if (!nguoi.length) nguoi = ds.filter((n) => n.vai_tro.includes('giam_doc'));
  nguoi.sort((a, b) => a.ho_ten.localeCompare(b.ho_ten, 'vi'));
  const ten = nguoi.map((n) => n.ho_ten.trim().split(/\s+/).pop());
  return ten.length > 3 ? `${ten.slice(0, 3).join(', ')} +${ten.length - 3}` : ten.join(', ');
}
export const tenVaiTro = (vaiTro) => vaiTro.map((v) => VAI_TRO[v] || v).join(' / ');

// Hạn xử lý của phiếu kho / đề nghị chi
export function hanPhieu(loai, r) {
  const b = buocTiepPhieu(loai, r);
  if (!b) return null;
  switch (loai) {
    case 'de_xuat': return cong(r.tao_luc, gioCaiDat('so_gio_xuat_vat_tu', 4));
    case 'mua': return r.trang_thai === 'cho_duyet' ? cong(r.tao_luc, gioCaiDat('so_gio_duyet_mua', 24)) : null;
    case 'nhap': return cong(r.tao_luc, gioCaiDat('so_gio_khop_hoa_don', 48));
    case 'de_nghi_chi': return r.trang_thai === 'cho_duyet' ? cong(r.tao_luc, gioCaiDat('so_gio_duyet_chi', 24)) : null;
    default: return null;
  }
}

// Hạn của bước tiếp theo trên hồ sơ xe (hs: dòng v_ho_so; giaoLuc: ho_so.giao_viec_luc)
export function hanHoSo(hs, giaoLuc) {
  const v = viecTiepTheo(hs);
  if (!v) return null;
  switch (hs.trang_thai) {
    case 'tiep_nhan': return cong(hs.ngay_vao, gioCaiDat('so_gio_lap_bao_gia', 24));
    case 'bao_gia': return cong(hs.ngay_vao, ngayCaiDat('so_ngay_cho_duyet', 3));
    case 'da_duyet': return cong(giaoLuc, gioCaiDat('so_gio_lap_lenh', 24));
    case 'dang_sua': return hs.hen_giao ? new Date(hs.hen_giao) : null;
    case 'cho_kcs': { const h1 = cong(giaoLuc, gioCaiDat('so_gio_kcs', 4)); const h2 = hs.hen_giao ? new Date(hs.hen_giao) : null; return h1 && h2 ? (h1 < h2 ? h1 : h2) : (h1 || h2); }
    case 'dat_kcs': return hs.hen_giao ? new Date(hs.hen_giao) : null;
    case 'da_giao': return v.ten === 'Gửi hồ sơ bảo hiểm' ? cong(hs.giao_luc, ngayCaiDat('so_ngay_gui_ho_so', 3)) : cong(hs.giao_luc, ngayCaiDat('so_ngay_goi_cham_soc', 3));
    case 'da_gui_hs': case 'dong': return cong(hs.giao_luc, ngayCaiDat('so_ngay_goi_cham_soc', 3));
    default: return null;
  }
}

export const quaHan = (han) => !!han && han.getTime() < Date.now();

// "Hạn 14:00 13/10" / "Quá hạn 2 giờ" / "Quá hạn 3 ngày"
export function chuHan(han) {
  if (!han) return '';
  const ms = han.getTime() - Date.now();
  const gio = Math.abs(ms) / GIO;
  const bao = gio < 1 ? `${Math.max(1, Math.round(gio * 60))} phút` : gio < 48 ? `${Math.round(gio)} giờ` : `${Math.round(gio / 24)} ngày`;
  return ms < 0 ? `Quá hạn ${bao}` : `Còn ${bao}`;
}
