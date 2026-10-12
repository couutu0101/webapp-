// Chi tiết hồ sơ xe: 10 bước trên một trang, mỗi bước chỉ hiện nút cho đúng người
import {
  h, oChonTep, bienSo, oNgayVN, tien, ngay, ngayGio, homNay, choODatetime, truong, oChu, oTien, oChon, oVung, oNgay, oCheck, docForm, docTien,
  chay, moModal, toast, nhanTrangThai, nenAnh, bang, BUOC_SO, NHOM, NGUON, TRANG_THAI, xacNhan, dat, veDanhSachHoSo,
} from '../ui.js';
import * as api from '../api.js';
import { ghiTiep, tuGhiNgayKhiBam, nhacHetHan, layLichSu, khoiLichSu } from './lich-su-xe.js';

const BUOC = ['Tiếp nhận', 'Báo giá', 'Duyệt giá', 'Lệnh SC', 'Cấp vật tư', 'Sửa chữa', 'KCS', 'Giao xe', 'Hồ sơ BH', 'Chăm sóc'];
const TT_DONG = { cho_duyet: 'Chờ duyệt', duyet: 'Đã duyệt', tu_choi: 'Không duyệt', dang_lam: 'Đang làm', xong: 'Xong' };
const BUOC_TEP = { tiep_nhan: 'Nhận xe', duyet_gia: 'Giám định / duyệt giá / HĐ 3 bên', phat_sinh: 'Phát sinh', kcs: 'Sau sửa (KCS)', giao_xe: 'Giao xe', ho_so_bh: 'Hồ sơ bảo hiểm', khac: 'Khác' };

export default async function trangChiTiet(el, idChu) {
  const id = Number(idChu);
  // Lưu xong bất kỳ thao tác nào: về danh sách Hồ sơ xe; lỗi thì vẽ lại trang để thấy dữ liệu mới nhất
  let hsDangXem = { id, ma: '' };
  const ve = () => veDanhSachHoSo(hsDangXem);
  const veLai = ve.lai = async () => {
    const [hs, hm, nk, tep, ps, dsKcs] = await Promise.all([
      api.layHoSo(id), api.layHangMuc(id), api.layNhatKy(id), api.layTep(id), api.layPhatSinh(id), api.layKcs(id)]);
    if (!hs) { dat(el, h('p', { class: 'trong' }, 'Không tìm thấy hồ sơ, hoặc bạn không có quyền xem.')); return; }
    hsDangXem = hs;
    const ctx = { hs, hm, nk, tep, ps, dsKcs, ve };
    dat(el, 
      dau(ctx), tienDo(hs),
      h('div', { class: 'cot-doi' },
        h('div', null, theThongTin(ctx), theBaoGia(ctx), theSuaChua(ctx), theKcs(ctx), theGiaoXe(ctx), theHoSoBH(ctx), theChamSoc(ctx)),
        h('div', null, theTien(ctx), theTep(ctx), theNhatKy(ctx))));
  };
  await veLai();
}

const q = (...ds) => api.coVaiTro(...ds);
const nut = (nhan, onclick, chinh = false) => h('button', { class: `nut ${chinh ? 'chinh' : ''}`, type: 'button', onclick }, nhan);

function dau({ hs }) {
  return h('div', { class: 'tieu-de-trang' },
    h('div', null,
      h('p', { class: 'mo-ta' }, h('a', { href: '#/ho-so' }, '← Hồ sơ xe')),
      h('h1', { class: 'tieu-de-xe' }, bienSo(hs.bien_so_hien_thi, { lon: true }), nhanTrangThai(hs.trang_thai)),
      h('p', { class: 'mo-ta' }, [hs.ma, hs.xe, hs.mau].filter(Boolean).join(' · '),
        hs.loai === 'bao_hanh' ? h('span', { class: 'nhan tt-canh-bao' }, 'Bảo hành') : null,
        hs.tu_excel ? h('span', { class: 'nhan' }, 'Chuyển từ Excel') : null)),
    h('div', { class: 'hang-nut' },
      ['tiep_nhan', 'bao_gia', 'da_duyet'].includes(hs.trang_thai) && q('cvdv', 'quan_ly', 'giam_doc')
        ? nut('Hủy hồ sơ', () => moHuy(hs)) : null,
      hs.trang_thai === 'dong' && q('cvdv', 'quan_ly', 'giam_doc')
        ? h('a', { class: 'nut', href: `#/ho-so/moi?bao_hanh=${hs.id}` }, 'Tạo hồ sơ bảo hành') : null));
}

function tienDo(hs) {
  const hienTai = BUOC_SO[hs.trang_thai] || 0;
  if (hs.trang_thai === 'huy') return h('p', { class: 'thong-bao canh-bao' }, 'Hồ sơ đã hủy: ', hs.ly_do_huy || '');
  const daXong = hs.trang_thai === 'dong';
  return h('div', { class: 'tien-do-khung' },
    h('p', { class: 'tien-do-chu' }, daXong ? 'Đã xong cả 10 bước' : `Bước ${hienTai} trên 10: ${BUOC[hienTai - 1]}`),
    h('ol', { class: 'tien-do', 'aria-label': 'Tiến độ 10 bước' }, BUOC.map((b, i) => {
      const so = i + 1;
      const lop = so < hienTai || daXong ? 'xong' : so === hienTai ? 'dang' : '';
      return h('li', { class: lop, 'aria-current': so === hienTai && !daXong ? 'step' : null }, h('span', null, so), h('small', null, b));
    })));
}

// ---------- Thông tin ----------
function theThongTin({ hs, ve }) {
  const dong = (nhan, gt) => [h('dt', null, nhan), h('dd', null, gt || '—')];
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '1. Thông tin xe và khách'),
      q('cvdv', 'ke_toan', 'quan_ly', 'giam_doc') && !['dong', 'huy'].includes(hs.trang_thai) ? nut('Sửa', () => moSuaThongTin(hs, ve)) : null),
    h('dl', { class: 'thong-tin' },
      dong('Khách', hs.ten_khach), dong('SĐT', hs.dien_thoai ? h('a', { href: `tel:${hs.dien_thoai}` }, hs.dien_thoai) : null),
      dong('Nguồn', NGUON[hs.nguon_tt]),
      hs.nguon_tt !== 'khach' ? [
        dong('Bảo hiểm', hs.hang_bh),
        dong('Giám định viên', hs.gdv_cho_them ? h('span', null, hs.gdv, ' ', h('span', { class: 'nhan tt-canh-bao' }, 'chờ thêm vào danh sách')) : hs.gdv)] : null,
      dong('Hết hạn BH thân vỏ', ngay(hs.han_bh_than_vo)), dong('Hết hạn BH TNDS', ngay(hs.han_bao_hiem)),
      dong('Vào xưởng', ngayGio(hs.ngay_vao)), dong('Hẹn giao', ngayGio(hs.hen_giao)),
      dong('Tình trạng', hs.tinh_trang_xe), dong('Có thể tư vấn', hs.tu_van)),
    khungLichSuXe(hs));
}

// Các lần vào gara trước của cùng xe: tình trạng, tư vấn, phản hồi
function khungLichSuXe(hs) {
  const vung = h('div');
  layLichSu(hs.xe_id, hs.id).then((ds) => dat(vung, khoiLichSu(ds, { tieuDe: 'Các lần vào gara trước', moSan: false }))).catch(() => {});
  return vung;
}

function moSuaThongTin(hs, ve) {
  const dm = api.dm;
  const chonGdv = oChon('gdv_id', dm.giam_dinh_vien.filter((g) => g.hoat_dong).map((g) => ({
    value: g.id, label: g.la_cho_them ? g.ten : `${g.ten}${g.hang_id ? ` (${dm.ten('hang_bao_hiem', g.hang_id)})` : ''}` })), hs.gdv_id);
  const oGdvMoi = oChu('gdv_ten_tam', hs.gdv_cho_them ? hs.gdv : '');
  const oThemTinhTrang = oVung('them_tinh_trang', '', { rows: 2 });
  const oThemTuVan = oVung('them_tu_van', '', { rows: 2 });
  tuGhiNgayKhiBam(oThemTinhTrang); tuGhiNgayKhiBam(oThemTuVan);
  const form = h('form', { class: 'luoi-o' },
    truong('Tên khách', oChu('ten_khach', hs.ten_khach)),
    truong('Số điện thoại', oChu('dien_thoai', hs.dien_thoai, { inputmode: 'tel' })),
    truong('Màu xe', oChu('mau', hs.mau)),
    truong('Hẹn giao', h('input', { type: 'datetime-local', name: 'hen_giao', value: choODatetime(hs.hen_giao) })),
    hs.nguon_tt !== 'khach' ? [
      truong('Hãng bảo hiểm', oChon('hang_bh_id', dm.hang_bao_hiem.map((x) => ({ value: x.id, label: x.ten })), hs.hang_bh_id)),
      truong('Giám định viên', chonGdv), truong('Tên GDV mới (nếu chọn "chờ thêm")', oGdvMoi)] : null,
    truong('Hết hạn bảo hiểm thân vỏ', oNgayVN('han_bh_than_vo', hs.han_bh_than_vo), 'Ngày/tháng/năm'),
    truong('Hết hạn bảo hiểm TNDS', oNgayVN('han_bao_hiem', hs.han_bao_hiem), 'Ngày/tháng/năm'),
    // Tình trạng và tư vấn: không sửa nội dung cũ, chỉ ghi thêm (tự có ngày ở đầu) để giữ toàn bộ lịch sử
    h('div', { class: 'truong rong' }, h('span', { class: 'truong-nhan' }, 'Tình trạng đã ghi'), h('div', { class: 'nhat-ky-ghi' }, hs.tinh_trang_xe || '—')),
    truong('Ghi thêm tình trạng', oThemTinhTrang, 'Để trống nếu không có gì mới', { rong: true }),
    h('div', { class: 'truong rong' }, h('span', { class: 'truong-nhan' }, 'Tư vấn đã ghi'), h('div', { class: 'nhat-ky-ghi' }, hs.tu_van || '—')),
    truong('Ghi thêm tư vấn', oThemTuVan, 'Để trống nếu không có gì mới', { rong: true }));
  moModal('Sửa thông tin', form, {
    rong: true,
    nutChinh: async () => {
      const d = docForm(form);
      if (d.han_bh_than_vo === 'sai' || d.han_bao_hiem === 'sai') throw new Error('Ngày hết hạn bảo hiểm không đúng. Nhập dạng ngày/tháng/năm, ví dụ 01/03/2027.');
      if (hs.nguon_tt !== 'khach' && (!d.han_bh_than_vo || !d.han_bao_hiem)) throw new Error('Xe bảo hiểm: nhập đủ ngày hết hạn bảo hiểm thân vỏ và TNDS.');
      // Bảo hiểm hết hạn mà ô tư vấn chưa nhắc thì tự ghi thêm lời nhắc
      const nhac = nhacHetHan(d.han_bh_than_vo, d.han_bao_hiem).filter((x) => !(hs.tu_van || '').includes(x.split(' – ')[0]));
      let tuVan = hs.tu_van || '';
      for (const x of nhac) tuVan = ghiTiep(tuVan, x);
      tuVan = ghiTiep(tuVan, d.them_tu_van);
      const tinhTrang = ghiTiep(hs.tinh_trang_xe || '', d.them_tinh_trang);
      const p = { ten_khach: d.ten_khach, dien_thoai: d.dien_thoai, mau: d.mau,
        hen_giao: d.hen_giao ? new Date(d.hen_giao).toISOString() : null, han_bao_hiem: d.han_bao_hiem, han_bh_than_vo: d.han_bh_than_vo };
      if (tinhTrang !== (hs.tinh_trang_xe || '')) p.tinh_trang_xe = tinhTrang;
      if (tuVan !== (hs.tu_van || '')) p.tu_van = tuVan;
      if (hs.nguon_tt !== 'khach') Object.assign(p, { hang_bh_id: d.hang_bh_id, gdv_id: d.gdv_id, gdv_ten_tam: d.gdv_ten_tam });
      await api.suaThongTin(hs.id, p);
      toast('Đã lưu.'); await ve();
    },
  });
}

// ---------- Báo giá và duyệt giá (bước 2–3) ----------
// VAT chọn riêng cho từng lần báo giá
const MUC_VAT = [0.08, 0.10, 0.12];
const phanTram = (r) => `${Math.round(Number(r) * 100)}%`;
const sauVat = (gia, tyLe) => Math.round(Number(gia) * (1 + Number(tyLe)));
// Tiền sau VAT của một dòng đã lưu (dòng cũ chưa chọn VAT: tạm hiện theo 8%)
const sauVatDong = (m, gia) => (m.xuat_hd ? sauVat(gia, m.ty_le_vat ?? 0.08) : Number(gia));

function theBaoGia({ hs, hm, ve }) {
  const khach = hs.nguon_tt === 'khach';
  const choDuyet = hm.filter((m) => m.trang_thai === 'cho_duyet');
  const duocBaoGia = q('cvdv', 'quan_ly', 'giam_doc');
  const goc = ['tiep_nhan', 'bao_gia'].includes(hs.trang_thai);
  const boSung = ['da_duyet', 'dang_sua', 'cho_kcs'].includes(hs.trang_thai);
  const cotLan = { nhan: 'Lần', lay: (m) => (m.lan_bao_gia ? `Bổ sung ${m.lan_bao_gia}` : 'Gốc') };
  const cotTen = { nhan: 'Nội dung sửa chữa', lay: (m) => h('span', null, m.ten, !khach && m.nguoi_tra === 'khach' ? h('small', { class: 'nhan' }, 'khách trả') : null) };
  const cotNhom = { nhan: 'Nhóm', lay: (m) => NHOM[m.nhom] };
  const cotVat = { nhan: 'VAT', lay: (m) => (!m.xuat_hd ? 'Không' : m.ty_le_vat !== null && m.ty_le_vat !== undefined ? phanTram(m.ty_le_vat) : '') };
  const cotTT = { nhan: 'Trạng thái', lay: (m) => h('span', null, TT_DONG[m.trang_thai], m.ngay_duyet && m.trang_thai !== 'cho_duyet' ? h('small', null, ` ${ngay(m.ngay_duyet)}`) : null,
    m.trang_thai === 'cho_duyet' && duocBaoGia ? h('button', { class: 'nut-chu', type: 'button', onclick: (e) => { e.stopPropagation(); xoaDong(m, ve); } }, 'Xóa') : null) };
  const cot = khach
    ? [cotLan, cotTen, cotNhom,
      { nhan: 'Khách trả trước VAT', so: true, lay: (m) => tien(m.gia_bao) }, cotVat,
      { nhan: 'Khách trả sau VAT', so: true, lay: (m) => tien(sauVatDong(m, m.gia_duyet ?? m.gia_bao)) }, cotTT]
    : [cotLan, cotTen, cotNhom,
      { nhan: 'Báo giá trước duyệt', so: true, lay: (m) => tien(m.gia_bao) },
      { nhan: 'Giá duyệt (chưa VAT)', so: true, lay: (m) => m.gia_duyet === null ? '' : tien(m.gia_duyet) }, cotVat, cotTT];
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, khach ? '2. Báo giá (khách ngoài bảo hiểm)' : '2–3. Báo giá và duyệt giá'),
      h('div', { class: 'hang-nut' },
        duocBaoGia && (goc || boSung) ? nut(goc ? '+ Thêm dòng báo giá' : '+ Báo giá bổ sung (phát sinh)', () => moBaoGia(hs, hm, ve, boSung)) : null,
        duocBaoGia && choDuyet.length ? nut(`Nhập kết quả duyệt (${choDuyet.length})`, () => moDuyetGia(hs, choDuyet, ve), true) : null)),
    bang(cot, hm, { trong: hs.trang_thai === 'tiep_nhan' ? 'Chưa có báo giá.' : 'Chưa có dòng nào.' }),
    khach ? h('p', { class: 'goi-y' }, 'Khách ngoài bảo hiểm không qua bước duyệt giá: lưu báo giá là duyệt luôn, lập lệnh sửa chữa được ngay.')
      : hs.trang_thai === 'bao_gia' ? h('p', { class: 'goi-y' }, 'Xe bảo hiểm: quá 3 ngày chưa duyệt thì báo giám đốc làm việc với bảo hiểm.') : null);
}

async function xoaDong(m, ve) {
  if (!(await xacNhan(`Xóa dòng "${m.ten}"?`, 'Xóa'))) return;
  await chay(() => api.xoaHangMuc(m.id), { thanhCong: 'Đã xóa.' }).then(ve, ve.lai);
}

// Lập báo giá theo nguồn lúc nhận xe:
//  - Xe bảo hiểm: Nội dung sửa chữa, Nhóm, Báo giá trước duyệt (chưa VAT) → chờ bảo hiểm duyệt
//  - Khách ngoài bảo hiểm: Nội dung sửa chữa, Nhóm, Khách trả trước VAT ⇄ sau VAT (nhập ô nào cũng được) → duyệt luôn
function moBaoGia(hs, hm, ve, boSung) {
  const khach = hs.nguon_tt === 'khach';
  const vatCu = [...hm].reverse().find((m) => m.ty_le_vat !== null && m.ty_le_vat !== undefined)?.ty_le_vat;
  const chonVat = oChon('vat', MUC_VAT.map((r) => ({ value: String(r), label: phanTram(r) })),
    String(MUC_VAT.find((r) => Math.abs(r - Number(vatCu)) < 1e-6) ?? 0.08), { trong: null, 'aria-label': 'VAT' });
  const tyLe = () => Number(chonVat.value);
  const danhSach = h('div', { class: 'ds-dong-nhap' });
  const tong = h('dl', { class: 'tong-bao-gia', 'aria-live': 'polite' });

  function capNhatTong() {
    const gia = [...danhSach.children].map((d) => docTien(d.querySelector('[name=gia_bao]').value) || 0);
    const truoc = gia.reduce((a, b) => a + b, 0);
    const sau = gia.reduce((a, b) => a + sauVat(b, tyLe()), 0);
    dat(tong,
      h('dt', null, 'Tổng trước VAT'), h('dd', null, tien(truoc) || '0'),
      h('dt', null, `VAT ${phanTram(tyLe())}`), h('dd', null, tien(sau - truoc) || '0'),
      h('dt', null, khach ? 'Khách thanh toán sau VAT' : 'Tổng sau VAT'), h('dd', null, h('b', null, tien(sau) || '0')));
  }
  // Khách: hai ô trước/sau VAT tự tính qua lại theo VAT đang chọn
  const tinhSau = (d) => { const t = docTien(d.querySelector('[name=gia_bao]').value); const o = d.querySelector('[name=gia_sau_vat]'); if (o) o.value = t === null ? '' : tien(sauVat(t, tyLe())); };
  chonVat.addEventListener('change', () => { if (khach) [...danhSach.children].forEach(tinhSau); capNhatTong(); });

  const themDong = () => {
    const oTruoc = oTien('gia_bao', null);
    const oSau = khach ? oTien('gia_sau_vat', null) : null;
    const dong = h('div', { class: `dong-nhap ${khach ? 'dong-khach' : 'dong-bh'}` },
      truong('Nội dung sửa chữa', oChu('ten', '', { placeholder: 'Ví dụ: Gò sơn cửa trước trái' }), null, { batBuoc: true }),
      truong('Nhóm', oChon('nhom', Object.entries(NHOM).map(([value, label]) => ({ value, label })), 'dong_son', { trong: null })),
      khach ? truong('Khách thanh toán trước VAT', oTruoc, null, { batBuoc: true }) : truong('Báo giá trước duyệt (chưa VAT)', oTruoc, null, { batBuoc: true }),
      khach ? truong('Khách thanh toán sau VAT', oSau) : null,
      h('button', { class: 'nut-chu', type: 'button', onclick: () => { dong.remove(); capNhatTong(); }, 'aria-label': 'Bỏ dòng này' }, 'Bỏ dòng'));
    oTruoc.addEventListener('input', () => { if (khach) tinhSau(dong); capNhatTong(); });
    oSau?.addEventListener('input', () => {
      const s = docTien(oSau.value);
      oTruoc.value = s === null ? '' : tien(Math.round(s / (1 + tyLe())));
      capNhatTong();
    });
    danhSach.append(dong);
    dong.querySelector('input').focus();
    capNhatTong();
  };
  themDong();

  const chiXem = (nhan, giaTri) => h('div', { class: 'truong' }, h('span', { class: 'truong-nhan' }, nhan), h('div', { class: 'o-chi-xem' }, giaTri));
  const noiDung = h('div', null,
    boSung ? h('p', { class: 'thong-bao canh-bao' }, khach ? 'Báo giá bổ sung cho phần phát sinh.' : 'Báo giá bổ sung: phần phát sinh chỉ được làm sau khi duyệt xong.') : null,
    h('div', { class: 'luoi-o dau-bao-gia' },
      khach ? chiXem('Nguồn', 'Khách ngoài bảo hiểm – không qua duyệt giá') : chiXem('Hãng bảo hiểm', hs.hang_bh || '—'),
      truong('VAT', chonVat)),
    danhSach, nut('+ Thêm dòng', themDong), tong);
  moModal(boSung ? 'Báo giá bổ sung' : 'Lập báo giá', noiDung, {
    rong: true, nhanNut: 'Lưu báo giá',
    nutChinh: async () => {
      const dong = [...danhSach.children].map((d) => ({
        ten: d.querySelector('[name=ten]').value.trim(), nhom: d.querySelector('[name=nhom]').value,
        gia_bao: docTien(d.querySelector('[name=gia_bao]').value),
      })).filter((d) => d.ten || d.gia_bao);
      if (!dong.length) { toast('Nhập ít nhất một dòng.', 'loi'); return false; }
      await api.lapBaoGia(hs.id, dong, tyLe());
      toast(khach ? 'Đã lưu báo giá – đã duyệt, lập lệnh sửa chữa được ngay.' : 'Đã lưu báo giá.'); await ve();
    },
  });
}

function moDuyetGia(hs, choDuyet, ve) {
  const oNgayDuyet = oNgay('ngay', homNay(), { max: homNay() });
  const dongs = choDuyet.map((m) => {
    const dongY = h('input', { type: 'checkbox', checked: true, 'aria-label': `Duyệt ${m.ten}` });
    const gia = oTien('gia', m.gia_bao, { 'aria-label': `Giá duyệt ${m.ten}` });
    dongY.addEventListener('change', () => { gia.disabled = !dongY.checked; });
    return { m, dongY, gia, el: h('tr', null, h('td', null, h('label', null, dongY, ' ', m.ten)), h('td', { class: 'so' }, tien(m.gia_bao)), h('td', null, gia)) };
  });
  const noiDung = h('div', null,
    truong('Ngày duyệt', oNgayDuyet, 'Doanh thu tính vào tháng của ngày duyệt', { batBuoc: true }),
    h('div', { class: 'bang-cuon' }, h('table', { class: 'bang' },
      h('thead', null, h('tr', null, h('th', null, 'Hạng mục (bỏ chọn nếu không duyệt)'), h('th', { class: 'so' }, 'Giá báo'), h('th', null, 'Giá duyệt (chưa VAT)'))),
      h('tbody', null, dongs.map((d) => d.el)))),
    hs.nguon_tt !== 'khach' ? h('p', { class: 'goi-y' }, 'Nhớ chụp biên bản giám định, bản duyệt giá, HĐ 3 bên vào mục Ảnh & giấy tờ.') : null);
  moModal('Kết quả duyệt giá', noiDung, {
    rong: true, nhanNut: 'Lưu kết quả',
    nutChinh: async () => {
      const ketQua = dongs.map((d) => ({ id: d.m.id, dong_y: d.dongY.checked, gia_duyet: d.dongY.checked ? docTien(d.gia.value) : null }));
      await api.duyetGia(hs.id, oNgayDuyet.value, ketQua);
      toast('Đã lưu kết quả duyệt.'); await ve();
    },
  });
}

// ---------- Lệnh sửa chữa, sửa chữa (bước 4–6) ----------
function theSuaChua({ hs, hm, ps, ve }) {
  if (!['da_duyet', 'dang_sua', 'cho_kcs', 'dat_kcs'].includes(hs.trang_thai) && !hm.some((m) => m.to_id)) return null;
  const chuaGiao = hm.filter((m) => m.trang_thai === 'duyet');
  const dangLam = hm.filter((m) => ['dang_lam', 'xong'].includes(m.trang_thai));
  const duocLap = q('cvdv', 'quan_ly', 'giam_doc');
  const psMo = ps.filter((p) => !p.da_xu_ly);
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '4–6. Lệnh sửa chữa và sửa chữa'),
      h('div', { class: 'hang-nut' },
        duocLap && chuaGiao.length && ['da_duyet', 'dang_sua'].includes(hs.trang_thai)
          ? nut(hs.trang_thai === 'da_duyet' ? 'Lập lệnh sửa chữa' : `Giao thêm cho tổ (${chuaGiao.length})`, () => moLenh(hs, chuaGiao, ve), true) : null,
        ['dang_sua', 'cho_kcs'].includes(hs.trang_thai) ? nut('Báo phát sinh', () => moPhatSinh(hs, ve)) : null)),
    psMo.length ? h('div', { class: 'thong-bao canh-bao' }, h('b', null, 'Phát sinh chờ báo giá bổ sung: '),
      psMo.map((p) => h('div', null, `${ngayGio(p.luc)} – ${p.mo_ta}`))) : null,
    !dangLam.length ? h('p', { class: 'trong' }, 'Chưa giao việc cho tổ nào. Chưa có lệnh sửa chữa thì chưa làm, chưa xuất vật tư.') :
      bang([
        { nhan: 'Hạng mục', khoa: 'ten' },
        { nhan: 'Tổ', lay: (m) => api.dm.ten('to_thuc_hien', m.to_id) },
        { nhan: 'Người làm', lay: (m) => m.nguoi_lam || '' },
        { nhan: 'Trạng thái', lay: (m) => m.trang_thai === 'xong' ? `Xong ${ngayGio(m.xong_luc)}` :
          duocLap ? h('button', { class: 'nut nho', type: 'button', onclick: () => chay(() => api.baoXong(m.id), { thanhCong: 'Đã báo xong.' }).then(ve, ve.lai) }, 'Báo xong') : 'Đang làm' },
      ], dangLam));
}

function moLenh(hs, ds, ve) {
  const oHen = h('input', { type: 'datetime-local', name: 'hen_giao', value: choODatetime(hs.hen_giao) });
  const dongs = ds.map((m) => {
    const to = oChon('to', api.dm.to_thuc_hien.map((t) => ({ value: t.id, label: t.ten })),
      { dong_son: 'DS', phu_tung: 'DS', dmg: 'DMG', detailing: 'DT' }[m.nhom], { trong: null, 'aria-label': `Tổ làm ${m.ten}` });
    const nguoi = oChu('nguoi', '', { placeholder: 'Người làm', 'aria-label': `Người làm ${m.ten}` });
    return { m, to, nguoi, el: h('tr', null, h('td', null, m.ten), h('td', null, to), h('td', null, nguoi)) };
  });
  moModal('Lệnh sửa chữa', h('div', null,
    truong('Giờ hẹn giao xe', oHen, null, { batBuoc: !hs.hen_giao }),
    h('div', { class: 'bang-cuon' }, h('table', { class: 'bang' },
      h('thead', null, h('tr', null, h('th', null, 'Hạng mục'), h('th', null, 'Tổ'), h('th', null, 'Người làm'))),
      h('tbody', null, dongs.map((d) => d.el))))), {
    rong: true, nhanNut: 'Giao việc',
    nutChinh: async () => {
      await api.lapLenh(hs.id, oHen.value ? new Date(oHen.value).toISOString() : null,
        dongs.map((d) => ({ id: d.m.id, to_id: d.to.value, nguoi_lam: d.nguoi.value })));
      toast('Đã giao việc cho tổ.'); await ve();
    },
  });
}

function moPhatSinh(hs, ve) {
  const form = h('form', null,
    truong('Hư hỏng phát sinh', oVung('mo_ta', '', { rows: 3 }), 'Dừng phần phát sinh, chờ báo giá bổ sung và duyệt.', { batBuoc: true }),
    truong('Ảnh hư hỏng', oChonTep({ name: 'anh', capture: 'environment', multiple: true }, 'Chụp ảnh hư hỏng')));
  moModal('Báo phát sinh', form, {
    nhanNut: 'Gửi',
    nutChinh: async () => {
      await api.baoPhatSinh(hs.id, docForm(form).mo_ta);
      for (const f of form.anh.files) await api.taiTep(hs, 'phat_sinh', await nenAnh(f, 'phat_sinh'));
      toast('Đã báo phát sinh.'); await ve();
    },
  });
}

// ---------- KCS (bước 7) ----------
function theKcs({ hs, hm, tep, dsKcs, ve }) {
  if (!['cho_kcs', 'dat_kcs', 'da_giao', 'da_gui_hs', 'dong'].includes(hs.trang_thai) && !dsKcs.length) return null;
  const coAnh = tep.some((t) => t.buoc === 'kcs');
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '7. Nghiệm thu (KCS) và rửa xe'),
      hs.trang_thai === 'cho_kcs' && q('quan_ly', 'giam_doc') ? h('div', { class: 'hang-nut' },
        nut('Chưa đạt – làm lại', () => moKhongDat(hs, hm, ve)),
        nut('Đạt KCS', async () => {
          if (!coAnh) { toast('Tải ảnh sau sửa ở mục "Ảnh & giấy tờ" (bước: Sau sửa) trước khi ký KCS.', 'loi'); return; }
          await chay(() => api.kcs(hs.id, true, null, null), { thanhCong: 'Đã ký đạt KCS.' }).then(ve, ve.lai);
        }, true)) : null),
    hs.trang_thai === 'cho_kcs' && !q('quan_ly', 'giam_doc') ? h('p', { class: 'goi-y' }, 'Chờ quản lý chung nghiệm thu.') : null,
    hs.trang_thai === 'cho_kcs' && !coAnh ? h('p', { class: 'goi-y' }, 'Chưa có ảnh sau sửa.') : null,
    dsKcs.length ? h('ul', { class: 'ds-don' }, dsKcs.map((k) => h('li', null, ngayGio(k.luc), ' – ', k.dat ? h('b', { class: 'chu-tot' }, 'Đạt') : h('b', { class: 'chu-loi' }, 'Chưa đạt: '), k.loi || ''))) : null);
}

function moKhongDat(hs, hm, ve) {
  const ds = hm.filter((m) => m.trang_thai === 'xong');
  const form = h('form', null,
    truong('Lỗi cần làm lại', oVung('loi', '', { rows: 2 }), null, { batBuoc: true }),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Hạng mục phải làm lại'),
      ds.map((m) => oCheck(`m_${m.id}`, false, `${m.ten} (${api.dm.ten('to_thuc_hien', m.to_id)})`))));
  moModal('KCS chưa đạt', form, {
    nhanNut: 'Trả về tổ',
    nutChinh: async () => {
      const d = docForm(form);
      const lamLai = ds.filter((m) => d[`m_${m.id}`]).map((m) => m.id);
      await api.kcs(hs.id, false, d.loi, lamLai);
      toast('Đã trả xe về tổ làm lại.'); await ve();
    },
  });
}

// ---------- Giao xe (bước 8) ----------
function theGiaoXe({ hs, ve }) {
  if (hs.trang_thai !== 'dat_kcs' && !hs.giao_luc) return null;
  if (hs.giao_luc) {
    return h('section', { class: 'the' }, h('h2', null, '8. Thanh toán và giao xe'),
      h('p', null, 'Đã giao lúc ', h('b', null, ngayGio(hs.giao_luc)), hs.cho_giao_no_boi ? ' (được duyệt giao khi khách còn nợ)' : ''),
      hs.cam_nhan_khach ? h('p', null, 'Cảm nhận của khách: ', hs.cam_nhan_khach) : null,
      h('p', { class: 'mo-ta' }, `Số HĐ bảo hiểm: ${hs.so_hd_bao_hiem || '—'} · Số HĐ khách: ${hs.so_hd_khach || '—'}`));
  }
  const bh = hs.nguon_tt !== 'khach';
  const form = h('form', { class: 'luoi-o' },
    bh ? truong('Khấu trừ – giảm trừ (khách trả)', oTien('khau_tru_giam_tru', hs.khau_tru_giam_tru), 'Gộp mọi tên gọi của hãng: khấu trừ, miễn thường, giảm trừ, chế tài') : null,
    bh ? truong('Số hóa đơn phần bảo hiểm', oChu('so_hd_bao_hiem', hs.so_hd_bao_hiem)) : null,
    truong('Số hóa đơn phần khách (nếu có)', oChu('so_hd_khach', hs.so_hd_khach)),
    q('quan_ly', 'giam_doc') ? truong('Cảm nhận của khách khi nhận xe', oVung('cam_nhan_khach', hs.cam_nhan_khach), 'Quản lý chung ghi', { rong: true }) : null);
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '8. Thanh toán và giao xe')),
    h('p', { class: 'goi-y' }, 'Kế toán thu tiền phần khách trước (mục Thu chi), rồi bấm Giao xe. Khách còn nợ thì cần giám đốc hoặc quản lý chung duyệt.'),
    form,
    h('div', { class: 'hang-nut' },
      q('quan_ly', 'giam_doc') ? nut('Duyệt giảm giá cho khách', () => moGiamGia(hs, ve)) : null,
      q('quan_ly', 'giam_doc') && !hs.cho_giao_no_boi ? nut('Duyệt giao khi khách còn nợ', () =>
        chay(() => api.duyetGiaoConNo(hs.id), { thanhCong: 'Đã duyệt giao xe khi còn nợ.' }).then(ve, ve.lai)) : null,
      q('ke_toan', 'giam_doc') ? h('a', { class: 'nut', href: `#/thu-chi?ho_so=${hs.id}` }, 'Thu tiền khách') : null,
      q('ke_toan', 'cvdv', 'quan_ly', 'giam_doc') ? nut('Giao xe', async () => {
        const d = docForm(form);
        await chay(() => api.giaoXe(hs.id, d), { thanhCong: 'Đã giao xe.' }).then(ve, ve.lai);
      }, true) : null));
}

function moGiamGia(hs, ve) {
  const form = h('form', null,
    truong('Số tiền giảm cho khách', oTien('so_tien', hs.giam_gia), 'Giảm giá làm giảm doanh thu của tháng duyệt', { batBuoc: true }),
    truong('Lý do', oVung('ly_do', ''), null, { batBuoc: true }));
  moModal('Duyệt giảm giá', form, {
    nhanNut: 'Duyệt',
    nutChinh: async () => { const d = docForm(form); await api.duyetGiamGia(hs.id, d.so_tien ?? 0, d.ly_do); toast('Đã duyệt giảm giá.'); await ve(); },
  });
}

// ---------- Hồ sơ bảo hiểm, hoa hồng (bước 9) ----------
function theHoSoBH({ hs, ve }) {
  if (hs.nguon_tt === 'khach' || !hs.giao_luc) return null;
  const keToan = q('ke_toan', 'giam_doc');
  return h('section', { class: 'the' },
    h('h2', null, '9. Hồ sơ bảo hiểm, thu nợ, hoa hồng'),
    hs.gui_hs_ngay ? h('p', null, 'Đã gửi hồ sơ ngày ', h('b', null, ngay(hs.gui_hs_ngay)))
      : keToan ? h('div', { class: 'hang-nut' },
        oNgay('ngay_gui', homNay(), { max: homNay(), 'aria-label': 'Ngày gửi hồ sơ' }),
        nut('Đã gửi hồ sơ bảo hiểm', (e) => {
          const ngayGui = e.target.parentElement.querySelector('[name=ngay_gui]').value;
          chay(() => api.guiHoSoBH(hs.id, ngayGui), { thanhCong: 'Đã ghi ngày gửi hồ sơ.' }).then(ve, ve.lai);
        }, true))
        : h('p', { class: 'goi-y' }, 'Chờ kế toán gửi hồ sơ (trong 3 ngày sau giao xe).'),
    hs.gdv_id ? h('div', { class: 'hang-nut' },
      h('span', null, 'Hoa hồng GDV ', h('b', null, hs.gdv), ': ', hs.hoa_hong_gdv === null ? h('i', null, 'chưa nhập') : h('b', null, tien(hs.hoa_hong_gdv) + ' đ'),
        hs.hoa_hong_ghi_chu ? h('small', null, ` (${hs.hoa_hong_ghi_chu})`) : null),
      keToan ? nut(hs.hoa_hong_gdv === null ? 'Nhập hoa hồng' : 'Sửa', () => moHoaHong(hs, ve)) : null) : null);
}

function moHoaHong(hs, ve) {
  const form = h('form', null,
    truong('Số tiền hoa hồng', oTien('so_tien', hs.hoa_hong_gdv), 'Kế toán tính tay theo cách của từng hãng / GDV', { batBuoc: true }),
    truong('Ghi chú cách tính', oChu('ghi_chu', hs.hoa_hong_ghi_chu, { placeholder: 'Ví dụ: 5% + 200.000' })));
  moModal('Hoa hồng giám định viên', form, {
    nutChinh: async () => {
      const d = docForm(form);
      await chay((boQua) => api.nhapHoaHong(hs.id, d.so_tien, d.ghi_chu, boQua), { thanhCong: 'Đã lưu hoa hồng.' });
      await ve();
    },
  });
}

// ---------- Chăm sóc (bước 10) ----------
function theChamSoc({ hs, ve }) {
  if (!hs.giao_luc) return null;
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '10. Chăm sóc sau giao'),
      q('quan_ly', 'giam_doc') ? nut(hs.cham_soc_luc ? 'Ghi lại' : 'Ghi kết quả gọi', () => moChamSoc(hs, ve), !hs.cham_soc_luc) : null),
    hs.cham_soc_luc ? h('p', null, `${ngayGio(hs.cham_soc_luc)}: ${hs.cham_soc_ket_qua}`,
      hs.hen_bao_duong ? h('br') : null, hs.hen_bao_duong ? `Hẹn bảo dưỡng: ${ngay(hs.hen_bao_duong)}` : null)
      : h('p', { class: 'goi-y' }, `Gọi hỏi thăm khách sau 3 ngày (từ ${ngay(new Date(new Date(hs.giao_luc).getTime() + 3 * 864e5))}).`));
}

function moChamSoc(hs, ve) {
  const form = h('form', null,
    truong('Kết quả gọi', oVung('ket_qua', hs.cham_soc_ket_qua, { rows: 3 }), null, { batBuoc: true }),
    truong('Hẹn bảo dưỡng (3–6 tháng sau)', oNgay('hen', hs.hen_bao_duong)));
  moModal('Chăm sóc sau giao', form, {
    nutChinh: async () => { const d = docForm(form); await api.ghiChamSoc(hs.id, d.ket_qua, d.hen); toast('Đã lưu.'); await ve(); },
  });
}

// ---------- Tiền ----------
function theTien({ hs }) {
  const d = (nhan, gt, dam) => h('div', { class: `dong-tien ${dam ? 'dam' : ''}` }, h('span', null, nhan), h('b', null, tien(gt) || '0'));
  const bh = hs.nguon_tt !== 'khach';
  return h('section', { class: 'the' }, h('h2', null, 'Tiền'),
    bh ? [d('Bảo hiểm duyệt (có VAT)', hs.bh_duyet), Number(hs.khau_tru_giam_tru) ? d('− Khấu trừ – giảm trừ', hs.khau_tru_giam_tru) : null,
      d('Bảo hiểm phải trả', hs.phai_thu_bh), d('Bảo hiểm đã trả', hs.da_thu_bh), d('Bảo hiểm còn nợ', hs.con_no_bh, true), h('hr')] : null,
    d('Khách làm thêm / sửa lẻ', hs.khach_duyet),
    bh && Number(hs.khau_tru_giam_tru) ? d('+ Khấu trừ – giảm trừ', hs.khau_tru_giam_tru) : null,
    Number(hs.giam_gia) ? d('− Giảm giá đã duyệt', hs.giam_gia) : null,
    d('Khách phải trả', hs.phai_thu_khach), d('Khách đã trả (gồm cọc)', hs.da_thu_khach), d('Khách còn nợ', hs.con_no_khach, true),
    q('ke_toan', 'giam_doc') && !['dong', 'huy'].includes(hs.trang_thai)
      ? h('div', { class: 'hang-nut' }, h('a', { class: 'nut nho', href: `#/thu-chi?ho_so=${hs.id}` }, 'Lập phiếu thu cho xe này')) : null);
}

// ---------- Ảnh và giấy tờ ----------
function theTep({ hs, tep, ve }) {
  const luoi = h('div', { class: 'luoi-anh' });
  (async () => {
    let link = {};
    try { link = await api.linkTepNhieu(tep.map((t) => t.duong_dan)); } catch { /* lỗi mạng: để trống */ }
    for (const t of tep) {
      const l = link[t.duong_dan];
      if (!l?.lon) continue;
      const laAnh = /\.(jpe?g|png|webp|heic)$/i.test(t.duong_dan);
      luoi.append(h('a', { href: l.lon, target: '_blank', rel: 'noopener', class: 'o-anh', title: BUOC_TEP[t.buoc] || t.buoc },
        laAnh ? h('img', { src: l.nho, alt: BUOC_TEP[t.buoc] || t.buoc, loading: 'lazy' }) : h('span', { class: 'tep' }, 'PDF'),
        h('small', null, BUOC_TEP[t.buoc] || t.buoc)));
    }
  })();
  const chonBuoc = oChon('buoc', Object.entries(BUOC_TEP).map(([value, label]) => ({ value, label })),
    { tiep_nhan: 'tiep_nhan', bao_gia: 'duyet_gia', da_duyet: 'duyet_gia', dang_sua: 'phat_sinh', cho_kcs: 'kcs', dat_kcs: 'giao_xe', da_giao: 'ho_so_bh' }[hs.trang_thai] || 'khac',
    { trong: null, 'aria-label': 'Ảnh của bước' });
  const oTep = h('input', { type: 'file', accept: 'image/*,application/pdf', multiple: true, 'aria-label': 'Chọn ảnh hoặc tệp' });
  oTep.addEventListener('change', async () => {
    let n = 0;
    for (const f of oTep.files) {
      try { await api.taiTep(hs, chonBuoc.value, await nenAnh(f, chonBuoc.value), f.type === 'application/pdf' ? 'bien_ban' : 'anh'); n++; }
      catch (e) { toast(`Không tải được ${f.name}: ${e.message}`, 'loi'); }
    }
    if (n) { toast(`Đã tải ${n} tệp.`); ve(); }
  });
  return h('section', { class: 'the' }, h('h2', null, `Ảnh & giấy tờ (${tep.length})`),
    !['dong', 'huy'].includes(hs.trang_thai) || q('ke_toan', 'giam_doc')
      ? h('div', { class: 'tai-tep' }, chonBuoc, h('label', { class: 'nut' }, 'Chụp / chọn tệp', oTep)) : null,
    tep.length ? luoi : h('p', { class: 'trong' }, 'Chưa có ảnh.'));
}

function theNhatKy({ nk }) {
  const ten = (id) => (api.dm.nhan_vien || []).find((n) => n.id === id)?.ho_ten || '';
  return h('details', { class: 'the' }, h('summary', null, h('h2', null, `Nhật ký (${nk.length})`)),
    h('ul', { class: 'nhat-ky' }, nk.map((n) => h('li', null, h('small', null, ngayGio(n.luc), ' · ', ten(n.boi)), h('div', null, n.ghi_chu || TRANG_THAI[n.sang_trang_thai])))));
}

function moHuy(hs) {
  const form = h('form', null, truong('Lý do hủy', oVung('ly_do', ''), 'Ví dụ: khách không sửa, bảo hiểm từ chối. Nếu đã thu cọc, lập đề nghị chi "Trả lại cọc cho khách".', { batBuoc: true }));
  moModal('Hủy hồ sơ', form, {
    nhanNut: 'Hủy hồ sơ',
    nutChinh: async () => { await api.huyHoSo(hs.id, docForm(form).ly_do); toast('Đã hủy hồ sơ.'); veDanhSachHoSo(hs); },
  });
}
