-- Every profile/record/counter write is rolled back.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','41ad4268-5653-4ab0-84c4-b89dda95adf8',true);
insert into public.vehicles(brand,model,year,price,plate,published) values('TEST ACCESS','Rollback',2026,100000,'TESTACCESS',true);
insert into public.jobs(customer,bike,plate,complaint,items) values('TEST ACCESS','Bike','TESTACCESS','Test','[{"name":"Service","kind":"labour","qty":1,"rate":100000}]');
reset role;
update public.staff set role='both',permissions='{"inventory_edit":false,"garage_edit":false,"receive_payments":false,"publish_catalogue":false,"manage_whatsapp":false,"manage_photos":false}',payment_limit=5000 where id='41ad4268-5653-4ab0-84c4-b89dda95adf8';
set local role authenticated;
do $$
declare v bigint;j bigint;n int;
begin
 select id into v from public.vehicles where brand='TEST ACCESS';select id into j from public.jobs where customer='TEST ACCESS';
 if v is null or j is null then raise exception 'FAIL both-module access';end if;
 begin update public.vehicles set model='Changed' where id=v;raise exception 'FAIL read-only inventory';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.jobs set notes='Changed' where id=j;raise exception 'FAIL read-only garage';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.catalogue set price=1 where id=v;raise exception 'FAIL direct catalogue tamper';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,1000,'cash','deposit');raise exception 'FAIL payment-disabled';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.staff set role='owner' where id=auth.uid();raise exception 'FAIL staff self-escalation';exception when insufficient_privilege then null;end;
 begin perform public.save_staff_access(auth.uid(),auth.uid(),1,'{}');raise exception 'FAIL owner-management RPC exposed';exception when insufficient_privilege then null;end;
 update public.business_settings set whatsapp_phone='60123456789' where id=1;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL WhatsApp restriction';end if;
end $$;
reset role;
update public.staff set permissions=jsonb_set(permissions,'{receive_payments}','true') where id='41ad4268-5653-4ab0-84c4-b89dda95adf8';
set local role authenticated;
do $$
declare v bigint;j bigint;
begin
 select id into v from public.vehicles where brand='TEST ACCESS';select id into j from public.jobs where customer='TEST ACCESS';
 begin insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,6000,'cash','deposit');raise exception 'FAIL payment limit';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,5000,'cash','deposit');
 insert into public.payments(request_id,job_id,amount,method,purpose) values(gen_random_uuid(),j,5000,'cash','service');
 if (select paid from public.vehicles where id=v)<>5000 or (select paid from public.jobs where id=j)<>5000 then raise exception 'FAIL payment synchronization for read-only operator';end if;
 begin update public.vehicles set published=false where id=v;raise exception 'FAIL publish permission';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end $$;
reset role;
update public.staff set must_change_password=true where id='41ad4268-5653-4ab0-84c4-b89dda95adf8';
set local role authenticated;
do $$ begin if exists(select 1 from public.vehicles) or exists(select 1 from public.jobs) then raise exception 'FAIL temporary-password access';end if;end $$;
reset role;
update public.staff set must_change_password=false,enabled=false where id='41ad4268-5653-4ab0-84c4-b89dda95adf8';
set local role authenticated;
do $$ begin if exists(select 1 from public.vehicles) or exists(select 1 from public.jobs) then raise exception 'FAIL disabled access';end if;end $$;
reset role;
set local role anon;
do $$
declare token uuid:=gen_random_uuid();before_total bigint;once_total bigint;twice_total bigint;second_total bigint;
begin
 before_total:=(public.catalogue_visit(null)->>'total')::bigint;
 once_total:=(public.catalogue_visit(token)->>'total')::bigint;
 twice_total:=(public.catalogue_visit(token)->>'total')::bigint;
 second_total:=(public.catalogue_visit(gen_random_uuid())->>'total')::bigint;
 if once_total<>before_total+1 or twice_total<>once_total or second_total<>once_total+1 then raise exception 'FAIL visitor deduplication';end if;
 begin perform total from private.catalogue_visit_summary;raise exception 'FAIL private aggregate row exposed';exception when insufficient_privilege then null;end;
 begin perform token_hash from private.catalogue_visit_seen;raise exception 'FAIL visitor tokens exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'PASS staff read-only, module access, payment limit, disabled and temporary accounts, escalation prevention, catalogue projection and counter deduplication; all writes rolled back' as result;
