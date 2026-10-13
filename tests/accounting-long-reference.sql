-- Synthetic high-number fixtures, counter edits and all ledger writes roll back.
begin;
update private.stock_counter set last_no=9999;
select set_config('request.jwt.claim.sub',(select id::text from public.staff where role='owner' and enabled and not must_change_password order by id limit 1),true);
set local role authenticated;
do $$declare v bigint;j bigint;p bigint;n bigint;begin
 insert into public.vehicles(brand,model,year,price) values('UAT HIGH NUMBER','Rollback',2026,10000) returning id,stock_no into v,n;
 if n<>10000 then raise exception 'FAIL high stock fixture';end if;
 insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,1000,'cash','deposit') returning id into p;
 if (select reference from private.accounting_rows() where source_key='P:'||p)<>'3AM-10000' then raise exception 'FAIL stock reference truncated';end if;
 insert into public.jobs(id,customer,bike,plate,complaint,items) overriding system value values(10000,'UAT HIGH NUMBER','Rollback','UATHIGH','Test','[{"name":"Work","kind":"labour","qty":1,"rate":10000}]') returning id into j;
 insert into public.payments(request_id,job_id,amount,method,purpose) values(gen_random_uuid(),j,1000,'cash','service') returning id into p;
 if (select reference from private.accounting_rows() where source_key='P:'||p)<>'JOB-10000' then raise exception 'FAIL job reference truncated';end if;
end;$$;
reset role;
rollback;
select 'PASS stock and job accounting references retain all digits above 9999; fixtures rolled back' as result;
