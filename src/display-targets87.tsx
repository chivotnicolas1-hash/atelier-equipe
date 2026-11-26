import {targetProgress} from './lib/target-progress';
import TargetBackdrop117 from './target-backdrop117';
import SaleCelebration123 from './sale-celebration123';
import {useEffect,useState,useRef,useId} from 'react';
import {ClipboardCheck} from 'lucide-react';
import {supabase} from './lib/supabase';
import {setSyncInterval,clearSyncInterval} from './lib/sync';
import {parisToday}from'./lib/workshop';
import './update123.css';
const labelsBase:Record<string,string>={purge:'Purge de freins',batteries:'Batteries montées',geometry:'Géométrie',clim:'Clim'};
type Person123={name:string,quantity:number};
function SalesTile123({category,label,total,goal,people,detailsReady}:{category:string,label:string,total:number,goal:number,people:Person123[],detailsReady:boolean}){
 const id=useId(),[open,O]=useState(false),[placement,P]=useState({right:false,above:false});
 const reveal=(node:HTMLElement)=>{const r=node.getBoundingClientRect();P({right:r.left+r.width/2>window.innerWidth/2,above:r.bottom>window.innerHeight-260});O(true)};
 return <div className={'sales-target-wrap123'+(open?' is-open':'')} tabIndex={0} role="group" aria-label={label+' : '+total+' ventes pour une cible de '+goal} aria-describedby={open?id:undefined} onMouseEnter={e=>reveal(e.currentTarget)} onMouseLeave={()=>O(false)} onFocus={e=>reveal(e.currentTarget)} onBlur={()=>O(false)} onPointerDown={e=>{if(e.pointerType==='touch'){e.preventDefault();if(open)O(false);else reveal(e.currentTarget)}}} onKeyDown={e=>{if(e.key==='Escape')O(false);if(e.key==='Enter'||e.key===' '){e.preventDefault();if(open)O(false);else reveal(e.currentTarget)}}}>
 <article className={'display-target87'+(goal>0&&total>=goal?' reached':'')}><TargetBackdrop117 category={category} label={label}/><small>{label}</small><span>{total} / <strong>{goal}</strong></span><small>ventes / cible</small></article>
 {open&&<div id={id} role="tooltip" className={'sales-tooltip123'+(placement.right?' align-right':'')+(placement.above?' above':'')}><strong>{label} · Ventes réalisées</strong>{!detailsReady?<p>Détail momentanément indisponible.</p>:!people.length?<p>Aucune vente enregistrée.</p>:<ul>{people.map((person,i)=><li key={i}><span>{person.name}</span><b>{person.quantity} vente{person.quantity!==1?'s':''}</b></li>)}</ul>}</div>}
 </div>;
}
export default function DisplayTargets87({snapshot,date}:{snapshot?:any,date:string}){
 const[data,S]=useState<any>(null),[error,E]=useState(''),[celebration,C]=useState(0);
 const pulse=useRef<{date:string,at:number}|null>(null);
 useEffect(()=>{if(snapshot){S(snapshot.performance?{...snapshot.performance,...snapshot.sales_details123,_date123:snapshot.date}:null);E(snapshot.performance?'':'Compteurs en attente de la mise à jour SQL 87.');return}
 S(null);let live=true,running=false;async function refresh(){if(running)return;running=true;try{
  const[t,q,people]=await Promise.all([supabase.rpc('workshop_targets86',{p_date:date}),supabase.rpc('workshop_quality_status',{p_date:date}),supabase.rpc('workshop_screen_sales123',{p_date:date})]);
  if(t.error)throw t.error;if(q.error)throw q.error;
  if(live){S({...t.data,quality:q.data,...(!people.error?people.data:{}),_date123:date});E(people.error?'Les compteurs restent visibles ; le détail des ventes est indisponible. Vérifie le SQL MAJ123.':'')}
 }catch{if(live)E('Actualisation des cibles indisponible.')}finally{running=false}}
 void refresh();const timer=setSyncInterval(()=>void refresh(),20000);return()=>{live=false;clearSyncInterval(timer)}},[snapshot,date]);
 useEffect(()=>{
  if(data?._date123!==date||!Object.prototype.hasOwnProperty.call(data,'last_sale_at123'))return;
  const at=Date.parse(data.last_sale_at123||'')||0,previous=pulse.current;
  if(!previous||previous.date!==date){pulse.current={date,at};return}
  if(at>previous.at){pulse.current={date,at};if(date===parisToday())C(v=>v+1)}
 },[data,date]);
 const labels={...labelsBase,...data?.labels},keys=Object.keys(labels),progress=targetProgress(data?.targets,data?.totals,keys);
 return <section className="display-targets87" aria-label="Cibles et contrôles qualité du jour"><SaleCelebration123 event={celebration}/><header><h2>Cibles du jour</h2>{data&&<strong>{progress.percent==null?'—':progress.percent.toLocaleString('fr-FR',{maximumFractionDigits:1})+' %'} · {progress.realized} ventes</strong>}</header>{error&&<p role="status">{error}</p>}{data&&<div className="display-targets-grid87">{keys.map(k=><SalesTile123 key={k} category={k} label={labels[k]} total={Number(data.totals?.[k]||0)} goal={Number(data.targets?.[k]||0)} people={Array.isArray(data.contributors123?.[k])?data.contributors123[k]:[]} detailsReady={!!data.contributors123}/>)}<article className={'display-target87 display-quality87'+(data.quality?.goal>0&&data.quality.total>=data.quality.goal?' reached':'')}><TargetBackdrop117 category="quality"/><small><ClipboardCheck size={17}/>Contrôles qualité</small><span>{data.quality?.total??'—'} / <strong>{data.quality?.goal??'—'}</strong></span><small>Hors ventes</small></article></div>}</section>;
}
