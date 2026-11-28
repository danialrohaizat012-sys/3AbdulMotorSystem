import {Copy} from 'lucide-react';
import {toast} from 'sonner';
import {stockLink} from '../lib/business';
export async function copyStockLink(id:number){const link=stockLink(id);try{await navigator.clipboard.writeText(link);toast.success('Pautan motosikal disalin.')}catch{toast.error('Tidak dapat salin automatik. Pautan: '+link)}}
export function ShareButton({id}:{id:number}){return <button className="btn subtle" onClick={()=>void copyStockLink(id)}><Copy size={16}/>Salin pautan</button>}
