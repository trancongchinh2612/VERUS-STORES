
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.variant_sizes enable row level security;
alter table public.product_costs enable row level security;
alter table public.site_settings enable row level security;
alter table public.coupons enable row level security;
alter table public.vip_tiers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_events enable row level security;
alter table public.payments enable row level security;
alter table public.wishlist enable row level security;
alter table public.cart_snapshots enable row level security;
alter table public.outfits enable row level security;
alter table public.outfit_items enable row level security;
alter table public.reviews enable row level security;
alter table public.chat_threads enable row level security;
alter table public.chat_messages enable row level security;
alter table public.events enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.audit_log enable row level security;
alter table public.crm_queue enable row level security;

-- Public catalog reads.
create policy "public read active categories" on public.categories for select using(active or public.is_staff());
create policy "public read active products" on public.products for select using(status='active' or public.is_staff());
create policy "public read variants of visible products" on public.product_variants for select using(exists(select 1 from public.products p where p.id=product_id and (p.status='active' or public.is_staff())));
create policy "public read sizes of visible products" on public.variant_sizes for select using(exists(select 1 from public.product_variants v join public.products p on p.id=v.product_id where v.id=variant_id and (p.status='active' or public.is_staff())));
create policy "public read settings" on public.site_settings for select using(true);
create policy "public read vip tiers" on public.vip_tiers for select using(true);
create policy "public read active outfits" on public.outfits for select using(active or public.is_staff());
create policy "public read outfit items" on public.outfit_items for select using(exists(select 1 from public.outfits o where o.id=outfit_id and (o.active or public.is_staff())));
create policy "public read published reviews" on public.reviews for select using(status='published' or user_id=auth.uid() or public.is_staff());

-- Profiles: user reads/updates own basic profile; staff can read all.
create policy "profile read own or staff" on public.profiles for select using(id=auth.uid() or public.is_staff());
create policy "profile update own" on public.profiles for update using(id=auth.uid()) with check(id=auth.uid() and role='customer');
create policy "profile staff update" on public.profiles for update using(public.is_admin()) with check(public.is_admin());

-- Staff-managed data.
create policy "staff manage products" on public.products for all using(public.is_staff()) with check(public.is_staff());
create policy "staff manage categories" on public.categories for all using(public.is_admin()) with check(public.is_admin());
create policy "staff manage variants" on public.product_variants for all using(public.is_staff()) with check(public.is_staff());
create policy "staff manage sizes" on public.variant_sizes for all using(public.is_staff()) with check(public.is_staff());
create policy "staff manage outfits" on public.outfits for all using(public.is_staff()) with check(public.is_staff());
create policy "staff manage outfit items" on public.outfit_items for all using(public.is_staff()) with check(public.is_staff());
create policy "admin manage product costs" on public.product_costs for all using(public.is_admin()) with check(public.is_admin());
create policy "admin manage settings" on public.site_settings for all using(public.is_admin()) with check(public.is_admin());
create policy "admin manage coupons" on public.coupons for all using(public.is_admin()) with check(public.is_admin());
create policy "admin manage vip tiers" on public.vip_tiers for all using(public.is_admin()) with check(public.is_admin());

-- Customer-owned records. Order creation/payment changes are RPC-only.
create policy "orders own or staff read" on public.orders for select using(user_id=auth.uid() or public.is_staff());
create policy "order items own or staff read" on public.order_items for select using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_staff())));
create policy "order events own or staff read" on public.order_events for select using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_staff())));
create policy "payments staff read" on public.payments for select using(public.is_staff());
create policy "wishlist own" on public.wishlist for all using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "cart snapshots own" on public.cart_snapshots for all using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "chat thread own or staff" on public.chat_threads for select using(user_id=auth.uid() or public.is_staff());
create policy "chat thread customer insert" on public.chat_threads for insert with check(user_id=auth.uid());
create policy "chat thread staff update" on public.chat_threads for update using(public.is_staff()) with check(public.is_staff());
create policy "chat messages own or staff read" on public.chat_messages for select using(exists(select 1 from public.chat_threads t where t.id=thread_id and (t.user_id=auth.uid() or public.is_staff())));
create policy "chat messages insert own thread" on public.chat_messages for insert with check(exists(select 1 from public.chat_threads t where t.id=thread_id and (t.user_id=auth.uid() or public.is_staff())) and sender_id=auth.uid());
create policy "events insert" on public.events for insert with check(user_id is null or user_id=auth.uid());
create policy "events staff read" on public.events for select using(public.is_staff());

-- Staff-only operations; no direct client-side writes to money/order tables.
create policy "staff read ledger" on public.ledger_entries for select using(public.is_admin());
create policy "admin manage ledger" on public.ledger_entries for all using(public.is_admin()) with check(public.is_admin());
create policy "admin manage withdrawals" on public.withdrawal_requests for all using(public.is_admin()) with check(public.is_admin());
create policy "admin read audit" on public.audit_log for select using(public.is_admin());
create policy "admin insert audit" on public.audit_log for insert with check(public.is_admin());
create policy "admin read crm queue" on public.crm_queue for select using(public.is_admin());

grant usage on schema public to anon, authenticated;
grant select on public.categories,public.products,public.product_variants,public.variant_sizes,public.site_settings,public.vip_tiers,public.outfits,public.outfit_items,public.public_reviews,public.product_rating_stats to anon,authenticated;
grant select on public.coupons to authenticated;
grant insert,update,delete on public.outfits,public.outfit_items to authenticated;
grant update on public.vip_tiers to authenticated;
grant select,update on public.profiles to authenticated;
grant select on public.orders,public.order_items,public.order_events to authenticated;
grant select,insert,delete on public.wishlist to authenticated;
grant select,insert,update,delete on public.cart_snapshots to authenticated;
grant select,insert on public.chat_threads,public.chat_messages to authenticated;
grant insert on public.events to anon,authenticated;
grant select on public.reviews,public.payments,public.product_costs,public.ledger_entries,public.withdrawal_requests,public.audit_log,public.crm_queue to authenticated;
grant insert,update,delete on public.products,public.product_variants,public.variant_sizes to authenticated;
grant insert,update,delete on public.categories,public.coupons,public.vip_tiers,public.site_settings,public.product_costs,public.ledger_entries,public.withdrawal_requests,public.audit_log,public.crm_queue to authenticated;

-- RPC execute grants. RLS still applies to direct table access; SECURITY DEFINER functions enforce roles.
grant execute on function public.my_vip() to authenticated;
grant execute on function public.preview_coupon(text,bigint) to anon,authenticated;
grant execute on function public.place_order(jsonb,text,text,text,text,text,text,text,text,integer,text) to authenticated;
grant execute on function public.track_order(text,text) to anon,authenticated;
grant execute on function public.report_deposit_transfer(uuid,text) to authenticated;
grant execute on function public.submit_review(uuid,integer,text,text,text[]) to authenticated;
grant execute on function public.admin_set_order_status(uuid,text,text) to authenticated;
grant execute on function public.admin_set_shipping(uuid,text,text) to authenticated;
grant execute on function public.admin_set_internal_note(uuid,text) to authenticated;
grant execute on function public.admin_confirm_payment(uuid) to authenticated;
grant execute on function public.admin_reject_payment(uuid,text) to authenticated;
grant execute on function public.admin_refund(uuid,bigint,text) to authenticated;
grant execute on function public.admin_moderate_review(uuid,text) to authenticated;
grant execute on function public.admin_set_role(uuid,text) to authenticated;
grant execute on function public.admin_request_withdrawal(bigint,text,text,text) to authenticated;
grant execute on function public.admin_decide_withdrawal(uuid,text,text) to authenticated;
grant execute on function public.wallet_summary() to authenticated;
grant execute on function public.admin_dashboard(integer) to authenticated;
grant execute on function public.admin_crm() to authenticated;
grant execute on function public.admin_queue_crm(text,text) to authenticated;

-- Product media bucket. Public reads, authenticated staff uploads only.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('product-media','product-media',true,10485760,array['image/jpeg','image/png','image/webp','image/avif','video/mp4','video/webm'])
on conflict(id) do update set public=true;
create policy "public read product media" on storage.objects for select using(bucket_id='product-media');
create policy "staff upload product media" on storage.objects for insert to authenticated with check(bucket_id='product-media' and public.is_staff());
create policy "staff update product media" on storage.objects for update to authenticated using(bucket_id='product-media' and public.is_staff()) with check(bucket_id='product-media' and public.is_staff());
create policy "staff delete product media" on storage.objects for delete to authenticated using(bucket_id='product-media' and public.is_staff());
