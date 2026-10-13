// Báo cáo cổ đông: chỉ số tổng của các tháng giám đốc đã chốt (025)
import { h, tien, ngayGio, bang, dat } from '../ui.js';
import * as api from '../api.js';

export default async function trangCoDong(el) {
  const ds = await api.baoCaoCoDong();
  const nhanThang = (d) => `${String(d.thang).slice(5, 7)}/${String(d.thang).slice(0, 4)}`;
  const DONG = [['Doanh thu (sau VAT)', 'doanh_thu'], ['Giá vốn', (s) => Number(s.gia_von_xe) + Number(s.gia_von_dung_chung) + Number(s.chi_gia_von)],
    ['Lãi gộp', 'lai_gop'], ['Lương', 'luong'], ['Hoa hồng GDV', 'hoa_hong'], ['Chi phí vận hành', 'chi_van_hanh'], ['Chi phí cố định', 'chi_co_dinh'],
    ['Lãi trước thuế', 'lai_truoc_thue'], ['Số xe', 'so_xe']];
  const lay = (s, k) => (typeof k === 'function' ? k(s) : s[k]);
  dat(el, h('section', { class: 'the' }, h('h1', null, 'Báo cáo cổ đông'),
    h('p', { class: 'mo-ta' }, 'Số tổng của các tháng giám đốc đã chốt sổ. Tháng đang mở chưa hiện ở đây.'),
    ds.length ? h('div', { class: 'bang-cuon' }, bang([
      { nhan: 'Khoản mục', lay: (r) => h('span', { class: ['doanh_thu', 'lai_gop', 'lai_truoc_thue'].includes(r.k) ? 'dam' : '' }, r.nhan) },
      ...ds.map((d) => ({ nhan: h('span', null, nhanThang(d), h('br'), h('small', null, `chốt ${ngayGio(d.chot_luc)}`)), so: true,
        lay: (r) => (r.k === 'so_xe' ? lay(d.so_lieu, r.k) : h('span', { class: r.k === 'lai_truoc_thue' ? (Number(lay(d.so_lieu, r.k)) < 0 ? 'chu-loi' : 'chu-tot') : '' }, tien(lay(d.so_lieu, r.k)) || '0')) })),
    ], DONG.map(([nhan, k]) => ({ nhan, k })))) : h('p', { class: 'trong' }, 'Chưa có tháng nào được chốt.')));
}
