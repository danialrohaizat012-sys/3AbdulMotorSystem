-- Catalogue loan calculator defaults and 10 photos per motorcycle.
-- One-time reviewed upgrade for the dedicated project. Apply after vehicle-quick-sale.sql.
begin;
-- 1. Loan calculator defaults shown to customers (public, like the WhatsApp settings).
--    Flat rate in basis points per year (550 = 5.50%). NULL hides the calculator until the owner sets a rate.
alter table public.business_settings
 add column loan_rate_bp integer check(loan_rate_bp is null or loan_rate_bp between 0 and 3000),
 add column loan_down_pct integer not null default 10 check(loan_down_pct between 0 and 90),
 add column loan_max_months integer not null default 60 check(loan_max_months in (12,24,36,48,60,72,84,96,108,120));
create function private.guard_loan_settings() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if row(NEW.loan_rate_bp,NEW.loan_down_pct,NEW.loan_max_months) is distinct from row(OLD.loan_rate_bp,OLD.loan_down_pct,OLD.loan_max_months)
 and not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password and role='owner') then raise exception 'Hanya owner boleh mengubah tetapan kalkulator pinjaman.';end if;
 return NEW;
end;$$;
revoke all on function private.guard_loan_settings() from public,anon,authenticated;
create trigger settings_loan_owner before update on public.business_settings for each row execute function private.guard_loan_settings();

-- 2. Up to 10 photos per motorcycle (was 5). Same guard, only the limit changes.
create or replace function private.guard_vehicle() returns trigger language plpgsql security invoker set search_path='' as $$
declare net bigint; role_name text; key text; dup boolean;
begin
 if not private.staff_can('inventory_view') then raise exception 'Akses inventori tidak dibenarkan.';end if;
 if TG_OP='INSERT' and not private.staff_can('inventory_edit') then raise exception 'Anda hanya mempunyai akses baca inventori.';end if;
 if TG_OP='UPDATE' and not private.staff_can('inventory_edit') and (to_jsonb(NEW)-array['paid','version','updated_at']) is distinct from (to_jsonb(OLD)-array['paid','version','updated_at']) then raise exception 'Anda tidak dibenarkan mengubah stok.';end if;
 if not private.staff_can('publish_catalogue') and ((TG_OP='INSERT' and NEW.published) or (TG_OP='UPDATE' and NEW.published is distinct from OLD.published)) then raise exception 'Anda tidak dibenarkan mengubah paparan katalog.';end if;
 if not private.staff_can('manage_photos') and ((TG_OP='INSERT' and (NEW.photo<>'' or cardinality(NEW.photos)>0)) or (TG_OP='UPDATE' and (NEW.photos is distinct from OLD.photos or NEW.photo is distinct from OLD.photo))) then raise exception 'Anda tidak dibenarkan mengubah foto stok.';end if;
 select role into role_name from public.staff where id=auth.uid() and enabled;
 NEW.plate:=upper(trim(NEW.plate));NEW.chassis:=upper(trim(NEW.chassis));
 if TG_OP='UPDATE' then
  NEW.version:=OLD.version+1;
  if NEW.price<>OLD.price and role_name is distinct from 'owner' then raise exception 'Hanya owner boleh mengubah harga jualan.';end if;
  if OLD.status='sold' and NEW.status<>'sold' and role_name is distinct from 'owner' then raise exception 'Hanya owner boleh membuka semula jualan.';end if;
 end if;
 if not private.valid_job_items(NEW.prep_items) then raise exception 'Pecahan kos persediaan tidak sah.';end if;
 NEW.prep:=private.job_total(NEW.prep_items);
 select coalesce(sum(amount),0) into net from public.payments where vehicle_id=NEW.id;
 if NEW.paid<>net then raise exception 'Bayaran mesti direkod melalui transaksi bayaran.';end if;
 if NEW.paid>NEW.price then raise exception 'Harga tidak boleh lebih rendah daripada bayaran yang sudah diterima.';end if;
 if NEW.published and NEW.price<=0 then raise exception 'Masukkan harga jualan sebelum paparkan stok di katalog.';end if;
 if NEW.status='sold' then
  if NEW.price<=0 or NEW.paid<>NEW.price or trim(NEW.buyer)='' or trim(NEW.buyer_phone)='' then raise exception 'Sold memerlukan harga sah, nama dan telefon pembeli serta bayaran penuh.';end if;
  if TG_OP='INSERT' then NEW.sold_at:=now();elsif OLD.status<>'sold' then NEW.sold_at:=now();else NEW.sold_at:=OLD.sold_at;end if;
 else NEW.sold_at:=null;end if;
 if NEW.status<>'sold' and NEW.plate<>'' and (TG_OP='INSERT' or OLD.status='sold' or regexp_replace(NEW.plate,'[^A-Z0-9]','','g')<>regexp_replace(OLD.plate,'[^A-Z0-9]','','g')) then
  perform pg_advisory_xact_lock(hashtext('3am-plate'),hashtext(regexp_replace(NEW.plate,'[^A-Z0-9]','','g')));
  select exists(select 1 from public.vehicles where id<>NEW.id and status<>'sold' and regexp_replace(upper(plate),'[^A-Z0-9]','','g')=regexp_replace(NEW.plate,'[^A-Z0-9]','','g')) into dup;
  if dup and length(trim(NEW.duplicate_reason))<5 then raise exception 'Nombor plat ini sudah ada dalam stok aktif. Semak atau isi sebab rekod pendua.';end if;
 end if;
 if cardinality(NEW.photos)>10 then raise exception 'Maksimum 10 gambar setiap stok.';end if;
 if NEW.photo<>'' and not NEW.photo=any(NEW.photos) then NEW.photos:=array_prepend(NEW.photo,NEW.photos);end if;
 if cardinality(NEW.photos)>10 then raise exception 'Maksimum 10 gambar setiap stok.';end if;
 NEW.photo:=coalesce(NEW.photos[1],'');
 foreach key in array NEW.photos loop
  if key!~'^[a-z0-9-]+\.(jpg|png|webp)$' or not exists(select 1 from storage.objects where bucket_id='vehicle-photos' and name=key) then raise exception 'Foto tidak tersedia. Muat naik gambar semula.';end if;
 end loop;
 return NEW;
end;$$;
commit;
