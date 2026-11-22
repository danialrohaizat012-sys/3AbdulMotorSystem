-- Business details printed on invoices, estimates and receipts.
-- One-time reviewed upgrade. Readable by enabled staff only (not anon: it may
-- hold bank account details). Only an enabled owner can change it.
begin;
create table public.invoice_profile(
 id integer primary key check(id=1),
 business_name text not null default '3 Abdul Motor' check(length(trim(business_name)) between 1 and 120),
 registration_no text not null default '' check(length(registration_no)<=60),
 address text not null default '' check(length(address)<=400),
 phone text not null default '' check(length(phone)<=40),
 email text not null default '' check(email='' or (length(email)<=120 and email~'^[^@\s]+@[^@\s]+\.[^@\s]+$')),
 bank_name text not null default '' check(length(bank_name)<=80),
 bank_account_name text not null default '' check(length(bank_account_name)<=120),
 bank_account_no text not null default '' check(bank_account_no='' or bank_account_no~'^[0-9 -]{5,34}$'),
 terms text not null default '' check(length(terms)<=1500),
 version integer not null default 1,
 updated_at timestamptz not null default now()
);
insert into public.invoice_profile(id) values(1);
alter table public.invoice_profile enable row level security;
revoke all on public.invoice_profile from anon;
grant select,update on public.invoice_profile to authenticated;
create policy invoice_profile_staff_read on public.invoice_profile for select to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and not must_change_password));
create policy invoice_profile_owner_update on public.invoice_profile for update to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and not must_change_password and role='owner'))
 with check(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and not must_change_password and role='owner'));
create function private.invoice_profile_version() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 NEW.id:=1;NEW.business_name:=trim(NEW.business_name);NEW.email:=lower(trim(NEW.email));NEW.bank_account_no:=trim(NEW.bank_account_no);
 NEW.version:=OLD.version+1;NEW.updated_at:=now();return NEW;
end;$$;
revoke all on function private.invoice_profile_version() from public,anon,authenticated;
create trigger invoice_profile_version before update on public.invoice_profile for each row execute function private.invoice_profile_version();
create trigger invoice_profile_audit after update on public.invoice_profile for each row execute function private.audit_change();
commit;
