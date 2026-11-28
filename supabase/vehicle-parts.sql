-- Spare parts used to prepare a motorcycle for sale. One-time reviewed upgrade, apply after pos-service.sql.
-- A part taken for a bike leaves POS stock and is added to the bike's preparation cost at the
-- product's average cost. The bike's stock-linked cost lines must always match the stock ledger,
-- so they can only be added or returned through the two functions below. All SECURITY INVOKER.
begin;
alter table public.pos_stock_moves
 add column vehicle_id bigint references public.vehicles(id) on delete restrict,
 add column reverses_move_id bigint references public.pos_stock_moves(id) on delete restrict;
alter table public.pos_stock_moves drop constraint pos_stock_moves_kind_check;
alter table public.pos_stock_moves add constraint pos_stock_moves_kind_check check(kind in ('receive','adjust','sale','void','vehicle','vehicle_return'));
alter table public.pos_stock_moves add constraint pos_stock_moves_vehicle_link check((kind in ('vehicle','vehicle_return'))=(vehicle_id is not null));
alter table public.pos_stock_moves add constraint pos_stock_moves_return_link check((kind='vehicle_return')=(reverses_move_id is not null));
create unique index pos_stock_moves_one_return on public.pos_stock_moves(reverses_move_id) where reverses_move_id is not null;
create index pos_stock_moves_vehicle on public.pos_stock_moves(vehicle_id,id) where vehicle_id is not null;

-- Inventory editors may pick parts and see the moves for motorcycles; managing products is unchanged.
alter policy pos_products_read on public.pos_products using((select private.staff_can('pos_view')) or (select private.staff_can('inventory_edit')));
alter policy pos_products_update on public.pos_products using((select private.staff_can('pos_view')) or (select private.staff_can('inventory_edit'))) with check((select private.staff_can('pos_view')) or (select private.staff_can('inventory_edit')));
alter policy pos_moves_insert on public.pos_stock_moves with check(created_by=(select auth.uid()) and ((select private.staff_can('pos_view')) or (vehicle_id is not null and (select private.staff_can('inventory_edit')))));
-- Stock is a sum over the whole ledger, so anyone who can move stock must be able to read all of it.
alter policy pos_moves_read on public.pos_stock_moves using((select private.staff_can('pos_view')) or (select private.staff_can('inventory_edit')) or (vehicle_id is not null and (select private.staff_can('inventory_view'))));

create or replace function private.guard_pos_move() returns trigger language plpgsql security invoker set search_path='' as $$
declare p public.pos_products; s public.pos_sales; line_qty integer; v public.vehicles; o public.pos_stock_moves;
begin
 if NEW.kind in ('vehicle','vehicle_return') then
  if not private.staff_can('inventory_edit') then raise exception 'Anda tidak dibenarkan mengubah stok motosikal.';end if;
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

-- A bike's stock-linked cost lines (those with "moveId") must equal its open 'vehicle' moves.
create function private.guard_vehicle_parts() returns trigger language plpgsql security invoker set search_path='' as $$
declare mismatch boolean;
begin
 if TG_OP='INSERT' then
  if exists(select 1 from jsonb_array_elements(NEW.prep_items) x where x ? 'moveId') then raise exception 'Alat ganti dari stok hanya boleh ditambah selepas motosikal disimpan.';end if;
  return NEW;
 end if;
 if NEW.prep_items is not distinct from OLD.prep_items then return NEW;end if;
 select exists(
  select 1 from (select (x->>'moveId')::bigint mid,(x->>'qty')::integer q,(x->>'rate')::bigint r from jsonb_array_elements(NEW.prep_items) x where x ? 'moveId') a
  full join (select m.id mid,-m.qty q,m.unit_cost r from public.pos_stock_moves m where m.vehicle_id=NEW.id and m.kind='vehicle' and not exists(select 1 from public.pos_stock_moves r where r.reverses_move_id=m.id)) b on a.mid=b.mid
  where a.mid is null or b.mid is null or a.q<>b.q or a.r is distinct from b.r) into mismatch;
 if not mismatch then
  select count(*)<>count(distinct x->>'moveId') into mismatch from jsonb_array_elements(NEW.prep_items) x where x ? 'moveId';
 end if;
 if mismatch then raise exception 'Alat ganti dari stok tidak boleh diubah dalam borang. Gunakan "Pulangkan ke stok" pada rekod motosikal.';end if;
 return NEW;
end;$$;
revoke all on function private.guard_vehicle_parts() from public,anon,authenticated;
create trigger vehicles_parts_guard before insert or update on public.vehicles for each row execute function private.guard_vehicle_parts();

create function private.vehicle_parts_result(p_vehicle bigint) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('version',v.version,'prep',v.prep) from public.vehicles v where v.id=p_vehicle;
$$;
revoke all on function private.vehicle_parts_result(bigint) from public,anon;
grant execute on function private.vehicle_parts_result(bigint) to authenticated;

create function public.vehicle_use_part(p_vehicle bigint,p_version integer,p_request uuid,p_product bigint,p_qty integer) returns jsonb language plpgsql security invoker set search_path='' as $$
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
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,vehicle_id,note,created_by)
  values(p_request,p_product,-p_qty,'vehicle',p_vehicle,'Persediaan motosikal 3AM-'||lpad(coalesce(v.stock_no,v.id)::text,4,'0'),auth.uid()) returning * into m;
 update public.vehicles set prep_items=prep_items||jsonb_build_array(jsonb_build_object('name',left('Alat ganti: '||p.name,120),'kind','part','qty',p_qty,'rate',m.unit_cost,'moveId',m.id)) where id=p_vehicle;
 return private.vehicle_parts_result(p_vehicle);
end;$$;

create function public.vehicle_return_part(p_vehicle bigint,p_version integer,p_move bigint,p_request uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
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
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,vehicle_id,reverses_move_id,note,created_by)
  values(p_request,o.product_id,-o.qty,'vehicle_return',p_vehicle,o.id,'Pulang dari motosikal 3AM-'||lpad(coalesce(v.stock_no,v.id)::text,4,'0'),auth.uid());
 update public.vehicles set prep_items=(select coalesce(jsonb_agg(x order by n),'[]'::jsonb) from jsonb_array_elements(prep_items) with ordinality t(x,n) where (x->>'moveId') is distinct from o.id::text) where id=p_vehicle;
 return private.vehicle_parts_result(p_vehicle);
end;$$;
revoke all on function public.vehicle_use_part(bigint,integer,uuid,bigint,integer),public.vehicle_return_part(bigint,integer,bigint,uuid) from public,anon;
grant execute on function public.vehicle_use_part(bigint,integer,uuid,bigint,integer),public.vehicle_return_part(bigint,integer,bigint,uuid) to authenticated;
commit;
