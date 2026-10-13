begin;
create table public.vehicle_brands(name text primary key check(length(name) between 2 and 80));
insert into public.vehicle_brands(name) select distinct upper(regexp_replace(trim(brand),'[[:space:]]+',' ','g')) from public.vehicles where length(trim(brand)) between 2 and 80;
alter table public.vehicle_brands enable row level security;
grant select,insert on public.vehicle_brands to authenticated;
revoke all on public.vehicle_brands from anon;
create policy brands_inventory_read on public.vehicle_brands for select to authenticated using((select private.staff_can('inventory_view')));
create policy brands_inventory_add on public.vehicle_brands for insert to authenticated with check((select private.staff_can('inventory_edit')));
create function private.normalize_vehicle_brand() returns trigger language plpgsql security invoker set search_path='' as $$
begin NEW.name:=upper(regexp_replace(trim(NEW.name),'[[:space:]]+',' ','g'));return NEW;end;$$;
create trigger brands_normalize before insert on public.vehicle_brands for each row execute function private.normalize_vehicle_brand();
revoke all on function private.normalize_vehicle_brand() from public,anon,authenticated;

alter table public.vehicles add column bike_condition text not null default 'pre_owned' check(bike_condition in ('new','pre_owned')),
 add column original_price bigint check(original_price between 1 and 100000000),
 add column installment_from bigint check(installment_from between 1 and 100000000),
 add column installment_terms text not null default '' check(length(installment_terms)<=600),
 add constraint vehicle_original_price_valid check(original_price is null or original_price>=price);
alter table public.catalogue add column bike_condition text not null default 'pre_owned' check(bike_condition in ('new','pre_owned')),
 add column original_price bigint, add column installment_from bigint, add column installment_terms text not null default '';
create function private.guard_vehicle_offer() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if TG_OP='UPDATE' and row(NEW.original_price,NEW.installment_from,NEW.installment_terms) is distinct from row(OLD.original_price,OLD.installment_from,OLD.installment_terms) and not private.accounting_owner() then raise exception 'Hanya owner boleh mengubah harga asal dan tawaran ansuran.';end if;
 return NEW;
end;$$;
create trigger vehicles_offer_guard before insert or update on public.vehicles for each row execute function private.guard_vehicle_offer();
revoke all on function private.guard_vehicle_offer() from public,anon,authenticated;
create or replace function private.sync_catalogue() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.published then
 insert into public.catalogue(id,brand,model,year,mileage,price,status,photo,description,photos,stock_no,bike_condition,original_price,installment_from,installment_terms)
 values(NEW.id,NEW.brand,NEW.model,NEW.year,NEW.mileage,NEW.price,NEW.status,NEW.photo,NEW.description,NEW.photos,NEW.stock_no,NEW.bike_condition,NEW.original_price,NEW.installment_from,NEW.installment_terms)
 on conflict(id) do update set brand=excluded.brand,model=excluded.model,year=excluded.year,mileage=excluded.mileage,price=excluded.price,status=excluded.status,photo=excluded.photo,description=excluded.description,photos=excluded.photos,stock_no=excluded.stock_no,bike_condition=excluded.bike_condition,original_price=excluded.original_price,installment_from=excluded.installment_from,installment_terms=excluded.installment_terms;
 else delete from public.catalogue where id=NEW.id;end if;return NEW;
end;$$;
CREATE OR REPLACE FUNCTION private.guard_catalogue_projection()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare expected jsonb;
begin
 if not private.staff_can('inventory_view') then raise exception 'Akses katalog tidak dibenarkan.';end if;
 if TG_OP='DELETE' then
  if exists(select 1 from public.vehicles where id=OLD.id and published) then raise exception 'Ubah paparan katalog melalui rekod stok.';end if;
  return OLD;
 end if;
 select jsonb_build_object('id',id,'stock_no',stock_no,'bike_condition',bike_condition,'original_price',original_price,'installment_from',installment_from,'installment_terms',installment_terms,'brand',brand,'model',model,'year',year,'mileage',mileage,'price',price,'status',status,'photo',photo,'description',description,'photos',to_jsonb(photos)) into expected from public.vehicles where id=NEW.id and published;
 if expected is null or to_jsonb(NEW) is distinct from expected then raise exception 'Katalog mesti sepadan dengan stok yang dipaparkan.';end if;
 return NEW;
end;$function$;
commit;
