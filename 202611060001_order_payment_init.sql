-- Create a pending payment record as soon as an order is created.
-- This does NOT mark the payment as received; only verified webhook/admin confirmation may do that.
create or replace function public.create_initial_order_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.payments(order_id, type, amount, status, note)
  values (
    new.id,
    case when new.pay_method = 'bank_transfer_full' then 'full' else 'deposit' end,
    new.deposit_amount,
    'pending',
    case when new.pay_method = 'bank_transfer_full'
      then 'Chờ thanh toán chuyển khoản 100%'
      else 'Chờ thanh toán tiền cọc 20%' end
  );
  return new;
end;
$$;

drop trigger if exists trg_create_initial_order_payment on public.orders;
create trigger trg_create_initial_order_payment
after insert on public.orders
for each row execute function public.create_initial_order_payment();
