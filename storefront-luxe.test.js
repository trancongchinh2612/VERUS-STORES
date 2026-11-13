// Kiểm thử lớp giao diện VERUS LUXE trên trang khách hàng (index.html).
// Mục tiêu: nâng cấp giao diện KHÔNG được chạm vào nghiệp vụ (Supabase, giỏ hàng,
// thanh toán, đơn hàng). Chạy: npm test
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const before = fs.readFileSync(path.join(root, 'backup/index-truoc-nang-cap-luxe.html'), 'utf8');

const scripts = s => [...s.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[0]);
const luxeStart = html.indexOf('<!-- VERUS LUXE START');
const luxeEnd = html.indexOf('<!-- VERUS LUXE END -->');
const luxe = html.slice(luxeStart, luxeEnd);
const luxeJs = (luxe.match(/<script id="verus-luxe-fx">([\s\S]*?)<\/script>/) || [])[1] || '';
const luxeCode = luxeJs.replace(/\/\*[\s\S]*?\*\//g, '');

test('các luồng cửa hàng và thanh toán cốt lõi vẫn có mặt sau khi nâng cấp QR', () => {
  const original = scripts(before);
  assert.ok(original.length >= 15, 'bản sao lưu phải chứa các script gốc');
  for (const marker of ['place_order', 'report_deposit_transfer', 'window.verusPaymentPanel', 'window.vOrder', 'window.trackOrderResult']) {
    assert.ok(html.includes(marker), 'thiếu luồng cốt lõi: ' + marker);
  }
  assert.match(html, /window\.verusPaymentPanel=function\(orderId,amount,memo,title\)/);
});

test('lớp LUXE xuất hiện đúng một lần và nằm sau mọi style/script gốc', () => {
  assert.equal(html.split('<!-- VERUS LUXE START').length - 1, 1);
  assert.ok(luxeStart > 0 && luxeEnd > luxeStart);
  assert.ok(luxeStart > html.lastIndexOf('VERUS payment UX v1'), 'lớp giao diện phải đứng cuối để thắng cascade');
});

test('lớp LUXE không gọi mạng, không đọc/ghi dữ liệu, không đụng thanh toán', () => {
  assert.ok(luxeJs.length > 500);
  assert.doesNotMatch(luxeCode, /fetch\(|XMLHttpRequest|WebSocket|sendBeacon|supabase|localStorage|sessionStorage|indexedDB|document\.cookie/i);
  assert.doesNotMatch(luxeCode, /place_order|report_deposit_transfer|checkout|db\.cart|db\.orders|payment/i);
});

test('nút trên banner vẫn gọi đúng các hàm có sẵn', () => {
  const hero = html.slice(html.indexOf('<section class="hero lx-hero"'), html.indexOf('</section>', html.indexOf('<section class="hero lx-hero"')));
  for (const call of ["vCat('Áo')", "vCat('Quần')", "vCat('Giày')", 'showCoupons()', "getElementById('productArea').scrollIntoView"]) {
    assert.ok(hero.includes(call), 'thiếu thao tác: ' + call);
  }
  assert.match(hero, /id="hero3d"/);
  assert.match(hero, /class="h3d-stage"/);
});

test('nút danh mục 3D không nằm trong vùng aria-hidden (đọc được bằng trình đọc màn hình)', () => {
  assert.doesNotMatch(html, /<div class="hero3d" id="hero3d" aria-hidden="true">/);
  assert.match(html, /<button class="h3d-card c1"[^>]*aria-label="Xem danh mục Áo"/);
});

test('hiệu ứng tôn trọng chế độ giảm chuyển động', () => {
  assert.match(luxe, /@media \(prefers-reduced-motion:reduce\)/);
  assert.match(luxeJs, /prefers-reduced-motion: reduce/);
});

test('nội dung không bị ẩn vĩnh viễn nếu JavaScript không chạy', () => {
  // Trạng thái ẩn chờ hiệu ứng chỉ áp dụng khi script đã gắn class lux-js.
  const hiddenRules = [...luxe.matchAll(/([^}{]*)\{[^}]*opacity:0[;}]/g)].map(m => m[1].trim());
  for (const sel of hiddenRules.filter(s => s.includes('.lx-rv'))) assert.match(sel, /html\.lux-js/);
});

test('không thêm sản phẩm hay đánh giá giả trong lớp giao diện', () => {
  assert.doesNotMatch(luxe, /★|đánh giá 5 sao|\d+\s*(khách hàng|đơn đã bán)|testimonial/i);
});

test('QR động dùng số tiền máy chủ trả về, nội dung chuyển khoản và cấu hình ngân hàng', () => {
  assert.ok(html.includes('img.vietqr.io/image/'));
  assert.ok(html.includes('amount=\'+encodeURIComponent(String(amt))'));
  assert.ok(html.includes('addInfo=\'+encodeURIComponent(safeMemo)'));
  assert.match(html, /const amt=Math\.round\(Number\(amount\)\|\|0\)/);
  assert.match(html, /deposit_amount\|\|0/);
  assert.match(html, /Chưa thể tạo QR thanh toán/);
  assert.match(html, /Shop vẫn phải đối soát giao dịch thực tế/);
  const helper = html.match(/window\.verusPaymentPanel=function\(orderId,amount,memo,title\)\{[\s\S]*?\n\};/);
  assert.ok(helper, 'phải có hàm tạo QR động');
  const ctx = { window: { VERUS_CONFIG: { BANK_BIN: '970407', BANK_ACCOUNT_NUMBER: '19072227509017', BANK_ACCOUNT_NAME: 'DANG THI HUONG', BANK_NAME: 'Techcombank' } }, money: n => String(n), esc: s => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;').replace(/'/g,'&#39;') };
  vm.createContext(ctx); vm.runInContext(helper[0], ctx);
  const panel = ctx.window.verusPaymentPanel('order-123', 250000, 'VERUS VS202611140001', 'Tiền cọc');
  assert.ok(panel.includes('amount=250000'), 'QR phải chứa đúng số tiền');
  assert.ok(panel.includes('addInfo=VERUS%20VS202611140001'), 'QR phải chứa mã tham chiếu đã mã hóa');
  assert.ok(panel.includes('img.vietqr.io/image/970407-19072227509017-compact2.png'), 'QR phải dùng cấu hình ngân hàng');
  assert.ok(!panel.includes('Chưa thể tạo QR thanh toán'), 'cấu hình hợp lệ phải tạo được markup QR');
  const invalid = { window: { VERUS_CONFIG: {} }, money: n => String(n), esc: s => String(s) };
  vm.createContext(invalid); vm.runInContext(helper[0], invalid);
  assert.ok(invalid.window.verusPaymentPanel('order-123', 250000, 'VERUS TEST', 'Tiền cọc').includes('Chưa thể tạo QR thanh toán'), 'cấu hình thiếu phải chặn QR');
});

test('cấu hình công khai không chứa khóa bí mật', () => {
  const config = fs.readFileSync(path.join(root, 'config.js'), 'utf8');
  assert.doesNotMatch(config, /sb_secret_/i);
  for (const jwt of config.match(/eyJ[\w-]+\.[\w-]+\.[\w-]+/g) || []) {
    const payload = Buffer.from(jwt.split('.')[1], 'base64url').toString('utf8');
    assert.doesNotMatch(payload, /service_role/);
  }
});
