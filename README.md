# 3 Abdul Motor

Independent Vite/React frontend for GitHub Pages and a dedicated Supabase backend. Visitors and staff do not need ChatGPT accounts.

## Screens

- `#catalogue`: public motorcycle stock, status and price only.
- `#inventory`: inventory and buying/selling administration.
- `#garage`: customer service jobs, parts, labour and payments.

Inventory and garage use email/password Supabase Auth. Only enabled staff profiles have access; roles are `owner`, `inventory`, `garage`. There is no public admin registration.

## Setup pending dedicated Supabase account access

Owner account requested: `binalab.3abdulmotor@gmail.com`. The currently connected Supabase account does not expose this account's organization/project. No connection to Abe Din's database is configured.

1. Select/create the dedicated 3 Abdul Motor project, reviewing its plan/cost first.
2. Review and apply `supabase/schema.sql` to that project only.
3. Create the owner's verified email/password user in Supabase Auth and insert their verified UUID in `public.staff` as `owner` (see `supabase/owner-setup.sql`). Never commit passwords or service/secret keys.
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` as GitHub Actions repository variables, or in local `.env`. Publishable keys are expected; service/secret keys must never be frontend variables.
5. Set Supabase Site URL and allowed password-recovery redirect URL to the actual deployed Pages URL.
6. Enable GitHub Pages with Source = GitHub Actions; workflow publishes after a main push.

Without configuration, the public catalogue clearly labels display-only sample records; login is unavailable with an explanatory message. This does not claim a working database connection.

## Development

`pnpm install --frozen-lockfile`, `pnpm dev`, `pnpm build`.

Currency is integer cents. Catalogue has a separate safe projection containing no buyer, purchase cost or garage information. Storage is private with read access for published stock photographs and authorized inventory staff. RLS enforces roles server-side. Photo URLs expire after one hour; hiding a vehicle stops new anonymous photo access, but an existing signed URL remains valid until expiry.

## Operational limitations

Payment values are cumulative, not a transaction ledger. Concurrent edits are last-write-wins. Existing prototype D1/R2 data has not been exported or migrated; that requires a fresh inventory of stored records before cutover. The existing private Sites prototype is preserved while this independent deployment is prepared.
