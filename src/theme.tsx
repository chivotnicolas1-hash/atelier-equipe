import {useEffect,useState} from 'react';
import {Sun,Moon} from 'lucide-react';
const key='atelier-fayet-theme';
function apply(dark:boolean){document.documentElement.classList.toggle('dark',dark);document.querySelector('meta[name="theme-color"]')?.setAttribute('content','#142b43')}
let initial=false;try{initial=localStorage.getItem(key)==='dark'}catch{}apply(initial);
export function ThemeToggle(){const [dark,setDark]=useState(()=>document.documentElement.classList.contains('dark'));useEffect(()=>{const sync=()=>setDark(document.documentElement.classList.contains('dark'));window.addEventListener('atelier-theme-change',sync);return()=>window.removeEventListener('atelier-theme-change',sync)},[]);return <button className="icon-btn theme-toggle" aria-label={dark?'Passer en mode clair':'Passer en mode sombre'} title={dark?'Mode clair':'Mode sombre'} onClick={()=>{const next=!dark;setDark(next);apply(next);window.dispatchEvent(new Event('atelier-theme-change'));try{localStorage.setItem(key,next?'dark':'light')}catch{}}}>{dark?<Sun size={19}/>:<Moon size={19}/>}</button>}
