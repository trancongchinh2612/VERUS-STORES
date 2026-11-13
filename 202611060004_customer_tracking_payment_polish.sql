-- VERUS STORE: customer tracking payload and duplicate pending-payment protection.
-- Run after migrations 202611060001-003.

-- Keep at most one pending payment row per order/payment type. Older duplicate
-- pending rows (from previous versions) are rejected before adding the constraint.
with ranked as (
  select id, row_number() over (
    partition by order_id, type
    order by created_at desc, id desc
  ) as rn
  from public.payments
  where status='pending'
)
update public.payments p
set status='rejected',
    note=concat_ws(' | ', nullif(p.note,''), 'Bản ghi chờ trùng được đóng khi nâng cấp'),
    updated_at=now()
from ranked r
where p.id=r.id and r.rn>1;

create unique index if not exists payments_one_pending_per_order_type
on public.payments(order_id,type)
where status='pending';

-- Public order lookup requires BOTH order code and matching phone number.
-- Return only customer-safe order details, line items and status history.
create or replace function public.track_order(p_code text,p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,auth
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
    'id',i.id,
    'name',i.product_name,
    'variant',coalesce(i.variant_name,''),
    'size',coalesce(i.size,''),
    'qty',i.qty,
    'price',i.price,
    'line_total',i.line_total
  ) order by i.created_at,i.id),'[]'::jsonb)
  into item_data
  from public.order_items i
  where i.order_id=o.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'status',e.status,
    'note',e.note,
    'at',e.created_at
  ) order by e.created_at,e.id),'[]'::jsonb)
  into event_data
  from public.order_events e
  where e.order_id=o.id;

  return jsonb_build_object(
    'id',o.id,
    'code',o.code,
    'status',o.status,
    'deposit_status',o.deposit_status,
    'pay_method',o.pay_method,
    'created_at',o.created_at,
    'eta_date',o.eta_date,
    'subtotal',o.subtotal,
    'shipping_fee',o.shipping_fee,
    'discount',o.discount,
    'total',o.total,
    'deposit_percent',o.deposit_percent,
    'deposit_amount',o.deposit_amount,
    'balance_amount',o.balance_amount,
    'carrier',o.carrier,
    'tracking_code',o.tracking_code,
    'items',item_data,
    'events',event_data
  );
end;
$$;

revoke all on function public.track_order(text,text) from public;
grant execute on function public.track_order(text,text) to anon,authenticated;

-- Re-define transfer reporting to update the existing pending row, never create
-- a second pending record for the same order/type.
create or replace function public.report_deposit_transfer(p_order uuid,p_reference text)
returns uuid
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  o public.orders%rowtype;
  p public.payments%rowtype;
  pid uuid;
  expected bigint;
  pay_type text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if coalesce(trim(p_reference),'')='' or length(trim(p_reference))>120 then
    raise exception 'INVALID_PAYMENT_REFERENCE';
  end if;

  select * into o
  from public.orders
  where id=p_order and user_id=auth.uid()
  for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status in ('cancelled','refunded') then raise exception 'ORDER_CLOSED'; end if;
  if o.deposit_status='confirmed' then raise exception 'PAYMENT_ALREADY_CONFIRMED'; end if;

  expected:=case when o.pay_method='bank_transfer_full' then o.total else o.deposit_amount end;
  pay_type:=case when o.pay_method='bank_transfer_full' then 'full' else 'deposit' end;
  if expected<=0 then raise exception 'NO_PAYMENT_REQUIRED'; end if;

  select * into p
  from public.payments
  where order_id=o.id and type=pay_type and status='pending'
  order by created_at desc
  limit 1
  for update;

  if found then
    update public.payments
      set amount=expected,
          reference=trim(p_reference),
          note='Khách báo đã chuyển khoản; chờ shop đối soát',
          updated_at=now()
    where id=p.id
    returning id into pid;
  else
    insert into public.payments(order_id,type,amount,reference,status,note)
    values(o.id,pay_type,expected,trim(p_reference),'pending','Khách báo đã chuyển khoản; chờ shop đối soát')
    returning id into pid;
  end if;

  update public.orders
  set deposit_status='pending_review',updated_at=now()
  where id=o.id;
  return pid;
end;
$$;

revoke all on function public.report_deposit_transfer(uuid,text) from public,anon;
grant execute on function public.report_deposit_transfer(uuid,text) to authenticated;
