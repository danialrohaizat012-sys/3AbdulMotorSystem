import type {Vehicle,Job,Payment} from './motor';
import {money} from './motor';
import {buildInvoice} from './invoice-model';
import type {DocType,InvoiceDoc} from './invoice-model';
import {loadInvoiceProfile} from './invoice-profile';

const escape=(value:unknown)=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const lines=(values:string[])=>values.map(escape).join('<br/>');

const css=`*{box-sizing:border-box}html{-webkit-print-color-adjust:exact;print-color-adjust:exact}
body{margin:0;background:#eef1f4;font-family:"Helvetica Neue",Arial,sans-serif;color:#1d2731;font-size:12.5px;line-height:1.5}
.page{width:210mm;min-height:297mm;margin:16px auto;background:#fff;padding:16mm 15mm 14mm;display:flex;flex-direction:column;box-shadow:0 4px 24px #0002}
.top{display:flex;justify-content:space-between;gap:24px;align-items:flex-start}
.brand{display:flex;gap:14px;align-items:flex-start;max-width:60%}.brand img{width:64px;height:56px;object-fit:contain}
.brand h1{font-size:19px;margin:0 0 2px;letter-spacing:.02em;text-transform:uppercase}.brand p{margin:0;color:#56626e;font-size:11px;line-height:1.55}
.doc{text-align:right}.doc h2{margin:0;font-size:26px;letter-spacing:.06em;text-transform:uppercase;color:#1d2731}
.doc table{margin-left:auto;margin-top:6px;border-collapse:collapse}.doc td{padding:1px 0 1px 14px;font-size:11.5px}.doc td:first-child{color:#6a7681}.doc td:last-child{font-weight:700}
.badge{display:inline-block;margin-top:8px;padding:4px 10px;border-radius:4px;font-size:10.5px;font-weight:700;letter-spacing:.08em}
.badge.paid{background:#e3f4e8;color:#1d6b3a}.badge.partial{background:#fff3d6;color:#8a5a00}.badge.due{background:#fde6e6;color:#a52626}.badge.draft{background:#e7edf3;color:#36506a}.badge.free{background:#eceff2;color:#4a5560}
.bar{height:4px;background:linear-gradient(90deg,#e8b923,#e8b923 70%,#d8312b 70%);margin:14px 0 18px;border-radius:2px}
.parties{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:18px}
.box{border:1px solid #dfe4e8;border-radius:6px;padding:10px 12px}.box h3{margin:0 0 4px;font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:#6a7681}.box p{margin:0}.box p b{font-size:13.5px}
table.items{width:100%;border-collapse:collapse}
.items th{background:#1d2731;color:#fff;font-size:10.5px;text-transform:uppercase;letter-spacing:.06em;padding:8px 10px;text-align:left}
.items td{padding:9px 10px;border-bottom:1px solid #e6eaee;vertical-align:top}.items tbody tr:nth-child(even) td{background:#f8fafb}
.items small{color:#6a7681}.num{text-align:right!important;white-space:nowrap}.c{text-align:center!important}
.summary{display:flex;justify-content:space-between;gap:24px;margin-top:14px;align-items:flex-start}
.bank{flex:1;border:1px dashed #c9d1d8;border-radius:6px;padding:10px 12px;font-size:11.5px}.bank h3{margin:0 0 4px;font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:#6a7681}
.totals{width:270px;margin-left:auto;border-collapse:collapse}.totals td{padding:5px 10px}.totals td:last-child{text-align:right;white-space:nowrap}
.totals .strong td{font-weight:700;font-size:14px;border-top:1.5px solid #1d2731}.totals .due td{background:#fff4e0;color:#8a4b00}.totals .paidtone td:last-child{color:#1d6b3a}
h4{font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;color:#6a7681;margin:20px 0 6px}
table.ledger{width:100%;border-collapse:collapse;font-size:11.5px}.ledger th{text-align:left;border-bottom:1.5px solid #1d2731;padding:5px 8px;font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:#56626e}.ledger td{padding:6px 8px;border-bottom:1px solid #e6eaee;vertical-align:top}
.note{margin-top:12px;font-size:11.5px}.note b{display:block;font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:#6a7681}.note p{margin:2px 0 0;white-space:pre-wrap}
.sign{display:flex;gap:40px;margin-top:auto;padding-top:36px}.sign div{flex:1;max-width:220px;border-top:1px solid #1d2731;padding-top:5px;font-size:11px;color:#56626e}
footer{margin-top:18px;padding-top:8px;border-top:1px solid #e6eaee;display:flex;justify-content:space-between;font-size:10px;color:#8a949e}
tr{break-inside:avoid}
@page{size:A4;margin:0}@media print{body{background:#fff}.page{margin:0;box-shadow:none;min-height:296mm}}`;

/** Full A4 HTML for a document. Exported for previews and tests. */
export function invoiceHtml(doc:InvoiceDoc,logoUrl:string){
 const item=doc.items.map(i=>`<tr><td class="c">${i.no}</td><td><b>${escape(i.description)}</b>${i.detail?'<br/><small>'+escape(i.detail)+'</small>':''}</td><td class="c">${i.qty}</td><td class="num">${money(i.unitPrice)}</td><td class="num">${money(i.amount)}</td></tr>`).join('')||'<tr><td colspan="5"><small>Tiada caj direkodkan.</small></td></tr>';
 const totals=doc.totals.map(t=>`<tr class="${t.strong?'strong':''} ${t.tone==='due'?'due':t.tone==='paid'?'paidtone':''}"><td>${escape(t.label)}</td><td>${escape(t.value)}</td></tr>`).join('');
 const ledger=doc.payments.length?`<h4>${doc.type==='receipt'?'Butiran bayaran diterima':'Sejarah bayaran'}</h4><table class="ledger"><thead><tr><th>Rujukan</th><th>Tarikh</th><th>Kaedah</th><th>Catatan</th><th>Diterima oleh</th><th class="num">Amaun</th></tr></thead><tbody>${doc.payments.map(p=>`<tr><td>${p.reference}</td><td>${escape(p.date)}</td><td>${escape(p.method)}</td><td>${escape(p.note)}</td><td>${escape(p.receiver)}</td><td class="num">${money(p.amount)}</td></tr>`).join('')}</tbody></table>`:'';
 const bank=doc.bank?`<div class="bank"><h3>Cara bayaran</h3>${lines(doc.bank)}</div>`:'<div></div>';
 return `<!doctype html><html lang="ms"><head><meta charset="utf-8"><title>${escape(doc.title+' '+doc.number)}</title><style>${css}</style></head><body><main class="page">
<section class="top"><div class="brand"><img src="${escape(logoUrl)}" alt=""><div><h1>${escape(doc.business.name)}</h1><p>${lines(doc.business.lines)}</p></div></div>
<div class="doc"><h2>${escape(doc.title)}</h2><table><tr><td>No. dokumen</td><td>${escape(doc.number)}</td></tr><tr><td>Tarikh</td><td>${escape(doc.issuedAt)}</td></tr><tr><td>Rujukan</td><td>${escape(doc.reference)}</td></tr></table><span class="badge ${doc.status.tone}">${escape(doc.status.label)}</span></div></section>
<div class="bar"></div>
<section class="parties"><div class="box"><h3>${escape(doc.billTo.title)}</h3><p>${doc.billTo.lines.map((l,i)=>i===0?'<b>'+escape(l)+'</b>':escape(l)).join('<br/>')}</p></div><div class="box"><h3>${escape(doc.subject.title)}</h3><p>${lines(doc.subject.lines)}</p></div></section>
<table class="items"><thead><tr><th class="c" style="width:34px">No.</th><th>Perkara</th><th class="c" style="width:60px">Kuantiti</th><th class="num" style="width:110px">Harga seunit</th><th class="num" style="width:110px">Amaun</th></tr></thead><tbody>${item}</tbody></table>
<section class="summary">${bank}<table class="totals">${totals}</table></section>
${ledger}
${doc.notes.map(n=>`<div class="note"><b>${escape(n.title)}</b><p>${escape(n.text)}</p></div>`).join('')}
<section class="sign">${doc.signatures.map(s=>`<div>${escape(s)}</div>`).join('')}</section>
<footer><span>Dokumen ini dijana oleh komputer.</span><span>${escape(doc.business.name)} · ${escape(doc.number)}</span></footer>
</main></body></html>`;
}

export async function printRecord(record:Vehicle|Job,payments:Payment[],documentType:DocType='invoice'){
 // Open synchronously inside the click so pop-up blockers allow it, then fill it.
 const w=window.open('','_blank');if(!w)throw Error('Benarkan pop-up untuk cetak atau simpan PDF.');
 w.document.write('<p style="font-family:Arial;padding:24px">Menyediakan dokumen…</p>');
 try{
  const doc=buildInvoice(record,payments,documentType,await loadInvoiceProfile());
  w.document.open();w.document.write(invoiceHtml(doc,location.origin+location.pathname+'logo-transparent-v2.png'));w.document.close();
  const img=w.document.querySelector('img');const go=()=>{w.focus();w.print()};
  if(img&&!img.complete){img.addEventListener('load',go,{once:true});img.addEventListener('error',go,{once:true})}else setTimeout(go,50);
 }catch(e){w.close();throw e}
}
