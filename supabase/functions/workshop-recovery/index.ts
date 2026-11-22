import {createClient} from 'npm:@supabase/supabase-js@2';
// Aucun accès aux mots de passe ou aux codes dans les journaux.
type Dependencies={createClient:(url:string,key:string,options:any)=>any,env:(name:string)=>string|undefined};
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
const hash=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(x=>x.toString(16).padStart(2,'0')).join('');
const codeHash=(code:string)=>hash('atelier-recovery-117:'+code.replace(/[\s-]/g,'').toUpperCase());
async function body117(req:Request){const reader=req.body?.getReader();if(!reader)throw Error();let bytes=0;const chunks:Uint8Array[]=[];try{for(;;){const r=await reader.read();if(r.done)break;bytes+=r.value.length;if(bytes>4096){await reader.cancel();throw Error()}chunks.push(r.value)}}finally{reader.releaseLock()}const raw=new Uint8Array(bytes);let offset=0;for(const c of chunks){raw.set(c,offset);offset+=c.length}return JSON.parse(new TextDecoder().decode(raw));}
export function createRecoveryHandler117({createClient,env}:Dependencies){return async(req:Request)=>{
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
   const bytes=crypto.getRandomValues(new Uint8Array(16)),code=Array.from(bytes).map(x=>x.toString(16).padStart(2,'0')).join('').toUpperCase();
   const saved=await server.rpc('workshop_recovery_save117',{p_user:user.id,p_staff:profile.data.self,p_hash:await codeHash(code),p_expected:b.expected_version});
   if(saved.error)return reply({error:'Le code n’a pas pu être créé. Ferme puis rouvre Mon profil et réessaie.'},409);
   return reply({code:code.match(/.{8}/g)!.join('-'),login:profile.data.login_id,expires_in_days:365});
  }
  if(b.action!=='reset'||typeof b.login!=='string'||!/^[a-z0-9_-]{3,32}$/i.test(b.login.trim())||typeof b.code!=='string'||b.code.length>80||!/^[0-9A-F]{32}$/.test(b.code.replace(/[\s-]/g,'').toUpperCase())||typeof b.password!=='string'||b.password.length<12||b.password.length>128)return reply({error:'Renseigne ton ID, ton code de récupération et un mot de passe de 12 à 128 caractères.'},400);
  const attempt=crypto.randomUUID(),claimed=await server.rpc('workshop_recovery_claim117',{p_login:b.login.trim(),p_hash:await codeHash(b.code),p_network:network,p_attempt:attempt});
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
};}

Deno.serve(createRecoveryHandler117({createClient,env:name=>Deno.env.get(name)}));
