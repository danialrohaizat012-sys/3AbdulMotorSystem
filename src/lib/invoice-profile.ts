import {supabase} from './supabase';
import {RequestCache} from './request-cache';
import {loadSettings} from './records';
import {defaultProfile} from './invoice-model';
import type {InvoiceProfile} from './invoice-model';
const cache=new RequestCache<InvoiceProfile>(5*60_000);
supabase?.auth.onAuthStateChange(()=>cache.clear());
const fields:[keyof InvoiceProfile,string][]=[['businessName','business_name'],['registrationNo','registration_no'],['address','address'],['phone','phone'],['email','email'],['bankName','bank_name'],['bankAccountName','bank_account_name'],['bankAccountNo','bank_account_no'],['terms','terms']];
/** Loads invoice details; falls back to the catalogue WhatsApp number when the profile is not set up (or not yet migrated). */
export function loadInvoiceProfile(force=false){if(force)cache.clear();return cache.get('profile',async()=>{let profile:InvoiceProfile={...defaultProfile};let stored=false;
 if(supabase){const {data,error}=await supabase.from('invoice_profile').select('*').eq('id',1).maybeSingle();if(!error&&data){stored=true;profile={...profile,version:data.version as number};for(const [k,col] of fields)(profile as Record<string,unknown>)[k]=String(data[col]??'')}}
 if(!profile.phone){try{const s=await loadSettings();if(s.whatsappPhone)profile.phone=s.whatsappPhone}catch{}}
 return stored?profile:{...profile,version:undefined}})}
export async function saveInvoiceProfile(p:InvoiceProfile){if(!supabase)throw Error('Sistem belum tersedia.');if(p.version===undefined)throw Error('Maklumat invois belum disediakan dalam pangkalan data. Jalankan supabase/invoice-profile.sql dahulu.');
 const payload=Object.fromEntries(fields.map(([k,col])=>[col,String(p[k]??'').trim()]));
 const {data,error}=await supabase.from('invoice_profile').update(payload).eq('id',1).eq('version',p.version).select('*').maybeSingle();
 if(error)throw Error(error.code==='23514'?'Semak format e-mel atau nombor akaun bank.':'Maklumat invois belum disimpan. Hanya owner boleh mengubahnya.');if(!data)throw Error('Maklumat invois telah berubah. Tutup dan buka semula.');cache.clear()}
