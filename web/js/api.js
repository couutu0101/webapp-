// Mọi lệnh gọi cơ sở dữ liệu nằm ở đây. Trang giao diện chỉ gọi các hàm trong file này.
import { sb } from './supabase.js';
import { taoAnhNho, duongDanAnhNho, nenAnh, chaySongSong } from './ui.js';

function loi(error) {
  const e = new Error(error?.message || 'Lỗi không xác định');
  e.code = error?.code;
  return e;
}
// Cổ đông chỉ xem (030): chặn mọi lệnh ghi ngay ở trình duyệt; máy chủ cũng không cho cổ đông ghi
const RPC_CHI_DOC = new Set(['bang_viec_to', 'bao_cao_co_dong', 'ket_qua_kinh_doanh', 'tra_cuu_xe', 'tra_cuu_xe_nhanh', 'da_doi_mat_khau',
  'nhap_xuat_ton', 'doanh_thu_theo_thang', 'chi_tiet_kqkd', 'chi_phi_theo_muc', 'lai_gop_theo_to', 'so_du_cuoi_thang', 'so_tien_tra_lai_khach',
  'khoi_dong', 'viec_hom_nay', 'canh_bao_hom_nay',
  // 054: xem thông báo của hồ sơ; bấm "Đã nhận" chỉ đổi dòng thông báo của chính mình (không đụng số liệu nào, không làm bộ nhớ tạm kho tải lại)
  'thong_bao_ho_so', 'nhan_thong_bao']);
// Đếm số lần ghi thành công trong phiên: bộ nhớ tạm (vd danh sách hàng kho) biết khi nào phải tải lại
let soGhi = 0;
export const soLanGhi = () => soGhi;
export async function rpc(ten, thamSo = {}) {
  if (laCoDong() && !RPC_CHI_DOC.has(ten)) throw new Error('Tài khoản cổ đông chỉ được xem số liệu, không sửa được.');
  const { data, error } = await sb.rpc(ten, thamSo);
  if (error) throw loi(error);
  if (!RPC_CHI_DOC.has(ten)) soGhi++;
  return data;
}
// 045: giám đốc xem được mọi chi nhánh (quyền máy chủ) nhưng màn hình chỉ hiện chi nhánh đang chọn.
// Bảng / view có cột chi_nhanh_id tự lọc theo chi nhánh đó. Không lọc: nhan_vien (trang Nhân viên xem cả công ty),
// tai_khoan_quy (danh mục – từng trang tự lọc), don_vi_lien_quan (dùng chung), khách / xe (dùng chung).
const BANG_THEO_CHI_NHANH = new Set([
  'ho_so', 'v_ho_so', 'phieu_thu_chi', 'v_phieu_thu_chi', 'de_nghi_chi', 'v_de_nghi_chi', 'dich_vu_nhanh', 'v_dich_vu_nhanh',
  'de_nghi_mua', 'v_de_nghi_mua', 'de_xuat_vat_tu', 'v_de_xuat', 'hang_kho', 'lo_kho', 'v_ton_kho', 'v_the_kho',
  'phieu_nhap', 'v_phieu_nhap', 'phieu_xuat', 'v_phieu_xuat', 'kiem_ke', 'kiem_quy', 'v_so_du_quy', 'v_cong_no_ncc',
  'v_cong_no_noi_bo', 'v_doanh_thu', 'v_canh_bao', 'bang_luong_thang', 'chot_thang', 'chot_thang_lich_su',
  'tai_san', 'v_tai_san', 'kiem_tra_tai_san', 'su_co_tai_san', 'v_viec_tai_san', 'v_nhom_tai_san', 'nhat_ky_xuat_file']);
// doc('v_ho_so', q => q.eq('id', 5).single())
export async function doc(bang, tuyChinh = (q) => q, cot = '*') {
  let q = sb.from(bang).select(cot);
  if (toi?.chi_nhanh_id && BANG_THEO_CHI_NHANH.has(bang) && coVaiTro('giam_doc')) q = q.eq('chi_nhanh_id', toi.chi_nhanh_id);
  const { data, error } = await tuyChinh(q);
  if (error) throw loi(error);
  return data;
}
export async function them(bang, dong) {
  const { data, error } = await sb.from(bang).insert(dong).select();
  if (error) throw loi(error);
  soGhi++;
  return data;
}
export async function sua(bang, id, giaTri, khoa = 'id') {
  const { data, error } = await sb.from(bang).update(giaTri).eq(khoa, id).select();
  if (error) throw loi(error);
  if (!data || !data.length) throw new Error('Không lưu được (có thể bạn không có quyền sửa mục này).');
  soGhi++;
  return data;
}

// ---------- Đăng nhập ----------
// Nhân viên đăng nhập bằng tên đăng nhập (vd duy.cvdv) → địa chỉ nội bộ; giám đốc vẫn gõ email
export const DUOI_NOI_BO = '@nv.autohoangson.com';
export const emailDangNhap = (s) => { const t = String(s || '').trim().toLowerCase(); return t.includes('@') ? t : `${t}${DUOI_NOI_BO}`; };
export const dangNhap = async (email, matKhau) => {
  const { data, error } = await sb.auth.signInWithPassword({ email: emailDangNhap(email), password: matKhau });
  if (error) throw new Error(error.message === 'Invalid login credentials' ? 'Sai tên đăng nhập hoặc mật khẩu.' : error.message);
  return data;
};
// Giám đốc: tạo tài khoản nhân viên, đặt lại mật khẩu
export const taoTaiKhoan = (p) => rpc('tao_tai_khoan_nhan_vien', { p });
export const datLaiMatKhau = (id, matKhau) => rpc('dat_lai_mat_khau', { p_id: id, p_mat_khau: matKhau });
export const daDoiMatKhau = () => rpc('da_doi_mat_khau');
// 046: xóa tài khoản chưa có dữ liệu (đã dùng thì máy chủ báo khóa thay vì xóa)
export const xoaTaiKhoan = (id) => rpc('xoa_tai_khoan_nhan_vien', { p_id: id });
export const dangXuat = () => sb.auth.signOut();
export const layPhien = async () => (await sb.auth.getSession()).data.session;
export const khiDoiPhien = (cb) => sb.auth.onAuthStateChange(cb);
export const guiQuenMatKhau = async (email) => {
  const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
  if (error) throw loi(error);
};
export const datMatKhau = async (matKhau) => {
  const { error } = await sb.auth.updateUser({ password: matKhau });
  if (error) throw loi(error);
};

// ---------- Người đang dùng và danh mục (tải một lần) ----------
export const dm = {};
export let toi = null;

export async function taiToi(userId) {
  const ds = await doc('nhan_vien', (q) => q.eq('id', userId));
  toi = ds[0] || null;
  return toi;
}
export const coVaiTro = (...ds) => !!toi && toi.hoat_dong && ds.some((v) => toi.vai_tro.includes(v));
export const laNhanVien = () => coVaiTro('giam_doc', 'quan_ly', 'ke_toan', 'cvdv', 'kho');
// Cổ đông: xem được mọi số liệu như giám đốc, không có thao tác nào (nút thao tác vẫn kiểm bằng coVaiTro)
export const laCoDong = () => coVaiTro('co_dong');
export const duocXem = (...ds) => coVaiTro(...ds) || laCoDong();          // chỉ dùng cho phần XEM: menu, thẻ, cột tiền
export const xemNhuNhanVien = () => laNhanVien() || laCoDong();

// Đặt lại toàn bộ danh mục trong bộ nhớ (xóa phần của người dùng trước nếu đổi tài khoản không tải lại trang)
function ganDanhMuc(duLieu) {
  for (const k of Object.keys(dm)) delete dm[k];
  Object.assign(dm, duLieu);
  dm.ten = (bang, id) => (dm[bang] || []).find((x) => String(x.id) === String(id))?.ten ?? '';
  return dm;
}

// Cách cũ: nhiều lượt đọc riêng (dùng khi máy chủ chưa có hàm khoi_dong hoặc hàm báo lỗi)
export async function taiDanhMuc() {
  const bangs = ['chi_nhanh', 'hang_bao_hiem', 'giam_dinh_vien', 'hang_xe', 'dong_xe',
    'to_thuc_hien', 'muc_thu_chi', 'nha_cung_cap', 'don_vi_lien_quan', 'cai_dat'];
  if (duocXem('giam_doc', 'ke_toan', 'quan_ly')) bangs.push('tai_khoan_quy');
  if (xemNhuNhanVien()) bangs.push('nhan_vien');
  // 043: nợ đầu kỳ nội bộ chỉ giám đốc / quản lý chung / kế toán / cổ đông đọc; vai khác đọc tên đơn vị qua view
  const nguon = { don_vi_lien_quan: duocXem('giam_doc', 'ke_toan', 'quan_ly') ? 'don_vi_lien_quan' : 'v_don_vi_lien_quan' };
  // 052: bảng cai_dat khóa theo "khoa", không có cột id (xếp theo id trước đây báo lỗi nên cài đặt luôn rỗng → dùng giá trị mặc định)
  const cotKhoa = { cai_dat: 'khoa' };
  const kq = await Promise.all(bangs.map((b) => doc(nguon[b] || b, (q) => q.order(cotKhoa[b] || 'id', { ascending: true })).catch(() => [])));
  return ganDanhMuc(Object.fromEntries(bangs.map((b, i) => [b, kq[i]])));
}

// 052: MỘT lượt máy chủ trả người đăng nhập + danh mục (trước: đọc nhan_vien rồi mới đọc ~12 bảng danh mục = 2 đợt nối tiếp).
// Trả { toi, coDanhMuc }: coDanhMuc = false khi chưa có danh mục (chưa cấp vai trò, phải đổi mật khẩu, hoặc dùng cách cũ).
export async function khoiDong(userId) {
  if (!new URLSearchParams(location.search).has('khoi_dong_cu')) {
    try {
      const kq = await rpc('khoi_dong');
      if (kq && 'toi' in kq) {
        toi = kq.toi || null;
        if (kq.danh_muc) ganDanhMuc(kq.danh_muc);
        return { toi, coDanhMuc: !!kq.danh_muc };
      }
    } catch (e) {
      console.warn('Khởi động một lượt không được, dùng cách cũ:', e);
    }
  }
  return { toi: await taiToi(userId), coDanhMuc: false };
}
// 049: hãng xe / dòng xe xếp cho ô chọn – hãng hay gặp lên đầu (theo thứ tự này), còn lại A–Z, "Khác" cuối
const HANG_XE_HAY_GAP = ['VinFast', 'Toyota', 'Hyundai', 'Kia', 'Mazda', 'Mitsubishi', 'Ford', 'Honda'];
const soSanhTen = (a, b) => ((a.ten === 'Khác') - (b.ten === 'Khác')) || a.ten.localeCompare(b.ten, 'vi', { numeric: true, sensitivity: 'base' });
export function nhomHangXe() {
  const ds = dm.hang_xe || [];
  const hay = HANG_XE_HAY_GAP.map((t) => ds.find((x) => x.ten === t)).filter(Boolean);
  return { hay, khac: ds.filter((x) => !hay.includes(x)).sort(soSanhTen) };
}
export const dsDongXe = (hangId) => (dm.dong_xe || []).filter((d) => String(d.hang_xe_id) === String(hangId)).sort(soSanhTen);
// 045: chi nhánh đang hoạt động; giám đốc chọn chi nhánh làm việc (đổi xong tải lại trang)
export const dsChiNhanh = () => (dm.chi_nhanh || []).filter((c) => c.hoat_dong !== false);
export const tenChiNhanh = (id) => {
  const t = (dm.ten ? dm.ten('chi_nhanh', id) : '').replace(/^.*[–-]\s*/, '');
  return /^CN\b/i.test(t) ? t.replace(/^CN\s*/i, 'Chi nhánh ') : t;
};
// Tên ngắn (Phan Huy Ích / Tô Ký) và màu nhãn riêng của từng chi nhánh (046)
export const tenNganChiNhanh = (id) => tenChiNhanh(id).replace(/^Chi nhánh\s+/i, '');
const MAU_CHI_NHANH = { TK: 'vang', PHI: 'xanh' };
export const mauChiNhanh = (id) => MAU_CHI_NHANH[id]
  || ['tim', 'xanh-la', 'cam'][[...String(id || '')].reduce((t, c) => t + c.charCodeAt(0), 0) % 3];
export const doiChiNhanh = async (cn) => {
  const kq = await rpc('doi_chi_nhanh_lam_viec', { p_cn: cn });
  if (toi) toi.chi_nhanh_id = kq?.chi_nhanh_id || cn;
  return kq;
};
export const caiDat = (khoa, macDinh) => {
  const r = (dm.cai_dat || []).find((x) => x.khoa === khoa);
  return r ? Number(r.gia_tri) : macDinh;
};

// Xóa dòng danh mục chưa dùng ở đâu (019)
export const xoaDanhMuc = (bang, khoa) => rpc('xoa_danh_muc', { p_bang: bang, p_khoa: String(khoa) });

// ---------- Hồ sơ xe ----------
export const tiepNhanXe = (p) => rpc('tiep_nhan_xe', { p });
export const traCuuXe = (bienSo) => rpc('tra_cuu_xe', { p_bien_so: bienSo });
export const suaThongTin = (id, p) => rpc('sua_thong_tin_ho_so', { p_id: id, p });
// Báo giá theo nguồn (009): xe bảo hiểm chờ duyệt; khách ngoài bảo hiểm duyệt luôn. vat: 0.08 / 0.10 / 0.12
export const lapBaoGia = (id, dong, vat) => rpc('lap_bao_gia', { p_ho_so: id, dong, p_vat: vat });
// Giao / đổi người làm bước tiếp theo (010)
export const giaoViec = (id, nguoi) => rpc('giao_viec', { p_ho_so: id, p_nguoi: nguoi });
export const xoaHangMuc = (id) => rpc('xoa_hang_muc', { p_id: id });
// Duyệt giá + chia công nợ BH / khách (020): khachTra = tổng khách chi trả (có VAT), null = giữ như cũ
export const duyetGiaChia = (id, ngay, ketQua, khachTra) => rpc('duyet_gia_chia', { p_ho_so: id, p_ngay: ngay, ket_qua: ketQua, p_khach_tra: khachTra });
export const lapLenh = (id, henGiao, phanCong) => rpc('lap_lenh_sua_chua', { p_ho_so: id, p_hen_giao: henGiao, phan_cong: phanCong });
export const baoXong = (hangMucId) => rpc('bao_xong_hang_muc', { p_id: hangMucId });
export const baoPhatSinh = (id, moTa) => rpc('bao_phat_sinh', { p_ho_so: id, p_mo_ta: moTa });
// 045: máy chủ trả xe của mọi chi nhánh cho giám đốc → chỉ giữ chi nhánh đang chọn
export const locBangViec = (ds) => {
  ds = ds || [];
  return coVaiTro('giam_doc') && toi?.chi_nhanh_id ? ds.filter((x) => !x.chi_nhanh_id || x.chi_nhanh_id === toi.chi_nhanh_id) : ds;
};
export const bangViecTo = async () => locBangViec(await rpc('bang_viec_to'));

// 052: mọi thứ trang "Việc hôm nay" cần trong HAI lượt chạy song song (viec_hom_nay + canh_bao_hom_nay: hai phần nặng nhất ở máy chủ
// chạy cùng lúc). Khi mở app thẳng vào trang này, ứng dụng bấm gọi sẵn ngay từ lúc khởi động (song song với khoi_dong)
// và trang lấy kết quả đã gọi sẵn.
let viecSan = null;
const goiViecHomNay = () => {
  const p = { chinh: rpc('viec_hom_nay'), canhBao: rpc('canh_bao_hom_nay') };
  p.chinh.catch(() => {}); p.canhBao.catch(() => {});             // lỗi được xử lý ở nơi trang dùng kết quả
  return p;
};
export function taiSanViecHomNay() { viecSan = { luc: Date.now(), p: goiViecHomNay() }; }
// Trả { chinh, canhBao } (hai Promise riêng: phần nào lỗi thì trang tự đọc lại phần đó bằng cách cũ)
export function layViecHomNay() {
  const s = viecSan; viecSan = null;
  return s && Date.now() - s.luc < 30000 ? s.p : goiViecHomNay();
}
export const kcs = (id, dat, loi, lamLai) => rpc('kcs', { p_ho_so: id, p_dat: dat, p_loi: loi, p_lam_lai: lamLai });
// 050: bước Detailing (rửa xe, đánh bóng) trước KCS; CVDV bật / tắt bước này cho từng xe
export const detailing = (id, dat, loi = null, lamLai = null) => rpc('detailing', { p_ho_so: id, p_dat: dat, p_loi: loi, p_lam_lai: lamLai });
export const datQuaDetailing = (id, qua) => rpc('dat_qua_detailing', { p_ho_so: id, p_qua: qua });
export const duyetGiamGia = (id, soTien, lyDo) => rpc('duyet_giam_gia', { p_ho_so: id, p_so_tien: soTien, p_ly_do: lyDo });
export const duyetGiaoConNo = (id) => rpc('duyet_giao_xe_con_no', { p_ho_so: id });
export const giaoXe = (id, p) => rpc('giao_xe', { p_ho_so: id, p });
// 036: kế toán thu tiền & giao xe trong một lần (giao không được thì phiếu thu cũng không ghi)
export const thuTienGiaoXe = (id, p) => rpc('thu_tien_giao_xe', { p_ho_so: id, p });
// 036: sửa cách chia công nợ bảo hiểm / khách sau khi đã duyệt giá (khấu trừ – giảm trừ)
export const suaChiaCongNo = (id, khachTra) => rpc('sua_chia_cong_no', { p_ho_so: id, p_khach_tra: khachTra });
export const guiHoSoBH = (id, ngay) => rpc('gui_ho_so_bh', { p_ho_so: id, p_ngay: ngay });
export const nhapHoaHong = (id, soTien, ghiChu, boQua) =>
  rpc('nhap_hoa_hong_gdv', { p_ho_so: id, p_so_tien: soTien, p_ghi_chu: ghiChu, p_bo_qua_canh_bao: boQua });
export const ghiChamSoc = (id, ketQua, henBD) => rpc('ghi_cham_soc', { p_ho_so: id, p_ket_qua: ketQua, p_hen_bao_duong: henBD });
// 041: boQua = false → máy chủ hỏi lại (CANH_BAO) nếu hồ sơ đã thu cọc; dùng với chay()
export const huyHoSo = (id, lyDo, boQua = false) => rpc('huy_ho_so', { p_ho_so: id, p_ly_do: lyDo, p_bo_qua_canh_bao: !!boQua });
// 041: phát sinh không cần làm thêm; hồ sơ bảo hành thêm hạng mục miễn phí
export const xuLyPhatSinh = (id, ghiChu) => rpc('xu_ly_phat_sinh', { p_ho_so: id, p_ghi_chu: ghiChu });
export const themHangMucBaoHanh = (id, dong) => rpc('them_hang_muc_bao_hanh', { p_ho_so: id, p_dong: dong });

// v_ho_so có sẵn số km (037), người làm bước tiếp theo và lúc giao việc (040): một lần đọc
export const layHoSo = async (id) => {
  const hs = (await doc('v_ho_so', (q) => q.eq('id', id)))[0] ?? null;
  if (!hs) return hs;
  // 047: cờ bắt ảnh / file và lúc lưu báo giá gần nhất (cột ở bảng ho_so; vai không đọc được bảng thì coi như không bắt)
  const [x] = await doc('ho_so', (q) => q.eq('id', id), 'bat_buoc_anh,bao_gia_luc').catch(() => []);
  return { ...hs, bat_buoc_anh: !!x?.bat_buoc_anh, bao_gia_luc: x?.bao_gia_luc || null };
};
export const layHangMuc = (id) => doc('hang_muc', (q) => q.eq('ho_so_id', id).order('lan_bao_gia').order('id'));
export const layNhatKy = (id) => doc('ho_so_nhat_ky', (q) => q.eq('ho_so_id', id).order('luc', { ascending: false }));
export const layTep = (id) => doc('ho_so_tep', (q) => q.eq('ho_so_id', id).order('tai_luc'));
export const layPhatSinh = (id) => doc('phat_sinh', (q) => q.eq('ho_so_id', id).order('luc', { ascending: false }));
export const layKcs = (id) => doc('kcs', (q) => q.eq('ho_so_id', id).order('luc', { ascending: false }));
export const layDetailing = (id) => doc('ket_qua_detailing', (q) => q.eq('ho_so_id', id).order('luc', { ascending: false }));

// Tên tệp trong kho lưu trữ: bỏ dấu, ký tự lạ; thêm thời điểm + chuỗi ngẫu nhiên để nhiều ảnh tải cùng lúc
// (điện thoại hay đặt cùng tên image.jpg) không đè nhau
const tenLuu = (file) => `${Date.now()}-${Math.random().toString(36).slice(2, 7)}-${file.name.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^\w.-]+/g, '-')}`;

// Tải nhiều tệp: nén ảnh lần lượt (đỡ tốn bộ nhớ điện thoại), tải lên 3 tệp cùng lúc; tệp lỗi không chặn tệp khác.
// taiMot(tepDaNen, tepGoc) → Promise; tienDo(soXong, tong) báo sau mỗi tệp. Trả { tong, xong, loi: [{ ten, e }] }.
let hangNen = Promise.resolve();
const nenLanLuot = (f, buoc) => { const p = hangNen.then(() => nenAnh(f, buoc)); hangNen = p.catch(() => {}); return p; };
export async function taiNhieu(files, buoc, taiMot, { toiDa = 3, tienDo = null } = {}) {
  const ds = [...(files || [])];
  let daXong = 0;
  const kq = await chaySongSong(ds, async (f) => {
    try { return await taiMot(await nenLanLuot(f, buoc), f); } finally { daXong++; tienDo?.(daXong, ds.length); }
  }, toiDa);
  const loi = kq.map((r, i) => (r.status === 'rejected' ? { ten: ds[i].name, e: r.reason } : null)).filter(Boolean);
  for (const x of loi) console.warn('Tải tệp lỗi', x.ten, x.e);
  return { tong: ds.length, xong: ds.length - loi.length, loi };
}

// Ảnh và biên bản: tải lên kho 'ho-so-xe' rồi ghi nhận vào hồ sơ
// 055: lyDo – quản lý chung / giám đốc tải vào bước đã khóa (máy chủ bắt lý do, ghi nhật ký). Không có lý do thì không gửi
// tham số này (CSDL chưa có 055 vẫn chạy).
export async function taiTep(hoSo, buoc, file, loai = 'anh', lyDo = null) {
  const duongDan = `${hoSo.chi_nhanh_id}/${hoSo.ma}/${buoc}-${tenLuu(file)}`;
  const kho = sb.storage.from('ho-so-xe');
  // 052: ảnh thu nhỏ làm và tải lên cùng lúc với ảnh chính (trước: xong ảnh chính mới bắt đầu). Lỗi ảnh nhỏ thì bỏ qua,
  // hồ sơ sẽ dùng ảnh lớn thay thế.
  const anhNho = taoAnhNho(file)
    .then((nho) => nho && kho.upload(duongDanAnhNho(duongDan), nho, { upsert: false, contentType: 'image/jpeg' }))
    .catch(() => {});
  const { error } = await kho.upload(duongDan, file, { upsert: false });
  await anhNho;
  if (error) throw loi(error);
  return rpc('them_tep', { p_ho_so: hoSo.id, p_buoc: buoc, p_loai: loai, p_duong_dan: duongDan, ...(lyDo ? { p_ly_do: lyDo } : {}) });
}
// Lấy link cho nhiều tệp một lần: { duong_dan: { lon, nho } }. Ảnh cũ chưa có bản nhỏ thì nho = lon.
export async function linkTepNhieu(dsDuongDan) {
  if (!dsDuongDan.length) return {};
  const tatCa = dsDuongDan.flatMap((d) => [d, duongDanAnhNho(d)]);
  const { data, error } = await sb.storage.from('ho-so-xe').createSignedUrls(tatCa, 3600);
  if (error) throw loi(error);
  const theoDuong = Object.fromEntries((data || []).filter((x) => x.signedUrl && !x.error).map((x) => [x.path, x.signedUrl]));
  return Object.fromEntries(dsDuongDan.map((d) => [d, { lon: theoDuong[d], nho: theoDuong[duongDanAnhNho(d)] || theoDuong[d] }]));
}

// Gợi ý xe khi gõ biển số (hoặc 4 số trở lên của SĐT khách): tối đa 8 xe
export async function goiYXe(chu) {
  const gon = String(chu || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
  if (gon.length < 2) return [];
  let xe = await doc('xe', (q) => q.ilike('bien_so', `%${gon}%`).order('bien_so').limit(8), 'id,bien_so,mau,dong_xe_id,khach_hang_id');
  if (/^\d{4,}$/.test(gon) && xe.length < 8) {
    const khTheoSdt = await doc('khach_hang', (q) => q.ilike('dien_thoai', `%${gon}%`).limit(8), 'id');
    if (khTheoSdt.length) {
      const them = await doc('xe', (q) => q.in('khach_hang_id', khTheoSdt.map((k) => k.id)).limit(8), 'id,bien_so,mau,dong_xe_id,khach_hang_id');
      for (const x of them) if (!xe.some((y) => y.id === x.id)) xe.push(x);
      xe = xe.slice(0, 8);
    }
  }
  const idKh = [...new Set(xe.map((x) => x.khach_hang_id).filter(Boolean))];
  const kh = idKh.length ? await doc('khach_hang', (q) => q.in('id', idKh), 'id,ten,dien_thoai') : [];
  const theoId = Object.fromEntries(kh.map((k) => [k.id, k]));
  return xe.filter((x) => x.bien_so).map((x) => ({ ...x, khach: theoId[x.khach_hang_id] || null }));
}

// ---------- Dịch vụ nhanh ----------
// 043: p.bo_qua_canh_bao = false → máy chủ hỏi lại khi trùng lượt (cùng xe, ngày, dịch vụ); dùng với chay()
export const ghiDichVuNhanh = (p) => rpc('ghi_dich_vu_nhanh', { p });
// Gợi ý / tra xe theo biển số hoặc SĐT cho Dịch vụ nhanh (032) – trưởng nhóm cũng dùng được
export const traCuuXeNhanh = (tu) => rpc('tra_cuu_xe_nhanh', { p_tu: tu });
export const huyDichVuNhanh = (id, lyDo) => rpc('huy_dich_vu_nhanh', { p_id: id, p_ly_do: lyDo });

// ---------- Thu chi ----------
export const lapPhieuThu = (p) => rpc('lap_phieu_thu', { p });
export const phanBoThem = (phieu, ds) => rpc('phan_bo_them', { p_phieu: phieu, p_ds: ds });
export const lapPhieuChuyen = (p) => rpc('lap_phieu_chuyen', { p });
export const huyPhieu = (id, lyDo) => rpc('huy_phieu', { p_id: id, p_ly_do: lyDo });
// 043: p.bo_qua_canh_bao = false → máy chủ hỏi lại (CANH_BAO) khi trả NCC vượt số còn nợ / chi hoa hồng chưa ghi; dùng với chay()
export const lapDeNghiChi = (p) => rpc('lap_de_nghi_chi', { p });
// 043: số tiền khách tối đa được trả lại của hồ sơ { dang_giu, dang_de_nghi, toi_da }
export const soTienTraLaiKhach = (id) => rpc('so_tien_tra_lai_khach', { p_ho_so: id });
// 043: chuyển phần đã chia của một phiếu thu từ xe này sang xe khác (kế toán / giám đốc; được cả khi tháng của phiếu đã chốt)
export const chuyenPhanBo = (phieu, tu, den, soTien, lyDo) =>
  rpc('chuyen_phan_bo', { p_phieu: phieu, p_tu_ho_so: tu, p_den_ho_so: den, p_so_tien: soTien, p_ly_do: lyDo });
export const duyetDeNghi = (id, dongY, lyDo) => rpc('duyet_de_nghi_chi', { p_id: id, p_dong_y: dongY, p_ly_do: lyDo });
export const huyDeNghi = (id) => rpc('huy_de_nghi_chi', { p_id: id });
// ---------- Tài sản – dụng cụ, máy móc của các nhóm (028) ----------
export const luuTaiSan = (p) => rpc('luu_tai_san', { p });
export const chuyenNhomTaiSan = (id, nhom, ghiChu) => rpc('chuyen_nhom_tai_san', { p_id: id, p_nhom: nhom, p_ghi_chu: ghiChu ?? null });
export const xacNhanNhanTaiSan = (ids) => rpc('xac_nhan_nhan_tai_san', { p_ids: ids });
export const luuKiemTraTaiSan = (p) => rpc('luu_kiem_tra_tai_san', { p });
export const baoSuCoTaiSan = (p) => rpc('bao_su_co_tai_san', { p });
export const xuLySuCoTaiSan = (p) => rpc('xu_ly_su_co_tai_san', { p });
export const danhDauBoiThuong = (id, daTru) => rpc('danh_dau_boi_thuong', { p_id: id, p_da_tru: daTru });
export const thanhLyTaiSan = (id, lyDo) => rpc('thanh_ly_tai_san', { p_id: id, p_ly_do: lyDo });
export const luuLichBaoDuong = (p) => rpc('luu_lich_bao_duong', { p });
export const ghiBaoDuong = (p) => rpc('ghi_bao_duong', { p });
export const xuatDuLieuTaiSan = () => rpc('xuat_du_lieu_tai_san');
export async function taiAnhTaiSan(ts, file) {
  const duongDan = `${ts.chi_nhanh_id}/tai-san/${ts.ma}/${tenLuu(file)}`;
  const kho = sb.storage.from('ho-so-xe');
  const anhNho = taoAnhNho(file)
    .then((nho) => nho && kho.upload(duongDanAnhNho(duongDan), nho, { upsert: false, contentType: 'image/jpeg' }))
    .catch(() => {});
  const { error } = await kho.upload(duongDan, file, { upsert: false });
  await anhNho;
  if (error) throw loi(error);
  return rpc('anh_tai_san', { p_id: ts.id, p_duong_dan: duongDan });
}
export const chiTien = (id, taiKhoan, ngay, chiHoBoi = null) => rpc('chi_tien', { p_de_nghi: id, p_tai_khoan: taiKhoan, p_ngay: ngay, ...(chiHoBoi ? { p_chi_ho_boi: chiHoBoi } : {}) });

// ---------- Nhân viên ----------
export const luuNhanVien = (id, p) => rpc('luu_nhan_vien', { p_id: id, p });
export const nhapBangLuong = (thang, tong) => rpc('nhap_bang_luong', { p_thang: thang, p_tong: tong });
// Kết quả kinh doanh tháng, chốt / mở lại tháng, báo cáo cổ đông (025)
export const ketQuaKinhDoanh = () => rpc('ket_qua_kinh_doanh');
export const chotThang = (thang, boQua = false) => rpc('chot_thang', { p_thang: thang, p_bo_qua_canh_bao: !!boQua });
export const moLaiThang = (thang, lyDo) => rpc('mo_lai_thang', { p_thang: thang, p_ly_do: lyDo });
export const baoCaoCoDong = () => rpc('bao_cao_co_dong');
// 042: báo cáo chuyên nghiệp – xem chi tiết một ô, chi phí theo mục, lãi gộp theo tổ, doanh thu theo tháng (máy chủ cộng),
// tiền – công nợ – tồn kho tại ngày cuối tháng. Tham số tháng/ngày dạng 'YYYY-MM-DD'.
export const chiTietKqkd = (thang, khoan) => rpc('chi_tiet_kqkd', { p_thang: thang, p_khoan: khoan });
export const chiPhiTheoMuc = (tu, den) => rpc('chi_phi_theo_muc', { p_tu: tu, p_den: den });
export const laiGopTheoTo = (tu, den) => rpc('lai_gop_theo_to', { p_tu: tu, p_den: den });
export const doanhThuTheoThang = (cn) => rpc('doanh_thu_theo_thang', cn ? { p_chi_nhanh: cn } : {});
export const soDuCuoiThang = (thang) => rpc('so_du_cuoi_thang', { p_thang: thang });
export const ghiKiemQuy = (taiKhoan, soDem, ghiChu) => rpc('ghi_kiem_quy', { p_tai_khoan: taiKhoan, p_so_dem: soDem, p_ghi_chu: ghiChu });

// ---------- Thông báo trên màn hình (054) ----------
// Máy chủ chưa chạy 054 (bảng chưa có) thì các hàm đọc báo lỗi; thongBaoThieuBang(e) nhận ra lỗi đó để giao diện lặng lẽ bỏ qua.
const COT_THONG_BAO = 'id,loai,khoa,tieu_de,noi_dung,chi_tiet,dich,ho_so_id,chi_nhanh_id,tao_luc,cap_nhat_luc,so_lan,da_nhan_luc';
export const thongBaoChuaNhan = () =>
  doc('thong_bao', (q) => q.is('da_nhan_luc', null).order('cap_nhat_luc', { ascending: true }).limit(50), COT_THONG_BAO);
export const thongBaoGanDay = (soDong = 80) =>
  doc('thong_bao', (q) => q.order('cap_nhat_luc', { ascending: false }).limit(soDong), COT_THONG_BAO);
// soLan = "số lần cập nhật" (so_lan) của từng thông báo lúc màn hình hiện – máy chủ chỉ ghi nhận đúng bản đó; trả về danh sách id đã ghi nhận
export const nhanThongBao = (ids, soLan = null) => rpc('nhan_thong_bao', soLan ? { p_ids: ids, p_so_lan: soLan } : { p_ids: ids });
export const thongBaoHoSo = (id) => rpc('thong_bao_ho_so', { p_ho_so: id });
export const thongBaoThieuBang = (e) => ['PGRST205', 'PGRST202', '42P01', '42883'].includes(e?.code)
  || /thong_bao/.test(e?.message || '') && /(schema cache|does not exist|Could not find)/i.test(e?.message || '');

// ---------- Kho (012) ----------
export const luuHangKho = (p) => rpc('luu_hang_kho', { p });
// Nhập – xuất – tồn một tháng ('YYYY-MM'), cộng ở máy chủ (040)
export const nhapXuatTon = (thang) => rpc('nhap_xuat_ton', { p_thang: thang });
// Xuất Excel – chỉ giám đốc (máy chủ kiểm quyền và ghi nhật ký mỗi lần xuất)
export const xuatDuLieuKho = () => rpc('xuat_du_lieu_kho');
export const xuatDuLieuKhach = () => rpc('xuat_du_lieu_khach');
// 043: p.bo_qua_canh_bao = false → máy chủ hỏi lại khi phiếu lớn không theo đề nghị mua; dùng với chay()
export const lapPhieuNhap = (p) => rpc('lap_phieu_nhap', { p });
// 043: kế toán sửa đơn giá phiếu nhập chưa khớp (theo hóa đơn) – lô trong kho và giá vốn phần đã xuất cập nhật theo
export const dieuChinhPhieuNhap = (id, dong, lyDo) => rpc('dieu_chinh_phieu_nhap', { p_id: id, p_dong: dong, p_ly_do: lyDo });
export const khopPhieuNhap = (id, khop, lyDo) => rpc('khop_phieu_nhap', { p_id: id, p_khop: khop, p_ly_do: lyDo ?? null });
export const huyPhieuNhap = (id, lyDo) => rpc('huy_phieu_nhap', { p_id: id, p_ly_do: lyDo });
export const lapDeXuat = (p) => rpc('lap_de_xuat_vat_tu', { p });
export const huyDeXuat = (id) => rpc('huy_de_xuat_vat_tu', { p_id: id });
// 043: đóng phần còn lại của đề xuất đã xuất một phần (không cần nữa)
export const dongDeXuat = (id, lyDo) => rpc('dong_de_xuat_vat_tu', { p_id: id, p_ly_do: lyDo });
export const xuatTheoDeXuat = (id, dong = null) => rpc('xuat_kho_de_xuat', { p_de_xuat: id, p_dong: dong });
export const chuyenMua = (id, p) => rpc('chuyen_mua', { p_de_xuat: id, p });
export const xuatDungChung = (p) => rpc('xuat_dung_chung', { p });
export const huyPhieuXuat = (id, lyDo) => rpc('huy_phieu_xuat', { p_id: id, p_ly_do: lyDo });
export const lapDeNghiMua = (p) => rpc('lap_de_nghi_mua', { p });
export const duyetDeNghiMua = (id, dongY, lyDo) => rpc('duyet_de_nghi_mua', { p_id: id, p_dong_y: dongY, p_ly_do: lyDo ?? null });
export const duyetMuaNgoaiLe = (id, lyDo) => rpc('duyet_mua_ngoai_le', { p_id: id, p_ly_do: lyDo });
export const huyDeNghiMua = (id) => rpc('huy_de_nghi_mua', { p_id: id });
export const taoKiemKe = (p) => rpc('tao_kiem_ke', { p });
export const luuDemKiemKe = (id, dong) => rpc('luu_dem_kiem_ke', { p_id: id, p_dong: dong });
export const chotKiemKe = (id, bienBan) => rpc('chot_kiem_ke', { p_id: id, p_bien_ban: bienBan ?? null });
export const huyKiemKe = (id) => rpc('huy_kiem_ke', { p_id: id });
// Ảnh hóa đơn / báo giá NCC: lưu vào 'ho-so-xe' dưới thư mục kho của chi nhánh
export async function taiTepKho(loai, chungTu, file) {
  const duongDan = `${chungTu.chi_nhanh_id}/kho/${chungTu.ma}/${tenLuu(file)}`;
  const { error } = await sb.storage.from('ho-so-xe').upload(duongDan, file, { upsert: false });
  if (error) throw loi(error);
  return rpc('them_tep_kho', { p_loai: loai, p_id: chungTu.id, p_duong_dan: duongDan, p_ten: file.name });
}
