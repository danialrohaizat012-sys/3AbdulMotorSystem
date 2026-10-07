# 3 Abdul Motor

Independent Vite/React frontend for GitHub Pages and a dedicated Supabase backend. Visitors and staff do not need ChatGPT accounts.

## Screens

- `#catalogue`: public motorcycle stock, status and price only.
- `#inventory`: inventory and buying/selling administration.
- `#garage`: customer service jobs, parts, labour and payments.

Inventory and garage use email/password Supabase Auth. Only enabled staff profiles have access; roles are `owner`, `inventory`, `garage`. There is no public admin registration.

## Deployment status

The dedicated Supabase project `jvmqpucsbeddusqrgsyt` is connected. Schema, role policies and private photo storage are installed. The browser uses a publishable key; environment variables can override the defaults. Never use service/secret keys in frontend configuration.

Remaining setup:
1. Create the owner's email/password user in Supabase Authentication > Users, then insert the verified UUID in `public.staff` as `owner` (see `supabase/owner-setup.sql`). Supabase dashboard accounts are separate from application login accounts.
2. Enable GitHub Pages with Source = GitHub Actions and run the Pages workflow.
3. Set Supabase Site URL and allowed password-recovery redirect URL to the actual deployed Pages URL.

The database currently has no stock or service records. Sample catalogue records are clearly marked and cannot be saved as real records.

## Development

`pnpm install --frozen-lockfile`, `pnpm dev`, `pnpm build`.

Currency is integer cents. Catalogue has a separate safe projection containing no buyer, purchase cost or garage information. Storage is private with read access for published stock photographs and authorized inventory staff. RLS enforces roles server-side. Photo URLs expire after one hour; hiding a vehicle stops new anonymous photo access, but an existing signed URL remains valid until expiry.

## Operational limitations

Payment values are cumulative, not a transaction ledger. Concurrent edits are last-write-wins. Existing prototype D1/R2 data has not been exported or migrated; that requires a fresh inventory of stored records before cutover. The existing private Sites prototype is preserved while this independent deployment is prepared.
