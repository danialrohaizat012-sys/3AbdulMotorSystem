import {useEffect,useState,useRef} from 'react';
import {ChevronLeft,ChevronRight,Expand,Bike} from 'lucide-react';
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from './ui/dialog';
import {downFor,flatRateLoan,loanSettings,monthlyRateText} from '@/lib/loan';
import {VehicleOffer} from './vehicle-offer';
import {MotorBenefits} from './motor-benefits';
import {ShareButton} from './share-button';
import {photoPaths,signPhotos} from '@/lib/records';
import {money,conditionLabels,bikeStatuses} from '@/lib/motor';
import type {Vehicle} from '@/lib/motor';
import {whatsappLink} from '@/lib/business';
import type {BusinessSettings} from '@/lib/business';
export function CatalogueProfile({vehicle,settings,preview=false}:{vehicle:Vehicle;settings:BusinessSettings|null;preview?:boolean}){
 const href=settings?whatsappLink(settings,vehicle):'';
 return <><div className="customer-profile-scroll"><div className="customer-profile-grid"><Gallery vehicle={vehicle}/><div className="customer-profile-info"><span className={'status '+vehicle.status}>{bikeStatuses[vehicle.status]}</span><div className="detail-stats"><span>Kategori<b>{conditionLabels[vehicle.bikeCondition||'pre_owned']}</b></span><span>Tahun<b>{vehicle.year}</b></span><span>Jarak<b>{vehicle.mileage.toLocaleString()} km</b></span></div><VehicleOffer vehicle={vehicle} detail/><LoanDetails vehicle={vehicle} settings={settings}/><h3 className="profile-description-title">Tentang motosikal ini</h3><p className="description">{vehicle.description||'Hubungi kedai untuk maklumat lanjut.'}</p><MotorBenefits freegift={vehicle.freegift}/></div></div></div><div className="customer-contact-bar"><div className="customer-contact-summary"><b>{vehicle.brand} {vehicle.model}</b><span>{money(vehicle.price)} <small>harga jualan</small></span></div>{!preview&&<ShareButton id={vehicle.id}/>}<a className="btn primary" target="_blank" rel="noopener noreferrer" href={href||undefined} aria-disabled={!href} onClick={e=>{if(!href)e.preventDefault()}}>{href?'Tanya melalui WhatsApp':'WhatsApp belum ditetapkan'}</a></div></>
}
function LoanDetails({vehicle,settings}:{vehicle:Vehicle;settings:BusinessSettings|null}){
 const {rateBp,downPct,maxMonths}=loanSettings(settings);
 const terms=[24,36,48].filter(months=>months<=maxMonths);
 if(rateBp===null||vehicle.status==='sold'||vehicle.price<=0||terms.length===0)return null;
 const deposit=downFor(vehicle.price,downPct);
 return <section className="mt-5" aria-label="Butiran pinjaman">
  <h3 className="profile-description-title">Butiran pinjaman</h3>
  <div className="mt-2 rounded-xl border border-slate-600 bg-slate-900/60 p-4">
   <dl>
    <div className="flex flex-wrap items-baseline justify-between gap-x-3 border-b border-dashed border-slate-600 pb-3">
     <dt className="text-slate-300">Deposit ({downPct}%)</dt><dd className="font-bold">{money(deposit)}</dd>
    </div>
    {terms.map(months=><div key={months} className="flex flex-wrap items-baseline justify-between gap-x-3 pt-3">
     <dt className="text-slate-300">{months/12} tahun</dt>
     <dd><strong className="text-lg text-yellow-300">{money(flatRateLoan(vehicle.price,deposit,rateBp,months).monthly)}</strong> <small>/ bulan</small></dd>
    </div>)}
   </dl>
  </div>
  <p className="mt-2 text-xs text-slate-300">Anggaran pada kadar rata {monthlyRateText(rateBp)}% sebulan. Kadar dan ansuran sebenar bergantung pada pembiaya.</p>
 </section>;
}
function Gallery({vehicle}:{vehicle:Vehicle}){
 const keys=photoPaths(vehicle),signature=JSON.stringify(keys);const [urls,setUrls]=useState<Record<string,string>>({}),[active,setActive]=useState(0),[expanded,setExpanded]=useState(false),[failed,setFailed]=useState(false);const swiped=useRef(false);const touch=useRef<{x:number;y:number}|null>(null);
 useEffect(()=>{let live=true;setActive(0);setFailed(false);void signPhotos(JSON.parse(signature)).then(v=>{if(live)setUrls(v)}).catch(()=>{if(live)setFailed(true)});return()=>{live=false}},[signature]);
 const move=(direction:number)=>setActive(i=>(i+direction+keys.length)%keys.length);const src=urls[keys[active]]||(active===0?vehicle.photo:'');
 const gestures={onTouchStart:(e:React.TouchEvent)=>{swiped.current=false;touch.current={x:e.touches[0].clientX,y:e.touches[0].clientY}},onTouchEnd:(e:React.TouchEvent)=>{const start=touch.current;touch.current=null;if(!start||keys.length<2)return;const dx=e.changedTouches[0].clientX-start.x,dy=e.changedTouches[0].clientY-start.y;if(Math.abs(dx)>50&&Math.abs(dx)>Math.abs(dy)*1.3){swiped.current=true;move(dx<0?1:-1)}}};
 const controls=keys.length>1?<div className="gallery-controls"><button type="button" aria-label="Foto sebelumnya" onClick={()=>move(-1)}><ChevronLeft size={20}/></button><span aria-live="polite">{active+1} / {keys.length}</span><button type="button" aria-label="Foto seterusnya" onClick={()=>move(1)}><ChevronRight size={20}/></button></div>:null;
 return <div className="customer-gallery"><button className="customer-main-photo" aria-label="Besarkan gambar motosikal" disabled={!src} onClick={()=>{if(!swiped.current)setExpanded(true);swiped.current=false}} {...gestures}>{src?<img src={src} alt={vehicle.brand+' '+vehicle.model+' · Foto '+(active+1)}/>:<div className="gallery-placeholder"><Bike size={48}/><span>{failed?'Foto belum dapat dimuatkan':keys.length?'Memuatkan foto…':'Foto belum tersedia'}</span></div>}{src&&<span className="gallery-expand"><Expand size={16}/> Besarkan</span>}</button>{controls}{keys.length>1&&<div className="customer-thumbnails">{keys.map((key,i)=><button key={key} aria-label={'Pilih foto '+(i+1)} aria-pressed={active===i} onClick={()=>setActive(i)}>{urls[key]?<img src={urls[key]} alt={'Foto '+(i+1)} loading="lazy"/>:<span>{i+1}</span>}</button>)}</div>}<Dialog open={expanded} onOpenChange={setExpanded}><DialogContent className="customer-lightbox" onKeyDown={e=>{if(keys.length>1&&(e.key==='ArrowLeft'||e.key==='ArrowRight')){e.preventDefault();move(e.key==='ArrowLeft'?-1:1)}}}><DialogHeader><DialogTitle>{vehicle.brand} {vehicle.model}</DialogTitle><DialogDescription>Galeri motosikal · Gunakan anak panah atau swipe untuk tukar foto.</DialogDescription></DialogHeader><div className="lightbox-photo" {...gestures}>{src&&<img src={src} alt={'Foto '+(active+1)+' motosikal '+vehicle.model}/>}</div>{controls}</DialogContent></Dialog></div>
}
