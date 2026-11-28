-- =====================================================================
-- 3 Abdul Motor · Pakej SQL rollout November 2026
-- Jalankan SEKALI di Supabase → SQL Editor (projek jvmqpucsbeddusqrgsyt).
-- Mengandungi, ikut susunan: pos.sql, invoice-profile.sql, vehicle-quick-sale.sql, catalogue-loan-and-photos.sql, pos-service.sql, vehicle-parts.sql.
-- Setiap bahagian ialah transaksi sendiri. Jika ada ralat, berhenti dan
-- jangan jalankan semula keseluruhan fail: hantar mesej ralat kepada pembangun.
-- Prasyarat: staff-accounting-access.sql sudah dijalankan.
-- Selepas berjaya: deploy semula edge function manage-staff.
-- =====================================================================

-- Semakan awal: berhenti sebelum sebarang perubahan jika prasyarat tiada
-- atau pakej ini sudah pernah dijalankan.
do $$
begin
 if to_regprocedure('private.accounting_can(text)') is null then
  raise exception 'BERHENTI: jalankan supabase/staff-accounting-access.sql dahulu, kemudian jalankan fail ini.';
 end if;
 if to_regclass('public.pos_products') is not null then
  raise exception 'BERHENTI: pakej POS sudah pernah dijalankan (jadual pos_products wujud). Jangan jalankan semula.';
 end if;
end$$;


-- ---------------------------------------------------------------------
-- pos.sql
-- ---------------------------------------------------------------------
-- POS kaunter (alat ganti, aksesori, upah) for the dedicated 3 Abdul Motor project.
-- One-time reviewed upgrade. Apply AFTER staff-accounting-access.sql.
-- Every function is SECURITY INVOKER: RLS and the existing payment ledger
-- guards stay the authority. Stock and paid totals are ledger-derived.
begin;

-- 1. Permissions: POS flags are independent of the Inventory/Garage role.
create or replace function private.staff_can(action text) returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.staff s where s.id=auth.uid() and s.enabled and not s.must_change_password and
 (s.role='owner' or case
 when action='inventory_view' then s.role in ('inventory','both')
 when action='garage_view' then s.role in ('garage','both')
 when action in ('inventory_edit','publish_catalogue','manage_whatsapp','manage_photos') then s.role in ('inventory','both') and coalesce((s.permissions->>action)::boolean,false)
 when action='garage_edit' then s.role in ('garage','both') and coalesce((s.permissions->>action)::boolean,false)
 when action='receive_payments' then coalesce((s.permissions->>action)::boolean,false)
 when action in ('pos_sell','pos_manage') then coalesce((s.permissions->>action)::boolean,false)
 when action='pos_view' then coalesce((s.permissions->>'pos_sell')::boolean,false) or coalesce((s.permissions->>'pos_manage')::boolean,false)
 else false end));
$$;

-- 2. Products. stock_qty always equals the sum of the immutable stock ledger.
create table public.pos_products(
 id bigint generated always as identity primary key,
 sku text not null check(sku~'^[A-Z0-9][A-Z0-9._/-]{0,39}$'),
 barcode text not null default '' check(barcode='' or barcode~'^[0-9A-Za-z-]{4,64}$'),
 name text not null check(length(trim(name)) between 1 and 120),
 category text not null default '' check(length(category)<=60),
 unit text not null default 'unit' check(length(trim(unit)) between 1 and 20),
 price bigint not null check(price between 0 and 100000000),
 cost bigint not null default 0 check(cost between 0 and 100000000),
 stock_qty integer not null default 0,
 reorder_level integer not null default 0 check(reorder_level between 0 and 100000),
 track_stock boolean not null default true,
 active boolean not null default true,
 version integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index pos_products_sku on public.pos_products(sku);
create unique index pos_products_barcode on public.pos_products(barcode) where barcode<>'';

create table public.pos_shifts(
 id bigint generated always as identity primary key,
 opened_by uuid not null references auth.users(id), opener_name text not null default '',
 opened_at timestamptz not null default now(),
 opening_float bigint not null check(opening_float between 0 and 100000000),
 closed_at timestamptz, closed_by uuid references auth.users(id), closer_name text not null default '',
 counted_cash bigint check(counted_cash is null or counted_cash between 0 and 100000000),
 expected_cash bigint, note text not null default '' check(length(note)<=1000),
 version integer not null default 1
);
-- A single shop drawer: at most one open shift at a time.
create unique index pos_one_open_shift on public.pos_shifts((true)) where closed_at is null;

create table public.pos_sales(
 id bigint generated always as identity primary key,
 request_id uuid not null unique,
 shift_id bigint not null references public.pos_shifts(id) on delete restrict,
 customer_name text not null default '' check(length(customer_name)<=120),
 customer_phone text not null default '' check(length(customer_phone)<=20),
 note text not null default '' check(length(note)<=1000),
 subtotal bigint not null check(subtotal between 1 and 100000000),
 discount bigint not null default 0 check(discount>=0),
 total bigint not null check(total>0),
 paid bigint not null default 0,
 cash_tendered bigint check(cash_tendered is null or cash_tendered between 0 and 100000000),
 change_given bigint not null default 0 check(change_given>=0),
 status text not null default 'completed' check(status in ('completed','voided')),
 void_reason text not null default '' check(length(void_reason)<=1000),
 voided_by uuid references auth.users(id), voided_at timestamptz,
 created_by uuid not null references auth.users(id), cashier_name text not null default '',
 created_at timestamptz not null default now(), version integer not null default 1,
 check(discount<=subtotal and total=subtotal-discount)
);
create index pos_sales_created on public.pos_sales(created_at desc);
create index pos_sales_shift on public.pos_sales(shift_id);

create table public.pos_sale_lines(
 id bigint generated always as identity primary key,
 sale_id bigint not null references public.pos_sales(id) on delete restrict,
 product_id bigint references public.pos_products(id) on delete restrict,
 sku text not null default '', name text not null check(length(trim(name)) between 1 and 120),
 qty integer not null check(qty between 1 and 1000),
 unit_price bigint not null check(unit_price between 0 and 100000000),
 unit_cost bigint not null default 0 check(unit_cost between 0 and 100000000)
);
create unique index pos_sale_lines_product on public.pos_sale_lines(sale_id,product_id) where product_id is not null;
create index pos_sale_lines_sale on public.pos_sale_lines(sale_id);

create table public.pos_stock_moves(
 id bigint generated always as identity primary key,
 request_id uuid not null unique,
 product_id bigint not null references public.pos_products(id) on delete restrict,
 qty integer not null check(qty<>0 and abs(qty)<=100000),
 kind text not null check(kind in ('receive','adjust','sale','void')),
 unit_cost bigint check(unit_cost is null or unit_cost between 0 and 100000000),
 sale_id bigint references public.pos_sales(id) on delete restrict,
 note text not null default '' check(length(note)<=500),
 balance_after integer not null default 0,
 created_by uuid not null references auth.users(id), actor_name text not null default '',
 created_at timestamptz not null default now(),
 check((kind in ('sale','void'))=(sale_id is not null))
);
create index pos_stock_moves_product on public.pos_stock_moves(product_id,id desc);
create unique index pos_stock_moves_sale on public.pos_stock_moves(sale_id,product_id,kind) where sale_id is not null;

-- 3. Payments ledger gains a third owner: a POS sale.
alter table public.payments add column sale_id bigint references public.pos_sales(id) on delete restrict;
alter table public.payments drop constraint payments_check;
alter table public.payments add constraint payments_one_record check(num_nonnulls(vehicle_id,job_id,sale_id)=1);
alter table public.payments drop constraint payments_purpose_check;
alter table public.payments add constraint payments_purpose_check check(purpose in ('deposit','balance','service','refund','pos'));
create index payments_sale on public.payments(sale_id,id) where sale_id is not null;

-- 4. Guards.
create function private.guard_pos_product() returns trigger language plpgsql security invoker set search_path='' as $$
declare ledger integer; stock_only boolean;
begin
 NEW.sku:=upper(trim(NEW.sku));NEW.barcode:=trim(NEW.barcode);NEW.name:=trim(NEW.name);NEW.category:=trim(NEW.category);NEW.unit:=trim(NEW.unit);
 if TG_OP='INSERT' then
  if not private.staff_can('pos_manage') then raise exception 'Anda tidak dibenarkan mengurus produk POS.';end if;
  if NEW.stock_qty<>0 then raise exception 'Stok awal mesti direkod melalui terimaan stok.';end if;
  NEW.version:=1;NEW.created_at:=now();NEW.updated_at:=now();return NEW;
 end if;
 select coalesce(sum(qty),0) into ledger from public.pos_stock_moves where product_id=NEW.id;
 if NEW.stock_qty<>ledger then raise exception 'Stok mesti direkod melalui pergerakan stok.';end if;
 if NEW.id<>OLD.id or NEW.created_at<>OLD.created_at then raise exception 'Rekod produk tidak sah.';end if;
 stock_only:=(to_jsonb(NEW)-'stock_qty'-'version'-'updated_at')=(to_jsonb(OLD)-'stock_qty'-'version'-'updated_at');
 if stock_only then NEW.version:=OLD.version;return NEW;end if;
 if not private.staff_can('pos_manage') then raise exception 'Anda tidak dibenarkan mengurus produk POS.';end if;
 if OLD.track_stock and not NEW.track_stock and NEW.stock_qty<>0 then raise exception 'Laraskan stok kepada 0 sebelum berhenti menjejak stok.';end if;
 NEW.version:=OLD.version+1;NEW.updated_at:=now();return NEW;
end;$$;
create trigger pos_products_guard before insert or update on public.pos_products for each row execute function private.guard_pos_product();
create trigger pos_products_audit_insert after insert on public.pos_products for each row execute function private.audit_change();
-- Stock-only synchronisation from sales is recorded in the stock ledger, not the audit log.
create trigger pos_products_audit_update after update on public.pos_products for each row
 when ((to_jsonb(OLD)-'stock_qty'-'version'-'updated_at') is distinct from (to_jsonb(NEW)-'stock_qty'-'version'-'updated_at')) execute function private.audit_change();

create function private.guard_pos_shift() returns trigger language plpgsql security invoker set search_path='' as $$
declare actor text;
begin
 if not private.staff_can('pos_sell') then raise exception 'Anda tidak dibenarkan mengendalikan kaunter POS.';end if;
 select display_name into actor from public.staff where id=auth.uid();
 if TG_OP='INSERT' then
  NEW.opened_by:=auth.uid();NEW.opener_name:=coalesce(actor,'');NEW.opened_at:=now();NEW.closed_at:=null;NEW.closed_by:=null;NEW.closer_name:='';NEW.counted_cash:=null;NEW.expected_cash:=null;NEW.version:=1;
  if exists(select 1 from public.pos_shifts where closed_at is null) then raise exception 'Shift kaunter sudah dibuka.';end if;
  return NEW;
 end if;
 if OLD.closed_at is not null then raise exception 'Shift yang sudah ditutup tidak boleh diubah.';end if;
 if row(NEW.opened_by,NEW.opener_name,NEW.opened_at,NEW.opening_float) is distinct from row(OLD.opened_by,OLD.opener_name,OLD.opened_at,OLD.opening_float) then raise exception 'Butiran pembukaan shift tidak boleh diubah.';end if;
 if NEW.closed_at is null then raise exception 'Hanya penutupan shift dibenarkan.';end if;
 if NEW.counted_cash is null then raise exception 'Masukkan jumlah tunai dikira.';end if;
 NEW.closed_at:=now();NEW.closed_by:=auth.uid();NEW.closer_name:=coalesce(actor,'');
 NEW.expected_cash:=OLD.opening_float+private.pos_cash_between(OLD.opened_at,NEW.closed_at);
 if NEW.counted_cash<>NEW.expected_cash and length(trim(NEW.note))<5 then raise exception 'Tunai tidak sepadan. Isi sebab perbezaan sekurang-kurangnya 5 aksara.';end if;
 NEW.version:=OLD.version+1;return NEW;
end;$$;

create function private.pos_cash_between(p_from timestamptz,p_to timestamptz) returns bigint language sql stable security invoker set search_path='' as $$
 select coalesce(sum(p.amount),0)::bigint from public.payments p where p.sale_id is not null and p.method='cash' and p.created_at>=p_from and p.created_at<=p_to;
$$;
create trigger pos_shifts_guard before insert or update on public.pos_shifts for each row execute function private.guard_pos_shift();

-- Returns the open drawer, opening one with RM0 float if needed. Safe when two staff start at once.
create function private.pos_open_shift() returns bigint language plpgsql security invoker set search_path='' as $$
declare v bigint;
begin
 select id into v from public.pos_shifts where closed_at is null;
 if v is null then
  begin insert into public.pos_shifts(opening_float) values(0) returning id into v;
  exception when unique_violation then select id into v from public.pos_shifts where closed_at is null;end;
 end if;
 return v;
end;$$;
revoke all on function private.pos_open_shift() from public,anon;
grant execute on function private.pos_open_shift() to authenticated;

create function private.guard_pos_sale() returns trigger language plpgsql security invoker set search_path='' as $$
declare ledger bigint; owner boolean; open_shift bigint;
begin
 owner:=exists(select 1 from public.staff where id=auth.uid() and enabled and role='owner' and not must_change_password);
 NEW.customer_name:=trim(NEW.customer_name);NEW.customer_phone:=regexp_replace(NEW.customer_phone,'[^0-9]','','g');
 if left(NEW.customer_phone,1)='0' then NEW.customer_phone:='60'||substr(NEW.customer_phone,2);end if;
 if TG_OP='INSERT' then
  if not private.staff_can('pos_sell') then raise exception 'Anda tidak dibenarkan merekod jualan kaunter.';end if;
  select id into open_shift from public.pos_shifts where closed_at is null for share;
  if open_shift is null then raise exception 'Buka shift kaunter sebelum membuat jualan.';end if;
  if NEW.shift_id<>open_shift then raise exception 'Jualan mesti direkod dalam shift yang sedang dibuka.';end if;
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
create trigger pos_sales_guard before insert or update on public.pos_sales for each row execute function private.guard_pos_sale();

-- Checked at COMMIT: a sale exists only as a complete, fully paid, stock-consistent unit.
create function private.check_pos_sale() returns trigger language plpgsql security invoker set search_path='' as $$
declare s public.pos_sales; lines_total bigint; line_count integer; mismatch boolean;
begin
 select * into s from public.pos_sales where id=NEW.id;
 select coalesce(sum(qty::bigint*unit_price),0),count(*) into lines_total,line_count from public.pos_sale_lines where sale_id=s.id;
 if line_count=0 or lines_total<>s.subtotal then raise exception 'Item jualan tidak sepadan dengan jumlah.';end if;
 if s.status='completed' and s.paid<>s.total then raise exception 'Jualan kaunter mesti dibayar penuh.';end if;
 if s.status='voided' and s.paid<>0 then raise exception 'Jualan dibatalkan mesti dipulangkan sepenuhnya.';end if;
 select exists(select 1 from
  (select l.product_id,sum(l.qty) q from public.pos_sale_lines l join public.pos_products p on p.id=l.product_id where l.sale_id=s.id and p.track_stock group by l.product_id) l
  full join (select product_id,sum(qty) m from public.pos_stock_moves where sale_id=s.id group by product_id) mv on mv.product_id=l.product_id
  where s.status='completed' and coalesce(mv.m,0)<>-coalesce(l.q,0)) into mismatch;
 -- A void returns stock for every product still tracked; untracked products keep their original sale move.
 if not mismatch and s.status='voided' then
  select exists(select 1 from public.pos_stock_moves m join public.pos_products p on p.id=m.product_id where m.sale_id=s.id and p.track_stock group by m.product_id having sum(m.qty)<>0) into mismatch;
 end if;
 if mismatch then raise exception 'Pergerakan stok jualan tidak sepadan.';end if;
 return null;
end;$$;
create constraint trigger pos_sales_complete after insert or update on public.pos_sales deferrable initially deferred for each row execute function private.check_pos_sale();

create function private.guard_pos_line() returns trigger language plpgsql security invoker set search_path='' as $$
declare s public.pos_sales; p public.pos_products;
begin
 select * into s from public.pos_sales where id=NEW.sale_id for update;
 if s.id is null or s.status<>'completed' or s.paid<>0 or s.created_by<>auth.uid() then raise exception 'Item hanya boleh ditambah semasa jualan dibuat.';end if;
 NEW.name:=trim(NEW.name);
 if NEW.product_id is null then
  if not private.staff_can('pos_manage') then raise exception 'Item tanpa produk memerlukan kebenaran pengurus POS.';end if;
  NEW.sku:='';NEW.unit_cost:=coalesce(NEW.unit_cost,0);
 else
  select * into p from public.pos_products where id=NEW.product_id for update;
  if p.id is null or not p.active then raise exception 'Produk tidak aktif atau tidak dijumpai.';end if;
  NEW.sku:=p.sku;NEW.name:=p.name;NEW.unit_cost:=p.cost;
  if NEW.unit_price<>p.price and not private.staff_can('pos_manage') then raise exception 'Harga % telah berubah. Muat semula produk.',p.name;end if;
 end if;
 return NEW;
end;$$;
create trigger pos_sale_lines_guard before insert on public.pos_sale_lines for each row execute function private.guard_pos_line();

create function private.pos_line_stock() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.product_id is not null and exists(select 1 from public.pos_products where id=NEW.product_id and track_stock) then
  insert into public.pos_stock_moves(request_id,product_id,qty,kind,unit_cost,sale_id,created_by) values(gen_random_uuid(),NEW.product_id,-NEW.qty,'sale',NEW.unit_cost,NEW.sale_id,auth.uid());
 end if;
 return NEW;
end;$$;
create trigger pos_sale_lines_stock after insert on public.pos_sale_lines for each row execute function private.pos_line_stock();

create function private.guard_pos_move() returns trigger language plpgsql security invoker set search_path='' as $$
declare p public.pos_products; s public.pos_sales; line_qty integer;
begin
 if not private.staff_can('pos_view') then raise exception 'Akses POS diperlukan.';end if;
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
create trigger pos_stock_moves_guard before insert on public.pos_stock_moves for each row execute function private.guard_pos_move();

create function private.sync_pos_stock() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 update public.pos_products set stock_qty=(select coalesce(sum(qty),0) from public.pos_stock_moves where product_id=NEW.product_id),
  cost=case when NEW.kind='receive' and NEW.unit_cost is not null and private.staff_can('pos_manage') then NEW.unit_cost else cost end
  where id=NEW.product_id;
 return NEW;
end;$$;
create trigger pos_stock_moves_sync after insert on public.pos_stock_moves for each row execute function private.sync_pos_stock();

-- 5. Payment guard/sync extended with the POS branch; vehicle and job rules unchanged.
create or replace function private.guard_payment() returns trigger language plpgsql security invoker set search_path='' as $$
declare limit_amount bigint; net bigint; original public.payments; role_name text;
begin
 select role,display_name into role_name,NEW.receiver_name from public.staff where id=auth.uid() and enabled;
 if NEW.sale_id is not null then
  if not private.staff_can('pos_sell') then raise exception 'Anda tidak dibenarkan merekod jualan kaunter.';end if;
 elsif not private.staff_can('receive_payments') then raise exception 'Anda tidak dibenarkan menerima bayaran.';end if;
 -- The per-transaction staff limit governs Inventory/Garage receipts; counter sales are governed by pos_sell.
 if NEW.amount>0 and NEW.sale_id is null and exists(select 1 from public.staff where id=auth.uid() and role<>'owner' and payment_limit is not null and NEW.amount>payment_limit) then raise exception 'Amaun melebihi had bayaran staf. Minta owner merekodkan transaksi ini.';end if;
 if role_name is null then raise exception 'Akses staf diperlukan.';end if;
 NEW.created_by:=auth.uid();NEW.created_at:=now();
 if NEW.vehicle_id is not null then
  select price into limit_amount from public.vehicles where id=NEW.vehicle_id for update;
  select coalesce(sum(amount),0) into net from public.payments where vehicle_id=NEW.vehicle_id;
 elsif NEW.job_id is not null then
  select private.job_total(items) into limit_amount from public.jobs where id=NEW.job_id for update;
  select coalesce(sum(amount),0) into net from public.payments where job_id=NEW.job_id;
 else
  select total into limit_amount from public.pos_sales where id=NEW.sale_id and status='completed' for update;
  select coalesce(sum(amount),0) into net from public.payments where sale_id=NEW.sale_id;
 end if;
 if limit_amount is null then raise exception 'Rekod tidak dijumpai atau akses tidak dibenarkan.';end if;
 -- A retried request reaches the unique constraint without re-applying balance guards.
 if exists(select 1 from public.payments where request_id=NEW.request_id) then return NEW;end if;
 if NEW.amount>0 and ((NEW.vehicle_id is not null and NEW.purpose not in ('deposit','balance')) or (NEW.job_id is not null and NEW.purpose<>'service') or (NEW.sale_id is not null and NEW.purpose<>'pos')) then raise exception 'Tujuan bayaran tidak sepadan dengan rekod.';end if;
 if NEW.paid_at>now() or NEW.paid_at<'2020-01-01'::timestamptz then raise exception 'Tarikh bayaran tidak sah.';end if;
 if NEW.amount<0 then
  if role_name<>'owner' or length(trim(NEW.note))<5 or NEW.reverses_id is null then raise exception 'Refund memerlukan owner, transaksi asal dan sebab.';end if;
  select * into original from public.payments where id=NEW.reverses_id;
  if original.id is null or original.amount<=0 or original.vehicle_id is distinct from NEW.vehicle_id or original.job_id is distinct from NEW.job_id or original.sale_id is distinct from NEW.sale_id then raise exception 'Transaksi asal refund tidak sah.';end if;
  if abs(NEW.amount)>original.amount+coalesce((select sum(amount) from public.payments where reverses_id=original.id),0) then raise exception 'Refund melebihi bayaran asal yang masih tersedia.';end if;
 elsif NEW.reverses_id is not null then raise exception 'Transaksi positif tidak boleh mempunyai rujukan refund.';end if;
 if net+NEW.amount<0 or net+NEW.amount>limit_amount then raise exception 'Jumlah bayaran melebihi baki atau refund melebihi bayaran diterima.';end if;
 return NEW;
end;$$;

create or replace function private.sync_payment() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.vehicle_id is not null then update public.vehicles set paid=(select coalesce(sum(amount),0) from public.payments where vehicle_id=NEW.vehicle_id) where id=NEW.vehicle_id;
 elsif NEW.job_id is not null then update public.jobs set paid=(select coalesce(sum(amount),0) from public.payments where job_id=NEW.job_id) where id=NEW.job_id;
 else update public.pos_sales set paid=(select coalesce(sum(amount),0) from public.payments where sale_id=NEW.sale_id) where id=NEW.sale_id;end if;
 return NEW;
end;$$;

-- 6. RLS.
alter table public.pos_products enable row level security;
alter table public.pos_shifts enable row level security;
alter table public.pos_sales enable row level security;
alter table public.pos_sale_lines enable row level security;
alter table public.pos_stock_moves enable row level security;
grant select,insert,update on public.pos_products,public.pos_shifts,public.pos_sales to authenticated;
grant select,insert on public.pos_sale_lines,public.pos_stock_moves to authenticated;
revoke all on public.pos_products,public.pos_shifts,public.pos_sales,public.pos_sale_lines,public.pos_stock_moves from anon;
create policy pos_products_read on public.pos_products for select to authenticated using((select private.staff_can('pos_view')));
create policy pos_products_insert on public.pos_products for insert to authenticated with check((select private.staff_can('pos_manage')));
create policy pos_products_update on public.pos_products for update to authenticated using((select private.staff_can('pos_view'))) with check((select private.staff_can('pos_view')));
create policy pos_shifts_read on public.pos_shifts for select to authenticated using((select private.staff_can('pos_view')));
create policy pos_shifts_write on public.pos_shifts for insert to authenticated with check((select private.staff_can('pos_sell')));
create policy pos_shifts_close on public.pos_shifts for update to authenticated using((select private.staff_can('pos_sell'))) with check((select private.staff_can('pos_sell')));
create policy pos_sales_read on public.pos_sales for select to authenticated using((select private.staff_can('pos_view')) or (select private.accounting_can('accounting_view')));
create policy pos_sales_insert on public.pos_sales for insert to authenticated with check((select private.staff_can('pos_sell')) and created_by=(select auth.uid()));
create policy pos_sales_update on public.pos_sales for update to authenticated using((select private.staff_can('pos_sell'))) with check((select private.staff_can('pos_sell')));
create policy pos_lines_read on public.pos_sale_lines for select to authenticated using((select private.staff_can('pos_view')) or (select private.accounting_can('accounting_view')));
create policy pos_lines_insert on public.pos_sale_lines for insert to authenticated with check((select private.staff_can('pos_sell')));
create policy pos_moves_read on public.pos_stock_moves for select to authenticated using((select private.staff_can('pos_view')));
create policy pos_moves_insert on public.pos_stock_moves for insert to authenticated with check((select private.staff_can('pos_view')) and created_by=(select auth.uid()));
create policy pos_payment_read on public.payments for select to authenticated using(sale_id is not null and (select private.staff_can('pos_view')));
alter policy payments_insert on public.payments with check(created_by=(select auth.uid()) and (amount>0 or exists(select 1 from public.staff where id=(select auth.uid()) and enabled and role='owner')) and (
 (sale_id is null and (select private.staff_can('receive_payments')) and ((vehicle_id is not null and (select private.staff_can('inventory_view'))) or (job_id is not null and (select private.staff_can('garage_view')))))
 or (sale_id is not null and (select private.staff_can('pos_sell')))));
grant usage,select on sequence public.pos_products_id_seq,public.pos_shifts_id_seq,public.pos_sales_id_seq,public.pos_sale_lines_id_seq,public.pos_stock_moves_id_seq to authenticated;

-- 7. Checkout and void: one transaction each, retry-safe via request IDs.
-- p_data: {customer_name,customer_phone,note,discount,cash_tendered,
--  lines:[{product_id,qty,unit_price}|{name,qty,unit_price}],payments:[{method,amount}]}
create function public.pos_checkout(p_request uuid,p_data jsonb) returns bigint language plpgsql security invoker set search_path='' as $$
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
 insert into public.pos_sales(request_id,shift_id,customer_name,customer_phone,note,subtotal,discount,total,cash_tendered,change_given,created_by)
  values(p_request,v_shift,coalesce(p_data->>'customer_name',''),coalesce(p_data->>'customer_phone',''),coalesce(p_data->>'note',''),v_subtotal,v_discount,v_total,case when v_cash>0 then coalesce(v_tendered,v_cash) end,case when v_cash>0 then coalesce(v_tendered,v_cash)-v_cash else 0 end,auth.uid())
  returning id into v_sale;
 -- Lock products in id order to avoid deadlocks between concurrent checkouts.
 perform 1 from public.pos_products where id in (select (l->>'product_id')::bigint from jsonb_array_elements(p_data->'lines') l where l ? 'product_id') order by id for update;
 for x in select * from jsonb_array_elements(p_data->'lines') loop
  insert into public.pos_sale_lines(sale_id,product_id,name,qty,unit_price,unit_cost) values(v_sale,(x->>'product_id')::bigint,coalesce(x->>'name',''),(x->>'qty')::integer,(x->>'unit_price')::bigint,coalesce((x->>'unit_cost')::bigint,0));
 end loop;
 for x in select * from jsonb_array_elements(p_data->'payments') loop
  insert into public.payments(request_id,sale_id,amount,method,purpose,note,created_by) values(gen_random_uuid(),v_sale,(x->>'amount')::bigint,x->>'method','pos','',auth.uid());
 end loop;
 return v_sale;
end;$$;

create function public.pos_void_sale(p_sale bigint,p_reason text) returns void language plpgsql security invoker set search_path='' as $$
declare s public.pos_sales; p record; l record;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and role='owner' and not must_change_password) then raise exception 'Hanya owner boleh membatalkan jualan.';end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Isi sebab pembatalan sekurang-kurangnya 5 aksara.';end if;
 select * into s from public.pos_sales where id=p_sale for update;
 if s.id is null then raise exception 'Jualan tidak dijumpai.';end if;
 if s.status='voided' then return;end if;
 -- Cash refunds leave the drawer that is open now, so it must exist to be counted at close.
 if exists(select 1 from public.payments where sale_id=p_sale and method='cash' and amount>0) then perform private.pos_open_shift();end if;
 for p in select o.id,o.amount+coalesce((select sum(r.amount) from public.payments r where r.reverses_id=o.id),0) remaining,o.method from public.payments o where o.sale_id=p_sale and o.amount>0 order by o.id loop
  if p.remaining>0 then insert into public.payments(request_id,sale_id,amount,method,purpose,note,reverses_id,created_by) values(gen_random_uuid(),p_sale,-p.remaining,p.method,'refund','Batal jualan: '||trim(p_reason),p.id,auth.uid());end if;
 end loop;
 update public.pos_sales set status='voided',void_reason=trim(p_reason) where id=p_sale;
 for l in select product_id,qty from public.pos_sale_lines where sale_id=p_sale and product_id is not null and exists(select 1 from public.pos_stock_moves m where m.sale_id=p_sale and m.product_id=pos_sale_lines.product_id and m.kind='sale')
  and exists(select 1 from public.pos_products pp where pp.id=pos_sale_lines.product_id and pp.track_stock) loop
  insert into public.pos_stock_moves(request_id,product_id,qty,kind,sale_id,note,created_by) values(gen_random_uuid(),l.product_id,l.qty,'void',p_sale,'Batal jualan',auth.uid());
 end loop;
end;$$;

create function public.pos_shift_report(p_shift bigint) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare sh public.pos_shifts; until_at timestamptz; result jsonb;
begin
 if not private.staff_can('pos_view') then raise exception 'Akses POS diperlukan.';end if;
 select * into sh from public.pos_shifts where id=p_shift;
 if sh.id is null then raise exception 'Shift tidak dijumpai.';end if;
 until_at:=coalesce(sh.closed_at,now());
 select jsonb_build_object(
  'shift',to_jsonb(sh),
  'salesCount',(select count(*) from public.pos_sales where shift_id=sh.id and status='completed'),
  'voidCount',(select count(*) from public.pos_sales where shift_id=sh.id and status='voided'),
  'gross',(select coalesce(sum(subtotal),0) from public.pos_sales where shift_id=sh.id and status='completed'),
  'discount',(select coalesce(sum(discount),0) from public.pos_sales where shift_id=sh.id and status='completed'),
  'net',(select coalesce(sum(total),0) from public.pos_sales where shift_id=sh.id and status='completed'),
  'cost',(select coalesce(sum(l.qty::bigint*l.unit_cost),0) from public.pos_sale_lines l join public.pos_sales s on s.id=l.sale_id where s.shift_id=sh.id and s.status='completed'),
  'methods',(select coalesce(jsonb_object_agg(method,amount),'{}'::jsonb) from (select p.method,sum(p.amount) amount from public.payments p where p.sale_id is not null and p.created_at>=sh.opened_at and p.created_at<=until_at group by p.method) m),
  'expectedCash',coalesce(sh.expected_cash,sh.opening_float+private.pos_cash_between(sh.opened_at,until_at)),
  'topItems',(select coalesce(jsonb_agg(t order by t.qty desc),'[]'::jsonb) from (select l.name,sum(l.qty) qty,sum(l.qty::bigint*l.unit_price) amount from public.pos_sale_lines l join public.pos_sales s on s.id=l.sale_id where s.shift_id=sh.id and s.status='completed' group by l.name order by sum(l.qty) desc limit 5) t)
 ) into result;
 return result;
end;$$;

revoke all on function public.pos_checkout(uuid,jsonb),public.pos_void_sale(bigint,text),public.pos_shift_report(bigint) from public,anon;
grant execute on function public.pos_checkout(uuid,jsonb),public.pos_void_sale(bigint,text),public.pos_shift_report(bigint) to authenticated;
revoke all on function private.guard_pos_product(),private.guard_pos_shift(),private.guard_pos_sale(),private.check_pos_sale(),private.guard_pos_line(),private.pos_line_stock(),private.guard_pos_move(),private.sync_pos_stock() from public,anon,authenticated;
revoke all on function private.pos_cash_between(timestamptz,timestamptz) from public,anon;
grant execute on function private.pos_cash_between(timestamptz,timestamptz) to authenticated;

-- 8. Accounting projection: POS payments appear once, as source 'POS'.
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
 coalesce(a.account_id,case when p.method='cash' then 'cash' end),null::text,case when p.amount<0 then 'Refund pelanggan' when p.purpose='deposit' then 'Deposit pelanggan' when p.job_id is not null then 'Bayaran servis' when p.sale_id is not null then 'Jualan kaunter' else 'Bayaran motosikal' end,
 case when p.vehicle_id is not null then 'Bayaran · '||v.brand||' '||v.model when p.job_id is not null then 'Bayaran servis · '||j.bike else 'Jualan kaunter POS' end,
 coalesce(v.buyer,j.customer,nullif(s.customer_name,''),case when p.sale_id is not null then 'Pelanggan kaunter' end,''),case when p.vehicle_id is not null then '3AM-'||lpad(v.stock_no::text,greatest(4,length(v.stock_no::text)),'0') when p.job_id is not null then 'JOB-'||lpad(p.job_id::text,greatest(4,length(p.job_id::text)),'0') else 'POS-'||lpad(p.sale_id::text,greatest(4,length(p.sale_id::text)),'0') end,p.note,p.created_at,p.created_by,p.vehicle_id,p.job_id,p.reverses_id,false,coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='P:'||p.id)
 from public.payments p left join public.vehicles v on v.id=p.vehicle_id left join public.jobs j on j.id=p.job_id left join public.pos_sales s on s.id=p.sale_id left join public.accounting_annotations a on a.source_key='P:'||p.id where (select private.accounting_can('accounting_view'));
$function$;
commit;

-- ---------------------------------------------------------------------
-- invoice-profile.sql
-- ---------------------------------------------------------------------
-- Business details printed on invoices, estimates and receipts.
-- One-time reviewed upgrade. Readable by enabled staff only (not anon: it may
-- hold bank account details). Only an enabled owner can change it.
begin;
create table public.invoice_profile(
 id integer primary key check(id=1),
 business_name text not null default '3 Abdul Motor' check(length(trim(business_name)) between 1 and 120),
 registration_no text not null default '' check(length(registration_no)<=60),
 address text not null default '' check(length(address)<=400),
 phone text not null default '' check(length(phone)<=40),
 email text not null default '' check(email='' or (length(email)<=120 and email~'^[^@\s]+@[^@\s]+\.[^@\s]+$')),
 bank_name text not null default '' check(length(bank_name)<=80),
 bank_account_name text not null default '' check(length(bank_account_name)<=120),
 bank_account_no text not null default '' check(bank_account_no='' or bank_account_no~'^[0-9 -]{5,34}$'),
 terms text not null default '' check(length(terms)<=1500),
 version integer not null default 1,
 updated_at timestamptz not null default now()
);
insert into public.invoice_profile(id) values(1);
alter table public.invoice_profile enable row level security;
revoke all on public.invoice_profile from anon;
grant select,update on public.invoice_profile to authenticated;
create policy invoice_profile_staff_read on public.invoice_profile for select to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and not must_change_password));
create policy invoice_profile_owner_update on public.invoice_profile for update to authenticated
 using(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and not must_change_password and role='owner'))
 with check(exists(select 1 from public.staff where id=(select auth.uid()) and enabled and not must_change_password and role='owner'));
create function private.invoice_profile_version() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 NEW.id:=1;NEW.business_name:=trim(NEW.business_name);NEW.email:=lower(trim(NEW.email));NEW.bank_account_no:=trim(NEW.bank_account_no);
 NEW.version:=OLD.version+1;NEW.updated_at:=now();return NEW;
end;$$;
revoke all on function private.invoice_profile_version() from public,anon,authenticated;
create trigger invoice_profile_version before update on public.invoice_profile for each row execute function private.invoice_profile_version();
create trigger invoice_profile_audit after update on public.invoice_profile for each row execute function private.audit_change();
commit;

-- ---------------------------------------------------------------------
-- vehicle-quick-sale.sql
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- catalogue-loan-and-photos.sql
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- pos-service.sql
-- ---------------------------------------------------------------------
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
-- Owner-set cap for a free-text labour line entered by a seller without 'POS: urus'. Default RM300 per line.
alter table public.business_settings add column pos_labour_max bigint not null default 30000 check(pos_labour_max between 0 and 100000000);
create function private.guard_pos_labour_setting() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if NEW.pos_labour_max is distinct from OLD.pos_labour_max and not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password and role='owner') then raise exception 'Hanya owner boleh mengubah had upah kerja.';end if;
 return NEW;
end;$$;
revoke all on function private.guard_pos_labour_setting() from public,anon,authenticated;
create trigger settings_pos_labour_owner before update on public.business_settings for each row execute function private.guard_pos_labour_setting();
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
  -- A free-text labour line cannot be used to sell parts cheaply: sellers are capped per line.
  if not private.staff_can('pos_manage') and NEW.qty::bigint*NEW.unit_price>(select pos_labour_max from public.business_settings where id=1) then raise exception 'Upah kerja melebihi had % seunit baris. Minta pengurus POS merekodkannya.','RM'||to_char((select pos_labour_max from public.business_settings where id=1)/100.0,'FM999990.00');end if;
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

-- Close report shows parts vs labour, and labour per mechanic (e.g. for commission).
create or replace function public.pos_shift_report(p_shift bigint) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare sh public.pos_shifts; until_at timestamptz; result jsonb;
begin
 if not private.staff_can('pos_view') then raise exception 'Akses POS diperlukan.';end if;
 select * into sh from public.pos_shifts where id=p_shift;
 if sh.id is null then raise exception 'Shift tidak dijumpai.';end if;
 until_at:=coalesce(sh.closed_at,now());
 select jsonb_build_object(
  'shift',to_jsonb(sh),
  'salesCount',(select count(*) from public.pos_sales where shift_id=sh.id and status='completed'),
  'voidCount',(select count(*) from public.pos_sales where shift_id=sh.id and status='voided'),
  'gross',(select coalesce(sum(subtotal),0) from public.pos_sales where shift_id=sh.id and status='completed'),
  'discount',(select coalesce(sum(discount),0) from public.pos_sales where shift_id=sh.id and status='completed'),
  'net',(select coalesce(sum(total),0) from public.pos_sales where shift_id=sh.id and status='completed'),
  'cost',(select coalesce(sum(l.qty::bigint*l.unit_cost),0) from public.pos_sale_lines l join public.pos_sales s on s.id=l.sale_id where s.shift_id=sh.id and s.status='completed'),
  'methods',(select coalesce(jsonb_object_agg(method,amount),'{}'::jsonb) from (select p.method,sum(p.amount) amount from public.payments p where p.sale_id is not null and p.created_at>=sh.opened_at and p.created_at<=until_at group by p.method) m),
  'expectedCash',coalesce(sh.expected_cash,sh.opening_float+private.pos_cash_between(sh.opened_at,until_at)),
  'parts',(select coalesce(sum(l.qty::bigint*l.unit_price),0) from public.pos_sale_lines l join public.pos_sales s on s.id=l.sale_id where s.shift_id=sh.id and s.status='completed' and l.kind='part'),
  'labour',(select coalesce(sum(l.qty::bigint*l.unit_price),0) from public.pos_sale_lines l join public.pos_sales s on s.id=l.sale_id where s.shift_id=sh.id and s.status='completed' and l.kind='labour'),
  'serviceCount',(select count(*) from public.pos_sales where shift_id=sh.id and status='completed' and sale_type='service'),
  'labourBy',(select coalesce(jsonb_agg(t order by t.amount desc),'[]'::jsonb) from (select coalesce(nullif(s.mechanic,''),'Tanpa nama mekanik') name,count(distinct s.id) jobs,sum(l.qty::bigint*l.unit_price) amount from public.pos_sale_lines l join public.pos_sales s on s.id=l.sale_id where s.shift_id=sh.id and s.status='completed' and s.sale_type='service' and l.kind='labour' group by 1) t),
  'topItems',(select coalesce(jsonb_agg(t order by t.qty desc),'[]'::jsonb) from (select l.name,sum(l.qty) qty,sum(l.qty::bigint*l.unit_price) amount from public.pos_sale_lines l join public.pos_sales s on s.id=l.sale_id where s.shift_id=sh.id and s.status='completed' group by l.name order by sum(l.qty) desc limit 5) t)
 ) into result;
 return result;
end;$$;

-- Owner overview now includes POS sales and service jobs (repairs moved to POS).
create or replace function public.owner_overview() returns jsonb language plpgsql security invoker set search_path='' as $$
declare month_start timestamptz;result jsonb;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and role='owner') then raise exception 'Akses owner diperlukan.';end if;
 month_start:=date_trunc('month',now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
 select jsonb_build_object('month',to_char(month_start at time zone 'Asia/Kuala_Lumpur','MM/YYYY'),
 'soldCount',(select count(*) from public.vehicles where status='sold' and sold_at>=month_start),
 'sales',(select coalesce(sum(price),0) from public.vehicles where status='sold' and sold_at>=month_start),
 'grossProfit',(select coalesce(sum(price-cost-prep),0) from public.vehicles where status='sold' and sold_at>=month_start),
 'vehicleReceipts',(select coalesce(sum(amount),0) from public.payments where vehicle_id is not null and paid_at>=month_start and paid_at<=now()),
 'serviceReceipts',(select coalesce(sum(amount),0) from public.payments where job_id is not null and paid_at>=month_start and paid_at<=now()),
 'vehicleOutstanding',(select coalesce(sum(greatest(price-paid,0)),0) from public.vehicles where status='reserved' or (paid>0 and status<>'sold')),
 'serviceOutstanding',(select coalesce(sum(greatest(private.job_total(items)-paid,0)),0) from public.jobs),
 'posSales',(select coalesce(sum(total),0) from public.pos_sales where status='completed' and created_at>=month_start),
 'posServiceCount',(select count(*) from public.pos_sales where status='completed' and sale_type='service' and created_at>=month_start),
 'posGrossProfit',(select coalesce(sum(s.total),0)-coalesce(sum((select sum(l.qty::bigint*l.unit_cost) from public.pos_sale_lines l where l.sale_id=s.id)),0) from public.pos_sales s where s.status='completed' and s.created_at>=month_start),
 'posReceipts',(select coalesce(sum(amount),0) from public.payments where sale_id is not null and paid_at>=month_start and paid_at<=now())) into result;
 return result;
end;$$;

create or replace function private.sync_pos_stock() returns trigger language plpgsql security invoker set search_path='' as $$
declare p public.pos_products; prev integer;
begin
 select * into p from public.pos_products where id=NEW.product_id;
 prev:=greatest(coalesce(p.stock_qty,0),0);
 update public.pos_products set stock_qty=(select coalesce(sum(qty),0) from public.pos_stock_moves where product_id=NEW.product_id),
  -- Weighted average cost on receipt, so margins stay right when supplier prices change.
  cost=case when NEW.kind='receive' and NEW.unit_cost is not null and private.staff_can('pos_manage') then
   case when prev>0 then round((prev::numeric*p.cost+NEW.qty::numeric*NEW.unit_cost)/(prev+NEW.qty))::bigint else NEW.unit_cost end else cost end
  where id=NEW.product_id;
 return NEW;
end;$$;

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

-- ---------------------------------------------------------------------
-- vehicle-parts.sql
-- ---------------------------------------------------------------------
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

-- Semakan akhir: senarai objek baharu yang sepatutnya wujud.
select 'pos_products' objek,to_regclass('public.pos_products') is not null wujud
union all select 'invoice_profile',to_regclass('public.invoice_profile') is not null
union all select 'sell_vehicle',to_regprocedure('public.sell_vehicle(bigint,integer,uuid,jsonb)') is not null
union all select 'loan_rate_bp',exists(select 1 from information_schema.columns where table_schema='public' and table_name='business_settings' and column_name='loan_rate_bp')
union all select 'pos_service_history',to_regprocedure('public.pos_service_history(text)') is not null
union all select 'vehicle_use_part',to_regprocedure('public.vehicle_use_part(bigint,integer,uuid,bigint,integer)') is not null;
