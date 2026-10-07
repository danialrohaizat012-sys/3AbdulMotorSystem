begin;
create or replace function private.guard_job() returns trigger language plpgsql security invoker set search_path='' as $$
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

create or replace function private.guard_payment() returns trigger language plpgsql security invoker set search_path='' as $$
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

create or replace function public.service_history(search_text text) returns setof public.jobs language plpgsql security invoker set search_path='' as $$
declare term text; plate_term text; phone_term text;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and role in ('owner','garage')) then raise exception 'Akses garaj diperlukan.';end if;
 term:=trim(search_text);if length(term)<2 or length(term)>120 then return;end if;
 plate_term:=regexp_replace(upper(term),'[^A-Z0-9]','','g');
 phone_term:=regexp_replace(term,'[^0-9]','','g');if left(phone_term,1)='0' then phone_term:='60'||substr(phone_term,2);end if;
 return query select j.* from public.jobs j where regexp_replace(upper(j.plate),'[^A-Z0-9]','','g')=plate_term or (length(phone_term)>=3 and j.phone=phone_term) or position(lower(term) in lower(j.customer))>0 order by j.id desc limit 100;
end;$$;
revoke all on function public.service_history(text) from public,anon;
grant execute on function public.service_history(text) to authenticated;

create index payments_actor on public.payments(created_by);
create index audit_actor on public.audit_log(actor);
create index jobs_credit_actor on public.jobs(credit_approved_by) where credit_approved_by is not null;
commit;
