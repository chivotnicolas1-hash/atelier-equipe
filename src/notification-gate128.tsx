import {Dialog,DialogContent,DialogTitle,DialogDescription} from './components/ui/dialog';
import {useEffect,useRef,useState,type ReactNode} from 'react';
import {BellRing} from 'lucide-react';
import {supabase,logout} from './lib/supabase';
import {NotificationSettings} from './notifications';
import {useAutoRefresh} from './lib/sync';
import './update128.css';
export type NotificationPolicy128={required:boolean,endpoints:string[]};
export async function deviceNotificationState128(policy:NotificationPolicy128){
 if(!policy||typeof policy.required!=='boolean'||!Array.isArray(policy.endpoints))throw Error('Réponse de vérification des notifications invalide.');
 if(!policy.required)return 'ready' as const;
 if(typeof Notification==='undefined'||!('serviceWorker'in navigator)||!('PushManager'in window))return 'unsupported' as const;
 if(Notification.permission!=='granted')return 'required' as const;
 let timer:ReturnType<typeof setTimeout>|undefined;
 try{const reg=await Promise.race([navigator.serviceWorker.ready,new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(Error('Le service de notification ne répond pas. Ferme puis rouvre l’application.')),8000)})]);const sub=await reg.pushManager.getSubscription();return sub&&policy.endpoints.includes(sub.endpoint)?'ready' as const:'required' as const}finally{clearTimeout(timer)}
}
export default function NotificationGate128({children}:{children:ReactNode}){
 const[state,S]=useState<'checking'|'required'|'unsupported'|'ready'|'error'>('checking'),[error,E]=useState(''),[admitted,A]=useState(false),sequence=useRef(0),alive=useRef(true);
 async function check(){const n=++sequence.current;try{const r=await supabase.rpc('workshop_notification_access128');if(r.error)throw Error(r.error.code==='PGRST202'?'L’administrateur doit installer le SQL128 pour vérifier les notifications.':r.error.message);const next=await deviceNotificationState128(r.data);if(alive.current&&n===sequence.current){S(next);E('');if(next==='ready')A(true)}}catch(e:any){if(alive.current&&n===sequence.current){S('error');E(e.message||'Vérification indisponible. Réessaie avec une connexion disponible.')}}}
 useEffect(()=>{alive.current=true;void check();const changed=()=>void check(),visible=()=>{if(!document.hidden)void check()};window.addEventListener('focus',changed);window.addEventListener('workshop-notifications-change128',changed);document.addEventListener('visibilitychange',visible);return()=>{alive.current=false;sequence.current++;window.removeEventListener('focus',changed);window.removeEventListener('workshop-notifications-change128',changed);document.removeEventListener('visibilitychange',visible)}},[]);
 useEffect(()=>{if(state!=='ready'){document.documentElement.dataset.notificationsRequired128='true';window.dispatchEvent(new Event('workshop-notifications-blocked128'))}else delete document.documentElement.dataset.notificationsRequired128;return()=>{delete document.documentElement.dataset.notificationsRequired128}},[state]);
 useAutoRefresh(check);
 return <>{admitted&&<div className="notification-workspace128" hidden={state!=='ready'} inert={state!=='ready'}>{children}</div>}{state!=='ready'&&<Dialog open onOpenChange={()=>{}}><DialogContent showCloseButton={false} onEscapeKeyDown={e=>e.preventDefault()} onInteractOutside={e=>e.preventDefault()} className="app-dialog notification-lock-dialog128"><div className="notification-required128"><section className="panel"><BellRing size={36}/><DialogTitle>{state==='checking'?'Vérification des notifications…':state==='error'?'Vérification indisponible':'Active les notifications pour continuer'}</DialogTitle><DialogDescription>Les notifications sont obligatoires sur l’appareil utilisé pour accéder à ton compte.</DialogDescription>{state==='unsupported'&&<p className="error-banner">Ce navigateur ne propose pas les notifications nécessaires. Sur iPhone, installe l’application sur l’écran d’accueil et ouvre-la depuis son icône. Sur les autres appareils, utilise un navigateur compatible.</p>}{error&&<p className="error-banner" role="alert">{error}</p>}{state!=='checking'&&<NotificationSettings onActivated={()=>void check()}/>}<p className="muted">Si l’autorisation est bloquée, réactive les notifications dans les réglages du navigateur ou du téléphone, puis reviens ici.</p><div className="order-actions">{state!=='checking'&&<button type="button" className="secondary" onClick={()=>void check()}>Vérifier l’activation</button>}<button type="button" className="secondary danger" onClick={()=>void logout().catch(e=>E(e.message))}>Se déconnecter</button></div></section></div></DialogContent></Dialog>}</>;
}
