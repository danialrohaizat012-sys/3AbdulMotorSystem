-- Metadata-only fixtures; no physical uploads. All stock and storage changes roll back.
begin;
create temp table uat_ten_photo_paths(path text) on commit drop;
insert into uat_ten_photo_paths select gen_random_uuid()::text||'.jpg' from generate_series(1,11);
grant select on uat_ten_photo_paths to authenticated;
insert into storage.objects(bucket_id,name,metadata) select 'vehicle-photos',path,'{"mimetype":"image/jpeg","size":100}'::jsonb from uat_ten_photo_paths;
select set_config('request.jwt.claim.sub',(select id::text from public.staff where role='owner' and enabled and not must_change_password order by id limit 1),true);
set local role authenticated;
do $test$
declare paths text[]; v bigint;
begin
 select array_agg(path order by path) into paths from uat_ten_photo_paths;
 insert into public.vehicles(brand,model,year,price,published,photo,photos)
 values('UAT PHOTO LIMIT','Rollback',2026,100000,true,paths[1],paths[1:10]) returning id into v;
 if (select cardinality(photos) from public.vehicles where id=v)<>10 or (select cardinality(photos) from public.catalogue where id=v)<>10 then
  raise exception 'FAIL ten-photo stock/catalogue projection';
 end if;
 begin
  update public.vehicles set photos=paths where id=v;
  raise exception 'FAIL eleven photos accepted';
 exception when raise_exception then
  if SQLERRM not like 'Maksimum 10 gambar%' then raise;end if;
 end;
 -- A cover that would silently push ten gallery photos to eleven is also rejected.
 begin
  update public.vehicles set photo=paths[11] where id=v;
  raise exception 'FAIL cover overflow accepted';
 exception when raise_exception then
  if SQLERRM not like 'Maksimum 10 gambar%' then raise;end if;
 end;
end;
$test$;
reset role;
rollback;
select 'PASS: ten photos saved and projected; eleven and cover overflow rejected; fixtures rolled back' as result;
