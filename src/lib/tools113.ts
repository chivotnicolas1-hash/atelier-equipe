import {supabase} from './supabase';
export const toolStatuses={pending:'En attente',accepted:'Acceptée',refused:'Refusée',ordered:'Commandée',received:'Réceptionnée'};
export const toolPriorities={normal:'Normal',important:'Important',urgent:'Urgent'};
export type ToolPole={id:string,name:string,active:boolean,position:number,version:number};
export type ToolRequest={id:string,author_id:string,author_name:string,title:string,pole_id:string,pole_name:string,quantity:number,unit_price:number|null,product_url:string,comment:string,priority:keyof typeof toolPriorities,status:keyof typeof toolStatuses,refusal_reason:string,actual_unit_price:number|null,purchase_date:string|null,created_at:string,updated_at:string,deleted_at:string|null,version:number,has_photo?:boolean};
export type ToolEvent={id:number,actor_name:string,at:string,action:string,before_data:Record<string,unknown>|null,after_data:Record<string,unknown>|null};
export type ToolDetail={request:ToolRequest,photo:string|null,events:ToolEvent[]};
export type ToolMeta={admin:boolean,can_create:boolean,pending:number,poles:ToolPole[],authors:{id:string,name:string}[]};
export const emptyToolMeta:ToolMeta={admin:false,can_create:false,pending:0,poles:[],authors:[]};
export const toolMoney=(n:number|null|undefined)=>n==null?'Non renseigné':new Intl.NumberFormat('fr-FR',{style:'currency',currency:'EUR'}).format(n);
export const toolWhen=(s:string)=>new Date(s).toLocaleString('fr-FR',{timeZone:'Europe/Paris',dateStyle:'short',timeStyle:'short'});
export const toolTotal=(price:number|null,quantity:number)=>price===null?null:Math.round(price*quantity*100)/100;
export async function toolRpc<T=any>(name:string,args:Record<string,unknown>={}):Promise<T>{
 const abort=new AbortController();let timer:ReturnType<typeof setTimeout>|undefined;
 try{const result=await Promise.race([supabase.rpc(name,args).abortSignal(abort.signal),new Promise<never>((_,reject)=>{timer=setTimeout(()=>{abort.abort();reject(Error('La réponse n’a pas été confirmée en 30 secondes. Vérifie la demande avant de réessayer.'))},30000)})]);
  if(result.error)throw Error(result.error.code==='PGRST202'?'Installe le script SQL 113 dans Supabase avant d’utiliser les demandes d’outillage.':result.error.message);return result.data as T;
 }finally{if(timer)clearTimeout(timer)}
}
