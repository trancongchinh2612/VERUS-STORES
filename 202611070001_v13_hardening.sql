-- VERUS STORE V13 hardening. Chạy SAU 202611060004. Idempotent (chạy lại an toàn).
-- CHƯA được chạy thử trên Supabase thật: hãy chạy trên project staging trước.

-- 0) Chẩn đoán (chạy riêng nếu muốn): pgcrypto nằm schema nào?
--    select n.nspname from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto';

-- 1) place_order gọi gen_random_bytes nhưng search_path chỉ có public,auth.
--    Nếu pgcrypto ở schema "extensions" (mặc định Supabase) thì đặt hàng báo lỗi 42883.
--    Tạo hàm cùng tên trong public (chỉ khi chưa có), không phụ thuộc extension.
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='gen_random_bytes'
  ) then
    execute $f$
      create function public.gen_random_bytes(n integer)
      returns bytea language sql volatile set search_path = pg_catalog
      as $b$
        select decode(substr(replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''), 1, 2*least(greatest(n,1),32)), 'hex')
      $b$
    $f$;
  end if;
end $$;

-- 2) Khách chỉ được sửa 3 cột hồ sơ của chính mình (không tự sửa points/highest_tier/role).
revoke update on public.profiles from authenticated;
grant update (full_name, phone, marketing_opt_in) on public.profiles to authenticated;

-- 3) Giới hạn đơn chờ thanh toán / chống đặt khống giữ kho.
create or replace function public.guard_pending_orders()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if (select count(*) from public.orders
      where user_id=new.user_id and status='pending' and deposit_status in ('unpaid','pending_review')) >= 5 then
    raise exception 'TOO_MANY_PENDING_ORDERS';
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_pending_orders on public.orders;
create trigger trg_guard_pending_orders before insert on public.orders
for each row execute function public.guard_pending_orders();

-- 4) Không cho đặt nhà cung cấp khi chưa xác nhận cọc/thanh toán (khớp thông báo DEPOSIT_NOT_CONFIRMED của giao diện).
create or replace function public.guard_supplier_order()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status::text='supplier_ordered' and old.status::text<>'supplier_ordered' and new.deposit_status<>'confirmed' then
    raise exception 'DEPOSIT_NOT_CONFIRMED';
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_supplier_order on public.orders;
create trigger trg_guard_supplier_order before update of status on public.orders
for each row execute function public.guard_supplier_order();

-- 5) Sổ cái và audit chỉ ghi qua hàm của hệ thống (append-only với client).
drop policy if exists "admin manage ledger" on public.ledger_entries;
drop policy if exists "admin insert audit" on public.audit_log;
revoke insert, update, delete on public.ledger_entries from authenticated;
revoke insert, update, delete on public.audit_log from authenticated;

-- 6) Chat: staff cần quyền UPDATE (policy đã có nhưng thiếu GRANT), giới hạn độ dài, chống spam, chống gắn đơn của người khác.
grant update on public.chat_threads to authenticated;
alter table public.chat_messages drop constraint if exists chat_body_len;
alter table public.chat_messages add constraint chat_body_len check (char_length(body) <= 2000) not valid;
alter table public.chat_threads drop constraint if exists chat_subject_len;
alter table public.chat_threads add constraint chat_subject_len check (char_length(subject) <= 120) not valid;

create or replace function public.chat_rate_limit()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() and
     (select count(*) from public.chat_messages where sender_id=auth.uid() and created_at > now()-interval '1 minute') >= 15 then
    raise exception 'RATE_LIMITED';
  end if;
  return new;
end $$;
drop trigger if exists trg_chat_rate_limit on public.chat_messages;
create trigger trg_chat_rate_limit before insert on public.chat_messages
for each row execute function public.chat_rate_limit();

create or replace function public.chat_thread_guard()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.order_id is not null and not public.is_staff()
     and not exists(select 1 from public.orders o where o.id=new.order_id and o.user_id=new.user_id) then
    raise exception 'FORBIDDEN';
  end if;
  return new;
end $$;
drop trigger if exists trg_chat_thread_guard on public.chat_threads;
create trigger trg_chat_thread_guard before insert on public.chat_threads
for each row execute function public.chat_thread_guard();

-- 7) Bảng events (anon ghi được): giới hạn kích thước.
alter table public.events drop constraint if exists events_props_size;
alter table public.events add constraint events_props_size check (pg_column_size(props) < 4096) not valid;
alter table public.events drop constraint if exists events_name_len;
alter table public.events add constraint events_name_len check (char_length(name) <= 60) not valid;

-- 8) Khóa quyền gọi RPC của anon/public (hàm vẫn tự kiểm tra role bên trong).
do $$
declare f text;
begin
  foreach f in array array[
    'public.admin_set_order_status(uuid,text,text)','public.admin_set_shipping(uuid,text,text)',
    'public.admin_set_internal_note(uuid,text)','public.admin_confirm_payment(uuid)',
    'public.admin_reject_payment(uuid,text)','public.admin_refund(uuid,bigint,text)',
    'public.admin_moderate_review(uuid,text)','public.admin_set_role(uuid,text)',
    'public.admin_request_withdrawal(bigint,text,text,text)','public.admin_decide_withdrawal(uuid,text,text)',
    'public.wallet_summary()','public.admin_dashboard(integer)','public.admin_crm()','public.admin_queue_crm(text,text)',
    'public.my_vip()','public.submit_review(uuid,integer,text,text,text[])',
    'public.place_order(jsonb,text,text,text,text,text,text,text,text,integer,text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- 9) track_order dùng upper(code): thêm index biểu thức để không quét toàn bảng.
create index if not exists idx_orders_code_upper on public.orders (upper(code));

-- 10) Hủy đơn chưa thanh toán quá hạn (hoàn kho/điểm/coupon một lần qua cancel_order_internal).
create or replace function public.expire_unpaid_orders(p_hours integer default 48)
returns integer language plpgsql security definer set search_path=public,auth as $$
declare r record; n integer:=0;
begin
  for r in select id from public.orders
           where status='pending' and deposit_status='unpaid' and created_at < now()-make_interval(hours=>greatest(1,p_hours))
           order by created_at limit 200 loop
    begin
      perform public.cancel_order_internal(r.id, null, false);
      n:=n+1;
    exception when others then null;
    end;
  end loop;
  return n;
end $$;
revoke all on function public.expire_unpaid_orders(integer) from public, anon, authenticated;

create or replace function public.admin_expire_unpaid_orders(p_hours integer default 48)
returns integer language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  return public.expire_unpaid_orders(p_hours);
end $$;
revoke all on function public.admin_expire_unpaid_orders(integer) from public, anon;
grant execute on function public.admin_expire_unpaid_orders(integer) to authenticated;
