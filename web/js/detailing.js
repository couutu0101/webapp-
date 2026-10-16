// 050: bước Detailing (rửa xe, đánh bóng) giữa "Cấp phụ tùng – Sửa chữa" và KCS
//  - Ai làm: trưởng nhóm tổ Detailing, quản lý chung, giám đốc (khớp máy chủ public.detailing).
//  - Đạt → xe chuyển Chờ KCS. Chưa đạt → ghi lỗi, chọn hạng mục phải sửa lại → xe về Đang sửa (sửa xong lại qua Detailing).
//  - Dùng ở trang hồ sơ xe và bảng việc tổ (trưởng nhóm không mở được trang hồ sơ).
import { h, truong, oVung, oCheck, docForm, moModal, toast, chay } from './ui.js';
import * as api from './api.js';
import { TO_DETAILING } from './trang/giao-viec.js';

export const duocDetailing = () => !api.laCoDong()
  && (api.coVaiTro('quan_ly', 'giam_doc') || (api.coVaiTro('truong_nhom') && api.toi?.to_id === TO_DETAILING));

// hs: { id, ma | bien_so }; sauKhi: gọi khi xong (lỗi cũng gọi để vẽ lại)
export function detailingDat(hs, sauKhi, loi = sauKhi) {
  return chay(() => api.detailing(hs.id, true), { thanhCong: 'Đã xong Detailing – xe chuyển sang KCS.' }).then(sauKhi, loi);
}

// hm: hạng mục của xe (id, ten, to_id, trang_thai) – chọn trong các hạng mục đã xong
export function moDetailingTraVe(hs, hm, sauKhi) {
  const ds = (hm || []).filter((m) => m.trang_thai === 'xong');
  const form = h('form', null,
    truong('Lỗi cần sửa lại', oVung('loi', '', { rows: 2, placeholder: 'Ví dụ: cửa trước trái còn gợn sóng, sơn cản sau bị chảy' }), null, { batBuoc: true }),
    h('fieldset', { class: 'nhom-o' }, h('legend', null, 'Hạng mục phải sửa lại'),
      ds.length ? ds.map((m) => oCheck(`m_${m.id}`, false, `${m.ten}${m.to_id ? ` (${api.dm.ten('to_thuc_hien', m.to_id)})` : ''}`))
        : h('p', { class: 'trong' }, 'Không có hạng mục đã xong.')));
  moModal(`Detailing chưa đạt – ${hs.bien_so || hs.ma || ''}`, form, {
    nhanNut: 'Trả về sửa chữa',
    nutChinh: async () => {
      const d = docForm(form);
      if (!d.loi) { toast('Ghi lỗi cần sửa lại.', 'loi'); return false; }
      const lamLai = ds.filter((m) => d[`m_${m.id}`]).map((m) => m.id);
      if (!lamLai.length) { toast('Tích ít nhất một hạng mục phải sửa lại.', 'loi'); return false; }
      await api.detailing(hs.id, false, d.loi, lamLai);
      toast('Đã trả xe về tổ sửa lại – sửa xong xe quay lại Detailing.');
      await sauKhi();
    },
  });
}
