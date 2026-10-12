import {supabase,getStaff} from './supabase';
import {RequestCache} from './request-cache';
import {preparePhoto} from './photo';
export type AccountingKind='income'|'expense'|'capital'|'drawings'|'transfer'|'adjustment';
export type CashAccount='cash'|'bank';
export type AccountingEntry={source_key:string;source_id:number;source:'Manual'|'Inventori'|'Garaj';entry_date:string;kind:AccountingKind;amount:number;account_id:CashAccount|null;to_account_id:CashAccount|null;category:string;description:string;counterparty:string;reference:string;note:string;created_at:string;created_by:string;vehicle_id:number|null;job_id:number|null;reversal_of:number|null;voided:boolean;reviewed:boolean;version:number;receipt_count:number};
export type AccountingAccount={id:CashAccount;name:string;opening_balance:number|null;opening_on:string|null;balance:number|null};
export type AccountingSnapshot={asOf:string;accounts:AccountingAccount[];summary:{income:number;expense:number;net:number;capital:number;drawings:number;refunds:number;adjustments:number};unassignedTotal:number;unassignedCount:number;pendingCount:number;audit:{id:number;table_name:string;record_key:string;action:string;actor:string;created_at:string}[]};
export type AccountingData={entries:AccountingEntry[];snapshot:AccountingSnapshot};
export type EntryInput={date:string;kind:AccountingKind;amount:number;account:CashAccount;toAccount?:CashAccount;category:string;description:string;counterparty:string;reference:string;note:string};
export {expenseCategories,kindLabels,todayKL,entryMovement,needsAttention,parseMoney,accountingCsv} from './accounting-model';
function client(){if(!supabase)throw Error('Sistem belum tersedia.');return supabase}
function message(error:{code?:string;message?:string}){return error.code==='P0001'?error.message||'Semak transaksi.':'Operasi Accounting gagal. Semak akses dan cuba semula.'}
const cache=new RequestCache<AccountingData>(30_000);
supabase?.auth.onAuthStateChange(()=>cache.clear());
export async function loadAccounting(month:string,force=false){if(force)cache.clear();if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))throw Error('Bulan tidak sah.');return cache.get(month,async()=>{
 const {data:snapshot,error}=await client().rpc('accounting_snapshot',{p_month:month+'-01'});if(error)throw Error(message(error));
 const entries:AccountingEntry[]=[];for(let offset=0;;offset+=200){const {data,error}=await client().rpc('accounting_feed',{p_month:month+'-01',p_before:snapshot.asOf}).range(offset,offset+199);if(error)throw Error(message(error));entries.push(...(data as AccountingEntry[]));if(data.length<200)break;}
 return {snapshot:snapshot as AccountingSnapshot,entries};
})}
export async function postEntry(requestId:string,input:EntryInput){const {data,error}=await client().rpc('accounting_post',{p_request:requestId,p_data:input});if(error)throw Error(message(error));cache.clear();return data as number}
export async function reverseEntry(e:AccountingEntry,requestId:string,date:string,reason:string){if(e.source!=='Manual')throw Error('Refund pelanggan perlu direkodkan melalui rekod Inventori atau Garage asal.');const {data,error}=await client().rpc('accounting_reverse',{p_id:e.source_id,p_request:requestId,p_date:date,p_reason:reason});if(error)throw Error(message(error));cache.clear();return data as number}
export async function annotateEntry(e:AccountingEntry,account:CashAccount|null,reviewed:boolean,reason:string){const {error}=await client().rpc('accounting_annotate',{p_key:e.source_key,p_version:e.version,p_account:e.source==='Manual'?null:account,p_reviewed:reviewed,p_reason:reason});if(error)throw Error(message(error));cache.clear()}
export async function configureAccount(id:CashAccount,balance:number,date:string){const {data,error}=await client().from('accounting_accounts').update({opening_balance:balance,opening_on:date}).eq('id',id).is('opening_on',null).select('id').maybeSingle();if(error)throw Error(message(error));if(!data)throw Error('Baki awal telah ditetapkan oleh pengguna lain. Muat semula.');cache.clear()}
export type Receipt={id:string;storage_path:string;original_name:string;created_at:string};
export async function loadReceipts(key:string){const {data,error}=await client().from('accounting_receipts').select('id,storage_path,original_name,created_at').eq('source_key',key).order('created_at');if(error)throw Error(message(error));return data as Receipt[]}
export async function uploadReceipt(key:string,file:File){const staff=await getStaff();if(staff?.role!=='owner')throw Error('Akses owner diperlukan.');let blob:Blob;
 if(file.type==='application/pdf'){if(file.size>2*1024*1024||file.size===0)throw Error('PDF mesti di bawah 2 MB.');if(new TextDecoder().decode(await file.slice(0,5).arrayBuffer())!=='%PDF-')throw Error('Fail PDF tidak sah.');blob=file}else blob=await preparePhoto(file);
 const extension=blob.type==='application/pdf'?'pdf':blob.type==='image/webp'?'webp':'jpg';const path=staff.id+'/'+crypto.randomUUID()+'.'+extension;
 const {error}=await client().storage.from('accounting-receipts').upload(path,blob,{upsert:false,contentType:blob.type,cacheControl:'3600'});if(error)throw Error('Resit gagal dimuat naik. Cuba semula.');
 const {error:attachError}=await client().from('accounting_receipts').insert({source_key:key,storage_path:path,original_name:file.name.slice(0,180)||'Resit',created_by:staff.id});if(attachError){const {data:attached}=await client().from('accounting_receipts').select('id').eq('storage_path',path).maybeSingle();if(!attached){await client().storage.from('accounting-receipts').remove([path]);throw Error('Resit belum dapat dilampirkan. Transaksi asal kekal. Cuba lampir semula.')}}cache.clear()}
export async function openReceipt(path:string){const {data,error}=await client().storage.from('accounting-receipts').createSignedUrl(path,120);if(error)throw Error('Resit tidak dapat dibuka.');return data.signedUrl}
