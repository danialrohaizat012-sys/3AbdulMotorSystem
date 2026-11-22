// Optional local verifier (no production access): npm install --prefix /tmp/3am-db-test @electric-sql/pglite@0.5.14
// PGLITE_MODULE=/tmp/3am-db-test/node_modules/@electric-sql/pglite/dist/index.js node tests/run-pos-sql.mjs
// Applies every reviewed upgrade in rollout order to an in-memory PostgreSQL,
// then runs the POS and staff Accounting regressions (both roll back).
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
import {readFileSync} from 'node:fs';
const root=new URL('../',import.meta.url).pathname;
const runner=readFileSync(root+'tests/run-staff-accounting-sql.mjs','utf8');
const bootstrap=runner.match(/db\.exec\(`([\s\S]*?)`\)/)[1];
const files=['schema.sql','operations.sql','service-history.sql','guard-refinement.sql','payment-history-refinement.sql','staff-access-and-visitors.sql','staff-write-safety.sql','catalogue-projection-guard.sql','brands-and-catalogue-offers.sql','footer-links.sql','accounting.sql','accounting-accounts-v2.sql','service-cost-invoice-guard.sql','service-cost-guard-fix.sql','accounting-unmatched-queue.sql','sequential-stock-numbers.sql','stock-number-accounting-references.sql','accounting-long-reference-fix.sql','catalogue-freegift.sql','staff-accounting-access.sql','pos.sql','invoice-profile.sql','vehicle-quick-sale.sql'];
const db=new PGlite();
await db.exec(bootstrap);
for(const file of files){try{await db.exec(readFileSync(root+'supabase/'+file,'utf8'))}catch(e){console.error('FAILED',file,e.message);process.exit(1)}}
console.log('APPLIED',files.length,'migrations');
for(const test of ['pos.sql','staff-accounting-access.sql','invoice-profile.sql','vehicle-quick-sale.sql']){try{await db.exec(readFileSync(root+'tests/'+test,'utf8'));console.log('PASS',test,'(rolled back)')}catch(e){console.error('SQL TEST FAILED',test,e.message);await db.exec('rollback').catch(()=>{});process.exit(1)}}
await db.close();
