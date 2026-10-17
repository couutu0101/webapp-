// Chi tiết hồ sơ xe: 10 bước trên một trang, mỗi bước chỉ hiện nút cho đúng người
import {
  h, oChonTep, bienSo, oNgayVN, oNgayGioVN, vnSangIso, tien, ngay, ngayGio, homNay, truong, oChu, oTien, oChon, oVung, oCheck, docForm, docTien, chay, moModal, toast, nhanTrangThai, bang, NHOM, NHOM_CHON, NGUON, TRANG_THAI, xacNhan, dat, veDanhSachHoSo, icon, buocXe, BUOC_XE, chipNguoi, hoiLyDo, coBuocHoSoBH, vaiChinh,
} from '../ui.js';
import { khoiPhuTungXe } from './kho.js';
import { khungGiaoViec, giaoSauKhiLuu, dongDangCho, nguoiLamTungBuoc, tenGoi, VAI_TRO_BUOC, aiDangLam, chipNhanVien } from './giao-viec.js';
import { hanHoSo, chuHan } from '../han-viec.js';
import { gioBao, tachTieuDe, TEN_LOAI } from '../thong-bao.js';
import * as api from '../api.js';
import { ghiTiep, tuGhiNgayKhiBam, nhacHetHan, layLichSu, khoiLichSu } from './lich-su-xe.js';
import { khungChonBaoHiem } from '../chon-bao-hiem.js';
import { duocDetailing, detailingDat, moDetailingTraVe } from '../detailing.js';
import { khungAnhNhanXe, anhNhanXeThieu, coFileBaoGiaMoi, coFileDuyetMoi, soAnhKcs, SO_ANH_KCS, NHAN_BUOC_MOI, NHAN_GIAY_TO_XE, ANH_NHAN_XE, taiVaoBuoc, oDinhKem, buocTepMo, duocMoKhoa, hoiLyDoMoKhoa } from '../anh-bat-buoc.js';

const TT_DONG = { cho_duyet: 'Chờ duyệt', duyet: 'Đã duyệt', tu_choi: 'Không duyệt', dang_lam: 'Đang làm', xong: 'Xong' };
const BUOC_TEP = { tiep_nhan: 'Nhận xe', ...NHAN_BUOC_MOI, duyet_gia: 'Giám định / duyệt giá / HĐ 3 bên', lenh_sua_chua: 'Lệnh sửa chữa', phat_sinh: 'Phát sinh', huy_vat_tu: 'Hủy vật tư (bảo hiểm)', kcs: 'Sau sửa (KCS)', giao_xe: 'Giao xe', ho_so_bh: 'Hồ sơ bảo hiểm', giay_to_xe: NHAN_GIAY_TO_XE, khac: 'Khác' };

export default async function trangChiTiet(el, idChu) {
  const id = Number(idChu);
  // Lưu xong bất kỳ thao tác nào: về danh sách Hồ sơ xe; lỗi thì vẽ lại trang để thấy dữ liệu mới nhất
  let hsDangXem = { id, ma: '' };
  // 17/10 (anh Thuận): mở hồ sơ chỉ hiện BƯỚC ĐANG LÀM (+ Thông tin xe và khách, Tiền); nút "Hiện tất cả công đoạn".
  // Mỗi lần mở hồ sơ đều gọn; trong lúc đang xem (lưu xong vẽ lại) thì giữ lựa chọn.
  let hienTatCa = !!window.__HIEN_TAT_CA;   // móc kiểm thử: bộ thử cũ mở hồ sơ là thấy đủ các thẻ
  const ve = () => veDanhSachHoSo(hsDangXem);
  const veLai = ve.lai = async () => {
    const [hs, hm, nk, tep, ps, dsKcs, dsDet, [viec], [gv], [cho], tb, dc] = await Promise.all([
      api.layHoSo(id), api.layHangMuc(id), api.layNhatKy(id), api.layTep(id), api.layPhatSinh(id), api.layKcs(id),
      api.layDetailing(id).catch(() => []),
      api.doc('v_viec_ho_so', (q) => q.eq('ho_so_id', id)).catch(() => []),
      api.doc('v_gia_von_ho_so', (q) => q.eq('ho_so_id', id)).catch(() => []),
      api.doc('v_cho_phu_tung', (q) => q.eq('ho_so_id', id)).catch(() => []),
      // 054: thông báo đã gửi về hồ sơ này (ai nhận lúc nào); máy chủ chưa có 054 hoặc không đủ quyền thì bỏ qua
      api.laNhanVien() ? api.thongBaoHoSo(id).catch(() => []) : [],
      // 056: đề nghị chỉnh công nợ theo thực thu của hồ sơ (CSDL chưa có 056 thì bỏ qua)
      api.xemNhuNhanVien() ? api.layDieuChinh(id).catch(() => []) : []]);
    if (!hs) { dat(el, h('p', { class: 'trong' }, 'Không tìm thấy hồ sơ, hoặc bạn không có quyền xem.')); return; }
    hsDangXem = hs;
    veTrang({ hs, hm, nk, tep, ps, dsKcs, dsDet, ve, viec, giaVon: Number(gv?.gia_von || 0), cho, tb: Array.isArray(tb) ? tb : [], dc: Array.isArray(dc) ? dc : [] });
  };
  // Vẽ trang từ dữ liệu đã tải (bấm "Hiện tất cả công đoạn" chỉ vẽ lại, không tải lại)
  const veTrang = (ctx) => {
    const hien = phanCuaBuoc(ctx);
    const chon = (ten, fn) => (hienTatCa || !hien || hien.has(ten) ? fn(ctx) : null);
    const trai = [['thong_tin', theThongTin], ['anh_nhan_xe', theAnhNhanXe], ['bao_gia', theBaoGia], ['sua_chua', theSuaChua],
      ['huy_vat_tu', theHuyVatTu], ['detailing', theDetailing], ['kcs', theKcs], ['giao_xe', theGiaoXe], ['ho_so_bh', theHoSoBH], ['cham_soc', theChamSoc]];
    const phai = [['tien', theTien], ['tep', theTep], ['thong_bao', theThongBao], ['nhat_ky', theNhatKy]];
    const nutHien = hien
      ? h('div', { class: 'hien-tat-ca' }, h('button', { class: 'nut noi-bat', type: 'button', 'data-hien-tat-ca': hienTatCa ? '1' : '0',
          'aria-expanded': String(hienTatCa), onclick: () => { hienTatCa = !hienTatCa; veTrang(ctx); } },
        hienTatCa ? 'Chỉ hiện bước đang làm' : 'Hiện tất cả công đoạn'))
      : null;
    dat(el, 
      dau(ctx), theTienDo(ctx, veLai), nutHien,
      h('div', { class: 'cot-doi' },
        h('div', null, trai.map(([ten, fn]) => chon(ten, fn))),
        h('div', null, phai.map(([ten, fn]) => chon(ten, fn)))));
  };
  await veLai();
}

const q = (...ds) => api.coVaiTro(...ds);

// Các phần hiện khi xem gọn, theo bước đang chờ (buocXe). null = hiện tất cả (hồ sơ hủy, đã xong cả 10 bước, chuyển từ Excel).
function phanCuaBuoc({ hs, hm, ps, tep }) {
  const { dang } = buocXe(hs);
  if (!dang) return null;
  const s = new Set(['thong_tin', 'tien']);
  const thieuAnh = hs.bat_buoc_anh && anhNhanXeThieu(tep).length > 0;
  if (dang <= 3) { s.add('bao_gia'); if (thieuAnh || dang === 1) s.add('anh_nhan_xe'); }
  else if (dang <= 5) {
    s.add('sua_chua');
    // đang sửa mà có phát sinh chờ xử lý / dòng chờ duyệt: cần thẻ báo giá (báo giá bổ sung, duyệt bổ sung)
    if (ps.some((p) => !p.da_xu_ly) || hm.some((m) => m.trang_thai === 'cho_duyet')) s.add('bao_gia');
    if (thieuAnh) s.add('anh_nhan_xe');
  } else if (dang === 6) s.add('detailing');
  else if (dang === 7) s.add('kcs');
  else if (dang === 8) { s.add('giao_xe'); s.add('tep'); }
  // Sau giao xe các việc chạy song song (036): gửi hồ sơ BH / thu nợ BH / hoa hồng GDV (kế toán) và chăm sóc (quản lý chung)
  else if (dang === 9) { s.add('ho_so_bh'); s.add('cham_soc'); s.add('tep'); }
  else if (dang === 10) { s.add('cham_soc'); s.add('ho_so_bh'); }
  // Ảnh hủy vật tư (xe bảo hiểm) chụp được từ lúc thay phụ tùng tới khi gửi hồ sơ BH → hiện suốt bước 4 – 9 (thẻ tự ẩn với xe khác)
  if (dang >= 4 && dang <= 9) s.add('huy_vat_tu');
  return s;
}
// kieu: true = nút chính của thẻ (vàng đặc); 'noi-bat' = nút quan trọng loại 2 (nền vàng nhạt, viền vàng đậm – "+ Thêm dòng", tải ảnh…)
const nut = (nhan, onclick, kieu = false) => h('button', { class: `nut ${kieu === true ? 'chinh' : kieu || ''}`.trim(), type: 'button', onclick }, nhan);

function dau({ hs, cho }) {
  return h('div', { class: 'tieu-de-trang' },
    h('div', null,
      h('p', { class: 'mo-ta' }, h('a', { href: '#/ho-so' }, '← Hồ sơ xe')),
      h('h1', { class: 'tieu-de-xe' }, bienSo(hs.bien_so_hien_thi, { lon: true }), nhanTrangThai(hs.trang_thai),
        cho ? h('span', { class: 'nhan tt-canh-bao' }, `Chờ phụ tùng ${cho.so_ngay} ngày`) : null),
      h('p', { class: 'mo-ta' }, [hs.ma, hs.xe, hs.mau].filter(Boolean).join(' · '),
        hs.loai === 'bao_hanh' ? [' ', h('span', { class: 'nhan tt-canh-bao' }, 'Bảo hành'),
          hs.ho_so_goc_id ? [' – làm lại miễn phí lỗi cũ của ', h('a', { href: `#/ho-so/${hs.ho_so_goc_id}` }, 'hồ sơ gốc')] : null] : null,
        hs.tu_excel ? h('span', { class: 'nhan' }, 'Chuyển từ Excel') : null,
        hs.huy_thoa_thuan ? [' ', h('span', { class: 'nhan tt-canh-bao', 'data-huy-thoa-thuan': '' }, 'Đã hủy – thu theo thỏa thuận'),
          hs.ly_do_huy ? h('small', null, ` Lý do: ${hs.ly_do_huy}`) : null] : null)),
    h('div', { class: 'hang-nut doc' },
      // 056: giám đốc hủy được ở MỌI bước (doanh thu theo giá thương lượng, vật tư chưa dùng trả kho);
      // CVDV / quản lý chung hủy như cũ khi xe chưa vào sửa
      q('giam_doc') && !api.laCoDong() && !['huy', 'dong'].includes(hs.trang_thai) && !hs.tu_excel
        ? h('button', { class: 'nut', type: 'button', 'data-huy-gd': '', onclick: () => moHuyGiamDoc(hs) }, 'Hủy hồ sơ')
        : ['tiep_nhan', 'bao_gia', 'da_duyet'].includes(hs.trang_thai) && q('cvdv', 'quan_ly', 'giam_doc')
          ? nut('Hủy hồ sơ', () => moHuy(hs)) : null,
      // Xe đã rời xưởng quay lại: tiếp nhận lần mới với mọi thông tin điền sẵn
      ['da_giao', 'da_gui_hs', 'dong'].includes(hs.trang_thai) && q('cvdv', 'quan_ly', 'giam_doc')
        ? h('a', { class: 'nut chinh', href: `#/ho-so/moi?tu_ho_so=${hs.id}` }, '+ Tiếp nhận xe') : null,
      // 043: xe đã giao (kể cả đang chờ bảo hiểm trả) quay lại vì lỗi cũ: tạo hồ sơ bảo hành được ngay, không phải chờ hồ sơ đóng
      ['da_giao', 'da_gui_hs', 'dong'].includes(hs.trang_thai) && q('cvdv', 'quan_ly', 'giam_doc')
        ? h('a', { class: 'nut', href: `#/ho-so/moi?bao_hanh=${hs.id}` }, 'Tạo hồ sơ bảo hành') : null));
}

// Thẻ tiến độ: dòng "Đang chờ" (bước, người được giao, hạn) + đường 10 bước, xe dừng ở bước đang chờ
const daChayTienDo = new Set();   // hiệu ứng xe chạy chỉ một lần cho mỗi hồ sơ + bước (vẽ lại sau thao tác thì thôi)
function theTienDo({ hs, hm, nk, viec }, veLai) {
  if (hs.trang_thai === 'huy') return h('p', { class: 'thong-bao canh-bao' }, 'Hồ sơ đã hủy: ', hs.ly_do_huy || '');
  const han = hanHoSo(hs, viec?.giao_viec_luc);
  const thongTinHan = { han, chuHan: han ? chuHan(han) : '' };
  return h('section', { class: 'the the-tien-do' },
    dongDangCho(hs, viec, hm, veLai, thongTinHan),
    tienDo(hs, nk, aiDangLam(hs, viec, hm)),
    nutDenBuoc(hs));
}

// Kịch bản thử 16/10: trên điện thoại phần làm bước đang chờ (vd KCS) nằm rất xa dưới (phải cuộn qua thông tin, ảnh,
// báo giá…) → nút nhảy thẳng tới thẻ của bước đó (thẻ có tiêu đề bắt đầu bằng số bước).
function nutDenBuoc(hs) {
  const { dang } = buocXe(hs);
  if (!dang) return null;
  const so = dang <= 3 ? '2' : dang <= 5 ? '4' : `${dang}.`;
  const den = () => {
    const the = [...document.querySelectorAll('#noi-dung section.the h2')].find((t) => t.textContent.trim().startsWith(so))?.closest('section');
    if (!the) { toast('Bước này không có phần thao tác trên trang.'); return; }
    the.scrollIntoView({ behavior: 'smooth', block: 'start' });
    the.classList.remove('nhay-sang'); void the.offsetWidth; the.classList.add('nhay-sang');
  };
  // 17/10 (anh Thuận): lối tắt quan trọng nhất của trang → nút vàng to, mũi tên nhún (CSS .den-buoc)
  return h('div', { class: 'den-buoc' },
    h('button', { class: 'nut chinh', type: 'button', 'data-den-buoc': so, onclick: den },
      `Đến phần làm bước ${dang}: ${BUOC_XE[dang - 1]} `, h('span', { class: 'mui-xuong', 'aria-hidden': 'true' }, '↓')));
}

function tienDo(hs, nk, aiDang) {
  const nguoi = nguoiLamTungBuoc(nk);
  const { dang, boQua, xong } = buocXe(hs);
  const soXong = BUOC_XE.filter((_, i) => xong(i + 1)).length;
  const tien = dang === 0 ? 1 : Math.max(0, (dang - 1) / (BUOC_XE.length - 1));
  const khoa = `${hs.id}-${dang}`;
  const chayLan = !daChayTienDo.has(khoa);
  daChayTienDo.add(khoa);
  return h('div', { class: 'tien-do-khung' },
    h('ol', { class: `tien-do${chayLan ? ' chay' : ''}`, style: `--tien:${tien};--so-buoc:${BUOC_XE.length}`, 'aria-label': `Tiến độ ${BUOC_XE.length} bước` }, BUOC_XE.map((b, i) => {
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
    h('p', { class: 'tien-do-chu' }, dang === 0 ? `Đã xong cả ${BUOC_XE.length} bước` : `Bước ${dang}/${BUOC_XE.length}: ${BUOC_XE[dang - 1]} · đã xong ${soXong} bước`));
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
        dong('Bảo hiểm', hs.hang_bh || (['dong', 'huy'].includes(hs.trang_thai) ? null : h('span', { class: 'nhan tt-canh-bao' }, 'Chọn khi nhập kết quả duyệt giá'))),
        // 036: GDV để trống được lúc nhận xe – nhắc ghi trước khi nhập kết quả duyệt giá
        dong('Giám định viên', hs.gdv_cho_them ? h('span', null, hs.gdv, ' ', h('span', { class: 'nhan tt-canh-bao' }, 'chờ thêm vào danh sách'))
          : hs.gdv || (['dong', 'huy'].includes(hs.trang_thai) ? null : h('span', { class: 'nhan tt-canh-bao', 'data-thieu-gdv': '' }, 'Chọn khi nhập kết quả duyệt giá')))] : null,
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

function theBaoGia({ hs, hm, ve, tep }) {
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
  const boSung = ['da_duyet', 'dang_sua', 'cho_detailing', 'cho_kcs'].includes(hs.trang_thai);
  // Cột "Lần" chỉ hiện khi có báo giá bổ sung; nhóm (đồng, sơn, phụ tùng…) ghi nhỏ dưới tên để bảng vừa khung
  const coBoSung = hm.some((m) => m.lan_bao_gia);
  const cotLan = coBoSung ? { nhan: 'Lần', lay: (m) => (m.lan_bao_gia ? `Bổ sung ${m.lan_bao_gia}` : 'Gốc') } : null;
  const cotTen = { nhan: 'Nội dung sửa chữa', lay: (m) => h('span', { class: 'ten-hang-muc' }, h('span', null, m.ten, !khach && m.nguoi_tra === 'khach' ? h('small', { class: 'nhan' }, 'khách trả') : null), h('small', null, NHOM[m.nhom])) };
  const cotVat = { nhan: 'VAT', lay: (m) => (!m.xuat_hd ? 'Không' : m.ty_le_vat !== null && m.ty_le_vat !== undefined ? phanTram(m.ty_le_vat) : '') };
  const cotTT = { nhan: 'Trạng thái', lay: (m) => h('span', null, m.loai_dong ? h('span', { class: 'nhan' }, m.loai_dong === 'dieu_chinh' ? 'Điều chỉnh' : 'Thỏa thuận hủy') : TT_DONG[m.trang_thai], m.ngay_duyet && m.trang_thai !== 'cho_duyet' ? h('small', null, ` ${ngay(m.ngay_duyet)}`) : null,
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
        // 17/10 (anh Thuận): nút nổi bật. Việc chính của thẻ = vàng đặc: "+ Thêm dòng báo giá" khi chưa có dòng nào chờ duyệt;
        // đã có dòng chờ duyệt thì "Nhập kết quả duyệt" là việc chính, nút thêm dòng còn lại kiểu nổi bật (vàng nhạt, viền đậm)
        duocBaoGia && (goc || boSung) ? nut(goc ? '+ Thêm dòng báo giá' : '+ Báo giá bổ sung (phát sinh)', () => moBaoGia(hs, hm, ve, boSung, tep),
          goc && !choDuyet.length ? true : 'noi-bat') : null,
        duocBaoGia && choDuyet.length ? nut(`Nhập kết quả duyệt (${choDuyet.length})`, () => moDuyetGia(hs, choDuyet, ve, hm, tep), true) : null)),
    bang(cot, hm, { trong: hs.trang_thai === 'tiep_nhan' ? 'Chưa có báo giá.' : 'Chưa có dòng nào.', gon: true }),
    hs.bat_buoc_anh && (goc || boSung) && anhNhanXeThieu(tep).length
      ? h('p', { class: 'thong-bao canh-bao' }, `Chưa đủ 6 ảnh nhận xe (thiếu ${anhNhanXeThieu(tep).map((a) => a.ten.toLowerCase()).join(', ')}) – tải ở mục "Ảnh nhận xe" trước khi lập báo giá.`) : null,
    thieuGdv ? h('p', { class: 'goi-y' }, 'Hãng bảo hiểm và giám định viên chọn trong hộp "Nhập kết quả duyệt".') : null,
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
function moBaoGia(hs, hm, ve, boSung, tep = []) {
  // 047: hồ sơ bắt ảnh → đủ 6 ảnh nhận xe; mỗi lần lưu báo giá kèm ảnh / PDF báo giá (tải trước khi lưu)
  const thieuAnh = hs.bat_buoc_anh ? anhNhanXeThieu(tep) : [];
  if (thieuAnh.length) {
    toast(`Chưa đủ 6 ảnh nhận xe – còn thiếu: ${thieuAnh.map((a) => a.ten.toLowerCase()).join(', ')}. Tải ở mục "Ảnh nhận xe" trước.`, 'loi');
    return;
  }
  let daCoFile = coFileBaoGiaMoi(hs, tep);
  const oFileBG = oDinhKem('Ảnh / file báo giá', { buoc: 'bao_gia', batBuoc: hs.bat_buoc_anh && !daCoFile,
    goiY: daCoFile ? 'Đã có file báo giá tải lên – chọn thêm nếu cần.' : 'Chọn ảnh bảng báo giá hoặc file PDF.' });
  // 053 (anh Thuận 17/10): dòng tải ảnh, giấy tờ xe (đăng ký, đăng kiểm, bảo hiểm xe, CCCD chủ xe…) ngay lúc lập báo giá. Không bắt buộc.
  const soGiayTo = tep.filter((t) => t.buoc === 'giay_to_xe').length;
  const oGiayTo = oDinhKem(NHAN_GIAY_TO_XE, { buoc: 'giay_to_xe',
    goiY: soGiayTo ? `Hồ sơ đã có ${soGiayTo} tệp – chọn thêm nếu cần. Không bắt buộc.` : 'Ảnh xe, đăng ký, đăng kiểm, bảo hiểm xe, CCCD chủ xe… Không bắt buộc.' });
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
        khach ? chiXem('Nguồn', 'Khách ngoài bảo hiểm – không qua duyệt giá') : chiXem('Hãng bảo hiểm', hs.hang_bh || 'Chọn khi nhập kết quả duyệt giá'),
        truong('VAT', chonVat)),
      tong),
    danhSach, nut('+ Thêm dòng', themDong, 'noi-bat'),
    h('div', { class: 'khoi-dinh-kem' }, oFileBG, oGiayTo));
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
      const files = oFileBG.input.files;
      if (hs.bat_buoc_anh && !daCoFile && !files.length) {
        oFileBG.classList.add('thieu'); oFileBG.scrollIntoView({ block: 'center' });
        toast('Đính kèm ảnh hoặc file báo giá.', 'loi'); return false;
      }
      if (files.length) {
        if (await taiVaoBuoc(hs, 'bao_gia', files)) return false;
        daCoFile = true; oFileBG.xoa();
      }
      // Ảnh, giấy tờ xe: tải trước khi lưu báo giá (như file báo giá) để lỗi mạng thì hộp còn mở, chọn lại được
      const giayTo = [...oGiayTo.input.files];
      if (giayTo.length) {
        if (await taiVaoBuoc(hs, 'giay_to_xe', giayTo)) return false;
        oGiayTo.xoa();
      }
      await api.lapBaoGia(hs.id, dong, tyLe());
      if (giao) await giaoSauKhiLuu(hs.id, giao.nguoi());
      toast((khach ? 'Đã lưu báo giá – đã duyệt, lập lệnh sửa chữa được ngay.' : 'Đã lưu báo giá.')
        + (giayTo.length ? ` Đã tải ${giayTo.length} ảnh, giấy tờ xe.` : '')); await ve();
    },
  });
}

// 056 (anh Thuận 17/10): xe bảo hiểm – hộp kết quả duyệt giá chỉ còn 2 ô: Bảo hiểm thanh toán + Khách hàng thanh toán
// (của CẢ XE); tổng = doanh thu của xe. Mọi dòng chờ duyệt được duyệt, máy chủ chia giá từng dòng theo tỷ lệ giá báo.
function moDuyetGiaTong(hs, choDuyet, ve, hm = [], tep = []) {
  let daCoFile = coFileDuyetMoi(hs, tep);
  const canFile = hs.bat_buoc_anh;
  const chonBH = khungChonBaoHiem({ hangId: hs.hang_bh_id, gdvId: hs.gdv_id, gdvTenTam: hs.gdv_cho_them ? hs.gdv : '' });
  const oFileDuyet = oDinhKem('Ảnh / file duyệt giá của bảo hiểm', { buoc: 'duyet_gia', batBuoc: canFile && !daCoFile,
    goiY: daCoFile ? 'Đã có file duyệt giá tải lên – chọn thêm nếu cần.' : 'Bản duyệt giá, biên bản giám định, HĐ 3 bên (ảnh hoặc PDF).' });
  const oNgayDuyet = oNgayVN('ngay', homNay());
  const tienDong = (m, gia) => (m.nguoi_tra === 'khach' ? sauVatDong(m, gia) : sauVat(gia, m.ty_le_vat ?? 0.08));
  const daDuyet = hm.filter((m) => ['duyet', 'dang_lam', 'xong'].includes(m.trang_thai));
  const tongCu = daDuyet.reduce((t, m) => t + tienDong(m, m.gia_duyet), 0);
  const tongBao = choDuyet.reduce((t, m) => t + tienDong(m, m.gia_bao), 0);
  // Gợi ý: khách giữ phần đang phải trả, bảo hiểm phần còn lại của (đã duyệt + báo giá chờ duyệt)
  const khachGoiY = Math.max(0, Number(hs.phai_thu_khach || 0) + Number(hs.giam_gia || 0));
  const oBH = oTien('bao_hiem', Math.max(0, tongCu + tongBao - khachGoiY), { 'aria-label': 'Bảo hiểm thanh toán' });
  const oKhach = oTien('khach', khachGoiY, { 'aria-label': 'Khách hàng thanh toán' });
  const soTong = h('b', { 'data-tong-duyet': '' });
  const tinhLai = () => { soTong.textContent = `${tien((docTien(oBH.value) || 0) + (docTien(oKhach.value) || 0))} đ`; };
  oBH.addEventListener('input', tinhLai); oKhach.addEventListener('input', tinhLai); tinhLai();
  const noiDung = h('div', null,
    chonBH.el,
    truong('Ngày duyệt', oNgayDuyet, `Doanh thu tính vào tháng của ngày duyệt (từ ngày nhận xe ${ngay(hs.ngay_vao)} đến hôm nay)`, { batBuoc: true }),
    h('div', { class: 'luoi-o' },
      truong('Bảo hiểm thanh toán (gồm VAT)', oBH, null, { batBuoc: true }),
      truong('Khách hàng thanh toán (gồm VAT)', oKhach, 'Khấu trừ, miễn thường, phần khách tự trả… – 0 nếu không có', { batBuoc: true })),
    h('div', { class: 'dong-tien dam' }, h('span', null, 'Tổng doanh thu của xe'), soTong),
    h('p', { class: 'goi-y' }, `Hai số là của CẢ XE${tongCu ? ` (đã duyệt các lần trước ${tien(tongCu)} đ)` : ''}. Báo giá đang chờ duyệt: `,
      choDuyet.map((m) => `${m.ten} ${tien(tienDong(m, m.gia_bao))} đ`).join(' · '), ` – tổng ${tien(tongBao)} đ.`),
    h('div', { class: 'khoi-dinh-kem' }, oFileDuyet));
  const giao = hs.trang_thai === 'bao_gia' ? khungGiaoViec('Lập lệnh sửa chữa', VAI_TRO_BUOC.lenh) : null;
  if (giao) noiDung.append(giao.el);
  moModal('Kết quả duyệt giá', noiDung, {
    rong: true, nhanNut: 'Lưu kết quả',
    nutChinh: async () => {
      const ngayDuyet = vnSangIso(oNgayDuyet.value);
      if (!ngayDuyet) { toast('Ngày duyệt không đúng (dd/mm/yyyy).', 'loi'); oNgayDuyet.focus(); return false; }
      const loiBH = chonBH.kiemTra();
      if (loiBH) { toast(loiBH, 'loi'); return false; }
      const baoHiem = docTien(oBH.value); const khach = docTien(oKhach.value);
      if (baoHiem === null || khach === null || Number.isNaN(baoHiem) || Number.isNaN(khach)) { toast('Nhập đủ 2 ô số tiền (0 nếu không có).', 'loi'); return false; }
      if (baoHiem + khach < tongCu) { toast(`Tổng ${tien(baoHiem + khach)} đ nhỏ hơn phần đã duyệt các lần trước (${tien(tongCu)} đ) – hai số là của cả xe.`, 'loi'); return false; }
      const files = oFileDuyet.input.files;
      if (canFile && !daCoFile && !files.length) {
        oFileDuyet.classList.add('thieu'); oFileDuyet.scrollIntoView({ block: 'center' });
        toast('Đính kèm ảnh hoặc file duyệt giá của bảo hiểm.', 'loi'); return false;
      }
      const bhMoi = chonBH.giaTri();
      if (String(bhMoi.hang_bh_id) !== String(hs.hang_bh_id ?? '') || String(bhMoi.gdv_id) !== String(hs.gdv_id ?? '')
        || (bhMoi.gdv_ten_tam || '') !== (hs.gdv_cho_them ? hs.gdv || '' : '')) {
        await api.suaThongTin(hs.id, bhMoi);
        Object.assign(hs, { hang_bh_id: bhMoi.hang_bh_id, gdv_id: bhMoi.gdv_id, gdv_cho_them: !!bhMoi.gdv_ten_tam, gdv: bhMoi.gdv_ten_tam || hs.gdv });
      }
      if (files.length) {
        if (await taiVaoBuoc(hs, 'duyet_gia', files)) return false;
        daCoFile = true; oFileDuyet.input.value = '';
      }
      const kq = await api.duyetGiaTong(hs.id, ngayDuyet, baoHiem, khach);
      if (giao) await giaoSauKhiLuu(hs.id, giao.nguoi());
      toast(`Đã lưu. Bảo hiểm thanh toán ${tien(kq?.bao_hiem ?? baoHiem)} đ, khách thanh toán ${tien(kq?.khach ?? khach)} đ.`); await ve();
    },
  });
}

function moDuyetGia(hs, choDuyet, ve, hm = [], tep = []) {
  const bh = hs.nguon_tt !== 'khach';
  if (bh) return moDuyetGiaTong(hs, choDuyet, ve, hm, tep);
  // 047: xe bảo hiểm (hồ sơ bắt ảnh) → kèm ảnh / file duyệt giá của bảo hiểm tải lên sau lần báo giá gần nhất
  let daCoFile = coFileDuyetMoi(hs, tep);
  const canFile = bh && hs.bat_buoc_anh;
  // 048: xe bảo hiểm – chọn hãng bảo hiểm + giám định viên ngay trong hộp này (bắt buộc), lưu vào hồ sơ trước khi duyệt
  const chonBH = bh ? khungChonBaoHiem({ hangId: hs.hang_bh_id, gdvId: hs.gdv_id, gdvTenTam: hs.gdv_cho_them ? hs.gdv : '' }) : null;
  const oFileDuyet = oDinhKem('Ảnh / file duyệt giá của bảo hiểm', { buoc: 'duyet_gia', batBuoc: canFile && !daCoFile,
    goiY: daCoFile ? 'Đã có file duyệt giá tải lên – chọn thêm nếu cần.' : 'Bản duyệt giá, biên bản giám định, HĐ 3 bên (ảnh hoặc PDF).' });
  // Ngày luôn dd/mm/yyyy (ô date của trình duyệt đổi theo ngôn ngữ máy, dễ nhầm ngày/tháng); không trước ngày nhận xe, không sau hôm nay
  const oNgayDuyet = oNgayVN('ngay', homNay());
  const dongs = choDuyet.map((m) => {
    const dongY = h('input', { type: 'checkbox', checked: true, 'aria-label': `Duyệt ${m.ten}` });
    const gia = oTien('gia', m.gia_bao, { 'aria-label': `Giá duyệt ${m.ten}` });
    dongY.addEventListener('change', () => { gia.disabled = !dongY.checked; tinhLai(); });
    gia.addEventListener('input', tinhLai);
    return { m, dongY, gia, el: h('tr', null, h('td', { 'data-nhan': 'Hạng mục' }, h('label', null, dongY, ' ', m.ten, bh && m.nguoi_tra === 'khach' ? h('small', { class: 'nhan' }, 'khách trả') : null)),
      h('td', { class: 'so', 'data-nhan': 'Giá báo' }, tien(m.gia_bao)), h('td', { 'data-nhan': 'Giá duyệt' }, gia)) };
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
    chonBH ? chonBH.el : null,
    truong('Ngày duyệt', oNgayDuyet, `Doanh thu tính vào tháng của ngày duyệt (từ ngày nhận xe ${ngay(hs.ngay_vao)} đến hôm nay)`, { batBuoc: true }),
    h('div', { class: 'bang-cuon' }, h('table', { class: 'bang' },
      h('thead', null, h('tr', null, h('th', null, 'Hạng mục (bỏ chọn nếu không duyệt)'), h('th', { class: 'so' }, 'Giá báo'), h('th', null, 'Giá duyệt (chưa VAT)'))),
      h('tbody', null, dongs.map((d) => d.el)))),
    khoiChia,
    bh ? h('div', { class: 'khoi-dinh-kem' }, oFileDuyet) : null);
  tinhLai();
  const giao = hs.trang_thai === 'bao_gia' ? khungGiaoViec('Lập lệnh sửa chữa', VAI_TRO_BUOC.lenh) : null;
  if (giao) noiDung.append(giao.el);
  moModal('Kết quả duyệt giá', noiDung, {
    rong: true, nhanNut: 'Lưu kết quả',
    nutChinh: async () => {
      const ngayDuyet = vnSangIso(oNgayDuyet.value);
      if (!ngayDuyet) { toast('Ngày duyệt không đúng (dd/mm/yyyy).', 'loi'); oNgayDuyet.focus(); return false; }
      if (chonBH) {
        const loi = chonBH.kiemTra();
        if (loi) { toast(loi, 'loi'); return false; }
      }
      const files = bh ? oFileDuyet.input.files : [];
      if (canFile && !daCoFile && !files.length) {
        oFileDuyet.classList.add('thieu'); oFileDuyet.scrollIntoView({ block: 'center' });
        toast('Đính kèm ảnh hoặc file duyệt giá của bảo hiểm.', 'loi'); return false;
      }
      if (chonBH) {
        const bhMoi = chonBH.giaTri();
        if (String(bhMoi.hang_bh_id) !== String(hs.hang_bh_id ?? '') || String(bhMoi.gdv_id) !== String(hs.gdv_id ?? '')
          || (bhMoi.gdv_ten_tam || '') !== (hs.gdv_cho_them ? hs.gdv || '' : '')) {
          await api.suaThongTin(hs.id, bhMoi);
          Object.assign(hs, { hang_bh_id: bhMoi.hang_bh_id, gdv_id: bhMoi.gdv_id, gdv_cho_them: !!bhMoi.gdv_ten_tam, gdv: bhMoi.gdv_ten_tam || hs.gdv });
        }
      }
      if (files.length) {
        if (await taiVaoBuoc(hs, 'duyet_gia', files)) return false;
        daCoFile = true; oFileDuyet.input.value = '';
      }
      const ketQua = dongs.map((d) => ({ id: d.m.id, dong_y: d.dongY.checked, gia_duyet: d.dongY.checked ? docTien(d.gia.value) : null }));
      const kq = await api.duyetGiaChia(hs.id, ngayDuyet, ketQua, bh ? (docTien(oKhach.value) || 0) : null);
      if (giao) await giaoSauKhiLuu(hs.id, giao.nguoi());
      toast(bh && kq ? `Đã lưu. Bảo hiểm chi trả ${tien(kq.bao_hiem)} đ, khách chi trả ${tien(kq.khach)} đ.` : 'Đã lưu kết quả duyệt.'); await ve();
    },
  });
}

// ---------- Lệnh sửa chữa, sửa chữa (bước 4–5) ----------
function theSuaChua({ hs, hm, ps, ve, cho, tep }) {
  if (!['da_duyet', 'dang_sua', 'cho_detailing', 'cho_kcs', 'dat_kcs'].includes(hs.trang_thai) && !hm.some((m) => m.to_id)) return null;
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
          ? nut(hs.trang_thai === 'da_duyet' ? 'Lập lệnh sửa chữa' : `Giao thêm cho tổ (${chuaGiao.length})`, () => moLenh(hs, chuaGiao, ve, tep), true) : null,
        ['dang_sua', 'cho_detailing', 'cho_kcs'].includes(hs.trang_thai) && q('truong_nhom', 'cvdv', 'quan_ly', 'giam_doc') ? nut('Báo phát sinh', () => moPhatSinh(hs, ve)) : null)),
    psMo.length ? h('div', { class: 'thong-bao canh-bao', 'data-phat-sinh': '' },
      h('b', null, hs.loai === 'bao_hanh' ? 'Phát sinh chờ xử lý: ' : 'Phát sinh chờ báo giá bổ sung: '),
      psMo.map((p) => h('div', null, `${ngayGio(p.luc)} – ${p.mo_ta}`)),
      duocLap ? h('div', { class: 'hang-nut' },
        hs.loai === 'bao_hanh' && ['da_duyet', 'dang_sua', 'cho_detailing', 'cho_kcs'].includes(hs.trang_thai)
          ? nut('+ Thêm hạng mục bảo hành', () => moThemBaoHanh(hs, ve), true) : null,
        nut('Không cần làm thêm', () => moXuLyPhatSinh(hs, ve))) : null) : null,
    !dangLam.length ? h('p', { class: 'trong' }, 'Chưa giao việc cho tổ nào. Chưa có lệnh sửa chữa thì chưa làm, chưa cấp phụ tùng.') :
      bang([
        { nhan: 'Hạng mục', khoa: 'ten' },
        { nhan: 'Tổ', lay: (m) => api.dm.ten('to_thuc_hien', m.to_id) },
        { nhan: 'Người làm', lay: (m) => chipNguoi(m.nguoi_lam, { vai: 'truong_nhom' }) || '' },
        { nhan: 'Trạng thái', lay: (m) => m.trang_thai === 'xong' ? `Xong ${ngayGio(m.xong_luc)}` :
          duocLap ? h('button', { class: 'nut nho chinh', type: 'button', onclick: () => chay(() => api.baoXong(m.id), { thanhCong: 'Đã báo xong.' }).then(ve, ve.lai) }, 'Báo xong') : 'Đang làm' },
      ], dangLam),
    khoiPT);
}

// 056 (anh Thuận 17/10): lệnh sửa chữa gọn theo tổ – Đồng, Sơn → tổ Đồng sơn; Phụ tùng → tổ Điện – máy – gầm; Detailing →
// tổ Detailing. Mỗi tổ chọn một NGƯỜI THỰC HIỆN là tài khoản phần mềm (người đó nhận thông báo việc mới). Ảnh lệnh bắt buộc.
const TO_THEO_NHOM = { dong: 'DS', son: 'DS', dong_son: 'DS', phu_tung: 'DMG', dmg: 'DMG', detailing: 'DT' };
function nguoiChoTo(toId, cn) {
  const ds = (api.dm.nhan_vien || []).filter((n) => n.hoat_dong && (!cn || !n.chi_nhanh_id || n.chi_nhanh_id === cn));
  const tn = (n) => (n.vai_tro || []).includes('truong_nhom');
  const dung = ds.filter((n) => tn(n) && n.to_id === toId);
  const khac = ds.filter((n) => tn(n) && n.to_id !== toId);
  const qlgd = ds.filter((n) => !tn(n) && (n.vai_tro || []).some((v) => ['quan_ly', 'giam_doc'].includes(v)));
  return { dung, ds: [...dung, ...khac, ...qlgd] };
}
function moLenh(hs, ds, ve, tep = []) {
  // Chưa có giờ hẹn: mặc định sau N ngày (cài đặt so_ngay_hen_giao, 3) lúc 17:00; người lập lệnh sửa lại nếu khác
  const henMacDinh = () => { const d = new Date(); d.setDate(d.getDate() + api.caiDat('so_ngay_hen_giao', 3)); d.setHours(17, 0, 0, 0); return d; };
  const oHenKhung = oNgayGioVN('hen_giao', hs.hen_giao || henMacDinh(), { batBuoc: !hs.hen_giao });
  const oHen = oHenKhung.querySelector('input[name=hen_giao]');
  const tenTo = (id) => api.dm.to_thuc_hien.find((t) => t.id === id)?.ten || id;
  const nhom = new Map();
  for (const m of ds) { const to = TO_THEO_NHOM[m.nhom] || 'DS'; if (!nhom.has(to)) nhom.set(to, []); nhom.get(to).push(m); }
  const dongs = [...nhom].map(([toId, dsHm]) => {
    const { dung, ds: nguoi } = nguoiChoTo(toId, hs.chi_nhanh_id);
    const chon = oChon(`nguoi_${toId}`, nguoi.map((n) => ({ value: n.id, label: `${n.ho_ten}${n.to_id === toId ? ' – trưởng nhóm' : n.to_id ? ` – tổ ${tenTo(n.to_id)}` : ''}` })),
      dung[0]?.id ?? null, { 'aria-label': `Người thực hiện tổ ${tenTo(toId)}`, 'data-nguoi-to': toId });
    return { toId, dsHm, chon, el: h('tr', null,
      h('td', { 'data-nhan': 'Tổ' }, h('b', null, tenTo(toId))),
      h('td', { 'data-nhan': 'Hạng mục' }, dsHm.map((m) => m.ten).join(', ')),
      h('td', { 'data-nhan': 'Người thực hiện' }, chon)) };
  });
  const daCoAnh = tep.some((t) => t.buoc === 'lenh_sua_chua' && (!hs.bao_gia_luc || new Date(t.tai_luc) > new Date(hs.bao_gia_luc)));
  const oAnhLenh = oDinhKem('Ảnh lệnh sửa chữa', { buoc: 'lenh_sua_chua', batBuoc: !daCoAnh,
    goiY: daCoAnh ? 'Đã có ảnh lệnh sửa chữa – chọn thêm nếu cần.' : 'Chụp tờ lệnh sửa chữa đã ký (ảnh hoặc PDF).' });
  moModal(hs.trang_thai === 'da_duyet' ? 'Lệnh sửa chữa' : 'Giao thêm cho tổ', h('div', null,
    truong('Giờ hẹn giao xe', oHenKhung, hs.hen_giao ? 'Ngày dd/mm/yyyy · giờ 24h' : `Mặc định sau ${api.caiDat('so_ngay_hen_giao', 3)} ngày, 17:00 – sửa lại nếu khác`, { batBuoc: !hs.hen_giao }),
    h('div', { class: 'bang-cuon' }, h('table', { class: 'bang' },
      h('thead', null, h('tr', null, h('th', null, 'Tổ'), h('th', null, 'Hạng mục'), h('th', null, 'Người thực hiện (nhận thông báo)'))),
      h('tbody', null, dongs.map((d) => d.el)))),
    h('div', { class: 'khoi-dinh-kem' }, oAnhLenh)), {
    rong: true, nhanNut: 'Giao việc',
    nutChinh: async () => {
      for (const d of dongs) if (!d.chon.value) { toast(`Chọn người thực hiện cho tổ ${tenTo(d.toId)}.`, 'loi'); d.chon.focus(); return false; }
      const files = [...oAnhLenh.input.files];
      if (!daCoAnh && !files.length) {
        oAnhLenh.classList.add('thieu'); oAnhLenh.scrollIntoView({ block: 'center' });
        toast('Đính kèm ảnh lệnh sửa chữa.', 'loi'); return false;
      }
      if (files.length) { if (await taiVaoBuoc(hs, 'lenh_sua_chua', files)) return false; oAnhLenh.xoa(); }
      const ten = (id) => (api.dm.nhan_vien || []).find((n) => n.id === id)?.ho_ten || '';
      await api.lapLenh(hs.id, oHen.value ? new Date(oHen.value).toISOString() : null,
        dongs.flatMap((d) => d.dsHm.map((m) => ({ id: m.id, to_id: d.toId, nguoi_lam: ten(d.chon.value), nguoi_lam_id: d.chon.value }))), true);
      toast('Đã giao việc cho tổ.'); await ve();
    },
  });
}

// 041: hồ sơ bảo hành – phát sinh phải làm thêm: thêm hạng mục miễn phí (giá 0), rồi "Giao thêm cho tổ"
function moThemBaoHanh(hs, ve) {
  const ds = h('div', { class: 'ds-dong-nhap' });
  const themDong = () => ds.append(h('div', { class: 'dong-kho' },
    truong('Hạng mục làm thêm', oChu('ten', '', { placeholder: 'Ví dụ: sơn lại cản sau' }), null, { batBuoc: true, co: 'lon' }),
    truong('Nhóm', oChon('nhom', NHOM_CHON.map((n) => ({ value: n, label: NHOM[n] })), 'dong', { trong: null }))));
  themDong();
  moModal('Thêm hạng mục bảo hành', h('div', null,
    h('p', { class: 'mo-ta' }, 'Làm lại miễn phí, không báo giá, không tính doanh thu. Lưu xong bấm "Giao thêm cho tổ".'),
    ds, h('button', { class: 'nut noi-bat', type: 'button', onclick: themDong }, '+ Thêm dòng')), {
    nhanNut: 'Lưu hạng mục',
    nutChinh: async () => {
      const dong = [...ds.children].map((d) => ({ ten: d.querySelector('[name=ten]').value.trim(), nhom: d.querySelector('[name=nhom]').value }))
        .filter((d) => d.ten);
      if (!dong.length) { toast('Ghi ít nhất một hạng mục.', 'loi'); return false; }
      const n = await api.themHangMucBaoHanh(hs.id, dong);
      toast(`Đã thêm ${n} hạng mục bảo hành – giao cho tổ ở mục 4–5.`); await ve();
    },
  });
}
// 041: phát sinh không phải làm thêm (đã kiểm, không lỗi; đã làm trong hạng mục cũ…) – ghi lý do, hết cảnh báo
function moXuLyPhatSinh(hs, ve) {
  hoiLyDo('Phát sinh không cần làm thêm', async (lyDo) => { await api.xuLyPhatSinh(hs.id, lyDo); toast('Đã ghi xử lý phát sinh.'); await ve(); },
    { nhan: 'Cách xử lý', placeholder: 'Ví dụ: đã kiểm tra, đèn không lỗi', nhanNut: 'Lưu' });
}

function moPhatSinh(hs, ve) {
  const form = h('form', null,
    truong('Hư hỏng phát sinh', oVung('mo_ta', '', { rows: 3 }), 'Dừng phần phát sinh, chờ báo giá bổ sung và duyệt.', { batBuoc: true }),
    truong('Ảnh hư hỏng', oChonTep({ name: 'anh', multiple: true }, 'Tải ảnh hư hỏng')));
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

// ---------- Ảnh hủy vật tư (051): xe bảo hiểm, nếu có – không bắt buộc ----------
// Phụ tùng / vật tư thay ra phải hủy theo yêu cầu bảo hiểm: chụp lại để gửi kèm hồ sơ bảo hiểm.
const TT_HUY_VAT_TU = ['da_duyet', 'dang_sua', 'cho_detailing', 'cho_kcs', 'dat_kcs', 'da_giao', 'da_gui_hs'];
function theHuyVatTu({ hs, tep, ve }) {
  if (hs.nguon_tt === 'khach' || hs.loai === 'bao_hanh' || hs.trang_thai === 'huy') return null;
  const ds = tep.filter((t) => t.buoc === 'huy_vat_tu');
  const duocTai = !api.laCoDong() && q('cvdv', 'kho', 'ke_toan', 'quan_ly', 'giam_doc') && TT_HUY_VAT_TU.includes(hs.trang_thai);
  if (!ds.length && !duocTai) return null;
  const oAnh = h('input', { type: 'file', accept: 'image/*,application/pdf', multiple: true, 'aria-label': 'Tải ảnh hủy vật tư' });
  const dangTai = h('small', { class: 'goi-y', role: 'status', 'aria-live': 'polite' });
  oAnh.addEventListener('change', async () => {
    const chon = [...oAnh.files];
    if (!chon.length) return;
    oAnh.disabled = true;
    const loi = await taiVaoBuoc(hs, 'huy_vat_tu', chon, (n, t) => { dangTai.textContent = `Đang tải ${n}/${t}…`; });
    oAnh.disabled = false; oAnh.value = ''; dangTai.textContent = '';
    if (chon.length > loi) toast(`Đã lưu ${chon.length - loi} ảnh hủy vật tư.`);
    ve.lai();
  });
  const luoi = h('div', { class: 'luoi-anh' });
  (async () => {
    if (!ds.length) return;
    let link = {};
    try { link = await api.linkTepNhieu(ds.map((t) => t.duong_dan)); } catch { return; }
    for (const t of ds) {
      const l = link[t.duong_dan];
      if (!l?.lon) continue;
      const laAnh = /\.(jpe?g|png|webp|heic)$/i.test(t.duong_dan);
      luoi.append(h('a', { href: l.lon, target: '_blank', rel: 'noopener', class: 'o-anh' },
        laAnh ? h('img', { src: l.nho, alt: 'Hủy vật tư', loading: 'lazy' }) : h('span', { class: 'tep' }, 'PDF'), h('small', null, ngay(t.tai_luc))));
    }
  })();
  return h('section', { class: 'the', 'data-the': 'huy-vat-tu' },
    h('div', { class: 'the-dau' }, h('h2', null, `Ảnh hủy vật tư (${ds.length})`),
      duocTai ? h('label', { class: 'nut nho' }, icon('anh'), 'Tải ảnh hủy vật tư', oAnh) : null),
    h('p', { class: 'goi-y' }, 'Xe bảo hiểm có phụ tùng, vật tư thay ra phải hủy: tải ảnh lúc hủy để gửi kèm hồ sơ bảo hiểm. Không có thì bỏ qua.'),
    dangTai, ds.length ? luoi : null);
}

// ---------- Detailing (bước 6) – 050 ----------
// Sửa xong hết hạng mục → tổ Detailing rửa xe, đánh bóng → đạt thì sang KCS, chưa đạt trả về sửa lại.
// CVDV / quản lý / giám đốc bật – tắt bước này cho từng xe (trước khi sang KCS).
const TRUOC_KCS = ['tiep_nhan', 'bao_gia', 'da_duyet', 'dang_sua', 'cho_detailing'];
function theDetailing({ hs, hm, ps, dsDet, ve }) {
  if (hs.trang_thai === 'huy' || hs.tu_excel) return null;
  const coBuoc = hs.qua_detailing || hs.trang_thai === 'cho_detailing';
  const doiDuoc = !api.laCoDong() && q('cvdv', 'quan_ly', 'giam_doc') && TRUOC_KCS.includes(hs.trang_thai);
  if (!coBuoc && !dsDet.length && !doiDuoc) return null;
  const cho = hs.trang_thai === 'cho_detailing';
  const conPhatSinh = (ps || []).some((p) => !p.da_xu_ly);
  const duoc = duocDetailing();
  const bat = async (qua) => {
    if (!qua && !(await xacNhan(cho ? 'Bỏ bước Detailing của xe này? Xe chuyển sang chờ KCS ngay.' : 'Xe này không qua Detailing – sửa xong chuyển thẳng KCS?', 'Bỏ qua Detailing'))) return;
    await chay(() => api.datQuaDetailing(hs.id, qua), { thanhCong: qua ? 'Đã thêm bước Detailing.' : 'Xe không qua Detailing.' }).then(ve.lai, ve.lai);
  };
  return h('section', { class: 'the', 'data-the': 'detailing' },
    h('div', { class: 'the-dau' }, h('h2', null, '6. Detailing – rửa xe, đánh bóng'),
      h('div', { class: 'hang-nut' },
        cho && duoc ? nut('Chưa đạt – trả về sửa chữa', () => moDetailingTraVe(hs, hm, ve)) : null,
        cho && duoc ? nut('Đạt – chuyển KCS', () => {
          if (conPhatSinh) { toast('Còn hư hỏng phát sinh chưa xử lý – CVDV lập báo giá bổ sung hoặc ghi "Không cần làm thêm" trước.', 'loi'); return; }
          detailingDat(hs, ve, ve.lai);
        }, true) : null)),
    !coBuoc ? h('p', { class: 'goi-y' }, 'Xe này không qua Detailing – sửa xong chuyển thẳng KCS.')
      : cho ? h('p', { class: 'goi-y' }, duoc ? 'Rửa xe, đánh bóng xong thì bấm "Đạt – chuyển KCS". Thấy lỗi sửa chữa thì trả về tổ sửa lại.'
        : 'Chờ tổ Detailing rửa xe, đánh bóng.')
        : TRUOC_KCS.includes(hs.trang_thai) ? h('p', { class: 'goi-y' }, 'Sửa xong hết hạng mục, xe chuyển sang tổ Detailing rửa xe, đánh bóng rồi mới KCS.') : null,
    cho && conPhatSinh ? h('p', { class: 'thong-bao canh-bao' }, 'Còn hư hỏng phát sinh chờ xử lý (mục 4–5) – xử lý xong mới chuyển KCS.') : null,
    doiDuoc ? h('div', { class: 'hang-nut' }, coBuoc
      ? h('button', { class: 'nut nho', type: 'button', 'data-bo-detailing': '', onclick: () => bat(false) }, 'Bỏ qua Detailing')
      : h('button', { class: 'nut nho', type: 'button', 'data-them-detailing': '', onclick: () => bat(true) }, 'Thêm bước Detailing')) : null,
    dsDet.length ? h('ul', { class: 'ds-don' }, dsDet.map((k) => h('li', null, ngayGio(k.luc), ' – ',
      k.dat ? h('b', { class: 'chu-tot' }, 'Đạt') : h('b', { class: 'chu-loi' }, 'Chưa đạt: '), k.loi || ''))) : null);
}

// ---------- KCS (bước 7) ----------
// 047: quản lý chung, CVDV, giám đốc nghiệm thu; hồ sơ bắt ảnh cần tối thiểu 6 ảnh KCS (tổng các lần)
// 043 (khớp máy chủ): lần KCS gần nhất chưa đạt thì phải có ảnh "Sau sửa" chụp SAU lần đó; còn phát sinh chờ xử lý thì chưa ký đạt
function theKcs({ hs, hm, tep, dsKcs, ps, ve }) {
  if (!['cho_kcs', 'dat_kcs', 'da_giao', 'da_gui_hs', 'dong'].includes(hs.trang_thai) && !dsKcs.length) return null;
  const truot = dsKcs.find((k) => !k.dat) || null;              // dsKcs mới nhất trước
  const coAnhMoi = tep.some((t) => t.buoc === 'kcs' && (!truot || new Date(t.tai_luc) > new Date(truot.luc)));
  const soAnh = soAnhKcs(tep);
  const canSo = hs.bat_buoc_anh ? SO_ANH_KCS : 1;
  const duAnh = soAnh >= canSo && coAnhMoi;
  const conPhatSinh = (ps || []).some((p) => !p.da_xu_ly);
  const choKcs = hs.trang_thai === 'cho_kcs';
  const duocKcs = q('quan_ly', 'cvdv', 'giam_doc');
  const thieuAnh = () => (soAnh < canSo
    ? `KCS cần tối thiểu ${canSo} ảnh sau sửa (mới có ${soAnh}).`
    : truot ? `Chưa có ảnh sau khi làm lại (lần KCS chưa đạt lúc ${ngayGio(truot.luc)}) – chụp thêm ít nhất 1 ảnh.` : 'Chưa có ảnh sau sửa.');
  // Tải ảnh KCS ngay trong thẻ (nhiều ảnh một lần; 051: chọn ảnh có sẵn trong máy, không mở thẳng camera)
  const oAnh = h('input', { type: 'file', accept: 'image/*', multiple: true, 'aria-label': 'Tải ảnh KCS' });
  const dangTai = h('small', { class: 'goi-y', role: 'status', 'aria-live': 'polite' });
  oAnh.addEventListener('change', async () => {
    const ds = [...oAnh.files];
    if (!ds.length) return;
    oAnh.disabled = true;
    const loi = await taiVaoBuoc(hs, 'kcs', ds, (n, t) => { dangTai.textContent = `Đang tải ${n}/${t}…`; });
    oAnh.disabled = false; oAnh.value = ''; dangTai.textContent = '';
    if (ds.length > loi) toast(`Đã lưu ${ds.length - loi} ảnh KCS.`);
    ve.lai();
  });
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, hs.qua_detailing ? '7. Nghiệm thu (KCS)' : '7. Nghiệm thu (KCS) và rửa xe'),
      choKcs && duocKcs ? h('div', { class: 'hang-nut' },
        nut('Chưa đạt – làm lại', () => moKhongDat(hs, hm, ve)),
        nut('Đạt KCS', async () => {
          if (conPhatSinh) { toast('Còn hư hỏng phát sinh chưa xử lý – CVDV lập báo giá bổ sung hoặc ghi "Không cần làm thêm" trước.', 'loi'); return; }
          if (!duAnh) { toast(`${thieuAnh()} Bấm "Tải ảnh KCS" rồi ký đạt.`, 'loi'); return; }
          await chay(() => api.kcs(hs.id, true, null, null), { thanhCong: 'Đã ký đạt KCS.' }).then(ve, ve.lai);
        }, true)) : null),
    choKcs && !duocKcs ? h('p', { class: 'goi-y' }, 'Chờ quản lý chung hoặc CVDV nghiệm thu.') : null,
    choKcs && conPhatSinh ? h('p', { class: 'thong-bao canh-bao' }, 'Còn hư hỏng phát sinh chờ xử lý (mục 4–5) – xử lý xong mới ký KCS đạt.') : null,
    choKcs ? h('div', { class: 'dem-anh-kcs' },
      h('span', { class: `nhan ${duAnh ? 'tt-tot' : 'tt-canh-bao'}`, 'data-anh-kcs': soAnh }, `Ảnh KCS: ${soAnh}/${canSo}`),
      duocKcs && !api.laCoDong() ? h('label', { class: `nut nho${duAnh ? '' : ' noi-bat'}` }, icon('anh'), 'Tải ảnh KCS', oAnh) : null, dangTai,
      !duAnh ? h('small', { class: 'goi-y' }, thieuAnh()) : null) : null,
    dsKcs.length ? h('ul', { class: 'ds-don' }, dsKcs.map((k) => h('li', null, ngayGio(k.luc), ' – ', k.dat ? h('b', { class: 'chu-tot' }, 'Đạt') : h('b', { class: 'chu-loi' }, 'Chưa đạt: '), k.loi || ''))) : null);
}

// ---------- Ảnh nhận xe (047): 6 ảnh có tên, thiếu thì chụp bổ sung ngay ở đây ----------
function theAnhNhanXe({ hs, tep, ve }) {
  const coAnhGoc = tep.some((t) => ANH_NHAN_XE.some((a) => a.buoc === t.buoc));
  if (!hs.bat_buoc_anh && !coAnhGoc) return null;
  const thieu = anhNhanXeThieu(tep);
  const choSua = !api.laCoDong() && q('cvdv', 'quan_ly', 'giam_doc') && !['dong', 'huy'].includes(hs.trang_thai);
  const khung = khungAnhNhanXe({ hs, tep, choSua, khiXong: () => ve.lai() });
  // Ảnh nhỏ của ảnh đã có (link ký tạm thời)
  (async () => {
    const coAnh = ANH_NHAN_XE.map((a) => tep.filter((t) => t.buoc === a.buoc).pop()).filter(Boolean);
    if (!coAnh.length) return;
    let link = {};
    try { link = await api.linkTepNhieu(coAnh.map((t) => t.duong_dan)); } catch { return; }
    for (const t of coAnh) {
      const o = khung.querySelector(`[data-o="${t.buoc}"] .o-anh-buoc-hinh`);
      const l = link[t.duong_dan];
      if (o && l?.nho) o.replaceChildren(h('img', { src: l.nho, alt: BUOC_TEP[t.buoc] || t.buoc }));
    }
  })();
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, `Ảnh nhận xe (${6 - thieu.length}/6)`)),
    hs.bat_buoc_anh && thieu.length
      ? h('p', { class: 'thong-bao canh-bao' }, `Còn thiếu: ${thieu.map((a) => a.ten.toLowerCase()).join(', ')} – chưa lập báo giá / lệnh sửa chữa được.`) : null,
    khung);
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
    // 041: đã giao mà khách còn nợ – giám đốc / quản lý chung vẫn duyệt giảm giá được (hết nợ thì hồ sơ tự đóng)
    const giamSauGiao = q('quan_ly', 'giam_doc') && !['dong', 'huy'].includes(hs.trang_thai) && Number(hs.con_no_khach) > 0;
    return h('section', { class: 'the' },
      h('div', { class: 'the-dau' }, h('h2', null, '8. Thanh toán và giao xe'),
        giamSauGiao ? nut('Duyệt giảm giá cho khách', () => moGiamGia(hs, ve)) : null),
      h('p', null, 'Đã giao lúc ', h('b', null, ngayGio(hs.giao_luc)), hs.cho_giao_no_boi ? ' (được duyệt giao khi khách còn nợ)' : ''),
      hs.cam_nhan_khach ? h('p', null, 'Cảm nhận của khách: ', hs.cam_nhan_khach) : null,
      h('p', { class: 'mo-ta' }, `Số HĐ bảo hiểm: ${hs.so_hd_bao_hiem || '—'} · Số HĐ khách: ${hs.so_hd_khach || '—'}`));
  }
  const bh = hs.nguon_tt !== 'khach';
  const keToan = q('ke_toan', 'giam_doc');
  const noKhach = Number(hs.con_no_khach) || 0;
  const form = h('form', { class: 'luoi-o' }, keToan ? null : cacOGiaoXe(hs));
  return h('section', { class: 'the' },
    h('div', { class: 'the-dau' }, h('h2', null, '8. Thanh toán và giao xe')),
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
  // Số nhập là TỔNG giảm giá của hồ sơ (không phải số giảm thêm); tối đa = phần khách phải trả trước giảm giá
  const toiDa = Number(hs.phai_thu_khach) + Number(hs.giam_gia || 0);
  const form = h('form', null,
    h('p', { class: 'mo-ta' }, `Khách phải trả ${tien(toiDa)} đ trước giảm giá · đã trả ${tien(hs.da_thu_khach) || '0'} đ · còn nợ ${tien(hs.con_no_khach) || '0'} đ.`),
    truong('Tổng số tiền giảm cho khách', oTien('so_tien', hs.giam_gia),
      `Tối đa ${tien(toiDa)} đ. Ghi TỔNG giảm giá của hồ sơ: phần chênh so với lần trước trừ vào doanh thu hôm nay, các lần trước giữ ở tháng cũ.${hs.giao_luc ? ' Hết nợ thì hồ sơ tự đóng.' : ''}`, { batBuoc: true }),
    truong('Lý do', oVung('ly_do', ''), null, { batBuoc: true }));
  moModal('Duyệt giảm giá', form, {
    nhanNut: 'Duyệt',
    nutChinh: async () => { const d = docForm(form); await api.duyetGiamGia(hs.id, d.so_tien ?? 0, d.ly_do); toast('Đã duyệt giảm giá.'); await ve(); },
  });
}

// ---------- Hồ sơ bảo hiểm, hoa hồng (bước 9) ----------
function theHoSoBH({ hs, tep, ve }) {
  if (hs.nguon_tt === 'khach' || !hs.giao_luc) return null;
  const soHuy = (tep || []).filter((t) => t.buoc === 'huy_vat_tu').length;
  const keToan = q('ke_toan', 'giam_doc');
  // 043 (khớp máy chủ): bảo hiểm chi trả 0 đ (khách trả hết) / hồ sơ bảo hành thì không có hồ sơ gửi bảo hiểm
  const canGui = coBuocHoSoBH(hs);
  const oNgayGui = oNgayVN('ngay_gui', homNay(), { 'aria-label': 'Ngày gửi hồ sơ' });
  const thangHH = hs.hoa_hong_ky ? `${String(hs.hoa_hong_ky).slice(5, 7)}/${String(hs.hoa_hong_ky).slice(0, 4)}` : null;
  return h('section', { class: 'the' },
    h('h2', null, '9. Hồ sơ bảo hiểm, thu nợ, hoa hồng'),
    // 051: nhắc kế toán ảnh hủy vật tư (nếu có) để gửi kèm hồ sơ
    soHuy ? h('p', { class: 'goi-y' }, `Có ${soHuy} ảnh hủy vật tư – gửi kèm hồ sơ bảo hiểm (xem mục "Ảnh hủy vật tư").`) : null,
    hs.gui_hs_ngay ? h('p', null, 'Đã gửi hồ sơ ngày ', h('b', null, ngay(hs.gui_hs_ngay)))
      : !canGui ? h('p', { class: 'goi-y' }, 'Bảo hiểm không chi trả phần nào của xe này – không cần gửi hồ sơ bảo hiểm.')
        : keToan && hs.trang_thai === 'da_giao' && !hs.tu_excel ? h('div', { class: 'hang-nut' },
          oNgayGui,
          nut('Đã gửi hồ sơ bảo hiểm', () => {
            const ngayGui = vnSangIso(oNgayGui.value);
            if (!ngayGui) { toast('Ngày gửi hồ sơ không đúng (dd/mm/yyyy).', 'loi'); oNgayGui.focus(); return null; }
            return chay(() => api.guiHoSoBH(hs.id, ngayGui), { thanhCong: 'Đã ghi ngày gửi hồ sơ.' }).then(ve, ve.lai);
          }, true))
          : h('p', { class: 'goi-y' }, 'Chờ kế toán gửi hồ sơ (trong 3 ngày sau giao xe).'),
    hs.gdv_id ? h('div', { class: 'hang-nut' },
      h('span', null, 'Hoa hồng GDV ', h('b', null, hs.gdv), ': ', hs.hoa_hong_gdv === null ? h('i', null, 'chưa nhập') : h('b', null, tien(hs.hoa_hong_gdv) + ' đ'),
        hs.hoa_hong_ghi_chu ? h('small', null, ` (${hs.hoa_hong_ghi_chu})`) : null,
        // 043: tháng duyệt giá đã chốt sổ lúc nhập hoa hồng → tính vào tháng đang mở lúc nhập
        thangHH && hs.hoa_hong_gdv !== null ? h('small', { class: 'nhan' }, `tính vào lãi lỗ tháng ${thangHH}`) : null),
      keToan ? nut(hs.hoa_hong_gdv === null ? 'Nhập hoa hồng' : 'Sửa', () => moHoaHong(hs, ve), hs.hoa_hong_gdv === null ? 'noi-bat' : false) : null) : null);
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
    truong('Hẹn bảo dưỡng (3–6 tháng sau)', oNgayVN('hen', hs.hen_bao_duong), 'Ngày/tháng/năm, bỏ trống nếu chưa hẹn'));
  moModal('Chăm sóc sau giao', form, {
    nutChinh: async () => {
      const d = docForm(form);
      if (d.hen === 'sai') { toast('Ngày hẹn bảo dưỡng không đúng (dd/mm/yyyy).', 'loi'); return false; }
      await api.ghiChamSoc(hs.id, d.ket_qua, d.hen); toast('Đã lưu.'); await ve();
    },
  });
}

// ---------- Tiền ----------
// 056: phiếu thu lệch công nợ – giám đốc / quản lý chung duyệt (chỉnh công nợ về số thực thu) hoặc không duyệt
function khoiDieuChinh(dc, ve) {
  if (!dc.length) return null;
  const duyet = q('quan_ly', 'giam_doc') && !api.laCoDong();
  const TT = { cho_duyet: 'Chờ duyệt', da_duyet: 'Đã duyệt', tu_choi: 'Không duyệt', huy: 'Thôi (phiếu hủy)' };
  return h('div', { class: 'khoi-dieu-chinh', 'data-dieu-chinh': '' }, h('hr'), h('h3', null, 'Thu lệch công nợ'),
    h('ul', { class: 'ds-don' }, dc.map((d) => h('li', { 'data-dc': d.id },
      h('div', null, h('b', null, d.nguoi_tra === 'bao_hiem' ? 'Bảo hiểm' : 'Khách'), ` công nợ ${tien(d.cong_no)} đ, thực thu ${tien(d.thuc_thu)} đ – lệch `,
        h('b', null, `${Number(d.thuc_thu) - Number(d.cong_no) > 0 ? '+' : ''}${tien(Number(d.thuc_thu) - Number(d.cong_no))} đ`)),
      h('small', null, `Lý do: ${d.ly_do} · ${d.nguoi_lap_ten || ''} ${ngayGio(d.tao_luc)} · `),
      h('span', { class: `nhan ${d.trang_thai === 'cho_duyet' ? 'tt-canh-bao' : ''}` }, TT[d.trang_thai] || d.trang_thai),
      d.trang_thai === 'da_duyet' ? h('small', null, ` – ${d.duyet_boi_ten || ''} chỉnh doanh thu ${Number(d.so_tien_dieu_chinh) > 0 ? '+' : ''}${tien(d.so_tien_dieu_chinh)} đ`) : null,
      d.trang_thai === 'tu_choi' ? h('small', null, ` – ${d.ly_do_tu_choi || ''}`) : null,
      d.trang_thai === 'cho_duyet' && duyet ? h('div', { class: 'hang-nut' },
        nut('Duyệt chỉnh công nợ', () => chay(() => api.duyetDieuChinh(d.id, true), { thanhCong: 'Đã chỉnh công nợ về số thực thu.' }).then(ve, ve.lai), true),
        nut('Không duyệt', () => hoiLyDo('Không duyệt chỉnh công nợ', async (lyDo) => { await api.duyetDieuChinh(d.id, false, lyDo); toast('Đã ghi không duyệt.'); await ve(); },
          { nhan: 'Lý do không duyệt', nhanNut: 'Không duyệt' }))) : null))));
}

function theTien({ hs, hm, giaVon, ve, dc = [] }) {
  const d = (nhan, gt, dam) => h('div', { class: `dong-tien ${dam ? 'dam' : ''}` }, h('span', null, nhan), h('b', null, tien(gt) || '0'));
  const bh = hs.nguon_tt !== 'khach';
  if (hs.loai === 'bao_hanh' && !['tiep_nhan', 'bao_gia'].includes(hs.trang_thai)) {
    return h('section', { class: 'the' }, h('h2', null, 'Tiền'),
      h('p', { class: 'goi-y' }, 'Hồ sơ bảo hành: làm lại miễn phí, không thu tiền, không tính doanh thu.'),
      api.duocXem('giam_doc', 'quan_ly', 'ke_toan') && giaVon ? d('Phụ tùng, vật tư đã xuất (giá vốn bảo hành)', giaVon, true) : null);
  }
  const huy = hs.trang_thai === 'huy';
  const dangGiu = huy ? Math.max(0, Number(hs.da_thu_khach) || 0) : Math.max(0, -Number(hs.con_no_khach) || 0);
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
    // 043 (khớp máy chủ): hồ sơ hủy giữ toàn bộ số khách đã trả; hồ sơ khác giữ phần trả dư
    dangGiu > 0 ? d(huy ? 'Đang giữ tiền của khách – cần trả lại' : hs.giao_luc ? 'Khách trả dư – cần trả lại' : 'Khách đã cọc / ứng trước', dangGiu, true)
      : d('Khách còn nợ', huy ? 0 : hs.con_no_khach, true),
    dangGiu > 0 ? h('p', { class: 'goi-y' }, hs.giao_luc || huy
      ? (huy ? 'Hồ sơ đã hủy còn giữ tiền của khách – trả lại khách: ' : 'Hồ sơ chưa đóng khi còn tiền dư. Trả lại khách: ')
        + 'lập Đề nghị chi, mục "Trả lại cọc cho khách", chọn xe này (phần mềm điền sẵn số tối đa được trả). Khách cho thợ: kế toán lập phiếu thu "Tiền bo của khách" rồi hủy phần dư ở phiếu đã thu.'
      : 'Tiền cọc sẽ trừ vào phần khách trả khi giao xe.') : null,
    dangGiu > 0 && (hs.giao_luc || huy) && api.laNhanVien()
      ? h('div', { class: 'hang-nut' }, h('a', { class: 'nut nho', 'data-tra-coc': '',
        href: `#/de-nghi?lap=1&muc=${encodeURIComponent('Trả lại cọc cho khách')}&ho_so=${hs.id}&nd=${encodeURIComponent(`Trả lại tiền ${huy ? 'cọc' : 'dư'} – ${hs.bien_so_hien_thi || hs.ma}`)}&nhan=${encodeURIComponent(hs.ten_khach || '')}` },
        'Lập đề nghị chi trả lại khách')) : null,
    // Giá vốn phụ tùng, vật tư đã xuất cho xe và lãi gộp (doanh thu sau VAT − giá vốn)
    api.duocXem('giam_doc', 'quan_ly', 'ke_toan') && (giaVon || Number(hs.bh_duyet) || Number(hs.khach_duyet)) ? [h('hr'),
      d('Phụ tùng, vật tư đã xuất (giá vốn)', giaVon),
      d('Lãi gộp', Number(hs.bh_duyet) + Number(hs.khach_duyet) - Number(hs.giam_gia || 0) - giaVon, true)] : null,
    khoiDieuChinh(dc, ve),
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
  // 055: chỉ chọn được bước còn mở (hồ sơ đã qua bước thì ảnh bước đó khóa); quản lý chung / giám đốc thấy cả bước đã
  // khóa (ghi "đã khóa"), chọn thì phải ghi lý do trước khi tải
  const moKhoa = duocMoKhoa();
  const dsBuoc = Object.entries(BUOC_TEP).map(([value, label]) => ({ value, label, mo: buocTepMo(hs, value, tep) }))
    .filter((b) => b.mo || moKhoa)
    .map((b) => ({ value: b.value, label: b.mo ? b.label : `${b.label} (đã khóa)` }));
  const goiYBuoc = { tiep_nhan: 'tiep_nhan', bao_gia: 'duyet_gia', da_duyet: 'lenh_sua_chua', dang_sua: 'phat_sinh', cho_detailing: 'kcs', cho_kcs: 'kcs', dat_kcs: 'giao_xe', da_giao: 'ho_so_bh', da_gui_hs: 'ho_so_bh' }[hs.trang_thai];
  const chonBuoc = oChon('buoc', dsBuoc, buocTepMo(hs, goiYBuoc, tep) ? goiYBuoc : 'khac', { trong: null, 'aria-label': 'Ảnh của bước' });
  const oTep = h('input', { type: 'file', accept: 'image/*,application/pdf', multiple: true, 'aria-label': 'Chọn ảnh hoặc tệp' });
  const dangTai = h('small', { class: 'goi-y', role: 'status', 'aria-live': 'polite' });
  const taiLen = async (ds, buoc, lyDo) => {
    oTep.disabled = true; chonBuoc.disabled = true; dangTai.textContent = `Đang tải 0/${ds.length}…`;
    const kq = await api.taiNhieu(ds, buoc, (f, goc) => api.taiTep(hs, buoc, f, goc.type === 'application/pdf' ? 'bien_ban' : 'anh', lyDo),
      { tienDo: (n, t) => { dangTai.textContent = `Đang tải ${n}/${t}…`; } });
    oTep.value = ''; oTep.disabled = false; chonBuoc.disabled = false; dangTai.textContent = '';
    for (const x of kq.loi) toast(`Không tải được ${x.ten}: ${x.e?.message || x.e}`, 'loi');
    if (kq.xong) { toast(`Đã tải ${kq.xong} tệp.`); ve(); }
  };
  oTep.addEventListener('change', async () => {
    const ds = [...oTep.files]; const buoc = chonBuoc.value;
    if (!ds.length) return;
    if (!buocTepMo(hs, buoc, tep)) {
      hoiLyDoMoKhoa((BUOC_TEP[buoc] || buoc).toLowerCase(), (lyDo) => { taiLen(ds, buoc, lyDo); });
      oTep.value = '';
      return;
    }
    await taiLen(ds, buoc, null);
  });
  return h('section', { class: 'the' }, h('h2', null, `Ảnh & giấy tờ (${tep.length})`),
    !api.laCoDong() && (!['dong', 'huy'].includes(hs.trang_thai) || q('ke_toan', 'giam_doc'))
      ? h('div', { class: 'tai-tep' }, chonBuoc, h('label', { class: 'nut noi-bat' }, 'Tải ảnh / tệp', oTep), dangTai) : null,
    tep.length ? luoi : h('p', { class: 'trong' }, 'Chưa có ảnh.'));
}

// 054: thông báo đã gửi cho từng người về hồ sơ này – hồ sơ ghi AI nhận LÚC NÀO (người nhận bấm "Đã nhận" ở khung giữa màn hình)
function theThongBao({ tb }) {
  if (!tb.length) return null;
  const chua = tb.filter((n) => !n.da_nhan_luc).length;
  return h('details', { class: 'the the-thong-bao', open: chua > 0 || tb.length <= 8 },
    h('summary', null, h('h2', null, `Thông báo đã gửi (${tb.length})`),
      chua ? h('span', { class: 'nhan tb-chua' }, `${chua} chưa nhận`) : h('span', { class: 'nhan tt-tot' }, 'Đã nhận hết')),
    h('ul', { class: 'tb-ho-so' }, tb.map((n) => {
      const { chu } = tachTieuDe(n.tieu_de);
      return h('li', { class: n.da_nhan_luc ? 'da-nhan' : 'chua-nhan', 'data-tb-id': n.id },
        h('div', { class: 'tb-hs-nguoi' },
          chipNguoi(n.ho_ten, { vai: vaiChinh(n.vai_tro || []), gon: true }),
          h('small', null, TEN_LOAI[n.loai] || '')),
        h('div', { class: 'tb-hs-nd' }, h('b', null, chu),
          n.chi_tiet?.length ? h('small', null, n.chi_tiet.join('; ')) : null,
          h('small', null, `Gửi lúc ${gioBao(n.tao_luc)}${n.cap_nhat_luc && n.cap_nhat_luc !== n.tao_luc && !n.da_nhan_luc ? ` · cập nhật ${gioBao(n.cap_nhat_luc)}` : ''}`)),
        n.da_nhan_luc ? h('span', { class: 'nhan tt-tot' }, `Đã nhận ${gioBao(n.da_nhan_luc)}`) : h('span', { class: 'nhan tb-chua' }, 'Chưa nhận'));
    })));
}

function theNhatKy({ nk }) {
  const ten = (id) => (api.dm.nhan_vien || []).find((n) => n.id === id)?.ho_ten || '';
  return h('details', { class: 'the' }, h('summary', null, h('h2', null, `Nhật ký (${nk.length})`)),
    h('ul', { class: 'nhat-ky' }, nk.map((n) => h('li', null, h('small', null, ngayGio(n.luc), ' · ', ten(n.boi)), h('div', null, n.ghi_chu || TRANG_THAI[n.sang_trang_thai])))));
}

// 056: giám đốc hủy hồ sơ ở bất kỳ bước nào – lý do, doanh thu theo giá thương lượng với khách, vật tư chưa dùng trả về kho
async function moHuyGiamDoc(hs) {
  const px = await api.doc('v_phieu_xuat', (q2) => q2.eq('ho_so_id', hs.id).eq('trang_thai', 'hieu_luc').eq('loai', 'cho_xe')).catch(() => []);
  const dongs = px.length ? await api.doc('phieu_xuat_dong', (q2) => q2.in('phieu_id', px.map((p) => p.id)).order('id')).catch(() => []) : [];
  const hang = dongs.length ? await api.doc('hang_kho', (q2) => q2.in('id', [...new Set(dongs.map((d) => d.hang_id))]), 'id,ma,ten,dvt').catch(() => []) : [];
  const tenHang = (id) => hang.find((x) => x.id === id) || { ten: `Mã ${id}`, dvt: '' };
  const phaiThu = Number(hs.phai_thu_khach || 0) + Number(hs.phai_thu_bh || 0);
  const oLyDo = oVung('ly_do', '', { rows: 2, placeholder: 'Ví dụ: khách không sửa tiếp, lấy xe về' });
  const oDoanhThu = oTien('doanh_thu', 0, { 'aria-label': 'Doanh thu theo giá thương lượng' });
  const oTra = dongs.map((d) => {
    const hk = tenHang(d.hang_id);
    const o = h('input', { type: 'number', min: 0, max: Number(d.so_luong), step: 'any', value: 0, class: 'o-so', 'data-tra-kho': d.id, 'aria-label': `Số ${hk.ten} trả về kho` });
    return { d, o, el: h('tr', null, h('td', { 'data-nhan': 'Vật tư' }, `${hk.ma ? hk.ma + ' – ' : ''}${hk.ten}`),
      h('td', { class: 'so', 'data-nhan': 'Đã xuất' }, `${Number(d.so_luong)} ${hk.dvt || ''}`), h('td', { 'data-nhan': 'Chưa dùng – trả kho' }, o)) };
  });
  const noiDung = h('form', { onsubmit: (e) => e.preventDefault() },
    h('p', null, 'Hủy được ở mọi bước. Hồ sơ vẫn giữ trong dữ liệu, ghi rõ lý do và người hủy.'),
    truong('Lý do hủy', oLyDo, null, { batBuoc: true, rong: true }),
    truong('Doanh thu tính cho khách (giá thương lượng, gồm VAT)', oDoanhThu,
      `0 đ = không tính doanh thu (khách đã trả thì phải trả lại). Lớn hơn 0: khách trả đúng số này, hồ sơ chuyển "Đã giao", thu đủ tự đóng.${phaiThu ? ` Hiện phải thu ${tien(phaiThu)} đ.` : ''}`, { batBuoc: true }),
    dongs.length ? h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Vật tư đã xuất cho xe'),
      h('p', { class: 'goi-y' }, 'Ghi số CHƯA DÙNG để trả về kho; phần đã dùng vẫn tính chi phí (giá vốn) của xe.'),
      h('div', { class: 'bang-cuon' }, h('table', { class: 'bang gon' },
        h('thead', null, h('tr', null, h('th', null, 'Vật tư'), h('th', { class: 'so' }, 'Đã xuất'), h('th', null, 'Chưa dùng – trả kho'))),
        h('tbody', null, oTra.map((x) => x.el))))) : h('p', { class: 'goi-y' }, 'Xe chưa xuất vật tư nào.'));
  moModal('Hủy hồ sơ (giám đốc)', noiDung, {
    rong: true, nhanNut: 'Hủy hồ sơ',
    nutChinh: async () => {
      const lyDo = oLyDo.value.trim();
      if (!lyDo) { toast('Ghi lý do hủy.', 'loi'); oLyDo.focus(); return false; }
      const dt = docTien(oDoanhThu.value) || 0;
      const traKho = [];
      for (const x of oTra) {
        const sl = Number(x.o.value || 0);
        if (sl < 0 || sl > Number(x.d.so_luong)) { toast(`Số trả kho của ${tenHang(x.d.hang_id).ten} phải từ 0 đến ${Number(x.d.so_luong)}.`, 'loi'); x.o.focus(); return false; }
        if (sl > 0) traKho.push({ dong_id: x.d.id, so_luong: sl });
      }
      const kq = await chay((boQua) => api.huyHoSoGiamDoc(hs.id, lyDo, dt, traKho, boQua));
      toast(kq?.trang_thai === 'huy' ? 'Đã hủy hồ sơ (không tính doanh thu).' : `Đã hủy hồ sơ – thu theo thỏa thuận ${tien(dt)} đ.`);
      veDanhSachHoSo(hs);
    },
  });
}

function moHuy(hs) {
  // 041: hồ sơ đã thu cọc → máy chủ hỏi lại (chay hiện hộp xác nhận), hủy xong Việc hôm nay nhắc trả cọc
  hoiLyDo('Hủy hồ sơ', async (lyDo) => { await chay((boQua) => api.huyHoSo(hs.id, lyDo, boQua)); toast('Đã hủy hồ sơ.'); veDanhSachHoSo(hs); },
    { nhan: 'Lý do hủy', goiY: 'Ví dụ: khách không sửa, bảo hiểm từ chối. Nếu đã thu cọc, lập đề nghị chi "Trả lại cọc cho khách".', nhanNut: 'Hủy hồ sơ' });
}
