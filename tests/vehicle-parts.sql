-- Parts used for motorcycle preparation: stock out, cost in, locked lines, return. Rolls back.
begin;
insert into auth.users(id) values('a1000000-0000-4000-8000-000000000001'),('a1000000-0000-4000-8000-000000000002');
insert into public.staff(id,display_name,role,permissions) values('a1000000-0000-4000-8000-000000000001','Parts manager','inventory','{"pos_sell":true,"pos_manage":true,"inventory_edit":true}'),
('a1000000-0000-4000-8000-000000000002','Inventory editor','inventory','{"inventory_edit":true}');
set local role authenticated;
create temporary table vp_t(k text primary key,v bigint);grant all on vp_t to authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
do $$declare a bigint;v bigint;begin
 insert into public.pos_products(sku,name,price,cost) values('VP-TYRE','Tayar 70/90',12000,8000) returning id into a;
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,unit_cost,note) values(gen_random_uuid(),a,4,'receive',8000,'UAT');
 insert into public.vehicles(brand,model,year,price,cost,published,prep_items) values('UAT PARTS','Prep',2022,500000,300000,false,'[{"name":"Cuci","kind":"labour","qty":1,"rate":2000}]') returning id into v;
 insert into vp_t values('tyre',a),('bike',v);
end$$;
-- An inventory editor without POS flags can take parts for a bike (the admin flow).
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
do $$declare a bigint:=(select v from vp_t where k='tyre');v bigint:=(select v from vp_t where k='bike');r jsonb;req uuid:=gen_random_uuid();mid bigint;begin
 r:=public.vehicle_use_part(v,(select version from public.vehicles where id=v),req,a,2);
 if (select stock_qty from public.pos_products where id=a)<>2 then raise exception 'FAIL stock out';end if;
 if (r->>'prep')::bigint<>2000+16000 then raise exception 'FAIL prep cost %',r;end if;
 -- Retry with the same request does nothing more.
 r:=public.vehicle_use_part(v,1,req,a,2);
 if (select stock_qty from public.pos_products where id=a)<>2 then raise exception 'FAIL retry';end if;
 -- The stock-linked line cannot be edited or removed through a normal save.
 begin update public.vehicles set prep_items='[{"name":"Cuci","kind":"labour","qty":1,"rate":2000}]' where id=v;raise exception 'FAIL removed part line';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.vehicles set prep_items=jsonb_set(prep_items,'{1,rate}','1') where id=v;raise exception 'FAIL edited part cost';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 -- Other cost lines remain freely editable.
 update public.vehicles set prep_items=jsonb_set(prep_items,'{0,rate}','2500') where id=v;
 if (select prep from public.vehicles where id=v)<>18500 then raise exception 'FAIL normal prep edit';end if;
 begin perform public.vehicle_use_part(v,(select version from public.vehicles where id=v),gen_random_uuid(),a,5);raise exception 'FAIL oversell';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin perform public.vehicle_use_part(v,1,gen_random_uuid(),a,1);raise exception 'FAIL stale version';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 -- Return to stock removes the line and restores stock; a second return is rejected.
 mid:=(select id from public.pos_stock_moves where vehicle_id=v and kind='vehicle');
 r:=public.vehicle_return_part(v,(select version from public.vehicles where id=v),mid,gen_random_uuid());
 if (select stock_qty from public.pos_products where id=a)<>4 or (r->>'prep')::bigint<>2500 then raise exception 'FAIL return %',r;end if;
 begin perform public.vehicle_return_part(v,(select version from public.vehicles where id=v),mid,gen_random_uuid());raise exception 'FAIL double return';exception when raise_exception or unique_violation then if SQLERRM like 'FAIL%' then raise;end if;end;
 -- Parts cannot be forged on insert or taken for a sold bike.
 begin insert into public.vehicles(brand,model,year,price,published,prep_items) values('UAT PARTS','Forged',2022,100000,false,'[{"name":"x","kind":"part","qty":1,"rate":1,"moveId":1}]');raise exception 'FAIL forged insert';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 -- A bare 'vehicle' move through the API is rejected; only the RPCs may create one.
 begin insert into public.pos_stock_moves(request_id,product_id,qty,kind,vehicle_id,note) values(gen_random_uuid(),a,-1,'vehicle',v,'direct');raise exception 'FAIL direct vehicle move';exception when raise_exception then if SQLERRM like 'FAIL%' or SQLERRM not like '%Ambil dari stok%' then raise;end if;end;
 begin insert into public.pos_stock_moves(request_id,product_id,qty,kind,note) values(gen_random_uuid(),a,1,'receive','no POS flags');raise exception 'FAIL editor received stock';exception when raise_exception or insufficient_privilege then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;
reset role;set local role anon;
do $$begin begin perform public.vehicle_use_part(1,1,gen_random_uuid(),1,1);raise exception 'FAIL anon';exception when insufficient_privilege then null;end;end$$;
rollback;
