-- Mise à jour 10 — appliquer après 09. Compatible avec les données existantes.
begin;
create or replace function workshop_private.valid_link(v text)
returns boolean language sql immutable set search_path='' as $$
 select v is not null and length(v)<=2048 and v ~ '^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?([/?#][^[:space:]<>"\\]*)?$';
$$;
revoke all on function workshop_private.valid_link(text) from public,anon,authenticated;
alter table public.workshop_announcement add column if not exists link_url text;
alter table public.workshop_announcement add column if not exists link_label text;
create table if not exists public.workshop_daily_targets (
 date date primary key,
 amount numeric(12,2) not null check(amount>=0),
 updated_at timestamptz not null default now()
);
create table if not exists public.workshop_custom_buttons (
 id uuid primary key default gen_random_uuid(),
 label text not null check(length(trim(label)) between 1 and 80),
 url text not null,
 audience text not null default 'all' check(audience in ('all','encadrants','management','admin')),
 enabled boolean not null default true,
 position integer not null default 0 check(position between 0 and 99),
 updated_at timestamptz not null default now()
);
alter table public.workshop_daily_targets enable row level security;
alter table public.workshop_custom_buttons enable row level security;
revoke all on public.workshop_daily_targets,public.workshop_custom_buttons from public,anon,authenticated;
create or replace function workshop_private.actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text; v_staff text; v_admin boolean; v_role text;
begin
 if auth.uid() is null then raise exception 'Connexion requise.' using errcode='42501'; end if;
 if coalesce(auth.jwt()->'app_metadata'->>'provider','') <> 'email' or not exists (select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb)) m where m->>'method'='password') then
  raise exception 'Connecte-toi avec les identifiants fournis par ton administrateur.' using errcode='42501';
 end if;
 select lower(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'Une adresse e-mail vérifiée est nécessaire.' using errcode='42501'; end if;
 v_admin := v_email='nchivot@norauto.fr';
 select id,role into v_staff,v_role from public.workshop_staff where email=v_email and active;
 if not v_admin and v_staff is null then
  raise exception 'Cette adresse n’est pas autorisée. Demande à l’administrateur de renseigner ton adresse e-mail dans Équipe.' using errcode='42501';
 end if;
 return jsonb_build_object('admin',v_admin,'role',case when v_admin then 'admin' else coalesce(v_role,'employee') end,'manager',v_admin or coalesce(v_role='moderator',false),'reports_all',v_admin or exists(select 1 from public.workshop_staff where id=v_staff and active and team='Encadrants'),'self',v_staff,'user',v_email);
end $$;
revoke all on function workshop_private.actor() from public, anon, authenticated;


create or replace function public.workshop_load(p_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; v_staff jsonb; v_days jsonb; v_tasks jsonb;
begin
 a:=workshop_private.actor(); v_admin:=(a->>'admin')::boolean;
 if p_date is null then raise exception 'Choisis une date.'; end if;
 select coalesce(jsonb_agg(case when v_admin then to_jsonb(s)||jsonb_build_object('photo',(select p.photo from public.workshop_profiles p join auth.users u on u.id=p.user_id where lower(u.email)=s.email limit 1)) else jsonb_build_object('id',s.id,'name',s.name,'team',s.team) end order by s.id),'[]'::jsonb)
 into v_staff from public.workshop_staff s where s.active;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.staff_id),'[]'::jsonb) into v_days
 from public.workshop_days d where d.date=p_date and exists(select 1 from public.workshop_staff s where s.id=d.staff_id and s.active);
 select coalesce(jsonb_agg(to_jsonb(t) order by t.done,t.due,t.created_at desc),'[]'::jsonb) into v_tasks
 from public.workshop_tasks t where exists(select 1 from public.workshop_staff s where s.id=t.staff_id and s.active) and ((a->>'manager')::boolean or t.staff_id=a->>'self');
 return a || jsonb_build_object('staff',v_staff,'days',v_days,'tasks',v_tasks,'date',p_date,'profile',jsonb_build_object('photo',(select photo from public.workshop_profiles where user_id=auth.uid())),'announcement',(select jsonb_build_object('message',message,'enabled',enabled,'updated_at',updated_at,'link_url',link_url,'link_label',link_label) from public.workshop_announcement where id=1),
 'today_target',jsonb_build_object('date',(now() at time zone 'Europe/Paris')::date,'amount',(select amount from public.workshop_daily_targets where date=(now() at time zone 'Europe/Paris')::date)),
 'custom_buttons',(select coalesce(jsonb_agg(to_jsonb(b) order by b.position,b.label,b.id),'[]'::jsonb) from public.workshop_custom_buttons b where v_admin or (b.enabled and (b.audience='all' or (b.audience='encadrants' and (a->>'reports_all')::boolean) or (b.audience='management' and (a->>'manager')::boolean)))));
end $$;
revoke all on function public.workshop_load(date) from public, anon, authenticated;
grant execute on function public.workshop_load(date) to authenticated;

drop function if exists public.workshop_list_reports(integer,boolean);
create or replace function public.workshop_list_reports(p_offset integer default 0,p_own boolean default true,p_search text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; v_all boolean; result jsonb; total bigint; q text;
begin
 a:=workshop_private.actor();v_all:=(a->>'reports_all')::boolean and not coalesce(p_own,true);
 if p_search is null or length(p_search)>30 then raise exception 'Recherche limitée à 30 caractères.';end if;
 q:=regexp_replace(upper(p_search),'[^A-Z0-9]','','g');
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 select count(*) into total from public.workshop_reports where (v_all or author_id=auth.uid()) and strpos(regexp_replace(upper(registration),'[^A-Z0-9]','','g'),q)>0;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]'::jsonb) into result from (
  select id,author_name,registration,notes,created_at,(select count(*) from public.workshop_report_photos where report_id=x.id) as photo_count
  from public.workshop_reports x where (v_all or author_id=auth.uid()) and strpos(regexp_replace(upper(registration),'[^A-Z0-9]','','g'),q)>0 order by created_at desc,id desc limit 30 offset p_offset
 ) r;
 return jsonb_build_object('items',result,'total',total);
end $$;
create or replace function public.workshop_get_report(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_reports%rowtype; photos jsonb;
begin
 a:=workshop_private.actor();
 select * into r from public.workshop_reports where id=p_id and ((a->>'reports_all')::boolean or author_id=auth.uid());
 if not found then raise exception 'Signalement introuvable ou non autorisé.' using errcode='42501';end if;
 select coalesce(jsonb_agg(photo order by position),'[]'::jsonb) into photos from public.workshop_report_photos where report_id=p_id;
 return jsonb_build_object('id',r.id,'author_name',r.author_name,'registration',r.registration,'notes',r.notes,'created_at',r.created_at,'photos',photos);
end $$;
revoke all on function public.workshop_list_reports(integer,boolean,text),public.workshop_get_report(uuid) from public,anon,authenticated;
grant execute on function public.workshop_list_reports(integer,boolean,text),public.workshop_get_report(uuid) to authenticated;

drop function if exists public.workshop_save_announcement(text,boolean);
create or replace function public.workshop_save_announcement(p_message text,p_enabled boolean,p_link_url text default null,p_link_label text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; v_url text:=nullif(trim(p_link_url),''); v_label text:=nullif(trim(p_link_label),'');
begin
 a:=workshop_private.actor();
 if (a->>'manager')::boolean is not true then raise exception 'Annonce réservée à l’administration et aux modérateurs.' using errcode='42501';end if;
 if p_message is null or p_enabled is null or length(p_message)>1000 or (p_enabled and length(trim(p_message))=0) then raise exception 'Renseigne un message de 1 à 1000 caractères avant activation.';end if;
 if v_url is not null and (not workshop_private.valid_link(v_url) or v_label is null or length(v_label)>80) then raise exception 'Renseigne un lien HTTP(S) valide et un libellé de 1 à 80 caractères.';end if;
 update public.workshop_announcement set message=trim(p_message),enabled=p_enabled,link_url=v_url,link_label=case when v_url is null then null else v_label end,updated_at=now() where id=1;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_save_announcement(text,boolean,text,text) from public,anon,authenticated;
grant execute on function public.workshop_save_announcement(text,boolean,text,text) to authenticated;

create or replace function public.workshop_save_button(p_id uuid,p_label text,p_url text,p_audience text,p_enabled boolean,p_position integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; v_id uuid;
begin
 a:=workshop_private.actor();
 if (a->>'admin')::boolean is not true then raise exception 'Boutons réservés à l’administration.' using errcode='42501';end if;
 if p_label is null or length(trim(p_label)) not between 1 and 80 or not workshop_private.valid_link(trim(p_url)) or p_audience is null or p_audience not in ('all','encadrants','management','admin') or p_enabled is null or p_position is null or p_position not between 0 and 99 then raise exception 'Vérifie le libellé, le lien HTTP(S), la visibilité et l’ordre du bouton.';end if;
 if p_id is null then
  insert into public.workshop_custom_buttons(label,url,audience,enabled,position) values(trim(p_label),trim(p_url),p_audience,p_enabled,p_position) returning id into v_id;
 else
  update public.workshop_custom_buttons set label=trim(p_label),url=trim(p_url),audience=p_audience,enabled=p_enabled,position=p_position,updated_at=now() where id=p_id returning id into v_id;
  if not found then raise exception 'Bouton introuvable.';end if;
 end if;
 return jsonb_build_object('id',v_id);
end $$;
create or replace function public.workshop_delete_button(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin
 a:=workshop_private.actor();
 if (a->>'admin')::boolean is not true then raise exception 'Boutons réservés à l’administration.' using errcode='42501';end if;
 delete from public.workshop_custom_buttons where id=p_id;
 if not found then raise exception 'Bouton introuvable.';end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_save_button(uuid,text,text,text,boolean,integer),public.workshop_delete_button(uuid) from public,anon,authenticated;
grant execute on function public.workshop_save_button(uuid,text,text,text,boolean,integer),public.workshop_delete_button(uuid) to authenticated;

create or replace function public.workshop_import_planning(p_rows jsonb,p_targets jsonb,p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; target jsonb; day date; v_amount numeric; result jsonb:=jsonb_build_object('saved',0,'skipped',0); saved_targets integer:=0; skipped_targets integer:=0;
begin
 a:=workshop_private.actor();
 if (a->>'admin')::boolean is not true then raise exception 'Import réservé à l’administration.' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or p_targets is null or jsonb_typeof(p_targets)<>'array' then raise exception 'Import invalide.';end if;
 if jsonb_array_length(p_targets)>84 then raise exception 'Maximum 84 objectifs par import.';end if;
 if jsonb_array_length(p_rows)>0 then result:=public.workshop_import_schedule(p_rows,p_replace);end if;
 if exists(select 1 from jsonb_array_elements(p_targets) x group by x->>'date' having count(*)>1) then raise exception 'Objectifs en double pour une même date.';end if;
 lock table public.workshop_daily_targets in share row exclusive mode;
 for target in select value from jsonb_array_elements(p_targets) loop
  if coalesce(target->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or jsonb_typeof(target->'amount') is distinct from 'number' then raise exception 'Date ou montant d’objectif invalide.';end if;
  day:=(target->>'date')::date;v_amount:=(target->>'amount')::numeric;
  if v_amount<0 or v_amount>9999999999.99 or v_amount<>round(v_amount,2) then raise exception 'Objectif invalide : montant positif ou nul, avec deux décimales maximum.';end if;
  if exists(select 1 from public.workshop_daily_targets t where t.date=day) then
   if not coalesce(p_replace,false) then skipped_targets:=skipped_targets+1;continue;end if;
   update public.workshop_daily_targets t set amount=v_amount,updated_at=now() where t.date=day;
  else
   insert into public.workshop_daily_targets(date,amount) values(day,v_amount);
  end if;
  saved_targets:=saved_targets+1;
 end loop;
 return result||jsonb_build_object('targets_saved',saved_targets,'targets_skipped',skipped_targets);
end $$;
revoke all on function public.workshop_import_planning(jsonb,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.workshop_import_planning(jsonb,jsonb,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
