import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
const allowedOrigins=new Set(['https://3abdulmotor.binalab.my','https://danialrohaizat012-sys.github.io']);
const flags=['inventory_edit','garage_edit','receive_payments','publish_catalogue','manage_whatsapp','manage_photos'];
function response(req:Request,status:number,body:unknown){const origin=req.headers.get('origin')||'';return new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':allowedOrigins.has(origin)?origin:'https://3abdulmotor.binalab.my','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'}})}
function config(value:any){if(!value||typeof value!=='object')throw Error('Maklumat staf tidak sah.');const display_name=typeof value.display_name==='string'?value.display_name.trim():'';if(!display_name||display_name.length>120)throw Error('Nama staf diperlukan (maksimum 120 aksara).');if(!['inventory','garage','both'].includes(value.role))throw Error('Pilih akses inventori, garaj atau kedua-duanya.');if(typeof value.enabled!=='boolean')throw Error('Status akses tidak sah.');const permissions:Record<string,boolean>={};for(const flag of flags){if(typeof value.permissions?.[flag]!=='boolean')throw Error('Had tindakan staf tidak sah.');permissions[flag]=value.permissions[flag]}const payment_limit=value.payment_limit;if(payment_limit!==null&&(!Number.isSafeInteger(payment_limit)||payment_limit<0||payment_limit>100000000))throw Error('Had bayaran tidak sah.');return {display_name,role:value.role,enabled:value.enabled,permissions,payment_limit}}
function password(value:unknown){if(typeof value!=='string'||value.length<12||value.length>128||!/[A-Z]/.test(value)||!/[a-z]/.test(value)||!/[0-9]/.test(value))throw Error('Kata laluan perlu 12–128 aksara, huruf besar, kecil dan nombor.');return value}
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return response(req,200,{});
 if(req.method!=='POST')return response(req,405,{error:'Kaedah tidak dibenarkan.'});
 if(req.headers.get('origin')&&!allowedOrigins.has(req.headers.get('origin')!))return response(req,403,{error:'Asal permintaan tidak dibenarkan.'});
 const header=req.headers.get('authorization')||'';if(!header.startsWith('Bearer '))return response(req,401,{error:'Log masuk diperlukan.'});
 const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 // Gateway JWT verification is disabled for modern signing keys. Every request
 // is authenticated against Auth here; no user metadata is trusted for access.
 const {data:{user},error:authError}=await admin.auth.getUser(header.slice(7));if(authError||!user)return response(req,401,{error:'Sesi tidak sah. Log masuk semula.'});
 const {data:actor,error:actorError}=await admin.from('staff').select('*').eq('id',user.id).maybeSingle();if(actorError||!actor?.enabled)return response(req,403,{error:'Akses staf tidak dibenarkan.'});
 try{
  if(Number(req.headers.get('content-length')||0)>10000)return response(req,413,{error:'Permintaan terlalu besar.'});const text=await req.text();if(text.length>10000)return response(req,413,{error:'Permintaan terlalu besar.'});const input=JSON.parse(text);
  if(input.action==='change-password'){
   const next=password(input.password);const authResponse=await fetch(Deno.env.get('SUPABASE_URL')!+'/auth/v1/user',{method:'PUT',headers:{Authorization:header,apikey:Deno.env.get('SUPABASE_ANON_KEY')!,'Content-Type':'application/json'},body:JSON.stringify({password:next})});
   if(!authResponse.ok)return response(req,400,{error:'Kata laluan tidak dapat dikemas kini. Gunakan kata laluan baharu dan pastikan sesi masih sah.'});
   const {error:saveError}=await admin.from('staff').update({must_change_password:false}).eq('id',user.id);if(saveError)return response(req,500,{error:'Kata laluan berubah tetapi status akses belum dikemas kini. Hubungi owner.'});return response(req,200,{success:true});
  }
  if(actor.role!=='owner'||actor.must_change_password)return response(req,403,{error:'Hanya owner boleh mengurus akses staf.'});
  if(input.action==='list'){
   const {data:rows,error}=await admin.from('staff').select('*').order('display_name');if(error)throw Error('Senarai staf belum dapat dimuatkan.');const staff=await Promise.all(rows.map(async(row)=>{const {data}=await admin.auth.admin.getUserById(row.id);return {...row,email:data.user?.email||''}}));const {data:audit}=await admin.from('staff_access_log').select('id,target,action,changes,created_at').order('id',{ascending:false}).limit(30);return response(req,200,{staff,audit:audit||[]});
  }
  if(input.action==='create'){
   const values=config(input.staff);const email=typeof input.email==='string'?input.email.trim().toLowerCase():'';if(email.length>254||!/^\S+@\S+\.\S+$/.test(email))throw Error('E-mel staf tidak sah.');const temporary=password(input.password);
   const {data,error}=await admin.auth.admin.createUser({email,password:temporary,email_confirm:true});if(error||!data.user)return response(req,400,{error:'Akaun tidak dapat ditambah. E-mel mungkin sudah digunakan atau kata laluan tidak memenuhi syarat.'});
   const id=data.user.id;const {error:saveError}=await admin.rpc('save_staff_access',{actor_id:user.id,target_id:id,expected_version:null,details:values});if(saveError){await admin.auth.admin.deleteUser(id);return response(req,500,{error:'Akses tidak dapat disimpan. Akaun baharu dibatalkan; cuba semula.'})}
   return response(req,200,{success:true,id});
  }
  if(input.action==='update'){
   if(typeof input.id!=='string'||!Number.isInteger(input.version))throw Error('Rujukan staf tidak sah.');const values=config(input.staff);const {data:target}=await admin.from('staff').select('*').eq('id',input.id).maybeSingle();if(!target||target.id===user.id||target.role==='owner')return response(req,403,{error:'Akaun owner dilindungi dan tidak boleh diubah di sini.'});
   const {error}=await admin.rpc('save_staff_access',{actor_id:user.id,target_id:target.id,expected_version:input.version,details:values});if(error)return response(req,error.message.includes('berubah')?409:400,{error:error.message.includes('berubah')?'Akses telah berubah. Muat semula sebelum menyimpan.':'Akses staf gagal dikemas kini.'});
   return response(req,200,{success:true});
  }
  return response(req,400,{error:'Tindakan tidak sah.'});
 }catch(e){return response(req,400,{error:e instanceof Error&&!(e instanceof SyntaxError)?e.message:'Permintaan tidak sah.'})}
});
