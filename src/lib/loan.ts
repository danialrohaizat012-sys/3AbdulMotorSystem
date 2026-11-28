// Motorcycle hire-purchase estimate using the flat-rate method common in Malaysia:
// interest = loan × rate × years, spread evenly over the months. Integer cents.
export type LoanSettings={rateBp:number|null;downPct:number;maxMonths:number};
export const TENURES=[12,24,36,48,60,72,84,96,108,120];

export function loanSettings(s:{loanRateBp?:number|null;loanDownPct?:number;loanMaxMonths?:number}|null|undefined):LoanSettings{
 const rate=s?.loanRateBp;
 return {rateBp:typeof rate==='number'&&rate>=0&&rate<=3000?rate:null,downPct:Number.isInteger(s?.loanDownPct)&&s!.loanDownPct!>=0&&s!.loanDownPct!<=90?s!.loanDownPct!:10,
  maxMonths:TENURES.includes(s?.loanMaxMonths as number)?s!.loanMaxMonths!:60};
}
export const tenureOptions=(maxMonths:number)=>TENURES.filter(m=>m<=maxMonths);
/** Down payment in cents for a percentage, rounded to the nearest ringgit. */
export const downFor=(price:number,pct:number)=>Math.round(price*pct/100/100)*100;

export function flatRateLoan(price:number,down:number,rateBp:number,months:number){
 const d=Math.min(Math.max(0,Math.round(down)),price);const loan=price-d;
 const interest=Math.round(loan*rateBp/10000*months/12);
 const total=loan+interest;const monthly=months>0?Math.ceil(total/months):0;
 return {down:d,loan,interest,total,monthly,months,ratePct:rateBp/100};
}
/** Flat yearly rate (basis points) as the monthly rate lenders such as AEON quote, e.g. 1000 -> "0.833". */
export const monthlyRateText=(rateBp:number)=>(rateBp/12/100).toFixed(3).replace(/0$/,'');
/** Parses "5.5" / "5,5" (% per year) into basis points; NaN when outside 0–30%. */
export function parseRate(text:string){const v=Number(text.replace(',','.').trim());if(!text.trim()||!Number.isFinite(v)||v<0||v>30)return NaN;return Math.round(v*1000)/10}
