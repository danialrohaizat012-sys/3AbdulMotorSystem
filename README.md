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
- Inventory supports supplier details, chassis, itemized preparation costs, inspection and up to ten compressed photos. Cancelled/replaced photos are removed when unreferenced; manual cleanup removes unattached photos older than two hours. Storage policies prevent deletion of attached photos.
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

## Accounting cashbook (12 October 2026)

`#accounting` is the owner-only live cashbook. `#accounting-preview` remains an unauthenticated **synthetic-data preview**, isolated from live financial writes/reads. Both pages are lazy-loaded. No sample balances or bookkeeping records were inserted into production.

Owner configures each cash/bank opening balance once, as the balance **before transactions on the chosen starting date**. Earlier movements remain visible in historical reports but are excluded from current account balances. Unconfigured balances display as unknown. Opening balances are locked; signed, reasoned balance adjustments are separate from income. Balances include classified movements through the current Kuala Lumpur day. Transfers change the two account balances without changing business inflow/outflow.

Manual postings support expenses, other income, owner capital/drawings, transfers and signed balance adjustments. Posted rows cannot be updated/deleted. Cancellations append an exact opposite row referencing the original, with date/reason and an audit trail. Account configuration, posting, metadata edits and receipt attachment create immutable audit events; ordinary/disabled/temporary-password staff and anonymous visitors cannot access Accounting. Amounts are integer cents. Request UUIDs make retries idempotent; annotation versions reject stale saves.

Payments/refunds appear as a live projection of existing immutable `payments` IDs, exactly once; no copying, backfill or change to operational payment rules occurs. Cash methods default to cash; transfer/card methods require owner account mapping. Mapping changes and review flags are audited. Unassigned payments appear in cash-flow reports but are **excluded from account balances** until mapped. The dashboard shows their count and net value separately. These are book balances, not automatically reconciled bank-statement balances. Links open the original authorized Inventory/Garage record.

Transactions can be searched/filtered, opened for details, marked reviewed, assigned to an account, and supplied with up to five private receipt files. Images reuse browser compression (256 KiB max); validated PDFs are limited to 2 MiB. Storage bucket `accounting-receipts` is private with owner-only policies. Attached receipts are preserved; only unreferenced uploads can be cleaned up. File links are short-lived signed URLs, kept only in memory. After a saved transaction, receipt attachment is a separate action so an upload failure cannot duplicate the posting.

Monthly CSV covers the entire selected month, regardless of on-screen filters. Formula-like text is escaped; numeric negative amounts remain numeric. Monthly reads are cached in memory for 30 seconds, clear on Auth changes, and refresh after writes. Feed paging uses the snapshot timestamp to exclude newly posted rows during pagination. No Realtime or polling is added.

Rollout: `supabase/accounting.sql` is the consolidated new-project SQL script. Production migration history also contains reviewed refinements for immutable reversal locks, timestamp paging/refund review, balance adjustments and unassigned counts. Do not rerun the consolidated script against an already upgraded project. `tests/accounting.sql` validates cash math, deposit/refund projection, retry safety, reversals, metadata concurrency, immutable audit, receipt references and role isolation inside a rolled-back transaction. Storage fixtures are metadata-only and rolled back; no real customer data or physical file is created/deleted by these tests.

Scope: cashbook and operational receipt integration. Full profit-and-loss recognition, supplier/customer subledgers, tax reporting, bank-statement import/reconciliation and configurable Accounting staff permissions remain outside this first phase. Inventory cost/preparation figures are **not assumed paid**; owner records their actual payments separately. No paid plan or unrelated client project was changed.

## Compact visits and footer links (13 October 2026)

The catalogue visit estimate remains once per browser/day, displayed in a compact text row. The shared footer includes monochrome TikTok, Facebook, Maps and WhatsApp icons with 44px touch targets. Owner sets their HTTPS URLs through Inventory → Tetapan katalog → Pautan ikon footer. Empty links render as inactive icons; no business URL is guessed. The footer WhatsApp URL is independent of the vehicle enquiry phone/template. Public settings reads reuse the existing cache; footer updates propagate immediately on settings save. New URLs are validated in the browser and database, and link changes require the enabled owner role even if a staff member has WhatsApp-edit permission. Changes retain the existing settings version/audit behavior. Rollout SQL: `supabase/footer-links.sql`; rolled-back permission/URL regression: `tests/footer-links.sql`.

## Delivery audit — 13 October 2026

See `docs/audit-delivery-2026-10-13.md` for executed tests, the long accounting-reference fix, known limitations, owner setup and the final device UAT checklist. The current catalogue supports 10 records per display page, sorting, a customer gallery/lightbox, fixed contact actions, and owner-managed per-stock freegift descriptions. Inventory provides a public-layout preview without publishing the record. Tests use transaction rollback; never insert imaginary customer payments or opening balances for a production demonstration.

## Staff Accounting access — pending production rollout (3 November 2026)

Owner can grant `accounting_view`, `accounting_post` and `accounting_export` independently in Akses staf. Posting and CSV require view access; existing profiles default to denied. These flags supplement the existing Inventory/Garage assignment. Disabled accounts and temporary-password accounts remain blocked.

View access includes the full cashbook, balances, costs, customer debts and receipt documents across both operational modules. Posting allows expenses, other income and receipt attachment. Customer receipts/refunds still use Inventory/Garage permissions. Account configuration/opening balances, reconciliation, mapping/review, capital, drawings, transfers, adjustments and reversals stay owner-only. CSV permission governs the built-in CSV download; it cannot prevent copying data already visible to an authorized reader.

Rollout order: apply `supabase/staff-accounting-access.sql` to the already upgraded dedicated project, deploy `supabase/functions/manage-staff/index.ts` with the existing configuration (gateway verification disabled, JWT checked inside the function), then merge/deploy the frontend. Do not deploy only the frontend: the old staff-management function discards these flags. No existing staff member is granted financial access automatically.

Validation: `node --test tests/*.test.mjs`, `pnpm build`, and the isolated PostgreSQL regression via `tests/run-staff-accounting-sql.mjs`. The latter uses optional PGlite 0.5.14 outside the application dependencies and bootstraps auth/storage stand-ins. It exercises actual SQL/RLS, owner/staff role transitions, posting/retries, immutable audit, receipt metadata, denial of privileged RPCs/direct writes, and anonymous isolation. It does not test production Auth, Storage upload, Edge deployment, or logged-in browser flows. The fixture transaction rolls back. Do not execute the fixture identity inserts against production Auth; use the isolated runner or a disposable development database.

The private account-lock helper is a narrowly authorized definer used only to acquire shared row locks for postings without granting staff account UPDATE rights. The existing private audit trigger authorizes staff only for entry/receipt inserts. All remaining account/annotation/reconciliation mutation policies stay owner-only. Production rollout and advisors remain unverified because the connected management account currently denies access to project `jvmqpucsbeddusqrgsyt`.

## POS kaunter (19 November 2026) — pending production rollout

`#pos` is a counter point-of-sale for parts, accessories and labour, lazy-loaded and linked from the staff sidebar. Owner grants two independent flags in Akses staf: **POS: jual** (sell and close the drawer) and **POS: urus** (products, stock receipts/adjustments, price override, discount, one-off items). Neither is granted automatically. Only the owner can void a sale.

Staff flow is deliberately short: scan/tap products → Bayar. The first sale of the day opens the drawer automatically with a RM0 float (an optional float can be entered under Tutup kaunter). Cash is the default method; tendered cash and change are optional helpers; split cash + transfer/card is available. Customer name/phone is optional and enables a WhatsApp receipt. Receipts print on 80 mm paper through the browser.

Database rules (`supabase/pos.sql`, SECURITY INVOKER throughout): stock quantity always equals an immutable stock ledger; sales cannot oversell tracked stock; prices come from the product unless a POS manager overrides; a sale exists only as a complete, fully paid, stock-consistent unit (deferred commit check); request UUIDs make retries idempotent; POS payments are rows in the existing `payments` ledger (`sale_id`, purpose `pos`) so refund rules and the Accounting projection apply unchanged. The staff per-transaction payment limit governs Inventory/Garage receipts only; counter sales are governed by the POS: jual flag. Cash refunds from a void come out of the drawer open at that moment (one is opened automatically if needed). Voids append owner refunds and stock returns; nothing is edited or deleted. Closing the drawer computes expected cash on the server and requires a reason for any variance. Accounting shows POS receipts as source **POS** with reference `POS-0001`.

Rollout order: confirm `staff-accounting-access.sql` is applied, apply `supabase/pos.sql`, redeploy `supabase/functions/manage-staff` (it now accepts `pos_sell`/`pos_manage`), then deploy the frontend. Validation: `node --test tests/*.test.mjs`, `pnpm build`, and `PGLITE_MODULE=… node tests/run-pos-sql.mjs` (applies all 21 migrations to in-memory PostgreSQL and runs `tests/pos.sql` + `tests/staff-accounting-access.sql`, rolled back). Not tested: production Auth/PostgREST, real printers and barcode scanners.

Not in this phase: garage job parts deducting POS stock, partial returns (void is whole-sale), purchase orders/suppliers, SST invoices.

## Invois, jualan satu langkah, katalog telefon & SEO (22 November 2026) — pending production rollout

- **Invois profesional:** invois, anggaran dan resit menggunakan satu reka bentuk A4 (cetak dan PDF servis vektor). Owner mengisi **Maklumat invois** (nama, SSM, alamat, telefon, e-mel, bank, terma) — `supabase/invoice-profile.sql`; staf boleh baca, owner sahaja ubah, tidak boleh dibaca anon. Sebelum migrasi, invois guna nama kedai dan nombor WhatsApp katalog.
- **Jual motor satu langkah:** butang **Jual motor** pada rekod stok — pembeli, bayar penuh / deposit / tempah sahaja, kaedah bayaran — dalam satu transaksi (`supabase/vehicle-quick-sale.sql`, RPC `sell_vehicle`, invoker). Semua guard sedia ada kekal. Sebelum migrasi, dialog menggunakan langkah lama secara automatik.
- **Katalog telefon:** bahagian atas dipadatkan; kad motor pertama kelihatan dalam skrin pertama (iPhone 13: dari 1046px ke 436px).
- **SEO:** tajuk & meta description, canonical, Open Graph/Twitter (`og-image.jpg`), `robots.txt`, `sitemap.xml`, data berstruktur `MotorcycleDealer` + `ItemList` stok awam (harga, keadaan, jarak — tiada data peribadi), tajuk halaman ikut motosikal yang dibuka, logo 757 KB → 30 KB WebP. Had: URL `#catalogue?motor=ID` ialah hash, jadi Google mengindeks satu halaman sahaja dan pratonton WhatsApp untuk setiap motor kekal pratonton umum.

Rollout tambahan selepas `pos.sql`: `invoice-profile.sql`, `vehicle-quick-sale.sql`. `tests/run-pos-sql.mjs` kini menjalankan 23 migrasi dan empat regresi SQL.

## Kalkulator pinjaman & 10 gambar (28 November 2026) — pending production rollout

- **Kalkulator ansuran** dalam profil motosikal katalog: deposit (Tiada/10/20/30% atau amaun sendiri), tempoh 1–N tahun, kadar rata setahun. Kaedah kadar rata: faedah = pinjaman × kadar × tahun; bayaran bulanan dibundarkan ke atas. Butang WhatsApp menghantar anggaran pelanggan kepada kedai. Paparan bertanda "anggaran sahaja"; tidak dipaparkan untuk stok Sold.
- Owner menetapkan **kadar asal, deposit asal dan tempoh maksimum** di Inventori → Tetapan katalog. Kalkulator **tersembunyi sehingga owner menetapkan kadar** — tiada kadar rekaan dipaparkan.
- **Gambar setiap motosikal: 5 → 10** (borang, validasi dan guard database).

Rollout: `supabase/catalogue-loan-and-photos.sql` selepas `vehicle-quick-sale.sql`. Sebelum migrasi, tetapan kalkulator memaparkan nota migrasi dan simpanan foto ke-6 hingga ke-10 ditolak oleh database dengan mesej "Maksimum 5 gambar".

## Servis/repair melalui POS & inventori alat ganti (28 November 2026) — pending production rollout

Keputusan operasi: kerja repair baharu tidak lagi melalui aliran Garage (Baharu → Dalam kerja → Siap → Diserahkan). Repair direkod terus sebagai jualan **Servis / repair** di POS.

- **POS → Kaunter → Servis / repair:** no. plat (wajib), motosikal, mekanik, odometer dan kerja dibuat; alat ganti dipilih dari senarai produk (stok ditolak) dan **Upah kerja** boleh ditambah oleh mana-mana staf "POS: jual". Item bebas lain masih memerlukan "POS: urus". Bayaran penuh semasa selesai, seperti jualan POS lain.
- Taip no. plat → servis lepas dipaparkan dan nama, telefon serta motosikal diisi automatik.
- **Jualan → Sejarah servis motosikal:** cari ikut plat, telefon atau nama, merentas semua tarikh.
- Resit 80mm dan **Invois A4** memaparkan butiran servis serta jenis setiap item (alat ganti / upah).
- Accounting: kategori **Bayaran servis**, penerangan "Servis · motosikal plat".
- **Inventori → Alat ganti:** stok alat ganti (produk POS yang sama): tambah, terima stok, laras, stok rendah, nilai stok. Akses mengikut "POS: urus" (urus) atau "POS: jual" (lihat).
- **Garaj (lama)** kekal di hujung menu untuk menyelesaikan job dan baki pelanggan lama; butang job baharu kini membuka Servis di POS. Tiada data dipadam.

Rollout: `supabase/pos-service.sql` selepas `catalogue-loan-and-photos.sql`. Ujian: `tests/pos-service.sql` (dalam `tests/run-pos-sql.mjs`, 25 migrasi).

### Audit 28 November 2026 — pembetulan
- Upah kerja ditaip sendiri oleh staf tanpa "POS: urus" dihadkan setiap baris (asal RM300; owner ubah di Tetapan katalog → POS: had upah kerja). Laporan tutup kaunter memaparkan alat ganti vs upah, dan upah ikut mekanik (bilangan servis dan jumlah upah). Yang merekod jualan dan servis ialah admin kaunter; mekanik tidak perlu akaun.
- Carian plat tidak lagi mengisi nama/telefon pelanggan secara senyap; staf tekan "Guna pelanggan lepas" selepas mengesahkan pemilik.
- Kos alat ganti menggunakan purata berwajaran semasa terima stok (bukan harga terakhir).
- Ringkasan owner kini merangkumi jualan POS & servis, untung kasar POS dan kutipan POS.
- Invois A4 jualan dibatalkan menunjukkan baki RM0 dan amaun dipulangkan.

## Alat ganti untuk persediaan motor & katalog lebih ringan (28 November 2026) — pending production rollout

- Rekod motosikal (Inventori) → **Alat ganti untuk motor ini → Ambil dari stok**: stok alat ganti ditolak dan kos (harga kos purata) dicampur ke kos persediaan, jadi untung kasar motor tepat. **Pulangkan** mengembalikan stok dan membuang kos itu. Baris ini dikunci dalam borang edit motor; database memastikan ia sentiasa sepadan dengan ledger stok (`supabase/vehicle-parts.sql`, RPC `vehicle_use_part` / `vehicle_return_part`, invoker). Staf "Inventori: edit" boleh menggunakannya tanpa akses POS dan boleh membaca ledger stok penuh.
- Kod admin (borang, bayaran, tetapan, jual motor, alat ganti, akses staf) dan validasi (zod) dimuat hanya apabila diperlukan. Fail JS utama katalog: 873 KB → 671 KB (257 KB → 199 KB dimampatkan).

Rollout: `supabase/vehicle-parts.sql` selepas `pos-service.sql`. Ujian: `tests/vehicle-parts.sql` (dalam `tests/run-pos-sql.mjs`, 26 migrasi).

### Audit 28 November 2026 (3) — pembetulan
- `supabase/vehicle-parts-hardening.sql` (selepas `vehicle-parts.sql`; menggantikan `vehicle-parts-note-fix.sql`): pergerakan stok "untuk motor" hanya melalui butang Ambil dari stok / Pulangkan, bukan terus melalui API; nota stok motor >9999 tidak terpotong.
- Muat semula automatik selepas deploy hanya apabila fail lama benar-benar tiada (404) dan peranti dalam talian; jika sambungan terputus, paparan meminta semak internet.
- Resit dinomborkan ikut bayaran terkini (RES-PAY-xxxx); invois garaj lama memaparkan "Tarikh job dibuka".
- Tukar troli dari Servis ke Jualan kaunter membuang upah kerja bagi akaun tanpa "POS: urus".
- PWA dipasang pelanggan dibuka di katalog (start_url `#catalogue`).
- **POS → hantar invois PDF ke WhatsApp:** dalam butiran jualan, "Sediakan PDF" → (1) Buka WhatsApp: chat pelanggan dibuka dengan mesej ringkas, walaupun nombor belum disimpan; (2) Kongsi PDF (telefon) atau Muat turun PDF (komputer, seret ke WhatsApp Web). WhatsApp tidak membenarkan laman web melampirkan fail secara automatik; penghantaran automatik memerlukan WhatsApp Business API (berbayar).
