import {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {Toaster,toast} from 'sonner';
import {ArrowLeft,Search,X,Plus,Minus,Trash2,ShoppingCart,Package,Receipt,Wallet,Printer,MessageCircle,RefreshCw,ScanLine,AlertTriangle,PackagePlus,SlidersHorizontal,Pencil,Banknote,Wrench,Bike} from 'lucide-react';
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from './ui/dialog';
import {Switch} from './ui/switch';
import {Field} from './motor-fields';
import {can,canAccess} from '@/lib/staff';
import type {StaffProfile} from '@/lib/staff';
import {money,dateText,vehicleId} from '@/lib/motor';
import type {Vehicle} from '@/lib/motor';
import {getRecord,loadPayments,loadRecords,loadVehicleSales} from '@/lib/records';
import type {VehicleSaleRow} from '@/lib/records';
import {printRecordFrom} from '@/lib/print';
import {normalizePhone} from '@/lib/business';
import {VehicleSaleDialog} from './vehicle-sale';
import {blankService,kindLabels,addProduct,addCustom,setQty,setPrice,refreshCart,cartTotals,changeDue,quickCash,parseRinggit,findByCode,searchProducts,categories,buildCheckout,receiptNo,lowStock,sellable,methodLabels,blankProduct} from '@/lib/pos-model';
import type {PosProduct,CartLine,PayMethod,LineKind,SaleType,ServiceInfo} from '@/lib/pos-model';
import {loadProducts,saveProduct,stockMove,loadMoves,loadOpenShift,loadShifts,openShift,closeShift,shiftReport,checkout,loadSales,loadSale,voidSale,printReceipt,posInvoicePdf,printWindow,serviceHistory,printPosInvoice,printShift,receiptWhatsapp} from '@/lib/pos';
import type {PosSale,PosShift,PosMove,ShiftReport} from '@/lib/pos';
import {PdfWhatsapp} from './pdf-whatsapp';
import '../pos.css';

type Tab='counter'|'vehicles'|'products'|'sales'|'shift';
const tabs:{id:Tab;label:string;icon:typeof Package}[]=[{id:'counter',label:'Kaunter',icon:ShoppingCart},{id:'vehicles',label:'Jual motor',icon:Bike},{id:'products',label:'Produk & stok',icon:Package},{id:'sales',label:'Jualan',icon:Receipt},{id:'shift',label:'Tutup kaunter',icon:Wallet}];
const errorText=(e:unknown)=>e instanceof Error?e.message:'Operasi gagal. Cuba semula.';

/** A ringgit input that keeps the staff's own typing (e.g. "12.") until it parses. */
function MoneyInput({label,value,onChange,autoFocus=false,placeholder='0.00'}:{label:string;value:number|null;onChange:(cents:number|null)=>void;autoFocus?:boolean;placeholder?:string}){const [text,setText]=useState(value===null?'':(value/100).toFixed(2));const last=useRef(value);useEffect(()=>{if(value!==last.current){last.current=value;setText(value===null?'':(value/100).toFixed(2))}},[value]);return <Field label={label}><input inputMode="decimal" autoFocus={autoFocus} placeholder={placeholder} value={text} onChange={e=>{setText(e.target.value);const v=e.target.value.trim()===''?null:parseRinggit(e.target.value);if(v===null||!Number.isNaN(v)){last.current=v;onChange(v)}}}/></Field>}

export function PosPage({staff}:{staff:StaffProfile}){
 const owner=staff.role==='owner';const manager=can(staff,'pos_manage');const seller=can(staff,'pos_sell');
 const [tab,setTab]=useState<Tab>(seller?'counter':'products');
 const [products,setProducts]=useState<PosProduct[]>([]);const [loading,setLoading]=useState(true);const [error,setError]=useState('');
 const [shift,setShift]=useState<PosShift|null>(null);
 const [openSale,setOpenSale]=useState<PosSale|null>(null);const [justSold,setJustSold]=useState<number|null>(null);
 const reload=useCallback(async()=>{setLoading(true);try{const [p,s]=await Promise.all([loadProducts(),loadOpenShift()]);setProducts(p);setShift(s);setError('')}catch(e){setError(errorText(e))}finally{setLoading(false)}},[]);
 useEffect(()=>{void reload()},[reload]);
 useEffect(()=>{const id=Number(new URLSearchParams(location.hash.split('?')[1]||'').get('sale'));if(Number.isInteger(id)&&id>0)void loadSale(id).then(setOpenSale).catch(e=>toast.error(errorText(e)))},[]);
 const startService=new URLSearchParams(location.hash.split('?')[1]||'').get('service')==='1';
 const canSellVehicles=seller&&can(staff,'inventory_edit');
 const visibleTabs=tabs.filter(t=>t.id==='vehicles'?canSellVehicles:t.id==='products'||seller||t.id==='sales');
 return <main className="workspace pos-workspace"><Toaster richColors position="top-center"/>
  <div className="pos-top"><div><a className="quiet-link" href={staff.role==='garage'?'#garage':'#inventory'}><ArrowLeft size={16}/>Kembali</a><h1>POS kaunter<span className="yellow-period">.</span></h1><p className="muted">{shift?<>Kaunter dibuka {dateText(shift.openedAt)} · {shift.openerName}</>:'Kaunter akan dibuka secara automatik pada jualan pertama.'}</p></div>
   <nav className="pos-tabs" aria-label="Bahagian POS">{visibleTabs.map(t=><button key={t.id} aria-pressed={tab===t.id} className={tab===t.id?'active':''} onClick={()=>setTab(t.id)}><t.icon size={18}/><span>{t.label}</span></button>)}</nav></div>
  {error&&<div className="error-banner" role="alert"><span>{error}</span><button className="btn subtle" onClick={()=>void reload()}><RefreshCw size={16}/>Cuba semula</button></div>}
  {tab==='counter'&&seller&&<Counter initialService={startService} products={products} loading={loading} manager={manager} onSold={sale=>{void reload();setJustSold(sale.id);setOpenSale(sale)}} onStale={reload}/>}
  {tab==='vehicles'&&canSellVehicles&&<CounterVehicles staff={staff}/>}
  {tab==='products'&&<Products products={products} loading={loading} manager={manager} onChanged={reload}/>}
  {tab==='sales'&&<Sales onOpen={setOpenSale} showVehicleSales={canAccess(staff,'inventory')}/>}
  {tab==='shift'&&seller&&<ShiftPanel shift={shift} onChanged={reload}/>}
  {openSale&&<SaleDialog fresh={justSold===openSale.id&&openSale.status==='completed'} sale={openSale} owner={owner} onClose={()=>{setOpenSale(null);setJustSold(null);if(location.hash.includes('sale='))history.replaceState(null,'','#pos')}} onChanged={s=>{setOpenSale(s);void reload()}}/>}
 </main>;
}

function CounterVehicles({staff}:{staff:StaffProfile}){
 const [vehicles,setVehicles]=useState<Vehicle[]>([]);
 const [selected,setSelected]=useState<Vehicle|null>(null);
 const [search,setSearch]=useState('');
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState('');
 const reload=useCallback(async()=>{
  setLoading(true);
  setError('');
  try {
   const records=await loadRecords('vehicles',true);
   setVehicles(records.filter((record):record is Vehicle=>'brand' in record&&record.status!=='sold'&&record.price>0));
  } catch(e){
   setVehicles([]);
   setError(errorText(e));
  } finally {
   setLoading(false);
  }
 },[]);
 useEffect(()=>{void reload()},[reload]);
 const needle=search.trim().toLowerCase();
 const shown=vehicles.filter(v=>[vehicleId(v.id,v.stockNo),v.brand,v.model,v.plate].join(' ').toLowerCase().includes(needle));

 return <section aria-label="Jual motosikal dari inventori">
  <p className="form-note">Tempahan dan bayaran motor direkod pada rekod motosikal di Inventori.</p>
  <div className="action-row">
   <div className="search pos-search"><Search size={18}/><input aria-label="Cari motosikal" placeholder="Cari nombor stok, model atau plat…" value={search} onChange={e=>setSearch(e.target.value)}/></div>
   <button className="btn subtle" disabled={loading} onClick={()=>void reload()}><RefreshCw size={16}/>Muat semula</button>
  </div>
  {loading&&<p role="status">Memuatkan stok motosikal…</p>}
  {error&&<p className="form-error" role="alert">{error}</p>}
  {!loading&&!error&&shown.length===0&&<p className="muted">Tiada stok motosikal yang sepadan.</p>}
  {!loading&&<div className="pos-product-list">{shown.map(v=><button type="button" className="pos-product-row" key={v.id} onClick={()=>setSelected(v)}>
   <span><b>{v.brand} {v.model}</b><small>{vehicleId(v.id,v.stockNo)}{v.plate?' · '+v.plate:''} · {v.status==='reserved'?'Ditempah':'Tersedia'}</small></span>
   <strong>{money(v.price-v.paid)}</strong>
  </button>)}</div>}
  {selected&&<VehicleSaleDialog vehicle={selected} staff={staff} onClose={()=>setSelected(null)} onDone={reload}/>}
 </section>;
}

function Counter({products,loading,manager,onSold,onStale,initialService=false}:{initialService?:boolean;products:PosProduct[];loading:boolean;manager:boolean;onSold:(s:PosSale)=>void;onStale:()=>Promise<void>}){
 const [cart,setCart]=useState<CartLine[]>([]);const [query,setQuery]=useState('');const [category,setCategory]=useState('all');
 const [method,setMethod]=useState<PayMethod>('cash');const [tendered,setTendered]=useState<number|null>(null);
 const [split,setSplit]=useState(false);const [splitCash,setSplitCash]=useState<number|null>(null);const [splitMethod,setSplitMethod]=useState<PayMethod>('transfer');
 const [discount,setDiscount]=useState(0);const [customer,setCustomer]=useState(false);const [customerName,setCustomerName]=useState('');const [customerPhone,setCustomerPhone]=useState('');
 const [custom,setCustom]=useState<LineKind|null>(null);const [busy,setBusy]=useState(false);const [error,setError]=useState('');
 const [saleType,setSaleType]=useState<SaleType>(initialService?'service':'counter');const [service,setService]=useState<ServiceInfo>(blankService);const [history,setHistory]=useState<PosSale[]>([]);const [suggest,setSuggest]=useState<PosSale|null>(null);
 const isService=saleType==='service';const sv=<K extends keyof ServiceInfo>(k:K,v:ServiceInfo[K])=>setService(s=>({...s,[k]:v}));
 // Typing a plate looks up earlier services and fills in the customer and bike when empty.
 const plateKey=service.plate.replace(/[^A-Za-z0-9]/g,'').toUpperCase();
 useEffect(()=>{if(!isService||plateKey.length<4){setHistory([]);setSuggest(null);return}let live=true;const t=window.setTimeout(()=>{void serviceHistory(plateKey).then(rows=>{if(!live)return;setHistory(rows.slice(0,3));const last=rows[0];setSuggest(last&&(last.customerName||last.customerPhone)?last:null);if(last)setService(s=>({...s,bike:s.bike||last.bike||''}))}).catch(()=>{})},450);return()=>{live=false;window.clearTimeout(t)}},[isService,plateKey]);
 const request=useRef<string|null>(null);const search=useRef<HTMLInputElement>(null);const cartRef=useRef<HTMLElement>(null);const [cartVisible,setCartVisible]=useState(false);
 useEffect(()=>{const el=cartRef.current;if(!el||typeof IntersectionObserver==='undefined')return;const o=new IntersectionObserver(([e])=>setCartVisible(e.isIntersecting),{threshold:0.05});o.observe(el);return()=>o.disconnect()},[]);
 // A retry after a dropped connection reuses the same request ID; any cart change starts a new sale.
 useEffect(()=>{request.current=null},[cart,discount,method,split,splitCash,splitMethod,customerName,customerPhone,saleType,service]);
 useEffect(()=>{setCart(c=>refreshCart(c,products,manager))},[products,manager]);
 const totals=cartTotals(cart,discount);const list=useMemo(()=>searchProducts(products,query,category),[products,query,category]);const cats=useMemo(()=>categories(products),[products]);
 const cashDue=split?(splitCash??0):method==='cash'?totals.total:0;
 function add(p:PosProduct){if(!sellable(p)){toast.error(p.name+' kehabisan stok.');return}const r=addProduct(cart,p);if(r.capped)toast.warning('Baki stok '+p.name+' hanya '+p.stockQty+'.');setCart(r.cart)}
 function scan(e:React.KeyboardEvent<HTMLInputElement>){if(e.key!=='Enter')return;e.preventDefault();const hit=findByCode(products,query)||(list.length===1?list[0]:undefined);if(hit){add(hit);setQuery('')}else if(query.trim())toast.error('Kod "'+query.trim()+'" tidak dijumpai.')}
 function reset(){setCart([]);setTendered(null);setSplit(false);setSplitCash(null);setDiscount(0);setCustomer(false);setCustomerName('');setCustomerPhone('');setMethod('cash');setService(blankService);setHistory([]);setSuggest(null);setError('');request.current=null;search.current?.focus()}
 async function pay(){if(busy)return;setBusy(true);setError('');try{const payload=buildCheckout(cart,{discount,customerName,customerPhone,note:'',method,split,splitCash:splitCash??0,splitMethod,cashTendered:cashDue>0?tendered:null,saleType,service});request.current??=crypto.randomUUID();const sale=await checkout(request.current,payload);toast.success((isService?'Servis ':'Jualan ')+receiptNo(sale.id)+' direkod.');reset();onSold(sale)}catch(e){const m=errorText(e);setError(m);if(/harga|stok|tidak aktif/i.test(m))void onStale()}finally{setBusy(false)}}
 return <div className="pos-counter">
  <section className="pos-catalogue" aria-label="Pilih produk">
   <div className="search pos-search"><ScanLine size={18}/><input ref={search} autoFocus aria-label="Cari atau scan barcode" placeholder="Scan barcode atau cari nama / SKU…" value={query} onChange={e=>setQuery(e.target.value)} onKeyDown={scan}/>{query&&<button aria-label="Kosongkan carian" onClick={()=>setQuery('')}><X size={16}/></button>}</div>
   {cats.length>0&&<div className="pos-chips" role="group" aria-label="Kategori">{['all',...cats].map(c=><button key={c} aria-pressed={category===c} className={category===c?'active':''} onClick={()=>setCategory(c)}>{c==='all'?'Semua':c}</button>)}</div>}
   {loading?<p className="muted">Memuatkan produk…</p>:!products.length?<div className="empty-state"><Package size={32}/><h3>Belum ada produk</h3><p>{manager?'Tambah produk di tab Produk & stok.':'Minta pengurus POS menambah produk.'}</p></div>:
   <div className="pos-grid">{list.map(p=><button key={p.id} className={'pos-product'+(sellable(p)?'':' out')} onClick={()=>add(p)}><span className="pos-product-name">{p.name}</span><span className="pos-product-meta">{p.sku}{p.trackStock?<> · <b className={lowStock(p)?'low':''}>{p.stockQty} {p.unit}</b></>:' · Servis'}</span><strong>{money(p.price)}</strong></button>)}{!list.length&&<p className="muted">Tiada produk sepadan.</p>}</div>}
  </section>
  <section ref={cartRef} className="pos-cart operation-panel" id="pos-cart" aria-label="Troli">
   <div className="pos-type" role="radiogroup" aria-label="Jenis jualan"><button type="button" role="radio" aria-checked={!isService} className={!isService?'active':''} onClick={()=>{if(!manager&&cart.some(l=>l.productId===null&&l.kind==='labour')){setCart(c=>c.filter(l=>!(l.productId===null&&l.kind==='labour')));toast.warning('Upah kerja hanya untuk servis dan telah dibuang dari troli.')}setSaleType('counter')}}><ShoppingCart size={16}/>Jualan kaunter</button><button type="button" role="radio" aria-checked={isService} className={isService?'active':''} onClick={()=>{setSaleType('service');setCustomer(true)}}><Wrench size={16}/>Servis / repair</button></div>
   {isService&&<div className="pos-service">
    <div className="form-grid"><Field label="No. plat *"><input required autoCapitalize="characters" maxLength={30} value={service.plate} onChange={e=>sv('plate',e.target.value.toUpperCase())} placeholder="cth. WXY 1234"/></Field><Field label="Motosikal"><input maxLength={100} value={service.bike} onChange={e=>sv('bike',e.target.value)} placeholder="cth. Honda Wave 125"/></Field>
    <Field label="Mekanik"><input maxLength={100} value={service.mechanic} onChange={e=>sv('mechanic',e.target.value)}/></Field><Field label="Odometer (km)"><input inputMode="numeric" value={service.mileage??''} onChange={e=>{const v=e.target.value.replace(/\D/g,'');sv('mileage',v?Math.min(Number(v),10000000):null)}}/></Field></div>
    <Field label="Kerja dibuat / aduan"><textarea rows={2} maxLength={3000} value={service.workNotes} onChange={e=>sv('workNotes',e.target.value)} placeholder="cth. Tukar minyak, laras brek belakang"/></Field>
    {suggest&&(customerName!==suggest.customerName||customerPhone!==suggest.customerPhone)&&<button type="button" className="btn subtle pos-small pos-suggest" onClick={()=>{setCustomerName(suggest.customerName);setCustomerPhone(suggest.customerPhone)}}>Guna pelanggan lepas: {suggest.customerName||'—'}{suggest.customerPhone?' · '+suggest.customerPhone:''}</button>}{suggest&&<small className="form-note">Motor mungkin sudah bertukar pemilik — sahkan dengan pelanggan.</small>}
    {history.length>0&&<div className="pos-history"><b>Servis lepas ({history.length}{history.length===3?'+':''})</b>{history.map(h=><span key={h.id}>{new Date(h.createdAt).toLocaleDateString('ms-MY',{timeZone:'Asia/Kuala_Lumpur'})} · {money(h.total)}{h.mileage?' · '+h.mileage.toLocaleString('ms-MY')+' km':''}{h.workNotes?' · '+h.workNotes.slice(0,60):''}</span>)}</div>}
   </div>}
   <div className="section-label"><h2><ShoppingCart size={19}/>{isService?'Alat ganti & upah':'Troli'} <span className="count">{totals.items}</span></h2>{cart.length>0&&<button className="btn subtle" onClick={reset}>Kosongkan</button>}</div>
   {!cart.length?<p className="muted pos-empty">{isService?'Tambah alat ganti dari senarai, dan upah kerja di bawah.':'Tekan produk atau scan barcode untuk mula.'}</p>:<ul className="pos-lines">{cart.map(l=><li key={l.key}><div className="pos-line-main"><b>{l.name}</b>{isService&&l.kind&&<small className="pos-kind">{kindLabels[l.kind]}</small>}{manager?<label className="pos-line-price"><span>@</span><input inputMode="decimal" aria-label={'Harga '+l.name} defaultValue={(l.unitPrice/100).toFixed(2)} onBlur={e=>{const v=parseRinggit(e.target.value);if(!Number.isNaN(v))setCart(c=>setPrice(c,l.key,v));else e.target.value=(l.unitPrice/100).toFixed(2)}}/></label>:<small>@ {money(l.unitPrice)}</small>}</div>
    <div className="pos-qty"><button aria-label="Kurang" onClick={()=>setCart(c=>setQty(c,l.key,l.qty-1))}>{l.qty===1?<Trash2 size={16}/>:<Minus size={16}/>}</button><span aria-live="polite">{l.qty}</span><button aria-label="Tambah" disabled={l.maxQty!==null&&l.qty>=l.maxQty} onClick={()=>setCart(c=>setQty(c,l.key,l.qty+1))}><Plus size={16}/></button></div><strong>{money(l.qty*l.unitPrice)}</strong></li>)}</ul>}
   <div className="action-row pos-add-row">{isService&&<button className="btn primary pos-small" onClick={()=>setCustom('labour')}><Plus size={15}/>Upah kerja</button>}{manager&&<button className="btn subtle pos-small" onClick={()=>setCustom('other')}><Plus size={15}/>Item lain (tanpa stok)</button>}</div>
   <div className="pos-totals"><div><span>Jumlah kecil</span><span>{money(totals.subtotal)}</span></div>{manager&&<div className="pos-discount"><span>Diskaun</span><MoneyInput label="Diskaun (RM)" value={discount||null} onChange={v=>setDiscount(v??0)}/></div>}{totals.discount>0&&<div><span>Diskaun</span><span>-{money(totals.discount)}</span></div>}<div className="pos-grand"><span>JUMLAH</span><span>{money(totals.total)}</span></div></div>
   <div className="pos-methods" role="radiogroup" aria-label="Kaedah bayaran">{(Object.keys(methodLabels) as PayMethod[]).map(m=><button key={m} role="radio" aria-checked={!split&&method===m} className={!split&&method===m?'active':''} onClick={()=>{setSplit(false);setMethod(m)}}>{methodLabels[m]}</button>)}<button role="radio" aria-checked={split} className={split?'active':''} onClick={()=>setSplit(true)}>Campur</button></div>
   {split&&<div className="form-grid"><MoneyInput label="Bahagian tunai (RM)" value={splitCash} onChange={setSplitCash}/><Field label="Baki dibayar dengan"><select value={splitMethod} onChange={e=>setSplitMethod(e.target.value as PayMethod)}><option value="transfer">{methodLabels.transfer}</option><option value="card">{methodLabels.card}</option></select></Field>{splitCash!==null&&splitCash<totals.total&&<p className="form-note">{methodLabels[splitMethod]}: <b>{money(totals.total-splitCash)}</b></p>}</div>}
   {cashDue>0&&totals.total>0&&<div className="pos-cash"><span className="pos-cash-label">Tunai diterima (pilihan)</span><div className="pos-quick">{quickCash(cashDue).map(v=><button key={v} className={tendered===v?'active':''} onClick={()=>setTendered(v)}>{v===cashDue?'Tepat':money(v).replace(/\.00$/,'')}</button>)}</div><MoneyInput label="Jumlah lain (RM)" value={tendered} onChange={setTendered}/>{tendered!==null&&tendered>=cashDue&&<p className="pos-change">Baki dipulangkan: <b>{money(changeDue(tendered,cashDue))}</b></p>}</div>}
   {!isService&&<button className="btn subtle pos-small" onClick={()=>setCustomer(v=>!v)}>{customer?'Sembunyi maklumat pelanggan':'+ Nama / telefon pelanggan (pilihan)'}</button>}
   {(customer||isService)&&<div className="form-grid"><Field label={isService?'Nama pelanggan':'Nama'}><input maxLength={120} value={customerName} onChange={e=>setCustomerName(e.target.value)}/></Field><Field label="Telefon (untuk resit WhatsApp)"><input inputMode="tel" maxLength={20} value={customerPhone} onChange={e=>setCustomerPhone(e.target.value)}/></Field></div>}
   {error&&<p className="form-error" role="alert">{error}</p>}
   <button className="btn primary pos-pay" disabled={busy||!cart.length||totals.total<=0} onClick={()=>void pay()}>{busy?'Merekod…':(isService?'Selesai & bayar ':'Bayar ')+money(totals.total)}</button>
  </section>
  {cart.length>0&&!cartVisible&&<a className="pos-mobile-bar" href="#pos-cart" onClick={e=>{e.preventDefault();document.getElementById('pos-cart')?.scrollIntoView({behavior:'smooth'})}}><span>{totals.items} item · <b>{money(totals.total)}</b></span><span>Ke troli & bayar</span></a>}
  {custom&&<CustomItem kind={custom} onClose={()=>setCustom(null)} onAdd={(n,p)=>{setCart(c=>addCustom(c,n,p,custom));setCustom(null)}}/>}
 </div>;
}

function CustomItem({kind,onClose,onAdd}:{kind:LineKind;onClose:()=>void;onAdd:(name:string,price:number)=>void}){const labour=kind==='labour';const [name,setName]=useState(labour?'Upah kerja':'');const [price,setPrice]=useState<number|null>(null);return <Dialog open onOpenChange={o=>{if(!o)onClose()}}><DialogContent className="motor-dialog"><DialogHeader><DialogTitle>{labour?'Upah kerja':'Item lain'}</DialogTitle><DialogDescription>{labour?'Caj kerja mekanik. Boleh tambah lebih daripada satu baris (cth. servis, tukar tayar).':'Untuk item sekali sahaja yang tiada dalam senarai. Stok tidak ditolak.'}</DialogDescription></DialogHeader><form onSubmit={e=>{e.preventDefault();if(name.trim()&&price!==null&&price>0)onAdd(name,price)}}><Field label={labour?'Penerangan kerja':'Nama item'}><input required autoFocus maxLength={120} value={name} onChange={e=>setName(e.target.value)}/></Field><MoneyInput label="Harga (RM)" value={price} onChange={setPrice}/><button className="btn primary" disabled={!name.trim()||!price}>Tambah ke troli</button></form></DialogContent></Dialog>}

function Products({products,loading,manager,onChanged}:{products:PosProduct[];loading:boolean;manager:boolean;onChanged:()=>Promise<void>}){
 const [query,setQuery]=useState('');const [low,setLow]=useState(false);const [editing,setEditing]=useState<PosProduct|null>(null);const [stock,setStock]=useState<{p:PosProduct;kind:'receive'|'adjust'}|null>(null);
 const list=products.filter(p=>(!low||lowStock(p)&&p.active)&&(p.name+' '+p.sku+' '+p.barcode+' '+p.category).toLowerCase().includes(query.trim().toLowerCase()));const lowCount=products.filter(p=>p.active&&lowStock(p)).length;
 const value=products.filter(p=>p.trackStock).reduce((s,p)=>s+p.stockQty*p.cost,0);
 return <section>
  <div className="stats pos-stats"><div className="stat"><div><span>Produk aktif</span><Package size={18}/></div><strong>{loading?'—':products.filter(p=>p.active).length}</strong></div><div className="stat"><div><span>Stok rendah</span><AlertTriangle size={18}/></div><strong>{loading?'—':lowCount}</strong></div><div className="stat"><div><span>Nilai stok (kos)</span><Banknote size={18}/></div><strong>{loading?'—':money(value)}</strong></div></div>
  <div className="filters"><div className="search"><Search size={18}/><input aria-label="Cari produk" placeholder="Cari nama, SKU atau barcode…" value={query} onChange={e=>setQuery(e.target.value)}/></div><button className={'btn subtle'+(low?' active':'')} aria-pressed={low} onClick={()=>setLow(!low)}><AlertTriangle size={16}/>Stok rendah ({lowCount})</button>{manager&&<button className="btn primary" onClick={()=>setEditing(blankProduct)}><Plus size={18}/>Produk baharu</button>}</div>
  {!manager&&<p className="form-note">Paparan sahaja. Pengurus POS boleh menambah produk dan menerima stok.</p>}
  <div className="pos-product-list">{list.map(p=><article key={p.id} className={'pos-product-row'+(p.active?'':' inactive')}><div><b>{p.name}</b><small>{p.sku}{p.barcode?' · '+p.barcode:''}{p.category?' · '+p.category:''}{!p.active?' · Tidak aktif':''}</small></div><div className="pos-row-stock">{p.trackStock?<span className={lowStock(p)?'low':''}>{p.stockQty} {p.unit}</span>:<span>Servis</span>}<strong>{money(p.price)}</strong></div>{manager&&<div className="pos-row-actions">{p.trackStock&&<button className="btn subtle" onClick={()=>setStock({p,kind:'receive'})}><PackagePlus size={16}/>Terima</button>}{p.trackStock&&<button className="btn subtle" aria-label={'Laras stok '+p.name} onClick={()=>setStock({p,kind:'adjust'})}><SlidersHorizontal size={16}/></button>}<button className="btn subtle" aria-label={'Edit '+p.name} onClick={()=>setEditing(p)}><Pencil size={16}/></button></div>}</article>)}{!loading&&!list.length&&<p className="muted">Tiada produk.</p>}</div>
  {editing&&<ProductEditor initial={editing} onClose={()=>setEditing(null)} onSaved={()=>{setEditing(null);void onChanged()}}/>}
  {stock&&<StockDialog product={stock.p} kind={stock.kind} onClose={()=>setStock(null)} onSaved={()=>{setStock(null);void onChanged()}}/>}
 </section>;
}

function ProductEditor({initial,onClose,onSaved}:{initial:PosProduct;onClose:()=>void;onSaved:()=>void}){
 const [p,setP]=useState(initial);const [opening,setOpening]=useState(0);const created=useRef<PosProduct|null>(null);const openingRequest=useRef(crypto.randomUUID());const [busy,setBusy]=useState(false);const [error,setError]=useState('');const [moves,setMoves]=useState<PosMove[]>([]);
 useEffect(()=>{if(initial.id&&initial.trackStock)void loadMoves(initial.id).then(setMoves).catch(()=>{})},[initial]);
 const set=<K extends keyof PosProduct>(k:K,v:PosProduct[K])=>setP(x=>({...x,[k]:v}));
 async function save(e:React.FormEvent){e.preventDefault();setBusy(true);setError('');try{if(!p.sku.trim()||!p.name.trim())throw Error('Isi SKU dan nama produk.');// A retry after the product was created only records the opening stock.
  const saved=await saveProduct(created.current?{...p,id:created.current.id,version:created.current.version}:p);if(!initial.id)created.current=saved;if(!initial.id&&saved.trackStock&&opening>0)await stockMove(saved.id,'receive',opening,'Stok awal',saved.cost,openingRequest.current);toast.success('Produk disimpan.');onSaved()}catch(e){setError(errorText(e))}finally{setBusy(false)}}
 return <Dialog open onOpenChange={o=>{if(!o&&!busy)onClose()}}><DialogContent className="motor-dialog"><DialogHeader><DialogTitle>{initial.id?'Edit produk':'Produk baharu'}</DialogTitle><DialogDescription>Harga dalam RM. Stok berubah melalui jualan, terimaan atau pelarasan sahaja.</DialogDescription></DialogHeader>
  <form onSubmit={save}><Field label="Nama produk"><input required autoFocus maxLength={120} value={p.name} onChange={e=>set('name',e.target.value)}/></Field>
   <div className="form-grid"><Field label="SKU / kod"><input required maxLength={40} value={p.sku} onChange={e=>set('sku',e.target.value.toUpperCase().replace(/\s/g,'-'))} placeholder="cth. OIL-10W40"/></Field><Field label="Barcode (pilihan)"><input maxLength={64} inputMode="numeric" value={p.barcode} onChange={e=>set('barcode',e.target.value.trim())} placeholder="Scan di sini"/></Field>
   <MoneyInput label="Harga jual (RM)" value={p.price} onChange={v=>set('price',v??0)}/><MoneyInput label="Kos (RM)" value={p.cost} onChange={v=>set('cost',v??0)}/>
   <Field label="Kategori"><input maxLength={60} value={p.category} onChange={e=>set('category',e.target.value)} placeholder="cth. Minyak, Tayar, Upah"/></Field><Field label="Unit"><input maxLength={20} value={p.unit} onChange={e=>set('unit',e.target.value)}/></Field></div>
   <div className="switch-field"><span>Jejak stok (matikan untuk upah / servis)</span><Switch checked={p.trackStock} disabled={!!initial.id&&initial.trackStock&&initial.stockQty!==0} onCheckedChange={v=>set('trackStock',v)}/></div>
   {p.trackStock&&<div className="form-grid">{!initial.id&&<Field label="Stok awal"><input type="number" min="0" max="100000" value={opening} onChange={e=>setOpening(Math.max(0,Math.trunc(Number(e.target.value))))}/></Field>}<Field label="Amaran stok rendah pada"><input type="number" min="0" max="100000" value={p.reorderLevel} onChange={e=>set('reorderLevel',Math.max(0,Math.trunc(Number(e.target.value))))}/></Field></div>}
   {!!initial.id&&<div className="switch-field"><span>Produk aktif (dijual di kaunter)</span><Switch checked={p.active} onCheckedChange={v=>set('active',v)}/></div>}
   {error&&<p className="form-error" role="alert">{error}</p>}<button className="btn primary" disabled={busy}>{busy?'Menyimpan…':'Simpan produk'}</button></form>
  {moves.length>0&&<section className="pos-moves"><h3>Sejarah stok terkini</h3>{moves.map(m=><div key={m.id}><span>{({receive:'Terima',adjust:'Laras',sale:'Jual',void:'Batal jual',vehicle:'Guna untuk motor',vehicle_return:'Pulang dari motor'} as Record<string,string>)[m.kind]} {m.qty>0?'+':''}{m.qty}{m.saleId?' · '+receiptNo(m.saleId):''}{m.note?' · '+m.note:''}</span><small>{dateText(m.createdAt)} · {m.actorName} · baki {m.balanceAfter}</small></div>)}</section>}
 </DialogContent></Dialog>;
}

function StockDialog({product,kind,onClose,onSaved}:{product:PosProduct;kind:'receive'|'adjust';onClose:()=>void;onSaved:()=>void}){
 const [qty,setQtyValue]=useState(kind==='receive'?1:0);const [cost,setCost]=useState<number|null>(product.cost);const [note,setNote]=useState('');const [busy,setBusy]=useState(false);const [error,setError]=useState('');const request=useRef(crypto.randomUUID());
 async function save(e:React.FormEvent){e.preventDefault();setBusy(true);setError('');try{if(!qty)throw Error('Masukkan kuantiti.');if(kind==='adjust'&&note.trim().length<5)throw Error('Isi sebab pelarasan (cth. rosak, hilang, kiraan stok).');await stockMove(product.id,kind,qty,note,cost,request.current);toast.success(kind==='receive'?'Stok diterima.':'Stok dilaraskan.');onSaved()}catch(e){setError(errorText(e))}finally{setBusy(false)}}
 return <Dialog open onOpenChange={o=>{if(!o&&!busy)onClose()}}><DialogContent className="motor-dialog"><DialogHeader><DialogTitle>{kind==='receive'?'Terima stok':'Laras stok'} · {product.name}</DialogTitle><DialogDescription>Baki semasa: {product.stockQty} {product.unit}. {kind==='adjust'?'Gunakan nombor negatif untuk tolak stok (cth. -2).':'Kos baharu dikemas kini pada produk.'}</DialogDescription></DialogHeader>
  <form onSubmit={save}><div className="form-grid"><Field label={kind==='receive'?'Kuantiti diterima':'Tambah / tolak'}><input type="number" autoFocus required min={kind==='receive'?1:-100000} max="100000" value={qty} onChange={e=>setQtyValue(Math.trunc(Number(e.target.value)))}/></Field>{kind==='receive'&&<MoneyInput label="Kos seunit (RM)" value={cost} onChange={setCost}/>}</div>
   <Field label={kind==='receive'?'Pembekal / no. invois (pilihan)':'Sebab pelarasan'}><input maxLength={500} required={kind==='adjust'} value={note} onChange={e=>setNote(e.target.value)}/></Field>
   {kind==='adjust'&&<p className="form-note">Baki selepas pelarasan: <b>{product.stockQty+qty}</b></p>}
   {error&&<p className="form-error" role="alert">{error}</p>}<button className="btn primary" disabled={busy}>{busy?'Menyimpan…':'Simpan'}</button></form></DialogContent></Dialog>;
}

const dayStart=(iso:string)=>new Date(iso+'T00:00:00+08:00');
const todayKL=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kuala_Lumpur'});
function Sales({onOpen,showVehicleSales}:{onOpen:(s:PosSale)=>void;showVehicleSales:boolean}){
 const [vehicleSales,setVehicleSales]=useState<VehicleSaleRow[]>([]);
 const latestLoad=useRef(0);
 const [day,setDay]=useState(todayKL());const [sales,setSales]=useState<PosSale[]>([]);const [found,setFound]=useState<PosSale[]|null>(null);const [hq,setHq]=useState('');const [searching,setSearching]=useState(false);
 async function searchHistory(e:React.FormEvent){e.preventDefault();if(hq.trim().length<2)return;setSearching(true);try{setFound(await serviceHistory(hq.trim()))}catch(err){toast.error(errorText(err))}finally{setSearching(false)}}const [loading,setLoading]=useState(true);const [error,setError]=useState('');const [query,setQuery]=useState('');
 const load=useCallback(async()=>{
  const revision=++latestLoad.current;
  setLoading(true);setError('');setSales([]);setVehicleSales([]);
  const from=dayStart(day);const to=new Date(from.getTime()+86400000);
  const [counter,motors]=await Promise.allSettled([
   loadSales(from,to),showVehicleSales?loadVehicleSales(from,to):Promise.resolve([]),
  ]);
  if(revision!==latestLoad.current)return;
  if(counter.status==='fulfilled')setSales(counter.value);
  if(motors.status==='fulfilled')setVehicleSales(motors.value);
  setError([counter,motors].flatMap(result=>result.status==='rejected'?[errorText(result.reason)]:[]).join(' '));
  setLoading(false);
 },[day,showVehicleSales]);
 useEffect(()=>{void load();return()=>{latestLoad.current++}},[load]);
 const done=sales.filter(s=>s.status==='completed');
 const needle=query.trim().toLowerCase();
 const shown=[
  ...sales.filter(s=>[receiptNo(s.id),s.customerName,s.customerPhone,s.cashierName,s.plate].join(' ').toLowerCase().includes(needle)).map(s=>({kind:'pos' as const,time:s.createdAt,s})),
  ...vehicleSales.filter(v=>[vehicleId(v.id,v.stockNo??undefined),v.brand,v.model,v.plate,v.buyer,v.buyerPhone].join(' ').toLowerCase().includes(needle)).map(v=>({kind:'motor' as const,time:v.soldAt,v})),
 ].sort((a,b)=>new Date(b.time).getTime()-new Date(a.time).getTime());
 function printMotorInvoice(id:number){
  void printRecordFrom(()=>Promise.all([getRecord('vehicles',id),loadPayments('vehicles',id)]),'invoice').catch(e=>toast.error(errorText(e)));
 }
 return <section>
  <div className="filters"><Field label="Tarikh"><input type="date" value={day} max={todayKL()} onChange={e=>e.target.value&&setDay(e.target.value)}/></Field><div className="search"><Search size={18}/><input aria-label="Cari jualan" placeholder="No. stok, no. resit, plat atau pelanggan…" value={query} onChange={e=>setQuery(e.target.value)}/></div><button className="btn subtle" disabled={loading} onClick={()=>void load()}><RefreshCw size={16}/>Muat semula</button></div>
  <div className="stats pos-stats"><div className="stat"><div><span>Bil. jualan</span><Receipt size={18}/></div><strong>{loading?'—':done.length+vehicleSales.length}</strong></div><div className="stat"><div><span>Jumlah jualan</span><Banknote size={18}/></div><strong>{loading?'—':money(done.reduce((s,x)=>s+x.total,0)+vehicleSales.reduce((s,v)=>s+v.price,0))}</strong></div><div className="stat"><div><span>Dibatalkan</span><X size={18}/></div><strong>{loading?'—':sales.length-done.length}</strong></div></div>
  <form className="operation-panel pos-history-search" onSubmit={searchHistory}><h3><Wrench size={17}/>Sejarah servis motosikal</h3><div className="search"><Search size={18}/><input aria-label="Cari sejarah servis" placeholder="No. plat, telefon atau nama pelanggan…" value={hq} onChange={e=>setHq(e.target.value)}/></div><button className="btn subtle" disabled={searching||hq.trim().length<2}>{searching?'Mencari…':'Cari'}</button>
   {found&&(found.length?<div className="pos-product-list">{found.map(s=><button type="button" key={s.id} className="pos-product-row pos-sale-row" onClick={()=>void loadSale(s.id).then(onOpen).catch(err=>toast.error(errorText(err)))}><div><b>{s.plate} · {s.bike||'—'}</b><small>{dateText(s.createdAt)} · {receiptNo(s.id)}{s.mileage?' · '+s.mileage.toLocaleString('ms-MY')+' km':''}{s.workNotes?' · '+s.workNotes:''}</small></div><div className="pos-row-stock"><span>{s.mechanic||''}</span><strong>{money(s.total)}</strong></div></button>)}</div>:<p className="muted">Tiada rekod servis dijumpai.</p>)}</form>
  {error&&<p className="form-error" role="alert">{error}</p>}
  <div className="pos-product-list">{shown.map(row=>{if(row.kind==='motor'){
   const v=row.v;
   const phone=normalizePhone(v.buyerPhone||'');
   const invoiceRef='INV-'+vehicleId(v.id,v.stockNo??undefined);
   const message='Salam '+v.buyer+', terima kasih membeli '+v.brand+' '+v.model+' di 3 Abdul Motor. Rujukan invois anda '+invoiceRef+'.';
   const whatsapp=/^[1-9][0-9]{8,14}$/.test(phone)?'https://wa.me/'+phone+'?text='+encodeURIComponent(message):'';
   return <div key={'motor-'+v.id} className="pos-product-row pos-sale-row"><div><b>{v.brand} {v.model} <span className="pos-badge"><Bike size={12}/>Jualan motor</span></b><small>{vehicleId(v.id,v.stockNo??undefined)}{v.plate?' · '+v.plate:''} · {v.buyer} · {dateText(v.soldAt)}</small></div><div className="pos-row-stock"><strong>{money(v.price)}</strong><div className="action-row"><a className="quiet-link" href={'#inventory?record='+v.id}>Lihat rekod</a><button type="button" className="btn subtle" onClick={()=>printMotorInvoice(v.id)}><Printer size={15}/>Invois</button>{whatsapp?<a className="btn subtle" href={whatsapp} target="_blank" rel="noopener noreferrer"><MessageCircle size={15}/>WhatsApp</a>:<button type="button" className="btn subtle" disabled title="Nombor telefon pembeli belum tersedia"><MessageCircle size={15}/>WhatsApp</button>}</div></div></div>;
  }
  const s=row.s;
  return <button key={'pos-'+s.id} className={'pos-product-row pos-sale-row'+(s.status==='voided'?' inactive':'')} onClick={()=>void loadSale(s.id).then(onOpen).catch(e=>toast.error(errorText(e)))}><div><b>{receiptNo(s.id)}{s.saleType==='service'&&<span className="pos-badge"><Wrench size={12}/>Servis · {s.plate}</span>}{s.status==='voided'?' · DIBATALKAN':''}</b><small>{new Date(s.createdAt).toLocaleTimeString('ms-MY',{timeZone:'Asia/Kuala_Lumpur',hour:'2-digit',minute:'2-digit'})} · {s.customerName||'Walk-in'} · {s.cashierName}</small></div><div className="pos-row-stock"><span>{[...new Set((s.payments||[]).filter(p=>p.amount>0).map(p=>methodLabels[p.method]))].join(' + ')}</span><strong>{money(s.total)}</strong></div></button>;})}{!loading&&!error&&!shown.length&&<p className="muted">Tiada jualan pada tarikh ini.</p>}</div>
 </section>;
}

function SaleDialog({sale,owner,onClose,onChanged,fresh=false}:{sale:PosSale;owner:boolean;onClose:()=>void;onChanged:(s:PosSale)=>void;fresh?:boolean}){
 const [voiding,setVoiding]=useState(false);const [reason,setReason]=useState('');const [busy,setBusy]=useState(false);const [error,setError]=useState('');const wa=receiptWhatsapp(sale);
 async function doVoid(){setBusy(true);setError('');try{onChanged(await voidSale(sale.id,reason));toast.success('Jualan dibatalkan. Bayaran direkod sebagai refund dan stok dipulangkan.');setVoiding(false)}catch(e){setError(errorText(e))}finally{setBusy(false)}}
 return <Dialog open onOpenChange={o=>{if(!o&&!busy)onClose()}}><DialogContent className="motor-dialog pos-sale-dialog"><DialogHeader><DialogTitle>{receiptNo(sale.id)}{sale.status==='voided'?' · Dibatalkan':''}</DialogTitle><DialogDescription>{dateText(sale.createdAt)} · {sale.cashierName}{sale.customerName?' · '+sale.customerName:''}</DialogDescription></DialogHeader>
  {sale.saleType==='service'&&<div className="pos-service-summary"><b><Wrench size={15}/>Servis · {sale.plate}{sale.bike?' · '+sale.bike:''}</b><span>{[sale.mechanic&&'Mekanik: '+sale.mechanic,sale.mileage?sale.mileage.toLocaleString('ms-MY')+' km':''].filter(Boolean).join(' · ')}</span>{sale.workNotes&&<p>{sale.workNotes}</p>}</div>}
  {fresh&&sale.changeGiven>0&&<div className="pos-change-big">Pulangkan baki <b>{money(sale.changeGiven)}</b></div>}
  <ul className="pos-receipt-lines">{(sale.lines||[]).map(l=><li key={l.id}><span>{l.qty} × {l.name}{sale.saleType==='service'&&l.kind?<small className="pos-kind"> · {kindLabels[l.kind]}</small>:null}</span><span>{money(l.qty*l.unitPrice)}</span></li>)}{sale.discount>0&&<li><span>Diskaun</span><span>-{money(sale.discount)}</span></li>}<li className="pos-grand"><span>Jumlah</span><span>{money(sale.total)}</span></li></ul>
  <ul className="pos-receipt-lines muted">{(sale.payments||[]).map(p=><li key={p.id}><span>{p.amount<0?'Refund ':''}{methodLabels[p.method]} · {p.receiverName}</span><span>{money(p.amount)}</span></li>)}</ul>
  {sale.status==='voided'&&<p className="form-note">Sebab batal: {sale.voidReason}</p>}
  <div className="action-row"><button className="btn primary" onClick={()=>{try{printReceipt(sale)}catch(e){toast.error(errorText(e))}}}><Printer size={16}/>Cetak resit</button><button className="btn subtle" onClick={()=>void printPosInvoice(sale).catch(e=>toast.error(errorText(e)))}><Printer size={16}/>Invois A4</button>{wa&&<a className="btn subtle" target="_blank" rel="noopener noreferrer" href={wa}><MessageCircle size={16}/>Resit ringkas (teks)</a>}<button className="btn subtle" onClick={onClose}>{fresh?'Jualan seterusnya':'Tutup'}</button></div>
  {sale.status==='completed'&&<PdfWhatsapp key={sale.id} prepare={()=>posInvoicePdf(sale)} phone={sale.customerPhone} message={'Salam '+(sale.customerName||'tuan/puan')+', ini invois '+(sale.saleType==='service'?'servis':'pembelian')+' '+receiptNo(sale.id)+(sale.saleType==='service'&&sale.plate?' untuk '+sale.plate:'')+' berjumlah '+money(sale.total)+'. Saya hantar PDF selepas mesej ini. Terima kasih daripada 3 Abdul Motor.'}/>}
  {owner&&sale.status==='completed'&&(!voiding?<button className="btn subtle pos-small" onClick={()=>setVoiding(true)}>Batalkan jualan (owner)</button>:<div className="pos-void"><Field label="Sebab pembatalan"><input autoFocus maxLength={500} value={reason} onChange={e=>setReason(e.target.value)} placeholder="cth. Pelanggan pulangkan barang"/></Field><p className="form-note">Semua bayaran direkod sebagai refund dan stok dipulangkan. Tidak boleh diundur.</p><button className="btn primary" disabled={busy||reason.trim().length<5} onClick={()=>void doVoid()}>{busy?'Membatalkan…':'Sahkan pembatalan'}</button></div>)}
  {error&&<p className="form-error" role="alert">{error}</p>}
 </DialogContent></Dialog>;
}

function ShiftPanel({shift,onChanged}:{shift:PosShift|null;onChanged:()=>Promise<void>}){
 const [report,setReport]=useState<ShiftReport|null>(null);const [history,setHistory]=useState<PosShift[]>([]);const [counted,setCounted]=useState<number|null>(null);const [note,setNote]=useState('');const [float,setFloat]=useState<number|null>(null);const [busy,setBusy]=useState(false);const [error,setError]=useState('');
 const load=useCallback(async()=>{try{setHistory(await loadShifts());setReport(shift?await shiftReport(shift.id):null)}catch(e){setError(errorText(e))}},[shift]);
 useEffect(()=>{void load()},[load]);
 const variance=report&&counted!==null?counted-report.expectedCash:0;
 async function close(e:React.FormEvent){e.preventDefault();if(!shift||counted===null)return;const w=printWindow();setBusy(true);setError('');try{const closed=await closeShift(shift,counted,note);const final=await shiftReport(closed.id);toast.success('Kaunter ditutup.');try{printShift(final,closed,w)}catch{toast.warning('Benarkan pop-up untuk cetak laporan. Laporan boleh dicetak semula dari sejarah tutup kaunter.')}setCounted(null);setNote('');await onChanged()}catch(e){w?.close();setError(errorText(e))}finally{setBusy(false)}}
 async function open(){setBusy(true);setError('');try{await openShift(float??0);toast.success('Kaunter dibuka.');await onChanged()}catch(e){setError(errorText(e))}finally{setBusy(false)}}
 return <section className="pos-shift">
  {!shift?<div className="operation-panel"><h3>Kaunter belum dibuka</h3><p className="muted">Tidak perlu buka secara manual — jualan pertama membuka kaunter dengan float RM0. Buka di sini hanya jika ada duit float dalam laci.</p><div className="form-grid"><MoneyInput label="Duit float dalam laci (RM)" value={float} onChange={setFloat}/></div><button className="btn primary" disabled={busy} onClick={()=>void open()}>Buka kaunter</button></div>:
  <div className="operation-panel"><div className="section-label"><h3>Kaunter semasa · #{shift.id}</h3><button className="btn subtle" onClick={()=>void load()}><RefreshCw size={16}/>Muat semula</button></div>
   {report&&<div className="pos-report"><div><span>Bil. jualan</span><b>{report.salesCount}</b></div><div><span>Jualan bersih</span><b>{money(report.net)}</b></div>{report.parts!==undefined&&<><div><span>Alat ganti</span><b>{money(report.parts)}</b></div><div><span>Upah kerja{report.serviceCount?' · '+report.serviceCount+' servis':''}</span><b>{money(report.labour||0)}</b></div></>}{(Object.entries(report.methods) as [PayMethod,number][]).map(([m,v])=><div key={m}><span>{methodLabels[m]}</span><b>{money(v)}</b></div>)}<div><span>Float</span><b>{money(shift.openingFloat)}</b></div><div className="pos-grand"><span>Tunai sepatutnya dalam laci</span><b>{money(report.expectedCash)}</b></div></div>}{report?.labourBy&&report.labourBy.length>0&&<div className="pos-labour-by"><b>Upah ikut mekanik</b>{report.labourBy.map(l=><span key={l.name}>{l.name} · {l.jobs??0} servis · <b>{money(l.amount)}</b></span>)}</div>}
   <form onSubmit={close}><div className="form-grid"><MoneyInput label="Tunai dikira dalam laci (RM)" value={counted} onChange={setCounted}/>{counted!==null&&report&&<p className={'pos-variance'+(variance===0?' ok':'')}>{variance===0?'Tepat ✓':variance>0?'Lebih '+money(variance):'Kurang '+money(-variance)}</p>}</div>{counted!==null&&variance!==0&&<Field label="Sebab perbezaan"><input required minLength={5} maxLength={1000} value={note} onChange={e=>setNote(e.target.value)}/></Field>}
    {error&&<p className="form-error" role="alert">{error}</p>}<button className="btn primary" disabled={busy||counted===null}>{busy?'Menutup…':'Tutup kaunter & cetak laporan'}</button></form></div>}
  {history.filter(h=>h.closedAt).length>0&&<div className="operation-panel"><h3>Sejarah tutup kaunter</h3><div className="pos-product-list">{history.filter(h=>h.closedAt).map(h=><button key={h.id} className="pos-product-row" onClick={()=>void shiftReport(h.id).then(r=>printShift(r,h)).catch(e=>toast.error(errorText(e)))}><div><b>#{h.id} · {dateText(h.closedAt!)}</b><small>{h.openerName} → {h.closerName}{h.note?' · '+h.note:''}</small></div><div className="pos-row-stock"><span className={h.countedCash!==h.expectedCash?'low':''}>{h.countedCash===h.expectedCash?'Tepat':'Beza '+money((h.countedCash??0)-(h.expectedCash??0))}</span><strong>{money(h.countedCash??0)}</strong></div></button>)}</div></div>}
 </section>;
}

/** Spare-parts stock inside the Inventory page; same products and stock ledger as the POS. */
export function PartsInventory({staff}:{staff:StaffProfile|null}){
 // Inventory editors can read parts (they take parts for motorcycles); managing stays with POS managers.
 const allowed=canAccess(staff,'pos')||can(staff,'inventory_edit');const manager=can(staff,'pos_manage');
 const [products,setProducts]=useState<PosProduct[]>([]);const [loading,setLoading]=useState(true);const [error,setError]=useState('');
 const reload=useCallback(async()=>{setLoading(true);try{setProducts(await loadProducts());setError('')}catch(e){setError(errorText(e))}finally{setLoading(false)}},[]);
 useEffect(()=>{if(allowed)void reload()},[allowed,reload]);
 if(!allowed)return <div className="demo-banner"><Package size={18}/><span>Akses alat ganti diberi oleh owner di Akses staf: <b>POS: urus</b> untuk tambah produk dan terima stok, atau <b>POS: jual</b> / <b>Inventori: edit</b> untuk lihat.</span></div>;
 return <div className="parts-inventory">{error&&<div className="error-banner" role="alert"><span>{error}</span><button className="btn subtle" onClick={()=>void reload()}><RefreshCw size={16}/>Cuba semula</button></div>}<Products products={products} loading={loading} manager={manager} onChanged={reload}/></div>;
}
