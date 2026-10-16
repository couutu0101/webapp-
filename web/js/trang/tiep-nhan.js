// Bước 1: Tiếp nhận xe – 10 thông tin bắt buộc + ảnh nhận xe
import { h, oGoiY, bienSo, vietBienSo, oCheck, truong, oChu, oChon, oVung, oNgayVN, oTien, isoSangVN, vnSangIso, docForm, chay, toast, dat, veDanhSachHoSo, xacNhan, tien, ngay, NHOM, NHOM_CHON, khoaKhiGui } from '../ui.js';
import * as api from '../api.js';
import { khungGiaoViec, giaoSauKhiLuu, VAI_TRO_BUOC } from './giao-viec.js';
import { homNayVN, themNgay, tuGhiNgayKhiBam, nhacHetHan, layLichSu, khoiLichSu } from './lich-su-xe.js';
import { khungAnhNhanXe, taiVaoBuoc } from '../anh-bat-buoc.js';

export default async function trangTiepNhan(el) {
  if (!api.coVaiTro('cvdv', 'quan_ly', 'giam_doc')) {
    dat(el, h('p', { class: 'trong' }, 'Chỉ CVDV, quản lý chung và giám đốc được tiếp nhận xe.'));
    return;
  }
  const dm = api.dm;
  const thamSoUrl = new URLSearchParams(location.hash.split('?')[1] || '');
  // Hồ sơ bảo hành (036): xe quay lại vì lỗi cũ – không báo giá, không duyệt giá, không hãng BH / GDV;
  // chọn hạng mục làm lại (giá 0) → hồ sơ sang "Đã duyệt giá", lập lệnh sửa chữa ngay
  const baoHanh = thamSoUrl.get('bao_hanh');
  const hoSoGoc = baoHanh ? await api.layHoSo(baoHanh) : null;
  const hangMucGoc = hoSoGoc ? (await api.layHangMuc(hoSoGoc.id).catch(() => [])).filter((m) => ['duyet', 'dang_lam', 'xong'].includes(m.trang_thai)) : [];
  const tenLoaiXe = (idDong) => {
    const d = dm.dong_xe.find((x) => String(x.id) === String(idDong));
    return d ? `${dm.ten('hang_xe', d.hang_xe_id)} ${d.ten}` : '';
  };
  // 049: hãng hay gặp lên đầu, các hãng khác A–Z; dòng xe A–Z
  const nhomHang = api.nhomHangXe();
  const chonHangXe = h('select', { name: 'hang_xe_id', required: true }, h('option', { value: '' }, '— Chọn —'),
    h('optgroup', { label: 'Hay gặp' }, nhomHang.hay.map((x) => h('option', { value: x.id }, x.ten))),
    h('optgroup', { label: 'Hãng khác (A–Z)' }, nhomHang.khac.map((x) => h('option', { value: x.id }, x.ten))));
  const chonDongXe = oChon('dong_xe_id', [], null, { required: true });
  const capNhatDongXe = (giu) => {
    const ds = api.dsDongXe(chonHangXe.value);
    dat(chonDongXe, h('option', { value: '' }, chonHangXe.value ? '— Chọn —' : '— Chọn hãng trước —'), ds.map((d) => h('option', { value: d.id }, d.ten)));
    if (giu) chonDongXe.value = giu;
  };
  chonHangXe.addEventListener('change', () => capNhatDongXe());
  capNhatDongXe();

  // 048: hãng bảo hiểm và giám định viên KHÔNG nhập lúc tiếp nhận – CVDV chọn khi nhập kết quả duyệt giá (bắt buộc)
  // Hai ngày hết hạn bảo hiểm: luôn hiện; bắt buộc với xe bảo hiểm, khách ngoài bảo hiểm thì không bắt buộc
  const oHanThanVo = oNgayVN('han_bh_than_vo');
  const oHan = oNgayVN('han_bao_hiem');
  const sao = () => h('b', { class: 'bat-buoc', 'aria-hidden': 'true' }, ' *');
  const saoThanVo = sao(); const saoTnds = sao();
  // Xe bảo hiểm: mỗi loại bảo hiểm có dấu tích "Không có" riêng ngay dưới ô ngày (khách ngoài bảo hiểm không có dấu tích)
  const tichThanVo = oCheck('khong_than_vo', false, 'Không có BH thân vỏ');
  const tichTnds = oCheck('khong_tnds', false, 'Không có BH TNDS');
  const truongNgay = (nhan, o, s, goiY, tich) => h('div', { class: 'truong truong-ngay-bh co-vua' },
    h('label', null, h('span', { class: 'truong-nhan' }, nhan, s), o), h('small', { class: 'goi-y' }, goiY), tich);
  const oKhongThanVo = tichThanVo.querySelector('input');
  const oKhongTnds = tichTnds.querySelector('input');
  const KHONG_BH = [[oHanThanVo, oKhongThanVo, saoThanVo], [oHan, oKhongTnds, saoTnds]];

  const oBienSo = oChu('bien_so', '', { placeholder: 'Ví dụ 50H-923.61', autocapitalize: 'characters', autocomplete: 'off' });
  const thongBaoXe = h('div', { class: 'thong-bao', hidden: true });
  const oTen = oChu('ten_khach', '', { autocomplete: 'off' });
  const oSdt = oChu('dien_thoai', '', { inputmode: 'tel', placeholder: '09xxxxxxxx', autocomplete: 'off' });
  const oMau = oChu('mau', '', { placeholder: 'Trắng, đỏ…' });
  // Số km (ODD) trên đồng hồ lúc nhận xe; xe cũ: hiện số km lần trước để so
  const oKm = oTien('so_km', null, { placeholder: 'Vd 45.230', 'aria-label': 'Số km (ODD)' });
  const goiYKm = h('span', null, 'Số trên đồng hồ công tơ mét');
  let kmTruoc = null;

  const khungBH = h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Bảo hiểm'),
    h('div', { class: 'luoi-o hai-cot' },
      truongNgay('Ngày hết hạn bảo hiểm thân vỏ', oHanThanVo, saoThanVo, 'Ngày/tháng/năm. Dùng để nhắc khách gia hạn', tichThanVo),
      truongNgay('Ngày hết hạn bảo hiểm TNDS', oHan, saoTnds, 'Ngày/tháng/năm. Dùng để nhắc khách gia hạn', tichTnds)),
    h('p', { class: 'goi-y' }, 'Hãng bảo hiểm và giám định viên chọn khi nhập kết quả duyệt giá.'));

  const radioNguon = h('div', { class: 'chon-nut', role: 'radiogroup', 'aria-label': 'Xe bảo hiểm hay khách ngoài bảo hiểm' },
    [['bao_hiem', 'Xe bảo hiểm'], ['khach', 'Khách ngoài bảo hiểm']].map(([v, nhan], i) =>
      h('label', null, h('input', { type: 'radio', name: 'nguon_tt', value: v, checked: i === 0 }), h('span', null, nhan))));
  // Khách ngoài bảo hiểm: vẫn giữ hai ô ngày hết hạn nhưng không bắt buộc, không có dấu tích "Không có"
  const hienBH = () => {
    const bh = form.nguon_tt.value !== 'khach';
    tichThanVo.hidden = tichTnds.hidden = !bh;
    if (!bh) for (const [, oTich] of KHONG_BH) oTich.checked = false;
    doiKhongBH(false);
  };
  radioNguon.addEventListener('change', () => { hienBH(); capNhatNhac(); });

  // Yêu cầu khách hàng (cột tinh_trang_xe) và tư vấn: mỗi lần nhập có ngày ở đầu; lịch sử các lần trước hiện ngay trên
  const oTinhTrang = oVung('tinh_trang_xe', '', { rows: 3, placeholder: 'Khách muốn làm gì: sơn cản sau, kiểm tra tiếng kêu gầm, bảo dưỡng định kỳ…' });
  const oTuVan = oVung('tu_van', '', { rows: 3, placeholder: 'Bảo dưỡng, đồ chơi, detailing… (ghi "Không" nếu không có)' });
  tuGhiNgayKhiBam(oTinhTrang); tuGhiNgayKhiBam(oTuVan);
  const khungLichSu = h('div', { class: 'rong' });
  // Bảo hiểm đã hết hạn: tự ghi lời nhắc lên đầu ô tư vấn (cập nhật lại khi đổi ngày, không ghi trùng)
  let nhacCu = '';
  const capNhatNhac = () => {
    const nhac = [
      ...(oKhongThanVo.checked ? ['Khách không có BH thân vỏ – tư vấn mua bảo hiểm thân vỏ.'] : []),
      ...(oKhongTnds.checked ? ['Khách không có BH TNDS – tư vấn mua bảo hiểm TNDS.'] : []),
      ...nhacHetHan(vnSangIso(oHanThanVo.value), vnSangIso(oHan.value))];
    const dong = nhac.map((x) => `${homNayVN()}: ${x}`);
    const moi = dong.length ? dong.join('\n') + '\n' : '';
    let v = oTuVan.value;
    if (nhacCu && v.startsWith(nhacCu)) v = v.slice(nhacCu.length);
    oTuVan.value = moi + v;
    nhacCu = moi;
  };
  for (const o of [oHanThanVo, oHan]) { o.addEventListener('change', capNhatNhac); o.addEventListener('blur', capNhatNhac); }
  // Tích "Không có" loại nào thì khóa ô ngày loại đó, bỏ dấu * và ghi nhắc tư vấn
  function doiKhongBH(nhacLai = true) {
    const bh = form.nguon_tt.value !== 'khach';
    for (const [oNgay, oTich, sao] of KHONG_BH) {
      oNgay.disabled = oTich.checked;
      if (oTich.checked) oNgay.value = '';
      sao.hidden = !bh || oTich.checked;
    }
    if (nhacLai) capNhatNhac();
  }
  for (const [, oTich] of KHONG_BH) oTich.addEventListener('change', () => doiKhongBH());

  // 047: bắt buộc 6 ảnh nhận xe có tên (4 quanh xe + 2 nội thất); tải lên ngay sau khi tạo hồ sơ
  const khungAnh = khungAnhNhanXe();

  // Người thực hiện + giao bước tiếp theo (mặc định: chính CVDV tiếp nhận). Bảo hành: bước tiếp theo là lập lệnh sửa chữa
  const giao = hoSoGoc ? khungGiaoViec('Lập lệnh sửa chữa', VAI_TRO_BUOC.lenh) : khungGiaoViec('Lập báo giá', VAI_TRO_BUOC.bao_gia);
  giao.el.classList.add('nhom-o');
  // Hạng mục bảo hành: chọn trong các hạng mục đã làm của hồ sơ gốc, hoặc ghi thêm hạng mục khác
  const oHmKhac = oChu('hm_khac', '', { placeholder: 'Ví dụ: Sơn lại cửa trước trái' });
  const chonNhomKhac = oChon('hm_khac_nhom', NHOM_CHON.map((value) => ({ value, label: NHOM[value] })), 'son', { trong: null, 'aria-label': 'Nhóm hạng mục khác' });
  const khungBaoHanh = hoSoGoc ? h('fieldset', { class: 'nhom-o khung-bao-hanh' }, h('legend', null, 'Hạng mục bảo hành (làm lại miễn phí)'),
    h('p', { class: 'goi-y' }, `Tích các hạng mục của hồ sơ ${hoSoGoc.ma} phải làm lại. Không báo giá, không duyệt giá – lưu xong lập lệnh sửa chữa ngay.`),
    hangMucGoc.length ? h('div', { class: 'ds-hm-bao-hanh' }, hangMucGoc.map((m) => oCheck(`hm_${m.id}`, false, `${m.ten} (${NHOM[m.nhom] || m.nhom})`)))
      : h('p', { class: 'trong' }, 'Hồ sơ gốc không có hạng mục đã làm – ghi hạng mục bên dưới.'),
    h('div', { class: 'luoi-o' }, truong('Hạng mục khác (nếu có)', oHmKhac), truong('Nhóm', chonNhomKhac))) : null;
  const form = h('form', { class: 'the', novalidate: true },
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Thông tin xe'),
      h('div', { class: 'luoi-o' },
        truong('Biển số', oGoiY(oBienSo, {
          tim: api.goiYXe,
          ve: (x) => h('span', { class: 'goi-y-xe' }, bienSo(x.bien_so),
            h('span', null,
              h('span', null, [tenLoaiXe(x.dong_xe_id), x.mau].filter(Boolean).join(' – ') || 'Chưa rõ loại xe'),
              h('small', null, [x.khach && x.khach.ten !== 'Chưa có tên' ? x.khach.ten : null, x.khach?.dien_thoai].filter(Boolean).join(' – ') || 'Chưa có thông tin khách'))),
          chon: (x) => { oBienSo.value = vietBienSo(x.bien_so); traCuu(); },
        }), 'Gõ vài số (hoặc SĐT khách) để chọn xe cũ', { batBuoc: true, co: 'vua' }),
        thongBaoXe,
        truong('Hãng xe', chonHangXe, null, { batBuoc: true }),
        truong('Dòng xe', chonDongXe, null, { batBuoc: true }),
        truong('Màu', oMau),
        truong('Số km (ODD)', oKm, goiYKm, { batBuoc: true, co: 'vua' }))),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Khách hàng'),
      h('div', { class: 'luoi-o' },
        truong('Tên khách', oTen, null, { batBuoc: true }),
        truong('Số điện thoại', oSdt, 'Không gửi SĐT khách ra ngoài', { batBuoc: true }))),
    // Bảo hành: luôn là "khách" (không liên quan bảo hiểm) – ẩn phần chọn nguồn và bảo hiểm
    h('fieldset', { class: 'nhom-o', hidden: !!hoSoGoc }, h('legend', null, 'Xe bảo hiểm hay khách ngoài bảo hiểm'), radioNguon),
    hoSoGoc ? null : khungBH,
    khungBaoHanh,
    h('fieldset', { class: 'nhom-o' }, h('legend', null, hoSoGoc ? 'Lỗi khách phản ánh và tư vấn' : 'Yêu cầu khách hàng và tư vấn'),
      h('div', { class: 'luoi-o' },
        khungLichSu,
        truong(hoSoGoc ? 'Yêu cầu khách hàng (lỗi cần làm lại)' : 'Yêu cầu khách hàng', oTinhTrang, 'Ngày hôm nay tự thêm vào đầu khi bấm vào ô', { batBuoc: true, rong: true }),
        truong('Những gì có thể tư vấn', oTuVan, 'Anh Long dùng để tư vấn khi giao xe. Bảo hiểm hết hạn sẽ tự ghi nhắc ở đầu.', { batBuoc: true, rong: true }))),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Ảnh nhận xe – bắt buộc 6 ảnh'),
      h('p', { class: 'goi-y' }, 'Đủ 4 góc quanh xe và 2 ảnh nội thất. Bấm vào từng ô để chọn ảnh trong máy, hoặc "Chọn nhiều ảnh một lần" (điền lần lượt vào ô trống).'), khungAnh),
    // 050: sửa xong → tổ Detailing rửa xe, đánh bóng → KCS. Xe không cần thì tích (đổi lại được trong hồ sơ trước khi KCS)
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Detailing trước KCS'),
      oCheck('khong_qua_detailing', false, 'Không qua Detailing (xe không cần rửa, đánh bóng trước khi KCS)'),
      h('p', { class: 'goi-y' }, 'Mặc định: sửa xong, tổ Detailing rửa xe, đánh bóng rồi mới KCS.')),
    giao.el,
    h('div', { class: 'hang-nut' },
      h('a', { class: 'nut', href: '#/ho-so' }, 'Hủy'),
      h('button', { class: 'nut chinh', type: 'submit' }, 'Lưu hồ sơ')));
  hienBH();

  // Tra cứu xe cũ khi nhập xong biển số
  let daTraCuu = null;
  async function traCuu() {
    const bs = oBienSo.value.trim();
    const gon = bs.toUpperCase().replace(/[^0-9A-Z]/g, '');
    if (gon === daTraCuu) return; // vừa tra xe này rồi (chọn từ gợi ý rồi rời ô)
    daTraCuu = gon;
    thongBaoXe.hidden = true;
    dat(khungLichSu);
    kmTruoc = null; dat(goiYKm, 'Số trên đồng hồ công tơ mét');
    if (!bs) return;
    try {
      const x = await api.traCuuXe(bs);
      if (!x) { thongBaoXe.hidden = false; thongBaoXe.className = 'thong-bao'; thongBaoXe.textContent = 'Xe mới, chưa từng vào gara.'; return; }
      oBienSo.value = x.bien_so;
      if (x.hang_xe_id) { chonHangXe.value = x.hang_xe_id; capNhatDongXe(x.dong_xe_id); }
      if (x.mau && !oMau.value) oMau.value = x.mau;
      if (!oTen.value && x.ten_khach !== 'Chưa có tên') oTen.value = x.ten_khach || '';
      if (!oSdt.value) oSdt.value = x.dien_thoai || '';
      if (x.han_bao_hiem && !oHan.value && !oKhongTnds.checked) oHan.value = isoSangVN(x.han_bao_hiem);
      if (x.han_bh_than_vo && !oHanThanVo.value && !oKhongThanVo.checked) oHanThanVo.value = isoSangVN(x.han_bh_than_vo);
      const g = x.ho_so_gan_nhat;
      if (g) {
        for (const r of form.querySelectorAll('input[name=nguon_tt]')) r.checked = r.value === (g.nguon_tt === 'khach' ? 'khach' : 'bao_hiem');
        hienBH();
      }
      capNhatNhac();
      layLichSu(x.xe_id).then((ds) => {
        dat(khungLichSu, khoiLichSu(ds));
        const coKm = ds.find((y) => y.so_km !== null && y.so_km !== undefined);
        kmTruoc = coKm ? { so: Number(coKm.so_km), ngay: coKm.ngay_vao } : null;
        dat(goiYKm, kmTruoc ? `Lần trước: ${tien(kmTruoc.so)} km (${ngay(kmTruoc.ngay)})` : 'Số trên đồng hồ công tơ mét');
      }).catch(() => {});
      thongBaoXe.hidden = false;
      thongBaoXe.className = x.ho_so_mo ? 'thong-bao canh-bao' : 'thong-bao';
      dat(thongBaoXe, `Xe cũ, đã vào gara ${x.so_lan_vao} lần. Đã tự điền thông tin của lần trước – kiểm tra lại. Lịch sử yêu cầu, tư vấn, phản hồi ở mục "Yêu cầu khách hàng và tư vấn".`,
        x.ho_so_mo ? h('div', null, 'Đang có hồ sơ chưa đóng: ', x.ho_so_mo.map((m) => h('a', { href: `#/ho-so/${m.id}` }, m.ma, ' '))) : null);
    } catch (e) { /* chỉ là gợi ý, bỏ qua lỗi */ }
  }
  oBienSo.addEventListener('change', traCuu);

  // Chống gửi 2 lần (bấm đúp, Enter khi đang hỏi xác nhận số km) → không tạo trùng hồ sơ
  khoaKhiGui(form, async () => {
    const d = docForm(form);
    if (!d.bien_so) { oBienSo.focus(); return toast('Nhập biển số xe.', 'loi'); }
    const bh = !hoSoGoc && d.nguon_tt !== 'khach';
    // Bảo hành: ít nhất một hạng mục làm lại (tích từ hồ sơ gốc hoặc ghi thêm)
    const hangMucBH = hoSoGoc ? [
      ...hangMucGoc.filter((m) => d[`hm_${m.id}`]).map((m) => ({ ten: m.ten, nhom: m.nhom })),
      ...(d.hm_khac ? [{ ten: d.hm_khac, nhom: d.hm_khac_nhom || 'son' }] : [])] : [];
    if (hoSoGoc && !hangMucBH.length) { (hangMucGoc.length ? form.querySelector('.ds-hm-bao-hanh input') : oHmKhac)?.focus(); return toast('Tích hoặc ghi ít nhất một hạng mục bảo hành.', 'loi'); }
    for (const [o, v, ten, khong] of [[oHanThanVo, d.han_bh_than_vo, 'thân vỏ', d.khong_than_vo], [oHan, d.han_bao_hiem, 'TNDS', d.khong_tnds]]) {
      if (v === 'sai') { o.focus(); return toast(`Ngày hết hạn bảo hiểm ${ten} không đúng. Nhập dạng ngày/tháng/năm, ví dụ 01/03/2027.`, 'loi'); }
      if (bh && !v && !khong) { o.focus(); return toast(`Xe bảo hiểm: nhập ngày hết hạn bảo hiểm ${ten}, hoặc tích "Không có BH ${ten}".`, 'loi'); }
    }
    d.tinh_trang_xe = themNgay(d.tinh_trang_xe); d.tu_van = themNgay(d.tu_van);
    if (!d.tinh_trang_xe) { oTinhTrang.focus(); return toast('Ghi yêu cầu của khách hàng.', 'loi'); }
    if (d.so_km === null) { oKm.focus(); return toast('Ghi số km (ODD) của xe.', 'loi'); }
    if (d.so_km > 9999999) { oKm.focus(); return toast('Số km (ODD) không đúng.', 'loi'); }
    if (d.so_km !== null && kmTruoc && d.so_km < kmTruoc.so
      && !(await xacNhan(`Số km ${tien(d.so_km)} nhỏ hơn lần trước (${tien(kmTruoc.so)} km). Vẫn lưu?`, 'Vẫn lưu'))) { oKm.focus(); return; }
    if (!d.tu_van) { oTuVan.focus(); return toast('Ghi những gì có thể tư vấn (ghi "Không" nếu không có).', 'loi'); }
    const thieuAnh = khungAnh.thieu();
    if (thieuAnh.length) {
      khungAnh.danhDauThieu();
      khungAnh.scrollIntoView({ block: 'center', behavior: 'smooth' });
      return toast(`Tải đủ 6 ảnh nhận xe – còn thiếu: ${thieuAnh.map((a) => a.ten.toLowerCase()).join(', ')}.`, 'loi');
    }
    const p = {
      bien_so: d.bien_so, ten_khach: d.ten_khach, dien_thoai: d.dien_thoai,
      dong_xe_id: d.dong_xe_id, mau: d.mau, nguon_tt: hoSoGoc ? 'khach' : d.nguon_tt,
      ngay_vao: null,   // không nhập: máy chủ ghi đúng lúc lưu hồ sơ (vẫn hiện "Vào xưởng" trong hồ sơ)
      hang_bh_id: null, gdv_id: null, gdv_ten_tam: null, bh_khi_duyet: true,   // 048: hãng BH / GDV chọn lúc duyệt giá
      han_bao_hiem: d.han_bao_hiem, han_bh_than_vo: d.han_bh_than_vo, tinh_trang_xe: d.tinh_trang_xe, tu_van: d.tu_van, so_km: d.so_km, bat_buoc_km: true,
      loai: hoSoGoc ? 'bao_hanh' : 'sua_chua', ho_so_goc_id: hoSoGoc ? hoSoGoc.id : null,
      hang_muc: hoSoGoc ? hangMucBH : undefined,
      bat_buoc_anh: true,   // 047: hồ sơ này bắt ảnh / file ở các bước sau (máy chủ kiểm)
      qua_detailing: !d.khong_qua_detailing,   // 050: có bước Detailing trước KCS
    };
    const nut = form.querySelector('button[type=submit]');
    nut.disabled = true; nut.textContent = 'Đang lưu…';
    try {
      const kq = await chay((boQua) => api.tiepNhanXe({ ...p, bo_qua_canh_bao: boQua }));
      nut.textContent = 'Đang tải ảnh…';
      await giaoSauKhiLuu(kq.id, giao.nguoi());
      const hoSo = { id: kq.id, ma: kq.ma, chi_nhanh_id: kq.chi_nhanh_id || api.toi.chi_nhanh_id };
      // 6 ảnh nhận xe tải song song (nén lần lượt), báo tiến độ trên nút
      let daTai = 0; let loiAnh = 0;
      const tong = khungAnh.chon.size;
      await Promise.all([...khungAnh.chon].map(async ([buoc, f]) => {
        loiAnh += await taiVaoBuoc(hoSo, buoc, [f]);
        daTai++; nut.textContent = `Đang tải ảnh ${daTai}/${tong}…`;
      }));
      const daTao = hoSoGoc ? `Đã tạo hồ sơ bảo hành ${kq.ma} – lập lệnh sửa chữa được ngay` : `Đã tạo hồ sơ ${kq.ma}`;
      toast(loiAnh ? `${daTao}, nhưng ${loiAnh} ảnh tải lên lỗi – tải lại ở mục "Ảnh nhận xe" trong hồ sơ.` : daTao, loiAnh ? 'loi' : 'ok');
      veDanhSachHoSo({ id: kq.id, ma: kq.ma });
      return true;   // đã tạo hồ sơ: giữ khóa nút, không cho gửi lại trong lúc chuyển trang
    } catch {
      nut.disabled = false; nut.textContent = 'Lưu hồ sơ';
    }
  });

  // Hồ sơ bảo hành: mở từ hồ sơ cũ đã đóng – điền sẵn xe, khách; luôn là nguồn "khách" (không liên quan bảo hiểm)
  if (hoSoGoc) {
    oBienSo.value = hoSoGoc.bien_so_hien_thi || '';
    await traCuu();
    for (const r of form.querySelectorAll('input[name=nguon_tt]')) r.checked = r.value === 'khach';
    hienBH();
    oBienSo.readOnly = true;
    form.prepend(h('p', { class: 'thong-bao canh-bao' }, `Bảo hành cho xe quay lại vì lỗi cũ của hồ sơ ${hoSoGoc.ma}: làm lại miễn phí, không báo giá, không duyệt giá, không tính doanh thu.`));
  }

  // Tiếp nhận lại xe từ một hồ sơ cũ: điền sẵn biển số rồi tự tra cứu – xe, khách, bảo hiểm, GĐV, hạn BH, lịch sử
  const tuHoSo = !baoHanh && thamSoUrl.get('tu_ho_so');
  if (tuHoSo) {
    const cu = await api.layHoSo(tuHoSo);
    if (cu?.bien_so_hien_thi) {
      oBienSo.value = cu.bien_so_hien_thi;
      await traCuu();
      form.prepend(h('p', { class: 'thong-bao' }, `Đã điền sẵn thông tin từ hồ sơ ${cu.ma}. Kiểm tra lại, ghi tình trạng và tư vấn lần này rồi lưu.`));
    }
  }

  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, hoSoGoc ? 'Tiếp nhận xe bảo hành' : 'Tiếp nhận xe'),
    h('p', { class: 'mo-ta' }, hoSoGoc ? 'Bước 1 · CVDV. Chọn hạng mục làm lại, ghi lỗi khách phản ánh rồi lưu – sang thẳng lệnh sửa chữa.' : 'Bước 1 · CVDV · trong 30 phút. Mục có dấu * là bắt buộc.')), form);
  if (tuHoSo || hoSoGoc) oTinhTrang.focus(); else oBienSo.focus();
}
