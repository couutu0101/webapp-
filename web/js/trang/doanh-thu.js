// Doanh thu và công nợ
//  - Doanh thu theo ngày duyệt giá (thay file BC DOANH THU THEO NGÀY). Tính sau VAT.
//  - Công nợ phải thu hiện tại: khách hàng và hãng bảo hiểm, từng hồ sơ đã giao xe còn nợ; nợ nhà cung cấp (phải trả).
import { h, bienSo, tien, ngay, ngayGio, homNay, bang, taiTepCSV, NHOM_BAO_CAO, nhomBaoCao, nhanTrangThai, dat, nhoPhien, moModal, oTien, oVung, truong, docForm, toast, xacNhan, chay } from '../ui.js';
import * as api from '../api.js';
import { bieuDoDuong } from '../bieu-do.js';

const NGUON = { bao_hiem: 'Bảo hiểm trả', khach: 'Khách trả', dich_vu_nhanh: 'Dịch vụ nhanh', giam_gia: 'Giảm giá cho khách' };

export default async function trangDoanhThu(el) {
  let the = nhoPhien.doc('dt_the') || 'doanh_thu';
  let thang = '';                                             // '' = từ trước đến nay
  const oThang = h('input', { type: 'month', value: '', 'aria-label': 'Lọc theo tháng', max: homNay().slice(0, 7) });
  const nutTatCa = h('button', { class: 'nut nho', type: 'button', hidden: true, onclick: () => { thang = ''; oThang.value = ''; ve(); } }, 'Tất cả');
  const khungLoc = h('div', { class: 'hang-nut' }, h('span', { class: 'mo-ta' }, 'Lọc theo tháng:'), oThang, nutTatCa);
  const ketQua = h('div');
  oThang.addEventListener('change', () => { thang = oThang.value; ve(); });
  const tabs = h('div', { class: 'tabs', role: 'tablist' }, [['doanh_thu', 'Doanh thu'], ['cong_no', 'Công nợ'], ['kqkd', 'Kết quả kinh doanh']].map(([ma, nhan]) => h('button', {
    type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === the),
    onclick: () => { the = ma; nhoPhien.ghi('dt_the', ma); for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === the)); ve(); },
  }, nhan)));
  const moTa = h('p', { class: 'mo-ta' });
  dat(el,
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Doanh thu & công nợ'), khungLoc),
    h('div', { class: 'thanh-loc' }, tabs), moTa, ketQua);

  async function ve() {
    dat(ketQua, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    khungLoc.hidden = the !== 'doanh_thu';
    nutTatCa.hidden = !thang;
    if (the === 'doanh_thu') {
      moTa.textContent = (thang ? `Doanh thu tháng ${thang.slice(5, 7)}/${thang.slice(0, 4)}` : 'Doanh thu từ trước đến nay')
        + ' – ghi vào ngày duyệt giá (xe bảo hiểm) hoặc ngày khách đồng ý báo giá (khách lẻ), tính sau VAT. Không gồm xe bảo hành và hồ sơ chuyển từ Excel.';
      await veDoanhThu();
    } else if (the === 'kqkd') {
      moTa.textContent = 'Lãi lỗ từng tháng: doanh thu (sau VAT, theo ngày duyệt giá) − giá vốn (vật tư xuất kho theo tháng xuất, chi phí nhóm Giá vốn) = lãi gộp − lương (bảng lương tháng) − hoa hồng GDV (theo tháng duyệt giá của xe) − chi phí vận hành, cố định = lãi trước thuế. Giám đốc chốt tháng để khóa sổ; cổ đông chỉ xem tháng đã chốt.';
      await veKqkd();
    } else {
      moTa.textContent = 'Công nợ phải thu tính đến hôm nay theo giá đã duyệt: cả xe đã giao lẫn xe còn trong xưởng, khách hoặc hãng bảo hiểm chưa trả đủ (gồm nợ cũ chuyển từ Excel). Nợ nhà cung cấp lấy từ Kho → Công nợ NCC.';
      await veCongNo();
    }
  }

  // ---------------- Doanh thu ----------------
  async function veDoanhThu() {
    const den = thang ? new Date(Number(thang.slice(0, 4)), Number(thang.slice(5, 7)), 0).toISOString().slice(0, 10) : null;
    const rows = await api.doc('v_doanh_thu', (q) => (thang ? q.gte('ngay', `${thang}-01`).lte('ngay', den) : q).order('ngay').order('ma').limit(5000));
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
    // Gộp theo tháng (khi xem từ trước đến nay): bấm vào một tháng để lọc
    const theoThang = new Map();
    for (const r of rows) {
      const k = String(r.ngay).slice(0, 7);
      const g = theoThang.get(k) || { thang: k, bao_hiem: 0, khach: 0, dich_vu_nhanh: 0, giam_gia: 0, tong: 0, so_xe: new Set() };
      g[r.nguon] += Number(r.so_tien); g.tong += Number(r.so_tien); if (r.ho_so_id) g.so_xe.add(r.ho_so_id);
      theoThang.set(k, g);
    }
    const dsThang = [...theoThang.values()].sort((a, b) => (a.thang < b.thang ? 1 : -1));
    const cotThang = [
      { nhan: 'Tháng', lay: (d) => h('a', { href: '#', onclick: (e) => { e.preventDefault(); thang = d.thang; oThang.value = d.thang; ve(); } }, `${d.thang.slice(5, 7)}/${d.thang.slice(0, 4)}`), xuat: (d) => d.thang },
      { nhan: 'Số xe', so: true, lay: (d) => d.so_xe.size, xuat: (d) => d.so_xe.size },
      { nhan: 'Bảo hiểm', so: true, lay: (d) => tien(d.bao_hiem), xuat: (d) => d.bao_hiem },
      { nhan: 'Khách', so: true, lay: (d) => tien(d.khach + d.dich_vu_nhanh + d.giam_gia), xuat: (d) => d.khach + d.dich_vu_nhanh + d.giam_gia },
      { nhan: 'Dịch vụ nhanh', so: true, lay: (d) => tien(d.dich_vu_nhanh), xuat: (d) => d.dich_vu_nhanh },
      { nhan: 'Tổng', so: true, lay: (d) => h('b', null, tien(d.tong)), xuat: (d) => d.tong },
    ];
    dat(ketQua,
      h('section', { class: 'luoi-dem tien' },
        h('div', { class: 'o-dem' }, h('b', null, tien(tong(() => true))), h('span', null, thang ? 'Tổng doanh thu tháng (sau VAT)' : 'Tổng doanh thu từ trước đến nay (sau VAT)')),
        Object.entries(NGUON).map(([k, nhan]) => h('div', { class: 'o-dem' }, h('b', null, tien(tong((r) => r.nguon === k))), h('span', null, nhan))),
        h('div', { class: 'o-dem' }, h('b', null, tien(tongVat)), h('span', null, 'VAT đầu ra trong số trên'))),
      h('section', { class: 'luoi-dem tien' }, Object.entries(NHOM_BAO_CAO).map(([k, nhan]) =>
        h('div', { class: 'o-dem' }, h('b', null, tien(tong((r) => nhomBaoCao(r.nhom) === k && r.nguon !== 'giam_gia'))), h('span', null, nhan)))),
      !thang && dsThang.length ? h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, 'Theo tháng'),
          api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV('doanh-thu-theo-thang.csv', cotThang, dsThang) }, 'Tải file CSV') : null),
        h('p', { class: 'goi-y' }, 'Bấm vào tháng để xem chi tiết theo ngày của tháng đó.'),
        bang(cotThang, dsThang)) : null,
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, thang ? 'Theo ngày' : `Theo ngày (${ds.length} dòng)`),
          api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`doanh-thu-${thang || 'tat-ca'}.csv`, cot, ds) }, 'Tải file CSV') : null),
        bang(cot, ds, { trong: thang ? 'Tháng này chưa có doanh thu.' : 'Chưa có doanh thu.' })));
  }

  // ---------------- Công nợ ----------------
  async function veCongNo() {
    const homNayMs = Date.now();
    const soNgay = (d) => (d ? Math.max(0, Math.floor((homNayMs - new Date(d).getTime()) / 864e5)) : null);
    const [hs, ncc] = await Promise.all([
      api.doc('v_ho_so', (q) => q.neq('trang_thai', 'huy').or('con_no_khach.gt.0,con_no_bh.gt.0').order('giao_luc', { ascending: true, nullsFirst: false }).order('ngay_vao')),
      api.coVaiTro('giam_doc', 'ke_toan', 'quan_ly') ? api.doc('v_cong_no_ncc').catch(() => []) : [],
    ]);
    const noKhach = hs.filter((x) => Number(x.con_no_khach) > 0);
    const noBH = hs.filter((x) => Number(x.con_no_bh) > 0);
    const chuaGiao = hs.filter((x) => !x.giao_luc && !x.tu_excel);
    const tongChuaGiao = chuaGiao.reduce((s, x) => s + Number(x.con_no_khach) + Number(x.con_no_bh), 0);
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
    // Phần khách: khách ngoài bảo hiểm, và khách của xe bảo hiểm (khấu trừ, dòng tự trả)
    const gomKhach = (ds, ten) => {
      if (!ds.length) return null;
      const c = { hang: ten, so: ds.length, tien: 0, lau_nhat: null, khach: true };
      for (const x of ds) { c.tien += Number(x.con_no_khach); const n = soNgay(x.giao_luc); if (n !== null && (c.lau_nhat === null || n > c.lau_nhat)) c.lau_nhat = n; }
      return c;
    };
    const dsBen = [...dsHang, gomKhach(noKhach.filter((x) => x.nguon_tt === 'khach'), 'Khách ngoài bảo hiểm'),
      gomKhach(noKhach.filter((x) => x.nguon_tt !== 'khach'), 'Khách của xe bảo hiểm (khấu trừ, phần tự trả)')].filter(Boolean);

    let loc = 'tat';
    const kq = h('div');
    const tabsCon = h('div', { class: 'tabs nho', role: 'tablist' }, [['tat', `Tất cả (${hs.length})`], ['khach', `Khách nợ (${noKhach.length})`], ['bao_hiem', `Bảo hiểm nợ (${noBH.length})`], ['chua_giao', `Xe chưa giao (${chuaGiao.length})`]].map(([ma, nhan]) =>
      h('button', { type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === loc),
        onclick: () => { loc = ma; for (const b of tabsCon.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); veBang(); } }, nhan)));
    const cot = [
      { nhan: 'Biển số', lay: (x) => h('a', { href: `#/ho-so/${x.id}`, class: 'lien-ket-xe' }, bienSo(x.bien_so_hien_thi, { maThay: x.ma })), xuat: (x) => x.bien_so_hien_thi || x.ma },
      { nhan: 'Khách', lay: (x) => h('span', null, x.ten_khach, h('br'), h('small', null, x.dien_thoai || '')), xuat: (x) => x.ten_khach },
      { nhan: 'Nguồn', lay: (x) => (x.nguon_tt === 'khach' ? 'Ngoài BH' : x.hang_bh || 'Bảo hiểm'), xuat: (x) => (x.nguon_tt === 'khach' ? 'Ngoài BH' : x.hang_bh || 'Bảo hiểm') },
      { nhan: 'Giao xe', lay: (x) => (x.giao_luc ? h('span', null, ngay(x.giao_luc), h('br'), h('small', null, `${soNgay(x.giao_luc)} ngày`)) : (x.tu_excel ? 'Nợ cũ (Excel)' : h('span', { class: 'chu-cam' }, 'Chưa giao'))), xuat: (x) => (x.giao_luc ? ngay(x.giao_luc) : x.tu_excel ? 'Nợ cũ' : 'Chưa giao') },
      { nhan: 'Gửi hồ sơ BH', lay: (x) => (x.nguon_tt === 'khach' ? '' : x.gui_hs_ngay ? h('span', null, ngay(x.gui_hs_ngay), h('br'), h('small', null, `${soNgay(x.gui_hs_ngay)} ngày`)) : h('span', { class: 'chu-loi' }, 'Chưa gửi')), xuat: (x) => (x.gui_hs_ngay ? ngay(x.gui_hs_ngay) : '') },
      { nhan: 'Khách còn nợ', so: true, lay: (x) => h('b', { class: Number(x.con_no_khach) > 0 ? 'chu-loi' : null }, tien(x.con_no_khach) || '0'), xuat: (x) => Number(x.con_no_khach) },
      { nhan: 'BH còn nợ', so: true, lay: (x) => (x.nguon_tt === 'khach' ? '' : h('b', { class: Number(x.con_no_bh) > 0 ? 'chu-cam' : null }, tien(x.con_no_bh) || '0')), xuat: (x) => (x.nguon_tt === 'khach' ? '' : Number(x.con_no_bh)) },
      { nhan: 'Bước', lay: (x) => nhanTrangThai(x.trang_thai), xuat: (x) => x.trang_thai },
    ];
    const dsLoc = () => (loc === 'khach' ? noKhach : loc === 'bao_hiem' ? noBH : loc === 'chua_giao' ? chuaGiao : hs);
    const veBang = () => {
      const ds = dsLoc();
      dat(kq, bang(cot, ds, { trong: 'Không có hồ sơ nào còn nợ.' }),
        ds.length ? h('p', { class: 'mo-ta' }, `${ds.length} hồ sơ · Khách còn nợ ${tien(ds.reduce((s, x) => s + Number(x.con_no_khach), 0))} đ · Bảo hiểm còn nợ ${tien(ds.reduce((s, x) => s + Number(x.con_no_bh), 0))} đ`) : null);
    };
    dat(ketQua,
      h('section', { class: 'luoi-dem tien' },
        h('div', { class: 'o-dem', 'data-no-khach': '' }, h('b', { class: tongKhach > 0 ? 'chu-loi' : null }, tien(tongKhach)), h('span', null, `Khách hàng còn nợ · ${noKhach.length} xe`)),
        h('div', { class: 'o-dem', 'data-no-bh': '' }, h('b', { class: tongBH > 0 ? 'chu-cam' : null }, tien(tongBH)), h('span', null, `Hãng bảo hiểm còn nợ · ${noBH.length} hồ sơ`)),
        h('div', { class: 'o-dem' }, h('b', null, tien(tongKhach + tongBH)), h('span', null, `Tổng phải thu · trong đó xe chưa giao ${tien(tongChuaGiao)} đ`)),
        ncc.length ? h('a', { class: 'o-dem', href: '#/kho?the=cong_no' }, h('b', null, tien(tongNcc)), h('span', null, `Nợ nhà cung cấp (phải trả) · ${noNcc.length} NCC`)) : null),
      dsBen.length ? h('section', { class: 'the' }, h('h2', null, 'Theo bên nợ'),
        bang([
          { nhan: 'Bên nợ', lay: (c) => h('b', null, c.hang) },
          { nhan: 'Số hồ sơ', so: true, lay: (c) => c.so },
          { nhan: 'Còn nợ', so: true, lay: (c) => h('b', { class: c.khach ? 'chu-loi' : 'chu-cam' }, tien(c.tien)) },
          { nhan: 'Lâu nhất (từ giao xe / gửi hồ sơ)', so: true, lay: (c) => (c.lau_nhat === null ? '' : `${c.lau_nhat} ngày`) },
        ], dsBen),
        h('p', { class: 'mo-ta' }, `Tổng cộng ${tien(dsBen.reduce((s, c) => s + c.tien, 0))} đ`)) : null,
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, 'Hồ sơ còn nợ'),
          api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`cong-no_${homNay()}.csv`, cot, dsLoc()) }, 'Tải file CSV') : null),
        tabsCon, kq));
    veBang();
  }
  // ---------------- Kết quả kinh doanh ----------------
  //  Mỗi tháng một cột (sang tháng mới tự có cột mới, tháng cũ vẫn còn), biểu đồ tăng giảm, trạng thái từng tháng,
  //  checklist trước khi chốt (lương, chi phí định kỳ như điện, đề nghị chi chưa chi). Kỳ khóa ở ngày cuối tháng.
  async function veKqkd() {
    const tatCa = await api.ketQuaKinhDoanh();            // tăng dần theo tháng
    const gd = api.coVaiTro('giam_doc'); const kt = api.coVaiTro('ke_toan', 'giam_doc');
    const nhanThang = (d) => `${String(d.thang).slice(5, 7)}/${String(d.thang).slice(0, 4)}`;
    const namCua = (d) => String(d.thang).slice(0, 4);
    const cacNam = [...new Set(tatCa.map(namCua))].sort().reverse();
    let nam = nhoPhien.doc('kqkd_nam') || homNay().slice(0, 4);
    if (!cacNam.includes(nam)) nam = cacNam[0] || homNay().slice(0, 4);
    const ds = tatCa.filter((d) => namCua(d) === nam);
    const so = (v) => Number(v) || 0;
    const phanTram = (tu, mau) => (mau ? `${((tu / Math.abs(mau)) * 100).toLocaleString('vi-VN', { maximumFractionDigits: 1 })}%` : '—');
    const tangTruong = (cur, prev) => (prev === null || prev === undefined || !so(prev) ? null : (so(cur) - so(prev)) / Math.abs(so(prev)));
    const oTang = (tt, { tot = true } = {}) => {
      if (tt === null) return h('span', { class: 'mo' }, '—');
      const len = tt >= 0; const lenTot = tot ? len : !len;
      return h('span', { class: `tang-truong ${lenTot ? 'tot' : 'xau'}` }, `${len ? '▲' : '▼'} ${Math.abs(tt * 100).toLocaleString('vi-VN', { maximumFractionDigits: 1 })}%`);
    };
    const NHAN_TT = { dang_mo: ['Đang mở', 'tt-mo'], cho_chot: ['Chờ chốt', 'tt-canh-bao'], da_chot: ['Đã chốt', 'tt-tot'] };
    const theTT = (d) => h('span', { class: `nhan ${NHAN_TT[d.trang_thai][1]}`, title: d.da_chot ? `Chốt lúc ${ngayGio(d.chot_luc)}` : `Kỳ 01/${nhanThang(d)} – ${ngay(d.ngay_cuoi)}` }, NHAN_TT[d.trang_thai][0]);

    // ----- Ô số tháng gần nhất + lũy kế năm -----
    const cuoi = ds[ds.length - 1]; const truoc = ds[ds.length - 2];
    const luyKe = (k) => ds.reduce((t, d) => t + so(d[k]), 0);
    const oSo = (nhan, giaTri, phu, { tt = null } = {}) => h('div', { class: 'o-dem' }, h('b', null, giaTri), h('span', null, nhan), phu ? h('small', { class: 'o-dem-phu' }, phu) : null);
    const khoiSo = cuoi ? h('section', { class: 'luoi-dem tien' },
      oSo(`Doanh thu tháng ${nhanThang(cuoi)}`, tien(cuoi.doanh_thu) || '0', h('span', null, oTang(tangTruong(cuoi.doanh_thu, truoc?.doanh_thu)), truoc ? ` so với ${nhanThang(truoc)}` : '')),
      oSo(`Lãi gộp tháng ${nhanThang(cuoi)}`, tien(cuoi.lai_gop) || '0', h('span', null, `Tỷ suất ${phanTram(so(cuoi.lai_gop), so(cuoi.doanh_thu))} · `, oTang(tangTruong(cuoi.lai_gop, truoc?.lai_gop)))),
      h('div', { class: 'o-dem' }, h('b', { class: so(cuoi.lai_truoc_thue) < 0 ? 'chu-loi' : 'chu-tot' }, tien(cuoi.lai_truoc_thue) || '0'), h('span', null, `Lãi trước thuế tháng ${nhanThang(cuoi)}`),
        h('small', { class: 'o-dem-phu' }, `Tỷ suất ${phanTram(so(cuoi.lai_truoc_thue), so(cuoi.doanh_thu))} · `, oTang(tangTruong(cuoi.lai_truoc_thue, truoc?.lai_truoc_thue)))),
      h('div', { class: 'o-dem' }, h('b', { class: luyKe('lai_truoc_thue') < 0 ? 'chu-loi' : 'chu-tot' }, tien(luyKe('lai_truoc_thue')) || '0'), h('span', null, `Lãi trước thuế lũy kế năm ${nam}`),
        h('small', { class: 'o-dem-phu' }, `Doanh thu lũy kế ${tien(luyKe('doanh_thu')) || '0'} đ · ${ds.length} tháng`))) : null;

    // ----- Biểu đồ -----
    const bieuDo = bieuDoDuong({
      tieuDe: `Doanh thu – Lãi gộp – Lãi trước thuế theo tháng, năm ${nam}`,
      phuDe: cuoi ? `Số liệu đến hết ngày ${ngay(cuoi.ngay_cuoi)}${cuoi.trang_thai === 'dang_mo' ? ' (tháng hiện tại chưa đủ, đang cập nhật)' : ''}. Rê chuột hoặc dùng phím ← → để xem từng tháng.` : '',
      nhan: ds.map(nhanThang),
      chuoi: [{ ten: 'Doanh thu', giaTri: ds.map((d) => so(d.doanh_thu)) }, { ten: 'Lãi gộp', giaTri: ds.map((d) => so(d.lai_gop)) }, { ten: 'Lãi trước thuế', giaTri: ds.map((d) => so(d.lai_truoc_thue)) }],
    });

    // ----- Bảng: dòng = khoản mục, cột = tháng tăng dần + Lũy kế năm -----
    const DONG = [
      ['Doanh thu bảo hiểm', 'doanh_thu_bh'], ['Doanh thu khách', 'doanh_thu_khach'], ['Dịch vụ nhanh', 'doanh_thu_dvn'], ['Giảm giá cho khách', 'giam_gia'],
      ['DOANH THU (sau VAT)', 'doanh_thu', 'dam'],
      ['Tăng trưởng doanh thu so tháng trước', 'tang_dt', 'ty_le'],
      ['Vật tư, phụ tùng xuất cho xe', 'gia_von_xe', 'tru'], ['Vật tư dùng chung xưởng', 'gia_von_dung_chung', 'tru'], ['Chi phí nhóm Giá vốn (sơn, thuê ngoài…)', 'chi_gia_von', 'tru'],
      ['LÃI GỘP', 'lai_gop', 'dam'], ['Tỷ suất lãi gộp / doanh thu', 'ts_lai_gop', 'ty_le'],
      ['Lương (bảng lương tháng)', 'luong', 'tru'], ['Hoa hồng GDV', 'hoa_hong', 'tru'], ['Chi phí vận hành', 'chi_van_hanh', 'tru'], ['Chi phí cố định (điện, mặt bằng…)', 'chi_co_dinh', 'tru'],
      ['LÃI TRƯỚC THUẾ', 'lai_truoc_thue', 'dam'], ['Tỷ suất lãi trước thuế / doanh thu', 'ts_lai', 'ty_le'],
      ['VAT đầu ra (trong doanh thu)', 'vat_ra', 'phu'], ['VAT đầu vào (hóa đơn mua)', 'vat_vao', 'phu'], ['Số xe có doanh thu', 'so_xe', 'phu'],
    ].map(([nhan, khoa, kieu]) => ({ nhan, khoa, kieu }));
    const giaTriO = (r, d, dTruoc) => {
      if (r.khoa === 'tang_dt') return oTang(tangTruong(d.doanh_thu, dTruoc?.doanh_thu));
      if (r.khoa === 'ts_lai_gop') return h('span', { class: 'mo' }, phanTram(so(d.lai_gop), so(d.doanh_thu)));
      if (r.khoa === 'ts_lai') return h('span', { class: 'mo' }, phanTram(so(d.lai_truoc_thue), so(d.doanh_thu)));
      if (r.khoa === 'so_xe') return h('span', { class: 'mo' }, d.so_xe);
      const v = so(d[r.khoa]);
      return h('span', { class: `${r.kieu === 'dam' ? 'dam' : ''} ${r.kieu === 'tru' || r.kieu === 'phu' ? 'mo' : ''} ${r.khoa === 'lai_truoc_thue' || r.khoa === 'lai_gop' ? (v < 0 ? 'chu-loi' : '') : ''}` },
        r.kieu === 'tru' && v ? `− ${tien(v)}` : tien(v) || '0');
    };
    const xuatO = (r, d, dTruoc) => {
      if (r.khoa === 'tang_dt') { const t = tangTruong(d.doanh_thu, dTruoc?.doanh_thu); return t === null ? '' : Math.round(t * 1000) / 10; }
      if (r.khoa === 'ts_lai_gop') return so(d.doanh_thu) ? Math.round((so(d.lai_gop) / so(d.doanh_thu)) * 1000) / 10 : '';
      if (r.khoa === 'ts_lai') return so(d.doanh_thu) ? Math.round((so(d.lai_truoc_thue) / so(d.doanh_thu)) * 1000) / 10 : '';
      return so(d[r.khoa]);
    };
    const tong = { thang: null };
    for (const r of DONG) tong[r.khoa] = ['tang_dt', 'ts_lai_gop', 'ts_lai'].includes(r.khoa) ? null : ds.reduce((t, d) => t + so(d[r.khoa]), 0);
    const cot = [{ nhan: 'Khoản mục', lay: (r) => h('span', { class: r.kieu === 'dam' ? 'dam' : r.kieu === 'phu' || r.kieu === 'ty_le' ? 'mo' : '' }, r.nhan), xuat: (r) => r.nhan },
      ...ds.map((d, i) => ({ nhan: h('span', { class: 'cot-thang' }, nhanThang(d), h('br'), theTT(d)), so: true, lay: (r) => giaTriO(r, d, ds[i - 1]), xuat: (r) => xuatO(r, d, ds[i - 1]) })),
      { nhan: h('span', { class: 'cot-thang' }, `Lũy kế ${nam}`, h('br'), h('small', { class: 'mo' }, `${ds.length} tháng`)), so: true,
        lay: (r) => (r.khoa === 'tang_dt' ? '' : giaTriO(r, { ...tong, so_xe: tong.so_xe }, null)), xuat: (r) => (r.khoa === 'tang_dt' ? '' : xuatO(r, tong, null)) }];
    const chonNam = cacNam.length > 1 ? h('select', { 'aria-label': 'Năm', onchange: (e) => { nhoPhien.ghi('kqkd_nam', e.target.value); ve(); } },
      cacNam.map((n) => h('option', { value: n, selected: n === nam }, `Năm ${n}`))) : null;

    // ----- Khóa sổ từng tháng -----
    const dongThang = (d) => {
      const thieu = d.thieu_dinh_ky || [];
      const nutLap = (ten) => h('a', { class: 'nut nho', href: `#/de-nghi?lap=1&muc=${encodeURIComponent(ten)}&ky=${String(d.thang).slice(0, 10)}` }, `+ ${ten}`);
      return h('div', { class: `dong-thang ${d.trang_thai}` },
        h('div', { class: 'dong-thang-dau' }, h('b', null, `Tháng ${nhanThang(d)}`), h('small', null, ` kỳ 01/${nhanThang(d)} – ${ngay(d.ngay_cuoi)}`), theTT(d),
          d.da_chot ? h('small', null, ` · chốt lúc ${ngayGio(d.chot_luc)}`) : null),
        d.da_chot ? null : h('ul', { class: 'checklist' },
          h('li', { class: d.luong_da_nhap ? 'xong' : 'thieu' }, d.luong_da_nhap ? `✓ Lương tháng: ${tien(d.luong)} đ` : '✗ Chưa nhập bảng lương tháng',
            kt ? h('button', { class: 'nut nho', type: 'button', onclick: () => moLuong(d) }, d.luong_da_nhap ? 'Sửa lương' : 'Nhập lương') : null),
          h('li', { class: thieu.length ? 'thieu' : 'xong' }, thieu.length ? ['✗ Chi phí định kỳ chưa có: ', thieu.map((t) => nutLap(t))] : '✓ Chi phí định kỳ (điện, nước, mặt bằng…) đã có đủ'),
          h('li', { class: so(d.de_nghi_cho_chi) ? 'thieu' : 'xong' }, so(d.de_nghi_cho_chi) ? ['✗ ', h('a', { href: '#/de-nghi' }, `${d.de_nghi_cho_chi} đề nghị chi của kỳ chưa chi`)] : '✓ Không còn đề nghị chi chờ của kỳ')),
        h('div', { class: 'hang-nut' },
          gd && d.trang_thai === 'cho_chot' ? h('button', { class: 'nut nho chinh', type: 'button', 'data-chot': String(d.thang), onclick: async () => {
            if (!(await xacNhan(`Chốt tháng ${nhanThang(d)} (kỳ 01/${nhanThang(d)} – ${ngay(d.ngay_cuoi)})? Sau khi chốt không ghi hay sửa được phiếu, hồ sơ, chi phí của tháng này; cổ đông sẽ xem được số tổng.`, 'Chốt tháng'))) return;
            await chay((boQua) => api.chotThang(d.thang, boQua), { thanhCong: `Đã chốt tháng ${nhanThang(d)}.` }).then(ve, () => {});
          } }, 'Chốt tháng') : null,
          d.trang_thai === 'dang_mo' ? h('small', { class: 'mo' }, `Chốt được từ ngày ${ngay(new Date(new Date(d.ngay_cuoi).getTime() + 864e5).toISOString())}; tiền điện, lương của tháng nhập sau ngày đó vẫn tính vào tháng này (chọn "Chi phí của tháng" khi lập đề nghị chi).`) : null,
          gd && d.da_chot ? h('button', { class: 'nut nho', type: 'button', onclick: () => moMoLai(d) }, 'Mở lại') : null));
    };

    dat(ketQua,
      khoiSo,
      h('section', { class: 'the' }, bieuDo),
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, 'Kết quả kinh doanh theo tháng'),
          h('div', { class: 'hang-nut' }, chonNam, gd ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`ket-qua-kinh-doanh-${nam}.csv`, cot, DONG) }, 'Tải file CSV') : null)),
        ds.length ? bang(cot, DONG) : h('p', { class: 'trong' }, 'Chưa có số liệu.')),
      h('section', { class: 'the' },
        h('h2', null, 'Khóa sổ tháng'),
        h('p', { class: 'goi-y' }, 'Kỳ báo cáo khóa ở ngày cuối tháng. Các khoản nhập sau (tiền điện, lương…) chọn đúng tháng là vẫn tính vào tháng đó. Chốt xong thì không ghi, sửa gì vào tháng đó nữa; cổ đông chỉ xem tháng đã chốt.'),
        h('div', { class: 'ds-thang-kqkd' }, [...ds].reverse().map(dongThang))));

    function moLuong(d) {
      const form = h('form', null, truong(`Tổng lương tháng ${nhanThang(d)}`, oTien('tong', Number(d.luong) || null), 'Nhập một số tổng; phiếu chi trả lương chỉ là chi tiền, không tính hai lần.', { batBuoc: true }));
      moModal('Bảng lương tháng', form, { nhanNut: 'Lưu', nutChinh: async () => {
        const t = docForm(form).tong; if (t === null) { toast('Nhập số tiền.', 'loi'); return false; }
        await api.nhapBangLuong(d.thang, t); toast('Đã lưu lương tháng.'); await ve();
      } });
    }
    function moMoLai(d) {
      const form = h('form', null, truong('Lý do mở lại', oVung('ly_do', ''), 'Mở lại để sửa số liệu; sửa xong nhớ chốt lại.', { batBuoc: true }));
      moModal(`Mở lại tháng ${nhanThang(d)}`, form, { nhanNut: 'Mở lại', nutChinh: async () => {
        const l = docForm(form).ly_do; if (!l) { toast('Ghi lý do.', 'loi'); return false; }
        await api.moLaiThang(d.thang, l); toast('Đã mở lại tháng.'); await ve();
      } });
    }
  }
  await ve();
}
