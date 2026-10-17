// Trang Thông báo (054): các thông báo gần đây gửi riêng cho người đăng nhập, cái nào đã nhận lúc nào.
// Cái CHƯA nhận hiện ở khung giữa màn hình (js/thong-bao.js) cho tới khi bấm "Đã nhận"; trang này để xem lại và mở lại nơi cần làm.
import { h, dat, bienSo, ngay } from '../ui.js';
import * as api from '../api.js';
import { TEN_LOAI, tachTieuDe, duongDich, gioBao, nhanChiNhanh } from '../thong-bao.js';

const SO_DONG = 80;

function tieuDeTrang() {
  return h('div', { class: 'tieu-de-trang' }, h('div', null,
    h('h1', null, 'Thông báo'),
    h('p', { class: 'mo-ta' }, 'Thông báo gửi riêng cho anh/chị. Việc chưa nhận hiện khung giữa màn hình cho tới khi bấm "Đã nhận".')));
}

function nhanNgay(luc) {
  const t = new Date(luc); const bay = new Date();
  const homQua = new Date(bay.getFullYear(), bay.getMonth(), bay.getDate() - 1);
  if (t.toDateString() === bay.toDateString()) return 'Hôm nay';
  if (t.toDateString() === homQua.toDateString()) return 'Hôm qua';
  return ngay(t);
}

function theThongBao(n) {
  const { chu, bien, ghiChu } = tachTieuDe(n.tieu_de);
  const khac = !!(n.chi_nhanh_id && api.toi?.chi_nhanh_id && n.chi_nhanh_id !== api.toi.chi_nhanh_id);
  const dich = khac ? null : duongDich(n);
  return h('li', { class: `tb-dong loai-${n.loai}${n.da_nhan_luc ? ' da-nhan' : ' chua-nhan'}`, 'data-tb-id': n.id },
    h('div', { class: 'tb-the-dau' },
      h('span', { class: 'tb-loai' }, TEN_LOAI[n.loai] || 'Thông báo'),
      bien ? bienSo(bien) : null,
      khac ? nhanChiNhanh(n.chi_nhanh_id) : null,
      h('span', { class: 'tb-luc' }, gioBao(n.cap_nhat_luc))),
    h('div', { class: 'tb-tieu' }, chu, ghiChu ? h('small', null, ' ', ghiChu) : null),
    n.noi_dung ? h('p', { class: 'tb-nd' }, n.noi_dung) : null,
    n.chi_tiet?.length ? h('ul', { class: 'tb-ds' }, n.chi_tiet.map((d) => h('li', null, d))) : null,
    h('div', { class: 'tb-dong-chan' },
      n.da_nhan_luc ? h('span', { class: 'nhan tt-tot' }, `Đã nhận lúc ${gioBao(n.da_nhan_luc)}`)
        : h('span', { class: 'nhan tb-chua' }, 'Chưa nhận'),
      dich ? h('a', { class: 'nut nho', href: dich.href }, dich.nhan.charAt(0).toUpperCase() + dich.nhan.slice(1)) : null));
}

export default async function trangThongBao(el) {
  let ds;
  try {
    ds = await api.thongBaoGanDay(SO_DONG);
  } catch (e) {
    if (api.thongBaoThieuBang(e)) {
      dat(el, tieuDeTrang(), h('p', { class: 'thong-bao canh-bao' }, 'Phần thông báo chưa được bật trên máy chủ (cần chạy bản cập nhật cơ sở dữ liệu 054). Nhắc việc quá hạn vẫn dùng được.'));
      return;
    }
    throw e;
  }
  ds = ds || [];
  const chuaNhan = ds.filter((n) => !n.da_nhan_luc).length;
  // Gom theo ngày của lần cập nhật gần nhất
  const nhom = [];
  for (const n of ds) {
    const nhan = nhanNgay(n.cap_nhat_luc);
    if (!nhom.length || nhom[nhom.length - 1].nhan !== nhan) nhom.push({ nhan, ds: [] });
    nhom[nhom.length - 1].ds.push(n);
  }
  dat(el,
    tieuDeTrang(),
    chuaNhan ? h('p', { class: 'thong-bao canh-bao', role: 'status' }, `Còn ${chuaNhan} thông báo chưa nhận – bấm "Đã nhận" ở khung giữa màn hình.`) : null,
    !ds.length ? h('p', { class: 'trong' }, 'Chưa có thông báo nào gửi cho anh/chị.')
      : nhom.map((g) => h('section', { class: 'the tb-nhom' },
        h('h2', null, g.nhan),
        h('ul', { class: 'tb-ds-trang' }, g.ds.map(theThongBao)))),
    ds.length >= SO_DONG ? h('p', { class: 'mo-ta' }, `Chỉ hiện ${SO_DONG} thông báo gần nhất.`) : null);
}
