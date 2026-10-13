// Bản giả lập supabase-js CHỈ DÙNG KHI KIỂM THỬ: nói chuyện với test/may_chu_thu.py.
// Hỗ trợ đúng phần giao diện đang dùng: auth, from().select()/insert()/update() + bộ lọc, rpc(), storage.
let user = JSON.parse(localStorage.getItem('gia_user') || 'null');
const nghe = [];
const goi = async (duong, body) => {
  const r = await fetch(duong, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...body, user: user?.id }) });
  return r.json();
};
const phat = (sk) => { const s = user ? { user } : null; nghe.forEach((cb) => cb(sk, s)); };

class Truy {
  constructor(bang) { this.q = { bang, loc: [], sap: [] }; this.kieu = 'doc'; }
  select() { return this; }
  insert(dong) { this.kieu = 'them'; this.dong = dong; return this; }
  update(gt) { this.kieu = 'sua'; this.gt = gt; return this; }
  _l(op, cot, gt) { this.q.loc.push({ op, cot, gt }); return this; }
  eq(c, v) { return this._l('eq', c, v); }
  neq(c, v) { return this._l('neq', c, v); }
  gt(c, v) { return this._l('gt', c, v); }
  gte(c, v) { return this._l('gte', c, v); }
  lt(c, v) { return this._l('lt', c, v); }
  lte(c, v) { return this._l('lte', c, v); }
  ilike(c, v) { return this._l('ilike', c, v); }
  is(c, v) { return this._l('is', c, v); }
  in(c, v) { return this._l('in', c, v); }
  or(s) { this.q.loc.push({ op: 'or', gt: s }); return this; }
  not(c, op, v) { this.q.loc.push({ op: 'not', op2: op, cot: c, gt: v }); return this; }
  order(c, o = {}) { this.q.sap.push({ cot: c, tang: o.ascending !== false }); return this; }
  limit(n) { this.q.gioi_han = n; return this; }
  single() { this.motDong = true; return this; }
  maybeSingle() { this.motDong = true; return this; }
  then(ok, loi) {
    let p;
    if (this.kieu === 'them') p = goi('/api/them', { bang: this.q.bang, dong: this.dong });
    else if (this.kieu === 'sua') p = goi('/api/sua', { bang: this.q.bang, gt: this.gt, loc: this.q.loc });
    else p = goi('/api/doc', this.q);
    return p.then((r) => (this.motDong && r.data ? { data: r.data[0] ?? null, error: r.error } : r)).then(ok, loi);
  }
}

export function createClient() {
  return {
    auth: {
      async signInWithPassword({ email, password }) {
        const r = await goi('/api/dang-nhap', { email, mat_khau: password });
        if (r.error) return { data: null, error: r.error };
        user = r.data; localStorage.setItem('gia_user', JSON.stringify(user));
        setTimeout(() => phat('SIGNED_IN'), 0);
        return { data: { user, session: { user } }, error: null };
      },
      async signOut() { user = null; localStorage.removeItem('gia_user'); phat('SIGNED_OUT'); return { error: null }; },
      async getSession() { return { data: { session: user ? { user } : null } }; },
      onAuthStateChange(cb) { nghe.push(cb); return { data: { subscription: { unsubscribe() {} } } }; },
      async resetPasswordForEmail() { return { error: null }; },
      async updateUser({ password } = {}) {
        if (password) { const r = await goi('/api/doi-mat-khau', { mat_khau: password }); if (r.error) return { error: r.error }; }
        return { error: null };
      },
    },
    from: (bang) => new Truy(bang),
    rpc: (ham, ts) => goi('/api/rpc', { ham, ts }),
    storage: {
      from: () => ({
        async upload(duongDan) { return goi('/api/tai-len', { duong_dan: duongDan }); },
        async createSignedUrl() { return { data: { signedUrl: '/test-anh.svg' }, error: null }; },
        // Giả lập: ảnh nhỏ (.nho.jpg) có link riêng để kiểm thử chọn đúng ảnh nhỏ
        async createSignedUrls(ds) {
          return { data: ds.map((p) => ({ path: p, signedUrl: p.endsWith('.nho.jpg') ? '/test-anh.svg?nho' : '/test-anh.svg', error: null })), error: null };
        },
      }),
    },
  };
}
