-- Staff Accounting permissions. Apply only after the existing Accounting v2 upgrades.
-- Deny by default: existing staff profiles have no accounting_view flag.
begin;
create or replace function private.accounting_can(action text) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.staff s where s.id=auth.uid() and s.enabled and not s.must_change_password
 and (s.role='owner' or (action in ('accounting_view','accounting_post','accounting_export')
 and s.permissions->'accounting_view'='true'::jsonb and s.permissions->action='true'::jsonb)));
$$;
revoke all on function private.accounting_can(text) from public,anon;
grant execute on function private.accounting_can(text) to authenticated;

-- Reading financial source records grants no operational write permission.
create policy accounting_vehicle_read on public.vehicles for select to authenticated using((select private.accounting_can('accounting_view')));
create policy accounting_job_read on public.jobs for select to authenticated using((select private.accounting_can('accounting_view')));
create policy accounting_payment_read on public.payments for select to authenticated using((select private.accounting_can('accounting_view')));


alter policy accounting_accounts_read on public.accounting_accounts using((select private.accounting_can('accounting_view')));

alter policy accounting_entries_read on public.accounting_entries using((select private.accounting_can('accounting_view')));

alter policy accounting_annotations_read on public.accounting_annotations using((select private.accounting_can('accounting_view')));

alter policy accounting_receipts_read on public.accounting_receipts using((select private.accounting_can('accounting_view')));

alter policy accounting_audit_read on public.accounting_audit using((select private.accounting_can('accounting_view')));

alter policy accounting_recon_read on public.accounting_reconciliations using((select private.accounting_can('accounting_view')));

alter policy accounting_entries_post on public.accounting_entries with check((select private.accounting_can('accounting_post')) and created_by=(select auth.uid()) and ((select private.accounting_owner()) or (kind in ('income','expense') and reversal_of is null and amount>0)));
alter policy accounting_receipts_insert on public.accounting_receipts with check((select private.accounting_can('accounting_post')) and created_by=(select auth.uid()));
alter policy accounting_receipt_storage_read on storage.objects using(bucket_id='accounting-receipts' and (select private.accounting_can('accounting_view')));
alter policy accounting_receipt_storage_insert on storage.objects with check(bucket_id='accounting-receipts' and (select private.accounting_can('accounting_post')) and name~('^'||(select auth.uid())::text||'/[a-f0-9-]+\.(jpg|png|webp|pdf)$'));
alter policy accounting_receipt_orphan_delete on storage.objects using(bucket_id='accounting-receipts' and (select private.accounting_can('accounting_post')) and ((select private.accounting_owner()) or name~('^'||(select auth.uid())::text||'/')) and not exists(select 1 from public.accounting_receipts where storage_path=name));


CREATE OR REPLACE FUNCTION private.accounting_rows()
 RETURNS TABLE(source_key text, source_id bigint, source text, entry_date date, kind text, amount bigint, account_id text, to_account_id text, category text, description text, counterparty text, reference text, note text, created_at timestamp with time zone, created_by uuid, vehicle_id bigint, job_id bigint, reversal_of bigint, voided boolean, reviewed boolean, version integer, receipt_count bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select 'M:'||e.id,e.id,'Manual',e.entry_date,e.kind,e.amount,e.account_id,e.to_account_id,e.category,e.description,e.counterparty,e.reference,e.note,e.created_at,e.created_by,null::bigint,null::bigint,e.reversal_of,
 exists(select 1 from public.accounting_entries r where r.reversal_of=e.id),coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='M:'||e.id)
 from public.accounting_entries e left join public.accounting_annotations a on a.source_key='M:'||e.id where (select private.accounting_can('accounting_view'))
 union all
 select 'P:'||p.id,p.id,case when p.vehicle_id is not null then 'Inventori' else 'Garaj' end,(p.paid_at at time zone 'Asia/Kuala_Lumpur')::date,'income',p.amount,
 coalesce(a.account_id,case when p.method='cash' then 'cash' end),null::text,case when p.amount<0 then 'Refund pelanggan' when p.purpose='deposit' then 'Deposit pelanggan' when p.job_id is not null then 'Bayaran servis' else 'Bayaran motosikal' end,
 case when p.vehicle_id is not null then 'Bayaran · '||v.brand||' '||v.model else 'Bayaran servis · '||j.bike end,
 coalesce(v.buyer,j.customer,''),case when p.vehicle_id is not null then '3AM-'||lpad(v.stock_no::text,greatest(4,length(v.stock_no::text)),'0') else 'JOB-'||lpad(p.job_id::text,greatest(4,length(p.job_id::text)),'0') end,p.note,p.created_at,p.created_by,p.vehicle_id,p.job_id,p.reverses_id,false,coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='P:'||p.id)
 from public.payments p left join public.vehicles v on v.id=p.vehicle_id left join public.jobs j on j.id=p.job_id left join public.accounting_annotations a on a.source_key='P:'||p.id where (select private.accounting_can('accounting_view'));
$function$;

create or replace function private.accounting_balance(p_account text,p_date date) returns bigint language sql stable security invoker set search_path='' as $$
 select case when a.opening_on is null or p_date<a.opening_on then null else a.opening_balance+coalesce((select sum(case when r.account_id=a.id then case when r.kind in ('income','capital','adjustment') then r.amount-r.fee_amount else -r.amount end else 0 end+case when r.to_account_id=a.id then r.amount else 0 end) from private.accounting_rows_v2() r where r.entry_date>=a.opening_on and r.entry_date<=least(p_date,(now() at time zone 'Asia/Kuala_Lumpur')::date)),0) end from public.accounting_accounts a where a.id=p_account and (select private.accounting_can('accounting_view'));
$$;

create or replace function public.accounting_feed(p_month date,p_before timestamptz default now()) returns table(source_key text,source_id bigint,source text,entry_date date,kind text,amount bigint,account_id text,to_account_id text,category text,description text,counterparty text,reference text,note text,created_at timestamptz,created_by uuid,vehicle_id bigint,job_id bigint,reversal_of bigint,voided boolean,reviewed boolean,version integer,receipt_count bigint) language plpgsql stable security invoker set search_path='' as $$
begin
 if not private.accounting_can('accounting_view') then raise exception 'Akses lihat Accounting diperlukan.';end if;
 return query select r.* from private.accounting_rows() r where r.entry_date>=date_trunc('month',p_month)::date and r.entry_date<(date_trunc('month',p_month)+interval '1 month')::date and r.created_at<=p_before order by r.entry_date desc,r.created_at desc,r.source_key desc;
end;$$;

create or replace function public.accounting_feed_v2(p_month date,p_before timestamptz default now()) returns table(source_key text,source_id bigint,source text,entry_date date,kind text,amount bigint,account_id text,to_account_id text,category text,description text,counterparty text,reference text,note text,created_at timestamptz,created_by uuid,vehicle_id bigint,job_id bigint,reversal_of bigint,voided boolean,reviewed boolean,version integer,receipt_count bigint,fee_amount bigint,settled_on date,received_on date,receipt_exemption text,cost_scope text,payment_method text) language plpgsql stable security invoker set search_path='' as $$
begin
 if not private.accounting_can('accounting_view') then raise exception 'Akses lihat Accounting diperlukan.';end if;
 return query select r.* from private.accounting_rows_v2() r where r.entry_date>=date_trunc('month',p_month)::date and r.entry_date<(date_trunc('month',p_month)+interval '1 month')::date and r.created_at<=p_before order by r.entry_date desc,r.created_at desc,r.source_key desc;
end;$$;

create or replace function public.accounting_snapshot(p_month date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not private.accounting_can('accounting_view') then raise exception 'Akses lihat Accounting diperlukan.';end if;
 with rows as materialized(select * from private.accounting_rows_v2()), accounts as(
 select a.*,exists(select 1 from rows r where r.account_id=a.id or r.to_account_id=a.id) has_activity,case when a.opening_on is null then null else a.opening_balance+coalesce((select sum(case when r.account_id=a.id then case when r.kind in ('income','capital','adjustment') then r.amount-r.fee_amount else -r.amount end else 0 end+case when r.to_account_id=a.id then r.amount else 0 end) from rows r where r.entry_date>=a.opening_on and r.entry_date<=(now() at time zone 'Asia/Kuala_Lumpur')::date),0) end balance from public.accounting_accounts a
 ), period as(select *,case when source<>'Manual' and account_id is null then 0 when kind in ('income','capital','adjustment') then amount-fee_amount when kind in ('expense','drawings') then -amount else 0 end movement from rows where entry_date>=date_trunc('month',p_month)::date and entry_date<(date_trunc('month',p_month)+interval '1 month')::date)
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

CREATE OR REPLACE FUNCTION public.accounting_operations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password) then raise exception 'Akses staf diperlukan.';end if;
 with debts as (
 select v.id,v.stock_no,'inventory'::text kind,v.buyer name,v.buyer_phone phone,v.brand||' '||v.model label,v.plate,v.status,v.price amount,v.paid,v.price-v.paid balance,v.created_at::date created_on,greatest(0,(now() at time zone 'Asia/Kuala_Lumpur')::date-(v.created_at at time zone 'Asia/Kuala_Lumpur')::date) age_days
 from public.vehicles v where v.price>v.paid and (v.paid>0 or (v.status in ('reserved','sold') and trim(v.buyer)<>''))
 union all
 select j.id,null::bigint,'garage',j.customer,j.phone,j.bike,j.plate,j.status,private.job_total(j.items),j.paid,private.job_total(j.items)-j.paid,j.created_at::date,greatest(0,(now() at time zone 'Asia/Kuala_Lumpur')::date-(j.created_at at time zone 'Asia/Kuala_Lumpur')::date)
 from public.jobs j where j.estimate_status='approved' and private.job_total(j.items)>j.paid
 ), costs as (
 select v.id,'inventory'::text kind,v.brand||' '||v.model||' · '||v.plate label,v.cost expected_purchase,v.prep expected_prep,null::bigint expected_service,
 coalesce((select sum(e.amount) from public.accounting_entries e where e.vehicle_id=v.id and e.cost_scope='purchase'),0) paid_purchase,
 coalesce((select sum(e.amount) from public.accounting_entries e where e.vehicle_id=v.id and e.cost_scope='prep'),0) paid_prep,0::numeric paid_service,true cost_complete,v.price sales,0::numeric labour,0::numeric parts
 from public.vehicles v where (select private.accounting_can('accounting_view'))
 union all
 select j.id,'garage',j.bike||' · '||j.plate,null::bigint,null::bigint,
 case when not exists(select 1 from jsonb_array_elements(j.items) l where l->>'cost' is null) then (select coalesce(sum((l->>'qty')::bigint*(l->>'cost')::bigint),0)::bigint from jsonb_array_elements(j.items) l) else null end,
 0::numeric,0::numeric,coalesce((select sum(e.amount) from public.accounting_entries e where e.job_id=j.id and e.cost_scope='service'),0),
 not exists(select 1 from jsonb_array_elements(j.items) l where l->>'cost' is null),private.job_total(j.items),
 (select coalesce(sum((l->>'qty')::bigint*(l->>'rate')::bigint) filter(where l->>'kind'='labour'),0) from jsonb_array_elements(j.items) l),
 (select coalesce(sum((l->>'qty')::bigint*(l->>'rate')::bigint) filter(where l->>'kind'='part'),0) from jsonb_array_elements(j.items) l)
 from public.jobs j where (select private.accounting_can('accounting_view'))
 ) select jsonb_build_object('debts',(select coalesce(jsonb_agg(to_jsonb(d) order by d.age_days desc,d.id desc),'[]') from debts d),'costs',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id desc),'[]') from costs c)) into result;
 return result;
end;$function$;

create or replace function private.accounting_source_exists(k text) returns boolean language sql stable security invoker set search_path='' as $$
 select private.accounting_can('accounting_view') and case when k~'^M:[1-9][0-9]*$' then exists(select 1 from public.accounting_entries where id=substr(k,3)::bigint) when k~'^P:[1-9][0-9]*$' then exists(select 1 from public.payments where id=substr(k,3)::bigint) else false end;
$$;

-- Row locks require UPDATE visibility. Use a narrowly scoped private definer
-- to retain account locks without granting staff account UPDATE permission.
create or replace function private.accounting_lock_account(p_id text) returns date
language plpgsql security definer set search_path='' as $$
declare start_date date;
begin
 if auth.uid() is null or not private.accounting_can('accounting_post') then raise exception 'Akses catat Accounting diperlukan.';end if;
 select opening_on into start_date from public.accounting_accounts where id=p_id for share;
 return start_date;
end;$$;
revoke all on function private.accounting_lock_account(text) from public,anon;
grant execute on function private.accounting_lock_account(text) to authenticated;

CREATE OR REPLACE FUNCTION private.guard_accounting_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare original public.accounting_entries; start_date date;
begin
 if not private.accounting_can('accounting_post') then raise exception 'Akses catat Accounting diperlukan.';end if;
 if not private.accounting_owner() and (NEW.kind not in ('income','expense') or NEW.reversal_of is not null or NEW.amount<=0) then raise exception 'Tindakan ini memerlukan owner.';end if;
 NEW.created_by:=auth.uid();NEW.created_at:=now();
 if NEW.entry_date<'2020-01-01' or NEW.entry_date>(now() at time zone 'Asia/Kuala_Lumpur')::date then raise exception 'Tarikh transaksi tidak sah.';end if;
 start_date:=private.accounting_lock_account(NEW.account_id);
 if start_date is null or NEW.entry_date<start_date then raise exception 'Tetapkan baki awal akaun atau pilih tarikh selepas baki awal.';end if;
 if NEW.to_account_id is not null then
  start_date:=private.accounting_lock_account(NEW.to_account_id);
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
 if not private.accounting_can('accounting_post') then raise exception 'Akses catat Accounting diperlukan.';end if;
 if not private.accounting_owner() and coalesce(p_data->>'kind','') not in ('income','expense') then raise exception 'Tindakan ini memerlukan owner.';end if;
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

create or replace function private.audit_accounting() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password
 and (role='owner' or (TG_TABLE_SCHEMA='public' and TG_TABLE_NAME in ('accounting_entries','accounting_receipts') and TG_OP='INSERT'
 and permissions->'accounting_view'='true'::jsonb and permissions->'accounting_post'='true'::jsonb))) then raise exception 'Akses Accounting diperlukan.';end if;
 insert into public.accounting_audit(table_name,record_key,action,before_data,after_data,actor)
 values(TG_TABLE_NAME,coalesce(to_jsonb(NEW)->>'source_key',to_jsonb(NEW)->>'id'),TG_OP,case when TG_OP='UPDATE' then to_jsonb(OLD) else null end,to_jsonb(NEW),auth.uid());return NEW;
end;$$;

commit;
