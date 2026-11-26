import {useEffect,useRef,useState} from 'react';
import {Snowflake} from 'lucide-react';
import {supabase} from './lib/supabase';
import './update124.css';

type AirconValue124={enabled:boolean,version:number};
export function AirconBadge124(){
 return <span className="aircon-badge124" role="img" aria-label="Habilité climatisation" title="Habilité climatisation"><Snowflake size={23} aria-hidden="true"/></span>;
}
export default function StaffAircon124({id}:{id:string}){
 const [value,setValue]=useState<AirconValue124|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const saving=useRef(false);
 useEffect(()=>{let live=true;setValue(null);setError('');setMessage('');void supabase.rpc('workshop_staff_aircon124',{p_staff:id}).then(({data,error})=>{if(!live)return;if(error){setError(error.code==='PGRST202'?'Installe le script SQL 124 pour gérer l’habilitation clim.':error.message);return}setValue(data)},()=>{if(live)setError('Chargement impossible. Ferme puis rouvre la fiche.')});return()=>{live=false}},[id]);
 async function change(enabled:boolean){
  if(!value||saving.current)return;saving.current=true;setBusy(true);setError('');setMessage('');
  try{const {data,error}=await supabase.rpc('workshop_staff_aircon124',{p_staff:id,p_enabled:enabled,p_version:value.version});if(error)throw error;setValue(data);setMessage(enabled?'Habilitation clim enregistrée.':'Habilitation clim retirée.')}
  catch(e:any){setError(e.message||'Modification non enregistrée. Réessaie.');try{const r=await supabase.rpc('workshop_staff_aircon124',{p_staff:id});if(!r.error)setValue(r.data)}catch{/* L'état précédent reste affiché avec l'erreur, sans valider la case. */}}
  finally{saving.current=false;setBusy(false)}
 }
 return <fieldset className="staff-aircon124"><legend><Snowflake size={18} aria-hidden="true"/> Habilitation climatisation</legend><label className="import-checkbox"><input type="checkbox" checked={value?.enabled===true} disabled={!value||busy} onChange={e=>void change(e.target.checked)}/><span>Habilité clim</span></label><p className="muted">Enregistrement immédiat, indépendant des autres champs de la fiche. Le flocon apparaît à droite des horaires sur l’écran atelier.</p>{busy&&<p role="status">Enregistrement…</p>}{message&&<p className="aircon-saved124" role="status">{message}</p>}{error&&<p className="error-banner" role="alert">{error}</p>}</fieldset>;
}
