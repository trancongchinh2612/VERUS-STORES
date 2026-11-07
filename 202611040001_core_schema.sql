
-- VERUS STORE: core schema for the supplied Customer + Admin HTML apps.
-- Run once in Supabase SQL Editor or with `supabase db push`.
-- Security model: browser uses anon/publishable key only; writes go through guarded RPCs.

create extension if not exists pgcrypto;

do $$ begin
  create type public.verus_order_status as enum
    ('pending','confirmed','sourcing','supplier_ordered','in_transit_vn','inspecting','shipping','delivered','return_requested','cancelled','refunded');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'customer' check (role in ('customer','staff','admin')),
  points integer not null default 0 check (points >= 0),
  highest_tier text,
  marketing_opt_in boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  name text not null,
  category text,
  status text not null default 'hidden' check (status in ('active','hidden','draft')),
  badge text,
  material text,
  fit text,
  care text,
  delivery_note text,
  description_html text,
  style_tags text[] not null default '{}',
  occasion text,
  styling_tips text,
  price bigint not null default 0 check (price >= 0),
  compare_price bigint check (compare_price is null or compare_price >= 0),
  size_chart jsonb,
  size_rules jsonb,
  featured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null default 'Mặc định',
  sku text not null unique,
  image_urls text[] not null default '{}',
  video_urls text[] not null default '{}',
  sort integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.variant_sizes (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  size text not null default 'Free Size',
  stock integer not null default 0 check (stock >= 0),
  unique (variant_id, size)
);

create table if not exists public.product_costs (
  product_id uuid primary key references public.products(id) on delete cascade,
  base_cost bigint not null default 0,
  extra_cost bigint not null default 0,
  target_profit bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text,
  kind text not null default 'percent' check (kind in ('percent','fixed','shipping')),
  value bigint not null default 0,
  min_subtotal bigint not null default 0,
  max_discount bigint,
  usage_limit integer,
  used_count integer not null default 0,
  per_user_limit integer not null default 1,
  min_tier text,
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.vip_tiers (
  code text primary key,
  name text not null,
  min_spend_12m bigint not null default 0,
  points_multiplier numeric(8,3) not null default 1,
  sort integer not null default 0
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  user_id uuid not null references public.profiles(id),
  customer_name text not null,
  phone text not null,
  province text not null,
  ward text not null,
  street text not null,
  note text,
  status public.verus_order_status not null default 'pending',
  deposit_status text not null default 'unpaid' check (deposit_status in ('unpaid','pending_review','confirmed','refunded')),
  pay_method text not null check (pay_method in ('cod_balance','bank_transfer_full')),
  subtotal bigint not null default 0,
  shipping_fee bigint not null default 0,
  discount bigint not null default 0,
  points_discount bigint not null default 0,
  total bigint not null default 0,
  deposit_percent numeric(5,2) not null default 20,
  deposit_amount bigint not null default 0,
  balance_amount bigint not null default 0,
  coupon_code text,
  points_used integer not null default 0,
  carrier text,
  tracking_code text,
  internal_note text,
  eta_date date,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, idempotency_key)
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  variant_id uuid references public.product_variants(id) on delete set null,
  product_name text not null,
  variant_name text,
  sku text,
  size text,
  qty integer not null check (qty > 0),
  price bigint not null check (price >= 0),
  line_total bigint not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  status text not null,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  type text not null default 'deposit' check (type in ('deposit','full','refund')),
  amount bigint not null check (amount >= 0),
  reference text,
  status text not null default 'pending' check (status in ('pending','confirmed','rejected','refunded')),
  note text,
  confirmed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wishlist (
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, product_id)
);

create table if not exists public.cart_snapshots (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  items jsonb not null default '[]',
  updated_at timestamptz not null default now()
);

create table if not exists public.outfits (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  style_tag text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.outfit_items (
  id uuid primary key default gen_random_uuid(),
  outfit_id uuid not null references public.outfits(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  role text,
  sort integer not null default 0,
  unique(outfit_id, product_id)
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null unique references public.order_items(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  title text,
  body text not null,
  photos text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','published','rejected')),
  created_at timestamptz not null default now(),
  moderated_at timestamptz
);

create table if not exists public.chat_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  kind text not null default 'support' check (kind in ('support','complaint')),
  subject text not null,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  sender_id uuid default auth.uid() references auth.users(id),
  sender_role text not null default 'customer' check (sender_role in ('customer','staff','admin')),
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles(id) on delete set null,
  session_id text,
  name text not null,
  props jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.ledger_entries (
  id bigint generated always as identity primary key,
  direction text not null check (direction in ('credit','debit')),
  kind text not null,
  amount bigint not null check (amount >= 0),
  note text,
  order_id uuid references public.orders(id) on delete set null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  amount bigint not null check (amount > 0),
  bank text not null,
  owner text not null,
  hint text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid_manually')),
  note text,
  requested_by uuid references auth.users(id),
  decided_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id),
  action text not null,
  entity text,
  entity_id text,
  detail jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.crm_queue (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  segment text not null,
  template text not null,
  status text not null default 'queued',
  created_at timestamptz not null default now()
);

create or replace view public.product_rating_stats as
select product_id, round(avg(rating)::numeric,2) as rating_avg, count(*)::integer as review_count
from public.reviews where status='published' group by product_id;

create or replace view public.public_reviews as
select r.id,r.product_id,r.user_id,r.rating,r.title,r.body,r.photos,r.created_at
from public.reviews r where r.status='published';

create index if not exists idx_products_status_created on public.products(status,created_at desc);
create index if not exists idx_variants_product on public.product_variants(product_id);
create index if not exists idx_sizes_variant on public.variant_sizes(variant_id);
create index if not exists idx_orders_user_created on public.orders(user_id,created_at desc);
create index if not exists idx_orders_status_created on public.orders(status,created_at desc);
create index if not exists idx_order_items_order on public.order_items(order_id);
create index if not exists idx_payments_status_created on public.payments(status,created_at);
create index if not exists idx_reviews_product_status on public.reviews(product_id,status);
create index if not exists idx_chat_threads_last on public.chat_threads(last_message_at desc);

insert into public.site_settings(key,value) values
 ('deposit_percent','20'::jsonb),
 ('lead_days','15'::jsonb),
 ('shipping_fee','30000'::jsonb),
 ('free_shipping_threshold','500000'::jsonb),
 ('payment_cod_enabled','true'::jsonb),
 ('payment_bank_enabled','true'::jsonb),
 ('policy_text','""'::jsonb),
 ('redeem_vnd_per_point','500'::jsonb),
 ('max_redeem_percent','30'::jsonb)
on conflict(key) do nothing;

insert into public.categories(name,sort) values
 ('Áo',1),('Áo khoác',2),('Quần',3),('Giày',4),('Dép',5),('Mũ',6),('Phụ kiện',7)
on conflict(name) do nothing;

insert into public.vip_tiers(code,name,min_spend_12m,points_multiplier,sort) values
 ('member','Member',0,1,1),('silver','Silver',2000000,1.1,2),('gold','Gold',5000000,1.25,3),('diamond','Diamond',12000000,1.5,4)
on conflict(code) do nothing;
