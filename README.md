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

## Owner staff access and catalogue visits

`#staff` is a dedicated owner-only workspace, also linked from the owner sidebar and phone navigation. Owners can create staff application logins, choose Inventory / Garage / both, enable or disable accounts, and control record edits, receiving payments, publishing catalogue stock, WhatsApp settings and photo management. The payment amount limit is **per transaction**, in cents; it is not a daily cash limit. Read-only operators can separately be allowed to receive payments, with database synchronization restricted to ledger-derived paid totals. Stock/garage read access includes the existing financial fields; these controls restrict modules and actions, not individual fields.

New staff logins use an owner-chosen temporary password (12–128 characters, upper/lowercase and digits). The owner verifies the email before creating the account and shares credentials independently; no invitation email is automatically sent. A server-enforced first-password-change gate blocks access to operational records until staff change the password. The original owner is protected from staff-management edits, and staff cannot grant their own permissions. Disablement is checked on each database operation, regardless of token age. Access changes and audit metadata are written atomically; password values never enter profile/audit rows.

Deploy `supabase/functions/manage-staff` using the pinned SDK and `deno.json`. This narrow Auth administration endpoint uses the built-in **server-only** `SUPABASE_SERVICE_ROLE_KEY`. Gateway `verify_jwt=false` supports current signing keys; the function independently validates every bearer token with Auth `getUser`, loads enabled staff authorization from the database, and checks owner role before staff-management operations. Caller password changes use the caller's token against Auth's user endpoint. Never include server keys in the app bundle.

Additional one-time SQL rollout: `staff-access-and-visitors.sql`, `catalogue-projection-guard.sql`, `staff-write-safety.sql`. All are already applied in the dedicated project. `catalogue-projection-guard` prevents direct API edits to the public projection, including by a read-only payment operator.

The catalogue counter shows **estimated browser visits**, today and cumulative, starting from rollout. One browser identifier contributes once per Kuala Lumpur day; revisiting on another day contributes another visit to the cumulative total. It is not an all-time unique-person count or a verified human count. Browser storage clearing, multiple devices and bots can affect it. No IP address is stored. UUIDs are hashed in private tables with only two days retained for deduplication, while aggregate counts persist. The browser remembers successful counting and reuses aggregate results in memory for five minutes. There is no polling or Realtime subscription. Public APIs can only increment through the narrow deduplicating function and read aggregate values.

`tests/staff-access.sql` verifies module isolation, read-only payment operators, payment caps, disablement, temporary-password locks, escalation prevention and anonymous counter deduplication in a rolled-back transaction. Edge authorization/provisioning failure paths and frontend permission rules are covered in `tests/staff*.test.mjs`. No real test staff account is created by these tests.
