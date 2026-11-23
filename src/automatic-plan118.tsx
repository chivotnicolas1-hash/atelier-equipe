import {useEffect,useRef,useState} from 'react';
import {CalendarClock} from 'lucide-react';
import {supabase} from './lib/supabase';
import {parisToday} from './lib/workshop';
import {useAutoRefresh} from './lib/sync';
function stamp120(v:string|undefined){return v&&Number.isFinite(Date.parse(v))?new Date(v).toLocaleString('fr-FR',{timeZone:'Europe/Paris',dateStyle:'short',timeStyle:'short'}):null}
function reason120(info:any){
 const check=info?.automation?.last_check;
 if(info?.draft_exists&&info?.finished)return 'Un nouveau brouillon est en cours. Il est conservé sans remplacement automatique.';
 if(info?.retry_planned){
  const when=stamp120(info.retry_after);
  return 'Une préparation a été fermée avant 5 h. Une nouvelle proposition sera préparée'+(when?' à partir du '+when:' à partir de 5 h')+', dès que les horaires seront disponibles. '+(check?.state==='failed'?'Le dernier essai a échoué'+(check.error_code?' (code '+check.error_code+')':'')+' ; un nouveau passage est prévu.':'La publication reste manuelle.');
 }
 if(info?.finished||info?.kind==='closed'){
  const first=info.kind==='closed'?stamp120(info.created_at):null,last=stamp120(info.finished_at);
  const action=info.last_closure?.action==='publish'?'publiée':info.last_closure?.action==='discard'?'annulée':'publiée ou fermée';
  return 'La préparation a été '+action+(last?' le '+last:'')+'. '+(first?'Première clôture enregistrée le '+first+'. ':'')+'La génération automatique conserve cette décision. Pour créer un nouveau brouillon, utilise la génération manuelle.';
 }
 if(info?.kind==='existing_plan')return 'Des affectations existent déjà pour cette date. Elles sont conservées ; aucune nouvelle proposition automatique ne les remplace.';
 if(info?.kind==='existing_draft')return 'Un brouillon existait déjà. Il est conservé sans être écrasé.';
 if(check?.state==='failed')return 'Le dernier essai serveur a échoué'+(check.error_code?' (code '+check.error_code+')':'')+'. La génération manuelle reste disponible.';
 if(check?.state==='waiting_schedule')return 'En attente de collaborateurs présents avec des horaires. Le programme réessaiera au prochain passage.';
 if(check?.state==='before_5')return 'La préparation commencera à partir de 5 h, heure de Paris.';
 if(!info?.kind&&!check)return 'Aucun passage enregistré pour cette date. La préparation automatique concerne la journée en cours.';
 return '';
}
export default function AutomaticPlan118({date,onGenerated}:{date:string,onGenerated?:()=>void}){
 const [info,I]=useState<any>(null),[error,E]=useState('');const alive=useRef(false),sequence=useRef(0),changed=useRef(onGenerated);changed.current=onGenerated;
 async function read(ensure=false){const id=++sequence.current;let warning='';
  try{
   let r=await supabase.rpc('workshop_plan_automatic_status120',{p_date:date});
   if(!alive.current||id!==sequence.current)return;
   if(r.error?.code==='PGRST202'||r.error?.code==='42883'){
    warning='Le suivi et le secours automatique nécessitent supabase/120-installation.sql. Consulte le guide avant de l’exécuter.';
    r=await supabase.rpc('workshop_plan_automatic_status118',{p_date:date});
   }else if(!r.error&&r.data?.version===120&&ensure&&date===parisToday()){
    const check=await supabase.rpc('workshop_plan_ensure120',{p_date:date});
    if(check.error)warning=check.error.message;
    else if(check.data?.state==='generated'&&alive.current&&id===sequence.current)changed.current?.();
    r=await supabase.rpc('workshop_plan_automatic_status120',{p_date:date});
   }
   if(!alive.current||id!==sequence.current)return;
   if(r.error){E(r.error.code==='PGRST202'?'Le moteur de préparation attendu n’est pas disponible. Vérifie la version installée avant d’exécuter les scripts.':r.error.message);return}
   I(r.data);E(warning);
  }catch{if(alive.current&&id===sequence.current)E('Impossible de vérifier la préparation automatique. Nouvelle vérification dans 20 secondes.')}
 }
 useEffect(()=>{alive.current=true;I(null);E('');void read(true);return()=>{alive.current=false;sequence.current++}},[date]);
 useAutoRefresh(()=>read());
 const automation=info?.automation,reason=reason120(info);
 return <aside className="automatic-plan118"><CalendarClock size={18} aria-hidden="true"/><div><strong>Préparation automatique quotidienne</strong><p>À partir de 5 h, avec les horaires importés et les compétences « Autonome ». Les plans existants sont conservés. La publication reste manuelle.</p>
 {info?.kind==='generated'&&<p className="automatic-plan118-result">Proposition initiale du {new Date(info.created_at).toLocaleString('fr-FR',{timeZone:'Europe/Paris',dateStyle:'short',timeStyle:'short'})} · {info.summary?.added||0} affectation(s).{!info.finished&&' Vérifie les postes et la couverture des horaires avant de publier.'}</p>}
 {reason&&<p role="status">{reason}</p>}
 {info?.last_retry_at&&!info?.finished&&<p>Proposition recréée après une clôture précoce : {stamp120(info.last_retry_at)}. L’historique de clôture est conservé.</p>}
 {automation&&<details><summary>État de la préparation automatique</summary><p>{automation.scheduler_known?(automation.scheduled?'Programme serveur actif · passage toutes les 10 minutes.':'Attention : le programme serveur attendu n’est pas actif ou sa commande a changé.'):'Programmation serveur non vérifiée. Consulte le diagnostic Supabase.'}</p><p>{automation.last_check?.checked_at?'Dernière vérification : '+new Date(automation.last_check.checked_at).toLocaleString('fr-FR',{timeZone:'Europe/Paris'}):'Aucune vérification enregistrée pour ce jour.'}</p><p>À l’ouverture du plan du jour par un gestionnaire, un essai de secours est effectué. Il ne remplace ni un plan existant ni un brouillon et ne publie rien.</p></details>}
 {info?.kind==='generated'&&!info.finished&&(!!info.summary?.uncovered?.length||!!info.summary?.unassigned?.length)&&<details><summary>Points à vérifier dans la proposition initiale</summary><p>Postes restants : {info.summary.uncovered?.join(' · ')||'aucun'}</p><p>Collaborateurs restants : {info.summary.unassigned?.join(', ')||'aucun'}</p></details>}
 {error&&<p className="error-banner" role="alert">{error}</p>}</div></aside>;
}
