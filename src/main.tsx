import SignatureGate from './signature-gate';
import Maintenance from './maintenance';
import {PasswordRequest} from './password-tools';
import {DesignProvider,useDesign} from './design';
import LoadingScreen from './loading-screen';
import {ThemeToggle} from './theme';
import {useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import type {Session} from '@supabase/supabase-js';
import {Wrench,LogIn,RefreshCw,Eye,EyeOff} from 'lucide-react';
import {supabase,loginPassword} from './lib/supabase';
import Workshop from './workshop';
import './globals.css';
import './professional.css';
function App(){
 const {design}=useDesign();
 const [showPassword,setShowPassword]=useState(false);
 const [session,setSession]=useState<Session|null>(null),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{let active=true;const url=new URL(location.href);const callbackError=url.searchParams.get('error_description')||new URLSearchParams(url.hash.slice(1)).get('error_description');if(callbackError){setError(callbackError);history.replaceState({},'',location.pathname);}
 supabase.auth.getSession().then(({data,error})=>{if(!active)return;if(error)setError(error.message);setSession(data.session);setLoading(false);}).catch(()=>{if(active){setError('Connexion indisponible. Réessaie.');setLoading(false);}});
 const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,s)=>{if(active){setSession(s);setLoading(false);}});
 return()=>{active=false;subscription.unsubscribe();};},[]);
 if(loading)return <LoadingScreen/>;
 if(session)return <Maintenance userId={session.user.id}><SignatureGate key={session.user.id}><Workshop/></SignatureGate></Maintenance>;
 return <Maintenance><div className="login-page login-v55"><section className="login-card"><div className="login-theme"><ThemeToggle/></div><span className="brand-mark"><img src="/icon-fayet-v34-512.png" alt="Logo Atelier Fayet 33" className="app-logo"/></span><div className="eyebrow">{design.appName.toUpperCase()}</div><h1>{design.loginTitle}</h1><p className="muted">{design.loginDescription}</p>{error&&<div className="error-banner" role="alert">{error}</div>}<form className="login-form" onSubmit={async e=>{e.preventDefault();const f=new FormData(e.currentTarget);setBusy(true);setError('');try{await loginPassword(String(f.get('email')),String(f.get('password')))}catch(e:any){setError(e.message)}finally{setBusy(false)}}}><label>Adresse e-mail<input name="email" type="email" autoComplete="username" required placeholder="exemple@norauto.fr"/></label><label>Mot de passe<span className="password-field"><input name="password" type={showPassword?'text':'password'} autoComplete="current-password" required/><button type="button" className="icon-btn" aria-label={showPassword?'Masquer le mot de passe':'Afficher le mot de passe'} aria-pressed={showPassword} onClick={()=>setShowPassword(v=>!v)}>{showPassword?<EyeOff size={20}/>:<Eye size={20}/>}</button></span></label><button className="primary full" disabled={busy}><LogIn size={20}/>{busy?'Connexion…':'Se connecter'}</button></form><PasswordRequest/><p className="login-note">{design.loginNote}</p></section></div></Maintenance>;
}
createRoot(document.getElementById('root')!).render(<DesignProvider><App/></DesignProvider>);
