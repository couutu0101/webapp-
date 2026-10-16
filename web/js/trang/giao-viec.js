// Người thực hiện và người làm bước tiếp theo của hồ sơ
//  - Người thực hiện: tự lấy người đăng nhập.
//  - Người làm bước tiếp theo: phần mềm tự giao theo gợi ý mỗi lần chuyển bước (CSDL, 010_giao_viec.sql);
//    ở tiếp nhận, báo giá, duyệt giá người làm chọn lại được; đổi giữa chừng: quản lý chung, giám đốc.
import { h, oChon, truong, moModal, toast, ngayGio, VAI_TRO, chipNguoi, vaiChinh, tenNgan, vienHan, coBuocHoSoBH } from '../ui.js';
import * as api from '../api.js';

// Ai làm được bước nào
export const VAI_TRO_BUOC = {
  bao_gia: ['cvdv', 'quan_ly', 'giam_doc'],
  duyet_gia: ['cvdv', 'quan_ly', 'giam_doc'],
  lenh: ['cvdv', 'quan_ly', 'giam_doc'],
  detailing: ['truong_nhom', 'quan_ly', 'giam_doc'],   // 050: trưởng nhóm tổ Detailing (DT), quản lý chung, giám đốc
  kcs: ['quan_ly', 'cvdv', 'giam_doc'],   // 047: CVDV cũng nghiệm thu KCS
  giao_xe: ['ke_toan', 'cvdv', 'quan_ly', 'giam_doc'],
  ho_so_bh: ['ke_toan', 'giam_doc'],
  cham_soc: ['quan_ly', 'giam_doc'],
};

// Việc tiếp theo của hồ sơ theo bước hiện tại: { ten, vaiTro } hoặc null khi không còn việc
export function viecTiepTheo(hs) {
  if (!hs || hs.tu_excel) return null;
  const chamSoc = !hs.cham_soc_luc ? { ten: 'Chăm sóc sau giao', vaiTro: VAI_TRO_BUOC.cham_soc } : null;
  switch (hs.trang_thai) {
    case 'tiep_nhan': return { ten: 'Lập báo giá', vaiTro: VAI_TRO_BUOC.bao_gia };
    case 'bao_gia': return { ten: 'Nhập kết quả duyệt giá', vaiTro: VAI_TRO_BUOC.duyet_gia };
    case 'da_duyet': return { ten: 'Lập lệnh sửa chữa', vaiTro: VAI_TRO_BUOC.lenh };
    case 'dang_sua': return { ten: 'Cấp phụ tùng – Sửa chữa', vaiTro: [], theoTo: true };
    case 'cho_detailing': return { ten: 'Detailing – rửa xe, đánh bóng', vaiTro: VAI_TRO_BUOC.detailing, toId: TO_DETAILING };
    case 'cho_kcs': return { ten: 'KCS', vaiTro: VAI_TRO_BUOC.kcs };
    case 'dat_kcs': return { ten: 'Thu tiền – giao xe', vaiTro: VAI_TRO_BUOC.giao_xe };
    case 'da_giao':
      // 043: phần bảo hiểm chi trả 0 đ / hồ sơ bảo hành thì không có hồ sơ gửi bảo hiểm (khớp máy chủ)
      if (coBuocHoSoBH(hs) && !hs.gui_hs_ngay) return { ten: 'Gửi hồ sơ bảo hiểm', vaiTro: VAI_TRO_BUOC.ho_so_bh };
      return chamSoc;
    case 'da_gui_hs': case 'dong': return chamSoc;
    default: return null;
  }
}

const nhanVien = () => (api.dm.nhan_vien || []).filter((n) => n.hoat_dong);
export const tenNhanVien = (id) => (api.dm.nhan_vien || []).find((n) => n.id === id)?.ho_ten || '';
// Tên gọi ngắn: "Nguyễn Trọng Duy" → "Duy"
export const tenGoi = (id) => tenNhanVien(id).trim().split(/\s+/).pop() || '';

export const TO_DETAILING = 'DT';
// toId: trưởng nhóm chỉ lấy người của tổ này (bước Detailing chỉ giao trưởng nhóm tổ Detailing)
function oChonNguoi(vaiTro, macDinh, name = 'giao_cho', toId = null) {
  const ds = nhanVien().filter((n) => !vaiTro?.length || n.vai_tro.some((v) => vaiTro.includes(v)
    && (v !== 'truong_nhom' || !toId || n.to_id === toId)));
  const vaiTroNhan = (n) => n.vai_tro.filter((v) => VAI_TRO[v] && v !== 'co_dong').map((v) => VAI_TRO[v]).join(', ');
  return oChon(name, ds.map((n) => ({ value: n.id, label: `${n.ho_ten}${vaiTroNhan(n) ? ` – ${vaiTroNhan(n)}` : ''}` })),
    ds.some((n) => n.id === macDinh) ? macDinh : (ds[0]?.id ?? ''), { trong: null });
}

// Khung cuối form: "Người thực hiện" + "Giao bước tiếp theo cho"
//   buocTiep: tên bước tiếp theo; vaiTro: ai làm được bước đó; macDinh: người gợi ý (mặc định: mình nếu làm được)
export function khungGiaoViec(buocTiep, vaiTro, macDinh = null) {
  const toi = api.toi;
  const minhLamDuoc = toi && toi.vai_tro.some((v) => vaiTro.includes(v));
  const chon = oChonNguoi(vaiTro, macDinh || (minhLamDuoc ? toi.id : null));
  const el = h('div', { class: 'khung-giao-viec luoi-o' },
    h('div', { class: 'truong' }, h('span', { class: 'truong-nhan' }, 'Người thực hiện'),
      h('div', { class: 'o-chi-xem' }, toi?.ho_ten || '')),
    truong(`Giao bước tiếp theo – ${buocTiep}`, chon, 'Gợi ý sẵn, chọn lại nếu giao người khác'));
  return { el, nguoi: () => chon.value || null };
}

// Sau khi lưu bước: giao cho người đã chọn (lỗi giao thì chỉ báo, không làm hỏng bước vừa lưu)
export async function giaoSauKhiLuu(hoSoId, nguoi) {
  if (!nguoi) return;
  try { await api.giaoViec(hoSoId, nguoi); } catch (e) { toast(`Đã lưu, nhưng chưa giao được người làm bước tiếp theo: ${e.message}`, 'loi'); }
}

// Ai đang phải làm bước tiếp theo của hồ sơ: [{ ten, nhan, vai, chu }]
//   Đang sửa: trưởng nhóm các tổ còn hạng mục; bước khác: người được giao (v_viec_ho_so)
export function aiDangLam(hs, viec, hm = []) {
  const v = viecTiepTheo(hs);
  if (!v) return [];
  if (v.theoTo) {
    const toDangLam = [...new Set(hm.filter((m) => ['duyet', 'dang_lam'].includes(m.trang_thai) && m.to_id).map((m) => m.to_id))];
    return toDangLam.map((t) => {
      const tr = (api.dm.nhan_vien || []).find((n) => n.hoat_dong && n.vai_tro.includes('truong_nhom') && n.to_id === t);
      return { ten: tr ? tr.ho_ten : `Tổ ${t}`, nhan: tr ? `Tổ ${t} · ${tr.ho_ten}` : `Tổ ${t}`, gon: tr ? tenNgan(tr.ho_ten) : `Tổ ${t}`, vai: 'truong_nhom', chu: String(t).slice(0, 2).toUpperCase() };
    });
  }
  const nv = (api.dm.nhan_vien || []).find((n) => n.id === viec?.nguoi_tiep_theo);
  const ten = nv?.ho_ten || viec?.nguoi_tiep_theo_ten;
  return ten ? [{ ten, nhan: ten, gon: tenNgan(ten), vai: vaiChinh(nv?.vai_tro || []) }] : [];
}
// Thẻ tên của một nhân viên theo id (người đã làm một bước)
export function chipNhanVien(id, opts = {}) {
  const nv = (api.dm.nhan_vien || []).find((n) => n.id === id);
  return nv ? chipNguoi(nv.ho_ten, { vai: vaiChinh(nv.vai_tro), ...opts }) : null;
}
// Thẻ tên từ một dòng v_viec_ho_so (danh sách hồ sơ): "Đặng Thanh Hận (tổ DS), Tổ DT" hoặc người được giao
export function chipsViec(hs, viec, { gon = true } = {}) {
  if (!viec) return [];
  if (hs.trang_thai === 'dang_sua' && viec.nguoi_tiep_theo_ten) {
    return viec.nguoi_tiep_theo_ten.split(/,\s*/).filter(Boolean).map((p) => {
      const m = /^(.+?)\s*\(tổ\s+([^)]+)\)$/i.exec(p);
      return m ? chipNguoi(m[1], { vai: 'truong_nhom', chu: m[2].slice(0, 2).toUpperCase(), gon, title: `Tổ ${m[2]} · ${m[1]}` })
        : chipNguoi(p, { vai: 'truong_nhom' });
    });
  }
  const nv = (api.dm.nhan_vien || []).find((n) => n.id === viec.nguoi_tiep_theo);
  const ten = nv?.ho_ten || viec.nguoi_tiep_theo_ten;
  return ten ? [chipNguoi(ten, { vai: vaiChinh(nv?.vai_tro || []), gon })] : [];
}

// Dòng "Đang chờ" ở đầu thẻ tiến độ của hồ sơ
//   viec: dòng v_viec_ho_so; hm: hạng mục (để biết các tổ đang sửa); han / chuHan: hạn của bước này
export function dongDangCho(hs, viec, hm, veLai, { han = null, chuHan = '' } = {}) {
  const v = viecTiepTheo(hs);
  if (!v) return null;
  const ds = aiDangLam(hs, viec, hm);
  const quaHan = han && han.getTime() < Date.now();
  const duocDoi = !v.theoTo && api.coVaiTro('quan_ly', 'giam_doc');
  return h('div', { class: `dang-cho${quaHan ? ' qua-han' : ''}` },
    h('span', { class: 'dang-cho-buoc' }, h('small', null, 'Đang chờ'), h('b', null, v.ten)),
    h('span', { class: 'dang-cho-ai' }, h('small', null, 'Giao cho'),
      ds.length ? ds.map((x) => chipNguoi(x.nhan, { vai: x.vai, chu: x.chu, title: x.ten }))
        : h('b', null, v.theoTo ? 'các tổ được giao' : 'Chưa giao ai'),
      viec?.giao_viec_luc && !v.theoTo ? h('small', { class: 'dang-cho-tu' }, `từ ${ngayGio(viec.giao_viec_luc)}`) : null),
    h('span', { class: 'dang-cho-phai' },
      vienHan(han, chuHan),
      duocDoi ? h('button', { class: 'nut nho', type: 'button', onclick: () => moDoiNguoi(hs, v, viec, veLai) }, 'Đổi người') : null));
}

function moDoiNguoi(hs, v, viec, veLai) {
  const chon = oChonNguoi(v.vaiTro, viec?.nguoi_tiep_theo, 'giao_cho', v.toId);
  moModal('Đổi người làm bước tiếp theo', h('div', null,
    h('p', { class: 'mo-ta' }, `${hs.ma} · Bước tiếp theo: ${v.ten}`),
    truong('Giao cho', chon)), {
    nhanNut: 'Giao việc',
    nutChinh: async () => {
      await api.giaoViec(hs.id, chon.value);
      toast(`Đã giao "${v.ten}" cho ${tenNhanVien(chon.value)}.`);
      await veLai();
    },
  });
}

// Người làm và ngày làm của từng bước (lấy từ nhật ký) – dùng cho thanh 10 bước
// Vào trạng thái nào = vừa xong bước nào (bước 5 "Cấp phụ tùng – Sửa chữa" xong khi sang chờ Detailing / chờ KCS;
// 050: từ chờ Detailing sang chờ KCS = xong bước 6 Detailing)
const BUOC_CUA_TRANG_THAI = { tiep_nhan: 1, bao_gia: 2, da_duyet: 3, dang_sua: 4, cho_detailing: 5, cho_kcs: 5, dat_kcs: 7, da_giao: 8, da_gui_hs: 9 };
export function nguoiLamTungBuoc(nk) {
  const kq = {};
  for (const n of [...nk].sort((a, b) => new Date(a.luc) - new Date(b.luc))) {
    let so = null;
    if (n.sang_trang_thai && n.tu_trang_thai !== n.sang_trang_thai) {
      so = BUOC_CUA_TRANG_THAI[n.sang_trang_thai] ?? null;
      if (n.sang_trang_thai === 'cho_kcs' && n.tu_trang_thai === 'cho_detailing') so = 6;
    } else if ((n.ghi_chu || '').startsWith('Gọi chăm sóc')) so = 10;
    if (!so || !n.boi) continue;
    // KCS chưa đạt đưa xe về "Đang sửa": bước 4 (lệnh sửa chữa) giữ người lập lệnh lần đầu, không đổi thành người ký KCS
    if (so === 4 && kq[4]) continue;
    kq[so] = { boi: n.boi, luc: n.luc };
    // Khách ngoài bảo hiểm: báo giá xong là duyệt luôn – bước 2 và 3 cùng một người
    if (so === 3 && n.tu_trang_thai === 'tiep_nhan') kq[2] = kq[3];
  }
  return kq;
}
