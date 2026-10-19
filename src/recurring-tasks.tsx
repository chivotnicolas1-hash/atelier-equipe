import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import {Dialog,DialogContent,DialogTitle,DialogDescription} from './components/ui/dialog';
type Series={id:string,title:string,staff_name:string,unit:string,every:number,next_due:string,ends_on:string|null,active:boolean};
const units:Record<string,string>={day:'jour(s)',week:'semaine(s)',month:'mois'};
export default function RecurringTasks({onClose}:{onClose:()=>void}){
 const [rows,setRows]=useState<Series[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function load(){const {data,error}=await supabase.rpc('workshop_list_recurring_tasks');if(error)throw Error(error.code==='PGRST202'?'Applique le script 18-taches-recurrentes.sql dans Supabase.':error.message);setRows(data)}
 useEffect(()=>{void load().catch(e=>setError(e.message))},[]);
 async function stop(s:Series){if(!confirm('Arrêter les futures occurrences de « '+s.title+' » ? Les tâches déjà créées restent disponibles.'))return;setBusy(true);setError('');try{const {error}=await supabase.rpc('workshop_stop_recurring_task',{p_id:s.id});if(error)throw error;await load()}catch(e:any){setError(e.message)}finally{setBusy(false)}}
 return <Dialog open onOpenChange={v=>!v&&!busy&&onClose()}><DialogContent className="app-dialog"><DialogTitle>Tâches récurrentes</DialogTitle><DialogDescription>Chaque occurrence est indépendante. Modifier ou supprimer une tâche ne modifie pas les prochaines occurrences. Pour changer une série, arrête-la puis crée une nouvelle récurrence.</DialogDescription>{error&&<p role="alert" className="error-banner">{error}</p>}{!rows.length&&!error&&<p>Aucune récurrence enregistrée.</p>}{rows.map(r=><article key={r.id} className="recurrence-card"><strong>{r.title}</strong><p>{r.staff_name} · Tous les {r.every} {units[r.unit]}</p><p>{r.active?'Prochaine échéance : '+new Date(r.next_due+'T12:00:00').toLocaleDateString('fr-FR'):'Récurrence arrêtée ou terminée'}</p>{r.ends_on&&<small>Fin : {new Date(r.ends_on+'T12:00:00').toLocaleDateString('fr-FR')}</small>}{r.active&&<button type="button" className="secondary danger" disabled={busy} onClick={()=>stop(r)}>Arrêter la récurrence</button>}</article>)}</DialogContent></Dialog>
}
