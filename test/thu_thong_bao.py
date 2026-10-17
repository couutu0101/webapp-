"""Kiểm thử giao diện THÔNG BÁO hiện lên màn hình người đảm nhận tiếp theo (054).
Chạy (máy chủ thử đang chạy ở cổng 8765): bash test/lam_moi_csdl.sh && python3 test/thu_thong_bao.py
Thử bản đóng gói: (cd web && node build.mjs --thu) rồi chạy máy chủ thử với WEB=web/dist-thu.
Khác bộ thử chính: ở đây khung thông báo BẬT (hỏi máy chủ mỗi 0,6 giây cho nhanh); bộ thử chính tắt khung bằng window.__TAT_THONG_BAO."""
import os, re, subprocess, sys
from playwright.sync_api import sync_playwright, expect, TimeoutError as PwTimeout

GOC = os.path.dirname(os.path.abspath(__file__))
URL = 'http://127.0.0.1:8765/index.html'
CHUP = os.path.join('/tmp', 'chup')
os.makedirs(CHUP, exist_ok=True)
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
    page.wait_for_timeout(450)          # đợi hiệu ứng hộp hiện xong
    page.screenshot(path=os.path.join(CHUP, f'{ten}.png'))


def sql(cau):
    return subprocess.run(['psql', '-h', '/tmp', '-U', 'postgres', '-d', 'gara', '-qAt', '-c', cau], check=True, capture_output=True, text=True).stdout.strip()


def mo(browser, email, rong=1280, cao=900, hoi_ms=600, tat_tb=False):
    ctx = browser.new_context(viewport={'width': rong, 'height': cao}, locale='vi-VN')
    ctx.add_init_script(MOD_JS)
    ctx.add_init_script(f'window.__HOI_TB_MS = {hoi_ms}; window.__HIEN_TAT_CA = true;' + (' window.__TAT_THONG_BAO = true;' if tat_tb else ''))
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


ANH_LENH = '/tmp/anh-lenh-thu.png'
with open(ANH_LENH, 'wb') as _f:
    import base64 as _b64
    _f.write(_b64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))

def ve_trang(page, hash_):
    page.evaluate('(h) => { location.hash = h; }', hash_)
    yen(page)
    page.wait_for_timeout(250)


def toast_co(page, chu):
    expect(page.locator('#toast')).to_contain_text(chu, timeout=8000)


def api_goi(page, js, *args):
    return page.evaluate('async (a) => { const api = await window.__mod("api"); ' + js + ' }', list(args) if args else [])


def tao_ho_so_khach(duy, bien, ten_khach='Khách thử thông báo'):
    """Tiếp nhận xe khách ngoài BH + lập báo giá 2 dòng → "Đã duyệt giá" ngay, chờ lập lệnh sửa chữa. Trả id hồ sơ."""
    return duy.evaluate("""async ([bien, ten]) => {
      const api = await window.__mod('api');
      const kq = await api.tiepNhanXe({ bien_so: bien, ten_khach: ten, dien_thoai: '0909054001', nguon_tt: 'khach', tinh_trang_xe: 'Móp cửa trước', tu_van: 'Không',
        dong_xe_id: api.dm.dong_xe.find((d) => d.ten === 'VF3').id });
      await api.lapBaoGia(kq.id, [{ ten: 'Gò cánh cửa trước', nhom: 'dong', gia_bao: 900000 }, { ten: 'Sơn cánh cửa trước', nhom: 'son', gia_bao: 700000 }], 0.08);
      return kq.id;
    }""", [bien, ten_khach])


def lap_lenh_api(duy, id_hs, to='DS', nguoi='Minh', lan_dau=True):
    """Lập lệnh sửa chữa cho các hạng mục vừa duyệt. Lệnh đầu của hồ sơ phải có giờ hẹn giao; lệnh bổ sung thì không cần."""
    duy.evaluate("""async ([id, to, nguoi, lanDau]) => {
      const api = await window.__mod('api');
      const hm = (await api.layHangMuc(id)).filter((m) => m.trang_thai === 'duyet');
      await api.lapLenh(id, lanDau ? new Date(Date.now() + 864e5).toISOString() : null, hm.map((m) => ({ id: m.id, to_id: to, nguoi_lam: nguoi })));
    }""", [id_hs, to, nguoi, lan_dau])


with sync_playwright() as p:
    b = p.chromium.launch()

    # ===== A. Ví dụ của anh Thuận: CVDV lập lệnh sửa chữa → trưởng nhóm tổ phụ trách nhận thông báo lên màn hình =====
    han = mo(b, 'han@gara.vn')
    han.wait_for_selector('.menu-ds a[data-duong="thong-bao"]:not([hidden])', timeout=15000)
    ghi('Trưởng nhóm Hận (tổ Đồng sơn) đăng nhập, menu: ' + ', '.join(han.locator('.menu-ds a:not([hidden])').all_inner_texts()))
    expect(han.locator('.tb-nen')).to_have_count(0)
    expect(han.locator('.menu-ds a[data-duong="thong-bao"] .tb-dem')).to_be_hidden()

    duy = mo(b, 'duy@gara.vn')
    id_hs = tao_ho_so_khach(duy, '51K-054.01')
    ve_trang(duy, f'#/ho-so/{id_hs}')
    duy.wait_for_selector('h1')
    expect(duy.locator('h1 .nhan')).to_contain_text('Đã duyệt giá')
    expect(duy.locator('details.the-thong-bao')).to_have_count(0)           # chưa có thông báo nào về hồ sơ này
    duy.locator('button', has_text='Lập lệnh sửa chữa').click()
    m = duy.locator('.modal').last
    # 056: lệnh gọn theo tổ (Đồng + Sơn → tổ Đồng sơn, người thực hiện mặc định trưởng nhóm Hận), bắt ảnh lệnh sửa chữa
    expect(m.locator('select[name=nguoi_DS] option:checked')).to_contain_text('Hận')
    m.locator('.khoi-dinh-kem input[type=file]').set_input_files(ANH_LENH)
    m.locator('text=Giao việc').click()
    toast_co(duy, 'Đã giao việc')
    expect(duy.locator('.tb-nen')).to_have_count(0)                         # người lập lệnh không tự nhận thông báo của mình
    ghi('CVDV Duy lập lệnh sửa chữa cho xe 51K-054.01 (2 hạng mục → tổ Đồng sơn); khung thông báo KHÔNG hiện cho chính Duy')

    han.wait_for_selector('.tb-nen', timeout=15000)
    the = han.locator('.tb-nen .tb-the')
    expect(the).to_have_count(1)
    expect(the).to_contain_text('Việc mới cho tổ Đồng sơn')
    expect(the.locator('.bien-so')).to_have_text('51K-054.01')
    expect(the).to_contain_text('Gò cánh cửa trước')
    expect(the).to_contain_text('Sơn cánh cửa trước')
    expect(the).to_contain_text('Nguyễn Trọng Duy giao việc')
    expect(the.locator('.tb-loai')).to_have_text('Tổ sửa chữa')
    expect(han.locator('.tb-hop h2')).to_have_text('Thông báo mới')
    assert han.title().startswith('(1) '), han.title()
    che = han.evaluate("() => { const e = document.elementFromPoint(120, 200); return !!(e && e.closest('.tb-nen')); }")
    assert che, 'Khung thông báo phải che kín màn hình (không bấm xuyên được)'
    han.keyboard.press('Escape')
    han.mouse.click(30, 30)
    expect(han.locator('.tb-nen')).to_have_count(1)                         # Esc / bấm ra ngoài không tắt được: phải bấm Đã nhận
    ghi('Trưởng nhóm Hận thấy khung to giữa màn hình: "' + the.locator('.tb-tieu').inner_text() + '" | biển ' + the.locator('.bien-so').inner_text()
        + ' | dòng: ' + ' / '.join(the.locator('.tb-ds li').all_inner_texts()) + ' | tiêu đề thẻ trình duyệt: ' + han.title()
        + ' | Esc và bấm ra ngoài không tắt được')
    chup(han, 'tb-01-truong-nhom-nhan-thong-bao')
    # Trang Việc hôm nay phía sau tự tải lại để có sẵn xe mới
    expect(han.locator('.the-xe', has_text='51K-054.01')).to_have_count(1, timeout=10000)
    ghi('Trang Việc hôm nay phía sau khung tự cập nhật: xe 51K-054.01 đã nằm trong "Xe của tổ Đồng sơn"')

    han.locator('[data-tb=nhan]').click()
    expect(han.locator('.tb-nen')).to_have_count(0)
    assert not han.title().startswith('('), han.title()
    r = sql("select count(*) from public.thong_bao t join public.nhan_vien n on n.id = t.nguoi_nhan where n.email = 'han@gara.vn' and t.khoa = 'to:moi:" + str(id_hs) + ":DS' and t.da_nhan_luc is not null")
    assert r == '1', r
    han.wait_for_timeout(1800)                                              # vài lượt hỏi nữa: khung không được hiện lại
    expect(han.locator('.tb-nen')).to_have_count(0)
    ghi('Hận bấm "Đã nhận" → khung tắt, tiêu đề thẻ trở lại bình thường, máy chủ ghi lúc nhận; hỏi tiếp vẫn không hiện lại')

    ve_trang(duy, '#/viec')
    ve_trang(duy, f'#/ho-so/{id_hs}')
    duy.wait_for_selector('h1')
    the_tb = duy.locator('details.the-thong-bao')
    expect(the_tb).to_have_count(1)
    expect(the_tb).to_contain_text('Thông báo đã gửi (1)')
    expect(the_tb).to_contain_text('Đặng Thanh Hận')
    expect(the_tb).to_contain_text(re.compile(r'Đã nhận \d{2}:\d{2}'))
    expect(the_tb.locator('.nhan.tb-chua')).to_have_count(0)
    the_tb.scroll_into_view_if_needed()
    yen(duy)
    duy.wait_for_timeout(300)
    the_tb.screenshot(path=os.path.join(CHUP, 'tb-02-ho-so-ghi-ai-nhan-luc-nao.png'))       # chụp riêng thẻ để thấy rõ ai nhận lúc nào
    ghi('Hồ sơ xe ghi lại: ' + the_tb.locator('summary').inner_text().replace('\n', ' ') + ' → ' + the_tb.locator('li').first.inner_text().replace('\n', ' | '))

    # ===== B. "Đã nhận – xem xe của tổ" đưa đúng tới nơi làm; trang Thông báo liệt kê lịch sử =====
    ve_trang(han, '#/thong-bao')
    han.wait_for_selector('.tb-dong', timeout=10000)
    expect(han.locator('.tb-dong')).to_have_count(1)
    expect(han.locator('.tb-dong')).to_contain_text('Việc mới cho tổ Đồng sơn')
    expect(han.locator('.tb-dong .nhan.tt-tot')).to_contain_text('Đã nhận lúc')
    chup(han, 'tb-03-trang-thong-bao')
    ghi('Trang Thông báo của Hận: ' + han.locator('.tb-dong').first.inner_text().replace('\n', ' | ')[:160])
    duy.evaluate("""async (id) => {
      const api = await window.__mod('api');
      await api.lapBaoGia(id, [{ ten: 'Thay ốp cản trước', nhom: 'phu_tung', gia_bao: 300000 }], 0.08);
    }""", id_hs)
    lap_lenh_api(duy, id_hs, lan_dau=False)
    han.wait_for_selector('.tb-nen', timeout=15000)
    expect(han.locator('.tb-nen .tb-the')).to_have_count(1)
    expect(han.locator('.tb-nen .tb-ds li')).to_have_text(['Thay ốp cản trước (Minh)'])
    ghi('Sau khi đã nhận, giao thêm hạng mục → khung MỚI hiện lại (1 dòng: ' + han.locator('.tb-nen .tb-ds li').first.inner_text() + ')')
    han.locator('[data-tb=nhan-mo]').click()
    expect(han.locator('.tb-nen')).to_have_count(0)
    expect(han).to_have_url(re.compile(r'#/viec$'))
    expect(han.locator('.the-xe', has_text='51K-054.01')).to_contain_text('Thay ốp cản trước', timeout=10000)
    ghi('"Đã nhận – xem xe của tổ" → vào Việc hôm nay, thấy hạng mục mới; trưởng nhóm không bị đưa vào trang hồ sơ (không có quyền)')

    han.context.close()          # từ đây dùng các máy riêng của Hận (hỏi thưa) để dựng đúng từng tình huống, tránh máy này tranh nhận

    # ===== B2. Bấm "Đã nhận" đúng lúc có dòng mới gộp vào thông báo → chưa tính là nhận, thẻ hiện nội dung mới =====
    han3 = mo(b, 'han@gara.vn', hoi_ms=600000)                               # gần như không tự hỏi lại: chỉ hỏi khi mình ra hiệu → dựng đúng tình huống "đang hiện bản cũ"
    han3.wait_for_selector('.menu-ds a[data-duong="thong-bao"]:not([hidden])', timeout=15000)
    ve_trang(han3, '#/thong-bao')
    id_hs6 = tao_ho_so_khach(duy, '51K-054.06', 'Khách sáu')
    lap_lenh_api(duy, id_hs6)
    han3.evaluate("() => window.dispatchEvent(new Event('online'))")
    han3.wait_for_selector('.tb-nen .tb-the', timeout=10000)
    expect(han3.locator('.tb-nen .tb-ds li')).to_have_count(2)
    # CVDV giao thêm 1 hạng mục NGAY LÚC khung đang hiện (máy Hận chưa kịp hỏi lại nên vẫn đang hiện bản 2 dòng)
    duy.evaluate("""async (id) => {
      const api = await window.__mod('api');
      await api.lapBaoGia(id, [{ ten: 'Thay đèn hậu', nhom: 'phu_tung', gia_bao: 450000 }], 0.08);
    }""", id_hs6)
    lap_lenh_api(duy, id_hs6, lan_dau=False)
    assert sql(f"select cardinality(chi_tiet) from public.thong_bao where khoa = 'to:moi:{id_hs6}:DS'") == '3'
    han3.locator('[data-tb=nhan-mo]').click()
    expect(han3.locator('.tb-nen .tb-them')).to_be_visible(timeout=10000)
    expect(han3.locator('.tb-nen .tb-ds li')).to_have_count(3)
    expect(han3.locator('.tb-nen .tb-ds li').last).to_contain_text('Thay đèn hậu')
    expect(han3.locator('.tb-nen .tb-loi')).to_have_count(0)
    assert sql(f"select count(*) from public.thong_bao where khoa = 'to:moi:{id_hs6}:DS' and da_nhan_luc is null") == '1'
    assert han3.evaluate('location.hash') == '#/thong-bao', han3.evaluate('location.hash')      # chưa nhận được nên không bị đưa đi chỗ khác
    chup(han3, 'tb-07-co-them-noi-dung-moi')
    ghi('Giao thêm hạng mục đúng lúc Hận đang đọc khung: bấm "Đã nhận" KHÔNG ghi nhận (máy chủ giữ nguyên chưa nhận), thẻ tự cập nhật 3 dòng + ghi chú "'
        + han3.locator('.tb-nen .tb-them').inner_text() + '", không bị đưa sang trang khác')
    han3.locator('[data-tb=nhan-mo]').click()
    expect(han3.locator('.tb-nen')).to_have_count(0)
    expect(han3).to_have_url(re.compile(r'#/viec$'))
    assert sql(f"select count(*) from public.thong_bao where khoa = 'to:moi:{id_hs6}:DS' and da_nhan_luc is not null and cardinality(chi_tiet) = 3") == '1'
    ghi('Đọc xong bản mới, bấm "Đã nhận – xem xe của tổ" → ghi nhận, vào Việc hôm nay')

    # Đã nhận ở máy khác (cùng tài khoản) rồi mới bấm ở máy này → khung tắt êm, không báo lỗi
    id_hs8 = tao_ho_so_khach(duy, '51K-054.08', 'Khách tám')
    lap_lenh_api(duy, id_hs8)
    han3.evaluate("() => window.dispatchEvent(new Event('online'))")
    han3.wait_for_selector('.tb-nen .tb-the', timeout=10000)
    sql(f"update public.thong_bao set da_nhan_luc = now() where khoa = 'to:moi:{id_hs8}:DS'")
    han3.locator('[data-tb=nhan]').click()
    expect(han3.locator('.tb-nen')).to_have_count(0, timeout=10000)
    ghi('Thông báo đã được nhận từ máy khác: bấm "Đã nhận" ở máy này thì khung tắt êm, không báo lỗi')
    han3.context.close()

    # ===== B3. Mạng treo (không trả lời cũng không báo lỗi): quá giờ chờ thì báo lỗi trên thẻ, không kẹt, có lối "Tạm ẩn" =====
    han4 = mo(b, 'han@gara.vn', hoi_ms=600000)
    han4.wait_for_selector('.menu-ds a[data-duong="thong-bao"]:not([hidden])', timeout=15000)
    han4.evaluate('window.__HET_GIO_TB_MS = 1500')
    # Giả lập mạng treo ngay trong trang: yêu cầu "nhan_thong_bao" không bao giờ có trả lời (cũng không có lỗi) khi window.__treo = true
    han4.evaluate("""() => {
      window.__treo = true; window.__soTreo = 0;
      const goc = window.fetch.bind(window);
      window.fetch = (u, o) => {
        if (window.__treo && String(o && o.body).includes('"nhan_thong_bao"')) { window.__soTreo++; return new Promise(() => {}); }
        return goc(u, o);
      };
    }""")
    id_hs7 = tao_ho_so_khach(duy, '51K-054.07', 'Khách bảy')
    lap_lenh_api(duy, id_hs7)
    han4.evaluate("() => window.dispatchEvent(new Event('online'))")
    han4.wait_for_selector('.tb-nen .tb-the', timeout=10000)
    han4.locator('[data-tb=nhan]').click()
    expect(han4.locator('.tb-nen .tb-loi')).to_be_visible(timeout=8000)
    expect(han4.locator('[data-tb=nhan]')).to_be_enabled()
    expect(han4.locator('[data-tb=an-tam]')).to_be_visible()
    assert han4.evaluate('window.__soTreo') >= 1
    assert sql(f"select count(*) from public.thong_bao where khoa = 'to:moi:{id_hs7}:DS' and da_nhan_luc is null") == '1'
    chup(han4, 'tb-08-mang-treo-bao-loi')
    ghi('Mạng treo: sau ít giây thẻ báo "' + han4.locator('.tb-nen .tb-loi').inner_text() + '", nút bấm lại được, có nút "Tạm ẩn khung 10 phút"')
    han4.locator('[data-tb=an-tam]').click()
    expect(han4.locator('.tb-nen')).to_have_count(0)
    assert sql(f"select count(*) from public.thong_bao where khoa = 'to:moi:{id_hs7}:DS' and da_nhan_luc is null") == '1'
    han4.reload()                                                            # tải lại: thông báo chưa nhận nên khung hiện lại
    han4.wait_for_selector('.tb-nen .tb-the', timeout=15000)
    han4.locator('[data-tb=nhan]').click()
    expect(han4.locator('.tb-nen')).to_have_count(0)
    assert sql(f"select count(*) from public.thong_bao where khoa = 'to:moi:{id_hs7}:DS' and da_nhan_luc is not null") == '1'
    ghi('Bấm "Tạm ẩn" thì khung tắt nhưng thông báo vẫn CHƯA nhận; tải lại thấy khung, mạng ổn bấm "Đã nhận" là xong')
    han4.context.close()

    # ===== C. Kho và tiền: đề nghị chi → quản lý duyệt → kế toán chi =====
    long_ = mo(b, 'long@gara.vn')
    tien_ = mo(b, 'tien@gara.vn')
    id_dn = duy.evaluate("""async () => {
      const api = await window.__mod('api');
      return api.lapDeNghiChi({ muc_id: api.dm.muc_thu_chi.find((m) => m.ten === 'Nước').id, so_tien: 120000, noi_dung: 'Nước uống cho tổ' });
    }""")
    long_.wait_for_selector('.tb-nen', timeout=15000)
    t = long_.locator('.tb-nen .tb-the')
    expect(t.locator('.tb-loai')).to_have_text('Tiền')
    expect(t.locator('.tb-tieu')).to_have_text('Đề nghị chi 120.000 đ chờ duyệt')
    expect(t).to_contain_text('Nước uống cho tổ')
    expect(t).to_contain_text('Nguyễn Trọng Duy đề nghị')
    chup(long_, 'tb-04-quan-ly-duyet-chi')
    ghi('Quản lý Long nhận: ' + t.locator('.tb-loai').inner_text() + ' – ' + t.locator('.tb-tieu').inner_text() + ' – ' + t.locator('.tb-nd').inner_text())
    long_.locator('[data-tb=nhan-mo]').click()
    expect(long_.locator('.tb-nen')).to_have_count(0)
    expect(long_).to_have_url(re.compile(r'#/de-nghi$'))
    long_.evaluate("async (id) => { const api = await window.__mod('api'); await api.duyetDeNghi(id, true, null); }", id_dn)
    tien_.wait_for_selector('.tb-nen', timeout=15000)
    t2 = tien_.locator('.tb-nen .tb-the')
    expect(t2.locator('.tb-tieu')).to_have_text('Đề nghị chi 120.000 đ đã duyệt – chi tiền')
    expect(t2).to_contain_text('Trần Tử Long duyệt')
    ghi('Long duyệt → kế toán Tiên nhận: ' + t2.locator('.tb-tieu').inner_text() + ' (' + t2.locator('.tb-nd').inner_text() + ')')
    tien_.locator('[data-tb=nhan]').click()
    expect(tien_.locator('.tb-nen')).to_have_count(0)

    # ===== D. Nhắc quá hạn (tính trên máy, "Đã biết" nhớ 4 giờ) =====
    id_hs2 = tao_ho_so_khach(duy, '51K-054.02', 'Khách quá hạn')
    sql(f"update public.ho_so set nguoi_tiep_theo = (select id from public.nhan_vien where email = 'duy@gara.vn'), giao_viec_luc = now() - interval '2 days' where id = {id_hs2}")
    # (1) Đang ở trang khác (hồ sơ) rồi tải lại: máy tự tính việc quá hạn sau ít giây (ở đây rút còn 1 giây cho nhanh)
    duy.evaluate('window.__QUA_HAN_SAU_MS = 1000')
    ve_trang(duy, f'#/ho-so/{id_hs}')
    duy.reload()
    duy.evaluate('window.__QUA_HAN_SAU_MS = 1000')
    duy.wait_for_selector('.tb-nen', timeout=25000)
    ghi('Duy đang ở trang hồ sơ (không phải Việc hôm nay): máy tự tính lại việc quá hạn và nhắc')
    # (2) Mở Việc hôm nay: nhắc ngay theo danh sách vừa tải
    ve_trang(duy, '#/viec')
    qh = duy.locator('.tb-nen .tb-the[data-tb-the=qua-han]')
    expect(qh).to_have_count(1)
    expect(qh.locator('.tb-loai')).to_have_text('Nhắc quá hạn')
    expect(qh).to_contain_text('Có 1 việc của anh/chị đã quá hạn')
    expect(qh.locator('.bien-so')).to_have_text('51K-054.02')
    expect(qh).to_contain_text('Lập lệnh sửa chữa')
    expect(qh).to_contain_text('Quá hạn')
    chup(duy, 'tb-05-nhac-qua-han')
    ghi('Duy có xe quá hạn lập lệnh → khung "Nhắc quá hạn": ' + qh.locator('.tb-tieu').inner_text() + ' | ' + qh.locator('.tb-ds-qh li').first.inner_text().replace('\n', ' '))
    qh.locator('[data-tb=biet]').click()
    expect(duy.locator('.tb-nen')).to_have_count(0)
    duy.reload()
    duy.wait_for_selector('.viec-cua-toi', timeout=15000)
    duy.wait_for_timeout(2500)
    expect(duy.locator('.tb-nen')).to_have_count(0)
    khoa_nho = duy.evaluate("() => Object.keys(localStorage).filter((k) => k.startsWith('gara_nhac_qua_han_'))")
    assert len(khoa_nho) == 1, khoa_nho
    ghi('Duy bấm "Đã biết" → tải lại trang, khung không hiện lại trong 4 giờ (đã nhớ trong trình duyệt)')

    # ===== E. Nhiều thông báo cùng lúc trên điện thoại + "Đã nhận tất cả" =====
    han_dt = mo(b, 'han@gara.vn', rong=390, cao=844)
    han_dt.wait_for_selector('.menu', state='attached')
    id_hs3 = tao_ho_so_khach(duy, '51K-054.03', 'Khách ba')
    id_hs4 = tao_ho_so_khach(duy, '51K-054.04', 'Khách bốn')
    lap_lenh_api(duy, id_hs3)
    lap_lenh_api(duy, id_hs4)
    han_dt.wait_for_selector('.tb-nen .tb-the', timeout=15000)
    expect(han_dt.locator('.tb-nen .tb-the')).to_have_count(2, timeout=10000)
    expect(han_dt.locator('.tb-hop h2')).to_have_text('Có 2 thông báo mới')
    expect(han_dt.locator('[data-tb=nhan-tat-ca]')).to_have_text('Đã nhận tất cả (2)')
    kich = han_dt.evaluate("() => { const r = document.querySelector('.tb-hop').getBoundingClientRect(); return [Math.round(r.width), innerWidth, document.documentElement.scrollWidth]; }")
    assert kich[2] <= kich[1] + 1, f'Điện thoại bị tràn ngang: {kich}'
    chup(han_dt, 'tb-06-dien-thoai-hai-thong-bao')
    ghi(f'Điện thoại 390px: "{han_dt.locator(".tb-hop h2").inner_text()}", khung rộng {kich[0]}px, không tràn ngang; nút: {han_dt.locator("[data-tb=nhan-tat-ca]").inner_text()}')
    han_dt.locator('[data-tb=nhan-tat-ca]').click()
    expect(han_dt.locator('.tb-nen')).to_have_count(0)
    r = sql("select count(*) from public.thong_bao t join public.nhan_vien n on n.id = t.nguoi_nhan where n.email = 'han@gara.vn' and t.da_nhan_luc is null")
    assert r == '0', r
    ghi('"Đã nhận tất cả" → cả hai thông báo được ghi nhận')

    # ===== F. Máy chủ chưa có bảng thông báo (chưa chạy 054) → lặng lẽ không làm gì; việc chính không bị hỏng =====
    sql("alter table public.thong_bao rename to thong_bao_tam")
    try:
        id_hs5 = tao_ho_so_khach(duy, '51K-054.05', 'Khách năm')
        lap_lenh_api(duy, id_hs5)
        ghi('Bảng thông báo tạm biến mất: CVDV vẫn lập báo giá + lập lệnh sửa chữa bình thường (thông báo lỗi bị cô lập)')
        han2 = mo(b, 'han@gara.vn')
        han2.wait_for_selector('.menu', state='attached')
        han2.wait_for_timeout(2500)
        expect(han2.locator('.tb-nen')).to_have_count(0)
        expect(han2.locator('.menu-ds a[data-duong="thong-bao"]')).to_be_hidden()
        ghi('Trưởng nhóm đăng nhập khi máy chủ chưa có 054: không khung, mục "Thông báo" ẩn khỏi menu, trang vẫn dùng bình thường')
        han2.context.close()
    finally:
        sql("alter table public.thong_bao_tam rename to thong_bao")
    # Việc nhận xe năm không có thông báo (bảng vắng lúc đó) nên không còn gì chờ nhận
    r = sql("select count(*) from public.thong_bao where khoa like 'to:moi:" + str(id_hs5) + ":%'")
    assert r == '0', r

    # ===== G. Tài khoản không có thông báo =====
    cd = mo(b, 'codong@gara.vn')
    cd.wait_for_timeout(2000)
    expect(cd.locator('.tb-nen')).to_have_count(0)
    expect(cd.locator('.menu-ds a[data-duong="thong-bao"]')).to_have_count(0)
    ghi('Cổ đông: không có mục Thông báo, không có khung')

    b.close()

print('\n=== KẾT QUẢ ===')
if loi:
    print(f'{len(loi)} lỗi JavaScript / console:')
    for x in loi:
        print('  -', x)
    sys.exit(1)
print(f'ĐẠT cả {buoc} bước, 0 lỗi JavaScript.')
