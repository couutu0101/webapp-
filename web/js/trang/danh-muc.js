// Danh mục và cài đặt: giám đốc, kế toán thêm / sửa. Không xóa – bỏ chọn "Đang dùng" để ẩn.
import { h, tien, ngay, truong, oChu, oTien, oChon, oNgay, oCheck, docForm, bang, moModal, toast, dat } from '../ui.js';
import * as api from '../api.js';

const TINH_CHAT = {
  thu_khach: 'Thu của khách (gắn xe)', thu_bao_hiem: 'Bảo hiểm trả', thu_coc: 'Thu cọc (gắn xe)', thu_dich_vu_nhanh: 'Thu dịch vụ nhanh',
  thu_khac: 'Thu khác', thu_noi_bo: 'Thu nội bộ',
  chi_phi: 'Chi phí (vào lãi lỗ)', tra_ncc: 'Trả nhà cung cấp', tra_hoa_hong: 'Trả hoa hồng GDV', tra_luong: 'Trả lương',
  tam_ung: 'Tạm ứng', tra_noi_bo: 'Trả nội bộ', tra_coc: 'Trả lại cọc', nop_thue: 'Nộp thuế',
};
const NHOM_CHI = { gia_von: 'Giá vốn', co_dinh: 'Cố định', van_hanh: 'Vận hành' };

const DANH_MUC = [
  { bang: 'hang_bao_hiem', ten: 'Hãng bảo hiểm', cot: [{ k: 'ten', nhan: 'Tên', batBuoc: true }, { k: 'hoat_dong', nhan: 'Đang dùng', loai: 'bool' }] },
  { bang: 'giam_dinh_vien', ten: 'Giám định viên', cot: [{ k: 'ten', nhan: 'Tên', batBuoc: true }, { k: 'hang_id', nhan: 'Hãng', loai: 'chon', nguon: 'hang_bao_hiem' }, { k: 'dien_thoai', nhan: 'SĐT' }, { k: 'hoat_dong', nhan: 'Đang dùng', loai: 'bool' }],
    ghiChu: 'Gặp hồ sơ ghi "GDV mới – chờ thêm": thêm người đó ở đây, rồi vào hồ sơ bấm Sửa để chọn lại đúng người.' },
  { bang: 'hang_xe', ten: 'Hãng xe', cot: [{ k: 'ten', nhan: 'Tên', batBuoc: true }] },
  { bang: 'dong_xe', ten: 'Dòng xe', cot: [{ k: 'hang_xe_id', nhan: 'Hãng xe', loai: 'chon', nguon: 'hang_xe', batBuoc: true }, { k: 'ten', nhan: 'Dòng xe', batBuoc: true }] },
  { bang: 'tai_khoan_quy', ten: 'Tài khoản quỹ', coDinh: () => ({ chi_nhanh_id: api.toi.chi_nhanh_id }),
    cot: [{ k: 'ten', nhan: 'Tên', batBuoc: true }, { k: 'so_du_dau_ky', nhan: 'Số dư đầu kỳ', loai: 'tien' }, { k: 'ngay_dau_ky', nhan: 'Ngày đầu kỳ', loai: 'ngay' }, { k: 'hoat_dong', nhan: 'Đang dùng', loai: 'bool' }],
    ghiChu: 'Số dư đầu kỳ nhập một lần lúc bắt đầu dùng phần mềm (số dư ngày 31/10/2026). Tài khoản cá nhân nhân viên: bỏ chọn "Đang dùng".' },
  { bang: 'muc_thu_chi', ten: 'Mục thu chi', cot: [
    { k: 'loai', nhan: 'Loại', loai: 'chon', ds: { thu: 'Thu', chi: 'Chi' }, batBuoc: true }, { k: 'ten', nhan: 'Tên', batBuoc: true },
    { k: 'nhom', nhan: 'Nhóm chi phí', loai: 'chon', ds: NHOM_CHI }, { k: 'tinh_chat', nhan: 'Tính chất', loai: 'chon', ds: TINH_CHAT, batBuoc: true },
    { k: 'can_ho_so', nhan: 'Bắt buộc gắn xe', loai: 'bool' }, { k: 'hoat_dong', nhan: 'Đang dùng', loai: 'bool' }],
    ghiChu: '"Tính chất" quyết định khoản đó có vào lãi lỗ hay không: chỉ "Chi phí" vào lãi lỗ; trả nhà cung cấp, tạm ứng, trả nội bộ chỉ trừ công nợ.' },
  { bang: 'nha_cung_cap', ten: 'Nhà cung cấp', cot: [{ k: 'ten', nhan: 'Tên', batBuoc: true }, { k: 'hoat_dong', nhan: 'Đang dùng', loai: 'bool' }] },
  { bang: 'don_vi_lien_quan', ten: 'Đơn vị liên quan', cot: [{ k: 'ten', nhan: 'Tên', batBuoc: true }] },
  { bang: 'cai_dat', ten: 'Cài đặt', khoa: 'khoa', chiGD: true, khongThem: true,
    cot: [{ k: 'mo_ta', nhan: 'Nội dung', chiXem: true }, { k: 'gia_tri', nhan: 'Giá trị', loai: 'so', batBuoc: true }] },
  { bang: 'thue_suat_vat', ten: 'Thuế suất VAT', khoa: 'ap_dung_tu', chiGD: true, khongSua: true,
    cot: [{ k: 'ap_dung_tu', nhan: 'Áp dụng từ ngày', loai: 'ngay', batBuoc: true }, { k: 'ty_le', nhan: 'Tỷ lệ (0,08 = 8%)', loai: 'so', batBuoc: true }],
    ghiChu: 'Khi thuế suất đổi (ví dụ trở lại 10%), thêm một dòng mới với ngày áp dụng. Không sửa dòng cũ để số liệu các tháng trước giữ nguyên.' },
];

export default async function trangDanhMuc(el) {
  const ds = DANH_MUC.filter((d) => !d.chiGD || api.coVaiTro('giam_doc'));
  let chon = ds[0];
  const vung = h('div');
  const chonDM = h('select', { 'aria-label': 'Chọn danh mục', onchange: (e) => { chon = ds.find((d) => d.bang === e.target.value); tai(); } },
    ds.map((d) => h('option', { value: d.bang }, d.ten)));
  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Danh mục'), chonDM), vung);

  async function tai() {
    const cfg = chon;
    const khoa = cfg.khoa || 'id';
    let rows = await api.doc(cfg.bang, (q) => q.order(khoa));
    if (cfg.bang === 'tai_khoan_quy') rows = rows.filter((r) => r.chi_nhanh_id === api.toi.chi_nhanh_id);
    const hienThi = (c, r) => {
      const v = r[c.k];
      if (c.loai === 'bool') return v ? '✓' : '—';
      if (c.loai === 'chon' && c.nguon) return api.dm.ten(c.nguon, v);
      if (c.loai === 'chon' && c.ds) return c.ds[v] || v || '';
      if (c.loai === 'tien') return tien(v);
      if (c.loai === 'ngay') return ngay(v);
      return v ?? '';
    };
    dat(vung, h('section', { class: 'the' },
      h('div', { class: 'the-dau' }, h('h2', null, cfg.ten),
        cfg.khongThem ? null : h('button', { class: 'nut chinh', type: 'button', onclick: () => moForm(cfg, null) }, '+ Thêm')),
      cfg.ghiChu ? h('p', { class: 'goi-y' }, cfg.ghiChu) : null,
      bang([...cfg.cot.map((c) => ({ nhan: c.nhan, lay: (r) => hienThi(c, r) })),
        cfg.khongSua ? null : { nhan: '', lay: (r) => h('button', { class: 'nut-chu', type: 'button', onclick: (e) => { e.stopPropagation(); moForm(cfg, r); } }, 'Sửa') }].filter(Boolean), rows)));
  }

  function moForm(cfg, r) {
    const form = h('form', { class: 'luoi-o' }, cfg.cot.map((c) => {
      const v = r ? r[c.k] : (c.loai === 'bool' ? true : null);
      if (c.chiXem) return r ? h('p', { class: 'rong' }, h('b', null, r.khoa), ' – ', v) : null;
      let o;
      if (c.loai === 'bool') return h('div', { class: 'truong' }, oCheck(c.k, v, c.nhan));
      if (c.loai === 'chon' && c.nguon) o = oChon(c.k, (api.dm[c.nguon] || []).map((x) => ({ value: x.id, label: x.ten })), v);
      else if (c.loai === 'chon') o = oChon(c.k, Object.entries(c.ds).map(([value, label]) => ({ value, label })), v);
      else if (c.loai === 'tien') o = oTien(c.k, v);
      else if (c.loai === 'ngay') o = oNgay(c.k, v);
      else if (c.loai === 'so') o = oChu(c.k, v, { inputmode: 'decimal' });
      else o = oChu(c.k, v);
      return truong(c.nhan, o, null, { batBuoc: c.batBuoc });
    }));
    moModal(`${r ? 'Sửa' : 'Thêm'} – ${cfg.ten}`, form, {
      nutChinh: async () => {
        const d = docForm(form);
        for (const c of cfg.cot) {
          if (c.chiXem) delete d[c.k];
          else if (c.batBuoc && (d[c.k] === null || d[c.k] === undefined || d[c.k] === '')) { toast(`Thiếu "${c.nhan}".`, 'loi'); return false; }
          if (c.loai === 'so' && d[c.k] !== null) d[c.k] = Number(String(d[c.k]).replace(',', '.'));
        }
        Object.assign(d, cfg.coDinh ? cfg.coDinh() : {});
        if (r) await api.sua(cfg.bang, r[cfg.khoa || 'id'], d, cfg.khoa || 'id');
        else await api.them(cfg.bang, d);
        await api.taiDanhMuc();
        toast('Đã lưu.'); await tai();
      },
    });
  }
  await tai();
}
