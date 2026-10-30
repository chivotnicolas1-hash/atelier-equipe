import { createClient } from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
if(!url||!key)throw new Error('Configuration Supabase manquante : renseigne le fichier .env.');
// La détection dépend du type d’appareil, pas de la largeur de la fenêtre.
export const desktopSession=!(/Android|iPhone|iPad|iPod/i.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1));
if(desktopSession){const legacy='sb-'+new URL(url).hostname.split('.')[0]+'-auth-token';try{localStorage.removeItem(legacy);localStorage.removeItem(legacy+'-code-verifier');localStorage.removeItem(legacy+'-user')}catch{}}
export const supabase=createClient(url,key,{auth:{flowType:'pkce',persistSession:!desktopSession,autoRefreshToken:true,detectSessionInUrl:!desktopSession}});
let desktopEndpoint:string|null=null;
export function trackDesktopPush(endpoint:string|null){if(desktopSession)desktopEndpoint=endpoint}
if(desktopSession){
 let token:string|null=null;
 supabase.auth.onAuthStateChange((_event,session)=>{token=session?.access_token||null});
 if('serviceWorker'in navigator)void navigator.serviceWorker.getRegistration().then(reg=>reg?.pushManager.getSubscription()).then(sub=>{desktopEndpoint=sub?.endpoint||null}).catch(()=>{});
 window.addEventListener('pagehide',()=>{if(!token)return;const headers={apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'};if(desktopEndpoint)void fetch(url+'/rest/v1/rpc/workshop_push_remove',{method:'POST',headers,body:JSON.stringify({p_endpoint:desktopEndpoint}),keepalive:true}).catch(()=>{});void fetch(url+'/auth/v1/logout?scope=local',{method:'POST',headers,keepalive:true}).catch(()=>{});token=null;void supabase.auth.signOut({scope:'local'}).catch(()=>{});});
 window.addEventListener('pageshow',event=>{if(event.persisted)location.reload()});
}
function friendly(error:any){
 if(error.code==='PGRST202'||error.code==='42883')return new Error('La base doit être mise à jour : consulte MISE-A-JOUR-62.txt et exécute le script SQL fourni.');
 return new Error(error.message||'Connexion impossible. Vérifie ta connexion Internet.');
}
export async function loadWorkshop(date:string){const {data,error}=await supabase.rpc('workshop_load',{p_date:date});if(error)throw friendly(error);return data;}
export async function mutateWorkshop(payload:unknown){const {data,error}=await supabase.rpc('workshop_mutate',{p:payload});if(error)throw friendly(error);return data;}
export async function loginPassword(identifier:string,password:string){
 const login=identifier.trim();
 if(login.includes('@')){const {error}=await supabase.auth.signInWithPassword({email:login,password});if(error)throw new Error(error.code==='invalid_credentials'?'Identifiant ou mot de passe incorrect.':error.message);return;}
 const {data,error}=await supabase.functions.invoke('workshop-login',{body:{matricule:login,password}});
 if(error||!data?.session){let message='Connexion par matricule impossible. Vérifie les identifiants ou utilise ton e-mail.';try{const body=await error?.context?.json();if(body?.error)message=body.error}catch{}throw new Error(message)}
 const {error:sessionError}=await supabase.auth.setSession(data.session);if(sessionError)throw new Error('Session impossible. Réessaie.');
}
export async function provisionAccount(staffId:string,password:string){
 const {data,error}=await supabase.functions.invoke('workshop-accounts',{body:{staffId,password}});
 if(error){let message='Création du compte impossible. Vérifie que la fonction workshop-accounts est déployée.';try{const body=await error.context?.json();if(body?.error)message=body.error;}catch{}throw new Error(message);}
 if(data?.error)throw new Error(data.error);return data;
}
export async function logout(){if('serviceWorker'in navigator&&'PushManager'in window){const reg=await navigator.serviceWorker.getRegistration();const sub=await reg?.pushManager.getSubscription();if(sub){const {error:removeError}=await supabase.rpc('workshop_push_remove',{p_endpoint:sub.endpoint});if(removeError)throw new Error('Impossible de désinscrire cet appareil. Vérifie ta connexion puis réessaie de te déconnecter.');await sub.unsubscribe();}}const {error}=await supabase.auth.signOut({scope:'local'});if(error)throw error;}
