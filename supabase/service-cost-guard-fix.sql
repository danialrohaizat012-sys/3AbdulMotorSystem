create or replace function private.guard_service_costs() returns trigger language plpgsql security invoker set search_path='' as $$
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
