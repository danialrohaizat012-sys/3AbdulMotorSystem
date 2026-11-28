// Pure POS helpers (no network). Amounts are integer cents, like the rest of the app.
export type PosProduct={id:number;sku:string;barcode:string;name:string;category:string;unit:string;price:number;cost:number;stockQty:number;reorderLevel:number;trackStock:boolean;active:boolean;version:number};
export type LineKind='part'|'labour'|'other';
export type CartLine={key:string;productId:number|null;name:string;sku:string;qty:number;unitPrice:number;maxQty:number|null;kind?:LineKind};
export type SaleType='counter'|'service';
export type ServiceInfo={plate:string;bike:string;mileage:number|null;mechanic:string;workNotes:string};
export const blankService:ServiceInfo={plate:'',bike:'',mileage:null,mechanic:'',workNotes:''};
export const kindLabels:Record<LineKind,string>={part:'Alat ganti',labour:'Upah kerja',other:'Lain-lain'};
export type PayMethod='cash'|'transfer'|'card';
export type Tender={method:PayMethod;amount:number};
export const methodLabels:Record<PayMethod,string>={cash:'Tunai',transfer:'Transfer / QR',card:'Kad'};
export const blankProduct:PosProduct={id:0,sku:'',barcode:'',name:'',category:'',unit:'unit',price:0,cost:0,stockQty:0,reorderLevel:0,trackStock:true,active:true,version:1};

export const receiptNo=(id:number)=>'POS-'+String(id).padStart(4,'0');
export const lowStock=(p:Pick<PosProduct,'trackStock'|'stockQty'|'reorderLevel'>)=>p.trackStock&&p.stockQty<=p.reorderLevel;
export const sellable=(p:PosProduct)=>p.active&&(!p.trackStock||p.stockQty>0);

/** Adds one product, merging with an existing line. Tracked stock caps the quantity. */
export function addProduct(cart:CartLine[],p:PosProduct,qty=1):{cart:CartLine[];capped:boolean}{
 const max=p.trackStock?p.stockQty:null;const existing=cart.find(l=>l.productId===p.id);const wanted=(existing?.qty??0)+qty;const next=max===null?wanted:Math.min(wanted,max);
 if(next<=0)return {cart,capped:true};
 const line:CartLine={key:'p'+p.id,productId:p.id,name:p.name,sku:p.sku,qty:next,unitPrice:existing?.unitPrice??p.price,maxQty:max,kind:p.trackStock?'part':'labour'};
 return {cart:existing?cart.map(l=>l.key===line.key?line:l):[...cart,line],capped:next<wanted};
}
export function addCustom(cart:CartLine[],name:string,unitPrice:number,kind:LineKind='other'):CartLine[]{return [...cart,{key:'c'+Date.now()+Math.random().toString(36).slice(2,6),productId:null,name:name.trim(),sku:'',qty:1,unitPrice,maxQty:null,kind}]}
export function setQty(cart:CartLine[],key:string,qty:number):CartLine[]{return qty<=0?cart.filter(l=>l.key!==key):cart.map(l=>l.key===key?{...l,qty:Math.min(Math.trunc(qty),l.maxQty??1000,1000)}:l)}
export function setPrice(cart:CartLine[],key:string,unitPrice:number):CartLine[]{return cart.map(l=>l.key===key?{...l,unitPrice:Math.max(0,Math.round(unitPrice))}:l)}
/** Refresh cart prices and stock caps after the product list reloads. */
export function refreshCart(cart:CartLine[],products:PosProduct[],keepPrices=false):CartLine[]{return cart.flatMap(l=>{if(l.productId===null)return [l];const p=products.find(x=>x.id===l.productId);if(!p||!p.active)return [];const max=p.trackStock?p.stockQty:null;const qty=max===null?l.qty:Math.min(l.qty,max);return qty>0?[{...l,name:p.name,sku:p.sku,maxQty:max,qty,unitPrice:keepPrices?l.unitPrice:p.price}]:[]})}

export function cartTotals(cart:CartLine[],discount=0){const subtotal=cart.reduce((s,l)=>s+l.qty*l.unitPrice,0);const d=Math.min(Math.max(0,Math.round(discount)),subtotal);return {subtotal,discount:d,total:subtotal-d,items:cart.reduce((s,l)=>s+l.qty,0)}}
export const changeDue=(tendered:number,cash:number)=>Math.max(0,tendered-cash);
/** Exact amount plus the next round notes a customer is likely to hand over. */
export function quickCash(total:number){const out=[total];for(const step of [1000,5000,10000]){const v=Math.ceil(total/step)*step;if(v>total)out.push(v)}return [...new Set(out)].sort((a,b)=>a-b).slice(0,4)}
/** Parses "12", "12.5", "RM 1,234.50" into cents. Returns NaN when invalid. */
export function parseRinggit(text:string){const clean=text.replace(/rm/i,'').replace(/[\s,]/g,'');if(!/^\d{1,7}(\.\d{0,2})?$/.test(clean))return NaN;return Math.round(Number(clean)*100)}
const norm=(s:string)=>s.trim().toUpperCase();
/** Exact barcode or SKU match, as sent by a barcode scanner followed by Enter. */
export function findByCode(products:PosProduct[],code:string){const c=norm(code);if(!c)return undefined;return products.find(p=>p.active&&(norm(p.barcode)===c||p.sku===c))}
export function searchProducts(products:PosProduct[],query:string,category='all'){const q=query.trim().toLowerCase();return products.filter(p=>p.active&&(category==='all'||p.category===category)&&(!q||(p.name+' '+p.sku+' '+p.barcode+' '+p.category).toLowerCase().includes(q)))}
export const categories=(products:PosProduct[])=>[...new Set(products.filter(p=>p.active&&p.category).map(p=>p.category))].sort((a,b)=>a.localeCompare(b));

export type CheckoutInput={discount:number;customerName:string;customerPhone:string;note:string;method:PayMethod;split:boolean;splitCash:number;splitMethod:PayMethod;cashTendered:number|null;saleType?:SaleType;service?:ServiceInfo};
/** Builds the RPC payload. Throws a staff-readable message when the input is not payable. */
export function buildCheckout(cart:CartLine[],input:CheckoutInput){
 if(!cart.length)throw Error('Troli masih kosong.');
 const service=input.saleType==='service'?input.service??blankService:null;
 if(service&&!service.plate.trim())throw Error('Isi nombor plat motosikal untuk servis.');
 const {total,discount}=cartTotals(cart,input.discount);if(total<=0)throw Error('Jumlah jualan mesti lebih daripada RM0.');
 let tenders:Tender[];
 if(input.split){const cash=Math.round(input.splitCash);if(!(cash>0&&cash<total))throw Error('Masukkan bahagian tunai yang kurang daripada jumlah.');if(input.splitMethod==='cash')throw Error('Pilih kaedah kedua selain tunai.');tenders=[{method:'cash',amount:cash},{method:input.splitMethod,amount:total-cash}]}
 else tenders=[{method:input.method,amount:total}];
 const cash=tenders.filter(t=>t.method==='cash').reduce((s,t)=>s+t.amount,0);
 if(cash>0&&input.cashTendered!==null&&input.cashTendered<cash)throw Error('Tunai diterima kurang daripada jumlah tunai.');
 return {sale_type:service?'service':'counter',...(service?{plate:service.plate.trim().toUpperCase(),bike:service.bike.trim(),mileage:service.mileage,mechanic:service.mechanic.trim(),work_notes:service.workNotes.trim()}:{}),customer_name:input.customerName.trim(),customer_phone:input.customerPhone.trim(),note:input.note.trim(),discount,cash_tendered:cash>0?input.cashTendered??cash:null,
  lines:cart.map(l=>l.productId===null?{name:l.name,kind:l.kind??'other',qty:l.qty,unit_price:l.unitPrice}:{product_id:l.productId,qty:l.qty,unit_price:l.unitPrice}),payments:tenders};
}
