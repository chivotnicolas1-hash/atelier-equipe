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
 // La fonction de lecture contrôle l’adresse administrateur, le fournisseur et la session.
 const caller=createClient(url,key,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:workshop,error:roleError}=await caller.rpc('workshop_load',{p_date:new Date().toISOString().slice(0,10)});
 if(roleError||workshop?.admin!==true)return reply({error:'Action réservée à l’administrateur.'},403);
 const body=await req.json();
 if(typeof body.staffId!=='string'||typeof body.password!=='string'||body.password.length<12||body.password.length>128)return reply({error:'Choisis une fiche et un mot de passe de 12 à 128 caractères.'},400);
 const person=workshop.staff.find((s:{id:string})=>s.id===body.staffId);
 if(!person?.email)return reply({error:'Enregistre d’abord une adresse e-mail sur la fiche.'},400);
 const {data:userId,error:lookupError}=await server.rpc('workshop_account_id',{p_staff_id:body.staffId});
 if(lookupError)return reply({error:'Applique le script 02-connexion-identifiants.sql avant de créer les comptes.'},503);
 if(userId){
 const {error}=await server.auth.admin.updateUserById(userId,{password:body.password,email_confirm:true});
 if(error)return reply({error:'Le mot de passe n’a pas pu être remplacé : '+error.message},400);
 return reply({ok:true,created:false});
 }
 const {error}=await server.auth.admin.createUser({email:person.email,password:body.password,email_confirm:true});
 if(error)return reply({error:'Le compte n’a pas pu être créé : '+error.message},400);
 return reply({ok:true,created:true});
 }catch{return reply({error:'Création impossible. Réessaie.'},500);}
});
