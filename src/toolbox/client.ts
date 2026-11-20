import type {Card,ToolId} from './model';
export type SyncData={revision:number,self_id?:string,unchanged?:boolean,tools:Partial<Record<ToolId,boolean>>,categories:string[],cards:Card[],hidden:string[],pending:number,admin:boolean,can_write:boolean};
// Import différé : le point d’entrée hors connexion n’initialise jamais Auth.
export async function tbRpc<T=any>(name:string,args:Record<string,unknown>={}):Promise<T>{const{toolRpc}=await import('../lib/tools113');return toolRpc<T>(name,args)}
export async function prepareToolboxOffline(onProgress:(s:string)=>void){
 if(!('serviceWorker'in navigator))throw Error('Le navigateur ne permet pas le stockage hors connexion.');
 await navigator.serviceWorker.register('/sw.js');const reg=await navigator.serviceWorker.ready;const worker=reg.active;if(!worker)throw Error('Ferme puis rouvre l’application avant de réessayer.');
 return new Promise<void>((resolve,reject)=>{const id=crypto.randomUUID(),channel=new MessageChannel();const timer=setTimeout(()=>{channel.port1.close();reject(Error('Téléchargement non confirmé. Reste connecté puis réessaie.'))},180000);channel.port1.onmessage=e=>{if(e.data.id!==id)return;if(e.data.error){clearTimeout(timer);channel.port1.close();reject(Error(e.data.error))}else if(e.data.done){clearTimeout(timer);channel.port1.close();resolve()}else onProgress('Préparation hors connexion · '+e.data.loaded+' / '+e.data.total)};worker.postMessage({type:'TOOLBOX_PREPARE114',id},[channel.port2])})
}
