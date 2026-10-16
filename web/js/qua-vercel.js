// Đường đi của lời gọi dữ liệu REST. Mặc định gọi thẳng Supabase (như từ trước tới nay).
// Khi bật "đi qua tên miền của app" thì lời gọi /rest/v1/... đi vòng qua /sb/rest/v1/... của chính trang này,
// Vercel chuyển tiếp sang Supabase (xem "rewrites" trong vercel.json). Lợi: bỏ được bước hỏi quyền của trình duyệt (CORS preflight)
// và dùng chung kết nối đã mở sẵn với trang. Đăng nhập (/auth) và ảnh (/storage) vẫn đi thẳng, không qua đây.
// Bật thử trên một máy: mở app với ?proxy=1 trên thanh địa chỉ (máy nhớ lại); tắt: ?proxy=0.
// Không import gì cả để chạy thử được bằng Node (test/thu_qua_vercel.mjs).

const KHOA_NHO = 'gara.qua_vercel';
const TIEN_TO = '/sb';

/** Máy này có đang bật đường đi qua tên miền không (đọc ?proxy=1/0 trên địa chỉ rồi nhớ lại). */
export function dangBat(chuoiTimKiem, kho) {
  try {
    const m = /[?&]proxy=([01])(?![0-9])/.exec(chuoiTimKiem);
    if (m) {
      if (m[1] === '1') kho.setItem(KHOA_NHO, '1');
      else kho.removeItem(KHOA_NHO);
    }
    return kho.getItem(KHOA_NHO) === '1';
  } catch {
    return false;
  }
}

/** Đổi địa chỉ REST của đúng dự án này sang đường đi qua tên miền; mọi địa chỉ khác giữ nguyên. */
export function diaChiMoi(url, goc) {
  const dau = goc + '/rest/v1/';
  return typeof url === 'string' && url.startsWith(dau) ? TIEN_TO + '/rest/v1/' + url.slice(dau.length) : url;
}

/** Hàm fetch riêng cho supabase-js khi đang bật; trả null nếu tắt (supabase-js dùng fetch mặc định). */
export function layFetch(goc, bat, fetchGoc) {
  if (!bat) return null;
  return (input, init) => fetchGoc(input instanceof URL ? diaChiMoi(input.href, goc) : diaChiMoi(input, goc), init);
}
