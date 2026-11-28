import {useEffect,useRef,useState} from 'react';
import {Camera} from 'lucide-react';
import type {Worker} from 'tesseract.js';
import PlateCapture128 from './plate-capture128';
import {ocrCanvas128,plateOptions128} from './lib/plate-frame128';
export default function PlateScanner({disabled,current,onResult,onBusy}:{disabled:boolean,current:string,onResult:(plate:string)=>void,onBusy:(busy:boolean)=>void}){
 const worker=useRef<Worker|null>(null),run=useRef(0),alive=useRef(true);
 const[open,O]=useState(false),[scanning,S]=useState(false),[status,T]=useState(''),[options,P]=useState<ReturnType<typeof plateOptions128>>([]),[preview,V]=useState('');
 useEffect(()=>{alive.current=true;const blocked=()=>cancel();window.addEventListener('workshop-notifications-blocked128',blocked);return()=>{alive.current=false;run.current++;void worker.current?.terminate();worker.current=null;window.removeEventListener('workshop-notifications-blocked128',blocked)}},[]);
 function cancel(){run.current++;void worker.current?.terminate();worker.current=null;S(false);onBusy(false);T('Lecture annulée. La saisie manuelle reste disponible.')}
 async function scan(source:HTMLCanvasElement){
  O(false);const id=++run.current;S(true);onBusy(true);P([]);T('Préparation de la plaque cadrée…');V(source.toDataURL('image/jpeg',.7));let local:Worker|null=null,timer:ReturnType<typeof setTimeout>|undefined;
  try{const operation=async()=>{const {createWorker,PSM}=await import('tesseract.js');local=await createWorker('eng',1,{workerPath:'/ocr/worker.min.js',corePath:'/ocr',langPath:'/ocr',gzip:false,logger:m=>{if(alive.current&&run.current===id&&m.status==='recognizing text')T('Lecture de la zone cadrée… '+Math.round(m.progress*100)+' %')}});
   if(run.current!==id){await local.terminate();return []}worker.current=local;await local.setParameters({tessedit_char_whitelist:'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- ',tessedit_pageseg_mode:PSM.SINGLE_LINE,user_defined_dpi:'300'});
   const found=new Map<string,{plate:string,corrected:boolean}>();for(let pass=0;pass<4&&run.current===id;pass++){const image=ocrCanvas128(source,pass);try{const r=await local.recognize(image);for(const p of plateOptions128(r.data.text)){const previous=found.get(p.plate);if(!previous||!p.corrected)found.set(p.plate,p)}}finally{image.width=0;image.height=0}if(pass>=1&&found.size)break}
   return [...found.values()].slice(0,6)};
   const found=await Promise.race([operation(),new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(Error('Lecture trop longue. Réessaie en rapprochant la plaque ou saisis-la à la main.')),60000)})]);
   if(!alive.current||run.current!==id)return;P(found);T(found.length?'Vérifie la photo puis touche la bonne immatriculation pour remplir le formulaire.':'Aucune plaque complète reconnue. Réessaie bien de face ou saisis-la à la main.');
  }catch(e:any){if(alive.current&&run.current===id)T(e.message?.includes('Lecture trop longue')?e.message:'Lecture impossible. Réessaie avec une photo nette ou saisis la plaque à la main.')}
  finally{clearTimeout(timer);source.width=0;source.height=0;if(local)void(local as Worker).terminate();if(worker.current===local)worker.current=null;if(alive.current&&run.current===id){run.current++;S(false);onBusy(false)}}
 }
 return <div className="plate-scanner"><button type="button" className="secondary" disabled={disabled||scanning||open} onClick={()=>{if(current&&!confirm('Remplacer la plaque saisie après vérification de la lecture ?'))return;O(true);onBusy(true)}}><Camera size={18}/> Scanner la plaque</button>{open&&<PlateCapture128 onClose={()=>{O(false);onBusy(false)}} onCapture={c=>void scan(c)}/>} {scanning&&<button type="button" className="secondary" onClick={cancel}>Annuler la lecture</button>}<p className="muted">Cadre la plaque entière, bien droite et sans reflet. Lecture locale des plaques AA-123-BB ; tous les formats restent saisissables à la main.</p>{preview&&<img className="plate-scanner-preview128" src={preview} alt="Zone de plaque utilisée pour la lecture"/>}{status&&<p role="status">{status}</p>}<div className="plate-scanner-options128">{options.map(p=><button type="button" className="secondary" key={p.plate} disabled={disabled||scanning} onClick={()=>{onResult(p.plate);P([]);T('Plaque renseignée. Vérifie-la avant d’enregistrer le signalement.')}}>{p.plate}{p.corrected&&<small>Lecture incertaine · chiffres à vérifier</small>}</button>)}</div></div>;
}
