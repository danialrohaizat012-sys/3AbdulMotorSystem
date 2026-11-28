-- Garage repairs recorded as POS service sales (customer, plate, mechanic, parts and labour).
-- One-time reviewed upgrade. Apply after pos.sql (and the later upgrades). All functions stay SECURITY INVOKER.
begin;
alter table public.pos_sales
 add column sale_type text not null default 'counter' check(sale_type in ('counter','service')),
 add column bike text not null default '' check(length(bike)<=100),
 add column plate text not null default '' check(length(plate)<=30),
 add column mileage integer check(mileage is null or mileage between 0 and 10000000),
 add column mechanic text not null default '' check(length(mechanic)<=100),
 add column work_notes text not null default '' check(length(work_notes)<=3000);
alter table public.pos_sale_lines add column kind text not null default 'part' check(kind in ('part','labour','other'));
update public.pos_sale_lines set kind='other' where product_id is null;
update public.pos_sale_lines l set kind='labour' from public.pos_products p where p.id=l.product_id and not p.track_stock;
create index pos_sales_service_plate on public.pos_sales((regexp_replace(plate,'[^A-Z0-9]','','g')),id desc) where sale_type='service';
create index pos_sales_service_phone on public.pos_sales(customer_phone,id desc) where sale_type='service' and customer_phone<>'';

create or replace function private.guard_pos_sale() returns trigger language plpgsql security invoker set search_path='' as $$
declare ledger bigint; owner boolean; open_shift bigint;
begin
 owner:=exists(select 1 from public.staff where id=auth.uid() and enabled and role='owner' and not must_change_password);
 NEW.customer_name:=trim(NEW.customer_name);NEW.customer_phone:=regexp_replace(NEW.customer_phone,'[^0-9]','','g');
 if left(NEW.customer_phone,1)='0' then NEW.customer_phone:='60'||substr(NEW.customer_phone,2);end if;
 NEW.plate:=upper(regexp_replace(trim(NEW.plate),'\s+',' ','g'));NEW.bike:=trim(NEW.bike);NEW.mechanic:=trim(NEW.mechanic);NEW.work_notes:=trim(NEW.work_notes);
 if TG_OP='INSERT' then
  if not private.staff_can('pos_sell') then raise exception 'Anda tidak dibenarkan merekod jualan kaunter.';end if;
  select id into open_shift from public.pos_shifts where closed_at is null for share;
  if open_shift is null then raise exception 'Buka shift kaunter sebelum membuat jualan.';end if;
  if NEW.shift_id<>open_shift then raise exception 'Jualan mesti direkod dalam shift yang sedang dibuka.';end if;
  if NEW.sale_type='service' and NEW.plate='' then raise exception 'Isi nombor plat motosikal untuk servis.';end if;
  if NEW.sale_type='counter' then NEW.plate:='';NEW.bike:='';NEW.mechanic:='';NEW.mileage:=null;NEW.work_notes:='';end if;
  if NEW.discount>0 and not private.staff_can('pos_manage') then raise exception 'Diskaun memerlukan kebenaran pengurus POS.';end if;
  NEW.created_by:=auth.uid();NEW.created_at:=now();NEW.paid:=0;NEW.status:='completed';NEW.void_reason:='';NEW.voided_by:=null;NEW.voided_at:=null;NEW.version:=1;
  select display_name into NEW.cashier_name from public.staff where id=auth.uid();
  return NEW;
 end if;
 select coalesce(sum(amount),0) into ledger from public.payments where sale_id=NEW.id;
 if NEW.paid<>ledger then raise exception 'Bayaran mesti direkod melalui transaksi bayaran.';end if;
 if (to_jsonb(NEW)-'paid'-'status'-'void_reason'-'voided_by'-'voided_at'-'version')<>(to_jsonb(OLD)-'paid'-'status'-'void_reason'-'voided_by'-'voided_at'-'version') then raise exception 'Jualan yang direkod tidak boleh diubah.';end if;
 if NEW.status<>OLD.status then
  if OLD.status<>'completed' or NEW.status<>'voided' then raise exception 'Status jualan tidak sah.';end if;
  if not owner then raise exception 'Hanya owner boleh membatalkan jualan.';end if;
  if length(trim(NEW.void_reason))<5 then raise exception 'Isi sebab pembatalan sekurang-kurangnya 5 aksara.';end if;
  NEW.voided_by:=auth.uid();NEW.voided_at:=now();NEW.version:=OLD.version+1;
 elsif row(NEW.void_reason,NEW.voided_by,NEW.voided_at) is distinct from row(OLD.void_reason,OLD.voided_by,OLD.voided_at) then raise exception 'Butiran pembatalan tidak boleh diubah.';
 else NEW.version:=OLD.version;end if;
 return NEW;
end;$$;

create or replace function private.guard_pos_line() returns trigger language plpgsql security invoker set search_path='' as $$
declare s public.pos_sales; p public.pos_products;
begin
 select * into s from public.pos_sales where id=NEW.sale_id for update;
 if s.id is null or s.status<>'completed' or s.paid<>0 or s.created_by<>auth.uid() then raise exception 'Item hanya boleh ditambah semasa jualan dibuat.';end if;
 NEW.name:=trim(NEW.name);
 if NEW.product_id is null then
  -- Service jobs: any POS seller may add a labour charge; other free-form items still need a POS manager.
  if not private.staff_can('pos_manage') and not (s.sale_type='service' and NEW.kind='labour') then raise exception 'Item tanpa produk memerlukan kebenaran pengurus POS.';end if;
  if NEW.kind not in ('part','labour','other') then NEW.kind:='other';end if;
  NEW.sku:='';NEW.unit_cost:=coalesce(NEW.unit_cost,0);
 else
  select * into p from public.pos_products where id=NEW.product_id for update;
  if p.id is null or not p.active then raise exception 'Produk tidak aktif atau tidak dijumpai.';end if;
  NEW.sku:=p.sku;NEW.name:=p.name;NEW.unit_cost:=p.cost;NEW.kind:=case when p.track_stock then 'part' else 'labour' end;
  if NEW.unit_price<>p.price and not private.staff_can('pos_manage') then raise exception 'Harga % telah berubah. Muat semula produk.',p.name;end if;
 end if;
 return NEW;
end;$$;

create or replace function public.pos_checkout(p_request uuid,p_data jsonb) returns bigint language plpgsql security invoker set search_path='' as $$
declare v_sale bigint; v_shift bigint; v_subtotal bigint:=0; v_discount bigint; v_total bigint; v_tendered bigint; v_cash bigint:=0; v_paid bigint:=0; x jsonb;
begin
 if p_request is null then raise exception 'Rujukan jualan diperlukan.';end if;
 select id into v_sale from public.pos_sales where request_id=p_request and created_by=auth.uid();
 if v_sale is not null then return v_sale;end if;
 if jsonb_typeof(p_data->'lines')<>'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'Tambah sekurang-kurangnya satu item (maksimum 100).';end if;
 if jsonb_typeof(p_data->'payments')<>'array' or jsonb_array_length(p_data->'payments') not between 1 and 3 then raise exception 'Pilih kaedah bayaran.';end if;
 for x in select * from jsonb_array_elements(p_data->'lines') loop
  if (x->>'qty')::integer not between 1 and 1000 or (x->>'unit_price')::bigint not between 0 and 100000000 then raise exception 'Kuantiti atau harga item tidak sah.';end if;
  v_subtotal:=v_subtotal+(x->>'qty')::bigint*(x->>'unit_price')::bigint;
 end loop;
 v_discount:=coalesce((p_data->>'discount')::bigint,0);v_total:=v_subtotal-v_discount;
 if v_discount<0 or v_total<=0 then raise exception 'Diskaun tidak boleh melebihi jumlah.';end if;
 for x in select * from jsonb_array_elements(p_data->'payments') loop
  if x->>'method' not in ('cash','transfer','card') or (x->>'amount')::bigint<=0 then raise exception 'Bayaran tidak sah.';end if;
  v_paid:=v_paid+(x->>'amount')::bigint;if x->>'method'='cash' then v_cash:=v_cash+(x->>'amount')::bigint;end if;
 end loop;
 if v_paid<>v_total then raise exception 'Jumlah bayaran mesti sama dengan jumlah jualan.';end if;
 v_tendered:=(p_data->>'cash_tendered')::bigint;
 if v_cash>0 and v_tendered is not null and v_tendered<v_cash then raise exception 'Tunai diterima kurang daripada bayaran tunai.';end if;
 -- Staff never need a separate step: the first sale opens the drawer with RM0 float.
 v_shift:=private.pos_open_shift();
 insert into public.pos_sales(request_id,shift_id,sale_type,bike,plate,mileage,mechanic,work_notes,customer_name,customer_phone,note,subtotal,discount,total,cash_tendered,change_given,created_by)
  values(p_request,v_shift,coalesce(p_data->>'sale_type','counter'),left(coalesce(p_data->>'bike',''),100),left(coalesce(p_data->>'plate',''),30),(p_data->>'mileage')::integer,left(coalesce(p_data->>'mechanic',''),100),left(coalesce(p_data->>'work_notes',''),3000),coalesce(p_data->>'customer_name',''),coalesce(p_data->>'customer_phone',''),coalesce(p_data->>'note',''),v_subtotal,v_discount,v_total,case when v_cash>0 then coalesce(v_tendered,v_cash) end,case when v_cash>0 then coalesce(v_tendered,v_cash)-v_cash else 0 end,auth.uid())
  returning id into v_sale;
 -- Lock products in id order to avoid deadlocks between concurrent checkouts.
 perform 1 from public.pos_products where id in (select (l->>'product_id')::bigint from jsonb_array_elements(p_data->'lines') l where l ? 'product_id') order by id for update;
 for x in select * from jsonb_array_elements(p_data->'lines') loop
  insert into public.pos_sale_lines(sale_id,product_id,kind,name,qty,unit_price,unit_cost) values(v_sale,(x->>'product_id')::bigint,coalesce(x->>'kind','other'),coalesce(x->>'name',''),(x->>'qty')::integer,(x->>'unit_price')::bigint,coalesce((x->>'unit_cost')::bigint,0));
 end loop;
 for x in select * from jsonb_array_elements(p_data->'payments') loop
  insert into public.payments(request_id,sale_id,amount,method,purpose,note,created_by) values(gen_random_uuid(),v_sale,(x->>'amount')::bigint,x->>'method','pos','',auth.uid());
 end loop;
 return v_sale;
end;$$;

-- Service history by plate, phone or customer name (same rules as the old Garage search).
create function public.pos_service_history(search_text text) returns setof public.pos_sales language plpgsql stable security invoker set search_path='' as $$
declare term text; plate_term text; phone_term text;
begin
 if not private.staff_can('pos_view') then raise exception 'Akses POS diperlukan.';end if;
 term:=trim(coalesce(search_text,''));if length(term)<2 or length(term)>120 then return;end if;
 plate_term:=regexp_replace(upper(term),'[^A-Z0-9]','','g');
 phone_term:=regexp_replace(term,'[^0-9]','','g');if left(phone_term,1)='0' then phone_term:='60'||substr(phone_term,2);end if;
 return query select s.* from public.pos_sales s where s.sale_type='service' and (
  (length(plate_term)>=2 and regexp_replace(s.plate,'[^A-Z0-9]','','g')=plate_term) or (length(phone_term)>=6 and s.customer_phone=phone_term) or position(lower(term) in lower(s.customer_name))>0)
  order by s.id desc limit 50;
end;$$;
revoke all on function public.pos_service_history(text) from public,anon;
grant execute on function public.pos_service_history(text) to authenticated;

-- Accounting: service sales are labelled as service payments with the bike and plate.
CREATE OR REPLACE FUNCTION private.accounting_rows()
 RETURNS TABLE(source_key text, source_id bigint, source text, entry_date date, kind text, amount bigint, account_id text, to_account_id text, category text, description text, counterparty text, reference text, note text, created_at timestamp with time zone, created_by uuid, vehicle_id bigint, job_id bigint, reversal_of bigint, voided boolean, reviewed boolean, version integer, receipt_count bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select 'M:'||e.id,e.id,'Manual',e.entry_date,e.kind,e.amount,e.account_id,e.to_account_id,e.category,e.description,e.counterparty,e.reference,e.note,e.created_at,e.created_by,null::bigint,null::bigint,e.reversal_of,
 exists(select 1 from public.accounting_entries r where r.reversal_of=e.id),coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='M:'||e.id)
 from public.accounting_entries e left join public.accounting_annotations a on a.source_key='M:'||e.id where (select private.accounting_can('accounting_view'))
 union all
 select 'P:'||p.id,p.id,case when p.vehicle_id is not null then 'Inventori' when p.job_id is not null then 'Garaj' else 'POS' end,(p.paid_at at time zone 'Asia/Kuala_Lumpur')::date,'income',p.amount,
 coalesce(a.account_id,case when p.method='cash' then 'cash' end),null::text,case when p.amount<0 then 'Refund pelanggan' when p.purpose='deposit' then 'Deposit pelanggan' when p.job_id is not null then 'Bayaran servis' when s.sale_type='service' then 'Bayaran servis' when p.sale_id is not null then 'Jualan kaunter' else 'Bayaran motosikal' end,
 case when p.vehicle_id is not null then 'Bayaran · '||v.brand||' '||v.model when p.job_id is not null then 'Bayaran servis · '||j.bike when s.sale_type='service' then 'Servis · '||trim(s.bike||' '||s.plate) else 'Jualan kaunter POS' end,
 coalesce(v.buyer,j.customer,nullif(s.customer_name,''),case when p.sale_id is not null then 'Pelanggan kaunter' end,''),case when p.vehicle_id is not null then '3AM-'||lpad(v.stock_no::text,greatest(4,length(v.stock_no::text)),'0') when p.job_id is not null then 'JOB-'||lpad(p.job_id::text,greatest(4,length(p.job_id::text)),'0') else 'POS-'||lpad(p.sale_id::text,greatest(4,length(p.sale_id::text)),'0') end,p.note,p.created_at,p.created_by,p.vehicle_id,p.job_id,p.reverses_id,false,coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='P:'||p.id)
 from public.payments p left join public.vehicles v on v.id=p.vehicle_id left join public.jobs j on j.id=p.job_id left join public.pos_sales s on s.id=p.sale_id left join public.accounting_annotations a on a.source_key='P:'||p.id where (select private.accounting_can('accounting_view'));
$function$;
commit;
