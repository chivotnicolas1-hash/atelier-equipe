import {createContext,useContext,useEffect,useState} from 'react';
import {supabase} from './lib/supabase';
import {stations as defaults} from './lib/workshop';
export type Palette={background:string,surface:string,text:string,primary:string,header:string};
export type Design={appName:string,subtitle:string,loginTitle:string,loginDescription:string,loginNote:string,signature:string,light:Palette,dark:Palette,fontSize:number,radius:number,spacing:number,stations:Record<string,{name:string,number:string}>};
export const baseDesign:Design={appName:'ATELIER FAYET 33',subtitle:'ÉQUIPE & ORGANISATION',loginTitle:'Ta journée commence ici.',loginDescription:'Retrouve ton poste, confirme ta présence et consulte les tâches qui te sont confiées.',loginNote:'Utilise les identifiants transmis par ton administrateur. Pour obtenir un accès ou réinitialiser ton mot de passe, contacte-le.',signature:'Par Nicolas CHIVOT',light:{background:'#f3f8fe',surface:'#ffffff',text:'#244460',primary:'#0866b6',header:'#142b43'},dark:{background:'#101f30',surface:'#192f46',text:'#e2edf8',primary:'#237dc7',header:'#142b43'},fontSize:16,radius:12,spacing:20,stations:{}};
export function mergeDesign(d:Partial<Design>):Design{return {...baseDesign,...d,light:{...baseDesign.light,...d.light},dark:{...baseDesign.dark,...d.dark},stations:d.stations||{}}}
const Context=createContext({design:baseDesign,revision:0,refresh:async()=>{}});
export const useDesign=()=>useContext(Context);
export function useStations(){const {design}=useDesign();return defaults.map((s,i)=>({...s,name:design.stations[s.id]?.name||s.name,short:design.stations[s.id]?.name||s.short,number:design.stations[s.id]?.number||String(i+1).padStart(2,'0')}))}
export function DesignProvider({children}:{children:React.ReactNode}){const [design,setDesign]=useState(baseDesign),[revision,setRevision]=useState(0);
 async function refresh(){const {data,error}=await supabase.rpc('workshop_get_design');if(!error&&data?.settings){setDesign(mergeDesign(data.settings));setRevision(data.revision)}}
 useEffect(()=>{void refresh();const id=setInterval(()=>void refresh(),60000);return()=>clearInterval(id)},[]);
 useEffect(()=>{const el=document.documentElement;for(const mode of ['light','dark'] as const)for(const [key,value] of Object.entries(design[mode]))el.style.setProperty('--design-'+mode+'-'+key,value);for(const key of ['fontSize','radius','spacing'] as const)el.style.setProperty('--design-'+key,design[key]+'px');document.title=design.appName},[design]);
 return <Context.Provider value={{design,revision,refresh}}>{children}</Context.Provider>;
}
