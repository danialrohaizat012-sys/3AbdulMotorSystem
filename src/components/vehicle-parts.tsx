import {useEffect,useMemo,useRef,useState} from 'react';
import {toast} from 'sonner';
import {PackageMinus,Plus,Search,Undo2} from 'lucide-react';
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from './ui/dialog';
import {Field} from './motor-fields';
import {takeVehiclePart,returnVehiclePart} from '../lib/records';
import {loadProducts} from '../lib/pos';
import {money,parseLines} from '../lib/motor';
import type {Vehicle} from '../lib/motor';
import type {PosProduct} from '../lib/pos-model';
import {can} from '../lib/staff';
import type {StaffProfile} from '../lib/staff';

/** Spare parts taken from POS stock to prepare this motorcycle. Cost goes into the bike's preparation cost. */
export function VehicleParts({vehicle,staff,onChanged}:{vehicle:Vehicle;staff:StaffProfile|null;onChanged:()=>Promise<void>}){
 const used=parseLines(vehicle.prepItems||'[]').filter(l=>l.moveId);
 const editable=can(staff,'inventory_edit')&&vehicle.status!=='sold';
 const [picking,setPicking]=useState(false);const [busy,setBusy]=useState<number|null>(null);
 if(!editable&&!used.length)return null;
 async function giveBack(moveId:number){if(busy!==null)return;setBusy(moveId);try{await returnVehiclePart(vehicle,moveId,crypto.randomUUID());toast.success('Alat ganti dipulangkan ke stok.');await onChanged()}catch(e){toast.error((e as Error).message)}finally{setBusy(null)}}
 return <section className="operation-panel vehicle-parts"><div className="section-label"><h3><PackageMinus size={18}/>Alat ganti untuk motor ini</h3>{editable&&<button className="btn subtle" onClick={()=>setPicking(true)}><Plus size={16}/>Ambil dari stok</button>}</div>
  {used.length?<ul>{used.map(l=><li key={l.moveId}><span>{l.qty} × {l.name.replace(/^Alat ganti: /,'')}</span><b>{money(l.qty*l.rate)}</b>{editable&&<button className="btn subtle pos-small" disabled={busy!==null} onClick={()=>void giveBack(l.moveId!)}><Undo2 size={14}/>{busy===l.moveId?'…':'Pulangkan'}</button>}</li>)}</ul>:<p className="form-note">Belum ada. Alat ganti yang diambil akan ditolak dari stok dan dicampur ke kos persediaan (harga kos purata).</p>}
  {picking&&<PartPicker vehicle={vehicle} onClose={()=>setPicking(false)} onDone={async()=>{setPicking(false);await onChanged()}}/>}
 </section>;
}

function PartPicker({vehicle,onClose,onDone}:{vehicle:Vehicle;onClose:()=>void;onDone:()=>Promise<void>}){
 const [products,setProducts]=useState<PosProduct[]>([]);const [query,setQuery]=useState('');const [chosen,setChosen]=useState<PosProduct|null>(null);const [qty,setQty]=useState(1);const [busy,setBusy]=useState(false);const [error,setError]=useState('');const request=useRef(crypto.randomUUID());
 useEffect(()=>{void loadProducts().then(setProducts).catch(e=>setError((e as Error).message))},[]);
 const list=useMemo(()=>{const q=query.trim().toLowerCase();return products.filter(p=>p.active&&p.trackStock&&(!q||(p.name+' '+p.sku+' '+p.barcode).toLowerCase().includes(q))).slice(0,40)},[products,query]);
 async function save(e:React.FormEvent){e.preventDefault();if(!chosen)return;setBusy(true);setError('');try{if(qty<1||qty>chosen.stockQty)throw Error('Baki stok '+chosen.name+' hanya '+chosen.stockQty+'.');await takeVehiclePart(vehicle,chosen.id,qty,request.current);toast.success(qty+' × '+chosen.name+' diambil untuk motosikal ini.');await onDone()}catch(err){setError((err as Error).message)}finally{setBusy(false)}}
 return <Dialog open onOpenChange={o=>{if(!o&&!busy)onClose()}}><DialogContent className="motor-dialog"><DialogHeader><DialogTitle>Ambil alat ganti dari stok</DialogTitle><DialogDescription>{vehicle.brand} {vehicle.model} · stok ditolak dan kos ditambah ke kos persediaan.</DialogDescription></DialogHeader>
  <form onSubmit={save}>
   <div className="search"><Search size={18}/><input autoFocus aria-label="Cari alat ganti" placeholder="Cari nama, SKU atau scan barcode…" value={query} onChange={e=>{setQuery(e.target.value);setChosen(null)}}/></div>
   <div className="part-picker-list">{list.map(p=><button type="button" key={p.id} aria-pressed={chosen?.id===p.id} className={chosen?.id===p.id?'active':''} disabled={p.stockQty<=0} onClick={()=>{setChosen(p);setQty(1);request.current=crypto.randomUUID()}}><span>{p.name}<small>{p.sku} · baki {p.stockQty} {p.unit}</small></span><b>{money(p.cost)}</b></button>)}{!list.length&&<p className="muted">Tiada alat ganti sepadan.</p>}</div>
   {chosen&&<div className="form-grid"><Field label="Kuantiti"><input type="number" min="1" max={chosen.stockQty} value={qty} onChange={e=>setQty(Math.max(1,Math.trunc(Number(e.target.value))||1))}/></Field><p className="form-note">Kos ditambah: <b>{money(qty*chosen.cost)}</b> (kos purata).</p></div>}
   {error&&<p className="form-error" role="alert">{error}</p>}
   <button className="btn primary" disabled={busy||!chosen}>{busy?'Menyimpan…':'Ambil untuk motosikal'}</button>
  </form></DialogContent></Dialog>;
}
