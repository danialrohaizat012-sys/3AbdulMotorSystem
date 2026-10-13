begin;
select set_config('request.jwt.claim.sub',(select id::text from public.staff where role='owner' and enabled and not must_change_password order by id limit 1),true);
set local role authenticated;
do $$declare v bigint;begin
 insert into public.vehicles(brand,model,year,price,published,freegift) values('UAT ONLY','Gift test',2026,100000,true,'UAT helmet') returning id into v;
 if (select freegift from public.catalogue where id=v)<>'UAT helmet' then raise exception 'FAIL gift projection';end if;
 begin update public.catalogue set freegift='Invented gift' where id=v;raise exception 'FAIL altered projection';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin update public.vehicles set freegift=repeat('x',501) where id=v;raise exception 'FAIL gift too long';exception when check_violation then null;end;
 update public.vehicles set freegift='' where id=v;
 if (select freegift from public.catalogue where id=v)<>'' then raise exception 'FAIL clearing gift';end if;
end;$$;
reset role;
update public.staff set role='inventory' where id=auth.uid();
set local role authenticated;
do $$begin
 begin update public.vehicles set freegift='Unauthorized gift' where brand='UAT ONLY';raise exception 'FAIL staff gift update';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 begin insert into public.vehicles(brand,model,year,price,freegift) values('UAT ONLY','Forbidden',2026,100000,'Gift');raise exception 'FAIL staff gift insert';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
end;$$;
reset role;
set local role anon;
do $$declare changed int;begin
 if not exists(select 1 from public.catalogue where brand='UAT ONLY' and freegift='') then raise exception 'FAIL public reading';end if;
 begin update public.catalogue set freegift='Forbidden' where brand='UAT ONLY';get diagnostics changed=row_count;if changed<>0 then raise exception 'FAIL anon mutation';end if;exception when insufficient_privilege then null;end;
end;$$;
reset role;
rollback;
select 'PASS: optional gifts, exact public projection, length limit, clearing and owner-only mutation; all fixtures rolled back' as result;
