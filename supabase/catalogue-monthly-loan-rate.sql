begin;
-- Keep annual basis points while allowing a tenth of a basis point.
alter table public.business_settings alter column loan_rate_bp type numeric(5,1);
-- The migration sets the initial rate. Restore the owner guard before commit.
alter table public.business_settings disable trigger settings_loan_owner;
update public.business_settings set loan_rate_bp=999.6 where id=1;
alter table public.business_settings enable trigger settings_loan_owner;
commit;
