// Việc hôm nay: số xe theo bước, việc cần xử lý, bảng việc của tổ
import { h, oChonTep, bienSo, icon, ngayGio, chay, moModal, oVung, truong, docForm, nhanTrangThai, nenAnh, TRANG_THAI, dat } from '../ui.js';
import * as api from '../api.js';
import { viecTiepTheo } from './giao-viec.js';

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
  const [hoSo, canhBao, bangViec, viecCuaToi] = await Promise.all([
    laVanPhong ? api.doc('v_ho_so', (q) => q.not('trang_thai', 'in', '(dong,huy)')) : [],
    laVanPhong ? api.doc('v_canh_bao') : [],
    api.coVaiTro('truong_nhom', 'quan_ly', 'cvdv', 'giam_doc') ? api.bangViecTo() : [],
    laVanPhong ? layViecCuaToi() : [],
  ]);

  const nut = [];
  if (api.coVaiTro('cvdv', 'quan_ly', 'giam_doc')) nut.push(h('a', { class: 'nut chinh', href: '#/ho-so/moi' }, '+ Tiếp nhận xe'));
  nut.push(h('a', { class: 'nut', href: '#/dich-vu' }, '+ Dịch vụ nhanh'));
  nut.push(h('a', { class: 'nut', href: '#/de-nghi' }, '+ Đề nghị chi'));

  dat(el, 
    h('div', { class: 'tieu-de-trang' }, h('h1', null, 'Việc hôm nay'), h('div', { class: 'hang-nut' }, nut)),
    laVanPhong ? khoiViecCuaToi(viecCuaToi) : null,
    laVanPhong ? h('section', { class: 'luoi-dem' }, NHOM_DEM.map((n) => {
      const so = hoSo.filter((x) => n.tt.includes(x.trang_thai)).length;
      return h('a', { class: `o-dem ${so ? '' : 'mo'}`, href: `#/ho-so?tt=${n.tt.join(',')}` },
        h('b', null, so), h('span', null, n.nhan));
    })) : null,
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
      h('div', { class: 'luoi-the' }, ds.map((x) => h('article', { class: 'the-xe' },
        h('div', { class: 'the-xe-dau' }, bienSo(x.bien_so, { maThay: x.ma }), nhanTrangThai(x.trang_thai)),
        h('div', { class: 'mo-ta' }, x.xe),
        x.hen_giao ? h('div', { class: 'mo-ta' }, 'Hẹn giao: ', h('b', null, ngayGio(x.hen_giao))) : null,
        h('ul', { class: 'ds-hang-muc' }, (x.hang_muc || []).map((m) => h('li', { class: m.trang_thai },
          h('span', null, m.ten, m.nguoi_lam ? h('small', null, ` – ${m.nguoi_lam}`) : null),
          m.trang_thai === 'dang_lam'
            ? h('button', { class: 'nut nho', type: 'button', onclick: () => chay(() => api.baoXong(m.id), { thanhCong: `Đã báo xong: ${m.ten}` }).then(taiLai, taiLai) }, 'Báo xong')
            : h('span', { class: 'xong' }, '✓ Xong')))),
        h('div', { class: 'hang-nut' },
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

// ---------- Việc của tôi: các xe đang giao bước tiếp theo cho người đăng nhập ----------
async function layViecCuaToi() {
  try {
    const viec = await api.doc('v_viec_ho_so', (q) => q.eq('nguoi_tiep_theo', api.toi.id).neq('trang_thai', 'huy').order('giao_viec_luc', { ascending: true }));
    if (!viec.length) return [];
    const hs = await api.doc('v_ho_so', (q) => q.in('id', viec.map((v) => v.ho_so_id)));
    const theoId = Object.fromEntries(hs.map((x) => [x.id, x]));
    return viec.map((v) => ({ ...v, hs: theoId[v.ho_so_id] })).filter((v) => v.hs && viecTiepTheo(v.hs));
  } catch { return []; }
}

function khoiViecCuaToi(ds) {
  return h('section', { class: 'the viec-cua-toi' },
    h('h2', null, `Việc của tôi (${ds.length})`),
    ds.length
      ? h('ul', { class: 'ds-viec-toi' }, ds.map((v) => h('li', null,
        h('a', { href: `#/ho-so/${v.ho_so_id}` },
          bienSo(v.hs.bien_so_hien_thi, { maThay: v.hs.ma }),
          h('span', { class: 'viec-ten' }, h('b', null, viecTiepTheo(v.hs).ten), h('small', null, [v.hs.xe, v.hs.ten_khach].filter(Boolean).join(' · '))),
          h('small', { class: 'viec-luc' }, `Giao ${ngayGio(v.giao_viec_luc)}`)))))
      : h('p', { class: 'trong' }, 'Không có xe nào đang chờ anh/chị làm.'));
}
