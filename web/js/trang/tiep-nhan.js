// Bước 1: Tiếp nhận xe – 10 thông tin bắt buộc + ảnh nhận xe
import { h, oChonTep, truong, oChu, oChon, oVung, oNgayVN, isoSangVN, docForm, chay, toast, nenAnh, choODatetime, dat } from '../ui.js';
import * as api from '../api.js';

export default async function trangTiepNhan(el) {
  if (!api.coVaiTro('cvdv', 'quan_ly', 'giam_doc')) {
    dat(el, h('p', { class: 'trong' }, 'Chỉ CVDV, quản lý chung và giám đốc được tiếp nhận xe.'));
    return;
  }
  const dm = api.dm;
  const chonHangXe = oChon('hang_xe_id', dm.hang_xe.map((x) => ({ value: x.id, label: x.ten })), null, { required: true });
  const chonDongXe = oChon('dong_xe_id', [], null, { required: true });
  const capNhatDongXe = (giu) => {
    const ds = dm.dong_xe.filter((d) => String(d.hang_xe_id) === chonHangXe.value);
    dat(chonDongXe, h('option', { value: '' }, '— Chọn —'), ds.map((d) => h('option', { value: d.id }, d.ten)));
    if (giu) chonDongXe.value = giu;
  };
  chonHangXe.addEventListener('change', () => capNhatDongXe());

  const chonHangBH = oChon('hang_bh_id', dm.hang_bao_hiem.filter((x) => x.hoat_dong).map((x) => ({ value: x.id, label: x.ten })), null);
  const chonGdv = oChon('gdv_id', [], null);
  const oGdvMoi = oChu('gdv_ten_tam', '', { placeholder: 'Tên giám định viên mới' });
  const khungGdvMoi = truong('Tên GDV mới', oGdvMoi, 'Kế toán sẽ thêm người này vào danh sách trong Cài đặt.', { batBuoc: true });
  const capNhatBH = (giuGdv) => {
    const hang = chonHangBH.value;
    const gdv = dm.giam_dinh_vien.filter((g) => g.hoat_dong && (g.la_cho_them || !g.hang_id || String(g.hang_id) === hang))
      .sort((a, b) => (b.la_cho_them - a.la_cho_them) || ((String(b.hang_id) === hang) - (String(a.hang_id) === hang)) || a.ten.localeCompare(b.ten, 'vi'));
    dat(chonGdv, h('option', { value: '' }, '— Chọn —'),
      gdv.map((g) => h('option', { value: g.id }, g.la_cho_them ? g.ten : `${g.ten}${g.hang_id ? ` (${dm.ten('hang_bao_hiem', g.hang_id)})` : ''}`)));
    if (giuGdv) chonGdv.value = giuGdv;
    hienGdvMoi();
  };
  const hienGdvMoi = () => {
    const g = dm.giam_dinh_vien.find((x) => String(x.id) === chonGdv.value);
    khungGdvMoi.hidden = !g?.la_cho_them;
  };
  chonHangBH.addEventListener('change', () => capNhatBH());
  // Hai ngày hết hạn bảo hiểm: luôn hiện; bắt buộc với xe bảo hiểm, khách ngoài bảo hiểm thì không bắt buộc
  const oHanThanVo = oNgayVN('han_bh_than_vo');
  const oHan = oNgayVN('han_bao_hiem');
  const sao = () => h('b', { class: 'bat-buoc', 'aria-hidden': 'true' }, ' *');
  const saoThanVo = sao(); const saoTnds = sao();
  const truongNgay = (nhan, o, s, goiY) => h('label', { class: 'truong' },
    h('span', { class: 'truong-nhan' }, nhan, s), o, h('small', { class: 'goi-y' }, goiY));
  chonGdv.addEventListener('change', hienGdvMoi);

  const oBienSo = oChu('bien_so', '', { placeholder: 'Ví dụ 50H-923.61', autocapitalize: 'characters', autocomplete: 'off' });
  const thongBaoXe = h('div', { class: 'thong-bao', hidden: true });
  const oTen = oChu('ten_khach', '', { autocomplete: 'off' });
  const oSdt = oChu('dien_thoai', '', { inputmode: 'tel', placeholder: '09xxxxxxxx', autocomplete: 'off' });
  const oMau = oChu('mau', '', { placeholder: 'Trắng, đỏ…' });

  const truongHangBH = truong('Hãng bảo hiểm', chonHangBH, null, { batBuoc: true });
  const truongGdv = truong('Giám định viên', chonGdv, null, { batBuoc: true });
  const khungBH = h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Bảo hiểm'),
    h('div', { class: 'luoi-o hai-cot' },
      truongHangBH,
      truongNgay('Ngày hết hạn bảo hiểm thân vỏ', oHanThanVo, saoThanVo, 'Ngày/tháng/năm. Dùng để nhắc khách gia hạn'),
      truongGdv,
      truongNgay('Ngày hết hạn bảo hiểm TNDS', oHan, saoTnds, 'Ngày/tháng/năm. Dùng để nhắc khách gia hạn'),
      khungGdvMoi));
  khungGdvMoi.hidden = true;

  const radioNguon = h('div', { class: 'chon-nut', role: 'radiogroup', 'aria-label': 'Xe bảo hiểm hay khách ngoài bảo hiểm' },
    [['bao_hiem', 'Xe bảo hiểm'], ['khach', 'Khách ngoài bảo hiểm']].map(([v, nhan], i) =>
      h('label', null, h('input', { type: 'radio', name: 'nguon_tt', value: v, checked: i === 0 }), h('span', null, nhan))));
  // Khách ngoài bảo hiểm: ẩn hãng bảo hiểm và giám định viên, vẫn giữ hai ô ngày hết hạn nhưng không bắt buộc
  const hienBH = () => {
    const bh = form.nguon_tt.value !== 'khach';
    truongHangBH.hidden = !bh; truongGdv.hidden = !bh;
    if (!bh) khungGdvMoi.hidden = true; else hienGdvMoi();
    saoThanVo.hidden = !bh; saoTnds.hidden = !bh;
  };
  radioNguon.addEventListener('change', hienBH);

  const chonAnh = oChonTep({ name: 'anh', capture: 'environment', multiple: true }, 'Chụp ảnh xe');
  const oAnh = chonAnh.input;
  const xemAnh = h('div', { class: 'xem-anh' });
  oAnh.addEventListener('change', () => {
    dat(xemAnh, ...[...oAnh.files].map((f) => h('img', { src: URL.createObjectURL(f), alt: f.name })));
  });

  const form = h('form', { class: 'the', novalidate: true },
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Thông tin xe'),
      h('div', { class: 'luoi-o' },
        truong('Biển số', oBienSo, null, { batBuoc: true }),
        thongBaoXe,
        truong('Hãng xe', chonHangXe, null, { batBuoc: true }),
        truong('Dòng xe', chonDongXe, null, { batBuoc: true }),
        truong('Màu', oMau),
        truong('Ngày giờ vào', h('input', { type: 'datetime-local', name: 'ngay_vao', value: choODatetime(new Date()) }), null, { batBuoc: true }))),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Khách hàng'),
      h('div', { class: 'luoi-o' },
        truong('Tên khách', oTen, null, { batBuoc: true }),
        truong('Số điện thoại', oSdt, 'Không gửi SĐT khách ra ngoài', { batBuoc: true }))),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Xe bảo hiểm hay khách ngoài bảo hiểm'), radioNguon),
    khungBH,
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Tình trạng và tư vấn'),
      h('div', { class: 'luoi-o' },
        truong('Tình trạng chung của xe', oVung('tinh_trang_xe', '', { rows: 3, placeholder: 'Ngoại thất, đồ trên xe, hư hỏng thấy được…' }), null, { batBuoc: true, rong: true }),
        truong('Những gì có thể tư vấn', oVung('tu_van', '', { rows: 2, placeholder: 'Bảo dưỡng, đồ chơi, detailing… (ghi "Không" nếu không có)' }), 'Anh Long dùng để tư vấn khi giao xe', { batBuoc: true, rong: true }))),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Ảnh nhận xe'),
      truong('Ảnh xe lúc nhận', chonAnh, 'Bắt buộc có ít nhất 1 ảnh trước khi lập báo giá', { batBuoc: true }), xemAnh),
    h('div', { class: 'hang-nut' },
      h('a', { class: 'nut', href: '#/ho-so' }, 'Hủy'),
      h('button', { class: 'nut chinh', type: 'submit' }, 'Lưu hồ sơ')));
  hienBH();

  // Tra cứu xe cũ khi nhập xong biển số
  async function traCuu() {
    const bs = oBienSo.value.trim();
    thongBaoXe.hidden = true;
    if (!bs) return;
    try {
      const x = await api.traCuuXe(bs);
      if (!x) { thongBaoXe.hidden = false; thongBaoXe.className = 'thong-bao'; thongBaoXe.textContent = 'Xe mới, chưa từng vào gara.'; return; }
      oBienSo.value = x.bien_so;
      if (x.hang_xe_id) { chonHangXe.value = x.hang_xe_id; capNhatDongXe(x.dong_xe_id); }
      if (x.mau && !oMau.value) oMau.value = x.mau;
      if (!oTen.value) oTen.value = x.ten_khach || '';
      if (!oSdt.value) oSdt.value = x.dien_thoai || '';
      if (x.han_bao_hiem && !oHan.value) oHan.value = isoSangVN(x.han_bao_hiem);
      if (x.han_bh_than_vo && !oHanThanVo.value) oHanThanVo.value = isoSangVN(x.han_bh_than_vo);
      const g = x.ho_so_gan_nhat;
      if (g && g.nguon_tt !== 'khach' && g.hang_bh_id) { chonHangBH.value = g.hang_bh_id; capNhatBH(g.gdv_id); }
      thongBaoXe.hidden = false;
      thongBaoXe.className = x.ho_so_mo ? 'thong-bao canh-bao' : 'thong-bao';
      dat(thongBaoXe, `Xe cũ, đã vào gara ${x.so_lan_vao} lần. Đã tự điền khách và loại xe – kiểm tra lại.`,
        x.ho_so_mo ? h('div', null, 'Đang có hồ sơ chưa đóng: ', x.ho_so_mo.map((m) => h('a', { href: `#/ho-so/${m.id}` }, m.ma, ' '))) : null);
    } catch (e) { /* chỉ là gợi ý, bỏ qua lỗi */ }
  }
  oBienSo.addEventListener('change', traCuu);

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const d = docForm(form);
    if (!d.bien_so) { oBienSo.focus(); return toast('Nhập biển số xe.', 'loi'); }
    const bh = d.nguon_tt !== 'khach';
    for (const [o, v, ten] of [[oHanThanVo, d.han_bh_than_vo, 'thân vỏ'], [oHan, d.han_bao_hiem, 'TNDS']]) {
      if (v === 'sai') { o.focus(); return toast(`Ngày hết hạn bảo hiểm ${ten} không đúng. Nhập dạng ngày/tháng/năm, ví dụ 01/03/2027.`, 'loi'); }
      if (bh && !v) { o.focus(); return toast(`Xe bảo hiểm: nhập ngày hết hạn bảo hiểm ${ten}.`, 'loi'); }
    }
    if (!oAnh.files.length) return toast('Chụp ít nhất 1 ảnh nhận xe.', 'loi');
    const p = {
      bien_so: d.bien_so, ten_khach: d.ten_khach, dien_thoai: d.dien_thoai,
      dong_xe_id: d.dong_xe_id, mau: d.mau, nguon_tt: d.nguon_tt,
      ngay_vao: d.ngay_vao ? new Date(d.ngay_vao).toISOString() : null,
      hang_bh_id: d.hang_bh_id, gdv_id: d.gdv_id, gdv_ten_tam: d.gdv_ten_tam,
      han_bao_hiem: d.han_bao_hiem, han_bh_than_vo: d.han_bh_than_vo, tinh_trang_xe: d.tinh_trang_xe, tu_van: d.tu_van,
      loai: hoSoGoc ? 'bao_hanh' : 'sua_chua', ho_so_goc_id: hoSoGoc ? hoSoGoc.id : null,
    };
    const nut = form.querySelector('button[type=submit]');
    nut.disabled = true; nut.textContent = 'Đang lưu…';
    try {
      const kq = await chay((boQua) => api.tiepNhanXe({ ...p, bo_qua_canh_bao: boQua }));
      nut.textContent = 'Đang tải ảnh…';
      const hoSo = { id: kq.id, ma: kq.ma, chi_nhanh_id: api.toi.chi_nhanh_id };
      let loiAnh = 0;
      for (const f of oAnh.files) {
        try { await api.taiTep(hoSo, 'tiep_nhan', await nenAnh(f)); } catch { loiAnh++; }
      }
      toast(loiAnh ? `Đã tạo hồ sơ ${kq.ma}, nhưng ${loiAnh} ảnh tải lên lỗi – tải lại trong hồ sơ.` : `Đã tạo hồ sơ ${kq.ma}`, loiAnh ? 'loi' : 'ok');
      location.hash = `#/ho-so/${kq.id}`;
    } catch {
      nut.disabled = false; nut.textContent = 'Lưu hồ sơ';
    }
  });

  // Hồ sơ bảo hành: mở từ hồ sơ cũ đã đóng
  const baoHanh = new URLSearchParams(location.hash.split('?')[1] || '').get('bao_hanh');
  let hoSoGoc = null;
  if (baoHanh) {
    hoSoGoc = await api.layHoSo(baoHanh);
    if (hoSoGoc) {
      oBienSo.value = hoSoGoc.bien_so_hien_thi || '';
      await traCuu();
      oBienSo.readOnly = true;
      form.prepend(h('p', { class: 'thong-bao canh-bao' }, `Hồ sơ bảo hành cho xe quay lại vì lỗi cũ của ${hoSoGoc.ma}. Không tính doanh thu.`));
    }
  }

  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, hoSoGoc ? 'Tiếp nhận xe bảo hành' : 'Tiếp nhận xe'),
    h('p', { class: 'mo-ta' }, 'Bước 1 · CVDV · trong 30 phút. Mục có dấu * là bắt buộc.')), form);
  oBienSo.focus();
}
