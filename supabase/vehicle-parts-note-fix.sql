-- Fix: stock-move notes for motorcycles truncated stock numbers above 9999 (lpad width 4).
-- Apply after vehicle-parts.sql. Same functions; only the note text changes.
begin;

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
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,vehicle_id,note,created_by)
  values(p_request,p_product,-p_qty,'vehicle',p_vehicle,'Persediaan motosikal 3AM-'||lpad(coalesce(v.stock_no,v.id)::text,greatest(4,length(coalesce(v.stock_no,v.id)::text)),'0'),auth.uid()) returning * into m;
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
 insert into public.pos_stock_moves(request_id,product_id,qty,kind,vehicle_id,reverses_move_id,note,created_by)
  values(p_request,o.product_id,-o.qty,'vehicle_return',p_vehicle,o.id,'Pulang dari motosikal 3AM-'||lpad(coalesce(v.stock_no,v.id)::text,greatest(4,length(coalesce(v.stock_no,v.id)::text)),'0'),auth.uid());
 update public.vehicles set prep_items=(select coalesce(jsonb_agg(x order by n),'[]'::jsonb) from jsonb_array_elements(prep_items) with ordinality t(x,n) where (x->>'moveId') is distinct from o.id::text) where id=p_vehicle;
 return private.vehicle_parts_result(p_vehicle);
end;$$;

commit;
