export type Vehicle={id:number;brand:string;model:string;year:number;plate:string;mileage:number;price:number;cost:number;prep:number;paid:number;buyer:string;status:string;published:number;photo:string;photos?:string[];description:string;inspection:string;createdAt:string;updatedAt:string;version?:number;supplier?:string;supplierPhone?:string;chassis?:string;buyerPhone?:string;prepItems?:string;duplicateReason?:string;soldAt?:string|null};
export type Line={name:string;kind:string;qty:number;rate:number};
export type Job={id:number;customer:string;phone:string;bike:string;plate:string;mileage:number;complaint:string;notes:string;mechanic:string;status:string;items:string;paid:number;createdAt:string;updatedAt:string;version?:number;estimateStatus?:string;approvalNote?:string;approvedTotal?:number|null;noChargeReason?:string;creditReason?:string;creditApprovedBy?:string|null;creditApprovedAt?:string|null};
export type Payment={id:number;requestId:string;vehicleId:number|null;jobId:number|null;amount:number;method:string;purpose:string;paidAt:string;note:string;reversesId:number|null;receiverName:string;createdAt:string};
export type AuditEntry={id:number;recordKind:string;recordId:number;action:string;changedFields:string[];actorName:string;createdAt:string};
export type Overview={month:string;soldCount:number;sales:number;grossProfit:number;vehicleReceipts:number;serviceReceipts:number;vehicleOutstanding:number;serviceOutstanding:number};
export const bikeStatuses:Record<string,string>={available:'Available',reserved:'Reserved',sold:'Sold'};
export const jobStatuses:Record<string,string>={new:'Baharu',working:'Dalam kerja',ready:'Siap',collected:'Diserahkan'};
export const inspectionLabels=['Enjin & kebocoran','Brek hadapan / belakang','Tayar & rim','Lampu & signal','Rantai / belt','Bateri & starter','Suspensi','Dokumen & nombor casis'];
export const money=(n:number)=>new Intl.NumberFormat('ms-MY',{style:'currency',currency:'MYR',maximumFractionDigits:2}).format(n/100);
export const dateText=(s:string)=>s?new Date(s).toLocaleString('ms-MY',{timeZone:'Asia/Kuala_Lumpur',dateStyle:'medium',timeStyle:'short'}):'—';
export function parseLines(s:string):Line[]{try{const a=JSON.parse(s);return Array.isArray(a)?a:[]}catch{return []}}
export const lineTotal=(lines:Line[])=>lines.reduce((s,l)=>s+l.qty*l.rate,0);
export const total=(j:Pick<Job,'items'>)=>lineTotal(parseLines(j.items));
export const vehicleId=(id:number)=>'3AM-'+String(id).padStart(4,'0');
export const jobId=(id:number)=>'JOB-'+String(id).padStart(4,'0');
export function paymentStatus(paid:number,amount:number){return amount===0?'Percuma':paid>=amount?'Dibayar penuh':paid>0?'Bayaran sebahagian':'Belum dibayar'}
export const blankBike:Vehicle={id:0,brand:'',model:'',year:new Date().getFullYear(),plate:'',mileage:0,price:0,cost:0,prep:0,paid:0,buyer:'',buyerPhone:'',supplier:'',supplierPhone:'',chassis:'',prepItems:'[]',duplicateReason:'',status:'available',published:0,photo:'',photos:[],description:'',inspection:'[]',createdAt:'',updatedAt:'',version:1};
export const blankJob:Job={id:0,customer:'',phone:'',bike:'',plate:'',mileage:0,complaint:'',notes:'',mechanic:'',status:'new',items:'[]',paid:0,createdAt:'',updatedAt:'',version:1,estimateStatus:'draft',approvalNote:'',approvedTotal:null,noChargeReason:'',creditReason:''};
export const demoVehicles:Vehicle[]=[['Yamaha','Y15ZR',2023,780000,'available'],['Honda','RS-X',2022,650000,'reserved'],['Yamaha','NVX 155',2024,1050000,'available']].map((r,i)=>({...blankBike,id:9001+i,brand:String(r[0]),model:String(r[1]),year:Number(r[2]),price:Number(r[3]),status:String(r[4]),published:1,mileage:12000+i*2300,description:'Data demo sahaja. Bukan stok sebenar.'}));
export const demoJobs:Job[]=[{...blankJob,id:9001,customer:'Pelanggan demo',bike:'Yamaha Y15ZR',plate:'DEMO 01',complaint:'Servis berkala',items:JSON.stringify([{name:'Minyak enjin',kind:'part',qty:1,rate:4500}]),status:'new'}];
