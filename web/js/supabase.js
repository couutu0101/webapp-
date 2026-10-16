// Kết nối Supabase. Thư viện tải từ CDN, phiên bản cố định để không tự đổi.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './cau-hinh.js';
import { dangBat, layFetch } from './qua-vercel.js';

// Mặc định gọi thẳng Supabase. ?proxy=1 trên địa chỉ: lời gọi dữ liệu đi qua tên miền của app (xem qua-vercel.js)
let batQuaVercel = false;
try { batQuaVercel = dangBat(location.search, localStorage); } catch { /* trình duyệt chặn bộ nhớ: dùng mặc định */ }
const fetchRieng = layFetch(SUPABASE_URL, batQuaVercel, (...a) => fetch(...a));

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  ...(fetchRieng ? { global: { fetch: fetchRieng } } : {}),
});
