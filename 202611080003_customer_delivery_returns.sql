-- Customer delivery confirmation, loyalty award, and return requests.
-- Apply after the existing VERUS schema/functions migrations.
insert into public.site_settings(key,value) values ('earn_vnd_per_point','10000'::jsonb) on conflict (key) do update set value=excluded.value,updated_at=now();
insert into public.site_settings(key,value) values ('redeem_vnd_per_point','500'::jsonb) on conflict (key) do update set value=excluded.value,updated_at=now();

alter table public.orders
  add column if not exists customer_confirmed_at timestamptz,
  add column if not exists points_awarded integer not null default 0,
  add column if not exists customer_return_reason text,
  add column if not exists customer_return_note text;

create or replace function public.customer_confirm_delivery(p_order uuid)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare o public.orders%rowtype; award integer;
begin
  select * into o from public.orders where id=p_order and user_id=auth.uid() for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.customer_confirmed_at is not null then
    return jsonb_build_object('ok',true,'already_confirmed',true,'points_awarded',o.points_awarded);
  end if;
  if o.status not in ('shipping','delivered') then raise exception 'ORDER_NOT_READY_FOR_CONFIRMATION'; end if;
  -- Earn 1 point per 10,000 VND of the final order total, rounded down. Award only once.
  award:=greatest(0,floor(o.total/10000.0)::integer);
  update public.orders set status='delivered',customer_confirmed_at=now(),points_awarded=award,updated_at=now() where id=p_order;
  update public.profiles set points=points+award,updated_at=now() where id=o.user_id;
  insert into public.order_events(order_id,status,note,created_by)
    values(p_order,'delivered','Khách xác nhận đã nhận hàng; cộng '||award||' điểm thưởng',auth.uid());
  return jsonb_build_object('ok',true,'already_confirmed',false,'points_awarded',award);
end $$;

create or replace function public.customer_request_return(p_order uuid,p_reason text,p_note text)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare o public.orders%rowtype; why text; detail text; delivered_at timestamptz;
begin
  why:=case when p_reason in ('size','defect','wrong_item','other') then p_reason else 'other' end;
  detail:=left(trim(coalesce(p_note,'')),1000);
  if length(detail)<5 then raise exception 'RETURN_DETAILS_REQUIRED'; end if;
  select * into o from public.orders where id=p_order and user_id=auth.uid() for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status<>'delivered' or o.customer_confirmed_at is not null then raise exception 'ORDER_NOT_ELIGIBLE_FOR_RETURN'; end if;
  select max(created_at) into delivered_at from public.order_events where order_id=p_order and status='delivered';
  if coalesce(delivered_at,o.updated_at) < now()-interval '7 days' then raise exception 'RETURN_WINDOW_EXPIRED'; end if;
  update public.orders set status='return_requested',customer_return_reason=why,customer_return_note=detail,updated_at=now() where id=p_order;
  insert into public.order_events(order_id,status,note,created_by)
    values(p_order,'return_requested','Yêu cầu đổi/trả ('||why||'): '||detail,auth.uid());
  return jsonb_build_object('ok',true);
end $$;

revoke all on function public.customer_confirm_delivery(uuid) from public;
revoke all on function public.customer_request_return(uuid,text,text) from public;
grant execute on function public.customer_confirm_delivery(uuid) to authenticated;
grant execute on function public.customer_request_return(uuid,text,text) to authenticated;
notify pgrst, 'reload schema';

-- VIP qualification uses cumulative spend from completed delivery records for the lifetime of the account.
create or replace function public.my_vip()
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare uid uuid:=auth.uid(); pts integer:=0; spend numeric:=0; tier text:='member'; tiers jsonb; next_code text; next_name text; next_min bigint;
begin
  if uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select points into pts from public.profiles where id=uid;
  select coalesce(sum(total),0) into spend from public.orders
    where user_id=uid and status='delivered' and deposit_status<>'refunded';
  select code into tier from public.vip_tiers where min_spend_12m<=spend order by min_spend_12m desc limit 1;
  select code,name,min_spend_12m into next_code,next_name,next_min from public.vip_tiers
    where min_spend_12m>spend order by min_spend_12m asc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name,'min',min_spend_12m,'min_spend_12m',min_spend_12m,'points_multiplier',points_multiplier) order by sort),'[]'::jsonb)
    into tiers from public.vip_tiers;
  return jsonb_build_object('points',coalesce(pts,0),'active_tier',coalesce(tier,'member'),
    'highest_tier',(select highest_tier from public.profiles where id=uid),'tiers',tiers,
    'spend_lifetime',spend,'spend_12m',spend,'next_tier',next_name,'next_threshold',next_min);
end $$;
grant execute on function public.my_vip() to authenticated;

-- Admin CRM uses the same lifetime delivery total as the customer VIP display.
create or replace function public.admin_crm()
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'user_id',p.id,'name',p.full_name,'segment',case when p.points>0 then 'repeat' else 'new' end,
      'tier',p.highest_tier,'points',p.points,
      'spend_lifetime',coalesce((select sum(o.total) from public.orders o where o.user_id=p.id and o.status='delivered' and o.deposit_status<>'refunded'),0),
      'spend_12m',coalesce((select sum(o.total) from public.orders o where o.user_id=p.id and o.status='delivered' and o.deposit_status<>'refunded'),0),
      'opt_in',p.marketing_opt_in)) from public.profiles p where p.role='customer'
  ),'[]'::jsonb);
end $$;
grant execute on function public.admin_crm() to authenticated;
