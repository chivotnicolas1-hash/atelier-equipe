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
// Aucun accès aux mots de passe ou aux codes dans les journaux.
type Dependencies={createClient:(url:string,key:string,options:any)=>any,env:(name:string)=>string|undefined};
const cors={'Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
const hash=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(x=>x.toString(16).padStart(2,'0')).join('');
// Codes courts : empreinte liée à une clé serveur, absente de la base.
// Les anciens codes longs gardent leur empreinte pour rester utilisables.
const alphabet118='0123456789ABCDEFGHJKMNPQRSTVWXYZ';
async function codeHash(code:string,secret:string){const normalized=code.replace(/[\s-]/g,'').toUpperCase();if(normalized.length!==8)return hash('atelier-recovery-117:'+normalized);const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode('atelier-recovery-118:'+normalized)))).map(x=>x.toString(16).padStart(2,'0')).join('');}
async function body117(req:Request){const reader=req.body?.getReader();if(!reader)throw Error();let bytes=0;const chunks:Uint8Array[]=[];try{for(;;){const r=await reader.read();if(r.done)break;bytes+=r.value.length;if(bytes>4096){await reader.cancel();throw Error()}chunks.push(r.value)}}finally{reader.releaseLock()}const raw=new Uint8Array(bytes);let offset=0;for(const c of chunks){raw.set(c,offset);offset+=c.length}return JSON.parse(new TextDecoder().decode(raw));}
export function createRecoveryHandler117({createClient,env}:Dependencies){return secureHandler120(env,async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply({error:'Méthode non autorisée.'},405);
 const invalid=()=>reply({error:'ID ou code de récupération incorrect, expiré ou déjà utilisé.'},401);
 try{
  const url=env('SUPABASE_URL'),service=env('SUPABASE_SERVICE_ROLE_KEY'),anon=env('SUPABASE_ANON_KEY');
  if(!url||!service||!anon)return reply({error:'Récupération indisponible. Contacte ton administrateur.'},503);
  const b=await body117(req);if(!b||typeof b!=='object'||Array.isArray(b))return reply({error:'Requête invalide.'},400);
  const server=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  // La limite par compte et la limite globale restent effectives même si un en-tête réseau est falsifié.
  const network=await hash(service+':network117:'+(req.headers.get('cf-connecting-ip')||req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown').slice(0,100));
  if(b.action==='generate'){
   const token=req.headers.get('Authorization')?.match(/^Bearer (.+)$/i)?.[1];if(!token)return reply({error:'Connexion requise.'},401);
   const identity=await server.auth.getUser(token);if(identity.error||!identity.data.user?.email)return reply({error:'Session expirée. Reconnecte-toi.'},401);
   const user=identity.data.user;
   if(typeof b.current_password!=='string'||!b.current_password||b.current_password.length>128||!Number.isInteger(b.expected_version)||b.expected_version<0)return reply({error:'Mot de passe actuel et version du profil requis.'},400);
   const budget=await server.rpc('workshop_recovery_budget117',{p_login:'enroll:'+user.id,p_network:network});if(budget.error)return reply({error:'Installe le SQL 117b avant de générer un code.'},503);if(!budget.data)return reply({error:'Trop de tentatives. Réessaie dans 15 minutes.'},429);
   const verifier=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
   const verified=await verifier.auth.signInWithPassword({email:user.email,password:b.current_password});
   if(verified.error||verified.data.user?.id!==user.id){if(verified.data.session)await verifier.auth.signOut({scope:'local'});return reply({error:'Mot de passe actuel incorrect.'},401)}
   await verifier.auth.signOut({scope:'local'});
   const caller=createClient(url,anon,{global:{headers:{Authorization:'Bearer '+token}},auth:{persistSession:false,autoRefreshToken:false}});
   const profile=await caller.rpc('workshop_load',{p_date:new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())});
   if(profile.error||!profile.data?.self||profile.data?.guest||profile.data?.role==='guest')return reply({error:'Compte indisponible.'},403);
   const target=await server.rpc('workshop_account_target100',{p_staff:profile.data.self});
   if(target.error||target.data?.user_id!==user.id)return reply({error:'Association du compte à vérifier avec ton administrateur.'},403);
   const bytes=crypto.getRandomValues(new Uint8Array(8)),code=Array.from(bytes,x=>alphabet118[x&31]).join('');
   const saved=await server.rpc('workshop_recovery_save117',{p_user:user.id,p_staff:profile.data.self,p_hash:await codeHash(code,env('RECOVERY_CODE_SECRET')||service),p_expected:b.expected_version});
   if(saved.error)return reply({error:'Le code n’a pas pu être créé. Ferme puis rouvre Mon profil et réessaie.'},409);
   return reply({code,login:profile.data.login_id,expires_in_days:365});
  }
  if(b.action!=='reset'||typeof b.login!=='string'||!/^[a-z0-9_-]{3,32}$/i.test(b.login.trim())||typeof b.code!=='string'||b.code.length>80||!/^(?:[0-9A-HJKMNP-TV-Z]{8}|[0-9A-F]{32})$/.test(b.code.replace(/[\s-]/g,'').toUpperCase())||typeof b.password!=='string'||b.password.length<12||b.password.length>128)return reply({error:'Renseigne ton ID, ton code de récupération et un mot de passe de 12 à 128 caractères.'},400);
  const attempt=crypto.randomUUID(),claimed=await server.rpc('workshop_recovery_claim117',{p_login:b.login.trim(),p_hash:await codeHash(b.code,env('RECOVERY_CODE_SECRET')||service),p_network:network,p_attempt:attempt});
  if(claimed.error)return reply({error:'Récupération indisponible. Contacte ton administrateur.'},503);
  if(claimed.data?.limited)return reply({error:'Trop de tentatives. Réessaie dans 15 minutes.'},429);
  const target=claimed.data;if(!target?.user_id||!target?.staff_id)return invalid();
  const mapping=await server.rpc('workshop_account_target100',{p_staff:target.staff_id});
  const account=await server.auth.admin.getUserById(target.user_id);
  if(mapping.error||mapping.data?.user_id!==target.user_id||account.error||!account.data.user||new Date(account.data.user.banned_until||0).getTime()>Date.now())return invalid();
  // Le code est consommé atomiquement AVANT l’appel Auth : deux requêtes ne peuvent pas l’utiliser.
  const changed=await server.auth.admin.updateUserById(target.user_id,{password:b.password});
  if(changed.error){if(changed.error.status>=400&&changed.error.status<500){await server.rpc('workshop_recovery_release117',{p_user:target.user_id,p_attempt:attempt});return reply({error:'Ce nouveau mot de passe a été refusé. Choisis-en un autre. Ton code reste utilisable.'},400)}return reply({error:'Le résultat du changement n’est pas confirmé. Essaie de te connecter avec le nouveau mot de passe ; si nécessaire, contacte ton administrateur.'},503)}
  await server.rpc('workshop_recovery_notice117',{p_user:target.user_id,p_attempt:attempt});
  return reply({ok:true,message:'Mot de passe modifié. Connecte-toi avec ton ID et ton nouveau mot de passe, puis génère un nouveau code dans Mon profil. Le précédent est désormais inutilisable.'});
 }catch{return reply({error:'Opération non confirmée. Réessaie de te connecter ; si nécessaire, contacte ton administrateur.'},503)}
});}

Deno.serve(createRecoveryHandler117({createClient,env:name=>Deno.env.get(name)}));
