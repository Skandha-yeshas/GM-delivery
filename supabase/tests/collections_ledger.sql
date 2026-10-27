-- TEST ONLY, on the disposable PostgreSQL cluster created by verify_maps_sql.ps1.
\set ON_ERROR_STOP on
\ir maps_link_delivery.sql
-- Simulate a pre-upgrade delivered result whose response was lost.
do $$ declare d public.delivery_stops; begin
  select * into d from public.delivery_stops where shop_id = '10000000-0000-0000-0000-000000000001';
  perform public.record_visit('30000000-0000-0000-0000-000000000001',d.id,'delivered','',d.version);
end; $$;
\ir ../migrations/20261016_collections_ledger.sql

create function public.test_ledger_payload(n integer, k text, paid bigint default 0, bill bigint default 0) returns jsonb
language sql stable as $$
  select jsonb_build_object('operation_id',('20000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    'shop_id','10000000-0000-0000-0000-000000000001','kind',k,'captured_at','2026-10-16T06:00:00Z',
    'stop_id',case when k in ('bill','payment','correction') then d.id end,
    'expected_stop_version',d.version,'original_id',null,'expected_revision',0,
    'bill_number',case when k = 'bill' then 'B-'||n::text else '' end,
    'bill_paise',bill,'collected_paise',paid,'mode',case when paid > 0 then 'cash' else 'credit' end,
    'reference','','note','','reason','','collect_next_visit',case when k = 'flag' then true end,
    'latitude',null,'longitude',null,'accuracy',null,'gps_status','unavailable')
  from (select id,version from public.delivery_stops where shop_id = '10000000-0000-0000-0000-000000000001' limit 1) d;
$$;
set test.user_id = '00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$
declare p jsonb; r jsonb;
begin
  p := public.test_ledger_payload(1,'opening',0,50000) || '{"captured_at":"2026-10-10T06:00:00Z"}'::jsonb;
  r := public.record_ledger(p);
  if (r->'balance'->>'balance_paise')::bigint <> 50000 then raise exception 'WRONG_OPENING'; end if;
  perform public.record_ledger(p);
  if (select count(*) from public.ledger_events) <> 1 then raise exception 'OPENING_RETRY_DUPLICATED'; end if;
  begin
    perform public.record_ledger(public.test_ledger_payload(99,'opening',0,50000));
    raise exception 'SECOND_OPENING_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'OPENING_EXISTS' then raise; end if; end;
  r := public.record_ledger(public.test_ledger_payload(8,'flag'));
  if not (r->'balance'->>'collect_next_visit')::boolean then raise exception 'FLAG_MISSING'; end if;
end;
$$;
set test.user_id = '00000000-0000-0000-0000-000000000002';
do $$
declare p jsonb; r jsonb; original_stop jsonb; n bigint;
begin
  perform public.record_visit('30000000-0000-0000-0000-000000000001',(select id from public.delivery_stops where shop_id = '10000000-0000-0000-0000-000000000001'),'delivered','',1);
  begin
    perform public.record_visit('30000000-0000-0000-0000-000000000002',(select id from public.delivery_stops where shop_id = '10000000-0000-0000-0000-000000000001'),'delivered','',2);
    raise exception 'LEGACY_ENDPOINT_BYPASS';
  exception when raise_exception then if sqlerrm <> 'COLLECTION_REQUIRED' then raise; end if; end;
  p := public.test_ledger_payload(2,'bill',40000,100000) || '{"captured_at":"2026-10-13T06:00:00Z","gps_status":"available","latitude":12.3,"longitude":77.5,"accuracy":8}'::jsonb;
  p := p || '{"legacy_visit_operation_id":"30000000-0000-0000-0000-000000000001","expected_stop_version":1}'::jsonb;
  r := public.record_ledger(p); original_stop := r->'entry'->'stop_after';
  if (r->'balance'->>'balance_paise')::bigint <> 110000 then raise exception 'PARTIAL_BALANCE_WRONG'; end if;
  if original_stop->>'status' <> 'delivered' then raise exception 'DELIVERY_NOT_ATOMIC'; end if;
  select count(*) into n from public.ledger_events;
  r := public.record_ledger(p);
  if r->'entry'->'stop_after' <> original_stop or (select count(*) from public.ledger_events) <> n then raise exception 'RETRY_CHANGED_BILL'; end if;
  begin
    perform public.record_ledger(p || '{"collected_paise":50000}'::jsonb);
    raise exception 'ID_MISMATCH_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'OPERATION_MISMATCH' then raise; end if; end;
  begin
    perform public.record_ledger(public.test_ledger_payload(3,'bill',40000,100000) || '{"bill_number":"B-2"}'::jsonb);
    raise exception 'DUPLICATE_BILL_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'DUPLICATE_BILL' then raise; end if; end;
  r := public.record_ledger(public.test_ledger_payload(4,'payment',30000));
  if (r->'balance'->>'balance_paise')::bigint <> 80000 then raise exception 'PAYMENT_BALANCE_WRONG'; end if;
  r := public.record_ledger(public.test_ledger_payload(5,'bill',0,20000));
  if (r->'balance'->>'balance_paise')::bigint <> 100000 then raise exception 'CREDIT_BALANCE_WRONG'; end if;
  r := public.record_ledger(public.test_ledger_payload(6,'bill',10000,10000) || '{"mode":"upi","reference":"UPI-test"}'::jsonb);
  r := public.record_ledger(public.test_ledger_payload(7,'bill',10000,10000) || '{"mode":"cheque","reference":"CHQ-test"}'::jsonb);
  if (r->'balance'->>'balance_paise')::bigint <> 100000 then raise exception 'PAID_BILL_CHANGED_BALANCE'; end if;
  begin
    perform public.record_ledger(public.test_ledger_payload(90,'payment',100001));
    raise exception 'OVERPAYMENT_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'PAYMENT_EXCEEDS_BALANCE' then raise; end if; end;
  begin
    perform public.record_ledger(public.test_ledger_payload(91,'bill',0,100) || '{"bill_paise":1.5}'::jsonb);
    raise exception 'FLOAT_MONEY_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'INVALID_MONEY' then raise; end if; end;
  begin
    perform public.record_ledger(public.test_ledger_payload(92,'bill',200,100));
    raise exception 'BILL_OVERPAYMENT_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'INVALID_BILL' then raise; end if; end;
  begin
    perform public.record_ledger(public.test_ledger_payload(93,'correction',50000,90000) || '{"original_id":"20000000-0000-0000-0000-000000000002","expected_revision":1,"reason":"forged","bill_number":"B-2"}'::jsonb);
    raise exception 'DRIVER_CORRECTED_MONEY';
  exception when raise_exception then if sqlerrm <> 'OWNER_REQUIRED' then raise; end if; end;
  begin
    update public.ledger_events set credit_delta = 0;
    raise exception 'DIRECT_WRITE_ACCEPTED';
  exception when insufficient_privilege then null; end;
end;
$$;
set test.user_id = '00000000-0000-0000-0000-000000000001';
do $$
declare p jsonb; r jsonb;
begin
  p := public.test_ledger_payload(10,'correction',50000,90000) || '{"original_id":"20000000-0000-0000-0000-000000000002","expected_revision":1,"reason":"Owner checked receipt","bill_number":"B-2"}'::jsonb;
  r := public.record_ledger(p);
  if (r->'balance'->>'balance_paise')::bigint <> 80000 or (r->'entry'->>'revision')::integer <> 2 then raise exception 'CORRECTION_BALANCE_WRONG'; end if;
  if (r->'balance'->>'oldest_unpaid_at')::date <> '2026-10-13' then raise exception 'FIFO_AGE_WRONG'; end if;
  if (select (payload->>'bill_paise')::bigint from public.ledger_events where operation_id = '20000000-0000-0000-0000-000000000002') <> 100000 then raise exception 'ORIGINAL_OVERWRITTEN'; end if;
  perform public.record_ledger(p);
  begin
    perform public.record_ledger(p || '{"operation_id":"20000000-0000-0000-0000-000000000011"}'::jsonb);
    raise exception 'STALE_CORRECTION_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'VERSION_CONFLICT' then raise; end if; end;
  begin
    perform public.record_ledger(public.test_ledger_payload(12,'flag') || '{"collect_next_visit":false}'::jsonb);
    raise exception 'STALE_FLAG_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'VERSION_CONFLICT' then raise; end if; end;
  r := public.record_ledger(public.test_ledger_payload(13,'flag') || '{"collect_next_visit":false,"expected_revision":1}'::jsonb);
  if (r->'balance'->>'collect_next_visit')::boolean then raise exception 'FLAG_NOT_CLEARED'; end if;
end;
$$;
-- Corrections to the driver's own records remain visible to that driver.
set test.user_id = '00000000-0000-0000-0000-000000000002';
do $$ begin
  if not exists(select 1 from public.ledger_events where kind = 'correction') then raise exception 'DRIVER_CANNOT_SEE_OWN_CORRECTION'; end if;
  if exists(select 1 from public.ledger_events where kind in ('opening','flag')) then raise exception 'DRIVER_READ_OWNER_ONLY_EVENT'; end if;
end; $$;
reset role;
do $$ begin
  begin
    update public.ledger_events set credit_delta = credit_delta;
    raise exception 'AUDIT_MUTABLE';
  exception when raise_exception then if sqlerrm <> 'LEDGER_APPEND_ONLY' then raise; end if; end;
end; $$;
insert into auth.users values('00000000-0000-0000-0000-000000000003');
insert into public.profiles values('00000000-0000-0000-0000-000000000003','Other driver','driver');
set test.user_id = '00000000-0000-0000-0000-000000000003';
set role authenticated;
do $$ begin
  if exists(select 1 from public.ledger_events) or exists(select 1 from public.ledger_balances()) then raise exception 'UNASSIGNED_DATA_LEAKED'; end if;
  begin
    perform public.record_ledger(public.test_ledger_payload(20,'bill',100,100));
    raise exception 'UNASSIGNED_WRITE_ACCEPTED';
  exception when raise_exception then if sqlerrm <> 'AUTH_REQUIRED' and sqlerrm <> 'NOT_ASSIGNED' and sqlerrm <> 'INVALID_LEDGER' then raise; end if; end;
end; $$;
reset role;
set role anon;
do $$ begin
  begin perform public.ledger_balances(); raise exception 'ANON_READ'; exception when insufficient_privilege then null; end;
  begin perform public.record_ledger('{}'::jsonb); raise exception 'ANON_WRITE'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
select 'Collections ledger SQL checks passed' as result;
