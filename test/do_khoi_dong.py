"""Đo thời gian mở app (đã đăng nhập, vào "Việc hôm nay") với đường truyền giả lập.
Mỗi lời gọi dữ liệu bị trễ RTT ms (mặc định 130 ms ≈ Hà Nội/TP.HCM → Supabase Singapore); lần đầu gặp một địa chỉ
còn trả thêm 1 RTT cho bước "hỏi quyền" của trình duyệt (CORS preflight, bộ nhớ đệm theo từng địa chỉ).
Chỉ so CẤU TRÚC các lượt gọi (nối tiếp / song song, số lượng). Thời gian CSDL xử lý bỏ ra ngoài (máy chủ thử chạy NHO_API=1),
tải tệp mã chạy trong máy nên cũng không tính trễ – hai thứ này đo riêng.
Chạy (hai bản cạnh nhau):
  NHO_API=1 WEB=/duong/dan/ban_cu/web python3 test/may_chu_thu.py 8765 &      # bản cũ
  NHO_API=1 WEB=web/dist           python3 test/may_chu_thu.py 8766 &      # bản mới
  python3 test/do_khoi_dong.py http://127.0.0.1:8765/index.html http://127.0.0.1:8766/index.html"""
import re, sys, os, json, statistics
from playwright.sync_api import sync_playwright

GOC = os.path.dirname(os.path.abspath(__file__))
GIA = open(os.path.join(GOC, 'supabase-gia.js'), encoding='utf-8').read()
RTT = int(os.environ.get('RTT', '130'))
VONG = int(os.environ.get('VONG', '7'))
EMAIL = os.environ.get('EMAIL', 'thuan@gara.vn')
URLS = sys.argv[1:] or ['http://127.0.0.1:8765/index.html']

TRE_JS = """(() => {
  const RTT = %d, goc = window.fetch.bind(window);
  const da = () => { try { return new Set(JSON.parse(sessionStorage.getItem('__hoi_quyen') || '[]')); } catch { return new Set(); } };
  window.__luot = [];
  window.fetch = async (url, opt) => {
    const u = String(url);
    if (!u.includes('/api/')) return goc(url, opt);
    let khoa = u;
    try { const q = JSON.parse(opt.body); delete q.user; khoa = u + (u.endsWith('/rpc') ? '|' + q.ham : '|' + JSON.stringify(q)); } catch {}
    const set = da(), lanDau = !set.has(khoa);
    if (lanDau) { set.add(khoa); sessionStorage.setItem('__hoi_quyen', JSON.stringify([...set])); }
    const t0 = performance.now();
    await new Promise((r) => setTimeout(r, RTT * (lanDau ? 2 : 1)));
    const kq = await goc(url, opt);
    window.__luot.push([Math.round(t0), Math.round(performance.now()), u.split('/api/')[1] + (u.endsWith('/rpc') ? ':' + (JSON.parse(opt.body).ham || '') : '')]);
    return kq;
  };
})();""" % RTT

XONG = "() => !!document.querySelector('.menu') && !document.querySelector('#noi-dung .dang-tai') && document.querySelector('#noi-dung').children.length > 0 ? performance.now() : false"


def do(b, url, lanh):
    ctx = b.new_context(viewport={'width': 1280, 'height': 900}, locale='vi-VN')
    pg = ctx.new_page()
    pg.route(re.compile(r'.*supabase-js@2\.45\.4/\+esm$'), lambda r: r.fulfill(status=200, content_type='application/javascript', body=GIA))
    ctx.add_init_script(TRE_JS)
    loi = []
    pg.on('pageerror', lambda e: loi.append(str(e)))
    pg.goto(url)
    pg.fill('input[name=email]', EMAIL); pg.fill('input[name=mat_khau]', 'matkhau123'); pg.click('button[type=submit]')
    pg.wait_for_function(XONG, polling=10, timeout=60000)
    pg.wait_for_load_state('networkidle')
    kq = []
    for i in range(VONG + 1):
        if lanh: pg.evaluate("sessionStorage.removeItem('__hoi_quyen')")
        pg.goto('about:blank'); pg.goto(url)
        t = pg.wait_for_function(XONG, polling=10, timeout=60000).json_value()
        pg.wait_for_load_state('networkidle')
        luot = pg.evaluate('window.__luot')
        if i: kq.append((t, len(luot), luot))     # bỏ lần đầu (làm ấm)
    ctx.close()
    assert not loi, loi
    return kq


with sync_playwright() as p:
    b = p.chromium.launch()
    for url in URLS:
        for lanh, ten in ((True, 'bộ nhớ "hỏi quyền" lạnh (máy mới mở trình duyệt)'), (False, 'bộ nhớ "hỏi quyền" đã ấm')):
            kq = do(b, url, lanh)
            ts = [round(k[0]) for k in kq]
            print(f'{url}\n   {ten}: mở xong sau {statistics.median(ts):.0f} ms (các lần: {ts}) · {kq[0][1]} lượt gọi dữ liệu')
            if lanh: print('   các lượt gọi (bắt đầu→xong, ms từ lúc mở):', sorted(kq[len(kq) // 2][2]))
    b.close()
