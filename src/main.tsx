import {useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import type {Session} from '@supabase/supabase-js';
import {Wrench,LogIn,RefreshCw} from 'lucide-react';
import {supabase,loginPassword} from './lib/supabase';
import Workshop from './workshop';
import './globals.css';
function App(){
 const [session,setSession]=useState<Session|null>(null),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{let active=true;const url=new URL(location.href);const callbackError=url.searchParams.get('error_description')||new URLSearchParams(url.hash.slice(1)).get('error_description');if(callbackError){setError(callbackError);history.replaceState({},'',location.pathname);}
 supabase.auth.getSession().then(({data,error})=>{if(!active)return;if(error)setError(error.message);setSession(data.session);setLoading(false);}).catch(()=>{if(active){setError('Connexion indisponible. Réessaie.');setLoading(false);}});
 const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,s)=>{if(active){setSession(s);setLoading(false);}});
 return()=>{active=false;subscription.unsubscribe();};},[]);
 if(loading)return <div className="empty large"><RefreshCw className="spin"/>Connexion à l’atelier…</div>;
 if(session)return <Workshop key={session.user.id}/>;
 return <div className="login-page"><section className="login-card"><span className="brand-mark"><Wrench size={28}/></span><div className="eyebrow">ATELIER / ÉQUIPE</div><h1>Ta journée commence ici.</h1><p className="muted">Retrouve ton poste, confirme ta présence et consulte les tâches qui te sont confiées.</p>{error&&<div className="error-banner" role="alert">{error}</div>}<form className="login-form" onSubmit={async e=>{e.preventDefault();const f=new FormData(e.currentTarget);setBusy(true);setError('');try{await loginPassword(String(f.get('email')),String(f.get('password')))}catch(e:any){setError(e.message)}finally{setBusy(false)}}}><label>Adresse e-mail<input name="email" type="email" autoComplete="username" required placeholder="prenom@exemple.fr"/></label><label>Mot de passe<input name="password" type="password" autoComplete="current-password" required/></label><button className="primary full" disabled={busy}><LogIn size={20}/>{busy?'Connexion…':'Se connecter'}</button></form><p className="login-note">Utilise les identifiants transmis par ton administrateur. Pour obtenir un accès ou réinitialiser ton mot de passe, contacte-le.</p></section></div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
