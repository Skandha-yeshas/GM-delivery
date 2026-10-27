-- Disposable test database only; includes all previous migration regression checks.
\set ON_ERROR_STOP on
\ir collections_ledger.sql
\ir ../migrations/20261017_daily_settlements.sql
create function public.test_settlement_payload(n integer, a text, rev integer, handed bigint default 80000, reason text default '') returns jsonb
language sql stable as $$
  select jsonb_build_object('operation_id',('40000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    'driver_id','00000000-0000-0000-0000-000000000002','service_date','2026-10-15',
    'action',a,'expected_revision',rev,'handed_paise',handed,'reason',reason,
    'ledger_version',public.settlement_day('00000000-0000-0000-0000-000000000002','2026-10-15')->'totals'->'ledger_version',
    'captured_at','2026-10-17T10:00:00Z');
$$;
set test.user_id='00000000-0000-0000-0000-000000000002';
set role authenticated;
do $$ declare p jsonb; r jsonb; t jsonb; begin
  if not exists(select 1 from public.settlement_snapshot() d
    where d->>'driver_id'=auth.uid()::text and d->>'service_date'=(now() at time zone 'Asia/Kolkata')::date::text)
    then raise exception 'CURRENT_ZERO_ACTIVITY_DAY_MISSING'; end if;
  t := public.settlement_day(auth.uid(),'2026-10-15')->'totals';
  -- Latest corrected bill: 900/500 cash, old payment 300 cash, credit bill 200,
  -- and fully paid UPI/cheque bills 100 each. Opening 500 is excluded.
  if (t-'ledger_version') <> '{"bills":130000,"old_payments":30000,"cash":80000,"upi":10000,"cheque":10000,"credit":60000}'::jsonb then raise exception 'WRONG_DAILY_TOTALS: %',t; end if;
  if (t->>'ledger_version')::bigint <> (select max(sequence) from public.ledger_events where kind in ('bill','payment','correction')) then raise exception 'WRONG_DAY_SEQUENCE'; end if;
  begin
    perform public.record_settlement(public.test_settlement_payload(1,'submit',0,79000));
    raise exception 'MISSING_DIFFERENCE_REASON_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'DIFFERENCE_REASON_REQUIRED' then raise; end if; end;
  begin
    perform public.record_settlement(public.test_settlement_payload(1,'submit',0)||'{"handed_paise":1.5}'::jsonb);
    raise exception 'FLOAT_HANDOVER_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'INVALID_MONEY' then raise; end if; end;
  begin
    perform public.record_settlement(public.test_settlement_payload(1,'submit',0)||'{"expected_revision":"0","reason":123}'::jsonb);
    raise exception 'INVALID_JSON_TYPES_ACCEPTED';
  exception when raise_exception then if sqlerrm<>'INVALID_SETTLEMENT' then raise; end if; end;
  p:=public.test_settlement_payload(2,'submit',0,79000,'Cash shortage of 10; owner informed');
  r:=public.record_settlement(p);
  if jsonb_array_length(r->'events')<>1 then raise exception 'SUBMISSION_MISSING'; end if;
  perform public.record_settlement(p);
  if (select count(*) from public.settlement_events)<>1 then raise exception 'REPLAY_DUPLICATED'; end if;
  perform public.record_ledger((select payload from public.ledger_events where operation_id='20000000-0000-0000-0000-000000000002'));
  begin perform public.record_settlement(p||'{"handed_paise":78000}'::jsonb); raise exception 'CHANGED_REPLAY_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'OPERATION_MISMATCH' then raise; end if; end;
  begin perform public.record_ledger(public.test_ledger_payload(201,'bill',100,100)); raise exception 'LOCKED_DAY_BILL_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'SETTLEMENT_LOCKED' then raise; end if; end;
  begin perform public.record_ledger_before_settlements(public.test_ledger_payload(201,'bill',100,100)); raise exception 'PRIVATE_RPC_BYPASS';
    exception when insufficient_privilege then null; end;
  begin perform public.record_settlement(public.test_settlement_payload(3,'approve',1,79000)); raise exception 'DRIVER_APPROVED';
    exception when raise_exception then if sqlerrm<>'OWNER_REQUIRED' then raise; end if; end;
  begin delete from public.settlement_events; raise exception 'DIRECT_SETTLEMENT_DELETE';
    exception when insufficient_privilege then null; end;
end; $$;
set test.user_id='00000000-0000-0000-0000-000000000001';
do $$ declare p jsonb; begin
  begin
    insert into public.delivery_stops(id,shop_id,driver_id,service_date,stop_order)
      values(gen_random_uuid(),'10000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000002','2026-10-15',3);
    raise exception 'NEW_STOP_ON_LOCKED_DAY';
  exception when raise_exception then if sqlerrm<>'SETTLEMENT_LOCKED' then raise; end if; end;
  begin perform public.record_ledger(public.test_ledger_payload(202,'correction',40000,90000)||'{"original_id":"20000000-0000-0000-0000-000000000002","expected_revision":2,"reason":"Owner edit","bill_number":"B-2"}'::jsonb);
    raise exception 'OWNER_EDITED_LOCKED_DAY'; exception when raise_exception then if sqlerrm<>'SETTLEMENT_LOCKED' then raise; end if; end;
  begin perform public.record_settlement(public.test_settlement_payload(4,'submit',1)); raise exception 'OWNER_SUBMITTED_AS_DRIVER';
    exception when raise_exception then if sqlerrm<>'DRIVER_REQUIRED' then raise; end if; end;
  perform public.record_settlement(public.test_settlement_payload(5,'approve',1,79000));
  begin perform public.record_settlement(public.test_settlement_payload(6,'reopen',1,79000,'stale owner')); raise exception 'STALE_OWNER_REOPENED';
    exception when raise_exception then if sqlerrm<>'SETTLEMENT_VERSION_CONFLICT' then raise; end if; end;
  begin perform public.record_settlement(public.test_settlement_payload(7,'reopen',2,79000)); raise exception 'NO_REOPEN_REASON';
    exception when raise_exception then if sqlerrm<>'REOPEN_REASON_REQUIRED' then raise; end if; end;
  perform public.record_settlement(public.test_settlement_payload(8,'reopen',2,79000,'Receipt correction requested'));
  -- Save the driver's stale summary token before an owner correction.
end; $$;
reset role;
create table public.test_stale_settlement(payload jsonb);
insert into public.test_stale_settlement select public.test_settlement_payload(10,'submit',3,79000,'Resubmit');
grant select on public.test_stale_settlement to authenticated;
set role authenticated;
do $$ begin
  perform public.record_ledger(public.test_ledger_payload(203,'correction',40000,90000)||'{"original_id":"20000000-0000-0000-0000-000000000002","expected_revision":2,"reason":"Receipt rechecked","bill_number":"B-2"}'::jsonb);
end; $$;
set test.user_id='00000000-0000-0000-0000-000000000002';
do $$ begin
  begin perform public.record_settlement((select payload from public.test_stale_settlement)); raise exception 'STALE_LEDGER_SETTLED';
    exception when raise_exception then if sqlerrm<>'SETTLEMENT_DAY_CHANGED' then raise; end if; end;
  perform public.record_settlement(public.test_settlement_payload(11,'submit',3,70000));
  if (select count(*) from public.settlement_events)<>4 then raise exception 'AUDIT_EVENTS_LOST'; end if;
end; $$;
set test.user_id='00000000-0000-0000-0000-000000000003';
do $$ begin
  if exists(select 1 from public.settlement_events) then raise exception 'OTHER_DRIVER_HISTORY_LEAK'; end if;
  perform public.record_settlement(jsonb_build_object('operation_id','40000000-0000-0000-0000-000000000999',
    'driver_id',auth.uid(),'service_date',(now() at time zone 'Asia/Kolkata')::date,'action','submit',
    'expected_revision',0,'handed_paise',0,'reason','','ledger_version',0,'captured_at',now()));
  if (select count(*) from public.settlement_events)<>1 then raise exception 'ZERO_ACTIVITY_DAY_NOT_SETTLED'; end if;
  begin perform public.settlement_day('00000000-0000-0000-0000-000000000002','2026-10-15'); raise exception 'OTHER_DRIVER_SUMMARY_LEAK';
    exception when raise_exception then if sqlerrm<>'NOT_ASSIGNED' then raise; end if; end;
end; $$;
reset role;
do $$ begin
  begin update public.settlement_events set revision=revision; raise exception 'SETTLEMENT_AUDIT_MUTABLE';
    exception when raise_exception then if sqlerrm<>'LEDGER_APPEND_ONLY' then raise; end if; end;
end; $$;
set role anon;
do $$ begin
  begin perform public.settlement_snapshot(); raise exception 'ANON_SETTLEMENT_READ'; exception when insufficient_privilege then null; end;
  begin perform public.record_settlement('{}'); raise exception 'ANON_SETTLEMENT_WRITE'; exception when insufficient_privilege then null; end;
end; $$;
reset role;
select 'Daily settlement SQL checks passed' as result;
