# 3 Abdul Motor — audit sebelum serahan

Tarikh: 13 Oktober 2026 (Malaysia). Projek: `jvmqpucsbeddusqrgsyt`. Website: https://3abdulmotor.binalab.my/.

## Keputusan

**Lulus semakan teknikal yang dijalankan; serahan operasi memerlukan pengesahan owner dan UAT pada peranti sebenar.** Tiada isu kritikal ditemui dalam skop ujian. Keputusan ini bukan jaminan sistem bebas semua ralat. Aplikasi admin memerlukan akaun Supabase aplikasi, tanpa akaun ChatGPT.

## Bukti dan liputan

| Semakan | Hasil | Kaedah / had |
|---|---|---|
| Build production | PASS | TypeScript dan Vite; amaran bundle besar masih ada, bukan build failure. |
| Ujian automatik frontend/domain | PASS — 40/40 | Semua `tests/*.test.mjs`: wang dalam sen, CSV, cashbook, permissions, cache, template WhatsApp, offers, pagination dan visitor day Malaysia. |
| Dependency production | PASS | `pnpm audit --prod --json`: 0 kerentanan dilaporkan ketika audit. Ini tidak menggantikan audit keselamatan menyeluruh. |
| Inventori dan pembayaran | PASS | `tests/operations.sql`: deposit, baki, refund, retry, Sold hanya selepas penuh, version stale, sejarah dan audit. |
| Staff dan batas akses | PASS | `tests/staff-access.sql`: module isolation, baca sahaja, had bayaran per transaksi, disabled/temporary users, escalation, publish dan visitor deduplication. |
| Accounting asas | PASS | `tests/accounting.sql`: signed reversal, retry idempotency, deposits/refunds, transfer, opening balance lock, audit, receipt references dan RLS. |
| Accounting multi-bank / servis | PASS | `tests/accounting-accounts-v2.sql`: akaun berasingan, card net/fee/settlement, cost links, hutang job collected, reversal dan statement balance comparison. |
| Footer | PASS | `tests/footer-links.sql`: HTTPS validation, owner-only URLs, WhatsApp staff permission dan public reads. |
| Nombor stok | PASS | `tests/sequential-stock-numbers.sql`: urutan human ID, rollback reuse, immutable number dan catalogue projection. |
| Jenama / tawaran harga | PASS | `tests/brands-and-offers.sql`: normalization, duplicate brand, kategori, harga asal sah, optional ansuran, payment totals dan role isolation. |
| Freegift | PASS | `tests/catalogue-freegift.sql`: owner-only write, maximum 500 aksara, projection tepat dan clear gift. |
| Rujukan accounting >9,999 | PASS selepas fix | `tests/accounting-long-reference.sql`: `3AM-10000` dan `JOB-10000` tidak terpotong. |
| Storage resit | PASS policy check | Authenticated owner boleh INSERT metadata dengan path sebenar; anon tidak boleh membaca. Transaction rolled back; tiada physical file dimuat naik. |
| RLS / storage | PASS semakan | Kesemua 18 jadual public/private mempunyai RLS. Kedua-dua bucket private; foto awam terhad kepada published stock; resit owner-only. |
| Staff Edge Function | PASS basic live gate | `manage-staff` ACTIVE; permintaan list tanpa token menghasilkan HTTP 401. Authorization/provisioning failure paths diuji dengan mocked Edge tests. Tiada akaun staff sebenar diwujudkan semasa audit. |
| Catalogue live | PASS desktop | Satu stok sebenar, 5 foto, harga jualan/original/ansuran, professional icons, pagination satu halaman, New filter mengecualikan Pre-owned dan reset mengembalikan stok. |
| Profil / galeri live | PASS desktop | Layout dua kolum, thumbnail fit, lightbox next 1/5→2/5, close kembali ke profil, WhatsApp bar visible. |
| Pautan share live | PASS | `#catalogue?motor=32` terus membuka profil tanpa redirect login; ID asal kekal. |
| Login routes live | PASS unauthenticated gate | Inventory, Garage, Accounting dan Staff memerlukan log masuk; tiada data dalaman dipaparkan kepada pelawat. |
| PWA assets | PASS file review | Manifest standalone, scope root, start Inventory, icon 192×192, 512×512 dan Apple 180×180; HTTPS live. Install/relaunch sebenar pada iPhone/Android belum diuji. |
| Phone UI | REVIEWED / UAT PENDING | CSS responsive disemak. Headless viewport automation tidak dapat berjalan kerana executable browser ujian tiada dan download gagal. Jangan tafsir sebagai phone UAT PASS. |
| Owner browser E2E | UAT PENDING | Tiada sesi owner authenticated digunakan. Create/edit/save/upload/print melalui UI owner sebenar tidak disahkan hujung ke hujung; database dan domain tests lulus. |

Semua SQL suites menggunakan transaction rollback. Perubahan profile, counter, accounting balance, storage metadata dan rekod synthetic dibatalkan. Baseline awal: 1 vehicle, 1 catalogue, 0 jobs, 0 payments dan 0 manual accounting entries. Semakan akhir: 2 vehicles, 1 catalogue, 0 jobs, 0 payments, 0 manual accounting entries dan empat profile staff; tiada rekod synthetic tertinggal. Rekod stok kedua ditambah oleh inventory staff pada 13 Oktober 2026, 11:53:42 MYT, ketika audit berjalan. Rekod sebenar baharu ini dikekalkan; nombor paparan counter kini 2. Ujian INSERT boleh menggunakan nombor internal identity walaupun rollback; nombor paparan stock manusia menggunakan transactional counter dan kekal berurutan.

## Pembetulan semasa audit

Accounting SQL menggunakan `lpad(...,4,...)`, yang memotong digit apabila ID melebihi 9,999. Fixed kepada lebar `greatest(4,length(...))`, untuk stock number dan job ID. Migration `accounting_long_reference_fix` applied dalam projek ini; SQL dan regression disimpan dalam repo. Tiada stok, harga, staff permission atau baki pelanggan sebenar diubah.

## Owner perlu sahkan sebelum mula

1. **Tahun stok pertama:** medan tahun YAMAHA Y15 ialah 2025, tetapi keterangan menyebut Y15ZR tahun 2024. Owner perlu tentukan tahun sebenar dan betulkan melalui Inventori. Jangan teka tahun berdasarkan keterangan sahaja.
2. **Akaun kedai:** Tunai kedai dan Bank utama belum mempunyai opening balance/date. Nama bank dan akaun sebenar seperti Maybank/CIMB boleh ditambah. Tetapkan baki sebelum transaksi pada tarikh mula; opening balance dikunci selepas simpan. Tidak menetapkan baki bermaksud baki akaun masih unknown, bukannya RM0.
3. **Akaun owner:** gunakan password peribadi yang kuat; jangan serahkan password awal melalui mesej awam. Staff baharu perlu akaun individu dengan minimum permissions. Tiga profile inventory sedia ada tidak diberi permission tambahan semasa audit.
4. **UAT ringkas peranti sebenar:** owner log masuk, buka keempat-empat modul yang dibenarkan, semak satu stok dan preview, gambar/WhatsApp, serta print/save PDF. Uji install/relaunch PWA pada phone. Jangan rekod bayaran atau baki rekaan dalam production. Jika perlu transaksi ujian, gunakan persekitaran ujian berasingan atau transaksi sebenar yang memang hendak direkod.

## Nota keselamatan / had yang diketahui

- Supabase Security Advisor hanya mengeluarkan amaran **Leaked Password Protection Disabled**. RLS tiada warning lain ketika semakan. Feature ini belum diaktifkan; semak kelayakan plan sebelum mengubah billing. Rujukan: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.
- Performance advisor menyenaraikan 21 unused indexes (INFO) ketika data masih sedikit. Tidak dipadam kerana index membantu foreign key/rekod apabila data bertambah.
- Signed photo URL sah satu jam: menyembunyikan stok menghentikan signing awam baharu, tetapi pautan signed sedia ada tidak dibatalkan segera.
- Staff inventory/garage read access merangkumi medan kewangan dalam modul masing-masing. Permissions menghadkan module dan tindakan, bukan menyembunyikan setiap medan secara berasingan. Accounting penuh owner-only.
- PWA memerlukan internet; tiada service worker/offline financial queue. Tiada cubaan menyimpan perubahan kewangan offline.
- Accounting ialah cashbook dan integrasi kutipan/cost/debts, bukan tax returns, full accrual P&L atau bank statement matching automatik. Monthly account balance comparison tersedia; bank transaction import tidak tersedia.
- Pagination memaparkan 10 stok; metadata catalogue masih dibaca/cached sebagai satu set untuk carian dan sorting. Cover image lazy-loaded; gambar tersembunyi di halaman lain tidak dirender. Ini tidak menaikkan quota free Supabase.
- Upload browser dikecilkan ≤256 KiB setiap foto, maksimum 5/stock; server bucket foto masih membenarkan fail sehingga 5 MiB. Quota sebenar bergantung trafik/foto. Tiada polling/Realtime, cache record 30s dan signing 45 min.
- Backup/export operasi database dan fail Storage serta recovery drill tidak dijalankan dalam audit ini. Audit bukan sijil disaster recovery.

## Pautan serahan

- Catalogue: https://3abdulmotor.binalab.my/#catalogue
- Inventory: https://3abdulmotor.binalab.my/#inventory
- Garage: https://3abdulmotor.binalab.my/#garage
- Accounting: https://3abdulmotor.binalab.my/#accounting
- Staff access (owner): https://3abdulmotor.binalab.my/#staff

## Apabila customer melaporkan isu

Minta nama halaman, langkah sebelum error, mesej tepat/screenshot, masa berlaku dan peranti/browser. Jangan minta password atau token. Untuk bayaran yang kelihatan gagal, semak sejarah transaksi dahulu sebelum retry supaya tidak menerima bayaran dua kali. Bezakan bug dengan feature baharu; rekod dan uji perubahan dengan data synthetic, deploy selepas lulus, dan maklumkan hasil pembetulan. Bekukan perubahan besar semasa serahan supaya versi rujukan kekal jelas.
