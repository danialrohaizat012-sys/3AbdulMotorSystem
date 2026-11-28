import {Component} from 'react';
import type {ReactNode} from 'react';
const CHUNK=/dynamically imported module|Importing a module script failed|Failed to fetch|Loading (CSS )?chunk|error loading dynamically/i;
/** Catches render/lazy-load errors. After a deploy, old code chunks no longer exist: reload once automatically,
 * then offer a manual reload instead of a blank screen. */
export class AppErrorBoundary extends Component<{children:ReactNode},{error:Error|null}>{
 state={error:null as Error|null};
 static getDerivedStateFromError(error:Error){return {error}}
 componentDidCatch(error:Error){if(!CHUNK.test(error.message)||!navigator.onLine)return;
  // Reload only for a new deploy (old file now 404), never for a dropped connection.
  const url=error.message.match(/https?:\/\/\S+\.js/)?.[0];
  void (url?fetch(url,{method:'HEAD',cache:'no-store'}).then(r=>r.status===404).catch(()=>false):Promise.resolve(false)).then(gone=>{if(!gone)return;try{if(!sessionStorage.getItem('3am-chunk-reload')){sessionStorage.setItem('3am-chunk-reload','1');location.reload()}}catch{}})}
 render(){const e=this.state.error;if(!e)return this.props.children;const update=CHUNK.test(e.message);
  return <main className="login-page"><section className="login-card"><h1>{update?(navigator.onLine?'Versi baharu tersedia':'Sambungan terputus'):'Ralat tidak dijangka'}</h1><p>{update?(navigator.onLine?'Sistem telah dikemas kini atau sambungan terganggu. Muat semula untuk teruskan.':'Semak internet, kemudian tekan Muat semula.'):'Muat semula halaman. Jika berulang, maklumkan langkah sebelum ralat ini.'}</p><button className="btn primary" onClick={()=>{try{sessionStorage.removeItem('3am-chunk-reload')}catch{};location.reload()}}>Muat semula</button></section></main>}
}
