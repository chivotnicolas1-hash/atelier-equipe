import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import {useAutoRefresh} from './lib/sync';
export default function SuspendedStaff({onSaved}:{onSaved:()=>Promise<unknown>}){
 const [rows,setRows]=useState<any[]>([]),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 async function load(){const {data,error}=await supabase.rpc('workshop_suspended_staff');if(error)setError(error.message);else setRows(data||[])}
 useEffect(()=>{void load();const refresh=()=>{void load()};window.addEventListener('workshop-staff-status-change',refresh);return()=>window.removeEventListener('workshop-staff-status-change',refresh)},[]);useAutoRefresh(load,!busy);
 return <details className="panel suspended-staff"><summary>Comptes suspendus · {rows.length}</summary><div className="operations-content">{error&&<p className="error-banner" role="alert">{error}</p>}{!rows.length&&<p>Aucun compte suspendu.</p>}{rows.map(r=><article className="operation-card" key={r.id}><strong>{r.name}</strong><p>{r.team} · {r.email}</p><button className="secondary" disabled={busy} onClick={async()=>{if(!confirm('Réactiver l’accès de '+r.name+' ?'))return;setBusy(true);const {error}=await supabase.rpc('workshop_suspend_staff',{p_staff:r.id,p_suspended:false});if(error)setError(error.message);else{await load();await onSaved()}setBusy(false)}}>Réactiver le collaborateur</button></article>)}</div></details>
}
