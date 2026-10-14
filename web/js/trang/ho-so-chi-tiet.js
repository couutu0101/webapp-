// Chi tiết hồ sơ xe: 9 bước trên một trang, mỗi bước chỉ hiện nút cho đúng người
import {
  h, oChonTep, bienSo, oNgayVN, oNgayGioVN, tien, ngay, ngayGio, homNay, truong, oChu, oTien, oChon, oVung, oNgay, oCheck, docForm, docTien, chay, moModal, toast, nhanTrangThai, bang, NHOM, NHOM_CHON, NGUON, TRANG_THAI, xacNhan, dat, veDanhSachHoSo, icon, buocXe, BUOC_XE, chipNguoi, hoiLyDo,
} from '../ui.js';
import { khoiPhuTungXe } from './kho.js';
import { khungGiaoViec, giaoSauKhiLuu, dongDangCho, nguoiLamTungBuoc, tenGoi, VAI_TRO_BUOC, aiDangLam, chipNhanVien } from './giao-viec.js';
import { hanHoSo, chuHan } from '../han-viec.js';
import * as api from '../api.js';
import { ghiTiep, tuGhiNgayKhiBam, nhacHetHan, layLichSu, khoiLichSu } from './lich-su-xe.js';

const TT_DONG = { cho_duyet: 'Chờ duyệt', duyet: 'Đã duyệt', tu_choi: 'Không duyệt', dang_lam: 'Đang làm', xong: 'Xong' };
const BUOC_TEP = { tiep_nhan: 'Nhận xe', duyet_gia: 'Giám định / duyệt giá / HĐ 3 bên', phat_sinh: 'Phát sinh', kcs: 'Sau sửa (KCS)', giao_xe: 'Giao xe', ho_so_bh: 'Hồ sơ bảo hiểm', khac: 'Khác' };

export default async function trangChiTiet(el, idChu) {
  const id = Number(idChu);
  // Lưu xong bất kỳ thao tác nào: về danh sách Hồ sơ xe; lỗi thì vẽ lại trang để thấy dữ liệu mới nhất
  let hsDangXem = { id, ma: '' };
  const ve = () => veDanhSachHoSo(hsDangXem);
  const veLai = ve.lai = async () => {
    const [hs, hm, nk, tep, ps, dsKcs, [viec], [gv], [cho]] = await Promise.all([
      api.layHoSo(id), api.layHangMuc(id), api.layNhatKy(id), api.layTep(id), api.layPhatSinh(id), api.layKcs(id),
      api.doc('v_viec_ho_so', (q) => q.eq('ho_so_id', id)).catch(() => []),
      api.doc('v_gia_von_ho_so', (q) => q.eq('ho_so_id', id)).catch(() => []),
      api.doc('v_cho_phu_tung', (q) => q.eq('ho_so_id', id)).catch(() => [])]);
    if (!hs) { dat(el, h('p', { class: 'trong' }, 'Không tìm thấy hồ sơ, hoặc bạn không có quyền xem.')); return; }
    hsDangXem = hs;
    const ctx = { hs, hm, nk, tep, ps, dsKcs, ve, viec, giaVon: Number(gv?.gia_von || 0), cho };
    dat(el, 
      dau(ctx), theTienDo(ctx, veLai),
      h('div', { class: 'cot-doi' },
        h('div', null, theThongTin(ctx), theBaoGia(ctx), theSuaChua(ctx), theKcs(ctx), theGiaoXe(ctx), theHoSoBH(ctx), theChamSoc(ctx)),
        h('div', null, theTien(ctx), theTep(ctx), theNhatKy(ctx))));
  };
  await veLai();
}

const q = (...ds) => api.coVaiTro(...ds);
const nut = (nhan, onclick, chinh = false) => h('button', { class: `nut ${chinh ? 'chinh' : ''}`, type: 'button', onclick }, nhan);

function dau({ hs, cho }) {
  return h('div', { class: 'tieu-de-trang' },
    h('div', null,
      h('p', { class: 'mo-ta' }, h('a', { href: '#/ho-so' }, '← Hồ sơ xe')),
      h('h1', { class: 'tieu-de-xe' }, bienSo(hs.bien_so_hien_thi, { lon: true }), nhanTrangThai(hs.trang_thai),
        cho ? h('span', { class: 'nhan tt-canh-bao' }, `Chờ phụ tùng ${cho.so_ngay} ngày`) : null),
      h('p', { class: 'mo-ta' }, [hs.ma, hs.xe, hs.mau].filter(Boolean).join(' · '),
        hs.loai === 'bao_hanh' ? [' ', h('span', { class: 'nhan tt-canh-bao' }, 'Bảo hành'),
          hs.ho_so_goc_id ? [' – làm lại miễn phí lỗi cũ của ', h('a', { href: `#/ho-so/${hs.ho_so_goc_id}` }, 'hồ sơ gốc')] : null] : null,
        hs.tu_excel ? h('span', { class: 'nhan' }, 'Chuyển từ Excel') : null)),
    h('div', { class: 'hang-nut doc' },
      ['tiep_nhan', 'bao_gia', 'da_duyet'].includes(hs.trang_thai) && q('cvdv', 'quan_ly', 'giam_doc')
        ? nut('Hủy hồ sơ', () => moHuy(hs)) : null,
      // Xe đã rời xưởng quay lại: tiếp nhận lần mới với mọi thông tin điền sẵn
      ['da_giao', 'da_gui_hs', 'dong'].includes(hs.trang_thai) && q('cvdv', 'quan_ly', 'giam_doc')
        ? h('a', { class: 'nut chinh', href: `#/ho-so/moi?tu_ho_so=${hs.id}` }, '+ Tiếp nhận xe') : null,
      hs.trang_thai === 'dong' && q('cvdv', 'quan_ly', 'giam_doc')
        ? h('a', { class: 'nut', href: `#/ho-so/moi?bao_hanh=${hs.id}` }, 'Tạo hồ sơ bảo hành') : null));
}

// Thẻ tiến độ: dòng "Đang chờ" (bước, người được giao, hạn) + đường 9 bước, xe dừng ở bước đang chờ
const daChayTienDo = new Set();   // hiệu ứng xe chạy chỉ một lần cho mỗi hồ sơ + bước (vẽ lại sau thao tác thì thôi)
function theTienDo({ hs, hm, nk, viec }, veLai) {
  if (hs.trang_thai === 'huy') return h('p', { class: 'thong-bao canh-bao' }, 'Hồ sơ đã hủy: ', hs.ly_do_huy || '');
  const han = hanHoSo(hs, viec?.giao_viec_luc);
  const thongTinHan = { han, chuHan: han ? chuHan(han) : '' };
  return h('section', { class: 'the the-tien-do' },
    dongDangCho(hs, viec, hm, veLai, thongTinHan),
    tienDo(hs, nk, aiDangLam(hs, viec, hm)));
}

function tienDo(hs, nk, aiDang) {
  const nguoi = nguoiLamTungBuoc(nk);
  const { dang, boQua, xong } = buocXe(hs);
  const soXong = BUOC_XE.filter((_, i) => xong(i + 1)).length;
  const tien = dang === 0 ? 1 : Math.max(0, (dang - 1) / 8);
  const khoa = `${hs.id}-${dang}`;
  const chayLan = !daChayTienDo.has(khoa);
  daChayTienDo.add(khoa);
  return h('div', { class: 'tien-do-khung' },
    h('ol', { class: `tien-do${chayLan ? ' chay' : ''}`, style: `--tien:${tien}`, 'aria-label': 'Tiến độ 9 bước' }, BUOC_XE.map((b, i) => {
      const so = i + 1;
      const lop = boQua.includes(so) ? 'bo' : xong(so) ? 'xong' : so === dang ? 'dang' : '';
      const ai = nguoi[so];
      let nguoiLam = null;
      if (lop === 'dang') {
        nguoiLam = h('span', { class: 'buoc-nguoi nguoi-lam' },
          aiDang.slice(0, 2).map((x) => chipNguoi(x.gon, { vai: x.vai, chu: x.chu, title: x.nhan, nho: true })),
          aiDang.length > 2 ? h('small', null, `+${aiDang.length - 2} tổ`) : null);
      } else if (ai && lop !== 'bo') {
        nguoiLam = h('span', { class: 'buoc-nguoi nguoi-lam', title: `${tenGoi(ai.boi)} · ${ngayGio(ai.luc)}` },
          chipNhanVien(ai.boi, { gon: true, nho: true }) || chipNguoi(tenGoi(ai.boi) || '?', { nho: true }),
          h('span', { class: 'buoc-luc' }, ngay(ai.luc).slice(0, 5)));
      } else if (lop === 'bo') nguoiLam = h('span', { class: 'buoc-luc' }, 'Không áp dụng');
      return h('li', { class: lop || null, 'aria-current': lop === 'dang' ? 'step' : null },
        h('span', { class: 'buoc-nut', 'aria-hidden': 'true' },
          lop === 'xong' ? icon('check') : lop === 'dang' ? icon('xeChay') : lop === 'bo' ? '–' : String(so)),
        h('span', { class: 'buoc-ten' }, h('span', { class: 'buoc-so' }, `${so}`), ' ', b),
        nguoiLam);
    })),
    h('p', { class: 'tien-do-chu' }, dang === 0 ? 'Đã xong cả 9 bước' : `Bước ${dang}/9: ${BUOC_XE[dang - 1]} · đã xong ${soXong} bước`));
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
        // 036: GDV để trống được lúc nhận xe – nhắc ghi trước khi nhập kết quả duyệt giá
        dong('Giám định viên', hs.gdv_cho_them ? h('span', null, hs.gdv, ' ', h('span', { class: 'nhan tt-canh-bao' }, 'chờ thêm vào danh sách'))
          : hs.gdv || (['dong', 'huy'].includes(hs.trang_thai) ? null : h('span', { class: 'nhan tt-canh-bao', 'data-thieu-gdv': '' }, 'Chưa có – ghi trước khi duyệt giá')))] : null,
      dong('Hết hạn BH thân vỏ', ngay(hs.han_bh_than_vo)), dong('Hết hạn BH TNDS', ngay(hs.han_bao_hiem)),
      dong('Vào xưởng', ngayGio(hs.ngay_vao)), dong('Số km (ODD)', hs.so_km !== null && hs.so_km !== undefined ? `${tien(hs.so_km)} km` : null),
      dong('Hẹn giao', ngayGio(hs.hen_giao)),
      dong('Yêu cầu khách hàng', hs.tinh_trang_xe), dong('Có thể tư vấn', hs.tu_van)),
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
    truong('Số km (ODD)', oTien('so_km', hs.so_km ?? null), 'Số trên đồng hồ lúc nhận xe'),
    truong('Hẹn giao', oNgayGioVN('hen_giao', hs.hen_giao), 'Giờ 24h'),
    hs.nguon_tt !== 'khach' ? [
      truong('Hãng bảo hiểm', oChon('hang_bh_id', dm.hang_bao_hiem.map((x) => ({ value: x.id, label: x.ten })), hs.hang_bh_id)),
      truong('Giám định viên', chonGdv), truong('Tên GDV mới (nếu chọn "chờ thêm")', oGdvMoi)] : null,
    truong('Hết hạn bảo hiểm thân vỏ', oNgayVN('han_bh_than_vo', hs.han_bh_than_vo), 'Ngày/tháng/năm'),
    truong('Hết hạn bảo hiểm TNDS', oNgayVN('han_bao_hiem', hs.han_bao_hiem), 'Ngày/tháng/năm'),
    // Yêu cầu khách hàng và tư vấn: không sửa nội dung cũ, chỉ ghi thêm (tự có ngày ở đầu) để giữ toàn bộ lịch sử
    h('div', { class: 'truong rong' }, h('span', { class: 'truong-nhan' }, 'Yêu cầu khách hàng đã ghi'), h('div', { class: 'nhat-ky-ghi' }, hs.tinh_trang_xe || '—')),
    truong('Ghi thêm yêu cầu', oThemTinhTrang, 'Để trống nếu không có gì mới', { rong: true }),
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
      if (d.so_km !== null && d.so_km > 9999999) throw new Error('Số km (ODD) không đúng.');
      const p = { ten_khach: d.ten_khach, dien_thoai: d.dien_thoai, mau: d.mau, so_km: d.so_km,
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
// Mức VAT đầu ra trên báo giá (009 – máy chủ chỉ nhận 8/10/12%); VAT đầu vào phiếu nhập kho ở kho.js
const VAT_BAO_GIA = [0.08, 0.10, 0.12];
const phanTram = (r) => `${Math.round(Number(r) * 100)}%`;
const sauVat = (gia, tyLe) => Math.round(Number(gia) * (1 + Number(tyLe)));
// Tiền sau VAT của một dòng đã lưu (dòng cũ chưa chọn VAT: tạm hiện theo 8%)
const sauVatDong = (m, gia) => (m.xuat_hd ? sauVat(gia, m.ty_le_vat ?? 0.08) : Number(gia));

function theBaoGia({ hs, hm, ve }) {
  const khach = hs.nguon_tt === 'khach';
  const choDuyet = hm.filter((m) => m.trang_thai === 'cho_duyet');
  const duocBaoGia = q('cvdv', 'quan_ly', 'giam_doc');
  // Hồ sơ bảo hành (036): làm lại miễn phí – không báo giá, không duyệt giá; chỉ liệt kê hạng mục
  if (hs.loai === 'bao_hanh' && !['tiep_nhan', 'bao_gia'].includes(hs.trang_thai)) {
    return h('section', { class: 'the' },
      h('div', { class: 'the-dau' }, h('h2', null, '2–3. Bảo hành – không báo giá, không duyệt giá')),
      bang([
        { nhan: 'Hạng mục làm lại', lay: (m) => h('span', { class: 'ten-hang-muc' }, h('span', null, m.ten), h('small', null, NHOM[m.nhom])) },
        { nhan: 'Trạng thái', lay: (m) => h('span', null, TT_DONG[m.trang_thai], m.xong_luc ? h('small', null, ` ${ngay(m.xong_luc)}`) : null) },
      ], hm, { trong: 'Chưa có hạng mục.', gon: true }),
      h('p', { class: 'goi-y' }, 'Hạng mục bảo hành làm lại miễn phí, không tính doanh thu. Khách muốn làm thêm việc tính tiền thì tiếp nhận một hồ sơ sửa chữa riêng.'));
  }
  const thieuGdv = !khach && !hs.gdv_id && choDuyet.length > 0;
  const goc = ['tiep_nhan', 'bao_gia'].includes(hs.trang_thai);
  const boSung = ['da_duyet', 'dang_sua', 'cho_kcs'].includes(hs.trang_thai);
  // Cột "Lần" chỉ hiện khi có báo giá bổ sung; nhóm (đồng, sơn, phụ tùng…) ghi nhỏ dưới tên để bảng vừa khung
  const coBoSung = hm.some((m) => m.lan_bao_gia);
  const cotLan = coBoSung ? { nhan: 'Lần', lay: (m) => (m.lan_bao_gia ? `Bổ sung ${m.lan_bao_gia}` : 'Gốc') } : null;
  const cotTen = { nhan: 'Nội dung sửa chữa', lay: (m) => h('span', { class: 'ten-hang-muc' }, h('span', null, m.ten, !khach && m.nguoi_tra === 'khach' ? h('small', { class: 'nhan' }, 'khách trả') : null), h('small', null, NHOM[m.nhom])) };
  const cotVat = { nhan: 'VAT', lay: (m) => (!m.xuat_hd ? 'Không' : m.ty_le_vat !== null && m.ty_le_vat !== undefined ? phanTram(m.ty_le_vat) : '') };
  const cotTT = { nhan: 'Trạng thái', lay: (m) => h('span', null, TT_DONG[m.trang_thai], m.ngay_duyet && m.trang_thai !== 'cho_duyet' ? h('small', null, ` ${ngay(m.ngay_duyet)}`) : null,
    m.trang_thai === 'cho_duyet' && duocBaoGia ? h('button', { class: 'nut-chu', type: 'button', onclick: (e) => { e.stopPropagation(); xoaDong(m, ve); } }, 'Xóa') : null) };
  const cot = (khach
    ? [cotLan, cotTen,
      { nhan: 'Đơn giá (chưa VAT)', so: true, lay: (m) => tien(m.gia_bao) }, cotVat,
      { nhan: 'Khách trả sau VAT', so: true, lay: (m) => tien(sauVatDong(m, m.gia_duyet ?? m.gia_bao)) }, cotTT]
    : [cotLan, cotTen,
      { nhan: 'Đơn giá báo (chưa VAT)', so: true, lay: (m) => tien(m.gia_bao) },
      { nhan: 'Giá duyệt (chưa VAT)', so: true, lay: (m) => m.gia_duyet === null ? '' : tien(m.gia_duyet) }, cotVat, cotTT]).filter(Boolean);
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, khach ? '2. Báo giá (khách ngoài bảo hiểm)' : '2–3. Báo giá và duyệt giá'),
      h('div', { class: 'hang-nut' },
        duocBaoGia && (goc || boSung) ? nut(goc ? '+ Thêm dòng báo giá' : '+ Báo giá bổ sung (phát sinh)', () => moBaoGia(hs, hm, ve, boSung)) : null,
        duocBaoGia && choDuyet.length ? nut(`Nhập kết quả duyệt (${choDuyet.length})`, () => moDuyetGia(hs, choDuyet, ve, hm), true) : null)),
    bang(cot, hm, { trong: hs.trang_thai === 'tiep_nhan' ? 'Chưa có báo giá.' : 'Chưa có dòng nào.', gon: true }),
    thieuGdv ? h('p', { class: 'thong-bao canh-bao' }, 'Chưa có giám định viên – bấm "Sửa" ở mục Thông tin xe và khách để ghi GDV trước khi nhập kết quả duyệt giá.') : null,
    khach ? h('p', { class: 'goi-y' }, 'Khách ngoài bảo hiểm không qua bước duyệt giá: lưu báo giá là duyệt luôn, lập lệnh sửa chữa được ngay.')
      : hs.trang_thai === 'bao_gia' ? h('p', { class: 'goi-y' }, 'Xe bảo hiểm: quá 3 ngày chưa duyệt thì báo giám đốc làm việc với bảo hiểm.') : null);
}

// Tổng giá đã duyệt (có VAT) và phần các dòng khách tự trả – dùng cho chia công nợ (020 / 036)
function tongDuyet(hm) {
  let tong = 0; let khachDong = 0;
  for (const m of hm.filter((x) => ['duyet', 'dang_lam', 'xong'].includes(x.trang_thai))) {
    const t = m.nguoi_tra === 'khach' ? sauVatDong(m, m.gia_duyet) : sauVat(m.gia_duyet, m.ty_le_vat ?? 0.08);
    tong += t; if (m.nguoi_tra === 'khach') khachDong += t;
  }
  return { tong, khachDong };
}

// 036: sửa cách chia công nợ bảo hiểm / khách sau khi đã duyệt (khấu trừ – giảm trừ của hãng)
function moChiaCongNo(hs, hm, ve) {
  const { tong, khachDong } = tongDuyet(hm);
  const oKhach = oTien('khach_tra', Math.min(tong, khachDong + Number(hs.khau_tru_giam_tru || 0)), { 'aria-label': 'Khách hàng chi trả' });
  const soBH = h('b', { 'data-bh-tra': '' });
  const tinhLai = () => { soBH.textContent = `${tien(tong - Math.min(tong, docTien(oKhach.value) || 0))} đ`; };
  oKhach.addEventListener('input', tinhLai); tinhLai();
  const noiDung = h('div', { class: 'chia-cong-no' },
    h('div', { class: 'dong-tien' }, h('span', null, 'Tổng giá duyệt (có VAT)'), h('b', null, `${tien(tong)} đ`)),
    h('div', { class: 'dong-tien dam' }, h('span', null, 'Bảo hiểm chi trả'), soBH),
    truong('Khách hàng chi trả', oKhach, h('span', null, 'Khấu trừ, miễn thường, giảm trừ, chế tài của hãng + các dòng khách tự trả',
      khachDong ? ` (gồm ${tien(khachDong)} đ các dòng khách tự trả)` : ''), { batBuoc: true }),
    h('p', { class: 'goi-y' }, 'Công nợ tách lại ngay: nợ của hãng bảo hiểm và nợ của chủ xe. Phiếu thu đã lập không đổi.'));
  moModal('Chia công nợ bảo hiểm / khách', noiDung, {
    nhanNut: 'Lưu',
    nutChinh: async () => {
      const kq = await api.suaChiaCongNo(hs.id, docTien(oKhach.value) || 0);
      toast(`Đã chia lại: bảo hiểm chi trả ${tien(kq.bao_hiem)} đ, khách chi trả ${tien(kq.khach)} đ.`); await ve();
    },
  });
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
  const chonVat = oChon('vat', VAT_BAO_GIA.map((r) => ({ value: String(r), label: phanTram(r) })),
    String(VAT_BAO_GIA.find((r) => Math.abs(r - Number(vatCu)) < 1e-6) ?? 0.08), { trong: null, 'aria-label': 'VAT' });
  const tyLe = () => Number(chonVat.value);
  const danhSach = h('div', { class: 'ds-dong-nhap' });
  const tong = h('dl', { class: 'tong-bao-gia', 'aria-live': 'polite' });

  // Khối 1 – Tổng giá sửa chữa: giá thay thế (phụ tùng), giá đồng sơn (đồng + sơn), giá detailing; tổng đã gồm VAT
  function capNhatTong() {
    const dongs = [...danhSach.children].map((d) => ({ nhom: d.querySelector('[name=nhom]').value, gia: docTien(d.querySelector('[name=gia_bao]').value) || 0 }));
    const cong = (ds) => dongs.filter((d) => ds.includes(d.nhom)).reduce((a, d) => a + d.gia, 0);
    const sau = dongs.reduce((a, d) => a + sauVat(d.gia, tyLe()), 0);
    dat(tong,
      h('dt', null, 'Giá thay thế'), h('dd', null, tien(cong(['phu_tung'])) || '0'),
      h('dt', null, 'Giá đồng sơn'), h('dd', null, tien(cong(['dong', 'son'])) || '0'),
      h('dt', null, 'Giá Detailing'), h('dd', null, tien(cong(['detailing'])) || '0'),
      h('dt', { class: 'tong-chinh' }, 'Tổng giá sửa chữa', h('small', null, `(đã gồm VAT ${phanTram(tyLe())})`)),
      h('dd', { class: 'tong-chinh' }, h('b', null, tien(sau) || '0')));
  }
  chonVat.addEventListener('change', capNhatTong);

  // Khối 2 – từng dòng: Nhóm, Nội dung sửa chữa, Đơn giá (chưa VAT)
  const themDong = () => {
    const oGia = oTien('gia_bao', null);
    const chonNhom = oChon('nhom', NHOM_CHON.map((value) => ({ value, label: NHOM[value] })), 'dong', { trong: null });
    const dong = h('div', { class: 'dong-nhap dong-bao-gia' },
      truong('Nhóm', chonNhom),
      truong('Nội dung sửa chữa', oChu('ten', '', { placeholder: 'Ví dụ: Gò cửa trước trái' }), null, { batBuoc: true }),
      truong('Đơn giá (chưa VAT)', oGia, null, { batBuoc: true }),
      h('button', { class: 'nut-chu', type: 'button', onclick: () => { dong.remove(); capNhatTong(); }, 'aria-label': 'Bỏ dòng này' }, 'Bỏ dòng'));
    oGia.addEventListener('input', capNhatTong);
    chonNhom.addEventListener('change', capNhatTong);
    danhSach.append(dong);
    dong.querySelector('[name=ten]').focus();
    capNhatTong();
  };
  themDong();

  const chiXem = (nhan, giaTri) => h('div', { class: 'truong' }, h('span', { class: 'truong-nhan' }, nhan), h('div', { class: 'o-chi-xem' }, giaTri));
  const noiDung = h('div', null,
    boSung ? h('p', { class: 'thong-bao canh-bao' }, khach ? 'Báo giá bổ sung cho phần phát sinh.' : 'Báo giá bổ sung: phần phát sinh chỉ được làm sau khi duyệt xong.') : null,
    h('div', { class: 'khoi-bao-gia' },
      h('div', { class: 'luoi-o dau-bao-gia' },
        khach ? chiXem('Nguồn', 'Khách ngoài bảo hiểm – không qua duyệt giá') : chiXem('Hãng bảo hiểm', hs.hang_bh || '—'),
        truong('VAT', chonVat)),
      tong),
    danhSach, nut('+ Thêm dòng', themDong));
  // Báo giá gốc: chọn người làm bước tiếp theo (xe BH: nhập kết quả duyệt; khách: lập lệnh sửa chữa)
  const giao = boSung ? null : khach ? khungGiaoViec('Lập lệnh sửa chữa', VAI_TRO_BUOC.lenh) : khungGiaoViec('Nhập kết quả duyệt giá', VAI_TRO_BUOC.duyet_gia);
  if (giao) noiDung.append(giao.el);
  moModal(boSung ? 'Báo giá bổ sung' : 'Lập báo giá', noiDung, {
    rong: true, nhanNut: 'Lưu báo giá',
    nutChinh: async () => {
      const dong = [...danhSach.children].map((d) => ({
        ten: d.querySelector('[name=ten]').value.trim(), nhom: d.querySelector('[name=nhom]').value,
        gia_bao: docTien(d.querySelector('[name=gia_bao]').value),
      })).filter((d) => d.ten || d.gia_bao);
      if (!dong.length) { toast('Nhập ít nhất một dòng.', 'loi'); return false; }
      await api.lapBaoGia(hs.id, dong, tyLe());
      if (giao) await giaoSauKhiLuu(hs.id, giao.nguoi());
      toast(khach ? 'Đã lưu báo giá – đã duyệt, lập lệnh sửa chữa được ngay.' : 'Đã lưu báo giá.'); await ve();
    },
  });
}

function moDuyetGia(hs, choDuyet, ve, hm = []) {
  const bh = hs.nguon_tt !== 'khach';
  const oNgayDuyet = oNgay('ngay', homNay(), { max: homNay() });
  const dongs = choDuyet.map((m) => {
    const dongY = h('input', { type: 'checkbox', checked: true, 'aria-label': `Duyệt ${m.ten}` });
    const gia = oTien('gia', m.gia_bao, { 'aria-label': `Giá duyệt ${m.ten}` });
    dongY.addEventListener('change', () => { gia.disabled = !dongY.checked; tinhLai(); });
    gia.addEventListener('input', tinhLai);
    return { m, dongY, gia, el: h('tr', null, h('td', null, h('label', null, dongY, ' ', m.ten, bh && m.nguoi_tra === 'khach' ? h('small', { class: 'nhan' }, 'khách trả') : null)), h('td', { class: 'so' }, tien(m.gia_bao)), h('td', null, gia)) };
  });
  // Chia công nợ (xe bảo hiểm): Tổng giá duyệt = BH chi trả + Khách chi trả. Khách chi trả = dòng khách tự trả + khấu trừ / giảm trừ
  const daDuyet = hm.filter((m) => ['duyet', 'dang_lam', 'xong'].includes(m.trang_thai) && !choDuyet.some((c) => c.id === m.id));
  const tienDong = (m, gia) => (m.nguoi_tra === 'khach' ? sauVatDong(m, gia) : sauVat(gia, m.ty_le_vat ?? 0.08));
  const oKhach = oTien('khach_tra', 0, { 'aria-label': 'Khách hàng chi trả' });
  const soTong = h('b', { 'data-tong-duyet': '' }); const soBH = h('b', { 'data-bh-tra': '' }); const soKhachDong = h('small');
  let tuSua = false; let khachDongTruoc = null;
  function tongHop() {
    let tong = 0; let khachDong = 0;
    for (const m of daDuyet) { const t = tienDong(m, m.gia_duyet); tong += t; if (m.nguoi_tra === 'khach') khachDong += t; }
    for (const d of dongs) { if (!d.dongY.checked) continue; const t = tienDong(d.m, docTien(d.gia.value) || 0); tong += t; if (d.m.nguoi_tra === 'khach') khachDong += t; }
    return { tong, khachDong };
  }
  function tinhLai() {
    if (!bh) return;
    const { tong, khachDong } = tongHop();
    if (!tuSua || khachDongTruoc !== khachDong) {
      // chưa tự sửa: khách trả = dòng khách + khấu trừ đã ghi; đã sửa mà dòng khách đổi: giữ phần khấu trừ
      const khauTru = tuSua ? Math.max(0, (docTien(oKhach.value) || 0) - khachDongTruoc) : Number(hs.khau_tru_giam_tru || 0);
      oKhach.value = tien(Math.min(tong, khachDong + khauTru));
      khachDongTruoc = khachDong;
    }
    const khach = Math.min(tong, docTien(oKhach.value) || 0);
    soTong.textContent = `${tien(tong)} đ`;
    soBH.textContent = `${tien(tong - khach)} đ`;
    soKhachDong.textContent = khachDong ? ` (gồm ${tien(khachDong)} đ các dòng khách tự trả)` : '';
  }
  oKhach.addEventListener('input', () => { tuSua = true; tinhLai(); });
  const khoiChia = bh ? h('div', { class: 'chia-cong-no' },
    h('h3', null, 'Chia công nợ'),
    h('div', { class: 'dong-tien' }, h('span', null, 'Tổng giá duyệt (có VAT)'), soTong),
    h('div', { class: 'dong-tien dam' }, h('span', null, 'Bảo hiểm chi trả'), soBH),
    truong('Khách hàng chi trả', oKhach, h('span', null, 'Khấu trừ, miễn thường, giảm trừ, chế tài của hãng + các dòng khách tự trả', soKhachDong)),
  ) : null;
  const noiDung = h('div', null,
    truong('Ngày duyệt', oNgayDuyet, 'Doanh thu tính vào tháng của ngày duyệt', { batBuoc: true }),
    h('div', { class: 'bang-cuon' }, h('table', { class: 'bang' },
      h('thead', null, h('tr', null, h('th', null, 'Hạng mục (bỏ chọn nếu không duyệt)'), h('th', { class: 'so' }, 'Giá báo'), h('th', null, 'Giá duyệt (chưa VAT)'))),
      h('tbody', null, dongs.map((d) => d.el)))),
    khoiChia,
    bh ? h('p', { class: 'goi-y' }, 'Nhớ chụp biên bản giám định, bản duyệt giá, HĐ 3 bên vào mục Ảnh & giấy tờ.') : null);
  tinhLai();
  const giao = hs.trang_thai === 'bao_gia' ? khungGiaoViec('Lập lệnh sửa chữa', VAI_TRO_BUOC.lenh) : null;
  if (giao) noiDung.append(giao.el);
  moModal('Kết quả duyệt giá', noiDung, {
    rong: true, nhanNut: 'Lưu kết quả',
    nutChinh: async () => {
      const ketQua = dongs.map((d) => ({ id: d.m.id, dong_y: d.dongY.checked, gia_duyet: d.dongY.checked ? docTien(d.gia.value) : null }));
      const kq = await api.duyetGiaChia(hs.id, oNgayDuyet.value, ketQua, bh ? (docTien(oKhach.value) || 0) : null);
      if (giao) await giaoSauKhiLuu(hs.id, giao.nguoi());
      toast(bh && kq ? `Đã lưu. Bảo hiểm chi trả ${tien(kq.bao_hiem)} đ, khách chi trả ${tien(kq.khach)} đ.` : 'Đã lưu kết quả duyệt.'); await ve();
    },
  });
}

// ---------- Lệnh sửa chữa, sửa chữa (bước 4–6) ----------
function theSuaChua({ hs, hm, ps, ve, cho }) {
  if (!['da_duyet', 'dang_sua', 'cho_kcs', 'dat_kcs'].includes(hs.trang_thai) && !hm.some((m) => m.to_id)) return null;
  // Cấp phụ tùng, vật tư (kho): tải sau, chèn vào cuối thẻ (dùng lại "chờ phụ tùng" đã đọc ở đầu trang)
  const khoiPT = h('div');
  khoiPhuTungXe(hs, ve, cho).then((k) => { if (k) dat(khoiPT, k); }).catch((e) => console.warn(e));
  const chuaGiao = hm.filter((m) => m.trang_thai === 'duyet');
  const dangLam = hm.filter((m) => ['dang_lam', 'xong'].includes(m.trang_thai));
  const duocLap = q('cvdv', 'quan_ly', 'giam_doc');
  const psMo = ps.filter((p) => !p.da_xu_ly);
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '4–5. Lệnh sửa chữa, cấp phụ tùng và sửa chữa'),
      h('div', { class: 'hang-nut' },
        duocLap && chuaGiao.length && ['da_duyet', 'dang_sua'].includes(hs.trang_thai)
          ? nut(hs.trang_thai === 'da_duyet' ? 'Lập lệnh sửa chữa' : `Giao thêm cho tổ (${chuaGiao.length})`, () => moLenh(hs, chuaGiao, ve), true) : null,
        ['dang_sua', 'cho_kcs'].includes(hs.trang_thai) ? nut('Báo phát sinh', () => moPhatSinh(hs, ve)) : null)),
    psMo.length ? h('div', { class: 'thong-bao canh-bao' }, h('b', null, 'Phát sinh chờ báo giá bổ sung: '),
      psMo.map((p) => h('div', null, `${ngayGio(p.luc)} – ${p.mo_ta}`))) : null,
    !dangLam.length ? h('p', { class: 'trong' }, 'Chưa giao việc cho tổ nào. Chưa có lệnh sửa chữa thì chưa làm, chưa cấp phụ tùng.') :
      bang([
        { nhan: 'Hạng mục', khoa: 'ten' },
        { nhan: 'Tổ', lay: (m) => api.dm.ten('to_thuc_hien', m.to_id) },
        { nhan: 'Người làm', lay: (m) => chipNguoi(m.nguoi_lam, { vai: 'truong_nhom' }) || '' },
        { nhan: 'Trạng thái', lay: (m) => m.trang_thai === 'xong' ? `Xong ${ngayGio(m.xong_luc)}` :
          duocLap ? h('button', { class: 'nut nho', type: 'button', onclick: () => chay(() => api.baoXong(m.id), { thanhCong: 'Đã báo xong.' }).then(ve, ve.lai) }, 'Báo xong') : 'Đang làm' },
      ], dangLam),
    khoiPT);
}

function moLenh(hs, ds, ve) {
  // Chưa có giờ hẹn: mặc định sau N ngày (cài đặt so_ngay_hen_giao, 3) lúc 17:00; người lập lệnh sửa lại nếu khác
  const henMacDinh = () => { const d = new Date(); d.setDate(d.getDate() + api.caiDat('so_ngay_hen_giao', 3)); d.setHours(17, 0, 0, 0); return d; };
  const oHenKhung = oNgayGioVN('hen_giao', hs.hen_giao || henMacDinh(), { batBuoc: !hs.hen_giao });
  const oHen = oHenKhung.querySelector('input[name=hen_giao]');
  const dongs = ds.map((m) => {
    const to = oChon('to', api.dm.to_thuc_hien.map((t) => ({ value: t.id, label: t.ten })),
      { dong: 'DS', son: 'DS', dong_son: 'DS', phu_tung: 'DS', dmg: 'DMG', detailing: 'DT' }[m.nhom], { trong: null, 'aria-label': `Tổ làm ${m.ten}` });
    // Người làm điền sẵn tên trưởng nhóm của tổ đang chọn; sửa được, đổi tổ thì điền lại (nếu chưa tự gõ)
    const truongNhom = (toId) => (api.dm.nhan_vien || []).find((n) => n.hoat_dong && n.vai_tro.includes('truong_nhom') && n.to_id === toId)?.ho_ten || '';
    const nguoi = oChu('nguoi', truongNhom(to.value), { placeholder: 'Người làm', 'aria-label': `Người làm ${m.ten}` });
    let tuGo = false;
    nguoi.addEventListener('input', () => { tuGo = !!nguoi.value; });
    to.addEventListener('change', () => { if (!tuGo) nguoi.value = truongNhom(to.value); });
    return { m, to, nguoi, el: h('tr', null, h('td', null, m.ten), h('td', null, to), h('td', null, nguoi)) };
  });
  moModal('Lệnh sửa chữa', h('div', null,
    truong('Giờ hẹn giao xe', oHenKhung, hs.hen_giao ? 'Ngày dd/mm/yyyy · giờ 24h' : `Mặc định sau ${api.caiDat('so_ngay_hen_giao', 3)} ngày, 17:00 – sửa lại nếu khác`, { batBuoc: !hs.hen_giao }),
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
      // Ảnh tải song song; ảnh lỗi không làm hộp mở lại (bấm Gửi lần nữa sẽ báo phát sinh trùng)
      const kq = await api.taiNhieu(form.anh.files, 'phat_sinh', (f) => api.taiTep(hs, 'phat_sinh', f));
      toast(kq.loi.length ? `Đã báo phát sinh, nhưng ${kq.loi.length}/${kq.tong} ảnh tải lên lỗi – tải lại ở mục "Ảnh & giấy tờ".` : 'Đã báo phát sinh.',
        kq.loi.length ? 'loi' : 'ok');
      await ve();
    },
  });
}

// ---------- KCS (bước 7) ----------
function theKcs({ hs, hm, tep, dsKcs, ve }) {
  if (!['cho_kcs', 'dat_kcs', 'da_giao', 'da_gui_hs', 'dong'].includes(hs.trang_thai) && !dsKcs.length) return null;
  const coAnh = tep.some((t) => t.buoc === 'kcs');
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '6. Nghiệm thu (KCS) và rửa xe'),
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
// Các ô ghi lúc giao xe: số hóa đơn, cảm nhận khách (dùng ở thẻ và ở hộp "Thu tiền & giao xe")
function cacOGiaoXe(hs) {
  const bh = hs.nguon_tt !== 'khach';
  return [
    bh ? truong('Số hóa đơn phần bảo hiểm', oChu('so_hd_bao_hiem', hs.so_hd_bao_hiem)) : null,
    truong('Số hóa đơn phần khách (nếu có)', oChu('so_hd_khach', hs.so_hd_khach)),
    q('quan_ly', 'giam_doc') ? truong('Cảm nhận của khách khi nhận xe', oVung('cam_nhan_khach', hs.cam_nhan_khach), 'Quản lý chung ghi', { rong: true }) : null,
  ];
}

function theGiaoXe({ hs, hm, ve }) {
  if (hs.trang_thai !== 'dat_kcs' && !hs.giao_luc) return null;
  if (hs.giao_luc) {
    return h('section', { class: 'the' }, h('h2', null, '7. Thanh toán và giao xe'),
      h('p', null, 'Đã giao lúc ', h('b', null, ngayGio(hs.giao_luc)), hs.cho_giao_no_boi ? ' (được duyệt giao khi khách còn nợ)' : ''),
      hs.cam_nhan_khach ? h('p', null, 'Cảm nhận của khách: ', hs.cam_nhan_khach) : null,
      h('p', { class: 'mo-ta' }, `Số HĐ bảo hiểm: ${hs.so_hd_bao_hiem || '—'} · Số HĐ khách: ${hs.so_hd_khach || '—'}`));
  }
  const bh = hs.nguon_tt !== 'khach';
  const keToan = q('ke_toan', 'giam_doc');
  const noKhach = Number(hs.con_no_khach) || 0;
  const form = h('form', { class: 'luoi-o' }, keToan ? null : cacOGiaoXe(hs));
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '7. Thanh toán và giao xe')),
    h('div', { class: 'luoi-dem tien' },
      bh ? h('div', { class: 'o-dem' }, h('b', null, tien(hs.con_no_bh)), h('span', null, 'Bảo hiểm chi trả – còn nợ (đ)')) : null,
      h('div', { class: `o-dem ${noKhach > 0 ? 'canh-bao' : ''}`, 'data-no-khach': '' }, h('b', null, tien(hs.con_no_khach)), h('span', null, 'Khách hàng chi trả – còn nợ (đ)'))),
    // 036: khấu trừ – giảm trừ đã chia ở Kết quả duyệt giá; ở đây chỉ xem, sửa thì mở "Chia công nợ"
    bh ? h('p', { class: 'mo-ta', 'data-khau-tru': '' }, `Khấu trừ – giảm trừ (khách trả): ${tien(hs.khau_tru_giam_tru) || '0'} đ – đã chia ở Kết quả duyệt giá. `,
      q('cvdv', 'ke_toan', 'quan_ly', 'giam_doc') ? h('button', { class: 'nut-chu', type: 'button', onclick: () => moChiaCongNo(hs, hm, ve) }, 'Chia lại công nợ') : null) : null,
    h('p', { class: 'goi-y' }, keToan
      ? 'Bấm "Thu tiền & giao xe": phiếu thu phần khách còn nợ và giao xe làm một lần. Thu ít hơn số nợ thì cần giám đốc hoặc quản lý chung duyệt giao khi còn nợ.'
      : 'Kế toán thu tiền phần khách rồi giao xe. Khách còn nợ thì cần giám đốc hoặc quản lý chung duyệt.'),
    form,
    h('div', { class: 'hang-nut' },
      q('quan_ly', 'giam_doc') ? nut('Duyệt giảm giá cho khách', () => moGiamGia(hs, ve)) : null,
      q('quan_ly', 'giam_doc') && !hs.cho_giao_no_boi && !keToan ? nut('Duyệt giao khi khách còn nợ', () =>
        chay(() => api.duyetGiaoConNo(hs.id), { thanhCong: 'Đã duyệt giao xe khi còn nợ.' }).then(ve, ve.lai)) : null,
      keToan ? nut(noKhach > 0 ? 'Thu tiền & giao xe' : 'Giao xe', () => moThuTienGiaoXe(hs, ve), true)
        : q('cvdv', 'quan_ly') ? nut('Giao xe', async () => {
          const d = docForm(form);
          await chay(() => api.giaoXe(hs.id, d), { thanhCong: 'Đã giao xe.' }).then(ve, ve.lai);
        }, true) : null));
}

// 036: kế toán thu tiền phần khách còn nợ và giao xe trong một hộp thoại (một giao dịch trên máy chủ)
function moThuTienGiaoXe(hs, ve) {
  const noKhach = Math.max(0, Number(hs.con_no_khach) || 0);
  const dsTk = (api.dm.tai_khoan_quy || []).filter((t) => t.hoat_dong && t.chi_nhanh_id === api.toi.chi_nhanh_id);
  const oSoTien = oTien('so_tien', noKhach || null);
  const chonTk = oChon('tai_khoan_id', dsTk.map((t) => ({ value: t.id, label: t.ten })), (dsTk.find((t) => t.mac_dinh) || dsTk[0])?.id, { trong: null });
  const tichDuyet = q('quan_ly', 'giam_doc') && !hs.cho_giao_no_boi ? oCheck('duyet_con_no', false, 'Duyệt giao xe khi khách còn nợ (giám đốc / quản lý chung)') : null;
  const nhacNo = h('small', { class: 'goi-y' });
  const capNhatNhac = () => {
    const thu = docTien(oSoTien.value) || 0;
    nhacNo.textContent = thu > noKhach ? `Nhiều hơn số nợ ${tien(noKhach)} đ – phần dư (tiền bo, trả dư) lập ở Thu chi → Phiếu thu.`
      : thu < noKhach ? `Còn nợ ${tien(noKhach - thu)} đ sau khi thu – cần duyệt giao khi còn nợ.` : 'Thu đủ số khách còn nợ.';
  };
  oSoTien.addEventListener('input', capNhatNhac); capNhatNhac();
  const form = h('form', { class: 'luoi-o', novalidate: true },
    noKhach > 0 ? [
      h('div', { class: 'truong rong' }, h('span', { class: 'truong-nhan' }, 'Khách còn nợ'), h('div', { class: 'o-chi-xem' }, h('b', { 'data-no-khach': '' }, `${tien(noKhach)} đ`))),
      truong('Khách trả', oSoTien, nhacNo, { batBuoc: true }),
      truong('Tài khoản nhận', chonTk),
      truong('Nội dung phiếu thu', oChu('noi_dung', `Khách trả sửa xe ${hs.bien_so_hien_thi || hs.ma} – ${hs.ten_khach}`), null, { rong: true }),
      tichDuyet ? h('div', { class: 'truong rong' }, tichDuyet) : null,
      hs.cho_giao_no_boi ? h('p', { class: 'goi-y rong' }, 'Đã được duyệt giao xe khi khách còn nợ.') : null,
    ] : h('p', { class: 'goi-y rong' }, 'Khách không còn nợ – chỉ ghi số hóa đơn và giao xe.'),
    cacOGiaoXe(hs));
  moModal(noKhach > 0 ? 'Thu tiền & giao xe' : 'Giao xe', form, {
    rong: true, nhanNut: noKhach > 0 ? 'Thu tiền & giao xe' : 'Giao xe',
    nutChinh: async () => {
      const d = docForm(form);
      const p = { so_tien: noKhach > 0 ? (d.so_tien ?? 0) : 0, tai_khoan_id: d.tai_khoan_id, noi_dung: d.noi_dung, duyet_con_no: !!d.duyet_con_no,
        so_hd_bao_hiem: d.so_hd_bao_hiem, so_hd_khach: d.so_hd_khach, cam_nhan_khach: d.cam_nhan_khach };
      const kq = await api.thuTienGiaoXe(hs.id, p);
      toast(Number(kq?.da_thu) > 0 ? `Đã thu ${tien(kq.da_thu)} đ và giao xe.` : 'Đã giao xe.');
      await ve();
    },
  });
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
    h('h2', null, '8. Hồ sơ bảo hiểm, thu nợ, hoa hồng'),
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
    h('div', { class: 'the-dau' }, h('h2', null, '9. Chăm sóc sau giao'),
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
function theTien({ hs, hm, giaVon, ve }) {
  const d = (nhan, gt, dam) => h('div', { class: `dong-tien ${dam ? 'dam' : ''}` }, h('span', null, nhan), h('b', null, tien(gt) || '0'));
  const bh = hs.nguon_tt !== 'khach';
  if (hs.loai === 'bao_hanh' && !['tiep_nhan', 'bao_gia'].includes(hs.trang_thai)) {
    return h('section', { class: 'the' }, h('h2', null, 'Tiền'),
      h('p', { class: 'goi-y' }, 'Hồ sơ bảo hành: làm lại miễn phí, không thu tiền, không tính doanh thu.'),
      api.duocXem('giam_doc', 'quan_ly', 'ke_toan') && giaVon ? d('Phụ tùng, vật tư đã xuất (giá vốn bảo hành)', giaVon, true) : null);
  }
  // 036: chia lại công nợ BH / khách sau duyệt (khấu trừ – giảm trừ) – CVDV, kế toán, quản lý chung, giám đốc
  const nutChia = bh && !['tiep_nhan', 'bao_gia', 'dong', 'huy'].includes(hs.trang_thai) && Number(hs.bh_duyet) + Number(hs.khach_duyet) > 0 && q('cvdv', 'ke_toan', 'quan_ly', 'giam_doc')
    ? h('button', { class: 'nut nho', type: 'button', onclick: () => moChiaCongNo(hs, hm, ve) }, 'Chia lại công nợ BH / khách') : null;
  return h('section', { class: 'the' }, h('h2', null, 'Tiền'),
    bh ? [d('Bảo hiểm duyệt (có VAT)', hs.bh_duyet), Number(hs.khau_tru_giam_tru) ? d('− Khấu trừ – giảm trừ', hs.khau_tru_giam_tru) : null,
      d('Bảo hiểm phải trả', hs.phai_thu_bh), d('Bảo hiểm đã trả', hs.da_thu_bh), d('Bảo hiểm còn nợ', hs.con_no_bh, true), h('hr')] : null,
    d('Khách làm thêm / sửa lẻ', hs.khach_duyet),
    bh && Number(hs.khau_tru_giam_tru) ? d('+ Khấu trừ – giảm trừ', hs.khau_tru_giam_tru) : null,
    Number(hs.giam_gia) ? d('− Giảm giá đã duyệt', hs.giam_gia) : null,
    d('Khách phải trả', hs.phai_thu_khach), d('Khách đã trả (gồm cọc)', hs.da_thu_khach),
    Number(hs.con_no_khach) < 0 ? d(hs.giao_luc ? 'Khách trả dư – cần trả lại' : 'Khách đã cọc / ứng trước', -Number(hs.con_no_khach), true) : d('Khách còn nợ', hs.con_no_khach, true),
    Number(hs.con_no_khach) < 0 ? h('p', { class: 'goi-y' }, hs.giao_luc
      ? 'Hồ sơ chưa đóng khi còn tiền dư. Trả lại khách: lập Đề nghị chi, mục "Trả lại cọc cho khách", chọn xe này. Khách cho thợ: kế toán lập phiếu thu "Tiền bo của khách" rồi hủy phần dư ở phiếu đã thu.'
      : 'Tiền cọc sẽ trừ vào phần khách trả khi giao xe.') : null,
    // Giá vốn phụ tùng, vật tư đã xuất cho xe và lãi gộp (doanh thu sau VAT − giá vốn)
    api.duocXem('giam_doc', 'quan_ly', 'ke_toan') && (giaVon || Number(hs.bh_duyet) || Number(hs.khach_duyet)) ? [h('hr'),
      d('Phụ tùng, vật tư đã xuất (giá vốn)', giaVon),
      d('Lãi gộp', Number(hs.bh_duyet) + Number(hs.khach_duyet) - Number(hs.giam_gia || 0) - giaVon, true)] : null,
    q('ke_toan', 'giam_doc') && !['dong', 'huy'].includes(hs.trang_thai) || nutChia
      ? h('div', { class: 'hang-nut' },
        q('ke_toan', 'giam_doc') && !['dong', 'huy'].includes(hs.trang_thai) ? h('a', { class: 'nut nho', href: `#/thu-chi?ho_so=${hs.id}` }, 'Lập phiếu thu cho xe này') : null,
        nutChia) : null);
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
  const dangTai = h('small', { class: 'goi-y', role: 'status', 'aria-live': 'polite' });
  oTep.addEventListener('change', async () => {
    const ds = [...oTep.files]; const buoc = chonBuoc.value;
    if (!ds.length) return;
    oTep.disabled = true; chonBuoc.disabled = true; dangTai.textContent = `Đang tải 0/${ds.length}…`;
    const kq = await api.taiNhieu(ds, buoc, (f, goc) => api.taiTep(hs, buoc, f, goc.type === 'application/pdf' ? 'bien_ban' : 'anh'),
      { tienDo: (n, t) => { dangTai.textContent = `Đang tải ${n}/${t}…`; } });
    oTep.value = ''; oTep.disabled = false; chonBuoc.disabled = false; dangTai.textContent = '';
    for (const x of kq.loi) toast(`Không tải được ${x.ten}: ${x.e?.message || x.e}`, 'loi');
    if (kq.xong) { toast(`Đã tải ${kq.xong} tệp.`); ve(); }
  });
  return h('section', { class: 'the' }, h('h2', null, `Ảnh & giấy tờ (${tep.length})`),
    !api.laCoDong() && (!['dong', 'huy'].includes(hs.trang_thai) || q('ke_toan', 'giam_doc'))
      ? h('div', { class: 'tai-tep' }, chonBuoc, h('label', { class: 'nut' }, 'Chụp / chọn tệp', oTep), dangTai) : null,
    tep.length ? luoi : h('p', { class: 'trong' }, 'Chưa có ảnh.'));
}

function theNhatKy({ nk }) {
  const ten = (id) => (api.dm.nhan_vien || []).find((n) => n.id === id)?.ho_ten || '';
  return h('details', { class: 'the' }, h('summary', null, h('h2', null, `Nhật ký (${nk.length})`)),
    h('ul', { class: 'nhat-ky' }, nk.map((n) => h('li', null, h('small', null, ngayGio(n.luc), ' · ', ten(n.boi)), h('div', null, n.ghi_chu || TRANG_THAI[n.sang_trang_thai])))));
}

function moHuy(hs) {
  hoiLyDo('Hủy hồ sơ', async (lyDo) => { await api.huyHoSo(hs.id, lyDo); toast('Đã hủy hồ sơ.'); veDanhSachHoSo(hs); },
    { nhan: 'Lý do hủy', goiY: 'Ví dụ: khách không sửa, bảo hiểm từ chối. Nếu đã thu cọc, lập đề nghị chi "Trả lại cọc cho khách".', nhanNut: 'Hủy hồ sơ' });
}
