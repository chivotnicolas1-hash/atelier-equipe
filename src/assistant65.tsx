import {useState,useEffect,useRef} from 'react';
import {supabase} from './lib/supabase';
import {useAutoRefresh} from './lib/sync';
type Entry={group:string,text:string,at:string,action:boolean};
type Brief={start:string,end:string,pending:number,events:Entry[]};
const groups=['Signalements','Consommables','Déchets','Congés','BT à reprendre'];
const date=(s:string)=>s.split('-').reverse().join('/');
// Résumé extractif local : similarité lexicale entre fiches, puis classement TextRank.
// Le poids des dossiers en attente guide la sélection ; aucun texte n’est inventé.
function highlights(rows:Entry[]){
 const sorted=[...rows].sort((a,b)=>Number(b.action)-Number(a.action)), sample=sorted.slice(0,80);
 const stop=new Set('pour dans avec sans une les des sur est par son ses aux du de des le la un et en à'.split(' '));
 const tokens=sample.map(r=>new Set((r.text.toLocaleLowerCase('fr').match(/[\p{L}\d]+/gu)||[]).filter(w=>w.length>2&&!stop.has(w))));
 const w=tokens.map((s,i)=>tokens.map((t,j)=>i===j?0:[...s].filter(x=>t.has(x)).length/Math.sqrt(Math.max(1,s.size*t.size))));
 const sums=w.map(a=>a.reduce((x,y)=>x+y,0));let rank=sample.map(()=>1);
 for(let k=0;k<12;k++)rank=sample.map((r,i)=>.15*(r.action?2:1)+.85*w.reduce((n,a,j)=>n+(sums[j]?rank[j]*a[i]/sums[j]:0),0));
 return sample.map((r,i)=>({r,score:rank[i]+(r.action?1:0)})).sort((a,b)=>b.score-a.score).filter((v,i,all)=>all.findIndex(x=>x.r.group===v.r.group)===i).slice(0,3).map(x=>x.r);
}
function Body(){
 const [week,setWeek]=useState(false),[data,setData]=useState<Brief|null>(null),[err,setErr]=useState('');const revision=useRef(0);
 async function read(){const id=++revision.current;const r=await supabase.rpc('workshop_assistant65',{p_week:week});if(id!==revision.current)return;if(r.error)setErr('Lecture impossible : '+r.error.message);else{setErr('');setData(r.data)}}
 useEffect(()=>{setData(null);void read();return()=>{revision.current++}},[week]);useAutoRefresh(read);
 return <div className="operations-content"><div className="order-actions">{[false,true].map(v=><button key={String(v)} className={v===week?'primary':'secondary'} aria-pressed={v===week} onClick={()=>setWeek(v)}>{v?'Semaine passée':'La veille'}</button>)}</div>{err&&<p role="alert">{err}</p>}{!data&&!err&&<p>Lecture des données…</p>}{data&&<><h3>{week?'Du '+date(data.start)+' au '+date(data.end):'Journée du '+date(data.start)}</h3><p>{data.events.length?data.events.length+' fiche(s) à consulter sur la période.':'Aucune activité enregistrée sur la période.'} {data.pending?data.pending+' demande(s) de congé encore en attente d’accord, toutes dates confondues.':'Aucune demande de congé en attente.'}</p>{!!data.events.length&&<><h4>À retenir</h4><ul>{highlights(data.events).map(r=><li key={r.group}><strong>{r.group}</strong> · {r.text}</li>)}</ul></>}{groups.map(g=>{const rows=data.events.filter(x=>x.group===g);return <details key={g} className="brief-category"><summary>{g} · {rows.length}</summary>{rows.length?<ul>{rows.map((r,i)=><li key={i}>{r.text}</li>)}</ul>:<p>Aucune fiche sur cette période.</p>}</details>})}</>}</div>
}
export default function Assistant65(){const [open,setOpen]=useState(false);return <details className="panel brief65" open={open} onToggle={e=>setOpen(e.currentTarget.open)}><summary><strong>Assistant atelier</strong><small>Débrief de la veille et de la semaine · Administration</small></summary>{open&&<Body/>}</details>}
