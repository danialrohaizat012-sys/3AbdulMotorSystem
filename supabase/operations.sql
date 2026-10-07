-- Operational upgrade for the dedicated 3 Abdul Motor database.
begin;
alter table public.vehicles add column version integer not null default 1,
 add column supplier text not null default '', add column supplier_phone text not null default '',
 add column chassis text not null default '', add column buyer_phone text not null default '',
 add column prep_items jsonb not null default '[]', add column photos text[] not null default '{}',
 add column duplicate_reason text not null default '', add column sold_at timestamptz;
alter table public.jobs add column version integer not null default 1,
 add column estimate_status text not null default 'draft' check(estimate_status in ('draft','sent','approved')),
 add column approval_note text not null default '', add column approved_total bigint,
 add column no_charge_reason text not null default '', add column credit_reason text not null default '',
 add column credit_approved_by uuid references auth.users(id), add column credit_approved_at timestamptz;
alter table public.catalogue add column photos text[] not null default '{}';
create index vehicles_plate_lookup on public.vehicles ((regexp_replace(upper(plate),'[^A-Z0-9]','','g'))) where status<>'sold';
create unique index vehicles_active_chassis on public.vehicles ((upper(trim(chassis)))) where chassis<>'' and status<>'sold';
create index jobs_plate_history on public.jobs ((regexp_replace(upper(plate),'[^A-Z0-9]','','g')),id desc);
create index jobs_phone_history on public.jobs(phone,id desc) where phone<>'';
revoke delete on public.vehicles,public.jobs from authenticated;

create table public.business_settings(
 id integer primary key check(id=1), whatsapp_phone text not null default '' check(whatsapp_phone='' or whatsapp_phone~'^[1-9][0-9]{7,14}$'),
 whatsapp_template text not null default 'Hi 3 Abdul Motor, saya berminat dengan {jenama} {model} ({tahun}) pada harga {harga}. Masih tersedia? {link}' check(length(whatsapp_template) between 1 and 1500),
 version integer not null default 1, updated_at timestamptz not null default now()
);
insert into public.business_settings(id) values(1);
alter table public.business_settings enable row level security;
grant select on public.business_settings to anon,authenticated;
grant update on public.business_settings to authenticated;
create policy settings_public_read on public.business_settings for select to anon,authenticated using(true);
create policy settings_inventory_update on public.business_settings for update to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')))
 with check(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')));

create table public.payments(
 id bigint generated always as identity primary key, request_id uuid not null unique,
 vehicle_id bigint references public.vehicles(id) on delete restrict, job_id bigint references public.jobs(id) on delete restrict,
 amount bigint not null check(amount<>0 and abs(amount)<=100000000), method text not null check(method in ('cash','transfer','card')),
 purpose text not null check(purpose in ('deposit','balance','service','refund')),
 paid_at timestamptz not null default now(), note text not null default '' check(length(note)<=1000),
 reverses_id bigint references public.payments(id) on delete restrict,
 created_by uuid not null references auth.users(id), receiver_name text not null default '', created_at timestamptz not null default now(),
 check((vehicle_id is null)<>(job_id is null)),check((amount<0)=(purpose='refund'))
);
create index payments_vehicle on public.payments(vehicle_id,id) where vehicle_id is not null;
create index payments_job on public.payments(job_id,id) where job_id is not null;
create index payments_reversal on public.payments(reverses_id) where reverses_id is not null;
create index payments_paid_at on public.payments(paid_at);
alter table public.payments enable row level security;
grant select,insert on public.payments to authenticated;
grant usage,select on sequence public.payments_id_seq to authenticated;
create policy payments_read on public.payments for select to authenticated using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and (role='owner' or (role='inventory' and vehicle_id is not null) or (role='garage' and job_id is not null))));
create policy payments_insert on public.payments for insert to authenticated with check(created_by=(select auth.uid()) and exists(select 1 from public.staff where id=(select auth.uid()) and enabled and (role='owner' or (role='inventory' and vehicle_id is not null and amount>0) or (role='garage' and job_id is not null and amount>0))));

create table public.audit_log(
 id bigint generated always as identity primary key, record_kind text not null, record_id bigint not null,
 action text not null, changed_fields text[] not null default '{}', actor uuid not null references auth.users(id),actor_name text not null, created_at timestamptz not null default now()
);
create index audit_latest on public.audit_log(id desc);
alter table public.audit_log enable row level security;
grant select on public.audit_log to authenticated;
create policy audit_owner_read on public.audit_log for select to authenticated using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role='owner'));

create function private.guard_vehicle() returns trigger language plpgsql security invoker set search_path='' as $$
declare net bigint; role_name text; key text; dup boolean;
begin
 select role into role_name from public.staff where id=auth.uid() and enabled;
 NEW.plate:=upper(trim(NEW.plate));NEW.chassis:=upper(trim(NEW.chassis));
 if TG_OP='UPDATE' then
  NEW.version:=OLD.version+1;
  if NEW.price<>OLD.price and role_name is distinct from 'owner' then raise exception 'Hanya owner boleh mengubah harga jualan.';end if;
  if OLD.status='sold' and NEW.status<>'sold' and role_name is distinct from 'owner' then raise exception 'Hanya owner boleh membuka semula jualan.';end if;
 end if;
 if not private.valid_job_items(NEW.prep_items) then raise exception 'Pecahan kos persediaan tidak sah.';end if;
 NEW.prep:=private.job_total(NEW.prep_items);
 select coalesce(sum(amount),0) into net from public.payments where vehicle_id=NEW.id;
 if NEW.paid<>net then raise exception 'Bayaran mesti direkod melalui transaksi bayaran.';end if;
 if NEW.paid>NEW.price then raise exception 'Harga tidak boleh lebih rendah daripada bayaran yang sudah diterima.';end if;
 if NEW.published and NEW.price<=0 then raise exception 'Masukkan harga jualan sebelum paparkan stok di katalog.';end if;
 if NEW.status='sold' then
  if NEW.price<=0 or NEW.paid<>NEW.price or trim(NEW.buyer)='' or trim(NEW.buyer_phone)='' then raise exception 'Sold memerlukan harga sah, nama dan telefon pembeli serta bayaran penuh.';end if;
  if TG_OP='INSERT' then NEW.sold_at:=now();elsif OLD.status<>'sold' then NEW.sold_at:=now();else NEW.sold_at:=OLD.sold_at;end if;
 else NEW.sold_at:=null;end if;
 if NEW.status<>'sold' and NEW.plate<>'' and (TG_OP='INSERT' or OLD.status='sold' or regexp_replace(NEW.plate,'[^A-Z0-9]','','g')<>regexp_replace(OLD.plate,'[^A-Z0-9]','','g')) then
  perform pg_advisory_xact_lock(hashtext('3am-plate'),hashtext(regexp_replace(NEW.plate,'[^A-Z0-9]','','g')));
  select exists(select 1 from public.vehicles where id<>NEW.id and status<>'sold' and regexp_replace(upper(plate),'[^A-Z0-9]','','g')=regexp_replace(NEW.plate,'[^A-Z0-9]','','g')) into dup;
  if dup and length(trim(NEW.duplicate_reason))<5 then raise exception 'Nombor plat ini sudah ada dalam stok aktif. Semak atau isi sebab rekod pendua.';end if;
 end if;
 if cardinality(NEW.photos)>5 then raise exception 'Maksimum 5 gambar setiap stok.';end if;
 if NEW.photo<>'' and not NEW.photo=any(NEW.photos) then NEW.photos:=array_prepend(NEW.photo,NEW.photos);end if;
 if cardinality(NEW.photos)>5 then raise exception 'Maksimum 5 gambar setiap stok.';end if;
 NEW.photo:=coalesce(NEW.photos[1],'');
 foreach key in array NEW.photos loop
  if key!~'^[a-z0-9-]+\.(jpg|png|webp)$' or not exists(select 1 from storage.objects where bucket_id='vehicle-photos' and name=key) then raise exception 'Foto tidak tersedia. Muat naik gambar semula.';end if;
 end loop;
 return NEW;
end;$$;
revoke all on function private.guard_vehicle() from public;
create trigger vehicles_business_guard before insert or update on public.vehicles for each row execute function private.guard_vehicle();

create function private.guard_job() returns trigger language plpgsql security invoker set search_path='' as $$
declare net bigint; amount bigint; owner boolean;
begin
 owner:=exists(select 1 from public.staff where id=auth.uid() and enabled and role='owner');
 NEW.plate:=upper(trim(NEW.plate));NEW.phone:=regexp_replace(NEW.phone,'[^0-9]','','g');if left(NEW.phone,1)='0' then NEW.phone:='60'||substr(NEW.phone,2);end if;
 select coalesce(sum(p.amount),0) into net from public.payments p where p.job_id=NEW.id;
 if NEW.paid<>net then raise exception 'Bayaran mesti direkod melalui transaksi bayaran.';end if;
 amount:=private.job_total(NEW.items);
 if TG_OP='UPDATE' then
  NEW.version:=OLD.version+1;
  if OLD.status='collected' and NEW.status<>'collected' and not owner then raise exception 'Hanya owner boleh membuka semula job yang diserahkan.';end if;
  if OLD.status='collected' and NEW.status='collected' and NEW.items is distinct from OLD.items then raise exception 'Buka semula job sebelum mengubah caj invois yang sudah diserahkan.';end if;
 end if;
 if NEW.estimate_status='approved' then
  if length(trim(NEW.approval_note))<5 or NEW.approved_total is distinct from amount then raise exception 'Rekod persetujuan pelanggan untuk jumlah anggaran semasa.';end if;
 else NEW.approved_total:=null;end if;
 if NEW.status in ('working','ready','collected') then
  if amount>0 and NEW.estimate_status<>'approved' then raise exception 'Rekod persetujuan pelanggan sebelum mulakan kerja.';end if;
  if amount=0 and length(trim(NEW.no_charge_reason))<5 then raise exception 'Isi sebab servis percuma sebelum mulakan atau siapkan kerja.';end if;
 end if;
 if NEW.status='collected' and (TG_OP='INSERT' or OLD.status<>'collected') then
  if TG_OP='INSERT' or OLD.status<>'ready' then raise exception 'Job mesti berstatus Siap sebelum diserahkan.';end if;
 end if;
 if NEW.status='collected' and NEW.paid<amount then
  if TG_OP='INSERT' or OLD.status<>'collected' or NEW.credit_reason is distinct from OLD.credit_reason then
   if not owner or length(trim(NEW.credit_reason))<5 then raise exception 'Serahan dengan baki memerlukan kelulusan owner dan sebab.';end if;
   NEW.credit_approved_by:=auth.uid();NEW.credit_approved_at:=now();
  else NEW.credit_approved_by:=OLD.credit_approved_by;NEW.credit_approved_at:=OLD.credit_approved_at;end if;
  if NEW.credit_approved_by is null then raise exception 'Kelulusan owner untuk baki belum direkodkan.';end if;
 elsif TG_OP='UPDATE' then NEW.credit_approved_by:=OLD.credit_approved_by;NEW.credit_approved_at:=OLD.credit_approved_at;
 else NEW.credit_approved_by:=null;NEW.credit_approved_at:=null;end if;
 return NEW;
end;$$;
revoke all on function private.guard_job() from public;
create trigger jobs_business_guard before insert or update on public.jobs for each row execute function private.guard_job();

create function private.guard_payment() returns trigger language plpgsql security invoker set search_path='' as $$
declare limit_amount bigint; net bigint; original public.payments; role_name text;
begin
 select role,display_name into role_name,NEW.receiver_name from public.staff where id=auth.uid() and enabled;
 if role_name is null then raise exception 'Akses staf diperlukan.';end if;
 NEW.created_by:=auth.uid();NEW.created_at:=now();
 if NEW.vehicle_id is not null then
  select price into limit_amount from public.vehicles where id=NEW.vehicle_id for update;
  select coalesce(sum(amount),0) into net from public.payments where vehicle_id=NEW.vehicle_id;
 else
  select private.job_total(items) into limit_amount from public.jobs where id=NEW.job_id for update;
  select coalesce(sum(amount),0) into net from public.payments where job_id=NEW.job_id;
 end if;
 if limit_amount is null then raise exception 'Rekod tidak dijumpai atau akses tidak dibenarkan.';end if;
 -- A retried request reaches the unique constraint without re-applying balance guards.
 if exists(select 1 from public.payments where request_id=NEW.request_id) then return NEW;end if;
 if NEW.amount>0 and ((NEW.vehicle_id is not null and NEW.purpose not in ('deposit','balance')) or (NEW.job_id is not null and NEW.purpose<>'service')) then raise exception 'Tujuan bayaran tidak sepadan dengan rekod.';end if;
 if NEW.paid_at>now()+interval '1 day' or NEW.paid_at<'2020-01-01'::timestamptz then raise exception 'Tarikh bayaran tidak sah.';end if;
 if NEW.amount<0 then
  if role_name<>'owner' or length(trim(NEW.note))<5 or NEW.reverses_id is null then raise exception 'Refund memerlukan owner, transaksi asal dan sebab.';end if;
  select * into original from public.payments where id=NEW.reverses_id;
  if original.id is null or original.amount<=0 or original.vehicle_id is distinct from NEW.vehicle_id or original.job_id is distinct from NEW.job_id then raise exception 'Transaksi asal refund tidak sah.';end if;
  if abs(NEW.amount)>original.amount+coalesce((select sum(amount) from public.payments where reverses_id=original.id),0) then raise exception 'Refund melebihi bayaran asal yang masih tersedia.';end if;
 elsif NEW.reverses_id is not null then raise exception 'Transaksi positif tidak boleh mempunyai rujukan refund.';end if;
 if net+NEW.amount<0 or net+NEW.amount>limit_amount then raise exception 'Jumlah bayaran melebihi baki atau refund melebihi bayaran diterima.';end if;
 return NEW;
end;$$;
revoke all on function private.guard_payment() from public;
create trigger payments_validate before insert on public.payments for each row execute function private.guard_payment();
create function private.sync_payment() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.vehicle_id is not null then update public.vehicles set paid=(select coalesce(sum(amount),0) from public.payments where vehicle_id=NEW.vehicle_id) where id=NEW.vehicle_id;
 else update public.jobs set paid=(select coalesce(sum(amount),0) from public.payments where job_id=NEW.job_id) where id=NEW.job_id;end if;
 return NEW;
end;$$;
revoke all on function private.sync_payment() from public;
create trigger payments_sync after insert on public.payments for each row execute function private.sync_payment();

create or replace function private.sync_catalogue() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.published then
 insert into public.catalogue(id,brand,model,year,mileage,price,status,photo,description,photos)
 values(NEW.id,NEW.brand,NEW.model,NEW.year,NEW.mileage,NEW.price,NEW.status,NEW.photo,NEW.description,NEW.photos)
 on conflict(id) do update set brand=excluded.brand,model=excluded.model,year=excluded.year,mileage=excluded.mileage,price=excluded.price,status=excluded.status,photo=excluded.photo,description=excluded.description,photos=excluded.photos;
 else delete from public.catalogue where id=NEW.id;end if;return NEW;
end;$$;

-- The sole SECURITY DEFINER trigger writes an immutable audit row into an
-- otherwise unwritable table. It is private, checks auth.uid() and staff role,
-- and is not callable through the Data API. Business operations retain RLS.
create function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
declare staff_name text;staff_role text;fields text[];old_data jsonb;new_data jsonb;
begin
 if auth.uid() is null then return NEW;end if;
 select display_name,role into staff_name,staff_role from public.staff where id=auth.uid() and enabled;
 if staff_role is null or (TG_TABLE_NAME in ('vehicles','business_settings') and staff_role not in ('owner','inventory')) or (TG_TABLE_NAME='jobs' and staff_role not in ('owner','garage')) then raise exception 'Akses log tidak dibenarkan.';end if;
 new_data:=to_jsonb(NEW);old_data:=case when TG_OP='UPDATE' then to_jsonb(OLD) else '{}'::jsonb end;
 select array_agg(key order by key) into fields from jsonb_each(new_data) where key not in ('updated_at','version','created_at') and value is distinct from old_data->key;
 insert into public.audit_log(record_kind,record_id,action,changed_fields,actor,actor_name) values(TG_TABLE_NAME,(new_data->>'id')::bigint,TG_OP,coalesce(fields,'{}'),auth.uid(),staff_name);
 return NEW;
end;$$;
revoke all on function private.audit_change() from public,anon,authenticated;
create trigger vehicles_audit after insert or update on public.vehicles for each row execute function private.audit_change();
create trigger jobs_audit after insert or update on public.jobs for each row execute function private.audit_change();
create trigger settings_audit after update on public.business_settings for each row execute function private.audit_change();
create function private.settings_version() returns trigger language plpgsql security invoker set search_path='' as $$
begin NEW.version:=OLD.version+1;NEW.updated_at:=now();return NEW;end;$$;
revoke all on function private.settings_version() from public;
create trigger settings_version before update on public.business_settings for each row execute function private.settings_version();

-- Published galleries are readable; only inventory staff may delete images
-- that are not referenced by any stock record, including unpublished stock.
drop policy published_vehicle_photos on storage.objects;
create policy published_vehicle_photos on storage.objects for select to anon,authenticated using(bucket_id='vehicle-photos' and exists(select 1 from public.catalogue where photo=name or name=any(photos)));
create policy inventory_unused_photo_delete on storage.objects for delete to authenticated using(bucket_id='vehicle-photos' and exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role in ('owner','inventory')) and not exists(select 1 from public.vehicles where photo=name or name=any(photos)));

create function public.owner_overview() returns jsonb language plpgsql security invoker set search_path='' as $$
declare month_start timestamptz;result jsonb;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and role='owner') then raise exception 'Akses owner diperlukan.';end if;
 month_start:=date_trunc('month',now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
 select jsonb_build_object('month',to_char(month_start at time zone 'Asia/Kuala_Lumpur','MM/YYYY'),
 'soldCount',(select count(*) from public.vehicles where status='sold' and sold_at>=month_start),
 'sales',(select coalesce(sum(price),0) from public.vehicles where status='sold' and sold_at>=month_start),
 'grossProfit',(select coalesce(sum(price-cost-prep),0) from public.vehicles where status='sold' and sold_at>=month_start),
 'vehicleReceipts',(select coalesce(sum(amount),0) from public.payments where vehicle_id is not null and paid_at>=month_start and paid_at<=now()),
 'serviceReceipts',(select coalesce(sum(amount),0) from public.payments where job_id is not null and paid_at>=month_start and paid_at<=now()),
 'vehicleOutstanding',(select coalesce(sum(greatest(price-paid,0)),0) from public.vehicles where status='reserved' or (paid>0 and status<>'sold')),
 'serviceOutstanding',(select coalesce(sum(greatest(private.job_total(items)-paid,0)),0) from public.jobs)) into result;
 return result;
end;$$;
revoke all on function public.owner_overview() from public,anon;
grant execute on function public.owner_overview() to authenticated;
commit;
