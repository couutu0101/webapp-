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
export function dauThang(d = new Date()) { return `${d.getFullYear()}-${hai(d.getMonth() + 1)}-01`; }
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
export const BUOC_SO = { tiep_nhan: 1, bao_gia: 2, da_duyet: 3, dang_sua: 5, cho_kcs: 6, dat_kcs: 7, da_giao: 8, da_gui_hs: 8, dong: 9, huy: 0 };
// Nhóm hạng mục báo giá. Chọn mới: Đồng, Sơn, Phụ tùng, Detailing; "Đồng sơn", "Điện – máy – gầm" chỉ còn ở dòng cũ.
export const NHOM = { dong: 'Đồng', son: 'Sơn', phu_tung: 'Phụ tùng', detailing: 'Detailing', dong_son: 'Đồng sơn', dmg: 'Điện – máy – gầm' };
export const NHOM_CHON = ['dong', 'son', 'phu_tung', 'detailing'];
// Gộp nhóm cho báo cáo doanh thu: Đồng + Sơn tính vào "Đồng sơn"
export const NHOM_BAO_CAO = { dong_son: 'Đồng sơn', phu_tung: 'Phụ tùng', dmg: 'Điện – máy – gầm', detailing: 'Detailing' };
export const nhomBaoCao = (n) => (n === 'dong' || n === 'son' ? 'dong_son' : n);
export const NGUON = { bao_hiem: 'Bảo hiểm', khach: 'Khách ngoài bảo hiểm', bao_hiem_khach: 'Bảo hiểm + khách trả thêm' };
export const VAI_TRO = {
  giam_doc: 'Giám đốc', quan_ly: 'Quản lý chung', ke_toan: 'Kế toán', cvdv: 'CVDV',
  kho: 'Kho', truong_nhom: 'Trưởng nhóm', co_dong: 'Cổ đông',
};
export function nhanTrangThai(tt) {
  return h('span', { class: `nhan tt-${tt}` }, TRANG_THAI[tt] || tt);
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
export function truong(nhan, input, goiY, { batBuoc = false, rong = false } = {}) {
  // Ô đã là <label> (nút chọn ảnh) thì khung ngoài dùng <div> để không lồng label
  const tag = input?.tagName === 'LABEL' ? 'div' : 'label';
  return h(tag, { class: `truong ${rong ? 'rong' : ''}` },
    h('span', { class: 'truong-nhan' }, nhan, batBuoc ? h('b', { class: 'bat-buoc', 'aria-hidden': 'true' }, ' *') : null),
    input,
    goiY ? h('small', { class: 'goi-y' }, goiY) : null);
}
export function oChu(name, value = '', attrs = {}) {
  return h('input', { type: 'text', name, value: value ?? '', ...attrs });
}
export function oTien(name, value, attrs = {}) {
  const el = h('input', { type: 'text', inputmode: 'numeric', name, class: 'o-tien', autocomplete: 'off', ...attrs });
  el.value = value === null || value === undefined ? '' : tien(value);
  el.addEventListener('input', () => {
    const so = docTien(el.value);
    const viTriCuoi = el.value.length - el.selectionStart;
    el.value = so === null ? '' : tien(so);
    const p = Math.max(0, el.value.length - viTriCuoi);
    el.setSelectionRange(p, p);
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

export function trangThaiTai(el, dangTai = true) {
  dat(el, h('div', { class: 'dang-tai', role: 'status' }, dangTai ? 'Đang tải…' : ''));
}

export function bang(cot, dong, { trong = 'Chưa có dữ liệu.', onRow, idDong } = {}) {
  if (!dong.length) return h('p', { class: 'trong' }, trong);
  return h('div', { class: 'bang-cuon' },
    h('table', { class: 'bang' },
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
