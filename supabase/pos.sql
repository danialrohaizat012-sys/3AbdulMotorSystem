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
  where coalesce(mv.m,0)<>case when s.status='completed' then -coalesce(l.q,0) else 0 end) into mismatch;
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
 if NEW.amount>0 and exists(select 1 from public.staff where id=auth.uid() and role<>'owner' and payment_limit is not null and NEW.amount>payment_limit) then raise exception 'Amaun melebihi had bayaran staf. Minta owner merekodkan transaksi ini.';end if;
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
 select id into v_shift from public.pos_shifts where closed_at is null;
 if v_shift is null then insert into public.pos_shifts(opening_float) values(0) returning id into v_shift;end if;
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
 for p in select o.id,o.amount+coalesce((select sum(r.amount) from public.payments r where r.reverses_id=o.id),0) remaining,o.method from public.payments o where o.sale_id=p_sale and o.amount>0 order by o.id loop
  if p.remaining>0 then insert into public.payments(request_id,sale_id,amount,method,purpose,note,reverses_id,created_by) values(gen_random_uuid(),p_sale,-p.remaining,p.method,'refund','Batal jualan: '||trim(p_reason),p.id,auth.uid());end if;
 end loop;
 update public.pos_sales set status='voided',void_reason=trim(p_reason) where id=p_sale;
 for l in select product_id,qty from public.pos_sale_lines where sale_id=p_sale and product_id is not null and exists(select 1 from public.pos_stock_moves m where m.sale_id=p_sale and m.product_id=pos_sale_lines.product_id and m.kind='sale') loop
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
