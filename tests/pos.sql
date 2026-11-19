-- POS regression with isolated fixture identities. Everything rolls back.
-- Deferred sale checks are forced with SET CONSTRAINTS ... IMMEDIATE because
-- this transaction never commits.
begin;
insert into auth.users(id) values
('a0000000-0000-4000-8000-000000000001'),('a0000000-0000-4000-8000-000000000002'),
('a0000000-0000-4000-8000-000000000003'),('a0000000-0000-4000-8000-000000000004');
insert into public.staff(id,display_name,role,permissions,payment_limit) values
('a0000000-0000-4000-8000-000000000001','POS owner','owner','{}',null),
('a0000000-0000-4000-8000-000000000002','POS cashier','garage','{"pos_sell":true}',null),
('a0000000-0000-4000-8000-000000000003','POS manager','inventory','{"pos_sell":true,"pos_manage":true}',null),
('a0000000-0000-4000-8000-000000000004','No POS staff','garage','{"garage_edit":true,"receive_payments":true}',null);
set local role authenticated;

-- Staff without POS flags see nothing and cannot write.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000004',true);
do $$begin
 if private.staff_can('pos_view') then raise exception 'FAIL default pos access';end if;
 begin insert into public.pos_products(sku,name,price) values('X1','Forbidden',100);raise exception 'FAIL non-pos insert';exception when insufficient_privilege or raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.pos_shift_report(1);raise exception 'FAIL non-pos report';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;

-- Manager: products and stock receipts.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',true);
do $$declare a bigint;b bigint;begin
 insert into public.pos_products(sku,barcode,name,category,price,cost,reorder_level) values(' oil-10w40 ','955000111','Minyak enjin 10W40','Minyak',2500,1500,3) returning id into a;
 if (select sku from public.pos_products where id=a)<>'OIL-10W40' then raise exception 'FAIL sku normalise';end if;
 insert into public.pos_products(sku,name,category,price,track_stock) values('LAB-TYRE','Upah tukar tayar','Upah',3000,false) returning id into b;
 begin insert into public.pos_products(sku,name,price,stock_qty) values('BAD-1','Stock seed',100,5);raise exception 'FAIL seeded stock';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,unit_cost,note) values(gen_random_uuid(),a,10,'receive',1600,'Supplier UAT');
 if (select stock_qty from public.pos_products where id=a)<>10 or (select cost from public.pos_products where id=a)<>1600 then raise exception 'FAIL receive sync';end if;
 begin update public.pos_products set stock_qty=50 where id=a;raise exception 'FAIL direct stock edit';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.pos_stock_moves(request_id,product_id,qty,kind) values(gen_random_uuid(),a,-1,'adjust');raise exception 'FAIL adjust without reason';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.pos_stock_moves(request_id,product_id,qty,kind,note) values(gen_random_uuid(),b,5,'receive','labour');raise exception 'FAIL untracked stock';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.pos_stock_moves(request_id,product_id,qty,kind,note) values(gen_random_uuid(),a,-11,'adjust','Rosak semasa simpan');raise exception 'FAIL negative stock';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;

-- Cashier: cannot manage, must open a shift before selling.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
do $$declare a bigint:=(select id from public.pos_products where sku='OIL-10W40');begin
 begin insert into public.pos_products(sku,name,price) values('X2','Cashier product',100);raise exception 'FAIL cashier product';exception when insufficient_privilege or raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.pos_stock_moves(request_id,product_id,qty,kind,unit_cost) values(gen_random_uuid(),a,1,'receive',1);raise exception 'FAIL cashier receive';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.pos_products set price=1 where id=a;raise exception 'FAIL cashier price edit';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 insert into public.pos_shifts(opening_float) values(10000);
 begin insert into public.pos_shifts(opening_float) values(0);raise exception 'FAIL second shift';exception when raise_exception or unique_violation then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;

create temporary table pos_t(k text primary key,v bigint);
grant all on pos_t to authenticated;
do $$declare a bigint:=(select id from public.pos_products where sku='OIL-10W40');b bigint:=(select id from public.pos_products where sku='LAB-TYRE');r uuid:=gen_random_uuid();s bigint;ver integer;doc jsonb;begin
 ver:=(select version from public.pos_products where id=a);
 doc:=jsonb_build_object('customer_name','Ali','customer_phone','012-3456789','cash_tendered',6000,
  'lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',2,'unit_price',2500),jsonb_build_object('product_id',b,'qty',1,'unit_price',3000)),
  'payments','[{"method":"cash","amount":5000},{"method":"card","amount":3000}]'::jsonb);
 s:=public.pos_checkout(r,doc);
 if public.pos_checkout(r,doc)<>s then raise exception 'FAIL checkout retry';end if;
 set constraints public.pos_sales_complete immediate;set constraints public.pos_sales_complete deferred;
 if (select row(total,paid,change_given,customer_phone,cashier_name) from public.pos_sales where id=s)<>row(8000::bigint,8000::bigint,1000::bigint,'60123456789'::text,'POS cashier'::text) then raise exception 'FAIL sale totals';end if;
 if (select stock_qty from public.pos_products where id=a)<>8 then raise exception 'FAIL sale stock';end if;
 if (select version from public.pos_products where id=a)<>ver then raise exception 'FAIL sale bumped product version';end if;
 if (select count(*) from public.pos_stock_moves where sale_id=s)<>1 then raise exception 'FAIL untracked product moved';end if;
 if (select count(*) from public.payments where sale_id=s and purpose='pos')<>2 then raise exception 'FAIL sale payments';end if;
 if (select unit_cost from public.pos_sale_lines where sale_id=s and product_id=a)<>1600 then raise exception 'FAIL cost snapshot';end if;
 insert into pos_t values('sale',s);
 -- Rejections.
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',1,'unit_price',100)),'payments','[{"method":"cash","amount":100}]'::jsonb));raise exception 'FAIL price override';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('discount',500,'lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',1,'unit_price',2500)),'payments','[{"method":"cash","amount":2000}]'::jsonb));raise exception 'FAIL cashier discount';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',100,'unit_price',2500)),'payments','[{"method":"cash","amount":250000}]'::jsonb));raise exception 'FAIL oversell';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',1,'unit_price',2500)),'payments','[{"method":"cash","amount":2000}]'::jsonb));raise exception 'FAIL underpaid';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('name','Custom','qty',1,'unit_price',100)),'payments','[{"method":"cash","amount":100}]'::jsonb));raise exception 'FAIL cashier custom line';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin
  insert into public.pos_sales(request_id,shift_id,subtotal,total,created_by) values(gen_random_uuid(),(select id from public.pos_shifts where closed_at is null),1000,1000,auth.uid());
  set constraints public.pos_sales_complete immediate;raise exception 'FAIL incomplete sale committed';
 exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 set constraints public.pos_sales_complete deferred;
 begin insert into public.pos_sale_lines(sale_id,product_id,qty,unit_price) values(s,a,1,2500);raise exception 'FAIL line after sale';exception when raise_exception or unique_violation then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.pos_sales set customer_name='Changed' where id=s;raise exception 'FAIL sale edit';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.pos_sales set status='voided',void_reason='Cashier void' where id=s;raise exception 'FAIL cashier void';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.pos_void_sale(s,'Cashier void');raise exception 'FAIL cashier void rpc';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.payments(request_id,sale_id,amount,method,purpose,created_by) values(gen_random_uuid(),s,100,'cash','pos',auth.uid());raise exception 'FAIL overpay';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.pos_stock_moves(request_id,product_id,qty,kind,sale_id) values(gen_random_uuid(),a,2,'void',s);raise exception 'FAIL forged return';exception when raise_exception or unique_violation then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;

-- Accounting sees POS receipts as their own source.
reset role;
update public.staff set permissions='{"pos_sell":true,"accounting_view":true}' where display_name='No POS staff';
update public.staff set permissions='{"accounting_view":true}' where display_name='No POS staff';
set local role authenticated;
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000004',true);
do $$declare s bigint:=(select v from pos_t where k='sale');begin
 if (select count(*) from public.accounting_feed_v2(date_trunc('month',now() at time zone 'Asia/Kuala_Lumpur')::date,now()) where source='POS' and reference like 'POS-%' and counterparty='Ali')<>2 then raise exception 'FAIL accounting projection';end if;
 if exists(select 1 from public.pos_products) then raise exception 'FAIL accounting reader sees products';end if;
end$$;

-- Owner voids: payments refunded, stock restored, idempotent.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
do $$declare s bigint:=(select v from pos_t where k='sale');a bigint:=(select id from public.pos_products where sku='OIL-10W40');begin
 begin perform public.pos_void_sale(s,'abc');raise exception 'FAIL short void reason';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 perform public.pos_void_sale(s,'Pelanggan pulangkan barang');
 perform public.pos_void_sale(s,'Pelanggan pulangkan barang');
 set constraints public.pos_sales_complete immediate;set constraints public.pos_sales_complete deferred;
 if (select row(status,paid) from public.pos_sales where id=s)<>row('voided'::text,0::bigint) then raise exception 'FAIL void state';end if;
 if (select count(*) from public.payments where sale_id=s and amount<0)<>2 then raise exception 'FAIL void refunds';end if;
 if (select stock_qty from public.pos_products where id=a)<>10 then raise exception 'FAIL void stock';end if;
 if not exists(select 1 from public.audit_log where record_kind='pos_products') then raise exception 'FAIL product audit';end if;
end$$;

-- Shift close computes expected cash on the server.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
do $$declare a bigint:=(select id from public.pos_products where sku='OIL-10W40');sh bigint:=(select id from public.pos_shifts where closed_at is null);rep jsonb;begin
 perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',1,'unit_price',2500)),'payments','[{"method":"cash","amount":2500}]'::jsonb));
 set constraints public.pos_sales_complete immediate;set constraints public.pos_sales_complete deferred;
 rep:=public.pos_shift_report(sh);
 if (rep->>'expectedCash')::bigint<>12500 or (rep->>'salesCount')::int<>1 or (rep->>'voidCount')::int<>1 or (rep->>'net')::bigint<>2500 then raise exception 'FAIL shift report %',rep;end if;
 begin update public.pos_shifts set closed_at=now(),counted_cash=12000 where id=sh;raise exception 'FAIL variance without reason';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.pos_shifts set closed_at=now(),counted_cash=12000,note='Kurang RM5 semasa kira' where id=sh;
 if (select expected_cash from public.pos_shifts where id=sh)<>12500 then raise exception 'FAIL expected cash';end if;
 begin update public.pos_shifts set note='Edit after close' where id=sh;raise exception 'FAIL closed shift edit';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',1,'unit_price',2500)),'payments','[{"method":"cash","amount":2500}]'::jsonb));
 if (select count(*) from public.pos_shifts where closed_at is null and opening_float=0)<>1 then raise exception 'FAIL auto-open shift';end if;
end$$;

-- Manager discount and price change; vehicle/job payment rules remain intact.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',true);
do $$declare a bigint:=(select id from public.pos_products where sku='OIL-10W40');s bigint;ver integer:=(select version from public.pos_products where sku='OIL-10W40');begin
 s:=public.pos_checkout(gen_random_uuid(),jsonb_build_object('discount',500,'lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',1,'unit_price',2500),jsonb_build_object('name','Pelekat custom','qty',1,'unit_price',1000)),'payments','[{"method":"transfer","amount":3000}]'::jsonb));
 set constraints public.pos_sales_complete immediate;set constraints public.pos_sales_complete deferred;
 if (select total from public.pos_sales where id=s)<>3000 then raise exception 'FAIL manager discount';end if;
 update public.pos_products set price=2800 where id=a;
 if (select row(price,version) from public.pos_products where id=a)<>row(2800::bigint,ver+1) then raise exception 'FAIL manager price edit';end if;
end$$;
reset role;
set local role anon;
do $$begin
 begin perform 1 from public.pos_products;raise exception 'FAIL anon products';exception when insufficient_privilege then null;end;
 begin perform public.pos_checkout(gen_random_uuid(),'{}');raise exception 'FAIL anon checkout';exception when insufficient_privilege then null;end;
end$$;
rollback;
