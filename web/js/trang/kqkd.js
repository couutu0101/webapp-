// Kết quả kinh doanh – báo cáo lãi lỗ quản trị theo tháng (042)
//  • Số gồm VAT như sổ của gara. Phần V bỏ VAT ra để có lãi không gồm VAT (ước tính, trước thuế TNDN);
//    phần VI ước VAT phải nộp của tháng. Tháng đã chốt hiện số lúc chốt; số hiện tại khác thì báo "Lệch".
//  • Bấm vào số của một tháng để xem từng hồ sơ / phiếu tạo nên số đó.
//  • Lũy kế năm, cùng kỳ năm trước, ± so cùng kỳ; xem theo số tiền hoặc % trên doanh thu.
//  • Tiền – công nợ – tồn kho cuối tháng, lãi gộp theo tổ, chi phí theo mục, khóa sổ lần lượt, in khổ ngang, xuất Excel.
import { h, tien, ngay, ngayGio, dat, moModal, oTien, truong, docForm, toast, xacNhan, chay, hoiLyDo, bang, nhoPhien, homNay } from '../ui.js';
import * as api from '../api.js';
import { bieuDoDuong, soGon } from '../bieu-do.js';
import { TEN_GARA } from '../cau-hinh.js';

const so = (v) => Number(v) || 0;
export const nhanThang = (thang) => `${String(thang).slice(5, 7)}/${String(thang).slice(0, 4)}`;
// Lùi n tháng (n âm = tiến): ('2026-01-01', 1) → '2025-12-01'
export function thangLui(thang, n) {
  const [y, m] = String(thang).slice(0, 7).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1 - n, 1)).toISOString().slice(0, 10);
}
const phanTram = (x, le = 1) => (x === null || x === undefined || !Number.isFinite(x) ? '—'
  : `${x < 0 ? '−' : ''}${Math.abs(x * 100).toLocaleString('vi-VN', { maximumFractionDigits: le })}%`);
const tienO = (v) => (so(v) ? tien(v) : '–');                 // ô số: 0 hiện "–"
const tangTruong = (a, b) => (b === null || b === undefined || !so(b) ? null : (so(a) - so(b)) / Math.abs(so(b)));
// ▲▼ có màu: tot = true (tăng là tốt) / false (tăng là xấu) / null (không tô màu); diem: chênh lệch tỷ suất (điểm %)
export function oTang(tt, { tot = true, diem = false } = {}) {
  if (tt === null || tt === undefined || !Number.isFinite(tt)) return h('span', { class: 'mo' }, '—');
  const len = tt > 0; const xuong = tt < 0;
  const lop = tot === null || (!len && !xuong) ? '' : (tot ? len : xuong) ? 'tot' : 'xau';
  const chu = `${Math.abs(tt * 100).toLocaleString('vi-VN', { maximumFractionDigits: 1 })}${diem ? ' điểm' : '%'}`;
  return h('span', { class: `tang-truong ${lop}` }, `${len ? '▲' : xuong ? '▼' : '='} ${chu}`);
}
// So hai số: cả hai không âm (nền dương) → %; nền âm / bằng 0 hoặc số mới âm → chênh lệch tuyệt đối (▼ 29,3 tr),
// tránh kiểu "▼ 19.520%" khi so lãi âm với lãi gần 0
export function oChenh(a, b, { tot = true } = {}) {
  if (b === null || b === undefined || a === null || a === undefined) return h('span', { class: 'mo' }, '—');
  const x = so(a); const y = so(b);
  if (y > 0 && x >= 0) return oTang((x - y) / y, { tot });
  if (x === y) return h('span', { class: 'tang-truong' }, '= 0');
  const len = x > y; const lop = tot === null ? '' : (tot ? len : !len) ? 'tot' : 'xau';
  return h('span', { class: `tang-truong ${lop}` }, `${len ? '▲' : '▼'} ${soGon(Math.abs(x - y))}`);
}
// Số tiền theo đơn vị (bản in: nghìn / triệu đồng)
const soTien = (x, donVi = 1) => {
  if (donVi === 1) return tien(x);
  const v = x / donVi; const le = donVi >= 1e6 ? 1 : 0;
  return `${v < 0 ? '−' : ''}${Math.abs(v).toLocaleString('vi-VN', { minimumFractionDigits: le, maximumFractionDigits: le })}`;
};
const TEN_DON_VI = { 1: 'đồng', 1000: 'nghìn đồng', 1000000: 'triệu đồng' };
export const NHAN_TT = { dang_mo: ['Đang mở', 'tt-mo'], cho_chot: ['Chờ chốt', 'tt-canh-bao'], da_chot: ['Đã chốt', 'tt-tot'] };
export function tenCongTy() {
  const cn = api.dm.ten ? api.dm.ten('chi_nhanh', api.toi?.chi_nhanh_id) : '';
  return /hoàng sơn/i.test(cn || '') ? cn : `${TEN_GARA}${cn ? ` – ${cn}` : ''}`;
}

// ---------------------------------------------------------------------
// Dòng báo cáo. k: cột số liệu của ket_qua_kinh_doanh; ct: mã "xem chi tiết" (chi_tiet_kqkd);
// dau: '−' khoản trừ, '+' khoản cộng (hiện dấu); kieu: tong (dòng cộng), ket_qua (lãi), ty_le (tu / doanh thu),
// dem (số lượng), chi_so; trung: không tô màu tăng giảm (VAT); xau: tăng là xấu.
// ---------------------------------------------------------------------
export const DONG = [
  { muc: 'I. DOANH THU (gồm VAT)' },
  { nhan: 'Bảo hiểm trả', k: 'doanh_thu_bh', ct: 'doanh_thu_bh' },
  { nhan: 'Khách trả', k: 'doanh_thu_khach', ct: 'doanh_thu_khach' },
  { nhan: 'Dịch vụ nhanh', k: 'doanh_thu_dvn', ct: 'doanh_thu_dvn' },
  { nhan: 'Giảm giá cho khách', k: 'giam_gia', ct: 'giam_gia' },
  { nhan: 'DOANH THU THUẦN', k: 'doanh_thu', kieu: 'tong' },
  { muc: 'II. GIÁ VỐN' },
  { nhan: 'Vật tư, phụ tùng xuất cho xe', k: 'gia_von_xe', dau: '−', ct: 'gia_von_xe' },
  { nhan: 'Vật tư dùng chung xưởng', k: 'gia_von_dung_chung', dau: '−', ct: 'gia_von_dung_chung' },
  { nhan: 'Hao hụt kiểm kê (thiếu − thừa)', k: 'hao_hut', dau: '−', ct: 'hao_hut' },
  { nhan: 'Chi phí nhóm giá vốn (sơn, thuê ngoài…)', k: 'chi_gia_von', dau: '−', ct: 'chi_gia_von' },
  { nhan: 'TỔNG GIÁ VỐN', k: 'tong_gia_von', dau: '−', kieu: 'tong' },
  { nhan: 'LÃI GỘP', k: 'lai_gop', kieu: 'ket_qua' },
  { nhan: 'Tỷ suất lãi gộp', tu: 'lai_gop', kieu: 'ty_le' },
  { muc: 'III. CHI PHÍ HOẠT ĐỘNG' },
  { nhan: 'Lương (bảng lương tháng)', k: 'luong', dau: '−', ct: 'luong' },
  { nhan: 'Hoa hồng GDV', k: 'hoa_hong', dau: '−', ct: 'hoa_hong' },
  { nhan: 'Chi phí vận hành', k: 'chi_van_hanh', dau: '−', ct: 'chi_van_hanh' },
  { nhan: 'Chi phí cố định (điện, mặt bằng…)', k: 'chi_co_dinh', dau: '−', ct: 'chi_co_dinh' },
  { nhan: 'TỔNG CHI PHÍ HOẠT ĐỘNG', k: 'tong_chi_phi', dau: '−', kieu: 'tong' },
  { muc: 'IV. THU NHẬP KHÁC' },
  { nhan: 'Trạm sạc, thu khác', goiY: 'mục thu có tích "Vào lãi lỗ"', k: 'thu_khac', dau: '+', ct: 'thu_khac' },
  { nhan: 'LÃI TRƯỚC THUẾ (số gồm VAT)', k: 'lai_truoc_thue', kieu: 'ket_qua' },
  { nhan: 'Tỷ suất lãi trước thuế', tu: 'lai_truoc_thue', kieu: 'ty_le' },
  { muc: 'V. BỎ VAT KHỎI LÃI (ước tính)' },
  { nhan: 'VAT đầu ra nằm trong doanh thu', k: 'vat_ra', dau: '−', ct: 'vat_ra', trung: true },
  { nhan: 'VAT nằm trong giá vốn vật tư đã xuất', k: 'vat_trong_gia_von', dau: '+', ct: 'vat_trong_gia_von', trung: true },
  { nhan: 'VAT nằm trong chi phí (hóa đơn đầu vào)', k: 'vat_vao_chi_phi', dau: '+', ct: 'vat_vao_chi_phi', trung: true },
  { nhan: 'LÃI KHÔNG GỒM VAT (trước thuế TNDN)', k: 'lai_sau_vat', kieu: 'ket_qua' },
  { nhan: 'Tỷ suất trên doanh thu chưa VAT', tu: 'lai_sau_vat', mau: 'chua_vat', kieu: 'ty_le' },
  { muc: 'VI. THUẾ GTGT CỦA THÁNG (ước tính)' },
  { nhan: 'VAT đầu ra', k: 'vat_ra', ct: 'vat_ra', trung: true },
  { nhan: 'VAT đầu vào – hóa đơn nhập hàng', k: 'vat_vao_hang', dau: '−', ct: 'vat_vao_hang', trung: true },
  { nhan: 'VAT đầu vào – hóa đơn chi phí', k: 'vat_vao_chi_phi', dau: '−', ct: 'vat_vao_chi_phi', trung: true },
  { nhan: 'VAT PHẢI NỘP', goiY: 'âm = còn được khấu trừ tháng sau', k: 'vat_phai_nop', kieu: 'tong', trung: true },
  { muc: 'CHỈ SỐ' },
  { nhan: 'Xe sửa chữa', goiY: 'tính ở tháng duyệt giá đầu tiên', k: 'so_xe', kieu: 'dem', ct: 'so_xe' },
  { nhan: 'Lượt dịch vụ nhanh', k: 'so_luot_dvn', kieu: 'dem', ct: 'doanh_thu_dvn' },
  { nhan: 'Doanh thu bình quân một xe sửa chữa', tinh: 'binh_quan_xe', kieu: 'chi_so' },
  { nhan: 'Chi phí hoạt động / doanh thu', tu: 'tong_chi_phi', kieu: 'ty_le', xau: true },
];
// Các cột số được cộng khi tính lũy kế / cùng kỳ
const KHOA_SO = [...new Set([...DONG.flatMap((r) => [r.k, r.tu]).filter(Boolean), 'doanh_thu', 'vat_ra', 'so_xe', 'doanh_thu_bh', 'doanh_thu_khach', 'giam_gia', 'lai_truoc_thue_song'])];
export const congThang = (dsThang) => Object.fromEntries(KHOA_SO.map((k) => [k, dsThang.reduce((t, d) => t + so(d[k]), 0)]));

const mauSo = (r, d) => (r.mau === 'chua_vat' ? so(d.doanh_thu) - so(d.vat_ra) : so(d.doanh_thu));
const laTyLe = (r, pt) => r.kieu === 'ty_le' || (pt && !['dem', 'chi_so'].includes(r.kieu));
// Giá trị một dòng của một cột (pt: xem theo % trên doanh thu)
export function giaTri(r, d, pt = false) {
  if (!d || r.muc) return null;
  if (r.kieu === 'ty_le') { const m = mauSo(r, d); return m ? so(d[r.tu]) / Math.abs(m) : null; }
  if (r.tinh === 'binh_quan_xe') { const x = so(d.so_xe); return x ? (so(d.doanh_thu_bh) + so(d.doanh_thu_khach) + so(d.giam_gia)) / x : null; }
  const v = so(d[r.k]);
  if (pt && r.kieu !== 'dem') { const m = so(d.doanh_thu); return m ? v / Math.abs(m) : null; }
  return v;
}
// Chữ trong ô: khoản trừ hiện "− x", khoản cộng "+ x", số 0 hiện "–"
export function chuO(r, v, { pt = false, donVi = 1 } = {}) {
  if (v === null) return '—';
  const tyLe = laTyLe(r, pt);
  const fmt = (x) => (tyLe ? phanTram(x) : r.kieu === 'dem' ? x.toLocaleString('vi-VN') : soTien(r.kieu === 'chi_so' ? Math.round(x) : x, donVi));
  if (r.dau && r.kieu !== 'ty_le') {
    const e = r.dau === '−' ? -v : v;
    return e ? `${e < 0 ? '−' : '+'} ${fmt(Math.abs(e))}` : '–';
  }
  if (!v && r.kieu !== 'ty_le') return '–';
  return fmt(v);
}
const chieuTot = (r) => (r.trung ? null : !(r.dau === '−' || r.xau));
// Ô "± so cùng kỳ": tỷ suất so bằng điểm %, còn lại so bằng % (nền âm / 0: chênh lệch tuyệt đối)
function oSoSanh(r, a, b, pt) {
  const va = giaTri(r, a, pt); const vb = giaTri(r, b, pt);
  if (va === null || vb === null) return h('span', { class: 'mo' }, '—');
  if (laTyLe(r, pt)) return oTang(va - vb, { tot: chieuTot(r), diem: true });
  return oChenh(va, vb, { tot: chieuTot(r) });
}

// Bảng báo cáo dùng chung (P&L, số dư, phân tích): cột đầu là khoản mục (đứng yên khi cuộn ngang).
// dong: [{ loai: 'muc' | 'dong' | 'tong' | 'ket_qua' | 'ty_le' | 'dem', nhan, goiY, o: [nội dung ô…], am }]
export function bangBC(dau, dong, { lop = '' } = {}) {
  return h('div', { class: 'bang-cuon bc-cuon' }, h('table', { class: `bc-bang ${lop}` },
    h('thead', null, h('tr', null, dau.map((x, i) => h('th', { scope: 'col', class: i ? 'so' : 'bc-nhan' }, x)))),
    h('tbody', null, dong.map((r) => (r.loai === 'muc'
      ? h('tr', { class: 'bc-muc' }, h('th', { scope: 'rowgroup', class: 'bc-nhan' }, r.nhan), dau.length > 1 ? h('td', { colspan: dau.length - 1 }) : null)
      : h('tr', { class: `bc-${r.loai || 'dong'}${r.am ? ' bc-am' : ''}` },
        h('th', { scope: 'row', class: 'bc-nhan' }, r.nhan, r.goiY ? h('small', null, r.goiY) : null),
        r.o.map((x) => h('td', { class: 'so' }, x))))))));
}

// =====================================================================
// Trang: ketQua = vùng vẽ; veLai() vẽ lại cả thẻ; conMoi() = lần vẽ này còn là lần mới nhất
// =====================================================================
export async function veKqkd(ketQua, { veLai, conMoi = () => true }) {
  const tatCa = await api.ketQuaKinhDoanh();            // tăng dần theo tháng
  if (!conMoi()) return;
  const gd = api.coVaiTro('giam_doc'); const kt = api.coVaiTro('ke_toan', 'giam_doc');
  if (!tatCa.length) { dat(ketQua, h('p', { class: 'trong' }, 'Chưa có số liệu.')); return; }
  const namCua = (d) => String(d.thang).slice(0, 4);
  const cacNam = [...new Set(tatCa.map(namCua))].sort().reverse();
  let nam = nhoPhien.doc('kqkd_nam') || homNay().slice(0, 4);
  if (!cacNam.includes(nam)) nam = cacNam[0];
  const ds = tatCa.filter((d) => namCua(d) === nam);
  const theoThang = new Map(tatCa.map((d) => [String(d.thang), d]));
  const luyKe = congThang(ds);
  // Cùng kỳ: các tháng năm trước trùng tháng với các tháng đang xem
  const dsCungKy = ds.map((d) => theoThang.get(thangLui(d.thang, 12))).filter(Boolean);
  const cungKy = dsCungKy.length ? congThang(dsCungKy) : null;
  // Kỳ báo cáo chính: tháng đã qua gần nhất (tháng đang mở chỉ là tạm tính); chưa có thì lấy tháng đang mở
  const ky = [...ds].reverse().find((d) => d.trang_thai !== 'dang_mo') || ds[ds.length - 1];
  const kyTruoc = theoThang.get(thangLui(ky.thang, 1)); const kyNamTruoc = theoThang.get(thangLui(ky.thang, 12));
  const dangMo = ds.find((d) => d.trang_thai === 'dang_mo');
  const tamTinh = ky.trang_thai === 'dang_mo' ? ' (tạm tính)' : '';

  // ----- Tải song song: số chốt, lịch sử mở lại, phân tích theo tổ / theo mục, số dư cuối các tháng chưa có số chốt -----
  const cn = api.toi?.chi_nhanh_id;
  const tuNam = `${nam}-01-01`; const denNam = `${nam}-12-31`;
  const coSoDuChot = (d) => !!(d.da_chot && d._chot?.so_lieu?.so_du);
  const [chot, lichSu, dsTo, dsMuc] = await Promise.all([
    api.doc('chot_thang', (q) => q.eq('chi_nhanh_id', cn).gte('thang', tuNam).lte('thang', denNam)).catch(() => []),
    api.doc('chot_thang_lich_su', (q) => q.eq('chi_nhanh_id', cn).gte('thang', tuNam).lte('thang', denNam).order('mo_lai_luc', { ascending: false })).catch(() => []),
    api.laiGopTheoTo(tuNam, denNam).catch(() => null),
    api.chiPhiTheoMuc(thangLui(tuNam, 1), denNam).catch(() => null),
  ]);
  if (!conMoi()) return;
  const dsChot = new Map(chot.map((c) => [String(c.thang), c]));
  for (const d of ds) d._chot = dsChot.get(String(d.thang)) || null;
  // Số dư: tháng chốt có số lưu lúc chốt; còn lại tính tại ngày cuối tháng (tối đa 3 tháng gần nhất, đỡ nặng máy chủ)
  const canTinh = ds.filter((d) => !coSoDuChot(d)).slice(-3);
  const soDuSong = await Promise.all(canTinh.map((d) => api.soDuCuoiThang(d.thang).catch(() => null)));
  if (!conMoi()) return;
  const soDu = new Map();
  for (const d of ds) if (coSoDuChot(d)) soDu.set(String(d.thang), d._chot.so_lieu.so_du);
  canTinh.forEach((d, i) => { if (soDuSong[i]) soDu.set(String(d.thang), soDuSong[i]); });

  const lsTheoThang = new Map();
  for (const x of lichSu) { const k = String(x.thang); lsTheoThang.set(k, [...(lsTheoThang.get(k) || []), x]); }
  const tenNguoi = (id) => (api.dm.nhan_vien || []).find((x) => x.id === id)?.ho_ten || '';

  let pt = nhoPhien.doc('kqkd_pt') === '1';                // xem theo % trên doanh thu
  const theTT = (d) => h('span', { class: `nhan ${NHAN_TT[d.trang_thai][1]}`, title: d.da_chot ? `Chốt lúc ${ngayGio(d.chot_luc)}` : `Kỳ 01/${nhanThang(d.thang)} – ${ngay(d.ngay_cuoi)}` }, NHAN_TT[d.trang_thai][0]);
  const theLech = (d) => (d.lech_chot ? h('span', { class: 'nhan tt-lech', title: lyDoLech(d) }, 'Lệch') : null);
  const lyDoLech = (d) => (d._chot && !d._chot.so_lieu?.phien_ban
    ? 'Tháng chốt theo cách tính cũ (trước khi có báo cáo mới) – mở lại rồi chốt lại để lưu đủ các dòng mới.'
    : `Số hiện tại khác số lúc chốt: lãi trước thuế hiện tại ${tien(d.lai_truoc_thue_song)} đ, lúc chốt ${tien(d.lai_truoc_thue)} đ – mở lại tháng để kiểm tra rồi chốt lại.`);

  // ----- Thanh công cụ -----
  const chonNam = cacNam.length > 1 ? h('select', { class: 'chon-gon', 'aria-label': 'Năm báo cáo', onchange: (e) => { nhoPhien.ghi('kqkd_nam', e.target.value); veLai(); } },
    cacNam.map((n) => h('option', { value: n, selected: n === nam }, `Năm ${n}`))) : h('b', { class: 'bc-nam' }, `Năm ${nam}`);
  const oPt = h('input', { type: 'checkbox', checked: pt, onchange: (e) => { pt = e.target.checked; nhoPhien.ghi('kqkd_pt', pt ? '1' : '0'); veBang(); } });
  const congCu = h('div', { class: 'hang-nut bc-cong-cu' }, chonNam,
    h('label', { class: 'o-check' }, oPt, ' Xem theo % doanh thu'),
    h('button', { class: 'nut', type: 'button', onclick: moIn }, 'In báo cáo'),
    gd ? h('button', { class: 'nut', type: 'button', onclick: () => xuatExcel().catch((e) => toast(e.message, 'loi')) }, 'Tải Excel') : null);

  // ----- Ô số chính -----
  const ts = (k, d) => (so(d.doanh_thu) ? so(d[k]) / Math.abs(so(d.doanh_thu)) : null);
  const soSanhKy = (k) => [
    kyTruoc ? h('span', null, oChenh(ky[k], kyTruoc[k]), ` so ${nhanThang(kyTruoc.thang)}`) : null,
    kyNamTruoc ? h('span', null, ' · ', oChenh(ky[k], kyNamTruoc[k]), ` so ${nhanThang(kyNamTruoc.thang)}`) : null];
  const oKpi = (nhan, giaTriO, phu, { lop = '', mau = null } = {}) => h('div', { class: `o-dem ${lop}` }, h('b', { class: mau }, giaTriO), h('span', null, nhan),
    phu ? h('small', { class: 'o-dem-phu' }, phu) : null);
  const mauLai = (v) => (so(v) < 0 ? 'chu-loi' : 'chu-tot');
  const khoiKpi = h('section', { class: 'luoi-dem tien bc-kpi' },
    oKpi(`Doanh thu thuần tháng ${nhanThang(ky.thang)}${tamTinh}`, tien(ky.doanh_thu) || '0', soSanhKy('doanh_thu')),
    oKpi(`Lãi gộp tháng ${nhanThang(ky.thang)}`, tien(ky.lai_gop) || '0', [`Tỷ suất ${phanTram(ts('lai_gop', ky))} `, ...soSanhKy('lai_gop')], { mau: so(ky.lai_gop) < 0 ? 'chu-loi' : null }),
    oKpi(`Lãi trước thuế tháng ${nhanThang(ky.thang)}`, tien(ky.lai_truoc_thue) || '0', [`Tỷ suất ${phanTram(ts('lai_truoc_thue', ky))} `, ...soSanhKy('lai_truoc_thue')], { mau: mauLai(ky.lai_truoc_thue) }),
    oKpi(`Lãi không gồm VAT tháng ${nhanThang(ky.thang)}`, tien(ky.lai_sau_vat) || '0', `VAT phải nộp ước ${tien(ky.vat_phai_nop) || '0'} đ`, { mau: mauLai(ky.lai_sau_vat) }),
    oKpi(`Lãi trước thuế lũy kế năm ${nam}`, tien(luyKe.lai_truoc_thue) || '0',
      [`Doanh thu ${tien(luyKe.doanh_thu) || '0'} đ · ${ds.length} tháng`, cungKy ? h('span', null, ' · ', oChenh(luyKe.lai_truoc_thue, cungKy.lai_truoc_thue), ' so cùng kỳ') : null],
      { mau: mauLai(luyKe.lai_truoc_thue) }),
    dangMo && dangMo !== ky ? oKpi(`Tháng ${nhanThang(dangMo.thang)} đang mở – doanh thu đến hôm nay`, tien(dangMo.doanh_thu) || '0',
      `Lãi trước thuế tạm tính ${tien(dangMo.lai_truoc_thue) || '0'} đ`, { lop: 'bc-tam' }) : null);

  // ----- Biểu đồ (3 đường) -----
  const bieuDo = bieuDoDuong({
    tieuDe: `Doanh thu – Lãi gộp – Lãi trước thuế theo tháng, năm ${nam}`,
    phuDe: `Số liệu đến hết ngày ${ngay(ds[ds.length - 1].ngay_cuoi)}${ds[ds.length - 1].trang_thai === 'dang_mo' ? ' (tháng hiện tại chưa đủ, đang cập nhật)' : ''}. Rê chuột hoặc dùng phím ← → để xem từng tháng.`,
    nhan: ds.map((d) => nhanThang(d.thang)),
    chuoi: [{ ten: 'Doanh thu', giaTri: ds.map((d) => so(d.doanh_thu)) }, { ten: 'Lãi gộp', giaTri: ds.map((d) => so(d.lai_gop)) },
      { ten: 'Lãi trước thuế', giaTri: ds.map((d) => so(d.lai_truoc_thue)) }],
  });

  // ----- Bảng kết quả kinh doanh -----
  const cotBC = () => [
    ...ds.map((d) => ({ d, thang: String(d.thang), dau: h('span', { class: 'cot-thang' }, nhanThang(d.thang), h('br'), theTT(d), theLech(d)) })),
    { d: luyKe, dau: h('span', { class: 'cot-thang' }, `Lũy kế ${nam}`, h('br'), h('small', { class: 'mo' }, `${ds.length} tháng`)) },
    ...(cungKy ? [
      { d: cungKy, dau: h('span', { class: 'cot-thang', title: `Cộng ${dsCungKy.length} tháng cùng kỳ năm ${Number(nam) - 1}` }, `Cùng kỳ ${Number(nam) - 1}`, h('br'), h('small', { class: 'mo' }, `${dsCungKy.length} tháng`)) },
      { soSanh: true, dau: h('span', { class: 'cot-thang' }, '± so', h('br'), 'cùng kỳ') }] : []),
  ];
  const dongBC = ({ bam = true, donVi = 1 } = {}) => {
    const cot = cotBC();
    return { dau: ['Khoản mục', ...cot.map((c) => c.dau)], dong: DONG.map((r) => {
      if (r.muc) return { loai: 'muc', nhan: r.muc };
      const loai = r.kieu === 'tong' || r.kieu === 'ket_qua' || r.kieu === 'ty_le' ? r.kieu : r.kieu === 'dem' || r.kieu === 'chi_so' ? 'dem' : 'dong';
      return { loai, nhan: r.nhan, goiY: r.goiY, o: cot.map((c) => {
        if (c.soSanh) return oSoSanh(r, luyKe, cungKy, pt);
        const v = giaTri(r, c.d, pt);
        const chu = chuO(r, v, { pt, donVi });
        const am = r.kieu === 'ket_qua' && v !== null && v < 0;
        const nd = am ? h('span', { class: 'chu-loi' }, chu) : chu;
        return bam && c.thang && r.ct && v ? h('button', { class: 'bc-o', type: 'button', title: `Xem chi tiết ${r.nhan.toLowerCase()} tháng ${nhanThang(c.thang)}`, onclick: () => moChiTiet(r, c.d) }, nd) : nd;
      }) };
    }) };
  };
  const khungBang = h('div');
  // Nhiều tháng thì cuộn sẵn sang phải: tháng mới nhất, lũy kế, cùng kỳ nằm cạnh cột khoản mục
  const cuonCuoi = (khung) => requestAnimationFrame(() => { const c = khung.querySelector('.bc-cuon'); if (c) c.scrollLeft = c.scrollWidth; });
  const veBang = () => { const { dau, dong } = dongBC(); dat(khungBang, bangBC(dau, dong, { lop: 'bc-kqkd' })); cuonCuoi(khungBang); };
  veBang();

  // ----- Tiền – công nợ – tồn kho cuối tháng -----
  const SO_DU = [
    { nhan: 'Tiền (quỹ tiền mặt, ngân hàng)', k: 'so_du_quy', dau: 1 },
    { nhan: 'Tồn kho (giá vốn)', k: 'ton_kho', dau: 1 },
    { nhan: 'Phải thu khách', k: 'phai_thu_khach', dau: 1 },
    { nhan: 'Phải thu bảo hiểm', k: 'phai_thu_bh', dau: 1 },
    { nhan: 'Khách đã trả trước, trả dư', goiY: 'cọc, tiền dư phải trả lại', k: 'khach_tra_du', dau: -1 },
    { nhan: 'Phải trả nhà cung cấp', k: 'phai_tra_ncc', dau: -1 },
  ];
  const vonLuuDong = (x) => (x ? SO_DU.reduce((t, r) => t + r.dau * so(x[r.k]), 0) : null);
  // Chỉ các tháng có số dư (tháng chốt có số lưu, hoặc 3 tháng chưa chốt gần nhất)
  const dsSoDu = ds.filter((d) => soDu.has(String(d.thang)));
  const coSoDu = dsSoDu.length > 0;
  const dongSoDu = (donVi = 1) => {
    const cot = dsSoDu.map((d) => ({ d, x: soDu.get(String(d.thang)), truoc: soDu.get(thangLui(d.thang, 1)) || null }));
    const o = (v, dau = 1) => (!v ? '–' : dau < 0 ? `− ${soTien(v, donVi)}` : soTien(v, donVi));
    const oKy = (v) => (v === null ? h('span', { class: 'mo' }, '—') : !v ? '–' : `${v < 0 ? '−' : '+'} ${soTien(Math.abs(v), donVi)}`);
    return { dau: ['Khoản mục', ...cot.map((c) => h('span', { class: 'cot-thang' }, nhanThang(c.d.thang), h('br'),
      h('small', { class: 'mo' }, coSoDuChot(c.d) ? 'số lúc chốt' : `đến ${ngay(c.x.ngay)}`)))],
    dong: [
      ...SO_DU.map((r) => ({ loai: 'dong', nhan: r.nhan, goiY: r.goiY, o: cot.map((c) => o(so(c.x[r.k]), r.dau)) })),
      { loai: 'ket_qua', nhan: 'VỐN LƯU ĐỘNG RÒNG', o: cot.map((c) => { const v = vonLuuDong(c.x); return h('span', { class: v < 0 ? 'chu-loi' : null }, v ? soTien(v, donVi) : '–'); }) },
      { loai: 'dong', nhan: 'Tăng / giảm vốn lưu động trong tháng', o: cot.map((c) => oKy(c.truoc ? vonLuuDong(c.x) - vonLuuDong(c.truoc) : null)) },
      { loai: 'dong', nhan: 'Lãi trước thuế trong tháng (để so)', o: cot.map((c) => oKy(so(c.d.lai_truoc_thue))) },
    ] };
  };
  const khoiSoDu = h('section', { class: 'the' },
    h('h2', null, 'Tiền – công nợ – tồn kho cuối tháng'),
    h('p', { class: 'goi-y' }, 'Số tại ngày cuối tháng (tháng đang mở: đến hôm nay); tháng đã chốt lấy số lưu lúc chốt. Vốn lưu động ròng = tiền + tồn kho + phải thu − tiền khách trả trước − nợ nhà cung cấp. '
      + 'So "tăng / giảm vốn lưu động" với lãi của tháng: lãi đã thành tiền, nằm ở công nợ, tồn kho, hay đã rút ra (trả nợ nội bộ, mua tài sản…).'),
    coSoDu ? (() => { const x = dongSoDu(); return bangBC(x.dau, x.dong, { lop: 'bc-so-du' }); })() : h('p', { class: 'trong' }, 'Chưa tính được số dư.'));

  // ----- Phân tích: lãi gộp theo tổ, chi phí theo mục -----
  let kyPT = nhoPhien.doc('kqkd_ky_pt') || String(ky.thang);
  if (kyPT !== 'nam' && !ds.some((d) => String(d.thang) === kyPT)) kyPT = String(ky.thang);
  const chonKyPT = h('select', { class: 'chon-gon', 'aria-label': 'Kỳ phân tích', onchange: (e) => { kyPT = e.target.value; nhoPhien.ghi('kqkd_ky_pt', kyPT); vePhanTich(); } },
    [...ds].reverse().map((d) => h('option', { value: String(d.thang), selected: String(d.thang) === kyPT }, `Tháng ${nhanThang(d.thang)}`)),
    h('option', { value: 'nam', selected: kyPT === 'nam' }, `Cả năm ${nam}`));
  const khungPT = h('div');
  const NHOM_CP = [['gia_von', 'Chi phí nhóm giá vốn'], ['van_hanh', 'Chi phí vận hành'], ['co_dinh', 'Chi phí cố định']];
  function gopTo(loc) {
    const g = new Map();
    for (const x of (dsTo || []).filter((r) => loc(String(r.thang)))) {
      const o = g.get(x.to_id) || { to_id: x.to_id, ten: x.ten_to, dt: 0, gv: 0, xe: 0, dvn: 0 };
      o.dt += so(x.doanh_thu); o.gv += so(x.gia_von); o.xe += so(x.so_xe); o.dvn += so(x.so_luot_dvn);
      g.set(x.to_id, o);
    }
    return [...g.values()].sort((a, b) => (a.to_id === 'CHUNG') - (b.to_id === 'CHUNG') || (b.dt - b.gv) - (a.dt - a.gv));
  }
  function gopMuc(loc) {
    const g = new Map();
    for (const x of (dsMuc || []).filter((r) => loc(String(r.thang)))) {
      const k = `${x.nhom}|${x.muc}`;
      const o = g.get(k) || { nhom: x.nhom, muc: x.muc, tien: 0, phieu: 0 };
      o.tien += so(x.so_tien); o.phieu += so(x.so_phieu); g.set(k, o);
    }
    return g;
  }
  function vePhanTich() {
    const caNam = kyPT === 'nam';
    const trong = (t) => (caNam ? t.startsWith(`${nam}-`) : t === kyPT);
    const nhanKy = caNam ? `cả năm ${nam}` : `tháng ${nhanThang(kyPT)}`;
    // Lãi gộp theo tổ
    const to = gopTo(trong);
    const tongTo = to.reduce((t, x) => ({ dt: t.dt + x.dt, gv: t.gv + x.gv, dvn: t.dvn + x.dvn }), { dt: 0, gv: 0, dvn: 0 });
    const lgTong = tongTo.dt - tongTo.gv;
    const oLai = (v) => h('b', { class: v < 0 ? 'chu-loi' : null }, tien(v) || '0');
    const bangTo = dsTo === null ? h('p', { class: 'trong' }, 'Không tải được số liệu theo tổ.') : !to.length ? h('p', { class: 'trong' }, 'Kỳ này chưa có số liệu.')
      : bangBC(['Tổ', 'Doanh thu', 'Giá vốn', 'Lãi gộp', 'Tỷ suất', 'Tỷ trọng lãi gộp', 'Xe có doanh thu', 'Lượt DVN'], [
        ...to.map((x) => ({ loai: 'dong', nhan: x.ten, o: [tienO(x.dt), x.gv ? `− ${tien(x.gv)}` : '–', oLai(x.dt - x.gv),
          phanTram(x.dt ? (x.dt - x.gv) / Math.abs(x.dt) : null), phanTram(lgTong ? (x.dt - x.gv) / Math.abs(lgTong) : null),
          x.to_id === 'CHUNG' ? '' : (x.xe || '–'), x.dvn || '–'] })),
        { loai: 'ket_qua', nhan: 'LÃI GỘP', o: [tien(tongTo.dt) || '0', tongTo.gv ? `− ${tien(tongTo.gv)}` : '–', oLai(lgTong),
          phanTram(tongTo.dt ? lgTong / Math.abs(tongTo.dt) : null), '100%', '', tongTo.dvn || '–'] },
      ], { lop: 'bc-to' });
    // Chi phí theo mục (phiếu chi tính chất "Chi phí"); tháng: so với tháng trước
    const nay = gopMuc(trong);
    const truoc = caNam ? null : gopMuc((t) => t === thangLui(kyPT, 1));
    const tongCP = [...nay.values()].reduce((t, x) => t + x.tien, 0);
    const dongCP = [];
    for (const [nhom, ten] of [...NHOM_CP, ...[...new Set([...nay.values()].map((x) => x.nhom))].filter((n) => !NHOM_CP.some(([m]) => m === n)).map((n) => [n, n])]) {
      const muc = [...nay.values()].filter((x) => x.nhom === nhom).sort((a, b) => b.tien - a.tien);
      const mucTruoc = truoc ? [...truoc.values()].filter((x) => x.nhom === nhom && !nay.has(`${x.nhom}|${x.muc}`)) : [];
      if (!muc.length && !mucTruoc.length) continue;
      dongCP.push({ loai: 'muc', nhan: ten });
      const dongMuc = (x, tienNay) => {
        const tr = truoc ? (truoc.get(`${x.nhom}|${x.muc}`)?.tien || 0) : null;
        return { loai: 'dong', nhan: x.muc, o: [tienO(tienNay), ...(truoc ? [tienO(tr), tr ? oTang(tangTruong(tienNay, tr), { tot: false }) : (tienNay ? h('span', { class: 'mo' }, 'mới') : '')] : []),
          phanTram(tongCP ? tienNay / tongCP : null), x.phieu || '–'] };
      };
      muc.forEach((x) => dongCP.push(dongMuc(x, x.tien)));
      mucTruoc.forEach((x) => dongCP.push(dongMuc({ ...x, phieu: 0 }, 0)));
      const cong = muc.reduce((t, x) => t + x.tien, 0);
      const congTruoc = truoc ? [...truoc.values()].filter((x) => x.nhom === nhom).reduce((t, x) => t + x.tien, 0) : null;
      dongCP.push({ loai: 'tong', nhan: `Cộng ${ten.toLowerCase()}`, o: [tien(cong) || '0', ...(truoc ? [tien(congTruoc) || '0', oTang(tangTruong(cong, congTruoc), { tot: false })] : []),
        phanTram(tongCP ? cong / tongCP : null), muc.reduce((t, x) => t + x.phieu, 0) || '–'] });
    }
    const tongTruoc = truoc ? [...truoc.values()].reduce((t, x) => t + x.tien, 0) : null;
    if (dongCP.length) dongCP.push({ loai: 'ket_qua', nhan: 'TỔNG CHI PHÍ THEO PHIẾU CHI', o: [tien(tongCP) || '0', ...(truoc ? [tien(tongTruoc) || '0', oTang(tangTruong(tongCP, tongTruoc), { tot: false })] : []), '100%', [...nay.values()].reduce((t, x) => t + x.phieu, 0) || '–'] });
    const bangCP = dsMuc === null ? h('p', { class: 'trong' }, 'Không tải được chi phí theo mục.') : !dongCP.length ? h('p', { class: 'trong' }, 'Kỳ này chưa có phiếu chi phí.')
      : bangBC(['Mục chi phí', 'Số tiền', ...(truoc ? [`Tháng ${nhanThang(thangLui(kyPT, 1))}`, '±'] : []), '% tổng', 'Số phiếu'], dongCP, { lop: 'bc-muc-cp' });
    dat(khungPT,
      h('h3', null, `Lãi gộp theo tổ – ${nhanKy}`),
      h('p', { class: 'goi-y' }, 'Doanh thu theo tổ làm hạng mục, giá vốn theo tổ đề xuất vật tư. Dòng "Chung": giảm giá, vật tư dùng chung, xuất không qua đề xuất, hao hụt kiểm kê, chi phí nhóm giá vốn – cộng các dòng đúng bằng lãi gộp của báo cáo.'),
      bangTo,
      h('h3', null, `Chi phí theo mục – ${nhanKy}`),
      h('p', { class: 'goi-y' }, 'Các phiếu chi có tính chất "Chi phí" (theo "chi phí của tháng"). Lương lấy từ bảng lương tháng, hoa hồng GDV lấy từ hồ sơ – xem ở bảng kết quả kinh doanh.'),
      bangCP);
  }
  vePhanTich();
  const khoiPhanTich = h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, 'Phân tích'), chonKyPT), khungPT);

  // ----- Khóa sổ từng tháng: chốt lần lượt, mở lại từ tháng sau cùng, lưu lịch sử -----
  const coSoLieu = (x) => so(x.doanh_thu) || so(x.tong_gia_von) || so(x.tong_chi_phi) || so(x.thu_khac) || x.luong_da_nhap;
  const phaiChotTruoc = (d) => tatCa.find((x) => x.thang < d.thang && x.trang_thai === 'cho_chot' && coSoLieu(x)) || null;
  const thangChotCuoi = [...tatCa].reverse().find((x) => x.da_chot) || null;
  const dongThang = (d) => {
    const thieu = d.thieu_dinh_ky || [];
    const ls = lsTheoThang.get(String(d.thang)) || [];
    const truoc = d.trang_thai === 'cho_chot' ? phaiChotTruoc(d) : null;
    const nguoiChot = d._chot?.chot_boi ? tenNguoi(d._chot.chot_boi) : '';
    const nutLap = (ten) => (api.laCoDong() ? h('span', null, ten) : h('a', { class: 'nut nho', href: `#/de-nghi?lap=1&muc=${encodeURIComponent(ten)}&ky=${String(d.thang).slice(0, 10)}` }, `+ ${ten}`));
    return h('div', { class: `dong-thang ${d.trang_thai}` },
      h('div', { class: 'dong-thang-dau' }, h('b', null, `Tháng ${nhanThang(d.thang)}`), h('small', null, ` kỳ 01/${nhanThang(d.thang)} – ${ngay(d.ngay_cuoi)}`), theTT(d), theLech(d),
        d.da_chot ? h('small', null, ` · chốt lúc ${ngayGio(d.chot_luc)}${nguoiChot ? ` · ${nguoiChot}` : ''}`) : null),
      d.lech_chot ? h('p', { class: 'thong-bao canh-bao' }, lyDoLech(d)) : null,
      d.da_chot ? null : h('ul', { class: 'checklist' },
        h('li', { class: d.luong_da_nhap ? 'xong' : 'thieu' }, d.luong_da_nhap ? `✓ Lương tháng: ${tien(d.luong)} đ` : '✗ Chưa nhập bảng lương tháng',
          kt ? h('button', { class: 'nut nho', type: 'button', onclick: () => moLuong(d) }, d.luong_da_nhap ? 'Sửa lương' : 'Nhập lương') : null),
        h('li', { class: thieu.length ? 'thieu' : 'xong' }, thieu.length ? ['✗ Chi phí định kỳ chưa có: ', thieu.map((t) => nutLap(t))] : '✓ Chi phí định kỳ (điện, nước, mặt bằng…) đã có đủ'),
        h('li', { class: so(d.de_nghi_cho_chi) ? 'thieu' : 'xong' }, so(d.de_nghi_cho_chi) ? ['✗ ', h('a', { href: '#/de-nghi' }, `${d.de_nghi_cho_chi} đề nghị chi của kỳ chưa chi`)] : '✓ Không còn đề nghị chi chờ của kỳ')),
      h('div', { class: 'hang-nut' },
        gd && d.trang_thai === 'cho_chot' && !truoc ? h('button', { class: 'nut nho chinh', type: 'button', 'data-chot': String(d.thang), onclick: async () => {
          if (!(await xacNhan(`Chốt tháng ${nhanThang(d.thang)} (kỳ 01/${nhanThang(d.thang)} – ${ngay(d.ngay_cuoi)})? Sau khi chốt không ghi hay sửa được phiếu, hồ sơ, chi phí của tháng này; số liệu và tiền – công nợ – tồn kho cuối tháng được lưu lại, tháng này vào Báo cáo cổ đông.`, 'Chốt tháng'))) return;
          await chay((boQua) => api.chotThang(d.thang, boQua), { thanhCong: `Đã chốt tháng ${nhanThang(d.thang)}.` }).then(veLai, () => {});
        } }, 'Chốt tháng') : null,
        gd && truoc ? h('small', { class: 'mo' }, `Chốt tháng ${nhanThang(truoc.thang)} trước (chốt lần lượt từng tháng).`) : null,
        d.trang_thai === 'dang_mo' ? h('small', { class: 'mo' }, `Chốt được từ ngày ${ngay(thangLui(d.thang, -1))}; tiền điện, lương của tháng nhập sau ngày đó vẫn tính vào tháng này (chọn "Chi phí của tháng" khi lập đề nghị chi).`) : null,
        gd && d.da_chot && thangChotCuoi && String(thangChotCuoi.thang) === String(d.thang) ? h('button', { class: 'nut nho', type: 'button', onclick: () => moMoLai(d) }, 'Mở lại') : null),
      ls.length ? h('details', { class: 'ls-mo-lai' }, h('summary', null, `Đã mở lại ${ls.length} lần – xem lịch sử`),
        h('ul', null, ls.map((x) => h('li', null, h('b', null, ngayGio(x.mo_lai_luc)), ` · ${tenNguoi(x.mo_lai_boi) || 'Không rõ'}: ${x.ly_do}`,
          x.so_lieu && x.so_lieu.lai_truoc_thue !== undefined ? h('small', { class: 'mo' }, ` (số chốt trước đó: doanh thu ${tien(x.so_lieu.doanh_thu) || '0'} đ, lãi trước thuế ${tien(x.so_lieu.lai_truoc_thue) || '0'} đ; chốt lúc ${ngayGio(x.chot_luc)})`) : null)))) : null);
  };
  const khoiKhoaSo = h('section', { class: 'the' },
    h('h2', null, 'Khóa sổ tháng'),
    h('p', { class: 'goi-y' }, 'Kỳ báo cáo khóa ở ngày cuối tháng; các khoản nhập sau (tiền điện, lương…) chọn đúng tháng là vẫn tính vào tháng đó. Chốt lần lượt từ tháng cũ đến tháng mới; '
      + 'mở lại thì mở từ tháng chốt sau cùng, lý do và số cũ được lưu lại. Chốt xong không ghi, sửa gì vào tháng đó nữa.'),
    h('div', { class: 'ds-thang-kqkd' }, [...ds].reverse().map(dongThang)));

  if (!conMoi()) return;
  dat(ketQua,
    congCu,
    khoiKpi,
    h('section', { class: 'the' }, bieuDo),
    h('section', { class: 'the bc-the' },
      h('div', { class: 'the-dau' }, h('h2', null, `Kết quả kinh doanh năm ${nam}`)),
      h('p', { class: 'goi-y' }, 'Đơn vị: đồng. Số gồm VAT như sổ của gara: doanh thu theo ngày duyệt giá (xe bảo hiểm) hoặc ngày khách đồng ý báo giá (khách lẻ); vật tư theo tháng xuất kho; '
        + 'chi phí theo "chi phí của tháng"; lương theo bảng lương tháng; hoa hồng GDV theo tháng duyệt giá đầu của xe. Phần V bỏ VAT để ra lãi gần với sổ thuế; phần VI là VAT phải nộp ước tính '
        + '(hóa đơn nhập hàng được khấu trừ ngay tháng nhập). Tháng đã chốt hiện số lúc chốt. Bấm vào số của một tháng để xem chi tiết.'
        + (dangMo && cungKy ? ` Tháng ${nhanThang(dangMo.thang)} chưa hết tháng nên lũy kế và "± so cùng kỳ" còn thấp hơn thực tế.` : '')),
      khungBang),
    khoiSoDu,
    khoiPhanTich,
    khoiKhoaSo);

  // ---------------- Xem chi tiết một ô ----------------
  async function moChiTiet(r, d) {
    const noiDung = h('div', null, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    const dong = moModal(`${r.nhan.replace(/\s*\(.*\)$/, '')} – tháng ${nhanThang(d.thang)}`, noiDung, { rong: true });
    try {
      const dsCt = await api.chiTietKqkd(d.thang, r.ct);
      const tong = dsCt.reduce((t, x) => t + so(x.so_tien), 0);
      const laXe = r.ct === 'so_xe'; const laDvn = r.k === 'so_luot_dvn';
      const soBC = so(d[r.k]);
      const khop = laXe || laDvn ? dsCt.length === soBC : Math.abs(tong - soBC) < 1;
      dat(noiDung,
        bang([
          { nhan: 'Nhóm', lay: (x) => x.nhom },
          { nhan: laXe ? 'Xe · hồ sơ' : 'Nội dung', lay: (x) => (x.ho_so_id ? h('a', { href: `#/ho-so/${x.ho_so_id}`, onclick: () => dong() }, x.ten || x.ma) : x.ten) },
          { nhan: laXe ? 'Duyệt giá đầu' : 'Ngày', lay: (x) => ngay(x.ngay) },
          { nhan: laXe ? 'Giá đã duyệt (gồm VAT)' : 'Số tiền', so: true, lay: (x) => tien(x.so_tien) || '0' },
        ], dsCt, { trong: 'Không có dòng nào.' }),
        h('p', { class: 'bc-cong' }, `${dsCt.length} dòng`, laXe || laDvn ? ` · ${laXe ? 'giá đã duyệt' : 'doanh thu'} ${tien(tong) || '0'} đ` : ` · cộng ${tien(tong) || '0'} đ`),
        !khop ? h('p', { class: 'thong-bao canh-bao' }, d.da_chot
          ? `Tháng đã chốt với số ${laXe || laDvn ? soBC : `${tien(soBC)} đ`}; số hiện tại ${laXe || laDvn ? dsCt.length : `${tien(tong)} đ`}. Mở lại tháng để kiểm tra rồi chốt lại.`
          : 'Số chi tiết chưa khớp số báo cáo – tải lại trang để lấy số mới nhất.') : null);
    } catch (e) { dat(noiDung, h('p', { class: 'chu-loi' }, e.message)); }
  }

  // ---------------- Lương, mở lại tháng ----------------
  function moLuong(d) {
    const form = h('form', null, truong(`Tổng lương tháng ${nhanThang(d.thang)}`, oTien('tong', Number(d.luong) || null), 'Nhập một số tổng; phiếu chi trả lương chỉ là chi tiền, không tính hai lần.', { batBuoc: true }));
    moModal('Bảng lương tháng', form, { nhanNut: 'Lưu', nutChinh: async () => {
      const t = docForm(form).tong; if (t === null) { toast('Nhập số tiền.', 'loi'); return false; }
      await api.nhapBangLuong(d.thang, t); toast('Đã lưu lương tháng.'); await veLai();
    } });
  }
  function moMoLai(d) {
    hoiLyDo(`Mở lại tháng ${nhanThang(d.thang)}`, async (lyDo) => {
      await api.moLaiThang(d.thang, lyDo); toast(`Đã mở lại tháng ${nhanThang(d.thang)}.`); await veLai();
    }, { nhan: 'Lý do mở lại', nhanNut: 'Mở lại', goiY: 'Ví dụ: nhập thiếu hóa đơn điện, sửa lương. Số lúc chốt được lưu vào lịch sử; sửa xong nhớ chốt lại.' });
  }

  // ---------------- In báo cáo (khổ A4 ngang) ----------------
  function moIn() {
    let donVi = ds.length > 6 ? 1000 : 1;
    const khung = h('div', { class: 'bc-in' });
    const veIn = () => {
      const bc = dongBC({ bam: false, donVi }); const sd = coSoDu ? dongSoDu(donVi) : null;
      dat(khung,
        h('p', { class: 'bb-cty' }, tenCongTy().toUpperCase()),
        h('h3', { class: 'bb-tieu-de' }, `BÁO CÁO KẾT QUẢ KINH DOANH NĂM ${nam}`),
        h('p', { class: 'bb-phu' }, `Từ tháng ${nhanThang(ds[0].thang)} đến tháng ${nhanThang(ds[ds.length - 1].thang)} · Đơn vị: ${TEN_DON_VI[donVi]}${pt ? ' (theo % doanh thu)' : ''} · Số gồm VAT; tháng đã chốt lấy số lúc chốt`),
        bangBC(bc.dau, bc.dong, { lop: 'bc-kqkd' }),
        sd ? [h('h4', { class: 'bc-in-muc' }, 'TIỀN – CÔNG NỢ – TỒN KHO CUỐI THÁNG'), bangBC(sd.dau, sd.dong, { lop: 'bc-so-du' })] : null,
        h('p', { class: 'goi-y' }, 'Phần V bỏ VAT khỏi lãi (ước tính); phần VI là VAT phải nộp ước tính của tháng. Tháng "Đang mở" là số tạm tính đến ngày in.'),
        h('div', { class: 'bb-ky' }, ['Người lập', 'Kế toán', 'Giám đốc'].map((x) => h('div', null, h('b', null, x), h('small', null, '(ký, ghi rõ họ tên)')))),
        h('p', { class: 'goi-y bc-in-luc' }, `In lúc ${ngayGio(new Date())} · ${tenCongTy()}`));
    };
    veIn();
    const chonDV = h('select', { class: 'chon-gon', 'aria-label': 'Đơn vị tiền', onchange: (e) => { donVi = Number(e.target.value); veIn(); } },
      Object.entries(TEN_DON_VI).map(([v, t]) => h('option', { value: v, selected: Number(v) === donVi }, `Đơn vị: ${t}`)));
    moModal('In báo cáo kết quả kinh doanh', h('div', null,
      h('div', { class: 'hang-nut khong-in' }, chonDV, h('button', { class: 'nut chinh', type: 'button', onclick: (e) => {
        // Khổ ngang chỉ cho lần in này (biên bản kiểm kê vẫn in khổ dọc)
        const nen = e.currentTarget.closest('.modal-nen');
        const kho = h('style', null, '@page { size: A4 landscape; margin: 10mm; }');
        let daDon = false;
        const don = () => { if (daDon) return; daDon = true; kho.remove(); document.body.classList.remove('dang-in'); nen?.classList.remove('in-day'); };
        document.head.append(kho); nen?.classList.add('in-day'); document.body.classList.add('dang-in');
        window.addEventListener('afterprint', don, { once: true });
        window.print();
        if (!('onafterprint' in window)) setTimeout(don, 1000);
      } }, 'In'), h('small', { class: 'mo' }, 'Khổ A4 ngang. Nhiều tháng thì chọn đơn vị nghìn / triệu đồng cho gọn.')), khung), { rong: true });
  }

  // ---------------- Xuất Excel (giám đốc) ----------------
  async function xuatExcel() {
    const { taiFileExcel } = await import('../excel.js');
    const luc = ngayGio(new Date()); const cty = tenCongTy();
    const nhanCot = (d) => `${nhanThang(d.thang)}\n${NHAN_TT[d.trang_thai][0]}${d.lech_chot ? ' – lệch' : ''}`;
    // Trang 1: kết quả kinh doanh (khoản trừ ghi số âm để cộng được trong Excel)
    const cotKq = [{ nhan: 'Khoản mục', rong: 48, kieu: 'chu' }, ...ds.map((d) => ({ nhan: nhanCot(d), rong: 15, kieu: 'tien' })),
      { nhan: `Lũy kế ${nam}`, rong: 17, kieu: 'tien' }, ...(cungKy ? [{ nhan: `Cùng kỳ ${Number(nam) - 1}`, rong: 17, kieu: 'tien' }, { nhan: '± so cùng kỳ', rong: 13, kieu: 'phan_tram' }] : [])];
    const oExcel = (r, d) => {
      const v = giaTri(r, d); if (v === null) return null;
      if (r.kieu === 'ty_le') return { v, kieu: 'phan_tram', nghieng: true };
      const x = r.dau === '−' ? -v : v;
      if (r.kieu === 'dem' || r.kieu === 'chi_so') return Math.round(x);
      return r.kieu === 'tong' || r.kieu === 'ket_qua' ? { v: x, dam: true, nen: r.kieu === 'ket_qua' } : x;
    };
    const dongKq = DONG.map((r) => {
      if (r.muc) return [{ v: r.muc, dam: true, nen: true }, ...cotKq.slice(1).map(() => ({ v: null, nen: true }))];
      const nhan = r.goiY ? `${r.nhan} (${r.goiY})` : r.nhan;
      const dam = r.kieu === 'tong' || r.kieu === 'ket_qua';
      let ss;
      if (cungKy) {
        const a = giaTri(r, luyKe); const b = giaTri(r, cungKy);
        // tỷ suất: chênh lệch điểm %; số tiền: % khi cả hai không âm và nền dương, không thì chênh lệch tuyệt đối (đồng)
        ss = a === null || b === null ? null : r.kieu === 'ty_le' ? { v: a - b, kieu: 'phan_tram', nghieng: true }
          : b > 0 && a >= 0 ? { v: (a - b) / b, kieu: 'phan_tram' } : { v: Math.round(a - b), kieu: 'tien' };
      }
      return [dam ? { v: nhan, dam: true, nen: r.kieu === 'ket_qua' } : nhan, ...ds.map((d) => oExcel(r, d)), oExcel(r, luyKe),
        ...(cungKy ? [oExcel(r, cungKy), ss] : [])];
    });
    const trang = [{ ten: `KQKD ${nam}`, tieuDe: `BÁO CÁO KẾT QUẢ KINH DOANH NĂM ${nam}`, giuCot: 1, khongLoc: true,
      phuDe: `${cty} · Đơn vị: đồng · Số gồm VAT (phần V bỏ VAT, ước tính); khoản trừ ghi số âm · Tháng đã chốt lấy số lúc chốt · Xuất lúc ${luc}`,
      cot: cotKq, dong: dongKq }];
    // Trang 2: chi phí theo mục, mỗi tháng một cột
    if (dsMuc) {
      const thangs = ds.map((d) => String(d.thang));
      const cot = [{ nhan: 'Mục chi phí', rong: 40, kieu: 'chu' }, ...ds.map((d) => ({ nhan: nhanThang(d.thang), rong: 14, kieu: 'tien' })), { nhan: `Cộng ${nam}`, rong: 16, kieu: 'tien' }, { nhan: 'Số phiếu', rong: 10, kieu: 'so' }];
      const dong = [];
      for (const [nhom, ten] of [...NHOM_CP, ...[...new Set(dsMuc.map((x) => x.nhom))].filter((n) => !NHOM_CP.some(([m]) => m === n)).map((n) => [n, n])]) {
        const cua = dsMuc.filter((x) => x.nhom === nhom && thangs.includes(String(x.thang)));
        if (!cua.length) continue;
        dong.push([{ v: ten.toUpperCase(), dam: true, nen: true }, ...cot.slice(1).map(() => ({ v: null, nen: true }))]);
        for (const muc of [...new Set(cua.map((x) => x.muc))].sort((a, b) => a.localeCompare(b, 'vi'))) {
          const theo = thangs.map((t) => cua.filter((x) => x.muc === muc && String(x.thang) === t).reduce((s, x) => s + so(x.so_tien), 0));
          dong.push([muc, ...theo.map((v) => v || null), theo.reduce((s, v) => s + v, 0), cua.filter((x) => x.muc === muc).reduce((s, x) => s + so(x.so_phieu), 0)]);
        }
        const cong = thangs.map((t) => cua.filter((x) => String(x.thang) === t).reduce((s, x) => s + so(x.so_tien), 0));
        dong.push([{ v: `Cộng ${ten.toLowerCase()}`, dam: true }, ...cong.map((v) => ({ v, dam: true })), { v: cong.reduce((s, v) => s + v, 0), dam: true }, { v: cua.reduce((s, x) => s + so(x.so_phieu), 0), dam: true }]);
      }
      trang.push({ ten: 'Chi phí theo mục', tieuDe: `CHI PHÍ THEO MỤC NĂM ${nam}`, giuCot: 1, khongLoc: true,
        phuDe: `${cty} · Phiếu chi tính chất "Chi phí", theo "chi phí của tháng" · Không gồm lương (bảng lương) và hoa hồng GDV · Xuất lúc ${luc}`, cot, dong });
    }
    // Trang 3: lãi gộp theo tổ
    if (dsTo) {
      const cot = [{ nhan: 'Tháng', rong: 10, kieu: 'chu' }, { nhan: 'Tổ', rong: 40, kieu: 'chu' }, { nhan: 'Doanh thu', rong: 16, kieu: 'tien' }, { nhan: 'Giá vốn', rong: 16, kieu: 'tien' },
        { nhan: 'Lãi gộp', rong: 16, kieu: 'tien' }, { nhan: 'Tỷ suất', rong: 10, kieu: 'phan_tram' }, { nhan: 'Xe có doanh thu', rong: 12, kieu: 'so' }, { nhan: 'Lượt DVN', rong: 10, kieu: 'so' }];
      const dong = dsTo.map((x) => [nhanThang(x.thang), x.ten_to, so(x.doanh_thu), -so(x.gia_von), so(x.doanh_thu) - so(x.gia_von),
        so(x.doanh_thu) ? (so(x.doanh_thu) - so(x.gia_von)) / Math.abs(so(x.doanh_thu)) : null, x.to_id === 'CHUNG' ? null : so(x.so_xe), so(x.so_luot_dvn)]);
      dong.push([{ v: `CẢ NĂM ${nam}`, dam: true, nen: true }, ...cot.slice(1).map(() => ({ v: null, nen: true }))]);
      for (const x of gopTo((t) => t.startsWith(`${nam}-`))) {
        dong.push([String(nam), { v: x.ten, dam: true }, { v: x.dt, dam: true }, { v: -x.gv, dam: true }, { v: x.dt - x.gv, dam: true },
          { v: x.dt ? (x.dt - x.gv) / Math.abs(x.dt) : null, kieu: 'phan_tram', dam: true }, x.to_id === 'CHUNG' ? null : x.xe, x.dvn]);
      }
      trang.push({ ten: 'Lãi gộp theo tổ', tieuDe: `LÃI GỘP THEO TỔ NĂM ${nam}`, giuCot: 2, khongLoc: true,
        phuDe: `${cty} · Giá vốn ghi số âm · Dòng "Chung": giảm giá, vật tư dùng chung, xuất không qua đề xuất, hao hụt, chi phí nhóm giá vốn · Xuất lúc ${luc}`, cot, dong });
    }
    // Trang 4: tiền – công nợ – tồn kho cuối tháng
    if (coSoDu) {
      const cot = [{ nhan: 'Khoản mục', rong: 44, kieu: 'chu' }, ...dsSoDu.map((d) => ({ nhan: nhanThang(d.thang), rong: 15, kieu: 'tien' }))];
      const x = (d) => soDu.get(String(d.thang));
      const dong = [
        ...SO_DU.map((r) => [r.goiY ? `${r.nhan} (${r.goiY})` : r.nhan, ...dsSoDu.map((d) => r.dau * so(x(d)[r.k]))]),
        [{ v: 'VỐN LƯU ĐỘNG RÒNG', dam: true, nen: true }, ...dsSoDu.map((d) => ({ v: vonLuuDong(x(d)), dam: true, nen: true }))],
        ['Lãi trước thuế trong tháng (để so)', ...dsSoDu.map((d) => so(d.lai_truoc_thue))],
      ];
      trang.push({ ten: 'Tiền - công nợ cuối tháng', tieuDe: `TIỀN – CÔNG NỢ – TỒN KHO CUỐI THÁNG NĂM ${nam}`, giuCot: 1, khongLoc: true,
        phuDe: `${cty} · Khoản phải trả ghi số âm · Tháng đã chốt lấy số lúc chốt, tháng đang mở tính đến hôm nay · Xuất lúc ${luc}`, cot, dong });
    }
    // Trang 5: giải thích
    trang.push({ ten: 'Giải thích', tieuDe: 'CÁCH TÍNH CÁC DÒNG', khongLoc: true, cot: [{ nhan: 'Dòng', rong: 44, kieu: 'chu' }, { nhan: 'Cách tính', rong: 110, kieu: 'chu' }], dong: GIAI_THICH });
    taiFileExcel(`Ket-qua-kinh-doanh_${nam}_${homNay()}.xlsx`, trang);
  }
}

const GIAI_THICH = [
  ['Doanh thu', 'Giá đã duyệt gồm VAT, ghi vào ngày duyệt giá (xe bảo hiểm) hoặc ngày khách đồng ý báo giá (khách lẻ); dịch vụ nhanh theo ngày làm; giảm giá theo ngày duyệt giảm giá. Không gồm xe bảo hành, hồ sơ chuyển từ Excel.'],
  ['Vật tư xuất cho xe, dùng chung', 'Giá vốn (gồm VAT) các phiếu xuất kho trong tháng, theo lô nhập trước xuất trước.'],
  ['Hao hụt kiểm kê', 'Giá vốn hàng kiểm kê thiếu trừ giá trị hàng kiểm kê thừa trong tháng (âm = thừa nhiều hơn thiếu).'],
  ['Chi phí nhóm giá vốn / vận hành / cố định', 'Phiếu chi có tính chất "Chi phí", theo nhóm của mục chi; tính vào tháng ghi ở "Chi phí của tháng" (không có thì theo ngày chi).'],
  ['Lương', 'Tổng lương nhập ở bảng lương tháng (phiếu chi trả lương chỉ là chi tiền, không tính hai lần).'],
  ['Hoa hồng GDV', 'Hoa hồng ghi ở hồ sơ, tính vào tháng duyệt giá đầu tiên của xe.'],
  ['Thu nhập khác', 'Phiếu thu của các mục có tích "Vào lãi lỗ" (trạm sạc, thu khác). Tiền bo của thợ, phí bảo hiểm thu hộ không tính.'],
  ['Lãi trước thuế (số gồm VAT)', 'Lãi gộp − tổng chi phí hoạt động + thu nhập khác.'],
  ['Lãi không gồm VAT', 'Lãi trước thuế − VAT đầu ra + VAT nằm trong giá vốn vật tư đã xuất + VAT trong chi phí. Gần với lãi trên sổ thuế (trước thuế TNDN); là số ước tính.'],
  ['VAT phải nộp', 'VAT đầu ra − VAT hóa đơn nhập hàng trong tháng − VAT hóa đơn chi phí. Âm = còn được khấu trừ sang tháng sau. Số ước tính, kế toán thuế đối chiếu khi khai.'],
  ['Xe sửa chữa', 'Số hồ sơ có lần duyệt giá đầu tiên trong tháng (cộng lũy kế không bị trùng).'],
  ['Tháng đã chốt', 'Hiện số lưu lúc chốt. Nếu số hiện tại khác, báo "Lệch": mở lại tháng, kiểm tra rồi chốt lại. Chốt lần lượt từng tháng; mở lại từ tháng chốt sau cùng.'],
  ['Vốn lưu động ròng', 'Tiền + tồn kho + phải thu khách, bảo hiểm − tiền khách trả trước / trả dư − nợ nhà cung cấp, tại ngày cuối tháng.'],
];
