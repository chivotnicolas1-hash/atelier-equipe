import {useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import {parisToday} from './lib/workshop';
export function BirthdayGreeting({name,today}:{name:string,today:string}){
 const [birthday,setBirthday]=useState(false);
 useEffect(()=>{let live=true;const load=()=>void supabase.rpc('workshop_birthday_get').then(({data,error})=>{if(live&&!error)setBirthday(!!data?.birthday_today)});load();window.addEventListener('workshop-birthday-change',load);return()=>{live=false;window.removeEventListener('workshop-birthday-change',load)}},[today]);
 return birthday?<section className="birthday-greeting" role="status"><strong>Joyeux anniversaire, {name} ! 🎂</strong><p>Toute l’équipe d’Atelier Fayet 33 te souhaite une très belle journée !</p></section>:null;
}
