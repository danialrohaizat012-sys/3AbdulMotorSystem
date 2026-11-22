-- One-step motorcycle sale: buyer, optional payment and status in a single
-- transaction. SECURITY INVOKER: every existing vehicle and payment guard
-- (owner-only price change, staff payment limit, full payment before Sold,
-- immutable ledger) still applies. Retries with the same request ID are safe.
begin;
create function public.sell_vehicle(p_vehicle bigint,p_version integer,p_request uuid,p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v public.vehicles; v_amount bigint; v_price bigint; v_buyer text; v_phone text; v_pay bigint;
begin
 if p_request is null then raise exception 'Rujukan jualan diperlukan.';end if;
 -- A retried request whose payment already exists returns the stored result.
 select id into v_pay from public.payments where request_id=p_request and vehicle_id=p_vehicle;
 if v_pay is null then
  if not private.staff_can('inventory_edit') then raise exception 'Anda tidak dibenarkan merekod jualan motosikal.';end if;
  v_amount:=coalesce((p_data->>'amount')::bigint,0);
  if v_amount<0 then raise exception 'Amaun bayaran tidak sah.';end if;
  if v_amount>0 and not private.staff_can('receive_payments') then raise exception 'Anda tidak dibenarkan menerima bayaran. Pilih "Tempah sahaja" atau minta owner merekodkan bayaran.';end if;
  v_buyer:=trim(coalesce(p_data->>'buyer',''));
  v_phone:=regexp_replace(coalesce(p_data->>'buyer_phone',''),'[^0-9]','','g');
  if left(v_phone,1)='0' then v_phone:='60'||substr(v_phone,2);end if;
  if length(v_buyer) not between 2 and 120 then raise exception 'Isi nama pembeli.';end if;
  if v_phone!~'^[1-9][0-9]{8,14}$' then raise exception 'Isi nombor telefon pembeli yang sah.';end if;
  select * into v from public.vehicles where id=p_vehicle for update;
  if v.id is null then raise exception 'Stok tidak dijumpai atau akses tidak dibenarkan.';end if;
  -- Reserve-only has no payment row; a retry of an already saved reservation is a success.
  if v_amount=0 and v.status='reserved' and v.buyer=v_buyer and v.buyer_phone=v_phone then return jsonb_build_object('status',v.status,'paid',v.paid,'price',v.price,'balance',v.price-v.paid,'payment_id',null,'version',v.version);end if;
  if v.version<>p_version then raise exception 'Stok telah berubah oleh staf lain. Tutup dan buka semula rekod.';end if;
  if v.status='sold' then raise exception 'Motosikal ini sudah dijual.';end if;
  v_price:=coalesce((p_data->>'price')::bigint,v.price);
  if v_price<=0 then raise exception 'Masukkan harga jualan.';end if;
  update public.vehicles set buyer=v_buyer,buyer_phone=v_phone,price=v_price,status='reserved' where id=p_vehicle;
  if v_amount>0 then
   insert into public.payments(request_id,vehicle_id,amount,method,purpose,paid_at,note,created_by)
    values(p_request,p_vehicle,v_amount,coalesce(p_data->>'method','cash'),case when v.paid+v_amount>=v_price then 'balance' else 'deposit' end,
     coalesce((p_data->>'paid_at')::timestamptz,now()),left(coalesce(p_data->>'note',''),1000),auth.uid()) returning id into v_pay;
  end if;
  select * into v from public.vehicles where id=p_vehicle;
  if v.paid=v.price then update public.vehicles set status='sold' where id=p_vehicle;end if;
 end if;
 select * into v from public.vehicles where id=p_vehicle;
 return jsonb_build_object('status',v.status,'paid',v.paid,'price',v.price,'balance',v.price-v.paid,'payment_id',v_pay,'version',v.version);
end;$$;
revoke all on function public.sell_vehicle(bigint,integer,uuid,jsonb) from public,anon;
grant execute on function public.sell_vehicle(bigint,integer,uuid,jsonb) to authenticated;
commit;
