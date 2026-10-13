// Biểu đồ đường SVG thuần (không thư viện), theo hướng dẫn dataviz: 1 trục, nét 2px, điểm 8px có viền nền,
// lưới hairline, chú giải luôn có khi ≥ 2 chuỗi, nhãn giá trị chỉ ở điểm cuối, chữ thập + hộp giá trị khi rê chuột / phím mũi tên.
// Chuỗi tối đa 3 (bảng màu đã kiểm colorblind trên nền trắng: #2a78d6, #eb6834, #1baf7a).
import { h, tien } from './ui.js';

export const MAU_CHUOI = ['#2a78d6', '#eb6834', '#1baf7a'];

// Số gọn cho trục và nhãn cuối: 1.250.000 → "1,25 tr", 2.500.000.000 → "2,5 tỷ", 850.000 → "850 k"
export function soGon(n) {
  const v = Number(n) || 0; const dau = v < 0 ? '−' : ''; const a = Math.abs(v);
  const gon = (x, d) => x.toLocaleString('vi-VN', { maximumFractionDigits: d });
  if (a >= 1e9) return `${dau}${gon(a / 1e9, 2)} tỷ`;
  if (a >= 1e6) return `${dau}${gon(a / 1e6, a >= 1e8 ? 0 : 1)} tr`;
  if (a >= 1e3) return `${dau}${gon(a / 1e3, 0)} k`;
  return `${dau}${gon(a, 0)}`;
}

// Bước lưới "đẹp" cho khoảng giá trị
function buocDep(khoang, soVach = 4) {
  const tho = khoang / soVach; const mu = 10 ** Math.floor(Math.log10(tho || 1)); const d = tho / mu;
  const k = d <= 1 ? 1 : d <= 2 ? 2 : d <= 2.5 ? 2.5 : d <= 5 ? 5 : 10;
  return k * mu;
}

const ns = 'http://www.w3.org/2000/svg';
function svgEl(tag, attrs = {}, ...con) {
  const el = document.createElementNS(ns, tag);
  for (const [k, v] of Object.entries(attrs)) if (v !== null && v !== undefined) el.setAttribute(k, v);
  for (const c of con.flat()) if (c !== null && c !== undefined) el.append(typeof c === 'string' ? document.createTextNode(c) : c);
  return el;
}

/**
 * bieuDoDuong({ nhan: ['10/2026', ...], chuoi: [{ ten, giaTri: [...] }], tieuDe, phuDe, cao })
 *  - nhan: nhãn trục ngang (tháng), chuoi: tối đa 3 chuỗi cùng đơn vị (đồng)
 *  Trả về phần tử .bieu-do, tự vẽ lại khi đổi bề rộng.
 */
export function bieuDoDuong({ nhan, chuoi, tieuDe, phuDe, cao = 280 }) {
  const ds = chuoi.slice(0, 3).map((c, i) => ({ ...c, mau: MAU_CHUOI[i] }));
  const khung = h('div', { class: 'bieu-do' });
  const dau = h('div', { class: 'bieu-do-dau' }, tieuDe ? h('h3', null, tieuDe) : null, phuDe ? h('p', { class: 'mo-ta' }, phuDe) : null);
  const chuGiai = h('div', { class: 'bieu-do-chu-giai', role: 'list' }, ds.map((c) => h('span', { role: 'listitem' },
    h('i', { class: 'khoa-duong', style: `background:${c.mau}` }), c.ten)));
  const vung = h('div', { class: 'bieu-do-vung', tabindex: '0', role: 'img',
    'aria-label': `${tieuDe || 'Biểu đồ'}: ${ds.map((c) => `${c.ten} ${c.giaTri.map((v, i) => `${nhan[i]} ${tien(v) || 0}`).join(', ')}`).join('; ')}` });
  const hop = h('div', { class: 'bieu-do-hop', hidden: true });
  const khungSvg = h('div', { class: 'bieu-do-khung-svg' });
  vung.append(khungSvg, hop);
  khung.append(dau, ds.length > 1 ? chuGiai : null, vung);
  if (!nhan.length) { dat_(khungSvg, h('p', { class: 'trong' }, 'Chưa có số liệu.')); return khung; }

  let chon = nhan.length - 1;            // tháng đang xem (chữ thập)
  let hinh = null;                       // toạ độ sau khi vẽ

  function ve() {
    const W = Math.max(280, vung.clientWidth || 600); const H = cao;
    const trai = 56; const phai = 76; const tren = 14; const duoi = 30;
    const w = W - trai - phai; const hh = H - tren - duoi;
    const tatCa = ds.flatMap((c) => c.giaTri.map(Number));
    let min = Math.min(0, ...tatCa); let max = Math.max(0, ...tatCa);
    if (max === min) max = min + 1;
    const buoc = buocDep(max - min); min = Math.floor(min / buoc) * buoc; max = Math.ceil(max / buoc) * buoc;
    if (max === min) max = min + buoc;
    const y = (v) => tren + hh - ((v - min) / (max - min)) * hh;
    const x = (i) => (nhan.length === 1 ? trai + w / 2 : trai + (i * w) / (nhan.length - 1));
    const svg = svgEl('svg', { viewBox: `0 0 ${W} ${H}`, width: W, height: H, class: 'bieu-do-svg', 'aria-hidden': 'true' });
    // Lưới + nhãn trục dọc
    for (let v = min; v <= max + 1e-9; v += buoc) {
      const yy = y(v);
      svg.append(svgEl('line', { x1: trai, x2: W - phai, y1: yy, y2: yy, class: v === 0 ? 'bd-goc' : 'bd-luoi' }));
      svg.append(svgEl('text', { x: trai - 8, y: yy + 4, class: 'bd-truc', 'text-anchor': 'end' }, soGon(v)));
    }
    // Nhãn trục ngang
    nhan.forEach((t, i) => svg.append(svgEl('text', { x: x(i), y: H - 8, class: 'bd-truc', 'text-anchor': i === 0 && nhan.length > 1 ? 'start' : i === nhan.length - 1 && nhan.length > 1 ? 'end' : 'middle' }, t)));
    // Chữ thập (vẽ dưới đường)
    const chuThap = svgEl('line', { class: 'bd-chu-thap', y1: tren, y2: tren + hh, x1: x(chon), x2: x(chon) });
    svg.append(chuThap);
    // Đường + điểm
    const diem = [];
    ds.forEach((c, k) => {
      const d = c.giaTri.map((v, i) => `${i ? 'L' : 'M'}${x(i)} ${y(Number(v) || 0)}`).join(' ');
      svg.append(svgEl('path', { d, fill: 'none', stroke: c.mau, 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));
      c.giaTri.forEach((v, i) => {
        const dot = svgEl('circle', { cx: x(i), cy: y(Number(v) || 0), r: 4, fill: c.mau, stroke: '#fff', 'stroke-width': 2 });
        svg.append(dot); diem.push({ k, i, dot });
      });
    });
    // Nhãn cuối: giá trị điểm cuối từng chuỗi, tránh đè nhau (đẩy ra xa ≥ 14px, có nét dẫn khi phải dời)
    const cuoi = ds.map((c, k) => ({ k, v: Number(c.giaTri[c.giaTri.length - 1]) || 0, y0: y(Number(c.giaTri[c.giaTri.length - 1]) || 0) })).sort((a, b) => a.y0 - b.y0);
    let truoc = -Infinity;
    for (const n of cuoi) { n.y1 = Math.max(n.y0, truoc + 14); truoc = n.y1; }
    const xc = x(nhan.length - 1);
    for (const n of cuoi) {
      if (Math.abs(n.y1 - n.y0) > 1) svg.append(svgEl('line', { x1: xc + 5, y1: n.y0, x2: xc + 10, y2: n.y1, class: 'bd-dan' }));
      svg.append(svgEl('line', { x1: xc + 11, x2: xc + 19, y1: n.y1, y2: n.y1, stroke: ds[n.k].mau, 'stroke-width': 2, 'stroke-linecap': 'round' }));
      svg.append(svgEl('text', { x: xc + 23, y: n.y1 + 4, class: 'bd-nhan-cuoi' }, soGon(n.v)));
    }
    dat_(khungSvg, svg);
    hinh = { x, y, diem, W, trai, phai };
    capNhatChon();
  }
  function dat_(el, ...con) { el.replaceChildren(...con.filter(Boolean)); }

  function capNhatChon() {
    if (!hinh) return;
    const svg = vung.querySelector('svg'); if (!svg) return;
    svg.querySelector('.bd-chu-thap').setAttribute('x1', hinh.x(chon)); svg.querySelector('.bd-chu-thap').setAttribute('x2', hinh.x(chon));
    for (const d of hinh.diem) d.dot.setAttribute('r', d.i === chon ? 5.5 : 4);
    // Hộp giá trị
    dat_(hop, h('div', { class: 'bieu-do-hop-dau' }, nhan[chon]),
      ...ds.map((c) => h('div', { class: 'bieu-do-hop-dong' }, h('i', { class: 'khoa-duong', style: `background:${c.mau}` }),
        h('b', null, `${tien(c.giaTri[chon]) || '0'} đ`), h('span', null, c.ten))));
    hop.hidden = false;
    const px = hinh.x(chon); const benPhai = px < hinh.W / 2;
    hop.style.left = benPhai ? `${px + 12}px` : ''; hop.style.right = benPhai ? '' : `${hinh.W - px + 12}px`;
    hop.style.top = '18px';
  }
  function chonTheoX(clientX) {
    const r = vung.getBoundingClientRect(); const px = clientX - r.left;
    let tot = 0; let kc = Infinity;
    for (let i = 0; i < nhan.length; i++) { const d = Math.abs(hinh.x(i) - px); if (d < kc) { kc = d; tot = i; } }
    if (tot !== chon) { chon = tot; capNhatChon(); }
  }
  vung.addEventListener('pointermove', (e) => { if (hinh) chonTheoX(e.clientX); });
  vung.addEventListener('pointerleave', () => { hop.hidden = true; });
  vung.addEventListener('pointerenter', () => { if (hinh) capNhatChon(); });
  vung.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowLeft') { chon = Math.max(0, chon - 1); capNhatChon(); e.preventDefault(); }
    if (e.key === 'ArrowRight') { chon = Math.min(nhan.length - 1, chon + 1); capNhatChon(); e.preventDefault(); }
    if (e.key === 'Escape') hop.hidden = true;
  });
  vung.addEventListener('focus', () => { if (hinh) capNhatChon(); });
  vung.addEventListener('blur', () => { hop.hidden = true; });

  // Vẽ khi đã gắn vào trang, vẽ lại khi đổi bề rộng
  let rong = 0;
  const ro = new ResizeObserver(() => { const w = vung.clientWidth; if (w && w !== rong) { rong = w; ve(); hop.hidden = true; } });
  ro.observe(vung);
  return khung;
}
