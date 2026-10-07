import {useEffect,useState} from 'react';
import {Users} from 'lucide-react';
import {visitorStats} from '../lib/visitors';
import type {VisitorStats} from '../lib/visitors';
export function VisitorCounter(){const [stats,setStats]=useState<VisitorStats|null>(null);const [failed,setFailed]=useState(false);useEffect(()=>{let live=true;void visitorStats().then(s=>{if(live)setStats(s)}).catch(()=>{if(live)setFailed(true)});return()=>{live=false}},[]);return <section className="visitor-counter" aria-label="Lawatan katalog"><div className="visitor-title"><Users size={19}/><div><b>Lawatan katalog</b><small>Anggaran · sekali bagi setiap pelayar sehari</small></div></div><div className="visitor-counts"><span>Hari ini<strong>{stats?stats.today.toLocaleString('ms-MY'):'—'}</strong></span><span>Jumlah lawatan<strong>{stats?stats.total.toLocaleString('ms-MY'):'—'}</strong></span></div>{failed&&<small>Counter sementara tidak tersedia.</small>}</section>}
