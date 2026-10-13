-- Public business contact links, managed only by an enabled owner.
begin;
create function private.valid_footer_url(value text) returns boolean language sql immutable security invoker set search_path='' as $$
 select value='' or (length(value)<=2000 and value~'^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?([/?#][^[:space:]<>]*)?$' and strpos(value,chr(92))=0);
$$;
revoke all on function private.valid_footer_url(text) from public,anon;
grant execute on function private.valid_footer_url(text) to authenticated;
alter table public.business_settings
 add column tiktok_url text not null default '' check(private.valid_footer_url(tiktok_url)),
 add column facebook_url text not null default '' check(private.valid_footer_url(facebook_url)),
 add column maps_url text not null default '' check(private.valid_footer_url(maps_url)),
 add column footer_whatsapp_url text not null default '' check(private.valid_footer_url(footer_whatsapp_url));
create function private.guard_footer_links() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if row(NEW.tiktok_url,NEW.facebook_url,NEW.maps_url,NEW.footer_whatsapp_url) is distinct from row(OLD.tiktok_url,OLD.facebook_url,OLD.maps_url,OLD.footer_whatsapp_url)
 and not exists(select 1 from public.staff where id=auth.uid() and enabled and not must_change_password and role='owner') then raise exception 'Hanya owner boleh mengubah pautan footer.';end if;
 return NEW;
end;$$;
revoke all on function private.guard_footer_links() from public,anon,authenticated;
create trigger settings_footer_owner before update on public.business_settings for each row execute function private.guard_footer_links();
commit;
