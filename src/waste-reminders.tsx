import WasteTimeline100 from './waste-timeline100';
import {useState} from 'react';
import {supabase} from './lib/supabase';
export default function WasteReminders({row,canLog}:{row:any,canLog:boolean}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 return <div><WasteTimeline100 key={row.id+':'+row.version} row={row} canEdit={canLog}/>{canLog&&<button className="secondary" disabled={busy} onClick={async()=>{if(!confirm('Enregistrer que tu viens de relancer le prestataire pour cette demande ?'))return;setBusy(true);setError('');try{const {error}=await supabase.rpc('workshop_waste_remind73',{p_id:row.id,p_version:row.version});if(error)throw error;window.dispatchEvent(new Event('workshop-waste-refresh'))}catch(e:any){setError(e.message)}finally{setBusy(false)}}}>Enregistrer une relance</button>}{error&&<p role="alert">{error}</p>}</div>
}
