// Công cụ dựng giao diện dùng chung (không cần thư viện ngoài)

// h('div', {class:'the', onclick: fn}, 'chữ', con, [mảng con]) → phần tử DOM
export function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'onclick' && tag === 'button' && typeof v === 'function') {
        // Chống bấm hai lần: nút tự khóa trong lúc thao tác đang chạy
        el.addEventListener('click', (e) => {
          if (el.dataset.dangChay) return;
          const kq = v(e);
          if (kq && typeof kq.then === 'function') {
            el.dataset.dangChay = '1'; el.disabled = true;
            const mo = () => { delete el.dataset.dangChay; el.disabled = false; };
            kq.then(mo, mo);
          }
        });
      } else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (k === 'class') el.className = v;
      else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else if (k === 'html') el.innerHTML = v;
      else if (v === true) el.setAttribute(k, '');
      else el.setAttribute(k, v);
    }
  }
  themCon(el, children);
  return el;
}
function themCon(el, children) {
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    if (Array.isArray(c)) themCon(el, c);
    else el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
}
// Thay toàn bộ nội dung phần tử; bỏ qua null/false, trải phẳng mảng
export function dat(el, ...con) { el.replaceChildren(); themCon(el, con); return el; }
export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

// ---------- Định dạng ----------
export function tien(n) {
  if (n === null || n === undefined || n === '') return '';
  const so = Math.round(Number(n));
  return (so < 0 ? '−' : '') + Math.abs(so).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}
export function docTien(s) {
  if (s === null || s === undefined) return null;
  const chi = String(s).replace(/[^\d-]/g, '');
  return chi === '' || chi === '-' ? null : Number(chi);
}
const hai = (x) => String(x).padStart(2, '0');
export function ngay(d) {
  if (!d) return '';
  const t = typeof d === 'string' && d.length === 10 ? new Date(d + 'T00:00:00') : new Date(d);
  return `${hai(t.getDate())}/${hai(t.getMonth() + 1)}/${t.getFullYear()}`;
}
export function ngayGio(d) {
  if (!d) return '';
  const t = new Date(d);
  return `${hai(t.getHours())}:${hai(t.getMinutes())} ${ngay(t)}`;
}
export function homNay() {
  const t = new Date();
  return `${t.getFullYear()}-${hai(t.getMonth() + 1)}-${hai(t.getDate())}`;
}
export function cuoiThang(thang /* 'YYYY-MM' */) {
  const [y, m] = thang.split('-').map(Number);
  const t = new Date(y, m, 0);
  return `${t.getFullYear()}-${hai(t.getMonth() + 1)}-${hai(t.getDate())}`;
}
// giá trị cho ô datetime-local
export function choODatetime(d) {
  if (!d) return '';
  const t = new Date(d);
  return `${t.getFullYear()}-${hai(t.getMonth() + 1)}-${hai(t.getDate())}T${hai(t.getHours())}:${hai(t.getMinutes())}`;
}

export const TRANG_THAI = {
  tiep_nhan: 'Tiếp nhận', bao_gia: 'Chờ duyệt giá', da_duyet: 'Đã duyệt giá', dang_sua: 'Đang sửa',
  cho_kcs: 'Chờ KCS', dat_kcs: 'Đạt KCS – chờ giao', da_giao: 'Đã giao xe', da_gui_hs: 'Đã gửi hồ sơ BH',
  dong: 'Đã đóng', huy: 'Đã hủy',
};
// Nhóm hạng mục báo giá. Chọn mới: Đồng, Sơn, Phụ tùng, Detailing; "Đồng sơn", "Điện – máy – gầm" chỉ còn ở dòng cũ.
export const NHOM = { dong: 'Đồng', son: 'Sơn', phu_tung: 'Phụ tùng', detailing: 'Detailing', dong_son: 'Đồng sơn', dmg: 'Điện – máy – gầm' };
export const NHOM_CHON = ['dong', 'son', 'phu_tung', 'detailing'];
// Gộp nhóm cho báo cáo doanh thu: Đồng + Sơn tính vào "Đồng sơn"
export const NHOM_BAO_CAO = { dong_son: 'Đồng sơn', phu_tung: 'Phụ tùng', dmg: 'Điện – máy – gầm', detailing: 'Detailing' };
export const nhomBaoCao = (n) => (n === 'dong' || n === 'son' ? 'dong_son' : n);
// Nhóm hàng kho, theo thứ tự hiển thị (kho, xuất Excel)
export const NHOM_HANG = ['Sơn', 'Nhám', 'Vật tư phụ', 'Phụ tùng', 'Dầu nhớt', 'Detailing', 'Khác'];
export const NGUON = { bao_hiem: 'Bảo hiểm', khach: 'Khách ngoài bảo hiểm', bao_hiem_khach: 'Bảo hiểm + khách trả thêm' };
export const VAI_TRO = {
  giam_doc: 'Giám đốc', quan_ly: 'Quản lý chung', ke_toan: 'Kế toán', cvdv: 'CVDV',
  kho: 'Kho', truong_nhom: 'Trưởng nhóm', co_dong: 'Cổ đông',
};
export function nhanTrangThai(tt) {
  return h('span', { class: `nhan tt-${tt}` }, TRANG_THAI[tt] || tt);
}

// ---------- 9 bước của xe ----------
export const BUOC_XE = ['Tiếp nhận', 'Báo giá', 'Duyệt giá', 'Lệnh sửa chữa', 'Cấp phụ tùng – Sửa chữa', 'KCS', 'Giao xe', 'Hồ sơ BH', 'Chăm sóc'];
// Bước xe ĐANG CHỜ làm (1–9, khớp "Bước tiếp theo"); 0 = đã xong cả 9 bước; null = hồ sơ hủy.
// boQua: bước không áp dụng (khách ngoài bảo hiểm không có hồ sơ BH; hồ sơ bảo hành không báo giá, không duyệt giá – 036).
// Chăm sóc làm trước khi gửi hồ sơ BH vẫn tính xong.
export function buocXe(hs) {
  if (!hs || hs.trang_thai === 'huy') return { dang: null, boQua: [], xong: () => false };
  const boQua = hs.nguon_tt === 'khach' ? [8] : [];
  if (hs.loai === 'bao_hanh' && !['tiep_nhan', 'bao_gia'].includes(hs.trang_thai)) boQua.unshift(2, 3);
  const chamSoc = !!hs.cham_soc_luc;
  let dang;
  if (hs.tu_excel) dang = 0;
  else switch (hs.trang_thai) {
    case 'tiep_nhan': dang = 2; break;
    case 'bao_gia': dang = 3; break;
    case 'da_duyet': dang = 4; break;
    case 'dang_sua': dang = 5; break;
    case 'cho_kcs': dang = 6; break;
    case 'dat_kcs': dang = 7; break;
    case 'da_giao': dang = hs.nguon_tt !== 'khach' && !hs.gui_hs_ngay ? 8 : chamSoc ? 0 : 9; break;
    case 'da_gui_hs': case 'dong': dang = chamSoc ? 0 : 9; break;
    default: dang = 1;
  }
  const xong = (so) => !boQua.includes(so) && (dang === 0 || so < dang || (so === 9 && chamSoc));
  return { dang, boQua, xong };
}
// Thanh 9 vạch thu nhỏ: danh sách hồ sơ, thẻ xe ở bảng việc
export function thanhBuocNho(hs) {
  const { dang, boQua, xong } = buocXe(hs);
  if (dang === null) return null;
  const soXong = BUOC_XE.filter((_, i) => xong(i + 1)).length;
  const moTa = dang === 0 ? 'Đã xong cả 9 bước' : `Bước ${dang}/9: ${BUOC_XE[dang - 1]} – đã xong ${soXong} bước`;
  return h('span', { class: 'buoc-nho', role: 'img', 'aria-label': moTa, title: moTa },
    BUOC_XE.map((_, i) => h('i', { class: boQua.includes(i + 1) ? 'bo' : xong(i + 1) ? 'xong' : i + 1 === dang ? 'dang' : null })));
}

// ---------- Người đảm nhận: thẻ tên có chữ cái đầu, màu theo vai trò ----------
const UU_TIEN_VAI = ['giam_doc', 'quan_ly', 'ke_toan', 'cvdv', 'kho', 'truong_nhom', 'co_dong'];
export const vaiChinh = (vaiTro = []) => UU_TIEN_VAI.find((v) => vaiTro.includes(v)) || null;
export const tenNgan = (ten) => String(ten || '').trim().split(/\s+/).pop() || '';
export function chuDau(ten = '') {
  const t = String(ten).trim();
  const to = /^tổ\s+(\S+)/i.exec(t);
  if (to) return to[1].slice(0, 2).toUpperCase();
  return (t.split(/\s+/).pop() || '?').charAt(0).toUpperCase();
}
// chipNguoi('Nguyễn Trọng Duy', { vai: 'cvdv', gon: true }) → (D) Duy
export function chipNguoi(ten, { vai = null, gon = false, chu = null, title = null, nho = false } = {}) {
  if (!ten) return null;
  return h('span', { class: `nguoi${vai ? ` vai-${vai}` : ''}${nho ? ' nho' : ''}`, title: title || ten },
    h('span', { class: 'nguoi-av', 'aria-hidden': 'true' }, chu || chuDau(ten)),
    h('span', { class: 'nguoi-ten' }, gon ? tenNgan(ten) : ten));
}
// Hạn xử lý dạng viên: "Còn 5 giờ" (xanh), sắp tới hạn dưới 4 giờ (cam), "Quá hạn 2 giờ" (đỏ)
export function vienHan(han, chu, lop = '') {
  if (!han || !chu) return null;
  const ms = han.getTime() - Date.now();
  return h('span', { class: `han ${ms < 0 ? 'qua' : ms < 4 * 36e5 ? 'sap' : ''} ${lop}`.trim() }, chu);
}

// ---------- Biển số: vẽ như biển thật để nhận ra xe ngay ----------
export function vietBienSo(raw) {
  if (!raw) return '';
  const s = String(raw).trim().toUpperCase();
  if (/[-.\s]/.test(s)) return s;
  const m = s.match(/^([0-9]{2}[A-Z]{1,2}[0-9]?)([0-9]{3})([0-9]{2})$/) || s.match(/^([0-9]{2}[A-Z]{1,2})([0-9]{4})$/);
  if (!m) return s;
  return m[3] ? `${m[1]}-${m[2]}.${m[3]}` : `${m[1]}-${m[2]}`;
}
export function bienSo(raw, { lon = false, maThay = '' } = {}) {
  const chu = vietBienSo(raw);
  if (!chu) return h('span', { class: 'bien-so-trong' }, maThay || 'Chưa có biển');
  return h('span', { class: `bien-so${lon ? ' lon' : ''}`, translate: 'no' }, chu);
}

// ---------- Biểu tượng (SVG nét, 24px) ----------
const ICON = {
  viec: '<path d="M9 4h6v3H9z"/><path d="M15 5h2a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2"/><path d="m9 14 2 2 4-4"/>',
  xe: '<path d="M5 16V11l2-5h10l2 5v5"/><path d="M3 16h18v3H3z"/><path d="M5 11h14"/><circle cx="7.5" cy="19.5" r="1.5"/><circle cx="16.5" cy="19.5" r="1.5"/>',
  nhanh: '<path d="M13 3 5 14h6l-1 7 8-11h-6z"/>',
  quy: '<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M3 10h18"/><path d="M16 14.5h2"/>',
  phieu: '<path d="M7 3h7l4 4v14H7z"/><path d="M14 3v4h4"/><path d="M10 12h5M10 16h5"/>',
  doanhThu: '<path d="M4 20V4"/><path d="M4 20h16"/><path d="M8 16v-4M12 16V8M16 16v-6"/>',
  danhMuc: '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="5" cy="6" r="1"/><circle cx="5" cy="12" r="1"/><circle cx="5" cy="18" r="1"/>',
  nguoi: '<circle cx="9" cy="8" r="3.5"/><path d="M3 20c0-3.5 2.7-6 6-6s6 2.5 6 6"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7"/><path d="M18 14.5c1.8.8 3 2.7 3 5.5"/>',
  anh: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  them: '<path d="M12 5v14M5 12h14"/>',
  kho: '<path d="M3 8 12 4l9 4v11H3z"/><path d="M7 19v-7h10v7"/><path d="M7 15h10"/>',
  check: '<path d="m5 12.5 4.2 4.2L19 7"/>',
  // Hộp đồ nghề – mục Tài sản
  taiSan: '<path d="M3 10h18v9H3z"/><path d="M8 10V7a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v3"/><path d="M3 14h18"/><path d="M10 13v2M14 13v2"/>',
  // Xe nhìn ngang, hướng sang phải – xe đang ở bước nào trên thanh tiến độ
  xeChay: '<path d="M3 15.5v-3a1 1 0 0 1 .8-1l2.6-.6 2.4-3.3A2 2 0 0 1 10.4 6.8h4.2a2 2 0 0 1 1.6.8l2.6 3.4 1.6.4a1 1 0 0 1 .8 1v3.1"/><path d="M9.3 16h5.4"/><path d="M6.6 11h11.2"/><circle cx="6.8" cy="16.2" r="2.1"/><circle cx="17.2" cy="16.2" r="2.1"/>',
};
export function icon(ten) {
  return h('span', { class: 'ic', 'aria-hidden': 'true',
    html: `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICON[ten] || ''}</svg>` });
}

// Ô nhập có danh sách gợi ý thả xuống (gõ tới đâu gợi ý tới đó).
// tim(chuoi) -> Promise<mục[]>; ve(mục) -> nội dung một dòng; chon(mục) khi bấm hoặc Enter.
let soGoiY = 0;
export function oGoiY(input, { tim, ve, chon, choMs = 200 }) {
  const id = `goi-y-${++soGoiY}`;
  const ds = h('ul', { class: 'goi-y-ds', role: 'listbox', id, hidden: true });
  input.setAttribute('role', 'combobox');
  input.setAttribute('aria-autocomplete', 'list');
  input.setAttribute('aria-controls', id);
  input.setAttribute('aria-expanded', 'false');
  input.setAttribute('autocomplete', 'off');
  let muc = []; let dangChon = -1; let hen = null; let lan = 0;
  const dong = () => { ds.hidden = true; input.setAttribute('aria-expanded', 'false'); input.removeAttribute('aria-activedescendant'); dangChon = -1; };
  const danhDau = () => {
    [...ds.children].forEach((li, i) => li.setAttribute('aria-selected', String(i === dangChon)));
    if (dangChon >= 0) { input.setAttribute('aria-activedescendant', `${id}-${dangChon}`); ds.children[dangChon].scrollIntoView({ block: 'nearest' }); }
  };
  const lay = (m) => { dong(); chon(m); };
  async function tai() {
    const so = ++lan;
    let kq = [];
    try { kq = await tim(input.value); } catch { kq = []; }
    if (so !== lan) return; // đã gõ tiếp, bỏ kết quả cũ
    muc = kq;
    dat(ds, muc.map((m, i) => h('li', { role: 'option', id: `${id}-${i}`, 'aria-selected': 'false',
      onmousedown: (e) => e.preventDefault(), onclick: () => lay(m) }, ve(m))));
    if (muc.length && document.activeElement === input) { ds.hidden = false; input.setAttribute('aria-expanded', 'true'); dangChon = -1; } else dong();
  }
  input.addEventListener('input', () => { clearTimeout(hen); hen = setTimeout(tai, choMs); });
  input.addEventListener('keydown', (e) => {
    if (ds.hidden) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); dangChon = Math.min(muc.length - 1, dangChon + 1); danhDau(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); dangChon = Math.max(0, dangChon - 1); danhDau(); }
    else if (e.key === 'Enter' && dangChon >= 0) { e.preventDefault(); lay(muc[dangChon]); }
    else if (e.key === 'Escape') { dong(); }
  });
  input.addEventListener('blur', () => setTimeout(dong, 150));
  return h('div', { class: 'o-goi-y' }, input, ds);
}

// Nút chọn/chụp ảnh to, dễ bấm; ô file thật nằm ẩn bên trong để vẫn dùng bàn phím và trình đọc màn hình được
export function oChonTep(attrs = {}, nhan = 'Chụp hoặc chọn ảnh') {
  const input = h('input', { type: 'file', accept: 'image/*', ...attrs });
  const dem = h('span', { class: 'chon-tep-dem' }, 'Chưa có ảnh');
  input.addEventListener('change', () => { dem.textContent = input.files.length ? `Đã chọn ${input.files.length} ảnh` : 'Chưa có ảnh'; });
  const nhanEl = h('label', { class: 'chon-tep' }, input, icon('anh'), h('span', null, nhan), dem);
  nhanEl.input = input;
  return nhanEl;
}

// ---------- Thông báo ----------
export function toast(msg, loai = 'ok', giuMs = null) {
  let khung = $('#toast');
  if (!khung) { khung = h('div', { id: 'toast', role: 'status', 'aria-live': 'polite' }); document.body.append(khung); }
  const el = h('div', { class: `toast ${loai}` }, msg);
  khung.append(el);
  setTimeout(() => el.remove(), giuMs || (loai === 'loi' ? 7000 : 3500));
  return el;
}

// Ghi nhớ trong phiên làm việc (tab trình duyệt); lỗi bộ nhớ thì bỏ qua
export const nhoPhien = {
  doc(k) { try { return JSON.parse(sessionStorage.getItem(k)); } catch { return null; } },
  ghi(k, v) { try { sessionStorage.setItem(k, JSON.stringify(v)); } catch { /* bỏ qua */ } },
  xoa(k) { try { sessionStorage.removeItem(k); } catch { /* bỏ qua */ } },
};

// Lưu xong một thao tác của hồ sơ: về danh sách "Hồ sơ xe" (đúng tab đang xem),
// dòng vừa lưu được tô vàng, thông báo có nút mở lại hồ sơ.
export function veDanhSachHoSo(hs) {
  nhoPhien.ghi('hs_vua_luu', hs.id);
  const mo = h('a', { class: 'toast-mo', href: `#/ho-so/${hs.id}` }, `Mở lại hồ sơ ${hs.ma || ''}`.trim());
  $$('#toast .toast.loi').forEach((x) => x.remove()); // lưu được rồi thì bỏ các báo lỗi cũ
  const cu = $('#toast')?.querySelector('.toast.ok:last-child');
  const noiDung = cu ? cu.textContent : 'Đã lưu.';
  cu?.remove();
  toast(h('span', null, noiDung, ' ', mo), 'ok', 7000);
  const dich = nhoPhien.doc('hs_ds') || '#/ho-so';
  if (location.hash === dich) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = dich;
}

// ---------- Hộp thoại ----------
export function moModal(tieuDe, noiDung, { nutChinh, nhanNut = 'Lưu', nutPhu = 'Đóng', rong = false, khiDong } = {}) {
  const nen = h('div', { class: 'modal-nen' });
  const dong = () => { if (!nen.isConnected) return; nen.remove(); document.removeEventListener('keydown', phim); if (khiDong) khiDong(); };
  const phim = (e) => { if (e.key === 'Escape') dong(); };
  document.addEventListener('keydown', phim);
  const nut = nutChinh ? h('button', { class: 'nut chinh', type: 'button' }, nhanNut) : null;
  const hop = h('div', { class: `modal ${rong ? 'rong' : ''}`, role: 'dialog', 'aria-modal': 'true', 'aria-label': tieuDe },
    h('div', { class: 'modal-dau' }, h('h2', null, tieuDe), h('button', { class: 'nut-x', type: 'button', 'aria-label': 'Đóng', onclick: dong }, '×')),
    h('div', { class: 'modal-than' }, noiDung),
    h('div', { class: 'modal-chan' }, h('button', { class: 'nut', type: 'button', onclick: dong }, nutPhu), nut));
  if (nut) nut.addEventListener('click', async () => {
    nut.disabled = true;
    try { const ok = await nutChinh(); if (ok !== false) dong(); }
    catch (e) { if (!e?.daHuy) baoLoi(e); }
    finally { nut.disabled = false; }
  });
  nen.addEventListener('click', (e) => { if (e.target === nen) dong(); });
  nen.append(hop);
  document.body.append(nen);
  const dau = hop.querySelector('input,select,textarea');
  // Chỉ tự đặt con trỏ khi người dùng chưa bấm vào ô nào trong hộp thoại (tránh gõ nhầm sang ô khác)
  if (dau) setTimeout(() => { if (!hop.contains(document.activeElement)) dau.focus(); }, 50);
  return dong;
}

export function xacNhan(cauHoi, nhan = 'Đồng ý') {
  return new Promise((ok) => {
    let traLoi = false;
    moModal('Xác nhận', h('p', null, cauHoi), {
      nhanNut: nhan, nutPhu: 'Không',
      nutChinh: () => { traLoi = true; ok(true); },
      khiDong: () => { if (!traLoi) ok(false); },
    });
  });
}

export function baoLoi(e) {
  const msg = (e && (e.message || e.error_description)) || String(e);
  if (e && typeof e === 'object') e.daBao = true;   // đã hiện cho người dùng – nơi khác không báo lại
  console.warn(e);
  toast(msg.replace(/^CANH_BAO:\s*/, ''), 'loi');
}

// Chạy một thao tác ghi. Nếu máy chủ trả cảnh báo (CANH_BAO:), hỏi lại rồi chạy lại với coCanhBao = true.
export async function chay(fn, { thanhCong } = {}) {
  try {
    const kq = await fn(false);
    if (thanhCong) toast(thanhCong);
    return kq;
  } catch (e) {
    const msg = e?.message || '';
    if (msg.startsWith('CANH_BAO:')) {
      if (await xacNhan(msg.replace(/^CANH_BAO:\s*/, ''), 'Vẫn tiếp tục')) {
        try {
          const kq = await fn(true);
          if (thanhCong) toast(thanhCong);
          return kq;
        } catch (e2) { baoLoi(e2); throw e2; }
      }
      const huy = new Error('Đã hủy'); huy.daHuy = true;
      throw huy;
    }
    baoLoi(e);
    throw e;
  }
}

// ---------- Ô nhập ----------
// Bề rộng ô trong lưới .luoi-o theo loại dữ liệu (app.css): ngan – biển số, màu, số lượng; vua – SĐT, ngày, tiền; lon – tên, nội dung; rong – cả hàng
const TEN_NGAN = /^(bien_so|mau|so_luong|sl|don_vi|nam|so_km|km|ty_le|ty_le_vat|ma|ma_hang|so_phieu|so_hoa_don|so_seri|stt)$/;
const TEN_VUA = /(dien_thoai|sdt|so_tai_khoan|^ngay|_ngay|ngay_|han_|_han$|^gio|tien|gia$|^gia_|thang|ky_chi_phi|^vat|hoa_hong|so_du|phan_tram)/;
const TEN_LON = /^(ten|ten_khach|ho_ten|ten_dang_nhap|noi_dung|dia_chi|nguoi_nhan|email|nha_cung_cap_id|muc_id|ho_so_id|gdv_id|don_vi_lien_quan_id)$/;
function coTuDong(input) {
  if (!input || !input.tagName) return '';
  if (input.tagName === 'TEXTAREA') return 'rong';
  const cls = input.classList;
  if (cls.contains('o-ngay-gio-khung')) return 'ngay-gio';
  if (cls.contains('chon-tep') || cls.contains('chon-nut')) return 'rong';
  const o = ['INPUT', 'SELECT'].includes(input.tagName) ? input : input.querySelector?.('input, select, textarea');
  if (!o) return '';
  if (o.tagName === 'TEXTAREA') return 'rong';
  if (o.type === 'checkbox' || o.type === 'radio' || o.type === 'file') return '';
  const name = o.name || '';
  if (o.classList.contains('o-tien') || o.type === 'date' || o.type === 'month' || o.classList.contains('o-ngay-vn')) return 'vua';
  if (TEN_NGAN.test(name)) return 'ngan';
  if (TEN_VUA.test(name)) return 'vua';
  if (TEN_LON.test(name)) return 'lon';
  return '';
}
export function truong(nhan, input, goiY, { batBuoc = false, rong = false, co = '' } = {}) {
  // Ô đã là <label> (nút chọn ảnh) hoặc chứa label (nhóm nút chọn) thì khung ngoài dùng <div> để không lồng label
  const tag = input?.tagName === 'LABEL' || input?.querySelector?.('label') ? 'div' : 'label';
  const be = rong ? 'rong' : (co || coTuDong(input));
  // Ô bắt buộc (*) gắn lớp bb: viền đậm, nền ấm – nổi hơn ô không bắt buộc
  return h(tag, { class: `truong ${be === 'rong' ? 'rong' : be ? `co-${be}` : ''}${batBuoc ? ' bb' : ''}` },
    h('span', { class: 'truong-nhan' }, nhan, batBuoc ? h('b', { class: 'bat-buoc', 'aria-hidden': 'true' }, ' *') : null),
    input,
    goiY ? h('small', { class: 'goi-y' }, goiY) : null);
}
export function oChu(name, value = '', attrs = {}) {
  return h('input', { type: 'text', name, value: value ?? '', ...attrs });
}
// Ô tiền: tự chèn dấu chấm ngàn, giữ đúng vị trí con trỏ theo SỐ CHỮ SỐ trước con trỏ (không theo ký tự),
// tự xử lý gõ số / xóa (beforeinput) để bàn phím điện thoại không bị nhân đôi số và Backspace xóa được số đứng trước dấu chấm.
export function oTien(name, value, attrs = {}) {
  const el = h('input', { type: 'text', inputmode: 'numeric', name, class: 'o-tien', autocomplete: 'off', ...attrs });
  el.value = value === null || value === undefined ? '' : tien(value);
  const chuSo = (s) => s.replace(/\D/g, '');
  const am = () => /^[-−]/.test(el.value);
  // Đặt lại giá trị từ chuỗi chữ số, con trỏ đứng sau n chữ số
  const dat_ = (so, n, laAm) => {
    const moi = so === '' ? '' : (laAm ? '−' : '') + tien(Number(so));
    if (el.value !== moi) el.value = moi;
    let p = moi.length;
    if (n <= 0) p = laAm && moi ? 1 : 0;
    else { let dem = 0; for (let i = 0; i < moi.length; i++) { if (/\d/.test(moi[i])) { dem++; if (dem === n) { p = i + 1; break; } } } }
    try { el.setSelectionRange(p, p); } catch { /* bỏ qua */ }
  };
  // Tự xử lý xong thì vẫn phát 'input' để các chỗ khác (tính tổng…) nghe được
  const datVaBao = (so, n, laAm) => { dat_(so, n, laAm); el.dispatchEvent(new Event('input', { bubbles: true })); };
  let tuXuLy = false;
  el.addEventListener('beforeinput', (e) => {
    const loai = e.inputType || '';
    const dau = el.selectionStart ?? el.value.length; const cuoi = el.selectionEnd ?? dau;
    const truoc = chuSo(el.value.slice(0, dau)); const chon = chuSo(el.value.slice(dau, cuoi)); const sau = chuSo(el.value.slice(cuoi));
    if (loai === 'insertText' && e.data) {
      if (!/^\d+$/.test(e.data)) { e.preventDefault(); return; }       // chỉ nhận chữ số
      e.preventDefault(); tuXuLy = true;
      datVaBao((truoc + e.data + sau).replace(/^0+(?=\d)/, ''), truoc.length + e.data.length, am());
    } else if (loai === 'deleteContentBackward') {
      e.preventDefault(); tuXuLy = true;
      if (chon) datVaBao(truoc + sau, truoc.length, am());
      else if (truoc) datVaBao(truoc.slice(0, -1) + sau, truoc.length - 1, am());
      else if (am()) datVaBao(sau, 0, false);
      else tuXuLy = false;
    } else if (loai === 'deleteContentForward') {
      e.preventDefault(); tuXuLy = true;
      if (chon) datVaBao(truoc + sau, truoc.length, am());
      else datVaBao(truoc + sau.slice(1), truoc.length, am());
    }
    // dán, kéo thả, bàn phím gõ kiểu ghép (composition): để trình duyệt làm rồi chỉnh lại ở 'input'
  });
  // Bộ gõ kiểu ghép (bàn phím Tiếng Việt của Windows, một số bàn phím điện thoại): đang ghép thì KHÔNG đụng vào ô,
  // ghép xong mới chỉnh lại – nếu sửa giữa chừng bộ gõ sẽ chèn lại chữ, thành gõ 1 ra 2
  let dangGhep = false;
  const chinhLai = () => {
    const dau = el.selectionStart ?? el.value.length;
    const n = chuSo(el.value.slice(0, dau)).length;
    dat_(chuSo(el.value).replace(/^0+(?=\d)/, ''), n, am());
  };
  el.addEventListener('compositionstart', () => { dangGhep = true; });
  el.addEventListener('compositionend', () => { dangGhep = false; chinhLai(); el.dispatchEvent(new Event('input', { bubbles: true })); });
  el.addEventListener('input', (e) => {
    if (tuXuLy) { tuXuLy = false; return; }
    if (dangGhep || e.isComposing) return;
    chinhLai();
  });
  return el;
}
export function oNgay(name, value, attrs = {}) {
  return h('input', { type: 'date', name, value: value || '', ...attrs });
}
// Ô ngày luôn hiện dd/mm/yyyy (ô date của trình duyệt đổi theo ngôn ngữ máy, dễ nhập nhầm tháng/ngày)
// Gõ liền 8 số (01032027) cũng được: tự chèn dấu /. docForm trả về yyyy-mm-dd.
export function isoSangVN(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}
export function vnSangIso(s) {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec((s || '').trim());
  if (!m) return null;
  const [d, t, n] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const x = new Date(n, t - 1, d);
  if (x.getFullYear() !== n || x.getMonth() !== t - 1 || x.getDate() !== d) return null;
  return `${n}-${String(t).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}
export function oNgayVN(name, isoValue, attrs = {}) {
  const el = h('input', { type: 'text', name, inputmode: 'numeric', placeholder: 'dd/mm/yyyy', maxlength: 10, autocomplete: 'off',
    class: 'o-ngay-vn', ...attrs });
  el.value = isoSangVN(isoValue);
  el.addEventListener('input', (e) => {
    if (e.inputType && e.inputType.startsWith('delete')) return;
    const so = el.value.replace(/\D/g, '').slice(0, 8);
    el.value = [so.slice(0, 2), so.slice(2, 4), so.slice(4)].filter(Boolean).join('/');
  });
  el.addEventListener('blur', () => { el.setCustomValidity(el.value && !vnSangIso(el.value) ? 'Ngày không đúng (dd/mm/yyyy)' : ''); });
  return el;
}
// Ô ngày giờ 24h: ngày dd/mm/yyyy + chọn giờ (00–23) + phút. Giá trị đọc ra (el.value, docForm) dạng yyyy-mm-ddThh:mm, trống nếu chưa chọn ngày.
export function oNgayGioVN(name, value, { batBuoc = false } = {}) {
  const t = value ? new Date(value) : null;
  const an = h('input', { type: 'hidden', name, class: 'o-ngay-gio', value: t ? choODatetime(t) : '' });
  const oNgay_ = oNgayVN('', t ? `${t.getFullYear()}-${hai(t.getMonth() + 1)}-${hai(t.getDate())}` : '', { 'aria-label': 'Ngày', 'data-phan': 'ngay' });
  oNgay_.removeAttribute('name');
  const gio = h('select', { 'aria-label': 'Giờ', 'data-phan': 'gio' }, Array.from({ length: 24 }, (_, i) => h('option', { value: hai(i), selected: t && t.getHours() === i }, hai(i))));
  const dsPhut = [...new Set([...Array.from({ length: 12 }, (_, i) => i * 5), ...(t ? [t.getMinutes()] : [])])].sort((a, b) => a - b);
  const phut = h('select', { 'aria-label': 'Phút', 'data-phan': 'phut' }, dsPhut.map((m) => h('option', { value: hai(m), selected: t ? t.getMinutes() === m : m === 0 }, hai(m))));
  const capNhat = () => {
    const iso = vnSangIso(oNgay_.value);
    an.value = iso ? `${iso}T${gio.value}:${phut.value}` : '';
    an.dispatchEvent(new Event('change', { bubbles: true }));
  };
  for (const o of [oNgay_, gio, phut]) o.addEventListener('change', capNhat);
  oNgay_.addEventListener('input', capNhat);
  if (batBuoc) oNgay_.required = true;
  return h('span', { class: 'o-ngay-gio-khung' }, an, oNgay_, gio, h('span', { class: 'hai-cham' }, ':'), phut);
}
export function oChon(name, options, value, { trong = '— Chọn —', ...attrs } = {}) {
  const el = h('select', { name, ...attrs },
    trong !== null ? h('option', { value: '' }, trong) : null,
    options.map((o) => h('option', { value: o.value, selected: String(o.value) === String(value ?? '') }, o.label)));
  return el;
}
export function oVung(name, value = '', attrs = {}) {
  const el = h('textarea', { name, rows: 2, ...attrs });
  el.value = value ?? '';
  return el;
}
export function oCheck(name, checked, nhan) {
  return h('label', { class: 'o-check' }, h('input', { type: 'checkbox', name, checked: !!checked }), ' ', nhan);
}

// Đọc form: ô tiền tự đổi về số; ô trống → null
export function docForm(form) {
  const kq = {};
  for (const el of form.elements) {
    if (!el.name || el.disabled) continue;
    if (el.type === 'checkbox') { kq[el.name] = el.checked; continue; }
    if (el.type === 'radio') { if (el.checked) kq[el.name] = el.value; continue; }
    let v = el.value.trim();
    if (el.classList.contains('o-tien')) kq[el.name] = docTien(v);
    else if (el.classList.contains('o-ngay-vn')) kq[el.name] = v === '' ? null : (vnSangIso(v) || 'sai');
    else kq[el.name] = v === '' ? null : v;
  }
  return kq;
}

// Hàng thẻ dài hơn màn hình (điện thoại): cuộn ngang cho thẻ đang chọn nằm giữa, không bị che
export function cuonTheChon(tabs) {
  requestAnimationFrame(() => {
    const b = tabs?.querySelector('[aria-selected="true"]');
    if (!b || tabs.scrollWidth <= tabs.clientWidth) return;
    const lech = b.getBoundingClientRect().left - tabs.getBoundingClientRect().left + tabs.scrollLeft;
    tabs.scrollLeft = Math.max(0, lech - (tabs.clientWidth - b.offsetWidth) / 2);
  });
}

// Dải thẻ (tab) dùng chung: ds = [[ma, nhan], …]; chon(ma) chạy khi bấm thẻ khác.
// Giữ role="tab", data-ma, aria-selected; thẻ đang chọn luôn nằm trong tầm nhìn (điện thoại).
export function thanhThe(ds, dangChon, chon, { nho = false, nhan = null } = {}) {
  const tabs = h('div', { class: nho ? 'tabs nho' : 'tabs', role: 'tablist', 'aria-label': nhan },
    ds.map(([ma, chu]) => h('button', { type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === dangChon),
      onclick: () => { tabs.danhDau(ma); chon(ma); } }, chu)));
  tabs.danhDau = (ma) => { for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === ma)); cuonTheChon(tabs); };
  return tabs;
}

// Hộp hỏi lý do (hủy, từ chối, treo…): bắt buộc ghi; lam(lyDo) chạy khi bấm nút chính, lỗi thì hộp vẫn mở để sửa
export function hoiLyDo(tieuDe, lam, { nhan = 'Lý do', goiY = null, nhanNut = 'Xác nhận', placeholder = '', moTa = null } = {}) {
  const o = oVung('ly_do', '', { placeholder, rows: 3 });
  return moModal(tieuDe, h('form', { onsubmit: (e) => e.preventDefault() }, moTa ? h('p', null, moTa) : null, truong(nhan, o, goiY, { batBuoc: true })), {
    nhanNut,
    nutChinh: async () => {
      const lyDo = o.value.trim();
      if (!lyDo) { toast(`Ghi ${nhan.charAt(0).toLowerCase()}${nhan.slice(1)}.`, 'loi'); o.focus(); return false; }
      return lam(lyDo);
    },
  });
}

// Chạy fn(phần tử) cho cả danh sách, tối đa toiDa việc cùng lúc. Kết quả theo đúng thứ tự, dạng Promise.allSettled
// (một việc lỗi không làm dừng các việc khác).
export async function chaySongSong(ds, fn, toiDa = 3) {
  const kq = new Array(ds.length); let tiep = 0;
  const tho = async () => {
    while (tiep < ds.length) {
      const i = tiep++;
      try { kq[i] = { status: 'fulfilled', value: await fn(ds[i], i) }; } catch (e) { kq[i] = { status: 'rejected', reason: e }; }
    }
  };
  await Promise.all(Array.from({ length: Math.min(toiDa, ds.length) }, tho));
  return kq;
}

// Chặn gửi form 2 lần (bấm đúp, Enter liên tục): trong lúc xuLy(e) chạy, nút gửi bị khóa và lần gửi sau bị bỏ qua.
// xuLy trả về true = đã xong hẳn (vd chuyển sang trang khác) → giữ khóa luôn, không cho gửi lại.
export function khoaKhiGui(form, xuLy, { chuDangGui = null } = {}) {
  let dangGui = false;
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (dangGui) return;
    dangGui = true;
    const nut = form.querySelector('button[type=submit]'); const chuCu = nut?.textContent;
    if (nut) { nut.disabled = true; if (chuDangGui) nut.textContent = chuDangGui; }
    let giuKhoa = false;
    try { giuKhoa = (await xuLy(e)) === true; } catch (loi) { if (!loi?.daBao && !loi?.daHuy) baoLoi(loi); } finally {
      dangGui = giuKhoa;
      if (!giuKhoa && nut && nut.isConnected) { nut.disabled = false; if (chuDangGui) nut.textContent = chuCu; }
    }
  });
}

export function bang(cot, dong, { trong = 'Chưa có dữ liệu.', onRow, idDong, gon = false } = {}) {
  if (!dong.length) return h('p', { class: 'trong' }, trong);
  return h('div', { class: 'bang-cuon' },
    h('table', { class: gon ? 'bang gon' : 'bang' },
      h('thead', null, h('tr', null, cot.map((c) => h('th', { class: c.so ? 'so' : null }, c.nhan)))),
      h('tbody', null, dong.map((d) => h('tr', { class: onRow ? 'bam-duoc' : null, onclick: onRow ? () => onRow(d) : null, 'data-id': idDong ? idDong(d) : null },
        cot.map((c) => h('td', { class: c.so ? 'so' : null, 'data-nhan': c.nhan }, c.lay ? c.lay(d) : d[c.khoa])))))));
}

// Nén ảnh điện thoại trước khi tải lên (cạnh dài tối đa 1600px)
// Ảnh xe: cạnh dài 1280px (~0,2 MB) – đủ nhìn rõ vết trầy, móp.
// Giấy tờ (giám định, duyệt giá, HĐ 3 bên, hồ sơ bảo hiểm, khác): 1600px để đọc được chữ.
const BUOC_GIAY_TO = ['duyet_gia', 'ho_so_bh', 'khac'];
async function veLai(file, canh, chatLuong) {
  const bmp = await createImageBitmap(file);
  const tile = Math.min(1, canh / Math.max(bmp.width, bmp.height));
  const c = document.createElement('canvas');
  c.width = Math.round(bmp.width * tile); c.height = Math.round(bmp.height * tile);
  c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
  bmp.close?.();
  return new Promise((r) => c.toBlob(r, 'image/jpeg', chatLuong));
}
export async function nenAnh(file, buoc = 'tiep_nhan') {
  if (!file.type.startsWith('image/')) return file;
  const giayTo = BUOC_GIAY_TO.includes(buoc);
  try {
    const blob = await veLai(file, giayTo ? 1600 : 1280, giayTo ? 0.85 : 0.78);
    if (!blob || blob.size >= file.size) return file;
    return new File([blob], file.name.replace(/\.\w+$/, '') + '.jpg', { type: 'image/jpeg' });
  } catch { return file; }
}
// Ảnh thu nhỏ ~20 KB để hiện ô vuông trong hồ sơ; bấm vào mới tải ảnh lớn
export async function taoAnhNho(file) {
  if (!file.type.startsWith('image/')) return null;
  try { return await veLai(file, 360, 0.7); } catch { return null; }
}
export const duongDanAnhNho = (duongDan) => `${duongDan}.nho.jpg`;

export function taiTepCSV(tenTep, cot, dong) {
  const thoat = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const noiDung = '﻿' + [cot.map((c) => thoat(c.nhan)).join(','),
    ...dong.map((d) => cot.map((c) => thoat(c.xuat ? c.xuat(d) : d[c.khoa])).join(','))].join('\r\n');
  const url = URL.createObjectURL(new Blob([noiDung], { type: 'text/csv;charset=utf-8' }));
  const a = h('a', { href: url, download: tenTep });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
