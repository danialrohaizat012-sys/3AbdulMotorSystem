-- Additive upgrade for the dedicated 3 Abdul Motor database. Apply after accounting.sql.
begin;
drop trigger accounting_account_guard on public.accounting_accounts;
drop trigger accounting_accounts_audit on public.accounting_accounts;
alter table public.accounting_accounts drop constraint accounting_accounts_id_check;
alter table public.accounting_accounts add column account_type text not null default 'bank' check(account_type in ('cash','bank','ewallet')),
 add column bank_name text not null default '' check(length(bank_name)<=80),
 add column account_number text not null default '' check(length(account_number)<=40),
 add column active boolean not null default true, add column version integer not null default 1;
update public.accounting_accounts set account_type='cash' where id='cash';
alter table public.accounting_accounts add constraint accounting_account_name check(length(trim(name)) between 2 and 100);
grant insert on public.accounting_accounts to authenticated;
create policy accounting_accounts_create on public.accounting_accounts for insert to authenticated with check((select private.accounting_owner()));
create or replace function private.guard_accounting_account() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 NEW.name:=trim(NEW.name);NEW.bank_name:=trim(NEW.bank_name);NEW.account_number:=trim(NEW.account_number);
 if TG_OP='INSERT' then
  if NEW.id !~ '^acct_[a-f0-9-]{36}$' or NEW.opening_on is not null or NEW.opening_balance is not null or not NEW.active then raise exception 'Akaun baharu tidak sah.';end if;
  NEW.version:=1;NEW.configured_by:=null;NEW.configured_at:=null;
 else
  if NEW.id<>OLD.id or NEW.account_type<>OLD.account_type then raise exception 'Identiti dan jenis akaun tidak boleh diubah.';end if;
  if OLD.opening_on is not null and row(NEW.opening_on,NEW.opening_balance) is distinct from row(OLD.opening_on,OLD.opening_balance) then raise exception 'Baki awal dikunci. Gunakan pelarasan dengan sebab.';end if;
  NEW.version:=OLD.version+1;NEW.configured_by:=OLD.configured_by;NEW.configured_at:=OLD.configured_at;
  if OLD.opening_on is null and NEW.opening_on is not null then NEW.configured_by:=auth.uid();NEW.configured_at:=now();end if;
  if OLD.id='cash' and not NEW.active then raise exception 'Tunai kedai mesti kekal aktif.';end if;
 end if;
 if NEW.opening_on is not null and (NEW.opening_on<'2020-01-01' or NEW.opening_on>(now() at time zone 'Asia/Kuala_Lumpur')::date) then raise exception 'Tarikh baki awal tidak sah.';end if;
 return NEW;
end;$$;
create trigger accounting_account_guard before insert or update on public.accounting_accounts for each row execute function private.guard_accounting_account();
create trigger accounting_accounts_audit after insert or update on public.accounting_accounts for each row execute function private.audit_accounting();

alter table public.accounting_entries add column vehicle_id bigint references public.vehicles(id), add column job_id bigint references public.jobs(id),
 add column cost_scope text not null default '' check(cost_scope in ('','purchase','prep','service')),
 add constraint accounting_cost_link check(not(vehicle_id is not null and job_id is not null) and
 ((cost_scope='' and vehicle_id is null and job_id is null) or (kind='expense' and ((cost_scope in ('purchase','prep') and vehicle_id is not null and job_id is null) or (cost_scope='service' and job_id is not null and vehicle_id is null)))));
create index accounting_entries_vehicle on public.accounting_entries(vehicle_id) where vehicle_id is not null;
create index accounting_entries_job on public.accounting_entries(job_id) where job_id is not null;
alter table public.accounting_annotations add column settled_on date, add column fee_amount bigint not null default 0 check(fee_amount>=0 and fee_amount<=100000000),
 add column receipt_exemption text not null default '' check(receipt_exemption='' or length(trim(receipt_exemption)) between 5 and 500);

create function private.validate_accounting_annotation_v2() returns trigger language plpgsql security invoker set search_path='' as $$
declare p public.payments;target public.accounting_accounts;received date;
begin
 if NEW.source_key like 'M:%' and (NEW.settled_on is not null or NEW.fee_amount<>0) then raise exception 'Penyelesaian hanya untuk bayaran pelanggan.';end if;
 if NEW.source_key like 'P:%' then
  select * into p from public.payments where id=substr(NEW.source_key,3)::bigint;
  received:=(p.paid_at at time zone 'Asia/Kuala_Lumpur')::date;
  if NEW.fee_amount>greatest(p.amount,0) or (p.method='cash' and NEW.fee_amount<>0) then raise exception 'Caj bayaran tidak sah.';end if;
  if NEW.account_id is null and (NEW.settled_on is not null or NEW.fee_amount<>0) then raise exception 'Pilih akaun dahulu.';end if;
  if NEW.account_id is not null then
   select * into target from public.accounting_accounts where id=NEW.account_id for share;
   if not target.active and (TG_OP='INSERT' or NEW.account_id is distinct from OLD.account_id) then raise exception 'Akaun tidak aktif.';end if;
   if p.method='card' and NEW.settled_on is null then raise exception 'Isi tarikh bayaran kad masuk bank.';end if;
  end if;
  if NEW.settled_on is not null and (NEW.settled_on<received or NEW.settled_on>(now() at time zone 'Asia/Kuala_Lumpur')::date) then raise exception 'Tarikh penyelesaian mesti selepas bayaran dan tidak melebihi hari ini.';end if;
 end if;
 if TG_OP='UPDATE' and row(NEW.settled_on,NEW.fee_amount,NEW.receipt_exemption) is distinct from row(OLD.settled_on,OLD.fee_amount,OLD.receipt_exemption) and length(trim(NEW.reason))<5 then raise exception 'Isi sebab perubahan sekurang-kurangnya 5 aksara.';end if;
 return NEW;
end;$$;
create trigger accounting_annotation_v2_guard before insert or update on public.accounting_annotations for each row execute function private.validate_accounting_annotation_v2();
revoke all on function private.validate_accounting_annotation_v2() from public,anon,authenticated;
create function public.accounting_review(p_key text,p_version integer,p_account text,p_reviewed boolean,p_reason text,p_settled date,p_fee bigint,p_exemption text) returns void language plpgsql security invoker set search_path='' as $$
declare a public.accounting_annotations;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 perform pg_advisory_xact_lock(hashtext('3am-annotation'),hashtext(p_key));
 select * into a from public.accounting_annotations where source_key=p_key for update;
 if coalesce(a.version,0)<>p_version then raise exception 'Transaksi telah berubah. Muat semula.';end if;
 insert into public.accounting_annotations(source_key,account_id,reviewed,reason,updated_by,settled_on,fee_amount,receipt_exemption)
 values(p_key,nullif(p_account,''),p_reviewed,coalesce(p_reason,''),auth.uid(),p_settled,p_fee,trim(coalesce(p_exemption,'')))
 on conflict(source_key) do update set account_id=excluded.account_id,reviewed=excluded.reviewed,reason=excluded.reason,settled_on=excluded.settled_on,fee_amount=excluded.fee_amount,receipt_exemption=excluded.receipt_exemption;
end;$$;

-- Preserve the old typed endpoint for existing clients. New clients use the richer projection.
create function private.accounting_rows_v2() returns table(source_key text,source_id bigint,source text,entry_date date,kind text,amount bigint,account_id text,to_account_id text,category text,description text,counterparty text,reference text,note text,created_at timestamptz,created_by uuid,vehicle_id bigint,job_id bigint,reversal_of bigint,voided boolean,reviewed boolean,version integer,receipt_count bigint,fee_amount bigint,settled_on date,received_on date,receipt_exemption text,cost_scope text,payment_method text) language sql stable security invoker set search_path='' as $$
 select r.source_key,r.source_id,r.source,r.entry_date,r.kind,r.amount,r.account_id,r.to_account_id,r.category,r.description,r.counterparty,r.reference,r.note,r.created_at,r.created_by,e.vehicle_id,e.job_id,r.reversal_of,r.voided,r.reviewed,r.version,r.receipt_count,0::bigint,null::date,null::date,coalesce(a.receipt_exemption,''),e.cost_scope,''::text
 from private.accounting_rows() r join public.accounting_entries e on r.source='Manual' and r.source_id=e.id left join public.accounting_annotations a on a.source_key=r.source_key
 union all
 select r.source_key,r.source_id,r.source,coalesce(a.settled_on,r.entry_date),r.kind,r.amount,r.account_id,r.to_account_id,r.category,r.description,r.counterparty,r.reference,r.note,r.created_at,r.created_by,r.vehicle_id,r.job_id,r.reversal_of,r.voided,r.reviewed,r.version,r.receipt_count,coalesce(a.fee_amount,0),a.settled_on,r.entry_date,coalesce(a.receipt_exemption,''),''::text,p.method
 from private.accounting_rows() r join public.payments p on r.source<>'Manual' and r.source_id=p.id left join public.accounting_annotations a on a.source_key=r.source_key where p.paid_at<=now();
$$;


create function private.accounting_balance(p_account text,p_date date) returns bigint language sql stable security invoker set search_path='' as $$
 select case when a.opening_on is null or p_date<a.opening_on then null else a.opening_balance+coalesce((select sum(case when r.account_id=a.id then case when r.kind in ('income','capital','adjustment') then r.amount-r.fee_amount else -r.amount end else 0 end+case when r.to_account_id=a.id then r.amount else 0 end) from private.accounting_rows_v2() r where r.entry_date>=a.opening_on and r.entry_date<=least(p_date,(now() at time zone 'Asia/Kuala_Lumpur')::date)),0) end from public.accounting_accounts a where a.id=p_account and (select private.accounting_owner());
$$;
create table public.accounting_reconciliations(id uuid primary key default gen_random_uuid(),account_id text not null references public.accounting_accounts(id),statement_on date not null,statement_balance bigint not null check(abs(statement_balance)<=10000000000),note text not null default '' check(length(note)<=1000),created_by uuid not null references auth.users(id),created_at timestamptz not null default now());
create index accounting_reconciliations_account on public.accounting_reconciliations(account_id,statement_on desc);
create index accounting_reconciliations_actor on public.accounting_reconciliations(created_by);
alter table public.accounting_reconciliations enable row level security;
grant select,insert on public.accounting_reconciliations to authenticated;
create policy accounting_recon_read on public.accounting_reconciliations for select to authenticated using((select private.accounting_owner()));
create policy accounting_recon_insert on public.accounting_reconciliations for insert to authenticated with check((select private.accounting_owner()) and created_by=(select auth.uid()));
create function private.guard_accounting_reconciliation() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 if NEW.statement_on>(now() at time zone 'Asia/Kuala_Lumpur')::date or private.accounting_balance(NEW.account_id,NEW.statement_on) is null then raise exception 'Tarikh semakan atau baki awal akaun tidak sah.';end if;
 NEW.created_by:=auth.uid();NEW.created_at:=now();return NEW;
end;$$;
create trigger accounting_recon_guard before insert on public.accounting_reconciliations for each row execute function private.guard_accounting_reconciliation();
create trigger accounting_recon_audit after insert on public.accounting_reconciliations for each row execute function private.audit_accounting();
revoke all on function private.guard_accounting_reconciliation() from public,anon,authenticated;
revoke all on function private.accounting_rows_v2(),private.accounting_balance(text,date) from public,anon;
grant execute on function private.accounting_rows_v2(),private.accounting_balance(text,date) to authenticated;
revoke all on function public.accounting_review(text,integer,text,boolean,text,date,bigint,text) from public,anon;
grant execute on function public.accounting_review(text,integer,text,boolean,text,date,bigint,text) to authenticated;
CREATE OR REPLACE FUNCTION private.guard_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
 if NEW.paid_at>now() or NEW.paid_at<'2020-01-01'::timestamptz then raise exception 'Tarikh bayaran tidak sah.';end if;
 if NEW.amount<0 then
  if role_name<>'owner' or length(trim(NEW.note))<5 or NEW.reverses_id is null then raise exception 'Refund memerlukan owner, transaksi asal dan sebab.';end if;
  select * into original from public.payments where id=NEW.reverses_id;
  if original.id is null or original.amount<=0 or original.vehicle_id is distinct from NEW.vehicle_id or original.job_id is distinct from NEW.job_id then raise exception 'Transaksi asal refund tidak sah.';end if;
  if abs(NEW.amount)>original.amount+coalesce((select sum(amount) from public.payments where reverses_id=original.id),0) then raise exception 'Refund melebihi bayaran asal yang masih tersedia.';end if;
 elsif NEW.reverses_id is not null then raise exception 'Transaksi positif tidak boleh mempunyai rujukan refund.';end if;
 if net+NEW.amount<0 or net+NEW.amount>limit_amount then raise exception 'Jumlah bayaran melebihi baki atau refund melebihi bayaran diterima.';end if;
 return NEW;
end;$function$;

CREATE OR REPLACE FUNCTION private.guard_accounting_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare original public.accounting_entries; start_date date;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 NEW.created_by:=auth.uid();NEW.created_at:=now();
 if NEW.entry_date<'2020-01-01' or NEW.entry_date>(now() at time zone 'Asia/Kuala_Lumpur')::date then raise exception 'Tarikh transaksi tidak sah.';end if;
 select opening_on into start_date from public.accounting_accounts where id=NEW.account_id for share;
 if start_date is null or NEW.entry_date<start_date then raise exception 'Tetapkan baki awal akaun atau pilih tarikh selepas baki awal.';end if;
 if NEW.to_account_id is not null then
  select opening_on into start_date from public.accounting_accounts where id=NEW.to_account_id for share;
  if start_date is null or NEW.entry_date<start_date then raise exception 'Tetapkan baki awal akaun penerima dahulu.';end if;
 end if;
 if NEW.reversal_of is not null then
  perform pg_advisory_xact_lock(hashtext('3am-reverse'),hashtext(NEW.reversal_of::text));
  select * into original from public.accounting_entries where id=NEW.reversal_of;
  if original.id is null or original.reversal_of is not null or NEW.amount<>-original.amount or NEW.kind<>original.kind or NEW.account_id<>original.account_id or NEW.to_account_id is distinct from original.to_account_id or NEW.category<>original.category or length(trim(NEW.note))<5 or NEW.entry_date<original.entry_date then raise exception 'Pembatalan mesti sepadan dengan transaksi asal dan mempunyai sebab.';end if;
 elsif NEW.amount<0 and NEW.kind<>'adjustment' then raise exception 'Amaun mesti positif.';
 end if;
 if NEW.kind='capital' and NEW.category<>'Modal owner' or NEW.kind='drawings' and NEW.category<>'Pengeluaran owner' or NEW.kind='transfer' and NEW.category<>'Pindahan dalaman' then raise exception 'Kategori tidak sepadan dengan jenis transaksi.';end if;
 if NEW.kind='adjustment' and (NEW.category<>'Pelarasan baki' or length(trim(NEW.note))<5) then raise exception 'Pelarasan baki memerlukan kategori dan sebab yang sah.';end if;
 if NEW.kind='income' and NEW.category<>'Pendapatan lain' then raise exception 'Bayaran pelanggan mesti direkodkan melalui Inventori atau Garage.';end if;
 if NEW.kind='expense' and NEW.category not in ('Sewa','Utiliti','Gaji','Bahan bengkel','Pembelian stok','Operasi kedai','Lain-lain') then raise exception 'Kategori perbelanjaan tidak sah.';end if;
 if NEW.reversal_of is null and exists(select 1 from public.accounting_accounts where id in (NEW.account_id,NEW.to_account_id) and not active) then raise exception 'Pilih akaun aktif.';end if;
 if NEW.reversal_of is not null and row(NEW.vehicle_id,NEW.job_id,NEW.cost_scope) is distinct from row(original.vehicle_id,original.job_id,original.cost_scope) then raise exception 'Pautan pembatalan tidak sepadan.';end if;
 if NEW.vehicle_id is not null and not exists(select 1 from public.vehicles where id=NEW.vehicle_id) or NEW.job_id is not null and not exists(select 1 from public.jobs where id=NEW.job_id) then raise exception 'Rekod kos tidak tersedia.';end if;
 return NEW;
end;$function$;

create or replace function public.accounting_post(p_request uuid,p_data jsonb) returns bigint language plpgsql security invoker set search_path='' as $$
declare result bigint;existing public.accounting_entries;new_row public.accounting_entries;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 perform pg_advisory_xact_lock(hashtext('3am-entry'),hashtext(p_request::text));
 new_row.entry_date:=(p_data->>'date')::date;new_row.kind:=p_data->>'kind';new_row.amount:=(p_data->>'amount')::bigint;new_row.account_id:=p_data->>'account';new_row.to_account_id:=nullif(p_data->>'toAccount','');new_row.category:=p_data->>'category';new_row.description:=trim(p_data->>'description');new_row.counterparty:=coalesce(p_data->>'counterparty','');new_row.reference:=coalesce(p_data->>'reference','');new_row.note:=coalesce(p_data->>'note','');
 new_row.vehicle_id:=nullif(p_data->>'vehicleId','')::bigint;new_row.job_id:=nullif(p_data->>'jobId','')::bigint;new_row.cost_scope:=coalesce(p_data->>'costScope','');
 select * into existing from public.accounting_entries where request_id=p_request;
 if existing.id is not null then
  if row(existing.entry_date,existing.kind,existing.amount,existing.account_id,existing.to_account_id,existing.category,existing.description,existing.counterparty,existing.reference,existing.note,existing.reversal_of,existing.vehicle_id,existing.job_id,existing.cost_scope) is distinct from row(new_row.entry_date,new_row.kind,new_row.amount,new_row.account_id,new_row.to_account_id,new_row.category,new_row.description,new_row.counterparty,new_row.reference,new_row.note,null::bigint,new_row.vehicle_id,new_row.job_id,new_row.cost_scope) then raise exception 'Rujukan simpan tidak sepadan. Muat semula sebelum cuba lagi.';end if;
  return existing.id;
 end if;
 insert into public.accounting_entries(request_id,entry_date,kind,amount,account_id,to_account_id,category,description,counterparty,reference,note,created_by,vehicle_id,job_id,cost_scope)
 values(p_request,new_row.entry_date,new_row.kind,new_row.amount,new_row.account_id,new_row.to_account_id,new_row.category,new_row.description,new_row.counterparty,new_row.reference,new_row.note,auth.uid(),new_row.vehicle_id,new_row.job_id,new_row.cost_scope) returning id into result;return result;
end;$$;
create or replace function public.accounting_reverse(p_id bigint,p_request uuid,p_date date,p_reason text) returns bigint language plpgsql security invoker set search_path='' as $$
declare original public.accounting_entries;result bigint;existing public.accounting_entries;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 perform pg_advisory_xact_lock(hashtext('3am-reverse'),hashtext(p_id::text));
 select * into original from public.accounting_entries where id=p_id;
 if original.id is null then raise exception 'Transaksi tidak tersedia.';end if;
 select * into existing from public.accounting_entries where reversal_of=p_id;
 if existing.id is not null then
  if existing.request_id=p_request and existing.entry_date=p_date and existing.note=p_reason then return existing.id;end if;
  raise exception 'Transaksi ini sudah dibatalkan.';
 end if;
 insert into public.accounting_entries(request_id,entry_date,kind,amount,account_id,to_account_id,category,description,counterparty,reference,note,reversal_of,created_by,vehicle_id,job_id,cost_scope)
 values(p_request,p_date,original.kind,-original.amount,original.account_id,original.to_account_id,original.category,'Pembatalan: '||left(original.description,270),original.counterparty,original.reference,p_reason,p_id,auth.uid(),original.vehicle_id,original.job_id,original.cost_scope) returning id into result;return result;
end;$$;
create function public.accounting_feed_v2(p_month date,p_before timestamptz default now()) returns table(source_key text,source_id bigint,source text,entry_date date,kind text,amount bigint,account_id text,to_account_id text,category text,description text,counterparty text,reference text,note text,created_at timestamptz,created_by uuid,vehicle_id bigint,job_id bigint,reversal_of bigint,voided boolean,reviewed boolean,version integer,receipt_count bigint,fee_amount bigint,settled_on date,received_on date,receipt_exemption text,cost_scope text,payment_method text) language plpgsql stable security invoker set search_path='' as $$
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 return query select r.* from private.accounting_rows_v2() r where r.entry_date>=date_trunc('month',p_month)::date and r.entry_date<(date_trunc('month',p_month)+interval '1 month')::date and r.created_at<=p_before order by r.entry_date desc,r.created_at desc,r.source_key desc;
end;$$;
create or replace function public.accounting_snapshot(p_month date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 with rows as materialized(select * from private.accounting_rows_v2()), accounts as(
 select a.*,exists(select 1 from rows r where r.account_id=a.id or r.to_account_id=a.id) has_activity,case when a.opening_on is null then null else a.opening_balance+coalesce((select sum(case when r.account_id=a.id then case when r.kind in ('income','capital','adjustment') then r.amount-r.fee_amount else -r.amount end else 0 end+case when r.to_account_id=a.id then r.amount else 0 end) from rows r where r.entry_date>=a.opening_on and r.entry_date<=(now() at time zone 'Asia/Kuala_Lumpur')::date),0) end balance from public.accounting_accounts a
 ), period as(select *,case when kind in ('income','capital','adjustment') then amount-fee_amount when kind in ('expense','drawings') then -amount else 0 end movement from rows where entry_date>=date_trunc('month',p_month)::date and entry_date<(date_trunc('month',p_month)+interval '1 month')::date)
 select jsonb_build_object('asOf',now(),'accounts',(select coalesce(jsonb_agg(to_jsonb(a) order by id),'[]') from accounts a),
 'summary',jsonb_build_object('income',coalesce(sum(greatest(movement,0)),0),'expense',coalesce(sum(greatest(-movement,0)),0),'net',coalesce(sum(movement),0),'capital',coalesce(sum(amount) filter(where kind='capital'),0),'drawings',coalesce(sum(amount) filter(where kind='drawings'),0),'adjustments',coalesce(sum(amount) filter(where kind='adjustment'),0),'fees',coalesce(sum(fee_amount),0),'refunds',-coalesce(sum(amount) filter(where source<>'Manual' and amount<0),0)),
 'unmatched',(select coalesce(jsonb_agg(to_jsonb(u) order by u.entry_date,u.source_key),'[]') from (select * from rows where account_id is null order by entry_date,source_key limit 200)u),
 'unassignedCount',(select count(*) from rows where account_id is null),
 'unassignedTotal',(select coalesce(sum(amount),0) from rows where account_id is null),
 'pendingCount',(select count(*) from period where not voided and (source<>'Manual' or reversal_of is null) and (not reviewed or account_id is null or kind='expense' and receipt_count=0 and receipt_exemption='')),
 'reconciliations',(select coalesce(jsonb_agg(to_jsonb(x) order by x.statement_on desc),'[]') from (select q.*,private.accounting_balance(q.account_id,q.statement_on) system_balance,private.accounting_balance(q.account_id,q.statement_on)-q.statement_balance difference from public.accounting_reconciliations q order by created_at desc limit 30)x),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from(select * from public.accounting_audit order by id desc limit 20)a)) into result from period;
 return result;
end;$$;
revoke all on function public.accounting_feed_v2(date,timestamptz) from public,anon;
grant execute on function public.accounting_feed_v2(date,timestamptz) to authenticated;
create function public.accounting_operations() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password) then raise exception 'Akses staf diperlukan.';end if;
 with debts as (
 select v.id,'inventory'::text kind,v.buyer name,v.buyer_phone phone,v.brand||' '||v.model label,v.plate,v.status,v.price amount,v.paid,v.price-v.paid balance,v.created_at::date created_on,greatest(0,(now() at time zone 'Asia/Kuala_Lumpur')::date-(v.created_at at time zone 'Asia/Kuala_Lumpur')::date) age_days
 from public.vehicles v where v.price>v.paid and (v.paid>0 or (v.status in ('reserved','sold') and trim(v.buyer)<>''))
 union all
 select j.id,'garage',j.customer,j.phone,j.bike,j.plate,j.status,private.job_total(j.items),j.paid,private.job_total(j.items)-j.paid,j.created_at::date,greatest(0,(now() at time zone 'Asia/Kuala_Lumpur')::date-(j.created_at at time zone 'Asia/Kuala_Lumpur')::date)
 from public.jobs j where j.estimate_status='approved' and private.job_total(j.items)>j.paid
 ), costs as (
 select v.id,'inventory'::text kind,v.brand||' '||v.model||' · '||v.plate label,v.cost expected_purchase,v.prep expected_prep,null::bigint expected_service,
 coalesce((select sum(e.amount) from public.accounting_entries e where e.vehicle_id=v.id and e.cost_scope='purchase'),0) paid_purchase,
 coalesce((select sum(e.amount) from public.accounting_entries e where e.vehicle_id=v.id and e.cost_scope='prep'),0) paid_prep,0::numeric paid_service,true cost_complete,v.price sales,0::numeric labour,0::numeric parts
 from public.vehicles v where (select private.accounting_owner())
 union all
 select j.id,'garage',j.bike||' · '||j.plate,null::bigint,null::bigint,
 case when not exists(select 1 from jsonb_array_elements(j.items) l where l->>'cost' is null) then (select coalesce(sum((l->>'qty')::bigint*(l->>'cost')::bigint),0)::bigint from jsonb_array_elements(j.items) l) else null end,
 0::numeric,0::numeric,coalesce((select sum(e.amount) from public.accounting_entries e where e.job_id=j.id and e.cost_scope='service'),0),
 not exists(select 1 from jsonb_array_elements(j.items) l where l->>'cost' is null),private.job_total(j.items),
 (select coalesce(sum((l->>'qty')::bigint*(l->>'rate')::bigint) filter(where l->>'kind'='labour'),0) from jsonb_array_elements(j.items) l),
 (select coalesce(sum((l->>'qty')::bigint*(l->>'rate')::bigint) filter(where l->>'kind'='part'),0) from jsonb_array_elements(j.items) l)
 from public.jobs j where (select private.accounting_owner())
 ) select jsonb_build_object('debts',(select coalesce(jsonb_agg(to_jsonb(d) order by d.age_days desc,d.id desc),'[]') from debts d),'costs',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id desc),'[]') from costs c)) into result;
 return result;
end;$$;
revoke all on function public.accounting_operations() from public,anon;
grant execute on function public.accounting_operations() to authenticated;
create function private.guard_service_costs() returns trigger language plpgsql security invoker set search_path='' as $$
declare item jsonb;
begin
 for item in select * from jsonb_array_elements(NEW.items) loop
  if item->>'cost' is not null and (item->>'cost' !~ '^[0-9]+$' or (item->>'cost')::numeric>100000000) then raise exception 'Kos item mesti amaun sen yang sah.';end if;
 end loop;
 if TG_OP='INSERT' then
  if exists(select 1 from jsonb_array_elements(NEW.items) l where l->>'cost' is not null) and not private.accounting_owner() then raise exception 'Hanya owner boleh menetapkan kos servis.';end if;
 elsif not private.accounting_owner() and
 (select jsonb_agg(l->'cost' order by n) from jsonb_array_elements(NEW.items) with ordinality t(l,n)) is distinct from
 (select jsonb_agg(l->'cost' order by n) from jsonb_array_elements(OLD.items) with ordinality t(l,n)) and
 (exists(select 1 from jsonb_array_elements(NEW.items) l where l->>'cost' is not null) or exists(select 1 from jsonb_array_elements(OLD.items) l where l->>'cost' is not null)) then raise exception 'Hanya owner boleh mengubah kos servis.';end if;
 return NEW;
end;$$;
create trigger jobs_service_cost_guard before insert or update on public.jobs for each row execute function private.guard_service_costs();
revoke all on function private.guard_service_costs() from public,anon,authenticated;

commit;
