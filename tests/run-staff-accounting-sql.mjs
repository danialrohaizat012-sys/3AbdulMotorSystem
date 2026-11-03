// Optional local verifier: npm install --prefix /tmp/3am-db-test @electric-sql/pglite@0.5.14
// PGLITE_MODULE=/tmp/3am-db-test/node_modules/@electric-sql/pglite/dist/index.js node tests/run-staff-accounting-sql.mjs
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
import {readFileSync} from 'node:fs';
const root=new URL('../',import.meta.url).pathname;
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
create schema auth;create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth to public;grant execute on function auth.uid() to public;
create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,metadata jsonb,created_at timestamptz default now());
alter table storage.objects enable row level security;grant usage on schema storage to anon,authenticated;grant select,insert,delete,update on storage.objects to authenticated;grant select on storage.objects to anon;`);
const files=['schema.sql','operations.sql','service-history.sql','guard-refinement.sql','payment-history-refinement.sql','staff-access-and-visitors.sql','staff-write-safety.sql','accounting.sql','accounting-accounts-v2.sql','accounting-unmatched-queue.sql','sequential-stock-numbers.sql','stock-number-accounting-references.sql','accounting-long-reference-fix.sql','staff-accounting-access.sql'];
for(const file of files){try{await db.exec(readFileSync(root+'/supabase/'+file,'utf8'));console.log('APPLIED',file)}catch(e){console.error('FAILED',file,e.message);process.exit(1)}}
const sql=readFileSync(root+'/tests/staff-accounting-access.sql','utf8');
try{await db.exec(sql);console.log('PASS: staff Accounting SQL regression (rolled back)')}catch(e){console.error('SQL TEST FAILED',e.message);process.exit(1)}
await db.close();
