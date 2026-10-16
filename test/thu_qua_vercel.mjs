// Thử công tắc "đi qua tên miền của app" (web/js/qua-vercel.js) bằng Node: node test/thu_qua_vercel.mjs
import assert from 'node:assert/strict';
import { dangBat, diaChiMoi, layFetch } from '../web/js/qua-vercel.js';

const GOC = 'https://abc.supabase.co';
const kho = () => { const d = new Map(); return { getItem: (k) => (d.has(k) ? d.get(k) : null), setItem: (k, v) => d.set(k, String(v)), removeItem: (k) => d.delete(k) }; };

// --- công tắc: mặc định tắt; ?proxy=1 bật và nhớ; ?proxy=0 tắt; ?proxy=10 hay ?proxyx=1 không tính
let k = kho();
assert.equal(dangBat('', k), false, 'mặc định tắt');
assert.equal(dangBat('?proxy=1', k), true, 'bật bằng ?proxy=1');
assert.equal(dangBat('', k), true, 'máy nhớ lại, lần sau không cần ?proxy=1');
assert.equal(dangBat('?a=1&proxy=0', k), false, 'tắt bằng ?proxy=0');
assert.equal(dangBat('', k), false, 'đã tắt thì nhớ là tắt');
k = kho();
assert.equal(dangBat('?proxy=10', k), false, '?proxy=10 không phải 1');
assert.equal(dangBat('?xproxy=1', k), false, '?xproxy=1 không phải ?proxy=1');
assert.equal(dangBat('?x=2&proxy=1&y=3', k), true, 'proxy ở giữa chuỗi');
assert.equal(dangBat('?proxy=1', { getItem() { throw new Error('bị chặn'); }, setItem() { throw new Error('bị chặn'); }, removeItem() {} }), false, 'bộ nhớ bị chặn → tắt, không lỗi');

// --- đổi địa chỉ: chỉ /rest/v1/ của đúng dự án
assert.equal(diaChiMoi(`${GOC}/rest/v1/v_ho_so?select=*&id=eq.5`, GOC), '/sb/rest/v1/v_ho_so?select=*&id=eq.5');
assert.equal(diaChiMoi(`${GOC}/rest/v1/rpc/khoi_dong`, GOC), '/sb/rest/v1/rpc/khoi_dong');
assert.equal(diaChiMoi(`${GOC}/auth/v1/token?grant_type=password`, GOC), `${GOC}/auth/v1/token?grant_type=password`, 'đăng nhập đi thẳng');
assert.equal(diaChiMoi(`${GOC}/storage/v1/object/anh/x.jpg`, GOC), `${GOC}/storage/v1/object/anh/x.jpg`, 'ảnh đi thẳng');
assert.equal(diaChiMoi(`https://khac.supabase.co/rest/v1/x`, GOC), 'https://khac.supabase.co/rest/v1/x', 'dự án khác giữ nguyên');
assert.equal(diaChiMoi(`${GOC}/rest/v1`, GOC), `${GOC}/rest/v1`, 'thiếu dấu / cuối thì giữ nguyên');
assert.equal(diaChiMoi(`${GOC}.evil.com/rest/v1/x`, GOC), `${GOC}.evil.com/rest/v1/x`, 'tên miền giống đầu nhưng khác thì giữ nguyên');
const req = { url: `${GOC}/rest/v1/x`, method: 'GET' };
assert.equal(diaChiMoi(req, GOC), req, 'đối tượng Request giữ nguyên');

// --- fetch riêng: tắt → null; bật → đổi địa chỉ rồi gọi fetch gốc với đúng tham số
assert.equal(layFetch(GOC, false, () => {}), null);
const goi = [];
const f = layFetch(GOC, true, (u, o) => { goi.push([u, o]); return 'ok'; });
const tuy = { method: 'POST', headers: { apikey: 'k' }, body: '{}' };
assert.equal(f(`${GOC}/rest/v1/rpc/viec_hom_nay`, tuy), 'ok');
assert.equal(f(new URL(`${GOC}/rest/v1/v_ho_so`), undefined), 'ok');
assert.equal(f(`${GOC}/auth/v1/user`, undefined), 'ok');
assert.deepEqual(goi, [['/sb/rest/v1/rpc/viec_hom_nay', tuy], ['/sb/rest/v1/v_ho_so', undefined], [`${GOC}/auth/v1/user`, undefined]]);
console.log('thu_qua_vercel: đạt hết');
