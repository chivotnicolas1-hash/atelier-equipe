import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,x-client-info,apikey,content-type","Access-Control-Allow-Methods":"POST,OPTIONS"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply({error:'Méthode non autorisée.'},405);
 try{
 const url=Deno.env.get('SUPABASE_URL')!;
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 if(!url||!key)return reply({error:'Configuration serveur manquante.'},503);
 const server=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const token=req.headers.get('Authorization')?.match(/^Bearer (.+)$/i)?.[1];
 if(!token)return reply({error:'Connexion requise.'},401);
 const {data:identity,error:authError}=await server.auth.getUser(token);
 if(authError||!identity.user)return reply({error:'Session expirée. Reconnecte-toi.'},401);
 // Le serveur vérifie le compte et ses droits à chaque requête.
 const caller=createClient(url,key,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false}});
 const body=await req.json();
 const {data:workshop,error:roleError}=await caller.rpc('workshop_load',{p_date:new Date().toISOString().slice(0,10)});
 if(roleError)return reply({error:'Accès refusé.'},403);
 let requestPerson:any=null;
 if(body.requestId){const {data,error}=await caller.rpc('workshop_password_authorize',{p_id:body.requestId});if(error)return reply({error:'Demande inaccessible.'},403);requestPerson=data;body.staffId=data.staffId;}
 else if(workshop?.admin!==true)return reply({error:'Action réservée à l’administrateur.'},403);
 if(body.action==='anonymize'){
 if(workshop?.admin!==true)return reply({error:'Action réservée à l’administrateur.'},403);
 const {data:list,error:listError}=await caller.rpc('workshop_accounts100');if(listError)return reply({error:listError.message},400);
 const results=[];
 for(const item of list||[]){
 if(item.anonymized){results.push({staff_id:item.staff_id,ok:true});continue;}
 try{
 const {data:target,error}=await server.rpc('workshop_account_target100',{p_staff:item.staff_id});if(error||!target)throw Error('Fiche indisponible.');
 if(target.user_id){
 const {data:u,error:ue}=await server.auth.admin.getUserById(target.user_id);if(ue||!u.user)throw Error('Compte Auth introuvable.');
 const scrub=(value:any):any=>{if(typeof value==='string'){const old=String(target.old_email||'');if(!old)return value;let rest=value,result='',pos;while((pos=rest.toLowerCase().indexOf(old.toLowerCase()))>=0){result+=rest.slice(0,pos)+target.alias;rest=rest.slice(pos+old.length)}return result+rest;}if(Array.isArray(value))return value.map(scrub);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,scrub(v)]));return value};
 const {error:updated}=await server.auth.admin.updateUserById(target.user_id,{email:target.alias,email_confirm:true,user_metadata:scrub(u.user.user_metadata||{}),app_metadata:scrub(u.user.app_metadata||{})});if(updated)throw Error('Remplacement de la coordonnée Auth impossible.');
 }
 const {error:finished}=await server.rpc('workshop_account_finalize100',{p_staff:item.staff_id});if(finished)throw Error(finished.message);
 results.push({staff_id:item.staff_id,ok:true});
 }catch(e){results.push({staff_id:item.staff_id,ok:false,error:e instanceof Error?e.message:'Migration incomplète.'})}
 }
 return reply({results});
 }
 if(typeof body.staffId!=='string'||typeof body.password!=='string'||body.password.length<12||body.password.length>128)return reply({error:'Choisis une fiche et un mot de passe de 12 à 128 caractères.'},400);
 const person=requestPerson||workshop.staff.find((s:{id:string})=>s.id===body.staffId);
 if(!person)return reply({error:'Fiche introuvable.'},400);
 const {data:target,error:targetError}=await server.rpc('workshop_account_target100',{p_staff:body.staffId});if(targetError||!target?.alias)return reply({error:'Installe le SQL100a et renseigne un ID sur la fiche.'},400);
 const {data:lookupId,error:lookupError}=await server.rpc('workshop_account_id',{p_staff_id:body.staffId});
 if(lookupError)return reply({error:'Installe le script 100a-identifiants.sql avant de créer les accès.'},503);
 const userId=target.user_id||lookupId;
 if(userId){
 const revoked=await server.rpc('workshop_recovery_invalidate117',{p_user:userId});if(revoked.error)return reply({error:'Impossible de sécuriser la réinitialisation. Installe le SQL 117b avant de redéployer workshop-accounts.'},503);
 const {error}=await server.auth.admin.updateUserById(userId,{password:body.password,email_confirm:true});
 if(error)return reply({error:'Le mot de passe n’a pas pu être remplacé : '+error.message},400);
 if(!target.user_id){const {error:linked}=await server.rpc('workshop_account_link100',{p_staff:body.staffId,p_user:userId});if(linked)return reply({error:'Association du compte à reprendre.'},500);const {error:finished}=await server.rpc('workshop_account_finalize100',{p_staff:body.staffId});if(finished)return reply({error:'Synchronisation de la fiche à reprendre.'},500);}
 if(body.requestId){const {error:closeError}=await server.rpc('workshop_password_resolved',{p_id:body.requestId,p_actor:identity.user.id});if(closeError)return reply({error:'Mot de passe remplacé, mais clôture impossible. Contacte l’administrateur.'},500);}
 return reply({ok:true,created:false});
 }
 if(body.requestId)return reply({error:'Compte introuvable. Contacte l’administrateur.'},400);
 const {data:created,error}=await server.auth.admin.createUser({email:target.alias,password:body.password,email_confirm:true});
 if(error)return reply({error:'Le compte n’a pas pu être créé : '+error.message},400);
 const {error:linkError}=await server.rpc('workshop_account_link100',{p_staff:body.staffId,p_user:created.user!.id});if(linkError)return reply({error:'Compte créé, association à terminer : '+linkError.message},500);
 const {error:finalError}=await server.rpc('workshop_account_finalize100',{p_staff:body.staffId});if(finalError)return reply({error:'Compte créé, fiche à synchroniser : '+finalError.message},500);
 return reply({ok:true,created:true});
 }catch{return reply({error:'Création impossible. Réessaie.'},500);}
});
