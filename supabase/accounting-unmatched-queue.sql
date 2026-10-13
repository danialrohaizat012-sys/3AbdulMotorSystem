create or replace function public.accounting_snapshot(p_month date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not private.accounting_owner() then raise exception 'Akses owner diperlukan.';end if;
 with rows as materialized(select * from private.accounting_rows_v2()), accounts as(
 select a.*,exists(select 1 from rows r where r.account_id=a.id or r.to_account_id=a.id) has_activity,case when a.opening_on is null then null else a.opening_balance+coalesce((select sum(case when r.account_id=a.id then case when r.kind in ('income','capital','adjustment') then r.amount-r.fee_amount else -r.amount end else 0 end+case when r.to_account_id=a.id then r.amount else 0 end) from rows r where r.entry_date>=a.opening_on and r.entry_date<=(now() at time zone 'Asia/Kuala_Lumpur')::date),0) end balance from public.accounting_accounts a
 ), period as(select *,case when source<>'Manual' and account_id is null then 0 when kind in ('income','capital','adjustment') then amount-fee_amount when kind in ('expense','drawings') then -amount else 0 end movement from rows where entry_date>=date_trunc('month',p_month)::date and entry_date<(date_trunc('month',p_month)+interval '1 month')::date)
 select jsonb_build_object('asOf',now(),'accounts',(select coalesce(jsonb_agg(to_jsonb(a) order by id),'[]') from accounts a),
 'summary',jsonb_build_object('income',coalesce(sum(greatest(movement,0)),0),'expense',coalesce(sum(greatest(-movement,0)),0),'net',coalesce(sum(movement),0),'capital',coalesce(sum(amount) filter(where kind='capital'),0),'drawings',coalesce(sum(amount) filter(where kind='drawings'),0),'adjustments',coalesce(sum(amount) filter(where kind='adjustment'),0),'fees',coalesce(sum(fee_amount),0),'refunds',-coalesce(sum(amount) filter(where source<>'Manual' and amount<0),0)),
 'unmatched',(select coalesce(jsonb_agg(to_jsonb(u) order by u.entry_date,u.source_key),'[]') from (select * from rows where account_id is null order by entry_date,source_key limit 200)u),
 'unassignedCount',(select count(*) from rows where account_id is null),
 'unassignedTotal',(select coalesce(sum(amount),0) from rows where account_id is null),
 'pendingCount',(select count(*) from period where not voided and (source<>'Manual' or reversal_of is null) and (not reviewed or account_id is null or kind='expense' and receipt_count=0 and receipt_exemption='')),
 'reconciliations',(select coalesce(jsonb_agg(to_jsonb(x) order by x.statement_on desc),'[]') from (select q.*,private.accounting_balance(q.account_id,q.statement_on) system_balance,private.accounting_balance(q.account_id,q.statement_on)-q.statement_balance difference from public.accounting_reconciliations q order by created_at desc limit 30)x),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from(select * from public.accounting_audit order by id desc limit 20)a)) into result from period;
 return result;
end;$$;
