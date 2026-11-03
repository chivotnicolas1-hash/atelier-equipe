import {targetLabels,type DailyTargets} from './daily-targets-parser';
export function targetProgress(targets:DailyTargets|null|undefined,totals:Partial<Record<keyof typeof targetLabels,number>>|undefined){
 const keys=Object.keys(targetLabels) as (keyof typeof targetLabels)[];
 const realized=keys.reduce((n,k)=>n+Math.max(0,Number(totals?.[k])||0),0);
 const goal=targets?keys.reduce((n,k)=>n+Math.max(0,Number(targets[k])||0),0):null;
 return {realized,goal,percent:goal!=null&&goal>0?realized*100/goal:null};
}
