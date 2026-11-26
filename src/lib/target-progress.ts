import {targetLabels,type DailyTargets} from './daily-targets-parser';
export function targetProgress(targets:DailyTargets|null|undefined,totals:Partial<Record<keyof typeof targetLabels,number>>|undefined,customKeys?:string[]){
 const keys=(customKeys||Object.keys(targetLabels)) as (keyof typeof targetLabels)[];
 const positive=(n:unknown)=>Number.isFinite(Number(n))?Math.max(0,Number(n)):0;
 const realized=keys.reduce((n,k)=>n+positive(totals?.[k]),0);
 const known=(n:unknown)=>n!==null&&n!==undefined&&n!==''&&Number.isFinite(Number(n))&&Number(n)>=0;
 const goal=targets&&keys.every(k=>known(targets[k]))?keys.reduce((n,k)=>n+positive(targets[k]),0):null;
 const credited=targets?keys.reduce((n,k)=>n+Math.min(positive(totals?.[k]),positive(targets[k])),0):0;
 const allReached=!!targets&&!!goal&&keys.every(k=>positive(totals?.[k])>=positive(targets[k]));
 // Une survente ne compense pas une autre cible. Évite aussi l'arrondi 99,99 -> 100.
 const percent=goal!=null&&goal>0?(allReached?100:Math.min(99.9,credited*100/goal)):null;
 return {realized,goal,credited,allReached,percent};
}
