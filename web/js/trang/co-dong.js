// Báo cáo cổ đông: chỉ số tổng của các tháng giám đốc đã chốt (025/026)
import { h, tien, ngay, ngayGio, bang, dat } from '../ui.js';
import * as api from '../api.js';
import { bieuDoDuong } from '../bieu-do.js';

export default async function trangCoDong(el) {
  const ds = (await api.baoCaoCoDong()).slice().sort((a, b) => (a.thang < b.thang ? -1 : 1));   // tăng dần
  const nhanThang = (d) => `${String(d.thang).slice(5, 7)}/${String(d.thang).slice(0, 4)}`;
  const so = (v) => Number(v) || 0;
  const giaVon = (s) => so(s.gia_von_xe) + so(s.gia_von_dung_chung) + so(s.chi_gia_von);
  const DONG = [['Doanh thu (sau VAT)', 'doanh_thu', 'dam'], ['Giá vốn', giaVon, 'tru'], ['Lãi gộp', 'lai_gop', 'dam'],
    ['Lương', 'luong', 'tru'], ['Hoa hồng GDV', 'hoa_hong', 'tru'], ['Chi phí vận hành', 'chi_van_hanh', 'tru'], ['Chi phí cố định', 'chi_co_dinh', 'tru'],
    ['Lãi trước thuế', 'lai_truoc_thue', 'dam'], ['Số xe có doanh thu', 'so_xe', 'phu']].map(([nhan, k, kieu]) => ({ nhan, k, kieu }));
  const lay = (s, k) => (typeof k === 'function' ? k(s) : so(s[k]));
  const tong = {}; for (const r of DONG) tong[typeof r.k === 'function' ? 'gia_von' : r.k] = ds.reduce((t, d) => t + lay(d.so_lieu, r.k), 0);
  const layTong = (r) => (typeof r.k === 'function' ? tong.gia_von : tong[r.k]);
  const o = (r, v) => (r.k === 'so_xe' ? h('span', { class: 'mo' }, v) : h('span', { class: `${r.kieu === 'dam' ? 'dam' : 'mo'} ${r.k === 'lai_truoc_thue' && v < 0 ? 'chu-loi' : ''}` }, r.kieu === 'tru' && v ? `− ${tien(v)}` : tien(v) || '0'));
  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Báo cáo cổ đông')),
    h('p', { class: 'mo-ta' }, 'Số tổng của các tháng giám đốc đã chốt sổ (kỳ khóa ở ngày cuối tháng). Tháng đang mở chưa hiện ở đây.'),
    !ds.length ? h('section', { class: 'the' }, h('p', { class: 'trong' }, 'Chưa có tháng nào được chốt.')) : [
      h('section', { class: 'luoi-dem tien' },
        h('div', { class: 'o-dem' }, h('b', null, tien(ds[ds.length - 1].so_lieu.doanh_thu) || '0'), h('span', null, `Doanh thu tháng ${nhanThang(ds[ds.length - 1])}`)),
        h('div', { class: 'o-dem' }, h('b', { class: so(ds[ds.length - 1].so_lieu.lai_truoc_thue) < 0 ? 'chu-loi' : 'chu-tot' }, tien(ds[ds.length - 1].so_lieu.lai_truoc_thue) || '0'), h('span', null, `Lãi trước thuế tháng ${nhanThang(ds[ds.length - 1])}`)),
        h('div', { class: 'o-dem' }, h('b', { class: tong.lai_truoc_thue < 0 ? 'chu-loi' : 'chu-tot' }, tien(tong.lai_truoc_thue) || '0'), h('span', null, `Lãi trước thuế lũy kế ${ds.length} tháng đã chốt`))),
      h('section', { class: 'the' }, bieuDoDuong({ tieuDe: 'Doanh thu – Lãi gộp – Lãi trước thuế các tháng đã chốt', nhan: ds.map(nhanThang),
        chuoi: [{ ten: 'Doanh thu', giaTri: ds.map((d) => so(d.so_lieu.doanh_thu)) }, { ten: 'Lãi gộp', giaTri: ds.map((d) => so(d.so_lieu.lai_gop)) }, { ten: 'Lãi trước thuế', giaTri: ds.map((d) => so(d.so_lieu.lai_truoc_thue)) }] })),
      h('section', { class: 'the' }, h('h2', null, 'Theo tháng'), bang([
        { nhan: 'Khoản mục', lay: (r) => h('span', { class: r.kieu === 'dam' ? 'dam' : 'mo' }, r.nhan) },
        ...ds.map((d) => ({ nhan: h('span', { class: 'cot-thang' }, nhanThang(d), h('br'), h('small', { class: 'mo' }, `chốt ${ngay(d.chot_luc)}`)), so: true, lay: (r) => o(r, lay(d.so_lieu, r.k)) })),
        { nhan: h('span', { class: 'cot-thang' }, 'Lũy kế', h('br'), h('small', { class: 'mo' }, `${ds.length} tháng`)), so: true, lay: (r) => o(r, layTong(r)) },
      ], DONG))]);
}
