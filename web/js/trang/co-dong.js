// Báo cáo cổ đông: số của các tháng giám đốc đã chốt (025/026/042) – số lưu lúc chốt, không đổi theo dữ liệu nhập sau.
// Cùng cách trình bày với Kết quả kinh doanh (kqkd.js), gọn hơn: kết quả, tỷ suất, tiền – công nợ – tồn kho cuối tháng.
import { h, ngay, dat } from '../ui.js';
import * as api from '../api.js';
import { bieuDoDuong } from '../bieu-do.js';
import { bangBC, giaTri, chuO, congThang, nhanThang, oChenh } from './kqkd.js';

const so = (v) => Number(v) || 0;
// Số chốt theo cách tính cũ (trước 042) thiếu vài dòng: tính lại dòng cộng từ các dòng có sẵn
function chuanHoa(goc) {
  const x = { ...(goc || {}) };
  if (x.hao_hut === undefined) x.hao_hut = 0;
  if (x.thu_khac === undefined) x.thu_khac = 0;
  if (x.tong_gia_von === undefined) x.tong_gia_von = so(x.gia_von_xe) + so(x.gia_von_dung_chung) + so(x.chi_gia_von) + so(x.hao_hut);
  if (x.tong_chi_phi === undefined) x.tong_chi_phi = so(x.luong) + so(x.hoa_hong) + so(x.chi_van_hanh) + so(x.chi_co_dinh);
  return x;
}
const DONG_CD = [
  { nhan: 'DOANH THU THUẦN (gồm VAT)', k: 'doanh_thu', kieu: 'tong' },
  { nhan: 'Giá vốn (vật tư, hao hụt, thuê ngoài…)', k: 'tong_gia_von', dau: '−' },
  { nhan: 'LÃI GỘP', k: 'lai_gop', kieu: 'ket_qua' },
  { nhan: 'Tỷ suất lãi gộp', tu: 'lai_gop', kieu: 'ty_le' },
  { nhan: 'Chi phí hoạt động (lương, hoa hồng, vận hành, cố định)', k: 'tong_chi_phi', dau: '−' },
  { nhan: 'Thu nhập khác', k: 'thu_khac', dau: '+' },
  { nhan: 'LÃI TRƯỚC THUẾ (số gồm VAT)', k: 'lai_truoc_thue', kieu: 'ket_qua' },
  { nhan: 'Tỷ suất lãi trước thuế', tu: 'lai_truoc_thue', kieu: 'ty_le' },
  { nhan: 'Lãi không gồm VAT (ước tính, trước thuế TNDN)', k: 'lai_sau_vat', kieu: 'tong' },
  { nhan: 'Xe sửa chữa', k: 'so_xe', kieu: 'dem' },
];
// [nhãn, lấy số, dấu]: khoản phải trả hiện "− x", cộng vào vốn lưu động với dấu âm
const SO_DU = [
  ['Tiền (quỹ tiền mặt, ngân hàng)', (x) => so(x.so_du_quy), 1],
  ['Tồn kho (giá vốn)', (x) => so(x.ton_kho), 1],
  ['Phải thu khách, bảo hiểm', (x) => so(x.phai_thu_khach) + so(x.phai_thu_bh), 1],
  ['Phải trả nhà cung cấp, tiền khách trả trước', (x) => so(x.phai_tra_ncc) + so(x.khach_tra_du), -1],
];

export default async function trangCoDong(el) {
  const tatCa = await api.baoCaoCoDong();
  // Mỗi chi nhánh một báo cáo; mặc định chi nhánh của người xem
  const cacCn = [...new Set(tatCa.map((r) => r.chi_nhanh_id))];
  let cn = cacCn.includes(api.toi?.chi_nhanh_id) ? api.toi.chi_nhanh_id : cacCn[0];
  const vung = h('div');
  const chonCn = cacCn.length > 1 ? h('select', { 'aria-label': 'Chi nhánh', onchange: (e) => { cn = e.target.value; ve(); } },
    cacCn.map((c) => h('option', { value: c, selected: c === cn }, api.dm.ten('chi_nhanh', c) || c))) : null;
  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Báo cáo cổ đông'), chonCn),
    h('p', { class: 'mo-ta' }, 'Số của các tháng giám đốc đã chốt sổ (kỳ khóa ở ngày cuối tháng), lấy đúng số lúc chốt. Tháng đang mở chưa hiện ở đây.'),
    vung);

  function ve() {
    const ds = tatCa.filter((r) => r.chi_nhanh_id === cn).sort((a, b) => (a.thang < b.thang ? -1 : 1))   // tăng dần
      .map((r) => ({ ...r, s: chuanHoa(r.so_lieu) }));
    if (!ds.length) { dat(vung, h('section', { class: 'the' }, h('p', { class: 'trong' }, 'Chưa có tháng nào được chốt.'))); return; }
    const luyKe = congThang(ds.map((d) => d.s));
    const coDu = (k) => ds.every((d) => d.s[k] !== undefined);        // tháng chốt theo cách tính cũ thiếu "lãi không gồm VAT"
    const o = (r, d, laTong = false) => (r.k && (laTong ? !coDu(r.k) : d[r.k] === undefined) ? h('span', { class: 'mo', title: 'Tháng chốt trước khi có dòng này' }, '—')
      : (() => { const v = giaTri(r, d); const chu = chuO(r, v); return r.kieu === 'ket_qua' && v < 0 ? h('span', { class: 'chu-loi' }, chu) : chu; })());
    const cuoi = ds[ds.length - 1]; const truoc = ds[ds.length - 2];
    const thangCoSoDu = ds.filter((d) => d.s.so_du);
    dat(vung,
      h('section', { class: 'luoi-dem tien' },
        h('div', { class: 'o-dem' }, h('b', null, chuO({ k: 'doanh_thu' }, so(cuoi.s.doanh_thu)) || '0'), h('span', null, `Doanh thu tháng ${nhanThang(cuoi.thang)}`),
          truoc ? h('small', { class: 'o-dem-phu' }, oChenh(cuoi.s.doanh_thu, truoc.s.doanh_thu), ` so ${nhanThang(truoc.thang)}`) : null),
        h('div', { class: 'o-dem' }, h('b', { class: so(cuoi.s.lai_gop) < 0 ? 'chu-loi' : null }, chuO({ k: 'lai_gop' }, so(cuoi.s.lai_gop)) || '0'), h('span', null, `Lãi gộp tháng ${nhanThang(cuoi.thang)}`),
          truoc ? h('small', { class: 'o-dem-phu' }, oChenh(cuoi.s.lai_gop, truoc.s.lai_gop), ` so ${nhanThang(truoc.thang)}`) : null),
        h('div', { class: 'o-dem' }, h('b', { class: so(cuoi.s.lai_truoc_thue) < 0 ? 'chu-loi' : 'chu-tot' }, chuO({ k: 'lai_truoc_thue' }, so(cuoi.s.lai_truoc_thue)) || '0'),
          h('span', null, `Lãi trước thuế tháng ${nhanThang(cuoi.thang)}`)),
        h('div', { class: 'o-dem' }, h('b', { class: so(luyKe.lai_truoc_thue) < 0 ? 'chu-loi' : 'chu-tot' }, chuO({ k: 'lai_truoc_thue' }, so(luyKe.lai_truoc_thue)) || '0'),
          h('span', null, `Lãi trước thuế lũy kế ${ds.length} tháng đã chốt`)),
        cuoi.s.so_du ? h('div', { class: 'o-dem' }, h('b', null, chuO({ k: 'x' }, so(cuoi.s.so_du.so_du_quy)) || '0'), h('span', null, `Tiền cuối tháng ${nhanThang(cuoi.thang)}`)) : null),
      h('section', { class: 'the' }, bieuDoDuong({ tieuDe: 'Doanh thu – Lãi gộp – Lãi trước thuế các tháng đã chốt', nhan: ds.map((d) => nhanThang(d.thang)),
        chuoi: [{ ten: 'Doanh thu', giaTri: ds.map((d) => so(d.s.doanh_thu)) }, { ten: 'Lãi gộp', giaTri: ds.map((d) => so(d.s.lai_gop)) }, { ten: 'Lãi trước thuế', giaTri: ds.map((d) => so(d.s.lai_truoc_thue)) }] })),
      h('section', { class: 'the' }, h('h2', null, 'Kết quả theo tháng'),
        h('p', { class: 'goi-y' }, 'Đơn vị: đồng. Số gồm VAT như sổ của gara; "lãi không gồm VAT" là số ước tính gần với sổ thuế.'),
        bangBC(['Khoản mục', ...ds.map((d) => h('span', { class: 'cot-thang' }, nhanThang(d.thang), h('br'), h('small', { class: 'mo' }, `chốt ${ngay(d.chot_luc)}`))),
          h('span', { class: 'cot-thang' }, 'Lũy kế', h('br'), h('small', { class: 'mo' }, `${ds.length} tháng`))],
        DONG_CD.map((r) => ({ loai: r.kieu === 'dem' ? 'dem' : r.kieu || 'dong', nhan: r.nhan, o: [...ds.map((d) => o(r, d.s)), o(r, luyKe, true)] })), { lop: 'bc-kqkd' })),
      thangCoSoDu.length ? h('section', { class: 'the' }, h('h2', null, 'Tiền – công nợ – tồn kho cuối tháng'),
        bangBC(['Khoản mục', ...thangCoSoDu.map((d) => nhanThang(d.thang))], [
          ...SO_DU.map(([nhan, lay, dau]) => ({ loai: 'dong', nhan, o: thangCoSoDu.map((d) => chuO({ k: 'x', dau: dau < 0 ? '−' : null }, lay(d.s.so_du))) })),
          { loai: 'ket_qua', nhan: 'VỐN LƯU ĐỘNG RÒNG', o: thangCoSoDu.map((d) => chuO({ k: 'x' }, SO_DU.reduce((t, [, lay, dau]) => t + dau * lay(d.s.so_du), 0))) },
        ], { lop: 'bc-so-du' })) : null);
  }
  ve();
}
