-- VERUS STORE: read-only diagnostics for checkout 42883. Changes nothing. Run each block in the SQL Editor.

-- A) place_order: one row expected, 11 args, SECURITY DEFINER, and its source must NOT contain gen_random_bytes.
select p.oid::regprocedure as signature, p.prosecdef as security_definer, p.proconfig as config,
       position('gen_random_bytes' in pg_get_functiondef(p.oid))>0 as still_uses_gen_random_bytes,
       position('pg_catalog.gen_random_uuid' in pg_get_functiondef(p.oid))>0 as uses_pg_catalog_uuid
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='place_order';

-- B) Overloads / leftovers of the RPCs the website calls.
select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('place_order','track_order','report_deposit_transfer','cancel_my_order','cancel_order_internal',
 'admin_confirm_payment','admin_reject_payment','admin_set_order_status','gen_random_bytes') order by 1::text;

-- C) EXECUTE rights (authenticated must be true for place_order; anon must be false).
select 'place_order' fn, has_function_privilege('anon','public.place_order(jsonb,text,text,text,text,text,text,text,text,integer,text)','execute') anon_ok,
       has_function_privilege('authenticated','public.place_order(jsonb,text,text,text,text,text,text,text,text,integer,text)','execute') authenticated_ok;

-- D) Where is pgcrypto?
select e.extname, n.nspname from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname in ('pgcrypto','uuid-ossp');

-- E) Triggers on the tables checkout writes to (expect create_initial_order_payment + enforce_verus_payment_terms on orders).
select c.relname as table_name, t.tgname, pg_get_triggerdef(t.oid) as def
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and not t.tgisinternal and c.relname in ('orders','order_items','order_events','variant_sizes','profiles','coupons','payments')
order by 1,2;

-- F) Constraints needed for idempotency and unique order code.
select conname, pg_get_constraintdef(oid) from pg_constraint
where conrelid='public.orders'::regclass and contype='u';
select indexname from pg_indexes where schemaname='public' and tablename='orders' and indexname='orders_transfer_reference_uidx';

-- G) Settings read by place_order (missing rows fall back to defaults: lead_days=15).
select key, value from public.site_settings where key in ('lead_days','shipping_fee','free_shipping_threshold','payment_cod_enabled','payment_bank_enabled','redeem_vnd_per_point','max_redeem_percent');

-- H) End-to-end smoke test of place_order (creates nothing: it is rolled back inside the block). Read the NOTICE output.
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
