CREATE OR REPLACE FUNCTION private.accounting_rows()
 RETURNS TABLE(source_key text, source_id bigint, source text, entry_date date, kind text, amount bigint, account_id text, to_account_id text, category text, description text, counterparty text, reference text, note text, created_at timestamp with time zone, created_by uuid, vehicle_id bigint, job_id bigint, reversal_of bigint, voided boolean, reviewed boolean, version integer, receipt_count bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select 'M:'||e.id,e.id,'Manual',e.entry_date,e.kind,e.amount,e.account_id,e.to_account_id,e.category,e.description,e.counterparty,e.reference,e.note,e.created_at,e.created_by,null::bigint,null::bigint,e.reversal_of,
 exists(select 1 from public.accounting_entries r where r.reversal_of=e.id),coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='M:'||e.id)
 from public.accounting_entries e left join public.accounting_annotations a on a.source_key='M:'||e.id where (select private.accounting_owner())
 union all
 select 'P:'||p.id,p.id,case when p.vehicle_id is not null then 'Inventori' else 'Garaj' end,(p.paid_at at time zone 'Asia/Kuala_Lumpur')::date,'income',p.amount,
 coalesce(a.account_id,case when p.method='cash' then 'cash' end),null::text,case when p.amount<0 then 'Refund pelanggan' when p.purpose='deposit' then 'Deposit pelanggan' when p.job_id is not null then 'Bayaran servis' else 'Bayaran motosikal' end,
 case when p.vehicle_id is not null then 'Bayaran · '||v.brand||' '||v.model else 'Bayaran servis · '||j.bike end,
 coalesce(v.buyer,j.customer,''),case when p.vehicle_id is not null then '3AM-'||lpad(v.stock_no::text,4,'0') else 'JOB-'||lpad(p.job_id::text,4,'0') end,p.note,p.created_at,p.created_by,p.vehicle_id,p.job_id,p.reverses_id,false,coalesce(a.reviewed,false),coalesce(a.version,0),(select count(*) from public.accounting_receipts d where d.source_key='P:'||p.id)
 from public.payments p left join public.vehicles v on v.id=p.vehicle_id left join public.jobs j on j.id=p.job_id left join public.accounting_annotations a on a.source_key='P:'||p.id where (select private.accounting_owner());
$function$;
CREATE OR REPLACE FUNCTION public.accounting_operations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password) then raise exception 'Akses staf diperlukan.';end if;
 with debts as (
 select v.id,v.stock_no,'inventory'::text kind,v.buyer name,v.buyer_phone phone,v.brand||' '||v.model label,v.plate,v.status,v.price amount,v.paid,v.price-v.paid balance,v.created_at::date created_on,greatest(0,(now() at time zone 'Asia/Kuala_Lumpur')::date-(v.created_at at time zone 'Asia/Kuala_Lumpur')::date) age_days
 from public.vehicles v where v.price>v.paid and (v.paid>0 or (v.status in ('reserved','sold') and trim(v.buyer)<>''))
 union all
 select j.id,null::bigint,'garage',j.customer,j.phone,j.bike,j.plate,j.status,private.job_total(j.items),j.paid,private.job_total(j.items)-j.paid,j.created_at::date,greatest(0,(now() at time zone 'Asia/Kuala_Lumpur')::date-(j.created_at at time zone 'Asia/Kuala_Lumpur')::date)
 from public.jobs j where j.estimate_status='approved' and private.job_total(j.items)>j.paid
 ), costs as (
 select v.id,'inventory'::text kind,v.brand||' '||v.model||' · '||v.plate label,v.cost expected_purchase,v.prep expected_prep,null::bigint expected_service,
 coalesce((select sum(e.amount) from public.accounting_entries e where e.vehicle_id=v.id and e.cost_scope='purchase'),0) paid_purchase,
 coalesce((select sum(e.amount) from public.accounting_entries e where e.vehicle_id=v.id and e.cost_scope='prep'),0) paid_prep,0::numeric paid_service,true cost_complete,v.price sales,0::numeric labour,0::numeric parts
 from public.vehicles v where (select private.accounting_owner())
 union all
 select j.id,'garage',j.bike||' · '||j.plate,null::bigint,null::bigint,
 case when not exists(select 1 from jsonb_array_elements(j.items) l where l->>'cost' is null) then (select coalesce(sum((l->>'qty')::bigint*(l->>'cost')::bigint),0)::bigint from jsonb_array_elements(j.items) l) else null end,
 0::numeric,0::numeric,coalesce((select sum(e.amount) from public.accounting_entries e where e.job_id=j.id and e.cost_scope='service'),0),
 not exists(select 1 from jsonb_array_elements(j.items) l where l->>'cost' is null),private.job_total(j.items),
 (select coalesce(sum((l->>'qty')::bigint*(l->>'rate')::bigint) filter(where l->>'kind'='labour'),0) from jsonb_array_elements(j.items) l),
 (select coalesce(sum((l->>'qty')::bigint*(l->>'rate')::bigint) filter(where l->>'kind'='part'),0) from jsonb_array_elements(j.items) l)
 from public.jobs j where (select private.accounting_owner())
 ) select jsonb_build_object('debts',(select coalesce(jsonb_agg(to_jsonb(d) order by d.age_days desc,d.id desc),'[]') from debts d),'costs',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id desc),'[]') from costs c)) into result;
 return result;
end;$function$;
