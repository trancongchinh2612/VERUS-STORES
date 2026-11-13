-- VERUS STORE: checkout RPC repair for PostgreSQL 42883 (undefined_function).
-- File: 202611080001_verus_checkout_rpc_fix.sql
-- Run AFTER 202611040001..202611070003 have been applied, ideally on staging first.
--
-- WHY THIS EXISTS
--   The original place_order (migrations 202611040002 and 202611060003) calls
--   gen_random_bytes(5) while its search_path is only "public,auth". On Supabase the
--   pgcrypto functions live in schema "extensions", so the call fails with 42883.
--   The fixed place_order lives in 202611070002. If that migration was never applied
--   (or was applied only in part), the database still runs the old function and the
--   website keeps getting 42883. This migration re-applies the final function on its
--   own, with a precondition check, so one run converges the database.
--
-- SAFETY
--   * No DROP TABLE / TRUNCATE / DELETE. Existing orders are untouched.
--   * Idempotent: safe to run again.
--   * Everything runs in one transaction: if the precondition check fails, nothing changes.
--   * No secret keys are used. Needs a role that owns public.* (SQL Editor "postgres").
--
-- ROLLBACK
--   Re-run 202611060003_order_payment_safety.sql to restore the previous place_order.
--   That version is the one that triggers 42883, so only do it for diagnosis.

begin;

-- 1) Precondition check: list everything place_order needs and stop with a clear message.
do $$
declare missing text := '';
  need_cols text[][] := array[
    ['orders','code'],['orders','user_id'],['orders','customer_name'],['orders','phone'],
    ['orders','province'],['orders','ward'],['orders','street'],['orders','note'],['orders','status'],
    ['orders','deposit_status'],['orders','pay_method'],['orders','subtotal'],['orders','shipping_fee'],
    ['orders','discount'],['orders','points_discount'],['orders','total'],['orders','deposit_percent'],
    ['orders','deposit_amount'],['orders','balance_amount'],['orders','coupon_code'],['orders','points_used'],
    ['orders','idempotency_key'],['orders','eta_date'],
    ['order_items','order_id'],['order_items','product_id'],['order_items','variant_id'],['order_items','product_name'],
    ['order_items','variant_name'],['order_items','sku'],['order_items','size'],['order_items','qty'],
    ['order_items','price'],['order_items','line_total'],
    ['order_events','order_id'],['order_events','status'],['order_events','note'],['order_events','created_by'],
    ['variant_sizes','variant_id'],['variant_sizes','size'],['variant_sizes','stock'],
    ['product_variants','product_id'],['products','price'],['products','status'],
    ['coupons','code'],['coupons','active'],['coupons','starts_at'],['coupons','ends_at'],['coupons','usage_limit'],
    ['coupons','used_count'],['coupons','per_user_limit'],['coupons','min_subtotal'],['coupons','kind'],
    ['coupons','value'],['coupons','max_discount'],['profiles','points'],['site_settings','key'],['site_settings','value']
  ];
  i int;
begin
  for i in 1..array_length(need_cols,1) loop
    if not exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=need_cols[i][1] and column_name=need_cols[i][2]) then
      missing := missing || ' ' || need_cols[i][1] || '.' || need_cols[i][2];
    end if;
  end loop;
  if missing <> '' then
    raise exception 'VERUS_PRECONDITION_FAILED: missing columns:%. Apply migrations 202611040001..202611060003 first.', missing;
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                 where n.nspname='public' and p.proname='cancel_order_internal') then
    raise notice 'WARNING: public.cancel_order_internal is missing. Run 202611060003_order_payment_safety.sql (customer cancel will fail until then).';
  end if;
end $$;

-- 2) Stable transfer reference column used by place_order / track_order (same definition as 202611070002).
alter table public.orders
  add column if not exists transfer_reference text
  generated always as ('VERUS ' || right(upper(replace(code, '-', '')), 16)) stored;
create unique index if not exists orders_transfer_reference_uidx on public.orders(transfer_reference);

-- 3) Final place_order. Same signature the frontend calls (11 arguments):
--    place_order(jsonb,text,text,text,text,text,text,text,text,integer,text)
--    Uses pg_catalog.gen_random_uuid() so it no longer depends on pgcrypto / search_path.
create or replace function public.place_order(
 p_items jsonb,p_name text,p_phone text,p_province text,p_ward text,p_street text,p_note text,
 p_pay_method text,p_coupon text default null,p_points integer default 0,p_idem text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare
 uid uuid:=auth.uid(); item jsonb; vr public.product_variants%rowtype; pr public.products%rowtype;
 sz public.variant_sizes%rowtype; q integer; sub bigint:=0; ship bigint:=0; disc bigint:=0;
 total bigint; dep_pct numeric:=20; dep bigint; bal bigint; code text; oid uuid; transfer_ref text; token text;
 coupon public.coupons%rowtype; lead_days integer:=15; points_used_actual integer:=0;
 pay_enabled boolean; pts integer:=0; points_disc bigint:=0; vnd_point bigint:=500; max_redeem numeric:=30;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' or coalesce(trim(p_province),'')='' or coalesce(trim(p_ward),'')='' or coalesce(trim(p_street),'')='' then raise exception 'INVALID_ADDRESS'; end if;
 if p_pay_method not in ('cod_balance','bank_transfer_full') then raise exception 'INVALID_PAYMENT_METHOD'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART'; end if;
 if coalesce(p_points,0)<0 then raise exception 'INVALID_POINTS'; end if;
 if p_idem is not null then
   select id,orders.code,orders.total,orders.deposit_percent,orders.deposit_amount,orders.balance_amount,orders.transfer_reference
   into oid,code,total,dep_pct,dep,bal,transfer_ref from public.orders where user_id=uid and idempotency_key=p_idem;
   if found then return jsonb_build_object('id',oid,'code',code,'transfer_reference',transfer_ref,'total',total,'deposit_percent',dep_pct,'deposit',dep,'balance',bal); end if;
 end if;
  select coalesce((value#>>'{}')::integer,15) into lead_days from public.site_settings where key='lead_days';
 select coalesce((value#>>'{}')::boolean,true) into pay_enabled from public.site_settings where key=case when p_pay_method='cod_balance' then 'payment_cod_enabled' else 'payment_bank_enabled' end;
 if not coalesce(pay_enabled,true) then raise exception 'PAYMENT_METHOD_DISABLED'; end if;
 for item in
   select jsonb_build_object('variant_id',x->>'variant_id','size',coalesce(x->>'size','Free Size'),'qty',sum(coalesce((x->>'qty')::integer,0)))
   from jsonb_array_elements(p_items) x group by x->>'variant_id',coalesce(x->>'size','Free Size')
 loop
   q:=coalesce((item->>'qty')::integer,0);
   if q<1 then raise exception 'INVALID_QTY'; end if;
   select * into vr from public.product_variants where id=(item->>'variant_id')::uuid for update;
   if not found then raise exception 'ITEM_NOT_FOUND'; end if;
   select * into pr from public.products where id=vr.product_id and status='active';
   if not found then raise exception 'PRODUCT_UNAVAILABLE'; end if;
   select * into sz from public.variant_sizes where variant_id=vr.id and size=coalesce(item->>'size','Free Size') for update;
   if not found or sz.stock<q then raise exception 'OUT_OF_STOCK'; end if;
   sub:=sub+(pr.price*q);
 end loop;
 if p_coupon is not null and trim(p_coupon)<>'' then
   select * into coupon from public.coupons where code=upper(trim(p_coupon)) and active for update;
   if not found then raise exception 'COUPON_INVALID'; end if;
   if (coupon.starts_at is not null and now()<coupon.starts_at) or (coupon.ends_at is not null and now()>coupon.ends_at) then raise exception 'COUPON_EXPIRED'; end if;
   if coupon.usage_limit is not null and coupon.used_count>=coupon.usage_limit then raise exception 'COUPON_EXHAUSTED'; end if;
   if (select count(*) from public.orders where user_id=uid and coupon_code=coupon.code and status<>'cancelled')>=coupon.per_user_limit then raise exception 'COUPON_USER_LIMIT'; end if;
   if sub<coupon.min_subtotal then raise exception 'COUPON_MIN'; end if;
   if coupon.kind='percent' then disc:=floor(sub*coupon.value/100.0)::bigint;
   elsif coupon.kind='fixed' then disc:=coupon.value;
   end if;
   if coupon.max_discount is not null then disc:=least(disc,coupon.max_discount); end if;
   disc:=least(disc,sub);
 end if;
 select points into pts from public.profiles where id=uid for update;
 select coalesce((value#>>'{}')::bigint,500) into vnd_point from public.site_settings where key='redeem_vnd_per_point';
 select coalesce((value#>>'{}')::numeric,30) into max_redeem from public.site_settings where key='max_redeem_percent';
 if coalesce(p_points,0)>0 then
   if p_points>coalesce(pts,0) then raise exception 'NOT_ENOUGH_POINTS'; end if;
   points_disc:=least(p_points*vnd_point, floor((sub-disc)*max_redeem/100.0)::bigint);
   points_used_actual:=floor(points_disc/greatest(vnd_point,1))::integer;
 end if;
 total:=greatest(0,sub-disc-points_disc); -- free shipping for every order
 if p_pay_method='bank_transfer_full' then dep_pct:=100; dep:=total; bal:=0;
 else dep_pct:=20; dep:=ceil(total*0.20)::bigint; bal:=total-dep; end if;
 -- Use PostgreSQL's cryptographically secure UUID generator directly.
 token:=replace(pg_catalog.gen_random_uuid()::text,'-','');
 code:='VS-'||to_char(now(),'YYMMDD')||'-'||upper(substr(token,1,12)||substr(token,29,4));
 transfer_ref:='VERUS '||right(upper(replace(code,'-','')),16);
 insert into public.orders(code,user_id,customer_name,phone,province,ward,street,note,status,deposit_status,pay_method,subtotal,shipping_fee,discount,points_discount,total,deposit_percent,deposit_amount,balance_amount,coupon_code,points_used,idempotency_key,eta_date)
 values(code,uid,trim(p_name),p_phone,trim(p_province),trim(p_ward),trim(p_street),nullif(trim(coalesce(p_note,'')),''),'pending','unpaid',p_pay_method,sub,0,disc,points_disc,total,dep_pct,dep,bal,nullif(upper(trim(coalesce(p_coupon,''))),''),points_used_actual,p_idem,current_date+lead_days)
 returning id into oid;
 for item in select * from jsonb_array_elements(p_items) loop
   q:=(item->>'qty')::integer;
   select * into vr from public.product_variants where id=(item->>'variant_id')::uuid;
   select * into pr from public.products where id=vr.product_id;
   select * into sz from public.variant_sizes where variant_id=vr.id and size=coalesce(item->>'size','Free Size') for update;
   update public.variant_sizes set stock=stock-q where id=sz.id;
   insert into public.order_items(order_id,product_id,variant_id,product_name,variant_name,sku,size,qty,price,line_total)
   values(oid,pr.id,vr.id,pr.name,vr.name,vr.sku,sz.size,q,pr.price,pr.price*q);
 end loop;
 insert into public.order_events(order_id,status,note,created_by) values(oid,'pending','Đơn hàng được tạo',uid);
 if p_coupon is not null and trim(p_coupon)<>'' then update public.coupons set used_count=used_count+1 where id=coupon.id; end if;
 if points_used_actual>0 then update public.profiles set points=points-points_used_actual where id=uid; end if;
 return jsonb_build_object('id',oid,'code',code,'transfer_reference',transfer_ref,'total',total,'deposit_percent',dep_pct,'deposit',dep,'balance',bal);
end $$;

-- 4) Remove the old compatibility shim public.gen_random_bytes if (and only if) it is not owned by an extension.
do $$
declare f oid;
begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='gen_random_bytes' and p.pronargs=1 and p.proargtypes[0]='integer'::regtype;
  if f is not null and not exists (select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=f and d.deptype='e') then
    execute 'drop function public.gen_random_bytes(integer)';
  end if;
end $$;

-- 5) Grants: only signed-in customers may call checkout; anon/public may not.
revoke all on function public.place_order(jsonb,text,text,text,text,text,text,text,text,integer,text) from public, anon;
grant execute on function public.place_order(jsonb,text,text,text,text,text,text,text,text,integer,text) to authenticated;

-- 6) Smoke test: calls place_order as the first auth user with 1 in-stock item, then rolls the test back.
--    Read the NOTICE line in the SQL Editor output: PASSED / FAILED (with sqlstate and message) / SKIPPED.
do $$
declare uid uuid; v uuid; s text; r jsonb;
begin
  select id into uid from auth.users order by created_at limit 1;
  select variant_id, size into v, s from public.variant_sizes where stock > 0 limit 1;
  if uid is null or v is null then
    raise notice 'SMOKE TEST SKIPPED: no auth user or no in-stock variant.';
    return;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  begin
    r := public.place_order(
      jsonb_build_array(jsonb_build_object('variant_id', v, 'size', s, 'qty', 1)),
      'SMOKE TEST', '0900000000', 'Ha Noi', 'Phuong Test', '1 Test', null, 'cod_balance', null, 0, 'smoke-' || pg_catalog.gen_random_uuid()::text);
    -- Force the inner block to roll back so the test order, stock change and payment row are NOT kept.
    raise exception 'SMOKE_OK %', r;
  exception when others then
    if sqlerrm like 'SMOKE_OK%' then
      raise notice 'SMOKE TEST PASSED (rolled back, nothing saved): %', sqlerrm;
    else
      raise notice 'SMOKE TEST FAILED: sqlstate=% message=%', sqlstate, sqlerrm;
    end if;
  end;
end $$;

-- 7) Make PostgREST forget any cached (stale) function list.
notify pgrst, 'reload schema';

commit;

-- 8) Verification: run 202611080002_verus_checkout_diagnostics.sql afterwards.
