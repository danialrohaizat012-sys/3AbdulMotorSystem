-- Roll back all synthetic stock and counter increments.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.staff where role='owner' and enabled and not must_change_password order by id limit 1),true);
set local role authenticated;
do $$declare first_no bigint;next_no bigint;record_id bigint;begin
 select coalesce(max(stock_no),0)+1 into first_no from public.vehicles;
 begin
  insert into public.vehicles(brand,model,year,price,published,stock_no) values('UAT NUMBER','Rollback',2026,10000,false,999999) returning stock_no into next_no;
  if next_no<>first_no then raise exception 'FAIL number allocated incorrectly';end if;
  raise exception 'ROLLBACK_SUBTRANSACTION';
 exception when raise_exception then if SQLERRM<>'ROLLBACK_SUBTRANSACTION' then raise;end if;end;
 insert into public.vehicles(brand,model,year,price,published) values('UAT NUMBER','First',2026,10000,true) returning id,stock_no into record_id,next_no;
 if next_no<>first_no then raise exception 'FAIL rollback consumed stock number';end if;
 if not exists(select 1 from public.catalogue where id=record_id and stock_no=next_no) then raise exception 'FAIL public stock number mismatch';end if;
 begin update public.vehicles set stock_no=999999 where id=record_id;raise exception 'FAIL number editable';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.vehicles(brand,model,year,price,published) values('UAT NUMBER','Second',2026,10000,false) returning stock_no into next_no;
 if next_no<>first_no+1 then raise exception 'FAIL sequence skipped';end if;
 begin update private.stock_counter set last_no=0;raise exception 'FAIL counter exposed';exception when insufficient_privilege then null;end;
 if not exists(select 1 from public.vehicles where id=32 and stock_no=1) then raise exception 'FAIL original identity changed';end if;
end;$$;
reset role;
rollback;
select 'PASS: sequential display numbers, rollback reuse, immutable number, catalogue sync and private counter' as result;
