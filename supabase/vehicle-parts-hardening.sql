-- Hardening for motorcycle parts. Apply after vehicle-parts.sql (replaces vehicle-parts-note-fix.sql).
-- 1. 'vehicle'/'vehicle_return' stock moves can only come from vehicle_use_part / vehicle_return_part,
--    so an inventory editor cannot reduce parts stock directly through the API.
-- 2. Stock-move notes keep stock numbers above 9999.
begin;
create or replace function private.guard_pos_move() returns trigger language plpgsql security invoker set search_path='' as $$
declare p public.pos_products; s public.pos_sales; line_qty integer; v public.vehicles; o public.pos_stock_moves;
begin
 if NEW.kind in ('vehicle','vehicle_return') then
  if not private.staff_can('inventory_edit') then raise exception 'Anda tidak dibenarkan mengubah stok motosikal.';end if;
  -- Only the two RPCs below set this transaction-local flag; set_config is not exposed through the API.
  if coalesce(current_setting('app.vehicle_part',true),'')<>'on' then raise exception 'Gunakan butang "Ambil dari stok" atau "Pulangkan" pada rekod motosikal.';end if;
 elsif not private.staff_can('pos_view') then raise exception 'Akses POS diperlukan.';end if;
 NEW.created_by:=auth.uid();NEW.created_at:=now();
 select display_name into NEW.actor_name from public.staff where id=auth.uid();
 select * into p from public.pos_products where id=NEW.product_id for update;
 if p.id is null then raise exception 'Produk tidak dijumpai.';end if;
 if not p.track_stock then raise exception 'Produk ini tidak menjejak stok.';end if;
 if NEW.kind in ('receive','adjust') then
  if not private.staff_can('pos_manage') then raise exception 'Terimaan dan pelarasan stok memerlukan kebenaran pengurus POS.';end if;
  if NEW.kind='receive' and NEW.qty<=0 then raise exception 'Kuantiti terimaan mesti positif.';end if;
  if NEW.kind='adjust' and length(trim(NEW.note))<5 then raise exception 'Isi sebab pelarasan sekurang-kurangnya 5 aksara.';end if;
  if NEW.kind='adjust' then NEW.unit_cost:=null;end if;
 elsif NEW.kind='vehicle' then
  select * into v from public.vehicles where id=NEW.vehicle_id;
  if v.id is null then raise exception 'Motosikal tidak dijumpai.';end if;
  if v.status='sold' then raise exception 'Motosikal ini sudah dijual.';end if;
  if NEW.qty>=0 then raise exception 'Kuantiti alat ganti tidak sah.';end if;
  NEW.unit_cost:=p.cost;NEW.reverses_move_id:=null;
 elsif NEW.kind='vehicle_return' then
  select * into o from public.pos_stock_moves where id=NEW.reverses_move_id;
  if o.id is null or o.kind<>'vehicle' or o.product_id<>NEW.product_id or o.vehicle_id<>NEW.vehicle_id or NEW.qty<>-o.qty then raise exception 'Pemulangan alat ganti tidak sah.';end if;
  if (select status from public.vehicles where id=NEW.vehicle_id)='sold' then raise exception 'Motosikal ini sudah dijual.';end if;
  NEW.unit_cost:=o.unit_cost;
 else
  select * into s from public.pos_sales where id=NEW.sale_id;
  select sum(qty) into line_qty from public.pos_sale_lines where sale_id=NEW.sale_id and product_id=NEW.product_id;
  if s.id is null or line_qty is null then raise exception 'Pergerakan stok jualan tidak sah.';end if;
  if NEW.kind='sale' and (s.status<>'completed' or s.paid<>0 or NEW.qty<>-line_qty) then raise exception 'Pergerakan stok jualan tidak sah.';end if;
  if NEW.kind='void' and (s.status<>'voided' or NEW.qty<>line_qty) then raise exception 'Pemulangan stok tidak sah.';end if;
  NEW.unit_cost:=(select unit_cost from public.pos_sale_lines where sale_id=NEW.sale_id and product_id=NEW.product_id);
 end if;
 NEW.balance_after:=p.stock_qty+NEW.qty;
 if NEW.balance_after<0 then raise exception 'Stok % tidak mencukupi (baki %).',p.name,p.stock_qty;end if;
 return NEW;
end;$$;

create or replace function public.vehicle_use_part(p_vehicle bigint,p_version integer,p_request uuid,p_product bigint,p_qty integer) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v public.vehicles; p public.pos_products; m public.pos_stock_moves;
begin
 if p_request is null then raise exception 'Rujukan diperlukan.';end if;
 if exists(select 1 from public.pos_stock_moves where request_id=p_request and vehicle_id=p_vehicle) then return private.vehicle_parts_result(p_vehicle);end if;
 if not private.staff_can('inventory_edit') then raise exception 'Anda tidak dibenarkan mengubah stok motosikal.';end if;
 if p_qty is null or p_qty not between 1 and 1000 then raise exception 'Kuantiti tidak sah.';end if;
 select * into v from public.vehicles where id=p_vehicle for update;
 if v.id is null then raise exception 'Motosikal tidak dijumpai.';end if;
 if v.version<>p_version then raise exception 'Rekod motosikal telah berubah. Tutup dan buka semula.';end if;
 select * into p from public.pos_products where id=p_product;
 if p.id is null or not p.active then raise exception 'Alat ganti tidak aktif atau tidak dijumpai.';end if;
 perform set_config('app.vehicle_part','on',true);
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,vehicle_id,note,created_by)
  values(p_request,p_product,-p_qty,'vehicle',p_vehicle,'Persediaan motosikal 3AM-'||lpad(coalesce(v.stock_no,v.id)::text,greatest(4,length(coalesce(v.stock_no,v.id)::text)),'0'),auth.uid()) returning * into m;
 perform set_config('app.vehicle_part','off',true);
 update public.vehicles set prep_items=prep_items||jsonb_build_array(jsonb_build_object('name',left('Alat ganti: '||p.name,120),'kind','part','qty',p_qty,'rate',m.unit_cost,'moveId',m.id)) where id=p_vehicle;
 return private.vehicle_parts_result(p_vehicle);
end;$$;

create or replace function public.vehicle_return_part(p_vehicle bigint,p_version integer,p_move bigint,p_request uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v public.vehicles; o public.pos_stock_moves;
begin
 if p_request is null then raise exception 'Rujukan diperlukan.';end if;
 if exists(select 1 from public.pos_stock_moves where request_id=p_request and vehicle_id=p_vehicle) then return private.vehicle_parts_result(p_vehicle);end if;
 if not private.staff_can('inventory_edit') then raise exception 'Anda tidak dibenarkan mengubah stok motosikal.';end if;
 select * into v from public.vehicles where id=p_vehicle for update;
 if v.id is null then raise exception 'Motosikal tidak dijumpai.';end if;
 if v.version<>p_version then raise exception 'Rekod motosikal telah berubah. Tutup dan buka semula.';end if;
 select * into o from public.pos_stock_moves where id=p_move and vehicle_id=p_vehicle and kind='vehicle';
 if o.id is null then raise exception 'Alat ganti ini tidak dijumpai pada motosikal.';end if;
 perform set_config('app.vehicle_part','on',true);
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,vehicle_id,reverses_move_id,note,created_by)
  values(p_request,o.product_id,-o.qty,'vehicle_return',p_vehicle,o.id,'Pulang dari motosikal 3AM-'||lpad(coalesce(v.stock_no,v.id)::text,greatest(4,length(coalesce(v.stock_no,v.id)::text)),'0'),auth.uid());
 perform set_config('app.vehicle_part','off',true);
 update public.vehicles set prep_items=(select coalesce(jsonb_agg(x order by n),'[]'::jsonb) from jsonb_array_elements(prep_items) with ordinality t(x,n) where (x->>'moveId') is distinct from o.id::text) where id=p_vehicle;
 return private.vehicle_parts_result(p_vehicle);
end;$$;
commit;
