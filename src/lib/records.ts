import {RequestCache} from './request-cache';
import {preparePhoto} from './photo';
import {supabase,getStaff} from './supabase';
import {vehicle,job} from './validation';
import type {Vehicle,Job} from './motor';
export function mapRow(row:Record<string,unknown>):Vehicle|Job{const data:Record<string,unknown>={};for(const [k,v]of Object.entries(row)){data[k.replace(/_([a-z])/g,(_,l:string)=>l.toUpperCase())]=['items','inspection'].includes(k)?JSON.stringify(v):v;}return data as Vehicle|Job;}
const recordCache=new RequestCache<(Vehicle|Job)[]>(30_000);
const photoCache=new RequestCache<Record<string,string>>(45*60_000);
function clearCaches(){recordCache.clear();photoCache.clear()}
supabase?.auth.onAuthStateChange(event=>{if(['SIGNED_IN','SIGNED_OUT','USER_UPDATED'].includes(event))clearCaches()});
async function signPhotos(paths:string[]){
 if(!supabase||!paths.length)return {} as Record<string,string>;
 const unique=[...new Set(paths)].sort();
 return photoCache.get(JSON.stringify(unique),async()=>{
  const {data,error}=await supabase!.storage.from('vehicle-photos').createSignedUrls(unique,3600);
  if(error)throw Error('Foto gagal dimuatkan. Cuba muat semula.');
  return Object.fromEntries((data??[]).filter(p=>p.signedUrl&&p.path).map(p=>[p.path!,p.signedUrl!]));
 });
}
export async function loadRecords(kind:string,force=false):Promise<(Vehicle|Job)[]>{
 if(!supabase){if(kind==='catalogue')return [];throw new Error('Sistem sedang disediakan. Sila hubungi pentadbir.');}
 if(!['catalogue','vehicles','jobs'].includes(kind))throw Error('Rekod tidak sah.');
 if(force)recordCache.clear();
 const result=await recordCache.get(kind,async()=>{
  const {data,error}=await supabase!.from(kind).select('*').order('id',{ascending:false});
  if(error)throw Error('Rekod gagal dimuatkan. Cuba semula.');
  const mapped=(data??[]).map(mapRow);
  const urls=await signPhotos(mapped.flatMap(r=>'photo'in r&&r.photo?[r.photo]:[]));
  return mapped.map(r=>'photo'in r&&r.photo?{...r,photo:urls[r.photo]??''}:r);
 });
 return result.map(r=>({...r}));
}
export async function saveRecord(kind:'vehicles'|'jobs',value:Vehicle|Job,update:boolean){if(!supabase)throw Error('Sistem belum tersedia.');if(!await getStaff())throw Error('Akses admin tidak dibenarkan.');let candidate={...value};if('photo'in candidate&&candidate.photo.startsWith('https://')){const path=candidate.photo.split('/vehicle-photos/')[1]?.split('?')[0];if(!path)throw Error('Foto tidak sah.');candidate={...candidate,photo:decodeURIComponent(path)};}
const parsed=(kind==='vehicles'?vehicle:job).safeParse(candidate);if(!parsed.success)throw Error(parsed.error.issues[0]?.message||'Semak maklumat.');const payload:Record<string,unknown>={};for(const [k,v]of Object.entries(parsed.data)){payload[k.replace(/[A-Z]/g,m=>'_'+m.toLowerCase())]=['items','inspection'].includes(k)?JSON.parse(v as string):k==='published'?!!v:v;}
const query=update?supabase.from(kind).update(payload).eq('id',value.id):supabase.from(kind).insert(payload);const {data,error}=await query.select('id').single();if(error)throw Error('Rekod gagal disimpan. Semak akses dan maklumat, kemudian cuba semula.');recordCache.clear();return data;}
export async function uploadPhoto(file:File){
 if(!supabase)throw Error('Sistem belum tersedia.');
 const photo=await preparePhoto(file);const key=crypto.randomUUID()+(photo.type==='image/webp'?'.webp':'.jpg');
 const {error}=await supabase.storage.from('vehicle-photos').upload(key,photo,{upsert:false,cacheControl:'3600',contentType:photo.type});
 if(error)throw Error('Foto gagal dimuat naik. Cuba semula.');
 const {data,error:signedError}=await supabase.storage.from('vehicle-photos').createSignedUrl(key,3600);
 if(signedError||!data)throw Error('Foto belum dapat dipaparkan. Cuba semula.');
 return data.signedUrl;
}
