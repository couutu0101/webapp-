// Lịch sử tình trạng – tư vấn – phản hồi của một xe qua các lần vào gara.
// Quy ước ghi: mỗi lần nhập là một dòng bắt đầu bằng ngày "dd/mm/yyyy: …", ghi tiếp chứ không ghi đè.
import { h, ngay, tien, homNay, isoSangVN, NGUON } from '../ui.js';
import * as api from '../api.js';

export const homNayVN = () => isoSangVN(homNay());
const CO_NGAY = /^\d{2}\/\d{2}\/\d{4}:/;

// Thêm ngày hôm nay vào đầu nội dung mới (nếu người nhập chưa ghi ngày)
export function themNgay(noiDung) {
  const t = (noiDung || '').trim();
  if (!t || t === `${homNayVN()}:`) return '';
  return CO_NGAY.test(t) ? t : `${homNayVN()}: ${t}`;
}

// Ghi tiếp một lần nhập mới vào sau nội dung cũ
export function ghiTiep(cu, moi) {
  const m = themNgay(moi);
  if (!m) return cu || '';
  return cu ? `${cu.trim()}\n${m}` : m;
}

// Ô nhập: bấm vào ô trống thì tự có sẵn ngày hôm nay ở đầu
export function tuGhiNgayKhiBam(o) {
  o.addEventListener('focus', () => {
    if (o.value.trim()) return;
    o.value = `${homNayVN()}: `;
    requestAnimationFrame(() => o.setSelectionRange(o.value.length, o.value.length));
  });
  o.addEventListener('blur', () => { if (o.value.trim() === `${homNayVN()}:`) o.value = ''; });
}

// Nhắc gia hạn bảo hiểm đã hết hạn (ngày hôm nay lớn hơn ngày hết hạn)
export function nhacHetHan(isoThanVo, isoTnds) {
  const hom = homNay();
  const ra = [];
  if (isoThanVo && isoThanVo < hom) ra.push(`Bảo hiểm thân vỏ đã hết hạn ngày ${isoSangVN(isoThanVo)} – tư vấn khách gia hạn.`);
  if (isoTnds && isoTnds < hom) ra.push(`Bảo hiểm TNDS đã hết hạn ngày ${isoSangVN(isoTnds)} – tư vấn khách gia hạn.`);
  return ra;
}

// Các lần vào gara trước của xe (mới nhất trước), bỏ hồ sơ đang xem
export async function layLichSu(xeId, boQuaId = null) {
  if (!xeId) return [];
  const [ds, km, dvn] = await Promise.all([
    api.doc('v_ho_so', (q) => q.eq('xe_id', xeId).order('ngay_vao', { ascending: false }).limit(30)),
    api.doc('ho_so', (q) => q.eq('xe_id', xeId), 'id, so_km').catch(() => []),   // số km chưa có trong v_ho_so (031)
    // Lượt dịch vụ nhanh của xe (032)
    api.doc('v_dich_vu_nhanh', (q) => q.eq('xe_id', xeId).eq('trang_thai', 'hieu_luc').order('ngay', { ascending: false }).limit(30)).catch(() => []),
  ]);
  const soKm = new Map(km.map((x) => [x.id, x.so_km]));
  const hoSo = ds.filter((x) => String(x.id) !== String(boQuaId)).map((x) => ({ ...x, so_km: soKm.get(x.id) ?? null }));
  const nhanh = dvn.map((d) => ({ loai_ls: 'dvn', id: d.id, ngay_vao: `${d.ngay}T12:00:00`, dich_vu: d.dich_vu, so_tien: d.so_tien,
    so_km: d.so_km, nguoi_lam: d.nguoi_lam, tao_luc: d.tao_luc }));
  // Mới nhất trước; cùng ngày thì theo lúc ghi
  return [...hoSo, ...nhanh].sort((a, b) => String(b.ngay_vao).slice(0, 10).localeCompare(String(a.ngay_vao).slice(0, 10))
    || new Date(b.tao_luc || b.ngay_vao) - new Date(a.tao_luc || a.ngay_vao));
}

// Bỏ các câu giữ chỗ của dữ liệu chuyển từ Excel
const GIU_CHO = /^\d{2}\/\d{2}\/\d{4}: \((Chuyển từ Excel|Excel không ghi tình trạng)\)$/;
const dongNoiDung = (nhan, noiDung, ngayGhi) => noiDung && !GIU_CHO.test(noiDung.trim())
  ? h('div', { class: 'ls-dong' }, h('span', { class: 'ls-nhan' }, nhan),
    h('span', { class: 'ls-noi-dung' }, CO_NGAY.test(noiDung.trim()) || !ngayGhi ? noiDung : `${ngay(ngayGhi)}: ${noiDung}`))
  : null;

export function khoiLichSu(ds, { tieuDe = 'Lịch sử các lần trước', moSan = true } = {}) {
  if (!ds.length) return null;
  return h('details', { class: 'lich-su', open: moSan },
    h('summary', null, `${tieuDe} (${ds.length})`),
    h('ol', { class: 'ls-ds' }, ds.map((x) => (x.loai_ls === 'dvn' ? h('li', { class: 'ls-dvn' },
      h('div', { class: 'ls-dau' }, h('b', null, ngay(x.ngay_vao)), ' ', h('span', { class: 'nhan' }, 'Dịch vụ nhanh'), ' ',
        h('span', null, `${x.dich_vu} · ${tien(x.so_tien)} đ`), x.nguoi_lam ? h('small', null, ` · ${x.nguoi_lam}`) : null),
      x.so_km !== null && x.so_km !== undefined ? h('div', { class: 'ls-dong' }, h('span', { class: 'ls-nhan' }, 'Số km'), h('span', { class: 'ls-noi-dung' }, `${tien(x.so_km)} km`)) : null)
    : h('li', null,
      h('div', { class: 'ls-dau' },
        h('b', null, ngay(x.ngay_vao)), ' ',
        h('a', { href: `#/ho-so/${x.id}` }, x.ma), ' ',
        h('small', null, x.loai === 'bao_hanh' ? 'Bảo hành (làm lại miễn phí)' : x.nguon_tt === 'khach' ? NGUON.khach : (x.hang_bh || NGUON[x.nguon_tt])),
        x.tu_excel ? h('span', { class: 'nhan' }, 'Từ Excel') : null),
      x.so_km !== null && x.so_km !== undefined ? h('div', { class: 'ls-dong' }, h('span', { class: 'ls-nhan' }, 'Số km'), h('span', { class: 'ls-noi-dung' }, `${tien(x.so_km)} km`)) : null,
      dongNoiDung('Yêu cầu khách hàng', x.tinh_trang_xe, x.ngay_vao),
      dongNoiDung('Tư vấn', x.tu_van, x.ngay_vao),
      dongNoiDung('Phản hồi khi giao xe', x.cam_nhan_khach, x.giao_luc),
      dongNoiDung('Phản hồi khi gọi chăm sóc', x.cham_soc_ket_qua, x.cham_soc_luc))))));
}
