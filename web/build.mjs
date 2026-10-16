// Đóng gói bản chạy thật. Vercel tự gọi `node build.mjs` (xem vercel.json); kết quả nằm ở thư mục dist/.
//
// Làm 4 việc:
//  1. Gộp ~30 tệp mã thành MỘT tệp và nén nhỏ lại: lần đầu mở app tải ít hơn, ít lượt hỏi máy chủ hơn.
//  2. Đặt tên tệp theo nội dung (app-3F9A1C20.js). Tệp không đổi thì trình duyệt giữ nguyên cả năm, không hỏi lại máy chủ;
//     có bản mới thì tên đổi → tự tải đúng bản mới. (Trước đây mỗi lần mở app phải hỏi lại ~48 tệp xem có đổi không.)
//  3. Viết lại index.html: trỏ đúng tên mới + dặn trình duyệt tải song song ngay từ đầu (modulepreload).
//  4. Chép ảnh, manifest. Thư viện Supabase vẫn nạp từ CDN như cũ (địa chỉ cố định trong js/supabase.js).
//
// Chạy thử trên máy: `npm install && node build.mjs`. Mã nguồn trong js/, css/ KHÔNG đổi; thử giao diện vẫn chạy trên mã nguồn.
// `node build.mjs --thu` đóng gói bản DÙNG ĐỂ THỬ vào dist-thu/: y hệt bản thật nhưng xuất sẵn api, kho để bộ thử giao diện
// (test/thu_giao_dien.py) gọi thẳng như khi chạy trên mã nguồn. Bản này KHÔNG đưa lên mạng (Vercel chỉ dùng dist/).

import { build } from 'esbuild';
import { existsSync } from 'node:fs';
import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { brotliCompressSync, constants, gzipSync } from 'node:zlib';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const GOC = dirname(fileURLToPath(import.meta.url));
const THU = process.argv.includes('--thu');
const RA = THU ? 'dist-thu' : 'dist';
const duongRa = (...p) => join(GOC, RA, ...p);

function dung(dieuKien, loi) {
  if (!dieuKien) {
    console.error('LỖI ĐÓNG GÓI: ' + loi);
    process.exit(1);
  }
}

await rm(duongRa(), { recursive: true, force: true });
await mkdir(duongRa('assets'), { recursive: true });

const chung = {
  absWorkingDir: GOC,
  bundle: true,
  minify: true,
  legalComments: 'none',
  metafile: true,
  logLevel: 'warning',
  sourcemap: 'linked', // chỉ tải khi mở công cụ gỡ lỗi của trình duyệt
  target: 'es2020', // mã nguồn đã dùng ?. và ?? (cần trình duyệt từ 2020 trở lên)
  outdir: `${RA}/assets`,
};

// ---- 1. Mã JavaScript: gộp thành MỘT tệp (js/app.js và mọi tệp nó nạp, kể cả trang Thiết bị / Cổ đông nạp theo yêu cầu).
//         Không tách tệp con: tệp con tải theo yêu cầu sẽ lỗi nếu máy đang mở app lúc ra bản mới; phần thêm vào chỉ ~15 KB nén. ----
const dauVao = THU
  ? { stdin: { contents: "import './js/app.js';\nexport * as api from './js/api.js';\nexport * as kho from './js/trang/kho.js';\n", resolveDir: GOC, sourcefile: 'dau-vao-thu.js' } }
  : { entryPoints: { app: 'js/app.js' } };
const kqJs = await build({
  ...chung,
  ...dauVao,
  format: 'esm',
  splitting: false,
  entryNames: 'app-[hash]',
  external: ['https://*'], // thư viện Supabase giữ nguyên địa chỉ CDN
});

// ---- 2. CSS: nén + đặt tên phông chữ theo nội dung (url(...) trong CSS được viết lại theo) ----
const kqCss = await build({
  ...chung,
  entryPoints: { app: 'css/app.css' },
  entryNames: '[name]-[hash]',
  assetNames: '[name]-[hash]',
  loader: { '.woff2': 'file', '.woff': 'file' },
});

const raJs = kqJs.metafile.outputs;
const raCss = kqCss.metafile.outputs;
const bo = (p) => p.slice(RA.length + 1); // 'dist/assets/x.js' -> 'assets/x.js'

const tepJs = Object.keys(raJs).filter((k) => k.endsWith('.js'));
dung(tepJs.length === 1, `mong đợi đúng 1 tệp JS sau đóng gói, thực tế ${tepJs.length}: ${tepJs.join(', ')}`);
const tenJs = tepJs[0];
const tenCss = Object.keys(raCss).find((k) => k.endsWith('.css'));
dung(tenCss, 'không thấy tệp CSS sau đóng gói');
dung(raJs[tenJs].imports.every((i) => i.external), `${tenJs} còn nạp tệp con – đóng gói phải gộp thành một tệp`);
const taiNgay = [tenJs];

// Phông chữ đã đặt tên mới: 'fonts/be-vietnam-pro-Regular.woff2' -> 'assets/be-vietnam-pro-Regular-XXXX.woff2'
const phongMoi = {};
for (const [k, o] of Object.entries(raCss)) for (const vao of Object.keys(o.inputs || {})) if (vao.startsWith('fonts/')) phongMoi[vao] = bo(k);

// ---- 3. index.html ----
let html = await readFile(join(GOC, 'index.html'), 'utf8');

function thay(mau, moi, ten) {
  dung(mau.test(html), `index.html không có ${ten} (mẫu ${mau}) – sửa index.html hoặc build.mjs cho khớp`);
  mau.lastIndex = 0;
  html = html.replace(mau, moi);
}

thay(/<link rel="stylesheet" href="css\/app\.css">/, `<link rel="stylesheet" href="${bo(tenCss)}">`, 'thẻ nạp css/app.css');
thay(/<script type="module" src="js\/app\.js"><\/script>/, `<script type="module" src="${bo(tenJs)}"></script>`, 'thẻ nạp js/app.js');

// Danh sách "tải trước" viết tay (js/...) thay bằng danh sách sinh tự động từ kết quả đóng gói
const dongTruoc = taiNgay.map((k) => `  <link rel="modulepreload" href="${bo(k)}">`).join('\n') + '\n';
let daChen = false;
thay(/^[ \t]*<link rel="modulepreload" href="js\/[^"]+">\r?\n/gm, () => (daChen ? '' : ((daChen = true), dongTruoc)), 'dòng modulepreload js/...');

for (const m of [...html.matchAll(/href="(fonts\/[^"]+)"/g)]) {
  dung(phongMoi[m[1]], `index.html tải trước phông ${m[1]} nhưng css/app.css không dùng phông này`);
  html = html.replace(`href="${m[1]}"`, `href="${phongMoi[m[1]]}"`);
}

dung(!/(?:href|src)="(?:js|css)\//.test(html), 'index.html vẫn còn đường dẫn js/ hoặc css/ chưa viết lại');
// Mọi đường dẫn nội bộ trong index.html phải trỏ tới tệp có thật trong dist/ (kiểm sau khi chép ảnh, bên dưới)
await writeFile(duongRa('index.html'), html);

// ---- 4. Chép ảnh, manifest, giấy phép phông chữ ----
await cp(join(GOC, 'img'), duongRa('img'), { recursive: true });
await cp(join(GOC, 'manifest.webmanifest'), duongRa('manifest.webmanifest'));
await mkdir(duongRa('fonts'), { recursive: true });
for (const f of await readdir(join(GOC, 'fonts'))) if (f.startsWith('OFL-')) await cp(join(GOC, 'fonts', f), duongRa('fonts', f));

// ---- Kiểm tra cuối ----
for (const m of html.matchAll(/(?:href|src)="([^":#?]+)"/g)) dung(existsSync(duongRa(m[1])), `index.html trỏ tới ${m[1]} nhưng ${RA}/ không có tệp này`);
const manifest = JSON.parse(await readFile(duongRa('manifest.webmanifest'), 'utf8'));
for (const bieuTuong of manifest.icons || []) dung(existsSync(duongRa(bieuTuong.src)), `manifest trỏ tới ${bieuTuong.src} nhưng ${RA}/ không có`);

// ---- Báo cáo kích thước (nén như máy chủ sẽ gửi) ----
const nen = (b) => ({ tho: b.length, gz: gzipSync(b, { level: 9 }).length, br: brotliCompressSync(b, { params: { [constants.BROTLI_PARAM_QUALITY]: 11 } }).length });
const cong = (a, b) => ({ tho: a.tho + b.tho, gz: a.gz + b.gz, br: a.br + b.br });
const kb = (n) => (n / 1024).toFixed(1).padStart(7) + ' KB';
async function tong(tep) {
  let t = { tho: 0, gz: 0, br: 0 };
  for (const f of tep) t = cong(t, nen(await readFile(f)));
  return t;
}
async function tepTheoDuoi(thuMuc, duoi) {
  const ra = [];
  for (const e of await readdir(thuMuc, { withFileTypes: true })) {
    const p = join(thuMuc, e.name);
    if (e.isDirectory()) ra.push(...(await tepTheoDuoi(p, duoi)));
    else if (e.name.endsWith(duoi)) ra.push(p);
  }
  return ra;
}
const truocJs = await tong(await tepTheoDuoi(join(GOC, 'js'), '.js'));
const truocCss = await tong([join(GOC, 'css/app.css')]);
const sauJs = await tong((await readdir(duongRa('assets'))).filter((f) => f.endsWith('.js')).map((f) => duongRa('assets', f)));
const sauCss = await tong([duongRa(bo(tenCss))]);
console.log(`Đóng gói xong → web/${RA}/`);
console.log('                          thô        gzip      brotli');
for (const [ten, t] of [['Mã JS trước (≈30 tệp)', truocJs], ['Mã JS sau (1 tệp)', sauJs], ['CSS trước', truocCss], ['CSS sau', sauCss]]) {
  console.log(`${ten.padEnd(26)}${kb(t.tho)}${kb(t.gz)}${kb(t.br)}`);
}
console.log('Tệp JS:', bo(tenJs), '· CSS:', bo(tenCss));
