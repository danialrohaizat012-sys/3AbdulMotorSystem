# 3 Abdul Motor

Independent Vite/React frontend for GitHub Pages and a dedicated Supabase backend. Visitors and staff do not need ChatGPT accounts.

## Screens

- `#catalogue`: public motorcycle stock, status and price only.
- `#inventory`: inventory and buying/selling administration.
- `#garage`: customer service jobs, parts, labour and payments.

Inventory and garage use email/password Supabase Auth. Only enabled staff profiles have access; roles are `owner`, `inventory`, `garage`. There is no public admin registration.

## Deployment status

The dedicated Supabase project `jvmqpucsbeddusqrgsyt` is connected. Schema, role policies and private photo storage are installed. The browser uses a publishable key; environment variables can override the defaults. Never use service/secret keys in frontend configuration.

The app is live at https://3abdulmotor.binalab.my/ through GitHub Actions / Pages. The verified application owner account has been provisioned separately from Supabase dashboard membership. Public stock stays empty until staff add and publish real records. Demo records appear only when an admin explicitly selects **Lihat demo**; edits and payments are disabled in demo mode.

## Development

`pnpm install --frozen-lockfile`, `pnpm dev`, `pnpm build`.

Currency is integer cents. Catalogue has a separate safe projection containing no buyer, purchase cost or garage information. Storage is private with read access for published stock photographs and authorized inventory staff. RLS enforces roles server-side. Photo URLs expire after one hour; hiding a vehicle stops new anonymous photo access, but an existing signed URL remains valid until expiry.

## Operations

- Immutable payment transactions track deposits, balance payments, methods, dates, staff receiver and notes. Net paid amounts and balances are derived by database triggers. Owner refunds reference an original payment, cannot exceed its refundable balance and require a reason. Unique request IDs prevent duplicate retries. Transactions cannot be edited or deleted through the application.
- Sold requires a positive price, buyer name/phone and full payment. Only the owner can change an existing sale price or reopen Sold. Active plate duplicates require a recorded reason; active chassis numbers are unique.
- Garage work and payment states are separate. Charged work requires recorded customer approval of the current estimate; charge edits reset approval. Free work requires a reason. Collection requires Ready; unpaid collection requires owner approval with reason and actor/time. Archived jobs are retrieved through explicit plate, phone or customer history search.
- Save operations match the record version. A stale draft cannot overwrite another staff edit or newly recorded payment. The editor offers an explicit discard-and-reload action.
- Inventory supports supplier details, chassis, itemized preparation costs, inspection and up to five compressed photos. Cancelled/replaced photos are removed when unreferenced; manual cleanup removes unattached photos older than two hours. Storage policies prevent deletion of attached photos.
- **Inventori → Tetapan WhatsApp** controls the catalogue number and template. A blank number hides the WhatsApp action. Supported placeholders: `{jenama}`, `{model}`, `{tahun}`, `{harga}`, `{status}`, `{id}`, `{link}`. The message is previewed before saving. Phone numbers use international digits; Malaysian leading 0 is normalized to 60. Each published motorcycle has a shareable catalogue link and photo gallery.
- Record details provide printable sales/service invoices, payment receipts and service estimates (browser Print / Save as PDF). Customer agreement is a staff-entered record of approval; the system does not send or obtain agreement automatically.
- Owner overview shows current Kuala Lumpur month sales, gross profit and net receipts; customer balances cover all records. Gross profit excludes overhead. The immutable audit records staff identity, action and changed field names for stock, jobs and settings.

Schema rollout in a new dedicated project: `schema.sql`, `operations.sql`, `service-history.sql`, `guard-refinement.sql`, then `payment-history-refinement.sql` under `supabase/`. Scripts are reviewed one-time upgrades, not idempotent installers. The dedicated production project has all upgrades applied. No prototype records or other client project were migrated.

## Mobile and free-plan usage

Phone layouts use touch targets of at least 44px, 16px form inputs and viewport-sized scrollable dialogs. Stock photos are lazy-loaded. New uploads are re-encoded in the browser, longest edge at most 1280px, with a hard 256 KiB output limit; WebP is preferred with JPEG fallback. This avoids paid server image transformations and removes original photo metadata. Existing photos are not automatically rewritten.

Records are cached in memory for 30 seconds with concurrent requests deduplicated; verified staff lookups are cached for 15 seconds. Manual refresh bypasses record cache, and successful saves invalidate it. Auth changes clear caches. Private records are never persisted by these caches. Photo signing uses a batch request and reuses signed URLs for 45 minutes, within their one-hour expiry. No background polling or Realtime subscription is used. Cached results can be briefly stale; RLS remains the authority for reads and writes.

Run `node --test tests/*.test.mjs` for cache, WhatsApp template and form validation regression checks. `tests/operations.sql` verifies ledger/status rules, retry safety, optimistic versions, private access and history with the existing owner identity inside a rolled-back transaction; run only in the dedicated project. Actual quota savings depend on traffic and photographs; these changes do not increase the free-plan limits.
