/** Invalide les lectures lancées avant une ouverture d’éditeur ou une écriture. */
export function catalogReads105(){
 let generation=0,active=true;
 return {start:()=>++generation, invalidate:()=>{++generation}, accepts:(ticket:number)=>active&&ticket===generation, close:()=>{active=false;++generation}, reopen:()=>{active=true}};
}
