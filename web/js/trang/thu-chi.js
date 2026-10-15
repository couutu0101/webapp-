// Thu chi: số dư quỹ, sổ thu chi, phiếu thu (gắn vào xe), chuyển quỹ, kiểm quỹ
import { h, tien, ngay, homNay, cuoiThang, truong, oChu, oTien, oChon, oNgay, oVung, docForm, docTien, bang, moModal, toast, dat, hoiLyDo, chay } from '../ui.js';
import * as api from '../api.js';

export default async function trangThuChi(el) {
  const keToan = api.coVaiTro('ke_toan', 'giam_doc');
  const thamSo = new URLSearchParams(location.hash.split('?')[1] || '');
  let thang = homNay().slice(0, 7);

  const soDu = h('section', { class: 'luoi-dem' });
  const chuaChia = h('div');          // 043: tiền bảo hiểm đã về chưa chia vào xe (mọi tháng)
  const so = h('div');
  const oThang = h('input', { type: 'month', value: thang, 'aria-label': 'Tháng' });
  oThang.addEventListener('change', () => { thang = oThang.value; taiSo(); });

  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Thu chi'),
      keToan ? h('div', { class: 'hang-nut' },
        h('button', { class: 'nut chinh', type: 'button', onclick: () => moPhieuThu({}) }, '+ Phiếu thu'),
        h('button', { class: 'nut', type: 'button', onclick: moChuyen }, 'Chuyển quỹ'),
        h('button', { class: 'nut', type: 'button', onclick: moKiemQuy }, 'Kiểm quỹ'),
        h('a', { class: 'nut', href: '#/de-nghi' }, 'Phiếu chi (từ đề nghị chi)')) : null),
    soDu,
    chuaChia,
    h('section', { class: 'the' }, h('div', { class: 'the-dau' }, h('h2', null, 'Sổ thu chi'), oThang), so));

  const dsTaiKhoan = () => (api.dm.tai_khoan_quy || []).filter((t) => t.hoat_dong && t.chi_nhanh_id === api.toi.chi_nhanh_id);

  async function taiSoDu() {
    const ds = await api.doc('v_so_du_quy', (q) => q.order('id'));
    dat(soDu, ...ds.filter((t) => t.hoat_dong || Number(t.so_du) !== 0).map((t) =>
      h('div', { class: `o-dem ${Number(t.so_du) < 0 ? 'am' : ''}` }, h('b', null, tien(t.so_du)), h('span', null, t.ten))));
  }

  async function taiSo() {
    dat(so, h('div', { class: 'dang-tai' }, 'Đang tải…'));
    const den = cuoiThang(thang);   // 038: toISOString() lùi 1 ngày theo UTC → mất ngày 31
    const ds = await api.doc('v_phieu_thu_chi', (q) => q.gte('ngay', `${thang}-01`).lte('ngay', den).order('ngay', { ascending: false }).order('id', { ascending: false }));
    const hl = ds.filter((p) => p.trang_thai === 'hieu_luc');
    const tong = (loai) => hl.filter((p) => p.loai === loai).reduce((s, p) => s + Number(p.so_tien), 0);
    dat(so, 
      h('p', { class: 'mo-ta' }, `Tổng thu ${tien(tong('thu'))} đ · Tổng chi ${tien(tong('chi'))} đ · ${ds.length} phiếu`),
      bang([
        { nhan: 'Ngày', lay: (p) => ngay(p.ngay) },
        { nhan: 'Loại', lay: (p) => ({ thu: 'Thu', chi: 'Chi', chuyen: 'Chuyển' })[p.loai] },
        { nhan: 'Tài khoản', lay: (p) => p.loai === 'chuyen' ? `${p.tai_khoan} → ${p.tai_khoan_den}` : p.tai_khoan },
        { nhan: 'Mục', lay: (p) => p.muc || '' },
        { nhan: 'Nội dung', lay: (p) => h('span', null, [p.hang_bh, p.nha_cung_cap, p.gdv, p.don_vi_lien_quan, p.noi_dung].filter(Boolean).join(' · '),
          p.ho_so ? h('small', { class: 'nhan' }, p.ho_so) : null) },
        { nhan: 'Số tiền', so: true, lay: (p) => h('span', { class: p.trang_thai === 'huy' ? 'gach' : p.loai === 'chi' ? 'chu-loi' : '' },
          (p.loai === 'chi' ? '−' : '') + tien(p.so_tien)) },
        { nhan: '', lay: (p) => p.trang_thai === 'huy' ? h('small', null, `Đã hủy: ${p.ly_do_huy}`) : keToan ? nutPhieu(p) : '' },
      ], ds, { trong: 'Tháng này chưa có phiếu nào.' }));
  }
  // Nút của một phiếu còn hiệu lực: chia tiền BH còn lại vào xe, chuyển phần đã chia sang xe khác (chia nhầm), hủy
  const nutPhieu = (p) => h('span', { class: 'hang-nut' },
    Number(p.con_chua_chia) > 0
      ? h('button', { class: 'nut nho chinh', type: 'button', onclick: () => moChiaTien(p) }, `Chia ${tien(p.con_chua_chia)} đ vào xe`) : null,
    // Chia nhầm xe hay gặp ở phiếu bảo hiểm trả nhiều xe một lần (phiếu của khách gắn đúng một xe lúc thu)
    p.tinh_chat === 'thu_bao_hiem' && Number(p.da_phan_bo) > 0
      ? h('button', { class: 'nut-chu', type: 'button', onclick: () => moChuyenPhanBo(p) }, 'Chuyển phần chia') : null,
    h('button', { class: 'nut-chu', type: 'button', onclick: () => moHuy(p) }, 'Hủy'));

  // 043: tiền bảo hiểm đã về mà chưa chia vào xe – mọi tháng (trước đây chỉ thấy khi mở đúng tháng của phiếu)
  async function taiChuaChia() {
    if (!keToan) return;
    const ds = await api.doc('v_phieu_thu_chi', (q) => q.gt('con_chua_chia', 0).order('ngay')).catch(() => []);
    if (!ds.length) { dat(chuaChia); return; }
    const tong = ds.reduce((t, p) => t + Number(p.con_chua_chia), 0);
    dat(chuaChia, h('section', { class: 'the', id: 'chua-chia' },
      h('h2', null, `Tiền bảo hiểm đã về chưa chia vào xe – ${tien(tong)} đ`),
      h('p', { class: 'goi-y' }, 'Chia vào từng xe theo bảng kê của bảo hiểm thì công nợ xe mới đúng. Chia nhầm xe: bấm "Chuyển phần chia" ở phiếu đó.'),
      bang([
        { nhan: 'Ngày', lay: (p) => ngay(p.ngay) },
        { nhan: 'Hãng', lay: (p) => p.hang_bh || '' },
        { nhan: 'Nội dung', lay: (p) => p.noi_dung || '' },
        { nhan: 'Số tiền', so: true, lay: (p) => tien(p.so_tien) },
        { nhan: 'Chưa chia', so: true, lay: (p) => h('b', { class: 'chu-cam' }, tien(p.con_chua_chia)) },
        { nhan: '', lay: (p) => nutPhieu(p) },
      ], ds, { gon: true })));
  }
  const taiLai = () => Promise.all([taiSoDu(), taiSo(), taiChuaChia()]);

  // ---------- Phiếu thu ----------
  async function moPhieuThu({ hoSoId, dvnId }) {
    const mucThu = api.dm.muc_thu_chi.filter((m) => m.loai === 'thu' && m.hoat_dong);
    const form = h('form', { class: 'luoi-o', novalidate: true });
    const chonMuc = oChon('muc_id', mucThu.map((m) => ({ value: m.id, label: m.ten })), null);
    const oSoTien = oTien('so_tien', null);
    const vungRieng = h('div', { class: 'rong' });
    form.append(
      truong('Tài khoản nhận', oChon('tai_khoan_id', dsTaiKhoan().map((t) => ({ value: t.id, label: t.ten })), (dsTaiKhoan().find((t) => t.mac_dinh) || dsTaiKhoan()[0])?.id, { trong: null }), 'Mặc định: tài khoản công ty (đổi ở Danh mục → Tài khoản quỹ)'),
      truong('Mục thu', chonMuc, null, { batBuoc: true }),
      truong('Số tiền', oSoTien, null, { batBuoc: true }),
      truong('Ngày', oNgay('ngay', homNay(), { max: homNay() })),
      truong('Nội dung', oChu('noi_dung', ''), null, { rong: true }),
      vungRieng);
    let layPhanBo = () => [];
    let tachTienBo = () => null;
    let choTraDu = () => false;

    const hoSoMo = await api.doc('v_ho_so', (q) => q.not('trang_thai', 'in', '(huy)').or('con_no_khach.gt.0,con_no_bh.gt.0,trang_thai.in.(tiep_nhan,bao_gia,da_duyet,dang_sua,cho_kcs,dat_kcs)').order('ngay_vao', { ascending: false }).limit(300));
    const nhanHoSo = (x) => `${x.bien_so_hien_thi || x.ma} – ${x.ten_khach}`;

    async function doiMuc() {
      const m = mucThu.find((x) => String(x.id) === chonMuc.value);
      dat(vungRieng, );
      layPhanBo = () => [];
      if (!m) return;
      if (m.tinh_chat === 'thu_khach' || m.tinh_chat === 'thu_coc') {
        const ds = hoSoMo.filter((x) => m.tinh_chat === 'thu_coc' || Number(x.con_no_khach) > 0);
        const chon = oChon('ho_so_id', ds.map((x) => ({ value: x.id, label: `${nhanHoSo(x)}${m.tinh_chat === 'thu_khach' ? ` – còn nợ ${tien(x.con_no_khach)} đ` : ''}` })), hoSoId);
        chon.addEventListener('change', () => {
          const x = ds.find((y) => String(y.id) === chon.value);
          if (x && m.tinh_chat === 'thu_khach') oSoTien.value = tien(x.con_no_khach);
          if (x && !form.noi_dung.value) form.noi_dung.value = `${m.tinh_chat === 'thu_coc' ? 'Cọc' : 'Khách trả'} sửa xe ${x.bien_so_hien_thi || x.ma} – ${x.ten_khach}`;
        });
        vungRieng.append(truong('Xe', chon, m.tinh_chat === 'thu_coc' ? 'Tiền cọc trừ vào phần khách trả khi giao xe' : null, { batBuoc: true }));
        // Khách trả nhiều hơn số còn nợ: hỏi phần dư là tiền bo hay trả dư (sẽ trả lại).
        // 043: khối dựng một lần – gõ tiếp số tiền chỉ đổi dòng chữ, không làm mất lựa chọn đã bấm
        const chuDu = h('b');
        const khoiDu = h('div', { class: 'rong khoi-tra-du', hidden: true },
          h('div', { class: 'thong-bao canh-bao' }, chuDu,
            h('div', { class: 'chon-nut' },
              h('label', null, h('input', { type: 'radio', name: 'phan_du', value: 'bo', checked: true }), h('span', null, 'Tiền bo cho thợ')),
              h('label', null, h('input', { type: 'radio', name: 'phan_du', value: 'tra_lai' }), h('span', null, 'Trả dư – sẽ trả lại khách'))),
            h('small', { class: 'goi-y' }, 'Tiền bo: ghi thành phiếu thu riêng "Tiền bo của khách", không tính vào xe. Trả dư: hồ sơ ghi khách trả dư, kế toán lập đề nghị chi "Trả lại cọc cho khách" để trả.')));
        vungRieng.append(khoiDu);
        const capNhatDu = () => {
          const x = ds.find((y) => String(y.id) === chon.value);
          const du = x && m.tinh_chat === 'thu_khach' ? (docTien(oSoTien.value) || 0) - Number(x.con_no_khach) : 0;
          khoiDu.hidden = !(du > 0);
          if (du > 0) dat(chuDu, `Khách trả dư ${tien(du)} đ so với số còn nợ ${tien(x.con_no_khach)} đ. Phần dư là:`);
        };
        choTraDu = () => !khoiDu.hidden && form.querySelector('[name=phan_du]:checked')?.value === 'tra_lai';
        oSoTien.addEventListener('input', capNhatDu);
        chon.addEventListener('change', capNhatDu);
        if (hoSoId) chon.dispatchEvent(new Event('change'));
        layPhanBo = () => (chon.value ? [{ ho_so_id: Number(chon.value), so_tien: docTien(oSoTien.value) }] : []);
        // Tiền bo: tách thành 2 phiếu (xe nhận đúng số nợ, phần dư vào mục Tiền bo)
        tachTienBo = () => {
          const x = ds.find((y) => String(y.id) === chon.value);
          if (!x || m.tinh_chat !== 'thu_khach' || khoiDu.hidden) return null;
          if (form.querySelector('[name=phan_du]:checked')?.value !== 'bo') return null;
          const du = (docTien(oSoTien.value) || 0) - Number(x.con_no_khach);
          return du > 0 ? { du, noNo: Number(x.con_no_khach), hoSoId: x.id, x } : null;
        };
      } else if (m.tinh_chat === 'thu_bao_hiem') {
        const chonHang = oChon('hang_bh_id', api.dm.hang_bao_hiem.map((x) => ({ value: x.id, label: x.ten })), null);
        const dsXe = h('div', { class: 'ds-phan-bo' });
        let dongs = [];
        chonHang.addEventListener('change', () => {
          const ds = hoSoMo.filter((x) => String(x.hang_bh_id) === chonHang.value && Number(x.con_no_bh) > 0);
          dongs = ds.map((x) => ({ x, o: oTien(`pb_${x.id}`, null, { 'aria-label': `Số tiền cho ${nhanHoSo(x)}`, placeholder: tien(x.con_no_bh) }) }));
          dat(dsXe, ds.length ? h('p', { class: 'goi-y' }, 'Nhập số tiền cho từng xe theo bảng kê của bảo hiểm. Phần chưa chia sẽ nằm ở "chưa phân bổ" để chia sau.') : h('p', { class: 'trong' }, 'Hãng này không có xe nào còn nợ.'),
            ...dongs.map((d) => h('div', { class: 'dong-phan-bo' }, h('span', null, nhanHoSo(d.x), h('small', null, ` còn nợ ${tien(d.x.con_no_bh)} đ`)),
              h('button', { class: 'nut-chu', type: 'button', onclick: () => { d.o.value = tien(d.x.con_no_bh); } }, 'Đủ'), d.o)));
        });
        vungRieng.append(truong('Hãng bảo hiểm', chonHang, null, { batBuoc: true }), dsXe);
        layPhanBo = () => dongs.map((d) => ({ ho_so_id: d.x.id, so_tien: docTien(d.o.value) })).filter((d) => d.so_tien);
        const xHs = hoSoId ? hoSoMo.find((y) => String(y.id) === String(hoSoId)) : null;
        if (xHs && xHs.hang_bh_id) {
          chonHang.value = String(xHs.hang_bh_id);
          chonHang.dispatchEvent(new Event('change'));
          const d = dongs.find((z) => z.x.id === xHs.id);
          if (d) { d.o.value = tien(xHs.con_no_bh); oSoTien.value = tien(xHs.con_no_bh); }
          if (!form.noi_dung.value) form.noi_dung.value = `${xHs.hang_bh || 'Bảo hiểm'} trả xe ${xHs.bien_so_hien_thi || xHs.ma} – ${xHs.ten_khach}`;
        }
      } else if (m.tinh_chat === 'thu_dich_vu_nhanh') {
        // 043: lọc "còn phải thu" ở máy chủ (trước đây lấy 200 lượt gần nhất rồi mới lọc – lượt cũ chưa thu bị sót)
        const chuaThu = (q) => q.eq('trang_thai', 'hieu_luc').gt('con_thu', 0);
        const ds = await api.doc('v_dich_vu_nhanh', (q) => chuaThu(q).order('ngay', { ascending: false }).order('id', { ascending: false }).limit(300));
        if (dvnId && !ds.some((d) => String(d.id) === String(dvnId))) {
          const mot = await api.doc('v_dich_vu_nhanh', (q) => chuaThu(q.eq('id', dvnId))).catch(() => []);
          if (mot.length) ds.unshift(mot[0]); else toast('Lượt dịch vụ này đã thu đủ hoặc đã hủy.', 'loi');
        }
        const chon = oChon('dvn', ds.map((d) => ({ value: d.id, label: `${ngay(d.ngay)} ${d.bien_so_hien_thi || ''} ${d.dich_vu} – còn ${tien(d.con_thu)} đ` })), dvnId);
        chon.addEventListener('change', () => { const d = ds.find((y) => String(y.id) === chon.value); if (d) oSoTien.value = tien(d.con_thu); });
        if (dvnId) chon.dispatchEvent(new Event('change'));
        vungRieng.append(truong('Dịch vụ', chon, null, { batBuoc: true }));
        layPhanBo = () => (chon.value ? [{ dich_vu_nhanh_id: Number(chon.value), so_tien: docTien(oSoTien.value) }] : []);
      } else if (m.tinh_chat === 'thu_noi_bo') {
        vungRieng.append(truong('Đơn vị', oChon('don_vi_lien_quan_id', api.dm.don_vi_lien_quan.map((x) => ({ value: x.id, label: x.ten })), null), null, { batBuoc: true }));
      }
    }
    chonMuc.addEventListener('change', doiMuc);
    if (hoSoId) {
      const x = hoSoMo.find((y) => String(y.id) === String(hoSoId));
      // Tự chọn mục theo bên còn nợ: khách nợ → thu khách; chỉ bảo hiểm nợ → bảo hiểm trả; chưa nợ gì → thu cọc
      const tc = !x ? 'thu_khach' : Number(x.con_no_khach) > 0 ? 'thu_khach' : Number(x.con_no_bh) > 0 ? 'thu_bao_hiem' : 'thu_coc';
      chonMuc.value = mucThu.find((m) => m.tinh_chat === tc)?.id ?? '';
      await doiMuc();
    } else if (dvnId) {
      chonMuc.value = mucThu.find((m) => m.tinh_chat === 'thu_dich_vu_nhanh')?.id ?? '';
      await doiMuc();
    }

    moModal('Phiếu thu', form, {
      rong: true, nhanNut: 'Lập phiếu thu',
      nutChinh: async () => {
        const d = docForm(form);
        const bo = tachTienBo();
        if (bo) {
          // 038: máy chủ tách 2 phiếu trong MỘT giao dịch (trước đây gọi 2 lần, lỗi giữa chừng thì thiếu phiếu tiền bo)
          await api.lapPhieuThu({ tai_khoan_id: d.tai_khoan_id, muc_id: d.muc_id, so_tien: bo.noNo + bo.du, tien_bo: bo.du, ngay: d.ngay,
            noi_dung: d.noi_dung || `Khách trả sửa xe ${bo.x.bien_so_hien_thi || bo.x.ma} – ${bo.x.ten_khach}`,
            phan_bo: [{ ho_so_id: bo.hoSoId, so_tien: bo.noNo }] });
          toast(`Đã lập 2 phiếu thu: ${tien(bo.noNo)} đ cho xe và ${tien(bo.du)} đ tiền bo.`);
        } else {
          const p = { tai_khoan_id: d.tai_khoan_id, muc_id: d.muc_id, so_tien: d.so_tien, ngay: d.ngay, noi_dung: d.noi_dung,
            hang_bh_id: d.hang_bh_id, don_vi_lien_quan_id: d.don_vi_lien_quan_id, phan_bo: layPhanBo(),
            cho_tra_du: choTraDu() };
          await api.lapPhieuThu(p);
          toast('Đã lập phiếu thu.');
        }
        // Phiếu thu lập từ hồ sơ xe (036): quay về đúng hồ sơ đó để làm tiếp (giao xe…), không về danh sách
        if (hoSoId) { location.hash = `#/ho-so/${hoSoId}`; return; }
        history.replaceState(null, '', '#/thu-chi');
        await taiLai();
      },
    });
  }

  async function moChiaTien(p) {
    // 043: v_phieu_thu_chi có hang_bh_id (trước đây thiếu cột này nên danh sách xe luôn trống)
    const ds = await api.doc('v_ho_so', (q) => q.eq('hang_bh_id', p.hang_bh_id ?? -1).gt('con_no_bh', 0).order('ngay_vao'));
    const conLai = Number(p.con_chua_chia ?? (Number(p.so_tien) - Number(p.da_phan_bo)));
    const dongs = ds.map((x) => ({ x, o: oTien(`pb_${x.id}`, null, { placeholder: tien(x.con_no_bh), 'aria-label': `Số tiền cho ${x.bien_so_hien_thi}` }) }));
    const noiDung = h('div', null, h('p', null, `Còn ${tien(conLai)} đ chưa chia vào xe.`),
      dongs.length ? dongs.map((d) => h('div', { class: 'dong-phan-bo' }, h('span', null, `${d.x.bien_so_hien_thi || d.x.ma} – ${d.x.ten_khach}`, h('small', null, ` còn nợ ${tien(d.x.con_no_bh)} đ`)),
        h('button', { class: 'nut-chu', type: 'button', onclick: () => { d.o.value = tien(d.x.con_no_bh); } }, 'Đủ'), d.o)) : h('p', { class: 'trong' }, 'Không có xe nào của hãng này còn nợ.'));
    moModal('Chia tiền bảo hiểm vào xe', noiDung, {
      rong: true, nhanNut: 'Lưu',
      nutChinh: async () => {
        const pb = dongs.map((d) => ({ ho_so_id: d.x.id, so_tien: docTien(d.o.value) })).filter((d) => d.so_tien);
        if (!pb.length) { toast('Nhập số tiền cho ít nhất một xe.', 'loi'); return false; }
        await api.phanBoThem(p.id, pb);
        toast('Đã chia tiền.'); await taiLai();
      },
    });
  }

  // 043: chuyển phần đã chia của phiếu từ xe này sang xe khác (chia nhầm) – được cả khi tháng của phiếu đã chốt,
  // tiền phiếu và quỹ không đổi, hai hồ sơ đều ghi nhật ký
  async function moChuyenPhanBo(p) {
    const nguoiTra = p.tinh_chat === 'thu_bao_hiem' ? 'bao_hiem' : 'khach';
    const pb = await api.doc('phan_bo', (q) => q.eq('phieu_id', p.id).eq('nguoi_tra', nguoiTra));
    const theoXe = {};
    for (const r of pb) theoXe[r.ho_so_id] = (theoXe[r.ho_so_id] || 0) + Number(r.so_tien);
    const idDi = Object.keys(theoXe).filter((k) => theoXe[k] > 0);
    if (!idDi.length) { toast('Phiếu này chưa chia vào xe nào.', 'loi'); return; }
    const [xeDi, xeDen] = await Promise.all([
      api.doc('v_ho_so', (q) => q.in('id', idDi.map(Number))),
      api.doc('v_ho_so', (q) => {
        q = q.neq('trang_thai', 'huy').eq('chi_nhanh_id', p.chi_nhanh_id);
        if (nguoiTra === 'bao_hiem') q = q.eq('hang_bh_id', p.hang_bh_id ?? -1).gt('con_no_bh', 0);
        else if (p.tinh_chat === 'thu_khach') q = q.gt('con_no_khach', 0);
        return q.order('ngay_vao', { ascending: false }).limit(300);
      }),
    ]);
    const nhan = (x) => `${x.bien_so_hien_thi || x.ma} – ${x.ten_khach}`;
    const chonDi = oChon('tu', xeDi.map((x) => ({ value: x.id, label: `${nhan(x)} – đã chia ${tien(theoXe[x.id])} đ` })), xeDi.length === 1 ? xeDi[0].id : null);
    const conNo = (x) => (nguoiTra === 'bao_hiem' ? x.con_no_bh : p.tinh_chat === 'thu_khach' ? x.con_no_khach : null);
    const chonDen = oChon('den', xeDen.map((x) => ({ value: x.id, label: `${nhan(x)}${conNo(x) !== null ? ` – còn nợ ${tien(conNo(x))} đ` : ''}` })), null);
    const oSo = oTien('so_tien', null);
    const goiY = () => {
      const a = theoXe[chonDi.value]; const b = xeDen.find((x) => String(x.id) === chonDen.value);
      if (!a) return;
      const toiDa = b && conNo(b) !== null ? Math.min(a, Number(conNo(b))) : a;
      if (!docTien(oSo.value) || docTien(oSo.value) > toiDa) oSo.value = tien(toiDa);
    };
    chonDi.addEventListener('change', goiY); chonDen.addEventListener('change', goiY);
    const form = h('form', { class: 'luoi-o' },
      h('p', { class: 'rong' }, `Phiếu thu ${ngay(p.ngay)} – ${p.muc || ''}${p.hang_bh ? ` (${p.hang_bh})` : ''}: ${tien(p.so_tien)} đ.`),
      truong('Chuyển từ xe', chonDi, null, { batBuoc: true, rong: true }),
      truong('Sang xe', chonDen, nguoiTra === 'bao_hiem' ? 'Xe cùng hãng bảo hiểm còn nợ' : null, { batBuoc: true, rong: true }),
      truong('Số tiền chuyển', oSo, null, { batBuoc: true }),
      truong('Lý do', oChu('ly_do', '', { placeholder: 'Ví dụ: chia nhầm xe theo bảng kê' }), null, { batBuoc: true, rong: true }));
    goiY();
    moModal('Chuyển phần đã chia sang xe khác', form, {
      rong: true, nhanNut: 'Chuyển',
      nutChinh: async () => {
        const d = docForm(form);
        if (!d.tu || !d.den) { toast('Chọn xe chuyển đi và xe nhận.', 'loi'); return false; }
        if (!d.ly_do) { toast('Ghi lý do.', 'loi'); return false; }
        await chay(() => api.chuyenPhanBo(p.id, Number(d.tu), Number(d.den), d.so_tien, d.ly_do), { thanhCong: 'Đã chuyển phần chia.' });
        await taiLai();
      },
    });
  }

  function moChuyen() {
    const tks = dsTaiKhoan().map((t) => ({ value: t.id, label: t.ten }));
    const form = h('form', { class: 'luoi-o' },
      truong('Từ tài khoản', oChon('tai_khoan_id', tks, null), null, { batBuoc: true }),
      truong('Sang tài khoản', oChon('tai_khoan_den_id', tks, null), null, { batBuoc: true }),
      truong('Số tiền', oTien('so_tien', null), null, { batBuoc: true }),
      truong('Ngày', oNgay('ngay', homNay(), { max: homNay() })),
      truong('Nội dung', oChu('noi_dung', '', { placeholder: 'Ví dụ: rút tiền mặt từ TK công ty' }), null, { rong: true }));
    moModal('Chuyển quỹ', h('div', null, h('p', { class: 'goi-y' }, 'Chuyển quỹ không phải thu chi: không tính vào doanh thu hay chi phí.'), form), {
      nhanNut: 'Lưu', nutChinh: async () => { await api.lapPhieuChuyen(docForm(form)); toast('Đã chuyển quỹ.'); await taiLai(); },
    });
  }

  async function moKiemQuy() {
    const ds = await api.doc('v_so_du_quy', (q) => q.eq('hoat_dong', true).order('id'));
    const chon = oChon('tai_khoan_id', ds.map((t) => ({ value: t.id, label: `${t.ten} (sổ: ${tien(t.so_du)} đ)` })), ds[0]?.id, { trong: null });
    const form = h('form', null,
      truong('Tài khoản', chon),
      truong('Số tiền đếm được / số dư ngân hàng', oTien('so_dem', null), null, { batBuoc: true }),
      truong('Ghi chú (bắt buộc nếu lệch)', oVung('ghi_chu', '')));
    moModal('Kiểm quỹ cuối ngày', form, {
      nhanNut: 'Lưu kiểm quỹ',
      nutChinh: async () => {
        const d = docForm(form);
        const kq = await api.ghiKiemQuy(d.tai_khoan_id, d.so_dem, d.ghi_chu);
        toast(Number(kq.chenh_lech) === 0 ? 'Khớp sổ.' : `Đã ghi, lệch ${tien(kq.chenh_lech)} đ.`, Number(kq.chenh_lech) === 0 ? 'ok' : 'loi');
      },
    });
  }

  function moHuy(p) {
    hoiLyDo('Hủy phiếu', async (lyDo) => { await api.huyPhieu(p.id, lyDo); toast('Đã hủy phiếu.'); await taiLai(); },
      { nhan: 'Lý do hủy', goiY: 'Phiếu hủy vẫn được giữ lại để tra cứu.', nhanNut: 'Hủy phiếu' });
  }

  await taiLai();
  if (thamSo.get('chua_chia')) { history.replaceState(null, '', '#/thu-chi'); document.getElementById('chua-chia')?.scrollIntoView({ block: 'start' }); }
  if (keToan && thamSo.get('ho_so')) await moPhieuThu({ hoSoId: Number(thamSo.get('ho_so')) });
  else if (keToan && thamSo.get('dvn')) await moPhieuThu({ dvnId: Number(thamSo.get('dvn')) });
}
