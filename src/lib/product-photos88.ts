import {useSyncExternalStore} from 'react';
type Product={id:string,name:string,photo?:string,kind?:string,pack?:string};
const sections=new Map<string,Product[]>(),listeners=new Set<()=>void>();let revision=0;
export function publishPhotos88(section:string,items:Product[]){sections.set(section,items);revision++;listeners.forEach(fn=>fn())}
const subscribe=(fn:()=>void)=>{listeners.add(fn);return()=>{listeners.delete(fn)}};
const normalize=(s:string)=>s.trim().replace(/\s+/g,' ').toLocaleLowerCase('fr');
export function useProductPhoto88(){useSyncExternalStore(subscribe,()=>revision);return (item:{id?:string,label:string})=>{
 const all=[...sections.values()].flat();const byId=item.id?all.filter(p=>p.id===item.id):[];
 if(byId.length===1)return byId[0].photo||'';
 const matches=all.filter(p=>normalize(p.name+(p.pack?' ('+p.pack+')':''))===normalize(item.label)||(p.kind==='tank'&&normalize(item.label).startsWith(normalize(p.name)+' — livraison en cuve de ')));
 return matches.length===1?matches[0].photo||'':'';
}}
