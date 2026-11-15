-- Publicly readable active vouchers and database change feeds used by the live storefront.
grant select on public.coupons to anon,authenticated;
drop policy if exists "public read active coupons" on public.coupons;
create policy "public read active coupons" on public.coupons for select using(active or public.is_staff());

do $$
declare t text;
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array['products','coupons','site_settings','orders','profiles','chat_threads','chat_messages'] loop
      if to_regclass('public.'||t) is not null and not exists(
        select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t
      ) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end $$;
notify pgrst, 'reload schema';
