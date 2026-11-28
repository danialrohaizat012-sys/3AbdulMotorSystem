// Builds one document model used by both the A4 print page and the PDF.
// Pure (no DOM, no network) so the numbers and wording can be tested.
import type {Vehicle,Job,Payment} from './motor';
import {money,dateText,parseLines,vehicleId,jobId,jobStatuses,lineTotal} from './motor';

export type InvoiceProfile={businessName:string;registrationNo:string;address:string;phone:string;email:string;bankName:string;bankAccountName:string;bankAccountNo:string;terms:string;version?:number};
export const defaultProfile:InvoiceProfile={businessName:'3 Abdul Motor',registrationNo:'',address:'',phone:'',email:'',bankName:'',bankAccountName:'',bankAccountNo:'',terms:''};
export type DocType='invoice'|'estimate'|'receipt';
export type DocItem={no:number;description:string;detail:string;qty:number;unitPrice:number;amount:number};
export type DocLine={label:string;value:string;strong?:boolean;tone?:'due'|'paid'};
export type InvoiceDoc={meta:[string,string][];amountWords:string;thanks:string;contact:string;type:DocType;title:string;fileName:string;number:string;reference:string;issuedAt:string;status:{label:string;tone:'paid'|'partial'|'due'|'draft'|'free'};
 business:{name:string;lines:string[]};billTo:{title:string;lines:string[]};subject:{title:string;lines:string[]};
 items:DocItem[];totals:DocLine[];payments:{reference:string;date:string;method:string;receiver:string;note:string;amount:number}[];
 notes:{title:string;text:string}[];bank:string[]|null;signatures:string[]};

const methodName:Record<string,string>={cash:'Tunai',transfer:'Pindahan bank',card:'Kad'};
const purposeName:Record<string,string>={deposit:'Deposit',balance:'Bayaran baki',service:'Bayaran servis',refund:'Refund',pos:'Jualan kaunter'};
const clean=(v:unknown)=>String(v??'').trim();
/** Formats a stored Malaysian number (60123456789) as +60 12-345 6789 for print. */
export function formatPhone(value:string){const d=value.replace(/\D/g,'');if(/^60\d{9,10}$/.test(d)){const rest=d.slice(2);return '+60 '+rest.slice(0,2)+'-'+rest.slice(2,rest.length-4)+' '+rest.slice(-4)}return clean(value)}

/** Invoice dates are printed without a time, e.g. "28 November 2026". */
export const dateOnly=(iso:string|null|undefined)=>iso?new Date(iso).toLocaleDateString('ms-MY',{timeZone:'Asia/Kuala_Lumpur',day:'numeric',month:'long',year:'numeric'}):'';
const units=['','satu','dua','tiga','empat','lima','enam','tujuh','lapan','sembilan'];
function under1000(n:number){const h=Math.floor(n/100),r=n%100;const out:string[]=[];if(h)out.push(h===1?'seratus':units[h]+' ratus');
 if(r>=20)out.push(units[Math.floor(r/10)]+' puluh'+(r%10?' '+units[r%10]:''));else if(r>=12)out.push(units[r-10]+' belas');else if(r===11)out.push('sebelas');else if(r===10)out.push('sepuluh');else if(r)out.push(units[r]);return out.join(' ')}
function words(n:number){if(n===0)return 'kosong';const out:string[]=[];for(const [size,name] of [[1e9,'bilion'],[1e6,'juta'],[1e3,'ribu']] as [number,string][]){const c=Math.floor(n/size);if(c){out.push(c===1&&size===1e3?'seribu':under1000(c)+' '+name);n%=size}}if(n)out.push(under1000(n));return out.join(' ')}
const title=(s:string)=>s.replace(/(^|\s)\S/g,c=>c.toUpperCase());
/** Amount in Malay words as printed on Malaysian invoices, e.g. "Ringgit Malaysia Tujuh Ribu Lapan Ratus Sahaja". */
export function ringgitWords(cents:number){const c=Math.max(0,Math.round(cents));const rm=Math.floor(c/100),sen=c%100;return title('ringgit malaysia '+words(rm)+(sen?' dan '+words(sen)+' sen':'')+' sahaja')}
const footer=(p:InvoiceProfile,name:string)=>({thanks:'Terima kasih atas urusan anda bersama '+name+'.',contact:[p.phone&&formatPhone(p.phone),p.email].filter(Boolean).join('  ·  ')});

export function buildInvoice(record:Vehicle|Job,payments:Payment[],type:DocType,profile:InvoiceProfile,now:Date=new Date()):InvoiceDoc{
 const vehicle='brand'in record;const ref=vehicle?vehicleId(record.id,record.stockNo):jobId(record.id);
 const prefix=type==='estimate'?'ANG':type==='receipt'?'RES':'INV';
 // A receipt is numbered by its latest payment, so deposit and balance receipts differ.
 const lastPay=type==='receipt'?[...payments].filter(p=>p.amount>0).sort((a,b)=>b.id-a.id)[0]:undefined;
 const number=lastPay?'RES-PAY-'+String(lastPay.id).padStart(4,'0'):prefix+'-'+ref;
 const vehicleSubtotal=vehicle?(record.saleDiscount?record.price+record.saleDiscount:Math.max(record.price,record.originalPrice??0)):0;
 const items:DocItem[]=vehicle?[{no:1,description:record.brand+' '+record.model,detail:[record.bikeCondition==='new'?'Baharu':'Terpakai','Tahun '+record.year,record.mileage?record.mileage.toLocaleString('ms-MY')+' km':''].filter(Boolean).join(' · '),qty:1,unitPrice:vehicleSubtotal,amount:vehicleSubtotal}]
  :parseLines(record.items).map((l,i)=>({no:i+1,description:l.name,detail:l.kind==='part'?'Alat ganti':'Upah kerja',qty:l.qty,unitPrice:l.rate,amount:l.qty*l.rate}));
 const subtotal=items.reduce((s,i)=>s+i.amount,0);
 const amount=vehicle?record.price:lineTotal(parseLines(record.items));
 const discount=subtotal-amount;
 const paid=record.paid;const balance=Math.max(0,amount-paid);
 const ledger=[...payments].sort((a,b)=>a.paidAt.localeCompare(b.paidAt)||a.id-b.id).map(p=>({reference:'PAY-'+String(p.id).padStart(4,'0'),date:dateText(p.paidAt),method:(p.amount<0?'Refund · ':'')+(methodName[p.method]||p.method),receiver:clean(p.receiverName),note:clean(p.note)||purposeName[p.purpose]||'',amount:p.amount}));
 const status:InvoiceDoc['status']=type==='estimate'?{label:'ANGGARAN',tone:'draft'}:amount===0?{label:'PERCUMA',tone:'free'}:paid>=amount?{label:'DIBAYAR PENUH',tone:'paid'}:paid>0?{label:'BAYARAN SEBAHAGIAN',tone:'partial'}:{label:'BELUM DIBAYAR',tone:'due'};
 const totals:DocLine[]=[{label:'Jumlah kecil',value:money(subtotal)}];
 if(discount>0)totals.push({label:'Diskaun',value:'-'+money(discount)});
 totals.push({label:type==='estimate'?'Jumlah anggaran':'Jumlah',value:money(amount),strong:true});
 if(type!=='estimate'){totals.push({label:'Jumlah dibayar',value:money(paid),tone:'paid'});totals.push({label:'Baki perlu dibayar',value:money(balance),strong:true,tone:balance>0?'due':'paid'})}
 const business=[profile.registrationNo&&'No. pendaftaran: '+profile.registrationNo,profile.address,[profile.phone&&'Tel: '+formatPhone(profile.phone),profile.email].filter(Boolean).join('  ·  ')].filter(Boolean) as string[];
 const billTo=vehicle?[clean(record.buyer)||'Pembeli belum direkodkan',record.buyerPhone?formatPhone(record.buyerPhone):'']:[clean(record.customer),record.phone?formatPhone(record.phone):''];
 const subject=vehicle?{title:'Butiran motosikal',lines:[record.brand+' '+record.model+' ('+record.year+')',record.plate?'No. plat: '+record.plate:'',record.chassis?'No. casis: '+record.chassis:'','No. stok: '+ref].filter(Boolean)}
  :{title:'Butiran servis',lines:[record.bike+(record.plate?' · '+record.plate:''),record.mileage?'Odometer: '+record.mileage.toLocaleString('ms-MY')+' km':'','Mekanik: '+(clean(record.mechanic)||'—'),'Status kerja: '+jobStatuses[record.status],'No. job: '+ref].filter(Boolean)};
 const notes:{title:string;text:string}[]=[];
 if(!vehicle&&clean(record.complaint))notes.push({title:'Aduan / kerja diminta',text:clean(record.complaint)});
 if(!vehicle&&type==='estimate')notes.push({title:'Persetujuan pelanggan',text:record.estimateStatus==='approved'?clean(record.approvalNote):'Belum direkodkan. Kerja bermula selepas pelanggan bersetuju dengan anggaran ini.'});
 if(!vehicle&&record.status==='collected'&&record.paid<amount&&clean(record.creditReason))notes.push({title:'Serahan dengan baki (diluluskan owner)',text:clean(record.creditReason)});
 if(!vehicle&&amount===0&&clean(record.noChargeReason))notes.push({title:'Servis tanpa caj',text:clean(record.noChargeReason)});
 if(clean(profile.terms))notes.push({title:'Terma & syarat',text:clean(profile.terms)});
 const bank=type!=='receipt'&&(balance>0||type==='estimate')&&profile.bankName&&profile.bankAccountNo?[profile.bankName,'No. akaun: '+profile.bankAccountNo,profile.bankAccountName&&'Nama: '+profile.bankAccountName,'Rujukan: '+number].filter(Boolean) as string[]:null;
 const title=type==='estimate'?'Anggaran Servis':type==='receipt'?'Resit Bayaran':vehicle?'Invois Jualan':'Invois Servis';
 const received=payments.reduce((t,p)=>t+p.amount,0);const dateLabel=type==='estimate'?'Tarikh anggaran':type==='receipt'?'Tarikh resit':'Tarikh invois';
 const meta:[string,string][]=[[type==='estimate'?'No. anggaran':type==='receipt'?'No. resit':'No. invois',number],[dateLabel,dateOnly(now.toISOString())],...(vehicle?(record.soldAt?[['Tarikh jualan',dateOnly(record.soldAt)] as [string,string]]:[]):[['Tarikh job dibuka',dateOnly(record.createdAt||record.updatedAt)] as [string,string]])];
 const bizName=clean(profile.businessName)||defaultProfile.businessName;
 return {meta,amountWords:ringgitWords(type==='receipt'?received:amount),...footer(profile,bizName),type,title,fileName:title.replace(/\s+/g,'-')+'-'+ref+'.pdf',number,reference:ref,issuedAt:dateText(now.toISOString()),status,
  business:{name:clean(profile.businessName)||defaultProfile.businessName,lines:business},billTo:{title:type==='receipt'?'Diterima daripada':vehicle?'Pembeli':'Pelanggan',lines:billTo.filter(Boolean)},subject,
  items,totals,payments:type==='estimate'?[]:ledger,notes,bank,signatures:type==='estimate'?['Disediakan oleh','Persetujuan pelanggan']:type==='receipt'?['Diterima oleh']:vehicle?['Penjual','Pembeli']:['Disediakan oleh','Diterima oleh pelanggan']};
}

type PosLike={id:number;saleType?:'counter'|'service';bike?:string;plate?:string;mileage?:number|null;mechanic?:string;workNotes?:string;customerName:string;customerPhone:string;subtotal:number;discount:number;total:number;paid:number;status:'completed'|'voided';voidReason:string;cashierName:string;createdAt:string;
 lines?:{name:string;qty:number;unitPrice:number;kind?:'part'|'labour'|'other'}[];payments?:{id:number;amount:number;method:string;purpose:string;note:string;receiverName:string;createdAt:string}[]};
const kindName:Record<string,string>={part:'Alat ganti',labour:'Upah kerja',other:'Lain-lain'};
/** POS sale (counter or service) as the same A4 document model. */
export function buildPosInvoice(sale:PosLike,profile:InvoiceProfile,now:Date=new Date()):InvoiceDoc{
 const service=sale.saleType==='service';const ref='POS-'+String(sale.id).padStart(4,'0');const number='INV-'+ref;
 const items=(sale.lines||[]).map((l,i)=>({no:i+1,description:l.name,detail:kindName[l.kind||'other']||'',qty:l.qty,unitPrice:l.unitPrice,amount:l.qty*l.unitPrice}));
 const totals:DocLine[]=[{label:'Jumlah kecil',value:money(sale.subtotal)}];
 if(sale.discount>0)totals.push({label:'Diskaun',value:'-'+money(sale.discount)});
 totals.push({label:'Jumlah',value:money(sale.total),strong:true});
 if(sale.status==='voided')totals.push({label:'Dipulangkan kepada pelanggan',value:money(sale.total),tone:'paid'},{label:'Baki perlu dibayar',value:money(0),strong:true,tone:'paid'});
 else totals.push({label:'Jumlah dibayar',value:money(sale.paid),tone:'paid'},{label:'Baki perlu dibayar',value:money(Math.max(0,sale.total-sale.paid)),strong:true,tone:sale.paid>=sale.total?'paid':'due'});
 const status:InvoiceDoc['status']=sale.status==='voided'?{label:'DIBATALKAN',tone:'due'}:{label:'DIBAYAR PENUH',tone:'paid'};
 const business=[profile.registrationNo&&'No. pendaftaran: '+profile.registrationNo,profile.address,[profile.phone&&'Tel: '+formatPhone(profile.phone),profile.email].filter(Boolean).join('  ·  ')].filter(Boolean) as string[];
 const notes:{title:string;text:string}[]=[];
 if(service&&clean(sale.workNotes))notes.push({title:'Kerja dibuat',text:clean(sale.workNotes)});
 if(sale.status==='voided')notes.push({title:'Dibatalkan',text:clean(sale.voidReason)});
 if(clean(profile.terms))notes.push({title:'Terma & syarat',text:clean(profile.terms)});
 const title=service?'Invois Servis':'Invois Jualan';
 const bizName=clean(profile.businessName)||defaultProfile.businessName;
 return {meta:[['No. invois',number],['Tarikh invois',dateOnly(sale.createdAt)]],amountWords:ringgitWords(sale.total),...footer(profile,bizName),type:'invoice',title,fileName:title.replace(/\s+/g,'-')+'-'+ref+'.pdf',number,reference:ref,issuedAt:dateText(now.toISOString()),status,
  business:{name:clean(profile.businessName)||defaultProfile.businessName,lines:business},
  billTo:{title:'Pelanggan',lines:[clean(sale.customerName)||'Pelanggan walk-in',sale.customerPhone?formatPhone(sale.customerPhone):''].filter(Boolean)},
  subject:service?{title:'Butiran servis',lines:[[sale.bike,sale.plate].filter(Boolean).join(' · '),sale.mileage?'Odometer: '+sale.mileage.toLocaleString('ms-MY')+' km':'','Mekanik: '+(clean(sale.mechanic)||'—'),'Juruwang: '+clean(sale.cashierName)].filter(Boolean)}
   :{title:'Butiran jualan',lines:['Jualan kaunter','Juruwang: '+clean(sale.cashierName)]},
  items,totals,payments:(sale.payments||[]).slice().sort((a,b)=>a.id-b.id).map(p=>({reference:'PAY-'+String(p.id).padStart(4,'0'),date:dateText(p.createdAt),method:(p.amount<0?'Refund · ':'')+(methodName[p.method]||p.method),receiver:clean(p.receiverName),note:clean(p.note)||(p.amount<0?'Refund':service?'Bayaran servis':'Jualan kaunter'),amount:p.amount})),
  notes,bank:null,signatures:service?['Mekanik','Diterima oleh pelanggan']:['Juruwang','Pelanggan']};
}
