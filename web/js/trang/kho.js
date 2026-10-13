// Kho: tồn kho, đề xuất vật tư → xuất cho xe, nhập kho, mua hàng, kiểm kê, công nợ nhà cung cấp, nhập – xuất – tồn.
// Theo đặc tả 11/10/2026. Tồn theo đơn vị xuất; giá vốn nhập trước xuất trước, đã gồm VAT.
import {
  h, tien, ngay, ngayGio, homNay, truong, oChu, oTien, oChon, oNgay, oVung, oCheck, oChonTep, docTien, chay, bang,
  moModal, toast, dat, xacNhan, bienSo, nenAnh, taiTepCSV, nhoPhien, cuoiThang,
} from '../ui.js';
import * as api from '../api.js';
import { nutXuatExcel, xuatExcelKho } from './xuat-excel.js';

export const NHOM_HANG = ['Sơn', 'Nhám', 'Vật tư phụ', 'Phụ tùng', 'Dầu nhớt', 'Detailing', 'Khác'];
const DVT_GOI_Y = ['Cái', 'Bộ', 'Chai', 'Lít', 'Can 4L', 'Bình 20L', 'Hộp', 'Cây', 'Tờ', 'Kg', 'Mét', 'Cuộn'];
const MUC_VAT = [[0, '0%'], [0.08, '8%'], [0.1, '10%']];
const TT_DE_XUAT = { cho_xuat: 'Chờ xuất', da_xuat: 'Đã xuất đủ', huy: 'Đã hủy' };
const TT_MUA = { cho_duyet: 'Chờ duyệt', da_duyet: 'Đã duyệt – chờ hàng', tu_choi: 'Từ chối', da_nhap: 'Đã nhập', huy: 'Đã hủy' };
const TT_NHAP = { cho_khop: 'Chờ kế toán khớp', da_khop: 'Đã khớp hóa đơn', treo: 'Treo – lệch', huy: 'Đã hủy' };
const PHAM_VI = { son_nham: 'Sơn và nhám', toan_kho: 'Toàn kho', chon: 'Chọn mã' };

// Số lượng: tối đa 3 số lẻ, dấu phẩy kiểu Việt Nam
export const sl = (n) => (n === null || n === undefined || n === '' ? '' : Number(n).toLocaleString('vi-VN', { maximumFractionDigits: 3 }));
const oSoLuong = (name, value = '', attrs = {}) => h('input', { type: 'number', name, min: '0', step: 'any', inputmode: 'decimal', value: value ?? '', class: 'o-so', ...attrs });
const docSo = (v) => (v === '' || v === null || v === undefined ? null : Number(String(v).replace(',', '.')));
const ql = () => api.coVaiTro('quan_ly', 'giam_doc');
const laKho = () => api.coVaiTro('kho', 'giam_doc');
const keToan = () => api.coVaiTro('ke_toan', 'giam_doc');
const chungTu = (r) => ({ id: r.id, ma: r.ma, chi_nhanh_id: r.chi_nhanh_id || api.toi.chi_nhanh_id });

// Danh sách hàng (tồn hiện tại) dùng chung cho các ô chọn
let dsHang = [];
export async function taiHang() {
  dsHang = await api.doc('v_ton_kho', (q) => q.order('nhom').order('ma'));
  return dsHang;
}
const hangTheoId = (id) => dsHang.find((x) => String(x.id) === String(id));
function oChonHang(name = 'hang_id', value = null, { chiConHang = false } = {}) {
  const ds = dsHang.filter((x) => x.hoat_dong && (!chiConHang || Number(x.ton) > 0));
  return oChon(name, ds.map((x) => ({ value: x.id, label: `${x.ma} – ${x.ten} (tồn ${sl(x.ton)} ${x.dvt})` })), value, { trong: '— Chọn mã hàng —' });
}
const dvtNhap = (x) => x?.dvt_nhap || x?.dvt || '';
const quyDoi = (x) => (x && x.dvt_nhap && Number(x.he_so) !== 1 ? `1 ${x.dvt_nhap} = ${sl(x.he_so)} ${x.dvt}` : '');

// Hồ sơ đang có lệnh sửa chữa (được cấp phụ tùng)
// Trưởng nhóm không đọc bảng hồ sơ: lấy từ bảng việc của tổ
async function hoSoDangSua() {
  if (!api.laNhanVien()) {
    const ds = await api.bangViecTo().catch(() => []);
    return ds.map((x) => ({ id: x.ho_so_id, ma: x.ma, bien_so_hien_thi: x.bien_so, xe: x.xe }));
  }
  return api.doc('v_ho_so', (q) => q.in('trang_thai', ['dang_sua', 'cho_kcs']).order('ngay_vao', { ascending: false }));
}
const nhanXe = (x) => `${x.bien_so_hien_thi || x.ma} · ${x.ma}${x.xe ? ` · ${x.xe}` : ''}`;

// Danh sách dòng nhập trong hộp thoại: mỗi dòng một khối, nút "+ Thêm dòng"
function khungDong(taoDong, nhanThem = '+ Thêm dòng') {
  const ds = h('div', { class: 'ds-dong-nhap' });
  const them = (...a) => { const d = taoDong(...a); const dong = h('div', { class: 'dong-kho' }, d.o,
    h('button', { class: 'nut-chu', type: 'button', onclick: () => { dong.remove(); d.khiBo?.(); }, 'aria-label': 'Bỏ dòng này' }, 'Bỏ dòng'));
    dong.doc = d.doc; ds.append(dong); return dong; };
  return { el: h('div', null, ds, h('button', { class: 'nut', type: 'button', onclick: () => them() }, nhanThem)), them,
    doc: () => [...ds.children].map((d) => d.doc()).filter(Boolean), ds };
}

export default async function trangKho(el) {
  await taiHang();
  const vanPhong = api.laNhanVien();
  const THE = [
    ['ton', 'Tồn kho', true],
    ['de_xuat', 'Đề xuất & xuất', true],
    ['nhap', 'Nhập kho', vanPhong],
    ['mua', 'Mua hàng', vanPhong],
    ['kiem_ke', 'Kiểm kê', api.coVaiTro('kho', 'quan_ly', 'giam_doc')],
    ['cong_no', 'Công nợ NCC', api.coVaiTro('kho', 'quan_ly', 'giam_doc', 'ke_toan')],
    ['nxt', 'Nhập – xuất – tồn', api.coVaiTro('kho', 'quan_ly', 'giam_doc', 'ke_toan')],
  ].filter((t) => t[2]);
  const thamSo = new URLSearchParams(location.hash.split('?')[1] || '');
  let the = thamSo.get('the') || nhoPhien.doc('kho_the') || 'ton';
  if (!THE.some((t) => t[0] === the)) the = 'ton';
  const vung = h('div');
  const tabs = h('div', { class: 'tabs', role: 'tablist' }, THE.map(([ma, nhan]) => h('button', {
    type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === the),
    onclick: () => { the = ma; nhoPhien.ghi('kho_the', ma); for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === the)); ve(); },
  }, nhan)));
  const nut = h('div', { class: 'hang-nut' });
  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Kho'), nut), h('div', { class: 'thanh-loc' }, tabs), vung);

  async function ve() {
    dat(nut); dat(vung, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    await taiHang();
    const VE = { ton: veTon, de_xuat: veDeXuat, nhap: veNhap, mua: veMua, kiem_ke: veKiemKe, cong_no: veCongNo, nxt: veNxt };
    await VE[the]();
  }
  const ctx = { ve, vung, nut };

  // ---------------- Tồn kho ----------------
  async function veTon() {
    if (api.coVaiTro('kho', 'quan_ly', 'giam_doc')) nut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => moHang(null, ve) }, '+ Mã hàng'));
    if (laKho()) nut.append(h('button', { class: 'nut', type: 'button', onclick: () => moXuatDungChung(ve) }, 'Xuất dùng chung'));
    const nutExcel = nutXuatExcel('Xuất Excel', xuatExcelKho);
    if (nutExcel) nut.append(nutExcel);
    let tuKhoa = ''; let nhom = ''; let chiThieu = false;
    const oTim = h('input', { type: 'search', placeholder: 'Tìm mã, tên hàng…', 'aria-label': 'Tìm hàng' });
    const chonNhom = oChon('nhom', NHOM_HANG.map((x) => ({ value: x, label: x })), '', { trong: 'Mọi nhóm', 'aria-label': 'Nhóm hàng' });
    const tichThieu = oCheck('thieu', false, 'Dưới mức tối thiểu');
    const kq = h('div');
    const veBang = () => {
      const g = tuKhoa.toLowerCase();
      const ds = dsHang.filter((x) => (!g || `${x.ma} ${x.ten}`.toLowerCase().includes(g)) && (!nhom || x.nhom === nhom) && (!chiThieu || x.duoi_toi_thieu));
      const coGia = api.laNhanVien();
      const tongGT = ds.reduce((s, x) => s + Number(x.gia_tri || 0), 0);
      dat(kq,
        h('p', { class: 'mo-ta' }, `${ds.length} mã`, coGia ? ` · Giá trị tồn ${tien(tongGT)} đ` : '',
          ` · ${dsHang.filter((x) => x.duoi_toi_thieu).length} mã dưới mức tối thiểu`),
        bang([
          { nhan: 'Mã', lay: (x) => h('b', null, x.ma) },
          { nhan: 'Tên hàng', lay: (x) => h('span', null, x.ten, !x.hoat_dong ? h('small', { class: 'nhan' }, 'ngừng dùng') : null) },
          { nhan: 'Nhóm', lay: (x) => x.nhom },
          { nhan: 'Tồn', so: true, lay: (x) => h('span', { class: x.duoi_toi_thieu ? 'chu-loi' : null }, `${sl(x.ton)} ${x.dvt}`) },
          { nhan: 'Tối thiểu', so: true, lay: (x) => (Number(x.ton_toi_thieu) ? sl(x.ton_toi_thieu) : '') },
          coGia ? { nhan: 'Giá trị', so: true, lay: (x) => tien(x.gia_tri) } : null,
          { nhan: 'Nhà cung cấp', lay: (x) => x.nha_cung_cap || '' },
        ].filter(Boolean), ds, { onRow: (x) => moTheKho(x, ve), trong: dsHang.length ? 'Không có mã nào khớp.' : 'Chưa có mã hàng nào. Bấm "+ Mã hàng" để thêm.' }));
    };
    oTim.addEventListener('input', () => { tuKhoa = oTim.value.trim(); veBang(); });
    chonNhom.addEventListener('change', () => { nhom = chonNhom.value; veBang(); });
    tichThieu.querySelector('input').addEventListener('change', (e) => { chiThieu = e.target.checked; veBang(); });
    dat(vung, h('section', { class: 'the' }, h('div', { class: 'thanh-loc' }, oTim, chonNhom, tichThieu), kq));
    veBang();
  }

  // ---------------- Đề xuất & xuất ----------------
  async function veDeXuat() {
    if (api.coVaiTro('truong_nhom', 'cvdv', 'kho', 'quan_ly', 'giam_doc')) {
      nut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => moLapDeXuat(null, ve) }, '+ Đề xuất vật tư'));
    }
    let loc = 'cho_xuat';
    const kq = h('div');
    const tabsCon = h('div', { class: 'tabs nho', role: 'tablist' }, [['cho_xuat', 'Chờ xuất'], ['tat', 'Tất cả (60 ngày)']].map(([ma, nhan]) =>
      h('button', { type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === loc),
        onclick: () => { loc = ma; for (const b of tabsCon.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); tai(); } }, nhan)));
    async function tai() {
      dat(kq, h('div', { class: 'dang-tai' }, 'Đang tải…'));
      const ds = await api.doc('v_de_xuat', (q) => (loc === 'cho_xuat' ? q.eq('trang_thai', 'cho_xuat')
        : q.gte('tao_luc', new Date(Date.now() - 60 * 864e5).toISOString())).order('id', { ascending: false }).limit(300));
      dat(kq, bang([
        { nhan: 'Phiếu', lay: (r) => h('b', null, r.ma) },
        { nhan: 'Xe', lay: (r) => h('span', null, bienSo(r.bien_so, { maThay: r.ma_ho_so }), h('small', null, ` ${r.ma_ho_so}`)) },
        { nhan: 'Tổ', lay: (r) => r.to_id || '' },
        { nhan: 'Người lập', lay: (r) => h('span', null, r.nguoi_lap_ten || '', h('small', null, ` · ${ngayGio(r.tao_luc)}`)) },
        { nhan: 'Số dòng', so: true, lay: (r) => r.so_dong },
        { nhan: 'Trạng thái', lay: (r) => h('span', null, TT_DE_XUAT[r.trang_thai],
          r.so_dong_cho_mua ? h('span', { class: 'nhan tt-canh-bao' }, `Chờ mua ${r.so_dong_cho_mua}`) : null) },
      ], ds, { onRow: (r) => moDeXuat(r.id, tai), trong: loc === 'cho_xuat' ? 'Không có phiếu đề xuất nào chờ xuất.' : 'Chưa có phiếu đề xuất.' }));
    }
    dat(vung, h('section', { class: 'the' },
      h('p', { class: 'mo-ta' }, 'Trưởng nhóm (hoặc CVDV, kho) đề xuất vật tư cho xe đã có lệnh sửa chữa. Kho thấy tồn ngay trên phiếu: còn hàng thì xuất, hết hàng thì chuyển mua – xe hiện "Chờ phụ tùng" đến khi hàng về.'),
      tabsCon, kq));
    await tai();
  }

  // ---------------- Nhập kho ----------------
  async function veNhap() {
    if (laKho()) nut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => moPhieuNhap({}, ve) }, '+ Phiếu nhập'));
    let loc = keToan() ? 'cho_khop' : 'tat';
    const kq = h('div');
    const tabsCon = h('div', { class: 'tabs nho', role: 'tablist' }, [['cho_khop', 'Chờ khớp'], ['treo', 'Treo'], ['tat', 'Tất cả (60 ngày)']].map(([ma, nhan]) =>
      h('button', { type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === loc),
        onclick: () => { loc = ma; for (const b of tabsCon.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); tai(); } }, nhan)));
    async function tai() {
      dat(kq, h('div', { class: 'dang-tai' }, 'Đang tải…'));
      const ds = await api.doc('v_phieu_nhap', (q) => (loc === 'tat' ? q.gte('ngay', new Date(Date.now() - 60 * 864e5).toISOString().slice(0, 10))
        : q.eq('trang_thai', loc)).order('id', { ascending: false }).limit(300));
      dat(kq, bang([
        { nhan: 'Ngày', lay: (r) => ngay(r.ngay) },
        { nhan: 'Phiếu', lay: (r) => h('b', null, r.ma) },
        { nhan: 'Nhà cung cấp', lay: (r) => h('span', null, r.nha_cung_cap, r.so_hoa_don ? h('small', null, ` · HĐ ${r.so_hoa_don}`) : null) },
        { nhan: 'Cho xe / đề nghị', lay: (r) => [r.ma_ho_so, r.ma_de_nghi_mua].filter(Boolean).join(' · ') },
        { nhan: 'Tổng (gồm VAT)', so: true, lay: (r) => tien(r.tong_tien) },
        { nhan: 'Trạng thái', lay: (r) => h('span', null, TT_NHAP[r.trang_thai], r.so_tep ? h('small', null, ` · ${r.so_tep} ảnh`) : h('small', { class: 'chu-loi' }, ' · chưa có ảnh HĐ'),
          r.ly_do_treo ? h('small', null, ` · ${r.ly_do_treo}`) : null) },
      ], ds, { onRow: (r) => moChiTietNhap(r.id, tai), trong: 'Không có phiếu nhập nào.' }));
    }
    dat(vung, h('section', { class: 'the' },
      h('p', { class: 'mo-ta' }, 'Kho nhập theo hóa đơn, tồn tăng ngay. Kế toán đối chiếu hóa đơn rồi bấm Khớp mới ghi công nợ nhà cung cấp; lệch số lượng hay giá thì Treo lại chờ xử lý.'),
      tabsCon, kq));
    await tai();
  }

  // ---------------- Mua hàng ----------------
  async function veMua() {
    if (api.coVaiTro('kho', 'cvdv', 'quan_ly', 'giam_doc')) nut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => moLapDeNghiMua({}, ve) }, '+ Đề nghị mua'));
    let loc = ql() ? 'cho_duyet' : 'da_duyet';
    const kq = h('div');
    const tabsCon = h('div', { class: 'tabs nho', role: 'tablist' }, [['cho_duyet', 'Chờ duyệt'], ['da_duyet', 'Đã duyệt – chờ hàng'], ['tat', 'Tất cả (60 ngày)']].map(([ma, nhan]) =>
      h('button', { type: 'button', role: 'tab', 'data-ma': ma, 'aria-selected': String(ma === loc),
        onclick: () => { loc = ma; for (const b of tabsCon.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); tai(); } }, nhan)));
    const nguong = api.caiDat('nguong_3_bao_gia', 5000000);
    async function tai() {
      dat(kq, h('div', { class: 'dang-tai' }, 'Đang tải…'));
      const ds = await api.doc('v_de_nghi_mua', (q) => (loc === 'tat' ? q.gte('ngay', new Date(Date.now() - 60 * 864e5).toISOString().slice(0, 10))
        : q.eq('trang_thai', loc)).order('id', { ascending: false }).limit(300));
      dat(kq, bang([
        { nhan: 'Ngày', lay: (r) => ngay(r.ngay) },
        { nhan: 'Phiếu', lay: (r) => h('b', null, r.ma) },
        { nhan: 'Nhà cung cấp', lay: (r) => r.nha_cung_cap },
        { nhan: 'Cho xe', lay: (r) => r.ma_ho_so || '' },
        { nhan: 'Người lập', lay: (r) => r.nguoi_lap_ten || '' },
        { nhan: 'Tổng (gồm VAT)', so: true, lay: (r) => h('span', null, tien(r.tong_tien),
          r.can_3_bao_gia ? h('small', { class: r.so_bao_gia >= 3 ? 'nhan' : 'nhan tt-canh-bao' }, `${r.so_bao_gia}/3 báo giá`) : null) },
        { nhan: 'Trạng thái', lay: (r) => h('span', null, TT_MUA[r.trang_thai], r.duyet_boi_ten ? h('small', null, ` · ${r.duyet_boi_ten}`) : null,
          r.ly_do_tu_choi ? h('small', null, ` · ${r.ly_do_tu_choi}`) : null) },
      ], ds, { onRow: (r) => moChiTietMua(r.id, tai), trong: 'Không có đề nghị mua nào.' }));
    }
    dat(vung, h('section', { class: 'the' },
      h('p', { class: 'mo-ta' }, `Giám đốc hoặc quản lý chung duyệt mọi đơn mua; không ai tự duyệt đơn mình lập. Đơn từ ${tien(nguong)} đ phải đính kèm 3 báo giá. Hàng về thì kho bấm "Nhập hàng" trên đơn đã duyệt.`),
      tabsCon, kq));
    await tai();
  }

  // ---------------- Kiểm kê ----------------
  async function veKiemKe() {
    nut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => moTaoKiemKe(ve) }, '+ Đợt kiểm kê'));
    const ds = await api.doc('kiem_ke', (q) => q.order('id', { ascending: false }).limit(60));
    dat(vung, h('section', { class: 'the' },
      h('p', { class: 'mo-ta' }, 'Sơn và nhám kiểm mỗi thứ Bảy, toàn kho cuối tháng. Nhập số đếm thực tế (không hiện số sổ sách để đếm khách quan); chốt thì phần mềm so với sổ sách và tự điều chỉnh tồn. Chênh trên 5% giá trị phải ghi biên bản.'),
      bang([
        { nhan: 'Ngày', lay: (r) => ngay(r.ngay) },
        { nhan: 'Đợt', lay: (r) => h('b', null, r.ma) },
        { nhan: 'Phạm vi', lay: (r) => PHAM_VI[r.pham_vi] },
        { nhan: 'Trạng thái', lay: (r) => ({ dang_dem: 'Đang đếm', da_chot: 'Đã chốt', huy: 'Đã hủy' }[r.trang_thai]) },
        { nhan: 'Giá trị kiểm', so: true, lay: (r) => (r.gia_tri_so_sach === null ? '' : tien(r.gia_tri_so_sach)) },
        { nhan: 'Chênh lệch', so: true, lay: (r) => (r.gia_tri_chenh === null ? '' : h('span', { class: Number(r.gia_tri_chenh) ? 'chu-loi' : null }, tien(r.gia_tri_chenh))) },
      ], ds, { onRow: (r) => moKiemKe(r.id, ve), trong: 'Chưa có đợt kiểm kê nào.' })));
  }

  // ---------------- Công nợ NCC ----------------
  async function veCongNo() {
    const ds = (await api.doc('v_cong_no_ncc', (q) => q.order('ten'))).filter((r) => Number(r.da_nhap) || Number(r.cho_khop) || Number(r.da_tra));
    const conNo = (r) => Number(r.da_nhap) - Number(r.da_tra);
    dat(vung, h('section', { class: 'the' },
      h('p', { class: 'mo-ta' }, 'Công nợ = phiếu nhập đã khớp hóa đơn − tiền đã trả. Trả nợ: lập Đề nghị chi, mục "Trả NCC – …", chọn đúng nhà cung cấp; kế toán chi thì công nợ tự giảm.'),
      h('section', { class: 'luoi-dem' },
        h('div', { class: 'o-dem' }, h('b', null, tien(ds.reduce((s, r) => s + conNo(r), 0))), h('span', null, 'Tổng còn nợ nhà cung cấp')),
        h('div', { class: 'o-dem' }, h('b', null, tien(ds.reduce((s, r) => s + Number(r.cho_khop), 0))), h('span', null, 'Hàng đã nhập, chờ khớp hóa đơn'))),
      bang([
        { nhan: 'Nhà cung cấp', lay: (r) => h('b', null, r.ten) },
        { nhan: 'Đã nhập (đã khớp)', so: true, lay: (r) => tien(r.da_nhap) },
        { nhan: 'Đã trả', so: true, lay: (r) => tien(r.da_tra) },
        { nhan: 'Còn nợ', so: true, lay: (r) => h('b', { class: conNo(r) < 0 ? 'chu-loi' : null }, tien(conNo(r))) },
        { nhan: 'Chờ khớp / treo', so: true, lay: (r) => (Number(r.cho_khop) ? tien(r.cho_khop) : '') },
      ], ds, { trong: 'Chưa có công nợ nhà cung cấp.' })));
  }

  // ---------------- Nhập – xuất – tồn ----------------
  async function veNxt() {
    let thang = homNay().slice(0, 7);
    const oThang = h('input', { type: 'month', value: thang, 'aria-label': 'Tháng' });
    const kq = h('div');
    async function tai() {
      dat(kq, h('div', { class: 'dang-tai' }, 'Đang tải…'));
      const tu = `${thang}-01`; const den = cuoiThang(thang);
      const ps = await api.doc('v_the_kho', (q) => q.lte('ngay', den));
      const g = new Map();
      for (const x of dsHang) g.set(x.id, { x, dau: 0, gtDau: 0, nhap: 0, gtNhap: 0, xuat: 0, gtXuat: 0 });
      for (const p of ps) {
        const r = g.get(p.hang_id); if (!r) continue;
        const so = Number(p.so_luong); const gt = Number(p.gia_tri);
        if (p.ngay < tu) { r.dau += so; r.gtDau += gt; } else if (so > 0) { r.nhap += so; r.gtNhap += gt; } else { r.xuat -= so; r.gtXuat -= gt; }
      }
      const ds = [...g.values()].filter((r) => r.dau || r.nhap || r.xuat);
      const cot = [
        { nhan: 'Mã', lay: (r) => r.x.ma, xuat: (r) => r.x.ma },
        { nhan: 'Tên hàng', lay: (r) => r.x.ten, xuat: (r) => r.x.ten },
        { nhan: 'ĐVT', lay: (r) => r.x.dvt, xuat: (r) => r.x.dvt },
        { nhan: 'Tồn đầu', so: true, lay: (r) => sl(r.dau), xuat: (r) => r.dau },
        { nhan: 'Nhập', so: true, lay: (r) => sl(r.nhap), xuat: (r) => r.nhap },
        { nhan: 'Xuất', so: true, lay: (r) => sl(r.xuat), xuat: (r) => r.xuat },
        { nhan: 'Tồn cuối', so: true, lay: (r) => h('b', null, sl(r.dau + r.nhap - r.xuat)), xuat: (r) => r.dau + r.nhap - r.xuat },
        { nhan: 'Giá trị nhập', so: true, lay: (r) => tien(r.gtNhap), xuat: (r) => r.gtNhap },
        { nhan: 'Giá trị xuất', so: true, lay: (r) => tien(r.gtXuat), xuat: (r) => r.gtXuat },
        { nhan: 'Giá trị cuối', so: true, lay: (r) => tien(r.gtDau + r.gtNhap - r.gtXuat), xuat: (r) => r.gtDau + r.gtNhap - r.gtXuat },
      ];
      dat(kq,
        h('section', { class: 'luoi-dem' },
          h('div', { class: 'o-dem' }, h('b', null, tien(ds.reduce((s, r) => s + r.gtNhap, 0))), h('span', null, 'Giá trị nhập trong tháng')),
          h('div', { class: 'o-dem' }, h('b', null, tien(ds.reduce((s, r) => s + r.gtXuat, 0))), h('span', null, 'Giá trị xuất (giá vốn) trong tháng')),
          h('div', { class: 'o-dem' }, h('b', null, tien(ds.reduce((s, r) => s + r.gtDau + r.gtNhap - r.gtXuat, 0))), h('span', null, 'Giá trị tồn cuối tháng'))),
        api.coVaiTro('giam_doc') ? h('div', { class: 'hang-nut' }, h('button', { class: 'nut', type: 'button', onclick: () => taiTepCSV(`nhap-xuat-ton-${thang}.csv`, cot, ds) }, 'Tải file CSV')) : null,
        bang(cot, ds, { trong: 'Tháng này chưa có nhập xuất.' }));
    }
    oThang.addEventListener('change', () => { if (oThang.value) { thang = oThang.value; tai(); } });
    dat(vung, h('section', { class: 'the' }, h('div', { class: 'the-dau' }, h('h2', null, 'Nhập – xuất – tồn theo tháng'), oThang), kq));
    await tai();
  }

  void ctx;
  await ve();
}

// ======================================================================
// Hộp thoại dùng chung (cũng được trang hồ sơ xe gọi)
// ======================================================================

// Thêm / sửa mã hàng
function moHang(x, veLai) {
  const form = h('form', { class: 'luoi-o' },
    truong('Mã hàng', oChu('ma', x?.ma, { placeholder: 'Ví dụ ĐS-TRONP80', autocapitalize: 'characters' }), 'Viết liền, phần mềm tự viết hoa', { batBuoc: true }),
    truong('Tên hàng', oChu('ten', x?.ten), null, { batBuoc: true }),
    truong('Nhóm hàng', oChon('nhom', NHOM_HANG.map((v) => ({ value: v, label: v })), x?.nhom || 'Phụ tùng', { trong: null })),
    truong('Đơn vị xuất (đơn vị tồn)', oChu('dvt', x?.dvt, { list: 'dvt-goi-y', placeholder: 'Lít, Cái…' }), 'Đơn vị trưởng nhóm đề xuất và kho xuất', { batBuoc: true }),
    truong('Đơn vị nhập', oChu('dvt_nhap', x?.dvt_nhap, { list: 'dvt-goi-y', placeholder: 'Để trống nếu như đơn vị xuất' }), 'Ví dụ sơn nhập theo Can 4L'),
    truong('Hệ số quy đổi', oSoLuong('he_so', x?.he_so ?? 1), '1 đơn vị nhập = bao nhiêu đơn vị xuất (Can 4L → 4 Lít)'),
    truong('Tồn tối thiểu', oSoLuong('ton_toi_thieu', x?.ton_toi_thieu ?? 0), 'Tồn bằng hoặc dưới mức này thì báo sắp hết'),
    truong('Nhà cung cấp thường mua', oChon('nha_cung_cap_id', (api.dm.nha_cung_cap || []).filter((n) => n.hoat_dong).map((n) => ({ value: n.id, label: n.ten })), x?.nha_cung_cap_id)),
    truong('Ghi chú', oChu('ghi_chu', x?.ghi_chu), null, { rong: true }),
    x ? h('div', { class: 'truong' }, oCheck('hoat_dong', x.hoat_dong, 'Đang dùng')) : null,
    h('datalist', { id: 'dvt-goi-y' }, DVT_GOI_Y.map((v) => h('option', { value: v }))));
  moModal(x ? `Sửa mã ${x.ma}` : 'Thêm mã hàng', form, {
    rong: true,
    nutChinh: async () => {
      const d = Object.fromEntries(new FormData(form));
      await api.luuHangKho({ id: x?.id ?? null, ...d, he_so: docSo(d.he_so) ?? 1, ton_toi_thieu: docSo(d.ton_toi_thieu) ?? 0,
        nha_cung_cap_id: d.nha_cung_cap_id || null, hoat_dong: x ? form.hoat_dong.checked : true });
      toast(x ? 'Đã lưu mã hàng.' : 'Đã thêm mã hàng.');
      await veLai();
    },
  });
}

// Thẻ kho của một mã: các lần nhập, xuất
async function moTheKho(x, veLai) {
  const ps = await api.doc('v_the_kho', (q) => q.eq('hang_id', x.id).order('ngay', { ascending: false }).order('tao_luc', { ascending: false }).limit(100));
  const LOAI = { nhap: 'Nhập', kiem_ke_thua: 'Kiểm kê thừa', xuat_cho_xe: 'Xuất cho xe', xuat_dung_chung: 'Xuất dùng chung', kiem_ke_thieu: 'Kiểm kê thiếu' };
  const noiDung = h('div', null,
    h('p', { class: 'mo-ta' }, `${x.ten} · Nhóm ${x.nhom} · Tồn ${sl(x.ton)} ${x.dvt}`, quyDoi(x) ? ` · ${quyDoi(x)}` : '',
      api.laNhanVien() ? ` · Giá trị ${tien(x.gia_tri)} đ` : ''),
    api.coVaiTro('kho', 'quan_ly', 'giam_doc') ? h('div', { class: 'hang-nut' }, h('button', { class: 'nut', type: 'button', onclick: (e) => { e.target.closest('.modal-nen')?.remove(); moHang(x, veLai); } }, 'Sửa mã hàng')) : null,
    bang([
      { nhan: 'Ngày', lay: (p) => ngay(p.ngay) },
      { nhan: 'Loại', lay: (p) => LOAI[p.loai] || p.loai },
      { nhan: 'Chứng từ', lay: (p) => p.chung_tu },
      { nhan: 'Số lượng', so: true, lay: (p) => h('span', { class: Number(p.so_luong) < 0 ? 'chu-loi' : 'chu-tot' }, `${Number(p.so_luong) > 0 ? '+' : ''}${sl(p.so_luong)}`) },
      api.laNhanVien() ? { nhan: 'Giá trị', so: true, lay: (p) => tien(p.gia_tri) } : null,
    ].filter(Boolean), ps, { trong: 'Chưa có nhập xuất.' }));
  moModal(`Thẻ kho ${x.ma}`, noiDung, { rong: true });
}

// Lập phiếu đề xuất vật tư (có thể đặt sẵn xe từ trang hồ sơ)
export async function moLapDeXuat(hoSo, veLai) {
  if (!dsHang.length) await taiHang();
  const dsXe = hoSo ? [hoSo] : await hoSoDangSua();
  if (!dsXe.length) { toast('Chưa có xe nào có lệnh sửa chữa để đề xuất vật tư.', 'loi'); return; }
  const chonXe = oChon('ho_so_id', dsXe.map((x) => ({ value: x.id, label: nhanXe(x) })), hoSo?.id, { trong: hoSo ? null : '— Chọn xe —' });
  const laTN = api.coVaiTro('truong_nhom') && !api.laNhanVien();
  const chonTo = laTN ? null : oChon('to_id', (api.dm.to_thuc_hien || []).map((t) => ({ value: t.id, label: `${t.id} – ${t.ten}` })), '', { trong: '— Tổ dùng —' });
  const dong = khungDong(() => {
    const chon = oChonHang(); const oSl = oSoLuong('so_luong'); const goiY = h('small', { class: 'goi-y' });
    chon.addEventListener('change', () => { const x = hangTheoId(chon.value); goiY.textContent = x ? `Đơn vị: ${x.dvt} · Tồn ${sl(x.ton)}` : ''; });
    return { o: [h('div', { class: 'truong rong-hon' }, h('span', { class: 'truong-nhan' }, 'Mã hàng'), chon, goiY), truong('Số lượng', oSl)],
      doc: () => (chon.value ? { hang_id: Number(chon.value), so_luong: docSo(oSl.value) } : null) };
  }, '+ Thêm mã');
  dong.them();
  const oGhiChu = oChu('ghi_chu', '', { placeholder: 'Ví dụ: sơn cửa trước trái' });
  moModal('Đề xuất vật tư', h('div', null,
    h('div', { class: 'luoi-o' }, truong('Xe (đã có lệnh sửa chữa)', chonXe, null, { batBuoc: true }), chonTo ? truong('Tổ', chonTo) : null, truong('Ghi chú', oGhiChu)),
    h('h3', null, 'Vật tư cần lấy'), dong.el), {
    rong: true, nhanNut: 'Gửi đề xuất',
    nutChinh: async () => {
      if (!chonXe.value) { toast('Chọn xe.', 'loi'); return false; }
      const ds = dong.doc();
      if (!ds.length) { toast('Chọn ít nhất một mã hàng.', 'loi'); return false; }
      if (ds.some((d) => !(d.so_luong > 0))) { toast('Nhập số lượng cho từng dòng.', 'loi'); return false; }
      const kq = await api.lapDeXuat({ ho_so_id: Number(chonXe.value), to_id: chonTo?.value || null, ghi_chu: oGhiChu.value, dong: ds });
      toast(`Đã gửi đề xuất ${kq.ma} cho kho.`);
      await veLai?.();
    },
  });
}

// Chi tiết phiếu đề xuất: kho xuất / chuyển mua
export async function moDeXuat(id, veLai) {
  await taiHang();
  const [[r], dongs, phieu] = await Promise.all([
    api.doc('v_de_xuat', (q) => q.eq('id', id)),
    api.doc('de_xuat_dong', (q) => q.eq('de_xuat_id', id).order('id')),
    api.doc('v_phieu_xuat', (q) => q.eq('de_xuat_id', id).order('id')),
  ]);
  if (!r) return;
  const kho = laKho() && r.trang_thai === 'cho_xuat';
  const con = (d) => Number(d.so_luong) - Number(d.da_xuat);
  const coXuat = dongs.some((d) => con(d) > 0 && Number(hangTheoId(d.hang_id)?.ton) > 0);
  const thieu = dongs.filter((d) => con(d) > Number(hangTheoId(d.hang_id)?.ton || 0) && !d.cho_mua);
  const tinhTrang = (d) => {
    const x = hangTheoId(d.hang_id); const t = Number(x?.ton || 0);
    if (con(d) <= 0) return h('span', { class: 'chu-tot' }, 'Đã xuất đủ');
    if (d.cho_mua) return h('span', { class: 'nhan tt-canh-bao' }, 'Chờ mua');
    return t >= con(d) ? h('span', { class: 'chu-tot' }, 'Đủ hàng') : h('span', { class: 'chu-loi' }, t > 0 ? `Thiếu ${sl(con(d) - t)}` : 'Hết hàng');
  };
  const noiDung = h('div', null,
    h('p', { class: 'mo-ta' }, `Xe ${r.bien_so} · ${r.ma_ho_so}`, r.to_id ? ` · Tổ ${r.to_id}` : '', ` · ${r.nguoi_lap_ten || ''} lập ${ngayGio(r.tao_luc)}`, r.ghi_chu ? ` · ${r.ghi_chu}` : ''),
    bang([
      { nhan: 'Mã hàng', lay: (d) => { const x = hangTheoId(d.hang_id); return h('span', null, h('b', null, x?.ma), ` ${x?.ten || ''}`); } },
      { nhan: 'Đề xuất', so: true, lay: (d) => `${sl(d.so_luong)} ${hangTheoId(d.hang_id)?.dvt || ''}` },
      { nhan: 'Đã xuất', so: true, lay: (d) => sl(d.da_xuat) },
      { nhan: 'Tồn kho', so: true, lay: (d) => sl(hangTheoId(d.hang_id)?.ton) },
      { nhan: 'Tình trạng', lay: tinhTrang },
    ], dongs),
    phieu.length ? h('div', null, h('h3', null, 'Phiếu xuất'), bang([
      { nhan: 'Phiếu', lay: (p) => h('b', null, p.ma) },
      { nhan: 'Ngày', lay: (p) => ngay(p.ngay) },
      api.laNhanVien() ? { nhan: 'Giá vốn', so: true, lay: (p) => tien(p.gia_von) } : null,
      { nhan: '', lay: (p) => (p.trang_thai === 'huy' ? h('small', null, `Đã hủy: ${p.ly_do_huy || ''}`)
        : laKho() ? h('button', { class: 'nut-chu', type: 'button', onclick: () => huyXuat(p) }, 'Hủy phiếu xuất') : '') },
    ].filter(Boolean), phieu)) : null);
  const dongHop = moModal(`Đề xuất ${r.ma} – ${TT_DE_XUAT[r.trang_thai]}`, noiDung, {
    rong: true,
    nhanNut: 'Xuất kho',
    nutChinh: kho && coXuat ? async () => {
      const kq = await api.xuatTheoDeXuat(id);
      toast(`Đã xuất ${kq.ma}.`);
      await veLai?.();
    } : undefined,
  });
  const hangNut = h('div', { class: 'hang-nut' },
    kho && thieu.length ? h('button', { class: 'nut', type: 'button', onclick: () => { dongModal(); moChuyenMua(r, thieu, veLai); } }, `Chuyển mua phần thiếu (${thieu.length})`) : null,
    r.trang_thai === 'cho_xuat' && (r.nguoi_lap === api.toi.id || api.coVaiTro('kho', 'quan_ly', 'giam_doc')) && !dongs.some((d) => Number(d.da_xuat) > 0 || d.cho_mua)
      ? h('button', { class: 'nut-chu', type: 'button', onclick: async () => {
        if (!(await xacNhan(`Hủy phiếu đề xuất ${r.ma}?`, 'Hủy phiếu'))) return;
        await chay(() => api.huyDeXuat(id), { thanhCong: 'Đã hủy phiếu đề xuất.' }).then(() => { dongModal(); veLai?.(); }).catch(() => {});
      } }, 'Hủy phiếu đề xuất') : null);
  noiDung.append(hangNut);
  function dongModal() { dongHop(); }
  async function huyXuat(p) {
    const form = h('form', null, truong('Lý do hủy', oVung('ly_do', ''), 'Hàng trả về đúng lô cũ, giá vốn của xe giảm tương ứng.', { batBuoc: true }));
    moModal(`Hủy phiếu xuất ${p.ma}`, form, { nhanNut: 'Hủy phiếu xuất', nutChinh: async () => {
      await api.huyPhieuXuat(p.id, form.ly_do.value); toast('Đã hủy phiếu xuất, hàng đã về kho.'); dongModal(); await veLai?.();
    } });
  }
}

// Chuyển phần thiếu thành đề nghị mua
function moChuyenMua(r, thieu, veLai) {
  const nccMacDinh = hangTheoId(thieu[0].hang_id)?.nha_cung_cap_id;
  const chonNcc = oChon('nha_cung_cap_id', (api.dm.nha_cung_cap || []).filter((n) => n.hoat_dong).map((n) => ({ value: n.id, label: n.ten })), nccMacDinh);
  const dongs = thieu.map((d) => {
    const x = hangTheoId(d.hang_id);
    const canXuat = Number(d.so_luong) - Number(d.da_xuat) - Math.max(Number(x?.ton || 0), 0);
    const oSl = oSoLuong('so_luong', Math.max(1, Math.ceil(canXuat / Number(x?.he_so || 1))));
    const oGia = oTien('don_gia', x?.gia_nhap_gan_nhat ?? null);
    const chonVat = oChon('ty_le_vat', MUC_VAT.map(([v, l]) => ({ value: v, label: l })), 0.08, { trong: null });
    const tich = h('input', { type: 'checkbox', checked: true, 'aria-label': `Mua ${x?.ma}` });
    return { d, x, oSl, oGia, chonVat, tich, el: h('tr', null,
      h('td', null, h('label', null, tich, ' ', h('b', null, x?.ma), ` ${x?.ten || ''}`), h('small', { class: 'goi-y' }, ` Thiếu ${sl(canXuat)} ${x?.dvt}`)),
      h('td', null, oSl, h('small', null, ` ${dvtNhap(x)}`)), h('td', null, oGia), h('td', null, chonVat)) };
  });
  moModal(`Chuyển mua – ${r.ma}`, h('div', null,
    h('p', { class: 'mo-ta' }, `Xe ${r.bien_so} sẽ hiện "Chờ phụ tùng" cho đến khi hàng về và nhập kho.`),
    truong('Nhà cung cấp', chonNcc, null, { batBuoc: true }),
    h('div', { class: 'bang-cuon' }, h('table', { class: 'bang' },
      h('thead', null, h('tr', null, h('th', null, 'Mã hàng'), h('th', null, 'Số lượng mua'), h('th', null, 'Đơn giá (chưa VAT)'), h('th', null, 'VAT'))),
      h('tbody', null, dongs.map((x) => x.el))))), {
    rong: true, nhanNut: 'Tạo đề nghị mua',
    nutChinh: async () => {
      if (!chonNcc.value) { toast('Chọn nhà cung cấp.', 'loi'); return false; }
      const chon = dongs.filter((x) => x.tich.checked);
      if (!chon.length) { toast('Chọn ít nhất một dòng.', 'loi'); return false; }
      const kq = await api.chuyenMua(r.id, { nha_cung_cap_id: Number(chonNcc.value),
        dong: chon.map((x) => ({ dong_id: x.d.id, so_luong: docSo(x.oSl.value), don_gia: docTien(x.oGia.value), ty_le_vat: Number(x.chonVat.value) })) });
      toast(`Đã tạo đề nghị mua ${kq.ma}${kq.can_3_bao_gia ? ' – đơn từ 5 triệu: đính kèm 3 báo giá trước khi duyệt' : ''}.`);
      await veLai?.();
    },
  });
}

// Dòng hàng có số lượng + đơn giá + VAT (phiếu nhập, đề nghị mua)
function dongCoGia(capNhat) {
  return (macDinh = {}) => {
    const chon = oChonHang('hang_id', macDinh.hang_id); const oSl = oSoLuong('so_luong', macDinh.so_luong ?? '');
    const oGia = oTien('don_gia', macDinh.don_gia ?? null);
    const chonVat = oChon('ty_le_vat', MUC_VAT.map(([v, l]) => ({ value: v, label: l })), macDinh.ty_le_vat ?? 0.08, { trong: null });
    const goiY = h('small', { class: 'goi-y' }); const thanh = h('small', { class: 'goi-y' });
    const ve = () => {
      const x = hangTheoId(chon.value);
      goiY.textContent = x ? [`Nhập theo ${dvtNhap(x)}`, quyDoi(x)].filter(Boolean).join(' · ') : '';
      if (!macDinh.don_gia && x?.gia_nhap_gan_nhat && !oGia.value) oGia.value = tien(x.gia_nhap_gan_nhat);
      const t = (docSo(oSl.value) || 0) * (docTien(oGia.value) || 0) * (1 + Number(chonVat.value));
      thanh.textContent = t ? `Thành tiền ${tien(Math.round(t))} đ` : '';
      capNhat();
    };
    for (const o of [chon, oSl, oGia, chonVat]) { o.addEventListener('input', ve); o.addEventListener('change', ve); }
    setTimeout(ve);
    return {
      o: [h('div', { class: 'truong rong-hon' }, h('span', { class: 'truong-nhan' }, 'Mã hàng'), chon, goiY),
        truong('Số lượng', oSl), h('div', { class: 'truong' }, h('span', { class: 'truong-nhan' }, 'Đơn giá (chưa VAT)'), oGia, thanh), truong('VAT', chonVat)],
      doc: () => (chon.value ? { hang_id: Number(chon.value), so_luong: docSo(oSl.value), don_gia: docTien(oGia.value), ty_le_vat: Number(chonVat.value), ...(macDinh.de_xuat_dong_id ? { de_xuat_dong_id: macDinh.de_xuat_dong_id } : {}) } : null),
      khiBo: capNhat,
    };
  };
}
const tongDong = (ds) => ds.reduce((s, d) => s + Math.round((d.so_luong || 0) * (d.don_gia || 0) * (1 + d.ty_le_vat)), 0);

// Lập phiếu nhập (có thể theo đề nghị mua đã duyệt)
export async function moPhieuNhap({ deNghi = null } = {}, veLai) {
  await taiHang();
  const [dsDuyet, dsXe] = await Promise.all([api.doc('v_de_nghi_mua', (q) => q.eq('trang_thai', 'da_duyet').order('id', { ascending: false })), hoSoDangSua()]);
  const tong = h('b');
  const capNhat = () => { tong.textContent = `${tien(tongDong(dong.doc()))} đ`; };
  const dong = khungDong(dongCoGia(capNhat));
  const chonNcc = oChon('nha_cung_cap_id', (api.dm.nha_cung_cap || []).filter((n) => n.hoat_dong).map((n) => ({ value: n.id, label: n.ten })), deNghi?.nha_cung_cap_id);
  const chonDeNghi = oChon('de_nghi_mua_id', dsDuyet.map((d) => ({ value: d.id, label: `${d.ma} · ${d.nha_cung_cap} · ${tien(d.tong_tien)} đ${d.ma_ho_so ? ` · xe ${d.ma_ho_so}` : ''}` })), deNghi?.id, { trong: '— Không theo đề nghị —' });
  const chonXe = oChon('ho_so_id', dsXe.map((x) => ({ value: x.id, label: nhanXe(x) })), '', { trong: '— Nhập kho chung —' });
  const tichXuat = oCheck('xuat_cho_xe', true, 'Xuất ngay cho xe này (phụ tùng mua riêng cho xe)');
  tichXuat.hidden = true;
  chonXe.addEventListener('change', () => { tichXuat.hidden = !chonXe.value; });
  async function napDeNghi() {
    dat(dong.ds);
    if (!chonDeNghi.value) { dong.them(); capNhat(); return; }
    const d = dsDuyet.find((x) => String(x.id) === chonDeNghi.value);
    chonNcc.value = d.nha_cung_cap_id;
    if (d.ho_so_id && dsXe.some((x) => x.id === d.ho_so_id)) { chonXe.value = d.ho_so_id; tichXuat.hidden = false; tichXuat.querySelector('input').checked = false; }
    const ct = await api.doc('de_nghi_mua_dong', (q) => q.eq('de_nghi_id', d.id).order('id'));
    for (const c of ct) dong.them({ hang_id: c.hang_id, so_luong: c.so_luong, don_gia: c.don_gia, ty_le_vat: Number(c.ty_le_vat) });
    capNhat();
  }
  chonDeNghi.addEventListener('change', napDeNghi);
  const chonAnh = oChonTep({ name: 'anh', multiple: true, accept: 'image/*,application/pdf' }, 'Chụp / chọn ảnh hóa đơn');
  const oNgayNhap = oNgay('ngay', homNay(), { max: homNay() });
  const oSoHd = oChu('so_hoa_don', '', { placeholder: 'Số hóa đơn NCC' });
  const oGhiChu = oChu('ghi_chu', '');
  const noiDung = h('div', null,
    h('div', { class: 'luoi-o' },
      truong('Theo đề nghị mua', chonDeNghi, 'Chọn để điền sẵn hàng, số lượng, giá'),
      truong('Nhà cung cấp', chonNcc, null, { batBuoc: true }),
      truong('Ngày nhập', oNgayNhap, null, { batBuoc: true }),
      truong('Số hóa đơn', oSoHd),
      truong('Mua riêng cho xe', chonXe, 'Phụ tùng mua theo xe (VinFast, phụ tùng ngoài)'),
      h('div', { class: 'truong' }, tichXuat),
      truong('Ghi chú', oGhiChu, null, { rong: true })),
    h('h3', null, 'Hàng nhập'), dong.el,
    h('p', { class: 'tong-phieu' }, 'Tổng tiền (gồm VAT): ', tong),
    truong('Ảnh hóa đơn', chonAnh, 'Kế toán dùng để khớp hóa đơn'));
  if (deNghi) { chonDeNghi.value = deNghi.id; await napDeNghi(); } else { dong.them(); capNhat(); }
  moModal('Phiếu nhập kho', noiDung, {
    rong: true, nhanNut: 'Lưu phiếu nhập',
    nutChinh: async () => {
      const ds = dong.doc();
      if (!chonNcc.value) { toast('Chọn nhà cung cấp.', 'loi'); return false; }
      if (!ds.length) { toast('Chọn ít nhất một mã hàng.', 'loi'); return false; }
      if (ds.some((d) => !(d.so_luong > 0) || d.don_gia === null)) { toast('Nhập số lượng và đơn giá cho từng dòng.', 'loi'); return false; }
      const kq = await api.lapPhieuNhap({ ngay: oNgayNhap.value, nha_cung_cap_id: Number(chonNcc.value), so_hoa_don: oSoHd.value,
        de_nghi_mua_id: chonDeNghi.value ? Number(chonDeNghi.value) : null, ho_so_id: chonXe.value ? Number(chonXe.value) : null,
        xuat_cho_xe: !!chonXe.value && tichXuat.querySelector('input').checked, ghi_chu: oGhiChu.value, dong: ds });
      let loi = 0;
      for (const f of chonAnh.input.files) {
        try { await api.taiTepKho('phieu_nhap', chungTu(kq), f.type.startsWith('image/') ? await nenAnh(f, 'khac') : f); } catch { loi++; }
      }
      toast(`Đã nhập kho ${kq.ma}${kq.phieu_xuat ? ` và xuất ngay ${kq.phieu_xuat.ma} cho xe` : ''}.${loi ? ` ${loi} ảnh tải lên lỗi.` : ''}`, loi ? 'loi' : 'ok');
      await veLai?.();
    },
  });
}

// Chi tiết phiếu nhập: kế toán khớp / treo, kho hủy, xem ảnh hóa đơn
async function moChiTietNhap(id, veLai) {
  await taiHang();
  const [[r], dongs, tep] = await Promise.all([
    api.doc('v_phieu_nhap', (q) => q.eq('id', id)),
    api.doc('phieu_nhap_dong', (q) => q.eq('phieu_id', id).order('id')),
    api.doc('kho_tep', (q) => q.eq('loai', 'phieu_nhap').eq('doi_tuong_id', id).order('id')),
  ]);
  if (!r) return;
  const noiDung = h('div', null,
    h('p', { class: 'mo-ta' }, `${ngay(r.ngay)} · ${r.nha_cung_cap}`, r.so_hoa_don ? ` · HĐ ${r.so_hoa_don}` : '', ` · ${r.tao_boi_ten || ''} nhập`,
      r.ma_de_nghi_mua ? ` · theo ${r.ma_de_nghi_mua}` : '', r.ma_ho_so ? ` · cho xe ${r.ma_ho_so}` : ''),
    r.ly_do_treo ? h('p', { class: 'thong-bao canh-bao' }, `Treo: ${r.ly_do_treo}`) : null,
    bang([
      { nhan: 'Mã hàng', lay: (d) => { const x = hangTheoId(d.hang_id); return h('span', null, h('b', null, x?.ma), ` ${x?.ten || ''}`); } },
      { nhan: 'Số lượng', so: true, lay: (d) => `${sl(d.so_luong)} ${dvtNhap(hangTheoId(d.hang_id))}` },
      { nhan: 'Đơn giá (chưa VAT)', so: true, lay: (d) => tien(d.don_gia) },
      { nhan: 'VAT', so: true, lay: (d) => `${Math.round(Number(d.ty_le_vat) * 100)}%` },
      { nhan: 'Thành tiền', so: true, lay: (d) => tien(d.thanh_tien) },
    ], dongs),
    h('p', { class: 'tong-phieu' }, 'Tổng (gồm VAT): ', h('b', null, `${tien(r.tong_tien)} đ`), ` · VAT ${tien(r.tien_vat)} đ`),
    h('h3', null, `Ảnh hóa đơn (${tep.length})`), await luoiTep(tep));
  const hangNut = h('div', { class: 'hang-nut' });
  noiDung.append(hangNut);
  let dongModal = () => noiDung.closest('.modal-nen')?.remove();
  if (['cho_khop', 'treo'].includes(r.trang_thai)) {
    hangNut.append(nutTaiTep('phieu_nhap', r, async () => { dongModal(); await moChiTietNhap(id, veLai); }));
    if (keToan() && r.tao_boi !== api.toi.id) {
      hangNut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => chay(() => api.khopPhieuNhap(id, true), { thanhCong: 'Đã khớp hóa đơn – ghi công nợ nhà cung cấp.' }).then(() => { dongModal(); veLai?.(); }).catch(() => {}) }, 'Khớp hóa đơn'));
      hangNut.append(h('button', { class: 'nut', type: 'button', onclick: () => {
        const form = h('form', null, truong('Chỗ lệch', oVung('ly_do', ''), 'Số lượng, đơn giá, thiếu hóa đơn…', { batBuoc: true }));
        moModal(`Treo phiếu ${r.ma}`, form, { nhanNut: 'Treo phiếu', nutChinh: async () => { await api.khopPhieuNhap(id, false, form.ly_do.value); toast('Đã treo phiếu.'); dongModal(); await veLai?.(); } });
      } }, 'Treo – lệch'));
    }
    if (laKho()) {
      hangNut.append(h('button', { class: 'nut-chu', type: 'button', onclick: () => {
        const form = h('form', null, truong('Lý do hủy', oVung('ly_do', ''), 'Chỉ hủy được khi hàng của phiếu chưa xuất. Hủy xong lập lại phiếu đúng.', { batBuoc: true }));
        moModal(`Hủy phiếu nhập ${r.ma}`, form, { nhanNut: 'Hủy phiếu nhập', nutChinh: async () => { await api.huyPhieuNhap(id, form.ly_do.value); toast('Đã hủy phiếu nhập.'); dongModal(); await veLai?.(); } });
      } }, 'Hủy phiếu nhập'));
    }
  }
  dongModal = moModal(`Phiếu nhập ${r.ma} – ${TT_NHAP[r.trang_thai]}`, noiDung, { rong: true });
}

// Lập đề nghị mua
async function moLapDeNghiMua(_, veLai) {
  await taiHang();
  const dsXe = await hoSoDangSua();
  const tong = h('b'); const canhBao = h('small', { class: 'goi-y' });
  const nguong = api.caiDat('nguong_3_bao_gia', 5000000);
  const capNhat = () => { const t = tongDong(dong.doc()); tong.textContent = `${tien(t)} đ`; canhBao.textContent = t >= nguong ? ` – từ ${tien(nguong)} đ: đính kèm 3 báo giá` : ''; };
  const dong = khungDong(dongCoGia(capNhat));
  dong.them();
  const chonNcc = oChon('nha_cung_cap_id', (api.dm.nha_cung_cap || []).filter((n) => n.hoat_dong).map((n) => ({ value: n.id, label: n.ten })), '');
  const chonXe = oChon('ho_so_id', dsXe.map((x) => ({ value: x.id, label: nhanXe(x) })), '', { trong: '— Mua cho kho —' });
  const oGhiChu = oChu('ghi_chu', '');
  const chonBg = oChonTep({ name: 'bao_gia', multiple: true, accept: 'image/*,application/pdf' }, 'Chụp / chọn báo giá');
  moModal('Đề nghị mua hàng', h('div', null,
    h('div', { class: 'luoi-o' }, truong('Nhà cung cấp', chonNcc, null, { batBuoc: true }), truong('Mua cho xe', chonXe), truong('Ghi chú', oGhiChu, null, { rong: true })),
    h('h3', null, 'Hàng cần mua'), dong.el,
    h('p', { class: 'tong-phieu' }, 'Tổng (gồm VAT): ', tong, canhBao),
    truong('Báo giá nhà cung cấp', chonBg, 'Có thể bổ sung sau, trước khi duyệt')), {
    rong: true, nhanNut: 'Gửi đề nghị mua',
    nutChinh: async () => {
      const ds = dong.doc();
      if (!chonNcc.value) { toast('Chọn nhà cung cấp.', 'loi'); return false; }
      if (!ds.length || ds.some((d) => !(d.so_luong > 0) || d.don_gia === null)) { toast('Nhập mã hàng, số lượng, đơn giá cho từng dòng.', 'loi'); return false; }
      const kq = await api.lapDeNghiMua({ nha_cung_cap_id: Number(chonNcc.value), ho_so_id: chonXe.value ? Number(chonXe.value) : null, ghi_chu: oGhiChu.value, dong: ds });
      for (const f of chonBg.input.files) {
        try { await api.taiTepKho('de_nghi_mua', chungTu({ ...kq, chi_nhanh_id: api.toi.chi_nhanh_id }), f.type.startsWith('image/') ? await nenAnh(f, 'khac') : f); } catch { /* báo ở dưới */ }
      }
      toast(`Đã gửi đề nghị mua ${kq.ma}.`);
      await veLai?.();
    },
  });
}

// Chi tiết đề nghị mua: duyệt / từ chối / thêm báo giá / hủy / nhập hàng
async function moChiTietMua(id, veLai) {
  await taiHang();
  const [[r], dongs, tep] = await Promise.all([
    api.doc('v_de_nghi_mua', (q) => q.eq('id', id)),
    api.doc('de_nghi_mua_dong', (q) => q.eq('de_nghi_id', id).order('id')),
    api.doc('kho_tep', (q) => q.eq('loai', 'de_nghi_mua').eq('doi_tuong_id', id).order('id')),
  ]);
  if (!r) return;
  const noiDung = h('div', null,
    h('p', { class: 'mo-ta' }, `${ngay(r.ngay)} · ${r.nha_cung_cap}`, r.ma_ho_so ? ` · cho xe ${r.ma_ho_so}` : ' · mua cho kho', ` · ${r.nguoi_lap_ten || ''} lập`, r.ghi_chu ? ` · ${r.ghi_chu}` : ''),
    r.ly_do_tu_choi ? h('p', { class: 'thong-bao canh-bao' }, `Từ chối: ${r.ly_do_tu_choi}`) : null,
    bang([
      { nhan: 'Mã hàng', lay: (d) => { const x = hangTheoId(d.hang_id); return h('span', null, h('b', null, x?.ma), ` ${x?.ten || ''}`, h('small', null, ` · tồn ${sl(x?.ton)} ${x?.dvt || ''}`)); } },
      { nhan: 'Số lượng', so: true, lay: (d) => `${sl(d.so_luong)} ${dvtNhap(hangTheoId(d.hang_id))}` },
      { nhan: 'Đơn giá (chưa VAT)', so: true, lay: (d) => tien(d.don_gia) },
      { nhan: 'VAT', so: true, lay: (d) => `${Math.round(Number(d.ty_le_vat) * 100)}%` },
      { nhan: 'Thành tiền', so: true, lay: (d) => tien(Math.round(Number(d.so_luong) * Number(d.don_gia) * (1 + Number(d.ty_le_vat)))) },
    ], dongs),
    h('p', { class: 'tong-phieu' }, 'Tổng (gồm VAT): ', h('b', null, `${tien(r.tong_tien)} đ`)),
    h('h3', null, `Báo giá đính kèm (${tep.length}${r.can_3_bao_gia ? '/3 bắt buộc' : ''})`), await luoiTep(tep));
  const hangNut = h('div', { class: 'hang-nut' });
  noiDung.append(hangNut);
  let dongModal = () => noiDung.closest('.modal-nen')?.remove();
  const sau = async () => { dongModal(); await veLai?.(); };
  if (r.trang_thai === 'cho_duyet') {
    hangNut.append(nutTaiTep('de_nghi_mua', r, async () => { dongModal(); await moChiTietMua(id, veLai); }));
    if (ql() && r.nguoi_lap !== api.toi.id) {
      hangNut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => chay(() => api.duyetDeNghiMua(id, true), { thanhCong: 'Đã duyệt đề nghị mua.' }).then(sau).catch(() => {}) }, 'Duyệt'));
      hangNut.append(h('button', { class: 'nut', type: 'button', onclick: () => {
        const form = h('form', null, truong('Lý do từ chối', oVung('ly_do', ''), null, { batBuoc: true }));
        moModal(`Từ chối ${r.ma}`, form, { nhanNut: 'Từ chối', nutChinh: async () => { await api.duyetDeNghiMua(id, false, form.ly_do.value); toast('Đã từ chối.'); await sau(); } });
      } }, 'Từ chối'));
    }
  }
  if (r.trang_thai === 'da_duyet' && laKho()) {
    hangNut.append(h('button', { class: 'nut chinh', type: 'button', onclick: async () => { dongModal(); await moPhieuNhap({ deNghi: r }, veLai); } }, 'Nhập hàng'));
  }
  if (['cho_duyet', 'da_duyet'].includes(r.trang_thai) && (r.nguoi_lap === api.toi.id || ql())) {
    hangNut.append(h('button', { class: 'nut-chu', type: 'button', onclick: async () => {
      if (!(await xacNhan(`Hủy đề nghị mua ${r.ma}?`, 'Hủy đề nghị'))) return;
      await chay(() => api.huyDeNghiMua(id), { thanhCong: 'Đã hủy đề nghị mua.' }).then(sau).catch(() => {});
    } }, 'Hủy đề nghị'));
  }
  dongModal = moModal(`Đề nghị mua ${r.ma} – ${TT_MUA[r.trang_thai]}`, noiDung, { rong: true });
}

// Ảnh / tệp đính kèm: lưới ảnh nhỏ bấm mở ảnh lớn
async function luoiTep(tep) {
  if (!tep.length) return h('p', { class: 'trong' }, 'Chưa có tệp nào.');
  const link = await api.linkTepNhieu(tep.map((t) => t.duong_dan)).catch(() => ({}));
  return h('div', { class: 'luoi-anh' }, tep.map((t) => {
    const l = link[t.duong_dan];
    const laAnh = !/\.pdf$/i.test(t.duong_dan);
    return h('a', { href: l?.lon || '#', target: '_blank', rel: 'noopener', class: 'o-anh' },
      laAnh && l ? h('img', { src: l.nho, alt: t.ten || 'Ảnh', loading: 'lazy' }) : h('span', { class: 'tep' }, 'PDF'), h('small', null, t.ten || ''));
  }));
}
function nutTaiTep(loai, r, sau) {
  const o = h('input', { type: 'file', accept: 'image/*,application/pdf', multiple: true, 'aria-label': 'Chọn tệp' });
  o.addEventListener('change', async () => {
    let n = 0;
    for (const f of o.files) {
      try { await api.taiTepKho(loai, chungTu(r), f.type.startsWith('image/') ? await nenAnh(f, 'khac') : f); n++; }
      catch (e) { toast(`Không tải được ${f.name}: ${e.message}`, 'loi'); }
    }
    if (n) { toast(`Đã tải ${n} tệp.`); await sau(); }
  });
  return h('label', { class: 'nut' }, loai === 'phieu_nhap' ? '+ Ảnh hóa đơn' : '+ Báo giá', o);
}

// Xuất dùng chung xưởng (không theo xe)
async function moXuatDungChung(veLai) {
  await taiHang();
  const dong = khungDong(() => {
    const chon = oChonHang('hang_id', null, { chiConHang: true }); const oSl = oSoLuong('so_luong'); const goiY = h('small', { class: 'goi-y' });
    chon.addEventListener('change', () => { const x = hangTheoId(chon.value); goiY.textContent = x ? `Đơn vị: ${x.dvt} · Tồn ${sl(x.ton)}` : ''; });
    return { o: [h('div', { class: 'truong rong-hon' }, h('span', { class: 'truong-nhan' }, 'Mã hàng'), chon, goiY), truong('Số lượng', oSl)],
      doc: () => (chon.value ? { hang_id: Number(chon.value), so_luong: docSo(oSl.value) } : null) };
  }, '+ Thêm mã');
  dong.them();
  const oGhiChu = oChu('ghi_chu', '', { placeholder: 'Ví dụ: dầu rửa tay, giấy lau xưởng' });
  moModal('Xuất dùng chung xưởng', h('div', null,
    h('p', { class: 'mo-ta' }, 'Vật tư dùng chung, không tính vào xe nào (tính vào chi phí xưởng).'),
    truong('Dùng vào việc', oGhiChu, null, { batBuoc: true }), dong.el), {
    rong: true, nhanNut: 'Xuất kho',
    nutChinh: async () => {
      const ds = dong.doc();
      if (!ds.length || ds.some((d) => !(d.so_luong > 0))) { toast('Chọn mã hàng và số lượng.', 'loi'); return false; }
      const kq = await api.xuatDungChung({ ghi_chu: oGhiChu.value, dong: ds });
      toast(`Đã xuất ${kq.ma}.`);
      await veLai();
    },
  });
}

// Kiểm kê
function moTaoKiemKe(veLai) {
  const form = h('form', null,
    h('div', { class: 'chon-nut', role: 'radiogroup', 'aria-label': 'Phạm vi kiểm kê' },
      [['son_nham', 'Sơn và nhám (thứ Bảy)'], ['toan_kho', 'Toàn kho (cuối tháng)']].map(([v, nhan], i) =>
        h('label', null, h('input', { type: 'radio', name: 'pham_vi', value: v, checked: i === 0 }), h('span', null, nhan)))));
  moModal('Đợt kiểm kê mới', form, {
    nhanNut: 'Bắt đầu đếm',
    nutChinh: async () => {
      const kq = await api.taoKiemKe({ pham_vi: form.pham_vi.value });
      toast(`Đã tạo ${kq.ma}. Nhập số đếm thực tế từng mã.`);
      await veLai();
      await moKiemKe(kq.id, veLai);
    },
  });
}

async function moKiemKe(id, veLai) {
  await taiHang();
  const [[r], dongs] = await Promise.all([api.doc('kiem_ke', (q) => q.eq('id', id)), api.doc('kiem_ke_dong', (q) => q.eq('kiem_ke_id', id).order('id'))]);
  if (!r) return;
  const dangDem = r.trang_thai === 'dang_dem';
  const o = new Map();
  const noiDung = h('div', null,
    h('p', { class: 'mo-ta' }, `${ngay(r.ngay)} · ${PHAM_VI[r.pham_vi]} · ${dongs.length} mã`, r.bien_ban ? ` · Biên bản: ${r.bien_ban}` : ''),
    bang([
      { nhan: 'Mã hàng', lay: (d) => { const x = hangTheoId(d.hang_id); return h('span', null, h('b', null, x?.ma), ` ${x?.ten || ''}`); } },
      { nhan: 'ĐVT', lay: (d) => hangTheoId(d.hang_id)?.dvt || '' },
      dangDem ? null : { nhan: 'Sổ sách', so: true, lay: (d) => sl(d.ton_so_sach) },
      { nhan: 'Thực tế', so: true, lay: (d) => {
        if (!dangDem) return sl(d.ton_thuc_te);
        const oS = oSoLuong('ton_thuc_te', d.ton_thuc_te ?? '', { 'aria-label': `Số đếm ${hangTheoId(d.hang_id)?.ma}` });
        o.set(d.id, oS); return oS;
      } },
      dangDem ? null : { nhan: 'Chênh', so: true, lay: (d) => { const c = Number(d.ton_thuc_te) - Number(d.ton_so_sach); return h('span', { class: c ? 'chu-loi' : null }, c > 0 ? `+${sl(c)}` : sl(c)); } },
      dangDem ? null : { nhan: 'Giá trị chênh', so: true, lay: (d) => tien(Math.round((Number(d.ton_thuc_te) - Number(d.ton_so_sach)) * Number(d.don_gia_von || 0))) },
    ].filter(Boolean), dongs),
    r.trang_thai === 'da_chot' ? h('p', { class: 'tong-phieu' }, 'Giá trị kiểm ', h('b', null, `${tien(r.gia_tri_so_sach)} đ`), ' · chênh lệch ', h('b', null, `${tien(r.gia_tri_chenh)} đ`)) : null);
  const docDem = () => [...o.entries()].map(([dongId, oS]) => ({ dong_id: dongId, ton_thuc_te: docSo(oS.value) }));
  let dongModal = () => noiDung.closest('.modal-nen')?.remove();
  if (dangDem) {
    const oBienBan = oVung('bien_ban', '', { placeholder: 'Bắt buộc nếu chênh trên 5% giá trị: nguyên nhân, người chứng kiến…' });
    noiDung.append(truong('Biên bản (khi chốt)', oBienBan, null, { rong: true }),
      h('div', { class: 'hang-nut' },
        h('button', { class: 'nut', type: 'button', onclick: () => chay(() => api.luuDemKiemKe(id, docDem()), { thanhCong: 'Đã lưu số đếm.' }).catch(() => {}) }, 'Lưu số đếm'),
        h('button', { class: 'nut-chu', type: 'button', onclick: async () => {
          if (!(await xacNhan(`Hủy đợt kiểm kê ${r.ma}?`, 'Hủy đợt'))) return;
          await chay(() => api.huyKiemKe(id), { thanhCong: 'Đã hủy đợt kiểm kê.' }).then(() => { dongModal(); veLai(); }).catch(() => {});
        } }, 'Hủy đợt')));
    dongModal = moModal(`Kiểm kê ${r.ma}`, noiDung, {
      rong: true, nhanNut: 'Chốt kiểm kê',
      nutChinh: async () => {
        await api.luuDemKiemKe(id, docDem());
        const kq = await api.chotKiemKe(id, oBienBan.value);
        toast(`Đã chốt kiểm kê: chênh ${tien(kq.gia_tri_chenh)} đ (${kq.ty_le}% giá trị). Tồn đã điều chỉnh theo số đếm.`);
        await veLai();
      },
    });
  } else {
    moModal(`Kiểm kê ${r.ma}`, noiDung, { rong: true });
  }
}

// ---------- Dùng ở trang hồ sơ xe: phụ tùng, vật tư của xe ----------
export async function khoiPhuTungXe(hs, veLai) {
  const [dx, px, [cho]] = await Promise.all([
    api.doc('v_de_xuat', (q) => q.eq('ho_so_id', hs.id).order('id', { ascending: false })),
    api.doc('v_phieu_xuat', (q) => q.eq('ho_so_id', hs.id).eq('trang_thai', 'hieu_luc').order('id')),
    api.doc('v_cho_phu_tung', (q) => q.eq('ho_so_id', hs.id)),
  ]).catch(() => [[], [], []]);
  const duocDeXuat = ['dang_sua', 'cho_kcs'].includes(hs.trang_thai) && api.coVaiTro('truong_nhom', 'cvdv', 'kho', 'quan_ly', 'giam_doc');
  if (!dx.length && !px.length && !duocDeXuat) return null;
  const giaVon = px.reduce((s, p) => s + Number(p.gia_von), 0);
  return h('div', { class: 'khoi-phu-tung' },
    h('div', { class: 'the-dau' }, h('h3', null, 'Cấp phụ tùng, vật tư'),
      duocDeXuat ? h('button', { class: 'nut', type: 'button', onclick: () => moLapDeXuat(hs, veLai) }, '+ Đề xuất vật tư') : null),
    cho ? h('p', { class: 'thong-bao canh-bao' }, `Chờ phụ tùng ${cho.so_ngay} ngày (từ ${ngay(cho.tu_ngay)}).`) : null,
    dx.length ? bang([
      { nhan: 'Phiếu', lay: (r) => h('b', null, r.ma) },
      { nhan: 'Tổ', lay: (r) => r.to_id || '' },
      { nhan: 'Người lập', lay: (r) => r.nguoi_lap_ten || '' },
      { nhan: 'Trạng thái', lay: (r) => h('span', null, TT_DE_XUAT[r.trang_thai], r.so_dong_cho_mua ? h('span', { class: 'nhan tt-canh-bao' }, 'Chờ mua') : null) },
    ], dx, { onRow: (r) => moDeXuat(r.id, veLai) }) : h('p', { class: 'trong' }, 'Chưa có phiếu đề xuất vật tư.'),
    px.length && api.laNhanVien() ? h('p', { class: 'mo-ta' }, `Đã xuất ${px.length} phiếu · giá vốn phụ tùng, vật tư ${tien(giaVon)} đ`) : null);
}
