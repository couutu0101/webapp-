// Khung ứng dụng: đăng nhập, menu theo vai trò, điều hướng
import { h, $, toast, baoLoi, docForm, truong, VAI_TRO, dat, icon } from './ui.js';
import * as api from './api.js';
import { TEN_GARA } from './cau-hinh.js';

import trangViec from './trang/viec-hom-nay.js';
import trangHoSo from './trang/ho-so-danh-sach.js';
import trangTiepNhan from './trang/tiep-nhan.js';
import trangChiTiet from './trang/ho-so-chi-tiet.js';
import trangDichVu from './trang/dich-vu-nhanh.js';
import trangThuChi from './trang/thu-chi.js';
import trangDeNghi from './trang/de-nghi-chi.js';
import trangDoanhThu from './trang/doanh-thu.js';
import trangDanhMuc from './trang/danh-muc.js';
import trangNhanVien from './trang/nhan-vien.js';

const MENU = [
  { duong: 'viec', nhan: 'Việc hôm nay', ic: 'viec', ai: () => api.laNhanVien() || api.coVaiTro('truong_nhom') },
  { duong: 'ho-so', nhan: 'Hồ sơ xe', ic: 'xe', ai: () => api.laNhanVien() },
  { duong: 'dich-vu', nhan: 'Dịch vụ nhanh', ic: 'nhanh', ai: () => api.laNhanVien() || api.coVaiTro('truong_nhom') },
  { duong: 'thu-chi', nhan: 'Thu chi', ic: 'quy', ai: () => api.coVaiTro('giam_doc', 'ke_toan', 'quan_ly') },
  { duong: 'de-nghi', nhan: 'Đề nghị chi', ic: 'phieu', ai: () => api.laNhanVien() || api.coVaiTro('truong_nhom') },
  { duong: 'doanh-thu', nhan: 'Doanh thu', ic: 'doanhThu', ai: () => api.coVaiTro('giam_doc', 'ke_toan', 'quan_ly') },
  { duong: 'danh-muc', nhan: 'Danh mục', ic: 'danhMuc', ai: () => api.coVaiTro('giam_doc', 'ke_toan') },
  { duong: 'nhan-vien', nhan: 'Nhân viên', ic: 'nguoi', ai: () => api.coVaiTro('giam_doc') },
];

// Mỗi tuyến kèm điều kiện quyền: gõ thẳng địa chỉ cũng không mở được trang không thuộc vai trò mình
const quyenMenu = (duong) => MENU.find((m) => m.duong === duong).ai;
const TUYEN = [
  [/^viec$/, trangViec, quyenMenu('viec')],
  [/^ho-so$/, trangHoSo, quyenMenu('ho-so')],
  [/^ho-so\/moi$/, trangTiepNhan, () => api.coVaiTro('cvdv', 'quan_ly', 'giam_doc')],
  [/^ho-so\/(\d+)$/, trangChiTiet, quyenMenu('ho-so')],
  [/^dich-vu$/, trangDichVu, quyenMenu('dich-vu')],
  [/^thu-chi$/, trangThuChi, quyenMenu('thu-chi')],
  [/^de-nghi$/, trangDeNghi, quyenMenu('de-nghi')],
  [/^doanh-thu$/, trangDoanhThu, quyenMenu('doanh-thu')],
  [/^danh-muc$/, trangDanhMuc, quyenMenu('danh-muc')],
  [/^nhan-vien$/, trangNhanVien, quyenMenu('nhan-vien')],
];

const goc = document.getElementById('app');
let dangDatMatKhau = false;

// ---------- Đăng nhập ----------
function manDangNhap() {
  const form = h('form', { class: 'the dang-nhap', novalidate: true },
    h('div', { class: 'logo' }, 'HS'),
    h('h1', null, TEN_GARA),
    h('p', { class: 'mo-ta' }, 'Phần mềm quản lý gara'),
    truong('Email', h('input', { type: 'email', name: 'email', autocomplete: 'username', required: true })),
    truong('Mật khẩu', h('input', { type: 'password', name: 'mat_khau', autocomplete: 'current-password', required: true })),
    h('button', { class: 'nut chinh rong', type: 'submit' }, 'Đăng nhập'),
    h('button', { class: 'nut-chu', type: 'button', onclick: quenMatKhau }, 'Quên mật khẩu?'));
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const { email, mat_khau } = docForm(form);
    if (!email || !mat_khau) return toast('Nhập email và mật khẩu.', 'loi');
    const nut = form.querySelector('button[type=submit]');
    nut.disabled = true; nut.textContent = 'Đang đăng nhập…';
    try { await api.dangNhap(email, mat_khau); }
    catch (err) { baoLoi(err); nut.disabled = false; nut.textContent = 'Đăng nhập'; }
  });
  async function quenMatKhau() {
    const email = form.email.value.trim();
    if (!email) return toast('Nhập email trước, rồi bấm "Quên mật khẩu?".', 'loi');
    try { await api.guiQuenMatKhau(email); toast('Đã gửi email đặt lại mật khẩu. Mở email và bấm vào đường dẫn.'); }
    catch (err) { baoLoi(err); }
  }
  dat(goc, h('main', { class: 'man-hinh' }, form));
}

function manDatMatKhau() {
  dangDatMatKhau = true;
  const form = h('form', { class: 'the dang-nhap', novalidate: true },
    h('h1', null, 'Đặt mật khẩu'),
    h('p', { class: 'mo-ta' }, 'Đặt mật khẩu mới để dùng cho các lần đăng nhập sau.'),
    truong('Mật khẩu mới (ít nhất 8 ký tự)', h('input', { type: 'password', name: 'mk', autocomplete: 'new-password', minlength: 8 })),
    truong('Nhập lại mật khẩu', h('input', { type: 'password', name: 'mk2', autocomplete: 'new-password' })),
    h('button', { class: 'nut chinh rong', type: 'submit' }, 'Lưu mật khẩu'));
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const { mk, mk2 } = docForm(form);
    if (!mk || mk.length < 8) return toast('Mật khẩu cần ít nhất 8 ký tự.', 'loi');
    if (mk !== mk2) return toast('Hai lần nhập không khớp.', 'loi');
    try {
      await api.datMatKhau(mk);
      dangDatMatKhau = false;
      history.replaceState(null, '', location.pathname + '#/viec');
      toast('Đã lưu mật khẩu.');
      await vaoUngDung();
    } catch (err) { baoLoi(err); }
  });
  dat(goc, h('main', { class: 'man-hinh' }, form));
}

// ---------- Khung sau khi đăng nhập ----------
let khung = null;
function dungKhung() {
  const toi = api.toi;
  const menu = MENU.filter((m) => m.ai());
  const chiNhanh = (api.dm.ten('chi_nhanh', toi.chi_nhanh_id) || '').replace(/^.*[–-]\s*/, '');
  const nav = h('nav', { class: 'menu', id: 'menu', 'aria-label': 'Menu chính' },
    h('a', { class: 'thuong-hieu', href: '#/viec' }, h('span', { class: 'dau-hieu', 'aria-hidden': 'true' }, 'HS'),
      h('span', null, h('b', null, TEN_GARA), h('small', null, chiNhanh))),
    h('div', { class: 'menu-ds' }, menu.map((m) => h('a', { href: `#/${m.duong}`, 'data-duong': m.duong }, icon(m.ic), h('span', null, m.nhan)))),
    h('div', { class: 'menu-chan' },
      h('div', { class: 'ai-dang-dung' }, h('b', null, toi.ho_ten), h('small', null, toi.vai_tro.map((v) => VAI_TRO[v]).join(', '))),
      h('button', { class: 'nut-chu', type: 'button', onclick: doiMatKhau }, 'Đổi mật khẩu'),
      h('button', { class: 'nut-chu', type: 'button', onclick: () => api.dangXuat() }, 'Đăng xuất')));
  const dau = h('header', { class: 'dau' },
    h('button', { class: 'nut-menu', type: 'button', 'aria-label': 'Mở menu', 'aria-controls': 'menu',
      onclick: () => document.body.classList.toggle('mo-menu') }, icon('menu')),
    h('a', { class: 'ten-gara', href: '#/viec' }, TEN_GARA),
    h('span', { class: 'chi-nhanh' }, chiNhanh));
  const noiDung = h('main', { class: 'noi-dung', id: 'noi-dung', tabindex: '-1' });
  khung = { noiDung, nav };
  dat(goc, dau, h('div', { class: 'than' }, nav, h('div', { class: 'man-che', onclick: () => document.body.classList.remove('mo-menu') }), noiDung));
  nav.addEventListener('click', (e) => { if (e.target.closest('a')) document.body.classList.remove('mo-menu'); });
}

function doiMatKhau() {
  manDatMatKhau();
}

async function dieuHuong() {
  if (!khung || dangDatMatKhau) return;
  const duong = (location.hash.replace(/^#\/?/, '') || '').split('?')[0];
  if (!duong) {
    location.hash = api.coVaiTro('co_dong') && !api.laNhanVien() ? '#/co-dong' : '#/viec';
    return;
  }
  for (const a of khung.nav.querySelectorAll('.menu-ds a')) {
    a.classList.toggle('dang-chon', duong === a.dataset.duong || duong.startsWith(a.dataset.duong + '/'));
  }
  if (duong === 'co-dong') {
    dat(khung.noiDung, h('section', { class: 'the' }, h('h1', null, 'Báo cáo cổ đông'),
      h('p', null, 'Trang báo cáo cho cổ đông sẽ mở ở đợt 2 (giữa tháng 11/2026). Anh/chị chỉ xem được số tổng của những tháng giám đốc đã chốt.')));
    return;
  }
  const tim = TUYEN.find(([re]) => re.test(duong));
  if (!tim) { dat(khung.noiDung, h('p', { class: 'trong' }, 'Không tìm thấy trang.')); return; }
  if (!tim[2]()) { dat(khung.noiDung, h('p', { class: 'trong' }, 'Anh/chị không có quyền mở trang này.')); return; }
  const thamSo = duong.match(tim[0]).slice(1);
  // Mỗi lần chuyển trang dùng một vùng mới: trang cũ tải xong muộn cũng không đè lên trang mới
  const vung = h('div', { class: 'trang' }, h('div', { class: 'dang-tai', role: 'status' }, 'Đang tải…'));
  dat(khung.noiDung, vung);
  try {
    await tim[1](vung, ...thamSo);
    khung.noiDung.focus({ preventScroll: true });
    window.scrollTo(0, 0);
  } catch (e) {
    baoLoi(e);
    dat(vung, h('p', { class: 'trong' }, 'Không tải được trang: ' + e.message));
  }
}

async function vaoUngDung() {
  const phien = await api.layPhien();
  if (!phien) { khung = null; manDangNhap(); return; }
  const toi = await api.taiToi(phien.user.id);
  if (!toi || !toi.hoat_dong || !toi.vai_tro.length) {
    khung = null;
    dat(goc, h('main', { class: 'man-hinh' }, h('div', { class: 'the dang-nhap' },
      h('h1', null, 'Chờ cấp quyền'),
      h('p', null, `Tài khoản ${phien.user.email} đã đăng nhập nhưng chưa được giám đốc cấp vai trò. Báo giám đốc vào mục Nhân viên để cấp quyền.`),
      h('button', { class: 'nut', type: 'button', onclick: () => api.dangXuat() }, 'Đăng xuất'))));
    return;
  }
  await api.taiDanhMuc();
  dungKhung();
  await dieuHuong();
}

window.addEventListener('hashchange', dieuHuong);

api.khiDoiPhien((suKien, phien) => {
  if (suKien === 'PASSWORD_RECOVERY') { manDatMatKhau(); return; }
  if (suKien === 'SIGNED_IN' && /type=(invite|recovery)/.test(location.hash + location.search)) { manDatMatKhau(); return; }
  if (suKien === 'SIGNED_IN' || suKien === 'SIGNED_OUT') {
    if (dangDatMatKhau) return;
    if (suKien === 'SIGNED_IN' && khung && api.toi && phien?.user?.id === api.toi.id) return;
    vaoUngDung().catch(baoLoi);
  }
});

if (/type=(invite|recovery)/.test(location.hash + location.search)) {
  // chờ thư viện đọc mã trong đường dẫn rồi sự kiện ở trên sẽ mở màn đặt mật khẩu
} else {
  vaoUngDung().catch((e) => { baoLoi(e); manDangNhap(); });
}
