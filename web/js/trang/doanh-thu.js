// Doanh thu và công nợ
//  - Doanh thu theo ngày duyệt giá (thay file BC DOANH THU THEO NGÀY). Tính sau VAT.
//  - Công nợ phải thu hiện tại: khách hàng và hãng bảo hiểm, từng hồ sơ đã giao xe còn nợ; nợ nhà cung cấp (phải trả).
import { h, bienSo, tien, ngay, homNay, bang, taiTepCSV, NHOM_BAO_CAO, nhomBaoCao, nhanTrangThai, dat, nhoPhien } from '../ui.js';
import * as api from '../api.js';

const NGUON = { bao_hiem: 'Bảo hiểm trả', khach: 'Khách trả', dich_vu_nhanh: 'Dịch vụ nhanh', giam_gia: 'Giảm giá cho khách' };

export default async function trangDoanhThu(el) {
  let the = nhoPhien.doc('dt_the') || 'doanh_thu';
  let thang = homNay().slice(0, 7);
  const oThang = h('input', { type: 'month', value: thang, 'aria-label': 'Tháng' });
  const ketQua = h('div');
  oThang.addEventListener('change', () => { thang = oThang.value; ve(); });
  const tabs = h('div', { class: 'tabs', role: 'tablist' }, [['doanh_thu', 'Doanh thu'], ['cong_no', 'Công nợ']].map(([ma, nhan]) => h('button', {
    type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === the),
    onclick: () => { the = ma; nhoPhien.ghi('dt_the', ma); for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === the)); ve(); },
  }, nhan)));
  const moTa = h('p', { class: 'mo-ta' });
  dat(el,
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Doanh thu & công nợ'), oThang),
    h('div', { class: 'thanh-loc' }, tabs), moTa, ketQua);

  async function ve() {
    dat(ketQua, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    oThang.hidden = the !== 'doanh_thu';
    if (the === 'doanh_thu') {
      moTa.textContent = 'Doanh thu ghi vào ngày duyệt giá (xe bảo hiểm) hoặc ngày khách đồng ý báo giá (khách lẻ), tính sau VAT. Không gồm xe bảo hành và hồ sơ chuyển từ Excel.';
      await veDoanhThu();
    } else {
      moTa.textContent = 'Công nợ phải thu tính đến hôm nay: xe đã giao mà khách hoặc hãng bảo hiểm chưa trả đủ (gồm nợ cũ chuyển từ Excel). Nợ nhà cung cấp lấy từ Kho → Công nợ NCC.';
      await veCongNo();
    }
  }

  // ---------------- Doanh thu ----------------
  async function veDoanhThu() {
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
      h('section', { class: 'luoi-dem tien' },
        h('div', { class: 'o-dem' }, h('b', null, tien(tong(() => true))), h('span', null, 'Tổng doanh thu tháng (sau VAT)')),
        Object.entries(NGUON).map(([k, nhan]) => h('div', { class: 'o-dem' }, h('b', null, tien(tong((r) => r.nguon === k))), h('span', null, nhan))),
        h('div', { class: 'o-dem' }, h('b', null, tien(tongVat)), h('span', null, 'VAT đầu ra trong số trên'))),
      h('section', { class: 'luoi-dem tien' }, Object.entries(NHOM_BAO_CAO).map(([k, nhan]) =>
        h('div', { class: 'o-dem' }, h('b', null, tien(tong((r) => nhomBaoCao(r.nhom) === k && r.nguon !== 'giam_gia'))), h('span', null, nhan)))),
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, 'Theo ngày'),
          api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`doanh-thu-${thang}.csv`, cot, ds) }, 'Tải file CSV') : null),
        bang(cot, ds, { trong: 'Tháng này chưa có doanh thu.' })));
  }

  // ---------------- Công nợ ----------------
  async function veCongNo() {
    const homNayMs = Date.now();
    const soNgay = (d) => (d ? Math.max(0, Math.floor((homNayMs - new Date(d).getTime()) / 864e5)) : null);
    const [hs, ncc] = await Promise.all([
      api.doc('v_ho_so', (q) => q.in('trang_thai', ['da_giao', 'da_gui_hs', 'dong']).or('con_no_khach.gt.0,con_no_bh.gt.0').order('giao_luc', { ascending: true })),
      api.coVaiTro('giam_doc', 'ke_toan', 'quan_ly') ? api.doc('v_cong_no_ncc').catch(() => []) : [],
    ]);
    const noKhach = hs.filter((x) => Number(x.con_no_khach) > 0);
    const noBH = hs.filter((x) => Number(x.con_no_bh) > 0);
    const tongKhach = noKhach.reduce((s, x) => s + Number(x.con_no_khach), 0);
    const tongBH = noBH.reduce((s, x) => s + Number(x.con_no_bh), 0);
    const noNcc = ncc.map((r) => ({ ...r, con: Number(r.da_nhap) - Number(r.da_tra) })).filter((r) => r.con > 0);
    const tongNcc = noNcc.reduce((s, r) => s + r.con, 0);
    // Theo hãng bảo hiểm
    const theoHang = new Map();
    for (const x of noBH) {
      const k = x.hang_bh || 'Chưa ghi hãng';
      const c = theoHang.get(k) || { hang: k, so: 0, tien: 0, lau_nhat: null };
      c.so += 1; c.tien += Number(x.con_no_bh);
      const n = soNgay(x.gui_hs_ngay || x.giao_luc);
      if (n !== null && (c.lau_nhat === null || n > c.lau_nhat)) c.lau_nhat = n;
      theoHang.set(k, c);
    }
    const dsHang = [...theoHang.values()].sort((a, b) => b.tien - a.tien);

    let loc = 'tat';
    const kq = h('div');
    const tabsCon = h('div', { class: 'tabs nho', role: 'tablist' }, [['tat', `Tất cả (${hs.length})`], ['khach', `Khách nợ (${noKhach.length})`], ['bao_hiem', `Bảo hiểm nợ (${noBH.length})`]].map(([ma, nhan]) =>
      h('button', { type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === loc),
        onclick: () => { loc = ma; for (const b of tabsCon.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); veBang(); } }, nhan)));
    const cot = [
      { nhan: 'Biển số', lay: (x) => h('a', { href: `#/ho-so/${x.id}`, class: 'lien-ket-xe' }, bienSo(x.bien_so_hien_thi, { maThay: x.ma })), xuat: (x) => x.bien_so_hien_thi || x.ma },
      { nhan: 'Khách', lay: (x) => h('span', null, x.ten_khach, h('br'), h('small', null, x.dien_thoai || '')), xuat: (x) => x.ten_khach },
      { nhan: 'Nguồn', lay: (x) => (x.nguon_tt === 'khach' ? 'Ngoài BH' : x.hang_bh || 'Bảo hiểm'), xuat: (x) => (x.nguon_tt === 'khach' ? 'Ngoài BH' : x.hang_bh || 'Bảo hiểm') },
      { nhan: 'Giao xe', lay: (x) => (x.giao_luc ? h('span', null, ngay(x.giao_luc), h('br'), h('small', null, `${soNgay(x.giao_luc)} ngày`)) : (x.tu_excel ? 'Nợ cũ (Excel)' : '')), xuat: (x) => (x.giao_luc ? ngay(x.giao_luc) : '') },
      { nhan: 'Gửi hồ sơ BH', lay: (x) => (x.nguon_tt === 'khach' ? '' : x.gui_hs_ngay ? h('span', null, ngay(x.gui_hs_ngay), h('br'), h('small', null, `${soNgay(x.gui_hs_ngay)} ngày`)) : h('span', { class: 'chu-loi' }, 'Chưa gửi')), xuat: (x) => (x.gui_hs_ngay ? ngay(x.gui_hs_ngay) : '') },
      { nhan: 'Khách còn nợ', so: true, lay: (x) => h('b', { class: Number(x.con_no_khach) > 0 ? 'chu-loi' : null }, tien(x.con_no_khach) || '0'), xuat: (x) => Number(x.con_no_khach) },
      { nhan: 'BH còn nợ', so: true, lay: (x) => (x.nguon_tt === 'khach' ? '' : h('b', { class: Number(x.con_no_bh) > 0 ? 'chu-cam' : null }, tien(x.con_no_bh) || '0')), xuat: (x) => (x.nguon_tt === 'khach' ? '' : Number(x.con_no_bh)) },
      { nhan: 'Bước', lay: (x) => nhanTrangThai(x.trang_thai), xuat: (x) => x.trang_thai },
    ];
    const dsLoc = () => (loc === 'khach' ? noKhach : loc === 'bao_hiem' ? noBH : hs);
    const veBang = () => {
      const ds = dsLoc();
      dat(kq, bang(cot, ds, { trong: 'Không có hồ sơ nào còn nợ.' }),
        ds.length ? h('p', { class: 'mo-ta' }, `${ds.length} hồ sơ · Khách còn nợ ${tien(ds.reduce((s, x) => s + Number(x.con_no_khach), 0))} đ · Bảo hiểm còn nợ ${tien(ds.reduce((s, x) => s + Number(x.con_no_bh), 0))} đ`) : null);
    };
    dat(ketQua,
      h('section', { class: 'luoi-dem tien' },
        h('div', { class: 'o-dem', 'data-no-khach': '' }, h('b', { class: tongKhach > 0 ? 'chu-loi' : null }, tien(tongKhach)), h('span', null, `Khách hàng còn nợ · ${noKhach.length} xe`)),
        h('div', { class: 'o-dem', 'data-no-bh': '' }, h('b', { class: tongBH > 0 ? 'chu-cam' : null }, tien(tongBH)), h('span', null, `Hãng bảo hiểm còn nợ · ${noBH.length} hồ sơ`)),
        h('div', { class: 'o-dem' }, h('b', null, tien(tongKhach + tongBH)), h('span', null, 'Tổng phải thu')),
        ncc.length ? h('a', { class: 'o-dem', href: '#/kho?the=cong_no' }, h('b', null, tien(tongNcc)), h('span', null, `Nợ nhà cung cấp (phải trả) · ${noNcc.length} NCC`)) : null),
      dsHang.length ? h('section', { class: 'the' }, h('h2', null, 'Theo hãng bảo hiểm'),
        bang([
          { nhan: 'Hãng bảo hiểm', lay: (c) => h('b', null, c.hang) },
          { nhan: 'Số hồ sơ', so: true, lay: (c) => c.so },
          { nhan: 'Còn nợ', so: true, lay: (c) => h('b', { class: 'chu-cam' }, tien(c.tien)) },
          { nhan: 'Lâu nhất', so: true, lay: (c) => (c.lau_nhat === null ? '' : `${c.lau_nhat} ngày`) },
        ], dsHang)) : null,
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, 'Hồ sơ còn nợ'),
          api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`cong-no_${homNay()}.csv`, cot, dsLoc()) }, 'Tải file CSV') : null),
        tabsCon, kq));
    veBang();
  }
  await ve();
}
