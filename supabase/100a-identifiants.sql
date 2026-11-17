begin;
create table if not exists workshop_private.accounts100(staff_id text primary key references public.workshop_staff(id) on delete cascade,user_id uuid unique,alias text not null unique,is_admin boolean not null default false,anonymized_at timestamptz);
alter table workshop_private.accounts100 enable row level security;
revoke all on workshop_private.accounts100 from public,anon,authenticated;
insert into workshop_private.accounts100(staff_id,user_id,alias,is_admin)
 select s.id,u.id,replace(gen_random_uuid()::text,'-','')||'@atelier.invalid',lower(s.email)='nchivot@norauto.fr'
 from public.workshop_staff s left join auth.users u on lower(u.email)=lower(s.email) on conflict(staff_id) do nothing;
do $$ begin if not exists(select 1 from workshop_private.accounts100 where is_admin and user_id is not null) then raise exception 'Compte administrateur non identifié. Aucun changement appliqué.';end if;end $$;
-- Les anciennes valeurs de matricule sont effacées ; nouvelle table d'ID uniquement.
do $$ begin if to_regclass('public.workshop_custom_logins100') is null then
 alter table public.workshop_staff_logins rename to workshop_custom_logins100;
 alter table public.workshop_custom_logins100 rename column matricule to login_id;
 delete from public.workshop_custom_logins100 where true;
 delete from public.workshop_login_limits where true;
 end if;end $$;
insert into public.workshop_custom_logins100(staff_id,login_id)
 select staff_id,case when is_admin then 'ATELIER-ADMIN' else 'AF33-'||upper(substr(md5(staff_id),1,12)) end from workshop_private.accounts100 on conflict(staff_id) do nothing;
create or replace function workshop_private.admin_email100() returns text language sql volatile security definer set search_path='' as $$select s.email from public.workshop_staff s join workshop_private.accounts100 a on a.staff_id=s.id where a.is_admin limit 1$$;
revoke all on function workshop_private.admin_email100() from public,anon,authenticated;
-- Adapter les dépendances existantes sans modifier les règles de rôle.
do $patch$ declare r record;d text;n text;begin
 for r in select p.oid from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname in ('public','workshop_private') and p.prokind='f' loop
 d:=pg_get_functiondef(r.oid);n:=replace(replace(replace(replace(d,'public.workshop_staff_logins','public.workshop_custom_logins100'),'.matricule','.login_id'),'''matricule''','''login_id'''),'''nchivot@norauto.fr''','workshop_private.admin_email100()');
 if n<>d then execute n;end if;end loop;
end $patch$;
create or replace function workshop_private.actor_before36() returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.workshop_staff%rowtype;adm boolean;uid uuid:=auth.uid();begin
 if uid is null then raise exception 'Connexion requise.' using errcode='42501';end if;
 if coalesce(auth.jwt()->'app_metadata'->>'provider','')<>'email' or not exists(select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]')) m where m->>'method'='password') then raise exception 'Connecte-toi avec ton ID et ton mot de passe.' using errcode='42501';end if;
 if not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Compte de connexion non valide.' using errcode='42501';end if;
 select st.* into s from public.workshop_staff st join workshop_private.accounts100 a on a.staff_id=st.id where a.user_id=uid and st.active;
 select is_admin into adm from workshop_private.accounts100 where user_id=uid;
 if s.id is null then raise exception 'Compte suspendu ou accès non autorisé.' using errcode='42501';end if;
 return jsonb_build_object('admin',adm,'role',case when adm then 'admin' else coalesce(s.role,'employee') end,'manager',adm or s.role='moderator','can_manage_schedule',adm or (s.role='moderator' and s.can_manage_schedule),'reports_all',adm or s.role='moderator','self',s.id,'user',s.email);
end $$;
create or replace function public.workshop_login100(p_login text) returns jsonb language plpgsql security definer set search_path='' as $$
declare m text:=upper(btrim(p_login));e text;n int;k text;begin
 if m is null or m !~ '^[A-Z0-9_-]{3,32}$' then return '{}'::jsonb;end if;
 k:=md5('id100:'||m);perform pg_advisory_xact_lock(hashtextextended(k,0));
 delete from public.workshop_login_limits where started_at<now()-interval '1 day';
 insert into public.workshop_login_limits values(k,now(),1) on conflict(key) do update set attempts=case when workshop_login_limits.started_at<now()-interval '15 minutes' then 1 else workshop_login_limits.attempts+1 end,started_at=case when workshop_login_limits.started_at<now()-interval '15 minutes' then now() else workshop_login_limits.started_at end returning attempts into n;
 if n>10 then return jsonb_build_object('limited',true);end if;
 select u.email into e from public.workshop_custom_logins100 l join public.workshop_staff s on s.id=l.staff_id join workshop_private.accounts100 a on a.staff_id=s.id join auth.users u on u.id=a.user_id where l.login_id=m and s.active and u.email_confirmed_at is not null;
 return jsonb_build_object('email',e);
end $$;
revoke all on function public.workshop_login100(text) from public,anon,authenticated;grant execute on function public.workshop_login100(text) to service_role;
-- L'ancien point d'entrée par matricule ne doit plus être utilisable.
drop function if exists public.workshop_login_lookup(text);
create or replace function public.workshop_accounts100() returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('staff_id',s.id,'name',s.name,'login_id',l.login_id,'anonymized',a.anonymized_at is not null,'has_account',a.user_id is not null) order by s.name),'[]') from public.workshop_staff s join workshop_private.accounts100 a on a.staff_id=s.id left join public.workshop_custom_logins100 l on l.staff_id=s.id);end $$;
revoke all on function public.workshop_accounts100() from public,anon;grant execute on function public.workshop_accounts100() to authenticated;
create or replace function public.workshop_account_target100(p_staff text) returns jsonb language sql security definer set search_path='' as $$select jsonb_build_object('user_id',a.user_id,'alias',a.alias,'old_email',s.email,'is_admin',a.is_admin) from workshop_private.accounts100 a join public.workshop_staff s on s.id=a.staff_id where a.staff_id=p_staff$$;
revoke all on function public.workshop_account_target100(text) from public,anon,authenticated;grant execute on function public.workshop_account_target100(text) to service_role;
create or replace function public.workshop_account_link100(p_staff text,p_user uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from workshop_private.accounts100 a join auth.users u on lower(u.email)=a.alias where a.staff_id=p_staff and u.id=p_user) then raise exception 'Association de compte invalide.';end if;
 update workshop_private.accounts100 set user_id=p_user where staff_id=p_staff and (user_id is null or user_id=p_user);if not found then raise exception 'Compte déjà associé.';end if;end $$;
revoke all on function public.workshop_account_link100(text,uuid) from public,anon,authenticated;grant execute on function public.workshop_account_link100(text,uuid) to service_role;

CREATE OR REPLACE FUNCTION public.workshop_mutate(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;r jsonb;sid text;m text;internal_email text;begin
 if p->>'action' in ('staff','createStaff') then
  a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Action réservée à l’administration.' using errcode='42501';end if;
  if p->>'action'='createStaff' then internal_email:=replace(gen_random_uuid()::text,'-','')||'@atelier.invalid';else select email into internal_email from public.workshop_staff where id=p->>'id';end if;
  p:=p||jsonb_build_object('email',internal_email);
  if not (p ? 'login_id') then select login_id into m from public.workshop_custom_logins100 where staff_id=p->>'id';p:=p||jsonb_build_object('login_id',m);end if;
  if coalesce(upper(btrim(p->>'login_id')),'') !~ '^[A-Z0-9_-]{3,32}$' then raise exception 'ID requis : 3 à 32 lettres, chiffres, tirets ou underscores.';end if;
  lock table public.workshop_staff in share row exclusive mode;m:=nullif(upper(trim(p->>'login_id')),'');
  if p ? 'login_id' and m is not null and (m !~ '^[A-Z0-9_-]{1,32}$' or nullif(trim(p->>'email'),'') is null) then raise exception 'ID invalide ou adresse e-mail manquante.';end if;
  r:=public.workshop_mutate_before62(p);
  if p ? 'login_id' then
   if p->>'action'='staff' then sid:=p->>'id';else select id into sid from public.workshop_staff where email=lower(trim(p->>'email')) and active;end if;
   if m is null then delete from public.workshop_custom_logins100 where staff_id=sid;
   else
    if exists(select 1 from public.workshop_custom_logins100 where login_id=m and staff_id<>sid) then raise exception 'Ce ID est déjà utilisé.';end if;
    insert into public.workshop_custom_logins100 values(sid,m) on conflict(staff_id) do update set login_id=excluded.login_id;
   end if;
  end if;
  insert into workshop_private.accounts100(staff_id,alias) values(sid,internal_email) on conflict(staff_id) do nothing;
  return r;
 end if;return public.workshop_mutate_before62(p);end $function$
;
create or replace function public.workshop_load(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;l text;begin
 perform workshop_private.actor_before30();perform workshop_private.publish_scheduled(now());r:=public.workshop_load_before63(p_date);
 select x.login_id into l from public.workshop_custom_logins100 x join workshop_private.accounts100 a on a.staff_id=x.staff_id where a.user_id=auth.uid();
 r:=r||jsonb_build_object('login_id',l);
 if jsonb_typeof(r->'staff')='array' then r:=jsonb_set(r,'{staff}',(select coalesce(jsonb_agg(st.value||jsonb_build_object('is_admin',coalesce(ac.is_admin,false),'login_id',case when coalesce((r->>'admin')::boolean,false) or ac.user_id=auth.uid() then x.login_id end) order by st.ord),'[]') from jsonb_array_elements(r->'staff') with ordinality st(value,ord) left join workshop_private.accounts100 ac on ac.staff_id=st.value->>'id' left join public.workshop_custom_logins100 x on x.staff_id=st.value->>'id'));end if;
 return r;end $$;
create or replace function public.workshop_request_password100(p_login text) returns void language plpgsql security definer set search_path='' as $$declare e text;begin
 if p_login is null or btrim(p_login) !~* '^[A-Z0-9_-]{3,32}$' then return;end if;
 select s.email into e from public.workshop_staff s join public.workshop_custom_logins100 l on l.staff_id=s.id where s.active and l.login_id=upper(btrim(p_login));
 if e is not null then perform public.workshop_request_password(e);end if;end $$;
revoke all on function public.workshop_request_password(text) from public,anon,authenticated;
revoke all on function public.workshop_request_password100(text) from public;grant execute on function public.workshop_request_password100(text) to anon,authenticated;
create or replace function workshop_private.replace_identity100(value text, old_value text, replacement text) returns text language plpgsql immutable strict set search_path='' as $$
declare rest text:=value;result text:='';pos integer;begin
 if old_value='' then return value;end if;
 loop pos:=strpos(lower(rest),lower(old_value));exit when pos=0;result:=result||left(rest,pos-1)||replacement;rest:=substr(rest,pos+length(old_value));end loop;
 return result||rest;end $$;
revoke all on function workshop_private.replace_identity100(text,text,text) from public,anon,authenticated;
-- Finalisation appelée UNIQUEMENT après le changement d'adresse via l'API Auth.
create or replace function public.workshop_account_finalize100(p_staff text) returns void language plpgsql security definer set search_path='' as $$
declare a workshop_private.accounts100%rowtype;old_address text;c record;login text;begin
 perform 1 from public.workshop_staff where id=p_staff for update;
 select * into a from workshop_private.accounts100 where staff_id=p_staff for update;if not found then raise exception 'Fiche inconnue.';end if;
 if a.user_id is not null and not exists(select 1 from auth.users where id=a.user_id and lower(email)=a.alias) then raise exception 'Migration Auth non terminée.';end if;
 select email into old_address from public.workshop_staff where id=p_staff for update;
 select login_id into login from public.workshop_custom_logins100 where staff_id=p_staff;
 if nullif(old_address,'') is not null and old_address<>a.alias then
 -- Les liens internes par adresse sont conservés sous alias ; les autres traces
 -- textuelles sont remplacées par l'ID personnalisé, sans changer les UUID.
 for c in select table_schema,table_name,column_name,data_type from information_schema.columns where table_schema in ('public','workshop_private') and data_type in ('text','character varying','jsonb','json') and table_name not in ('accounts100') and exists(select 1 from information_schema.tables t where t.table_schema=columns.table_schema and t.table_name=columns.table_name and t.table_type='BASE TABLE') loop
  if c.column_name='email' then execute format('update %I.%I set %I=$1 where lower(%I)=lower($2)',c.table_schema,c.table_name,c.column_name,c.column_name) using a.alias,old_address;
  elsif c.data_type in ('json','jsonb') then execute format('update %I.%I set %I=workshop_private.replace_identity100(%I::text,$1,$2)::%s where strpos(lower(%I::text),lower($1))>0',c.table_schema,c.table_name,c.column_name,c.column_name,c.data_type,c.column_name) using old_address,coalesce(login,'Compte atelier');
  else execute format('update %I.%I set %I=workshop_private.replace_identity100(%I,$1,$2) where strpos(lower(%I),lower($1))>0',c.table_schema,c.table_name,c.column_name,c.column_name,c.column_name) using old_address,coalesce(login,'Compte atelier');end if;
 end loop;
 end if;
 update public.workshop_staff set email=a.alias where id=p_staff and email is distinct from a.alias;
 update workshop_private.accounts100 set anonymized_at=now() where staff_id=p_staff;
end $$;
revoke all on function public.workshop_account_finalize100(text) from public,anon,authenticated;grant execute on function public.workshop_account_finalize100(text) to service_role;
notify pgrst,'reload schema';
commit;
