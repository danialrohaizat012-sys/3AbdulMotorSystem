-- Run only in the dedicated 3 Abdul Motor project after reviewing this schema.
-- No existing client project or auth user is modified.
begin;
create table public.staff (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '',
 role text not null check (role in ('owner','inventory','garage')),
 enabled boolean not null default true
);
alter table public.staff enable row level security;
grant select on public.staff to authenticated;
create policy staff_read_self on public.staff for select to authenticated using(id=(select auth.uid()));

create table public.vehicles (
 id bigint generated always as identity primary key,
 brand text not null check(length(trim(brand))>0), model text not null check(length(trim(model))>0),
 year integer not null check(year between 1950 and 2100), plate text not null default '',
 mileage integer not null default 0 check(mileage>=0), price bigint not null check(price>=0),
 cost bigint not null default 0 check(cost>=0), prep bigint not null default 0 check(prep>=0),
 paid bigint not null default 0 check(paid>=0), buyer text not null default '',
 status text not null default 'available' check(status in ('available','reserved','sold')),
 published boolean not null default true, photo text not null default '', description text not null default '',
 inspection jsonb not null default '[]' check(jsonb_typeof(inspection)='array'),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 constraint full_payment_before_sold check(status<>'sold' or paid>=price)
);
alter table public.vehicles enable row level security;
grant select,insert,update,delete on public.vehicles to authenticated;
grant usage,select on sequence public.vehicles_id_seq to authenticated;
create policy inventory_staff on public.vehicles for all to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')))
 with check(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')));

create table public.catalogue (
 id bigint primary key references public.vehicles(id) on delete cascade,
 brand text not null,model text not null,year integer not null,mileage integer not null,
 price bigint not null,status text not null,photo text not null default '',description text not null default ''
);
alter table public.catalogue enable row level security;
grant select on public.catalogue to anon,authenticated;
grant insert,update,delete on public.catalogue to authenticated;
create policy public_catalogue_read on public.catalogue for select to anon,authenticated using(true);
create policy inventory_catalogue_insert on public.catalogue for insert to authenticated
 with check(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')));
create policy inventory_catalogue_update on public.catalogue for update to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')))
 with check(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')));
create policy inventory_catalogue_delete on public.catalogue for delete to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')));

create schema if not exists private;
create function private.sync_catalogue() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.published then
 insert into public.catalogue(id,brand,model,year,mileage,price,status,photo,description)
 values(NEW.id,NEW.brand,NEW.model,NEW.year,NEW.mileage,NEW.price,NEW.status,NEW.photo,NEW.description)
 on conflict(id) do update set brand=excluded.brand,model=excluded.model,year=excluded.year,mileage=excluded.mileage,price=excluded.price,status=excluded.status,photo=excluded.photo,description=excluded.description;
 else delete from public.catalogue where id=NEW.id;
 end if;
 return NEW;
end;
$$;
revoke all on function private.sync_catalogue() from public;
create trigger vehicles_sync_catalogue after insert or update on public.vehicles for each row execute function private.sync_catalogue();

create function private.job_total(lines jsonb) returns bigint language sql immutable security invoker set search_path='' as $$
 select coalesce(sum((x->>'qty')::bigint * (x->>'rate')::bigint),0)::bigint from jsonb_array_elements(lines) x;
$$;
grant usage on schema private to authenticated;
grant execute on function private.job_total(jsonb) to authenticated;
create function private.valid_job_items(lines jsonb) returns boolean language sql immutable security invoker set search_path='' as $$
 select jsonb_typeof(lines)='array' and jsonb_array_length(lines)<=100 and coalesce(bool_and(coalesce(
 jsonb_typeof(x)='object' and length(trim(x->>'name')) between 1 and 120
 and (x->>'kind') in ('part','labour') and (x->>'qty')::bigint between 1 and 1000
 and (x->>'rate')::bigint between 0 and 100000000,false)),true)
 from jsonb_array_elements(lines) x;
$$;
revoke all on function private.job_total(jsonb) from public;
revoke all on function private.valid_job_items(jsonb) from public;
grant execute on function private.valid_job_items(jsonb) to authenticated;
create table public.jobs (
 id bigint generated always as identity primary key,
 customer text not null check(length(trim(customer))>0),phone text not null default '',
 bike text not null check(length(trim(bike))>0),plate text not null check(length(trim(plate))>0),
 mileage integer not null default 0 check(mileage>=0),complaint text not null check(length(trim(complaint))>0),
 notes text not null default '',mechanic text not null default '',
 status text not null default 'new' check(status in ('new','working','ready','collected')),
 items jsonb not null default '[]' check(private.valid_job_items(items)),
 paid bigint not null default 0 check(paid>=0 and paid<=private.job_total(items)),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.jobs enable row level security;
grant select,insert,update,delete on public.jobs to authenticated;
grant usage,select on sequence public.jobs_id_seq to authenticated;
create policy garage_staff on public.jobs for all to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','garage')))
 with check(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','garage')));

create function private.touch_record() returns trigger language plpgsql security invoker set search_path='' as $$
begin NEW.updated_at=now();return NEW;end;
$$;
revoke all on function private.touch_record() from public;
create trigger vehicles_touch before update on public.vehicles for each row execute function private.touch_record();
create trigger jobs_touch before update on public.jobs for each row execute function private.touch_record();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('vehicle-photos','vehicle-photos',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy published_vehicle_photos on storage.objects for select to anon,authenticated
 using(bucket_id='vehicle-photos' and exists(select 1 from public.catalogue where photo=name));
create policy inventory_photo_read on storage.objects for select to authenticated
 using(bucket_id='vehicle-photos' and exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')));
create policy inventory_photo_insert on storage.objects for insert to authenticated
 with check(bucket_id='vehicle-photos' and exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')));
commit;
