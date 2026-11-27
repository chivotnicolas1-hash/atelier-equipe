import {hasSchedule121} from './presence121';
type Person127={id:string,name:string,photo?:string|null,role?:string,active?:boolean,suspended?:boolean};
type Day127={staff_id:string,presence:string,station:string|null,geometry?:boolean,slots?:{start:string,end:string}[]};
export function unassignedPeople127<S extends Person127,D extends Day127>(staff:S[],days:D[]){
 const byDay=new Map(days.map(d=>[d.staff_id,d]));
 const unique=new Map(staff.map(p=>[p.id,p]));
 return [...unique.values()].flatMap(person=>{const day=byDay.get(person.id);return person.active!==false&&!person.suspended&&person.role!=='guest'&&person.role!=='director'&&day&&day.presence==='present'&&!day.station&&!day.geometry&&hasSchedule121(day)?[{person,day}]:[]}).sort((a,b)=>a.person.name.localeCompare(b.person.name,'fr',{sensitivity:'base',numeric:true})||a.person.id.localeCompare(b.person.id));
}
export function unassignedPlacement127(stations:{col:number,row:number,office:boolean}[],count:number){
 if(count<1)return null;
 const offices=stations.filter(s=>s.office),anchor=offices.length?offices:stations;
 const row=offices.length?Math.min(...offices.map(s=>s.row)):1;
 const span=offices.length?Math.max(2,Math.max(...offices.map(s=>s.row))-row+1):2;
 let col=Math.max(0,...anchor.map(s=>s.col))+1;
 while(stations.some(s=>s.col===col&&s.row>=row&&s.row<row+span))col++;
 return {col,row,span};
}
