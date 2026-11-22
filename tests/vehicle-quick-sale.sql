-- One-step sale regression with fixture identities. Rolls back.
begin;
insert into auth.users(id) values('c0000000-0000-4000-8000-000000000001'),('c0000000-0000-4000-8000-000000000002'),('c0000000-0000-4000-8000-000000000003');
insert into public.staff(id,display_name,role,permissions,payment_limit) values
('c0000000-0000-4000-8000-000000000001','Sale owner','owner','{}',null),
('c0000000-0000-4000-8000-000000000002','Sale staff','inventory','{"inventory_edit":true,"receive_payments":true}',null),
('c0000000-0000-4000-8000-000000000003','No pay staff','inventory','{"inventory_edit":true}',null);
set local role authenticated;
select set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000002',true);
create temporary table sale_t(k text primary key,v bigint);grant all on sale_t to authenticated;
do $$declare id1 bigint;id2 bigint;r jsonb;req uuid:=gen_random_uuid();ver integer;begin
 insert into public.vehicles(brand,model,year,price,published) values('UAT SALE','Full',2024,500000,false) returning id into id1;
 insert into public.vehicles(brand,model,year,price,published) values('UAT SALE','Deposit',2024,600000,false) returning id into id2;
 insert into sale_t values('full',id1),('dep',id2);
 -- Full payment in one step: buyer saved, payment recorded, status Sold.
 ver:=(select version from public.vehicles where id=id1);
 r:=public.sell_vehicle(id1,ver,req,'{"buyer":" Ali ","buyer_phone":"012-345 6789","amount":500000,"method":"transfer"}');
 if r->>'status'<>'sold' or (r->>'balance')::bigint<>0 then raise exception 'FAIL full sale %',r;end if;
 if (select row(buyer,buyer_phone,paid) from public.vehicles where id=id1)<>row('Ali'::text,'60123456789'::text,500000::bigint) then raise exception 'FAIL full sale fields';end if;
 if (select purpose from public.payments where request_id=req)<>'balance' then raise exception 'FAIL full purpose';end if;
 -- Retry after a dropped connection returns the same result without a second payment.
 r:=public.sell_vehicle(id1,ver,req,'{"buyer":"Ali","buyer_phone":"0123456789","amount":500000}');
 if (select count(*) from public.payments where vehicle_id=id1)<>1 or r->>'status'<>'sold' then raise exception 'FAIL retry';end if;
 begin perform public.sell_vehicle(id1,(r->>'version')::integer,gen_random_uuid(),'{"buyer":"Ali","buyer_phone":"0123456789","amount":1}');raise exception 'FAIL sell twice';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 -- Deposit then balance.
 ver:=(select version from public.vehicles where id=id2);
 r:=public.sell_vehicle(id2,ver,gen_random_uuid(),'{"buyer":"Siti","buyer_phone":"0198765432","amount":100000,"method":"cash"}');
 if r->>'status'<>'reserved' or (r->>'balance')::bigint<>500000 then raise exception 'FAIL deposit %',r;end if;
 if (select purpose from public.payments where vehicle_id=id2)<>'deposit' then raise exception 'FAIL deposit purpose';end if;
 begin perform public.sell_vehicle(id2,ver,gen_random_uuid(),'{"buyer":"Siti","buyer_phone":"0198765432","amount":1}');raise exception 'FAIL stale version';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.sell_vehicle(id2,(r->>'version')::integer,gen_random_uuid(),'{"buyer":"Siti","buyer_phone":"0198765432","amount":900000}');raise exception 'FAIL overpay';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.sell_vehicle(id2,(r->>'version')::integer,gen_random_uuid(),'{"buyer":"Siti","buyer_phone":"0198765432","amount":500000,"price":550000}');raise exception 'FAIL staff price change';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.sell_vehicle(id2,(r->>'version')::integer,gen_random_uuid(),'{"buyer":"","buyer_phone":"0198765432","amount":1}');raise exception 'FAIL no buyer';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.sell_vehicle(id2,(r->>'version')::integer,gen_random_uuid(),'{"buyer":"Siti","buyer_phone":"12","amount":1}');raise exception 'FAIL bad phone';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 r:=public.sell_vehicle(id2,(r->>'version')::integer,gen_random_uuid(),'{"buyer":"Siti","buyer_phone":"0198765432","amount":500000,"method":"card"}');
 if r->>'status'<>'sold' or (select count(*) from public.payments where vehicle_id=id2)<>2 then raise exception 'FAIL balance completes sale %',r;end if;
end$$;
-- Staff without payment permission can reserve but cannot take money.
select set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000003',true);
do $$declare id3 bigint;r jsonb;begin
 insert into public.vehicles(brand,model,year,price,published) values('UAT SALE','Reserve',2024,300000,false) returning id into id3;
 begin perform public.sell_vehicle(id3,1,gen_random_uuid(),'{"buyer":"Abu","buyer_phone":"0111234567","amount":1000}');raise exception 'FAIL no-pay staff took money';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 r:=public.sell_vehicle(id3,1,'d0000000-0000-4000-8000-000000000009','{"buyer":"Abu","buyer_phone":"0111234567","amount":0}');
 if r->>'status'<>'reserved' then raise exception 'FAIL reserve only';end if;
 -- Retry with the original (now stale) version after a lost response.
 r:=public.sell_vehicle(id3,1,'d0000000-0000-4000-8000-000000000009','{"buyer":"Abu","buyer_phone":"0111234567","amount":0}');
 if r->>'status'<>'reserved' then raise exception 'FAIL reserve retry';end if;
end$$;
-- Owner may change the price during the sale.
select set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000001',true);
do $$declare id4 bigint;r jsonb;begin
 insert into public.vehicles(brand,model,year,price,published) values('UAT SALE','Owner',2024,300000,false) returning id into id4;
 r:=public.sell_vehicle(id4,(select version from public.vehicles where id=id4),gen_random_uuid(),'{"buyer":"Owner buyer","buyer_phone":"0111234567","amount":280000,"price":280000}');
 if r->>'status'<>'sold' or (r->>'price')::bigint<>280000 then raise exception 'FAIL owner price %',r;end if;
end$$;
reset role;set local role anon;
do $$begin begin perform public.sell_vehicle(1,1,gen_random_uuid(),'{}');raise exception 'FAIL anon';exception when insufficient_privilege then null;end;end$$;
rollback;
