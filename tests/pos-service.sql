-- POS service (repair) sales: plate required, labour by any seller, parts deduct stock, history search. Rolls back.
begin;
insert into auth.users(id) values('f0000000-0000-4000-8000-000000000001'),('f0000000-0000-4000-8000-000000000002');
insert into public.staff(id,display_name,role,permissions) values('f0000000-0000-4000-8000-000000000001','Svc manager','inventory','{"pos_sell":true,"pos_manage":true}'),
('f0000000-0000-4000-8000-000000000002','Svc mechanic','garage','{"pos_sell":true}');
set local role authenticated;
select set_config('request.jwt.claim.sub','f0000000-0000-4000-8000-000000000001',true);
create temporary table svc_t(k text primary key,v bigint);grant all on svc_t to authenticated;
do $$declare a bigint;begin
 insert into public.pos_products(sku,name,category,price,cost) values('SVC-OIL','Minyak enjin','Minyak',3500,2000) returning id into a;
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,unit_cost,note) values(gen_random_uuid(),a,5,'receive',2000,'UAT');
 insert into svc_t values('oil',a);
end$$;
select set_config('request.jwt.claim.sub','f0000000-0000-4000-8000-000000000002',true);
do $$declare a bigint:=(select v from svc_t where k='oil');s bigint;h int;begin
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('sale_type','service','plate','  ','lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',1,'unit_price',3500)),'payments','[{"method":"cash","amount":3500}]'::jsonb));raise exception 'FAIL service without plate';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 s:=public.pos_checkout(gen_random_uuid(),jsonb_build_object('sale_type','service','plate','wxy 1234','bike','Honda Wave','mileage',23000,'mechanic','Abu','work_notes','Tukar minyak, laras brek','customer_name','Siti','customer_phone','0123456789',
  'lines',jsonb_build_array(jsonb_build_object('product_id',a,'qty',2,'unit_price',3500),jsonb_build_object('name','Upah servis','kind','labour','qty',1,'unit_price',2500)),'payments','[{"method":"transfer","amount":9500}]'::jsonb));
 set constraints public.pos_sales_complete immediate;set constraints public.pos_sales_complete deferred;
 if (select row(sale_type,plate,bike,mileage,mechanic,total) from public.pos_sales where id=s)<>row('service'::text,'WXY 1234'::text,'Honda Wave'::text,23000,'Abu'::text,9500::bigint) then raise exception 'FAIL service fields';end if;
 if (select string_agg(kind,',' order by id) from public.pos_sale_lines where sale_id=s)<>'part,labour' then raise exception 'FAIL line kinds';end if;
 if (select stock_qty from public.pos_products where id=a)<>3 then raise exception 'FAIL parts stock';end if;
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('name','Upah','kind','labour','qty',1,'unit_price',100)),'payments','[{"method":"cash","amount":100}]'::jsonb));raise exception 'FAIL counter custom line';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.pos_checkout(gen_random_uuid(),jsonb_build_object('sale_type','service','plate','ABC1','lines',jsonb_build_array(jsonb_build_object('name','Aksesori','kind','part','qty',1,'unit_price',100)),'payments','[{"method":"cash","amount":100}]'::jsonb));raise exception 'FAIL service custom part';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 select count(*) into h from public.pos_service_history('wxy1234');if h<>1 then raise exception 'FAIL history plate';end if;
 select count(*) into h from public.pos_service_history('012-345 6789');if h<>1 then raise exception 'FAIL history phone';end if;
 select count(*) into h from public.pos_service_history('siti');if h<>1 then raise exception 'FAIL history name';end if;
end$$;
reset role;
update public.staff set permissions='{"accounting_view":true}' where display_name='Svc manager';
set local role authenticated;
select set_config('request.jwt.claim.sub','f0000000-0000-4000-8000-000000000001',true);
do $$begin
 if not exists(select 1 from public.accounting_feed_v2(date_trunc('month',now() at time zone 'Asia/Kuala_Lumpur')::date,now()) where source='POS' and category='Bayaran servis' and description='Servis · Honda Wave WXY 1234') then raise exception 'FAIL accounting service label';end if;
end$$;
reset role;set local role anon;
do $$begin begin perform public.pos_service_history('WXY1234');raise exception 'FAIL anon history';exception when insufficient_privilege then null;end;end$$;
rollback;
