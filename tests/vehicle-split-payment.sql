begin;
insert into auth.users(id) values ('c1000000-0000-4000-8000-000000000001');
insert into public.staff(id,display_name,role,permissions,payment_limit)
values ('c1000000-0000-4000-8000-000000000001','Split cashier','inventory','{"inventory_edit":true,"receive_payments":true}',300000);
set local role authenticated;
select set_config('request.jwt.claim.sub','c1000000-0000-4000-8000-000000000001',true);
do $$
declare
 motor_id bigint;
 motor_version integer;
 request_id uuid:=gen_random_uuid();
 sale jsonb:='{"buyer":"Pembeli","buyer_phone":"0123456789","amount":300000,"method":"split","cash_amount":100000}';
 result jsonb;
begin
 insert into public.vehicles(brand,model,year,price,published)
 values ('UAT SALE','Split',2024,400000,false) returning id,version into motor_id,motor_version;
 begin
  perform public.sell_vehicle(motor_id,motor_version,gen_random_uuid(),sale||'{"amount":350000,"cash_amount":175000}');
  raise exception 'FAIL: split bypassed the combined payment limit';
 exception when raise_exception then
  if SQLERRM not like 'Jumlah bayaran melebihi had%' then raise; end if;
 end;
 result:=public.sell_vehicle(motor_id,motor_version,request_id,sale);
 if result->>'status'<>'reserved' or (result->>'balance')::bigint<>100000 then
  raise exception 'FAIL: incorrect split deposit result %',result;
 end if;
 result:=public.sell_vehicle(motor_id,motor_version,request_id,sale);
 if (select count(*) from public.payments where vehicle_id=motor_id)<>2
  or not exists(select 1 from public.payments where id=(result->>'payment_id')::bigint and method='cash' and amount=100000)
  or not exists(select 1 from public.payments where id=(result->>'transfer_payment_id')::bigint and method='transfer' and amount=200000) then
  raise exception 'FAIL: split payment rows or retry result incorrect';
 end if;
 result:=public.sell_vehicle(motor_id,(result->>'version')::integer,gen_random_uuid(),sale||'{"amount":100000,"cash_amount":50000}');
 if result->>'status'<>'sold' or (result->>'balance')::bigint<>0 then
  raise exception 'FAIL: split balance does not complete sale %',result;
 end if;
end $$;
rollback;
