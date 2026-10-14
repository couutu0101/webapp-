// Thiết bị đồ nghề – một thẻ trong trang Kho: máy móc, đồ nghề giao cho các nhóm (028_tai_san.sql, 029)
//  - Mỗi nhóm một thẻ: 3 tổ + Dùng chung xưởng + Văn phòng. Trưởng nhóm chỉ thấy nhóm của tổ mình.
//  - Giám đốc, quản lý chung, kho: thêm, sửa, giao, chuyển nhóm, thanh lý. Người phụ trách nhóm xác nhận đã nhận.
//  - Kiểm tra chống mất mỗi tuần (người phụ trách nhóm), kiểm kê mỗi tháng (quản lý chung / kế toán + người cùng kiểm, có biên bản).
//  - Thiếu / hỏng → sự cố chờ xử lý (giám đốc, quản lý chung); người chịu + tiền bồi thường chỉ giám đốc ghi; kế toán đánh dấu đã trừ.
//  - Bảo dưỡng theo thời gian: mỗi máy một hoặc nhiều việc, chu kỳ; ghi lần làm, thuê ngoài thì lập đề nghị chi.
import {
  h, tien, ngay, ngayGio, homNay, truong, oChu, oTien, oChon, oNgay, oVung, oCheck, oChonTep, docForm, chay, bang, moModal, toast, dat, nhoPhien, chipNguoi, vaiChinh, nenAnh, cuonTheChon, hoiLyDo,
} from '../ui.js';
import * as api from '../api.js';
import { taiFileExcel } from '../excel.js';
import { nutXuatExcel } from './xuat-excel.js';

const TINH_TRANG = { tot: 'Tốt', hong: 'Hỏng', dang_sua: 'Đang sửa', mat: 'Đã mất', thanh_ly: 'Đã thanh lý' };
const LOAI = { may_moc: 'Thiết bị – máy móc', dung_cu: 'Đồ nghề – dụng cụ' };
const KET_QUA = { tim_thay: 'Đã tìm thấy', ghi_mat: 'Ghi mất', dua_sua: 'Đưa đi sửa', da_sua: 'Đã sửa xong', thanh_ly: 'Thanh lý' };
const CHU_KY = [[7, 'Mỗi tuần'], [14, '2 tuần một lần'], [30, 'Mỗi tháng'], [60, '2 tháng một lần'], [90, '3 tháng một lần'], [180, '6 tháng một lần'], [365, 'Mỗi năm']];
const tenChuKy = (n) => (CHU_KY.find(([d]) => d === Number(n)) || [0, `Mỗi ${n} ngày`])[1];
const cuoiNgay = (d) => (d ? new Date(`${String(d).slice(0, 10)}T23:59:59`) : null);
const hai = (x) => String(x).padStart(2, '0');
const isoNgay = (d) => `${d.getFullYear()}-${hai(d.getMonth() + 1)}-${hai(d.getDate())}`;   // theo giờ máy, không lệch múi giờ
const congNgay = (iso, so) => { const d = new Date(`${String(iso).slice(0, 10)}T00:00:00`); d.setDate(d.getDate() + Number(so)); return isoNgay(d); };
// Hạn theo ngày (kiểm tra, kiểm kê, bảo dưỡng): đếm theo lịch, không theo giờ
const soNgayToi = (d) => Math.round((new Date(`${String(d).slice(0, 10)}T00:00:00`) - new Date(`${homNay()}T00:00:00`)) / 864e5);
const hanVien = (d, lop = '') => {
  if (!d) return null;
  const so = soNgayToi(d);
  const chu = so < 0 ? `Quá hạn ${-so} ngày` : so === 0 ? 'Hạn hôm nay' : so === 1 ? 'Hạn ngày mai' : `Còn ${so} ngày`;
  return h('span', { class: `han ${so < 0 ? 'qua' : so <= 1 ? 'sap' : ''} ${lop}`.trim(), title: `Hạn ${ngay(d)}` }, chu);
};
const so0 = (x) => h('span', { class: 'so-0' }, x);
const nhanTinhTrang = (tt) => h('span', { class: `nhan ts-${tt}` }, TINH_TRANG[tt] || tt);
// Trưởng nhóm không tải danh sách nhân viên: tự nhận ra mình, người khác dùng tên đã lưu kèm (nếu có)
const tenNv = (id) => (id && api.toi?.id === id ? api.toi : (api.dm.nhan_vien || []).find((n) => n.id === id));
const chipNv = (id, tenLuu = null) => { const nv = tenNv(id); return nv ? chipNguoi(nv.ho_ten, { vai: vaiChinh(nv.vai_tro), nho: true }) : tenLuu ? chipNguoi(tenLuu, { nho: true }) : null; };

// ---------- Quyền (máy chủ kiểm lại) ----------
const quanLy = () => api.coVaiTro('giam_doc', 'quan_ly', 'kho');           // thêm, sửa, giao, chuyển nhóm, thanh lý
const xuLySuCo = () => api.coVaiTro('giam_doc', 'quan_ly');
const kiemKe = () => api.coVaiTro('giam_doc', 'quan_ly', 'ke_toan');
const xemGiaTri = () => api.duocXem('giam_doc', 'quan_ly', 'ke_toan', 'kho');
const phuTrach = (n) => api.coVaiTro('giam_doc', 'quan_ly')
  || (n.to_id ? api.coVaiTro('truong_nhom') && api.toi.to_id === n.to_id : (n.vai_phu_trach || []).some((v) => api.coVaiTro(v)));
const ghiBaoDuongDuoc = (n) => phuTrach(n) || api.coVaiTro('kho');
// Người phụ trách nhóm: trưởng nhóm tổ / những người có vai trò phụ trách
function nguoiPhuTrach(n) {
  const nguon = api.dm.nhan_vien?.length ? api.dm.nhan_vien : [api.toi].filter(Boolean);
  const ds = nguon.filter((x) => x.hoat_dong && (n.to_id ? x.vai_tro.includes('truong_nhom') && x.to_id === n.to_id
    : x.vai_tro.some((v) => (n.vai_phu_trach || []).includes(v))));
  return ds;
}

// Vẽ thẻ "Thiết bị đồ nghề" của trang Kho: el = vùng nội dung của thẻ, nut = hàng nút trên tiêu đề trang Kho
export default async function veThietBi(el, nut = null) {
  const cn = api.toi.chi_nhanh_id;
  let nhom = []; let suCo = [];
  let the = nhoPhien.doc('ts_the');
  let hienCu = false;
  const vungTabs = h('div', { class: 'tabs nho tb-nhom', role: 'tablist', 'aria-label': 'Nhóm' });
  const vung = h('div');
  if (nut) {
    if (quanLy()) nut.append(h('button', { class: 'nut chinh', type: 'button', onclick: () => moLuuTaiSan(null, the !== 'tong' ? the : null) }, '+ Thiết bị, đồ nghề'));
    const nutExcel = nutXuatExcel('Xuất Excel', xuatExcel);
    if (nutExcel) nut.append(nutExcel);
  }
  dat(el, h('p', { class: 'mo-ta tb-gioi-thieu' }, 'Máy móc, đồ nghề giao cho từng nhóm: kiểm tra mỗi tuần, kiểm kê mỗi tháng, lịch bảo dưỡng máy.'), vungTabs, vung);

  async function taiLai() {
    [nhom, suCo] = await Promise.all([
      api.doc('v_nhom_tai_san', (q) => q.eq('chi_nhanh_id', cn).order('thu_tu')),
      api.doc('su_co_tai_san', (q) => q.eq('chi_nhanh_id', cn).order('phat_hien_luc', { ascending: false }).limit(400)).catch(() => []),
    ]);
    const coTong = nhom.length > 1;
    const cacThe = [...(coTong ? [{ ma: 'tong', nhan: 'Tổng hợp' }] : []),
      ...nhom.map((n) => ({ ma: n.nhom_id, nhan: n.ten, so: Number(n.so_tai_san), canh: Number(n.so_su_co) > 0 || quaHanNgay(n.han_kiem_tra) || quaHanNgay(n.han_kiem_ke) }))];
    if (!cacThe.some((t) => t.ma === the)) the = cacThe[0]?.ma || null;
    dat(vungTabs, cacThe.map((t) => h('button', { type: 'button', role: 'tab', 'aria-selected': String(t.ma === the), 'data-the': t.ma,
      onclick: () => { the = t.ma; nhoPhien.ghi('ts_the', the); taiLai(); } },
      t.nhan, t.so !== undefined ? h('small', { class: 'so-the' }, ` ${t.so}`) : null, t.canh ? h('i', { class: 'cham-canh', 'aria-label': 'có việc quá hạn hoặc chờ xử lý' }) : null)));
    cuonTheChon(vungTabs);
    if (!the) { dat(vung, h('p', { class: 'trong' }, 'Chưa có nhóm nào anh/chị được xem.')); return; }
    if (the === 'tong') await veTong();
    else await veNhom(nhom.find((n) => n.nhom_id === the));
  }
  const quaHanNgay = (d) => d && cuoiNgay(d) < new Date();

  // ---------------- Tổng hợp ----------------
  async function veTong() {
    const [baoDuong] = await Promise.all([
      api.doc('v_tai_san', (q) => q.eq('chi_nhanh_id', cn).lte('han_bao_duong', ngayCong(30)).order('han_bao_duong')).catch(() => []),
    ]);
    const choXuLy = suCo.filter((s) => s.trang_thai === 'cho_xu_ly');
    const boiThuong = suCo.filter((s) => Number(s.boi_thuong) > 0);
    const taiSanCua = await layTaiSan([...new Set([...choXuLy, ...boiThuong].map((s) => s.tai_san_id))]);
    const tongGiaTri = nhom.reduce((s, n) => s + Number(n.gia_tri || 0), 0);
    dat(vung,
      h('section', { class: 'the' }, h('h2', null, 'Các nhóm'),
        // Ô bằng 0 / nhóm chưa có món nào gắn lớp so-0: máy tính hiện mờ, điện thoại ẩn cho thẻ gọn
        h('div', { class: 'bang-nhom-ts' }, bang([
          { nhan: 'Nhóm', lay: (n) => h('span', { class: 'ten-nhom-ts' }, h('b', null, n.ten), h('small', null, phuTrachText(n))) },
          { nhan: 'Số món', so: true, lay: (n) => (Number(n.so_tai_san) ? n.so_tai_san : h('span', { class: 'mo' }, '0')) },
          xemGiaTri() ? { nhan: 'Giá trị', so: true, lay: (n) => (Number(n.gia_tri) ? tien(n.gia_tri) : so0('0')) } : null,
          { nhan: 'Kiểm tra tuần', lay: (n) => (Number(n.so_tai_san) ? oHan(n.kiem_tra_cuoi, n.han_kiem_tra) : so0('—')) },
          { nhan: 'Kiểm kê tháng', lay: (n) => (Number(n.so_tai_san) ? oHan(n.kiem_ke_cuoi, n.han_kiem_ke) : so0('—')) },
          { nhan: 'Bảo dưỡng tới hạn', so: true, lay: (n) => (Number(n.so_bao_duong_toi_han) ? h('b', { class: 'chu-cam' }, n.so_bao_duong_toi_han) : so0('0')) },
          { nhan: 'Thiếu / hỏng', so: true, lay: (n) => (Number(n.so_su_co) ? h('b', { class: 'chu-loi' }, n.so_su_co) : so0('0')) },
          { nhan: 'Chờ nhận', so: true, lay: (n) => (Number(n.so_cho_nhan) ? h('b', null, n.so_cho_nhan) : so0('0')) },
        ].filter(Boolean), nhom, { onRow: (n) => { the = n.nhom_id; nhoPhien.ghi('ts_the', the); taiLai(); } })),
        xemGiaTri() ? h('p', { class: 'mo-ta' }, `Tổng giá trị thiết bị, đồ nghề đang dùng: ${tien(tongGiaTri)} đ (giá mua, chỉ để quản lý – chi phí mua đã tính vào tháng mua).`) : null),
      h('section', { class: 'the' }, h('h2', null, `Thiếu / hỏng chờ xử lý (${choXuLy.length})`),
        bang([
          { nhan: 'Phát hiện', lay: (s) => h('span', null, ngay(s.phat_hien_luc), h('br'), chipNv(s.phat_hien_boi)) },
          { nhan: 'Thiết bị, đồ nghề', lay: (s) => oTenTaiSan(taiSanCua[s.tai_san_id]) },
          { nhan: 'Sự cố', lay: (s) => h('span', null, h('span', { class: `nhan ${s.loai === 'mat' ? 'ts-mat-cho' : 'ts-hong'}` }, s.loai === 'mat' ? `Thiếu ${s.so_luong}` : `Hỏng ${s.so_luong}`), h('br'), h('small', null, s.mo_ta || '')) },
          xuLySuCo() ? { nhan: '', lay: (s) => h('button', { class: 'nut nho chinh', type: 'button', onclick: (e) => { e.stopPropagation(); moXuLySuCo(s, taiSanCua[s.tai_san_id]); } }, 'Xử lý') } : null,
        ].filter(Boolean), choXuLy, { trong: 'Không có món nào thiếu hoặc hỏng đang chờ xử lý.' })),
      boiThuong.length ? h('section', { class: 'the' }, h('h2', null, 'Bồi thường'),
        h('p', { class: 'goi-y' }, 'Giám đốc ghi người chịu và số tiền khi xử lý sự cố. Kế toán trừ lương / thu xong thì đánh dấu "Đã trừ".'),
        bang([
          { nhan: 'Ngày', lay: (s) => ngay(s.xu_ly_luc || s.phat_hien_luc) },
          { nhan: 'Người chịu', lay: (s) => (s.nguoi_chiu ? chipNv(s.nguoi_chiu) || s.nguoi_chiu_ten : s.nguoi_chiu_ten) },
          { nhan: 'Thiết bị, đồ nghề', lay: (s) => oTenTaiSan(taiSanCua[s.tai_san_id]) },
          { nhan: 'Số tiền', so: true, lay: (s) => h('b', null, tien(s.boi_thuong)) },
          { nhan: 'Trạng thái', lay: (s) => (api.coVaiTro('giam_doc', 'ke_toan')
            ? h('label', { class: 'o-check' }, h('input', { type: 'checkbox', checked: s.da_tru, 'data-boi-thuong': s.id,
              onchange: (e) => chay(() => api.danhDauBoiThuong(s.id, e.target.checked), { thanhCong: e.target.checked ? 'Đã đánh dấu đã trừ.' : 'Đã bỏ đánh dấu.' }).then(taiLai, taiLai) }), 'Đã trừ')
            : h('span', { class: `nhan ${s.da_tru ? 'ts-tot' : 'ts-hong'}` }, s.da_tru ? 'Đã trừ' : 'Chưa trừ')) },
        ], boiThuong)) : null,
      h('section', { class: 'the' }, h('h2', null, 'Bảo dưỡng trong 30 ngày tới'),
        bang([
          { nhan: 'Hạn', lay: (t) => hanVien(t.han_bao_duong) },
          { nhan: 'Máy', lay: (t) => oTenTaiSan(t) },
          { nhan: 'Nhóm', lay: (t) => t.nhom_ten },
          { nhan: 'Tình trạng', lay: (t) => nhanTinhTrang(t.tinh_trang) },
        ], baoDuong.filter((t) => t.dang_dung), { trong: 'Không có máy nào tới hạn bảo dưỡng trong 30 ngày.',
          onRow: (t) => moChiTiet(t, nhom.find((n) => n.nhom_id === t.nhom_id)) })));
  }

  // ---------------- Một nhóm ----------------
  async function veNhom(n) {
    const [ds, dsKiem] = await Promise.all([
      api.doc('v_tai_san', (q) => q.eq('chi_nhanh_id', cn).eq('nhom_id', n.nhom_id).order('ma')),
      api.doc('kiem_tra_tai_san', (q) => q.eq('chi_nhanh_id', cn).eq('nhom_id', n.nhom_id).order('tao_luc', { ascending: false }).limit(24)),
    ]);
    const dangDung = ds.filter((t) => t.dang_dung);
    const choNhan = dangDung.filter((t) => t.cho_nhan);
    const oTim = h('input', { type: 'search', placeholder: 'Tìm tên, mã, serial…', 'aria-label': 'Tìm thiết bị, đồ nghề' });
    const oCu = oCheck('hien_cu', hienCu, 'Hiện cả món đã mất / thanh lý');
    const ketQua = h('div');
    const veBang = () => {
      const tu = oTim.value.trim().toLowerCase();
      const loc = ds.filter((t) => (hienCu || t.dang_dung) && (!tu || [t.ten, t.ma, t.so_serial, t.hang_model, t.vi_tri].some((x) => (x || '').toLowerCase().includes(tu))));
      dat(ketQua, bang([
        { nhan: 'Mã', lay: (t) => h('b', { class: 'ma-ts' }, t.ma) },
        { nhan: 'Tên', lay: (t) => h('span', { class: 'ten-ts' }, h('span', null, t.ten,
          t.cho_nhan && t.dang_dung ? h('span', { class: 'nhan ts-cho-nhan' }, 'Chờ nhận') : null,
          Number(t.su_co_mo) ? h('span', { class: 'nhan ts-hong' }, `${t.su_co_mo} sự cố`) : null),
          h('small', null, [t.hang_model, t.so_serial ? `Serial ${t.so_serial}` : null, t.vi_tri].filter(Boolean).join(' · '))) },
        { nhan: 'Loại', lay: (t) => h('span', { class: 'loai-ts' }, t.loai === 'may_moc' ? 'Thiết bị' : 'Đồ nghề') },
        { nhan: 'Số lượng', so: true, lay: (t) => `${t.so_luong} ${t.don_vi}` },
        { nhan: 'Tình trạng', lay: (t) => nhanTinhTrang(t.tinh_trang) },
        { nhan: 'Bảo dưỡng', lay: (t) => (t.han_bao_duong && t.dang_dung ? hanVien(t.han_bao_duong, 'nho') : h('span', { class: 'mo' }, '—')) },
        { nhan: 'Kiểm gần nhất', lay: (t) => (t.kiem_tra_cuoi ? ngay(t.kiem_tra_cuoi) : h('span', { class: 'mo' }, 'Chưa')) },
        xemGiaTri() ? { nhan: 'Giá trị', so: true, lay: (t) => tien(t.gia_tri) || '0' } : null,
      ].filter(Boolean), loc, { onRow: (t) => moChiTiet(t, n), idDong: (t) => t.id, trong: ds.length ? 'Không có món nào khớp.' : 'Nhóm chưa có thiết bị, đồ nghề nào.' }),
      h('p', { class: 'mo-ta' }, `${loc.length} món${xemGiaTri() ? ` · giá trị ${tien(loc.filter((t) => t.dang_dung).reduce((s, t) => s + Number(t.gia_tri || 0), 0))} đ` : ''}`));
    };
    oTim.addEventListener('input', veBang);
    oCu.querySelector('input').addEventListener('change', (e) => { hienCu = e.target.checked; veBang(); });

    dat(vung,
      h('section', { class: 'luoi-dem tien ts-dem', 'aria-label': `Tình hình nhóm ${n.ten}` },
        h('div', { class: 'o-dem' }, h('b', null, n.so_tai_san), h('span', null, 'Món đang dùng'),
          xemGiaTri() ? h('span', { class: 'o-dem-phu' }, `Giá trị ${tien(n.gia_tri) || 0} đ`) : null),
        oDemHan('Kiểm tra tuần', n.kiem_tra_cuoi, n.so_tai_san > 0 ? n.han_kiem_tra : null, 'data-kiem-tra'),
        oDemHan('Kiểm kê tháng', n.kiem_ke_cuoi, n.so_tai_san > 0 ? n.han_kiem_ke : null, 'data-kiem-ke'),
        h('div', { class: `o-dem ${Number(n.so_bao_duong_toi_han) ? 'canh-bao-cam' : 'mo'}` }, h('b', null, n.so_bao_duong_toi_han), h('span', null, 'Bảo dưỡng tới hạn')),
        h('div', { class: `o-dem ${Number(n.so_su_co) ? 'canh-bao' : 'mo'}` }, h('b', null, n.so_su_co), h('span', null, 'Thiếu / hỏng chờ xử lý'))),
      choNhan.length && phuTrach(n) ? h('div', { class: 'thong-bao canh-bao ts-cho-nhan-bao' },
        h('span', null, h('b', null, `${choNhan.length} món mới giao`), ' cho nhóm, anh/chị kiểm lại rồi bấm xác nhận đã nhận.'),
        h('button', { class: 'nut nho chinh', type: 'button', onclick: () => moXacNhanNhan(n, choNhan) }, 'Xác nhận đã nhận')) : null,
      h('section', { class: 'the' },
        h('div', { class: 'the-dau' }, h('div', null, h('h2', null, n.ten), h('p', { class: 'mo-ta ts-phu-trach' }, 'Phụ trách: ', phuTrachChips(n))),
          h('div', { class: 'hang-nut' },
            phuTrach(n) && dangDung.length ? h('button', { class: 'nut chinh', type: 'button', 'data-mo-kiem-tra': '', onclick: () => moKiemTra(n, 'kiem_tra', ds) }, 'Kiểm tra tuần') : null,
            kiemKe() && dangDung.length ? h('button', { class: 'nut', type: 'button', 'data-mo-kiem-ke': '', onclick: () => moKiemTra(n, 'kiem_ke', ds) }, 'Kiểm kê tháng') : null)),
        h('div', { class: 'thanh-loc ts-loc' }, oTim, oCu), ketQua),
      dsKiem.length ? h('details', { class: 'the' }, h('summary', null, h('h2', null, `Các lần kiểm tra, kiểm kê (${dsKiem.length})`)),
        bang([
          { nhan: 'Ngày', lay: (k) => ngay(k.ngay) },
          { nhan: 'Loại', lay: (k) => (k.loai === 'kiem_ke' ? 'Kiểm kê tháng' : 'Kiểm tra tuần') },
          { nhan: 'Người kiểm', lay: (k) => h('span', null, chipNv(k.nguoi_kiem, k.nguoi_kiem_ten), k.cung_kiem ? h('small', null, ` cùng ${k.cung_kiem}`) : null) },
          { nhan: 'Kết quả', lay: (k) => (Number(k.so_thieu) || Number(k.so_hong)
            ? h('span', null, Number(k.so_thieu) ? h('span', { class: 'nhan ts-mat-cho' }, `Thiếu ${k.so_thieu} món`) : null, Number(k.so_hong) ? h('span', { class: 'nhan ts-hong' }, `Hỏng ${k.so_hong} món`) : null)
            : h('span', { class: 'nhan ts-tot' }, `Đủ ${k.so_dong} món`)) },
          { nhan: '', lay: (k) => h('button', { class: 'nut nho', type: 'button', onclick: (e) => { e.stopPropagation(); moBienBan(k, n); } }, k.loai === 'kiem_ke' ? 'Biên bản' : 'Xem') },
        ], dsKiem)) : null);
    veBang();
  }

  // ---------------- Chi tiết một món ----------------
  async function moChiTiet(t0, n) {
    const [[t], lich, bd, sc, ls] = await Promise.all([
      api.doc('v_tai_san', (q) => q.eq('id', t0.id)),
      api.doc('lich_bao_duong', (q) => q.eq('tai_san_id', t0.id).order('id')),
      api.doc('bao_duong_tai_san', (q) => q.eq('tai_san_id', t0.id).order('ngay', { ascending: false }).limit(50)),
      api.doc('su_co_tai_san', (q) => q.eq('tai_san_id', t0.id).order('phat_hien_luc', { ascending: false })),
      api.doc('tai_san_lich_su', (q) => q.eq('tai_san_id', t0.id).order('luc', { ascending: false }).limit(60)),
    ]);
    if (!t) return toast('Không tìm thấy món này.', 'loi');
    n = n || nhom.find((x) => x.nhom_id === t.nhom_id) || { nhom_id: t.nhom_id, ten: t.nhom_ten, to_id: t.to_id, vai_phu_trach: [] };
    const conDung = t.dang_dung;
    let dong = null;
    const lam = (fn) => () => { dong?.(); fn(); };
    const nut = (nhan, fn, chinh = false) => h('button', { class: `nut nho${chinh ? ' chinh' : ''}`, type: 'button', onclick: lam(fn) }, nhan);
    const anh = h('div', { class: 'ts-anh' }, h('span', { class: 'mo' }, 'Chưa có ảnh'));
    if (t.anh) api.linkTepNhieu([t.anh]).then((l) => { const u = l[t.anh]; if (u?.nho) dat(anh, h('a', { href: u.lon, target: '_blank', rel: 'noopener' }, h('img', { src: u.nho, alt: t.ten }))); }).catch(() => {});
    const dongTT = (nhan, gt) => (gt === null || gt === undefined || gt === '' ? null : [h('dt', null, nhan), h('dd', null, gt)]);
    const lichDs = lich.filter((l) => l.hoat_dong);
    const noiDung = h('div', { class: 'ts-chi-tiet' },
      h('div', { class: 'ts-dau' }, anh,
        h('div', null,
          h('p', { class: 'ts-ma' }, t.ma, ' ', nhanTinhTrang(t.tinh_trang), t.cho_nhan && conDung ? h('span', { class: 'nhan ts-cho-nhan' }, 'Chờ nhận') : null),
          h('dl', { class: 'thong-tin' },
            dongTT('Nhóm', t.nhom_ten), dongTT('Loại', LOAI[t.loai]), dongTT('Số lượng', `${t.so_luong} ${t.don_vi}`),
            dongTT('Hãng / model', t.hang_model), dongTT('Số serial', t.so_serial), dongTT('Vị trí', t.vi_tri),
            xemGiaTri() ? dongTT('Giá mua', t.gia_mua ? `${tien(t.gia_mua)} đ / ${t.don_vi}` : null) : null,
            dongTT('Ngày mua', t.ngay_mua ? ngay(t.ngay_mua) : null),
            dongTT('Bảo hành đến', t.bao_hanh_den ? ngay(t.bao_hanh_den) : null),
            dongTT('Nhà cung cấp', t.nha_cung_cap_id ? api.dm.ten('nha_cung_cap', t.nha_cung_cap_id) : null),
            dongTT('Đã nhận', t.nhan_luc ? h('span', null, chipNv(t.nhan_boi), ` ${ngayGio(t.nhan_luc)}`) : null),
            dongTT('Ghi chú', t.ghi_chu)))),
      conDung ? h('div', { class: 'hang-nut ts-hanh-dong' },
        ghiBaoDuongDuoc(n) ? nut(t.tinh_trang === 'hong' || t.tinh_trang === 'dang_sua' ? 'Ghi sửa chữa' : 'Ghi bảo dưỡng / sửa', () => moGhiBaoDuong(t, lichDs, null), true) : null,
        ghiBaoDuongDuoc(n) ? nut('Báo mất / hỏng', () => moBaoSuCo(t)) : null,
        ghiBaoDuongDuoc(n) ? h('label', { class: 'nut nho' }, h('input', { type: 'file', accept: 'image/*', capture: 'environment',
          onchange: async (e) => { const f = e.target.files[0]; if (!f) return; dong?.();
            await chay(async () => api.taiAnhTaiSan(t, await nenAnh(f)), { thanhCong: 'Đã lưu ảnh.' }).catch(() => {}); taiLai(); } }), t.anh ? 'Đổi ảnh' : 'Chụp ảnh') : null,
        quanLy() ? nut('Sửa', () => moLuuTaiSan(t)) : null,
        quanLy() ? nut('Chuyển nhóm', () => moChuyenNhom(t)) : null,
        quanLy() ? nut('Thanh lý', () => moThanhLy(t)) : null) : null,
      t.loai === 'may_moc' || lich.length ? h('section', { class: 'ts-khoi' },
        h('div', { class: 'the-dau' }, h('h3', null, 'Lịch bảo dưỡng'),
          conDung && ghiBaoDuongDuoc(n) ? nut('+ Lịch bảo dưỡng', () => moLichBaoDuong(t, null)) : null),
        lich.length ? h('ul', { class: 'ds-lich-bd' }, lich.map((l) => {
          const han = l.hoat_dong ? congNgay(l.lan_cuoi || l.bat_dau, l.chu_ky_ngay) : null;
          return h('li', { class: l.hoat_dong ? null : 'tat' },
            h('span', { class: 'lich-ten' }, h('b', null, l.ten_viec), h('small', null, `${tenChuKy(l.chu_ky_ngay)} · lần gần nhất ${l.lan_cuoi ? ngay(l.lan_cuoi) : 'chưa làm'}${l.hoat_dong ? '' : ' · đã tắt'}`)),
            han ? hanVien(han, 'nho') : null,
            conDung && ghiBaoDuongDuoc(n) ? h('span', { class: 'hang-nut' },
              l.hoat_dong ? nut('Đã làm', () => moGhiBaoDuong(t, lichDs, l)) : null, nut('Sửa', () => moLichBaoDuong(t, l))) : null);
        })) : h('p', { class: 'trong' }, 'Chưa có lịch bảo dưỡng. Thêm việc định kỳ như thay dầu, vệ sinh, kiểm định.')) : null,
      bd.length ? h('section', { class: 'ts-khoi' }, h('h3', null, 'Bảo dưỡng, sửa chữa đã làm'),
        bang([
          { nhan: 'Ngày', lay: (b) => ngay(b.ngay) },
          { nhan: 'Việc', lay: (b) => h('span', null, h('span', { class: `nhan ${b.loai === 'sua_chua' ? 'ts-dang_sua' : 'ts-tot'}` }, b.loai === 'sua_chua' ? 'Sửa chữa' : 'Bảo dưỡng'), ' ', b.noi_dung) },
          { nhan: 'Người làm', lay: (b) => h('span', null, b.nguoi_lam || '', b.thue_ngoai ? h('small', null, ' (thuê ngoài)') : null) },
          { nhan: 'Chi phí', so: true, lay: (b) => (Number(b.chi_phi) ? tien(b.chi_phi) : '') },
        ], bd, { gon: true })) : null,
      sc.length ? h('section', { class: 'ts-khoi' }, h('h3', null, 'Thiếu / hỏng'),
        bang([
          { nhan: 'Ngày', lay: (s) => ngay(s.phat_hien_luc) },
          { nhan: 'Sự cố', lay: (s) => h('span', null, h('span', { class: `nhan ${s.loai === 'mat' ? 'ts-mat-cho' : 'ts-hong'}` }, `${s.loai === 'mat' ? 'Thiếu' : 'Hỏng'} ${s.so_luong}`), ' ', s.mo_ta || '') },
          { nhan: 'Xử lý', lay: (s) => (s.trang_thai === 'cho_xu_ly'
            ? (xuLySuCo() ? h('button', { class: 'nut nho chinh', type: 'button', onclick: lam(() => moXuLySuCo(s, t)) }, 'Xử lý') : h('span', { class: 'nhan ts-hong' }, 'Chờ xử lý'))
            : h('span', null, KET_QUA[s.ket_qua] || '', Number(s.boi_thuong) ? h('small', null, ` · bồi thường ${tien(s.boi_thuong)} đ (${s.nguoi_chiu_ten || ''})${s.da_tru ? ' – đã trừ' : ''}`) : null)) },
        ], sc, { gon: true })) : null,
      h('details', { class: 'ts-khoi' }, h('summary', null, h('h3', null, `Lịch sử (${ls.length})`)),
        h('ul', { class: 'nhat-ky' }, ls.map((x) => h('li', null, h('small', null, `${ngayGio(x.luc)} · `), x.noi_dung || x.loai, ' ', chipNv(x.boi, x.boi_ten))))));
    dong = moModal(`${t.ten}`, noiDung, { rong: true });
  }

  // ---------------- Thêm / sửa ----------------
  function moLuuTaiSan(t, nhomMacDinh = null) {
    const dsNhom = (nhom.length ? nhom : []).map((n) => ({ value: n.nhom_id, label: n.ten }));
    const chonLoai = oChon('loai', Object.entries(LOAI).map(([value, label]) => ({ value, label })), t?.loai || 'dung_cu', { trong: null, disabled: !!t });
    const oSl = oChu('so_luong', t ? String(t.so_luong) : '1', { inputmode: 'numeric' });
    const oDv = oChu('don_vi', t?.don_vi || 'Cái', { list: 'ds-don-vi-ts' });
    const truongSl = truong('Số lượng', oSl, null, { batBuoc: true, co: 'ngan' });
    const truongDv = truong('Đơn vị', oDv, null, { co: 'ngan' });
    const chonCk = oChon('chu_ky_ngay', CHU_KY.map(([value, label]) => ({ value, label })), 90, { trong: null });
    const khoiLich = h('div', { class: 'rong luoi-o ts-lich-moi' },
      truong('Việc bảo dưỡng định kỳ (nếu có)', oChu('ten_viec', '', { placeholder: 'Thay dầu, xả nước bình…' }), 'Để trống nếu không cần', { co: 'lon' }),
      truong('Chu kỳ', chonCk, null, { co: 'vua' }));
    const chonAnh = t ? null : oChonTep({ name: 'anh', capture: 'environment' }, 'Chụp ảnh');
    const capNhatLoai = () => {
      const may = chonLoai.value === 'may_moc';
      truongSl.hidden = may; truongDv.hidden = may;
      khoiLich.hidden = !may || !!t;
    };
    chonLoai.addEventListener('change', capNhatLoai);
    const form = h('form', { class: 'luoi-o', novalidate: true },
      truong('Tên thiết bị, đồ nghề', oChu('ten', t?.ten || '', { placeholder: 'Máy nén khí 50L, Bộ tuýp 1/2…' }), null, { batBuoc: true, co: 'lon' }),
      truong('Loại', chonLoai, t ? 'Không đổi loại được' : 'Thiết bị (máy): quản lý từng cái, có bảo dưỡng. Đồ nghề: theo bộ / số lượng.', { batBuoc: true, co: 'vua' }),
      t ? null : truong('Giao cho nhóm', oChon('nhom_id', dsNhom, nhomMacDinh || dsNhom[0]?.value, { trong: null }), null, { batBuoc: true, co: 'vua' }),
      truongSl, truongDv,
      h('datalist', { id: 'ds-don-vi-ts' }, ['Cái', 'Bộ', 'Chiếc', 'Cây', 'Hộp', 'Cuộn'].map((x) => h('option', { value: x }))),
      truong('Hãng / model', oChu('hang_model', t?.hang_model || ''), null, { co: 'vua' }),
      truong('Số serial', oChu('so_serial', t?.so_serial || ''), null, { co: 'vua' }),
      truong('Giá mua (một cái / một bộ)', oTien('gia_mua', t?.gia_mua ?? null), 'Chỉ để quản lý – chi phí mua tính vào tháng mua qua đề nghị chi'),
      truong('Ngày mua', oNgay('ngay_mua', t?.ngay_mua || '', { max: homNay() })),
      truong('Bảo hành đến', oNgay('bao_hanh_den', t?.bao_hanh_den || '')),
      truong('Nhà cung cấp', oChon('nha_cung_cap_id', (api.dm.nha_cung_cap || []).filter((x) => x.hoat_dong).map((x) => ({ value: x.id, label: x.ten })), t?.nha_cung_cap_id), null, { co: 'vua' }),
      truong('Vị trí để', oChu('vi_tri', t?.vi_tri || '', { placeholder: 'Tủ đồ nghề tổ DS, góc xưởng…' }), null, { co: 'lon' }),
      truong('Ghi chú', oVung('ghi_chu', t?.ghi_chu || ''), null, { rong: true }),
      khoiLich,
      chonAnh ? truong('Ảnh', chonAnh, 'Không bắt buộc', { rong: true }) : null);
    capNhatLoai();
    moModal(t ? `Sửa – ${t.ma}` : 'Thêm thiết bị, đồ nghề', form, {
      rong: true, nhanNut: t ? 'Lưu' : 'Thêm và giao cho nhóm',
      nutChinh: async () => {
        const d = docForm(form);
        const p = { ...d, id: t?.id ?? null, loai: t?.loai || d.loai, so_luong: Number(d.so_luong || 1) };
        delete p.ten_viec; delete p.chu_ky_ngay; delete p.anh;
        const id = await api.luuTaiSan(p);
        if (!t && p.loai === 'may_moc' && d.ten_viec) {
          await api.luuLichBaoDuong({ tai_san_id: id, ten_viec: d.ten_viec, chu_ky_ngay: Number(d.chu_ky_ngay), bat_dau: d.ngay_mua || homNay() }).catch((e) => toast(`Đã thêm, chưa lưu được lịch bảo dưỡng: ${e.message}`, 'loi'));
        }
        const f = chonAnh?.input?.files?.[0];
        if (f) {
          const [moi] = await api.doc('tai_san', (q) => q.eq('id', id));
          if (moi) await api.taiAnhTaiSan(moi, await nenAnh(f)).catch((e) => toast(`Đã thêm, chưa lưu được ảnh: ${e.message}`, 'loi'));
        }
        toast(t ? 'Đã lưu.' : 'Đã thêm, chờ nhóm xác nhận đã nhận.');
        await taiLai();
      },
    });
  }

  function moChuyenNhom(t) {
    const form = h('form', { class: 'luoi-o' },
      truong('Chuyển sang nhóm', oChon('nhom', nhom.filter((n) => n.nhom_id !== t.nhom_id).map((n) => ({ value: n.nhom_id, label: n.ten })), null), null, { batBuoc: true, rong: true }),
      truong('Ghi chú', oChu('ghi_chu', ''), 'Vd: tổ ĐMG mượn đến hết tháng', { rong: true }));
    moModal(`Chuyển nhóm – ${t.ten}`, form, {
      nhanNut: 'Chuyển',
      nutChinh: async () => { const d = docForm(form); if (!d.nhom) { toast('Chọn nhóm nhận.', 'loi'); return false; }
        await api.chuyenNhomTaiSan(t.id, d.nhom, d.ghi_chu); toast('Đã chuyển, chờ nhóm mới xác nhận đã nhận.'); await taiLai(); },
    });
  }

  function moThanhLy(t) {
    hoiLyDo(`Thanh lý – ${t.ten}`, async (lyDo) => { await api.thanhLyTaiSan(t.id, lyDo); toast('Đã thanh lý.'); await taiLai(); },
      { moTa: `Thanh lý ${t.so_luong} ${t.don_vi} ${t.ten} (${t.ma}). Món này sẽ không còn trong danh sách kiểm tra.`,
        goiY: 'Hư hỏng không sửa được, bán ve chai…', nhanNut: 'Thanh lý' });
  }

  function moBaoSuCo(t) {
    const chonLoai = h('div', { class: 'chon-nut', role: 'radiogroup', 'aria-label': 'Mất hay hỏng' },
      [['hong', 'Hỏng'], ['mat', 'Mất / không thấy']].map(([v, nhan], i) => h('label', null, h('input', { type: 'radio', name: 'loai', value: v, checked: i === 0 }), h('span', null, nhan))));
    const form = h('form', { class: 'luoi-o' },
      truong('Sự cố', chonLoai, null, { rong: true }),
      t.loai === 'dung_cu' ? truong(`Số lượng (đang có ${t.so_luong} ${t.don_vi})`, oChu('so_luong', '1', { inputmode: 'numeric' }), null, { co: 'vua' }) : null,
      truong('Mô tả', oVung('mo_ta', ''), 'Mất khi nào, ở đâu; hỏng thế nào', { batBuoc: true, rong: true }));
    moModal(`Báo mất / hỏng – ${t.ten}`, form, {
      nhanNut: 'Báo', nutChinh: async () => { const d = docForm(form);
        await api.baoSuCoTaiSan({ tai_san_id: t.id, loai: d.loai, so_luong: Number(d.so_luong || 1), mo_ta: d.mo_ta });
        toast('Đã báo, giám đốc và quản lý chung sẽ xử lý.'); await taiLai(); },
    });
  }

  function moXuLySuCo(s, t) {
    const lua = s.loai === 'mat' ? [['tim_thay', 'Đã tìm thấy'], ['ghi_mat', 'Ghi mất – trừ khỏi danh sách']]
      : [['dua_sua', 'Đưa đi sửa'], ['da_sua', 'Đã sửa xong'], ['thanh_ly', 'Thanh lý']];
    const chonKq = h('div', { class: 'chon-nut', role: 'radiogroup', 'aria-label': 'Kết quả xử lý' },
      lua.map(([v, nhan]) => h('label', null, h('input', { type: 'radio', name: 'ket_qua', value: v }), h('span', null, nhan))));
    const gd = api.coVaiTro('giam_doc');
    const dsNv = (api.dm.nhan_vien || []).filter((x) => x.hoat_dong);
    const khoiBt = gd ? h('fieldset', { class: 'nhom-o rong ts-boi-thuong' }, h('legend', null, 'Bồi thường (nếu do lỗi người dùng)'),
      h('div', { class: 'luoi-o' },
        truong('Người chịu', oChon('nguoi_chiu', dsNv.map((x) => ({ value: x.id, label: x.ho_ten })), null, { trong: '— Không —' }), null, { co: 'lon' }),
        truong('Số tiền bồi thường', oTien('boi_thuong', null), 'Kế toán trừ lương xong thì đánh dấu "Đã trừ"', { co: 'vua' }))) : null;
    const form = h('form', { class: 'luoi-o' },
      h('div', { class: 'rong thong-bao' }, h('b', null, `${s.loai === 'mat' ? 'Thiếu' : 'Hỏng'} ${s.so_luong} ${t?.don_vi || ''} – ${t?.ten || ''}`), h('br'),
        `${ngayGio(s.phat_hien_luc)}: ${s.mo_ta || ''}`),
      truong('Kết quả', chonKq, null, { rong: true, batBuoc: true }),
      truong('Ghi chú', oChu('ghi_chu', ''), null, { rong: true }),
      khoiBt);
    moModal('Xử lý thiếu / hỏng', form, {
      nhanNut: 'Lưu xử lý', nutChinh: async () => {
        const d = docForm(form);
        if (!d.ket_qua) { toast('Chọn kết quả xử lý.', 'loi'); return false; }
        await api.xuLySuCoTaiSan({ id: s.id, ket_qua: d.ket_qua, ghi_chu: d.ghi_chu, nguoi_chiu: d.nguoi_chiu || null, boi_thuong: d.boi_thuong || 0 });
        toast('Đã xử lý.'); await taiLai();
      },
    });
  }

  function moLichBaoDuong(t, l) {
    const coSan = l && CHU_KY.some(([d]) => d === Number(l.chu_ky_ngay));
    const chonCk = oChon('chu_ky', [...CHU_KY.map(([value, label]) => ({ value, label })), { value: 'khac', label: 'Số ngày khác…' }], l ? (coSan ? l.chu_ky_ngay : 'khac') : 90, { trong: null });
    const oNgayCk = oChu('so_ngay', l && !coSan ? String(l.chu_ky_ngay) : '', { inputmode: 'numeric', placeholder: 'Số ngày' });
    const truongNgay = truong('Số ngày', oNgayCk, null, { co: 'ngan' });
    const capNhat = () => { truongNgay.hidden = chonCk.value !== 'khac'; };
    chonCk.addEventListener('change', capNhat);
    const form = h('form', { class: 'luoi-o' },
      truong('Việc bảo dưỡng', oChu('ten_viec', l?.ten_viec || '', { placeholder: 'Thay dầu, xả nước bình; vệ sinh lọc gió; kiểm định cầu nâng…' }), null, { batBuoc: true, rong: true }),
      truong('Chu kỳ', chonCk, null, { co: 'vua' }), truongNgay,
      truong('Tính từ ngày', oNgay('bat_dau', l?.bat_dau || homNay()), 'Chưa làm lần nào: hạn đầu tiên = ngày này + chu kỳ', { co: 'vua' }),
      truong('Lần làm gần nhất', oNgay('lan_cuoi', l?.lan_cuoi || '', { max: homNay() }), 'Nếu đã làm trước đây', { co: 'vua' }),
      l ? h('div', { class: 'truong' }, oCheck('hoat_dong', l.hoat_dong, 'Đang dùng lịch này')) : null);
    capNhat();
    moModal(l ? 'Sửa lịch bảo dưỡng' : `Lịch bảo dưỡng – ${t.ten}`, form, {
      nhanNut: 'Lưu', nutChinh: async () => {
        const d = docForm(form);
        const ck = d.chu_ky === 'khac' ? Number(d.so_ngay) : Number(d.chu_ky);
        await api.luuLichBaoDuong({ id: l?.id ?? null, tai_san_id: t.id, ten_viec: d.ten_viec, chu_ky_ngay: ck, bat_dau: d.bat_dau, lan_cuoi: d.lan_cuoi, hoat_dong: l ? d.hoat_dong : true });
        toast('Đã lưu lịch bảo dưỡng.'); await taiLai();
      },
    });
  }

  function moGhiBaoDuong(t, lichDs, l) {
    const hong = ['hong', 'dang_sua'].includes(t.tinh_trang);
    const chonLoai = h('div', { class: 'chon-nut', role: 'radiogroup', 'aria-label': 'Bảo dưỡng hay sửa chữa' },
      [['bao_duong', 'Bảo dưỡng'], ['sua_chua', 'Sửa chữa']].map(([v, nhan]) => h('label', null,
        h('input', { type: 'radio', name: 'loai', value: v, checked: hong ? v === 'sua_chua' : v === 'bao_duong' }), h('span', null, nhan))));
    const chonLich = lichDs.length ? oChon('lich_id', lichDs.map((x) => ({ value: x.id, label: `${x.ten_viec} (${tenChuKy(x.chu_ky_ngay).toLowerCase()})` })), l?.id, { trong: '— Không theo lịch —' }) : null;
    const oNd = oChu('noi_dung', l?.ten_viec || '');
    if (chonLich) chonLich.addEventListener('change', () => { const x = lichDs.find((y) => String(y.id) === chonLich.value); if (x && !oNd.value) oNd.value = x.ten_viec; });
    const form = h('form', { class: 'luoi-o' },
      truong('Loại', chonLoai, null, { rong: true }),
      chonLich ? truong('Theo lịch', chonLich, 'Chọn để tính lại hạn lần sau', { co: 'lon' }) : null,
      truong('Ngày làm', oNgay('ngay', homNay(), { max: homNay() }), null, { co: 'vua' }),
      truong('Nội dung đã làm', oNd, null, { batBuoc: true, rong: true }),
      truong('Người làm', oChu('nguoi_lam', ''), 'Thợ trong tổ hoặc nơi sửa ngoài', { co: 'lon' }),
      truong('Chi phí', oTien('chi_phi', null), null, { co: 'vua' }),
      h('div', { class: 'truong' }, oCheck('thue_ngoai', false, 'Thuê ngoài (lập đề nghị chi)')),
      hong ? h('div', { class: 'truong' }, oCheck('xong', true, 'Đã dùng lại được')) : null);
    moModal(`${l ? 'Đã làm' : 'Ghi bảo dưỡng / sửa chữa'} – ${t.ten}`, form, {
      rong: true, nhanNut: 'Lưu', nutChinh: async () => {
        const d = docForm(form);
        await api.ghiBaoDuong({ tai_san_id: t.id, lich_id: d.lich_id || null, loai: d.loai, ngay: d.ngay, noi_dung: d.noi_dung, nguoi_lam: d.nguoi_lam,
          chi_phi: d.chi_phi || 0, thue_ngoai: !!d.thue_ngoai, xong: !!d.xong });
        toast('Đã ghi.');
        await taiLai();
        if (d.thue_ngoai && Number(d.chi_phi) > 0) {
          const nd = `${d.loai === 'sua_chua' ? 'Sửa chữa' : 'Bảo dưỡng'} ${t.ten} (${t.ma}): ${d.noi_dung}`;
          location.hash = `#/de-nghi?lap=1&muc=${encodeURIComponent('Bảo dưỡng – sửa chữa máy móc')}&tien=${Number(d.chi_phi)}&nd=${encodeURIComponent(nd)}&nhan=${encodeURIComponent(d.nguoi_lam || '')}`;
        }
      },
    });
  }

  function moXacNhanNhan(n, ds) {
    const form = h('form', null,
      h('p', { class: 'mo-ta' }, 'Bỏ chọn món chưa nhận được, báo lại người giao.'),
      h('div', { class: 'ds-chon-ts' }, ds.map((t) => h('label', { class: 'o-check' }, h('input', { type: 'checkbox', name: `ts_${t.id}`, checked: true }),
        h('span', null, h('b', null, t.ten), ` · ${t.so_luong} ${t.don_vi} · ${t.ma}`)))));
    moModal(`Xác nhận đã nhận – ${n.ten}`, form, {
      nhanNut: 'Xác nhận', nutChinh: async () => {
        const ids = ds.filter((t) => form.querySelector(`[name=ts_${t.id}]`).checked).map((t) => t.id);
        if (!ids.length) { toast('Chưa chọn món nào.', 'loi'); return false; }
        await api.xacNhanNhanTaiSan(ids); toast(`Đã xác nhận nhận ${ids.length} món.`); await taiLai();
      },
    });
  }

  // Kiểm tra tuần / kiểm kê tháng: từng món chọn Đủ / Thiếu / Hỏng (máy: Có / Không thấy / Hỏng), dụng cụ ghi số
  function moKiemTra(n, loai, ds) {
    const can = ds.filter((t) => t.dang_dung && t.tinh_trang !== 'dang_sua');
    const kk = loai === 'kiem_ke';
    const dem = h('b', null, '0');
    // Sự cố đang chờ xử lý của từng món: hiện cho người kiểm biết, máy chủ chỉ báo phần thiếu / hỏng thêm
    const dangBao = (id, l) => suCo.filter((s) => s.tai_san_id === id && s.trang_thai === 'cho_xu_ly' && s.loai === l).reduce((a, s) => a + Number(s.so_luong), 0);
    const dong = can.map((t) => {
      const may = t.loai === 'may_moc';
      const daThieu = dangBao(t.id, 'mat'); const daHong = dangBao(t.id, 'hong');
      const ten = `kq_${t.id}`;
      const lua = may ? [['du', 'Có, tốt'], ['thieu', 'Không thấy'], ['hong', 'Hỏng']] : [['du', 'Đủ'], ['thieu', 'Thiếu'], ['hong', 'Có cái hỏng']];
      const chon = h('div', { class: 'chon-nut nho', role: 'radiogroup', 'aria-label': `Kết quả ${t.ten}` },
        lua.map(([v, nhan]) => h('label', null, h('input', { type: 'radio', name: ten, value: v }), h('span', null, nhan))));
      const oCon = h('input', { type: 'number', min: 0, max: t.so_luong, inputmode: 'numeric', 'aria-label': `Đếm được bao nhiêu ${t.ten}`, value: t.so_luong });
      const oHong = h('input', { type: 'number', min: 1, max: t.so_luong, inputmode: 'numeric', 'aria-label': `Số hỏng ${t.ten}`, value: 1 });
      const oGhi = h('input', { type: 'text', placeholder: kk ? 'Ghi chú (bắt buộc nếu thiếu)' : 'Ghi chú', 'aria-label': `Ghi chú ${t.ten}` });
      const phu = h('div', { class: 'kt-phu', hidden: true },
        may ? null : h('label', { class: 'kt-so', hidden: true, 'data-o': 'con' }, 'Đếm được', oCon, h('small', null, `/ ${t.so_luong} ${t.don_vi}`)),
        may ? null : h('label', { class: 'kt-so', hidden: true, 'data-o': 'hong' }, 'Số hỏng', oHong),
        oGhi);
      const li = h('li', { class: 'kt-dong' },
        h('div', { class: 'kt-ten' }, h('b', null, t.ten), h('small', null, `${t.ma} · trên sổ ${t.so_luong} ${t.don_vi}${t.vi_tri ? ` · ${t.vi_tri}` : ''}`),
          daThieu || daHong ? h('small', { class: 'kt-da-bao' }, `Đang báo ${[daThieu ? `thiếu ${daThieu}` : null, daHong ? `hỏng ${daHong}` : null].filter(Boolean).join(', ')}, chờ giám đốc xử lý`) : null),
        chon, phu);
      chon.addEventListener('change', () => {
        const v = chon.querySelector('input:checked')?.value;
        li.dataset.kq = v || '';
        phu.hidden = !v || v === 'du';
        if (!may) {
          phu.querySelector('[data-o=con]').hidden = v !== 'thieu';
          phu.querySelector('[data-o=hong]').hidden = v !== 'hong';
          if (v === 'thieu' && Number(oCon.value) >= t.so_luong) oCon.value = Math.max(0, t.so_luong - Math.max(1, daThieu));
        }
        capNhatDem();
      });
      return { t, li, may, chon, oCon, oHong, oGhi };
    });
    const capNhatDem = () => { dem.textContent = String(dong.filter((d) => d.li.dataset.kq).length); };
    const tatCaDu = h('button', { class: 'nut nho', type: 'button', onclick: () => {
      for (const d of dong) if (!d.li.dataset.kq) { const r = d.chon.querySelector('input[value=du]'); r.checked = true; d.chon.dispatchEvent(new Event('change')); }
    } }, 'Các món còn lại: Đủ');
    const dsPt = nguoiPhuTrach(n);
    const oCung = kk ? oChu('cung_kiem', dsPt[0]?.ho_ten || '', { list: 'ds-cung-kiem' }) : null;
    const form = h('form', { class: 'kiem-tra-ts', novalidate: true },
      h('div', { class: 'kt-dau' },
        h('p', { class: 'mo-ta' }, kk ? 'Đếm từng món cùng người phụ trách nhóm. Thiếu phải ghi lý do / nơi để. Lưu xong có biên bản để in.'
          : 'Đi một vòng chỗ để đồ nghề của nhóm, chọn từng món. Thiếu hoặc hỏng sẽ báo ngay cho giám đốc và quản lý chung.'),
        h('div', { class: 'kt-tien-do' }, h('span', null, 'Đã kiểm ', dem, ` / ${dong.length} món`), tatCaDu)),
      kk ? h('div', { class: 'luoi-o kt-cung' },
        truong('Người cùng kiểm', oCung, 'Trưởng nhóm / người phụ trách nhóm', { batBuoc: true, co: 'lon' }),
        h('datalist', { id: 'ds-cung-kiem' }, (api.dm.nhan_vien || []).filter((x) => x.hoat_dong).map((x) => h('option', { value: x.ho_ten })))) : null,
      h('ol', { class: 'ds-kiem-tra' }, dong.map((d) => d.li)),
      truong('Ghi chú chung', oChu('ghi_chu', ''), null));
    moModal(`${kk ? 'Kiểm kê tháng' : 'Kiểm tra tuần'} – ${n.ten}`, form, {
      rong: true, nhanNut: kk ? 'Lưu biên bản kiểm kê' : 'Lưu kiểm tra',
      nutChinh: async () => {
        const chua = dong.filter((d) => !d.li.dataset.kq);
        if (chua.length) { toast(`Còn ${chua.length} món chưa chọn: ${chua.slice(0, 3).map((d) => d.t.ten).join(', ')}${chua.length > 3 ? '…' : ''}`, 'loi'); chua[0].li.scrollIntoView({ block: 'center' }); return false; }
        const p = { nhom_id: n.nhom_id, loai, cung_kiem: oCung?.value || null, ghi_chu: form.ghi_chu.value, dong: dong.map((d) => {
          const v = d.li.dataset.kq; const sl = d.t.so_luong;
          let soThuc = sl; let soHong = 0;
          if (d.may) { soThuc = v === 'thieu' ? 0 : 1; soHong = v === 'hong' ? 1 : 0; }
          else if (v === 'thieu') soThuc = Math.max(0, Math.min(sl, Number(d.oCon.value) || 0));
          else if (v === 'hong') soHong = Math.max(1, Math.min(sl, Number(d.oHong.value) || 1));
          return { tai_san_id: d.t.id, so_thuc: soThuc, so_hong: soHong, ghi_chu: d.oGhi.value };
        }) };
        const id = await api.luuKiemTraTaiSan(p);
        const thieu = p.dong.filter((x, i) => x.so_thuc < dong[i].t.so_luong).length; const hongN = p.dong.filter((x) => x.so_hong > 0).length;
        toast(thieu || hongN ? `Đã lưu: thiếu ${thieu} món, hỏng ${hongN} món – đã báo giám đốc và quản lý chung.` : `Đã lưu: đủ cả ${p.dong.length} món.`);
        await taiLai();
        if (kk) moBienBan({ id, loai, ngay: homNay(), nguoi_kiem: api.toi.id, cung_kiem: p.cung_kiem, ghi_chu: p.ghi_chu }, n);
      },
    });
  }

  // Biên bản kiểm kê / phiếu kiểm tra: xem và in
  async function moBienBan(k, n) {
    const dsDong = await api.doc('kiem_tra_tai_san_dong', (q) => q.eq('kiem_tra_id', k.id).order('id'));
    const ts = await layTaiSan(dsDong.map((d) => d.tai_san_id));
    const kk = k.loai === 'kiem_ke';
    const ketQua = { du: 'Đủ', thieu: 'Thiếu', hong: 'Có hỏng', thieu_hong: 'Thiếu, có hỏng', du_thua: 'Dư' };
    const noiDung = h('div', { class: 'bien-ban' },
      h('p', { class: 'bb-cty' }, (/hoàng sơn/i.test(api.dm.ten('chi_nhanh', cn) || '') ? api.dm.ten('chi_nhanh', cn) : `Gara Hoàng Sơn${api.dm.ten('chi_nhanh', cn) ? ` – ${api.dm.ten('chi_nhanh', cn)}` : ''}`).toUpperCase()),
      h('h3', { class: 'bb-tieu-de' }, kk ? 'BIÊN BẢN KIỂM KÊ THIẾT BỊ ĐỒ NGHỀ' : 'PHIẾU KIỂM TRA ĐỒ NGHỀ TUẦN'),
      h('p', { class: 'bb-phu' }, `Nhóm: ${n.ten} · Ngày ${ngay(k.ngay)}`),
      h('p', null, 'Người kiểm: ', h('b', null, tenNv(k.nguoi_kiem)?.ho_ten || k.nguoi_kiem_ten || ''), k.cung_kiem ? [' · Người cùng kiểm: ', h('b', null, k.cung_kiem)] : null),
      h('table', { class: 'bang bb-bang' },
        h('thead', null, h('tr', null, ['STT', 'Mã', 'Tên thiết bị, đồ nghề', 'ĐVT', 'Trên sổ', 'Thực tế', 'Hỏng', 'Chênh lệch', 'Kết quả', 'Ghi chú'].map((c, i) => h('th', { class: i >= 4 && i <= 7 ? 'so' : null }, c)))),
        h('tbody', null, dsDong.map((d, i) => { const t = ts[d.tai_san_id] || {}; const cl = d.so_luong_thuc - d.so_luong_so;
          return h('tr', null, h('td', null, i + 1), h('td', null, t.ma || ''), h('td', null, t.ten || ''), h('td', null, t.don_vi || ''),
            h('td', { class: 'so' }, d.so_luong_so), h('td', { class: 'so' }, d.so_luong_thuc), h('td', { class: 'so' }, d.so_hong || ''),
            h('td', { class: `so ${cl < 0 ? 'chu-loi' : ''}` }, cl ? (cl > 0 ? `+${cl}` : cl) : ''), h('td', null, ketQua[d.ket_qua] || d.ket_qua), h('td', null, d.ghi_chu || '')); }))),
      k.ghi_chu ? h('p', null, 'Ghi chú: ', k.ghi_chu) : null,
      h('div', { class: 'bb-ky' }, ['Người kiểm', kk ? 'Người cùng kiểm' : 'Trưởng nhóm', 'Giám đốc'].map((x) => h('div', null, h('b', null, x), h('small', null, '(ký, ghi rõ họ tên)')))));
    const dong = moModal(kk ? 'Biên bản kiểm kê' : 'Phiếu kiểm tra tuần', h('div', null,
      h('div', { class: 'hang-nut khong-in' }, h('button', { class: 'nut', type: 'button', onclick: (e) => {
        const nen = e.currentTarget.closest('.modal-nen');
        nen?.classList.add('in-day'); document.body.classList.add('dang-in');
        window.print();
        setTimeout(() => { document.body.classList.remove('dang-in'); nen?.classList.remove('in-day'); }, 500);
      } }, 'In biên bản')), noiDung), { rong: true });
    return dong;
  }

  // ---------------- Tiện ích ----------------
  async function layTaiSan(ids) {
    if (!ids.length) return {};
    const ds = await api.doc('v_tai_san', (q) => q.in('id', ids));
    return Object.fromEntries(ds.map((t) => [t.id, t]));
  }
  function oTenTaiSan(t) {
    if (!t) return '';
    return h('span', { class: 'ten-ts' }, h('span', null, t.ten), h('small', null, `${t.ma} · ${t.nhom_ten || ''}`));
  }
  function oHan(cuoi, han) {
    return h('span', { class: 'o-han-ts' }, h('span', null, cuoi ? ngay(cuoi) : 'Chưa có'), han ? hanVien(han, 'nho') : null);
  }
  function oDemHan(nhan, cuoi, han, dau) {
    const qh = han && cuoiNgay(han) < new Date();
    return h('div', { class: `o-dem ${qh ? 'qua-han' : ''}`, [dau]: '' }, h('b', null, cuoi ? ngay(cuoi).slice(0, 5) : '—'), h('span', null, `${nhan}${cuoi ? ' gần nhất' : ': chưa làm'}`),
      han ? h('span', { class: 'o-dem-phu' }, hanVien(han, 'nho')) : null);
  }
  function phuTrachText(n) {
    const ds = nguoiPhuTrach(n);
    return ds.length ? `Phụ trách: ${ds.map((x) => x.ho_ten).join(', ')}` : (n.to_id ? 'Chưa có trưởng nhóm' : 'Phụ trách: ' + (n.vai_phu_trach || []).map((v) => ({ quan_ly: 'quản lý chung', ke_toan: 'kế toán' }[v] || v)).join(', '));
  }
  function phuTrachChips(n) {
    const ds = nguoiPhuTrach(n);
    if (!ds.length) return h('span', null, n.to_id ? 'chưa có trưởng nhóm' : (n.vai_phu_trach || []).map((v) => ({ quan_ly: 'quản lý chung', ke_toan: 'kế toán' }[v] || v)).join(', '));
    return h('span', { class: 'hang-nut' }, ds.map((x) => chipNguoi(x.ho_ten, { vai: vaiChinh(x.vai_tro), nho: true })));
  }
  function ngayCong(so) { const d = new Date(); d.setDate(d.getDate() + so); return isoNgay(d); }

  async function xuatExcel() {
    const kq = await api.xuatDuLieuTaiSan();
    const ds = kq.tai_san || [];
    const pd = `${kq.chi_nhanh || 'Gara Hoàng Sơn'} · Xuất lúc ${ngayGio(kq.luc)} · Người xuất: ${api.toi?.ho_ten || ''}`;
    const tenNhom = [...new Set(ds.map((x) => x.nhom))];
    const cot = [{ nhan: 'STT', kieu: 'tien', rong: 6 }, { nhan: 'Mã', rong: 14 }, { nhan: 'Tên thiết bị, đồ nghề', rong: 34 }, { nhan: 'Loại', rong: 16 },
      { nhan: 'Số lượng', kieu: 'so', rong: 9 }, { nhan: 'ĐVT', rong: 8 }, { nhan: 'Hãng / model', rong: 18 }, { nhan: 'Serial', rong: 16 },
      { nhan: 'Đơn giá mua (đ)', kieu: 'tien', rong: 15 }, { nhan: 'Giá trị (đ)', kieu: 'tien', rong: 15 }, { nhan: 'Ngày mua', rong: 11 },
      { nhan: 'Bảo hành đến', rong: 11 }, { nhan: 'Vị trí', rong: 18 }, { nhan: 'Tình trạng', rong: 12 }, { nhan: 'Kiểm tra gần nhất', rong: 13 },
      { nhan: 'Hạn bảo dưỡng', rong: 13 }, { nhan: 'Ghi chú', rong: 24 }];
    const dongTs = (x, i) => [i + 1, x.ma, x.ten, LOAI[x.loai], Number(x.so_luong), x.don_vi, x.hang_model || '', x.so_serial || '', Number(x.gia_mua), Number(x.gia_tri),
      x.ngay_mua ? ngay(x.ngay_mua) : '', x.bao_hanh_den ? ngay(x.bao_hanh_den) : '', x.vi_tri || '', TINH_TRANG[x.tinh_trang] || x.tinh_trang,
      x.kiem_tra_cuoi ? ngay(x.kiem_tra_cuoi) : '', x.han_bao_duong ? ngay(x.han_bao_duong) : '', x.ghi_chu || ''];
    const dangDung = (x) => !['mat', 'thanh_ly'].includes(x.tinh_trang);
    const trang = [{
      ten: 'Tổng hợp', tieuDe: 'THIẾT BỊ ĐỒ NGHỀ – TỔNG HỢP THEO NHÓM', phuDe: pd,
      cot: [{ nhan: 'Nhóm', rong: 24 }, { nhan: 'Số món đang dùng', kieu: 'tien', rong: 14 }, { nhan: 'Giá trị (đ)', kieu: 'tien', rong: 18 },
        { nhan: 'Hỏng / đang sửa', kieu: 'tien', rong: 14 }, { nhan: 'Đã mất / thanh lý', kieu: 'tien', rong: 14 }],
      dong: tenNhom.map((tn) => { const x = ds.filter((y) => y.nhom === tn);
        return [tn, x.filter(dangDung).length, x.filter(dangDung).reduce((s, y) => s + Number(y.gia_tri), 0), x.filter((y) => ['hong', 'dang_sua'].includes(y.tinh_trang)).length, x.filter((y) => !dangDung(y)).length]; }),
      tong: ['Tổng cộng', 'SUM', 'SUM', 'SUM', 'SUM'],
    }, ...tenNhom.map((tn) => { const x = ds.filter((y) => y.nhom === tn);
      return { ten: tn, tieuDe: `THIẾT BỊ ĐỒ NGHỀ – ${tn.toUpperCase()}`, phuDe: pd, cot, dong: x.map(dongTs),
        tong: ['', 'Tổng cộng', `${x.length} món`, null, null, null, null, null, null, 'SUM', null, null, null, null, null, null, null] }; })];
    const sc = kq.su_co || [];
    if (sc.length) trang.push({ ten: 'Thiếu – hỏng', tieuDe: 'THIẾT BỊ ĐỒ NGHỀ THIẾU / HỎNG VÀ BỒI THƯỜNG', phuDe: pd,
      cot: [{ nhan: 'Ngày', rong: 11 }, { nhan: 'Mã', rong: 14 }, { nhan: 'Thiết bị, đồ nghề', rong: 30 }, { nhan: 'Nhóm', rong: 18 }, { nhan: 'Sự cố', rong: 10 },
        { nhan: 'Số lượng', kieu: 'so', rong: 9 }, { nhan: 'Mô tả', rong: 28 }, { nhan: 'Xử lý', rong: 14 }, { nhan: 'Người chịu', rong: 20 },
        { nhan: 'Bồi thường (đ)', kieu: 'tien', rong: 14 }, { nhan: 'Đã trừ', rong: 8 }],
      dong: sc.map((s) => [ngay(s.ngay), s.ma, s.ten, s.nhom, s.loai === 'mat' ? 'Thiếu' : 'Hỏng', Number(s.so_luong), s.mo_ta || '',
        s.trang_thai === 'cho_xu_ly' ? 'Chờ xử lý' : (KET_QUA[s.ket_qua] || ''), s.nguoi_chiu || '', Number(s.boi_thuong) || null, Number(s.boi_thuong) ? (s.da_tru ? 'Có' : 'Chưa') : '']),
      tong: ['Tổng cộng', null, null, null, null, null, null, null, null, 'SUM', null] });
    taiFileExcel(`Thiet-bi-do-nghe_${homNay()}.xlsx`, trang);
    toast(`Đã xuất file thiết bị đồ nghề: ${ds.length} món.`);
  }

  await taiLai();
}
