// Simulation en mémoire uniquement : aucune écriture Supabase.
export const demoSlots=()=>[{start:'08:00',end:'12:00'},{start:'13:00',end:'17:00'}];
export function guestDemoDay(staffId:string,date:string,stationIds:string[],seed:number){
 const choices=stationIds.filter(id=>!['organisation','devis'].includes(id));
 return {staff_id:staffId,presence:'present',station:choices.length?choices[seed%choices.length]:null,confirmed:date+'T08:00:00Z',geometry:false,slots:demoSlots(),demo:true};
}
export function guestDemoWeek(date:string,staffId:string){
 const start=new Date(date+'T12:00:00Z');start.setUTCDate(start.getUTCDate()-(start.getUTCDay()+6)%7);
 return {start:start.toISOString().slice(0,10),staff_id:staffId,can_delete:false,days:Array.from({length:7},(_,i)=>{const d=new Date(start);d.setUTCDate(d.getUTCDate()+i);return {date:d.toISOString().slice(0,10),presence:'present',slots:demoSlots()}})};
}
