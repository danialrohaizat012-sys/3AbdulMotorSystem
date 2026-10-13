import {Gift,ClipboardCheck,WalletCards,ShieldCheck} from 'lucide-react';
const benefits=[
 {title:'Freegift menarik',description:'Tanya kami tentang hadiah untuk pembelian anda.',Icon:Gift},
 {title:'Passed inspection',description:'Motosikal diperiksa sebelum penyerahan.',Icon:ClipboardCheck},
 {title:'Easy financing',description:'Pilihan pembiayaan, tertakluk kelulusan.',Icon:WalletCards},
 {title:'Trusted',description:'Urusan jelas dan layanan yang mesra.',Icon:ShieldCheck},
];
export function MotorBenefits(){return <section className="motor-benefits" aria-labelledby="motor-benefits-title"><div className="motor-benefits-heading"><span>PILIHAN DENGAN KEYAKINAN</span><h3 id="motor-benefits-title">Kenapa beli dengan <b>3 Abdul Motor?</b></h3></div><div className="motor-benefits-grid">{benefits.map(({title,description,Icon})=><div className="motor-benefit" key={title}><span className="motor-benefit-icon" aria-hidden="true"><Icon size={20} width={20} height={20} strokeWidth={1.7}/></span><div><h4>{title}</h4><p>{description}</p></div></div>)}</div></section>}
