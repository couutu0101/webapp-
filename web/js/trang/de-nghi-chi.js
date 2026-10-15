// Đề nghị chi → duyệt (quản lý chung đến 2 triệu, trên 2 triệu giám đốc) → kế toán chi
import { h, tien, docTien, ngay, homNay, truong, oChu, oTien, oChon, oNgay, docForm, chay, bang, moModal, toast, dat, thanhThe, hoiLyDo } from '../ui.js';
import * as api from '../api.js';

const TT = { cho_duyet: 'Chờ duyệt', da_duyet: 'Đã duyệt – chờ chi', tu_choi: 'Từ chối', da_chi: 'Đã chi', huy: 'Đã hủy' };

export default async function trangDeNghi(el) {
  const nguoiDuyet = api.coVaiTro('quan_ly', 'giam_doc');
  const keToan = api.coVaiTro('ke_toan', 'giam_doc');
  const hanMuc = api.caiDat('han_muc_chi_quan_ly', 2000000);
  let loc = nguoiDuyet ? 'cho_duyet' : keToan ? 'da_duyet' : 'cua_toi';
  const ds = h('div');
  const LOC = [
    nguoiDuyet ? ['cho_duyet', 'Chờ duyệt'] : null,
    keToan ? ['da_duyet', 'Chờ chi'] : null,
    ['cua_toi', 'Của tôi'],
    nguoiDuyet || keToan ? ['tat', 'Tất cả (60 ngày)'] : null,
  ].filter(Boolean);
  const tabs = thanhThe(LOC, loc, (ma) => { loc = ma; tai(); }, { nhan: 'Lọc đề nghị chi' });

  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Đề nghị chi'),
      api.laCoDong() ? null : h('button', { class: 'nut chinh', type: 'button', onclick: () => moLap() }, '+ Lập đề nghị chi')),
    h('p', { class: 'mo-ta' }, `Mọi khoản chi đều qua đề nghị. Quản lý chung duyệt đến ${tien(hanMuc)} đ, trên mức này giám đốc duyệt. Không ai tự duyệt đề nghị của mình. Kế toán chỉ chi khi đã duyệt.`),
    h('section', { class: 'the' }, tabs, ds));

  async function tai() {
    dat(ds, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    const rows = await api.doc('v_de_nghi_chi', (q) => {
      if (loc === 'cho_duyet') q = q.eq('trang_thai', 'cho_duyet');
      else if (loc === 'da_duyet') q = q.eq('trang_thai', 'da_duyet');
      else if (loc === 'cua_toi') q = q.eq('nguoi_de_nghi', api.toi.id);
      else q = q.gte('ngay', new Date(Date.now() - 60 * 864e5).toISOString().slice(0, 10));
      return q.order('id', { ascending: false }).limit(300);
    });
    dat(ds, bang([
      { nhan: 'Ngày', lay: (r) => ngay(r.ngay) },
      { nhan: 'Người đề nghị', lay: (r) => r.nguoi_de_nghi_ten },
      { nhan: 'Mục', lay: (r) => r.muc },
      { nhan: 'Nội dung', lay: (r) => h('span', null, r.noi_dung,
        [r.nguoi_nhan, r.nha_cung_cap, r.gdv, r.don_vi_lien_quan, r.ho_so_ma].filter(Boolean).length
          ? h('small', null, ' · ' + [r.nguoi_nhan, r.nha_cung_cap, r.gdv, r.don_vi_lien_quan, r.ho_so_ma].filter(Boolean).join(' · ')) : null,
        r.nghi_tach_phieu && r.trang_thai === 'cho_duyet' ? h('span', { class: 'nhan tt-canh-bao' }, 'Nghi tách nhỏ phiếu') : null) },
      { nhan: 'Số tiền', so: true, lay: (r) => h('span', null, tien(r.so_tien), r.can_giam_doc ? h('small', { class: 'nhan' }, 'GĐ duyệt') : null) },
      { nhan: 'Trạng thái', lay: (r) => h('span', null, TT[r.trang_thai], r.nguoi_duyet_ten ? h('small', null, ` · ${r.nguoi_duyet_ten}`) : null,
        r.ly_do_tu_choi ? h('small', null, ` · ${r.ly_do_tu_choi}`) : null) },
      { nhan: '', lay: (r) => h('span', { class: 'hang-nut' }, nutHanhDong(r)) },
    ], rows, { trong: 'Không có đề nghị nào.' }));
  }

  function nutHanhDong(r) {
    const ra = [];
    const laCuaToi = r.nguoi_de_nghi === api.toi.id;
    // Không tự duyệt phiếu mình lập – trừ giám đốc
    // 043: đề nghị nghi tách nhỏ phiếu thì chỉ giám đốc duyệt (quản lý chung vẫn từ chối được)
    const duocDuyet = nguoiDuyet && (!laCuaToi || api.coVaiTro('giam_doc')) && (!r.can_giam_doc || api.coVaiTro('giam_doc'))
      && (!r.nghi_tach_phieu || api.coVaiTro('giam_doc'));
    const duocTuChoi = nguoiDuyet && (!laCuaToi || api.coVaiTro('giam_doc')) && (!r.can_giam_doc || api.coVaiTro('giam_doc'));
    if (r.trang_thai === 'cho_duyet' && duocDuyet) {
      ra.push(h('button', { class: 'nut nho chinh', type: 'button', onclick: () => chay(() => api.duyetDeNghi(r.id, true, null), { thanhCong: 'Đã duyệt.' }).then(tai).catch(() => {}) }, 'Duyệt'));
    } else if (r.trang_thai === 'cho_duyet' && duocTuChoi && r.nghi_tach_phieu) {
      ra.push(h('small', { class: 'nhan' }, 'GĐ duyệt'));
    }
    if (r.trang_thai === 'cho_duyet' && duocTuChoi) {
      ra.push(h('button', { class: 'nut nho', type: 'button', onclick: () => moTuChoi(r) }, 'Từ chối'));
    }
    if (r.trang_thai === 'da_duyet' && keToan) ra.push(h('button', { class: 'nut nho chinh', type: 'button', onclick: () => moChi(r) }, 'Chi tiền'));
    if (['cho_duyet', 'da_duyet'].includes(r.trang_thai) && (laCuaToi || keToan)) {
      ra.push(h('button', { class: 'nut-chu', type: 'button', onclick: () => chay(() => api.huyDeNghi(r.id), { thanhCong: 'Đã hủy đề nghị.' }).then(tai).catch(() => {}) }, 'Hủy'));
    }
    return ra;
  }

  function moTuChoi(r) {
    hoiLyDo('Từ chối đề nghị', async (lyDo) => { await api.duyetDeNghi(r.id, false, lyDo); toast('Đã từ chối.'); await tai(); },
      { nhan: 'Lý do từ chối', nhanNut: 'Từ chối' });
  }

  function moChi(r) {
    const tks = (api.dm.tai_khoan_quy || []).filter((t) => t.hoat_dong && t.chi_nhanh_id === r.chi_nhanh_id);
    const macDinh = tks.find((t) => t.mac_dinh) || tks[0];
    // Chi hộ: giám đốc / cổ đông bỏ tiền túi trả thay → phần mềm ghi thêm phiếu thu "công ty mượn" cùng số tiền, quỹ không đổi
    const nguoiChiHo = (api.dm.don_vi_lien_quan || []).filter((x) => x.hoat_dong !== false)
      .sort((a, b) => (a.loai === 'ca_nhan' ? 0 : 1) - (b.loai === 'ca_nhan' ? 0 : 1));
    const chonChiHo = oChon('chi_ho_boi', nguoiChiHo.map((x) => ({ value: x.id, label: x.ten })), null, { trong: '— Không, chi từ quỹ —' });
    const goiYChiHo = h('small', { class: 'goi-y' }, 'Chọn người khi tiền do giám đốc / cổ đông bỏ ra trả thay: công ty ghi nợ người đó, số dư quỹ không đổi, chi phí vẫn tính đúng tháng.');
    const form = h('form', null,
      h('p', null, `${r.noi_dung}: `, h('b', null, `${tien(r.so_tien)} đ`)),
      truong('Chi từ tài khoản', oChon('tai_khoan_id', tks.map((t) => ({ value: t.id, label: t.ten })), macDinh?.id, { trong: null })),
      truong('Ngày chi', oNgay('ngay', homNay(), { max: homNay() })),
      nguoiChiHo.length ? truong('Chi hộ bởi', chonChiHo, goiYChiHo) : null);
    moModal('Chi tiền', form, { nhanNut: 'Lập phiếu chi', nutChinh: async () => {
      const d = docForm(form);
      await api.chiTien(r.id, d.tai_khoan_id, d.ngay, d.chi_ho_boi ? Number(d.chi_ho_boi) : null);
      toast(d.chi_ho_boi ? 'Đã ghi phiếu chi và phiếu thu "công ty mượn" đối ứng.' : 'Đã chi.'); await tai();
    } });
  }

  // Các kỳ chi phí chọn được (khớp máy chủ): tháng này và 3 tháng trước; tháng đã chốt sổ (và các tháng trước nó) không chọn được
  function cacKy(daChotDen = null) {
    const d = new Date(); const ds = [];
    const TEN = ['Tháng này', 'Tháng trước', 'Hai tháng trước', 'Ba tháng trước'];
    for (let i = 0; i < 4; i++) {
      const t = new Date(d.getFullYear(), d.getMonth() - i, 1);
      const v = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-01`;
      const khoa = !!daChotDen && v <= daChotDen;
      ds.push({ value: v, khoa, label: `${TEN[i]} (${String(t.getMonth() + 1).padStart(2, '0')}/${t.getFullYear()})${khoa ? ' – đã chốt sổ' : ''}` });
    }
    return ds;
  }

  async function moLap({ mucTen = null, kyMacDinh = null, soTien = null, noiDung = '', nguoiNhan = '', hoSoId = null } = {}) {
    const mucChi = api.dm.muc_thu_chi.filter((m) => m.loai === 'chi' && m.hoat_dong);
    // Tháng chốt sổ gần nhất của chi nhánh (giám đốc / quản lý chung / kế toán đọc được; vai khác máy chủ tự chặn)
    const daChotDen = (await api.doc('chot_thang', (q) => q.eq('chi_nhanh_id', api.toi.chi_nhanh_id).order('thang', { ascending: false }).limit(1), 'thang')
      .catch(() => []))[0]?.thang || null;
    const NHOM = { gia_von: 'Giá vốn', co_dinh: 'Chi phí cố định', van_hanh: 'Chi phí vận hành' };
    const chonMuc = h('select', { name: 'muc_id' }, h('option', { value: '' }, '— Chọn —'),
      [...new Set(mucChi.map((m) => m.nhom || 'khac'))].map((n) => h('optgroup', { label: NHOM[n] || 'Không tính vào lãi lỗ' },
        mucChi.filter((m) => (m.nhom || 'khac') === n).map((m) => h('option', { value: m.id }, m.ten)))));
    const vungRieng = h('div', { class: 'luoi-o rong' });
    // Hồ sơ để gắn khoản chi; "Trả lại cọc" cần cả hồ sơ đã hủy / đã đóng còn giữ tiền của khách (041)
    const [hoSoMo, hoSoDu] = api.laNhanVien() ? await Promise.all([
      api.doc('v_ho_so', (q) => q.not('trang_thai', 'in', '(huy)').order('ngay_vao', { ascending: false }).limit(300)),
      api.doc('v_ho_so', (q) => q.lt('con_no_khach', 0).eq('tu_excel', false).order('ngay_vao', { ascending: false }).limit(100)),
    ]) : [[], []];
    const hoSo = [...hoSoMo, ...hoSoDu.filter((x) => !hoSoMo.some((y) => y.id === x.id))];
    // Mở từ hồ sơ / công nợ mà xe không nằm trong hai danh sách trên (hồ sơ cũ, đã đóng): nạp riêng xe đó
    const hoSoThem = hoSoId && api.laNhanVien() && !hoSo.some((x) => String(x.id) === String(hoSoId))
      ? (await api.doc('v_ho_so', (q) => q.eq('id', hoSoId)).catch(() => []))[0] || null : null;
    chonMuc.addEventListener('change', () => {
      const m = mucChi.find((x) => String(x.id) === chonMuc.value);
      dat(vungRieng, );
      if (!m) return;
      if (m.can_ho_so || ['tra_hoa_hong', 'tra_coc'].includes(m.tinh_chat)) {
        const traCoc = m.tinh_chat === 'tra_coc';
        const ds = [...(traCoc && hoSoDu.length ? hoSoDu : hoSo)];
        if (hoSoId && !ds.some((x) => String(x.id) === String(hoSoId)) && hoSoThem) ds.unshift(hoSoThem);
        const chonXe = oChon('ho_so_id', ds.map((x) => ({ value: x.id, label: `${x.bien_so_hien_thi || x.ma} – ${x.ten_khach}${x.gdv ? ` – GDV ${x.gdv}` : ''}`
          + (Number(x.con_no_khach) < 0 ? ` – ${x.trang_thai === 'huy' ? 'đang giữ' : 'khách dư'} ${tien(-x.con_no_khach)} đ${x.trang_thai === 'huy' ? ' (hồ sơ đã hủy)' : ''}` : '') })), hoSoId);
        const goiYXe = h('span', null, traCoc ? 'Danh sách xe đang giữ tiền của khách (trả dư, đặt cọc, hồ sơ đã hủy)' : '');
        // 043: trả lại cọc / tiền dư – hỏi máy chủ số đang giữ (trừ đề nghị trả lại đang chờ) rồi điền sẵn số tối đa
        if (traCoc) {
          const capNhatCoc = async () => {
            const id = chonXe.value;
            if (!id) return;
            const t = await api.soTienTraLaiKhach(Number(id)).catch(() => null);
            if (!t || chonXe.value !== id) return;
            dat(goiYXe, `Đang giữ ${tien(t.dang_giu) || '0'} đ của khách`,
              Number(t.dang_de_nghi) > 0 ? `, đã có đề nghị trả lại ${tien(t.dang_de_nghi)} đ chờ duyệt / chờ chi` : '',
              h('b', null, ` → trả lại tối đa ${tien(t.toi_da) || '0'} đ.`));
            const oSo = form.querySelector('[name=so_tien]');
            if (oSo && !docTien(oSo.value) && Number(t.toi_da) > 0) { oSo.value = tien(t.toi_da); }
          };
          chonXe.addEventListener('change', capNhatCoc);
          if (hoSoId) setTimeout(capNhatCoc);
        }
        vungRieng.append(truong('Xe', chonXe, goiYXe, { batBuoc: true }));
      }
      if (m.tinh_chat === 'tra_hoa_hong') vungRieng.append(truong('Giám định viên', oChon('gdv_id', api.dm.giam_dinh_vien.filter((g) => !g.la_cho_them).map((g) => ({ value: g.id, label: `${g.ten}${g.hang_id ? ` (${api.dm.ten('hang_bao_hiem', g.hang_id)})` : ''}` })), null), null, { batBuoc: true }));
      if (m.tinh_chat === 'tra_ncc') vungRieng.append(truong('Nhà cung cấp', oChon('nha_cung_cap_id', api.dm.nha_cung_cap.filter((x) => x.hoat_dong).map((x) => ({ value: x.id, label: x.ten })), null), null, { batBuoc: true }));
      if (m.tinh_chat === 'tra_noi_bo') vungRieng.append(truong('Đơn vị', oChon('don_vi_lien_quan_id', api.dm.don_vi_lien_quan.map((x) => ({ value: x.id, label: x.ten })), null), null, { batBuoc: true }));
      if (m.tinh_chat === 'chi_phi') {
        vungRieng.append(truong('VAT trên hóa đơn (nếu có)', oTien('vat_dau_vao', null), 'Phần VAT đã nằm trong số tiền, dùng để tính VAT phải nộp'));
        // Kỳ chi phí: tiền điện, nước… của tháng trước nhưng chi tháng này thì chọn tháng trước → tính vào lãi lỗ tháng trước
        const ky = cacKy(daChotDen);
        const kyMo = ky.filter((k) => !k.khoa);
        if (kyMacDinh && !ky.some((k) => k.value === kyMacDinh)) toast(`Kỳ chi phí tháng ${kyMacDinh.slice(5, 7)}/${kyMacDinh.slice(0, 4)} quá xa (chỉ chọn được tháng này và 3 tháng trước) – chọn lại kỳ.`, 'loi', 8000);
        else if (kyMacDinh && ky.find((k) => k.value === kyMacDinh)?.khoa) toast(`Tháng ${kyMacDinh.slice(5, 7)}/${kyMacDinh.slice(0, 4)} đã chốt sổ – khoản này ghi vào tháng đang mở.`, 'loi', 8000);
        const kyChon = h('select', { name: 'ky_chi_phi', 'aria-label': 'Chi phí của tháng' },
          ky.map((k) => h('option', { value: k.value, disabled: k.khoa }, k.label)));
        kyChon.value = kyMo.some((k) => k.value === kyMacDinh) ? kyMacDinh : (kyMo[0] || ky[0]).value;
        vungRieng.append(truong('Chi phí của tháng', kyChon, 'Hóa đơn của tháng trước (điện, nước, mặt bằng…) thì chọn tháng trước để tính đúng kỳ. Tháng đã chốt sổ thì không chọn được.'));
      }
    });
    if (mucTen) { const m = mucChi.find((x) => x.ten === mucTen); if (m) { chonMuc.value = String(m.id); chonMuc.dispatchEvent(new Event('change')); } }
    const form = h('form', { class: 'luoi-o', novalidate: true },
      truong('Mục chi', chonMuc, null, { batBuoc: true }),
      truong('Số tiền', oTien('so_tien', soTien), null, { batBuoc: true }),
      truong('Nội dung', oChu('noi_dung', noiDung || ''), null, { batBuoc: true, rong: true }),
      truong('Người nhận tiền', oChu('nguoi_nhan', nguoiNhan || '')),
      vungRieng);
    // 043: ngày đề nghị = hôm nay (máy chủ tự lấy, không chọn được – tránh lùi ngày để lách duyệt); khoản tính cho tháng nào chọn ở "Chi phí của tháng".
    // Trả NCC vượt số còn nợ / chi hoa hồng chưa ghi ở hồ sơ: máy chủ hỏi lại.
    moModal('Lập đề nghị chi', form, {
      rong: true, nhanNut: 'Gửi đề nghị',
      nutChinh: async () => {
        const d = docForm(form);
        await chay((boQua) => api.lapDeNghiChi({ ...d, bo_qua_canh_bao: boQua }), { thanhCong: 'Đã gửi đề nghị.' });
        loc = 'cua_toi'; for (const b of tabs.children) b.setAttribute('aria-selected', String(b.dataset.ma === loc)); await tai();
      },
    });
  }

  await tai();
  // Mở sẵn form từ trang khác: #/de-nghi?lap=1&muc=Điện&ky=2026-10-01 (Kết quả kinh doanh), &tien=…&nd=…&nhan=… (bảo dưỡng tài sản thuê ngoài)
  const thamSo = new URLSearchParams(location.hash.split('?')[1] || '');
  if (thamSo.get('lap') && !api.laCoDong()) {
    history.replaceState(null, '', '#/de-nghi');
    await moLap({ mucTen: thamSo.get('muc'), kyMacDinh: thamSo.get('ky'), soTien: thamSo.get('tien') ? Number(thamSo.get('tien')) : null, noiDung: thamSo.get('nd') || '',
      nguoiNhan: thamSo.get('nhan') || '', hoSoId: thamSo.get('ho_so') ? Number(thamSo.get('ho_so')) : null });
  }
}
