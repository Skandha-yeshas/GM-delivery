-- TEST ONLY: run with psql against an EMPTY, disposable PostgreSQL database.
-- Minimal stand-ins for Supabase-owned auth/storage objects; never run on Supabase.
\set ON_ERROR_STOP on
create role anon;
create role authenticated;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.user_id', true), '')::uuid;
$$;
grant usage on schema auth to authenticated;
create schema storage;
create table storage.buckets(id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key, bucket_id text, name text);
create function storage.foldername(text) returns text[] language sql immutable as $$
  select string_to_array($1, '/');
$$;

\ir ../schema.sql
\ir ../migrations/20261014_owner_import.sql
\ir ../migrations/20261015_maps_link_delivery.sql
-- The existing-project update must be safe to retry.
\ir ../migrations/20261015_maps_link_delivery.sql

do $$
declare link text;
begin
  foreach link in array array['https://maps.app.goo.gl/example',
    'https://goo.gl/maps/example', 'https://www.google.com/maps/place/Shop',
    'https://maps.google.com/?q=12.3,77.5',
    'https://www.google.co.in/maps/search/?api=1&query=Shop'] loop
    if not public.is_google_maps_link(link) then raise exception 'REJECTED_MAPS_LINK: %', link; end if;
  end loop;
  foreach link in array array['', 'Main Road', 'https://evil.test/maps',
    'https://www.google.com.evil.test/maps', 'https://user@www.google.com/maps',
    'http://www.google.com/maps', 'https://goo.gl/unrelated',
    'https://maps.app.goo.gl:444/example', 'https://www.google.com/search?q=shop'] loop
    if public.is_google_maps_link(link) then raise exception 'ACCEPTED_INVALID_LINK: %', link; end if;
  end loop;
end;
$$;

insert into auth.users values
  ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
insert into public.profiles values
  ('00000000-0000-0000-0000-000000000001', 'Owner', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'Driver', 'driver');
set test.user_id = '00000000-0000-0000-0000-000000000001';
-- Represents an existing saved link: no coordinates and verified=false.
insert into public.shops(id, name, area, maps_url) values
  ('10000000-0000-0000-0000-000000000001', 'Link Only', 'Market', 'https://maps.app.goo.gl/example'),
  ('10000000-0000-0000-0000-000000000002', 'No Location', 'Market', ''),
  ('10000000-0000-0000-0000-000000000003', 'Bad Link', 'Market', 'https://evil.test/maps');
insert into public.shops(id, name, area, latitude, longitude, verified) values
  ('10000000-0000-0000-0000-000000000004', 'Unverified Pin', 'Market', 12.3, 77.5, false),
  ('10000000-0000-0000-0000-000000000005', 'Verified Pin', 'Market', 12.3, 77.5, true);

set role authenticated;
insert into public.delivery_stops(id, shop_id, service_date, driver_id, stop_order, status)
select gen_random_uuid(), id, '2026-10-15', '00000000-0000-0000-0000-000000000002', 1, 'delivered'
from public.shops where name in ('Link Only', 'Verified Pin');
do $$
declare shop_id uuid;
begin
  if (select count(*) from public.delivery_stops) <> 2 then raise exception 'MISSING_ACCEPTED_STOPS'; end if;
  if exists(select 1 from public.delivery_stops where status <> 'pending') then raise exception 'STATUS_NOT_RESET'; end if;
  foreach shop_id in array array['10000000-0000-0000-0000-000000000002'::uuid,
    '10000000-0000-0000-0000-000000000003'::uuid, '10000000-0000-0000-0000-000000000004'::uuid] loop
    begin
      insert into public.delivery_stops(id, shop_id, service_date, driver_id, stop_order)
      values(gen_random_uuid(), shop_id, '2026-10-15', '00000000-0000-0000-0000-000000000002', 2);
      raise exception 'INVALID_LOCATION_ACCEPTED';
    exception when raise_exception then
      if sqlerrm <> 'LOCATION_REQUIRED' then raise; end if;
    end;
  end loop;
  begin
    insert into public.delivery_stops(id, shop_id, service_date, driver_id, stop_order)
    values(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '2026-10-15', '00000000-0000-0000-0000-000000000002', 2);
    raise exception 'DUPLICATE_ACCEPTED';
  exception when unique_violation then null;
  end;
  begin
    insert into public.delivery_stops(id, shop_id, service_date, driver_id, stop_order)
    values(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '2026-10-16', '00000000-0000-0000-0000-000000000001', 2);
    raise exception 'OWNER_AS_DRIVER_ACCEPTED';
  exception when raise_exception then
    if sqlerrm <> 'INVALID_DRIVER' then raise; end if;
  end;
end;
$$;
set test.user_id = '00000000-0000-0000-0000-000000000002';
do $$
begin
  begin
    insert into public.delivery_stops(id, shop_id, service_date, driver_id, stop_order)
    values(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '2026-10-16', auth.uid(), 2);
    raise exception 'DRIVER_ASSIGNED_STOP';
  exception when raise_exception then
    if sqlerrm <> 'OWNER_REQUIRED' then raise; end if;
  end;
end;
$$;
reset role;
select 'Maps-link SQL checks passed' as result;
