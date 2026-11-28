-- A motorcycle's buyer cannot be replaced once a payment exists, except by the owner.
-- Prevents one customer's deposit being carried into another customer's sale.
-- One-time reviewed upgrade; apply after vehicle-parts-hardening.sql.
begin;
create function private.guard_vehicle_buyer() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if OLD.paid>0 and (regexp_replace(lower(trim(NEW.buyer)),'\s+',' ','g') is distinct from regexp_replace(lower(trim(OLD.buyer)),'\s+',' ','g')
    or regexp_replace(NEW.buyer_phone,'[^0-9]','','g') is distinct from regexp_replace(OLD.buyer_phone,'[^0-9]','','g'))
  and not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password and role='owner') then
  raise exception 'Pembeli tidak boleh ditukar selepas bayaran diterima. Minta owner mengesahkan (refund atau pindah deposit).';
 end if;
 return NEW;
end;$$;
revoke all on function private.guard_vehicle_buyer() from public,anon,authenticated;
create trigger vehicles_buyer_guard before update on public.vehicles for each row execute function private.guard_vehicle_buyer();
commit;
