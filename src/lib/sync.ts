import {useEffect,useRef} from 'react';
// Une horloge commune : toutes les vues chargées reçoivent le même signal.
const listeners=new Map<number,()=>unknown>();let next=-1;
function tick(){for(const fn of listeners.values()){try{const r=fn();if(r instanceof Promise)void r.catch(()=>{})}catch{}}}
window.setInterval(tick,20000);
window.addEventListener('focus',tick);
window.addEventListener('online',tick);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)tick()});
export function setSyncInterval(fn:()=>unknown,ms=20000):number{if(ms<=1000)return window.setInterval(fn,ms);const id=next--;listeners.set(id,fn);return id}
export function clearSyncInterval(id:number){if(id<0)listeners.delete(id);else window.clearInterval(id)}
export function useAutoRefresh(fn:()=>unknown,enabled=true){const current=useRef(fn),allowed=useRef(enabled),running=useRef(false);current.current=fn;allowed.current=enabled;useEffect(()=>{const id=setSyncInterval(async()=>{if(!allowed.current||running.current)return;running.current=true;try{await current.current()}finally{running.current=false}});return()=>clearSyncInterval(id)},[])}
