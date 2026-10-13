// Nút "Xuất Excel" – chỉ giám đốc. Máy chủ kiểm quyền lần nữa và ghi nhật ký mỗi lần xuất.
import { h, chay, toast, ngayGio, homNay } from '../ui.js';
import { taiFileExcel } from '../excel.js';
import * as api from '../api.js';

const THU_TU_NHOM = ['Sơn', 'Nhám', 'Vật tư phụ', 'Phụ tùng', 'Dầu nhớt', 'Detailing', 'Khác'];
const phuDe = (chiNhanh, luc) => `${chiNhanh || 'Gara Hoàng Sơn'} · Xuất lúc ${ngayGio(luc)} · Người xuất: ${api.toi?.ho_ten || ''}`;

export function nutXuatExcel(nhan, lam) {
  if (!api.coVaiTro('giam_doc')) return null;
  return h('button', { class: 'nut', type: 'button', 'data-xuat-excel': '', onclick: (e) => {
    const nut = e.currentTarget; nut.disabled = true;
    chay(lam).catch(() => {}).finally(() => { nut.disabled = false; });
  } }, nhan);
}

// ---------------- Kho: trang Tổng hợp + mỗi nhóm một trang ----------------
export async function xuatExcelKho() {
  const kq = await api.xuatDuLieuKho();
  const hang = kq.hang || [];
  const nhom = [...new Set(hang.map((x) => x.nhom))]
    .sort((a, b) => (THU_TU_NHOM.indexOf(a) + 1 || 99) - (THU_TU_NHOM.indexOf(b) + 1 || 99) || a.localeCompare(b, 'vi'));
  const tongGT = hang.reduce((s, x) => s + Number(x.gia_tri || 0), 0);
  const pd = phuDe(kq.chi_nhanh, kq.luc);
  const trang = [{
    ten: 'Tổng hợp', tieuDe: 'TỒN KHO – TỔNG HỢP THEO NHÓM', phuDe: pd,
    cot: [{ nhan: 'Nhóm hàng', rong: 22 }, { nhan: 'Số mã', kieu: 'tien', rong: 10 }, { nhan: 'Số mã còn hàng', kieu: 'tien', rong: 12 },
      { nhan: 'Số mã dưới tối thiểu', kieu: 'tien', rong: 14 }, { nhan: 'Giá trị tồn (đ)', kieu: 'tien', rong: 18 }, { nhan: 'Tỷ lệ', kieu: 'phan_tram', rong: 10 }],
    dong: nhom.map((n) => {
      const ds = hang.filter((x) => x.nhom === n);
      const gt = ds.reduce((s, x) => s + Number(x.gia_tri || 0), 0);
      return [n, ds.length, ds.filter((x) => Number(x.ton) > 0).length, ds.filter((x) => x.duoi_toi_thieu).length, gt, tongGT ? gt / tongGT : 0];
    }),
    tong: ['Tổng cộng', 'SUM', 'SUM', 'SUM', 'SUM', null],
  }];
  for (const n of nhom) {
    const ds = hang.filter((x) => x.nhom === n);
    trang.push({
      ten: n, tieuDe: `TỒN KHO – NHÓM ${n.toUpperCase()}`, phuDe: pd,
      cot: [{ nhan: 'STT', kieu: 'tien', rong: 6 }, { nhan: 'Mã hàng', rong: 22 }, { nhan: 'Tên hàng', rong: 40 }, { nhan: 'ĐVT', rong: 9 },
        { nhan: 'Tồn', kieu: 'so', rong: 11 }, { nhan: 'Đơn giá vốn (đ/ĐVT)', kieu: 'so', rong: 15 }, { nhan: 'Giá trị tồn (đ)', kieu: 'tien', rong: 16 },
        { nhan: 'Tồn tối thiểu', kieu: 'so', rong: 10 }, { nhan: 'Dưới tối thiểu', rong: 10 }, { nhan: 'Đơn vị nhập', rong: 10 },
        { nhan: 'Quy đổi (1 ĐV nhập = ? ĐVT)', kieu: 'so', rong: 14 }, { nhan: 'Giá nhập gần nhất (đ/ĐV nhập)', kieu: 'tien', rong: 16 },
        { nhan: 'Nhà cung cấp', rong: 22 }, { nhan: 'Ghi chú', rong: 28 }],
      dong: ds.map((x, i) => [i + 1, x.ma, x.ten, x.dvt, Number(x.ton), x.don_gia === null ? null : Number(x.don_gia), Number(x.gia_tri || 0),
        Number(x.ton_toi_thieu) || null, x.duoi_toi_thieu ? 'Có' : '', x.dvt_nhap || '', x.dvt_nhap ? Number(x.he_so) : null,
        x.gia_nhap_gan_nhat === null ? null : Number(x.gia_nhap_gan_nhat), x.nha_cung_cap || '', x.ghi_chu || '']),
      tong: ['', 'Tổng cộng', `${ds.length} mã`, null, null, null, 'SUM', null, null, null, null, null, null, null],
    });
  }
  taiFileExcel(`Ton-kho_${homNay()}.xlsx`, trang);
  toast(`Đã xuất file tồn kho: ${hang.length} mã, ${nhom.length} nhóm.`);
}

// ---------------- Khách hàng: Khách – xe, Công nợ, Nợ theo hãng BH ----------------
export async function xuatExcelKhachHang() {
  const kq = await api.xuatDuLieuKhach();
  const xe = kq.xe || []; const no = kq.cong_no || [];
  const pd = phuDe(api.dm.ten?.('chi_nhanh', api.toi?.chi_nhanh_id), kq.luc);
  const so = (v) => (v === null || v === undefined ? null : Number(v));
  const trang = [
    {
      ten: 'Khách – xe', tieuDe: 'DANH SÁCH KHÁCH HÀNG – XE', phuDe: pd,
      cot: [{ nhan: 'STT', kieu: 'tien', rong: 6 }, { nhan: 'Biển số', rong: 13 }, { nhan: 'Khách hàng', rong: 26 }, { nhan: 'Điện thoại', rong: 13 },
        { nhan: 'Xe', rong: 22 }, { nhan: 'Màu', rong: 10 }, { nhan: 'Đơn vị bảo hiểm', rong: 18 }, { nhan: 'Hạn BH thân vỏ', kieu: 'ngay', rong: 13 }, { nhan: 'Hạn BH TNDS', kieu: 'ngay', rong: 13 },
        { nhan: 'Số lần vào xưởng', kieu: 'tien', rong: 10 }, { nhan: 'Lần vào gần nhất', kieu: 'ngay', rong: 13 },
        { nhan: 'Khách còn nợ (đ)', kieu: 'tien', rong: 15 }, { nhan: 'Bảo hiểm còn nợ (đ)', kieu: 'tien', rong: 15 }],
      dong: xe.map((x, i) => [i + 1, x.bien_so, x.khach, x.dien_thoai, x.xe, x.mau, x.hang_bh || '', x.han_than_vo, x.han_tnds, x.so_lan_vao, x.lan_vao_cuoi,
        so(x.con_no_khach) || null, so(x.con_no_bh) || null]),
      tong: ['', 'Tổng cộng', `${xe.length} xe`, null, null, null, null, null, null, 'SUM', null, 'SUM', 'SUM'],
    },
    {
      ten: 'Công nợ', tieuDe: 'CÔNG NỢ – XE ĐÃ GIAO CÒN NỢ', phuDe: `${pd} · Nợ khách và nợ bảo hiểm tách riêng`,
      cot: [{ nhan: 'STT', kieu: 'tien', rong: 6 }, { nhan: 'Mã hồ sơ', rong: 20 }, { nhan: 'Ngày vào', kieu: 'ngay', rong: 12 }, { nhan: 'Ngày giao', kieu: 'ngay', rong: 12 },
        { nhan: 'Số ngày nợ', kieu: 'tien', rong: 9 }, { nhan: 'Biển số', rong: 13 }, { nhan: 'Khách hàng', rong: 24 }, { nhan: 'Điện thoại', rong: 13 },
        { nhan: 'Hãng bảo hiểm', rong: 20 },
        { nhan: 'Khách phải trả (đ)', kieu: 'tien', rong: 15 }, { nhan: 'Khách đã trả (đ)', kieu: 'tien', rong: 15 }, { nhan: 'KHÁCH CÒN NỢ (đ)', kieu: 'tien', rong: 15 },
        { nhan: 'BH phải trả (đ)', kieu: 'tien', rong: 15 }, { nhan: 'BH đã trả (đ)', kieu: 'tien', rong: 15 }, { nhan: 'BẢO HIỂM CÒN NỢ (đ)', kieu: 'tien', rong: 16 }],
      dong: no.map((x, i) => [i + 1, x.ma, x.ngay_vao, x.ngay_giao, x.so_ngay, x.bien_so, x.khach, x.dien_thoai, x.hang_bh || '',
        so(x.phai_thu_khach), so(x.da_thu_khach), so(x.con_no_khach), so(x.phai_thu_bh), so(x.da_thu_bh), so(x.con_no_bh)]),
      tong: ['', 'Tổng cộng', `${no.length} hồ sơ`, null, null, null, null, null, null, 'SUM', 'SUM', 'SUM', 'SUM', 'SUM', 'SUM'],
    },
  ];
  // Tổng nợ theo hãng bảo hiểm (+ một dòng nợ của khách)
  const theoHang = new Map();
  for (const x of no) {
    if (Math.round(Number(x.con_no_bh)) === 0) continue;
    const k = x.hang_bh || '(Chưa ghi hãng)';
    const c = theoHang.get(k) || { so: 0, tien: 0 };
    c.so += 1; c.tien += Number(x.con_no_bh); theoHang.set(k, c);
  }
  const noKhach = no.filter((x) => Math.round(Number(x.con_no_khach)) !== 0);
  trang.push({
    ten: 'Nợ theo hãng BH', tieuDe: 'TỔNG CÔNG NỢ THEO HÃNG BẢO HIỂM', phuDe: pd,
    cot: [{ nhan: 'Bên nợ', rong: 30 }, { nhan: 'Số hồ sơ còn nợ', kieu: 'tien', rong: 14 }, { nhan: 'Còn nợ (đ)', kieu: 'tien', rong: 18 }],
    dong: [...[...theoHang].sort((a, b) => b[1].tien - a[1].tien).map(([k, c]) => [k, c.so, c.tien]),
      ['Khách hàng (tự trả)', noKhach.length, noKhach.reduce((s, x) => s + Number(x.con_no_khach), 0)]],
    tong: ['Tổng cộng', 'SUM', 'SUM'],
  });
  taiFileExcel(`Khach-hang-cong-no_${homNay()}.xlsx`, trang);
  toast(`Đã xuất file khách hàng: ${xe.length} xe, ${no.length} hồ sơ còn nợ.`);
}
