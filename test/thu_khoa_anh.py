"""055 + xem gọn hồ sơ (anh Thuận 17/10 20:01):
  - "Khi qua bước nào thì ảnh bước trước khóa lại không chỉnh sửa nữa" (quản lý chung / giám đốc thay được, ghi lý do)
  - "Khi vào hồ sơ xe hiện bước hiện tại. Có nút show mới hiện tất cả công đoạn"
Chạy: bash test/lam_moi_csdl.sh && (cd web && node build.mjs --thu) && WEB=web/dist-thu python3 test/may_chu_thu.py 8765 &
      python3 test/thu_khoa_anh.py"""
import os, sys, base64, re
from playwright.sync_api import sync_playwright, expect, TimeoutError as PwTimeout

GOC = os.path.dirname(os.path.abspath(__file__))
URL = 'http://127.0.0.1:8765/index.html'
ANH = os.path.join('/tmp', 'anh-thu.png')
CHUP = os.path.join('/tmp', 'chup')
os.makedirs(CHUP, exist_ok=True)
with open(ANH, 'wb') as f:
    f.write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))
GIA = open(os.path.join(GOC, 'supabase-gia.js'), encoding='utf-8').read()
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="#9ab"/></svg>'
MOD_JS = """window.__mod = async (ten) => {
  const dau = document.querySelector('script[type=module]').getAttribute('src');
  if (dau.startsWith('assets/')) return (await import(new URL(dau, location.href).href))[ten];
  return import(ten === 'api' ? './js/api.js' : './js/trang/' + ten + '.js');
};"""
loi = []
buoc = 0


def ghi(msg):
    global buoc
    buoc += 1
    print(f'[{buoc:02d}] {msg}', flush=True)


def yen(page, cho=8000):
    try:
        page.wait_for_load_state('networkidle', timeout=cho)
    except PwTimeout:
        pass


def chup(page, ten):
    yen(page)
    page.wait_for_timeout(250)
    page.screenshot(path=os.path.join(CHUP, f'{ten}.png'), full_page=True)


def mo(browser, email, rong=1280):
    ctx = browser.new_context(viewport={'width': rong, 'height': 900}, locale='vi-VN')
    ctx.add_init_script(MOD_JS)
    ctx.add_init_script('window.__TAT_THONG_BAO = true;')   # KHÔNG đặt __HIEN_TAT_CA: thử đúng cách xem gọn mặc định
    page = ctx.new_page()
    page.route(re.compile(r'.*supabase-js@2\.45\.4/\+esm$'), lambda r: r.fulfill(status=200, content_type='application/javascript', body=GIA))
    page.route(re.compile(r'.*/test-anh\.svg(\?.*)?$'), lambda r: r.fulfill(status=200, content_type='image/svg+xml', body=SVG))
    page.on('pageerror', lambda e: loi.append(f'{email}: {e}'))
    page.on('console', lambda m: loi.append(f'{email} console: {m.text}') if m.type == 'error' else None)
    page.goto(URL)
    page.fill('input[name=email]', email)
    page.fill('input[name=mat_khau]', 'matkhau123')
    page.click('button[type=submit]')
    page.wait_for_selector('.menu')
    return page


def ve_trang(page, hash_):
    if page.url == URL + hash_:
        page.reload()
    else:
        page.goto(URL + hash_)
    yen(page)
    page.wait_for_selector('h1 .bien-so, h1')
    page.wait_for_timeout(300)


def the(page, dau):
    """Thẻ (section.the) có tiêu đề h2 bắt đầu bằng chữ `dau`."""
    return page.locator('section.the').filter(has=page.locator('h2', has_text=re.compile('^' + re.escape(dau))))


def modal(page):
    return page.locator('.modal').last


TAO = """async ([bien, sdt]) => { const api = await window.__mod('api');
  const kq = await api.tiepNhanXe({ bien_so: bien, ten_khach: 'Khách 055', dien_thoai: sdt, nguon_tt: 'khach', tinh_trang_xe: 'Trầy cửa',
    tu_van: 'Không', qua_detailing: false, dong_xe_id: api.dm.dong_xe.find((d) => d.ten === 'VF3').id });
  const hs = await api.layHoSo(kq.id);
  const png = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='), (c) => c.charCodeAt(0));
  for (const b of ['nx_truoc', 'nx_sau', 'nx_trai', 'nx_phai', 'nt_truoc', 'nt_sau'])
    await api.taiTep(hs, b, new File([png], b + '.png', { type: 'image/png' }));
  await api.lapBaoGia(kq.id, [{ ten: 'Sơn cửa', nhom: 'son', gia_bao: 1200000 }], 0.08);
  return kq; }"""
LENH = """async (id) => { const api = await window.__mod('api'); const hm = await api.layHangMuc(id);
  await api.lapLenh(id, new Date(Date.now() + 864e5).toISOString(), hm.map((m) => ({ id: m.id, to_id: 'DS', nguoi_lam: '' }))); }"""

with sync_playwright() as p:
    b = p.chromium.launch()
    gd = mo(b, 'thuan@gara.vn')
    hs = gd.evaluate(TAO, ['51A-055.01', '0909055001'])
    ghi(f'Tạo hồ sơ {hs["ma"]}: khách ngoài BH, đủ 6 ảnh nhận xe, đã lập báo giá (đã duyệt – chờ lập lệnh, bước 4)')

    # ---------- Xem gọn ----------
    duy = mo(b, 'duy@gara.vn')
    ve_trang(duy, f'#/ho-so/{hs["id"]}')
    expect(the(duy, '1.')).to_have_count(1)
    expect(the(duy, '4')).to_have_count(1)                       # khách ngoài BH: báo giá lưu là duyệt → bước 4 Lệnh sửa chữa
    expect(the(duy, '2')).to_have_count(0)
    expect(the(duy, 'Tiền')).to_have_count(1)
    expect(the(duy, 'Ảnh & giấy tờ')).to_have_count(0)
    expect(duy.locator('section.the h2', has_text='Ảnh nhận xe')).to_have_count(0)
    expect(duy.locator('details.the', has_text='Nhật ký')).to_have_count(0)
    nut = duy.locator('[data-hien-tat-ca]')
    expect(nut).to_contain_text('Hiện tất cả công đoạn')
    chup(duy, '055-01-xem-gon')
    ghi('Mở hồ sơ: chỉ hiện Thông tin xe và khách, bước đang làm (4–5 Lệnh sửa chữa), Tiền; ẩn Báo giá; ẩn Ảnh nhận xe, Ảnh & giấy tờ, Nhật ký; có nút "Hiện tất cả công đoạn"')
    nut.click()
    expect(duy.locator('section.the h2', has_text='Ảnh nhận xe (6/6)')).to_have_count(1)
    expect(the(duy, 'Ảnh & giấy tờ')).to_have_count(1)
    expect(duy.locator('details.the', has_text='Nhật ký')).to_have_count(1)
    expect(duy.locator('[data-hien-tat-ca]')).to_contain_text('Chỉ hiện bước đang làm')
    ghi('Bấm "Hiện tất cả công đoạn" → hiện đủ (không tải lại); nút đổi thành "Chỉ hiện bước đang làm"')

    # ---------- Khóa ảnh: CVDV ----------
    expect(duy.locator('.o-anh-buoc.khoa')).to_have_count(6)
    expect(duy.locator('.o-anh-buoc[data-o=nx_trai] .o-anh-buoc-tt')).to_contain_text('Đã khóa')
    expect(duy.locator('label.o-anh-buoc')).to_have_count(0)
    expect(duy.locator('[data-thay-anh]')).to_have_count(0)
    expect(duy.locator('[data-nhieu-anh]')).to_have_count(0)
    opts = duy.locator('.tai-tep select[name=buoc] option').all_inner_texts()
    assert not any('Nhận xe' in o or 'Nội thất' in o for o in opts), opts
    assert 'Khác' in opts and 'Ảnh, giấy tờ xe' in opts, opts
    chup(duy, '055-02-anh-khoa-cvdv')
    ghi('CVDV: 6 ô ảnh nhận xe "Đã khóa", không bấm thay được, không có nút "Thay ảnh"; ô "Tải ảnh / tệp" không còn bước nhận xe – ' + ', '.join(opts))
    duy.locator('[data-hien-tat-ca]').click()
    expect(duy.locator('section.the h2', has_text='Ảnh nhận xe')).to_have_count(0)
    ghi('Bấm "Chỉ hiện bước đang làm" → gọn lại')
    ve_trang(duy, '#/ho-so')
    ve_trang(duy, f'#/ho-so/{hs["id"]}')
    expect(duy.locator('[data-hien-tat-ca]')).to_contain_text('Hiện tất cả công đoạn')
    ghi('Mở lại hồ sơ: lại gọn (mỗi lần mở đều gọn)')

    # ---------- Khóa ảnh: quản lý chung thay được, có lý do ----------
    long_ = mo(b, 'long@gara.vn')
    ve_trang(long_, f'#/ho-so/{hs["id"]}')
    long_.locator('[data-hien-tat-ca]').click()
    expect(long_.locator('[data-thay-anh]')).to_have_count(6)
    long_.locator('[data-thay-anh=nx_trai]').click()
    m = modal(long_)
    expect(m).to_contain_text('đã khóa')
    m.locator('.modal-chan .nut.chinh').click()
    expect(long_.locator('#toast')).to_contain_text('Ghi lý do', timeout=5000)
    m.locator('textarea[name=ly_do]').fill('Chụp nhầm xe khác')
    with long_.expect_file_chooser() as fc:
        m.locator('.modal-chan .nut.chinh').click()
    fc.value.set_files(ANH)
    expect(long_.locator('#toast')).to_contain_text('Đã lưu ảnh bên trái', timeout=8000)
    ghi('Quản lý chung: nút "Thay ảnh" → bắt ghi lý do → chọn ảnh → "Đã lưu ảnh bên trái"')
    ve_trang(long_, f'#/ho-so/{hs["id"]}')
    long_.locator('[data-hien-tat-ca]').click()
    nk = long_.locator('details.the', has_text='Nhật ký')
    nk.locator('summary').click()
    expect(nk).to_contain_text('Tải ảnh nhận xe – bên trái khi đã khóa – lý do: Chụp nhầm xe khác')
    opts = long_.locator('.tai-tep select[name=buoc] option').all_inner_texts()
    assert any('(đã khóa)' in o for o in opts), opts
    chup(long_, '055-03-ql-thay-anh')
    ghi('Nhật ký hồ sơ ghi lý do; ô "Tải ảnh / tệp" của quản lý có các bước "(đã khóa)"')
    long_.select_option('.tai-tep select[name=buoc]', label='Nhận xe – phía trước (đã khóa)')
    long_.set_input_files('.tai-tep input[type=file]', ANH)
    m = modal(long_)
    m.locator('textarea[name=ly_do]').fill('Bổ sung ảnh rõ hơn')
    m.locator('.modal-chan .nut.chinh').click()
    expect(long_.locator('#toast')).to_contain_text('Đã tải 1 tệp', timeout=8000)
    ghi('Quản lý chọn bước đã khóa ở "Tải ảnh / tệp" → hỏi lý do → tải được')

    # ---------- Đang sửa: xem gọn hiện thẻ sửa chữa ----------
    gd.evaluate(LENH, hs['id'])
    ve_trang(duy, f'#/ho-so/{hs["id"]}')
    expect(the(duy, '4')).to_have_count(1)
    expect(the(duy, '2')).to_have_count(0)
    chup(duy, '055-04-gon-dang-sua')
    ghi('Lập lệnh xong (đang sửa): xem gọn hiện thẻ 4–5 Lệnh sửa chữa, ẩn thẻ báo giá')
    dt = mo(b, 'duy@gara.vn', rong=390)
    ve_trang(dt, f'#/ho-so/{hs["id"]}')
    expect(dt.locator('[data-hien-tat-ca]')).to_be_visible()
    rong = dt.evaluate("(() => { const n = document.querySelector('[data-hien-tat-ca]'); return [n.scrollWidth, n.clientWidth, document.documentElement.scrollWidth]; })()")
    assert rong[0] <= rong[1] + 1 and rong[2] <= 390, rong
    chup(dt, '055-05-dien-thoai')
    ghi('Điện thoại 390px: nút "Hiện tất cả công đoạn" hiện dưới thanh tiến độ')
    b.close()

print('\nLỖI TRÌNH DUYỆT:' if loi else '\nKhông có lỗi JavaScript.')
for x in loi:
    print('  ', x)
sys.exit(1 if loi else 0)
