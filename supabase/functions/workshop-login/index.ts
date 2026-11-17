import {createClient} from 'npm:@supabase/supabase-js@2';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return reply({error:'Méthode non autorisée.'},405);
 const invalid=()=>reply({error:'Identifiant ou mot de passe incorrect.'},401);
 try{
  const raw=await req.text();if(raw.length>2048)return invalid();const body=JSON.parse(raw);
  if(typeof body.login!=='string'||!/^[a-z0-9_-]{3,32}$/i.test(body.login.trim())||typeof body.password!=='string'||!body.password||body.password.length>128)return invalid();
  const url=Deno.env.get('SUPABASE_URL')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
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
});
