import {Component} from 'react';
import type {ReactNode} from 'react';
const CHUNK=/dynamically imported module|Importing a module script failed|Failed to fetch|Loading (CSS )?chunk|error loading dynamically/i;
/** Catches render/lazy-load errors. After a deploy, old code chunks no longer exist: reload once automatically,
 * then offer a manual reload instead of a blank screen. */
export class AppErrorBoundary extends Component<{children:ReactNode},{error:Error|null}>{
 state={error:null as Error|null};
 static getDerivedStateFromError(error:Error){return {error}}
 componentDidCatch(error:Error){if(CHUNK.test(error.message)){try{if(!sessionStorage.getItem('3am-chunk-reload')){sessionStorage.setItem('3am-chunk-reload','1');location.reload()}}catch{}}}
 render(){const e=this.state.error;if(!e)return this.props.children;const update=CHUNK.test(e.message);
  return <main className="login-page"><section className="login-card"><h1>{update?'Versi baharu tersedia':'Ralat tidak dijangka'}</h1><p>{update?'Sistem telah dikemas kini. Muat semula untuk teruskan.':'Muat semula halaman. Jika berulang, maklumkan langkah sebelum ralat ini.'}</p><button className="btn primary" onClick={()=>{try{sessionStorage.removeItem('3am-chunk-reload')}catch{};location.reload()}}>Muat semula</button></section></main>}
}
