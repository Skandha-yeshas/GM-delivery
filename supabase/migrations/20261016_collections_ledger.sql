-- Milestone 1. Run AFTER the existing shop/import/Maps migrations.
-- Append-only events are also the complete audit history: no money row is edited.
begin;
create table public.ledger_events (
  operation_id uuid primary key,
  sequence bigint generated always as identity unique,
  shop_id uuid not null references public.shops(id),
  stop_id uuid references public.delivery_stops(id),
  actor_id uuid not null references public.profiles(id),
  subject_id uuid not null references public.profiles(id),
  kind text not null check(kind in ('bill','payment','opening','correction','flag')),
  original_id uuid references public.ledger_events(operation_id),
  revision integer not null check(revision > 0),
  debit_delta bigint not null, credit_delta bigint not null,
  payload jsonb not null,
  stop_after jsonb,
  recorded_at timestamptz not null default clock_timestamp(),
  check((kind = 'correction') = (original_id is not null)),
  check((payload->>'operation_id')::uuid = operation_id and (payload->>'shop_id')::uuid = shop_id and payload->>'kind' = kind),
  unique(original_id, revision)
);
create index ledger_shop_sequence on public.ledger_events(shop_id, sequence);
create index ledger_stop on public.ledger_events(stop_id);
create unique index ledger_one_opening on public.ledger_events(shop_id) where kind = 'opening';
alter table public.ledger_events enable row level security;
revoke all on public.ledger_events from public, anon, authenticated;
grant select on public.ledger_events to authenticated;
create policy ledger_read on public.ledger_events for select to authenticated using (
  public.is_owner() or (subject_id = auth.uid() and exists (
    select 1 from public.delivery_stops d where d.id = stop_id and d.driver_id = auth.uid()
  ))
);
create function public.reject_ledger_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin raise exception 'LEDGER_APPEND_ONLY'; end;
$$;
revoke all on function public.reject_ledger_mutation() from public, anon, authenticated;
create trigger ledger_immutable before update or delete on public.ledger_events
  for each row execute function public.reject_ledger_mutation();

-- Private aggregate: callers use ledger_balances(), which checks shop access.
create function public.credit_summary(p_shop uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with events as (select * from public.ledger_events where shop_id = p_shop),
  totals as (select coalesce(sum(debit_delta-credit_delta),0)::bigint balance,
    coalesce(sum(credit_delta),0)::bigint credits, coalesce(max(sequence),0) version from events),
  effective as (
    select distinct on (coalesce(e.original_id,e.operation_id))
      e.payload, b.sequence base_sequence, (b.payload->>'captured_at')::timestamptz captured_at
    from events e join events b on b.operation_id = coalesce(e.original_id,e.operation_id)
    where e.kind <> 'flag'
    order by coalesce(e.original_id,e.operation_id), e.revision desc
  ), aged as (select *, sum((payload->>'bill_paise')::bigint) over(order by base_sequence) cumulative_debit from effective),
  flag as (select payload, revision from events where kind = 'flag' order by sequence desc limit 1)
  select jsonb_build_object('shop_id',p_shop,'balance_paise',t.balance,'version',t.version,
    'oldest_unpaid_at',case when t.balance > 0 then (select captured_at from aged where cumulative_debit > t.credits order by base_sequence limit 1) end,
    'last_payment_at',(select max(captured_at) from effective where (payload->>'collected_paise')::bigint > 0),
    'collect_next_visit',coalesce((select (payload->>'collect_next_visit')::boolean from flag),false),
    'flag_revision',coalesce((select revision from flag),0)) from totals t;
$$;
revoke all on function public.credit_summary(uuid) from public, anon, authenticated;

create function public.ledger_balances(p_offset integer default 0, p_limit integer default 500) returns setof jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists(select 1 from public.profiles where id = auth.uid()) then raise exception 'AUTH_REQUIRED'; end if;
  if p_offset < 0 or p_limit < 1 or p_limit > 500 then raise exception 'INVALID_PAGE'; end if;
  return query select public.credit_summary(s.id) from public.shops s
    where public.is_owner() or exists(select 1 from public.delivery_stops d where d.shop_id = s.id and d.driver_id = auth.uid())
    order by s.id limit p_limit offset p_offset;
end;
$$;
revoke all on function public.ledger_balances(integer,integer) from public, anon;
grant execute on function public.ledger_balances(integer,integer) to authenticated;

create function public.record_ledger(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := (p_payload->>'operation_id')::uuid;
  v_shop uuid := (p_payload->>'shop_id')::uuid;
  v_stop_id uuid := (p_payload->>'stop_id')::uuid;
  v_kind text := p_payload->>'kind';
  v_type text := v_kind;
  v_original uuid := (p_payload->>'original_id')::uuid;
  v_bill bigint; v_paid bigint; v_old_bill bigint := 0; v_old_paid bigint := 0;
  v_revision integer := 1; v_flag_revision integer;
  v_event public.ledger_events; v_root public.ledger_events; v_latest public.ledger_events;
  v_stop public.delivery_stops; v_stop_after jsonb;
  v_expected_stop integer := (p_payload->>'expected_stop_version')::integer;
  v_legacy public.visit_events;
  v_owner boolean := public.is_owner(); v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then raise exception 'AUTH_REQUIRED'; end if;
  if v_id is null or v_shop is null then raise exception 'INVALID_LEDGER'; end if;
  -- Fixed lock order: operation, shop, then stop. Retries cannot double-apply money.
  perform pg_advisory_xact_lock(hashtextextended('ledger-op:'||v_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('ledger-shop:'||v_shop::text,0));
  if not exists(select 1 from public.shops where id = v_shop) then raise exception 'SHOP_NOT_FOUND'; end if;
  if not v_owner and (v_role <> 'driver' or v_stop_id is null or not exists(
    select 1 from public.delivery_stops where id = v_stop_id and shop_id = v_shop and driver_id = auth.uid()
  )) then raise exception 'NOT_ASSIGNED'; end if;
  select * into v_event from public.ledger_events where operation_id = v_id;
  if found then
    if v_event.actor_id <> auth.uid() or v_event.payload <> p_payload then raise exception 'OPERATION_MISMATCH'; end if;
    return jsonb_build_object('entry',to_jsonb(v_event),'balance',public.credit_summary(v_shop));
  end if;
  if v_kind is null or v_kind not in ('bill','payment','opening','correction','flag') then raise exception 'INVALID_LEDGER'; end if;
  if not v_owner and v_kind not in ('bill','payment') then raise exception 'OWNER_REQUIRED'; end if;
  if jsonb_typeof(p_payload->'bill_paise') <> 'number' or jsonb_typeof(p_payload->'collected_paise') <> 'number'
    or coalesce(p_payload->>'bill_paise','') !~ '^[0-9]{1,12}$'
    or coalesce(p_payload->>'collected_paise','') !~ '^[0-9]{1,12}$' then raise exception 'INVALID_MONEY'; end if;
  v_bill := (p_payload->>'bill_paise')::bigint; v_paid := (p_payload->>'collected_paise')::bigint;
  if v_bill > 100000000000 or v_paid > 100000000000 then raise exception 'INVALID_MONEY'; end if;
  if length(coalesce(p_payload->>'bill_number','')) > 100 or length(coalesce(p_payload->>'reference','')) > 200
    or length(coalesce(p_payload->>'note','')) > 1000 or length(coalesce(p_payload->>'reason','')) > 500 then raise exception 'INVALID_LEDGER'; end if;
  if coalesce(p_payload->>'mode','') not in ('cash','upi','cheque','credit') then raise exception 'INVALID_MODE'; end if;
  if (p_payload->>'captured_at')::timestamptz is null then raise exception 'CAPTURE_TIME_REQUIRED'; end if;
  if coalesce(p_payload->>'gps_status','') not in ('available','unavailable','denied','timeout') then raise exception 'INVALID_GPS'; end if;
  if p_payload->>'gps_status' = 'available' and not coalesce(
    (p_payload->>'latitude')::double precision between -90 and 90
    and (p_payload->>'longitude')::double precision between -180 and 180
    and (p_payload->>'accuracy')::double precision between 0 and 1000000,false) then raise exception 'INVALID_GPS'; end if;
  if v_kind = 'correction' then
    select * into v_root from public.ledger_events where operation_id = v_original and shop_id = v_shop and kind in ('bill','payment','opening');
    if not found or v_stop_id is distinct from v_root.stop_id then raise exception 'INVALID_ORIGINAL'; end if;
    select * into v_latest from public.ledger_events where operation_id = v_original or original_id = v_original order by revision desc limit 1;
    if v_latest.revision is distinct from (p_payload->>'expected_revision')::integer then raise exception 'VERSION_CONFLICT'; end if;
    if length(trim(coalesce(p_payload->>'reason',''))) = 0 then raise exception 'CORRECTION_REASON_REQUIRED'; end if;
    v_type := v_root.kind; v_revision := v_latest.revision + 1;
    v_old_bill := (v_latest.payload->>'bill_paise')::bigint; v_old_paid := (v_latest.payload->>'collected_paise')::bigint;
  elsif v_original is not null then raise exception 'INVALID_ORIGINAL';
  end if;
  if v_type = 'bill' then
    if length(trim(coalesce(p_payload->>'bill_number',''))) = 0 or (v_bill = 0 and v_kind <> 'correction') or v_paid > v_bill then raise exception 'INVALID_BILL'; end if;
    -- All writes to a shop share the advisory lock; compare current corrected bill references.
    if exists(select 1 from (
      select distinct on(coalesce(original_id,operation_id)) coalesce(original_id,operation_id) root, payload
      from public.ledger_events where shop_id = v_shop and kind in ('bill','correction')
      order by coalesce(original_id,operation_id), revision desc
    ) e join public.ledger_events b on b.operation_id = e.root and b.kind = 'bill'
      where e.root is distinct from v_original and lower(trim(e.payload->>'bill_number')) = lower(trim(p_payload->>'bill_number')))
      then raise exception 'DUPLICATE_BILL'; end if;
  elsif v_type = 'payment' then
    if v_bill <> 0 or (v_paid = 0 and v_kind <> 'correction') or p_payload->>'mode' = 'credit' then raise exception 'INVALID_PAYMENT'; end if;
    if v_kind = 'payment' and v_paid > (public.credit_summary(v_shop)->>'balance_paise')::bigint then raise exception 'PAYMENT_EXCEEDS_BALANCE'; end if;
  elsif v_type = 'opening' then
    if v_paid <> 0 or p_payload->>'mode' <> 'credit' then raise exception 'INVALID_OPENING'; end if;
    if v_kind = 'opening' and exists(select 1 from public.ledger_events where shop_id = v_shop and kind = 'opening') then raise exception 'OPENING_EXISTS'; end if;
  elsif v_type = 'flag' then
    if v_bill <> 0 or v_paid <> 0 or coalesce(jsonb_typeof(p_payload->'collect_next_visit'),'') <> 'boolean' then raise exception 'INVALID_FLAG'; end if;
    select coalesce(max(revision),0) into v_flag_revision from public.ledger_events where shop_id = v_shop and kind = 'flag';
    if v_flag_revision is distinct from (p_payload->>'expected_revision')::integer then raise exception 'VERSION_CONFLICT'; end if;
    v_revision := v_flag_revision + 1;
  end if;
  if p_payload->>'mode' = 'credit' and v_paid <> 0 then raise exception 'INVALID_MODE'; end if;
  if v_type = 'bill' and v_paid = 0 and p_payload->>'mode' <> 'credit' then raise exception 'INVALID_MODE'; end if;
  if v_kind in ('bill','payment') then
    select * into v_stop from public.delivery_stops where id = v_stop_id and shop_id = v_shop for update;
    if not found or (not v_owner and v_stop.driver_id <> auth.uid()) then raise exception 'NOT_ASSIGNED'; end if;
    if p_payload->>'legacy_visit_operation_id' is not null then
      select * into v_legacy from public.visit_events where operation_id = (p_payload->>'legacy_visit_operation_id')::uuid;
      if found then
        if v_legacy.actor_id <> auth.uid() or v_legacy.stop_id <> v_stop_id or v_legacy.status <> 'delivered'
          or v_legacy.expected_version <> v_expected_stop then raise exception 'INVALID_LEGACY_VISIT'; end if;
        if v_stop.version = (v_legacy.result->>'version')::integer then v_expected_stop := v_stop.version; end if;
      end if;
    end if;
    if v_stop.version is distinct from v_expected_stop then raise exception 'VERSION_CONFLICT'; end if;
    update public.delivery_stops set status = 'delivered', reason = '', version = version + 1, updated_at = now()
      where id = v_stop.id returning * into v_stop;
    v_stop_after := to_jsonb(v_stop);
  elsif v_kind in ('opening','flag') and v_stop_id is not null then raise exception 'INVALID_STOP'; end if;
  insert into public.ledger_events(operation_id,shop_id,stop_id,actor_id,subject_id,kind,original_id,revision,debit_delta,credit_delta,payload,stop_after)
  values(v_id,v_shop,v_stop_id,auth.uid(),case when v_kind = 'correction' then v_root.subject_id else auth.uid() end,v_kind,v_original,v_revision,v_bill-v_old_bill,v_paid-v_old_paid,p_payload,v_stop_after) returning * into v_event;
  return jsonb_build_object('entry',to_jsonb(v_event),'balance',public.credit_summary(v_shop));
end;
$$;
revoke all on function public.record_ledger(jsonb) from public, anon;
grant execute on function public.record_ledger(jsonb) to authenticated;
-- Old committed results still replay idempotently. New delivered results need
-- a financial record; older unsent results continue via the collection form.
create or replace function public.record_visit(p_operation_id uuid, p_stop_id uuid,
  p_status text, p_reason text, p_expected_version integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
  if p_status = 'delivered' and not exists(select 1 from public.ledger_events where stop_id = p_stop_id and kind in ('bill','payment')) then raise exception 'COLLECTION_REQUIRED'; end if;
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

notify pgrst, 'reload schema';
commit;
