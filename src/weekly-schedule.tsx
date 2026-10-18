import {useEffect,useState} from 'react';
import {Dialog,DialogContent,DialogTitle,DialogDescription} from './components/ui/dialog';
import {supabase} from './lib/supabase';
import {parisToday,presenceLabels} from './lib/workshop';
import {lunchBreaks,type Slot} from './lib/schedule';
type Week={start:string,days:{date:string,presence:string,slots:Slot[]}[]};
const pretty=(date:string)=>new Date(date+'T12:00:00').toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long'});
export default function WeeklySchedule({date,onClose}:{date:string,onClose:()=>void}){
 const [selected,setSelected]=useState(date),[week,setWeek]=useState<Week|null>(null),[error,setError]=useState(''),[loading,setLoading]=useState(true);
 useEffect(()=>{let active=true;setLoading(true);setError('');setWeek(null);void supabase.rpc('workshop_my_week',{p_date:selected}).then(({data,error})=>{if(!active)return;if(error)setError(error.code==='PGRST202'?'Applique le script 32-sondages-horaires.sql.':error.message);else setWeek(data);setLoading(false)});return()=>{active=false}},[selected]);
 function move(n:number){const d=new Date(selected+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);setSelected(d.toISOString().slice(0,10))}
 return <Dialog open onOpenChange={v=>!v&&onClose()}><DialogContent className="app-dialog weekly-schedule"><DialogTitle>Mes horaires de la semaine</DialogTitle><DialogDescription>Horaires prévus du lundi au dimanche, selon le planning renseigné.</DialogDescription><div className="week-controls"><button className="secondary" onClick={()=>move(-7)} disabled={loading}>Semaine précédente</button><button className="secondary" onClick={()=>setSelected(parisToday())} disabled={loading}>Cette semaine</button><button className="secondary" onClick={()=>move(7)} disabled={loading}>Semaine suivante</button></div>{loading?<p>Chargement…</p>:error?<p className="error-banner" role="alert">{error}</p>:week&&<><p className="muted">Du {pretty(week.start)} au {pretty(week.days[6].date)}</p><div className="weekly-schedule-days">{week.days.map(d=><article key={d.date} className={d.date===parisToday()?'today-schedule':''}><h3>{pretty(d.date)}</h3><p>{d.slots.length?d.slots.map(s=>s.start+'–'+s.end).join(' · '):d.presence==='present'?'Horaires non renseignés':presenceLabels[d.presence]||'À renseigner'}</p>{d.slots.length>0&&d.presence!=='present'&&<small>{presenceLabels[d.presence]}</small>}{d.presence==='present'&&lunchBreaks(d.slots).map(b=><small key={b.start}>Déjeuner prévu : {b.start}–{b.end}</small>)}</article>)}</div></>}</DialogContent></Dialog>
}
