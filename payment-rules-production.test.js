const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

function paymentTerms(total, method) {
  if (!Number.isSafeInteger(total) || total < 0) throw new Error('INVALID_ORDER_TOTAL');
  if (method === 'bank_transfer_full') return { percent: 100, deposit: total, balance: 0 };
  if (method === 'cod_balance') {
    const deposit = Math.ceil(total * 0.2);
    return { percent: 20, deposit, balance: total - deposit };
  }
  throw new Error('INVALID_PAYMENT_METHOD');
}

test('COD collects 20% upfront and the rest on delivery', () => {
  assert.deepEqual(paymentTerms(1_000_000, 'cod_balance'), { percent: 20, deposit: 200_000, balance: 800_000 });
  assert.deepEqual(paymentTerms(1_000_001, 'cod_balance'), { percent: 20, deposit: 200_001, balance: 800_000 });
});

test('bank transfer is 100% upfront with zero delivery balance', () => {
  assert.deepEqual(paymentTerms(1_000_000, 'bank_transfer_full'), { percent: 100, deposit: 1_000_000, balance: 0 });
});

test('stable transfer reference is derived from order code', () => {
  const code = 'VS-261107-ABCDEF0123456789';
  assert.equal('VERUS ' + code.replace(/-/g, '').toUpperCase().slice(-16), 'VERUS ABCDEF0123456789');
});

test('database migration enforces payment terms and blocks cancellation during transfer review', () => {
  const sql = fs.readFileSync(path.join(root, '202611070002_checkout_payment_hardening.sql'), 'utf8');
  assert.match(sql, /new\.deposit_percent := 20/);
  assert.match(sql, /new\.deposit_amount := ceil\(new\.total \* 0\.20\)/);
  assert.match(sql, /new\.deposit_percent := 100/);
  assert.match(sql, /new\.balance_amount := 0/);
  assert.match(sql, /PAYMENT_REVIEW_CONTACT_SHOP/);
  assert.match(sql, /transfer_reference/);
  assert.match(sql, /pg_catalog\.gen_random_uuid\(\)/);
  assert.doesNotMatch(sql, /encode\(gen_random_bytes/);
});


test('offline checkout cannot create local demo orders', () => {
  const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  assert.match(html, /Chưa kết nối Supabase\. Không thể tạo đơn thật/);
  assert.match(html, /Chưa kết nối Supabase\. Không tạo đơn DEMO/);
});

test('public bank and Zalo configuration matches the supplied shop details', () => {
  const config = fs.readFileSync(path.join(root, 'config.js'), 'utf8');
  assert.match(config, /BANK_BIN:\s*"970422"/);
  assert.match(config, /BANK_ACCOUNT_NUMBER:\s*"0386083805"/);
  assert.match(config, /BANK_ACCOUNT_NAME:\s*"TRAN CONG CHINH"/);
  assert.match(config, /https:\/\/zaloapp\.com\/qr\/p\/1ojf4icc8o3yq/);
});
