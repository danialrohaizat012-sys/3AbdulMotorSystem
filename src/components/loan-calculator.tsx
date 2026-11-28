import {useState} from 'react';
import {money} from '@/lib/motor';
import type {Vehicle} from '@/lib/motor';
import type {BusinessSettings} from '@/lib/business';
import {loanSettings,tenureOptions,flatRateLoan,parseRate,monthlyRateText} from '@/lib/loan';

export function LoanCalculator({vehicle,settings}:{vehicle:Vehicle;settings:BusinessSettings}){
 const config=loanSettings(settings);
 const terms=tenureOptions(config.maxMonths);
 const [priceText,setPrice]=useState(String(vehicle.price/100));
 const [depositText,setDeposit]=useState(String(config.downPct));
 const [rateText,setRate]=useState(config.rateBp===null?'':String(config.rateBp/100));
 const [months,setMonths]=useState(terms.includes(36)?36:terms[terms.length-1]);
 const price=Math.round(Number(priceText)*100);
 const deposit=Number(depositText);
 const rate=parseRate(rateText);
 const priceValid=priceText!==''&&Number.isSafeInteger(price)&&price>0;
 const depositValid=depositText!==''&&Number.isFinite(deposit)&&deposit>=0&&deposit<=100;
 const rateValid=Number.isFinite(rate);
 const estimate=priceValid&&depositValid&&rateValid
  ? flatRateLoan(price,price*deposit/100,rate,months)
  : null;

 return <section className="loan-estimator" aria-label="Anggaran ansuran">
  <div className="loan-estimator-fields">
   <label>Harga motosikal (RM)<input type="number" inputMode="decimal" min="0.01" step="0.01" value={priceText} onChange={e=>setPrice(e.target.value)} aria-invalid={!priceValid}/></label>
   <label>Deposit (%)<input type="number" inputMode="decimal" min="0" max="100" step="any" value={depositText} onChange={e=>setDeposit(e.target.value)} aria-invalid={!depositValid}/></label>
   <label>Kadar rata setahun (%)<input type="number" inputMode="decimal" min="0" max="30" step="0.001" value={rateText} onChange={e=>setRate(e.target.value)} aria-invalid={!rateValid}/>{rateValid&&<small>{monthlyRateText(rate)}% sebulan</small>}</label>
   <label>Tempoh<select value={months} onChange={e=>setMonths(Number(e.target.value))}>{terms.map(term=><option key={term} value={term}>{term/12} tahun</option>)}</select></label>
  </div>
  <div className="loan-estimator-result" aria-live="polite">
   <div><span>Anggaran bulanan</span> <strong>{estimate?money(estimate.monthly):'—'}</strong></div>
   <p>{estimate?<>Pinjaman {money(estimate.loan)} · {monthlyRateText(rate)}% sebulan · {months/12} tahun</>:'Semak harga, deposit (0–100%) dan kadar tahunan (0–30%).'}</p>
  </div>
  <p className="loan-estimator-note">Anggaran sahaja. Harga <strong>tidak termasuk</strong> fi pemprosesan, PUSPAKOM (jika berkenaan), tukar nama, cukai jalan dan insurans.</p>
 </section>;
}
