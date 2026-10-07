begin;
create function private.staff_touch() returns trigger language plpgsql security invoker set search_path='' as $$ begin NEW.version:=OLD.version+1;NEW.updated_at:=now();return NEW;end;$$;
revoke all on function private.staff_touch() from public,anon,authenticated;
create trigger staff_touch before update on public.staff for each row execute function private.staff_touch();
create function public.save_staff_access(actor_id uuid,target_id uuid,expected_version integer,details jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare old_profile public.staff; action_name text;
begin
 if not exists(select 1 from public.staff where id=actor_id and enabled and role='owner' and not must_change_password) then raise exception 'Akses owner diperlukan.';end if;
 if target_id=actor_id then raise exception 'Akaun owner dilindungi.';end if;
 if details->>'role' not in ('inventory','garage','both') then raise exception 'Peranan staf tidak sah.';end if;
 if expected_version is null then
  insert into public.staff(id,display_name,role,enabled,permissions,payment_limit,must_change_password) values(target_id,details->>'display_name',details->>'role',(details->>'enabled')::boolean,details->'permissions',(details->>'payment_limit')::bigint,true);action_name:='create';
 else
  select * into old_profile from public.staff where id=target_id for update;
  if old_profile.id is null or old_profile.role='owner' then raise exception 'Akaun owner dilindungi atau staf tidak dijumpai.';end if;
  if old_profile.version<>expected_version then raise exception 'Akses telah berubah. Muat semula sebelum menyimpan.';end if;
  update public.staff set display_name=details->>'display_name',role=details->>'role',enabled=(details->>'enabled')::boolean,permissions=details->'permissions',payment_limit=(details->>'payment_limit')::bigint where id=target_id;action_name:='update';
 end if;
 insert into public.staff_access_log(actor,target,action,changes) values(actor_id,target_id,action_name,jsonb_build_object('name',details->>'display_name','before',case when expected_version is null then null else jsonb_build_object('role',old_profile.role,'enabled',old_profile.enabled,'permissions',old_profile.permissions,'payment_limit',old_profile.payment_limit) end,'after',details));
 return target_id;
end;$$;
revoke all on function public.save_staff_access(uuid,uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.save_staff_access(uuid,uuid,integer,jsonb) to service_role;
commit;
