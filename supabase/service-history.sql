begin;
create function public.service_history(search_text text) returns setof public.jobs language plpgsql security invoker set search_path='' as $$
declare term text; plate_term text; phone_term text;
begin
 if not exists(select 1 from public.staff where id=auth.uid() and enabled and role in ('owner','garage')) then raise exception 'Akses garaj diperlukan.';end if;
 term:=trim(search_text);if length(term)<2 or length(term)>120 then return;end if;
 plate_term:=regexp_replace(upper(term),'[^A-Z0-9]','','g');
 phone_term:=regexp_replace(term,'[^0-9]','','g');if left(phone_term,1)='0' then phone_term:='60'||substr(phone_term,2);end if;
 return query select j.* from public.jobs j where regexp_replace(upper(j.plate),'[^A-Z0-9]','','g')=plate_term or (length(phone_term)>=3 and j.phone=phone_term) or position(lower(term) in lower(j.customer))>0 order by j.id desc limit 100;
end;$$;
revoke all on function public.service_history(text) from public,anon;
grant execute on function public.service_history(text) to authenticated;
commit;
