import ChristmasLogo from './christmas-logo';
import {useEffect,useState,type ReactNode} from 'react';
import {supabase,logout,desktopSession} from './lib/supabase';
import {useAutoRefresh} from './lib/sync';
import LoadingScreen from './loading-screen';
export default function AccessGate({children}:{children:ReactNode}){
 const [status,setStatus]=useState<any>(null),[error,setError]=useState('');
 async function load(){const {data,error}=await supabase.rpc('workshop_access_status');if(error)setError(error.message);else{if(desktopSession&&data?.allowed){const pc=await supabase.rpc('workshop_pc_access');if(pc.error){setStatus(null);setError(pc.error.message);return}setStatus({...data,allowed:pc.data===true,pcDenied:pc.data!==true})}else setStatus(data);setError('')}}
 useEffect(()=>{void load()},[]);useAutoRefresh(load);
 if(status?.allowed)return <>{children}</>;
 if(!status&&!error)return <LoadingScreen/>;
 return <div className="login-page"><section className="login-card"><ChristmasLogo src="/icon-fayet-v34-512.png" width="100" alt="Atelier Fayet 33"/><h1>{status?.suspended?'Accès suspendu':'Accès indisponible'}</h1><p>{status?.suspended?'Ton compte est conservé. Contacte ton responsable atelier pour réactiver ton accès.':status?.pcDenied?'Sur ordinateur, seuls l’administrateur, les modérateurs et le directeur peuvent se connecter. Ouvre l’application sur ton téléphone.':error||'Contacte ton responsable atelier.'}</p><button className="secondary danger" onClick={()=>void logout()}>Se déconnecter</button></section></div>
}
