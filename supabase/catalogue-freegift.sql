begin;
alter table public.vehicles add column freegift text not null default '' check(length(freegift)<=500);
alter table public.catalogue add column freegift text not null default '' check(length(freegift)<=500);
create function private.guard_vehicle_freegift() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if ((TG_OP='INSERT' and NEW.freegift<>'') or (TG_OP='UPDATE' and NEW.freegift is distinct from OLD.freegift)) and not private.accounting_owner() then raise exception 'Hanya owner boleh menetapkan hadiah pembelian.';end if;
 return NEW;
end;$$;
create trigger vehicles_freegift_guard before insert or update on public.vehicles for each row execute function private.guard_vehicle_freegift();
revoke all on function private.guard_vehicle_freegift() from public,anon,authenticated;
create or replace function private.sync_catalogue() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.published then
 insert into public.catalogue(id,brand,model,year,mileage,price,status,photo,description,photos,stock_no,bike_condition,original_price,installment_from,installment_terms,freegift)
 values(NEW.id,NEW.brand,NEW.model,NEW.year,NEW.mileage,NEW.price,NEW.status,NEW.photo,NEW.description,NEW.photos,NEW.stock_no,NEW.bike_condition,NEW.original_price,NEW.installment_from,NEW.installment_terms,NEW.freegift)
 on conflict(id) do update set brand=excluded.brand,model=excluded.model,year=excluded.year,mileage=excluded.mileage,price=excluded.price,status=excluded.status,photo=excluded.photo,description=excluded.description,photos=excluded.photos,stock_no=excluded.stock_no,bike_condition=excluded.bike_condition,original_price=excluded.original_price,installment_from=excluded.installment_from,installment_terms=excluded.installment_terms,freegift=excluded.freegift;
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
 select jsonb_build_object('freegift',freegift,'id',id,'stock_no',stock_no,'bike_condition',bike_condition,'original_price',original_price,'installment_from',installment_from,'installment_terms',installment_terms,'brand',brand,'model',model,'year',year,'mileage',mileage,'price',price,'status',status,'photo',photo,'description',description,'photos',to_jsonb(photos)) into expected from public.vehicles where id=NEW.id and published;
 if expected is null or to_jsonb(NEW) is distinct from expected then raise exception 'Katalog mesti sepadan dengan stok yang dipaparkan.';end if;
 return NEW;
end;$function$;
commit;
