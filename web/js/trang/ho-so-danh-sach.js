// Danh sách hồ sơ xe
import { h, bienSo, tien, ngay, bang, nhanTrangThai, NGUON, dat, nhoPhien } from '../ui.js';
import * as api from '../api.js';
import { viecTiepTheo } from './giao-viec.js';

const LOC = [
  { ma: 'dang', nhan: 'Đang ở xưởng', tt: ['tiep_nhan', 'bao_gia', 'da_duyet', 'dang_sua', 'cho_kcs', 'dat_kcs'] },
  { ma: 'no', nhan: 'Chờ thu tiền', tt: ['da_giao', 'da_gui_hs'] },
  { ma: 'dong', nhan: 'Đã đóng', tt: ['dong'] },
  { ma: 'huy', nhan: 'Đã hủy', tt: ['huy'] },
  { ma: 'tat', nhan: 'Tất cả', tt: null },
];

export default async function trangHoSo(el) {
  const thamSo = new URLSearchParams(location.hash.split('?')[1] || '');
  let ttRieng = thamSo.get('tt') ? thamSo.get('tt').split(',') : null;
  // Nhớ tab đang xem để lưu xong trong hồ sơ thì quay về đúng chỗ
  let loc = ttRieng ? null : (LOC.some((l) => l.ma === nhoPhien.doc('hs_tab')) ? nhoPhien.doc('hs_tab') : 'dang');
  nhoPhien.ghi('hs_ds', location.hash.startsWith('#/ho-so') ? location.hash : '#/ho-so');
  let tuKhoa = '';

  const ketQua = h('div');
  const oTim = h('input', { type: 'search', placeholder: 'Tìm biển số, mã hồ sơ, tên khách, SĐT…', 'aria-label': 'Tìm hồ sơ' });
  let hen;
  oTim.addEventListener('input', () => { clearTimeout(hen); hen = setTimeout(() => { tuKhoa = oTim.value.trim(); tai(); }, 300); });

  const tabs = h('div', { class: 'tabs', role: 'tablist' }, LOC.map((l) => h('button', {
    type: 'button', role: 'tab', 'data-ma': l.ma, 'aria-selected': String(l.ma === loc),
    onclick: () => { loc = l.ma; ttRieng = null; nhoPhien.ghi('hs_tab', loc); nhoPhien.ghi('hs_ds', '#/ho-so'); capNhatTab(); tai(); },
  }, l.nhan)));
  function capNhatTab() { for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); }

  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Hồ sơ xe'),
      api.coVaiTro('cvdv', 'quan_ly', 'giam_doc') ? h('a', { class: 'nut chinh', href: '#/ho-so/moi' }, '+ Tiếp nhận xe') : null),
    h('div', { class: 'thanh-loc' }, oTim, tabs),
    ketQua);

  async function tai() {
    dat(ketQua, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    const tt = ttRieng || LOC.find((l) => l.ma === loc)?.tt;
    const ds = await api.doc('v_ho_so', (q) => {
      if (tt) q = q.in('trang_thai', tt);
      if (tuKhoa) {
        const gon = tuKhoa.toUpperCase().replace(/[^0-9A-Z]/g, '');
        const s = tuKhoa.replace(/[,()]/g, ' ');
        q = q.or([`ma.ilike.%${gon || s}%`, `bien_so.ilike.%${gon || s}%`, `ten_khach.ilike.%${s}%`, `dien_thoai.ilike.%${s}%`].join(','));
      }
      return q.order('ngay_vao', { ascending: false }).limit(300);
    });
    // Ai đang được giao bước tiếp theo
    const viec = ds.length ? await api.doc('v_viec_ho_so', (q) => q.in('ho_so_id', ds.map((d) => d.id))).catch(() => []) : [];
    const nguoiCua = Object.fromEntries(viec.map((v) => [v.ho_so_id, v.nguoi_tiep_theo_ten]));
    const oViec = (d) => {
      const v = viecTiepTheo(d);
      if (!v) return '';
      const ai = nguoiCua[d.id];
      return h('span', { class: 'viec-tiep' }, v.ten, h('small', null, ai || 'Chưa giao'));
    };
    const coTien = api.coVaiTro('giam_doc', 'ke_toan', 'quan_ly');
    dat(ketQua, 
      ttRieng ? h('p', { class: 'mo-ta' }, 'Đang lọc theo bước được chọn ở trang Việc hôm nay. ',
        h('button', { class: 'nut-chu', type: 'button', onclick: () => { ttRieng = null; loc = 'dang'; nhoPhien.ghi('hs_tab', loc); nhoPhien.ghi('hs_ds', '#/ho-so'); capNhatTab(); tai(); } }, 'Bỏ lọc')) : null,
      h('p', { class: 'mo-ta' }, `${ds.length} hồ sơ`),
      bang([
        { nhan: 'Biển số', lay: (d) => bienSo(d.bien_so_hien_thi, { maThay: d.ma }) },
        { nhan: 'Xe', lay: (d) => d.xe },
        { nhan: 'Khách', lay: (d) => d.ten_khach },
        { nhan: 'Nguồn', lay: (d) => d.nguon_tt === 'khach' ? 'Ngoài BH' : (d.hang_bh || NGUON[d.nguon_tt]) },
        { nhan: 'Vào ngày', lay: (d) => ngay(d.ngay_vao) },
        { nhan: 'Bước', lay: (d) => h('span', null, nhanTrangThai(d.trang_thai), d.co_phat_sinh ? h('span', { class: 'nhan tt-canh-bao' }, 'Phát sinh') : null) },
        { nhan: 'Việc tiếp theo – Ai làm', lay: oViec },
        coTien ? { nhan: 'Còn nợ', so: true, lay: (d) => tien(Number(d.con_no_bh) + Number(d.con_no_khach)) || '0' } : null,
      ].filter(Boolean), ds, { onRow: (d) => { location.hash = `#/ho-so/${d.id}`; }, idDong: (d) => d.id, trong: 'Không có hồ sơ nào.' }));
    return ds;
  }
  await tai();
  await toVuaLuu();

  // Hồ sơ vừa lưu: tô vàng dòng đó. Nếu hồ sơ đã chuyển bước sang tab khác thì tự mở tab đó.
  async function toVuaLuu() {
    const id = nhoPhien.doc('hs_vua_luu');
    if (!id) return;
    nhoPhien.xoa('hs_vua_luu');
    let dong = ketQua.querySelector(`tr[data-id="${id}"]`);
    if (!dong && !ttRieng) {
      const [x] = await api.doc('v_ho_so', (q) => q.eq('id', id), 'trang_thai');
      const tab = x && LOC.find((l) => l.tt && l.tt.includes(x.trang_thai));
      if (tab && tab.ma !== loc) { loc = tab.ma; nhoPhien.ghi('hs_tab', loc); capNhatTab(); await tai(); }
      dong = ketQua.querySelector(`tr[data-id="${id}"]`);
    }
    if (!dong) return;
    dong.classList.add('vua-luu');
    dong.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }
}
