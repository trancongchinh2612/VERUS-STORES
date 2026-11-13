const test=require('node:test'),assert=require('node:assert'),fs=require('fs');
const h=fs.readFileSync('production/index.html','utf8'),sql=fs.readFileSync('production/supabase/migrations/202611080001_verus_checkout_rpc_fix.sql','utf8');
test('direct buy uses its own checkout context and never mutates the cart',()=>{
  assert.match(h,/function checkoutSource\(\)\{return Array\.isArray\(window\.__checkoutCartOverride\)/);
  assert.match(h,/if\(buy===true\)\{closeModal\(\);window\.__checkoutCartOverride=\[/);
  assert.match(h,/function closeModal\(\)\{window\.__checkoutCartOverride=null/);
  assert.match(h,/const cartItemsForServer=\(source=checkoutSource\(\)\)/);
});
test('cart checkout only sends and removes selected items',()=>{
  assert.match(h,/x\.sel!==false/);assert.match(h,/db\.cart=db\.cart\.filter\(x=>!bought\.has\(x\.key\)\)/);
});
test('zalo button is offset above the mobile dock',()=>{assert.match(h,/\.verus-zalo-float\{right:12px;bottom:calc\(66px \+ 14px \+ env\(safe-area-inset-bottom/)});
test('rpc fix migration defines the 11-argument place_order without gen_random_bytes calls',()=>{
  assert.match(sql,/create or replace function public\.place_order\(/);
  assert.doesNotMatch(sql,/encode\(gen_random_bytes/);
  assert.match(sql,/pg_catalog\.gen_random_uuid\(\)/);assert.match(sql,/notify pgrst, 'reload schema'/);assert.doesNotMatch(sql.replace(/--.*/g,''),/drop table|truncate|delete from/i);
});
test('smoke test is present and rolls itself back',()=>{assert.match(sql,/SMOKE TEST PASSED/);assert.match(sql,/raise exception 'SMOKE_OK/)});
test('42883 detail is shown to help diagnose',()=>{assert.match(h,/chi tiết kỹ thuật/)});
