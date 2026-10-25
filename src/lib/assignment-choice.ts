export type Skill={staff_id:string,station_id:string,level:string};
export function canAssign(station:{id:string,office:boolean},person:{id:string,team?:string|null,role?:string},day:{presence:string,slots?:{start:string,end:string}[]},skills:Skill[]=[]){
 const manager=person.team?.trim().toLocaleLowerCase('fr')==='encadrants';
 return person.role!=='guest'&&day.presence==='present'&&station.office===manager&&(station.office||!!day.slots?.length)&&skills.some(k=>k.staff_id===person.id&&k.station_id===station.id&&k.level==='autonomous');
}
