"""056 (anh Thuận 17/10 22:52): giám đốc hủy hồ sơ mọi bước (doanh thu thương lượng, trả vật tư chưa dùng về kho) và
phiếu thu lệch công nợ (ghi lý do → quản lý chung / giám đốc duyệt chỉnh công nợ về số thực thu). Duyệt giá 2 ô và lệnh sửa
chữa theo tổ có ở test/thu_giao_dien.py.
Chạy: bash test/lam_moi_csdl.sh && (cd web && node build.mjs --thu) && WEB=web/dist-thu python3 test/may_chu_thu.py 8765 &
      python3 test/thu_056.py"""
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



import subprocess
def sql(cau):
    return subprocess.run(['psql', '-h', '/tmp', '-U', 'postgres', '-d', 'gara', '-Atqc', cau], check=True, capture_output=True, text=True).stdout.strip()

TAO = """async ([bien, sdt, dong]) => { const api = await window.__mod('api');
  const kq = await api.tiepNhanXe({ bien_so: bien, ten_khach: 'Khách 056', dien_thoai: sdt, nguon_tt: 'khach', tinh_trang_xe: 'Đèn, cản',
    tu_van: 'Không', qua_detailing: false, dong_xe_id: api.dm.dong_xe.find((d) => d.ten === 'VF3').id });
  await api.lapBaoGia(kq.id, dong, 0.08);
  return kq; }"""
LENH_XUAT = """async ([id, hang]) => { const api = await window.__mod('api'); const hm = await api.layHangMuc(id);
  await api.lapLenh(id, new Date(Date.now() + 864e5).toISOString(), hm.map((m) => ({ id: m.id, to_id: 'DS', nguoi_lam: '' })));
  const dx = await api.rpc('lap_de_xuat_vat_tu', { p: { ho_so_id: id, dong: [{ hang_id: hang, so_luong: 3 }] } });
  await api.rpc('xuat_kho_de_xuat', { p_de_xuat: dx.id });
  const xong = hm.find((m) => m.ten === 'Sơn cản'); if (xong) await api.baoXong(xong.id); }"""

with sync_playwright() as p:
    b = p.chromium.launch()
    sql("insert into public.hang_kho (chi_nhanh_id, ma, ten, nhom, dvt) values ('TK', 'DEN-056', 'Đèn pha thử', 'Phụ tùng', 'Cái') on conflict do nothing")
    sql("insert into public.lo_kho (chi_nhanh_id, hang_id, ngay, so_luong, con_lai, don_gia_von) select 'TK', id, current_date - 1, 5, 5, 400000 from public.hang_kho where ma = 'DEN-056'")
    hang = int(sql("select id from public.hang_kho where ma = 'DEN-056'"))
    gd = mo(b, 'thuan@gara.vn')
    hs = gd.evaluate(TAO, ['51A-056.11', '0909056111', [{'ten': 'Thay đèn pha', 'nhom': 'phu_tung', 'gia_bao': 2000000}, {'ten': 'Sơn cản', 'nhom': 'son', 'gia_bao': 1000000}]])
    gd.evaluate(LENH_XUAT, [hs['id'], hang])
    ghi(f'Xe {hs["ma"]} đang sửa: đã xuất 3 đèn (giá vốn 1.200.000), "Sơn cản" đã xong')

    # ---------- 1. Giám đốc hủy hồ sơ đang sửa ----------
    ql = mo(b, 'long@gara.vn')
    ve_trang(ql, f'#/ho-so/{hs["id"]}')
    expect(ql.locator('[data-huy-gd]')).to_have_count(0)
    expect(ql.locator('.tieu-de-trang button', has_text='Hủy hồ sơ')).to_have_count(0)
    ghi('Quản lý chung: xe đang sửa không có nút Hủy hồ sơ (chỉ giám đốc)')
    ve_trang(gd, f'#/ho-so/{hs["id"]}')
    gd.locator('[data-huy-gd]').click()
    m = modal(gd)
    expect(m.locator('[data-tra-kho]')).to_have_count(1)
    expect(m.locator('tbody tr')).to_contain_text('Đèn pha thử')
    m.locator('.modal-chan .nut.chinh').click()
    expect(gd.locator('#toast')).to_contain_text('Ghi lý do hủy', timeout=5000)
    m.locator('textarea[name=ly_do]').fill('Khách không sửa tiếp, chỉ sơn cản')
    m.locator('[name=doanh_thu]').fill('1500000'); m.locator('[name=doanh_thu]').dispatch_event('input')
    m.locator('[data-tra-kho]').fill('2')
    chup(gd, '056-01-huy-giam-doc')
    m.locator('.modal-chan .nut.chinh').click()
    expect(gd.locator('#toast')).to_contain_text('thu theo thỏa thuận 1.500.000', timeout=8000)
    ghi('Giám đốc: nút Hủy hồ sơ ở xe đang sửa → bắt lý do; doanh thu thương lượng 1.500.000; trả 2/3 đèn về kho')
    ve_trang(gd, f'#/ho-so/{hs["id"]}')
    expect(gd.locator('[data-huy-thoa-thuan]')).to_have_count(1)
    expect(gd.locator('h1 .nhan').first).to_contain_text('Đã giao')
    tien_the = the(gd, 'Tiền')
    expect(tien_the).to_contain_text('1.500.000')
    assert sql("select sum(con_lai) from public.lo_kho l join public.hang_kho h on h.id = l.hang_id where h.ma = 'DEN-056'") == '4.000'
    assert sql(f"select sum(gia_von) from public.phieu_xuat_dong d join public.phieu_xuat p on p.id = d.phieu_id where p.ho_so_id = {hs['id']}") == '400000'
    chup(gd, '056-02-sau-huy')
    ghi('Sau hủy: nhãn "Đã hủy – thu theo thỏa thuận", khách phải trả 1.500.000, tồn kho đèn còn 4 (trả 2), giá vốn xe 400.000 (1 đèn đã dùng)')

    # ---------- 4. Phiếu thu lệch công nợ ----------
    kt = mo(b, 'tien@gara.vn')
    ve_trang(kt, f'#/thu-chi?ho_so={hs["id"]}')
    m = modal(kt)
    expect(m.locator('[name=so_tien]')).to_have_value('1.500.000')
    m.locator('[name=so_tien]').fill('1450000'); m.locator('[name=so_tien]').dispatch_event('input')
    expect(m.locator('.khoi-tra-du')).to_contain_text('Thực thu ít hơn công nợ 50.000')
    m.locator('.khoi-tra-du label', has_text='Thu lệch').click()
    expect(m.locator('textarea[name=ly_do_lech]')).to_be_visible()
    m.locator('.modal-chan .nut.chinh').click()
    expect(kt.locator('#toast')).to_contain_text('ghi lý do lệch', timeout=5000)
    m.locator('textarea[name=ly_do_lech]').fill('Khách xin bớt 50.000')
    chup(kt, '056-03-phieu-thu-lech')
    m.locator('.modal-chan .nut.chinh').click()
    expect(kt.locator('#toast')).to_contain_text('chờ giám đốc / quản lý chung duyệt', timeout=8000)
    ghi('Kế toán: phiếu thu 1.450.000 (công nợ 1.500.000) → chọn "Thu lệch", bắt ghi lý do → lập phiếu, phần lệch chờ duyệt')
    ve_trang(kt, '#/thu-chi')
    expect(kt.locator('#thu-lech')).to_contain_text('Khách xin bớt 50.000')
    expect(kt.locator('#thu-lech')).to_contain_text('−50.000')
    ghi('Trang Thu chi: thẻ "Thu lệch công nợ chờ duyệt (1)"')
    ve_trang(ql, f'#/ho-so/{hs["id"]}')
    khoi = ql.locator('[data-dieu-chinh]')
    expect(khoi).to_contain_text('Chờ duyệt')
    khoi.get_by_role('button', name='Duyệt chỉnh công nợ').click()
    expect(ql.locator('#toast')).to_contain_text('Đã chỉnh công nợ', timeout=8000)
    ve_trang(ql, f'#/ho-so/{hs["id"]}')
    expect(ql.locator('h1 .nhan').first).to_contain_text('Đã đóng')
    expect(ql.locator('[data-dieu-chinh]')).to_contain_text('Đã duyệt')
    chup(ql, '056-04-duyet-thu-lech')
    ghi('Quản lý chung bấm "Duyệt chỉnh công nợ" ở thẻ Tiền → doanh thu giảm 50.000, khách hết nợ, hồ sơ tự đóng')
    assert sql(f"select sum(so_tien) from public.v_doanh_thu where ho_so_id = {hs['id']}") == '1450000'
    ghi('Doanh thu của xe = đúng số thực thu 1.450.000')

    # Bảo hiểm trả thiếu: dòng phân bổ có ô "Lệch"
    hs2 = gd.evaluate("""async () => { const api = await window.__mod('api');
      const kq = await api.tiepNhanXe({ bien_so: '51A-056.12', ten_khach: 'Khách BH 056', dien_thoai: '0909056112', nguon_tt: 'bao_hiem', tinh_trang_xe: 'Cản',
        tu_van: 'Không', qua_detailing: false, han_bao_hiem: '2027-03-01', han_bh_than_vo: '2027-03-01', dong_xe_id: api.dm.dong_xe.find((d) => d.ten === 'VF3').id,
        hang_bh_id: api.dm.hang_bao_hiem.find((x) => x.ten === 'Tasco').id, gdv_id: api.dm.giam_dinh_vien.find((x) => x.ten === 'Hảo').id });
      await api.lapBaoGia(kq.id, [{ ten: 'Gò cản', nhom: 'dong', gia_bao: 1000000 }], 0.08);
      await api.duyetGiaTong(kq.id, new Date().toISOString().slice(0, 10), 1080000, 0);
      return kq; }""")
    ve_trang(kt, f'#/thu-chi?ho_so={hs2["id"]}')
    m = modal(kt)
    o = m.locator(f'[name=pb_{hs2["id"]}]')
    expect(o).to_have_value('1.080.000')
    o.fill('1000000'); o.dispatch_event('input')
    m.locator('[name=so_tien]').fill('1000000')
    expect(m.locator(f'[data-lech="{hs2["id"]}"]')).to_be_visible()
    m.locator(f'[data-lech="{hs2["id"]}"]').check()
    m.locator(f'[name=ly_do_{hs2["id"]}]').fill('Bảo hiểm trừ khấu hao 80.000')
    m.locator('.modal-chan .nut.chinh').click()
    expect(kt.locator('#toast')).to_contain_text('chờ giám đốc / quản lý chung duyệt', timeout=8000)
    assert sql(f"select count(*) from public.de_nghi_dieu_chinh where ho_so_id = {hs2['id']} and nguoi_tra = 'bao_hiem' and cong_no = 1080000 and thuc_thu = 1000000") == '1'
    ghi('Phiếu bảo hiểm trả thiếu 80.000: tích "Lệch – chỉnh công nợ" + lý do → đề nghị chỉnh (bên bảo hiểm) chờ duyệt')
    b.close()

print('\nLỖI TRÌNH DUYỆT:' if loi else '\nKhông có lỗi JavaScript.')
for x in loi:
    print('  ', x)
sys.exit(1 if loi else 0)
