// Dịch vụ nhanh: rửa xe, vá lốp, thay bóng đèn, kích bình… (không đi qua 9 bước)
// 032: gõ biển số / SĐT → gợi ý xe cũ, hiện khách, lần vào gần nhất, số km lần trước, hạn BH, tư vấn còn ghi.
//      Mỗi lượt lưu kèm xe – khách (chưa có thì tạo), số km BẮT BUỘC; lượt dịch vụ nhanh vào lịch sử xe.
import {
  h, bienSo, vietBienSo, oGoiY, tien, ngay, homNay, truong, oChu, oTien, oCheck, docForm, chay, bang, moModal, oVung, toast, dat, xacNhan,
} from '../ui.js';
import * as api from '../api.js';
import { nhacHetHan } from './lich-su-xe.js';

export default async function trangDichVu(el) {
  let xeChon = null;               // kết quả tra cứu của xe đang nhập
  const oBienSo = oChu('bien_so', '', { placeholder: 'Gõ vài số hoặc SĐT khách', autocapitalize: 'characters', autocomplete: 'off' });
  const oTen = oChu('ten_khach', '', { autocomplete: 'off' });
  const oSdt = oChu('dien_thoai', '', { inputmode: 'tel', autocomplete: 'off' });
  const oKm = oTien('so_km', null, { placeholder: 'Vd 45.230', 'aria-label': 'Số km (ODO)' });
  const goiYKm = h('span', null, 'Số trên đồng hồ công tơ mét');
  // Người làm: chỉ tổ Điện – máy – gầm hoặc Detailing (034) – doanh thu tính vào đúng tổ
  const TO_DVN = ['DMG', 'DT'];
  const chonTo = h('div', { class: 'chon-nut', role: 'radiogroup', 'aria-label': 'Tổ làm' },
    TO_DVN.map((id) => h('label', null, h('input', { type: 'radio', name: 'to_id', value: id }),
      h('span', null, api.dm.ten('to_thuc_hien', id) || (id === 'DMG' ? 'Điện – máy – gầm' : 'Detailing')))));
  const khungXe = h('div', { class: 'rong thong-tin-xe-nhanh', hidden: true, 'aria-live': 'polite' });

  const veGoiY = (x) => h('span', { class: 'goi-y-xe' }, bienSo(x.bien_so),
    h('span', null, h('span', null, [x.loai_xe, x.mau].filter(Boolean).join(' – ') || 'Chưa rõ loại xe'),
      h('small', null, [x.ten_khach, x.dien_thoai].filter(Boolean).join(' – ') || 'Chưa có thông tin khách')));

  function hienXe(x) {
    xeChon = x;
    if (!x) {
      khungXe.hidden = true; dat(khungXe);
      dat(goiYKm, 'Số trên đồng hồ công tơ mét');
      return;
    }
    if (x.ten_khach && !oTen.value) oTen.value = x.ten_khach;
    if (x.dien_thoai && !oSdt.value) oSdt.value = x.dien_thoai;
    dat(goiYKm, x.km_truoc ? `Lần trước: ${tien(x.km_truoc.so)} km (${ngay(x.km_truoc.ngay)})` : 'Chưa có số km lần trước');
    const nhac = nhacHetHan(x.han_bh_than_vo, x.han_bao_hiem);
    const lan = x.lan_cuoi;
    khungXe.hidden = false;
    dat(khungXe,
      h('p', { class: 'txn-dau' }, h('b', null, 'Xe cũ'), ` – đã vào gara ${x.so_lan_vao} lần`, x.loai_xe ? ` · ${x.loai_xe}` : '', x.mau ? ` · ${x.mau}` : ''),
      h('dl', { class: 'thong-tin' },
        h('dt', null, 'Khách'), h('dd', null, [x.ten_khach, x.dien_thoai].filter(Boolean).join(' – ') || '—'),
        h('dt', null, 'Lần vào gần nhất'), h('dd', null, lan
          ? [`${ngay(lan.ngay)} · ${lan.loai === 'ho_so' ? 'Sửa chữa' : 'Dịch vụ nhanh'}`, lan.noi_dung ? `: ${lan.noi_dung.replace(/^\d{2}\/\d{2}\/\d{4}:\s*/, '')}` : '',
            lan.loai === 'ho_so' && api.xemNhuNhanVien() ? [' ', h('a', { href: `#/ho-so/${lan.id}` }, lan.ma)] : null]
          : '—'),
        h('dt', null, 'Số km lần trước'), h('dd', null, x.km_truoc ? `${tien(x.km_truoc.so)} km (${ngay(x.km_truoc.ngay)})` : '—'),
        h('dt', null, 'Hạn bảo hiểm'), h('dd', null, `Thân vỏ ${x.han_bh_than_vo ? ngay(x.han_bh_than_vo) : '—'} · TNDS ${x.han_bao_hiem ? ngay(x.han_bao_hiem) : '—'}`)),
      nhac.length ? h('div', { class: 'thong-bao canh-bao' }, nhac.map((n) => h('div', null, n))) : null,
      x.tu_van ? h('div', { class: 'txn-tu-van' }, h('b', null, 'Có thể tư vấn (ghi ở lần sửa chữa trước)'), h('div', { class: 'nhat-ky-ghi' }, x.tu_van)) : null);
  }

  // Gõ xong biển số (không chọn gợi ý): tra đúng biển số đó
  let daTra = '';
  async function traBienSo() {
    const gon = oBienSo.value.toUpperCase().replace(/[^0-9A-Z]/g, '');
    if (gon === daTra) return;
    daTra = gon;
    if (!gon) return hienXe(null);
    const ds = await api.traCuuXeNhanh(gon).catch(() => []);
    const dung = ds.find((x) => x.bien_so.toUpperCase().replace(/[^0-9A-Z]/g, '') === gon);
    hienXe(dung || null);
    if (!dung && /[A-Z]/.test(gon)) dat(goiYKm, 'Xe mới – lưu xong lần sau sẽ nhận ra');
  }
  oBienSo.addEventListener('change', traBienSo);

  const form = h('form', { class: 'the luoi-o', novalidate: true },
    truong('Biển số', oGoiY(oBienSo, {
      tim: (chu) => api.traCuuXeNhanh(chu).catch(() => []),
      ve: veGoiY,
      chon: (x) => { oBienSo.value = vietBienSo(x.bien_so); daTra = x.bien_so.toUpperCase().replace(/[^0-9A-Z]/g, ''); hienXe(x); oKm.focus(); },
    }), 'Gõ vài số (hoặc SĐT khách) để chọn xe cũ', { co: 'vua' }),
    truong('Tên khách', oTen, null, { co: 'lon' }),
    truong('Số điện thoại', oSdt, null, { co: 'vua' }),
    truong('Số km (ODO)', oKm, goiYKm, { batBuoc: true, co: 'vua' }),
    khungXe,
    truong('Dịch vụ', oChu('dich_vu', '', { placeholder: 'Rửa xe, vá lốp, thay bóng đèn…', list: 'goi-y-dv' }), null, { batBuoc: true, co: 'lon' }),
    h('datalist', { id: 'goi-y-dv' }, ['Rửa xe', 'Vá lốp', 'Thay bóng đèn', 'Kích bình', 'Bơm lốp', 'Vệ sinh nội thất'].map((x) => h('option', { value: x }))),
    truong('Tổ làm', chonTo, null, { batBuoc: true }),
    truong('Số tiền khách trả', oTien('so_tien', null), null, { batBuoc: true }),
    h('div', { class: 'truong' }, oCheck('xuat_hd', false, 'Có xuất hóa đơn')),
    h('div', { class: 'hang-nut rong' }, h('button', { class: 'nut chinh', type: 'submit' }, 'Ghi dịch vụ')));
  const ds = h('div');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    await traBienSo();
    const d = docForm(form);
    if (d.so_km === null) { oKm.focus(); return toast('Ghi số km (ODO) của xe.', 'loi'); }
    if (!d.to_id) { chonTo.querySelector('input')?.focus(); return toast('Chọn tổ làm: Điện – máy – gầm hoặc Detailing.', 'loi'); }
    if (d.so_km > 9999999) { oKm.focus(); return toast('Số km (ODO) không đúng.', 'loi'); }
    const kmTruoc = xeChon?.km_truoc;
    if (kmTruoc && d.so_km < Number(kmTruoc.so)
      && !(await xacNhan(`Số km ${tien(d.so_km)} nhỏ hơn lần trước (${tien(kmTruoc.so)} km). Vẫn lưu?`, 'Vẫn lưu'))) { oKm.focus(); return; }
    try {
      // Ngày = hôm nay (giờ máy, không chọn được); máy chủ vẫn lưu cột ngay + giờ ghi tao_luc
      await chay(() => api.ghiDichVuNhanh({ ...d, ngay: homNay(), bat_buoc_km: true }), { thanhCong: 'Đã ghi.' });
      form.reset(); daTra = ''; hienXe(null); await tai();
    } catch { /* đã báo lỗi */ }
  });

  async function tai() {
    const tuNgay = new Date(Date.now() - 31 * 864e5).toISOString().slice(0, 10);
    const rows = await api.doc('v_dich_vu_nhanh', (q) => q.gte('ngay', tuNgay).order('ngay', { ascending: false }).order('id', { ascending: false }).limit(300));
    const homnay = rows.filter((r) => r.ngay === homNay() && r.trang_thai === 'hieu_luc');
    dat(ds,
      h('p', { class: 'mo-ta' }, `Hôm nay: ${homnay.length} lượt, ${tien(homnay.reduce((s, r) => s + Number(r.so_tien), 0))} đ`),
      bang([
        { nhan: 'Ngày', lay: (r) => ngay(r.ngay) },
        { nhan: 'Biển số', lay: (r) => r.bien_so_hien_thi ? bienSo(r.bien_so_hien_thi) : '' },
        { nhan: 'Khách', lay: (r) => [r.ten_khach && r.ten_khach !== 'Chưa có tên' ? r.ten_khach : null, r.dien_thoai].filter(Boolean).join(' – ') },
        { nhan: 'Số km', so: true, lay: (r) => (r.so_km === null || r.so_km === undefined ? '' : tien(r.so_km)) },
        { nhan: 'Dịch vụ', lay: (r) => r.trang_thai === 'huy' ? h('s', null, r.dich_vu) : r.dich_vu },
        { nhan: 'Tổ làm', lay: (r) => r.nguoi_lam || '' },
        { nhan: 'Số tiền', so: true, lay: (r) => tien(r.so_tien) },
        { nhan: 'Đã thu', lay: (r) => r.trang_thai === 'huy' ? 'Đã hủy' : Number(r.da_thu) >= Number(r.so_tien) ? '✓' :
          api.coVaiTro('ke_toan', 'giam_doc') ? h('a', { class: 'nut nho', href: `#/thu-chi?dvn=${r.id}` }, 'Thu tiền') : 'Chưa' },
        api.coVaiTro('ke_toan', 'giam_doc') ? { nhan: '', lay: (r) => r.trang_thai === 'hieu_luc' && Number(r.da_thu) === 0
          ? h('button', { class: 'nut-chu', type: 'button', onclick: () => moHuy(r) }, 'Hủy') : '' } : null,
      ].filter(Boolean), rows, { trong: 'Chưa có dịch vụ nào trong 31 ngày qua.' }));
  }
  function moHuy(r) {
    const f = h('form', null, truong('Lý do hủy', oVung('ly_do'), null, { batBuoc: true }));
    moModal(`Hủy dịch vụ ${r.dich_vu}`, f, { nhanNut: 'Hủy dịch vụ', nutChinh: async () => { await api.huyDichVuNhanh(r.id, docForm(f).ly_do); toast('Đã hủy.'); await tai(); } });
  }

  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Dịch vụ nhanh'),
    h('p', { class: 'mo-ta' }, 'Ghi ngay mỗi lượt làm. Gõ biển số để xem xe cũ; số km bắt buộc. Kế toán thu tiền ở mục Thu chi.')), api.laCoDong() ? null : form,
  h('section', { class: 'the' }, h('h2', null, '31 ngày gần nhất'), ds));
  await tai();
}
