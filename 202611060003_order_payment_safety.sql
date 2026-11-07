-- VERUS STORE: transactional order, payment and cancellation safeguards.
-- Run after migrations 001-002 and 202611060001-002.

-- Enforce free shipping at the source of truth for all new orders.
insert into public.site_settings(key,value,updated_at)
values ('shipping_fee','0'::jsonb,now()),('free_shipping_threshold','0'::jsonb,now())
on conflict(key) do update set value=excluded.value,updated_at=now();

-- Keep the original checkout calculation but make shipping zero regardless of stale settings,
-- enforce coupon per-user limits, and store the actual points redeemed.
create or replace function public.place_order(
 p_items jsonb,p_name text,p_phone text,p_province text,p_ward text,p_street text,p_note text,
 p_pay_method text,p_coupon text default null,p_points integer default 0,p_idem text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare
 uid uuid:=auth.uid(); item jsonb; vr public.product_variants%rowtype; pr public.products%rowtype;
 sz public.variant_sizes%rowtype; q integer; sub bigint:=0; ship bigint:=0; disc bigint:=0;
 total bigint; dep_pct numeric:=20; dep bigint; bal bigint; code text; oid uuid;
 coupon public.coupons%rowtype; lead_days integer:=15; points_used_actual integer:=0;
 pay_enabled boolean; pts integer:=0; points_disc bigint:=0; vnd_point bigint:=500; max_redeem numeric:=30;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' or coalesce(trim(p_province),'')='' or coalesce(trim(p_ward),'')='' or coalesce(trim(p_street),'')='' then raise exception 'INVALID_ADDRESS'; end if;
 if p_pay_method not in ('cod_balance','bank_transfer_full') then raise exception 'INVALID_PAYMENT_METHOD'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART'; end if;
 if coalesce(p_points,0)<0 then raise exception 'INVALID_POINTS'; end if;
 if p_idem is not null then
   select id,orders.code,orders.total,orders.deposit_percent,orders.deposit_amount,orders.balance_amount
   into oid,code,total,dep_pct,dep,bal from public.orders where user_id=uid and idempotency_key=p_idem;
   if found then return jsonb_build_object('id',oid,'code',code,'total',total,'deposit_percent',dep_pct,'deposit',dep,'balance',bal); end if;
 end if;
 select coalesce((value#>>'{}')::numeric,20) into dep_pct from public.site_settings where key='deposit_percent';
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
 else dep_pct:=coalesce(dep_pct,20); dep:=ceil(total*dep_pct/100.0)::bigint; bal:=total-dep; end if;
 code:='VS-'||to_char(now(),'YYMMDD')||'-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8));
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
 return jsonb_build_object('id',oid,'code',code,'total',total,'deposit_percent',dep_pct,'deposit',dep,'balance',bal);
end $$;

-- A single pending payment record per order/type; repeated customer reports update it instead of duplicating it.
create or replace function public.report_deposit_transfer(p_order uuid,p_reference text)
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare o public.orders%rowtype; p public.payments%rowtype; pid uuid; expected bigint;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into o from public.orders where id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if o.status in ('cancelled','refunded') then raise exception 'ORDER_CLOSED'; end if;
 if o.deposit_status='confirmed' then raise exception 'PAYMENT_ALREADY_CONFIRMED'; end if;
 expected:=case when o.pay_method='bank_transfer_full' then o.total else o.deposit_amount end;
 select * into p from public.payments where order_id=o.id and type=case when o.pay_method='bank_transfer_full' then 'full' else 'deposit' end and status='pending' order by created_at desc limit 1 for update;
 if found then
   update public.payments set amount=expected,reference=nullif(trim(p_reference),''),note='Khách báo đã chuyển khoản; chờ shop đối soát',updated_at=now() where id=p.id returning id into pid;
 else
   insert into public.payments(order_id,type,amount,reference,status,note)
   values(o.id,case when o.pay_method='bank_transfer_full' then 'full' else 'deposit' end,expected,nullif(trim(p_reference),''),'pending','Khách báo đã chuyển khoản; chờ shop đối soát') returning id into pid;
 end if;
 update public.orders set deposit_status='pending_review',updated_at=now() where id=o.id;
 return pid;
end $$;

-- Shared transactional cancellation: restore stock/points/coupon once, and reject pending payment reports.
create or replace function public.cancel_order_internal(p_order uuid,p_actor uuid,p_customer boolean default false)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare o public.orders%rowtype; x record;
begin
 select * into o from public.orders where id=p_order for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if p_customer and o.user_id<>p_actor then raise exception 'FORBIDDEN'; end if;
 if o.status in ('shipping','delivered','return_requested','cancelled','refunded') then raise exception 'CANCEL_NOT_ALLOWED'; end if;
 if exists(select 1 from public.payments where order_id=o.id and status='confirmed' and type<>'refund') then raise exception 'PAYMENT_CONFIRMED_CONTACT_SHOP'; end if;
 for x in select variant_id,size,sum(qty)::integer qty from public.order_items where order_id=o.id and variant_id is not null group by variant_id,size loop
   update public.variant_sizes set stock=stock+x.qty where variant_id=x.variant_id and size=x.size;
 end loop;
 if o.points_used>0 then update public.profiles set points=points+o.points_used where id=o.user_id; end if;
 if o.coupon_code is not null then update public.coupons set used_count=greatest(0,used_count-1) where code=o.coupon_code; end if;
 update public.payments set status='rejected',note=coalesce(note,'')||' | Đơn đã hủy',updated_at=now() where order_id=o.id and status='pending';
 update public.orders set status='cancelled',deposit_status='unpaid',updated_at=now() where id=o.id;
 insert into public.order_events(order_id,status,note,created_by) values(o.id,'cancelled','Đơn được hủy; tồn kho và quyền lợi đã được hoàn lại',p_actor);
 insert into public.audit_log(actor_id,action,entity,entity_id,detail) values(p_actor,'cancel_order','orders',o.id::text,jsonb_build_object('customer',p_customer));
 return jsonb_build_object('ok',true,'restocked',true);
end $$;

create or replace function public.cancel_my_order(p_order uuid)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$ begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 return public.cancel_order_internal(p_order,auth.uid(),true);
end $$;

-- Restrict status transitions; cancellation can only occur before sourcing/shipping.
create or replace function public.admin_set_order_status(p_order uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare old_status text;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('pending','confirmed','sourcing','supplier_ordered','in_transit_vn','inspecting','shipping','delivered','return_requested','cancelled','refunded') then raise exception 'INVALID_STATUS'; end if;
 select status::text into old_status from public.orders where id=p_order for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if old_status=p_status then return jsonb_build_object('ok',true,'unchanged',true); end if;
 if p_status='cancelled' then return public.cancel_order_internal(p_order,auth.uid(),false); end if;
 if not (
  (old_status='pending' and p_status='confirmed') or
  (old_status='confirmed' and p_status='sourcing') or
  (old_status='sourcing' and p_status='supplier_ordered') or
  (old_status='supplier_ordered' and p_status='in_transit_vn') or
  (old_status='in_transit_vn' and p_status='inspecting') or
  (old_status='inspecting' and p_status='shipping') or
  (old_status='shipping' and p_status in ('delivered','return_requested')) or
  (old_status='delivered' and p_status='return_requested') or
  (old_status='return_requested' and p_status='delivered')
 ) then raise exception 'INVALID_STATUS_TRANSITION'; end if;
 update public.orders set status=p_status::public.verus_order_status,updated_at=now() where id=p_order;
 insert into public.order_events(order_id,status,note,created_by) values(p_order,p_status,nullif(trim(coalesce(p_note,'')),''),auth.uid());
 insert into public.audit_log(actor_id,action,entity,entity_id,detail) values(auth.uid(),'set_order_status','orders',p_order::text,jsonb_build_object('from',old_status,'to',p_status));
 return jsonb_build_object('ok',true,'needs_refund',false);
end $$;

-- Confirm only an existing pending payment once, never above the order's unpaid amount.
create or replace function public.admin_confirm_payment(p_payment uuid)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare p public.payments%rowtype; o public.orders%rowtype; paid bigint; cap bigint;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 select * into p from public.payments where id=p_payment for update;
 if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;
 if p.status<>'pending' then raise exception 'PAYMENT_NOT_PENDING'; end if;
 select * into o from public.orders where id=p.order_id for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if o.status in ('cancelled','refunded') then raise exception 'ORDER_CLOSED'; end if;
 select coalesce(sum(amount),0) into paid from public.payments where order_id=o.id and status='confirmed' and type<>'refund';
 cap:=case when o.pay_method='bank_transfer_full' then o.total else o.deposit_amount end;
 if p.type='refund' or p.amount<=0 or paid+p.amount>cap then raise exception 'PAYMENT_AMOUNT_INVALID'; end if;
 update public.payments set status='confirmed',confirmed_by=auth.uid(),updated_at=now() where id=p.id;
 select coalesce(sum(amount),0) into paid from public.payments where order_id=o.id and status='confirmed' and type<>'refund';
 update public.orders set deposit_status=case when paid>=o.deposit_amount then 'confirmed' else 'pending_review' end,updated_at=now() where id=o.id;
 insert into public.ledger_entries(direction,kind,amount,note,order_id,created_by) values('credit',p.type,p.amount,'Đã đối soát thanh toán · payment '||p.id::text,o.id,auth.uid());
 return true;
end $$;

create or replace function public.admin_reject_payment(p_payment uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare p public.payments%rowtype; o public.orders%rowtype; paid bigint;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 select * into p from public.payments where id=p_payment for update;
 if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;
 if p.status<>'pending' then raise exception 'PAYMENT_NOT_PENDING'; end if;
 update public.payments set status='rejected',note=p_note,confirmed_by=auth.uid(),updated_at=now() where id=p.id;
 select * into o from public.orders where id=p.order_id for update;
 select coalesce(sum(amount),0) into paid from public.payments where order_id=p.order_id and status='confirmed' and type<>'refund';
 update public.orders set deposit_status=case when paid>=o.deposit_amount then 'confirmed' when exists(select 1 from public.payments where order_id=o.id and status='pending') then 'pending_review' else 'unpaid' end,updated_at=now() where id=o.id;
 return true;
end $$;

-- Record a refund only within the amount actually confirmed as received; execution to customer remains manual.
create or replace function public.admin_refund(p_order uuid,p_amount bigint,p_reason text)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare o public.orders%rowtype; received bigint; refunded bigint;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 if p_amount<=0 or coalesce(trim(p_reason),'')='' then raise exception 'INVALID_REFUND'; end if;
 select * into o from public.orders where id=p_order for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 select coalesce(sum(amount),0) into received from public.payments where order_id=p_order and status='confirmed' and type<>'refund';
 select coalesce(sum(amount),0) into refunded from public.payments where order_id=p_order and type='refund' and status='refunded';
 if p_amount>received-refunded then raise exception 'REFUND_EXCEEDS_RECEIVED'; end if;
 insert into public.payments(order_id,type,amount,status,note,confirmed_by) values(p_order,'refund',p_amount,'refunded',p_reason,auth.uid());
 insert into public.ledger_entries(direction,kind,amount,note,order_id,created_by) values('debit','refund',p_amount,p_reason,p_order,auth.uid());
 if p_amount=received-refunded then
   update public.orders set status='refunded',deposit_status='refunded',updated_at=now() where id=p_order;
   insert into public.order_events(order_id,status,note,created_by) values(p_order,'refunded','Shop ghi nhận đã hoàn tiền: '||p_reason,auth.uid());
 end if;
 return true;
end $$;

revoke all on function public.cancel_order_internal(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.cancel_my_order(uuid) from public,anon;
grant execute on function public.cancel_my_order(uuid) to authenticated;
grant execute on function public.admin_set_order_status(uuid,text,text) to authenticated;
grant execute on function public.admin_confirm_payment(uuid) to authenticated;
grant execute on function public.admin_reject_payment(uuid,text) to authenticated;
grant execute on function public.admin_refund(uuid,bigint,text) to authenticated;

-- Zero-total orders need no transfer and therefore must not create a zero-value pending payment.
create or replace function public.create_initial_order_payment()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 if new.deposit_amount>0 then
   insert into public.payments(order_id,type,amount,status,note)
   values(new.id,case when new.pay_method='bank_transfer_full' then 'full' else 'deposit' end,new.deposit_amount,'pending','Chờ khách thanh toán và shop đối soát');
 else
   update public.orders set deposit_status='confirmed' where id=new.id;
 end if;
 return new;
end $$;
