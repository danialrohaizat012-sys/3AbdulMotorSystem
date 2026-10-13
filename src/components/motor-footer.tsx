import {useEffect,useState} from 'react';
import {ArrowUpRight,MapPin} from 'lucide-react';
import {loadSettings} from '../lib/records';
import {safeFooterUrl} from '../lib/business';
import type {BusinessSettings} from '../lib/business';

function TikTokIcon(){return <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="currentColor"><path d="M16.5 2h-3.4v13.3a3 3 0 1 1-2.6-3V8.8a6.4 6.4 0 1 0 6 6.4V8.7a9.2 9.2 0 0 0 5.5 1.8V7.1a5.9 5.9 0 0 1-5.5-5.1Z"/></svg>}
function FacebookIcon(){return <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="currentColor"><path d="M14 22v-9h3l.5-3.5H14V7.3c0-1 .3-1.7 1.8-1.7h1.9V2.5a25 25 0 0 0-2.8-.2c-2.8 0-4.7 1.7-4.7 4.8v2.4H7V13h3.2v9Z"/></svg>}
function WhatsAppIcon(){return <svg viewBox="0 0 24 24" width="19" height="19" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M20.7 11.6a8.7 8.7 0 0 1-13 7.6L3 20.5l1.3-4.6A8.7 8.7 0 1 1 20.7 11.6Z"/><path d="M8.2 7.6c-.8.5-1.1 1.2-.8 2.2.6 2.3 2.6 4.3 4.8 5.1 1 .4 1.9.2 2.4-.6l.6-1-2.3-1.2-.8.9a6.8 6.8 0 0 1-2.7-2.7l.8-.9-1.1-2.3-.9.5Z"/></svg>}
export function MotorFooter({settings:provided}:{settings?:BusinessSettings|null}) {
 const [settings,setSettings]=useState<BusinessSettings|null>(provided||null);
 useEffect(()=>{let live=true;if(provided!==undefined)setSettings(provided);else void loadSettings().then(s=>{if(live)setSettings(s)}).catch(()=>{});const updated=(event:Event)=>setSettings((event as CustomEvent<BusinessSettings>).detail);window.addEventListener('3am-settings-changed',updated);return()=>{live=false;window.removeEventListener('3am-settings-changed',updated)}},[provided]);
 const links=[{label:'TikTok',url:settings?.tiktokUrl,icon:<TikTokIcon/>},{label:'Facebook',url:settings?.facebookUrl,icon:<FacebookIcon/>},{label:'Maps',url:settings?.mapsUrl,icon:<MapPin size={18} aria-hidden="true"/>},{label:'WhatsApp',url:settings?.footerWhatsappUrl,icon:<WhatsAppIcon/>}];
 return <footer className="page-footer motor-footer"><span>© {new Date().getFullYear()} 3 Abdul Motor</span><nav className="footer-socials" aria-label="Hubungi 3 Abdul Motor">{links.map(l=>{const href=safeFooterUrl(l.url);return href?<a key={l.label} href={href} target="_blank" rel="noopener noreferrer" aria-label={'Buka '+l.label+' (tab baharu)'} title={l.label}>{l.icon}</a>:<button key={l.label} type="button" disabled aria-label={l.label+' · pautan belum ditetapkan'} title={l.label+' · pautan belum ditetapkan'}>{l.icon}</button>})}</nav><a className="footer-credit" href="https://binalab.my/" target="_blank" rel="noopener noreferrer" aria-label="Lawati website BinaLab (tab baharu)"><span>Built by <b>BinaLab</b></span><ArrowUpRight size={12} aria-hidden="true" /></a></footer>;
}
