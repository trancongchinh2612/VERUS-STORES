-- VERUS STORE checkout/payment hardening (run after 202611070001_v13_hardening.sql).
-- No privileged credentials are used. Safe to re-run.

-- One stable transfer reference derived from the immutable order code.
alter table public.orders
  add column if not exists transfer_reference text
  generated always as ('VERUS ' || right(upper(replace(code, '-', '')), 16)) stored;
create unique index if not exists orders_transfer_reference_uidx
  on public.orders(transfer_reference);

-- Redefine checkout to use pg_catalog.gen_random_uuid directly (64-bit suffix),
-- return the server-derived transfer reference, and enforce fixed 20% / 100% terms.
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

-- Remove the old V13 compatibility shim if it is not owned by an extension.
do $$
declare f oid;
begin
  select p.oid into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='gen_random_bytes' and p.pronargs=1 and p.proargtypes[0]='integer'::regtype;
  if f is not null and not exists (select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=f and d.deptype='e') then
    execute 'drop function public.gen_random_bytes(integer)';
  end if;
end $$;

-- Enforce the agreed payment terms at the database boundary, even if another
-- client or a future RPC supplies incorrect deposit fields.
create or replace function public.enforce_verus_payment_terms()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.total is null or new.total < 0 then
    raise exception 'INVALID_ORDER_TOTAL';
  end if;
  if new.pay_method = 'bank_transfer_full' then
    new.deposit_percent := 100;
    new.deposit_amount := new.total;
    new.balance_amount := 0;
  elsif new.pay_method = 'cod_balance' then
    new.deposit_percent := 20;
    new.deposit_amount := ceil(new.total * 0.20)::bigint;
    new.balance_amount := new.total - new.deposit_amount;
  else
    raise exception 'INVALID_PAYMENT_METHOD';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_verus_payment_terms on public.orders;
create trigger trg_enforce_verus_payment_terms
before insert or update of total, pay_method, deposit_percent, deposit_amount, balance_amount
on public.orders
for each row execute function public.enforce_verus_payment_terms();

-- Public tracking only returns customer-safe details. Include the exact transfer
-- reference shown by checkout so the customer can recover it after closing QR.
create or replace function public.track_order(p_code text,p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  o public.orders%rowtype;
  item_data jsonb;
  event_data jsonb;
begin
  if coalesce(trim(p_code),'')='' or length(regexp_replace(coalesce(p_phone,''),'\D','','g')) < 9 then
    return null;
  end if;

  select * into o
  from public.orders
  where upper(code)=upper(trim(p_code))
    and regexp_replace(phone,'\D','','g')=regexp_replace(coalesce(p_phone,''),'\D','','g')
  limit 1;
  if not found then return null; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',i.id,'name',i.product_name,'variant',coalesce(i.variant_name,''),
    'size',coalesce(i.size,''),'qty',i.qty,'price',i.price,'line_total',i.line_total
  ) order by i.created_at,i.id),'[]'::jsonb)
  into item_data from public.order_items i where i.order_id=o.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'status',e.status,'note',e.note,'at',e.created_at
  ) order by e.created_at,e.id),'[]'::jsonb)
  into event_data from public.order_events e where e.order_id=o.id;

  return jsonb_build_object(
    'id',o.id,'code',o.code,'transfer_reference',o.transfer_reference,
    'status',o.status,'deposit_status',o.deposit_status,'pay_method',o.pay_method,
    'created_at',o.created_at,'eta_date',o.eta_date,'subtotal',o.subtotal,
    'shipping_fee',o.shipping_fee,'discount',o.discount,'total',o.total,
    'deposit_percent',o.deposit_percent,'deposit_amount',o.deposit_amount,
    'balance_amount',o.balance_amount,'carrier',o.carrier,
    'tracking_code',o.tracking_code,'items',item_data,'events',event_data
  );
end;
$$;

revoke all on function public.track_order(text,text) from public;
grant execute on function public.track_order(text,text) to anon, authenticated;

-- Keep direct execution of the trigger function unavailable to API roles.
revoke all on function public.enforce_verus_payment_terms() from public, anon, authenticated;

-- A customer who has reported a transfer must not cancel while the shop is
-- reconciling it. Staff must reject/resolve that payment report first.
create or replace function public.guard_cancel_during_payment_review()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status = 'cancelled' and old.status <> 'cancelled'
     and old.deposit_status = 'pending_review' then
    raise exception 'PAYMENT_REVIEW_CONTACT_SHOP';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_cancel_during_payment_review on public.orders;
create trigger trg_guard_cancel_during_payment_review
before update of status on public.orders
for each row execute function public.guard_cancel_during_payment_review();
revoke all on function public.guard_cancel_during_payment_review() from public, anon, authenticated;
