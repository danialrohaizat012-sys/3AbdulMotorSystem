-- All fixture URLs and profile changes roll back; public links are not guessed or seeded.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','41ad4268-5653-4ab0-84c4-b89dda95adf8',true);
update public.business_settings set tiktok_url='https://www.tiktok.com/@example',facebook_url='https://www.facebook.com/example',maps_url='https://maps.app.goo.gl/example',footer_whatsapp_url='https://wa.me/60123456789' where id=1;
do $$begin
 begin update public.business_settings set tiktok_url='javascript:alert(1)' where id=1;raise exception 'FAIL unsafe URL';exception when check_violation then null;end;
 begin update public.business_settings set maps_url='https://user:secret@example.com/' where id=1;raise exception 'FAIL URL credentials';exception when check_violation then null;end;
end $$;
reset role;
update public.staff set role='inventory',permissions=jsonb_set(permissions,'{manage_whatsapp}','true') where id='41ad4268-5653-4ab0-84c4-b89dda95adf8';
set local role authenticated;
do $$begin
 begin update public.business_settings set facebook_url='https://www.facebook.com/tampered' where id=1;raise exception 'FAIL staff social URL edit';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
 update public.business_settings set whatsapp_phone='60123456789' where id=1;
 if (select facebook_url from public.business_settings where id=1)<>'https://www.facebook.com/example' then raise exception 'FAIL phone edit changed social links';end if;
end $$;
reset role;
set local role anon;
do $$begin if (select tiktok_url from public.business_settings where id=1)<>'https://www.tiktok.com/@example' then raise exception 'FAIL public link read';end if;end $$;
rollback;
select 'PASS footer URL validation, owner-only edits, WhatsApp staff permissions and public reads' result;
