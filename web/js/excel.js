// Tạo file Excel (.xlsx) ngay trên trình duyệt, không cần thư viện ngoài.
// File .xlsx là một gói zip gồm vài tệp XML; ở đây gói zip "không nén" (đủ nhỏ với vài nghìn dòng).
//
// taoXlsx([{ ten, tieuDe, phuDe, cot: [{ nhan, rong, kieu }], dong: [[...]], tong: [...] }]) → Uint8Array
//   kieu: 'chu' | 'so' (tự 0 hoặc 2 số lẻ) | 'tien' (số nguyên) | 'ngay' (chuỗi yyyy-mm-dd) | 'phan_tram'
//   tong: dòng tổng cuối bảng; phần tử 'SUM' = cộng cả cột, chuỗi khác = chữ, null = trống

const enc = new TextEncoder();

// ---------------- zip (lưu, không nén) ----------------
const BANG_CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(b) {
  let c = 0xffffffff;
  for (let i = 0; i < b.length; i++) c = BANG_CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function goiZip(tep) {
  const phan = []; const muc = []; let viTri = 0;
  for (const { ten, noiDung } of tep) {
    const tenB = enc.encode(ten); const du = typeof noiDung === 'string' ? enc.encode(noiDung) : noiDung;
    const crc = crc32(du);
    const dau = new DataView(new ArrayBuffer(30));
    dau.setUint32(0, 0x04034b50, true); dau.setUint16(4, 20, true); dau.setUint16(6, 0x0800, true);
    dau.setUint16(8, 0, true); dau.setUint16(10, 0, true); dau.setUint16(12, 0x21, true);
    dau.setUint32(14, crc, true); dau.setUint32(18, du.length, true); dau.setUint32(22, du.length, true);
    dau.setUint16(26, tenB.length, true); dau.setUint16(28, 0, true);
    phan.push(new Uint8Array(dau.buffer), tenB, du);
    const tt = new DataView(new ArrayBuffer(46));
    tt.setUint32(0, 0x02014b50, true); tt.setUint16(4, 20, true); tt.setUint16(6, 20, true); tt.setUint16(8, 0x0800, true);
    tt.setUint16(10, 0, true); tt.setUint16(12, 0, true); tt.setUint16(14, 0x21, true);
    tt.setUint32(16, crc, true); tt.setUint32(20, du.length, true); tt.setUint32(24, du.length, true);
    tt.setUint16(28, tenB.length, true); tt.setUint32(42, viTri, true);
    muc.push(new Uint8Array(tt.buffer), tenB);
    viTri += 30 + tenB.length + du.length;
  }
  const coMuc = muc.reduce((s, x) => s + x.length, 0);
  const cuoi = new DataView(new ArrayBuffer(22));
  cuoi.setUint32(0, 0x06054b50, true); cuoi.setUint16(8, tep.length, true); cuoi.setUint16(10, tep.length, true);
  cuoi.setUint32(12, coMuc, true); cuoi.setUint32(16, viTri, true);
  const tatCa = [...phan, ...muc, new Uint8Array(cuoi.buffer)];
  const ra = new Uint8Array(tatCa.reduce((s, x) => s + x.length, 0));
  let i = 0; for (const x of tatCa) { ra.set(x, i); i += x.length; }
  return ra;
}

// ---------------- XML của Excel ----------------
const xml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
  // bỏ ký tự điều khiển Excel không chấp nhận
  .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
const tenCot = (i) => { let s = ''; i += 1; while (i > 0) { const m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); } return s; };
const soNgay = (iso) => { const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number); return (Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 86400000; };

// Kiểu ô (thứ tự khớp cellXfs trong styles.xml)
const S = { thuong: 0, dauCot: 1, soNguyen: 2, soLe: 3, ngay: 4, tieuDe: 5, tongSo: 6, phuDe: 7, tongChu: 8, phanTram: 9, tongSoLe: 10 };
const STYLES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="3"><numFmt numFmtId="164" formatCode="#,##0"/><numFmt numFmtId="165" formatCode="#,##0.00"/><numFmt numFmtId="166" formatCode="dd/mm/yyyy"/></numFmts>
<fonts count="4"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font><font><b/><sz val="14"/><name val="Arial"/></font><font><i/><sz val="10"/><color rgb="FF555555"/><name val="Arial"/></font></fonts>
<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2B705"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF1F1EC"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFBBBBBB"/></left><right style="thin"><color rgb="FFBBBBBB"/></right><top style="thin"><color rgb="FFBBBBBB"/></top><bottom style="thin"><color rgb="FFBBBBBB"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="11">
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment wrapText="1" vertical="center"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="164" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="10" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="165" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;

function oChu(ref, v, s) { return v === null || v === undefined || v === '' ? `<c r="${ref}" s="${s}"/>` : `<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${xml(v)}</t></is></c>`; }
function oSo(ref, v, s) { return v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? `<c r="${ref}" s="${s}"/>` : `<c r="${ref}" s="${s}"><v>${Number(v)}</v></c>`; }

function o(ref, v, kieu) {
  switch (kieu) {
    case 'tien': return oSo(ref, v === null || v === undefined || v === '' ? v : Math.round(Number(v)), S.soNguyen);
    case 'so': return oSo(ref, v, Number.isInteger(Number(v)) ? S.soNguyen : S.soLe);
    case 'phan_tram': return oSo(ref, v, S.phanTram);
    case 'ngay': return v ? oSo(ref, soNgay(v), S.ngay) : `<c r="${ref}" s="${S.ngay}"/>`;
    default: return oChu(ref, v, S.thuong);
  }
}

function trangTinh(t) {
  const dongXml = []; let r = 1;
  const soCot = t.cot.length; const cotCuoi = tenCot(soCot - 1);
  if (t.tieuDe) dongXml.push(`<row r="${r}">${oChu(`A${r}`, t.tieuDe, S.tieuDe)}</row>`), r++;
  if (t.phuDe) dongXml.push(`<row r="${r}">${oChu(`A${r}`, t.phuDe, S.phuDe)}</row>`), r++;
  if (t.tieuDe || t.phuDe) r++;
  const dongDau = r;
  dongXml.push(`<row r="${r}" ht="30" customHeight="1">${t.cot.map((c, i) => oChu(`${tenCot(i)}${r}`, c.nhan, S.dauCot)).join('')}</row>`); r++;
  const batDau = r;
  for (const d of t.dong) {
    dongXml.push(`<row r="${r}">${t.cot.map((c, i) => o(`${tenCot(i)}${r}`, d[i], c.kieu)).join('')}</row>`); r++;
  }
  const ketThuc = r - 1;
  if (t.tong) {
    const oTong = t.tong.map((v, i) => {
      const ref = `${tenCot(i)}${r}`;
      if (v === 'SUM') {
        const tong = t.dong.reduce((s, d) => s + (Number(d[i]) || 0), 0);
        const le = t.cot[i].kieu === 'so' && !Number.isInteger(Math.round(tong * 1000) / 1000);
        const s = le ? S.tongSoLe : S.tongSo;
        return t.dong.length ? `<c r="${ref}" s="${s}"><f>SUM(${tenCot(i)}${batDau}:${tenCot(i)}${ketThuc})</f><v>${Math.round(tong * 1000) / 1000}</v></c>` : `<c r="${ref}" s="${s}"><v>0</v></c>`;
      }
      return oChu(ref, v, S.tongChu);
    });
    dongXml.push(`<row r="${r}">${oTong.join('')}</row>`); r++;
  }
  const cols = t.cot.map((c, i) => `<col min="${i + 1}" max="${i + 1}" width="${c.rong || 14}" customWidth="1"/>`).join('');
  const loc = t.dong.length ? `<autoFilter ref="A${dongDau}:${cotCuoi}${ketThuc}"/>` : '';
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
<sheetViews><sheetView workbookViewId="0"><pane ySplit="${dongDau}" topLeftCell="A${dongDau + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="15"/><cols>${cols}</cols>
<sheetData>${dongXml.join('')}</sheetData>${loc}
<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>
<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>
</worksheet>`;
}

// Tên trang tính: tối đa 31 ký tự, không có : \ / ? * [ ], không trùng
function tenTrang(ds) {
  const da = new Set();
  return ds.map((t) => {
    let goc = String(t.ten || 'Trang').replace(/[:\\/?*[\]]/g, '-').slice(0, 31) || 'Trang';
    let ten = goc; let n = 2;
    while (da.has(ten.toLowerCase())) ten = `${goc.slice(0, 28)} ${n++}`;
    da.add(ten.toLowerCase());
    return ten;
  });
}

export function taoXlsx(dsTrang) {
  const ten = tenTrang(dsTrang);
  const tep = [
    { ten: '[Content_Types].xml', noiDung: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${dsTrang.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')}</Types>` },
    { ten: '_rels/.rels', noiDung: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>` },
    { ten: 'xl/workbook.xml', noiDung: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><bookViews><workbookView/></bookViews><sheets>${ten.map((t, i) => `<sheet name="${xml(t)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')}</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>` },
    { ten: 'xl/_rels/workbook.xml.rels', noiDung: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${dsTrang.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join('')}<Relationship Id="rId${dsTrang.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>` },
    { ten: 'xl/styles.xml', noiDung: STYLES },
    ...dsTrang.map((t, i) => ({ ten: `xl/worksheets/sheet${i + 1}.xml`, noiDung: trangTinh(t) })),
  ];
  return goiZip(tep);
}

// Tải file về máy
export function taiFileExcel(tenFile, dsTrang) {
  const blob = new Blob([taoXlsx(dsTrang)], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = tenFile; a.style.display = 'none';
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
