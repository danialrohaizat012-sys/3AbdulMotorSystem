import {useState} from 'react';
import {Calculator,MessageCircle} from 'lucide-react';
import {money} from '@/lib/motor';
import type {Vehicle} from '@/lib/motor';
import type {BusinessSettings} from '@/lib/business';
import {loanSettings,tenureOptions,downFor,flatRateLoan,parseRate,monthlyRateText} from '@/lib/loan';

/** Customer-facing hire-purchase estimate. Hidden until the owner sets a default rate. */
export function LoanCalculator({vehicle,settings}:{vehicle:Vehicle;settings:BusinessSettings|null}){
 const cfg=loanSettings(settings);
 const options=tenureOptions(cfg.maxMonths);
 const [down,setDown]=useState(()=>downFor(vehicle.price,cfg.downPct));
 const [downText,setDownText]=useState(()=>String(downFor(vehicle.price,cfg.downPct)/100));
 const [months,setMonths]=useState(()=>options.includes(36)?36:options[options.length-1]);
 const [rateText,setRateText]=useState(()=>cfg.rateBp===null?'':String(cfg.rateBp/100));
 if(cfg.rateBp===null||vehicle.status==='sold'||vehicle.price<=0)return null;
 const rateBp=parseRate(rateText);const validRate=!Number.isNaN(rateBp);
 const r=flatRateLoan(vehicle.price,down,validRate?rateBp:cfg.rateBp,months);
 const setDownCents=(c:number)=>{const v=Math.min(Math.max(0,c),vehicle.price);setDown(v);setDownText(String(v/100))};
 const phone=settings?.whatsappPhone||'';
 const wa=/^[1-9][0-9]{7,14}$/.test(phone)?'https://wa.me/'+phone+'?text='+encodeURIComponent('Hi 3 Abdul Motor, saya berminat dengan pembiayaan '+vehicle.brand+' '+vehicle.model+' ('+vehicle.year+'), harga '+money(vehicle.price)+'. Anggaran saya: deposit '+money(r.down)+', '+r.months+' bulan, lebih kurang '+money(r.monthly)+'/bulan. Boleh bantu semak kelayakan?'):'';
 return <section className="loan-calculator" aria-labelledby={'loan-'+vehicle.id}>
  <h3 id={'loan-'+vehicle.id}><Calculator size={18}/>Kira ansuran bulanan</h3>
  <div className="loan-result" aria-live="polite"><span>Anggaran bayaran</span><strong>{money(r.monthly)}<small> / bulan</small></strong><p>{r.months} bulan · pinjaman {money(r.loan)}</p></div>
  <div className="loan-field"><label htmlFor={'loan-down-'+vehicle.id}>Deposit (RM)</label><input id={'loan-down-'+vehicle.id} inputMode="decimal" value={downText} onChange={e=>{setDownText(e.target.value);const v=Math.round(Number(e.target.value.replace(/[^0-9.]/g,''))*100);if(Number.isFinite(v))setDown(Math.min(Math.max(0,v),vehicle.price))}}/>
   <div className="loan-chips" role="group" aria-label="Deposit cepat">{[0,10,20,30].map(p=><button type="button" key={p} aria-pressed={down===downFor(vehicle.price,p)} onClick={()=>setDownCents(downFor(vehicle.price,p))}>{p===0?'Tiada':p+'%'}</button>)}</div></div>
  <div className="loan-field"><span className="loan-label">Tempoh</span><div className="loan-chips" role="radiogroup" aria-label="Tempoh pinjaman">{options.map(m=><button type="button" role="radio" key={m} aria-checked={months===m} aria-pressed={months===m} onClick={()=>setMonths(m)}>{m/12} thn</button>)}</div></div>
  <div className="loan-field loan-rate"><label htmlFor={'loan-rate-'+vehicle.id}>Kadar rata setahun (%)</label><input id={'loan-rate-'+vehicle.id} inputMode="decimal" value={rateText} onChange={e=>setRateText(e.target.value)} aria-invalid={!validRate}/>{validRate?<small className="loan-monthly">≈ {monthlyRateText(rateBp)}% sebulan (cara pembiaya seperti AEON memaparkan kadar)</small>:<small className="form-error">Masukkan kadar 0–30%.</small>}</div>
  <dl className="loan-breakdown"><div><dt>Harga</dt><dd>{money(vehicle.price)}</dd></div><div><dt>Deposit</dt><dd>-{money(r.down)}</dd></div><div><dt>Jumlah pinjaman</dt><dd>{money(r.loan)}</dd></div><div><dt>Faedah ({r.ratePct}% setahun · {monthlyRateText(r.ratePct*100)}% sebulan × {r.months} bln)</dt><dd>{money(r.interest)}</dd></div><div className="loan-total"><dt>Jumlah bayaran balik</dt><dd>{money(r.total)}</dd></div></dl>
  <p className="loan-note">Anggaran sahaja menggunakan kadar rata. Kadar sebenar, deposit dan kelulusan tertakluk kepada bank atau syarikat pembiayaan.</p>
  {wa&&<a className="btn subtle loan-ask" target="_blank" rel="noopener noreferrer" href={wa}><MessageCircle size={16}/>Tanya pembiayaan di WhatsApp</a>}
 </section>;
}
