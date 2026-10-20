export function canAssign(station:{office:boolean},person:{team?:string|null,role?:string},day:{presence:string,slots?:{start:string,end:string}[]}){
 return person.role!=='guest'&&day.presence==='present'&&(station.office?person.team?.trim().toLocaleLowerCase('fr')==='encadrants':!!day.slots?.length);
}
