-- Loan settings are owner-only; vehicles accept up to 10 photos. Rolls back.
begin;
insert into auth.users(id) values('e0000000-0000-4000-8000-000000000001'),('e0000000-0000-4000-8000-000000000002');
insert into public.staff(id,display_name,role,permissions) values('e0000000-0000-4000-8000-000000000001','Loan owner','owner','{}'),
('e0000000-0000-4000-8000-000000000002','Catalogue staff','inventory','{"inventory_edit":true,"manage_whatsapp":true,"manage_photos":true}');
insert into storage.objects(bucket_id,name) select 'vehicle-photos','uat-photo-'||g||'.jpg' from generate_series(1,11) g;
set local role authenticated;
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000002',true);
do $$declare v bigint;begin
 if (select loan_rate_bp from public.business_settings where id=1) is not null then raise exception 'FAIL calculator visible before owner sets a rate';end if;
 begin update public.business_settings set loan_rate_bp=550 where id=1;raise exception 'FAIL staff changed loan rate';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.business_settings set whatsapp_template='Hi {model}' where id=1;
 insert into public.vehicles(brand,model,year,price,published,photos) values('UAT PHOTOS','Ten',2024,100000,false,(select array_agg('uat-photo-'||g||'.jpg' order by g) from generate_series(1,10) g)) returning id into v;
 if (select cardinality(photos) from public.vehicles where id=v)<>10 then raise exception 'FAIL 10 photos';end if;
 begin update public.vehicles set photos=(select array_agg('uat-photo-'||g||'.jpg' order by g) from generate_series(1,11) g) where id=v;raise exception 'FAIL 11 photos accepted';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','e0000000-0000-4000-8000-000000000001',true);
do $$begin
 update public.business_settings set loan_rate_bp=550,loan_down_pct=20,loan_max_months=48 where id=1;
 if (select row(loan_rate_bp,loan_down_pct,loan_max_months) from public.business_settings where id=1)<>row(550,20,48) then raise exception 'FAIL owner loan settings';end if;
 begin update public.business_settings set loan_max_months=50 where id=1;raise exception 'FAIL invalid tenure';exception when check_violation then null;end;
 begin update public.business_settings set loan_rate_bp=5000 where id=1;raise exception 'FAIL invalid rate';exception when check_violation then null;end;
end$$;
reset role;set local role anon;
do $$begin if (select loan_rate_bp from public.business_settings where id=1)<>550 then raise exception 'FAIL public read of loan rate';end if;end$$;
rollback;
