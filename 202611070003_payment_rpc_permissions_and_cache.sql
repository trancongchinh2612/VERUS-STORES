-- Run after 202611070002_checkout_payment_hardening.sql.
-- Reassert the exact RPC grants used by the customer checkout and manual reconciliation.
-- This migration also asks PostgREST to refresh its schema cache, which can otherwise
-- keep reporting PostgreSQL/PostgREST 42883 after a function signature was updated.

grant execute on function public.place_order(jsonb,text,text,text,text,text,text,text,text,integer,text) to authenticated;
grant execute on function public.report_deposit_transfer(uuid,text) to authenticated;
grant execute on function public.admin_confirm_payment(uuid) to authenticated;
grant execute on function public.admin_reject_payment(uuid,text) to authenticated;

notify pgrst, 'reload schema';
