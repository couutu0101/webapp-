// Nhân viên: giám đốc tạo tài khoản (tên đăng nhập = tên + bộ phận, không cần email mời),
// cấp / đổi quyền, đặt lại mật khẩu, khóa tài khoản khi nghỉ việc.
import { h, truong, oChu, oChon, oCheck, docForm, bang, moModal, toast, VAI_TRO, dat } from '../ui.js';
import * as api from '../api.js';

const boDau = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd').toLowerCase().replace(/[^a-z0-9]+/g, '');
const BO_PHAN = { giam_doc: 'giamdoc', quan_ly: 'quanly', ke_toan: 'ketoan', cvdv: 'cvdv', kho: 'kho', co_dong: 'codong' };
// Tên đăng nhập gợi ý: tên gọi + bộ phận (trưởng nhóm lấy tên tổ). Vd "Nguyễn Trọng Duy", CVDV → duy.cvdv
function goiYTen(hoTen, vaiTro, toId) {
  const ten = boDau(String(hoTen || '').trim().split(/\s+/).pop());
  if (!ten) return '';
  let bp = '';
  if (vaiTro.includes('truong_nhom')) bp = boDau(api.dm.ten('to_thuc_hien', toId) || toId || 'to');
  else bp = BO_PHAN[vaiTro.find((v) => BO_PHAN[v])] || '';
  return bp ? `${ten}.${bp}` : ten;
}
// Mật khẩu tạm dễ đọc qua điện thoại: hs + 4 số
const matKhauTam = () => `hs${String(crypto.getRandomValues(new Uint32Array(1))[0] % 10000).padStart(4, '0')}`;

function oVaiTro(daChon = []) {
  return h('fieldset', { class: 'nhom-o rong' }, h('legend', null, 'Bộ phận / vai trò (chọn được nhiều)'),
    Object.entries(VAI_TRO).map(([k, nhan]) => oCheck(`vt_${k}`, daChon.includes(k), nhan)),
    h('p', { class: 'goi-y' }, 'Cổ đông chỉ có một vai trò cổ đông. Trưởng nhóm phải chọn tổ.'));
}
const docVaiTro = (d) => Object.keys(VAI_TRO).filter((k) => d[`vt_${k}`]);
// 043: tổ chỉ gắn cho trưởng nhóm (máy chủ cũng tự bỏ tổ của tài khoản không phải trưởng nhóm): ô Tổ chỉ hiện khi chọn Trưởng nhóm
function oToTheoVai(form, truongTo) {
  const capNhat = () => { truongTo.hidden = !docVaiTro(docForm(form)).includes('truong_nhom'); };
  form.addEventListener('change', capNhat);
  capNhat();
}
const toCuaVai = (vaiTro, toId) => (vaiTro.includes('truong_nhom') ? toId || null : null);

// Hộp hiện tên đăng nhập + mật khẩu tạm để giám đốc đưa cho nhân viên
function moThongTinDangNhap(tieuDe, ten, mk) {
  const chu = `Tên đăng nhập: ${ten}\nMật khẩu tạm: ${mk}\nVào ${location.origin}${location.pathname} – lần đầu đăng nhập phải đổi mật khẩu riêng.`;
  moModal(tieuDe, h('div', null,
    h('dl', { class: 'thong-tin the-dang-nhap-nv' },
      h('dt', null, 'Tên đăng nhập'), h('dd', null, h('b', { 'data-ten-dang-nhap': '' }, ten)),
      h('dt', null, 'Mật khẩu tạm'), h('dd', null, h('b', { 'data-mat-khau-tam': '' }, mk))),
    h('p', { class: 'goi-y' }, 'Đưa cho nhân viên. Lần đầu đăng nhập phần mềm bắt đổi mật khẩu riêng, nên mật khẩu tạm chỉ dùng được một lần.'),
    h('button', { class: 'nut', type: 'button', onclick: async () => {
      try { await navigator.clipboard.writeText(chu); toast('Đã chép – dán gửi qua Zalo cho nhân viên.'); }
      catch { toast('Không chép được – anh ghi tay giúp em.', 'loi'); }
    } }, 'Chép để gửi Zalo')), { nutPhu: 'Xong' });
}

export default async function trangNhanVien(el) {
  const vung = h('div');
  dat(el,
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Nhân viên'),
      h('button', { class: 'nut chinh', type: 'button', onclick: () => moTao() }, '+ Tạo tài khoản nhân viên')),
    h('p', { class: 'mo-ta' }, 'Tạo tài khoản ngay tại đây, không cần email. Nhân viên đăng nhập bằng tên đăng nhập + mật khẩu tạm anh đưa, lần đầu tự đổi mật khẩu riêng. Quên mật khẩu: anh bấm "Đặt lại mật khẩu".'),
    vung);

  async function tai() {
    const rows = await api.doc('nhan_vien', (q) => q.order('tao_luc'));
    dat(vung, h('section', { class: 'the' }, h('h2', null, `Danh sách (${rows.length})`),
      bang([
        { nhan: 'Họ tên', lay: (r) => h('span', null, h('b', null, r.ho_ten), h('br'), h('small', null, r.ten_dang_nhap ? `Tên đăng nhập: ${r.ten_dang_nhap}` : (r.email || ''))) },
        { nhan: 'Bộ phận / vai trò', lay: (r) => (r.vai_tro.length ? r.vai_tro.map((v) => VAI_TRO[v]).join(', ') : h('span', { class: 'nhan tt-canh-bao' }, 'Chưa cấp quyền')) },
        { nhan: 'Chi nhánh', lay: (r) => api.dm.ten('chi_nhanh', r.chi_nhanh_id) },
        { nhan: 'Tổ', lay: (r) => (r.vai_tro.includes('truong_nhom') ? api.dm.ten('to_thuc_hien', r.to_id) : '') },
        { nhan: 'Trạng thái', lay: (r) => h('span', null, r.hoat_dong ? 'Đang làm' : 'Đã khóa',
          r.phai_doi_mat_khau ? h('span', { class: 'nhan tt-canh-bao' }, 'Chờ đổi mật khẩu') : null) },
        { nhan: '', lay: (r) => h('span', { class: 'hang-nut' },
          h('button', { class: 'nut nho', type: 'button', 'data-sua': r.id, onclick: () => moSua(r) }, r.vai_tro.length ? 'Sửa quyền' : 'Cấp quyền'),
          h('button', { class: 'nut nho', type: 'button', 'data-dat-lai': r.id, onclick: () => moDatLai(r) }, 'Đặt lại mật khẩu')) },
      ], rows)));
  }

  function moTao() {
    const oTen = oChu('ten_dang_nhap', '', { autocapitalize: 'none', spellcheck: 'false', placeholder: 'vd: duy.cvdv' });
    const oMk = oChu('mat_khau', matKhauTam(), { autocomplete: 'off' });
    const chonTo = oChon('to_id', api.dm.to_thuc_hien.map((t) => ({ value: t.id, label: t.ten })), '', { trong: '— Chọn tổ —' });
    const truongTo = truong('Tổ của trưởng nhóm', chonTo, null, { batBuoc: true });
    const form = h('form', { class: 'luoi-o', novalidate: true },
      truong('Họ tên', oChu('ho_ten', '', { placeholder: 'vd: Nguyễn Trọng Duy' }), null, { batBuoc: true }),
      truong('Chi nhánh', oChon('chi_nhanh_id', api.dm.chi_nhanh.map((c) => ({ value: c.id, label: c.ten })), api.toi.chi_nhanh_id)),
      oVaiTro(),
      truongTo,
      truong('Tên đăng nhập', oTen, 'Tự gợi ý theo tên + bộ phận, sửa được. Chữ không dấu, số, dấu chấm.', { batBuoc: true }),
      truong('Mật khẩu tạm', oMk, 'Ít nhất 6 ký tự. Nhân viên phải đổi ở lần đăng nhập đầu.', { batBuoc: true }));
    let daSuaTen = false;
    oTen.addEventListener('input', () => { daSuaTen = true; });
    const capNhatTen = () => { if (!daSuaTen) { const d = docForm(form); oTen.value = goiYTen(d.ho_ten, docVaiTro(d), d.to_id); } };
    form.addEventListener('input', (e) => { if (e.target !== oTen) capNhatTen(); });
    form.addEventListener('change', (e) => { if (e.target !== oTen) capNhatTen(); });
    oToTheoVai(form, truongTo);
    moModal('Tạo tài khoản nhân viên', form, {
      rong: true, nhanNut: 'Tạo tài khoản',
      nutChinh: async () => {
        const d = docForm(form);
        const vai_tro = docVaiTro(d);
        if (!d.ho_ten?.trim()) { toast('Nhập họ tên.', 'loi'); return false; }
        if (!vai_tro.length) { toast('Chọn bộ phận / vai trò.', 'loi'); return false; }
        if (!d.ten_dang_nhap?.trim()) { toast('Nhập tên đăng nhập.', 'loi'); return false; }
        if ((d.mat_khau || '').length < 6) { toast('Mật khẩu tạm cần ít nhất 6 ký tự.', 'loi'); return false; }
        const ten = d.ten_dang_nhap.trim().toLowerCase();
        if (vai_tro.includes('truong_nhom') && !d.to_id) { toast('Trưởng nhóm: chọn tổ.', 'loi'); return false; }
        await api.taoTaiKhoan({ ho_ten: d.ho_ten, ten_dang_nhap: ten, mat_khau: d.mat_khau, chi_nhanh_id: d.chi_nhanh_id, vai_tro, to_id: toCuaVai(vai_tro, d.to_id) });
        await api.taiDanhMuc();
        await tai();
        setTimeout(() => moThongTinDangNhap(`Đã tạo tài khoản ${d.ho_ten}`, ten, d.mat_khau));
      },
    });
  }

  function moSua(r) {
    const truongTo = truong('Tổ của trưởng nhóm', oChon('to_id', api.dm.to_thuc_hien.map((t) => ({ value: t.id, label: t.ten })), r.to_id, { trong: '— Chọn tổ —' }),
      null, { batBuoc: true });
    const form = h('form', { class: 'luoi-o' },
      truong('Họ tên', oChu('ho_ten', r.ho_ten)),
      truong('Chi nhánh', oChon('chi_nhanh_id', api.dm.chi_nhanh.map((c) => ({ value: c.id, label: c.ten })), r.chi_nhanh_id || api.toi.chi_nhanh_id)),
      oVaiTro(r.vai_tro),
      truongTo,
      // 041: không tự khóa tài khoản của chính mình (khóa rồi không ai mở lại được)
      r.id === api.toi.id ? h('p', { class: 'goi-y' }, 'Tài khoản của anh/chị – không tự khóa được.')
        : h('div', { class: 'truong' }, oCheck('hoat_dong', r.hoat_dong, 'Đang làm (bỏ chọn để khóa tài khoản)')));
    oToTheoVai(form, truongTo);
    moModal(`Quyền của ${r.ho_ten}`, form, {
      rong: true,
      nutChinh: async () => {
        const d = docForm(form);
        const vai_tro = docVaiTro(d);
        if (vai_tro.includes('truong_nhom') && !d.to_id) { toast('Trưởng nhóm: chọn tổ.', 'loi'); return false; }
        await api.luuNhanVien(r.id, { ho_ten: d.ho_ten, chi_nhanh_id: d.chi_nhanh_id, vai_tro, to_id: toCuaVai(vai_tro, d.to_id), hoat_dong: d.hoat_dong });
        await api.taiDanhMuc();
        toast('Đã lưu.'); await tai();
      },
    });
  }

  function moDatLai(r) {
    const laToi = r.id === api.toi.id;
    const oMk = oChu('mat_khau', laToi ? '' : matKhauTam(), { autocomplete: 'off' });
    const form = h('form', null,
      h('p', { class: 'mo-ta' }, laToi ? 'Đặt mật khẩu mới cho chính anh.'
        : `${r.ho_ten}${r.ten_dang_nhap ? ` (${r.ten_dang_nhap})` : ''} sẽ bị đăng xuất khỏi các máy đang dùng; lần đăng nhập sau phải đổi mật khẩu riêng.`),
      truong('Mật khẩu mới', oMk, 'Ít nhất 6 ký tự.', { batBuoc: true }));
    moModal(`Đặt lại mật khẩu – ${r.ho_ten}`, form, {
      nhanNut: 'Đặt lại mật khẩu',
      nutChinh: async () => {
        if ((oMk.value || '').length < 6) { toast('Mật khẩu cần ít nhất 6 ký tự.', 'loi'); return false; }
        await api.datLaiMatKhau(r.id, oMk.value);
        await tai();
        if (laToi) toast('Đã đổi mật khẩu của anh.');
        else setTimeout(() => moThongTinDangNhap(`Đã đặt lại mật khẩu – ${r.ho_ten}`, r.ten_dang_nhap || r.email, oMk.value));
      },
    });
  }
  await tai();
}
