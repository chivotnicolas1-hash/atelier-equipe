import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import {parisToday} from './lib/workshop';
export type StaffExtra={job:string,birth:string,jobVersion:number,birthVersion:number};
export default function StaffProfileFields({id,onChange,hideJob=false}:{hideJob?:boolean,id:string,onChange:(v:StaffExtra|null)=>void}){
 const [value,setValue]=useState<StaffExtra|null>(null),[error,setError]=useState('');
 useEffect(()=>{let live=true;onChange(null);setValue(null);setError('');void Promise.all([supabase.rpc('workshop_admin_job',{p_staff:id}),supabase.rpc('workshop_admin_birthday',{p_staff:id})]).then(([job,birth])=>{if(!live)return;const noAccount=!!job.error?.message.includes('Crée d’abord le compte');if(birth.error||(job.error&&!noAccount)){setError(job.error?.message||birth.error?.message||'Chargement impossible.');return}if(noAccount&&!hideJob)setError('La fonction pourra être renseignée après la création du compte de connexion.');const v={job:job.data?.job_title||'',birth:birth.data.birth_date||'',jobVersion:noAccount?-1:job.data.version,birthVersion:birth.data.version};setValue(v);onChange(v)});return()=>{live=false}},[id,onChange]);
 function update(p:Partial<StaffExtra>){if(!value)return;const v={...value,...p};setValue(v);onChange(v)}
 return <fieldset className="staff-extra"><legend>Informations du profil</legend>{error&&<p role="alert">{error}</p>}{!hideJob&&<label>Fonction dans l’atelier<input maxLength={100} disabled={!value||value.jobVersion<0} value={value?.job||''} onChange={e=>update({job:e.target.value})}/></label>}<label>Date de naissance<input type="date" min="1900-01-01" max={parisToday()} disabled={!value} value={value?.birth||''} onChange={e=>update({birth:e.target.value})}/></label><p className="muted">Réservé à l’administrateur. Efface la date pour retirer l’anniversaire.</p></fieldset>
}
