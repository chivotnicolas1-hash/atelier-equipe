import type {Slot} from './schedule';
export function weekSummary90(days:{presence:string,slots:Slot[]}[]){
 let minutes=0,workedDays=0;
 for(const day of days){
  if(day.presence!=='present')continue;
  const slots=day.slots.flatMap(s=>{const parse=(v:string)=>{const m=/^(\d{2}):(\d{2})/.exec(v);return m?Number(m[1])*60+Number(m[2]):NaN};const start=parse(s.start),end=parse(s.end);return Number.isFinite(start)&&end>start?[{start,end}]:[]}).sort((a,b)=>a.start-b.start);
  if(!slots.length)continue;workedDays++;let start=slots[0].start,end=slots[0].end;
  for(const s of slots.slice(1)){if(s.start<=end)end=Math.max(end,s.end);else{minutes+=end-start;start=s.start;end=s.end}}minutes+=end-start;
 }
 return {minutes,workedDays,s4j:workedDays>0&&workedDays<5,label:Math.floor(minutes/60)+' h'+(minutes%60?' '+String(minutes%60).padStart(2,'0'):'')};
}
