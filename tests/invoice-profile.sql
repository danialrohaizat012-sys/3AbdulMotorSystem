-- Invoice profile: staff read, owner-only write, hidden from anon. Rolls back.
begin;
insert into auth.users(id) values('b0000000-0000-4000-8000-000000000001'),('b0000000-0000-4000-8000-000000000002');
insert into public.staff(id,display_name,role,permissions) values('b0000000-0000-4000-8000-000000000001','Inv owner','owner','{}'),('b0000000-0000-4000-8000-000000000002','Inv staff','garage','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$begin
 if (select business_name from public.invoice_profile where id=1)<>'3 Abdul Motor' then raise exception 'FAIL staff read';end if;
 update public.invoice_profile set address='Staff edit' where id=1;
 if (select address from public.invoice_profile where id=1)<>'' then raise exception 'FAIL staff write';end if;
end$$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
do $$begin
 update public.invoice_profile set address='Lot 1',email=' Kedai@Example.com ',bank_account_no='5123 4567' where id=1 and version=1;
 if (select row(address,email,version) from public.invoice_profile where id=1)<>row('Lot 1'::text,'kedai@example.com'::text,2) then raise exception 'FAIL owner write';end if;
 begin update public.invoice_profile set email='not-an-email' where id=1;raise exception 'FAIL bad email';exception when check_violation then null;end;
 begin update public.invoice_profile set bank_account_no='abc' where id=1;raise exception 'FAIL bad account';exception when check_violation then null;end;
 if not exists(select 1 from public.audit_log where record_kind='invoice_profile') then raise exception 'FAIL audit';end if;
end$$;
reset role;set local role anon;
do $$begin begin perform 1 from public.invoice_profile;raise exception 'FAIL anon read';exception when insufficient_privilege then null;end;end$$;
rollback;
