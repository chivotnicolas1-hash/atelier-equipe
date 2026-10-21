import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import {parisToday} from './lib/workshop';
export function BirthdayProfile(){
 const [value,setValue]=useState(''),[ready,setReady]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 useEffect(()=>{let live=true;void supabase.rpc('workshop_birthday_get').then(({data,error})=>{if(!live)return;if(error)setMessage(error.message);else{setValue(data?.birth_date||'');setReady(true)}});return()=>{live=false}},[]);
 return <details className="profile-section"><summary>Date de naissance</summary><form className="profile-section-body" onSubmit={async e=>{e.preventDefault();setBusy(true);setMessage('');try{const {error}=await supabase.rpc('workshop_birthday_save',{p_date:value||null});if(error)throw Error(error.message);setMessage('Date de naissance enregistrée.');window.dispatchEvent(new Event('workshop-birthday-change'))}catch(e:any){setMessage(e.message)}finally{setBusy(false)}}}><label>Date de naissance<input type="date" min="1900-01-01" max={parisToday()} value={value} disabled={busy||!ready} onChange={e=>setValue(e.target.value)}/></label><p className="muted">Facultatif et visible uniquement dans ton profil. Un message te souhaitera ton anniversaire le jour venu. Efface la date pour la retirer.</p><button className="secondary" disabled={busy||!ready}>Enregistrer la date</button>{message&&<p role="status">{message}</p>}</form></details>
}
export function BirthdayGreeting({name,today}:{name:string,today:string}){
 const [birthday,setBirthday]=useState(false);
 useEffect(()=>{let live=true;const load=()=>void supabase.rpc('workshop_birthday_get').then(({data,error})=>{if(live&&!error)setBirthday(!!data?.birthday_today)});load();window.addEventListener('workshop-birthday-change',load);return()=>{live=false;window.removeEventListener('workshop-birthday-change',load)}},[today]);
 return birthday?<section className="birthday-greeting" role="status"><strong>Joyeux anniversaire, {name} ! 🎂</strong><p>Toute l’équipe d’Atelier Fayet 33 te souhaite une très belle journée !</p></section>:null;
}
