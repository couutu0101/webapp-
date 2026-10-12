"""Kiểm thử giao diện từ đầu đến cuối: một chiếc xe bảo hiểm đi hết 10 bước, đổi người dùng theo vai trò.
Chạy: test/lam_moi_csdl.sh && python3 test/may_chu_thu.py 8765 & python3 test/thu_giao_dien.py"""
import os, sys, base64, re
from playwright.sync_api import sync_playwright, expect

GOC = os.path.dirname(os.path.abspath(__file__))
URL = 'http://127.0.0.1:8765/index.html'
ANH = os.path.join('/tmp', 'anh-thu.png')
CHUP = os.path.join('/tmp', 'chup')
os.makedirs(CHUP, exist_ok=True)
with open(ANH, 'wb') as f:
    f.write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))
GIA = open(os.path.join(GOC, 'supabase-gia.js'), encoding='utf-8').read()
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="#9ab"/></svg>'

loi = []
buoc = 0


def ghi(msg):
    global buoc
    buoc += 1
    print(f'[{buoc:02d}] {msg}', flush=True)


def chup(page, ten):
    page.wait_for_load_state('networkidle')
    try:
        page.wait_for_function("!document.querySelector('#noi-dung .dang-tai')", timeout=8000)
    except Exception:
        pass
    page.wait_for_timeout(250)
    page.screenshot(path=os.path.join(CHUP, f'{ten}.png'), full_page=True)


def mo(browser, email, rong=1280):
    ctx = browser.new_context(viewport={'width': rong, 'height': 900}, locale='vi-VN')
    page = ctx.new_page()
    page.route(re.compile(r'.*supabase-js@2\.45\.4/\+esm$'), lambda r: r.fulfill(status=200, content_type='application/javascript', body=GIA))
    page.route(re.compile(r'.*/test-anh\.svg$'), lambda r: r.fulfill(status=200, content_type='image/svg+xml', body=SVG))
    page.on('pageerror', lambda e: loi.append(f'{email}: {e}'))
    page.on('console', lambda m: loi.append(f'{email} console: {m.text}') if m.type == 'error' else None)
    page.goto(URL)
    if email == 'duy@gara.vn' and rong == 1280 and not os.path.exists(os.path.join(CHUP, '00-dang-nhap.png')):
        page.wait_for_selector('input[name=email]')
        chup(page, '00-dang-nhap')
    page.fill('input[name=email]', email)
    page.fill('input[name=mat_khau]', 'matkhau123')
    page.click('button[type=submit]')
    page.wait_for_selector('.menu')
    return page


def cho_xong(page):
    """Chờ mọi nút đang chạy thao tác mở khóa lại (trang đã vẽ lại xong)."""
    page.wait_for_function("!document.querySelector('button[data-dang-chay]')", timeout=15000)
    page.wait_for_load_state('networkidle')


def toast_co(page, chu):
    expect(page.locator('#toast')).to_contain_text(chu, timeout=8000)


def ve_trang(page, hash_):
    if page.url == URL + hash_:
        page.reload()
    else:
        page.goto(URL + hash_)
    page.wait_for_load_state('networkidle')
    page.wait_for_timeout(300)


def modal(page):
    return page.locator('.modal').last


with sync_playwright() as p:
    b = p.chromium.launch()

    # ---------- CVDV tiếp nhận ----------
    duy = mo(b, 'duy@gara.vn')
    ghi('Duy đăng nhập, thấy menu: ' + ', '.join(duy.locator('.menu-ds a').all_inner_texts()))
    chup(duy, '01-viec-hom-nay-cvdv')
    ve_trang(duy, '#/ho-so/moi')
    duy.fill('input[name=bien_so]', '50h 923 61')
    duy.locator('input[name=bien_so]').dispatch_event('change')
    cho_xong(duy)
    duy.select_option('select[name=hang_xe_id]', label='VinFast')
    duy.select_option('select[name=dong_xe_id]', label='VF6 Plus')
    duy.fill('input[name=mau]', 'Trắng')
    duy.fill('input[name=ten_khach]', 'Phạm Nguyễn Liêm')
    duy.fill('input[name=dien_thoai]', '0567248565')
    duy.select_option('select[name=hang_bh_id]', label='Tasco')
    duy.select_option('select[name=gdv_id]', label='Hảo (Tasco)')
    duy.fill('input[name=han_bao_hiem]', '2027-03-01')
    duy.fill('textarea[name=tinh_trang_xe]', 'Móp cửa trước trái, trầy cản sau')
    duy.fill('textarea[name=tu_van]', 'Sắp đến hạn bảo dưỡng 20.000 km')
    chup(duy, '02-tiep-nhan')
    duy.click('button[type=submit]')
    toast_co(duy, 'Chụp ít nhất 1 ảnh')
    duy.set_input_files('input[name=anh]', ANH)
    duy.click('button[type=submit]')
    duy.wait_for_url(re.compile(r'#/ho-so/\d+$'), timeout=10000)
    duy.wait_for_selector('h1')
    id_hs = duy.url.rsplit('/', 1)[1]
    ghi('Tiếp nhận xong, hồ sơ ' + duy.locator('.tieu-de-trang .mo-ta').last.inner_text())
    expect(duy.locator('h1')).to_contain_text('50H-923.61')

    # ---------- Báo giá ----------
    duy.click('text=+ Thêm dòng báo giá')
    m = modal(duy)
    dong = [('Gò sơn cửa trước trái', 'Đồng sơn', 'bao_hiem', '3000000'), ('Thay tay nắm cửa', 'Phụ tùng', 'bao_hiem', '2000000'),
            ('Phủ ceramic', 'Detailing', 'khach', '500000')]
    for i, (ten, nhom, tra, gia) in enumerate(dong):
        if i:
            m.locator('text=+ Thêm dòng').click()
        r = m.locator('.dong-nhap').nth(i)
        r.locator('[name=ten]').fill(ten)
        r.locator('[name=nhom]').select_option(label=nhom)
        r.locator('[name=nguoi_tra]').select_option(tra)
        r.locator('[name=gia_bao]').fill(gia)
    chup(duy, '03-bao-gia')
    m.locator('text=Lưu báo giá').click()
    toast_co(duy, 'Đã lưu báo giá')
    cho_xong(duy)
    expect(duy.locator('h1 .nhan')).to_contain_text('Chờ duyệt giá')
    ghi('Lập báo giá 3 dòng → Chờ duyệt giá')

    duy.click('text=Nhập kết quả duyệt')
    m = modal(duy)
    m.locator('tbody tr').nth(0).locator('input.o-tien').fill('2800000')
    m.locator('tbody tr').nth(1).locator('input.o-tien').fill('1900000')
    m.locator('text=Lưu kết quả').click()
    toast_co(duy, 'Đã lưu kết quả duyệt')
    cho_xong(duy)
    expect(duy.locator('h1 .nhan')).to_contain_text('Đã duyệt giá')
    ghi('Duyệt giá → Đã duyệt giá; tiền BH: ' + duy.locator('.dong-tien').first.inner_text().replace('\n', ' '))

    duy.click('text=Lập lệnh sửa chữa')
    m = modal(duy)
    m.locator('input[name=hen_giao]').fill('2026-10-14T17:00')
    m.locator('text=Giao việc').click()
    toast_co(duy, 'Đã giao việc')
    cho_xong(duy)
    expect(duy.locator('h1 .nhan')).to_contain_text('Đang sửa')
    chup(duy, '04-chi-tiet-dang-sua')
    ghi('Lập lệnh sửa chữa → Đang sửa')

    # ---------- Trưởng nhóm ----------
    han = mo(b, 'han@gara.vn', rong=390)
    ghi('Hận (trưởng nhóm ĐS) menu: ' + ', '.join(han.locator('.menu-ds a').all_inner_texts()))
    han.wait_for_selector('.the-xe')
    chup(han, '05-bang-viec-to-dien-thoai')
    so_viec = han.locator('.the-xe button:has-text("Báo xong")').count()
    ghi(f'Hận thấy {so_viec} việc của tổ ĐS')
    for _ in range(so_viec):
        han.locator('.the-xe button:has-text("Báo xong")').first.click()
        cho_xong(han)
    ve_trang(han, '#/ho-so')
    ghi('Hận mở trang Hồ sơ xe (không có quyền): ' + han.locator('#noi-dung').inner_text()[:80].replace('\n', ' '))

    # Dòng Detailing: CVDV báo xong
    ve_trang(duy, f'#/ho-so/{id_hs}')
    for _ in range(6):
        if not duy.locator('button:has-text("Báo xong")').count(): break
        duy.locator('button:has-text("Báo xong")').first.click()
        cho_xong(duy)
        o_loi = duy.locator('.toast.loi')
        if o_loi.count(): raise AssertionError('Báo xong lỗi: ' + o_loi.first.inner_text())
    expect(duy.locator('h1 .nhan')).to_contain_text('Chờ KCS')
    ghi('Xong các hạng mục → Chờ KCS')

    # ---------- Quản lý chung: KCS ----------
    long_ = mo(b, 'long@gara.vn')
    ve_trang(long_, f'#/ho-so/{id_hs}')
    long_.click('text=Đạt KCS')
    toast_co(long_, 'Tải ảnh sau sửa')
    long_.select_option('.tai-tep select', 'kcs')
    long_.set_input_files('.tai-tep input[type=file]', ANH)
    toast_co(long_, 'Đã tải 1 tệp')
    expect(long_.locator('text=Chưa có ảnh sau sửa')).to_have_count(0)
    cho_xong(long_)
    long_.click('text=Đạt KCS')
    toast_co(long_, 'Đã ký đạt KCS')
    cho_xong(long_)
    expect(long_.locator('h1 .nhan')).to_contain_text('Đạt KCS')
    ghi('KCS đạt (sau khi có ảnh sau sửa)')

    # ---------- Kế toán: thu tiền khách, giao xe ----------
    tien_ = mo(b, 'tien@gara.vn')
    ve_trang(tien_, f'#/ho-so/{id_hs}')
    tien_.fill('input[name=khau_tru_giam_tru]', '500000')
    tien_.fill('input[name=so_hd_bao_hiem]', 'HD0001')
    tien_.click('.the button:has-text("Giao xe")')
    toast_co(tien_, 'Khách còn nợ')
    ghi('Giao xe khi khách còn nợ bị chặn đúng')
    # Thu tiền phần khách (ceramic 500.000) trước — chưa có khấu trừ nên khách nợ 500.000
    tien_.click('text=Thu tiền khách')
    tien_.wait_for_selector('.modal')
    m = modal(tien_)
    chup(tien_, '06-phieu-thu-khach')
    m.locator('text=Lập phiếu thu').click()
    toast_co(tien_, 'Đã lập phiếu thu')
    tien_.wait_for_url(re.compile(r'#/ho-so/\d+$'))
    cho_xong(tien_)
    tien_.fill('input[name=so_hd_bao_hiem]', 'HD0001')
    tien_.locator('.the button:has-text("Giao xe")').click()
    toast_co(tien_, 'Đã giao xe')
    cho_xong(tien_)
    expect(tien_.locator('h1 .nhan')).to_contain_text('Đã giao xe')
    ghi('Thu đủ phần khách → giao xe')
    tien_.click('text=Đã gửi hồ sơ bảo hiểm')
    toast_co(tien_, 'Đã ghi ngày gửi')
    cho_xong(tien_)
    tien_.click('text=Nhập hoa hồng')
    m = modal(tien_)
    m.locator('[name=so_tien]').fill('4500000')
    m.locator('text=Lưu').click()
    tien_.wait_for_selector('text=Vẫn tiếp tục')
    ghi('Hoa hồng quá lớn → hỏi lại')
    tien_.locator('.modal').last.get_by_role('button', name='Không', exact=True).click()
    tien_.wait_for_timeout(300)
    m = modal(tien_)
    m.locator('[name=so_tien]').fill('450000')
    m.locator('[name=ghi_chu]').fill('5% + 200.000')
    m.locator('text=Lưu').click()
    toast_co(tien_, 'Đã lưu hoa hồng')
    chup(tien_, '07-chi-tiet-cho-bh-tra')

    # Bảo hiểm chuyển gộp, chia theo bảng kê
    ve_trang(tien_, '#/thu-chi')
    tien_.click('text=+ Phiếu thu')
    m = modal(tien_)
    m.locator('[name=muc_id]').select_option(label='Bảo hiểm thanh toán')
    m.locator('[name=tai_khoan_id]').select_option(label='TK công ty (331 331 331 68)')
    m.locator('[name=so_tien]').fill('6000000')
    m.locator('[name=hang_bh_id]').select_option(label='Tasco')
    tien_.wait_for_timeout(300)
    m.locator('.dong-phan-bo button:has-text("Đủ")').first.click()
    chup(tien_, '08-phieu-thu-bao-hiem')
    m.locator('text=Lập phiếu thu').click()
    toast_co(tien_, 'Đã lập phiếu thu')
    cho_xong(tien_)
    chup(tien_, '09-so-thu-chi')
    ghi('Phiếu thu BH 6.000.000, chia đủ cho xe, phần dư chờ chia: ' + str(tien_.locator('button:has-text("vào xe")').count()))

    ve_trang(duy, f'#/ho-so/{id_hs}')
    ghi('Trạng thái cuối của hồ sơ: ' + duy.locator('h1 .nhan').inner_text())

    # ---------- Đề nghị chi ----------
    ve_trang(duy, '#/de-nghi')
    duy.click('text=+ Lập đề nghị chi')
    m = modal(duy)
    m.locator('[name=muc_id]').select_option(label='Điện')
    m.locator('[name=so_tien]').fill('2500000')
    m.locator('[name=noi_dung]').fill('Tiền điện tháng 10')
    m.locator('text=Gửi đề nghị').click()
    toast_co(duy, 'Đã gửi đề nghị')
    ghi('Duy lập đề nghị chi 2.500.000')
    ve_trang(long_, '#/de-nghi')
    ghi('Anh Long thấy nút Duyệt cho khoản 2,5 triệu: ' + str(long_.get_by_role('button', name='Duyệt', exact=True).count()))
    thuan = mo(b, 'thuan@gara.vn')
    chup(thuan, '10-viec-hom-nay-giam-doc')
    ve_trang(thuan, '#/de-nghi')
    thuan.get_by_role('button', name='Duyệt', exact=True).first.click()
    toast_co(thuan, 'Đã duyệt')
    ve_trang(tien_, '#/de-nghi')
    tien_.locator('button:has-text("Chi tiền")').first.click()
    modal(tien_).locator('text=Lập phiếu chi').click()
    toast_co(tien_, 'Đã chi')
    ghi('Giám đốc duyệt → kế toán chi')

    # ---------- Dịch vụ nhanh, doanh thu, danh mục, nhân viên ----------
    ve_trang(han, '#/dich-vu')
    han.fill('input[name=dich_vu]', 'Rửa xe')
    han.fill('input[name=so_tien]', '80000')
    han.click('text=Ghi dịch vụ')
    toast_co(han, 'Đã ghi')
    ghi('Trưởng nhóm ghi dịch vụ nhanh')
    ve_trang(thuan, '#/doanh-thu')
    chup(thuan, '11-doanh-thu')
    ghi('Doanh thu tháng: ' + thuan.locator('.o-dem b').first.inner_text())
    ve_trang(thuan, '#/danh-muc')
    thuan.select_option('.tieu-de-trang select', 'giam_dinh_vien')
    thuan.wait_for_timeout(400)
    thuan.click('text=+ Thêm')
    m = modal(thuan)
    m.locator('[name=ten]').fill('Tín')
    m.locator('[name=hang_id]').select_option(label='DBV')
    m.locator('text=Lưu').click()
    toast_co(thuan, 'Đã lưu')
    ghi('Giám đốc thêm GDV trong danh mục')
    ve_trang(thuan, '#/nhan-vien')
    chup(thuan, '12-nhan-vien')
    thuan.locator('tr:has-text("moi@gara.vn") button').click()
    m = modal(thuan)
    m.locator('[name=vt_cvdv]').check()
    m.locator('text=Lưu').click()
    toast_co(thuan, 'Đã lưu')
    ghi('Giám đốc cấp quyền CVDV cho nhân viên mới')

    codong = mo(b, 'codong@gara.vn')
    ghi('Cổ đông menu: ' + (', '.join(codong.locator('.menu-ds a').all_inner_texts()) or '(trống)') + ' | ' + codong.locator('#noi-dung').inner_text()[:60].replace('\n', ' '))

    # Điện thoại: chi tiết hồ sơ
    dt = mo(b, 'duy@gara.vn', rong=390)
    ve_trang(dt, f'#/ho-so/{id_hs}')
    chup(dt, '13-chi-tiet-dien-thoai')
    ve_trang(dt, '#/ho-so')
    chup(dt, '14-danh-sach-dien-thoai')
    ve_trang(dt, '#/ho-so/moi')
    chup(dt, '15-tiep-nhan-dien-thoai')
    dt.click('.nut-menu')
    dt.wait_for_timeout(400)
    dt.screenshot(path=os.path.join(CHUP, '16-menu-dien-thoai.png'))
    b.close()

print('\nLỖI TRÌNH DUYỆT:' if loi else '\nKhông có lỗi JavaScript.')
for x in loi:
    print('  ', x)
sys.exit(1 if loi else 0)
