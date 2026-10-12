// Doanh thu theo ngày duyệt giá (thay file BC DOANH THU THEO NGÀY). Tính sau VAT.
import { h, bienSo, tien, ngay, homNay, bang, taiTepCSV, NHOM_BAO_CAO, nhomBaoCao, dat } from '../ui.js';
import * as api from '../api.js';

const NGUON = { bao_hiem: 'Bảo hiểm trả', khach: 'Khách trả', dich_vu_nhanh: 'Dịch vụ nhanh', giam_gia: 'Giảm giá cho khách' };

export default async function trangDoanhThu(el) {
  let thang = homNay().slice(0, 7);
  const oThang = h('input', { type: 'month', value: thang, 'aria-label': 'Tháng' });
  const ketQua = h('div');
  oThang.addEventListener('change', () => { thang = oThang.value; tai(); });
  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Doanh thu'), oThang),
    h('p', { class: 'mo-ta' }, 'Doanh thu ghi vào ngày duyệt giá (xe bảo hiểm) hoặc ngày khách đồng ý báo giá (khách lẻ), tính sau VAT. Không gồm xe bảo hành và hồ sơ chuyển từ Excel.'),
    ketQua);

  async function tai() {
    dat(ketQua, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    const den = new Date(Number(thang.slice(0, 4)), Number(thang.slice(5, 7)), 0).toISOString().slice(0, 10);
    const rows = await api.doc('v_doanh_thu', (q) => q.gte('ngay', `${thang}-01`).lte('ngay', den).order('ngay').order('ma'));
    const tong = (loc) => rows.filter(loc).reduce((s, r) => s + Number(r.so_tien), 0);
    const tongVat = rows.reduce((s, r) => s + Number(r.vat_ra), 0);
    // Gộp theo ngày + hồ sơ
    const theoXe = new Map();
    for (const r of rows) {
      const k = `${r.ngay}|${r.ho_so_id || 'dvn-' + r.bien_so + r.so_tien}|${r.nguon === 'dich_vu_nhanh' ? Math.random() : ''}`;
      const g = theoXe.get(k) || { ngay: r.ngay, ma: r.ma, ho_so_id: r.ho_so_id, bien_so: r.bien_so, bao_hiem: 0, khach: 0, dich_vu_nhanh: 0, giam_gia: 0,
        dong_son: 0, phu_tung: 0, dmg: 0, detailing: 0, tong: 0 };
      g[r.nguon] += Number(r.so_tien);
      if (r.nhom && r.nguon !== 'giam_gia') g[nhomBaoCao(r.nhom)] += Number(r.so_tien);
      g.tong += Number(r.so_tien);
      theoXe.set(k, g);
    }
    const ds = [...theoXe.values()];
    const cot = [
      { nhan: 'Ngày', lay: (d) => ngay(d.ngay), xuat: (d) => ngay(d.ngay) },
      { nhan: 'Biển số', lay: (d) => d.ho_so_id ? h('a', { href: `#/ho-so/${d.ho_so_id}`, class: 'lien-ket-xe' }, bienSo(d.bien_so, { maThay: d.ma })) : (d.bien_so || 'Dịch vụ nhanh'), xuat: (d) => d.bien_so || d.ma || '' },
      { nhan: 'Bảo hiểm', so: true, lay: (d) => tien(d.bao_hiem), xuat: (d) => d.bao_hiem },
      { nhan: 'Khách', so: true, lay: (d) => tien(d.khach + d.dich_vu_nhanh + d.giam_gia), xuat: (d) => d.khach + d.dich_vu_nhanh + d.giam_gia },
      { nhan: 'Đồng sơn', so: true, lay: (d) => tien(d.dong_son), xuat: (d) => d.dong_son },
      { nhan: 'Phụ tùng', so: true, lay: (d) => tien(d.phu_tung), xuat: (d) => d.phu_tung },
      { nhan: 'ĐMG', so: true, lay: (d) => tien(d.dmg), xuat: (d) => d.dmg },
      { nhan: 'Detailing', so: true, lay: (d) => tien(d.detailing), xuat: (d) => d.detailing },
      { nhan: 'Tổng', so: true, lay: (d) => h('b', null, tien(d.tong)), xuat: (d) => d.tong },
    ];
    dat(ketQua, 
      h('section', { class: 'luoi-dem' },
        h('div', { class: 'o-dem' }, h('b', null, tien(tong(() => true))), h('span', null, 'Tổng doanh thu tháng (sau VAT)')),
        Object.entries(NGUON).map(([k, nhan]) => h('div', { class: 'o-dem' }, h('b', null, tien(tong((r) => r.nguon === k))), h('span', null, nhan))),
        h('div', { class: 'o-dem' }, h('b', null, tien(tongVat)), h('span', null, 'VAT đầu ra trong số trên'))),
      h('section', { class: 'luoi-dem' }, Object.entries(NHOM_BAO_CAO).map(([k, nhan]) =>
        h('div', { class: 'o-dem' }, h('b', null, tien(tong((r) => nhomBaoCao(r.nhom) === k && r.nguon !== 'giam_gia'))), h('span', null, nhan)))),
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, 'Theo ngày'),
          api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`doanh-thu-${thang}.csv`, cot, ds) }, 'Tải file CSV') : null),
        bang(cot, ds, { trong: 'Tháng này chưa có doanh thu.' })));
  }
  await tai();
}
