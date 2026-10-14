import {createClient} from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
Deno.serve(async req=>{
 const secret=Deno.env.get('PUSH_CRON_SECRET');
 if(req.method!=='POST'||!secret||req.headers.get('x-workshop-secret')!==secret)return new Response('Unauthorized',{status:401});
 const publicKey=Deno.env.get('VAPID_PUBLIC_KEY'),privateKey=Deno.env.get('VAPID_PRIVATE_KEY');
 if(!publicKey||!privateKey)return new Response('Missing push configuration',{status:503});
 webpush.setVapidDetails('mailto:nchivot@norauto.fr',publicKey,privateKey);
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
 const {data,error}=await db.rpc('workshop_push_claim');
 if(error)return new Response('Queue unavailable',{status:500});
 let sent=0,failed=0;
 for(let i=0;i<data.length;i+=5)await Promise.all(data.slice(i,i+5).map(async(q:any)=>{
  try{
   const url=q.kind==='message'?q.url:q.kind==='task'?'/?notifications=tasks':'/';
   await webpush.sendNotification({endpoint:q.endpoint,keys:{p256dh:q.p256dh,auth:q.auth}},JSON.stringify({title:'Atelier Fayet 33',body:q.kind==='message'?q.body:q.kind==='task'?'Une tâche vous a été attribuée ou mise à jour.':'Une annonce a été publiée pour toute l’équipe.',url,tag:q.id}),{TTL:86400,timeout:10000});
   const {error:ack}=await db.from('workshop_push_queue').update({sent_at:new Date().toISOString(),last_error:null}).eq('id',q.id);if(ack)throw ack;sent++;
  }catch(e:any){
   failed++;const status=Number(e?.statusCode)||0;
   if(status===404||status===410)await db.from('workshop_push_subscriptions').delete().eq('id',q.subscription_id);
   else await db.from('workshop_push_queue').update({last_error:status?`Push HTTP ${status}`:'Échec temporaire',next_at:new Date(Date.now()+Math.min(60,2**q.attempts)*60000).toISOString()}).eq('id',q.id);
  }
 }));
 return Response.json({sent,failed});
});
