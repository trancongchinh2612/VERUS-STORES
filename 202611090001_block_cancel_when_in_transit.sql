-- Khách không được tự hủy đơn khi shop đã chuyển sang 'Đang vận chuyển' / 'Đang kiểm tra hàng'.
-- Chạy file này trong Supabase SQL Editor.
create or replace function public.cancel_order_internal(p_order uuid,p_actor uuid,p_customer boolean default false)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare o public.orders%rowtype; x record;
begin
 select * into o from public.orders where id=p_order for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if p_customer and o.user_id<>p_actor then raise exception 'FORBIDDEN'; end if;
 if o.status in ('shipping','delivered','return_requested','cancelled','refunded') then raise exception 'CANCEL_NOT_ALLOWED'; end if;
 if p_customer and o.status in ('in_transit_vn','inspecting') then raise exception 'CANCEL_NOT_ALLOWED'; end if;
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
