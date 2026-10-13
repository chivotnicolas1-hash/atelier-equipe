-- D'abord : déployer workshop-push et créer dans Vault le secret
-- workshop_push_cron_secret, identique à PUSH_CRON_SECRET de la fonction.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
do $$begin
 if not exists(select 1 from vault.decrypted_secrets where name='workshop_push_cron_secret' and length(decrypted_secret)>=32) then
 raise exception 'Crée d’abord le secret workshop_push_cron_secret dans Vault (32 caractères minimum).';end if;
end $$;
select cron.schedule('atelier-notifications','* * * * *',$job$
 select net.http_post(
 url:='https://ifzdtnysccmcjfpnqyze.supabase.co/functions/v1/workshop-push',
 headers:=jsonb_build_object('Content-Type','application/json','x-workshop-secret',(select decrypted_secret from vault.decrypted_secrets where name='workshop_push_cron_secret' limit 1)),
 body:='{}'::jsonb,timeout_milliseconds:=120000
 );
$job$);
