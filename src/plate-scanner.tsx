import {useEffect,useRef,useState} from 'react';
import {Camera} from 'lucide-react';
import type {Worker} from 'tesseract.js';
import {plateCandidates} from './lib/plate-reader';
export default function PlateScanner({disabled,current,onResult,onBusy}:{disabled:boolean,current:string,onResult:(plate:string)=>void,onBusy:(busy:boolean)=>void}){
 const input=useRef<HTMLInputElement>(null),worker=useRef<Worker|null>(null),run=useRef(0),alive=useRef(true);
 const [scanning,setScanning]=useState(false),[status,setStatus]=useState(''),[candidates,setCandidates]=useState<string[]>([]);
 useEffect(()=>{alive.current=true;return()=>{alive.current=false;run.current++;void worker.current?.terminate();worker.current=null}},[]);
 function cancel(){run.current++;void worker.current?.terminate();worker.current=null;setScanning(false);onBusy(false);setStatus('Lecture annulée. Tu peux saisir la plaque à la main.');}
 async function scan(file:File){
  if(file.size>15*1024*1024){setStatus('Photo trop volumineuse (15 Mo maximum). Rapproche-toi de la plaque ou saisis-la à la main.');return}
  if(current&&!confirm('Remplacer la plaque saisie si une plaque est reconnue sur la photo ?'))return;
  const id=++run.current;setScanning(true);onBusy(true);setStatus('Chargement du lecteur…');setCandidates([]);let timer:ReturnType<typeof setTimeout>|undefined;let localWorker:Worker|null=null;
  try{
   const operation=async()=>{
    const bitmap=await createImageBitmap(file);const canvas=document.createElement('canvas');
    try{const scale=Math.min(1,2000/Math.max(bitmap.width,bitmap.height));canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));const ctx=canvas.getContext('2d');if(!ctx)throw Error('Lecture de photo indisponible.');ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height)}finally{bitmap.close()}
    if(run.current!==id)return [];
    const {createWorker,PSM}=await import('tesseract.js');
    localWorker=await createWorker('eng',1,{workerPath:'/ocr/worker.min.js',corePath:'/ocr',langPath:'/ocr',gzip:false,logger:m=>{if(alive.current&&run.current===id)setStatus(m.status==='recognizing text'?`Lecture de la plaque… ${Math.round(m.progress*100)} %`:'Chargement du lecteur…')}});
    if(run.current!==id){await localWorker.terminate();return []}worker.current=localWorker;
    await localWorker.setParameters({tessedit_char_whitelist:'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- ',tessedit_pageseg_mode:PSM.SINGLE_LINE});
    let result=await localWorker.recognize(canvas);let plates=plateCandidates(result.data.text);
    if(!plates.length&&run.current===id){await localWorker.setParameters({tessedit_pageseg_mode:PSM.SPARSE_TEXT});result=await localWorker.recognize(canvas);plates=plateCandidates(result.data.text)}
    return plates;
   };
   const found=await Promise.race([operation(),new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(Error('Lecture trop longue. Réessaie avec une photo nette et rapprochée, ou saisis la plaque à la main.')),45000)})]);
   if(!alive.current||run.current!==id)return;
   if(found.length===1){onResult(found[0]);setStatus('Plaque renseignée. Vérifie les lettres et les chiffres avant d’enregistrer.')}else if(found.length>1){setCandidates(found);setStatus('Plusieurs plaques possibles : choisis celle du véhicule.')}else setStatus('Plaque non reconnue. Réessaie en cadrant uniquement la plaque ou saisis-la à la main.');
  }catch(e:any){if(alive.current&&run.current===id)setStatus(e.message?.includes('Lecture trop longue')?e.message:'Lecture impossible. Réessaie avec une photo JPEG/PNG nette, ou saisis la plaque à la main.');}
  finally{clearTimeout(timer);if(alive.current&&run.current===id){run.current++;setScanning(false);onBusy(false);void worker.current?.terminate();worker.current=null}else if(localWorker)void (localWorker as Worker).terminate();}
 }
 return <div className="plate-scanner"><button type="button" className="secondary" disabled={disabled||scanning} onClick={()=>input.current?.click()}><Camera size={18}/> Scanner la plaque</button><input ref={input} type="file" accept="image/*" capture="environment" hidden disabled={disabled||scanning} onChange={e=>{const file=e.target.files?.[0];e.target.value='';if(file)void scan(file)}}/>{scanning&&<button type="button" className="secondary" onClick={cancel}>Annuler la lecture</button>}<p className="muted">Cadre la plaque de près, bien droite et sans reflet. Lecture des plaques françaises AA-123-BB. La saisie manuelle reste possible pour tous les formats. La photo de lecture n’est pas ajoutée au signalement.</p>{status&&<p role="status">{status}</p>}{candidates.map(p=><button type="button" className="secondary" key={p} onClick={()=>{onResult(p);setCandidates([]);setStatus('Plaque renseignée : vérifie-la avant de valider.')}}>{p}</button>)}</div>
}
