import { createClient } from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
if(!url||!key)throw new Error('Configuration Supabase manquante : renseigne le fichier .env.');
export const supabase=createClient(url,key,{auth:{flowType:'pkce',persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
function friendly(error:any){
 if(error.code==='PGRST202'||error.code==='42883')return new Error('La base de données n’est pas encore configurée. Exécute le fichier 01-installation.sql dans Supabase.');
 return new Error(error.message||'Connexion impossible. Vérifie ta connexion Internet.');
}
export async function loadWorkshop(date:string){const {data,error}=await supabase.rpc('workshop_load',{p_date:date});if(error)throw friendly(error);return data;}
export async function mutateWorkshop(payload:unknown){const {data,error}=await supabase.rpc('workshop_mutate',{p:payload});if(error)throw friendly(error);return data;}
export async function loginPassword(email:string,password:string){const {error}=await supabase.auth.signInWithPassword({email:email.trim(),password});if(error)throw new Error(error.code==='invalid_credentials'?'Adresse e-mail ou mot de passe incorrect.':error.message);}
export async function provisionAccount(staffId:string,password:string){
 const {data,error}=await supabase.functions.invoke('workshop-accounts',{body:{staffId,password}});
 if(error){let message='Création du compte impossible. Vérifie que la fonction workshop-accounts est déployée.';try{const body=await error.context?.json();if(body?.error)message=body.error;}catch{}throw new Error(message);}
 if(data?.error)throw new Error(data.error);return data;
}
export async function logout(){const {error}=await supabase.auth.signOut({scope:'local'});if(error)throw error;}
