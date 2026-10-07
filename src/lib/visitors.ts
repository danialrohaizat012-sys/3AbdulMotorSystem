import {RequestCache} from './request-cache';
import {malaysiaDay} from './visitor-day';
import {supabase} from './supabase';
export type VisitorStats={today:number;total:number;day:string};
const cache=new RequestCache<VisitorStats>(300000);
let fallbackToken='';
export async function visitorStats(){return cache.get(malaysiaDay(),async()=>{if(!supabase)throw Error('Counter belum tersedia.');let token:string|null=null;const day=malaysiaDay();try{let id=localStorage.getItem('3am-visitor-id');if(!id||!/^[0-9a-f-]{36}$/.test(id)){id=crypto.randomUUID();localStorage.setItem('3am-visitor-id',id)}if(localStorage.getItem('3am-visitor-counted-day')!==day)token=id;}catch{fallbackToken||=crypto.randomUUID();token=fallbackToken}
const {data,error}=await supabase.rpc('catalogue_visit',{token});if(error)throw Error('Counter belum dapat dimuatkan.');if(token)try{localStorage.setItem('3am-visitor-counted-day',data.day)}catch{}return data as VisitorStats})}
