// Thông báo hiện lên màn hình người đảm nhận tiếp theo (054 – anh Thuận yêu cầu 17/10/2026)
//  - Cứ ~20 giây hỏi máy chủ xem có thông báo CHƯA NHẬN gửi riêng cho mình không. Có thì hiện khung to giữa màn hình,
//    phải bấm "Đã nhận" mới tắt; máy chủ ghi lúc nhận → hồ sơ xe hiện "ai nhận lúc nào".
//  - Nhắc quá hạn: tính ngay trên máy từ danh sách "Việc hôm nay" (trang Việc hôm nay gửi sang qua sự kiện gara:viec-qua-han,
//    cứ 30 phút lại tự tính lại); bấm "Đã biết" thì 4 giờ sau mới nhắc lại (nhớ trong trình duyệt, không ghi máy chủ).
//  - Máy chủ chưa chạy 054 (chưa có bảng thong_bao): lặng lẽ không làm gì với phần thông báo, nhắc quá hạn vẫn chạy.
//    Tài khoản cổ đông không có thông báo.
//  Móc kiểm thử: window.__TAT_THONG_BAO = true tắt hẳn; window.__HOI_TB_MS = số mili-giây giữa hai lần hỏi (mặc định 20000);
//  window.__QUA_HAN_SAU_MS = chờ bao lâu sau khi mở app mới tự tính việc quá hạn khi đang ở trang khác (mặc định 20000);
//  window.__HET_GIO_TB_MS = rút ngắn thời gian chờ tối đa của các yêu cầu lên máy chủ (nhận 12 giây, hỏi 15 giây, quá hạn 25 giây).
import { h, bienSo, icon, ngay } from './ui.js';
import * as api from './api.js';
import { chuHan } from './han-viec.js';

const HOI_MS = 20000;
const HOI_KHI_THIEU_BANG_MS = 60000;       // chưa có bảng ở máy chủ: chỉ còn lo nhắc quá hạn nên thưa hơn
const NHAC_LAI_MS = 4 * 36e5;              // "Đã biết" việc quá hạn → 4 giờ sau mới nhắc lại
const TINH_LAI_QUA_HAN_MS = 30 * 60e3;     // tự tính lại việc quá hạn mỗi 30 phút (ngoài lúc trang Việc hôm nay vẽ lại)
const AN_TAM_MS = 10 * 60e3;               // chỉ khi bấm "Đã nhận" bị lỗi: cho ẩn khung tạm 10 phút để vẫn làm việc được
// Mạng chập chờn có thể làm một yêu cầu treo mãi không báo lỗi → quá giờ thì coi như lỗi, để khung không kẹt và vòng hỏi không đứng
const HET_GIO_NHAN_MS = 12000;
const HET_GIO_HOI_MS = 15000;
const HET_GIO_QUA_HAN_MS = 25000;
const TIEU_DE_GOC = document.title;

export const TEN_LOAI = { to: 'Tổ sửa chữa', kho: 'Kho', tien: 'Tiền' };

const S = {
  phien: 0, chay: false, timer: null, khaDung: true, daCoBang: false, lanDau: true, dangHoi: false, daBaoLoi: false,
  ds: [],                  // thông báo chưa nhận, lấy từ máy chủ (cũ nhất trước)
  daNhan: new Set(),       // vừa bấm nhận ở máy này: đừng vẽ lại nếu một lượt hỏi cũ còn trả về
  daThay: new Map(),       // id → cap_nhat_luc đã thấy: nhận ra thông báo MỚI hoặc vừa được gộp thêm dòng
  loi: new Map(),          // id → câu báo lỗi khi bấm nhận không được
  them: new Set(),         // id vừa bấm nhận nhưng thông báo đó vừa được gộp thêm dòng mới → chưa tính là nhận, hiện ghi chú trên thẻ
  quaHanTho: [], nhoTam: {}, lanQuaHan: 0, dangTaiQuaHan: false, tai: null,
  batDauLuc: 0, anDen: 0, lop: null,
};

function choToiDa(loiHua, mac) {
  let hen;
  const het = new Promise((_, tu) => { hen = setTimeout(() => tu(new Error('Máy chủ trả lời quá lâu')), Number(window.__HET_GIO_TB_MS) || mac); });
  return Promise.race([loiHua, het]).finally(() => clearTimeout(hen));
}

// ---------- Chữ hiển thị ----------
const hai = (x) => String(x).padStart(2, '0');
// "14:05" nếu hôm nay, "14:05 16/10" nếu ngày khác
export function gioBao(luc) {
  if (!luc) return '';
  const t = new Date(luc);
  const gio = `${hai(t.getHours())}:${hai(t.getMinutes())}`;
  const bay = new Date();
  return t.toDateString() === bay.toDateString() ? gio : `${gio} ${ngay(t).slice(0, 5)}`;
}

// Tiêu đề có biển số ("Việc mới cho tổ Đồng sơn – xe 50H-923.61", "Xe 50H-923.61 đến lượt Detailing") → vẽ biển số như biển thật ở đầu thẻ
export function tachTieuDe(tieu) {
  const t = String(tieu || '');
  let m = /^(.*?)\s+–\s+xe\s+(\S+)(.*)$/.exec(t);
  let chu = t; let bien = null; let ghiChu = null;
  if (m) {
    bien = m[2];
    const du = m[3].trim();
    if (du.startsWith('(')) { chu = m[1]; ghiChu = du; } else chu = `${m[1]} ${du}`.trim();
  } else if ((m = /^Xe\s+(\S+)\s+(.*)$/.exec(t))) {
    bien = m[1];
    const du = m[2];
    const mo = du.indexOf('(');
    const chinh = (mo > 0 ? du.slice(0, mo) : du).trim();
    chu = chinh.charAt(0).toUpperCase() + chinh.slice(1);
    if (mo > 0) ghiChu = du.slice(mo).trim();
  }
  return { chu, bien, ghiChu };
}

// Nơi mở khi bấm "Đã nhận – mở …": trưởng nhóm không mở được hồ sơ xe → xem xe của tổ ở Việc hôm nay
export function duongDich(n) {
  const truongNhom = !api.laNhanVien();
  switch (n.dich) {
    case 'ho_so': return n.ho_so_id ? (truongNhom ? { href: '#/viec', nhan: 'xem xe của tổ' } : { href: `#/ho-so/${n.ho_so_id}`, nhan: 'mở hồ sơ xe' }) : null;
    case 'kho_de_xuat': return { href: '#/kho?the=de_xuat', nhan: 'mở Kho' };
    case 'kho_mua': return { href: '#/kho?the=mua', nhan: 'mở Kho' };
    case 'kho_nhap': return { href: '#/kho?the=nhap', nhan: 'mở Kho' };
    case 'de_nghi': return { href: '#/de-nghi', nhan: 'mở Đề nghị chi' };
    default: return null;
  }
}
const khacChiNhanh = (n) => !!(n.chi_nhanh_id && api.toi?.chi_nhanh_id && n.chi_nhanh_id !== api.toi.chi_nhanh_id);
export const nhanChiNhanh = (id) => h('span', { class: `nhan-cn cn-${api.mauChiNhanh(id)}` }, api.tenNganChiNhanh(id));

// ---------- Nhớ "Đã biết" của nhắc quá hạn (trình duyệt này, 4 giờ) ----------
const khoaNho = () => `gara_nhac_qua_han_${api.toi?.id || ''}`;
function docNho() {
  const bay = Date.now();
  let o = {};
  try { o = JSON.parse(localStorage.getItem(khoaNho()) || '{}') || {}; } catch { o = {}; }
  return Object.fromEntries(Object.entries({ ...o, ...S.nhoTam }).filter(([, t]) => t > bay));
}
function ghiNho(o) { try { localStorage.setItem(khoaNho(), JSON.stringify(o)); } catch { /* bộ nhớ trình duyệt bị chặn: chỉ nhớ trong phiên */ } }
const quaHanChuaBiet = () => {
  const nho = docNho(); const bay = Date.now();
  return S.quaHanTho.filter((v) => v.han < bay && !(nho[v.khoa] > bay));
};

// ---------- Vẽ khung ----------
function danhSachThe() {
  const ds = S.ds.map((n) => ({ kieu: 'may-chu', n }));
  const qh = quaHanChuaBiet();
  if (qh.length) ds.push({ kieu: 'qua-han', ds: qh });
  return ds;
}
const chuKy = (ds) => ds.map((x) => (x.kieu === 'may-chu' ? `${x.n.id}@${x.n.cap_nhat_luc}` : `qh:${x.ds.map((v) => v.khoa).join(',')}`)).join('|');

function veTheMayChu(n) {
  const { chu, bien, ghiChu } = tachTieuDe(n.tieu_de);
  const khac = khacChiNhanh(n);
  const dich = khac ? null : duongDich(n);
  return h('article', { class: `tb-the loai-${n.loai}`, 'data-tb-the': 'may-chu', 'data-tb-id': n.id },
    h('div', { class: 'tb-the-dau' },
      h('span', { class: 'tb-loai' }, TEN_LOAI[n.loai] || 'Thông báo'),
      bien ? bienSo(bien) : null,
      khac ? nhanChiNhanh(n.chi_nhanh_id) : null,
      h('span', { class: 'tb-luc' }, gioBao(n.cap_nhat_luc))),
    h('h3', { class: 'tb-tieu' }, chu),
    ghiChu ? h('p', { class: 'tb-ghi-chu' }, ghiChu, ' – anh/chị nhận thay.') : null,
    n.noi_dung ? h('p', { class: 'tb-nd' }, n.noi_dung) : null,
    n.chi_tiet?.length ? h('ul', { class: 'tb-ds' }, n.chi_tiet.map((d) => h('li', null, d))) : null,
    khac ? h('p', { class: 'tb-ghi-chu' }, 'Thuộc ', h('b', null, api.tenChiNhanh(n.chi_nhanh_id)), ' – chuyển chi nhánh ở thanh menu để xem.') : null,
    S.them.has(n.id) ? h('p', { class: 'tb-them', role: 'status' }, 'Vừa có thêm nội dung mới – anh/chị xem lại rồi bấm "Đã nhận".') : null,
    S.loi.has(n.id) ? h('p', { class: 'tb-loi', role: 'alert' }, S.loi.get(n.id)) : null,
    h('div', { class: 'tb-nut' },
      h('button', { class: 'nut chinh', type: 'button', 'data-tb': 'nhan', onclick: () => nhan([n]) }, 'Đã nhận'),
      dich ? h('button', { class: 'nut noi-bat', type: 'button', 'data-tb': 'nhan-mo', onclick: () => nhan([n], dich.href) }, `Đã nhận – ${dich.nhan}`) : null));
}

function veTheQuaHan(ds) {
  const toiDa = 8;
  return h('article', { class: 'tb-the loai-qua-han', 'data-tb-the': 'qua-han' },
    h('div', { class: 'tb-the-dau' },
      h('span', { class: 'tb-loai' }, 'Nhắc quá hạn'),
      h('span', { class: 'tb-luc' }, `Tính lúc ${gioBao(Date.now())}`)),
    h('h3', { class: 'tb-tieu' }, ds.length === 1 ? 'Có 1 việc của anh/chị đã quá hạn' : `Có ${ds.length} việc của anh/chị đã quá hạn`),
    h('ul', { class: 'tb-ds-qh' }, ds.slice(0, toiDa).map((v) => h('li', null,
      v.bien ? bienSo(v.bien) : h('b', { class: 'tb-nhan-dau' }, v.nhan),
      h('span', { class: 'tb-viec' }, h('b', null, v.ten), v.phu ? h('small', null, v.phu) : null),
      h('span', { class: 'nhan qua-han' }, chuHan(new Date(v.han)))))),
    ds.length > toiDa ? h('p', { class: 'tb-ghi-chu' }, `… và ${ds.length - toiDa} việc khác (xem đủ ở Việc hôm nay).`) : null,
    h('div', { class: 'tb-nut' },
      h('button', { class: 'nut chinh', type: 'button', 'data-tb': 'biet', onclick: () => biet(ds) }, 'Đã biết'),
      h('button', { class: 'nut noi-bat', type: 'button', 'data-tb': 'biet-mo', onclick: () => biet(ds, '#/viec') }, 'Đã biết – xem Việc hôm nay')),
    h('p', { class: 'tb-ghi-chu tb-nhac-lai' }, 'Việc nào chưa xong sẽ được nhắc lại sau 4 giờ.'));
}

function go() {
  S.lop?.remove();
  S.lop = null;
}

function tieuDeHop(the) {
  if (the.every((x) => x.kieu === 'qua-han')) return 'Nhắc việc quá hạn';
  return the.length > 1 ? `Có ${the.length} thông báo mới` : 'Thông báo mới';
}

function veLai() {
  if (!S.chay) { go(); return; }
  const the = danhSachThe();
  if (!the.length || Date.now() < S.anDen) { go(); return; }
  const moiHien = !S.lop;
  const cuonCu = S.lop?.querySelector('.tb-than')?.scrollTop || 0;
  if (!S.lop) {
    S.lop = h('div', { class: 'tb-nen', role: 'alertdialog', 'aria-modal': 'true', 'aria-labelledby': 'tb-tieu-de', 'data-tb': 'khung' });
    document.body.append(S.lop);
  }
  const tong = the.length;
  const dsThe = h('div', { class: 'tb-than' }, the.map((x) => (x.kieu === 'may-chu' ? veTheMayChu(x.n) : veTheQuaHan(x.ds))));
  S.lop.replaceChildren(h('div', { class: 'tb-hop', tabindex: '-1' },
    h('div', { class: 'tb-dau' },
      h('span', { class: 'tb-chuong', 'aria-hidden': 'true' }, icon('chuong')),
      h('h2', { id: 'tb-tieu-de' }, tieuDeHop(the))),
    dsThe,
    tong > 1 || S.loi.size ? h('div', { class: 'tb-chan' },
      tong > 1 ? h('button', { class: 'nut chinh rong', type: 'button', 'data-tb': 'nhan-tat-ca', onclick: nhanTatCa }, `Đã nhận tất cả (${tong})`) : null,
      S.loi.size ? h('button', { class: 'nut-chu', type: 'button', 'data-tb': 'an-tam', onclick: anTam }, 'Tạm ẩn khung 10 phút (chỉ dùng khi không nhận được)') : null) : null));
  dsThe.scrollTop = cuonCu;
  // Đang gõ dở ở ô nào thì để yên con trỏ ở đó; chưa gõ gì thì đưa tiêu điểm vào khung cho trình đọc màn hình đọc to
  const dangGo = document.activeElement;
  if (moiHien && (!dangGo || dangGo === document.body)) S.lop.querySelector('.tb-hop')?.focus({ preventScroll: true });
}

// ---------- Thao tác ----------
// Bấm "Đã nhận": máy chủ ghi lúc nhận, và chỉ ghi đúng BẢN ĐANG HIỆN (so_lan): nếu giữa chừng thông báo vừa được gộp thêm dòng mới thì cái đó
// chưa tính là nhận – thẻ ở lại, hiện ghi chú "Vừa có thêm nội dung mới" để người nhận đọc rồi bấm lại.
// Lỗi / quá chậm (mạng…) thì giữ nguyên khung và báo ngay trên thẻ.
// Trả về false nếu chưa gửi được lên máy chủ; true nếu gửi được (kể cả khi còn thẻ vừa có nội dung mới).
async function nhan(dsN, dich = null) {
  const ids = dsN.map((n) => n.id);
  let xong;
  try {
    xong = await choToiDa(api.nhanThongBao(ids, dsN.map((n) => n.so_lan)), HET_GIO_NHAN_MS);
  } catch (e) {
    console.warn('Thông báo – ghi nhận "Đã nhận" lỗi:', e);
    for (const n of dsN) S.loi.set(n.id, 'Chưa ghi nhận được (mạng chậm hoặc mất kết nối) – bấm lại để thử lần nữa.');
    veLai();
    return false;
  }
  const da = new Set(Array.isArray(xong) ? xong.map(Number) : ids);          // máy chủ không trả danh sách: coi như nhận hết
  const con = ids.filter((id) => !da.has(id));
  for (const id of ids) S.loi.delete(id);
  for (const id of da) { S.daNhan.add(id); S.daThay.delete(id); S.them.delete(id); }
  S.ds = S.ds.filter((n) => !da.has(n.id));
  capNhatSo();
  const conCho = con.length ? await lamMoiNgay(con) : [];
  if (!con.length) veLai();
  if (dich && !conCho.length) location.hash = dich;
  return true;
}

// Có thông báo vừa được thêm nội dung (hoặc đã nhận ở máy khác) trong lúc người dùng bấm: hỏi lại máy chủ ngay để thẻ hiện đúng nội dung mới
async function lamMoiNgay(con) {
  for (const id of con) S.them.add(id);
  veLai();
  const phien = S.phien;
  try {
    const ds = await choToiDa(api.thongBaoChuaNhan(), HET_GIO_HOI_MS);
    if (phien !== S.phien) return [];
    const con2 = new Set((ds || []).map((n) => n.id));
    for (const id of con) if (!con2.has(id)) { S.them.delete(id); S.daNhan.add(id); S.daThay.delete(id); }   // đã nhận từ trước hoặc ở máy khác
    capNhatTuMayChu(ds || []);
  } catch (e) {
    console.warn('Thông báo – hỏi lại sau khi nhận lỗi (lượt hỏi sau sẽ cập nhật):', e);
  }
  return con.filter((id) => S.them.has(id));
}

async function nhanTatCa() {
  const may = S.ds.slice(); const qh = quaHanChuaBiet();
  if (may.length && !(await nhan(may))) return;
  if (qh.length) biet(qh);
}

function biet(ds, dich = null) {
  const den = Date.now() + NHAC_LAI_MS;
  const nho = docNho();
  for (const v of ds) { nho[v.khoa] = den; S.nhoTam[v.khoa] = den; }
  ghiNho(nho);
  veLai();
  if (dich) location.hash = dich;
}

function anTam() {
  S.anDen = Date.now() + AN_TAM_MS;
  go();
}

// ---------- Tiêu đề thẻ trình duyệt, mục menu ----------
function mucMenu() { return document.querySelector('.menu-ds a[data-duong="thong-bao"]'); }
function capNhatSo() {
  const n = S.ds.length;
  document.title = (n ? `(${n}) ` : '') + TIEU_DE_GOC;
  const b = mucMenu()?.querySelector('.tb-dem');
  if (b) { b.textContent = String(n); b.hidden = !n; }
}
function hienMucMenu(co) { const a = mucMenu(); if (a) a.hidden = !co; }

// ---------- Hỏi máy chủ ----------
function baoMoi(chiTietMoi) {
  try { navigator.vibrate?.([180, 90, 180]); } catch { /* máy không rung được */ }
  // Trang đang mở (vd Việc hôm nay của trưởng nhóm) tự tải lại để thấy ngay việc mới
  if (!chiTietMoi.lanDau) window.dispatchEvent(new CustomEvent('gara:thong-bao-moi', { detail: chiTietMoi }));
}

function capNhatTuMayChu(ds) {
  const moi = ds.filter((n) => !S.daNhan.has(n.id));
  const gan = new Map();
  let coMoi = false;
  for (const n of moi) {
    gan.set(n.id, n.cap_nhat_luc);
    if (S.daThay.get(n.id) !== n.cap_nhat_luc) coMoi = true;
  }
  for (const id of [...S.loi.keys()]) if (!gan.has(id)) S.loi.delete(id);
  S.daThay = gan;
  const doi = chuKy(moi.map((n) => ({ kieu: 'may-chu', n }))) !== chuKy(S.ds.map((n) => ({ kieu: 'may-chu', n })));
  S.ds = moi;
  const lanDau = S.lanDau; S.lanDau = false;
  capNhatSo();
  if (doi || !S.lop) veLai();
  if (coMoi) baoMoi({ lanDau });
}

async function hoi() {
  if (S.dangHoi || !S.khaDung) return;
  S.dangHoi = true;
  const phien = S.phien;
  try {
    const ds = await choToiDa(api.thongBaoChuaNhan(), HET_GIO_HOI_MS);
    if (phien !== S.phien) return;
    if (!S.daCoBang) { S.daCoBang = true; hienMucMenu(true); }
    capNhatTuMayChu(ds || []);
  } catch (e) {
    if (phien !== S.phien) return;
    if (api.thongBaoThieuBang(e)) { S.khaDung = false; hienMucMenu(false); return; }   // máy chủ chưa chạy 054: thôi, không báo lỗi
    if (!S.daBaoLoi) { S.daBaoLoi = true; console.warn('Thông báo – hỏi máy chủ lỗi (sẽ thử lại):', e); }
  } finally {
    S.dangHoi = false;
  }
}

// Tính lại việc quá hạn khi trang Việc hôm nay chưa gửi sang (đang ở trang khác) – tối đa 30 phút một lần, lúc thẻ đang hiện
async function kiemQuaHan() {
  if (!S.tai || S.dangTaiQuaHan || document.hidden) return;
  const bay = Date.now();
  if (bay - S.batDauLuc < (window.__QUA_HAN_SAU_MS ?? 20000) || bay - S.lanQuaHan < TINH_LAI_QUA_HAN_MS) return;
  S.dangTaiQuaHan = true;
  const phien = S.phien;
  try {
    const ds = await choToiDa(S.tai(), HET_GIO_QUA_HAN_MS);
    if (phien !== S.phien) return;
    S.quaHanTho = ds || []; S.lanQuaHan = Date.now();
  } catch (e) {
    console.warn('Nhắc quá hạn – tính lại lỗi (thử lại sau 5 phút):', e);
    S.lanQuaHan = Date.now() - TINH_LAI_QUA_HAN_MS + 5 * 60e3;
  } finally {
    S.dangTaiQuaHan = false;
  }
}

const chuKyHoi = () => (S.khaDung ? Number(window.__HOI_TB_MS) || HOI_MS : HOI_KHI_THIEU_BANG_MS);
async function vong() {
  clearTimeout(S.timer);
  if (!S.chay) return;
  const phien = S.phien;
  try {
    await hoi();
    await kiemQuaHan();
    if (phien === S.phien && !S.lop) veLai();               // hết giờ "tạm ẩn" hoặc việc quá hạn mới tính xong
  } finally {
    if (S.chay && phien === S.phien) { clearTimeout(S.timer); S.timer = setTimeout(vong, chuKyHoi()); }   // luôn chỉ một hẹn giờ đang chờ
  }
}
function hoiNgay() {
  if (!S.chay) return;
  clearTimeout(S.timer);
  S.timer = setTimeout(vong, 50);
}
const khiHienLai = () => { if (document.visibilityState === 'visible') hoiNgay(); };
const nhanQuaHanTuTrang = (e) => {
  S.quaHanTho = Array.isArray(e.detail) ? e.detail : [];
  S.lanQuaHan = Date.now();
  if (S.chay) veLai();
};

// ---------- Bật / tắt theo phiên đăng nhập ----------
export function batDau({ taiQuaHan = null } = {}) {
  dung();
  if (window.__TAT_THONG_BAO) return;
  if (!api.toi || !(api.laNhanVien() || api.coVaiTro('truong_nhom'))) return;      // cổ đông và tài khoản chưa có vai trò: không có thông báo
  S.chay = true; S.tai = taiQuaHan; S.batDauLuc = Date.now();
  window.addEventListener('gara:viec-qua-han', nhanQuaHanTuTrang);
  document.addEventListener('visibilitychange', khiHienLai);
  window.addEventListener('online', hoiNgay);
  S.timer = setTimeout(vong, 300);
}

export function dung() {
  clearTimeout(S.timer);
  window.removeEventListener('gara:viec-qua-han', nhanQuaHanTuTrang);
  document.removeEventListener('visibilitychange', khiHienLai);
  window.removeEventListener('online', hoiNgay);
  S.phien++; S.chay = false; S.khaDung = true; S.daCoBang = false; S.lanDau = true; S.dangHoi = false; S.daBaoLoi = false;
  S.ds = []; S.daNhan = new Set(); S.daThay = new Map(); S.loi = new Map(); S.them = new Set();
  S.quaHanTho = []; S.nhoTam = {}; S.lanQuaHan = 0; S.dangTaiQuaHan = false; S.tai = null; S.anDen = 0;
  go();
  document.title = TIEU_DE_GOC;
}
