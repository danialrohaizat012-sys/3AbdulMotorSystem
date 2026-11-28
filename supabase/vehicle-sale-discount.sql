begin;

alter table public.vehicles add column sale_discount bigint not null default 0 check(sale_discount>=0);

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
  if NEW.sale_discount<>OLD.sale_discount then
   if not private.staff_can('pos_sell') or OLD.status='sold'
    or NEW.sale_discount<OLD.sale_discount
    or (role_name<>'owner' and (NEW.price>=OLD.price or OLD.price-NEW.price<>NEW.sale_discount-OLD.sale_discount)) then
    raise exception 'Diskaun jualan tidak sah atau akses kaunter tidak dibenarkan.';
   end if;
  elsif NEW.price<>OLD.price and role_name is distinct from 'owner' then
   raise exception 'Hanya owner boleh mengubah harga jualan.';
  end if;
  if OLD.status='sold' and NEW.status<>'sold' and role_name is distinct from 'owner' then raise exception 'Hanya owner boleh membuka semula jualan.';end if;
 end if;
 if TG_OP='INSERT' and NEW.sale_discount<>0 then raise exception 'Rekod diskaun melalui jualan motosikal.';end if;
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

-- Record both payment methods atomically. Existing grants remain in force.
create or replace function public.sell_vehicle(p_vehicle bigint,p_version integer,p_request uuid,p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v public.vehicles; v_amount bigint; v_price bigint; v_buyer text; v_phone text; v_pay bigint;
 v_method text:=coalesce(p_data->>'method','cash');
 v_cash bigint;
 v_discount bigint:=coalesce((p_data->>'discount')::bigint,0);
 v_transfer_pay bigint;
 v_transfer_request uuid:=md5('3am-vehicle-transfer:'||p_request::text)::uuid;
begin
 if p_request is null then raise exception 'Rujukan jualan diperlukan.';end if;
 -- A retried request whose payment already exists returns the stored result.
 select id into v_pay from public.payments where request_id=p_request and vehicle_id=p_vehicle;
 if v_pay is null then
  if not private.staff_can('inventory_edit') then raise exception 'Anda tidak dibenarkan merekod jualan motosikal.';end if;
  if v_discount<0 or (v_discount>0 and not private.staff_can('pos_sell')) then
   raise exception 'Diskaun jualan tidak sah atau akses kaunter tidak dibenarkan.';
  end if;
  v_amount:=coalesce((p_data->>'amount')::bigint,0);
  if v_amount<0 then raise exception 'Amaun bayaran tidak sah.';end if;
  if v_amount>0 and not private.staff_can('receive_payments') then raise exception 'Anda tidak dibenarkan menerima bayaran. Pilih "Tempah sahaja" atau minta owner merekodkan bayaran.';end if;
  if v_method='split' then
   v_cash:=(p_data->>'cash_amount')::bigint;
   if v_cash is null or v_cash<=0 or v_cash>=v_amount then
    raise exception 'Amaun tunai dan transfer mesti lebih daripada RM0.';
   end if;
   if exists(select 1 from public.staff where id=auth.uid() and role<>'owner' and payment_limit<v_amount) then
    raise exception 'Jumlah bayaran melebihi had bayaran staf.';
   end if;
  end if;
  v_buyer:=trim(coalesce(p_data->>'buyer',''));
  v_phone:=regexp_replace(coalesce(p_data->>'buyer_phone',''),'[^0-9]','','g');
  if left(v_phone,1)='0' then v_phone:='60'||substr(v_phone,2);end if;
  if length(v_buyer) not between 2 and 120 then raise exception 'Isi nama pembeli.';end if;
  if v_phone!~'^[1-9][0-9]{8,14}$' then raise exception 'Isi nombor telefon pembeli yang sah.';end if;
  select * into v from public.vehicles where id=p_vehicle for update;
  if v.id is null then raise exception 'Stok tidak dijumpai atau akses tidak dibenarkan.';end if;
  -- Reserve-only has no payment row; a retry of an already saved reservation is a success.
  if v_amount=0 and v.status='reserved' and v.buyer=v_buyer and v.buyer_phone=v_phone and (v_discount=0 or (v.version=p_version+1 and v.price=(p_data->>'price')::bigint-v_discount)) then return jsonb_build_object('status',v.status,'paid',v.paid,'price',v.price,'balance',v.price-v.paid,'payment_id',null,'version',v.version);end if;
  if v.version<>p_version then raise exception 'Stok telah berubah oleh staf lain. Tutup dan buka semula rekod.';end if;
  if v.status='sold' then raise exception 'Motosikal ini sudah dijual.';end if;
  v_price:=coalesce((p_data->>'price')::bigint,v.price);
  if v_discount>0 then
   if p_data->>'price' is null then raise exception 'Harga sebelum diskaun diperlukan.';end if;
   v_price:=v_price-v_discount;
  end if;
  if v_amount>v_price-v.paid then
   raise exception 'Jumlah bayaran melebihi baki motosikal.';
  end if;
  if v_price<=0 then raise exception 'Masukkan harga jualan.';end if;
  update public.vehicles set buyer=v_buyer,buyer_phone=v_phone,price=v_price,sale_discount=v.sale_discount+v_discount,status='reserved' where id=p_vehicle;
  if v_amount>0 then
   insert into public.payments(request_id,vehicle_id,amount,method,purpose,paid_at,note,created_by)
    values(p_request,p_vehicle,coalesce(v_cash,v_amount),case when v_method='split' then 'cash' else v_method end,case when v.paid+coalesce(v_cash,v_amount)>=v_price then 'balance' else 'deposit' end,
     coalesce((p_data->>'paid_at')::timestamptz,now()),left(coalesce(p_data->>'note',''),1000),auth.uid()) returning id into v_pay;
   if v_cash is not null then
    insert into public.payments(request_id,vehicle_id,amount,method,purpose,paid_at,note,created_by)
     values(v_transfer_request,p_vehicle,v_amount-v_cash,'transfer',case when v.paid+v_amount>=v_price then 'balance' else 'deposit' end,
      coalesce((p_data->>'paid_at')::timestamptz,now()),left(coalesce(p_data->>'note',''),1000),auth.uid());
   end if;
  end if;
  select * into v from public.vehicles where id=p_vehicle;
  if v.paid=v.price then update public.vehicles set status='sold' where id=p_vehicle;end if;
 end if;
 select * into v from public.vehicles where id=p_vehicle;
 if v_pay is not null then
  select id into v_transfer_pay from public.payments where request_id=v_transfer_request and vehicle_id=p_vehicle;
 end if;
 return jsonb_build_object('status',v.status,'paid',v.paid,'price',v.price,'balance',v.price-v.paid,
  'payment_id',v_pay,'transfer_payment_id',v_transfer_pay,'version',v.version);
end;$$;

commit;
