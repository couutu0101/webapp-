// 047: ảnh / file bắt buộc ở các bước của hồ sơ xe (khớp máy chủ, chỉ áp cho hồ sơ có cờ bat_buoc_anh)
//  - Tiếp nhận: 6 ảnh có tên (4 quanh xe + 2 nội thất)
//  - Báo giá: mỗi lần lưu (cả bổ sung) kèm ảnh / PDF báo giá tải lên sau lần lưu trước (ho_so.bao_gia_luc)
//  - Duyệt giá xe bảo hiểm: ảnh / PDF duyệt giá của bảo hiểm tải lên sau lần báo giá gần nhất
//  - KCS đạt: tối thiểu 6 ảnh KCS (tổng các lần), sau lần chưa đạt có ít nhất 1 ảnh mới
import { h, icon, toast } from './ui.js';
import * as api from './api.js';

export const ANH_NHAN_XE = [
  { buoc: 'nx_truoc', ten: 'Phía trước' },
  { buoc: 'nx_sau', ten: 'Phía sau' },
  { buoc: 'nx_trai', ten: 'Bên trái' },
  { buoc: 'nx_phai', ten: 'Bên phải' },
  { buoc: 'nt_truoc', ten: 'Nội thất phía trước', goiY: 'Táp lô, vô lăng, đồng hồ km' },
  { buoc: 'nt_sau', ten: 'Nội thất phía sau', goiY: 'Hàng ghế sau' },
];
export const NHAN_BUOC_MOI = {
  bao_gia: 'Báo giá',
  ...Object.fromEntries(ANH_NHAN_XE.map((a) => [a.buoc, a.buoc.startsWith('nt') ? a.ten : `Nhận xe – ${a.ten.toLowerCase()}`])),
};
export const SO_ANH_KCS = 6;
// 053: ảnh, giấy tờ xe (đăng ký, đăng kiểm, bảo hiểm xe, CCCD chủ xe…) tải ngay trong hộp Lập báo giá; không bắt buộc. Bước tệp = 'giay_to_xe'.
export const NHAN_GIAY_TO_XE = 'Ảnh, giấy tờ xe';

const sau = (t, moc) => !moc || new Date(t.tai_luc) > new Date(moc);
export const anhNhanXeThieu = (tep) => ANH_NHAN_XE.filter((a) => !tep.some((t) => t.buoc === a.buoc));
export const coFileBaoGiaMoi = (hs, tep) => tep.some((t) => t.buoc === 'bao_gia' && sau(t, hs.bao_gia_luc));
export const coFileDuyetMoi = (hs, tep) => tep.some((t) => t.buoc === 'duyet_gia' && sau(t, hs.bao_gia_luc));
export const soAnhKcs = (tep) => tep.filter((t) => t.buoc === 'kcs' && (t.loai || 'anh') === 'anh').length;
export const loaiTep = (f) => (f.type === 'application/pdf' ? 'bien_ban' : 'anh');

// Tải một danh sách tệp vào một bước của hồ sơ; trả số tệp lỗi (đã báo từng tệp)
export async function taiVaoBuoc(hs, buoc, files, tienDo) {
  const ds = [...(files || [])];
  if (!ds.length) return 0;
  const kq = await api.taiNhieu(ds, buoc, (f, goc) => api.taiTep(hs, buoc, f, loaiTep(goc)), { tienDo });
  for (const x of kq.loi) toast(`Không tải được ${x.ten}: ${x.e?.message || x.e}`, 'loi');
  return kq.loi.length;
}

// Khung 6 ô ảnh nhận xe.
//  - Form tiếp nhận (không có hs): chọn ảnh giữ tạm trong máy, chon.get(buoc) = File; thieu() = các ô chưa có ảnh.
//  - Trang hồ sơ (có hs): ô đã có ảnh hiện ảnh; ô thiếu bấm chọn ảnh là tải lên ngay rồi gọi khiXong().
//  - 051: không mở thẳng camera (điện thoại giật, lag) – chọn ảnh có sẵn trong máy (vẫn chụp mới được);
//    nút "Chọn nhiều ảnh một lần" điền lần lượt vào các ô còn trống.
export function khungAnhNhanXe({ hs = null, tep = [], link = {}, choSua = true, khiXong = null } = {}) {
  const chon = new Map();
  const oCua = new Map();
  const luoi = h('div', { class: 'luoi-anh-buoc' }, ANH_NHAN_XE.map((a) => {
    const daCo = tep.filter((t) => t.buoc === a.buoc).pop();
    const anh = h('span', { class: 'o-anh-buoc-hinh' });
    const trangThai = h('small', { class: 'o-anh-buoc-tt' });
    const ve = (src, chu, xong) => {
      anh.replaceChildren(src ? h('img', { src, alt: a.ten }) : icon('anh'));
      trangThai.textContent = chu;
      o.classList.toggle('du', !!xong);
      if (xong) o.classList.remove('thieu');
    };
    const input = h('input', { type: 'file', accept: 'image/*', 'data-buoc': a.buoc, 'aria-label': `Ảnh ${a.ten}` });
    const o = h(choSua ? 'label' : 'div', { class: 'o-anh-buoc', 'data-o': a.buoc },
      choSua ? input : null, anh, h('b', null, a.ten), a.goiY ? h('small', { class: 'o-anh-buoc-goi-y' }, a.goiY) : null, trangThai);
    if (daCo) ve(link[daCo.duong_dan]?.nho || null, 'Đã có ảnh', true);
    else ve(null, choSua ? 'Bấm để chọn ảnh *' : 'Chưa có', false);
    const nhan = async (f, { im = false } = {}) => {
      ve(URL.createObjectURL(f), hs ? 'Đang tải…' : 'Đã chọn', !hs);
      if (!hs) { chon.set(a.buoc, f); return; }
      input.disabled = true;
      const loi = await taiVaoBuoc(hs, a.buoc, [f]);
      input.disabled = false; input.value = '';
      if (loi) { ve(null, 'Tải lỗi – chọn lại', false); return false; }
      ve(o.querySelector('img')?.src, 'Đã có ảnh', true);
      if (im) return true;
      toast(`Đã lưu ảnh ${a.ten.toLowerCase()}.`);
      khiXong?.();
      return true;
    };
    input.addEventListener('change', () => { if (input.files[0]) nhan(input.files[0]); });
    o.nhan = nhan;
    oCua.set(a.buoc, o);
    return o;
  }));
  // Chọn nhiều ảnh một lần: điền lần lượt vào các ô chưa có ảnh (thứ tự ô: trước, sau, trái, phải, nội thất trước, sau)
  const oNhieu = h('input', { type: 'file', accept: 'image/*', multiple: true, 'data-nhieu-anh': '', 'aria-label': 'Chọn nhiều ảnh nhận xe một lần' });
  oNhieu.addEventListener('change', async () => {
    const ds = [...oNhieu.files];
    oNhieu.value = '';
    const trong = ANH_NHAN_XE.map((a) => oCua.get(a.buoc)).filter((o) => o && !o.classList.contains('du'));
    if (!trong.length) { toast('Đủ 6 ô rồi – muốn đổi ảnh nào thì bấm vào ô đó.'); return; }
    if (ds.length > trong.length) toast(`Chỉ còn ${trong.length} ô trống – lấy ${trong.length} ảnh đầu.`);
    const so = Math.min(ds.length, trong.length);
    let daLuu = 0;
    oNhieu.disabled = true;
    for (let i = 0; i < so; i++) if (await trong[i].nhan(ds[i], { im: true })) daLuu++;
    oNhieu.disabled = false;
    if (hs) { if (daLuu) toast(`Đã lưu ${daLuu} ảnh nhận xe.`); khiXong?.(); }
  });
  const khung = h('div', { class: 'khung-anh-nhan-xe' },
    choSua ? h('label', { class: 'nut nho noi-bat nut-nhieu-anh' }, oNhieu, icon('anh'), 'Chọn nhiều ảnh một lần') : null,
    luoi);
  khung.chon = chon;
  khung.thieu = () => ANH_NHAN_XE.filter((a) => !chon.has(a.buoc) && !tep.some((t) => t.buoc === a.buoc));
  khung.danhDauThieu = () => { for (const a of khung.thieu()) oCua.get(a.buoc)?.classList.add('thieu'); };
  return khung;
}

// Ô chọn ảnh / PDF đính kèm (báo giá, duyệt giá, KCS)
export function oDinhKem(nhan, { batBuoc = false, chiAnh = false, goiY = '' } = {}) {
  const input = h('input', { type: 'file', multiple: true, accept: chiAnh ? 'image/*' : 'image/*,application/pdf', 'aria-label': nhan });
  const dem = h('span', { class: 'chon-tep-dem' }, 'Chưa chọn tệp');
  input.addEventListener('change', () => {
    dem.textContent = input.files.length ? `Đã chọn ${input.files.length} tệp` : 'Chưa chọn tệp';
    nhanEl.classList.remove('thieu');
  });
  const nhanEl = h('label', { class: `chon-tep${batBuoc ? ' bb' : ''}` }, input, icon('anh'),
    h('span', null, nhan, batBuoc ? ' *' : '', goiY ? h('small', { class: 'goi-y' }, h('br'), goiY) : null), dem);
  nhanEl.input = input;
  // Xóa các tệp đã chọn (sau khi đã tải lên) và đưa dòng đếm về "Chưa chọn tệp"
  nhanEl.xoa = () => { input.value = ''; input.dispatchEvent(new Event('change')); };
  return nhanEl;
}
