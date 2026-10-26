import {useEffect,useState} from 'react';
import {Wrench} from 'lucide-react';
import {supabase} from './lib/supabase';
import {Dialog,DialogContent,DialogTitle,DialogDescription} from './components/ui/dialog';
type Item={id:string,bt:string,remaining:string,author_name:string,created_at:string};
export default function LunchTeam(){
 const [rows,setRows]=useState<Item[]>([]),[open,setOpen]=useState(false),[error,setError]=useState('');
 useEffect(()=>{let live=true;async function load(){const {data,error}=await supabase.rpc('workshop_lunch_team');if(!live)return;if(error){setError('Impossible d’actualiser les reprises.');setRows([])}else{setRows(data||[]);setError('')}}void load();const timer=setInterval(()=>void load(),15000);window.addEventListener('focus',load);return()=>{live=false;clearInterval(timer);window.removeEventListener('focus',load)}},[]);
 return <>{rows.length>0&&<div className="lunch-return-launch"><button className="secondary" onClick={()=>setOpen(true)}><Wrench size={18}/> Reprise BT en cours <span className="count">{rows.length}</span></button></div>}{open&&<Dialog open onOpenChange={setOpen}><DialogContent className="app-dialog"><DialogTitle>BT à reprendre dans l’atelier</DialogTitle><DialogDescription>Les reprises transmises avant ton retour du déjeuner et pas encore prises en compte.</DialogDescription>{error&&<p role="alert">{error}</p>}{!rows.length&&<p>Aucun BT disponible ou créneau de consultation terminé.</p>}{rows.map(r=><article className="operation-card" key={r.id}><h3>BT {r.bt}</h3><p className="muted">Transmis par {r.author_name}</p><p className="handoff-remaining">{r.remaining}</p></article>)}</DialogContent></Dialog>}</>
}
