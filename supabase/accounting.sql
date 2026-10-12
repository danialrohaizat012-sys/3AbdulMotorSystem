-- Dedicated 3 Abdul Motor: owner cashbook. No operational records are rewritten.
begin;
create function private.accounting_owner() returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password and role='owner');
$$;
revoke all on function private.accounting_owner() from public,anon;
grant execute on function private.accounting_owner() to authenticated;

create table public.accounting_accounts(
 id text primary key check(id in ('cash','bank')), name text not null,
 opening_balance bigint check(abs(opening_balance)<=10000000000), opening_on date,
 configured_by uuid references auth.users(id), configured_at timestamptz,
 check((opening_balance is null)=(opening_on is null))
);
insert into public.accounting_accounts(id,name) values('cash','Tunai kedai'),('bank','Bank utama');
create table public.accounting_entries(
 id bigint generated always as identity primary key, request_id uuid not null unique,
 entry_date date not null,kind text not null check(kind in ('income','expense','capital','drawings','transfer','adjustment')),
 amount bigint not null check(amount<>0 and abs(amount)<=100000000),account_id text not null references public.accounting_accounts(id),
 to_account_id text references public.accounting_accounts(id),category text not null check(length(category) between 1 and 80),
 description text not null check(length(trim(description)) between 1 and 300),counterparty text not null default '' check(length(counterparty)<=160),
 reference text not null default '' check(length(reference)<=120),note text not null default '' check(length(note)<=1000),
 reversal_of bigint unique references public.accounting_entries(id),created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check((kind='transfer')=(to_account_id is not null)),check(to_account_id is null or to_account_id<>account_id),check(kind='adjustment' or (amount<0)=(reversal_of is not null))
);
create index accounting_entries_date on public.accounting_entries(entry_date,id);
create index accounting_entries_account on public.accounting_entries(account_id,entry_date);
create index accounting_entries_to_account on public.accounting_entries(to_account_id,entry_date) where to_account_id is not null;
create index accounting_accounts_actor on public.accounting_accounts(configured_by);
create index accounting_entries_actor on public.accounting_entries(created_by);
create table public.accounting_annotations(
 source_key text primary key check(source_key~'^[MP]:[1-9][0-9]*$'),account_id text references public.accounting_accounts(id),
 reviewed boolean not null default false,reason text not null default '' check(length(reason)<=1000),version integer not null default 1,
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create index accounting_annotations_account on public.accounting_annotations(account_id);
create index accounting_annotations_actor on public.accounting_annotations(updated_by);
create table public.accounting_receipts(
 id uuid primary key default gen_random_uuid(),source_key text not null check(source_key~'^[MP]:[1-9][0-9]*$'),
 storage_path text not null unique,original_name text not null check(length(original_name) between 1 and 180),created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create index accounting_receipts_source on public.accounting_receipts(source_key);
create index accounting_receipts_actor on public.accounting_receipts(created_by);
create table public.accounting_audit(
 id bigint generated always as identity primary key,table_name text not null,record_key text not null,action text not null,
 before_data jsonb,after_data jsonb,actor uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create index accounting_audit_actor on public.accounting_audit(actor);
create index accounting_audit_record on public.accounting_audit(record_key,id desc);

alter table public.accounting_accounts enable row level security;
alter table public.accounting_entries enable row level security;
alter table public.accounting_annotations enable row level security;
alter table public.accounting_receipts enable row level security;
alter table public.accounting_audit enable row level security;
-- Explicit grants remain separate from row authorization.
revoke all on public.accounting_accounts,public.accounting_entries,public.accounting_annotations,public.accounting_receipts,public.accounting_audit from anon,authenticated;
grant select,update on public.accounting_accounts to authenticated;
grant select,insert on public.accounting_entries,public.accounting_receipts to authenticated;
grant select,insert,update on public.accounting_annotations to authenticated;
grant select on public.accounting_audit to authenticated;
grant usage,select on sequence public.accounting_entries_id_seq to authenticated;
create policy accounting_accounts_read on public.accounting_accounts for select to authenticated using((select private.accounting_owner()));
create policy accounting_accounts_setup on public.accounting_accounts for update to authenticated using((select private.accounting_owner())) with check((select private.accounting_owner()));
create policy accounting_entries_read on public.accounting_entries for select to authenticated using((select private.accounting_owner()));
create policy accounting_entries_post on public.accounting_entries for insert to authenticated with check((select private.accounting_owner()) and created_by=(select auth.uid()));
create policy accounting_annotations_read on public.accounting_annotations for select to authenticated using((select private.accounting_owner()));
create policy accounting_annotations_insert on public.accounting_annotations for insert to authenticated with check((select private.accounting_owner()) and updated_by=(select auth.uid()));
create policy accounting_annotations_update on public.accounting_annotations for update to authenticated using((select private.accounting_owner())) with check((select private.accounting_owner()) and updated_by=(select auth.uid()));
create policy accounting_receipts_read on public.accounting_receipts for select to authenticated using((select private.accounting_owner()));
create policy accounting_receipts_insert on public.accounting_receipts for insert to authenticated with check((select private.accounting_owner()) and created_by=(select auth.uid()));
create policy accounting_audit_read on public.accounting_audit for select to authenticated using((select private.accounting_owner()));

create function private.guard_accounting_account() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 if OLD.opening_on is not null then raise exception 'Baki awal telah ditetapkan. Gunakan transaksi pelarasan dengan sebab untuk pembetulan.';end if;
 if NEW.id<>OLD.id or NEW.name<>OLD.name or NEW.opening_on is null or NEW.opening_balance is null or NEW.opening_on<'2020-01-01' or NEW.opening_on>(now() at time zone 'Asia/Kuala_Lumpur')::date then raise exception 'Tetapan baki awal tidak sah.';end if;
 NEW.configured_by:=auth.uid();NEW.configured_at:=now();return NEW;
end;$$;
create trigger accounting_account_guard before update on public.accounting_accounts for each row execute function private.guard_accounting_account();
create function private.guard_accounting_entry() returns trigger language plpgsql security invoker set search_path='' as $$
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
 return NEW;
end;$$;
create trigger accounting_entry_guard before insert on public.accounting_entries for each row execute function private.guard_accounting_entry();
create function private.accounting_source_exists(k text) returns boolean language sql stable security invoker set search_path='' as $$
 select private.accounting_owner() and case when k~'^M:[1-9][0-9]*$' then exists(select 1 from public.accounting_entries where id=substr(k,3)::bigint) when k~'^P:[1-9][0-9]*$' then exists(select 1 from public.payments where id=substr(k,3)::bigint) else false end;
$$;
create function private.guard_accounting_annotation() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not private.accounting_source_exists(NEW.source_key) then raise exception 'Transaksi tidak tersedia.';end if;
 if NEW.source_key like 'M:%' and NEW.account_id is not null then raise exception 'Akaun catatan manual tidak boleh diubah. Batalkan dan catat semula.';end if;
 if TG_OP='UPDATE' then
  if NEW.source_key<>OLD.source_key then raise exception 'Rujukan transaksi tidak boleh diubah.';end if;
  if NEW.account_id is distinct from OLD.account_id and length(trim(NEW.reason))<5 then raise exception 'Isi sebab perubahan akaun.';end if;
  NEW.version:=OLD.version+1;
 else NEW.version:=1;end if;
 NEW.updated_by:=auth.uid();NEW.updated_at:=now();return NEW;
end;$$;
create trigger accounting_annotation_guard before insert or update on public.accounting_annotations for each row execute function private.guard_accounting_annotation();
create function private.guard_accounting_receipt() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not private.accounting_source_exists(NEW.source_key) then raise exception 'Transaksi tidak tersedia.';end if;
 if NEW.storage_path !~ ('^'||auth.uid()::text||'/[a-f0-9-]+\.(jpg|png|webp|pdf)$') or not exists(select 1 from storage.objects where bucket_id='accounting-receipts' and name=NEW.storage_path) then raise exception 'Resit belum dimuat naik atau tidak sah.';end if;
 perform pg_advisory_xact_lock(hashtext('3am-receipts'),hashtext(NEW.source_key));
 if (select count(*) from public.accounting_receipts where source_key=NEW.source_key)>=5 then raise exception 'Maksimum 5 resit untuk satu transaksi.';end if;
 NEW.created_by:=auth.uid();NEW.created_at:=now();return NEW;
end;$$;
create trigger accounting_receipt_guard before insert on public.accounting_receipts for each row execute function private.guard_accounting_receipt();
-- Private SECURITY DEFINER trigger is necessary to append tamper-resistant audit rows.
-- The app has no audit INSERT/UPDATE/DELETE grants; the trigger independently authorizes its caller.
create function private.audit_accounting() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password and role='owner') then raise exception 'Akses owner diperlukan.';end if;
 insert into public.accounting_audit(table_name,record_key,action,before_data,after_data,actor)
 values(TG_TABLE_NAME,coalesce(to_jsonb(NEW)->>'source_key',to_jsonb(NEW)->>'id'),TG_OP,case when TG_OP='UPDATE' then to_jsonb(OLD) else null end,to_jsonb(NEW),auth.uid());return NEW;
end;$$;
create trigger accounting_accounts_audit after update on public.accounting_accounts for each row execute function private.audit_accounting();
create trigger accounting_entries_audit after insert on public.accounting_entries for each row execute function private.audit_accounting();
create trigger accounting_annotations_audit after insert or update on public.accounting_annotations for each row execute function private.audit_accounting();
create trigger accounting_receipts_audit after insert on public.accounting_receipts for each row execute function private.audit_accounting();
revoke all on function private.guard_accounting_account(),private.guard_accounting_entry(),private.guard_accounting_annotation(),private.guard_accounting_receipt(),private.audit_accounting() from public,anon,authenticated;
revoke all on function private.accounting_source_exists(text) from public,anon;
grant execute on function private.accounting_source_exists(text) to authenticated;

create function public.accounting_post(p_request uuid,p_data jsonb) returns bigint language plpgsql security invoker set search_path='' as $$
declare result bigint;existing public.accounting_entries;new_row public.accounting_entries;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 perform pg_advisory_xact_lock(hashtext('3am-entry'),hashtext(p_request::text));
 new_row.entry_date:=(p_data->>'date')::date;new_row.kind:=p_data->>'kind';new_row.amount:=(p_data->>'amount')::bigint;new_row.account_id:=p_data->>'account';new_row.to_account_id:=nullif(p_data->>'toAccount','');new_row.category:=p_data->>'category';new_row.description:=trim(p_data->>'description');new_row.counterparty:=coalesce(p_data->>'counterparty','');new_row.reference:=coalesce(p_data->>'reference','');new_row.note:=coalesce(p_data->>'note','');
 select * into existing from public.accounting_entries where request_id=p_request;
 if existing.id is not null then
  if row(existing.entry_date,existing.kind,existing.amount,existing.account_id,existing.to_account_id,existing.category,existing.description,existing.counterparty,existing.reference,existing.note,existing.reversal_of) is distinct from row(new_row.entry_date,new_row.kind,new_row.amount,new_row.account_id,new_row.to_account_id,new_row.category,new_row.description,new_row.counterparty,new_row.reference,new_row.note,null::bigint) then raise exception 'Rujukan simpan tidak sepadan. Muat semula sebelum cuba lagi.';end if;
  return existing.id;
 end if;
 insert into public.accounting_entries(request_id,entry_date,kind,amount,account_id,to_account_id,category,description,counterparty,reference,note,created_by)
 values(p_request,new_row.entry_date,new_row.kind,new_row.amount,new_row.account_id,new_row.to_account_id,new_row.category,new_row.description,new_row.counterparty,new_row.reference,new_row.note,auth.uid()) returning id into result;return result;
end;$$;
create function public.accounting_reverse(p_id bigint,p_request uuid,p_date date,p_reason text) returns bigint language plpgsql security invoker set search_path='' as $$
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
 insert into public.accounting_entries(request_id,entry_date,kind,amount,account_id,to_account_id,category,description,counterparty,reference,note,reversal_of,created_by)
 values(p_request,p_date,original.kind,-original.amount,original.account_id,original.to_account_id,original.category,'Pembatalan: '||left(original.description,270),original.counterparty,original.reference,p_reason,p_id,auth.uid()) returning id into result;return result;
end;$$;
create function public.accounting_annotate(p_key text,p_version integer,p_account text,p_reviewed boolean,p_reason text) returns void language plpgsql security invoker set search_path='' as $$
declare existing public.accounting_annotations;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 perform pg_advisory_xact_lock(hashtext('3am-annotation'),hashtext(p_key));
 select * into existing from public.accounting_annotations where source_key=p_key for update;
 if existing.source_key is null then
  if p_version<>0 then raise exception 'Transaksi telah berubah. Muat semula.';end if;
  insert into public.accounting_annotations(source_key,account_id,reviewed,reason,updated_by) values(p_key,nullif(p_account,''),p_reviewed,coalesce(p_reason,''),auth.uid());
 else
  if existing.version<>p_version then raise exception 'Transaksi telah berubah. Muat semula.';end if;
  update public.accounting_annotations set account_id=nullif(p_account,''),reviewed=p_reviewed,reason=coalesce(p_reason,'') where source_key=p_key;
 end if;
end;$$;

-- A live projection references each immutable payment ID exactly once. No backfill/copy/trigger is needed.
create function private.accounting_rows() returns table(source_key text,source_id bigint,source text,entry_date date,kind text,amount bigint,account_id text,to_account_id text,category text,description text,counterparty text,reference text,note text,created_at timestamptz,created_by uuid,vehicle_id bigint,job_id bigint,reversal_of bigint,voided boolean,reviewed boolean,version integer,receipt_count bigint) language sql stable security invoker set search_path='' as $$
 select 'M:'||e.id,e.id,'Manual',e.entry_date,e.kind,e.amount,e.account_id,e.to_account_id,e.category,e.description,e.counterparty,e.reference,e.note,e.created_at,e.created_by,null::bigint,null::bigint,e.reversal_of,
 exists(select 1 from public.accounting_entries r where r.reversal_of=e.id),coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='M:'||e.id)
 from public.accounting_entries e left join public.accounting_annotations a on a.source_key='M:'||e.id where (select private.accounting_owner())
 union all
 select 'P:'||p.id,p.id,case when p.vehicle_id is not null then 'Inventori' else 'Garaj' end,(p.paid_at at time zone 'Asia/Kuala_Lumpur')::date,'income',p.amount,
 coalesce(a.account_id,case when p.method='cash' then 'cash' end),null::text,case when p.amount<0 then 'Refund pelanggan' when p.purpose='deposit' then 'Deposit pelanggan' when p.job_id is not null then 'Bayaran servis' else 'Bayaran motosikal' end,
 case when p.vehicle_id is not null then 'Bayaran · '||v.brand||' '||v.model else 'Bayaran servis · '||j.bike end,
 coalesce(v.buyer,j.customer,''),case when p.vehicle_id is not null then '3AM-'||lpad(p.vehicle_id::text,4,'0') else 'JOB-'||lpad(p.job_id::text,4,'0') end,p.note,p.created_at,p.created_by,p.vehicle_id,p.job_id,p.reverses_id,false,coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='P:'||p.id)
 from public.payments p left join public.vehicles v on v.id=p.vehicle_id left join public.jobs j on j.id=p.job_id left join public.accounting_annotations a on a.source_key='P:'||p.id where (select private.accounting_owner());
$$;
revoke all on function private.accounting_rows() from public,anon;
grant execute on function private.accounting_rows() to authenticated;
create function public.accounting_feed(p_month date,p_before timestamptz default now()) returns table(source_key text,source_id bigint,source text,entry_date date,kind text,amount bigint,account_id text,to_account_id text,category text,description text,counterparty text,reference text,note text,created_at timestamptz,created_by uuid,vehicle_id bigint,job_id bigint,reversal_of bigint,voided boolean,reviewed boolean,version integer,receipt_count bigint) language plpgsql stable security invoker set search_path='' as $$
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 return query select r.* from private.accounting_rows() r where r.entry_date>=date_trunc('month',p_month)::date and r.entry_date<(date_trunc('month',p_month)+interval '1 month')::date and r.created_at<=p_before order by r.entry_date desc,r.created_at desc,r.source_key desc;
end;$$;
create function public.accounting_snapshot(p_month date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 with rows as materialized(select * from private.accounting_rows()), accounts as(
 select a.*,case when a.opening_on is null then null else a.opening_balance+coalesce((select sum(case when r.account_id=a.id then case when r.kind in ('income','capital','adjustment') then r.amount else -r.amount end else 0 end+case when r.to_account_id=a.id then r.amount else 0 end) from rows r where r.entry_date>=a.opening_on and r.entry_date<=(now() at time zone 'Asia/Kuala_Lumpur')::date),0) end balance from public.accounting_accounts a
 ), period as(select *,case when kind in ('income','capital','adjustment') then amount when kind in ('expense','drawings') then -amount else 0 end movement from rows where entry_date>=date_trunc('month',p_month)::date and entry_date<(date_trunc('month',p_month)+interval '1 month')::date)
 select jsonb_build_object('asOf',now(),'accounts',(select coalesce(jsonb_agg(to_jsonb(a) order by id),'[]') from accounts a),
 'summary',jsonb_build_object('income',coalesce(sum(greatest(movement,0)),0),'expense',coalesce(sum(greatest(-movement,0)),0),'net',coalesce(sum(movement),0),'capital',coalesce(sum(amount) filter(where kind='capital'),0),'drawings',coalesce(sum(amount) filter(where kind='drawings'),0),'adjustments',coalesce(sum(amount) filter(where kind='adjustment'),0),'refunds',-coalesce(sum(amount) filter(where source<>'Manual' and amount<0),0)),
 'unassignedCount',(select count(*) from rows where account_id is null),
 'unassignedTotal',(select coalesce(sum(amount),0) from rows where account_id is null),
 'pendingCount',(select count(*) from period where not voided and (source<>'Manual' or reversal_of is null) and (not reviewed or account_id is null or kind='expense' and receipt_count=0)),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from(select * from public.accounting_audit order by id desc limit 20)a)) into result from period;
 return result;
end;$$;
revoke all on function public.accounting_post(uuid,jsonb),public.accounting_reverse(bigint,uuid,date,text),public.accounting_annotate(text,integer,text,boolean,text),public.accounting_feed(date,timestamptz),public.accounting_snapshot(date) from public,anon;
grant execute on function public.accounting_post(uuid,jsonb),public.accounting_reverse(bigint,uuid,date,text),public.accounting_annotate(text,integer,text,boolean,text),public.accounting_feed(date,timestamptz),public.accounting_snapshot(date) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('accounting-receipts','accounting-receipts',false,2097152,array['image/jpeg','image/png','image/webp','application/pdf']);
create policy accounting_receipt_storage_read on storage.objects for select to authenticated using(bucket_id='accounting-receipts' and (select private.accounting_owner()));
create policy accounting_receipt_storage_insert on storage.objects for insert to authenticated with check(bucket_id='accounting-receipts' and (select private.accounting_owner()) and name~('^'||(select auth.uid())::text||'/[a-f0-9-]+\.(jpg|png|webp|pdf)$'));
create policy accounting_receipt_orphan_delete on storage.objects for delete to authenticated using(bucket_id='accounting-receipts' and (select private.accounting_owner()) and not exists(select 1 from public.accounting_receipts where storage_path=name));
commit;
