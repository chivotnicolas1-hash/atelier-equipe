import {supabase} from './supabase';
export const networkFailure88=(e:unknown)=>/failed to fetch|fetch failed|networkerror|load failed|network request failed/i.test(String((e as any)?.message||e));
// Lecture uniquement : ne jamais réessayer automatiquement une écriture.
export async function readConsumables88(name:string,args?:Record<string,unknown>){
 for(let attempt=0;;attempt++){
  try{const r=await supabase.rpc(name,args);if(r.error)throw r.error;return r.data}
  catch(e){if(attempt||!networkFailure88(e)||!navigator.onLine)throw e;await new Promise(r=>setTimeout(r,700))}
 }
}
