-- Isolated fixture identities. Transaction restores all profile and ledger changes.
begin;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.staff(id,display_name,role,permissions) values
('11111111-1111-4111-8111-111111111111','UAT owner','owner','{}'),
('22222222-2222-4222-8222-222222222222','UAT staff','garage','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
update public.accounting_accounts set opening_on='2026-01-01',opening_balance=100000 where id in ('cash','bank') and opening_on is null;
insert into public.vehicles(brand,model,year,price,published) values('UAT ACCOUNTING','Cross-module',2026,100000,false);
insert into public.payments(request_id,vehicle_id,amount,method,purpose,paid_at) select gen_random_uuid(),id,20000,'cash','deposit','2026-11-01T12:00:00+08' from public.vehicles where brand='UAT ACCOUNTING';
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$begin
 if private.accounting_can('accounting_view') then raise exception 'FAIL default access';end if;
 begin perform public.accounting_snapshot('2026-11-01');raise exception 'FAIL default snapshot';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;
reset role;
update public.staff set permissions='{"accounting_view":true}' where display_name='UAT staff';
set local role authenticated;
do $$begin
 perform public.accounting_snapshot('2026-11-01');
 if private.accounting_can('accounting_post') then raise exception 'FAIL read grants post';end if;
 begin perform public.accounting_post(gen_random_uuid(),'{"date":"2026-11-01","kind":"expense","amount":1000,"account":"cash","category":"Sewa","description":"UAT reader post"}');raise exception 'FAIL reader post';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;
reset role;
update public.staff set permissions='{"accounting_view":true,"accounting_post":true}' where display_name='UAT staff';
set local role authenticated;
do $$declare e bigint;request uuid:=gen_random_uuid();doc jsonb;state jsonb;begin
 doc:='{"date":"2026-11-01","kind":"expense","amount":1000,"account":"cash","category":"Sewa","description":"UAT STAFF ACCOUNTING"}';
 e:=public.accounting_post(request,doc);
 if public.accounting_post(request,doc)<>e then raise exception 'FAIL duplicate retry';end if;
 if not exists(select 1 from public.accounting_audit where actor=auth.uid() and record_key=e::text and table_name='accounting_entries') then raise exception 'FAIL staff audit';end if;
 state:=public.accounting_snapshot('2026-11-01');
 if (state->'summary'->>'expense')::bigint<>1000 then raise exception 'FAIL staff totals';end if;
 if (state->'summary'->>'income')::bigint<>20000 then raise exception 'FAIL cross-module receipts';end if;
 if (select count(*) from public.accounting_feed_v2('2026-11-01',now()))<>2 then raise exception 'FAIL staff feed';end if;
 perform public.accounting_operations();
 update public.vehicles set model='Forbidden staff edit' where brand='UAT ACCOUNTING';
 if found then raise exception 'FAIL accounting granted inventory edit';end if;
 begin insert into public.accounting_annotations(source_key,reviewed,updated_by) values('M:'||e,true,auth.uid());raise exception 'FAIL direct annotation';exception when insufficient_privilege or raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 for doc in select jsonb_build_object('date','2026-11-01','kind',k,'amount',1000,'account','cash','category','Lain-lain','description','UAT forbidden') from unnest(array['capital','drawings','transfer']) k loop
  begin perform public.accounting_post(gen_random_uuid(),doc);raise exception 'FAIL staff privileged posting';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 end loop;
 begin perform public.accounting_reverse(e,gen_random_uuid(),'2026-11-02','UAT reversal');raise exception 'FAIL staff reversal';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.accounting_post(gen_random_uuid(),'{"date":"2026-11-01","kind":"adjustment","amount":1000,"account":"cash","category":"Pelarasan baki","description":"UAT","note":"UAT reason"}');raise exception 'FAIL staff adjustment';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.accounting_entries(request_id,entry_date,kind,amount,account_id,to_account_id,category,description,created_by) values(gen_random_uuid(),'2026-11-01','transfer',1000,'cash','bank','Pindahan dalaman','UAT bypass',auth.uid());raise exception 'FAIL direct transfer';exception when raise_exception or insufficient_privilege then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.accounting_review('M:'||e,0,null,true,'UAT reason',null,0,'');raise exception 'FAIL staff review';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.accounting_accounts set name='UAT forbidden' where id='cash';
 if found then raise exception 'FAIL staff account update';end if;
 begin insert into public.accounting_accounts(id,name) values('acct_33333333-3333-4333-8333-333333333333','UAT forbidden');raise exception 'FAIL staff create account';exception when raise_exception or insufficient_privilege then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;
-- Metadata fixture only; no actual file is uploaded.
reset role;
insert into storage.objects(bucket_id,name,metadata) values('accounting-receipts','22222222-2222-4222-8222-222222222222/11111111-1111-4111-8111-111111111111.pdf','{"size":20,"mimetype":"application/pdf"}');
set local role authenticated;
insert into public.accounting_receipts(source_key,storage_path,original_name,created_by) select 'M:'||id,'22222222-2222-4222-8222-222222222222/11111111-1111-4111-8111-111111111111.pdf','UAT receipt',auth.uid() from public.accounting_entries where description='UAT STAFF ACCOUNTING';
reset role;
update public.staff set permissions='{"accounting_post":true}' where display_name='UAT staff';
set local role authenticated;
do $$begin if private.accounting_can('accounting_post') then raise exception 'FAIL post without view';end if;end$$;
reset role;
update public.staff set permissions='{"accounting_view":true,"accounting_post":true}',enabled=false where display_name='UAT staff';
set local role authenticated;
do $$begin if private.accounting_can('accounting_view') then raise exception 'FAIL disabled view';end if;end$$;
reset role;
update public.staff set enabled=true,must_change_password=true where display_name='UAT staff';
set local role authenticated;
do $$begin if private.accounting_can('accounting_view') then raise exception 'FAIL temporary access';end if;end$$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select public.accounting_reverse(id,gen_random_uuid(),'2026-11-02','UAT owner reversal') from public.accounting_entries where description='UAT STAFF ACCOUNTING';
reset role;
set local role anon;
do $$begin
 begin perform public.accounting_snapshot('2026-11-01');raise exception 'FAIL anon access';exception when insufficient_privilege then null;end;
end$$;
rollback;
