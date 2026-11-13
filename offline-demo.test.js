const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const p=fs.readFileSync('index.html','utf8');
test('offline storefront excludes Supabase runtime and OAuth',()=>{assert.doesNotMatch(p,/supabase\.createClient|signInWithOAuth|place_order/);});
test('demo checkout stores locally and calculates 20/80',()=>{assert.match(p,/depositPercent:method==='COD'\?20:100/);assert.match(p,/Math\.ceil\(total\*\.2\)/);assert.match(p,/state\.orders\.unshift\(order\)/);assert.match(p,/await persist\(\)/);});
test('Zalo is an icon action and 20 percent policy exists',()=>{assert.match(p,/class="iconbtn zalo"[\s\S]*?<svg/);assert.match(p,/COD: Đặt cọc 20%/);assert.doesNotMatch(p,/đặt cọc 30%|cọc 30%/i);});
test('no real payment API is called',()=>{assert.doesNotMatch(p,/fetch\(|XMLHttpRequest|vietqr|stripe|paypal/i);});
