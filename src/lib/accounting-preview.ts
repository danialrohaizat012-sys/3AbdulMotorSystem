export type AccountId='bank'|'cash';
export type PreviewEntry={id:string;date:string;description:string;kind:'income'|'expense'|'transfer';amount:number;account:AccountId;toAccount?:AccountId;category:string;source:'Inventori'|'Garaj'|'Manual';reference:string};
export const previewAccounts=[{id:'bank' as const,name:'Bank utama',opening:1800000},{id:'cash' as const,name:'Tunai kedai',opening:250000}];
export const previewEntries:PreviewEntry[]=[
 {id:'DEMO-001',date:'2026-10-02',description:'Bayaran motosikal · Yamaha Y15ZR',kind:'income',amount:680000,account:'bank',category:'Bayaran motosikal',source:'Inventori',reference:'CONTOH-M001'},
 {id:'DEMO-002',date:'2026-10-03',description:'Servis berkala · Honda RS150R',kind:'income',amount:28000,account:'cash',category:'Bayaran servis',source:'Garaj',reference:'CONTOH-J001'},
 {id:'DEMO-003',date:'2026-10-03',description:'Sewa premis · Oktober',kind:'expense',amount:120000,account:'bank',category:'Sewa',source:'Manual',reference:'CONTOH-E001'},
 {id:'DEMO-004',date:'2026-10-05',description:'Minyak enjin & bahan bengkel',kind:'expense',amount:45000,account:'bank',category:'Bahan bengkel',source:'Manual',reference:'CONTOH-E002'},
 {id:'DEMO-005',date:'2026-10-06',description:'Deposit tempahan · Honda Wave',kind:'income',amount:50000,account:'bank',category:'Deposit pelanggan',source:'Inventori',reference:'CONTOH-M002'},
 {id:'DEMO-006',date:'2026-10-07',description:'Pindahan bank ke tunai kedai',kind:'transfer',amount:100000,account:'bank',toAccount:'cash',category:'Pindahan dalaman',source:'Manual',reference:'CONTOH-T001'},
 {id:'DEMO-007',date:'2026-10-08',description:'Bil elektrik & air',kind:'expense',amount:18000,account:'bank',category:'Utiliti',source:'Manual',reference:'CONTOH-E003'},
 {id:'DEMO-008',date:'2026-10-09',description:'Bayaran pembekal · stok motosikal',kind:'expense',amount:350000,account:'bank',category:'Pembelian stok',source:'Manual',reference:'CONTOH-E004'},
 {id:'DEMO-009',date:'2026-10-10',description:'Tukar tayar & servis brek',kind:'income',amount:62000,account:'bank',category:'Bayaran servis',source:'Garaj',reference:'CONTOH-J002'},
 {id:'DEMO-010',date:'2026-10-11',description:'Barang kegunaan kedai',kind:'expense',amount:6000,account:'cash',category:'Operasi kedai',source:'Manual',reference:'CONTOH-E005'},
];
export function monthlyEntries(entries:PreviewEntry[],month:string){return entries.filter(e=>e.date.slice(0,7)===month)}
export function cashSummary(entries:PreviewEntry[]){const income=entries.filter(e=>e.kind==='income').reduce((s,e)=>s+e.amount,0);const expense=entries.filter(e=>e.kind==='expense').reduce((s,e)=>s+e.amount,0);return {income,expense,net:income-expense}}
export function accountBalance(account:AccountId,entries:PreviewEntry[]){return previewAccounts.find(a=>a.id===account)!.opening+entries.reduce((s,e)=>s+(e.toAccount===account?e.amount:0)+(e.account===account?(e.kind==='income'?e.amount:-e.amount):0),0)}
export function categoryTotals(entries:PreviewEntry[]){const values=new Map<string,number>();for(const e of entries)if(e.kind==='expense')values.set(e.category,(values.get(e.category)||0)+e.amount);return [...values].sort((a,b)=>b[1]-a[1])}
export function csvCell(value:string){return '"'+(/^[=+\-@\t\r]/.test(value)?"'":'')+value.replace(/"/g,'""')+'"'}
export function previewCsv(entries:PreviewEntry[]){return '\uFEFF'+[['DATA CONTOH SAHAJA — 3 ABDUL MOTOR'],['Tarikh','Rujukan','Butiran','Jenis','Kategori','Sumber','Akaun','Ke akaun','Amaun (RM)'],...entries.map(e=>[e.date,e.reference,e.description,e.kind,e.category,e.source,e.account,e.toAccount||'',(e.amount/100).toFixed(2)])].map(row=>row.map(csvCell).join(',')).join('\r\n')}

export function validPreviewMonth(value:string){return /^\d{4}-(0[1-9]|1[0-2])$/.test(value)}
