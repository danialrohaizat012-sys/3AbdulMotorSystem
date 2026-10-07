begin;
create or replace function private.guard_vehicle() returns trigger language plpgsql security invoker set search_path='' as $$
declare net bigint; role_name text; key text; dup boolean;
begin
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
 if cardinality(NEW.photos)>5 then raise exception 'Maksimum 5 gambar setiap stok.';end if;
 if NEW.photo<>'' and not NEW.photo=any(NEW.photos) then NEW.photos:=array_prepend(NEW.photo,NEW.photos);end if;
 if cardinality(NEW.photos)>5 then raise exception 'Maksimum 5 gambar setiap stok.';end if;
 NEW.photo:=coalesce(NEW.photos[1],'');
 foreach key in array NEW.photos loop
  if key!~'^[a-z0-9-]+\.(jpg|png|webp)$' or not exists(select 1 from storage.objects where bucket_id='vehicle-photos' and name=key) then raise exception 'Foto tidak tersedia. Muat naik gambar semula.';end if;
 end loop;
 return NEW;
end;$$;

revoke all on public.payments from anon,authenticated;
grant select,insert on public.payments to authenticated;
revoke all on public.audit_log from anon,authenticated;
grant select on public.audit_log to authenticated;
revoke all on public.business_settings from anon,authenticated;
grant select on public.business_settings to anon,authenticated;
grant update on public.business_settings to authenticated;
commit;
