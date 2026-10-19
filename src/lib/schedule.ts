export type Slot={start:string,end:string};
export function parisClock(now=new Date()){
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(now);
 const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));
 return {date:`${p.year}-${p.month}-${p.day}`,time:`${p.hour}:${p.minute}`};
}
// Une coupure à la mi-journée est déduite des créneaux, pas d'un pointage.
export function lunchBreaks(slots:Slot[]=[]){
 const sorted=[...slots].sort((a,b)=>a.start.localeCompare(b.start));
 return sorted.slice(0,-1).flatMap((s,i)=>{
 const next=sorted[i+1];return s.end>= '11:00'&&s.end<'15:00'&&next.start<='16:00'&&s.end<next.start?[{start:s.end,end:next.start}]:[];
 });
}
export function lunchInfo(day:{presence:string,slots?:Slot[]}|null|undefined,date:string,now=new Date()){
 const breaks=day?.presence==='present'?lunchBreaks(day.slots):[];
 const clock=parisClock(now);const current=date===clock.date?breaks.find(b=>clock.time>=b.start&&clock.time<b.end):undefined;
 return {breaks,current};
}
