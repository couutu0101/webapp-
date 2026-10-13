// Đề nghị chi → duyệt (quản lý chung đến 2 triệu, trên 2 triệu giám đốc) → kế toán chi
import { h, tien, ngay, homNay, truong, oChu, oTien, oChon, oNgay, oVung, docForm, chay, bang, moModal, toast, dat } from '../ui.js';
import * as api from '../api.js';

const TT = { cho_duyet: 'Chờ duyệt', da_duyet: 'Đã duyệt – chờ chi', tu_choi: 'Từ chối', da_chi: 'Đã chi', huy: 'Đã hủy' };

export default async function trangDeNghi(el) {
  const nguoiDuyet = api.coVaiTro('quan_ly', 'giam_doc');
  const keToan = api.coVaiTro('ke_toan', 'giam_doc');
  const hanMuc = api.caiDat('han_muc_chi_quan_ly', 2000000);
  let loc = nguoiDuyet ? 'cho_duyet' : keToan ? 'da_duyet' : 'cua_toi';
  const ds = h('div');
  const LOC = [
    nguoiDuyet ? ['cho_duyet', 'Chờ duyệt'] : null,
    keToan ? ['da_duyet', 'Chờ chi'] : null,
    ['cua_toi', 'Của tôi'],
    nguoiDuyet || keToan ? ['tat', 'Tất cả (60 ngày)'] : null,
  ].filter(Boolean);
  const tabs = h('div', { class: 'tabs', role: 'tablist' }, LOC.map(([ma, nhan]) => h('button', {
    type: 'button', role: 'tab', 'aria-selected': String(ma === loc), 'data-ma': ma,
    onclick: () => { loc = ma; for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); tai(); },
  }, nhan)));

  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Đề nghị chi'),
      h('button', { class: 'nut chinh', type: 'button', onclick: () => moLap() }, '+ Lập đề nghị chi')),
    h('p', { class: 'mo-ta' }, `Mọi khoản chi đều qua đề nghị. Quản lý chung duyệt đến ${tien(hanMuc)} đ, trên mức này giám đốc duyệt. Không ai tự duyệt đề nghị của mình. Kế toán chỉ chi khi đã duyệt.`),
    h('section', { class: 'the' }, tabs, ds));

  async function tai() {
    dat(ds, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    const rows = await api.doc('v_de_nghi_chi', (q) => {
      if (loc === 'cho_duyet') q = q.eq('trang_thai', 'cho_duyet');
      else if (loc === 'da_duyet') q = q.eq('trang_thai', 'da_duyet');
      else if (loc === 'cua_toi') q = q.eq('nguoi_de_nghi', api.toi.id);
      else q = q.gte('ngay', new Date(Date.now() - 60 * 864e5).toISOString().slice(0, 10));
      return q.order('id', { ascending: false }).limit(300);
    });
    dat(ds, bang([
      { nhan: 'Ngày', lay: (r) => ngay(r.ngay) },
      { nhan: 'Người đề nghị', lay: (r) => r.nguoi_de_nghi_ten },
      { nhan: 'Mục', lay: (r) => r.muc },
      { nhan: 'Nội dung', lay: (r) => h('span', null, r.noi_dung,
        [r.nguoi_nhan, r.nha_cung_cap, r.gdv, r.don_vi_lien_quan, r.ho_so_ma].filter(Boolean).length
          ? h('small', null, ' · ' + [r.nguoi_nhan, r.nha_cung_cap, r.gdv, r.don_vi_lien_quan, r.ho_so_ma].filter(Boolean).join(' · ')) : null,
        r.nghi_tach_phieu && r.trang_thai === 'cho_duyet' ? h('span', { class: 'nhan tt-canh-bao' }, 'Nghi tách nhỏ phiếu') : null) },
      { nhan: 'Số tiền', so: true, lay: (r) => h('span', null, tien(r.so_tien), r.can_giam_doc ? h('small', { class: 'nhan' }, 'GĐ duyệt') : null) },
      { nhan: 'Trạng thái', lay: (r) => h('span', null, TT[r.trang_thai], r.nguoi_duyet_ten ? h('small', null, ` · ${r.nguoi_duyet_ten}`) : null,
        r.ly_do_tu_choi ? h('small', null, ` · ${r.ly_do_tu_choi}`) : null) },
      { nhan: '', lay: (r) => h('span', { class: 'hang-nut' }, nutHanhDong(r)) },
    ], rows, { trong: 'Không có đề nghị nào.' }));
  }

  function nutHanhDong(r) {
    const ra = [];
    const laCuaToi = r.nguoi_de_nghi === api.toi.id;
    // Không tự duyệt phiếu mình lập – trừ giám đốc
    const duocDuyet = nguoiDuyet && (!laCuaToi || api.coVaiTro('giam_doc')) && (!r.can_giam_doc || api.coVaiTro('giam_doc'));
    if (r.trang_thai === 'cho_duyet' && duocDuyet) {
      ra.push(h('button', { class: 'nut nho chinh', type: 'button', onclick: () => chay(() => api.duyetDeNghi(r.id, true, null), { thanhCong: 'Đã duyệt.' }).then(tai).catch(() => {}) }, 'Duyệt'));
      ra.push(h('button', { class: 'nut nho', type: 'button', onclick: () => moTuChoi(r) }, 'Từ chối'));
    }
    if (r.trang_thai === 'da_duyet' && keToan) ra.push(h('button', { class: 'nut nho chinh', type: 'button', onclick: () => moChi(r) }, 'Chi tiền'));
    if (['cho_duyet', 'da_duyet'].includes(r.trang_thai) && (laCuaToi || keToan)) {
      ra.push(h('button', { class: 'nut-chu', type: 'button', onclick: () => chay(() => api.huyDeNghi(r.id), { thanhCong: 'Đã hủy đề nghị.' }).then(tai).catch(() => {}) }, 'Hủy'));
    }
    return ra;
  }

  function moTuChoi(r) {
    const form = h('form', null, truong('Lý do từ chối', oVung('ly_do', ''), null, { batBuoc: true }));
    moModal('Từ chối đề nghị', form, { nhanNut: 'Từ chối', nutChinh: async () => { await api.duyetDeNghi(r.id, false, docForm(form).ly_do); toast('Đã từ chối.'); await tai(); } });
  }

  function moChi(r) {
    const tks = (api.dm.tai_khoan_quy || []).filter((t) => t.hoat_dong && t.chi_nhanh_id === r.chi_nhanh_id);
    const form = h('form', null,
      h('p', null, `${r.noi_dung}: `, h('b', null, `${tien(r.so_tien)} đ`)),
      truong('Chi từ tài khoản', oChon('tai_khoan_id', tks.map((t) => ({ value: t.id, label: t.ten })), tks[0]?.id, { trong: null })),
      truong('Ngày chi', oNgay('ngay', homNay(), { max: homNay() })));
    moModal('Chi tiền', form, { nhanNut: 'Lập phiếu chi', nutChinh: async () => { const d = docForm(form); await api.chiTien(r.id, d.tai_khoan_id, d.ngay); toast('Đã chi.'); await tai(); } });
  }

  // Các kỳ chi phí chọn được: tháng này, 2 tháng trước
  function cacKy() {
    const d = new Date(); const ds = [];
    for (let i = 0; i < 3; i++) {
      const t = new Date(d.getFullYear(), d.getMonth() - i, 1);
      const v = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-01`;
      ds.push({ value: v, label: `${i === 0 ? 'Tháng này' : i === 1 ? 'Tháng trước' : 'Hai tháng trước'} (${String(t.getMonth() + 1).padStart(2, '0')}/${t.getFullYear()})` });
    }
    return ds;
  }

  async function moLap({ mucTen = null, kyMacDinh = null } = {}) {
    const mucChi = api.dm.muc_thu_chi.filter((m) => m.loai === 'chi' && m.hoat_dong);
    const NHOM = { gia_von: 'Giá vốn', co_dinh: 'Chi phí cố định', van_hanh: 'Chi phí vận hành' };
    const chonMuc = h('select', { name: 'muc_id' }, h('option', { value: '' }, '— Chọn —'),
      [...new Set(mucChi.map((m) => m.nhom || 'khac'))].map((n) => h('optgroup', { label: NHOM[n] || 'Không tính vào lãi lỗ' },
        mucChi.filter((m) => (m.nhom || 'khac') === n).map((m) => h('option', { value: m.id }, m.ten)))));
    const vungRieng = h('div', { class: 'luoi-o rong' });
    const hoSo = api.laNhanVien() ? await api.doc('v_ho_so', (q) => q.not('trang_thai', 'in', '(huy)').order('ngay_vao', { ascending: false }).limit(300)) : [];
    chonMuc.addEventListener('change', () => {
      const m = mucChi.find((x) => String(x.id) === chonMuc.value);
      dat(vungRieng, );
      if (!m) return;
      if (m.can_ho_so || ['tra_hoa_hong', 'tra_coc'].includes(m.tinh_chat)) {
        vungRieng.append(truong('Xe', oChon('ho_so_id', hoSo.map((x) => ({ value: x.id, label: `${x.bien_so_hien_thi || x.ma} – ${x.ten_khach}${x.gdv ? ` – GDV ${x.gdv}` : ''}` })), null), null, { batBuoc: true }));
      }
      if (m.tinh_chat === 'tra_hoa_hong') vungRieng.append(truong('Giám định viên', oChon('gdv_id', api.dm.giam_dinh_vien.filter((g) => !g.la_cho_them).map((g) => ({ value: g.id, label: `${g.ten}${g.hang_id ? ` (${api.dm.ten('hang_bao_hiem', g.hang_id)})` : ''}` })), null), null, { batBuoc: true }));
      if (m.tinh_chat === 'tra_ncc') vungRieng.append(truong('Nhà cung cấp', oChon('nha_cung_cap_id', api.dm.nha_cung_cap.filter((x) => x.hoat_dong).map((x) => ({ value: x.id, label: x.ten })), null), null, { batBuoc: true }));
      if (m.tinh_chat === 'tra_noi_bo') vungRieng.append(truong('Đơn vị', oChon('don_vi_lien_quan_id', api.dm.don_vi_lien_quan.map((x) => ({ value: x.id, label: x.ten })), null), null, { batBuoc: true }));
      if (m.tinh_chat === 'chi_phi') {
        vungRieng.append(truong('VAT trên hóa đơn (nếu có)', oTien('vat_dau_vao', null), 'Phần VAT đã nằm trong số tiền, dùng để tính VAT phải nộp'));
        // Kỳ chi phí: tiền điện, nước… của tháng trước nhưng chi tháng này thì chọn tháng trước → tính vào lãi lỗ tháng trước
        const kyChon = oChon('ky_chi_phi', cacKy(), kyMacDinh || cacKy()[0].value, { trong: null, 'aria-label': 'Chi phí của tháng' });
        vungRieng.append(truong('Chi phí của tháng', kyChon, 'Hóa đơn của tháng trước (điện, nước, mặt bằng…) thì chọn tháng trước để tính đúng kỳ. Tháng đã chốt sổ thì không chọn được.'));
      }
    });
    if (mucTen) { const m = mucChi.find((x) => x.ten === mucTen); if (m) { chonMuc.value = String(m.id); chonMuc.dispatchEvent(new Event('change')); } }
    const form = h('form', { class: 'luoi-o', novalidate: true },
      truong('Mục chi', chonMuc, null, { batBuoc: true }),
      truong('Số tiền', oTien('so_tien', null), null, { batBuoc: true }),
      truong('Nội dung', oChu('noi_dung', ''), null, { batBuoc: true, rong: true }),
      truong('Người nhận tiền', oChu('nguoi_nhan', '')),
      truong('Ngày', oNgay('ngay', homNay())),
      vungRieng);
    moModal('Lập đề nghị chi', form, {
      rong: true, nhanNut: 'Gửi đề nghị',
      nutChinh: async () => { await api.lapDeNghiChi(docForm(form)); toast('Đã gửi đề nghị.'); loc = 'cua_toi'; for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); await tai(); },
    });
  }

  await tai();
  // Mở sẵn form từ trang Kết quả kinh doanh: #/de-nghi?lap=1&muc=Điện&ky=2026-10-01
  const thamSo = new URLSearchParams(location.hash.split('?')[1] || '');
  if (thamSo.get('lap')) { history.replaceState(null, '', '#/de-nghi'); await moLap({ mucTen: thamSo.get('muc'), kyMacDinh: thamSo.get('ky') }); }
}
