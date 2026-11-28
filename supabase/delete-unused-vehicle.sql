begin;

create function public.delete_unused_vehicle(p_vehicle bigint,p_version integer)
returns void language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid();
 actor_name text;
 vehicle public.vehicles;
begin
 select display_name into actor_name from public.staff
 where id=actor and enabled and role='owner' and not must_change_password;
 if not found then raise exception 'Hanya owner boleh padam stok.'; end if;

 select * into vehicle from public.vehicles where id=p_vehicle for update;
 if not found then raise exception 'Stok tidak dijumpai.'; end if;
 if vehicle.version is distinct from p_version then
  raise exception 'Stok telah berubah. Buka semula rekod sebelum memadam.';
 end if;
 if vehicle.status='sold' then
  raise exception 'Rekod jualan motosikal tidak boleh dipadam. Nombor plat rekod Sold boleh digunakan semula.';
 end if;
 begin
  delete from public.vehicles where id=p_vehicle;
 exception when foreign_key_violation then
  raise exception 'Stok ini mempunyai rekod bayaran, perakaunan atau pergerakan stok. Rekod asal perlu disimpan.';
 end;
 insert into public.audit_log(record_kind,record_id,action,actor,actor_name)
 values('vehicles',p_vehicle,'DELETE',actor,actor_name);
end;
$$;

revoke all on function public.delete_unused_vehicle(bigint,integer) from public,anon;
grant execute on function public.delete_unused_vehicle(bigint,integer) to authenticated;

commit;
