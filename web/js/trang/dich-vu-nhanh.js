// Dịch vụ nhanh: rửa xe, vá lốp, thay bóng đèn, kích bình… (không đi qua 9 bước)
import { h, bienSo, tien, ngay, homNay, truong, oChu, oTien, oNgay, oCheck, docForm, chay, bang, moModal, oVung, toast, dat } from '../ui.js';
import * as api from '../api.js';

export default async function trangDichVu(el) {
  const form = h('form', { class: 'the luoi-o', novalidate: true },
    truong('Biển số', oChu('bien_so', '', { placeholder: 'Có thể bỏ trống', autocapitalize: 'characters' })),
    truong('Dịch vụ', oChu('dich_vu', '', { placeholder: 'Rửa xe, vá lốp, thay bóng đèn…', list: 'goi-y-dv' }), null, { batBuoc: true }),
    h('datalist', { id: 'goi-y-dv' }, ['Rửa xe', 'Vá lốp', 'Thay bóng đèn', 'Kích bình', 'Bơm lốp', 'Vệ sinh nội thất'].map((x) => h('option', { value: x }))),
    truong('Người làm', oChu('nguoi_lam', '')),
    truong('Số tiền khách trả', oTien('so_tien', null), null, { batBuoc: true }),
    truong('Ngày', oNgay('ngay', homNay(), { max: homNay() })),
    h('div', { class: 'truong' }, oCheck('xuat_hd', false, 'Có xuất hóa đơn')),
    h('div', { class: 'hang-nut rong' }, h('button', { class: 'nut chinh', type: 'submit' }, 'Ghi dịch vụ')));
  const ds = h('div');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const d = docForm(form);
    try {
      await chay(() => api.ghiDichVuNhanh(d), { thanhCong: 'Đã ghi.' });
      form.reset(); form.ngay.value = homNay(); await tai();
    } catch { /* đã báo lỗi */ }
  });

  async function tai() {
    const tuNgay = new Date(Date.now() - 31 * 864e5).toISOString().slice(0, 10);
    const rows = await api.doc('v_dich_vu_nhanh', (q) => q.gte('ngay', tuNgay).order('ngay', { ascending: false }).order('id', { ascending: false }).limit(300));
    const homnay = rows.filter((r) => r.ngay === homNay() && r.trang_thai === 'hieu_luc');
    dat(ds, 
      h('p', { class: 'mo-ta' }, `Hôm nay: ${homnay.length} lượt, ${tien(homnay.reduce((s, r) => s + Number(r.so_tien), 0))} đ`),
      bang([
        { nhan: 'Ngày', lay: (r) => ngay(r.ngay) },
        { nhan: 'Biển số', lay: (r) => r.bien_so_hien_thi ? bienSo(r.bien_so_hien_thi) : '' },
        { nhan: 'Dịch vụ', lay: (r) => r.trang_thai === 'huy' ? h('s', null, r.dich_vu) : r.dich_vu },
        { nhan: 'Người làm', lay: (r) => r.nguoi_lam || '' },
        { nhan: 'Số tiền', so: true, lay: (r) => tien(r.so_tien) },
        { nhan: 'Đã thu', lay: (r) => r.trang_thai === 'huy' ? 'Đã hủy' : Number(r.da_thu) >= Number(r.so_tien) ? '✓' :
          api.coVaiTro('ke_toan', 'giam_doc') ? h('a', { class: 'nut nho', href: `#/thu-chi?dvn=${r.id}` }, 'Thu tiền') : 'Chưa' },
        api.coVaiTro('ke_toan', 'giam_doc') ? { nhan: '', lay: (r) => r.trang_thai === 'hieu_luc' && Number(r.da_thu) === 0
          ? h('button', { class: 'nut-chu', type: 'button', onclick: () => moHuy(r) }, 'Hủy') : '' } : null,
      ].filter(Boolean), rows, { trong: 'Chưa có dịch vụ nào trong 31 ngày qua.' }));
  }
  function moHuy(r) {
    const f = h('form', null, truong('Lý do hủy', oVung('ly_do'), null, { batBuoc: true }));
    moModal(`Hủy dịch vụ ${r.dich_vu}`, f, { nhanNut: 'Hủy dịch vụ', nutChinh: async () => { await api.huyDichVuNhanh(r.id, docForm(f).ly_do); toast('Đã hủy.'); await tai(); } });
  }

  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Dịch vụ nhanh'),
    h('p', { class: 'mo-ta' }, 'Ghi ngay mỗi lượt làm, theo biển số nếu có. Kế toán thu tiền ở mục Thu chi.')), form,
  h('section', { class: 'the' }, h('h2', null, '31 ngày gần nhất'), ds));
  await tai();
}
