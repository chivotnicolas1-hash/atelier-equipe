import {useState} from 'react';import {CalendarClock,Clock3} from 'lucide-react';import {supabase} from './lib/supabase';import './waste100.css';
const when=(s:string)=>new Date(s).toLocaleString('fr-FR',{timeZone:'Europe/Paris',dateStyle:'short',timeStyle:'short'});
const date=(s:string)=>s.split('-').reverse().join('/');
export default function WasteTimeline100({row:r,canEdit}:{row:any,canEdit:boolean}){
 const [value,V]=useState(r.collection_expected100||''),[busy,B]=useState(false),[error,E]=useState('');
 const entries:{at:string,title:string,by?:string,detail?:string}[]=[];
 if(r.created_at)entries.push({at:r.created_at,title:'Demande créée',by:r.author_name});
 if(r.validated_at)entries.push({at:r.validated_at,title:'Demande validée',by:r.validated_name});
 if(r.updated_at)entries.push({at:r.updated_at,title:'Demande modifiée',by:r.updated_name});
 if(r.progress_at)entries.push({at:r.progress_at,title:'Suivi mis à jour',by:r.progress_name,detail:r.progress_note});
 for(const e of r.reminders73||[])entries.push({at:e.at,title:'Prestataire relancé',by:e.by});
 for(const e of r.collection_events100||[])entries.push({at:e.at,title:e.date?'Date de collecte annoncée':'Date de collecte retirée',by:e.by,detail:e.date?'Collecte prévue le '+date(e.date)+' · relances automatiques suspendues':'Suivi du délai réactivé'});
 for(const e of r.pickups72||[])entries.push({at:e.at,title:'Ramassage enregistré',by:e.by,detail:Object.entries(e.amounts||{}).map(([k,n])=>(names[k]||k)+' : '+n).join(' · ')});
 if(r.collected_at)entries.push({at:r.collected_at,title:'Enlèvement terminé',by:r.collected_name});
 entries.sort((a,b)=>Date.parse(a.at)-Date.parse(b.at));
 return <section className="waste-timeline100">{r.collection_expected100&&!r.collected_at&&<p className="waste-collection100"><CalendarClock size={20}/><span><strong>Collecte annoncée le {date(r.collection_expected100)}</strong><small>Relances automatiques suspendues. Cette date ne confirme pas le ramassage.</small></span></p>}<details><summary><Clock3 size={17}/> Chronologie de la demande · {entries.length}</summary><ol>{entries.map((e,i)=><li key={e.at+':'+i}><strong>{e.title}</strong><time dateTime={e.at}>{when(e.at)}</time>{e.by&&<span>{e.by}</span>}{e.detail&&<small>{e.detail}</small>}</li>)}</ol></details>{canEdit&&!r.collected_at&&<details><summary>Le prestataire a communiqué une date</summary><form onSubmit={async e=>{e.preventDefault();B(true);E('');try{const x=await supabase.rpc('workshop_waste_date100',{p_id:r.id,p_version:r.version,p_date:value||null});if(x.error)throw x.error;window.dispatchEvent(new Event('workshop-waste-refresh'))}catch(e:any){E(e.message)}finally{B(false)}}}><label>Date de collecte annoncée<input type="date" value={value} disabled={busy} onChange={e=>V(e.target.value)}/></label><p className="muted">Renseigner cette date suspend les rappels et ferme la tâche de relance. Retirer la date réactive le suivi habituel. Une notification déjà reçue sur un téléphone ne peut pas être rappelée.</p>{error&&<p role="alert">{error}</p>}<button type="submit" className="secondary" disabled={busy||value===(r.collection_expected100||'')}>Enregistrer la date</button>{value&&<button type="button" className="secondary" disabled={busy} onClick={()=>V('')}>Retirer la date</button>}</form></details>}</section>
}
const names:Record<string,string>={batteries:'Batteries',ferraille:'Ferraille',fonte:'Fonte',aluminium:'Aluminium',filtres:'Filtres',huiles:'Huiles',bidons:'Bidons',futs:'Fûts',souilles:'Matériaux souillés',refroidissement:'Refroidissement',aerosols:'Aérosols',pneus:'Pneus'};
