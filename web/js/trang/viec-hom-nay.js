// Việc hôm nay: số xe theo bước, việc cần xử lý, bảng việc của tổ
import { h, oChonTep, bienSo, icon, ngayGio, tien, chay, moModal, oVung, truong, docForm, nhanTrangThai, nenAnh, TRANG_THAI, dat, thanhBuocNho, chipNguoi, nhoPhien } from '../ui.js';
import * as api from '../api.js';
import { viecTiepTheo } from './giao-viec.js';
import { moLapDeXuat, moDeXuat, moChiTietMua, moChiTietNhap } from './kho.js';
import { buocTiepPhieu, hanPhieu, hanHoSo, quaHan, chuHan } from '../han-viec.js';

const NHOM_DEM = [
  { nhan: 'Chờ duyệt giá', tt: ['tiep_nhan', 'bao_gia'] },
  { nhan: 'Đã duyệt – chờ lệnh', tt: ['da_duyet'] },
  { nhan: 'Đang sửa', tt: ['dang_sua'] },
  { nhan: 'Chờ KCS', tt: ['cho_kcs'] },
  { nhan: 'Chờ giao xe', tt: ['dat_kcs'] },
  { nhan: 'Chờ gửi hồ sơ BH', tt: ['da_giao'] },
  { nhan: 'Chờ bảo hiểm trả', tt: ['da_gui_hs'] },
];
const MUC_DO = { cao: 'Cần làm ngay', vua: 'Trong tuần', thap: 'Bổ sung khi rảnh' };

export default async function trangViec(el) {
  const laVanPhong = api.laNhanVien();
  const [hoSo, canhBao, bangViec, viecCuaToi, kho] = await Promise.all([
    laVanPhong ? api.doc('v_ho_so', (q) => q.not('trang_thai', 'in', '(dong,huy)')) : [],
    laVanPhong ? api.doc('v_canh_bao') : [],
    api.coVaiTro('truong_nhom', 'quan_ly', 'cvdv', 'ke_toan', 'giam_doc') ? api.bangViecTo() : [],
    laVanPhong ? layViecCuaToi() : api.coVaiTro('truong_nhom') ? viecTaiSanCuaToi() : [],
    laVanPhong ? demKho() : null,
  ]);

  const nut = [];
  if (api.coVaiTro('cvdv', 'quan_ly', 'giam_doc')) nut.push(h('a', { class: 'nut chinh', href: '#/ho-so/moi' }, '+ Tiếp nhận xe'));
  nut.push(h('a', { class: 'nut', href: '#/dich-vu' }, '+ Dịch vụ nhanh'));
  nut.push(h('a', { class: 'nut', href: '#/de-nghi' }, '+ Đề nghị chi'));

  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Việc hôm nay'), h('div', { class: 'hang-nut' }, nut)),
    laVanPhong || viecCuaToi.length ? khoiViecCuaToi(viecCuaToi, () => trangViec(el)) : null,
    laVanPhong ? h('section', { class: 'luoi-dem chuoi-xe', 'aria-label': 'Số xe ở từng bước' }, NHOM_DEM.map((n) => {
      const so = hoSo.filter((x) => n.tt.includes(x.trang_thai)).length;
      return h('a', { class: `o-dem ${so ? '' : 'mo'}`, href: `#/ho-so?tt=${n.tt.join(',')}` },
        h('b', null, so), h('span', null, n.nhan));
    })) : null,
    kho ? khoiKho(kho) : null,
    laVanPhong ? khoiCanhBao(canhBao) : null,
    bangViec.length || api.coVaiTro('truong_nhom') ? khoiBangViec(bangViec, () => trangViec(el)) : null,
  );
}

function khoiCanhBao(ds) {
  if (!ds.length) return h('section', { class: 'the' }, h('h2', null, 'Việc cần xử lý'), h('p', { class: 'trong' }, 'Không có việc tồn đọng. Tốt lắm!'));
  return h('section', { class: 'the' }, h('h2', null, `Việc cần xử lý (${ds.length})`),
    ['cao', 'vua', 'thap'].map((md) => {
      const nhom = ds.filter((x) => x.muc_do === md);
      if (!nhom.length) return null;
      return h('div', { class: 'nhom-canh-bao' }, h('h3', { class: `muc-${md}` }, MUC_DO[md]),
        h('ul', { class: 'ds-canh-bao' }, nhom.map((c) => h('li', null,
          c.ho_so_id ? h('a', { href: `#/ho-so/${c.ho_so_id}`, class: 'lien-ket-xe' }, bienSo(c.bien_so, { maThay: c.ma })) :
            h('a', { href: c.loai === 'thu_chua_phan_bo' ? '#/thu-chi' : '#/de-nghi' }, h('b', null, 'Xem'), ' '),
          c.noi_dung))));
    }));
}

function khoiBangViec(ds, taiLai) {
  return h('section', { class: 'the' },
    h('h2', null, api.coVaiTro('truong_nhom') ? `Xe của tổ ${api.dm.ten('to_thuc_hien', api.toi.to_id)}` : 'Bảng việc xưởng'),
    !ds.length ? h('p', { class: 'trong' }, 'Không có xe đang sửa.') :
      h('div', { class: 'luoi-the' }, ds.map((x) => h('article', { class: `the-xe ${x.hen_giao && quaHan(new Date(x.hen_giao)) ? 'qua-han' : ''}` },
        h('div', { class: 'the-xe-dau' }, bienSo(x.bien_so, { maThay: x.ma }), nhanTrangThai(x.trang_thai)),
        thanhBuocNho(x),
        h('div', { class: 'mo-ta' }, x.xe),
        x.hen_giao ? h('div', { class: 'mo-ta' }, 'Hẹn giao: ', h('b', null, ngayGio(x.hen_giao)),
          quaHan(new Date(x.hen_giao)) ? h('span', { class: 'nhan qua-han' }, chuHan(new Date(x.hen_giao))) : null) : null,
        h('ul', { class: 'ds-hang-muc' }, (x.hang_muc || []).map((m) => h('li', { class: m.trang_thai },
          h('span', { class: 'hang-muc-ten' }, m.ten, m.nguoi_lam ? chipNguoi(m.nguoi_lam, { vai: 'truong_nhom', gon: true, nho: true }) : null),
          m.trang_thai === 'dang_lam'
            ? h('button', { class: 'nut nho', type: 'button', onclick: () => chay(() => api.baoXong(m.id), { thanhCong: `Đã báo xong: ${m.ten}` }).then(taiLai, taiLai) }, 'Báo xong')
            : h('span', { class: 'xong' }, '✓ Xong')))),
        h('div', { class: 'hang-nut' },
          h('button', { class: 'nut nho', type: 'button', onclick: () => moLapDeXuat({ id: x.ho_so_id, ma: x.ma, bien_so_hien_thi: x.bien_so, xe: x.xe }, taiLai) }, 'Đề xuất vật tư'),
          h('button', { class: 'nut nho', type: 'button', onclick: () => moPhatSinh(x, taiLai) }, 'Báo phát sinh')),
      ))));
}

function moPhatSinh(x, taiLai) {
  const form = h('form', null,
    truong('Hư hỏng phát sinh', oVung('mo_ta', '', { rows: 3, placeholder: 'Ví dụ: nứt đèn pha trái, cần thay' }), 'Dừng làm phần phát sinh, chờ CVDV báo giá bổ sung và duyệt.', { batBuoc: true }),
    truong('Ảnh hư hỏng', oChonTep({ name: 'anh', capture: 'environment', multiple: true }, 'Chụp ảnh hư hỏng')));
  moModal(`Báo phát sinh – ${x.bien_so || x.ma}`, form, {
    nhanNut: 'Gửi',
    nutChinh: async () => {
      const { mo_ta } = docForm(form);
      await api.baoPhatSinh(x.ho_so_id, mo_ta);
      for (const f of form.anh.files) await api.taiTep({ id: x.ho_so_id, ma: x.ma, chi_nhanh_id: api.toi.chi_nhanh_id }, 'phat_sinh', await nenAnh(f, 'phat_sinh'));
      taiLai();
    },
  });
}

export { TRANG_THAI };

// ---------- Việc của tôi: việc đang chờ đúng người đăng nhập, quá hạn tô vàng ----------
//   - Xe: bước tiếp theo được giao cho mình (ho_so.nguoi_tiep_theo).
//   - Phiếu kho / đề nghị chi: đang chờ đúng vai trò của mình (kho xuất, duyệt mua, khớp hóa đơn, duyệt chi, chi tiền).
//   Mỗi việc: { dau, ten, phu, luc, han, href | moChiTiet }
async function layViecCuaToi() {
  const toi = api.toi;
  const an = (p) => p.catch(() => []);
  const [viec, deXuat, muaChoDuyet, muaChoHang, nhap, chi] = await Promise.all([
    an(api.doc('v_viec_ho_so', (q) => q.eq('nguoi_tiep_theo', toi.id).neq('trang_thai', 'huy').order('giao_viec_luc', { ascending: true }))),
    api.coVaiTro('kho', 'giam_doc') ? an(api.doc('v_de_xuat', (q) => q.eq('trang_thai', 'cho_xuat').order('id'))) : [],
    api.coVaiTro('quan_ly', 'giam_doc') ? an(api.doc('v_de_nghi_mua', (q) => q.eq('trang_thai', 'cho_duyet').order('id'))) : [],
    api.coVaiTro('kho', 'giam_doc') ? an(api.doc('v_de_nghi_mua', (q) => q.eq('trang_thai', 'da_duyet').order('id'))) : [],
    api.coVaiTro('ke_toan', 'giam_doc') ? an(api.doc('v_phieu_nhap', (q) => q.in('trang_thai', ['cho_khop', 'treo']).order('id'))) : [],
    api.coVaiTro('quan_ly', 'giam_doc', 'ke_toan') ? an(api.doc('v_de_nghi_chi', (q) => q.in('trang_thai', ['cho_duyet', 'da_duyet']).order('id'))) : [],
  ]);
  const ds = [];
  if (viec.length) {
    const hs = await an(api.doc('v_ho_so', (q) => q.in('id', viec.map((v) => v.ho_so_id))));
    const theoId = Object.fromEntries(hs.map((x) => [x.id, x]));
    for (const v of viec) {
      const x = theoId[v.ho_so_id]; const b = x && viecTiepTheo(x);
      if (!b) continue;
      ds.push({ dau: bienSo(x.bien_so_hien_thi, { maThay: x.ma }), ten: b.ten, phu: [x.xe, x.ten_khach].filter(Boolean).join(' · '),
        luc: v.giao_viec_luc, han: hanHoSo(x, v.giao_viec_luc), href: `#/ho-so/${x.id}` });
    }
  }
  const themPhieu = (loai, r, dau, phu, mo) => {
    const b = buocTiepPhieu(loai, r);
    if (!b || !b.vaiTro.some((vt) => api.coVaiTro(vt))) return;
    ds.push({ dau: h('b', null, dau), ten: b.ten, phu, luc: r.tao_luc, han: hanPhieu(loai, r),
      ...(typeof mo === 'string' ? { href: mo } : { moChiTiet: mo }) });
  };
  for (const r of deXuat) themPhieu('de_xuat', r, r.ma, `Xe ${r.bien_so} · ${r.nguoi_lap_ten || ''} đề xuất · ${r.so_dong} dòng`, (ve) => moDeXuat(r.id, ve));
  for (const r of muaChoDuyet) {
    if (r.nguoi_lap === toi.id && !api.coVaiTro('giam_doc')) continue;           // không tự duyệt đơn mình lập
    themPhieu('mua', r, r.ma, `${r.nha_cung_cap} · ${tien(r.tong_tien)} đ · ${r.nguoi_lap_ten || ''} lập`, (ve) => moChiTietMua(r.id, ve));
  }
  for (const r of muaChoHang) themPhieu('mua', r, r.ma, `${r.nha_cung_cap} · ${tien(r.tong_tien)} đ · đã duyệt, chờ hàng về`, (ve) => moChiTietMua(r.id, ve));
  for (const r of nhap) themPhieu('nhap', r, r.ma, `${r.nha_cung_cap} · ${tien(r.tong_tien)} đ · ${r.tao_boi_ten || ''} nhập${r.trang_thai === 'treo' ? ' · đang treo' : ''}`, (ve) => moChiTietNhap(r.id, ve));
  for (const r of chi) {
    if (r.trang_thai === 'cho_duyet' && r.nguoi_de_nghi === toi.id && !api.coVaiTro('giam_doc')) continue;
    themPhieu('de_nghi_chi', r, `Đề nghị chi ${tien(r.so_tien)} đ`, `${r.noi_dung || r.muc || ''} · ${r.nguoi_de_nghi_ten || ''} đề nghị`, '#/de-nghi');
  }
  ds.push(...(await viecTaiSanCuaToi()));
  // Quá hạn lên đầu, rồi theo hạn gần nhất, rồi theo lúc giao
  const khoa = (v) => (v.han ? v.han.getTime() : Infinity);
  ds.sort((a, b) => (quaHan(b.han) - quaHan(a.han)) || (khoa(a) - khoa(b)) || (new Date(a.luc) - new Date(b.luc)));
  return ds;
}

// Việc về thiết bị đồ nghề (028): kiểm tra tuần, kiểm kê tháng, xác nhận nhận, bảo dưỡng tới hạn, thiếu / hỏng chờ xử lý – theo vai trò
async function viecTaiSanCuaToi() {
  if (!api.coVaiTro('giam_doc', 'quan_ly', 'ke_toan', 'kho', 'truong_nhom')) return [];
  const ds = await api.doc('v_viec_tai_san', (q) => q.eq('chi_nhanh_id', api.toi.chi_nhanh_id)).catch(() => []);
  const truongNhom = api.coVaiTro('truong_nhom');
  return ds.filter((x) => (x.vai || []).some((v) => api.coVaiTro(v)) && (!x.to_id || !truongNhom || api.laNhanVien() || x.to_id === api.toi.to_id))
    .map((x) => ({
      dau: h('b', { class: 'dau-tai-san' }, x.loai === 'bao_duong' ? x.chi_tiet : 'Đồ nghề'),
      ten: x.tieu_de,
      phu: x.loai === 'bao_duong' ? `Nhóm ${x.nhom_ten}` : x.chi_tiet,
      han: x.han ? new Date(`${String(x.han).slice(0, 10)}T23:59:59`) : null,
      luc: null,
      moChiTiet: () => { nhoPhien.ghi('ts_the', x.nhom_id); nhoPhien.ghi('kho_the', 'thiet_bi'); location.hash = '#/kho'; },
    }));
}

function khoiViecCuaToi(ds, taiLai) {
  const soQuaHan = ds.filter((v) => quaHan(v.han)).length;
  return h('section', { class: 'the viec-cua-toi' },
    h('h2', null, `Việc của ${api.toi.ho_ten.trim().split(/\s+/).pop()} (${ds.length})`,
      soQuaHan ? h('span', { class: 'nhan qua-han' }, `${soQuaHan} quá hạn`) : null),
    ds.length
      ? h('ul', { class: 'ds-viec-toi' }, ds.map((v) => {
        const qh = quaHan(v.han);
        const noiDung = [v.dau,
          h('span', { class: 'viec-ten' }, h('b', null, v.ten), h('small', null, v.phu)),
          v.han ? h('span', { class: `viec-luc han ${qh ? 'qua' : v.han.getTime() - Date.now() < 4 * 36e5 ? 'sap' : ''}` }, chuHan(v.han))
            : v.luc ? h('small', { class: 'viec-luc' }, `Từ ${ngayGio(v.luc)}`) : h('small', { class: 'viec-luc' }, 'Chờ xử lý')];
        return h('li', { class: qh ? 'qua-han' : null },
          v.href ? h('a', { href: v.href }, noiDung)
            : h('a', { href: '#', onclick: (e) => { e.preventDefault(); v.moChiTiet(taiLai); } }, noiDung));
      }))
      : h('p', { class: 'trong' }, 'Không có việc nào đang chờ anh/chị làm.'));
}

// ---------- Việc kho: số phiếu chờ xử lý theo vai trò ----------
async function demKho() {
  try {
    const [dx, thieu, mua, nhap] = await Promise.all([
      api.coVaiTro('kho', 'giam_doc', 'quan_ly') ? api.doc('de_xuat_vat_tu', (q) => q.eq('trang_thai', 'cho_xuat'), 'id') : [],
      api.coVaiTro('kho', 'giam_doc', 'quan_ly') ? api.doc('v_ton_kho', (q) => q.eq('duoi_toi_thieu', true).eq('hoat_dong', true), 'id') : [],
      api.coVaiTro('quan_ly', 'giam_doc') ? api.doc('de_nghi_mua', (q) => q.eq('trang_thai', 'cho_duyet'), 'id') : [],
      api.coVaiTro('ke_toan', 'giam_doc') ? api.doc('phieu_nhap', (q) => q.in('trang_thai', ['cho_khop', 'treo']), 'id') : [],
    ]);
    const o = [
      api.coVaiTro('kho', 'giam_doc', 'quan_ly') ? ['de_xuat', 'Đề xuất vật tư chờ xuất', dx.length] : null,
      api.coVaiTro('kho', 'giam_doc', 'quan_ly') ? ['ton', 'Mã hàng dưới mức tối thiểu', thieu.length] : null,
      api.coVaiTro('quan_ly', 'giam_doc') ? ['mua', 'Đề nghị mua chờ duyệt', mua.length] : null,
      api.coVaiTro('ke_toan', 'giam_doc') ? ['nhap', 'Phiếu nhập chờ khớp hóa đơn', nhap.length] : null,
    ].filter(Boolean);
    return o.length ? o : null;
  } catch { return null; }
}
function khoiKho(o) {
  return h('section', { class: 'luoi-dem' }, o.map(([the, nhan, so]) =>
    h('a', { class: `o-dem ${so ? '' : 'mo'}`, href: `#/kho?the=${the}` }, h('b', null, so), h('span', null, nhan))));
}
