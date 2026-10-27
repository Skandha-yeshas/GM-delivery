-- Disposable local PostgreSQL only. Includes every earlier migration check.
\set ON_ERROR_STOP on
\ir shop_profiles.sql
\ir ../migrations/20261023_delivery_order.sql
\ir ../migrations/20261023_delivery_order.sql
insert into auth.users values ('00000000-0000-0000-0000-000000000099');
insert into public.profiles values ('00000000-0000-0000-0000-000000000099','Other owner','owner');
set test.user_id='00000000-0000-0000-0000-000000000001';
set role authenticated;
insert into public.delivery_stops(id,shop_id,service_date,driver_id,stop_order) values
 ('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','2020-01-01','00000000-0000-0000-0000-000000000002',1),
 ('50000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000005','2020-01-01','00000000-0000-0000-0000-000000000002',2),
 ('50000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000091','2020-01-01','00000000-0000-0000-0000-000000000002',3);
set test.user_id='00000000-0000-0000-0000-000000000002';
select public.record_visit('60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000002','failed','Shop closed',1);
reset role;
create function public.test_route_payload(n integer) returns jsonb language sql stable as $$
  select jsonb_build_object('operation_id',('70000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    'driver_id','00000000-0000-0000-0000-000000000002','service_date','2020-01-01',
    'expected',(select jsonb_agg(jsonb_build_object('id',id,'stop_order',stop_order,'version',version,'status',status) order by id)
      from public.delivery_stops where service_date='2020-01-01'),
    'pending_ids','["50000000-0000-0000-0000-000000000003","50000000-0000-0000-0000-000000000001"]'::jsonb);
$$;
create table public.test_route_saved(payload jsonb);
insert into public.test_route_saved select public.test_route_payload(1);
grant select on public.test_route_saved to authenticated;
set role authenticated;
do $$ begin
  begin perform public.save_route_order(public.test_route_payload(1)); raise exception 'DRIVER_REORDERED';
  exception when raise_exception then if sqlerrm<>'OWNER_REQUIRED' then raise; end if; end;
  if exists(select 1 from public.route_order_events) then raise exception 'ROUTE_HISTORY_LEAK'; end if;
end; $$;
set test.user_id='00000000-0000-0000-0000-000000000001';
do $$ declare p jsonb; r jsonb; n bigint; begin
  p:=(select payload from public.test_route_saved);
  n:=(select count(*) from public.ledger_events);
  begin perform public.save_route_order(p||'{"pending_ids":["50000000-0000-0000-0000-000000000001","50000000-0000-0000-0000-000000000001"]}'); raise exception 'DUPLICATE_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'INVALID_ROUTE' then raise; end if; end;
  begin perform public.save_route_order(p||'{"pending_ids":["50000000-0000-0000-0000-000000000002","50000000-0000-0000-0000-000000000001"]}'); raise exception 'COMPLETED_MOVED';
    exception when raise_exception then if sqlerrm<>'INVALID_ROUTE' then raise; end if; end;
  begin perform public.save_route_order(p||'{"pending_ids":[]}'); raise exception 'OMITTED_STOPS_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'INVALID_ROUTE' then raise; end if; end;
  begin perform public.save_route_order(p||'{"service_date":"2020-01-02"}'); raise exception 'WRONG_DAY_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'ROUTE_CHANGED' then raise; end if; end;
  if exists(select 1 from public.route_order_events) then raise exception 'INVALID_ROUTE_AUDITED'; end if;
  r:=public.save_route_order(p);
  if r->0->>'id'<>'50000000-0000-0000-0000-000000000003' or r->2->>'id'<>'50000000-0000-0000-0000-000000000001' then raise exception 'WRONG_ROUTE'; end if;
  if r->1->>'status'<>'failed' or r->1->>'reason'<>'Shop closed' or (r->1->>'version')::integer<>2 then raise exception 'VISIT_CHANGED'; end if;
  if (r->0->>'version')::integer<>1 or (select count(*) from public.ledger_events)<>n then raise exception 'MONEY_OR_VISIT_VERSION_CHANGED'; end if;
  perform public.save_route_order(p);
  if (select count(*) from public.route_order_events)<>1 then raise exception 'DUPLICATE_ROUTE_EVENT'; end if;
  begin perform public.save_route_order(p||'{"pending_ids":[]}'); raise exception 'REPLAY_MUTATED';
    exception when raise_exception then if sqlerrm<>'OPERATION_MISMATCH' then raise; end if; end;
  begin perform public.save_route_order(p||'{"operation_id":"70000000-0000-0000-0000-000000000002"}'); raise exception 'STALE_OWNER_OVERWROTE_ROUTE';
    exception when raise_exception then if sqlerrm<>'ROUTE_CHANGED' then raise; end if; end;
  begin update public.delivery_stops set stop_order=20; raise exception 'DIRECT_ORDER_WRITE'; exception when insufficient_privilege then null; end;
  begin delete from public.route_order_events; raise exception 'AUDIT_REMOVED'; exception when insufficient_privilege then null; end;
end; $$;
set test.user_id='00000000-0000-0000-0000-000000000099';
do $$ begin
  begin perform public.save_route_order((select payload from public.test_route_saved)); raise exception 'OTHER_OWNER_REPLAYED_ID';
    exception when raise_exception then if sqlerrm<>'OPERATION_MISMATCH' then raise; end if; end;
end; $$;
-- A visit completed after an owner's draft must invalidate that draft. A queued
-- driver result made before reorder remains valid because visit versions survive.
set test.user_id='00000000-0000-0000-0000-000000000001';
reset role;
insert into public.test_route_saved select public.test_route_payload(3);
set role authenticated;
set test.user_id='00000000-0000-0000-0000-000000000002';
select public.record_visit('60000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000003','failed','Unable to deliver',1);
set test.user_id='00000000-0000-0000-0000-000000000001';
do $$ begin
  begin perform public.save_route_order((select payload from public.test_route_saved where payload->>'operation_id'='70000000-0000-0000-0000-000000000003')); raise exception 'STALE_STATUS_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'ROUTE_CHANGED' then raise; end if; end;
end; $$;
-- Lock the route's day through the real settlement RPC.
set test.user_id='00000000-0000-0000-0000-000000000002';
select public.record_settlement(jsonb_build_object('operation_id','80000000-0000-0000-0000-000000000001',
  'driver_id',auth.uid(),'service_date','2020-01-01','action','submit','expected_revision',0,
  'handed_paise',0,'reason','','ledger_version',0,'captured_at','2020-01-01T12:00:00Z'));
set test.user_id='00000000-0000-0000-0000-000000000001';
do $$ begin
  begin perform public.save_route_order(public.test_route_payload(4)); raise exception 'LOCKED_ROUTE_CHANGED';
    exception when raise_exception then if sqlerrm<>'SETTLEMENT_LOCKED' then raise; end if; end;
  -- An already committed operation can still be safely acknowledged on a locked day.
  perform public.save_route_order((select payload from public.test_route_saved where payload->>'operation_id'='70000000-0000-0000-0000-000000000001'));
end; $$;
reset role;
select 'Delivery route ordering SQL checks passed' as result;
