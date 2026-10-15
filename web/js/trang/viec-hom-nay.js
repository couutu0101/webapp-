// Việc hôm nay: số xe theo bước, việc cần xử lý, bảng việc của tổ
import { h, oChonTep, bienSo, ngayGio, tien, chay, moModal, oVung, truong, docForm, nhanTrangThai, dat, thanhBuocNho, chipNguoi, nhoPhien, toast } from '../ui.js';
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
// Việc cần xử lý không gắn xe (hoặc cần xử lý ở trang khác): mở đúng chỗ làm
const LIEN_KET_CANH_BAO = { thu_chua_phan_bo: '#/thu-chi?chua_chia=1', nhap_ngoai_de_nghi: '#/kho?the=nhap', de_nghi_cho_duyet: '#/de-nghi' };

// Mọi thứ của trang tải MỘT đợt song song (040): trước đây ~19 lượt, 4 đợt nối tiếp, đọc hồ sơ 4 lần.
// Phần nào tải lỗi (mạng, quyền) thì ghi lại và báo ở đầu trang, không để danh sách trống mà không nói gì.
async function taiDuLieu() {
  const vp = api.laNhanVien(); const toi = api.toi;
  const quanLy = api.coVaiTro('quan_ly', 'giam_doc'); const keToan = api.coVaiTro('ke_toan', 'giam_doc');
  const xemKho = api.coVaiTro('kho', 'giam_doc', 'quan_ly');
  const loi = [];
  const an = (p, ten) => Promise.resolve(p).catch((e) => { console.warn(`Việc hôm nay – ${ten}:`, e); loi.push(ten); return []; });
  const xeDaGiao = (q) => q.eq('trang_thai', 'dong').not('giao_luc', 'is', null).eq('tu_excel', false).order('giao_luc', { ascending: false }).limit(300);
  const [hoSo, chamSocDong, hoaHongDong, canhBao, bangViec, deXuat, mua, nhap, chi, dvn, thieu, taiSan] = await Promise.all([
    vp ? an(api.doc('v_ho_so', (q) => q.not('trang_thai', 'in', '(dong,huy)')), 'hồ sơ xe') : [],
    // Hồ sơ đã đóng còn việc song song sau giao (036): chăm sóc (quản lý), hoa hồng GDV (kế toán) – mới nhất trước
    vp && quanLy ? an(api.doc('v_ho_so', (q) => xeDaGiao(q.is('cham_soc_luc', null))), 'chăm sóc sau giao') : [],
    vp && keToan ? an(api.doc('v_ho_so', (q) => xeDaGiao(q.not('gdv_id', 'is', null).is('hoa_hong_gdv', null))), 'hoa hồng GDV') : [],
    // 048: hãng BH / GDV chọn lúc nhập kết quả duyệt giá → bỏ nhắc "chưa có giám định viên" (trùng việc chờ duyệt giá)
    vp ? an(api.doc('v_canh_bao').then((ds) => ds.filter((x) => x.loai !== 'thieu_gdv')), 'việc cần xử lý') : [],
    api.coVaiTro('truong_nhom', 'quan_ly', 'cvdv', 'ke_toan', 'giam_doc') ? an(api.bangViecTo(), 'bảng việc xưởng') : [],
    vp && xemKho ? an(api.doc('v_de_xuat', (q) => q.eq('trang_thai', 'cho_xuat').order('id')), 'đề xuất vật tư') : [],
    vp && api.coVaiTro('quan_ly', 'giam_doc', 'kho') ? an(api.doc('v_de_nghi_mua', (q) => q.in('trang_thai', ['cho_duyet', 'da_duyet']).order('id')), 'đề nghị mua') : [],
    vp && keToan ? an(api.doc('v_phieu_nhap', (q) => q.in('trang_thai', ['cho_khop', 'treo']).order('id')), 'phiếu nhập kho') : [],
    vp && api.coVaiTro('quan_ly', 'giam_doc', 'ke_toan') ? an(api.doc('v_de_nghi_chi', (q) => q.in('trang_thai', ['cho_duyet', 'da_duyet']).order('id')), 'đề nghị chi') : [],
    // 043: lượt dịch vụ nhanh còn phải thu – lọc ở máy chủ, không giới hạn 60 ngày (lượt cũ chưa thu trước đây bị sót)
    vp && keToan ? an(api.doc('v_dich_vu_nhanh', (q) => q.eq('trang_thai', 'hieu_luc').gt('con_thu', 0).order('ngay').limit(200)), 'dịch vụ nhanh') : [],
    vp && xemKho ? an(api.doc('v_ton_kho', (q) => q.eq('duoi_toi_thieu', true).eq('hoat_dong', true), 'id'), 'tồn kho') : [],
    vp || api.coVaiTro('truong_nhom') ? an(viecTaiSanCuaToi(), 'đồ nghề') : [],
  ]);
  const theoId = new Map([...chamSocDong, ...hoaHongDong, ...hoSo].map((x) => [x.id, x]));
  return { vp, toi, quanLy, keToan, xemKho, loi, hoSo, tatCaHoSo: [...theoId.values()], canhBao, bangViec, deXuat, mua, nhap, chi, dvn, thieu, taiSan };
}

export default async function trangViec(el) {
  const d = await taiDuLieu();
  const laVanPhong = d.vp;
  const { hoSo, canhBao, bangViec } = d;
  const viecCuaToi = laVanPhong ? viecCuaToiTu(d) : d.taiSan;
  const kho = laVanPhong ? demKho(d) : null;

  const nut = [];
  if (api.coVaiTro('cvdv', 'quan_ly', 'giam_doc')) nut.push(h('a', { class: 'nut chinh', href: '#/ho-so/moi' }, '+ Tiếp nhận xe'));
  nut.push(h('a', { class: 'nut', href: '#/dich-vu' }, '+ Dịch vụ nhanh'));
  nut.push(h('a', { class: 'nut', href: '#/de-nghi' }, '+ Đề nghị chi'));

  dat(el,
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Việc hôm nay'), h('div', { class: 'hang-nut' }, nut)),
    d.loi.length ? h('p', { class: 'thong-bao canh-bao', role: 'alert' },
      `Chưa tải được: ${d.loi.join(', ')} (mạng chậm hoặc mất kết nối) – số liệu bên dưới có thể thiếu. `,
      h('button', { class: 'nut nho', type: 'button', onclick: () => trangViec(el) }, 'Tải lại')) : null,
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
        h('ul', { class: 'ds-canh-bao' }, nhom.map((c) => {
          const href = LIEN_KET_CANH_BAO[c.loai] || (c.ho_so_id ? `#/ho-so/${c.ho_so_id}` : '#/de-nghi');
          return h('li', null,
            c.ho_so_id ? h('a', { href, class: 'lien-ket-xe' }, bienSo(c.bien_so, { maThay: c.ma })) : h('a', { href }, h('b', null, 'Xem'), ' '),
            c.noi_dung);
        })));
    }));
}

function khoiBangViec(ds, taiLai) {
  // Đúng danh sách vai trò của hàm máy chủ (bao_xong_hang_muc, lap_de_xuat_vat_tu, bao_phat_sinh)
  const duocBaoXong = api.coVaiTro('truong_nhom', 'cvdv', 'quan_ly', 'giam_doc');
  const duocDeXuat = api.coVaiTro('truong_nhom', 'cvdv', 'kho', 'quan_ly', 'giam_doc');
  const duocBaoPhatSinh = api.coVaiTro('truong_nhom', 'cvdv', 'quan_ly', 'giam_doc');
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
          m.trang_thai !== 'dang_lam' ? h('span', { class: 'xong' }, '✓ Xong')
            : duocBaoXong ? h('button', { class: 'nut nho', type: 'button', onclick: () => chay(() => api.baoXong(m.id), { thanhCong: `Đã báo xong: ${m.ten}` }).then(taiLai, taiLai) }, 'Báo xong')
              : h('span', { class: 'mo-ta' }, 'Đang làm')))),
        // 041: chỉ hiện nút người đó làm được (kế toán xem bảng việc nhưng không báo xong, không đề xuất, không báo phát sinh)
        duocDeXuat || duocBaoPhatSinh ? h('div', { class: 'hang-nut' },
          duocDeXuat ? h('button', { class: 'nut nho', type: 'button', onclick: () => moLapDeXuat({ id: x.ho_so_id, ma: x.ma, bien_so_hien_thi: x.bien_so, xe: x.xe }, taiLai) }, 'Đề xuất vật tư') : null,
          duocBaoPhatSinh ? h('button', { class: 'nut nho', type: 'button', onclick: () => moPhatSinh(x, taiLai) }, 'Báo phát sinh') : null) : null,
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
      const hs = { id: x.ho_so_id, ma: x.ma, chi_nhanh_id: x.chi_nhanh_id || api.toi.chi_nhanh_id };
      const kq = await api.taiNhieu(form.anh.files, 'phat_sinh', (f) => api.taiTep(hs, 'phat_sinh', f));
      if (kq.loi.length) toast(`Đã báo phát sinh, nhưng ${kq.loi.length}/${kq.tong} ảnh tải lên lỗi – báo CVDV chụp lại.`, 'loi');
      taiLai();
    },
  });
}

// ---------- Việc của tôi: việc đang chờ đúng người đăng nhập, quá hạn tô vàng ----------
//   - Xe: bước tiếp theo được giao cho mình (ho_so.nguoi_tiep_theo).
//   - Phiếu kho / đề nghị chi: đang chờ đúng vai trò của mình (kho xuất, duyệt mua, khớp hóa đơn, duyệt chi, chi tiền).
//   Mỗi việc: { dau, ten, phu, luc, han, href | moChiTiet }
function viecCuaToiTu(d) {
  const { toi } = d;
  const ds = [];
  // Xe: bước tiếp theo được giao cho mình (v_ho_so có sẵn người được giao và lúc giao – 040)
  for (const x of d.tatCaHoSo.filter((r) => r.nguoi_tiep_theo === toi.id)
    .sort((a, b) => String(a.giao_viec_luc || '').localeCompare(String(b.giao_viec_luc || '')))) {
    const b = viecTiepTheo(x);
    if (!b) continue;
    ds.push({ hoSoId: x.id, dau: bienSo(x.bien_so_hien_thi, { maThay: x.ma }), ten: b.ten, phu: [x.xe, x.ten_khach].filter(Boolean).join(' · '),
      luc: x.giao_viec_luc, han: hanHoSo(x, x.giao_viec_luc), href: `#/ho-so/${x.id}` });
  }
  const deXuat = api.coVaiTro('kho', 'giam_doc') ? d.deXuat : [];
  const muaChoDuyet = api.coVaiTro('quan_ly', 'giam_doc') ? d.mua.filter((r) => r.trang_thai === 'cho_duyet') : [];
  const muaChoHang = api.coVaiTro('kho', 'giam_doc') ? d.mua.filter((r) => r.trang_thai === 'da_duyet') : [];
  const { nhap, chi } = d;
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
  ds.push(...viecSauGiaoXe(d, ds));
  ds.push(...d.taiSan);
  // Quá hạn lên đầu, rồi theo hạn gần nhất, rồi theo lúc giao
  const khoa = (v) => (v.han ? v.han.getTime() : Infinity);
  ds.sort((a, b) => (quaHan(b.han) - quaHan(a.han)) || (khoa(a) - khoa(b)) || (new Date(a.luc) - new Date(b.luc)));
  return ds;
}

// Sau giao xe có nhiều việc SONG SONG (036): kế toán gửi hồ sơ BH / nhập hoa hồng / thu dịch vụ nhanh, quản lý gọi chăm sóc.
// Hồ sơ chỉ giao một người "bước tiếp theo", nên các việc còn lại lấy theo điều kiện của hồ sơ, không theo người được giao.
function viecSauGiaoXe(d, daCo) {
  const { toi, quanLy, keToan, dvn } = d;
  const xeDaGiao = d.tatCaHoSo.filter((x) => x.giao_luc && !x.tu_excel && x.trang_thai !== 'huy')
    .sort((a, b) => String(a.giao_luc).localeCompare(String(b.giao_luc)));
  const chamSoc = quanLy ? xeDaGiao.filter((x) => !x.cham_soc_luc) : [];
  const hoaHong = keToan ? xeDaGiao.filter((x) => x.gdv_id && (x.hoa_hong_gdv === null || x.hoa_hong_gdv === undefined)) : [];
  const ds = [];
  const daCoViec = (hoSoId, ten) => daCo.some((v) => v.hoSoId === hoSoId && v.ten === ten);
  const soNgay = api.caiDat('so_ngay_goi_cham_soc', 3);
  for (const x of chamSoc) {
    const b = viecTiepTheo(x);
    if (daCoViec(x.id, 'Chăm sóc sau giao')) continue;
    // Bước chăm sóc đã giao cho người khác thì hiện ở việc của người đó
    if (b?.ten === 'Chăm sóc sau giao' && x.nguoi_tiep_theo && x.nguoi_tiep_theo !== toi.id) continue;
    ds.push({ hoSoId: x.id, dau: bienSo(x.bien_so_hien_thi, { maThay: x.ma }), ten: 'Chăm sóc sau giao', phu: [x.xe, x.ten_khach, b?.ten && b.ten !== 'Chăm sóc sau giao' ? `đang chờ ${b.ten.toLowerCase()}` : null].filter(Boolean).join(' · '),
      luc: x.giao_luc, han: new Date(new Date(x.giao_luc).getTime() + soNgay * 864e5), href: `#/ho-so/${x.id}` });
  }
  for (const x of hoaHong) {
    if (daCoViec(x.id, 'Nhập hoa hồng GDV')) continue;
    ds.push({ hoSoId: x.id, dau: bienSo(x.bien_so_hien_thi, { maThay: x.ma }), ten: 'Nhập hoa hồng GDV', phu: [x.xe, x.gdv ? `GDV ${x.gdv}` : null].filter(Boolean).join(' · '),
      luc: x.giao_luc, han: null, href: `#/ho-so/${x.id}` });
  }
  for (const r of (keToan ? dvn : []).filter((v) => Number(v.con_thu ?? (Number(v.so_tien) - Number(v.da_thu))) > 0)) {
    ds.push({ dau: r.bien_so_hien_thi ? bienSo(r.bien_so_hien_thi) : h('b', null, 'Dịch vụ nhanh'), ten: `Thu tiền dịch vụ nhanh ${tien(r.con_thu ?? (Number(r.so_tien) - Number(r.da_thu)))} đ`,
      phu: `${r.dich_vu} · ${r.nguoi_lam || ''}`, luc: r.tao_luc, han: null, href: `#/thu-chi?dvn=${r.id}` });
  }
  return ds;
}

// Việc về thiết bị đồ nghề (028): kiểm tra tuần, kiểm kê tháng, xác nhận nhận, bảo dưỡng tới hạn, thiếu / hỏng chờ xử lý – theo vai trò
async function viecTaiSanCuaToi() {
  if (!api.coVaiTro('giam_doc', 'quan_ly', 'ke_toan', 'kho', 'truong_nhom')) return [];
  const ds = await api.doc('v_viec_tai_san', (q) => q.eq('chi_nhanh_id', api.toi.chi_nhanh_id));
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

// ---------- Việc kho: số phiếu chờ xử lý theo vai trò (đếm từ danh sách đã tải cho "Việc của tôi") ----------
function demKho(d) {
  const o = [
    d.xemKho ? ['de_xuat', 'Đề xuất vật tư chờ xuất', d.deXuat.length] : null,
    d.xemKho ? ['ton', 'Mã hàng dưới mức tối thiểu', d.thieu.length] : null,
    api.coVaiTro('quan_ly', 'giam_doc') ? ['mua', 'Đề nghị mua chờ duyệt', d.mua.filter((r) => r.trang_thai === 'cho_duyet').length] : null,
    d.keToan ? ['nhap', 'Phiếu nhập chờ khớp hóa đơn', d.nhap.length] : null,
  ].filter(Boolean);
  return o.length ? o : null;
}
function khoiKho(o) {
  return h('section', { class: 'luoi-dem' }, o.map(([the, nhan, so]) =>
    h('a', { class: `o-dem ${so ? '' : 'mo'}`, href: `#/kho?the=${the}` }, h('b', null, so), h('span', null, nhan))));
}
