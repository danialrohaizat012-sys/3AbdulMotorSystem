import type {Vehicle} from './motor';
export type BusinessSettings={id:number;whatsappPhone:string;whatsappTemplate:string;version:number};
export const defaultTemplate='Hi 3 Abdul Motor, saya berminat dengan {jenama} {model} ({tahun}), harga {harga}, status {status}. Boleh saya dapatkan maklumat lanjut? {link}';
export function stockLink(id:number){return location.origin+location.pathname+'#catalogue?motor='+id}
export function normalizePhone(value:string){let phone=value.replace(/[^0-9]/g,'');if(phone.startsWith('0'))phone='60'+phone.slice(1);return phone}
export function whatsappMessage(template:string,v:Pick<Vehicle,'id'|'brand'|'model'|'year'|'price'|'status'>,url:string){const values:Record<string,string>={jenama:v.brand,model:v.model,tahun:String(v.year),harga:new Intl.NumberFormat('ms-MY',{style:'currency',currency:'MYR'}).format(v.price/100),status:v.status==='available'?'Available':v.status==='reserved'?'Reserved':'Sold',id:'3AM-'+String(v.id).padStart(4,'0'),link:url};return template.replace(/\{(jenama|model|tahun|harga|status|id|link)\}/g,(_,key:string)=>values[key])}
export function whatsappLink(settings:BusinessSettings,v:Vehicle){if(!/^[1-9][0-9]{7,14}$/.test(settings.whatsappPhone))return '';return 'https://wa.me/'+settings.whatsappPhone+'?text='+encodeURIComponent(whatsappMessage(settings.whatsappTemplate,v,stockLink(v.id)))}
export function normalizePlate(value:string){return value.toUpperCase().replace(/[^A-Z0-9]/g,'')}
