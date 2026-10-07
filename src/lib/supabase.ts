import {RequestCache} from './request-cache';
import {createClient} from '@supabase/supabase-js';
const url=(import.meta.env.VITE_SUPABASE_URL as string|undefined)||'https://jvmqpucsbeddusqrgsyt.supabase.co';
// Publishable browser key; access is enforced by database RLS.
const key=(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string|undefined)||"sb_publishable_bVNc8hZtUwHNlNlBFyzdmw_EDhmswnX";
let legacyRole='';if(key?.split('.').length===3){try{legacyRole=JSON.parse(atob(key.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))).role}catch{legacyRole='invalid'}}
if(key?.startsWith('sb_secret_')||legacyRole==='service_role')throw new Error('Secret keys must not be used in frontend configuration.');
export const supabase=url&&key?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
import type {StaffProfile} from './staff';
export type {StaffRole} from './staff';
async function fetchStaff(){if(!supabase)return null;const {data,error}=await supabase.auth.getUser();if(error||!data.user)return null;const {data:profile,error:profileError}=await supabase.from('staff').select('id,display_name,role,enabled,permissions,payment_limit,must_change_password,version').eq('id',data.user.id).eq('enabled',true).maybeSingle();if(profileError)throw new Error('Akses pengguna belum dapat disahkan. Cuba semula.');return profile as StaffProfile|null;}
const staffCache=new RequestCache<Awaited<ReturnType<typeof fetchStaff>>>(15_000);
supabase?.auth.onAuthStateChange(()=>staffCache.clear());
export function getStaff(force=false){if(force)staffCache.clear();return staffCache.get('verified-staff',fetchStaff)}

export async function manageStaff(input:Record<string,unknown>){if(!supabase)throw Error('Sistem belum tersedia.');const {data,error}=await supabase.functions.invoke('manage-staff',{body:input});if(error){let message='Operasi akses staf gagal. Cuba semula.';try{const result=await (error as any).context?.json();if(result?.error)message=result.error}catch{}throw Error(message)}if(data?.error)throw Error(data.error);staffCache.clear();return data}
