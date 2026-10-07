-- Regression checks run in a transaction and rolled back. Uses the existing
-- owner identity; no login account or test business record is retained.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','41ad4268-5653-4ab0-84c4-b89dda95adf8',true);
do $$
declare v bigint;j bigint;p bigint;rev bigint;old_version int;n int;
begin
 insert into public.vehicles(brand,model,year,price,plate,chassis,published,buyer,buyer_phone) values('TEST','Rollback',2026,10000,'TEST 26','TEST-CASIS',true,'Test buyer','60123456789') returning id,version into v,old_version;
 if not exists(select 1 from public.catalogue where id=v) then raise exception 'FAIL catalogue projection';end if;
 begin update public.vehicles set paid=100 where id=v;raise exception 'FAIL direct payment allowed';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.vehicles(brand,model,year,price,status,published) values('TEST','Zero',2026,0,'sold',false);raise exception 'FAIL zero sold';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.vehicles(brand,model,year,price,plate,published) values('TEST','Duplicate',2026,10000,'TEST26',false);raise exception 'FAIL duplicate plate';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.vehicles(brand,model,year,price,plate,published,duplicate_reason) values('TEST','Allowed duplicate',2026,10000,'TEST26',false,'Verified test override');
 begin insert into public.vehicles(brand,model,year,price,chassis,published) values('TEST','Duplicate chassis',2026,10000,'TEST-CASIS',false);raise exception 'FAIL duplicate chassis';exception when unique_violation then null;end;
 insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,3000,'cash','deposit') returning id into p;
 if (select paid from public.vehicles where id=v)<>3000 then raise exception 'FAIL payment synchronization';end if;
 update public.vehicles set model='Stale overwrite' where id=v and version=old_version;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL stale write';end if;
 begin insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,8000,'cash','balance');raise exception 'FAIL overpayment';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,7000,'transfer','balance');
 begin insert into public.payments(request_id,vehicle_id,amount,method,purpose) select request_id,v,3000,'cash','deposit' from public.payments where id=p;raise exception 'FAIL retry inserted twice';exception when unique_violation then null;end;
 update public.vehicles set status='sold' where id=v;
 if (select sold_at is null from public.vehicles where id=v) then raise exception 'FAIL sold timestamp';end if;
 begin insert into public.payments(request_id,vehicle_id,amount,method,purpose,reverses_id,note) values(gen_random_uuid(),v,-100,'cash','refund',p,'Refund test');raise exception 'FAIL sold refund without reopen';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.vehicles set status='reserved',duplicate_reason='Verified reopen with duplicate' where id=v;
 begin insert into public.payments(request_id,vehicle_id,amount,method,purpose,reverses_id,note) values(gen_random_uuid(),v,-4000,'cash','refund',p,'Refund test');raise exception 'FAIL excessive original refund';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.payments(request_id,vehicle_id,amount,method,purpose,reverses_id,note) values(gen_random_uuid(),v,-1000,'cash','refund',p,'Refund test');
 if (select paid from public.vehicles where id=v)<>9000 then raise exception 'FAIL refund synchronization';end if;
 begin update public.payments set amount=1 where id=p;raise exception 'FAIL mutable payment';exception when insufficient_privilege then null;end;
 insert into public.jobs(customer,bike,plate,complaint,items) values('TEST rollback','Test bike','TESTJOB26','Servis','[{"name":"Service","kind":"labour","qty":1,"rate":10000}]') returning id into j;
 begin update public.jobs set status='working' where id=j;raise exception 'FAIL work without approval';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.jobs set status='working',estimate_status='approved',approved_total=10000,approval_note='Approved by test customer' where id=j;
 begin update public.jobs set status='collected',credit_reason='Owner test approval' where id=j;raise exception 'FAIL collection before ready';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.jobs set status='ready' where id=j;
 begin update public.jobs set status='collected' where id=j;raise exception 'FAIL collection without reason';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.jobs set status='collected',credit_reason='Owner test approval' where id=j;
 if (select credit_approved_by from public.jobs where id=j) is distinct from auth.uid() then raise exception 'FAIL credit actor';end if;
 insert into public.payments(request_id,job_id,amount,method,purpose) values(gen_random_uuid(),j,5000,'cash','service');
 if (select paid from public.jobs where id=j)<>5000 then raise exception 'FAIL collected partial payment';end if;
 if not exists(select 1 from public.service_history('TESTJOB26') where id=j) then raise exception 'FAIL archived history';end if;
 if exists(select 1 from public.service_history('zzzz-no-match')) then raise exception 'FAIL empty phone matches unrelated customer';end if;
 if public.owner_overview() is null then raise exception 'FAIL owner overview';end if;
 if not exists(select 1 from public.audit_log where record_kind='vehicles' and record_id=v and actor=auth.uid()) then raise exception 'FAIL audit actor';end if;
 if has_function_privilege('authenticated','private.audit_change()','execute') then raise exception 'FAIL exposed definer';end if;
end $$;
reset role;
-- Re-use the existing actor with a temporary staff role, within rollback.
update public.staff set role='garage' where id='41ad4268-5653-4ab0-84c4-b89dda95adf8';
set local role authenticated;
do $$
declare j bigint;n int;
begin
 if exists(select 1 from public.vehicles) then raise exception 'FAIL garage inventory isolation';end if;
 if exists(select 1 from public.audit_log) then raise exception 'FAIL garage audit isolation';end if;
 begin perform public.owner_overview();raise exception 'FAIL garage owner RPC';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.jobs(customer,bike,plate,complaint,items,estimate_status,approved_total,approval_note,status) values('TEST staff','Bike','TESTGAR26','Work','[{"name":"Service","kind":"labour","qty":1,"rate":5000}]','approved',5000,'Test approval','ready') returning id into j;
 begin update public.jobs set status='collected',credit_reason='Attempt bypass' where id=j;raise exception 'FAIL non-owner credit approval';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.payments(request_id,job_id,amount,method,purpose) values(gen_random_uuid(),j,5000,'cash','service');
 update public.jobs set status='collected' where id=j;
 update public.business_settings set whatsapp_phone='60123456789' where id=1;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL garage settings';end if;
end $$;
reset role;
update public.staff set role='inventory' where id='41ad4268-5653-4ab0-84c4-b89dda95adf8';
set local role authenticated;
do $$
declare v bigint;
begin
 if exists(select 1 from public.jobs) then raise exception 'FAIL inventory garage isolation';end if;
 select id into v from public.vehicles where chassis='TEST-CASIS';
 begin update public.vehicles set price=11000 where id=v;raise exception 'FAIL inventory price change';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.business_settings set whatsapp_phone='60123456789' where id=1;
end $$;
reset role;
set local role anon;
do $$
begin
 perform id from public.catalogue;
 if (select whatsapp_phone from public.business_settings where id=1)<>'60123456789' then raise exception 'FAIL public settings';end if;
 if exists(select 1 from public.vehicles) then raise exception 'FAIL anonymous private stock';end if;
 begin perform id from public.payments;raise exception 'FAIL anonymous ledger';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS: ledger, status guards, optimistic version, projection, history, owner and staff isolation; all test writes rolled back' as result;
