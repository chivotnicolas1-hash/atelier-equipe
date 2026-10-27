import {useEffect,useState} from 'react';
import {supabase,trackDesktopPush} from './lib/supabase';
async function rpc(name:string,args?:Record<string,unknown>){const {data,error}=await supabase.rpc(name,args);if(error)throw Error(error.code==='PGRST202'?'Les notifications ne sont pas encore configurées (script 12).':error.message);return data}
const supported=()=>typeof Notification!=='undefined'&&'serviceWorker'in navigator&&'PushManager'in window;
export function NotificationSettings({onActivated}:{onActivated?:()=>void}){
 const [active,setActive]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 useEffect(()=>{let live=true;if(supported())void navigator.serviceWorker.ready.then(async reg=>{const sub=await reg.pushManager.getSubscription();if(!sub)return;const status=await rpc('workshop_push_status');if(live)setActive(status.endpoints.includes(sub.endpoint)&&Notification.permission==='granted')}).catch(()=>{});return()=>{live=false}},[]);
 async function toggle(){if(active)return;setBusy(true);setMessage('');try{
  if(!supported())throw Error('Sur iPhone, ajoute cette application à l’écran d’accueil puis ouvre-la depuis son icône (iOS 16.4 minimum). Sinon, utilise un navigateur compatible avec les notifications.');
  if(!active&&Notification.permission!=='granted'&&await Notification.requestPermission()!=='granted')throw Error('Notifications non autorisées. Tu peux les autoriser dans les réglages du navigateur ou du téléphone.');
  const reg=await navigator.serviceWorker.ready;let sub=await reg.pushManager.getSubscription();

  const key=import.meta.env.VITE_VAPID_PUBLIC_KEY;if(!key)throw Error('L’administrateur doit configurer la clé publique des notifications dans Cloudflare.');
  const raw=atob(key.replace(/-/g,'+').replace(/_/g,'/'));const bytes=Uint8Array.from(raw,c=>c.charCodeAt(0));
  if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:bytes});
  await rpc('workshop_push_register',{p_subscription:sub.toJSON()});trackDesktopPush(sub.endpoint);setActive(true);setMessage('Cet appareil recevra les annonces et les notifications de tes tâches.');onActivated?.();
 }catch(e:any){setMessage(e.message||'Activation impossible. Réessaie.')}finally{setBusy(false)}}
 return <section className="notification-settings"><h3>Notifications sur cet appareil</h3><p className="muted">Reçois les annonces de l’atelier et les mises à jour de tes tâches, même lorsque l’application est fermée.</p><button className="secondary" disabled={busy||active} onClick={toggle}>{busy?'Veuillez patienter…':active?'Notifications activées':'Activer les notifications'}</button><p role="status">{message|| (active?'Cet appareil est inscrit. La réception dépend des réglages du téléphone.':'Autorise les notifications sur chacun de tes appareils. Sur iPhone, ouvre l’application depuis l’écran d’accueil.')}</p></section>
}
export function NotificationDirectory(){
 const [rows,setRows]=useState<{name:string,devices:number}[]>([]),[error,setError]=useState('');
 async function load(){try{const d=await rpc('workshop_push_status');setRows(d.team);setError('')}catch(e:any){setError(e.message)}}
 useEffect(()=>{void load()},[]);
 return <section className="panel"><div className="panel-head"><h2>Notifications de l’équipe</h2><button className="secondary" onClick={load}>Actualiser</button></div><p className="muted">Appareils inscrits : ce suivi ne confirme pas la réception ni la lecture d’une notification.</p>{error&&<p role="alert">{error}</p>}<div className="team-grid">{rows.map((r,i)=><div className={"team-card"+(!r.devices?" notifications-missing":"")} key={i}><strong>{r.name}</strong><p>{r.devices?`${r.devices} appareil(s) inscrit(s)`:'Aucun appareil inscrit'}</p></div>)}</div></section>
}
export function NotificationInvite({onOpen}:{onOpen:()=>void}){
 const [show,setShow]=useState(false);
 useEffect(()=>{let live=true;if(!supported()){setShow(true);return}void navigator.serviceWorker.ready.then(async reg=>{const sub=await reg.pushManager.getSubscription();const d=await rpc('workshop_push_status');if(live)setShow(!sub||!d.endpoints.includes(sub.endpoint)||Notification.permission!=='granted')}).catch(()=>{});return()=>{live=false}},[]);
 return show?<div className="info-line"><span>Active les notifications pour recevoir les annonces et tes tâches sur ce téléphone.</span><button className="secondary" onClick={onOpen}>Configurer</button></div>:null
}

export function NotificationCheck({onMissing}:{onMissing:()=>void}){
 useEffect(()=>{let live=true;async function check(){if(!supported()||Notification.permission!=='granted'){if(live)onMissing();return}try{const reg=await navigator.serviceWorker.ready;const sub=await reg.pushManager.getSubscription();const status=await rpc('workshop_push_status');if(live&&(!sub||Notification.permission!=='granted'||!status.endpoints.includes(sub.endpoint)))onMissing()}catch{/* Une erreur réseau ne doit pas déclencher une fausse redirection. */}}void check();window.addEventListener('focus',check);return()=>{live=false;window.removeEventListener('focus',check)}},[onMissing]);return null;
}
