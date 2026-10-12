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
    page.route(re.compile(r'.*/test-anh\.svg(\?.*)?$'), lambda r: r.fulfill(status=200, content_type='image/svg+xml', body=SVG))
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


def ve_ds(page, id_hs, mo_lai=True):
    """Lưu xong trong hồ sơ: phải về danh sách Hồ sơ xe, dòng vừa lưu tô vàng; rồi mở lại hồ sơ để làm tiếp."""
    page.wait_for_url(re.compile(r'#/ho-so(\?[^/]*)?$'), timeout=10000)
    page.wait_for_selector(f'tr.vua-luu[data-id="{id_hs}"]', timeout=10000)
    if mo_lai:
        ve_trang(page, f'#/ho-so/{id_hs}')
        page.wait_for_selector('h1')


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
    ghi('Lựa chọn nguồn: ' + ', '.join(duy.locator('.chon-nut span').all_inner_texts())
        + ' | còn ô "Xe chưa có biển số": ' + str(duy.locator('text=Xe chưa có biển số').count())
        + ' | còn ô Văn phòng: ' + str(duy.locator('select[name=van_phong_bh_id]').count()))
    duy.fill('textarea[name=tinh_trang_xe]', 'Móp cửa trước trái, trầy cản sau')
    duy.fill('textarea[name=tu_van]', 'Sắp đến hạn bảo dưỡng 20.000 km')
    duy.click('button[type=submit]')
    toast_co(duy, 'thân vỏ')
    ghi('Xe bảo hiểm thiếu hạn BH thân vỏ bị chặn')
    # Gõ liền 8 số: tự thành dd/mm/yyyy
    duy.locator('input[name=han_bh_than_vo]').press_sequentially('20052027')
    expect(duy.locator('input[name=han_bh_than_vo]')).to_have_value('20/05/2027')
    duy.locator('input[name=han_bao_hiem]').press_sequentially('31022027')
    duy.click('button[type=submit]')
    toast_co(duy, 'không đúng')
    ghi('Ngày 31/02 bị báo sai')
    duy.fill('input[name=han_bao_hiem]', '01/03/2027')
    chup(duy, '02-tiep-nhan')
    duy.click('button[type=submit]')
    duy.wait_for_url(re.compile(r'#/ho-so(\?[^/]*)?$'), timeout=10000)
    lien_ket = duy.locator('.toast-mo').last
    id_hs = lien_ket.get_attribute('href').rsplit('/', 1)[1]
    duy.wait_for_selector(f'tr.vua-luu[data-id="{id_hs}"]')
    chup(duy, '02b-luu-xong-ve-danh-sach')
    ghi('Lưu xong tự về danh sách Hồ sơ xe, dòng vừa lưu tô vàng; thông báo: ' + duy.locator('.toast').last.inner_text())
    lien_ket.click()
    duy.wait_for_url(re.compile(r'#/ho-so/\d+$'))
    duy.wait_for_selector('h1')
    ghi('Bấm "Mở lại hồ sơ" trên thông báo → mở hồ sơ ' + duy.locator('.tieu-de-trang .mo-ta').last.inner_text())
    expect(duy.locator('h1')).to_contain_text('50H-923.61')
    expect(duy.locator('dl.thong-tin')).to_contain_text('20/05/2027')
    ghi('Hồ sơ hiện hạn BH thân vỏ 20/05/2027 và TNDS 01/03/2027: ' + str('01/03/2027' in duy.locator('dl.thong-tin').inner_text()))

    expect(duy.locator('text=Chưa có ảnh.')).to_be_visible()
    ghi('Lưu hồ sơ không cần ảnh; chụp bổ sung ảnh nhận xe trong hồ sơ')
    duy.set_input_files('.tai-tep input[type=file]', ANH)
    toast_co(duy, 'Đã tải 1 tệp')
    ve_ds(duy, id_hs)

    # ---------- Báo giá ----------
    duy.click('text=+ Thêm dòng báo giá')
    m = modal(duy)
    expect(m.locator('.dau-bao-gia')).to_contain_text('Tasco')
    expect(m.locator('[name=nguoi_tra]')).to_have_count(0)
    expect(m.locator('[name=gia_sau_vat]')).to_have_count(0)
    dong = [('Gò sơn cửa trước trái', 'Đồng sơn', '3000000'), ('Thay tay nắm cửa', 'Phụ tùng', '2000000'),
            ('Vệ sinh khoang máy', 'Detailing', '500000')]
    for i, (ten, nhom, gia) in enumerate(dong):
        if i:
            m.locator('text=+ Thêm dòng').click()
        r = m.locator('.dong-nhap').nth(i)
        r.locator('[name=ten]').fill(ten)
        r.locator('[name=nhom]').select_option(label=nhom)
        r.locator('[name=gia_bao]').fill(gia)
    expect(m.locator('.tong-bao-gia')).to_contain_text('5.940.000')
    ghi('Báo giá xe BH: hiện hãng Tasco, không có cột ai trả; VAT 8% → tổng sau VAT ' + m.locator('.tong-bao-gia dd b').inner_text())
    chup(duy, '03-bao-gia')
    m.locator('text=Lưu báo giá').click()
    toast_co(duy, 'Đã lưu báo giá')
    ve_ds(duy, id_hs)
    expect(duy.locator('h1 .nhan')).to_contain_text('Chờ duyệt giá')
    ghi('Lập báo giá 3 dòng → Chờ duyệt giá')

    duy.click('text=Nhập kết quả duyệt')
    m = modal(duy)
    m.locator('tbody tr').nth(0).locator('input.o-tien').fill('2800000')
    m.locator('tbody tr').nth(1).locator('input.o-tien').fill('1900000')
    m.locator('text=Lưu kết quả').click()
    toast_co(duy, 'Đã lưu kết quả duyệt')
    ve_ds(duy, id_hs)
    expect(duy.locator('h1 .nhan')).to_contain_text('Đã duyệt giá')
    ghi('Duyệt giá → Đã duyệt giá; tiền BH: ' + duy.locator('.dong-tien').first.inner_text().replace('\n', ' '))

    duy.click('text=Lập lệnh sửa chữa')
    m = modal(duy)
    m.locator('input[name=hen_giao]').fill('2026-10-14T17:00')
    m.locator('text=Giao việc').click()
    toast_co(duy, 'Đã giao việc')
    ve_ds(duy, id_hs)
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
        ve_ds(duy, id_hs)
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
    ve_ds(long_, id_hs)
    expect(long_.locator('text=Chưa có ảnh sau sửa')).to_have_count(0)
    long_.click('text=Đạt KCS')
    toast_co(long_, 'Đã ký đạt KCS')
    ve_ds(long_, id_hs)
    expect(long_.locator('h1 .nhan')).to_contain_text('Đạt KCS')
    ghi('KCS đạt (sau khi có ảnh sau sửa)')

    # ---------- Kế toán: thu tiền khách, giao xe ----------
    tien_ = mo(b, 'tien@gara.vn')
    ve_trang(tien_, f'#/ho-so/{id_hs}')
    tien_.fill('input[name=khau_tru_giam_tru]', '500000')
    tien_.fill('input[name=so_hd_bao_hiem]', 'HD0001')
    tien_.click('.the button:has-text("Giao xe")')
    toast_co(tien_, 'Khách còn nợ')
    ghi('Giao xe khi khách còn nợ (khấu trừ 500.000) bị chặn đúng')
    ve_trang(long_, f'#/ho-so/{id_hs}')
    long_.click('text=Duyệt giao khi khách còn nợ')
    toast_co(long_, 'Đã duyệt giao xe khi còn nợ')
    ve_ds(long_, id_hs, mo_lai=False)
    ve_trang(tien_, f'#/ho-so/{id_hs}')
    tien_.fill('input[name=khau_tru_giam_tru]', '500000')
    tien_.fill('input[name=so_hd_bao_hiem]', 'HD0001')
    tien_.locator('.the button:has-text("Giao xe")').click()
    toast_co(tien_, 'Đã giao xe')
    ve_ds(tien_, id_hs)
    expect(tien_.locator('h1 .nhan')).to_contain_text('Đã giao xe')
    ghi('Quản lý duyệt giao khi còn nợ → giao xe')
    # Thu phần khấu trừ của khách từ hồ sơ
    tien_.click('text=Lập phiếu thu cho xe này')
    tien_.wait_for_selector('.modal')
    m = modal(tien_)
    chup(tien_, '06-phieu-thu-khach')
    m.locator('text=Lập phiếu thu').click()
    toast_co(tien_, 'Đã lập phiếu thu')
    ve_ds(tien_, id_hs)
    tien_.click('text=Đã gửi hồ sơ bảo hiểm')
    toast_co(tien_, 'Đã ghi ngày gửi')
    ve_ds(tien_, id_hs)
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
    ve_ds(tien_, id_hs)
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
    import datetime
    hom_nay = datetime.date.today().strftime('%d/%m/%Y')
    ghi('Tình trạng lưu kèm ngày ở đầu: ' + str(f'{hom_nay}: Móp cửa' in duy.locator('dl.thong-tin').inner_text()))

    # ---------- Xe quay lại: tự điền + lịch sử + nhắc bảo hiểm hết hạn ----------
    ve_trang(duy, '#/ho-so/moi')
    duy.fill('input[name=bien_so]', '50h92361')
    duy.locator('input[name=bien_so]').blur()
    expect(duy.locator('input[name=ten_khach]')).to_have_value('Phạm Nguyễn Liêm')
    expect(duy.locator('details.lich-su')).to_contain_text('Móp cửa trước trái')
    ghi('Nhập lại biển số: tự điền khách "' + duy.locator('input[name=ten_khach]').input_value() + '", hạn thân vỏ '
        + duy.locator('input[name=han_bh_than_vo]').input_value() + ', GDV ' + duy.locator('select[name=gdv_id] option:checked').inner_text()
        + ', lịch sử ' + duy.locator('details.lich-su summary').inner_text())
    ghi('Chưa hết hạn thì không nhắc: ' + str('hết hạn' not in duy.locator('textarea[name=tu_van]').input_value()))
    duy.fill('input[name=han_bh_than_vo]', '01/01/2026')
    duy.locator('input[name=han_bh_than_vo]').blur()
    expect(duy.locator('textarea[name=tu_van]')).to_have_value(re.compile(r'^' + re.escape(hom_nay) + r': Bảo hiểm thân vỏ đã hết hạn ngày 01/01/2026'))
    duy.fill('input[name=han_bh_than_vo]', '01/01/2027')
    duy.locator('input[name=han_bh_than_vo]').blur()
    ghi('Gia hạn xong thì lời nhắc tự bỏ: ' + str(duy.locator('textarea[name=tu_van]').input_value() == ''))
    # Xe bảo hiểm: dấu tích "Không có" riêng cho từng loại; khách ngoài bảo hiểm không có dấu tích
    tv, tn = duy.locator('input[name=khong_than_vo]'), duy.locator('input[name=khong_tnds]')
    tn.check()
    expect(duy.locator('input[name=han_bao_hiem]')).to_be_disabled()
    expect(duy.locator('input[name=han_bh_than_vo]')).to_be_enabled()
    expect(duy.locator('textarea[name=tu_van]')).to_have_value(re.compile(r'Khách không có BH TNDS – tư vấn mua bảo hiểm TNDS'))
    ghi('Tích "Không có BH TNDS": chỉ khóa ô TNDS, ô thân vỏ vẫn mở, tự nhắc tư vấn mua TNDS: '
        + str('thân vỏ –' not in duy.locator('textarea[name=tu_van]').input_value()))
    duy.locator('.chon-nut span', has_text='Khách ngoài bảo hiểm').click()
    ghi('Khách ngoài bảo hiểm: ẩn dấu tích, mở lại ô ngày, bỏ nhắc: '
        + str(not tv.is_visible() and not tn.is_visible() and duy.locator('input[name=han_bao_hiem]').is_enabled()
              and 'Khách không có BH' not in duy.locator('textarea[name=tu_van]').input_value()))
    duy.locator('.chon-nut span', has_text='Xe bảo hiểm').first.click()
    duy.locator('textarea[name=tinh_trang_xe]').click()
    ghi('Bấm vào ô tình trạng tự có ngày: ' + duy.locator('textarea[name=tinh_trang_xe]').input_value())
    duy.locator('textarea[name=tinh_trang_xe]').press_sequentially('Trầy cản sau')
    tv.check(); tn.check()
    chup(duy, '17-xe-quay-lai')
    duy.click('button[type=submit]')
    duy.wait_for_url(re.compile(r'#/ho-so(\?[^/]*)?$'), timeout=10000)
    duy.wait_for_selector('tr.vua-luu')
    ghi('Xe bảo hiểm tích không có cả 2 loại, không ảnh → lưu được: ' + duy.locator('.toast').last.inner_text())

    # ---------- Khách ngoài bảo hiểm: báo giá trước/sau VAT, không qua duyệt giá ----------
    ve_trang(duy, '#/ho-so/moi')
    duy.fill('input[name=bien_so]', '51G22233')
    duy.locator('input[name=bien_so]').dispatch_event('change')
    cho_xong(duy)
    duy.select_option('select[name=hang_xe_id]', label='VinFast')
    duy.select_option('select[name=dong_xe_id]', label='VF6 Plus')
    duy.fill('input[name=ten_khach]', 'Khách lẻ Tô Ký')
    duy.fill('input[name=dien_thoai]', '0909000333')
    duy.locator('.chon-nut span', has_text='Khách ngoài bảo hiểm').click()
    duy.fill('textarea[name=tinh_trang_xe]', 'Trầy cản sau')
    duy.fill('textarea[name=tu_van]', 'Không')
    duy.click('button[type=submit]')
    duy.wait_for_url(re.compile(r'#/ho-so(\?[^/]*)?$'), timeout=10000)
    id_k = duy.locator('.toast-mo').last.get_attribute('href').rsplit('/', 1)[1]
    ve_ds(duy, id_k)
    duy.click('text=+ Thêm dòng báo giá')
    m = modal(duy)
    expect(m.locator('.dau-bao-gia')).to_contain_text('không qua duyệt giá')
    r = m.locator('.dong-nhap').first
    r.locator('[name=ten]').fill('Sơn cản sau')
    r.locator('[name=gia_sau_vat]').press_sequentially('1080000')
    expect(r.locator('[name=gia_bao]')).to_have_value('1.000.000')
    m.locator('select[name=vat]').select_option(label='10%')
    expect(r.locator('[name=gia_sau_vat]')).to_have_value('1.100.000')
    ghi('Khách ngoài BH: nhập sau VAT 1.080.000 → trước VAT tự ra 1.000.000; đổi VAT 10% → sau VAT ' + r.locator('[name=gia_sau_vat]').input_value())
    chup(duy, '03b-bao-gia-khach')
    m.locator('text=Lưu báo giá').click()
    toast_co(duy, 'đã duyệt')
    ve_ds(duy, id_k)
    expect(duy.locator('h1 .nhan')).to_contain_text('Đã duyệt giá')
    ghi('Khách ngoài BH: lưu báo giá → ' + duy.locator('h1 .nhan').inner_text() + ' ngay, không qua duyệt; nút lập lệnh: '
        + str(duy.locator('text=Lập lệnh sửa chữa').count()))

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
