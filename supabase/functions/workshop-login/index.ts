import {createClient} from 'npm:@supabase/supabase-js@2';
// SECURITY120_BEGIN — identique dans les trois fonctions publiques
// CORS complète les vérifications d'identité ; ce n'est jamais une autorisation.
export type Environment120=(name:string)=>string|undefined;
export async function readJson120(req:Request,limit:number):Promise<any>{
 const declared=req.headers.get('content-length');
 if(declared&&(!/^\d+$/.test(declared)||Number(declared)>limit))throw new Error('Requête trop volumineuse.');
 const reader=req.body?.getReader();if(!reader)throw new Error('Requête vide.');
 const chunks:Uint8Array[]=[];let total=0;
 try{for(;;){const r=await reader.read();if(r.done)break;total+=r.value.byteLength;if(total>limit){await reader.cancel();throw new Error('Requête trop volumineuse.')}chunks.push(r.value)}}finally{reader.releaseLock()}
 const bytes=new Uint8Array(total);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length}
 const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('Requête invalide.');
 return value;
}
export function secureHandler120(env:Environment120,handler:(req:Request)=>Promise<Response>){return async(req:Request)=>{
 const origins=(env('WORKSHOP_ALLOWED_ORIGINS')||'').split(',').map(x=>x.trim()).filter(Boolean);
 const valid=origins.length>0&&origins.every(x=>{try{const u=new URL(x);return u.origin===x&&(u.protocol==='https:'||u.protocol==='http:'&&['localhost','127.0.0.1'].includes(u.hostname))}catch{return false}});
 const origin=req.headers.get('origin');const headers=new Headers({'Cache-Control':'no-store','Pragma':'no-cache','Content-Type':'application/json; charset=utf-8','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Vary':'Origin'});
 if(valid&&origin&&origins.includes(origin))headers.set('Access-Control-Allow-Origin',origin);
 headers.set('Access-Control-Allow-Headers','authorization,x-client-info,apikey,content-type');headers.set('Access-Control-Allow-Methods','POST,OPTIONS');
 const fail=(error:string,status:number)=>new Response(JSON.stringify({error}),{status,headers});
 if(!valid)return fail('Service temporairement indisponible. Contacte ton administrateur.',503);
 if(origin&&!origins.includes(origin))return fail('Origine non autorisée.',403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return fail('Méthode non autorisée.',405);
 if(req.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')return fail('Une requête JSON est requise.',415);
 try{const response=await handler(req);const final=new Headers(response.headers);
  final.delete('Access-Control-Allow-Origin');for(const [k,v]of headers)final.set(k,v);
  return new Response(response.body,{status:response.status,headers:final});
 }catch{return fail('Opération non confirmée. Réessaie ou contacte ton administrateur.',503)}
};}
// SECURITY120_END
type Dependencies120={createClient:typeof createClient,env:(name:string)=>string|undefined};
const cors={'Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
export function createLoginHandler120({createClient,env}:Dependencies120){return secureHandler120(env,async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply({error:'Méthode non autorisée.'},405);
 const invalid=()=>reply({error:'Identifiant ou mot de passe incorrect.'},401);
 try{
  const body=await readJson120(req,2048);
  if(typeof body.login!=='string'||!/^[a-z0-9_-]{3,32}$/i.test(body.login.trim())||typeof body.password!=='string'||!body.password||body.password.length>128)return invalid();
  const url=env('SUPABASE_URL')!,service=env('SUPABASE_SERVICE_ROLE_KEY')!,anon=env('SUPABASE_ANON_KEY')!;
  if(!url||!service||!anon)return reply({error:'Connexion par ID indisponible. Contacte ton administrateur.'},503);
  const server=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:lookup,error}=await server.rpc('workshop_login100',{p_login:body.login});
  if(error)return reply({error:'Connexion par ID indisponible. Contacte ton administrateur.'},503);
  if(lookup?.limited)return reply({error:'Trop de tentatives. Réessaie dans 15 minutes.'},429);
  const client=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error:authError}=await client.auth.signInWithPassword({email:lookup?.email||'unknown-login@invalid.example',password:body.password});
  if(!lookup?.email||authError||!data.session)return invalid();
  return reply({session:{access_token:data.session.access_token,refresh_token:data.session.refresh_token}});
 }catch{return invalid();}
});}
Deno.serve(createLoginHandler120({createClient,env:name=>Deno.env.get(name)}));
