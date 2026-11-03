import {useState} from 'react';
import {supabase} from './lib/supabase';
export default function WasteReminders({row,canLog}:{row:{id:string,version:number,reminders73?:{at:string,by:string}[]},canLog:boolean}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 return <div>{!!row.reminders73?.length&&<details><summary>Relances du prestataire · {row.reminders73.length}</summary><ul>{row.reminders73.slice().reverse().map((r,i)=><li key={i}>{new Date(r.at).toLocaleString('fr-FR',{timeZone:'Europe/Paris',dateStyle:'short',timeStyle:'short'})} · {r.by}</li>)}</ul></details>}{canLog&&<button className="secondary" disabled={busy} onClick={async()=>{if(!confirm('Enregistrer que tu viens de relancer le prestataire pour cette demande ?'))return;setBusy(true);setError('');try{const {error}=await supabase.rpc('workshop_waste_remind73',{p_id:row.id,p_version:row.version});if(error)throw error;window.dispatchEvent(new Event('workshop-waste-refresh'))}catch(e:any){setError(e.message)}finally{setBusy(false)}}}>Enregistrer une relance</button>}{error&&<p role="alert">{error}</p>}</div>
}
