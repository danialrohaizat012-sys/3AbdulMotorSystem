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

## Mobile and free-plan usage

Phone layouts use touch targets of at least 44px, 16px form inputs and viewport-sized scrollable dialogs. Stock photos are lazy-loaded. New uploads are re-encoded in the browser, longest edge at most 1280px, with a hard 256 KiB output limit; WebP is preferred with JPEG fallback. This avoids paid server image transformations and removes original photo metadata. Existing photos are not automatically rewritten.

Records are cached in memory for 30 seconds with concurrent requests deduplicated; verified staff lookups are cached for 15 seconds. Manual refresh bypasses record cache, and successful saves invalidate it. Auth changes clear caches. Private records are never persisted by these caches. Photo signing uses a batch request and reuses signed URLs for 45 minutes, within their one-hour expiry. No background polling or Realtime subscription is used. Cached results can be briefly stale; RLS remains the authority for reads and writes.

Run `node --test tests/request-cache.test.mjs` for request deduplication, expiry, retry and auth invalidation regression checks. Actual quota savings depend on traffic and photographs; these changes do not increase the free-plan limits.
