-- Milestone 2. Apply after 20261016_collections_ledger.sql. No history is rewritten.
begin;
create table public.settlement_events (
  operation_id uuid primary key,
  driver_id uuid not null references public.profiles(id),
  service_date date not null,
  actor_id uuid not null references public.profiles(id),
  action text not null check(action in ('submit','approve','reopen')),
  revision integer not null check(revision > 0),
  payload jsonb not null,
  totals jsonb not null,
  recorded_at timestamptz not null default clock_timestamp(),
  unique(driver_id,service_date,revision),
  check(payload->>'operation_id' = operation_id::text),
  check(payload->>'driver_id' = driver_id::text),
  check(payload->>'service_date' = service_date::text),
  check(payload->>'action' = action)
);
alter table public.settlement_events enable row level security;
create policy settlement_read on public.settlement_events for select to authenticated
  using(public.is_owner() or driver_id = auth.uid());
revoke all on public.settlement_events from public,anon,authenticated;
grant select on public.settlement_events to authenticated;
-- The append-only events are both state transitions and their complete audit log.
create trigger settlement_immutable before update or delete on public.settlement_events
  for each row execute function public.reject_ledger_mutation();

create function public.settlement_totals(p_driver uuid,p_date date) returns jsonb
language sql stable security definer set search_path = '' as $$
  with roots as (
    select * from public.ledger_events where kind in ('bill','payment')
      and stop_after->>'driver_id' = p_driver::text and (stop_after->>'service_date')::date = p_date
  ), effective as (
    select b.kind,e.payload,e.sequence from roots b cross join lateral (
      select payload,sequence from public.ledger_events
      where operation_id = b.operation_id or original_id = b.operation_id order by revision desc limit 1
    ) e
  ), totals as (
    select coalesce(sum((payload->>'bill_paise')::bigint) filter(where kind='bill'),0)::bigint bills,
      coalesce(sum((payload->>'collected_paise')::bigint) filter(where kind='payment'),0)::bigint old_payments,
      coalesce(sum((payload->>'collected_paise')::bigint) filter(where payload->>'mode'='cash'),0)::bigint cash,
      coalesce(sum((payload->>'collected_paise')::bigint) filter(where payload->>'mode'='upi'),0)::bigint upi,
      coalesce(sum((payload->>'collected_paise')::bigint) filter(where payload->>'mode'='cheque'),0)::bigint cheque,
      coalesce(sum((payload->>'bill_paise')::bigint-(payload->>'collected_paise')::bigint) filter(where kind='bill'),0)::bigint credit,
      coalesce(max(sequence),0) ledger_version from effective
  ) select to_jsonb(t) from totals t;
$$;
revoke all on function public.settlement_totals(uuid,date) from public,anon,authenticated;

create function public.settlement_day(p_driver uuid,p_date date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_owner() and p_driver is distinct from auth.uid() then raise exception 'NOT_ASSIGNED'; end if;
  return jsonb_build_object('driver_id',p_driver,'service_date',p_date,
    'totals',public.settlement_totals(p_driver,p_date),
    'events',coalesce((select jsonb_agg(to_jsonb(e) order by revision) from public.settlement_events e
      where driver_id=p_driver and service_date=p_date),'[]'::jsonb));
end;
$$;
revoke all on function public.settlement_day(uuid,date) from public,anon;
grant execute on function public.settlement_day(uuid,date) to authenticated;

create function public.settlement_snapshot(p_offset integer default 0,p_limit integer default 500) returns setof jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'AUTH_REQUIRED'; end if;
  if p_offset<0 or p_limit<1 or p_limit>500 then raise exception 'INVALID_PAGE'; end if;
  return query with days as (
    select driver_id,service_date from public.delivery_stops
    union select id,(now() at time zone 'Asia/Kolkata')::date from public.profiles where role='driver'
    union select driver_id,service_date from public.settlement_events
    union select (stop_after->>'driver_id')::uuid,(stop_after->>'service_date')::date
      from public.ledger_events where kind in ('bill','payment')
  ) select public.settlement_day(driver_id,service_date) from days
    where public.is_owner() or driver_id=auth.uid() order by service_date,driver_id limit p_limit offset p_offset;
end;
$$;
revoke all on function public.settlement_snapshot(integer,integer) from public,anon;
grant execute on function public.settlement_snapshot(integer,integer) to authenticated;

create function public.record_settlement(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := (p_payload->>'operation_id')::uuid;
  v_driver uuid := (p_payload->>'driver_id')::uuid;
  v_date date := (p_payload->>'service_date')::date;
  v_action text := p_payload->>'action';
  v_revision integer; v_handed bigint; v_totals jsonb;
  v_prior public.settlement_events; v_event public.settlement_events;
begin
  if not exists(select 1 from public.profiles where id=auth.uid()) then raise exception 'AUTH_REQUIRED'; end if;
  if v_id is null or v_driver is null or v_date is null then raise exception 'INVALID_SETTLEMENT'; end if;
  -- Keep JSON types consistent with the durable phone payload. A direct RPC
  -- caller must not be able to store strings in integer fields or numeric notes.
  if jsonb_typeof(p_payload->'reason') is distinct from 'string'
    or jsonb_typeof(p_payload->'captured_at') is distinct from 'string'
    or jsonb_typeof(p_payload->'expected_revision') is distinct from 'number'
    or jsonb_typeof(p_payload->'ledger_version') is distinct from 'number'
    or coalesce(p_payload->>'expected_revision','') !~ '^[0-9]{1,10}$'
    or coalesce(p_payload->>'ledger_version','') !~ '^[0-9]{1,19}$'
    then raise exception 'INVALID_SETTLEMENT'; end if;
  -- Same outer lock as ledger writes: day, then operation, then existing shop/stop locks.
  perform pg_advisory_xact_lock(hashtextextended('settlement-day:'||v_driver::text||':'||v_date::text,0));
  perform pg_advisory_xact_lock(hashtextextended('settlement-op:'||v_id::text,0));
  select * into v_event from public.settlement_events where operation_id=v_id;
  if found then
    if v_event.actor_id<>auth.uid() or v_event.payload<>p_payload then raise exception 'OPERATION_MISMATCH'; end if;
    return public.settlement_day(v_driver,v_date);
  end if;
  if v_action='submit' then
    if v_driver<>auth.uid() or not exists(select 1 from public.profiles where id=auth.uid() and role='driver')
      then raise exception 'DRIVER_REQUIRED'; end if;
  elsif v_action in ('approve','reopen') then
    if not public.is_owner() then raise exception 'OWNER_REQUIRED'; end if;
  else raise exception 'INVALID_SETTLEMENT'; end if;
  if not exists(select 1 from public.profiles where id=v_driver and role='driver') then raise exception 'DRIVER_REQUIRED'; end if;
  if v_date > (now() at time zone 'Asia/Kolkata')::date then raise exception 'FUTURE_SETTLEMENT'; end if;
  if jsonb_typeof(p_payload->'handed_paise') is distinct from 'number'
    or coalesce(p_payload->>'handed_paise','') !~ '^[0-9]{1,12}$' then raise exception 'INVALID_MONEY'; end if;
  v_handed := (p_payload->>'handed_paise')::bigint;
  if v_handed>100000000000 then raise exception 'INVALID_MONEY'; end if;
  if length(coalesce(p_payload->>'reason',''))>500 or (p_payload->>'captured_at')::timestamptz is null then raise exception 'INVALID_SETTLEMENT'; end if;
  select * into v_prior from public.settlement_events where driver_id=v_driver and service_date=v_date order by revision desc limit 1;
  v_revision := coalesce(v_prior.revision,0);
  if v_revision is distinct from (p_payload->>'expected_revision')::integer then raise exception 'SETTLEMENT_VERSION_CONFLICT'; end if;
  v_totals := public.settlement_totals(v_driver,v_date);
  if (v_totals->>'ledger_version')::bigint is distinct from (p_payload->>'ledger_version')::bigint then raise exception 'SETTLEMENT_DAY_CHANGED'; end if;
  if v_action='submit' then
    if v_prior.action in ('submit','approve') then raise exception 'SETTLEMENT_LOCKED'; end if;
    if v_handed<>(v_totals->>'cash')::bigint and length(trim(coalesce(p_payload->>'reason','')))=0 then raise exception 'DIFFERENCE_REASON_REQUIRED'; end if;
  elsif v_action='approve' then
    if v_prior.action is distinct from 'submit' then raise exception 'SETTLEMENT_NOT_SUBMITTED'; end if;
    -- Owner explicitly confirms the exact submitted amount; corrections require reopening.
    if v_handed is distinct from (v_prior.payload->>'handed_paise')::bigint or v_totals<>v_prior.totals then raise exception 'SETTLEMENT_DAY_CHANGED'; end if;
  else
    if v_prior.action is null or v_prior.action='reopen' then raise exception 'SETTLEMENT_NOT_SUBMITTED'; end if;
    if length(trim(coalesce(p_payload->>'reason','')))=0 then raise exception 'REOPEN_REASON_REQUIRED'; end if;
  end if;
  insert into public.settlement_events(operation_id,driver_id,service_date,actor_id,action,revision,payload,totals)
    values(v_id,v_driver,v_date,auth.uid(),v_action,v_revision+1,p_payload,v_totals);
  return public.settlement_day(v_driver,v_date);
end;
$$;
revoke all on function public.record_settlement(jsonb) from public,anon;
grant execute on function public.record_settlement(jsonb) to authenticated;

-- Preserve the complete validated milestone-1 implementation behind a private RPC.
alter function public.record_ledger(jsonb) rename to record_ledger_before_settlements;
revoke all on function public.record_ledger_before_settlements(jsonb) from public,anon,authenticated;
create function public.record_ledger(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_driver uuid; v_date date; v_action text;
begin
  -- Already committed requests must replay even after the day is locked.
  if exists(select 1 from public.ledger_events where operation_id=(p_payload->>'operation_id')::uuid) then
    return public.record_ledger_before_settlements(p_payload);
  end if;
  if p_payload->>'kind'='correction' then
    select (stop_after->>'driver_id')::uuid,(stop_after->>'service_date')::date into v_driver,v_date
      from public.ledger_events where operation_id=(p_payload->>'original_id')::uuid and kind in ('bill','payment');
  elsif p_payload->>'kind' in ('bill','payment') then
    select driver_id,service_date into v_driver,v_date from public.delivery_stops where id=(p_payload->>'stop_id')::uuid;
  end if;
  if v_driver is not null then
    perform pg_advisory_xact_lock(hashtextextended('settlement-day:'||v_driver::text||':'||v_date::text,0));
    -- Recheck after acquiring the lock: another device may have committed this ID.
    if not exists(select 1 from public.ledger_events where operation_id=(p_payload->>'operation_id')::uuid) then
      select action into v_action from public.settlement_events where driver_id=v_driver and service_date=v_date order by revision desc limit 1;
      if v_action in ('submit','approve') then raise exception 'SETTLEMENT_LOCKED'; end if;
    end if;
  end if;
  return public.record_ledger_before_settlements(p_payload);
end;
$$;
revoke all on function public.record_ledger(jsonb) from public,anon;
grant execute on function public.record_ledger(jsonb) to authenticated;

create function public.guard_settled_stop() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_action text;
begin
  if tg_op='UPDATE' then
    if (new.driver_id,new.service_date,new.shop_id) is distinct from (old.driver_id,old.service_date,old.shop_id)
      and exists(select 1 from public.ledger_events where stop_id=old.id) then raise exception 'FINANCIAL_STOP_IMMUTABLE'; end if;
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('settlement-day:'||new.driver_id::text||':'||new.service_date::text,0));
  select action into v_action from public.settlement_events where driver_id=new.driver_id and service_date=new.service_date order by revision desc limit 1;
  if v_action in ('submit','approve') then raise exception 'SETTLEMENT_LOCKED'; end if;
  return new;
end;
$$;
revoke all on function public.guard_settled_stop() from public,anon,authenticated;
create trigger settled_stop_guard before insert or update on public.delivery_stops for each row execute function public.guard_settled_stop();
notify pgrst,'reload schema';
commit;
