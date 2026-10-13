-- Human stock numbers are separate from immutable record IDs and share links.
begin;
alter table public.vehicles add column stock_no bigint;
alter table public.catalogue add column stock_no bigint;
create or replace function private.sync_catalogue() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.published then
 insert into public.catalogue(id,brand,model,year,mileage,price,status,photo,description,photos,stock_no)
 values(NEW.id,NEW.brand,NEW.model,NEW.year,NEW.mileage,NEW.price,NEW.status,NEW.photo,NEW.description,NEW.photos,NEW.stock_no)
 on conflict(id) do update set brand=excluded.brand,model=excluded.model,year=excluded.year,mileage=excluded.mileage,price=excluded.price,status=excluded.status,photo=excluded.photo,description=excluded.description,photos=excluded.photos,stock_no=excluded.stock_no;
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
 select jsonb_build_object('id',id,'stock_no',stock_no,'brand',brand,'model',model,'year',year,'mileage',mileage,'price',price,'status',status,'photo',photo,'description',description,'photos',to_jsonb(photos)) into expected from public.vehicles where id=NEW.id and published;
 if expected is null or to_jsonb(NEW) is distinct from expected then raise exception 'Katalog mesti sepadan dengan stok yang dipaparkan.';end if;
 return NEW;
end;$function$;

-- Use normal business guards/audit when assigning numbers to existing stock.
select set_config('request.jwt.claim.sub',(select id::text from public.staff where role='owner' and enabled and not must_change_password order by id limit 1),true);
set local role authenticated;
with numbered as(select id,row_number() over(order by created_at,id) n from public.vehicles)
update public.vehicles v set stock_no=n.n from numbered n where v.id=n.id;
reset role;
alter table public.vehicles alter column stock_no set not null;
alter table public.vehicles add constraint vehicles_stock_number_unique unique(stock_no),add constraint vehicles_stock_number_positive check(stock_no>0);
alter table public.catalogue alter column stock_no set not null;
alter table public.catalogue add constraint catalogue_stock_number_unique unique(stock_no);
create table private.stock_counter(id integer primary key check(id=1),last_no bigint not null check(last_no>=0));
insert into private.stock_counter values(1,(select coalesce(max(stock_no),0) from public.vehicles));
alter table private.stock_counter enable row level security;
revoke all on private.stock_counter from public,anon,authenticated;
create policy stock_counter_no_direct_access on private.stock_counter for all to authenticated using(false) with check(false);
-- Narrow private definer: only assigns numbers to authorized stock INSERTs.
-- The counter row is locked transactionally, so rolled-back/failed inserts do not consume numbers.
create function private.guard_stock_number() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Akses staf diperlukan.';end if;
 if TG_OP='UPDATE' then
  if NEW.stock_no is distinct from OLD.stock_no then raise exception 'Nombor stok tidak boleh diubah.';end if;
 else
  if auth.uid() is null or not private.staff_can('inventory_edit') then raise exception 'Akses tambah stok diperlukan.';end if;
  update private.stock_counter set last_no=last_no+1 where id=1 returning last_no into NEW.stock_no;
  if NEW.stock_no is null then raise exception 'Nombor stok belum tersedia.';end if;
 end if;
 return NEW;
end;$$;
revoke all on function private.guard_stock_number() from public,anon,authenticated;
create trigger vehicles_stock_number_guard before insert or update on public.vehicles for each row execute function private.guard_stock_number();
commit;
