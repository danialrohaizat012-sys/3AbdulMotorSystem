import {useState} from 'react';
import {Download,FileText,MessageCircle,Share2} from 'lucide-react';
import {Field} from './motor-fields';

/** Send an invoice PDF to a customer on WhatsApp. WhatsApp links cannot attach files, so:
 *  1) open the customer's chat (works for unsaved numbers), 2) share the PDF to that chat from the phone's
 *  share sheet, or download it and drag it into WhatsApp Web on a computer. */
export function PdfWhatsapp({prepare,phone:initialPhone,message,title='Hantar invois PDF ke WhatsApp'}:{prepare:()=>Promise<File>;phone:string;message:string;title?:string}){
 const [file,setFile]=useState<File|null>(null);const [busy,setBusy]=useState(false);const [error,setError]=useState('');const [phone,setPhone]=useState(initialPhone);
 const digits=(()=>{let d=phone.replace(/\D/g,'');if(d.startsWith('0'))d='60'+d.slice(1);return d})();
 const chat=/^[1-9][0-9]{8,14}$/.test(digits)?'https://wa.me/'+digits+'?text='+encodeURIComponent(message):'';
 const canShare=!!file&&typeof navigator.share==='function'&&!!navigator.canShare?.({files:[file]});
 async function make(){setBusy(true);setError('');try{setFile(await prepare())}catch(e){setError(e instanceof Error?e.message:'PDF gagal dijana.')}finally{setBusy(false)}}
 async function share(){if(!file)return;setError('');try{await navigator.share({files:[file],title:file.name})}catch(e){if(!(e instanceof DOMException&&e.name==='AbortError'))setError('Kongsi tidak berjaya. Muat turun PDF dan lampirkan dalam WhatsApp.')}}
 function download(){if(!file)return;const url=URL.createObjectURL(file);const a=document.createElement('a');a.href=url;a.download=file.name;a.click();window.setTimeout(()=>URL.revokeObjectURL(url),60_000)}
 return <section className="pdf-whatsapp" aria-label={title}><h3><MessageCircle size={17}/>{title}</h3>
  {!initialPhone&&<Field label="No. WhatsApp pelanggan"><input inputMode="tel" maxLength={20} value={phone} onChange={e=>setPhone(e.target.value)} placeholder="012-345 6789"/></Field>}
  {!file?<button className="btn primary" disabled={busy} onClick={()=>void make()}><FileText size={16}/>{busy?'Menjana PDF…':'Sediakan PDF'}</button>:<>
   <ol className="pdf-steps">
    <li><span>1. Buka chat pelanggan</span>{chat?<a className="btn subtle" target="_blank" rel="noopener noreferrer" href={chat}><MessageCircle size={16}/>Buka WhatsApp</a>:<small>Isi nombor WhatsApp pelanggan di atas.</small>}</li>
    <li><span>2. Hantar fail PDF ke chat itu</span><div className="action-row">{canShare&&<button className="btn primary" onClick={()=>void share()}><Share2 size={16}/>Kongsi PDF</button>}<button className="btn subtle" onClick={download}><Download size={16}/>Muat turun PDF</button></div>
     <small>{canShare?'Pilih WhatsApp, kemudian chat pelanggan (paling atas selepas langkah 1).':'Di komputer: muat turun, kemudian seret fail ke chat WhatsApp Web.'}</small></li>
   </ol></>}
  {error&&<p className="form-error" role="alert">{error}</p>}
 </section>;
}
