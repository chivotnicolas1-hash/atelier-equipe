import {canAssign,type Skill} from './assignment-choice';
export type PlanMove119={staffId:string,from:string,to:string};
export function moveReason119(move:PlanMove119,person:{id:string,role?:string,team?:string|null}|undefined,day:{station:string|null,presence:string,slots?:{start:string,end:string}[]}|undefined,station:{id:string,office:boolean}|undefined,skills:Skill[],status?:string){
 if(!person||!day||!station)return 'Poste ou collaborateur indisponible.';
 if(person.role==='guest'||person.role==='director')return 'Ce compte ne peut pas être déplacé.';
 if(day.station!==move.from)return 'Déplace la personne depuis son poste principal.';
 if(move.to===move.from)return 'Le collaborateur est déjà sur ce poste.';
 if(!day.slots?.some(s=>s.end>s.start))return 'Aucun horaire prévu pour cette journée.';
 if(status==='broken')return 'Ce pont est en panne : affectation impossible.';
 if(!canAssign(station,person,day,skills))return 'Destination incompatible : vérifie les compétences, la présence et l’équipe.';
 return null;
}
