// Nhân viên: giám đốc cấp vai trò, chi nhánh, tổ; khóa tài khoản khi nghỉ việc
import { h, truong, oChu, oChon, oCheck, docForm, bang, moModal, toast, VAI_TRO, dat } from '../ui.js';
import * as api from '../api.js';

export default async function trangNhanVien(el) {
  const vung = h('div');
  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Nhân viên')),
    h('section', { class: 'the' }, h('h2', null, 'Thêm người dùng mới'),
      h('ol', { class: 'goi-y' },
        h('li', null, 'Vào Supabase > Authentication > Users > "Invite user", nhập email của nhân viên hoặc cổ đông.'),
        h('li', null, 'Người đó mở email, bấm đường dẫn và tự đặt mật khẩu.'),
        h('li', null, 'Quay lại trang này, bấm "Cấp quyền" ở dòng của người đó để chọn vai trò. Chưa cấp vai trò thì người đó chưa dùng được gì.'))),
    vung);

  async function tai() {
    const rows = await api.doc('nhan_vien', (q) => q.order('tao_luc'));
    dat(vung, h('section', { class: 'the' }, h('h2', null, `Danh sách (${rows.length})`),
      bang([
        { nhan: 'Họ tên', lay: (r) => h('span', null, h('b', null, r.ho_ten), h('br'), h('small', null, r.email || '')) },
        { nhan: 'Vai trò', lay: (r) => r.vai_tro.length ? r.vai_tro.map((v) => VAI_TRO[v]).join(', ') : h('span', { class: 'nhan tt-canh-bao' }, 'Chưa cấp quyền') },
        { nhan: 'Chi nhánh', lay: (r) => api.dm.ten('chi_nhanh', r.chi_nhanh_id) },
        { nhan: 'Tổ', lay: (r) => api.dm.ten('to_thuc_hien', r.to_id) },
        { nhan: 'Trạng thái', lay: (r) => r.hoat_dong ? 'Đang làm' : 'Đã khóa' },
        { nhan: '', lay: (r) => h('button', { class: 'nut nho', type: 'button', onclick: () => moSua(r) }, r.vai_tro.length ? 'Sửa' : 'Cấp quyền') },
      ], rows)));
  }

  function moSua(r) {
    const form = h('form', { class: 'luoi-o' },
      truong('Họ tên', oChu('ho_ten', r.ho_ten)),
      truong('Chi nhánh', oChon('chi_nhanh_id', api.dm.chi_nhanh.map((c) => ({ value: c.id, label: c.ten })), r.chi_nhanh_id || api.toi.chi_nhanh_id)),
      h('fieldset', { class: 'nhom-o rong' }, h('legend', null, 'Vai trò (chọn được nhiều)'),
        Object.entries(VAI_TRO).map(([k, nhan]) => oCheck(`vt_${k}`, r.vai_tro.includes(k), nhan)),
        h('p', { class: 'goi-y' }, 'Cổ đông chỉ có một vai trò cổ đông. Trưởng nhóm phải chọn tổ.')),
      truong('Tổ (cho trưởng nhóm)', oChon('to_id', api.dm.to_thuc_hien.map((t) => ({ value: t.id, label: t.ten })), r.to_id, { trong: '— Không —' })),
      h('div', { class: 'truong' }, oCheck('hoat_dong', r.hoat_dong, 'Đang làm (bỏ chọn để khóa tài khoản)')));
    moModal(`Quyền của ${r.ho_ten}`, form, {
      rong: true,
      nutChinh: async () => {
        const d = docForm(form);
        const vai_tro = Object.keys(VAI_TRO).filter((k) => d[`vt_${k}`]);
        await api.luuNhanVien(r.id, { ho_ten: d.ho_ten, chi_nhanh_id: d.chi_nhanh_id, vai_tro, to_id: d.to_id, hoat_dong: d.hoat_dong });
        await api.taiDanhMuc();
        toast('Đã lưu.'); await tai();
      },
    });
  }
  await tai();
}
