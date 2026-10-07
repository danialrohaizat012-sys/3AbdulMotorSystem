import {createClient} from '@supabase/supabase-js';
const url=(import.meta.env.VITE_SUPABASE_URL as string|undefined)||'https://jvmqpucsbeddusqrgsyt.supabase.co';
// Publishable browser key; access is enforced by database RLS.
const key=(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string|undefined)||"sb_publishable_bVNc8hZtUwHNlNlBFyzdmw_EDhmswnX";
let legacyRole='';if(key?.split('.').length===3){try{legacyRole=JSON.parse(atob(key.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))).role}catch{legacyRole='invalid'}}
if(key?.startsWith('sb_secret_')||legacyRole==='service_role')throw new Error('Secret keys must not be used in frontend configuration.');
export const supabase=url&&key?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
export type StaffRole='owner'|'inventory'|'garage';
export async function getStaff(){if(!supabase)return null;const {data,error}=await supabase.auth.getUser();if(error||!data.user)return null;const {data:profile,error:profileError}=await supabase.from('staff').select('id,display_name,role,enabled').eq('id',data.user.id).eq('enabled',true).maybeSingle();if(profileError)throw new Error('Akses pengguna belum dapat disahkan. Cuba semula.');return profile;}
