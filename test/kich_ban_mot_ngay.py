"""Kịch bản "một ngày ở gara": đóng vai từng nhân viên, làm như người dùng thật (điện thoại cho người ở xưởng),
ghi thời gian từng thao tác, chụp màn hình, dò lỗi hiển thị (tràn ngang trên điện thoại) và lỗi JavaScript.
Chạy: test/lam_moi_csdl.sh && (máy chủ thử đang chạy) && python3 test/kich_ban_mot_ngay.py
Ảnh chụp: /tmp/kich-ban/, kết quả: /tmp/kich-ban/ket-qua.json"""
import os, re, sys, json, time, random
from playwright.sync_api import sync_playwright, expect, TimeoutError as PwTimeout
from PIL import Image

GOC = os.path.dirname(os.path.abspath(__file__))
URL = 'http://127.0.0.1:8765/index.html'
RA = '/tmp/kich-ban'
os.makedirs(RA, exist_ok=True)
GIA = open(os.path.join(GOC, 'supabase-gia.js'), encoding='utf-8').read()
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="#9ab"/></svg>'

# Ảnh giống ảnh điện thoại thật: 4000x3000, ~3–5 MB
ANH = []
for i in range(8):
    p = f'/tmp/anh-dt-{i}.jpg'
    if not os.path.exists(p):
        nhieu = Image.effect_noise((4000, 3000), 40 + i * 5)
        Image.merge('RGB', (nhieu, nhieu.rotate(180), nhieu.transpose(Image.FLIP_LEFT_RIGHT))).save(p, quality=92)
    ANH.append(p)
PDF = '/tmp/bao-gia-thu.pdf'
if not os.path.exists(PDF):
    Image.new('RGB', (1240, 1754), 'white').save(PDF)

loi_js, nhat_ky, van_de = [], [], []
dem = 0


def ghi(ai, viec, giay=None, anh=None):
    global dem
    dem += 1
    d = {'stt': dem, 'ai': ai, 'viec': viec}
    if giay is not None: d['giay'] = round(giay, 1)
    if anh: d['anh'] = anh
    nhat_ky.append(d)
    print(f"[{dem:02d}] {ai}: {viec}" + (f'  ({giay:.1f}s)' if giay is not None else ''), flush=True)


def bao(ai, chu):
    van_de.append({'ai': ai, 'chu': chu})
    print(f'   !! {ai}: {chu}', flush=True)


def chup(page, ten, ai):
    yen(page)
    page.wait_for_timeout(300)
    page.screenshot(path=os.path.join(RA, f'{ten}.png'), full_page=True)
    # Điện thoại: trang không được tràn ngang
    rong = page.evaluate('() => [document.documentElement.scrollWidth, window.innerWidth]')
    if rong[0] > rong[1] + 2:
        thu_pham = page.evaluate("""() => [...document.querySelectorAll('body *')].filter((e) => e.getBoundingClientRect().right > window.innerWidth + 2)
          .slice(0, 4).map((e) => e.tagName.toLowerCase() + (e.className ? '.' + String(e.className).split(' ')[0] : '') + ' ' + (e.innerText || '').slice(0, 30).replace(/\\n/g, ' '))""")
        bao(ai, f'Màn hình "{ten}" tràn ngang {rong[0]}px > {rong[1]}px: {thu_pham}')
    return f'{ten}.png'


def chup_man(page, ten):
    page.screenshot(path=os.path.join(RA, f'{ten}.png'))
    return f'{ten}.png'


def de_nhau(page, ai, cho):
    """Thông báo không được che nút ở chân hộp thoại."""
    t, c = page.locator('#toast').bounding_box(), page.locator('.modal').last.locator('.modal-chan').bounding_box()
    if t and c and t['height'] > 0 and t['y'] < c['y'] + c['height'] and t['y'] + t['height'] > c['y']:
        bao(ai, f'Thông báo che nút ở chân hộp thoại ({cho})')


def mo(b, email, ai, dien_thoai=True):
    ctx = b.new_context(viewport={'width': 390, 'height': 844} if dien_thoai else {'width': 1366, 'height': 860},
                        is_mobile=dien_thoai, has_touch=dien_thoai, locale='vi-VN')
    if os.environ.get('TB') == '1':
        # Chạy kịch bản với khung thông báo BẬT: người dùng thật gặp khung thì bấm "Đã nhận" rồi làm tiếp → Playwright tự bấm khi khung chặn thao tác
        ctx.add_init_script('window.__HOI_TB_MS = 1500;')
    else:
        ctx.add_init_script('window.__TAT_THONG_BAO = true;')     # 054: mặc định tắt khung để kịch bản cũ không đổi; TB=1 để chạy kèm khung
    page = ctx.new_page()
    if os.environ.get('TB') == '1':
        def _nhan_het():
            """Người dùng thật gặp khung thì bấm "Đã nhận" rồi làm tiếp. Thông báo khác có thể đến liền sau (khung hiện lại ngay) → bấm tiếp tới khi hết khung."""
            for lan in range(15):
                bam = None
                for sel in ('[data-tb=nhan-tat-ca]', '[data-tb=nhan]', '[data-tb=biet]'):
                    if page.locator(sel).count():
                        bam = sel
                        break
                if bam:
                    try:
                        chu = page.locator('.tb-nen').inner_text(timeout=2000).replace('\n', ' | ')[:170]
                        print(f'   (TB {ai}: khung hiện{" LẠI" if lan else ""} → bấm {bam}: {chu})', flush=True)
                        page.locator(bam).first.click(timeout=5000)
                    except PwTimeout:
                        pass                                   # nút vừa được vẽ lại / đang chờ máy chủ: vòng sau thử tiếp
                page.wait_for_timeout(400)
                if not page.locator('.tb-nen').count():
                    return
        page.add_locator_handler(page.locator('.tb-nen'), _nhan_het)
    page.route(re.compile(r'.*supabase-js@2\.45\.4/\+esm$'), lambda r: r.fulfill(status=200, content_type='application/javascript', body=GIA))
    page.route(re.compile(r'.*/test-anh\.svg(\?.*)?$'), lambda r: r.fulfill(status=200, content_type='image/svg+xml', body=SVG))
    page.on('pageerror', lambda e: loi_js.append(f'{ai}: {e}'))
    page.on('console', lambda m: loi_js.append(f'{ai} console: {m.text}') if m.type == 'error' else None)
    page.goto(URL)
    page.fill('input[name=email]', email)
    page.fill('input[name=mat_khau]', 'matkhau123')
    page.click('button[type=submit]')
    page.wait_for_selector('.menu')
    yen(page)
    return page


def yen(page, cho=8000):
    """Đợi mạng yên. Playwright đôi khi đếm sót một yêu cầu đã xong nên "networkidle" không bao giờ tới (đã dò 17/10: trang vẫn vẽ xong,
    trả lời bình thường, máy chủ thử trả lời trong 0,2 giây; gặp cả ở bản cũ chưa sửa gì, ~1/6 lần, luôn ở bước 23) → quá hạn thì đi tiếp."""
    try:
        page.wait_for_load_state('networkidle', timeout=cho)
    except PwTimeout:
        print(f'   (ghi chú: mạng chưa "yên" sau {cho // 1000} giây nhưng trang đã vẽ xong – đi tiếp)', flush=True)


def ve(page, hash_):
    page.goto(URL + hash_) if page.url != URL + hash_ else page.reload()
    yen(page)
    page.wait_for_timeout(300)
    # bỏ thông báo cũ để lần kiểm "đã lưu" sau đó chỉ nhìn thông báo mới
    page.evaluate("document.querySelectorAll('#toast .toast').forEach((x) => x.remove())")


def modal(page):
    return page.locator('.modal').last


def toast(page, chu, cho=20000):
    expect(page.locator('#toast .toast').last).to_contain_text(chu, timeout=cho)


def ve_ho_so(page, id_hs):
    ve(page, f'#/ho-so/{id_hs}')
    page.wait_for_selector('.the-tien-do')


def mo_menu(page):
    """Điện thoại: menu nằm trong nút ☰ – mở rồi đóng để chụp."""
    nut = page.locator('.dau button[aria-label*="enu"], .nut-menu').first
    return nut



def lenh_giao_viec(m, anh):
    """056: hộp lệnh sửa chữa theo tổ – tổ chưa có người thì chọn Hận (trưởng nhóm Đồng sơn), kèm ảnh lệnh."""
    for sel in m.locator('select[data-nguoi-to]').all():
        if not sel.input_value():
            sel.select_option(sel.locator('option', has_text='Hận').first.get_attribute('value'))
    m.locator('.khoi-dinh-kem input[type=file]').set_input_files(anh)
    m.locator('text=Giao việc').click()


with sync_playwright() as p:
    b = p.chromium.launch()
    T = time.time

    # ===================== 7:30 – CVDV Duy (điện thoại) tiếp nhận xe bảo hiểm =====================
    duy = mo(b, 'duy@gara.vn', 'Duy (CVDV)')
    a = chup(duy, '01-duy-viec-hom-nay', 'Duy (CVDV)')
    ghi('Duy (CVDV)', 'Đăng nhập trên điện thoại, mở Việc hôm nay', anh=a)
    ve(duy, '#/ho-so/moi')
    t0 = T()
    duy.fill('input[name=bien_so]', '51G 123 45')
    duy.locator('input[name=bien_so]').dispatch_event('change')
    duy.select_option('select[name=hang_xe_id]', label='VinFast')
    duy.select_option('select[name=dong_xe_id]', label='VF8')
    duy.fill('input[name=mau]', 'Xám')
    duy.locator('input[name=so_km]').press_sequentially('31250')
    duy.fill('input[name=ten_khach]', 'Nguyễn Văn Bình')
    duy.fill('input[name=dien_thoai]', '0908123456')
    duy.locator('input[name=han_bh_than_vo]').press_sequentially('15062027')
    duy.locator('input[name=han_bao_hiem]').press_sequentially('15062027')
    duy.fill('textarea[name=tinh_trang_xe]', 'Va quẹt cửa sau phải, bể đèn hậu phải')
    duy.fill('textarea[name=tu_van]', 'Sắp tới hạn bảo dưỡng 30.000 km')
    t_anh = T()
    duy.set_input_files('input[data-nhieu-anh]', ANH[:6])
    expect(duy.locator('.o-anh-buoc.du')).to_have_count(6, timeout=20000)
    ghi('Duy (CVDV)', 'Chọn 6 ảnh nhận xe một lần (ảnh điện thoại 4000x3000)', T() - t_anh)
    a = chup(duy, '02-duy-tiep-nhan', 'Duy (CVDV)')
    t_luu = T()
    duy.click('button[type=submit]')
    duy.wait_for_url(re.compile(r'#/ho-so(\?[^/]*)?$'), timeout=60000)
    id_bh = duy.locator('.toast-mo').last.get_attribute('href').rsplit('/', 1)[1]
    ghi('Duy (CVDV)', f'Lưu hồ sơ xe bảo hiểm 51G-123.45 (tải 6 ảnh lên) – cả form {T() - t0:.0f}s', T() - t_luu, a)

    # Báo giá kèm file PDF
    ve_ho_so(duy, id_bh)
    t0 = T()
    duy.click('text=+ Thêm dòng báo giá')
    m = modal(duy)
    for i, (ten, nhom, gia) in enumerate([('Gò sơn cửa sau phải', 'Đồng', '2500000'), ('Sơn cửa sau phải', 'Sơn', '1800000'),
                                           ('Thay đèn hậu phải', 'Phụ tùng', '4200000'), ('Đánh bóng toàn xe', 'Detailing', '800000')]):
        if i: m.locator('text=+ Thêm dòng').click()
        r = m.locator('.dong-nhap').nth(i)
        r.locator('[name=ten]').fill(ten); r.locator('[name=nhom]').select_option(label=nhom); r.locator('[name=gia_bao]').fill(gia)
    m.locator('input[aria-label="Ảnh / file báo giá"]').set_input_files(PDF)
    # 053: dòng "Ảnh, giấy tờ xe" – CVDV chụp luôn đăng ký, đăng kiểm của xe (2 ảnh) ngay trong hộp báo giá
    m.locator('input[aria-label="Ảnh, giấy tờ xe"]').set_input_files([ANH[0], ANH[1]])
    a = chup(duy, '03-duy-bao-gia', 'Duy (CVDV)')
    m.locator('text=Lưu báo giá').click()
    toast(duy, 'Đã lưu báo giá')
    ghi('Duy (CVDV)', 'Lập báo giá 4 dòng + file báo giá PDF', T() - t0, a)

    # Bảo hiểm duyệt: chọn hãng, GDV, ảnh biên bản duyệt
    ve_ho_so(duy, id_bh)
    t0 = T()
    duy.locator('button', has_text='Nhập kết quả duyệt').click()
    m = modal(duy)
    m.locator('select[name=hang_bh_id]').select_option(label='Tasco')
    m.locator('select[name=gdv_id]').select_option(label='Hảo (Tasco)')
    m.locator('.khoi-dinh-kem input[type=file]').set_input_files(ANH[6])
    m.locator('[name=bao_hiem]').fill('8000000'); m.locator('[name=bao_hiem]').dispatch_event('input')
    a = chup(duy, '04-duy-nhap-duyet-gia', 'Duy (CVDV)')
    m.locator('text=Lưu kết quả').click()
    toast(duy, 'khách thanh toán')
    ghi('Duy (CVDV)', 'Nhập kết quả duyệt giá (056: chỉ 2 ô): Tasco, GDV Hảo, ảnh biên bản duyệt, bảo hiểm thanh toán 8.000.000, khách 0', T() - t0, a)
    ve_ho_so(duy, id_bh)
    t0 = T()
    duy.locator('button', has_text='Lập lệnh sửa chữa').click()
    m = modal(duy)
    a = chup(duy, '05-duy-lenh-sua-chua', 'Duy (CVDV)')
    lenh_giao_viec(m, ANH[7])
    toast(duy, 'Đã giao việc')
    ghi('Duy (CVDV)', 'Lập lệnh sửa chữa (056: theo tổ, người thực hiện theo tài khoản, ảnh lệnh): đồng–sơn → Đồng sơn, phụ tùng → ĐMG (giao Hận), đánh bóng → Detailing', T() - t0, a)

    # Xe khách lẻ: thay dầu, không qua Detailing
    ve(duy, '#/ho-so/moi')
    t0 = T()
    duy.fill('input[name=bien_so]', '59A 888 99')
    duy.locator('input[name=bien_so]').dispatch_event('change')
    duy.select_option('select[name=hang_xe_id]', label='Toyota')
    duy.select_option('select[name=dong_xe_id]', label='Vios')
    duy.locator('input[name=so_km]').press_sequentially('88000')
    duy.fill('input[name=ten_khach]', 'Trần Thị Hoa')
    duy.fill('input[name=dien_thoai]', '0912345678')
    duy.locator('.chon-nut span', has_text='Khách ngoài bảo hiểm').click()
    duy.fill('textarea[name=tinh_trang_xe]', 'Gò lại cản trước bị móp nhẹ')
    duy.fill('textarea[name=tu_van]', 'Không')
    duy.set_input_files('input[data-nhieu-anh]', ANH[:6])
    expect(duy.locator('.o-anh-buoc.du')).to_have_count(6, timeout=20000)
    duy.locator('input[name=khong_qua_detailing]').check()
    duy.click('button[type=submit]')
    duy.wait_for_url(re.compile(r'#/ho-so(\?[^/]*)?$'), timeout=60000)
    id_le = duy.locator('.toast-mo').last.get_attribute('href').rsplit('/', 1)[1]
    ghi('Duy (CVDV)', 'Tiếp nhận xe khách lẻ 59A-888.99 (Vios), tích "Không qua Detailing"', T() - t0)
    ve_ho_so(duy, id_le)
    duy.click('text=+ Thêm dòng báo giá')
    m = modal(duy)
    r = m.locator('.dong-nhap').first
    r.locator('[name=ten]').fill('Gò cản trước'); r.locator('[name=nhom]').select_option(label='Đồng'); r.locator('[name=gia_bao]').fill('700000')
    m.locator('input[aria-label="Ảnh / file báo giá"]').set_input_files(ANH[7])
    m.locator('text=Lưu báo giá').click()
    toast(duy, 'Đã lưu báo giá')
    ve_ho_so(duy, id_le)
    duy.locator('button', has_text='Lập lệnh sửa chữa').click()
    lenh_giao_viec(modal(duy), ANH[7])
    toast(duy, 'Đã giao việc')
    ve_ho_so(duy, id_le)
    a = chup(duy, '06-duy-xe-le-dang-sua', 'Duy (CVDV)')
    if 'bo' not in (duy.locator('.tien-do li').nth(5).get_attribute('class') or ''):
        bao('Duy (CVDV)', 'Xe khách lẻ đã tích "Không qua Detailing" nhưng bước 6 không hiện "Không áp dụng"')
    ghi('Duy (CVDV)', 'Xe khách lẻ: báo giá (khách lẻ duyệt luôn) → lệnh sửa chữa; bước Detailing hiện "Không áp dụng"', anh=a)

    # Kho: thêm mã hàng + nhập kho (Duy kiêm kho)
    ve(duy, '#/kho?the=ton')
    duy.get_by_role('button', name='+ Mã hàng').click()
    m = modal(duy)
    m.locator('[name=ma]').fill('SON-XAM'); m.locator('[name=ten]').fill('Sơn xám VF8'); m.locator('[name=nhom]').select_option('Sơn')
    m.locator('[name=dvt]').fill('Lít'); m.locator('[name=dvt_nhap]').fill('Can 4L'); m.locator('[name=he_so]').fill('4'); m.locator('[name=ton_toi_thieu]').fill('2')
    m.get_by_role('button', name='Lưu').click()
    toast(duy, 'Đã thêm mã hàng')
    ve(duy, '#/kho?the=nhap')
    duy.get_by_role('button', name='+ Phiếu nhập').click()
    m = modal(duy)
    m.locator('select[name=nha_cung_cap_id]').select_option(label='Vật tư sơn VTN')
    m.locator('[name=so_hoa_don]').fill('VTN-2610')
    o = m.locator('.dong-kho').first.locator('input[name=hang_id_tim]')
    o.click(); o.fill('son xam'); m.locator('.goi-y-ds li', has_text='SON-XAM').first.click()
    m.locator('.dong-kho [name=so_luong]').first.fill('2'); m.locator('.dong-kho [name=don_gia]').first.fill('950000')
    a = chup(duy, '07-duy-phieu-nhap', 'Duy (kho)')
    m.get_by_role('button', name='Lưu phiếu nhập').click()
    toast(duy, 'Đã nhập kho')
    ghi('Duy (kho)', 'Thêm mã "Sơn xám VF8", nhập 2 can (8 lít) từ Vật tư sơn VTN', anh=a)

    # ===================== 9:00 – Trưởng nhóm Đồng sơn Hận (điện thoại) =====================
    han = mo(b, 'han@gara.vn', 'Hận (trưởng nhóm Đồng sơn)')
    han.wait_for_selector('.the-xe')
    a = chup(han, '08-han-bang-viec', 'Hận (trưởng nhóm Đồng sơn)')
    ghi('Hận (trưởng nhóm Đồng sơn)', f'Mở Việc hôm nay: thấy {han.locator(".the-xe").count()} xe của tổ', anh=a)
    t0 = T()
    the = han.locator('.the-xe', has_text='51G-123.45')
    the.get_by_role('button', name='Đề xuất vật tư').click()
    m = modal(han)
    m.locator('select[name=hang_id_nhom]').select_option('Sơn')
    o = m.locator('.dong-kho').first.locator('input[name=hang_id_tim]')
    o.click(); o.fill('son xam'); m.locator('.goi-y-ds li', has_text='SON-XAM').first.click()
    m.locator('.dong-kho [name=so_luong]').first.fill('2')
    a = chup(han, '09-han-de-xuat', 'Hận (trưởng nhóm Đồng sơn)')
    m.get_by_role('button', name='Gửi đề xuất').click()
    toast(han, 'Đã gửi đề xuất')
    ghi('Hận (trưởng nhóm Đồng sơn)', 'Đề xuất 2 lít sơn xám cho xe 51G', T() - t0, a)
    # Kho xuất
    ve(duy, '#/kho?the=de_xuat')
    duy.locator('tbody tr.bam-duoc').first.click()
    modal(duy).get_by_role('button', name='Xuất kho').click()
    toast(duy, 'Đã xuất')
    ghi('Duy (kho)', 'Xuất 2 lít sơn theo đề xuất của tổ Đồng sơn')
    # Báo phát sinh: gãy pát cản sau
    ve(han, '#/')
    t0 = T()
    han.locator('.the-xe', has_text='51G-123.45').get_by_role('button', name='Báo phát sinh').click()
    m = modal(han)
    m.locator('textarea[name=mo_ta]').fill('Gãy pát bắt cản sau bên phải, cần thay')
    m.locator('input[name=anh]').set_input_files(ANH[3:5])
    m.locator('.modal-chan button', has_text='Gửi').click()
    toast(han, 'Đã báo phát sinh', 40000)
    ghi('Hận (trưởng nhóm Đồng sơn)', 'Báo phát sinh "gãy pát cản sau" kèm 2 ảnh', T() - t0)
    # Báo xong các hạng mục tổ mình (xe khách lẻ + 3 hạng mục xe BH)
    ve(han, '#/')
    t0 = T()
    n = 0
    while han.locator('.the-xe button:has-text("Báo xong")').count():
        han.locator('.the-xe button:has-text("Báo xong")').first.click()
        han.wait_for_timeout(600); yen(han); n += 1
        if n > 10: break
    a = chup(han, '10-han-bao-xong', 'Hận (trưởng nhóm Đồng sơn)')
    ghi('Hận (trưởng nhóm Đồng sơn)', f'Bấm "Báo xong" {n} hạng mục của tổ', T() - t0, a)

    # ===================== CVDV xử lý phát sinh: báo giá bổ sung → BH duyệt bổ sung → giao thêm =====================
    ve_ho_so(duy, id_bh)
    a = chup(duy, '11-duy-thay-phat-sinh', 'Duy (CVDV)')
    t0 = T()
    duy.click('text=+ Báo giá bổ sung (phát sinh)')
    m = modal(duy)
    r = m.locator('.dong-nhap').first
    r.locator('[name=ten]').fill('Thay pát cản sau phải'); r.locator('[name=nhom]').select_option(label='Phụ tùng'); r.locator('[name=gia_bao]').fill('350000')
    m.locator('input[aria-label="Ảnh / file báo giá"]').set_input_files(ANH[5])
    m.locator('button', has_text='Lưu báo giá').click()
    toast(duy, 'Đã lưu')
    ve_ho_so(duy, id_bh)
    duy.locator('button', has_text='Nhập kết quả duyệt').click()
    m = modal(duy)
    m.locator('.khoi-dinh-kem input[type=file]').set_input_files(ANH[6])
    m.locator('text=Lưu kết quả').click()
    toast(duy, 'khách thanh toán')
    ve_ho_so(duy, id_bh)
    duy.locator('button', has_text='Giao thêm cho tổ').click()
    lenh_giao_viec(modal(duy), ANH[7])
    toast(duy, 'Đã giao việc')
    ghi('Duy (CVDV)', 'Phát sinh: báo giá bổ sung pát cản (kèm ảnh) → nhập duyệt bổ sung (kèm ảnh) → giao thêm tổ Đồng sơn', T() - t0, a)
    ve(han, '#/')
    han.locator('.the-xe', has_text='51G-123.45').locator('button:has-text("Báo xong")').first.click()
    toast(han, 'Đã báo xong')
    ghi('Hận (trưởng nhóm Đồng sơn)', 'Thay pát xong → báo xong')

    # ===================== Detailing Giang (điện thoại) =====================
    giang = mo(b, 'giang@gara.vn', 'Giang (trưởng nhóm Detailing)')
    giang.wait_for_selector('.the-xe')
    the = giang.locator('.the-xe', has_text='51G-123.45')
    if the.locator('button:has-text("Báo xong")').count():
        the.locator('button:has-text("Báo xong")').first.click()
        toast(giang, 'Đã báo xong')
        yen(giang)
        ghi('Giang (trưởng nhóm Detailing)', 'Báo xong hạng mục "Đánh bóng toàn xe" của tổ Detailing')
    ve(giang, '#/')
    the = giang.locator('.the-xe', has_text='51G-123.45')
    expect(the.locator('.nhan').first).to_contain_text('Chờ Detailing', timeout=15000)
    a = chup(giang, '12-giang-cho-detailing', 'Giang (trưởng nhóm Detailing)')
    t0 = T()
    the.get_by_role('button', name='Chưa đạt – trả về sửa').click()
    m = modal(giang)
    m.locator('textarea[name=loi]').fill('Sơn cửa sau phải còn hạt bụi, cần đánh lại')
    m.get_by_role('checkbox', name='Sơn cửa sau phải (Đồng sơn)', exact=True).check()
    de_nhau(giang, 'Giang (trưởng nhóm Detailing)', 'hộp trả về sửa chữa')
    a2 = chup_man(giang, '13-giang-tra-ve')
    m.locator('.modal-chan .nut.chinh').click()
    toast(giang, 'Đã trả xe về tổ sửa lại')
    ghi('Giang (trưởng nhóm Detailing)', 'Rửa xe thấy sơn còn bụi → "Chưa đạt – trả về sửa", tích "Sơn cửa sau phải"', T() - t0, a2)
    ve(han, '#/')
    han.locator('.the-xe', has_text='51G-123.45').locator('button:has-text("Báo xong")').first.click()
    toast(han, 'Đã báo xong')
    ghi('Hận (trưởng nhóm Đồng sơn)', 'Đánh lại sơn → báo xong; xe tự quay lại Detailing')
    ve(giang, '#/')
    giang.locator('.the-xe', has_text='51G-123.45').get_by_role('button', name='Detailing xong – chuyển KCS').click()
    toast(giang, 'Đã xong Detailing')
    ghi('Giang (trưởng nhóm Detailing)', 'Rửa, đánh bóng xong → "Detailing xong – chuyển KCS"')

    # ===================== Quản lý chung Long (điện thoại): KCS + ảnh hủy vật tư =====================
    long_ = mo(b, 'long@gara.vn', 'Long (quản lý chung)')
    long_.wait_for_selector('.viec-cua-toi', timeout=20000)
    a = chup(long_, '14-long-viec-hom-nay', 'Long (quản lý chung)')
    co_kcs = 'KCS' in long_.locator('.viec-cua-toi').inner_text()
    ghi('Long (quản lý chung)', 'Mở Việc hôm nay: ' + ('có việc "KCS" xe 51G' if co_kcs else 'KHÔNG thấy việc KCS'), anh=a)
    if not co_kcs: bao('Long (quản lý chung)', 'Việc hôm nay không có việc KCS của xe 51G')
    ve_ho_so(long_, id_bh)
    t0 = T()
    long_.set_input_files('[data-the=huy-vat-tu] input[type=file]', ANH[1:3])
    toast(long_, 'Đã lưu 2 ảnh hủy vật tư', 40000)
    ghi('Long (quản lý chung)', 'Tải 2 ảnh hủy đèn hậu cũ (ảnh hủy vật tư)', T() - t0)
    ve_ho_so(long_, id_bh)
    # 17/10 (anh Thuận): nút "Đến phần làm bước" phải nổi bật – to, vàng đặc, gần hết bề ngang điện thoại
    kich = long_.locator('[data-den-buoc]').bounding_box()
    if not kich or kich['height'] < 48 or kich['width'] < 300 or 'chinh' not in (long_.locator('[data-den-buoc]').get_attribute('class') or ''):
        bao('Long (quản lý chung)', f'Nút "Đến phần làm bước" trên điện thoại chưa đủ nổi bật: {kich}')
    chup_man(long_, '15-long-nut-den-buoc-noi-bat')
    long_.locator('[data-den-buoc]').click()
    long_.wait_for_timeout(900)
    a = chup_man(long_, '15a-long-den-buoc-kcs')
    the_kcs = long_.locator('section.the', has=long_.locator('h2', has_text='Nghiệm thu (KCS)')).bounding_box()
    if not the_kcs or the_kcs['y'] > 400:
        bao('Long (quản lý chung)', 'Bấm "Đến phần làm bước" không đưa tới thẻ KCS')
    ghi('Long (quản lý chung)', 'Bấm "Đến phần làm bước 7: KCS ↓" ở đầu hồ sơ → nhảy thẳng tới thẻ KCS', anh=a)
    t0 = T()
    long_.set_input_files('.dem-anh-kcs input[type=file]', ANH[:6])
    expect(long_.locator('[data-anh-kcs="6"]')).to_be_visible(timeout=60000)
    ghi('Long (quản lý chung)', 'Tải 6 ảnh KCS một lần', T() - t0)
    a = chup(long_, '15-long-kcs', 'Long (quản lý chung)')
    long_.click('text=Đạt KCS')
    toast(long_, 'Đã ký đạt KCS')
    ghi('Long (quản lý chung)', 'Ký "Đạt KCS" xe 51G', anh=a)
    ve_ho_so(long_, id_le)
    long_.set_input_files('.dem-anh-kcs input[type=file]', ANH[:6])
    expect(long_.locator('[data-anh-kcs="6"]')).to_be_visible(timeout=60000)
    long_.click('text=Đạt KCS')
    toast(long_, 'Đã ký đạt KCS')
    ghi('Long (quản lý chung)', 'Xe khách lẻ 59A (không qua Detailing) → KCS đạt')

    # ===================== Kế toán Tiên (máy tính): thu tiền, giao xe, hồ sơ BH =====================
    tien = mo(b, 'tien@gara.vn', 'Tiên (kế toán)', dien_thoai=False)
    a = chup(tien, '16-tien-viec-hom-nay', 'Tiên (kế toán)')
    ghi('Tiên (kế toán)', 'Mở Việc hôm nay trên máy tính', anh=a)
    ve_ho_so(tien, id_le)
    t0 = T()
    tien.locator('.the button', has_text='Thu tiền & giao xe').click()
    m = modal(tien)
    a = chup(tien, '17-tien-thu-tien-xe-le', 'Tiên (kế toán)')
    m.get_by_role('button', name='Thu tiền & giao xe').click()
    toast(tien, 'giao xe')
    ghi('Tiên (kế toán)', 'Xe khách lẻ: "Thu tiền & giao xe" thu đủ ' + 'một lần', T() - t0, a)
    ve_ho_so(tien, id_bh)
    t0 = T()
    tien.locator('.the button', has_text=re.compile(r'^(Thu tiền & giao xe|Giao xe)$')).click()
    m = modal(tien)
    m.locator('[name=so_hd_bao_hiem]').fill('HD-2610-01')
    m.locator('.modal-chan .nut.chinh').click()
    toast(tien, 'giao xe')
    ghi('Tiên (kế toán)', 'Xe bảo hiểm: giao xe (khách không phải trả), số HĐ bảo hiểm HD-2610-01', T() - t0)
    ve_ho_so(tien, id_bh)
    a = chup(tien, '18-tien-ho-so-bh', 'Tiên (kế toán)')
    if 'ảnh hủy vật tư' not in tien.locator('section.the', has=tien.locator('h2', has_text='Hồ sơ bảo hiểm, thu nợ')).inner_text():
        bao('Tiên (kế toán)', 'Thẻ Hồ sơ BH không nhắc ảnh hủy vật tư')
    tien.click('text=Đã gửi hồ sơ bảo hiểm')
    toast(tien, 'Đã ghi ngày gửi')
    ve_ho_so(tien, id_bh)
    tien.click('text=Nhập hoa hồng')
    m = modal(tien)
    m.locator('[name=so_tien]').fill('400000'); m.locator('[name=ghi_chu]').fill('5% phần BH')
    m.locator('text=Lưu').click()
    toast(tien, 'Đã lưu hoa hồng')
    ghi('Tiên (kế toán)', 'Thẻ Hồ sơ BH nhắc có ảnh hủy vật tư → bấm "Đã gửi hồ sơ bảo hiểm", nhập hoa hồng GDV 400.000', anh=a)

    # ===================== Long: chăm sóc sau giao =====================
    ve_ho_so(long_, id_le)
    long_.locator('button', has_text='Ghi kết quả gọi').click()
    m = modal(long_)
    m.locator('textarea[name=ket_qua]').fill('Khách hài lòng, hẹn bảo dưỡng tháng 1')
    m.locator('.modal-chan .nut.chinh').click()
    toast(long_, 'Đã lưu')
    ghi('Long (quản lý chung)', 'Gọi chăm sóc khách xe 59A, ghi kết quả')

    # ===================== Giám đốc, cổ đông xem =====================
    thuan = mo(b, 'thuan@gara.vn', 'Anh Thuận (giám đốc)', dien_thoai=False)
    a = chup(thuan, '19-thuan-viec-hom-nay', 'Anh Thuận (giám đốc)')
    ghi('Anh Thuận (giám đốc)', 'Việc hôm nay', anh=a)
    ve_ho_so(thuan, id_bh)
    a = chup(thuan, '20-thuan-ho-so-51g', 'Anh Thuận (giám đốc)')
    ghi('Anh Thuận (giám đốc)', 'Xem hồ sơ 51G: ' + thuan.locator('.tien-do-chu').inner_text() if thuan.locator('.tien-do-chu').is_visible() else 'Xem hồ sơ 51G (10 bước)', anh=a)
    ve(thuan, '#/doanh-thu')
    a = chup(thuan, '21-thuan-doanh-thu', 'Anh Thuận (giám đốc)')
    ghi('Anh Thuận (giám đốc)', 'Xem Doanh thu & công nợ', anh=a)
    thuan_dt = mo(b, 'thuan@gara.vn', 'Anh Thuận (điện thoại)')
    ve_ho_so(thuan_dt, id_bh)
    a = chup(thuan_dt, '22-thuan-dien-thoai-ho-so', 'Anh Thuận (điện thoại)')
    ghi('Anh Thuận (điện thoại)', 'Xem hồ sơ 51G trên điện thoại', anh=a)
    cd = mo(b, 'codong@gara.vn', 'Cổ đông')
    a = chup(cd, '23-co-dong', 'Cổ đông')
    ghi('Cổ đông', 'Đăng nhập xem (chỉ xem)', anh=a)

    # Các màn hình chính trên điện thoại: dò tràn ngang
    for trang in ['#/ho-so', '#/thu-chi', '#/kho?the=ton', '#/dich-vu', '#/de-nghi']:
        ve(duy, trang)
        chup(duy, 'dt-' + re.sub(r'\W+', '-', trang).strip('-'), 'Duy (CVDV)')
    b.close()

json.dump({'nhat_ky': nhat_ky, 'van_de': van_de, 'loi_js': loi_js}, open(os.path.join(RA, 'ket-qua.json'), 'w'), ensure_ascii=False, indent=1)
print('\nVẤN ĐỀ:', len(van_de), '· LỖI JS:', len(loi_js))
for x in loi_js: print('  JS', x)
