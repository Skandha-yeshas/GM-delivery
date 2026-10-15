-- Existing projects: run after 20261014_owner_import.sql in Supabase SQL Editor.
-- Accept saved Google Maps locations without requiring extracted coordinates.
-- Existing shops, stop history, permissions and coordinate verification are preserved.
begin;

create or replace function public.is_google_maps_link(p_url text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(
    length(trim(p_url)) between 1 and 4096
    and trim(p_url) !~ '[[:space:]]'
    and trim(p_url) ~* '^https://((maps[.]app[.]goo[.]gl|maps[.]google[.](com|co[.]in))(:443)?([/?#]|$)|(www[.])?google[.](com|co[.]in)(:443)?/maps|goo[.]gl(:443)?/maps/)',
    false);
$$;
revoke all on function public.is_google_maps_link(text) from public, anon, authenticated;

create or replace function public.check_new_stop() returns trigger
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

notify pgrst, 'reload schema';
commit;
