# Multi-account Accounting verification — 13 October 2026

Owner setup: Accounting → Akaun → rename the existing Bank utama or add Maybank/CIMB/e-wallet. Confirm the opening balance before that day's transactions. No real bank names, account numbers or balances were seeded.

## Implemented

- Separate named accounts, optional bank/provider and account reference, one-time opening balance, optimistic settings updates, archive without deleting history.
- Inter-account transfers excluded from aggregate cash flow.
- Card settlement date and explicit fee; net bank balance, gross customer receipt and fee remain distinguishable. Unmatched payments are available across all months (oldest 200 first), including historical payments.
- Future payment timestamps rejected by the server and client.
- Customer balances include approved Garage invoices after collection; unsold stock and unapproved service estimates are excluded. Staff can receive the final payment on a collected job. WhatsApp opens a draft for manual sending.
- Manual expense payments can link to a stock purchase, stock preparation or service job. Reversals preserve the link and reduce paid cost totals; existing cash receipts are projected once, without copying them into the ledger.
- Optional per-unit service cost: blank means unknown; zero means explicitly no cost. Internal cost corrections do not change customer approval or a collected invoice's commercial items. Only owner can set/change costs.
- Owner may document a missing receipt reason. Reviewed expenses with a valid exemption leave the pending queue.
- Statement/cash closing-balance comparisons on a chosen date, with dynamically recomputed system balance. They do not post an automatic adjustment.
- 30-second request caching; invalidation on writes/auth changes. No polling or realtime subscription added.

## Verification

- PASS: 32 Node tests, including net card receipts, receipt exemption and CSV field separation.
- PASS: TypeScript and Vite production build.
- PASS: tests/accounting-accounts-v2.sql — synthetic Maybank/CIMB balances, transfers, gross RM100 / fee RM3 / net RM97, settlement date/month, historical unmatched payments, locked openings with editable metadata, future-date rejection, idempotent cost postings, linked reversal, service costs, collected customer debt, final payment by Garage staff, receipt exemption, zero-difference statement comparison, archived account restrictions, owner/staff/disabled/anonymous isolation.
- PASS: existing tests/accounting.sql regression suite.
- PASS: post-test database inspection: original 1 vehicle; no jobs/payments/manual ledger entries/reconciliations or test bank accounts; owner access retained; actual opening balances remain unset. All SQL fixtures rolled back. Postgres sequences may advance during rolled-back tests.
- Security advisor: no new database/RLS issues. Existing leaked-password protection warning remains; remediation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- Browser: owner Accounting route correctly displays the login gate without a session. Authenticated owner form interactions, physical receipt uploads and phone viewport geometry were not end-to-end browser tested. Responsive grid/tab rules were adjusted and compiled.

## Deployment / migration

Existing installations: apply accounting-accounts-v2.sql after accounting.sql, then service-cost-invoice-guard.sql. The consolidated v2 file already contains the final service-cost variable and snapshot fixes. service-cost-guard-fix.sql and accounting-unmatched-queue.sql record production follow-ups; they are not required again when applying the final v2 file to a fresh baseline.

## Boundaries

This remains a cashbook with cost comparisons and item margins, not a complete profit-and-loss or supplier debt subledger. Cost/payment differences can include unlinked historical payments and are labelled accordingly. Bank checking compares closing balances; it does not import or match each statement line. Full spare-parts stock purchasing/consumption is a separate module and was not added. Receipt attachments remain preserved; document replacement/removal is not part of this upgrade.
