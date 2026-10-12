// Bước 1: Tiếp nhận xe – 10 thông tin bắt buộc + ảnh nhận xe
import { h, oGoiY, bienSo, vietBienSo, oChonTep, oCheck, truong, oChu, oChon, oVung, oNgayVN, isoSangVN, vnSangIso, docForm, chay, toast, nenAnh, choODatetime, dat, veDanhSachHoSo } from '../ui.js';
import * as api from '../api.js';
import { khungGiaoViec, giaoSauKhiLuu, VAI_TRO_BUOC } from './giao-viec.js';
import { homNayVN, themNgay, tuGhiNgayKhiBam, nhacHetHan, layLichSu, khoiLichSu } from './lich-su-xe.js';

export default async function trangTiepNhan(el) {
  if (!api.coVaiTro('cvdv', 'quan_ly', 'giam_doc')) {
    dat(el, h('p', { class: 'trong' }, 'Chỉ CVDV, quản lý chung và giám đốc được tiếp nhận xe.'));
    return;
  }
  const dm = api.dm;
  const tenLoaiXe = (idDong) => {
    const d = dm.dong_xe.find((x) => String(x.id) === String(idDong));
    return d ? `${dm.ten('hang_xe', d.hang_xe_id)} ${d.ten}` : '';
  };
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
  // Xe bảo hiểm: mỗi loại bảo hiểm có dấu tích "Không có" riêng ngay dưới ô ngày (khách ngoài bảo hiểm không có dấu tích)
  const tichThanVo = oCheck('khong_than_vo', false, 'Không có BH thân vỏ');
  const tichTnds = oCheck('khong_tnds', false, 'Không có BH TNDS');
  const truongNgay = (nhan, o, s, goiY, tich) => h('div', { class: 'truong truong-ngay-bh' },
    h('label', null, h('span', { class: 'truong-nhan' }, nhan, s), o), h('small', { class: 'goi-y' }, goiY), tich);
  const oKhongThanVo = tichThanVo.querySelector('input');
  const oKhongTnds = tichTnds.querySelector('input');
  const KHONG_BH = [[oHanThanVo, oKhongThanVo, saoThanVo], [oHan, oKhongTnds, saoTnds]];
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
      truongNgay('Ngày hết hạn bảo hiểm thân vỏ', oHanThanVo, saoThanVo, 'Ngày/tháng/năm. Dùng để nhắc khách gia hạn', tichThanVo),
      truongGdv,
      truongNgay('Ngày hết hạn bảo hiểm TNDS', oHan, saoTnds, 'Ngày/tháng/năm. Dùng để nhắc khách gia hạn', tichTnds),
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
    tichThanVo.hidden = tichTnds.hidden = !bh;
    if (!bh) for (const [, oTich] of KHONG_BH) oTich.checked = false;
    doiKhongBH(false);
  };
  radioNguon.addEventListener('change', () => { hienBH(); capNhatNhac(); });

  // Tình trạng và tư vấn: mỗi lần nhập có ngày ở đầu; lịch sử các lần trước hiện ngay trên
  const oTinhTrang = oVung('tinh_trang_xe', '', { rows: 3, placeholder: 'Ngoại thất, đồ trên xe, hư hỏng thấy được…' });
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

  const chonAnh = oChonTep({ name: 'anh', capture: 'environment', multiple: true }, 'Chụp ảnh xe');
  const oAnh = chonAnh.input;
  const xemAnh = h('div', { class: 'xem-anh' });
  oAnh.addEventListener('change', () => {
    dat(xemAnh, ...[...oAnh.files].map((f) => h('img', { src: URL.createObjectURL(f), alt: f.name })));
  });

  // Người thực hiện + giao bước báo giá (mặc định: chính CVDV tiếp nhận)
  const giao = khungGiaoViec('Lập báo giá', VAI_TRO_BUOC.bao_gia);
  giao.el.classList.add('nhom-o');
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
        }), 'Gõ vài số của biển số (hoặc SĐT khách) để chọn xe cũ', { batBuoc: true }),
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
        khungLichSu,
        truong('Tình trạng chung của xe', oTinhTrang, 'Ngày hôm nay tự thêm vào đầu khi bấm vào ô', { batBuoc: true, rong: true }),
        truong('Những gì có thể tư vấn', oTuVan, 'Anh Long dùng để tư vấn khi giao xe. Bảo hiểm hết hạn sẽ tự ghi nhắc ở đầu.', { batBuoc: true, rong: true }))),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Ảnh nhận xe'),
      truong('Ảnh xe lúc nhận', chonAnh, 'Không bắt buộc. Có thể chụp bổ sung sau trong hồ sơ.'), xemAnh),
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
      if (g && g.nguon_tt !== 'khach' && g.hang_bh_id) { chonHangBH.value = g.hang_bh_id; capNhatBH(g.gdv_id); }
      capNhatNhac();
      layLichSu(x.xe_id).then((ds) => dat(khungLichSu, khoiLichSu(ds))).catch(() => {});
      thongBaoXe.hidden = false;
      thongBaoXe.className = x.ho_so_mo ? 'thong-bao canh-bao' : 'thong-bao';
      dat(thongBaoXe, `Xe cũ, đã vào gara ${x.so_lan_vao} lần. Đã tự điền thông tin của lần trước – kiểm tra lại. Lịch sử tình trạng, tư vấn, phản hồi ở mục "Tình trạng và tư vấn".`,
        x.ho_so_mo ? h('div', null, 'Đang có hồ sơ chưa đóng: ', x.ho_so_mo.map((m) => h('a', { href: `#/ho-so/${m.id}` }, m.ma, ' '))) : null);
    } catch (e) { /* chỉ là gợi ý, bỏ qua lỗi */ }
  }
  oBienSo.addEventListener('change', traCuu);

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const d = docForm(form);
    if (!d.bien_so) { oBienSo.focus(); return toast('Nhập biển số xe.', 'loi'); }
    const bh = d.nguon_tt !== 'khach';
    for (const [o, v, ten, khong] of [[oHanThanVo, d.han_bh_than_vo, 'thân vỏ', d.khong_than_vo], [oHan, d.han_bao_hiem, 'TNDS', d.khong_tnds]]) {
      if (v === 'sai') { o.focus(); return toast(`Ngày hết hạn bảo hiểm ${ten} không đúng. Nhập dạng ngày/tháng/năm, ví dụ 01/03/2027.`, 'loi'); }
      if (bh && !v && !khong) { o.focus(); return toast(`Xe bảo hiểm: nhập ngày hết hạn bảo hiểm ${ten}, hoặc tích "Không có BH ${ten}".`, 'loi'); }
    }
    d.tinh_trang_xe = themNgay(d.tinh_trang_xe); d.tu_van = themNgay(d.tu_van);
    if (!d.tinh_trang_xe) { oTinhTrang.focus(); return toast('Ghi tình trạng chung của xe.', 'loi'); }
    if (!d.tu_van) { oTuVan.focus(); return toast('Ghi những gì có thể tư vấn (ghi "Không" nếu không có).', 'loi'); }
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
      await giaoSauKhiLuu(kq.id, giao.nguoi());
      const hoSo = { id: kq.id, ma: kq.ma, chi_nhanh_id: api.toi.chi_nhanh_id };
      let loiAnh = 0;
      for (const f of oAnh.files) {
        try { await api.taiTep(hoSo, 'tiep_nhan', await nenAnh(f)); } catch { loiAnh++; }
      }
      toast(loiAnh ? `Đã tạo hồ sơ ${kq.ma}, nhưng ${loiAnh} ảnh tải lên lỗi – tải lại trong hồ sơ.` : `Đã tạo hồ sơ ${kq.ma}`, loiAnh ? 'loi' : 'ok');
      veDanhSachHoSo({ id: kq.id, ma: kq.ma });
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

  // Tiếp nhận lại xe từ một hồ sơ cũ: điền sẵn biển số rồi tự tra cứu – xe, khách, bảo hiểm, GĐV, hạn BH, lịch sử
  const tuHoSo = !baoHanh && new URLSearchParams(location.hash.split('?')[1] || '').get('tu_ho_so');
  if (tuHoSo) {
    const cu = await api.layHoSo(tuHoSo);
    if (cu?.bien_so_hien_thi) {
      oBienSo.value = cu.bien_so_hien_thi;
      await traCuu();
      form.prepend(h('p', { class: 'thong-bao' }, `Đã điền sẵn thông tin từ hồ sơ ${cu.ma}. Kiểm tra lại, ghi tình trạng và tư vấn lần này rồi lưu.`));
    }
  }

  dat(el, h('div', { class: 'tieu-de-trang' }, h('h1', null, hoSoGoc ? 'Tiếp nhận xe bảo hành' : 'Tiếp nhận xe'),
    h('p', { class: 'mo-ta' }, 'Bước 1 · CVDV · trong 30 phút. Mục có dấu * là bắt buộc.')), form);
  if (tuHoSo) oTinhTrang.focus(); else oBienSo.focus();
}
