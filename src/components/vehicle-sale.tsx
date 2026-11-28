import {useRef,useState} from 'react';
import {toast} from 'sonner';
import {BadgeCheck,HandCoins,Printer} from 'lucide-react';
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from './ui/dialog';
import {Field,NumberField} from './motor-fields';
import {sellVehicle,getRecord,loadPayments} from '../lib/records';
import type {SaleResult} from '../lib/records';
import {printRecordFrom} from '../lib/print';
import {money,vehicleId} from '../lib/motor';
import type {Vehicle} from '../lib/motor';
import {can} from '../lib/staff';
import type {StaffProfile} from '../lib/staff';

type PayChoice='full'|'deposit'|'none';
type Method='cash'|'transfer'|'card'|'split';
const methodLabels:Record<Method,string>={cash:'Tunai',transfer:'Transfer',card:'Kad',split:'Tunai + Transfer'};
const localNow=()=>{const d=new Date();return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16)};

/** Prominent entry point on an unsold stock record. */
export function SaleCallToAction({vehicle,staff,onSold}:{vehicle:Vehicle;staff:StaffProfile|null;onSold:()=>Promise<void>}){
 const [open,setOpen]=useState(false);
 // The dialog stays mounted across the record refresh so the print step is not lost after a sale.
 const dialog=open&&<VehicleSaleDialog vehicle={vehicle} staff={staff} onClose={()=>setOpen(false)} onDone={onSold}/>;
 // The dialog sits in the same position in both branches so React keeps its state when the status flips to Sold.
 if(vehicle.status==='sold')return <><section className="sale-cta sold"><BadgeCheck size={20}/><div><b>Sudah dijual</b><p>{vehicle.buyer}{vehicle.soldAt?' · '+new Date(vehicle.soldAt).toLocaleDateString('ms-MY',{timeZone:'Asia/Kuala_Lumpur'}):''}</p></div></section>{dialog}</>;
 const balance=vehicle.price-vehicle.paid;const reserved=vehicle.status==='reserved'&&!!vehicle.buyer;
 return <><section className="sale-cta"><HandCoins size={20}/><div><b>{reserved?'Ditempah oleh '+vehicle.buyer:'Sedia untuk dijual'}</b><p>{vehicle.paid>0?'Dibayar '+money(vehicle.paid)+' · Baki '+money(balance):'Harga '+money(vehicle.price)}</p></div>
  <button className="btn primary" disabled={!can(staff,'inventory_edit')||vehicle.price<=0} onClick={()=>setOpen(true)}>{reserved?'Terima baki & jual':'Jual motor'}</button>
  </section>{dialog}</>;
}

export function VehicleSaleDialog({vehicle,staff,onClose,onDone}:{vehicle:Vehicle;staff:StaffProfile|null;onClose:()=>void;onDone:()=>Promise<void>}){
 const owner=staff?.role==='owner';const takeMoney=can(staff,'receive_payments');
 const [buyer,setBuyer]=useState(vehicle.buyer||'');const [phone,setPhone]=useState(vehicle.buyerPhone||'');const [price,setPrice]=useState(vehicle.price);
 const [discount,setDiscount]=useState(0);
 const canDiscount=can(staff,'pos_sell');
 const [choice,setChoice]=useState<PayChoice>(takeMoney?'full':'none');const [deposit,setDeposit]=useState(0);const [method,setMethod]=useState<Method>('cash');
 const [cashAmount,setCashAmount]=useState(0);
 const [more,setMore]=useState(false);const [paidAt,setPaidAt]=useState(localNow());const [note,setNote]=useState('');
 const [busy,setBusy]=useState(false);const [error,setError]=useState('');const [result,setResult]=useState<SaleResult|null>(null);
 const request=useRef(crypto.randomUUID());
 const netPrice=price-discount;
 const balance=Math.max(0,netPrice-vehicle.paid);const amount=choice==='full'?balance:choice==='deposit'?deposit:0;const after=balance-amount;
 const limit=!owner&&staff?.payment_limit!=null?staff.payment_limit:null;
 async function submit(e:React.FormEvent){e.preventDefault();if(busy)return;setBusy(true);setError('');try{
  if(buyer.trim().length<2)throw Error('Isi nama pembeli.');if(phone.replace(/\D/g,'').length<9)throw Error('Isi nombor telefon pembeli.');
  if(!Number.isSafeInteger(discount)||discount<0||netPrice<=0||netPrice<vehicle.paid)throw Error('Harga selepas diskaun mesti positif dan tidak kurang daripada bayaran yang sudah diterima.');
  if(choice==='deposit'&&(deposit<=0||deposit>=balance))throw Error('Deposit mesti lebih daripada RM0 dan kurang daripada baki. Pilih "Bayar penuh" untuk bayaran penuh.');
  const split=amount>0&&method==='split';
  if(split&&(!Number.isSafeInteger(cashAmount)||cashAmount<=0||cashAmount>=amount))throw Error('Isi amaun tunai yang lebih daripada RM0 dan kurang daripada jumlah bayaran.');
  if(limit!==null&&amount>limit)throw Error('Amaun melebihi had bayaran anda ('+money(limit)+'). Minta owner merekodkan bayaran ini.');
  const paid=new Date(paidAt);if(amount>0&&(Number.isNaN(paid.getTime())||paid.getTime()>Date.now()))throw Error('Tarikh bayaran tidak boleh melebihi masa sekarang.');
  const r=await sellVehicle(vehicle,{buyer,buyerPhone:phone,price,discount,amount,method:split?'split':method==='split'?'cash':method,cashAmount:split?cashAmount:undefined,paidAt:paid.toISOString(),note},request.current);
  setResult(r);toast.success(r.status==='sold'?'Jualan selesai. Status: Sold.':amount>0?'Deposit direkod. Status: Reserved.':'Tempahan disimpan.');await onDone();
 }catch(e){setError((e as Error).message)}finally{setBusy(false)}}
 function print(type:'invoice'|'receipt'){printRecordFrom(async()=>{
  const [record,payments]=await Promise.all([getRecord('vehicles',vehicle.id),loadPayments('vehicles',vehicle.id)]);
  if(type==='receipt'&&result?.transferPaymentId){
   return [record,payments.filter(p=>p.id===result.paymentId||p.id===result.transferPaymentId)];
  }
  return [record,payments];
 },type).catch(e=>toast.error((e as Error).message))}
 return <Dialog open onOpenChange={o=>{if(!o&&!busy)onClose()}}><DialogContent className="motor-dialog sale-dialog">
  <DialogHeader><DialogTitle>{result?'Jualan direkod':'Jual '+vehicle.brand+' '+vehicle.model}</DialogTitle><DialogDescription>{vehicleId(vehicle.id,vehicle.stockNo)}{vehicle.plate?' · '+vehicle.plate:''}</DialogDescription></DialogHeader>
  {result?<div className="sale-done"><BadgeCheck size={40}/><b>{result.status==='sold'?'SOLD · dibayar penuh':'RESERVED · baki '+money(result.balance)}</b><p>Dibayar {money(result.paid)} daripada {money(result.price)}</p>
   <div className="action-row"><button className="btn primary" onClick={()=>void print('invoice')}><Printer size={16}/>Cetak invois</button>{result.paid>0&&<button className="btn subtle" onClick={()=>void print('receipt')}><Printer size={16}/>Cetak resit</button>}<button className="btn subtle" onClick={onClose}>Tutup</button></div></div>:
  <form onSubmit={submit}>
   <div className="form-grid"><Field label="Nama pembeli *"><input required autoFocus maxLength={120} value={buyer} onChange={e=>setBuyer(e.target.value)}/></Field><Field label="Telefon pembeli *"><input required type="tel" inputMode="tel" maxLength={20} value={phone} onChange={e=>setPhone(e.target.value)} placeholder="012-345 6789"/></Field></div>
   {owner?<NumberField label="Harga jualan (RM)" cents value={price} onChange={setPrice}/>:<p className="sale-price">Harga jualan <b>{money(price)}</b></p>}
   {canDiscount&&<NumberField label={vehicle.saleDiscount?'Diskaun tambahan (RM)':'Diskaun (RM)'} cents value={discount} onChange={setDiscount}/>}
   {!!vehicle.saleDiscount&&<p className="form-note">Diskaun sudah direkod {money(vehicle.saleDiscount)}.</p>}
   {discount>0&&<p className="sale-price">Harga selepas diskaun <b>{money(netPrice)}</b></p>}
   {vehicle.paid>0&&<p className="form-note">Sudah dibayar {money(vehicle.paid)}. Baki {money(balance)}.</p>}
   <div className="sale-choice" role="radiogroup" aria-label="Bayaran sekarang">
    {([['full','Bayar penuh',money(balance)],['deposit','Deposit','Sebahagian'],['none','Tempah sahaja','Tiada bayaran']] as [PayChoice,string,string][]).map(([k,l,s])=><button type="button" key={k} role="radio" aria-checked={choice===k} className={choice===k?'active':''} disabled={k!=='none'&&!takeMoney} onClick={()=>setChoice(k)}><b>{l}</b><small>{s}</small></button>)}
   </div>
   {!takeMoney&&<p className="form-note">Anda tidak dibenarkan menerima bayaran. Simpan tempahan, kemudian owner atau staf kaunter rekod bayaran.</p>}
   {choice==='deposit'&&<NumberField label="Amaun deposit (RM)" cents value={deposit} onChange={setDeposit}/>}
   {amount>0&&<div className="sale-methods" role="radiogroup" aria-label="Kaedah bayaran">{(Object.keys(methodLabels) as Method[]).map(m=><button type="button" key={m} role="radio" aria-checked={method===m} className={method===m?'active':''} onClick={()=>setMethod(m)}>{methodLabels[m]}</button>)}</div>}
   {amount>0&&method==='split'&&<div className="form-grid">
    <NumberField label="Amaun tunai (RM)" cents value={cashAmount} onChange={setCashAmount}/>
    <p className="sale-price">Baki dibayar melalui transfer <b>{money(Math.max(0,amount-cashAmount))}</b></p>
   </div>}
   {amount>0&&<button type="button" className="quiet-link sale-more" onClick={()=>setMore(!more)}>{more?'Sembunyi pilihan lain':'Tukar tarikh bayaran / tambah nota'}</button>}
   {more&&amount>0&&<div className="form-grid"><Field label="Tarikh & masa bayaran"><input type="datetime-local" value={paidAt} max={localNow()} onChange={e=>setPaidAt(e.target.value)}/></Field><Field label="Nota (pilihan)"><input maxLength={500} value={note} onChange={e=>setNote(e.target.value)} placeholder="cth. No. rujukan transfer"/></Field></div>}
   <div className={'sale-summary '+(after===0&&netPrice>0?'done':'')}><span>Selepas ini</span><b>{after===0?'SOLD · dibayar penuh':(amount>0?'RESERVED · baki '+money(after):'RESERVED · belum dibayar')}</b></div>
   {error&&<p className="form-error" role="alert">{error}</p>}
   <button className="btn primary sale-submit" disabled={busy}>{busy?'Merekod…':amount>0?'Rekod jualan · '+money(amount)+' '+methodLabels[method]:'Simpan tempahan'}</button>
  </form>}
 </DialogContent></Dialog>;
}
