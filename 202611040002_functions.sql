
-- Helpers: SECURITY DEFINER functions always pin search_path.
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path=public,auth
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('staff','admin')) $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public,auth
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin') $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
begin
  insert into public.profiles(id,full_name)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'name'))
  on conflict(id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created_verus on auth.users;
create trigger on_auth_user_created_verus after insert on auth.users
for each row execute procedure public.handle_new_user();


create or replace function public.prepare_chat_message()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare r text;
begin
  new.sender_id:=auth.uid();
  select role into r from public.profiles where id=auth.uid();
  new.sender_role:=case when r='admin' then 'admin' when r='staff' then 'staff' else 'customer' end;
  if length(trim(coalesce(new.body,'')))=0 then raise exception 'EMPTY_MESSAGE'; end if;
  return new;
end $$;

drop trigger if exists verus_chat_message_before_insert on public.chat_messages;
create trigger verus_chat_message_before_insert before insert on public.chat_messages
for each row execute procedure public.prepare_chat_message();

create or replace function public.touch_chat_thread()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  update public.chat_threads set last_message_at=now() where id=new.thread_id;
  return new;
end $$;

drop trigger if exists verus_chat_message_after_insert on public.chat_messages;
create trigger verus_chat_message_after_insert after insert on public.chat_messages
for each row execute procedure public.touch_chat_thread();

create or replace function public.my_vip()
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare uid uuid:=auth.uid(); pts integer:=0; spend numeric:=0; tier text:='member'; tiers jsonb;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select points into pts from public.profiles where id=uid;
 select coalesce(sum(total),0) into spend from public.orders
 where user_id=uid and status='delivered' and created_at >= now()-interval '12 months' and deposit_status='confirmed';
 select code into tier from public.vip_tiers where min_spend_12m<=spend order by min_spend_12m desc limit 1;
 select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name,'min_spend_12m',min_spend_12m,'points_multiplier',points_multiplier) order by sort),'[]'::jsonb) into tiers from public.vip_tiers;
 return jsonb_build_object('points',coalesce(pts,0),'active_tier',coalesce(tier,'member'),'highest_tier',(select highest_tier from public.profiles where id=uid),'tiers',tiers,'spend_12m',spend);
end $$;

create or replace function public.preview_coupon(p_code text,p_subtotal bigint)
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare c public.coupons%rowtype; result bigint:=0;
begin
 select * into c from public.coupons where code=upper(trim(p_code)) and active;
 if not found then return jsonb_build_object('valid',false,'reason','COUPON_INVALID'); end if;
 if (c.starts_at is not null and now()<c.starts_at) or (c.ends_at is not null and now()>c.ends_at) then return jsonb_build_object('valid',false,'reason','COUPON_EXPIRED'); end if;
 if c.usage_limit is not null and c.used_count>=c.usage_limit then return jsonb_build_object('valid',false,'reason','COUPON_EXHAUSTED'); end if;
 if p_subtotal<c.min_subtotal then return jsonb_build_object('valid',false,'reason','COUPON_MIN','min',c.min_subtotal); end if;
 if c.kind='percent' then result:=floor(p_subtotal*c.value/100.0)::bigint;
 elsif c.kind='fixed' then result:=c.value;
 else result:=0; end if;
 if c.max_discount is not null then result:=least(result,c.max_discount); end if;
 return jsonb_build_object('valid',true,'code',c.code,'kind',c.kind,'discount',least(result,p_subtotal),'min',c.min_subtotal,'free_shipping',(c.kind='shipping'));
end $$;

create or replace function public.place_order(
 p_items jsonb,p_name text,p_phone text,p_province text,p_ward text,p_street text,p_note text,
 p_pay_method text,p_coupon text default null,p_points integer default 0,p_idem text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare
 uid uuid:=auth.uid(); item jsonb; vr public.product_variants%rowtype; pr public.products%rowtype;
 sz public.variant_sizes%rowtype; q integer; sub bigint:=0; ship bigint:=30000; disc bigint:=0;
 total bigint; dep_pct numeric:=20; dep bigint; bal bigint; code text; oid uuid;
 coupon public.coupons%rowtype; free_ship boolean:=false; lead_days integer:=15; points_used_actual integer:=0;
 pay_enabled boolean; pts integer:=0; points_disc bigint:=0; vnd_point bigint:=500; max_redeem numeric:=30;
begin
 if uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' or coalesce(trim(p_province),'')='' or coalesce(trim(p_ward),'')='' or coalesce(trim(p_street),'')='' then raise exception 'INVALID_ADDRESS'; end if;
 if p_pay_method not in ('cod_balance','bank_transfer_full') then raise exception 'INVALID_PAYMENT_METHOD'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART'; end if;
 if p_idem is not null then
   select id,orders.code,orders.total,orders.deposit_percent,orders.deposit_amount,orders.balance_amount
   into oid,code,total,dep_pct,dep,bal from public.orders where user_id=uid and idempotency_key=p_idem;
   if found then return jsonb_build_object('id',oid,'code',code,'total',total,'deposit_percent',dep_pct,'deposit',dep,'balance',bal); end if;
 end if;
 select coalesce((value#>>'{}')::numeric,20) into dep_pct from public.site_settings where key='deposit_percent';
 select coalesce((value#>>'{}')::bigint,30000) into ship from public.site_settings where key='shipping_fee';
 select coalesce((value#>>'{}')::integer,15) into lead_days from public.site_settings where key='lead_days';
 select coalesce((value#>>'{}')::boolean,true) into pay_enabled from public.site_settings where key=case when p_pay_method='cod_balance' then 'payment_cod_enabled' else 'payment_bank_enabled' end;
 if not coalesce(pay_enabled,true) then raise exception 'PAYMENT_METHOD_DISABLED'; end if;
 for item in
   select jsonb_build_object(
     'variant_id',x->>'variant_id',
     'size',coalesce(x->>'size','Free Size'),
     'qty',sum(coalesce((x->>'qty')::integer,0))
   )
   from jsonb_array_elements(p_items) x
   group by x->>'variant_id',coalesce(x->>'size','Free Size')
 loop
   q:=greatest(0,coalesce((item->>'qty')::integer,0));
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
   if sub<coupon.min_subtotal then raise exception 'COUPON_MIN'; end if;
   if coupon.kind='percent' then disc:=floor(sub*coupon.value/100.0)::bigint;
   elsif coupon.kind='fixed' then disc:=coupon.value;
   elsif coupon.kind='shipping' then free_ship:=true; end if;
   if coupon.max_discount is not null then disc:=least(disc,coupon.max_discount); end if;
   disc:=least(disc,sub);
 end if;
 if free_ship then ship:=0; end if;
 if ship>0 then
   if exists(select 1 from public.site_settings where key='free_shipping_threshold' and (value#>>'{}')::bigint<=sub-disc) then
     if (select (value#>>'{}')::bigint from public.site_settings where key='free_shipping_threshold')>0 then ship:=0; end if;
   end if;
 end if;
 select points into pts from public.profiles where id=uid for update;
 select coalesce((value#>>'{}')::bigint,500) into vnd_point from public.site_settings where key='redeem_vnd_per_point';
 select coalesce((value#>>'{}')::numeric,30) into max_redeem from public.site_settings where key='max_redeem_percent';
 if coalesce(p_points,0)>0 then
   if p_points>coalesce(pts,0) then raise exception 'NOT_ENOUGH_POINTS'; end if;
   points_disc:=least(p_points*vnd_point, floor((sub-disc)*max_redeem/100.0)::bigint);
   points_used_actual:=floor(points_disc/greatest(vnd_point,1))::integer;
 end if;
 total:=greatest(0,sub-disc-points_disc)+ship;
 if p_pay_method='bank_transfer_full' then dep_pct:=100; dep:=total; bal:=0;
 else dep_pct:=coalesce(dep_pct,20); dep:=ceil(total*dep_pct/100.0)::bigint; bal:=total-dep; end if;
 code:='VS-'||to_char(now(),'YYMMDD')||'-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8));
 insert into public.orders(code,user_id,customer_name,phone,province,ward,street,note,status,deposit_status,pay_method,subtotal,shipping_fee,discount,points_discount,total,deposit_percent,deposit_amount,balance_amount,coupon_code,points_used,idempotency_key,eta_date)
 values(code,uid,trim(p_name),p_phone,trim(p_province),trim(p_ward),trim(p_street),nullif(trim(coalesce(p_note,'')),''),'pending','unpaid',p_pay_method,sub,ship,disc,points_disc,total,dep_pct,dep,bal,nullif(upper(trim(coalesce(p_coupon,''))),''),coalesce(p_points,0),p_idem,current_date+lead_days)
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

create or replace function public.track_order(p_code text,p_phone text)
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare o public.orders%rowtype;
begin
 select * into o from public.orders where upper(code)=upper(trim(p_code)) and regexp_replace(phone,'\D','','g')=regexp_replace(coalesce(p_phone,''),'\D','','g');
 if not found then return null; end if;
 return jsonb_build_object('id',o.id,'code',o.code,'status',o.status,'deposit_status',o.deposit_status,'created_at',o.created_at,'eta_date',o.eta_date,'total',o.total,'deposit_amount',o.deposit_amount,'balance_amount',o.balance_amount,'carrier',o.carrier,'tracking_code',o.tracking_code);
end $$;

create or replace function public.report_deposit_transfer(p_order uuid,p_reference text)
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare o public.orders%rowtype; pid uuid;
begin
 select * into o from public.orders where id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if o.deposit_status='confirmed' then raise exception 'PAYMENT_ALREADY_CONFIRMED'; end if;
 insert into public.payments(order_id,type,amount,reference,status)
 values(o.id,case when o.pay_method='bank_transfer_full' then 'full' else 'deposit' end,o.deposit_amount,nullif(trim(p_reference),''),'pending')
 returning id into pid;
 update public.orders set deposit_status='pending_review',updated_at=now() where id=o.id;
 return pid;
end $$;

create or replace function public.submit_review(p_order_item uuid,p_rating integer,p_title text,p_body text,p_photos text[] default '{}')
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare oi public.order_items%rowtype; o public.orders%rowtype; rid uuid;
begin
 select * into oi from public.order_items where id=p_order_item;
 if not found then raise exception 'ORDER_ITEM_NOT_FOUND'; end if;
 select * into o from public.orders where id=oi.order_id and user_id=auth.uid();
 if not found or o.status<>'delivered' then raise exception 'REVIEW_REQUIRES_DELIVERED_ORDER'; end if;
 if p_rating not between 1 and 5 or length(trim(coalesce(p_body,'')))<5 then raise exception 'INVALID_REVIEW'; end if;
 insert into public.reviews(order_item_id,order_id,product_id,user_id,rating,title,body,photos)
 values(oi.id,o.id,oi.product_id,o.user_id,p_rating,nullif(trim(p_title),''),trim(p_body),coalesce(p_photos,'{}'))
 returning id into rid;
 return rid;
end $$;

create or replace function public.admin_set_order_status(p_order uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare old_status text;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('pending','confirmed','sourcing','supplier_ordered','in_transit_vn','inspecting','shipping','delivered','return_requested','cancelled','refunded') then raise exception 'INVALID_STATUS'; end if;
 select status::text into old_status from public.orders where id=p_order for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 update public.orders set status=p_status::public.verus_order_status,updated_at=now() where id=p_order;
 insert into public.order_events(order_id,status,note,created_by) values(p_order,p_status,p_note,auth.uid());
 insert into public.audit_log(actor_id,action,entity,entity_id,detail) values(auth.uid(),'set_order_status','orders',p_order::text,jsonb_build_object('from',old_status,'to',p_status));
 return jsonb_build_object('ok',true,'needs_refund',p_status='cancelled' and old_status<>'cancelled');
end $$;

create or replace function public.admin_set_shipping(p_order uuid,p_carrier text,p_tracking text)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 update public.orders set carrier=nullif(trim(p_carrier),''),tracking_code=nullif(trim(p_tracking),''),updated_at=now() where id=p_order;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 return true;
end $$;

create or replace function public.admin_set_internal_note(p_order uuid,p_note text)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 update public.orders set internal_note=p_note,updated_at=now() where id=p_order;
 return true;
end $$;

create or replace function public.admin_confirm_payment(p_payment uuid)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare p public.payments%rowtype;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 select * into p from public.payments where id=p_payment for update;
 if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;
 update public.payments set status='confirmed',confirmed_by=auth.uid(),updated_at=now() where id=p.id;
 update public.orders set deposit_status='confirmed',updated_at=now() where id=p.order_id;
 insert into public.ledger_entries(direction,kind,amount,note,order_id,created_by) values('credit',p.type,p.amount,'Đã đối soát thanh toán',p.order_id,auth.uid());
 return true;
end $$;

create or replace function public.admin_reject_payment(p_payment uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
declare p public.payments%rowtype;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 select * into p from public.payments where id=p_payment for update;
 if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;
 update public.payments set status='rejected',note=p_note,confirmed_by=auth.uid(),updated_at=now() where id=p.id;
 update public.orders set deposit_status='unpaid',updated_at=now() where id=p.order_id;
 return true;
end $$;

create or replace function public.admin_refund(p_order uuid,p_amount bigint,p_reason text)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 if p_amount<=0 then raise exception 'INVALID_AMOUNT'; end if;
 update public.orders set status='refunded',deposit_status='refunded',updated_at=now() where id=p_order;
 insert into public.payments(order_id,type,amount,status,note,confirmed_by) values(p_order,'refund',p_amount,'refunded',p_reason,auth.uid());
 insert into public.ledger_entries(direction,kind,amount,note,order_id,created_by) values('debit','refund',p_amount,p_reason,p_order,auth.uid());
 insert into public.order_events(order_id,status,note,created_by) values(p_order,'refunded',p_reason,auth.uid());
 return true;
end $$;

create or replace function public.admin_moderate_review(p_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('published','rejected') then raise exception 'INVALID_REVIEW_STATUS'; end if;
 update public.reviews set status=p_status,moderated_at=now() where id=p_id;
 return true;
end $$;

create or replace function public.admin_set_role(p_user uuid,p_role text)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_role not in ('customer','staff','admin') then raise exception 'INVALID_ROLE'; end if;
 update public.profiles set role=p_role,updated_at=now() where id=p_user;
 if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
 insert into public.audit_log(actor_id,action,entity,entity_id,detail) values(auth.uid(),'set_role','profiles',p_user::text,jsonb_build_object('role',p_role));
 return true;
end $$;

create or replace function public.admin_request_withdrawal(p_amount bigint,p_bank text,p_owner text,p_hint text)
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare rid uuid;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_amount<=0 or coalesce(trim(p_bank),'')='' or coalesce(trim(p_owner),'')='' then raise exception 'INVALID_WITHDRAWAL'; end if;
 insert into public.withdrawal_requests(amount,bank,owner,hint,requested_by) values(p_amount,trim(p_bank),trim(p_owner),p_hint,auth.uid()) returning id into rid;
 return rid;
end $$;

create or replace function public.admin_decide_withdrawal(p_id uuid,p_decision text,p_note text default null)
returns boolean language plpgsql security definer set search_path=public,auth
as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('approved','rejected','paid_manually') then raise exception 'INVALID_DECISION'; end if;
 update public.withdrawal_requests set status=p_decision,note=p_note,decided_by=auth.uid(),updated_at=now() where id=p_id;
 if not found then raise exception 'WITHDRAWAL_NOT_FOUND'; end if;
 return true;
end $$;

create or replace function public.wallet_summary()
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare cr bigint; dr bigint;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select coalesce(sum(amount),0) into cr from public.ledger_entries where direction='credit';
 select coalesce(sum(amount),0) into dr from public.ledger_entries where direction='debit';
 return jsonb_build_object('available',cr-dr,'credits',cr,'debits',dr);
end $$;

create or replace function public.admin_dashboard(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare customers bigint; gross bigint; by_status jsonb;
begin
 if not public.is_staff() then raise exception 'FORBIDDEN'; end if;
 select count(*) into customers from public.profiles where role='customer';
 select coalesce(sum(total),0) into gross from public.orders where status<>'cancelled' and created_at>=now()-make_interval(days=>greatest(1,least(p_days,365)));
 select coalesce(jsonb_object_agg(status,cnt),'{}'::jsonb) into by_status from (select status::text status,count(*) cnt from public.orders where created_at>=now()-make_interval(days=>greatest(1,least(p_days,365))) group by status) x;
 return jsonb_build_object('customers',customers,'gross_orders_value',gross,'orders_by_status',coalesce(by_status,'{}'::jsonb),'funnel',jsonb_build_object());
end $$;

create or replace function public.admin_crm()
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.id,'name',p.full_name,'segment',case when p.points>0 then 'repeat' else 'new' end,'tier',p.highest_tier,'points',p.points,'spend_12m',0,'opt_in',p.marketing_opt_in)) from public.profiles p where p.role='customer'),'[]'::jsonb);
end $$;

create or replace function public.admin_queue_crm(p_segment text,p_template text)
returns integer language plpgsql security definer set search_path=public,auth
as $$
declare n integer;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 insert into public.crm_queue(user_id,segment,template)
 select id,p_segment,p_template from public.profiles
 where role='customer' and marketing_opt_in=true
 and (p_segment='all' or (p_segment='new' and points=0) or (p_segment='repeat' and points>0))
 and not exists(select 1 from public.crm_queue q where q.user_id=profiles.id and q.created_at>now()-interval '7 days');
 get diagnostics n=row_count;
 return n;
end $$;

-- The UI only records the transfer reference. Actual bank reconciliation remains a human action.
