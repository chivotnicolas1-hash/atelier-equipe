import {useEffect,useState,type ReactNode} from 'react';
import {supabase,logout} from './lib/supabase';
import LoadingScreen from './loading-screen';
import Polls from './polls';
import {safeLink} from './lib/links';
export default function RequiredActions({children}:{children:ReactNode}){
 const [rows,setRows]=useState<any[]|null>(null),[error,setError]=useState(''),[opened,setOpened]=useState(''),[busy,setBusy]=useState(false);
 async function load(){const {data,error}=await supabase.rpc('workshop_required_buttons');if(error)setError(error.message);else{setRows(data||[]);setError('')}}
 useEffect(()=>{void load();const t=setInterval(()=>void load(),20000);const f=()=>void load();window.addEventListener('workshop-required-refresh',f);return()=>{clearInterval(t);window.removeEventListener('workshop-required-refresh',f)}},[]);
 if(rows===null&&!error)return <LoadingScreen/>;
 if(rows?.length===0)return <>{children}</>;
 const r=rows?.[0];
 return <main className="required-page"><section className="panel required-intro"><img src="/icon-fayet-v34-512.png" alt="Atelier Fayet 33"/><h1>Avant de continuer</h1>{r&&<><h2>{r.label}</h2><p>{r.required_reason}</p><small>{rows!.length} action(s) restante(s)</small></>}{error&&<p className="error-banner" role="alert">{error}</p>}<div className="order-actions"><button className="secondary" onClick={()=>void load()}>Vérifier</button><button className="secondary" onClick={()=>void logout()}>Se déconnecter</button></div></section>{r?.required_poll?<Polls key={r.id} id={r.required_poll} onOpen={()=>{}} onDeleted={()=>void load()}/>:r&&<section className="panel operations-content"><a className="primary" href={safeLink(r.url)||undefined} target="_blank" rel="noopener noreferrer" onClick={()=>setOpened(r.id+':'+r.requirement_version)}>{r.label}</a><p className="muted">Après avoir effectué l’action demandée sur ce site, confirme ci-dessous.</p><button className="secondary" disabled={busy||opened!==r.id+':'+r.requirement_version} onClick={async()=>{setBusy(true);const {error}=await supabase.rpc('workshop_required_ack',{p_id:r.id,p_version:r.requirement_version});setBusy(false);if(error)setError(error.message);else await load()}}>J’ai effectué l’action demandée</button></section>}</main>
}
