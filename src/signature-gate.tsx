import LoadingScreen from './loading-screen';
import {useCallback,useEffect,useState,type ReactNode} from 'react';
import {supabase,logout} from './lib/supabase';
import SignatureProfile from './signature-profile';
export default function SignatureGate({children}:{children:ReactNode}){
 const [state,setState]=useState<{required:boolean,admin:boolean,invalidated?:boolean}|null>(null),[error,setError]=useState('');
 const load=useCallback(async()=>{const {data,error}=await supabase.rpc('workshop_signature_gate');if(error){setError(error.code==='PGRST202'?'La mise à jour 42 doit être appliquée dans Supabase.':error.message);return}setState(data);setError('')},[]);
 useEffect(()=>{void load();const timer=setInterval(()=>void load(),30000);const update=()=>void load();window.addEventListener('focus',update);window.addEventListener('workshop-signature-change',update);return()=>{clearInterval(timer);window.removeEventListener('focus',update);window.removeEventListener('workshop-signature-change',update)}},[load]);
 if(!state&&!error)return <LoadingScreen/>;
 if(state&&!state.required)return <>{children}</>;
 return <main className="signature-onboarding"><section className="panel operations-content"><img className="signature-welcome-logo" src="/icon-fayet-v34-192.png" alt="Atelier Fayet 33"/><h1>{state?.invalidated?'Ta signature est à refaire':state?'Bienvenue · ta signature':'Chargement du profil'}</h1><p>{state?.invalidated?'L’administrateur a retiré ta signature. Trace une nouvelle signature lisible pour accéder à l’application.':'Enregistre ta signature pour accéder à l’application. Tu pourras la retrouver dans Mon profil.'}</p>{error&&<p role="alert" className="error-banner">{error}</p>}{error&&<button className="secondary" onClick={()=>void load()}>Réessayer</button>}{state?.required&&<SignatureProfile admin={state.admin} onSaved={()=>void load()}/>}<button className="secondary danger" onClick={()=>logout().catch(e=>setError(e.message))}>Se déconnecter</button></section></main>
}
