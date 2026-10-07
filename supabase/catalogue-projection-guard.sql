begin;
create function private.guard_catalogue_projection() returns trigger language plpgsql security invoker set search_path='' as $$
declare expected jsonb;
begin
 if not private.staff_can('inventory_view') then raise exception 'Akses katalog tidak dibenarkan.';end if;
 if TG_OP='DELETE' then
  if exists(select 1 from public.vehicles where id=OLD.id and published) then raise exception 'Ubah paparan katalog melalui rekod stok.';end if;
  return OLD;
 end if;
 select jsonb_build_object('id',id,'brand',brand,'model',model,'year',year,'mileage',mileage,'price',price,'status',status,'photo',photo,'description',description,'photos',to_jsonb(photos)) into expected from public.vehicles where id=NEW.id and published;
 if expected is null or to_jsonb(NEW) is distinct from expected then raise exception 'Katalog mesti sepadan dengan stok yang dipaparkan.';end if;
 return NEW;
end;$$;
revoke all on function private.guard_catalogue_projection() from public,anon,authenticated;
create trigger catalogue_projection_guard before insert or update or delete on public.catalogue for each row execute function private.guard_catalogue_projection();
commit;
