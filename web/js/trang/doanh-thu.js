// Doanh thu, công nợ, kết quả kinh doanh
//  - Doanh thu: theo ngày duyệt giá (xe bảo hiểm) hoặc ngày khách đồng ý báo giá (khách lẻ), số gồm VAT.
//    Xem từ trước đến nay: máy chủ cộng sẵn theo tháng (042); chọn một tháng mới tải từng dòng.
//  - Công nợ: phải thu khách / hãng bảo hiểm theo hồ sơ, tuổi nợ, tiền khách trả trước / trả dư phải trả lại, nợ NCC, nội bộ.
//  - Kết quả kinh doanh: trang/kqkd.js.
import { h, bienSo, tien, ngay, homNay, cuoiThang, bang, taiTepCSV, NHOM_BAO_CAO, nhomBaoCao, nhanTrangThai, dat, nhoPhien, thanhThe } from '../ui.js';
import * as api from '../api.js';
import { veKqkd, nhanThang } from './kqkd.js';

const NGUON = { bao_hiem: 'Bảo hiểm trả', khach: 'Khách trả', dich_vu_nhanh: 'Dịch vụ nhanh', giam_gia: 'Giảm giá cho khách' };
const so = (v) => Number(v) || 0;
const tienO = (v) => (so(v) ? tien(v) : '–');                 // ô số trong bảng: 0 hiện "–"

export default async function trangDoanhThu(el) {
  let the = nhoPhien.doc('dt_the') || 'doanh_thu';
  let thang = '';                                             // '' = từ trước đến nay
  const oThang = h('input', { type: 'month', value: '', 'aria-label': 'Lọc theo tháng', max: homNay().slice(0, 7) });
  const nutTatCa = h('button', { class: 'nut nho', type: 'button', hidden: true, onclick: () => { thang = ''; oThang.value = ''; ve(); } }, 'Tất cả');
  const khungLoc = h('div', { class: 'hang-nut' }, h('span', { class: 'mo-ta' }, 'Lọc theo tháng:'), oThang, nutTatCa);
  const ketQua = h('div');
  oThang.addEventListener('change', () => { thang = oThang.value; ve(); });
  const tabs = thanhThe([['doanh_thu', 'Doanh thu'], ['cong_no', 'Công nợ'], ['kqkd', 'Kết quả kinh doanh']], the,
    (ma) => { the = ma; nhoPhien.ghi('dt_the', ma); ve(); }, { nhan: 'Doanh thu, công nợ, kết quả kinh doanh' });
  const moTa = h('p', { class: 'mo-ta' });
  dat(el,
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Doanh thu & công nợ'), khungLoc),
    h('div', { class: 'thanh-loc' }, tabs), moTa, ketQua);

  // Mỗi lần vẽ một số thứ tự: đổi thẻ / tháng nhanh thì lần tải cũ xong muộn không đè lên lần mới
  // giu = vẽ lại tại chỗ sau một thao tác (chốt tháng, nhập lương…): giữ nội dung cũ đến khi có số mới, giữ vị trí cuộn
  let lanVe = 0;
  async function ve({ giu = false } = {}) {
    const lan = ++lanVe; const conMoi = () => lan === lanVe;
    const cuon = window.scrollY;
    if (!giu) dat(ketQua, h('div', { class: 'dang-tai', role: 'status' }, 'Đang tải…'));
    else { ketQua.classList.add('dang-cap-nhat'); ketQua.setAttribute('aria-busy', 'true'); }
    khungLoc.hidden = the !== 'doanh_thu';
    nutTatCa.hidden = !thang;
    try {
      if (the === 'doanh_thu') {
        moTa.textContent = (thang ? `Doanh thu tháng ${thang.slice(5, 7)}/${thang.slice(0, 4)}` : 'Doanh thu từ trước đến nay')
          + ' – ghi vào ngày duyệt giá (xe bảo hiểm) hoặc ngày khách đồng ý báo giá (khách lẻ), số gồm VAT. Không gồm xe bảo hành và hồ sơ chuyển từ Excel.';
        await veDoanhThu(conMoi);
      } else if (the === 'kqkd') {
        moTa.textContent = 'Báo cáo lãi lỗ từng tháng: doanh thu − giá vốn = lãi gộp; − lương, hoa hồng GDV, chi phí vận hành, cố định + thu nhập khác = lãi trước thuế; '
          + 'bỏ VAT ra để có lãi không gồm VAT. Giám đốc chốt tháng để khóa sổ (Báo cáo cổ đông chỉ tính tháng đã chốt).';
        await veKqkd(ketQua, { veLai: () => ve({ giu: true }), conMoi });
      } else {
        moTa.textContent = 'Công nợ tính đến hôm nay theo giá đã duyệt: xe đã giao lẫn xe còn trong xưởng, khách hoặc hãng bảo hiểm chưa trả đủ (gồm nợ cũ chuyển từ Excel); '
          + 'tiền khách trả trước, trả dư cần trả lại; nợ nhà cung cấp, nội bộ.';
        await veCongNo(conMoi);
      }
      if (giu && conMoi()) window.scrollTo(0, cuon);
    } catch (e) {
      if (!conMoi()) return;
      dat(ketQua, h('div', { class: 'the' }, h('p', { class: 'chu-loi' }, `Không tải được số liệu: ${e.message}`),
        h('button', { class: 'nut', type: 'button', onclick: () => ve() }, 'Tải lại')));
    } finally {
      if (conMoi()) { ketQua.classList.remove('dang-cap-nhat'); ketQua.removeAttribute('aria-busy'); }
    }
  }

  // ---------------- Doanh thu ----------------
  async function veDoanhThu(conMoi) {
    const nutCSV = (ten, cot, ds) => (api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(ten, cot, ds) }, 'Tải file CSV') : null);
    const oDem = (b, nhan, lop = null) => h('div', { class: 'o-dem' }, h('b', { class: lop }, tien(b) || '0'), h('span', null, nhan));
    if (!thang) {
      // 042: máy chủ cộng theo tháng – không tải từng dòng doanh thu về máy
      const dsThang = (await api.doanhThuTheoThang()).slice().sort((a, b) => (a.thang < b.thang ? 1 : -1));
      if (!conMoi()) return;
      const tong = (k) => dsThang.reduce((s, d) => s + so(d[k]), 0);
      const cotThang = [
        { nhan: 'Tháng', lay: (d) => h('a', { href: '#', onclick: (e) => { e.preventDefault(); thang = String(d.thang).slice(0, 7); oThang.value = thang; ve(); } }, nhanThang(d.thang)), xuat: (d) => String(d.thang).slice(0, 7) },
        { nhan: 'Xe có doanh thu', so: true, lay: (d) => so(d.so_xe), xuat: (d) => so(d.so_xe) },
        { nhan: 'Lượt DVN', so: true, lay: (d) => so(d.so_luot_dvn), xuat: (d) => so(d.so_luot_dvn) },
        { nhan: 'Bảo hiểm', so: true, lay: (d) => tienO(d.bao_hiem), xuat: (d) => so(d.bao_hiem) },
        { nhan: 'Khách', so: true, lay: (d) => tienO(d.khach), xuat: (d) => so(d.khach) },
        { nhan: 'Dịch vụ nhanh', so: true, lay: (d) => tienO(d.dich_vu_nhanh), xuat: (d) => so(d.dich_vu_nhanh) },
        { nhan: 'Giảm giá', so: true, lay: (d) => tienO(d.giam_gia), xuat: (d) => so(d.giam_gia) },
        { nhan: 'Tổng', so: true, lay: (d) => h('b', null, tien(d.tong) || '0'), xuat: (d) => so(d.tong) },
        { nhan: 'VAT trong đó', so: true, lay: (d) => h('span', { class: 'mo' }, tienO(d.vat_ra)), xuat: (d) => so(d.vat_ra) },
      ];
      dat(ketQua,
        h('section', { class: 'luoi-dem tien' },
          oDem(tong('tong'), 'Tổng doanh thu từ trước đến nay (gồm VAT)'),
          Object.entries(NGUON).map(([k, nhan]) => oDem(tong(k), nhan)),
          oDem(tong('vat_ra'), 'VAT đầu ra trong số trên')),
        h('section', { class: 'luoi-dem tien' }, Object.entries(NHOM_BAO_CAO).map(([k, nhan]) => oDem(tong(k), nhan))),
        h('section', { class: 'the' },
          h('div', { class: 'the-dau' }, h('h2', null, 'Theo tháng'), nutCSV('doanh-thu-theo-thang.csv', cotThang, dsThang)),
          h('p', { class: 'goi-y' }, 'Bấm vào tháng để xem từng xe, từng ngày của tháng đó.'),
          bang(cotThang, dsThang, { trong: 'Chưa có doanh thu.' })));
      return;
    }
    const den = cuoiThang(thang);   // 038: toISOString() lùi 1 ngày theo UTC → mất ngày cuối tháng
    const rows = await api.doc('v_doanh_thu', (q) => q.gte('ngay', `${thang}-01`).lte('ngay', den).order('ngay').order('ma').limit(5000));
    if (!conMoi()) return;
    const tong = (loc) => rows.filter(loc).reduce((s, r) => s + so(r.so_tien), 0);
    const tongVat = rows.reduce((s, r) => s + so(r.vat_ra), 0);
    // Gộp theo ngày + hồ sơ (giảm giá cùng ngày gộp vào xe); mỗi lượt dịch vụ nhanh một dòng
    const theoXe = new Map();
    rows.forEach((r, i) => {
      const k = r.ho_so_id ? `${r.ngay}|${r.ho_so_id}` : `dvn|${i}`;
      const g = theoXe.get(k) || { ngay: r.ngay, ma: r.ma, ho_so_id: r.ho_so_id, bien_so: r.bien_so, bao_hiem: 0, khach: 0, dich_vu_nhanh: 0, giam_gia: 0,
        dong_son: 0, phu_tung: 0, dmg: 0, detailing: 0, tong: 0 };
      if (!g.bien_so && r.bien_so) g.bien_so = r.bien_so;
      g[r.nguon] += so(r.so_tien);
      if (r.nhom && r.nguon !== 'giam_gia') g[nhomBaoCao(r.nhom)] += so(r.so_tien);
      g.tong += so(r.so_tien);
      theoXe.set(k, g);
    });
    const ds = [...theoXe.values()];
    const cot = [
      { nhan: 'Ngày', lay: (d) => ngay(d.ngay), xuat: (d) => ngay(d.ngay) },
      { nhan: 'Biển số', lay: (d) => (d.ho_so_id ? h('a', { href: `#/ho-so/${d.ho_so_id}`, class: 'lien-ket-xe' }, bienSo(d.bien_so, { maThay: d.ma })) : (d.bien_so || 'Dịch vụ nhanh')), xuat: (d) => d.bien_so || d.ma || '' },
      { nhan: 'Bảo hiểm', so: true, lay: (d) => tienO(d.bao_hiem), xuat: (d) => d.bao_hiem },
      { nhan: 'Khách', so: true, lay: (d) => tienO(d.khach + d.dich_vu_nhanh + d.giam_gia), xuat: (d) => d.khach + d.dich_vu_nhanh + d.giam_gia },
      { nhan: 'Đồng sơn', so: true, lay: (d) => tienO(d.dong_son), xuat: (d) => d.dong_son },
      { nhan: 'Phụ tùng', so: true, lay: (d) => tienO(d.phu_tung), xuat: (d) => d.phu_tung },
      { nhan: 'ĐMG', so: true, lay: (d) => tienO(d.dmg), xuat: (d) => d.dmg },
      { nhan: 'Detailing', so: true, lay: (d) => tienO(d.detailing), xuat: (d) => d.detailing },
      { nhan: 'Tổng', so: true, lay: (d) => h('b', null, tien(d.tong)), xuat: (d) => d.tong },
    ];
    dat(ketQua,
      h('section', { class: 'luoi-dem tien' },
        oDem(tong(() => true), 'Tổng doanh thu tháng (gồm VAT)'),
        Object.entries(NGUON).map(([k, nhan]) => oDem(tong((r) => r.nguon === k), nhan)),
        oDem(tongVat, 'VAT đầu ra trong số trên')),
      h('section', { class: 'luoi-dem tien' }, Object.entries(NHOM_BAO_CAO).map(([k, nhan]) =>
        oDem(tong((r) => nhomBaoCao(r.nhom) === k && r.nguon !== 'giam_gia'), nhan))),
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, `Theo ngày (${ds.length} dòng)`), nutCSV(`doanh-thu-${thang}.csv`, cot, ds)),
        bang(cot, ds, { trong: 'Tháng này chưa có doanh thu.' })));
  }

  // ---------------- Công nợ ----------------
  async function veCongNo(conMoi) {
    const homNayMs = Date.now();
    const soNgay = (d) => (d ? Math.max(0, Math.floor((homNayMs - new Date(d).getTime()) / 864e5)) : null);
    const xemTien = api.duocXem('giam_doc', 'ke_toan', 'quan_ly');
    const [tatCaHs, ncc, noiBoTatCa] = await Promise.all([
      // Còn nợ (khách, bảo hiểm) và khách trả trước / trả dư (cả hồ sơ đã hủy còn giữ cọc) – một lần đọc
      api.doc('v_ho_so', (q) => q.or('con_no_khach.gt.0,con_no_bh.gt.0,con_no_khach.lt.0').order('giao_luc', { ascending: true, nullsFirst: false }).order('ngay_vao')),
      xemTien ? api.doc('v_cong_no_ncc').catch(() => []) : [],
      xemTien ? api.doc('v_cong_no_noi_bo', (q) => q.order('ten')).catch(() => []) : [],
    ]);
    if (!conMoi()) return;
    const hs = tatCaHs.filter((x) => x.trang_thai !== 'huy' && (so(x.con_no_khach) > 0 || so(x.con_no_bh) > 0));
    const traTruoc = tatCaHs.filter((x) => so(x.con_no_khach) < 0);
    // Phải trả lại ngay: xe đã giao / hồ sơ đã hủy, đóng mà khách còn dư tiền; xe đang làm thì cọc trừ khi giao xe
    const phaiTraLai = traTruoc.filter((x) => x.giao_luc || ['huy', 'dong'].includes(x.trang_thai));
    const tongTraLai = phaiTraLai.reduce((s, x) => s - so(x.con_no_khach), 0);
    const tongCoc = traTruoc.filter((x) => !phaiTraLai.includes(x)).reduce((s, x) => s - so(x.con_no_khach), 0);
    // Nội bộ & cá nhân (027): còn lại dương = họ nợ công ty, âm = công ty nợ họ (giám đốc, cổ đông cho công ty mượn)
    const noiBo = noiBoTatCa.map((r) => ({ ...r, con: so(r.con_lai) })).filter((r) => r.con !== 0 || so(r.da_chi) || so(r.da_thu) || r.hoat_dong !== false);
    const phaiThuNoiBo = noiBo.reduce((t, r) => t + (r.con > 0 ? r.con : 0), 0);
    const phaiTraNoiBo = noiBo.reduce((t, r) => t + (r.con < 0 ? -r.con : 0), 0);
    const chieuNo = (v) => (!v ? '—' : v < 0 ? h('span', { class: 'chu-loi' }, `Công ty nợ ${tien(-v)}`) : h('span', { class: 'chu-cam' }, `Nợ công ty ${tien(v)}`));
    const noKhach = hs.filter((x) => so(x.con_no_khach) > 0);
    const noBH = hs.filter((x) => so(x.con_no_bh) > 0);
    const chuaGiao = hs.filter((x) => !x.giao_luc && !x.tu_excel);
    const tongChuaGiao = chuaGiao.reduce((s, x) => s + Math.max(so(x.con_no_khach), 0) + so(x.con_no_bh), 0);
    const tongKhach = noKhach.reduce((s, x) => s + so(x.con_no_khach), 0);
    const tongBH = noBH.reduce((s, x) => s + so(x.con_no_bh), 0);
    const noNcc = ncc.map((r) => ({ ...r, con: so(r.da_nhap) - so(r.da_tra) })).filter((r) => r.con > 0);
    const tongNcc = noNcc.reduce((s, r) => s + r.con, 0);
    const choKhopNcc = ncc.reduce((s, r) => s + so(r.cho_khop), 0);

    // Tuổi nợ: khách tính từ ngày giao xe; bảo hiểm từ ngày gửi hồ sơ (chưa gửi thì từ ngày giao xe)
    const KHOANG = [['chua_giao', 'Xe chưa giao'], ['d30', '0–30 ngày'], ['d60', '31–60 ngày'], ['d90', '61–90 ngày'], ['tren90', 'Trên 90 ngày'], ['cu', 'Nợ cũ (Excel)']];
    const tuoi = (x, bh) => {
      const moc = bh ? (x.gui_hs_ngay || x.giao_luc) : x.giao_luc;
      if (!moc) return x.tu_excel ? 'cu' : 'chua_giao';
      const n = soNgay(moc);
      return n <= 30 ? 'd30' : n <= 60 ? 'd60' : n <= 90 ? 'd90' : 'tren90';
    };
    const nhomNo = (ten, dsHs, bh) => {
      const c = { ten, so: dsHs.length, tong: 0, bh, ...Object.fromEntries(KHOANG.map(([k]) => [k, 0])) };
      for (const x of dsHs) { const v = so(bh ? x.con_no_bh : x.con_no_khach); c[tuoi(x, bh)] += v; c.tong += v; }
      return c;
    };
    const theoHang = new Map();
    for (const x of noBH) { const k = x.hang_bh || 'Chưa ghi hãng'; theoHang.set(k, [...(theoHang.get(k) || []), x]); }
    const dsBen = [...[...theoHang.entries()].map(([ten, ds]) => nhomNo(ten, ds, true)).sort((a, b) => b.tong - a.tong),
      nhomNo('Khách ngoài bảo hiểm', noKhach.filter((x) => x.nguon_tt === 'khach'), false),
      nhomNo('Khách của xe bảo hiểm (khấu trừ, phần tự trả)', noKhach.filter((x) => x.nguon_tt !== 'khach'), false)].filter((c) => c.so);
    const tongTuoi = Object.fromEntries(KHOANG.map(([k]) => [k, dsBen.reduce((s, c) => s + c[k], 0)]));
    const quaHan = tongTuoi.d90 + tongTuoi.tren90;
    const khoangHien = KHOANG.filter(([k]) => k !== 'cu' || tongTuoi.cu);

    let loc = 'tat';
    const kq = h('div');
    const tabsCon = thanhThe([['tat', `Tất cả (${hs.length})`], ['khach', `Khách nợ (${noKhach.length})`], ['bao_hiem', `Bảo hiểm nợ (${noBH.length})`],
      ['chua_giao', `Xe chưa giao (${chuaGiao.length})`], ['tra_lai', `Trả trước, trả dư (${traTruoc.length})`]], loc, (ma) => { loc = ma; veBang(); }, { nho: true, nhan: 'Lọc hồ sơ còn nợ' });
    const cot = [
      { nhan: 'Biển số', lay: (x) => h('a', { href: `#/ho-so/${x.id}`, class: 'lien-ket-xe' }, bienSo(x.bien_so_hien_thi, { maThay: x.ma })), xuat: (x) => x.bien_so_hien_thi || x.ma },
      { nhan: 'Khách', lay: (x) => h('span', null, x.ten_khach, h('br'), h('small', null, x.dien_thoai || '')), xuat: (x) => x.ten_khach },
      { nhan: 'Nguồn', lay: (x) => (x.nguon_tt === 'khach' ? 'Ngoài BH' : x.hang_bh || 'Bảo hiểm'), xuat: (x) => (x.nguon_tt === 'khach' ? 'Ngoài BH' : x.hang_bh || 'Bảo hiểm') },
      { nhan: 'Giao xe', lay: (x) => (x.giao_luc ? h('span', null, ngay(x.giao_luc), h('br'), h('small', null, `${soNgay(x.giao_luc)} ngày`)) : (x.tu_excel ? 'Nợ cũ (Excel)' : h('span', { class: 'chu-cam' }, 'Chưa giao'))), xuat: (x) => (x.giao_luc ? ngay(x.giao_luc) : x.tu_excel ? 'Nợ cũ' : 'Chưa giao') },
      { nhan: 'Gửi hồ sơ BH', lay: (x) => (x.nguon_tt === 'khach' ? '' : x.gui_hs_ngay ? h('span', null, ngay(x.gui_hs_ngay), h('br'), h('small', null, `${soNgay(x.gui_hs_ngay)} ngày`)) : h('span', { class: 'chu-loi' }, 'Chưa gửi')), xuat: (x) => (x.gui_hs_ngay ? ngay(x.gui_hs_ngay) : '') },
      { nhan: 'Khách còn nợ', so: true, lay: (x) => h('b', { class: so(x.con_no_khach) > 0 ? 'chu-loi' : null }, so(x.con_no_khach) > 0 ? tien(x.con_no_khach) : '0'), xuat: (x) => Math.max(so(x.con_no_khach), 0) },
      { nhan: 'BH còn nợ', so: true, lay: (x) => (x.nguon_tt === 'khach' ? '' : h('b', { class: so(x.con_no_bh) > 0 ? 'chu-cam' : null }, tien(x.con_no_bh) || '0')), xuat: (x) => (x.nguon_tt === 'khach' ? '' : so(x.con_no_bh)) },
      { nhan: 'Bước', lay: (x) => nhanTrangThai(x.trang_thai), xuat: (x) => x.trang_thai },
    ];
    const cotTraLai = [
      cot[0], cot[1],
      { nhan: 'Tình trạng', lay: (x) => (x.trang_thai === 'huy' ? h('span', { class: 'chu-loi' }, 'Đã hủy – trả lại cọc') : x.giao_luc || x.trang_thai === 'dong' ? h('span', { class: 'chu-cam' }, 'Đã giao – khách trả dư') : 'Đang làm – cọc trừ khi giao xe'),
        xuat: (x) => (x.trang_thai === 'huy' ? 'Đã hủy' : x.giao_luc || x.trang_thai === 'dong' ? 'Trả dư' : 'Cọc xe đang làm') },
      { nhan: 'Khách đã trả', so: true, lay: (x) => tien(x.da_thu_khach) || '0', xuat: (x) => so(x.da_thu_khach) },
      { nhan: 'Khách phải trả', so: true, lay: (x) => tien(x.phai_thu_khach) || '0', xuat: (x) => so(x.phai_thu_khach) },
      { nhan: 'Đang giữ của khách', so: true, lay: (x) => h('b', { class: 'chu-cam' }, tien(-so(x.con_no_khach))), xuat: (x) => -so(x.con_no_khach) },
      { nhan: '', lay: (x) => ((x.giao_luc || ['huy', 'dong'].includes(x.trang_thai)) && api.laNhanVien()
        ? h('a', { class: 'nut nho', 'data-tra-coc': '', href: `#/de-nghi?lap=1&muc=${encodeURIComponent('Trả lại cọc cho khách')}&tien=${-so(x.con_no_khach)}&ho_so=${x.id}&nd=${encodeURIComponent(`Trả lại tiền ${x.trang_thai === 'huy' ? 'cọc' : 'dư'} – ${x.bien_so_hien_thi || x.ma}`)}&nhan=${encodeURIComponent(x.ten_khach || '')}` }, 'Đề nghị chi trả lại')
        : ''), xuat: () => '' },
    ];
    const dsLoc = () => (loc === 'khach' ? noKhach : loc === 'bao_hiem' ? noBH : loc === 'chua_giao' ? chuaGiao : loc === 'tra_lai' ? traTruoc : hs);
    const cotLoc = () => (loc === 'tra_lai' ? cotTraLai : cot);
    const veBang = () => {
      const ds = dsLoc();
      dat(kq, bang(cotLoc(), ds, { trong: loc === 'tra_lai' ? 'Không có khách nào đang trả trước, trả dư.' : 'Không có hồ sơ nào còn nợ.' }),
        !ds.length ? null : loc === 'tra_lai'
          ? h('p', { class: 'mo-ta' }, `${ds.length} hồ sơ · cần trả lại ${tien(tongTraLai) || '0'} đ`, tongCoc ? ` · cọc của xe đang làm ${tien(tongCoc)} đ (trừ vào tiền khách trả khi giao xe)` : '')
          : h('p', { class: 'mo-ta' }, `${ds.length} hồ sơ · Khách còn nợ ${tien(ds.reduce((s, x) => s + Math.max(so(x.con_no_khach), 0), 0))} đ · Bảo hiểm còn nợ ${tien(ds.reduce((s, x) => s + so(x.con_no_bh), 0))} đ`));
    };
    const oTuoi = (v, k) => (!v ? h('span', { class: 'mo' }, '–') : h('span', { class: k === 'd90' || k === 'tren90' ? 'chu-loi' : k === 'chua_giao' ? 'mo' : null }, tien(v)));
    dat(ketQua,
      h('section', { class: 'luoi-dem tien' },
        h('div', { class: 'o-dem', 'data-no-khach': '' }, h('b', { class: tongKhach > 0 ? 'chu-loi' : null }, tien(tongKhach) || '0'), h('span', null, `Khách hàng còn nợ · ${noKhach.length} xe`)),
        h('div', { class: 'o-dem', 'data-no-bh': '' }, h('b', { class: tongBH > 0 ? 'chu-cam' : null }, tien(tongBH) || '0'), h('span', null, `Hãng bảo hiểm còn nợ · ${noBH.length} hồ sơ`)),
        h('div', { class: 'o-dem' }, h('b', null, tien(tongKhach + tongBH) || '0'), h('span', null, `Tổng phải thu · trong đó xe chưa giao ${tien(tongChuaGiao) || '0'} đ`)),
        h('div', { class: 'o-dem', 'data-qua-han': '' }, h('b', { class: quaHan > 0 ? 'chu-loi' : null }, tien(quaHan) || '0'), h('span', null, 'Nợ quá 60 ngày (từ giao xe / gửi hồ sơ BH)')),
        traTruoc.length ? h('div', { class: 'o-dem', 'data-tra-lai': '' }, h('b', { class: tongTraLai > 0 ? 'chu-cam' : null }, tien(tongTraLai) || '0'),
          h('span', null, `Phải trả lại khách (trả dư, cọc hồ sơ hủy) · ${phaiTraLai.length} hồ sơ`), tongCoc ? h('small', { class: 'o-dem-phu' }, `Cọc của xe đang làm: ${tien(tongCoc)} đ`) : null) : null,
        ncc.length ? h('a', { class: 'o-dem', href: '#/kho?the=cong_no' }, h('b', null, tien(tongNcc) || '0'), h('span', null, `Nợ nhà cung cấp (phải trả) · ${noNcc.length} NCC`),
          choKhopNcc ? h('small', { class: 'o-dem-phu' }, `+ ${tien(choKhopNcc)} đ hàng đã nhập chờ khớp hóa đơn`) : null) : null,
        noiBo.length ? h('div', { class: 'o-dem', 'data-noi-bo-thu': '' }, h('b', { class: phaiThuNoiBo > 0 ? 'chu-cam' : null }, tien(phaiThuNoiBo) || '0'), h('span', null, 'Nội bộ, cá nhân nợ công ty (phải thu)')) : null,
        noiBo.length ? h('div', { class: 'o-dem', 'data-noi-bo-tra': '' }, h('b', { class: phaiTraNoiBo > 0 ? 'chu-loi' : null }, tien(phaiTraNoiBo) || '0'), h('span', null, 'Công ty nợ nội bộ, cá nhân (phải trả)')) : null),
      dsBen.length ? h('section', { class: 'the', 'data-tuoi-no': '' }, h('h2', null, 'Tuổi nợ theo bên nợ'),
        h('p', { class: 'goi-y' }, 'Khách: tính từ ngày giao xe. Bảo hiểm: từ ngày gửi hồ sơ (chưa gửi thì từ ngày giao xe). Nợ trên 60 ngày tô đỏ – cần nhắc trả hoặc kiểm lại hồ sơ.'),
        bang([
          { nhan: 'Bên nợ', lay: (c) => h('b', null, c.ten), xuat: (c) => c.ten },
          { nhan: 'Số hồ sơ', so: true, lay: (c) => c.so, xuat: (c) => c.so },
          ...khoangHien.map(([k, nhan]) => ({ nhan, so: true, lay: (c) => oTuoi(c[k], k), xuat: (c) => c[k] })),
          { nhan: 'Còn nợ', so: true, lay: (c) => h('b', { class: c.la_tong ? null : c.bh ? 'chu-cam' : 'chu-loi' }, tien(c.tong)), xuat: (c) => c.tong },
        ], [...dsBen, { ten: 'Cộng', so: dsBen.reduce((s, c) => s + c.so, 0), tong: dsBen.reduce((s, c) => s + c.tong, 0), ...tongTuoi, la_tong: true }], { gon: true })) : null,
      noiBo.length ? h('section', { class: 'the', 'data-khoi-noi-bo': '' }, h('h2', null, 'Nội bộ & cá nhân'),
        h('p', { class: 'goi-y' }, 'Tiền vay mượn với công ty cùng hệ thống, giám đốc, cổ đông – không vào lãi lỗ. Ghi bằng Phiếu thu (mục "Công ty mượn tiền…", "…trả tiền mượn") và Đề nghị chi (mục "Cho cổ đông / cá nhân mượn", "Trả tiền mượn…"); giám đốc chi hộ thì chọn "Chi hộ bởi" lúc chi tiền. Nợ đầu kỳ sửa ở Danh mục → Đơn vị liên quan & cá nhân.'),
        bang([
          { nhan: 'Đơn vị / cá nhân', lay: (r) => h('span', null, h('b', null, r.ten), h('br'), h('small', null, r.loai === 'ca_nhan' ? 'Cá nhân' : 'Công ty cùng hệ thống')) },
          { nhan: 'Nợ đầu kỳ', so: true, lay: (r) => chieuNo(so(r.so_du_dau_ky)) },
          { nhan: 'Đã chi cho họ', so: true, lay: (r) => tien(r.da_chi) || '0' },
          { nhan: 'Đã thu từ họ', so: true, lay: (r) => tien(r.da_thu) || '0' },
          { nhan: 'Còn lại', so: true, lay: (r) => h('b', null, chieuNo(r.con)) },
          { nhan: 'Giao dịch gần nhất', so: true, lay: (r) => (r.ngay_cuoi ? ngay(r.ngay_cuoi) : '') },
        ], noiBo)) : null,
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('h2', null, 'Hồ sơ còn nợ'),
          api.coVaiTro('giam_doc') ? h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`cong-no_${loc}_${homNay()}.csv`, cotLoc(), dsLoc()) }, 'Tải file CSV') : null),
        tabsCon, kq));
    veBang();
  }
  await ve();
}
