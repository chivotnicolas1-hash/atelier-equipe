import {useEffect,useState} from 'react';
import {ClipboardCheck} from 'lucide-react';
import {supabase} from './lib/supabase';
import {setSyncInterval,clearSyncInterval} from './lib/sync';
import {parisToday} from './lib/workshop';
const labelsBase:Record<string,string>={purge:'Purge de freins',batteries:'Batteries montées',geometry:'Géométrie',clim:'Clim'};
export default function DisplayTargets87({snapshot}:{snapshot?:any}){
 const[data,S]=useState<any>(null),[error,E]=useState('');
 useEffect(()=>{if(snapshot){S(snapshot.performance||null);E(snapshot.performance?'':'Compteurs en attente de la mise à jour SQL 87.');return}let live=true,running=false;async function refresh(){if(running)return;running=true;try{const date=parisToday();const[t,q]=await Promise.all([supabase.rpc('workshop_targets86',{p_date:date}),supabase.rpc('workshop_quality_status',{p_date:date})]);if(t.error)throw t.error;if(q.error)throw q.error;if(live){S({...t.data,quality:q.data});E('')}}catch{if(live)E('Actualisation des cibles indisponible.')}finally{running=false}}void refresh();const timer=setSyncInterval(()=>void refresh(),20000);return()=>{live=false;clearSyncInterval(timer)}},[snapshot]);
 const labels={...labelsBase,...data?.labels},keys=Object.keys(labels),goal=keys.reduce((n,k)=>n+Number(data?.targets?.[k]||0),0),total=keys.reduce((n,k)=>n+Number(data?.totals?.[k]||0),0);
 return <section className="display-targets87" aria-label="Cibles et contrôles qualité du jour"><header><h2>Cibles du jour</h2>{data&&<strong>{goal>0?Math.round(total/goal*100)+' %':'—'} · {total} / {goal}</strong>}</header>{error&&<p role="status">{error}</p>}{data&&<div className="display-targets-grid87">{keys.map(k=>{const g=Number(data.targets?.[k]||0),n=Number(data.totals?.[k]||0);return <article key={k} className={'display-target87'+(g>0&&n>=g?' reached':'')}><small>{labels[k]}</small><span>{n} / <strong>{g}</strong></span><small>ventes / cible</small></article>})}<article className={'display-target87 display-quality87'+(data.quality?.goal>0&&data.quality.total>=data.quality.goal?' reached':'')}><small><ClipboardCheck size={17}/>Contrôles qualité</small><span>{data.quality?.total??'—'} / <strong>{data.quality?.goal??'—'}</strong></span><small>Hors ventes additionnelles</small></article></div>}</section>
}
