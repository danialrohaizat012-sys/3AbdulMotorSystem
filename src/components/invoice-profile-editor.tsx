import {useState} from 'react';
import {FileText} from 'lucide-react';
import {toast} from 'sonner';
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from './ui/dialog';
import {Field} from './motor-fields';
import {loadInvoiceProfile,saveInvoiceProfile} from '../lib/invoice-profile';
import type {InvoiceProfile} from '../lib/invoice-model';

/** Owner-only: business details printed on invoices, estimates and receipts. */
export function InvoiceProfileButton(){
 const [open,setOpen]=useState(false);const [p,setP]=useState<InvoiceProfile|null>(null);const [busy,setBusy]=useState(false);const [error,setError]=useState('');
 async function show(){setOpen(true);setP(null);setError('');try{setP(await loadInvoiceProfile(true))}catch(e){setError((e as Error).message)}}
 const set=(k:keyof InvoiceProfile)=>(e:React.ChangeEvent<HTMLInputElement|HTMLTextAreaElement>)=>setP(x=>x&&{...x,[k]:e.target.value});
 async function save(e:React.FormEvent){e.preventDefault();if(!p)return;setBusy(true);setError('');try{await saveInvoiceProfile(p);toast.success('Maklumat invois disimpan.');setOpen(false)}catch(e){setError((e as Error).message)}finally{setBusy(false)}}
 return <><button className="btn subtle" onClick={()=>void show()}><FileText size={16}/>Maklumat invois</button>
 <Dialog open={open} onOpenChange={o=>{if(!busy)setOpen(o)}}><DialogContent className="motor-dialog"><DialogHeader><DialogTitle>Maklumat invois</DialogTitle><DialogDescription>Dicetak pada invois, anggaran dan resit. Biarkan kosong jika tiada; medan kosong tidak dipaparkan.</DialogDescription></DialogHeader>
 {!p?<p className="muted">{error||'Memuatkan…'}</p>:<form onSubmit={save}>
  {p.version===undefined&&<p className="form-note">Pangkalan data belum dinaik taraf (supabase/invoice-profile.sql). Invois masih boleh dicetak dengan nama kedai dan nombor WhatsApp katalog.</p>}
  <div className="form-grid"><Field label="Nama perniagaan"><input required maxLength={120} value={p.businessName} onChange={set('businessName')}/></Field><Field label="No. pendaftaran (SSM)"><input maxLength={60} value={p.registrationNo} onChange={set('registrationNo')} placeholder="cth. 202301234567 (1234567-X)"/></Field></div>
  <Field label="Alamat kedai"><textarea rows={2} maxLength={400} value={p.address} onChange={set('address')}/></Field>
  <div className="form-grid"><Field label="Telefon"><input inputMode="tel" maxLength={40} value={p.phone} onChange={set('phone')}/></Field><Field label="E-mel"><input type="email" maxLength={120} value={p.email} onChange={set('email')}/></Field>
  <Field label="Nama bank"><input maxLength={80} value={p.bankName} onChange={set('bankName')} placeholder="cth. Maybank"/></Field><Field label="No. akaun bank"><input inputMode="numeric" maxLength={34} value={p.bankAccountNo} onChange={set('bankAccountNo')}/></Field></div>
  <Field label="Nama pemegang akaun"><input maxLength={120} value={p.bankAccountName} onChange={set('bankAccountName')}/></Field>
  <Field label="Terma & syarat (pilihan)"><textarea rows={3} maxLength={1500} value={p.terms} onChange={set('terms')} placeholder="cth. Barang yang dijual tidak boleh dipulangkan. Waranti enjin 30 hari."/></Field>
  <p className="form-note">Butiran bank hanya dipaparkan pada invois yang masih ada baki dan pada anggaran.</p>
  {error&&<p className="form-error" role="alert">{error}</p>}<button className="btn primary" disabled={busy||p.version===undefined}>{busy?'Menyimpan…':'Simpan'}</button></form>}
 </DialogContent></Dialog></>;
}
