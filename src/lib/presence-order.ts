import {parisClock,lunchInfo,type Slot} from './schedule';
type Day={presence:string,slots?:Slot[]};
export function shiftState(day:Day,date:string,now:Date){const clock=parisClock(now);if(date!==clock.date)return 0;
 const slots=[...(day.slots||[])].sort((a,b)=>a.start.localeCompare(b.start));
 if(slots.length&&clock.time>=slots.reduce((end,s)=>s.end>end?s.end:end,''))return 2;
 return lunchInfo(day,date,now).current?1:0;
}
export function presenceOrder(a:{id:string,name:string},b:{id:string,name:string},dayFor:(id:string)=>Day,date:string,now:Date){
 const da=dayFor(a.id),db=dayFor(b.id);const first=(d:Day)=>d.slots?.length?[...d.slots].map(s=>s.start).sort()[0]:'99:99';
 return shiftState(da,date,now)-shiftState(db,date,now)||first(da).localeCompare(first(db))||a.name.localeCompare(b.name,'fr');
}
