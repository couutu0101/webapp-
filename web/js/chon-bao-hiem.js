// 048: chọn hãng bảo hiểm + giám định viên – nhập lúc NHẬP KẾT QUẢ DUYỆT GIÁ (không còn ở tiếp nhận).
// GDV lọc theo hãng; chọn "GDV mới – chờ thêm" thì phải ghi tên (kế toán thêm vào danh sách sau).
import { h, truong, oChon, oChu, dat } from './ui.js';
import * as api from './api.js';

export function khungChonBaoHiem({ hangId = null, gdvId = null, gdvTenTam = '' } = {}) {
  const dm = api.dm;
  const chonHang = oChon('hang_bh_id', (dm.hang_bao_hiem || []).filter((x) => x.hoat_dong || String(x.id) === String(hangId))
    .map((x) => ({ value: x.id, label: x.ten })), hangId);
  const chonGdv = oChon('gdv_id', [], null);
  const oGdvMoi = oChu('gdv_ten_tam', gdvTenTam || '', { placeholder: 'Tên giám định viên mới' });
  const khungGdvMoi = truong('Tên GDV mới', oGdvMoi, 'Kế toán sẽ thêm người này vào danh sách trong Danh mục.', { batBuoc: true });
  const laChoThem = () => (dm.giam_dinh_vien || []).find((x) => String(x.id) === chonGdv.value)?.la_cho_them;
  const hienGdvMoi = () => { khungGdvMoi.hidden = !laChoThem(); };
  const capNhatGdv = (giu) => {
    const hang = chonHang.value;
    const ds = (dm.giam_dinh_vien || []).filter((g) => (g.hoat_dong || String(g.id) === String(giu)) && (g.la_cho_them || !g.hang_id || String(g.hang_id) === hang))
      .sort((a, b) => (b.la_cho_them - a.la_cho_them) || ((String(b.hang_id) === hang) - (String(a.hang_id) === hang)) || a.ten.localeCompare(b.ten, 'vi'));
    dat(chonGdv, h('option', { value: '' }, hang ? '— Chọn —' : '— Chọn hãng trước —'),
      ds.map((g) => h('option', { value: g.id }, g.la_cho_them ? g.ten : `${g.ten}${g.hang_id ? ` (${dm.ten('hang_bao_hiem', g.hang_id)})` : ''}`)));
    if (giu && [...chonGdv.options].some((o) => o.value === String(giu))) chonGdv.value = String(giu);
    hienGdvMoi();
  };
  chonHang.addEventListener('change', () => capNhatGdv(chonGdv.value));
  chonGdv.addEventListener('change', hienGdvMoi);
  capNhatGdv(gdvId);

  const el = h('div', { class: 'luoi-o hai-cot khung-chon-bh' },
    truong('Hãng bảo hiểm', chonHang, null, { batBuoc: true }),
    truong('Giám định viên', chonGdv, null, { batBuoc: true }),
    khungGdvMoi);
  return {
    el,
    // Kiểm đủ ô bắt buộc: trả câu báo lỗi (và đặt con trỏ vào ô thiếu) hoặc null
    kiemTra() {
      if (!chonHang.value) { chonHang.focus(); return 'Chọn hãng bảo hiểm.'; }
      if (!chonGdv.value) { chonGdv.focus(); return 'Chọn giám định viên.'; }
      if (laChoThem() && !oGdvMoi.value.trim()) { oGdvMoi.focus(); return 'Ghi tên giám định viên mới.'; }
      return null;
    },
    giaTri: () => ({
      hang_bh_id: Number(chonHang.value) || null,
      gdv_id: Number(chonGdv.value) || null,
      gdv_ten_tam: laChoThem() ? oGdvMoi.value.trim() : null,
    }),
  };
}
