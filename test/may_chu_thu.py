#!/usr/bin/env python3
"""Máy chủ thử nghiệm cục bộ: phục vụ thư mục web/ và giả lập API Supabase
bằng cách chạy SQL thật trên Postgres cục bộ (qua psql), với đúng vai trò
'authenticated' và auth.uid() của người đang đăng nhập -> phân quyền RLS được thử thật.
Chỉ dùng để kiểm thử, không dùng thật."""
import json, os, re, subprocess, sys
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

GOC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# WEB=web/dist để thử bản đã đóng gói (đường dẫn tính từ thư mục gốc của kho); mặc định chạy thẳng mã nguồn web/
WEB = os.path.join(GOC, os.environ.get('WEB') or 'web')
DB = os.environ.get('DB', 'gara')
# NHO_API=1 (chỉ dùng khi đo tốc độ): nhớ kết quả các lời gọi đọc để lần sau trả ngay, loại thời gian CSDL ra khỏi phép đo giao diện
NHO_API = os.environ.get('NHO_API') == '1'
NHO = {}
TEN_COT = re.compile(r'^[a-z_][a-z0-9_]*$')


def lit(v):
    if v is None:
        return 'NULL'
    if isinstance(v, bool):
        return "'true'" if v else "'false'"
    if isinstance(v, (dict, list)):
        if isinstance(v, list) and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v) and v:
            pass
        s = json.dumps(v, ensure_ascii=False)
        return "'" + s.replace("'", "''") + "'"
    return "'" + str(v).replace("'", "''") + "'"


def cot(c):
    if not TEN_COT.match(c):
        raise ValueError('tên cột không hợp lệ: ' + c)
    return '"' + c + '"'


def chay_sql(sql, user, quan_tri=False, ghi=False):
    claims = json.dumps({'sub': user, 'role': 'authenticated'}) if user else ''
    vai = 'authenticated' if user else 'anon'
    dat_vai = '' if quan_tri else f'set local role {vai};'
    full = (f"begin; {dat_vai} select set_config('request.jwt.claims', {lit(claims)}, true);\n"
            + (f"with x as ({sql}) select '@@KQ@@' || coalesce((select json_agg(j) from x)::text, 'null');\ncommit;" if ghi else
               f"select '@@KQ@@' || coalesce(({sql})::text, 'null');\ncommit;"))
    p = subprocess.run(['psql', '-h', '/tmp', '-U', 'postgres', '-d', DB, '-At', '-v', 'ON_ERROR_STOP=1', '-c', full],
                       capture_output=True, text=True)
    if p.returncode != 0:
        m = re.search(r'ERROR:\s+(.*)', p.stderr)
        return None, {'message': m.group(1).strip() if m else p.stderr.strip(), 'code': 'P0001'}
    for line in p.stdout.splitlines():
        if line.startswith('@@KQ@@'):
            raw = line[6:]
            return (None if raw == 'null' else json.loads(raw)), None
    return None, {'message': 'Không đọc được kết quả'}


def dieu_kien(f):
    op, c, v = f['op'], f.get('cot'), f.get('gt')
    if op == 'or':
        return '(' + ' or '.join(dieu_kien(x) for x in tach_or(v)) + ')'
    if op == 'and':                      # nhóm and(...) lồng trong or(...) như PostgREST
        return '(' + ' and '.join(dieu_kien(x) for x in tach_or(v)) + ')'
    if op == 'not':
        return 'not (' + dieu_kien({'op': f['op2'], 'cot': c, 'gt': v}) + ')'
    C = cot(c)
    if op in ('eq', 'neq', 'gt', 'gte', 'lt', 'lte'):
        so = {'eq': '=', 'neq': '<>', 'gt': '>', 'gte': '>=', 'lt': '<', 'lte': '<='}[op]
        return f"{C}::text {so} {lit(v)}" if not isinstance(v, (int, float)) or isinstance(v, bool) else f"{C} {so} {v}"
    if op == 'ilike':
        return f"{C}::text ilike {lit(v)}"
    if op == 'is':
        return f"{C} is {'null' if v is None else ('true' if v else 'false')}"
    if op == 'in':
        ds = v if isinstance(v, list) else [x.strip().strip('"') for x in str(v).strip('()').split(',')]
        return f"{C}::text in ({','.join(lit(str(x)) for x in ds)})" if ds else 'false'
    raise ValueError('toán tử chưa hỗ trợ: ' + op)


def tach_or(s):
    phan, sau, buf = [], 0, ''
    for ch in s:
        if ch == '(':
            sau += 1
        if ch == ')':
            sau -= 1
        if ch == ',' and sau == 0:
            phan.append(buf); buf = ''
        else:
            buf += ch
    if buf:
        phan.append(buf)
    kq = []
    for p in phan:
        if p.startswith('and(') and p.endswith(')'):
            kq.append({'op': 'and', 'gt': p[4:-1]})
            continue
        c, op, gt = p.split('.', 2)
        if op in ('gt', 'gte', 'lt', 'lte') and re.match(r'^-?\d+(\.\d+)?$', gt):
            gt = float(gt)
        kq.append({'op': op, 'cot': c, 'gt': gt})
    return kq


def doc(q):
    bang = q['bang']
    if not TEN_COT.match(bang):
        raise ValueError('bảng không hợp lệ')
    where = ' and '.join(dieu_kien(f) for f in q.get('loc', [])) or 'true'
    order = ', '.join(f"{cot(o['cot'])} {'asc' if o.get('tang', True) else 'desc'}" for o in q.get('sap', [])) or '1'
    lim = f" limit {int(q['gioi_han'])}" if q.get('gioi_han') else ''
    return f"select json_agg(to_jsonb(t)) from (select * from public.{bang} where {where} order by {order}{lim}) t"


def rpc(ten, ts):
    if not TEN_COT.match(ten):
        raise ValueError('tên hàm không hợp lệ')
    info, _ = chay_sql(f"(select json_build_object('rs', proretset, 'kieu', prorettype::regtype::text, "
                       f"'mang', (select coalesce(json_object_agg(n, t), '{{}}') from unnest(coalesce(proargnames, '{{}}'), proargtypes::regtype[]::text[]) a(n, t) where t like '%[]'))"
                       f" from pg_proc where proname = {lit(ten)} and pronamespace = 'public'::regnamespace limit 1)", None, True)
    if info is None:
        return None, {'message': f'Không có hàm {ten}'}
    # Như PostgREST: mảng JSON gửi vào tham số kiểu mảng Postgres (bigint[], text[]…) đổi thành mảng Postgres
    mang = info.get('mang') or {}
    def gia_tri(k, v):
        if isinstance(v, list) and k in mang:
            return f"(select array_agg(x) from jsonb_array_elements_text({lit(v)}::jsonb) x)::{mang[k]}"
        return lit(v)
    args = ', '.join(f"{cot(k)} => {gia_tri(k, v)}" for k, v in (ts or {}).items())
    if info['kieu'] == 'void':
        return chay_sql(f"(select null::json from (select public.{ten}({args})) x)", TL.user)
    if info['rs'] or info['kieu'] == 'record':
        return chay_sql(f"(select coalesce(json_agg(to_jsonb(r)), '[]') from public.{ten}({args}) r)", TL.user)
    return chay_sql(f"(select to_jsonb(public.{ten}({args})))", TL.user)


import threading
TL = threading.local()


class XuLy(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB, **k)

    def log_message(self, *a):
        pass

    def tra(self, data, err=None):
        body = json.dumps({'data': data, 'error': err}, ensure_ascii=False).encode()
        if NHO_API and getattr(self, 'khoa_nho', None) and err is None:
            NHO[self.khoa_nho] = body
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        q = json.loads(self.rfile.read(n) or b'{}')
        TL.user = q.get('user')
        if NHO_API and self.path in ('/api/doc', '/api/rpc', '/api/dang-nhap'):
            self.khoa_nho = (self.path, json.dumps(q, sort_keys=True))
            if self.khoa_nho in NHO:
                body = NHO[self.khoa_nho]
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
        try:
            if self.path == '/api/dang-nhap':
                # Tài khoản có mật khẩu thật (tạo trong phần mềm) thì kiểm mật khẩu; tài khoản thử cũ thì bỏ qua
                d, e = chay_sql(f"(select to_jsonb(u) from (select id, email from auth.users where email = {lit(q['email'])}"
                                f" and (encrypted_password is null or encrypted_password = extensions.crypt({lit(q.get('mat_khau') or '')}, encrypted_password))) u)", None, True)
                return self.tra(d, e if e else (None if d else {'message': 'Invalid login credentials'}))
            if self.path == '/api/doi-mat-khau':
                d, e = chay_sql(f"update auth.users set encrypted_password = extensions.crypt({lit(q.get('mat_khau') or '')}, extensions.gen_salt('bf'))"
                                f" where id = {lit(q.get('user'))}::uuid returning 1 as j", None, True, ghi=True)
                return self.tra({'ok': True}, e)
            if self.path == '/api/doc':
                d, e = chay_sql('(' + doc(q) + ')', TL.user)
                return self.tra(d or [], e)
            if self.path == '/api/rpc':
                d, e = rpc(q['ham'], q.get('ts'))
                return self.tra(d, e)
            if self.path == '/api/them':
                bang = q['bang']; dong = q['dong'] if isinstance(q['dong'], list) else [q['dong']]
                sqls = []
                for r in dong:
                    cols = ', '.join(cot(k) for k in r)
                    vals = ', '.join(lit(v) for v in r.values())
                    sqls.append(f"insert into public.{bang} ({cols}) values ({vals}) returning to_jsonb({bang}.*) j")
                d, e = chay_sql(sqls[0], TL.user, ghi=True)
                return self.tra(d, e)
            if self.path == '/api/sua':
                bang = q['bang']
                sets = ', '.join(f"{cot(k)} = {lit(v)}" for k, v in q['gt'].items())
                where = ' and '.join(dieu_kien(f) for f in q['loc'])
                d, e = chay_sql(f"update public.{bang} set {sets} where {where} returning to_jsonb({bang}.*) j", TL.user, ghi=True)
                return self.tra(d or [], e)
            if self.path == '/api/tai-len':
                return self.tra({'path': q['duong_dan']})
            self.send_error(404)
        except Exception as ex:
            return self.tra(None, {'message': str(ex)})


if __name__ == '__main__':
    cong = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f'http://127.0.0.1:{cong}')
    ThreadingHTTPServer(('127.0.0.1', cong), XuLy).serve_forever()
