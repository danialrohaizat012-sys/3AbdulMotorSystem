begin;
alter table public.staff drop constraint staff_role_check;
alter table public.staff add constraint staff_role_check check(role in ('owner','inventory','garage','both'));
alter table public.staff add column version integer not null default 1,
 add column permissions jsonb not null default '{"inventory_edit":true,"garage_edit":true,"receive_payments":true,"publish_catalogue":true,"manage_whatsapp":true,"manage_photos":true}',
 add column payment_limit bigint check(payment_limit is null or payment_limit between 0 and 100000000),
 add column must_change_password boolean not null default false,
 add column updated_at timestamptz not null default now();
revoke insert,update,delete on public.staff from anon,authenticated;
-- Reads only the caller's own row. Not a definer and not recursive with staff RLS.
create function private.staff_can(action text) returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.staff s where s.id=auth.uid() and s.enabled and not s.must_change_password and
 (s.role='owner' or case
 when action='inventory_view' then s.role in ('inventory','both')
 when action='garage_view' then s.role in ('garage','both')
 when action in ('inventory_edit','publish_catalogue','manage_whatsapp','manage_photos') then s.role in ('inventory','both') and coalesce((s.permissions->>action)::boolean,false)
 when action='garage_edit' then s.role in ('garage','both') and coalesce((s.permissions->>action)::boolean,false)
 when action='receive_payments' then coalesce((s.permissions->>action)::boolean,false)
 else false end));
$$;
revoke all on function private.staff_can(text) from public,anon;
grant execute on function private.staff_can(text) to authenticated;

-- Record edits and payment synchronization use distinct authorization checks.
-- A staff member can be allowed to accept payments while being read-only for records.
drop policy inventory_staff on public.vehicles;
create policy inventory_read on public.vehicles for select to authenticated using((select private.staff_can('inventory_view')));
create policy inventory_insert on public.vehicles for insert to authenticated with check((select private.staff_can('inventory_edit')));
create policy inventory_update on public.vehicles for update to authenticated using((select private.staff_can('inventory_view'))) with check((select private.staff_can('inventory_view')));
drop policy garage_staff on public.jobs;
create policy garage_read on public.jobs for select to authenticated using((select private.staff_can('garage_view')));
create policy garage_insert on public.jobs for insert to authenticated with check((select private.staff_can('garage_edit')));
create policy garage_update on public.jobs for update to authenticated using((select private.staff_can('garage_view'))) with check((select private.staff_can('garage_view')));
alter policy inventory_catalogue_insert on public.catalogue with check((select private.staff_can('inventory_view')));
alter policy inventory_catalogue_update on public.catalogue using((select private.staff_can('inventory_view'))) with check((select private.staff_can('inventory_view')));
alter policy inventory_catalogue_delete on public.catalogue using((select private.staff_can('inventory_view')));
alter policy settings_inventory_update on public.business_settings using((select private.staff_can('manage_whatsapp'))) with check((select private.staff_can('manage_whatsapp')));
alter policy inventory_photo_read on storage.objects using(bucket_id='vehicle-photos' and (select private.staff_can('inventory_view')));
alter policy inventory_photo_insert on storage.objects with check(bucket_id='vehicle-photos' and (select private.staff_can('manage_photos')));
alter policy inventory_unused_photo_delete on storage.objects using(bucket_id='vehicle-photos' and (select private.staff_can('manage_photos')) and not exists(select 1 from public.vehicles where photo=name or name=any(photos)));
alter policy payments_read on public.payments using((vehicle_id is not null and (select private.staff_can('inventory_view'))) or (job_id is not null and (select private.staff_can('garage_view'))));
alter policy payments_insert on public.payments with check(created_by=(select auth.uid()) and (select private.staff_can('receive_payments')) and (amount>0 or exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role='owner')) and ((vehicle_id is not null and (select private.staff_can('inventory_view'))) or (job_id is not null and (select private.staff_can('garage_view')))));

create or replace function private.guard_vehicle() returns trigger language plpgsql security invoker set search_path='' as $$
declare net bigint; role_name text; key text; dup boolean;
begin
 if not private.staff_can('inventory_view') then raise exception 'Akses inventori tidak dibenarkan.';end if;
 if TG_OP='INSERT' and not private.staff_can('inventory_edit') then raise exception 'Anda hanya mempunyai akses baca inventori.';end if;
 if TG_OP='UPDATE' and not private.staff_can('inventory_edit') and (to_jsonb(NEW)-array['paid','version','updated_at']) is distinct from (to_jsonb(OLD)-array['paid','version','updated_at']) then raise exception 'Anda tidak dibenarkan mengubah stok.';end if;
 if not private.staff_can('publish_catalogue') and ((TG_OP='INSERT' and NEW.published) or (TG_OP='UPDATE' and NEW.published is distinct from OLD.published)) then raise exception 'Anda tidak dibenarkan mengubah paparan katalog.';end if;
 if not private.staff_can('manage_photos') and ((TG_OP='INSERT' and (NEW.photo<>'' or cardinality(NEW.photos)>0)) or (TG_OP='UPDATE' and (NEW.photos is distinct from OLD.photos or NEW.photo is distinct from OLD.photo))) then raise exception 'Anda tidak dibenarkan mengubah foto stok.';end if;
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

create or replace function private.guard_job() returns trigger language plpgsql security invoker set search_path='' as $$
declare net bigint; amount bigint; owner boolean;
begin
 if not private.staff_can('garage_view') then raise exception 'Akses garaj tidak dibenarkan.';end if;
 if TG_OP='INSERT' and not private.staff_can('garage_edit') then raise exception 'Anda hanya mempunyai akses baca garaj.';end if;
 if TG_OP='UPDATE' and not private.staff_can('garage_edit') and (to_jsonb(NEW)-array['paid','version','updated_at']) is distinct from (to_jsonb(OLD)-array['paid','version','updated_at']) then raise exception 'Anda tidak dibenarkan mengubah job servis.';end if;
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

create or replace function private.guard_payment() returns trigger language plpgsql security invoker set search_path='' as $$
declare limit_amount bigint; net bigint; original public.payments; role_name text;
begin
 select role,display_name into role_name,NEW.receiver_name from public.staff where id=auth.uid() and enabled;
 if not private.staff_can('receive_payments') then raise exception 'Anda tidak dibenarkan menerima bayaran.';end if;
 if NEW.amount>0 and exists(select 1 from public.staff where id=auth.uid() and role<>'owner' and payment_limit is not null and NEW.amount>payment_limit) then raise exception 'Amaun melebihi had bayaran staf. Minta owner merekodkan transaksi ini.';end if;
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

create or replace function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
declare staff_name text;staff_role text;fields text[];old_data jsonb;new_data jsonb;
begin
 if auth.uid() is null then return NEW;end if;
 select display_name,role into staff_name,staff_role from public.staff where id=auth.uid() and enabled;
 if staff_role is null or (TG_TABLE_NAME in ('vehicles','business_settings') and staff_role not in ('owner','inventory','both')) or (TG_TABLE_NAME='jobs' and staff_role not in ('owner','garage','both')) then raise exception 'Akses log tidak dibenarkan.';end if;
 new_data:=to_jsonb(NEW);old_data:=case when TG_OP='UPDATE' then to_jsonb(OLD) else '{}'::jsonb end;
 select array_agg(key order by key) into fields from jsonb_each(new_data) where key not in ('updated_at','version','created_at') and value is distinct from old_data->key;
 insert into public.audit_log(record_kind,record_id,action,changed_fields,actor,actor_name) values(TG_TABLE_NAME,(new_data->>'id')::bigint,TG_OP,coalesce(fields,'{}'),auth.uid(),staff_name);
 return NEW;
end;$$;

create or replace function public.service_history(search_text text) returns setof public.jobs language plpgsql security invoker set search_path='' as $$
declare term text; plate_term text; phone_term text;
begin
 if not private.staff_can('garage_view') then raise exception 'Akses garaj diperlukan.';end if;
 term:=trim(search_text);if length(term)<2 or length(term)>120 then return;end if;
 plate_term:=regexp_replace(upper(term),'[^A-Z0-9]','','g');
 phone_term:=regexp_replace(term,'[^0-9]','','g');if left(phone_term,1)='0' then phone_term:='60'||substr(phone_term,2);end if;
 return query select j.* from public.jobs j where regexp_replace(upper(j.plate),'[^A-Z0-9]','','g')=plate_term or (length(phone_term)>=3 and j.phone=phone_term) or position(lower(term) in lower(j.customer))>0 order by j.id desc limit 100;
end;$$;
revoke all on function public.service_history(text) from public,anon;
grant execute on function public.service_history(text) to authenticated;

create table public.staff_access_log(
 id bigint generated always as identity primary key, actor uuid not null references auth.users(id),
 target uuid not null references auth.users(id), action text not null,
 changes jsonb not null, created_at timestamptz not null default now()
);
create index staff_access_actor on public.staff_access_log(actor);
create index staff_access_target on public.staff_access_log(target);
alter table public.staff_access_log enable row level security;
revoke all on public.staff_access_log from anon,authenticated;
grant select on public.staff_access_log to authenticated;
create policy staff_access_owner_read on public.staff_access_log for select to authenticated using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role='owner'));

-- Anonymous catalogue statistics expose aggregate numbers only. Hashed browser
-- identifiers are retained for two days for deduplication, never exposed.
create table private.catalogue_visit_summary(id integer primary key check(id=1),total bigint not null default 0,today bigint not null default 0,day date not null default ((now() at time zone 'Asia/Kuala_Lumpur')::date));
create table private.catalogue_visit_seen(day date not null,token_hash text not null,primary key(day,token_hash));
alter table private.catalogue_visit_summary enable row level security;
alter table private.catalogue_visit_seen enable row level security;
revoke all on private.catalogue_visit_summary,private.catalogue_visit_seen from public,anon,authenticated;
create policy counter_summary_deny on private.catalogue_visit_summary for all to anon,authenticated using(false) with check(false);
create policy counter_seen_deny on private.catalogue_visit_seen for all to anon,authenticated using(false) with check(false);
insert into private.catalogue_visit_summary(id) values(1);
-- This private definer is intentionally a narrow public counter, not an auth
-- endpoint: accepts only UUIDs; exposes no rows, identity, IP or user data.
create function private.catalogue_visit(token uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare d date:=(now() at time zone 'Asia/Kuala_Lumpur')::date;s private.catalogue_visit_summary;n int:=0;
begin
 if token is null then select * into s from private.catalogue_visit_summary where id=1;return jsonb_build_object('today',case when s.day=d then s.today else 0 end,'total',s.total,'day',d);end if;
 select * into s from private.catalogue_visit_summary where id=1 for update;
 if s.day<>d then s.day:=d;s.today:=0;delete from private.catalogue_visit_seen where day<d-1;end if;
 insert into private.catalogue_visit_seen(day,token_hash) values(d,encode(sha256(convert_to(token::text,'UTF8')),'hex')) on conflict do nothing;
 get diagnostics n=row_count;
 update private.catalogue_visit_summary set day=d,today=s.today+n,total=s.total+n where id=1 returning * into s;
 return jsonb_build_object('today',s.today,'total',s.total,'day',d);
end;$$;
revoke all on function private.catalogue_visit(uuid) from public;
grant usage on schema private to anon;
grant execute on function private.catalogue_visit(uuid) to anon,authenticated;
create function public.catalogue_visit(token uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select private.catalogue_visit(token); $$;
revoke all on function public.catalogue_visit(uuid) from public;
grant execute on function public.catalogue_visit(uuid) to anon,authenticated;
commit;
