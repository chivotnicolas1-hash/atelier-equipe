import {supabase} from './supabase';
/** Aucun réessai automatique d’une écriture : après délai, son résultat est incertain. */
export async function saveConsumables104(name:string,args:Record<string,unknown>,timeout=30000){
 const controller=new AbortController();let timer:ReturnType<typeof setTimeout>|undefined;
 try{
  const deadline=new Promise<never>((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(new Error('La sauvegarde n’a pas été confirmée dans les 30 secondes. Elle a peut-être été effectuée. Ferme puis rouvre la fiche pour vérifier avant de réessayer.'))},timeout)});
  const response=await Promise.race([supabase.rpc(name,args).abortSignal(controller.signal),deadline]);
  if(response.error)throw response.error;
  if(!response.data||!Array.isArray(response.data.items))throw new Error('Réponse de sauvegarde inattendue. Ferme puis rouvre le catalogue pour vérifier si la modification a été enregistrée.');
  return response.data;
 }finally{if(timer)clearTimeout(timer)}
}
