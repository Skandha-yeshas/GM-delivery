-- Existing projects: run this file in the Supabase SQL Editor.
-- Adds saved Maps links without replacing shops, roles or delivery history.
begin;
alter table public.shops add column if not exists maps_url text not null default ''
  check (length(maps_url) <= 4096);

create or replace function public.save_shop(p_shop jsonb, p_expected_version integer) returns jsonb
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
notify pgrst, 'reload schema';
commit;

