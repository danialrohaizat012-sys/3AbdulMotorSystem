// Runtime SEO for the public catalogue. Google renders JavaScript, so the
// structured data reflects live stock. No private fields are ever included.
import type {Vehicle} from './motor';
import type {BusinessSettings} from './business';
import {safeFooterUrl} from './business';
const SITE='https://3abdulmotor.binalab.my/';
const BASE_TITLE='3 Abdul Motor | Jual Beli Motosikal Baharu & Terpakai, Servis Motor';
const availability:Record<string,string>={available:'https://schema.org/InStock',reserved:'https://schema.org/LimitedAvailability',sold:'https://schema.org/SoldOut'};

function jsonLd(id:string,data:unknown){let el=document.getElementById(id) as HTMLScriptElement|null;if(!el){el=document.createElement('script');el.type='application/ld+json';el.id=id;document.head.appendChild(el)}el.textContent=JSON.stringify(data)}
function meta(selector:string,attr:string,value:string){const el=document.head.querySelector(selector);if(el)el.setAttribute(attr,value)}

/** Pure: schema.org ItemList of public catalogue vehicles. Exported for tests. */
export function catalogueSchema(vehicles:Vehicle[]){return {'@context':'https://schema.org','@type':'ItemList',name:'Stok motosikal 3 Abdul Motor',numberOfItems:vehicles.length,
 itemListElement:vehicles.slice(0,50).map((v,i)=>({'@type':'ListItem',position:i+1,url:SITE+'#catalogue?motor='+v.id,item:{'@type':'Motorcycle',name:v.brand+' '+v.model+' '+v.year,brand:{'@type':'Brand',name:v.brand},model:v.model,vehicleModelDate:String(v.year),
  itemCondition:v.bikeCondition==='new'?'https://schema.org/NewCondition':'https://schema.org/UsedCondition',
  ...(v.mileage?{mileageFromOdometer:{'@type':'QuantitativeValue',value:v.mileage,unitCode:'KMT'}}:{}),
  offers:{'@type':'Offer',price:(v.price/100).toFixed(2),priceCurrency:'MYR',availability:availability[v.status]||availability.available,seller:{'@id':SITE+'#business'}}}}))}}

export function businessSchema(settings:BusinessSettings){const sameAs=[settings.tiktokUrl,settings.facebookUrl].map(u=>safeFooterUrl(u)).filter(Boolean);const map=safeFooterUrl(settings.mapsUrl);
 return {'@context':'https://schema.org','@type':'MotorcycleDealer','@id':SITE+'#business','name':'3 Abdul Motor','url':SITE,'logo':SITE+'logo-320.png','image':SITE+'og-image.jpg',
  ...(/^[1-9][0-9]{7,14}$/.test(settings.whatsappPhone)?{telephone:'+'+settings.whatsappPhone}:{}),...(sameAs.length?{sameAs}:{}),...(map?{hasMap:map}:{})}}

export function publishCatalogueSeo(vehicles:Vehicle[]){if(vehicles.length)jsonLd('ld-catalogue',catalogueSchema(vehicles.filter(v=>v.status!=='sold')))}
export function publishBusinessSeo(settings:BusinessSettings){jsonLd('ld-business',businessSchema(settings))}
/** Title/description while a motorcycle profile is open; pass null to restore the catalogue defaults. */
export function setVehicleMeta(v:Vehicle|null){
 if(!v){document.title=BASE_TITLE;meta('meta[name="description"]','content','Katalog stok motosikal 3 Abdul Motor: harga, status dan gambar motor baharu & terpakai. Tanya terus melalui WhatsApp. Servis & penyelenggaraan motosikal.');return}
 const price=new Intl.NumberFormat('ms-MY',{style:'currency',currency:'MYR',maximumFractionDigits:0}).format(v.price/100);
 document.title=v.brand+' '+v.model+' '+v.year+' · '+price+' | 3 Abdul Motor';
 meta('meta[name="description"]','content',v.brand+' '+v.model+' tahun '+v.year+(v.mileage?', '+v.mileage.toLocaleString('ms-MY')+' km':'')+', harga '+price+'. '+(v.bikeCondition==='new'?'Baharu':'Terpakai')+' · 3 Abdul Motor. Tanya melalui WhatsApp.');
}
