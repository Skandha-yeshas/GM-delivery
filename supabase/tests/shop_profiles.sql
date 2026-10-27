-- Disposable local PostgreSQL only; includes all earlier financial/location checks.
\set ON_ERROR_STOP on
\ir daily_settlements.sql
\ir ../migrations/20261020_shop_profiles.sql
\ir ../migrations/20261020_shop_profiles.sql
set test.user_id='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$ declare p jsonb; r jsonb; begin
  p:='{"id":"10000000-0000-0000-0000-000000000091","name":"New shop","area":"Market","address":"Side door","phone":"+919876543210","contact_name":"Rajesh Sharma","postal_code":"560001","maps_url":"https://maps.app.goo.gl/example"}';
  r:=public.save_shop(p,0);
  if r->>'contact_name'<>'Rajesh Sharma' or r->>'postal_code'<>'560001' then raise exception 'PROFILE_NOT_SAVED'; end if;
  r:=public.save_shop(p||'{"contact_name":"New contact"}',1);
  if r->>'contact_name'<>'New contact' or (r->>'version')::integer<>2 then raise exception 'PROFILE_EDIT_FAILED'; end if;
  -- Older APKs omit new fields: those edits must not erase contact/PIN data.
  r:=public.save_shop((p-'contact_name'-'postal_code')||'{"address":"Updated address"}',2);
  if r->>'contact_name'<>'New contact' or r->>'postal_code'<>'560001' then raise exception 'LEGACY_EDIT_ERASED_PROFILE'; end if;
  begin perform public.save_shop(p,2); raise exception 'STALE_PROFILE_EDIT_ACCEPTED';
    exception when raise_exception then if sqlerrm<>'VERSION_CONFLICT' then raise; end if; end;
  begin perform public.save_shop(p||'{"postal_code":"000000"}',3); raise exception 'INVALID_PIN_ACCEPTED'; exception when check_violation then null; end;
  if (select count(*) from public.shop_history where shop_id=(p->>'id')::uuid)<>3 then raise exception 'PROFILE_AUDIT_MISSING'; end if;
  if not exists(select 1 from public.shop_history where shop_id=(p->>'id')::uuid and snapshot->>'contact_name'='New contact') then raise exception 'CONTACT_NOT_AUDITED'; end if;
  begin update public.shops set postal_code='560002' where id=(p->>'id')::uuid; raise exception 'DIRECT_EDIT_ACCEPTED'; exception when insufficient_privilege then null; end;
end; $$;
set test.user_id='00000000-0000-0000-0000-000000000002';
do $$ begin
  begin perform public.save_shop('{"id":"10000000-0000-0000-0000-000000000091","name":"Forged","area":"Market","contact_name":"Other"}',3);
    raise exception 'DRIVER_EDITED_PROFILE'; exception when raise_exception then if sqlerrm<>'OWNER_REQUIRED' then raise; end if; end;
  if exists(select 1 from public.shops where id='10000000-0000-0000-0000-000000000091') then raise exception 'UNASSIGNED_PROFILE_LEAK'; end if;
end; $$;
reset role;
select 'Shop profile SQL checks passed' as result;
