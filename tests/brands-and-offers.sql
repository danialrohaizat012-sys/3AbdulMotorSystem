-- All brands, stock, payments and temporary role changes are rolled back.
begin;
select set_config('request.jwt.claim.sub',(select id::text from public.staff where role='owner' and enabled and not must_change_password order by id limit 1),true);
set local role authenticated;
do $$declare v bigint;p bigint;begin
 insert into public.vehicle_brands(name) values('uat   brand');
 insert into public.vehicle_brands(name) values('UAT BRAND') on conflict(name) do nothing;
 if (select count(*) from public.vehicle_brands where name='UAT BRAND')<>1 then raise exception 'FAIL duplicate brand';end if;
 insert into public.vehicles(brand,model,year,price,published,bike_condition,original_price,installment_from,installment_terms)
 values('UAT BRAND','Offer only',2026,100000,true,'new',130000,9900,'UAT terms only') returning id into v;
 if not exists(select 1 from public.catalogue where id=v and bike_condition='new' and price=100000 and original_price=130000 and installment_from=9900 and installment_terms='UAT terms only') then raise exception 'FAIL offer projection';end if;
 begin update public.vehicles set original_price=90000 where id=v;raise exception 'FAIL inverted discount';exception when check_violation then null;end;
 begin update public.vehicles set installment_from=0 where id=v;raise exception 'FAIL zero installment';exception when check_violation then null;end;
 insert into public.payments(request_id,vehicle_id,amount,method,purpose) values(gen_random_uuid(),v,70000,'cash','deposit') returning id into p;
 if (select amount from private.accounting_rows() where source_key='P:'||p)<>70000 or (select price-paid from public.vehicles where id=v)<>30000 then raise exception 'FAIL installment/original price changed balance';end if;
 begin update public.vehicles set price=60000 where id=v;raise exception 'FAIL discounted price below payments';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.vehicles set original_price=null,installment_from=null,installment_terms='' where id=v;
 if exists(select 1 from public.catalogue where id=v and (original_price is not null or installment_from is not null or installment_terms<>'')) then raise exception 'FAIL optional offer not removed';end if;
end;$$;
reset role;
update public.staff set role='inventory' where id=auth.uid();
set local role authenticated;
do $$begin
 insert into public.vehicle_brands(name) values('UAT STAFF BRAND');
 update public.vehicles set bike_condition='pre_owned' where brand='UAT BRAND';
 begin update public.vehicles set original_price=130000 where brand='UAT BRAND';raise exception 'FAIL staff changed original price';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.vehicles set installment_from=9900 where brand='UAT BRAND';raise exception 'FAIL staff changed installment';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end;$$;
reset role;
update public.staff set role='garage' where id=auth.uid();
set local role authenticated;
do $$begin
 if exists(select 1 from public.vehicle_brands) then raise exception 'FAIL garage brand access';end if;
 begin insert into public.vehicle_brands(name) values('UAT FORBIDDEN');raise exception 'FAIL garage added brand';exception when insufficient_privilege then null;end;
end;$$;
reset role;
set local role anon;
do $$begin begin select count(*) from public.vehicle_brands;raise exception 'FAIL anon brand manager';exception when insufficient_privilege then null;end;end;$$;
reset role;
rollback;
select 'PASS: brands, duplicate normalization, new/pre-owned projection, discount validity, real payment balances, clearing offers and role isolation' as result;
