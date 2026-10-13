CREATE OR REPLACE FUNCTION private.guard_job()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare net bigint; amount bigint; owner boolean;
begin
 if not private.staff_can('garage_view') then raise exception 'Akses garaj tidak dibenarkan.';end if;
 if TG_OP='INSERT' and not private.staff_can('garage_edit') then raise exception 'Anda hanya mempunyai akses baca garaj.';end if;
 if TG_OP='UPDATE' and not private.staff_can('garage_edit') and (to_jsonb(NEW)-array['paid','version','updated_at']) is distinct from (to_jsonb(OLD)-array['paid','version','updated_at']) then raise exception 'Anda tidak dibenarkan mengubah job servis.';end if;
 owner:=exists(select 1 from public.staff where id=auth.uid() and enabled and role='owner');
 NEW.plate:=upper(trim(NEW.plate));NEW.phone:=regexp_replace(NEW.phone,'[^0-9]','','g');if left(NEW.phone,1)='0' then NEW.phone:='60'||substr(NEW.phone,2);end if;
 select coalesce(sum(p.amount),0) into net from public.payments p where p.job_id=NEW.id;
 if NEW.paid<>net then raise exception 'Bayaran mesti direkod melalui transaksi bayaran.';end if;
 amount:=private.job_total(NEW.items);
 if TG_OP='UPDATE' then
  NEW.version:=OLD.version+1;
  if OLD.status='collected' and NEW.status<>'collected' and not owner then raise exception 'Hanya owner boleh membuka semula job yang diserahkan.';end if;
  if OLD.status='collected' and NEW.status='collected' and (select coalesce(jsonb_agg(item-'cost' order by ord),'[]'::jsonb) from jsonb_array_elements(NEW.items) with ordinality t(item,ord)) is distinct from (select coalesce(jsonb_agg(item-'cost' order by ord),'[]'::jsonb) from jsonb_array_elements(OLD.items) with ordinality t(item,ord)) then raise exception 'Buka semula job sebelum mengubah caj invois yang sudah diserahkan.';end if;
 end if;
 if NEW.estimate_status='approved' then
  if length(trim(NEW.approval_note))<5 or NEW.approved_total is distinct from amount then raise exception 'Rekod persetujuan pelanggan untuk jumlah anggaran semasa.';end if;
 else NEW.approved_total:=null;end if;
 if NEW.status in ('working','ready','collected') then
  if amount>0 and NEW.estimate_status<>'approved' then raise exception 'Rekod persetujuan pelanggan sebelum mulakan kerja.';end if;
  if amount=0 and length(trim(NEW.no_charge_reason))<5 then raise exception 'Isi sebab servis percuma sebelum mulakan atau siapkan kerja.';end if;
 end if;
 if NEW.status='collected' and (TG_OP='INSERT' or OLD.status<>'collected') then
  if TG_OP='INSERT' or OLD.status<>'ready' then raise exception 'Job mesti berstatus Siap sebelum diserahkan.';end if;
 end if;
 if NEW.status='collected' and NEW.paid<amount then
  if TG_OP='INSERT' or OLD.status<>'collected' or NEW.credit_reason is distinct from OLD.credit_reason then
   if not owner or length(trim(NEW.credit_reason))<5 then raise exception 'Serahan dengan baki memerlukan kelulusan owner dan sebab.';end if;
   NEW.credit_approved_by:=auth.uid();NEW.credit_approved_at:=now();
  else NEW.credit_approved_by:=OLD.credit_approved_by;NEW.credit_approved_at:=OLD.credit_approved_at;end if;
  if NEW.credit_approved_by is null then raise exception 'Kelulusan owner untuk baki belum direkodkan.';end if;
 elsif TG_OP='UPDATE' then NEW.credit_approved_by:=OLD.credit_approved_by;NEW.credit_approved_at:=OLD.credit_approved_at;
 else NEW.credit_approved_by:=null;NEW.credit_approved_at:=null;end if;
 return NEW;
end;$function$;

