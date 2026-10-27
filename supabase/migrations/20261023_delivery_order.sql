-- Apply after 20261020_shop_profiles.sql. Safe to run again.
begin;
create table if not exists public.route_order_events (
  operation_id uuid primary key,
  actor_id uuid not null references public.profiles(id),
  driver_id uuid not null references public.profiles(id),
  service_date date not null,
  payload jsonb not null,
  before_order jsonb not null,
  after_order jsonb not null,
  recorded_at timestamptz not null default now()
);
alter table public.route_order_events enable row level security;
drop policy if exists route_order_read on public.route_order_events;
create policy route_order_read on public.route_order_events for select to authenticated
  using (public.is_owner());
revoke all on public.route_order_events from public,anon,authenticated;
grant select on public.route_order_events to authenticated;

create or replace function public.save_route_order(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := (p_payload->>'operation_id')::uuid;
  v_driver uuid := (p_payload->>'driver_id')::uuid;
  v_date date := (p_payload->>'service_date')::date;
  v_prior public.route_order_events;
  v_before jsonb; v_after jsonb; v_pending jsonb; v_action text;
begin
  if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  if v_id is null or v_driver is null or v_date is null
    or jsonb_typeof(p_payload->'expected') is distinct from 'array'
    or jsonb_typeof(p_payload->'pending_ids') is distinct from 'array'
    then raise exception 'INVALID_ROUTE'; end if;
  if not exists(select 1 from public.profiles where id=v_driver and role='driver') then raise exception 'INVALID_DRIVER'; end if;
  -- Same outer lock used by stop insertion, ledger writes and settlements.
  perform pg_advisory_xact_lock(hashtextextended('settlement-day:'||v_driver::text||':'||v_date::text,0));
  perform pg_advisory_xact_lock(hashtextextended('route-order:'||v_id::text,0));
  select * into v_prior from public.route_order_events where operation_id=v_id;
  if found then
    if v_prior.actor_id<>auth.uid() or v_prior.payload<>p_payload then raise exception 'OPERATION_MISMATCH'; end if;
    -- A retry acknowledges the commit, without restoring an obsolete route.
    return (select coalesce(jsonb_agg(to_jsonb(s) order by stop_order,id),'[]'::jsonb)
      from public.delivery_stops s where driver_id=v_driver and service_date=v_date);
  end if;
  select action into v_action from public.settlement_events where driver_id=v_driver and service_date=v_date order by revision desc limit 1;
  if v_action in ('submit','approve') then raise exception 'SETTLEMENT_LOCKED'; end if;
  -- Stable row-lock order protects concurrent visit completion/removal.
  perform id from public.delivery_stops where driver_id=v_driver and service_date=v_date order by id for update;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'stop_order',stop_order,'version',version,'status',status) order by id),'[]'::jsonb)
    into v_before from public.delivery_stops where driver_id=v_driver and service_date=v_date;
  if v_before='[]'::jsonb or v_before is distinct from p_payload->'expected' then raise exception 'ROUTE_CHANGED'; end if;
  select coalesce(jsonb_agg(to_jsonb(id::text) order by id),'[]'::jsonb) into v_pending
    from public.delivery_stops where driver_id=v_driver and service_date=v_date and status='pending';
  -- Exactly the pending stop IDs, once each; foreign/completed stops cannot be moved.
  if (select coalesce(jsonb_agg(value order by value),'[]'::jsonb) from jsonb_array_elements(p_payload->'pending_ids')) <> v_pending
    then raise exception 'INVALID_ROUTE'; end if;
  with slots as (
    select id,status,row_number() over(order by stop_order,id) as position,
      sum(case when status='pending' then 1 else 0 end) over(order by stop_order,id) as pending_position
    from public.delivery_stops where driver_id=v_driver and service_date=v_date
  ), desired as (
    select case when status='pending' then (p_payload->'pending_ids'->>(pending_position::integer-1))::uuid else id end as id,
      position::integer as position from slots
  ) update public.delivery_stops s set stop_order=d.position,updated_at=now()
      from desired d where s.id=d.id and s.stop_order<>d.position;
  -- Route edits deliberately preserve visit versions, status and all financial data:
  -- a driver's legitimate offline visit must still sync after an owner reorders.
  select jsonb_agg(jsonb_build_object('id',id,'stop_order',stop_order,'version',version,'status',status) order by id)
    into v_after from public.delivery_stops where driver_id=v_driver and service_date=v_date;
  insert into public.route_order_events(operation_id,actor_id,driver_id,service_date,payload,before_order,after_order)
    values(v_id,auth.uid(),v_driver,v_date,p_payload,v_before,v_after);
  return (select jsonb_agg(to_jsonb(s) order by stop_order,id)
    from public.delivery_stops s where driver_id=v_driver and service_date=v_date);
end;
$$;
revoke all on function public.save_route_order(jsonb) from public,anon;
grant execute on function public.save_route_order(jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
