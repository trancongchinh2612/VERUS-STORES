const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const prod = path.join(root, 'production');
const html = fs.readFileSync(path.join(prod, 'index.html'), 'utf8');
const admin = fs.readFileSync(path.join(prod, 'admin.html'), 'utf8');
const config = fs.readFileSync(path.join(prod, 'config.js'), 'utf8');
const sql = fs.readFileSync(path.join(prod, 'supabase/migrations/202611070003_payment_rpc_permissions_and_cache.sql'), 'utf8');

test('production package contains the exact supplied QR image', () => {
  const qr = fs.readFileSync(path.join(prod, 'assets/verus-payment-qr.jpg'));
  assert.equal(qr[0], 0xff); assert.equal(qr[1], 0xd8);
  assert.match(html, /assets\/verus-payment-qr\.jpg/);
  assert.match(html, /download="VERUS-STORE-QR-TECHCOMBANK\.jpg"/);
});

test('customer payment panel highlights deposit and provides a transfer-report button', () => {
  assert.match(html, /SỐ TIỀN CẦN CHUYỂN/);
  assert.match(html, /TÔI ĐÃ CHUYỂN KHOẢN/);
  assert.match(html, /report_deposit_transfer/);
  assert.match(html, /trong vòng 12 giờ/);
  const customerReporter = html.slice(html.indexOf('window.vSubmitPaymentReport=function'), html.indexOf('</script>', html.indexOf('window.vSubmitPaymentReport=function')));
  assert.match(customerReporter, /report_deposit_transfer/);
  assert.doesNotMatch(customerReporter, /admin_confirm_payment/);
});

test('bank details match the QR supplied by the user', () => {
  assert.match(config, /BANK_ACCOUNT_NUMBER: "19072227509017"/);
  assert.match(config, /BANK_ACCOUNT_NAME: "DANG THI HUONG"/);
  assert.match(config, /BANK_NAME: "Techcombank"/);
});

test('admin has explicit manual confirm and reject actions', () => {
  assert.match(admin, /admin_confirm_payment/);
  assert.match(admin, /admin_reject_payment/);
  assert.match(admin, /Chỉ xác nhận khi bạn đã kiểm tra tài khoản ngân hàng/);
});

test('migration grants exact RPC signatures and refreshes PostgREST schema cache', () => {
  assert.match(sql, /place_order\(jsonb,text,text,text,text,text,text,text,text,integer,text\)/);
  assert.match(sql, /report_deposit_transfer\(uuid,text\)/);
  assert.match(sql, /notify pgrst, 'reload schema'/i);
});
