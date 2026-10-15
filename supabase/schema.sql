-- Run once in the SQL editor of a NEW Supabase project.
-- No billing tables or Tally connection. All app accounts are provisioned manually.
begin;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 200),
  role text not null check (role in ('owner', 'driver'))
);
alter table public.profiles enable row level security;

create function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'owner');
$$;
revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_owner() to authenticated;
create policy profile_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_owner());
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

create table public.shops (
  id uuid primary key,
  name text not null check (length(trim(name)) between 1 and 200),
  area text not null check (length(trim(area)) between 1 and 200),
  address text not null default '' check (length(address) <= 1000),
  landmark text not null default '' check (length(landmark) <= 500),
  phone text not null default '' check (length(phone) <= 30),
  notes text not null default '' check (length(notes) <= 1000),
  maps_url text not null default '' check (length(maps_url) <= 4096),
  latitude double precision, longitude double precision,
  verified boolean not null default false,
  photo_path text,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid not null default auth.uid() references public.profiles(id),
  check ((latitude is null and longitude is null) or
    (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180)),
  check (not verified or (latitude is not null and longitude is not null)),
  check (photo_path is null or photo_path ~ ('^' || id::text || '/[0-9a-f-]{36}\.jpg$'))
);
alter table public.shops enable row level security;

create table public.delivery_stops (
  id uuid primary key,
  shop_id uuid not null references public.shops(id),
  service_date date not null,
  driver_id uuid not null references public.profiles(id),
  stop_order integer not null check (stop_order > 0),
  status text not null default 'pending' check (status in ('pending', 'delivered', 'failed')),
  reason text not null default '' check (length(reason) <= 500),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references public.profiles(id),
  unique (shop_id, service_date),
  check (status <> 'failed' or length(trim(reason)) > 0)
);
create index delivery_driver_date on public.delivery_stops(driver_id, service_date);
alter table public.delivery_stops enable row level security;
create policy delivery_read on public.delivery_stops for select to authenticated
  using (public.is_owner() or driver_id = auth.uid());
create policy delivery_create on public.delivery_stops for insert to authenticated
  with check (public.is_owner());
create policy shop_read on public.shops for select to authenticated
  using (public.is_owner() or exists (
    select 1 from public.delivery_stops where shop_id = shops.id and driver_id = auth.uid()
  ));
revoke all on public.shops, public.delivery_stops from anon, authenticated;
grant select on public.shops to authenticated;
grant select, insert on public.delivery_stops to authenticated;

create table public.shop_history (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops(id),
  actor_id uuid not null references public.profiles(id),
  recorded_at timestamptz not null default now(),
  snapshot jsonb not null
);
alter table public.shop_history enable row level security;
create policy shop_history_read on public.shop_history for select to authenticated using (public.is_owner());
revoke all on public.shop_history from anon, authenticated;
grant select on public.shop_history to authenticated;

create table public.visit_events (
  operation_id uuid primary key,
  stop_id uuid not null,
  actor_id uuid not null references public.profiles(id),
  status text not null,
  reason text not null,
  expected_version integer not null,
  recorded_at timestamptz not null default now(),
  result jsonb not null
);
alter table public.visit_events enable row level security;
create policy visit_history_read on public.visit_events for select to authenticated
  using (public.is_owner() or actor_id = auth.uid());
revoke all on public.visit_events from anon, authenticated;
grant select on public.visit_events to authenticated;

create or replace function public.is_google_maps_link(p_url text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(
    length(trim(p_url)) between 1 and 4096
    and trim(p_url) !~ '[[:space:]]'
    and trim(p_url) ~* '^https://((maps[.]app[.]goo[.]gl|maps[.]google[.](com|co[.]in))(:443)?([/?#]|$)|(www[.])?google[.](com|co[.]in)(:443)?/maps|goo[.]gl(:443)?/maps/)',
    false);
$$;
revoke all on function public.is_google_maps_link(text) from public, anon, authenticated;

create function public.check_new_stop() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  if not exists (select 1 from public.profiles where id = new.driver_id and role = 'driver') then
    raise exception 'INVALID_DRIVER';
  end if;
  if not exists (select 1 from public.shops where id = new.shop_id and (
    public.is_google_maps_link(maps_url)
    or (verified and latitude is not null and longitude is not null)
  )) then
    raise exception 'LOCATION_REQUIRED';
  end if;
  new.status := 'pending'; new.reason := ''; new.version := 1;
  new.created_by := auth.uid(); new.created_at := now(); new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.check_new_stop() from public, anon, authenticated;
create trigger check_delivery_insert before insert on public.delivery_stops
  for each row execute function public.check_new_stop();

create function public.save_shop(p_shop jsonb, p_expected_version integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := (p_shop->>'id')::uuid;
  v_shop public.shops;
begin
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  if p_expected_version = 0 then
    insert into public.shops(id, name, area, address, landmark, phone, notes, maps_url,
      latitude, longitude, verified, photo_path, updated_by)
    values (v_id, trim(p_shop->>'name'), trim(p_shop->>'area'),
      coalesce(p_shop->>'address',''), coalesce(p_shop->>'landmark',''),
      coalesce(p_shop->>'phone',''), coalesce(p_shop->>'notes',''),
      coalesce(p_shop->>'maps_url',''),
      (p_shop->>'latitude')::double precision, (p_shop->>'longitude')::double precision,
      coalesce((p_shop->>'verified')::boolean,false), p_shop->>'photo_path', auth.uid())
    returning * into v_shop;
  else
    select * into v_shop from public.shops where id = v_id for update;
    if not found or v_shop.version is distinct from p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
    update public.shops set name = trim(p_shop->>'name'), area = trim(p_shop->>'area'),
      address = coalesce(p_shop->>'address',''), landmark = coalesce(p_shop->>'landmark',''),
      phone = coalesce(p_shop->>'phone',''), notes = coalesce(p_shop->>'notes',''),
      maps_url = coalesce(p_shop->>'maps_url', maps_url),
      latitude = (p_shop->>'latitude')::double precision,
      longitude = (p_shop->>'longitude')::double precision,
      verified = coalesce((p_shop->>'verified')::boolean,false),
      photo_path = p_shop->>'photo_path', version = version + 1,
      updated_at = now(), updated_by = auth.uid()
    where id = v_id returning * into v_shop;
  end if;
  insert into public.shop_history(shop_id, actor_id, snapshot)
    values(v_id, auth.uid(), to_jsonb(v_shop));
  return to_jsonb(v_shop);
end;
$$;
revoke all on function public.save_shop(jsonb, integer) from public, anon;
grant execute on function public.save_shop(jsonb, integer) to authenticated;

create function public.record_visit(p_operation_id uuid, p_stop_id uuid,
  p_status text, p_reason text, p_expected_version integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_stop public.delivery_stops;
  v_event public.visit_events;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  -- Serialize retries using the same operation ID, including a lost response.
  perform pg_advisory_xact_lock(hashtextextended(p_operation_id::text, 0));
  select * into v_event from public.visit_events where operation_id = p_operation_id;
  if found then
    if v_event.actor_id <> auth.uid() or v_event.stop_id <> p_stop_id
      or v_event.status <> p_status or v_event.reason <> coalesce(p_reason,'')
      or v_event.expected_version is distinct from p_expected_version then raise exception 'OPERATION_MISMATCH'; end if;
    return v_event.result;
  end if;
  select * into v_stop from public.delivery_stops where id = p_stop_id for update;
  if not found then raise exception 'NOT_ASSIGNED'; end if;
  if not public.is_owner() and (v_stop.driver_id <> auth.uid() or not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'driver')) then
    raise exception 'NOT_ASSIGNED';
  end if;
  if v_stop.version is distinct from p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if p_status not in ('pending', 'delivered', 'failed') or p_status is null then raise exception 'INVALID_STATUS'; end if;
  if p_status = 'failed' and length(trim(coalesce(p_reason,''))) = 0 then raise exception 'REASON_REQUIRED'; end if;
  update public.delivery_stops set status = p_status,
    reason = case when p_status = 'failed' then trim(p_reason) else '' end,
    version = version + 1, updated_at = now()
    where id = p_stop_id returning * into v_stop;
  insert into public.visit_events(operation_id, stop_id, actor_id, status, reason, expected_version, result)
    values(p_operation_id, p_stop_id, auth.uid(), p_status, coalesce(p_reason,''), p_expected_version, to_jsonb(v_stop));
  return to_jsonb(v_stop);
end;
$$;
revoke all on function public.record_visit(uuid, uuid, text, text, integer) from public, anon;
grant execute on function public.record_visit(uuid, uuid, text, text, integer) to authenticated;

create function public.remove_stop(p_stop_id uuid, p_expected_version integer) returns void
language plpgsql security definer set search_path = public as $$
declare v_stop public.delivery_stops;
begin
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  select * into v_stop from public.delivery_stops where id = p_stop_id for update;
  if not found or v_stop.version is distinct from p_expected_version then raise exception 'VERSION_CONFLICT'; end if;
  if v_stop.status <> 'pending' then raise exception 'ONLY_PENDING_STOPS'; end if;
  -- Preserve any history even when an owner removes a pending assignment.
  insert into public.visit_events(operation_id, stop_id, actor_id, status, reason, expected_version, result)
    values(gen_random_uuid(), p_stop_id, auth.uid(), 'removed', '', p_expected_version, to_jsonb(v_stop));
  delete from public.delivery_stops where id = p_stop_id;
end;
$$;
revoke all on function public.remove_stop(uuid, integer) from public, anon;
grant execute on function public.remove_stop(uuid, integer) to authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
  values ('shop-photos', 'shop-photos', false, 5242880, array['image/jpeg']);
create policy shop_photo_read on storage.objects for select to authenticated
  using (bucket_id = 'shop-photos' and (public.is_owner() or exists (
    select 1 from public.delivery_stops where shop_id::text = (storage.foldername(name))[1]
      and driver_id = auth.uid()
  )));
create policy shop_photo_create on storage.objects for insert to authenticated
  with check (bucket_id = 'shop-photos' and public.is_owner());
-- Images use immutable UUID filenames. No app account can overwrite objects.
commit;
