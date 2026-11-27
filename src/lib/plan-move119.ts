import {canAssign,type Skill} from './assignment-choice';
export type PlanMove119={staffId:string,from:string|null,to:string};
export function moveReason119(move:PlanMove119,person:{id:string,role?:string,team?:string|null}|undefined,day:{station:string|null,presence:string,slots?:{start:string,end:string}[],geometry?:boolean}|undefined,station:{id:string,office:boolean}|undefined,skills:Skill[],status?:string,allowUnassigned=false){
 if(!person||!day||!station)return 'Poste ou collaborateur indisponible.';
 if(person.role==='guest'||person.role==='director')return 'Ce compte ne peut pas être déplacé.';
 if(move.from===null&&(!allowUnassigned||day.station!==null||day.geometry))return 'Utilise la zone Non affectés du brouillon pour une première affectation.';
 if(day.station!==move.from)return 'Déplace la personne depuis son poste principal.';
 if(move.to===move.from)return 'Le collaborateur est déjà sur ce poste.';
 if(!day.slots?.some(s=>s.end>s.start))return 'Aucun horaire prévu pour cette journée.';
 if(status==='broken')return 'Ce pont est en panne : affectation impossible.';
 if(!canAssign(station,person,day,skills))return 'Destination incompatible : vérifie les compétences, la présence et l’équipe.';
 return null;
}
