-- MAJ59 — après MAJ58. Réexécutable, données existantes conservées.
begin;
-- Une équipe ne confère aucun droit de gestion.
create or replace function workshop_private.actor_before30() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before36();
 if not coalesce((a->>'admin')::boolean,false) and (select enabled from public.workshop_maintenance where id=1) then raise exception 'Application en maintenance. Réessaie dans quelques instants.' using errcode='42501';end if;
 return a||jsonb_build_object('reports_all',coalesce((a->>'manager')::boolean,false));end $$;
-- Intervalle semi-ouvert : début inclus, fin exclue ; coupure déjeuner exclue.
create or replace function workshop_private.in_shift(p_slots jsonb,p_at timestamptz) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from jsonb_array_elements(coalesce(p_slots,'[]')) s where (p_at at time zone 'Europe/Paris')::time >= (s->>'start')::time and (p_at at time zone 'Europe/Paris')::time < (s->>'end')::time)
$$;
create table if not exists public.workshop_sections(section text primary key,disabled boolean not null default false,updated_at timestamptz not null default now(),updated_by uuid references auth.users(id) on delete set null);
alter table public.workshop_sections enable row level security;
revoke all on public.workshop_sections from public,anon,authenticated;
insert into public.workshop_sections(section) select unnest(array['journee','plan','tasks','reports','team','lunch','leave','orders','waste','recap','quality','disputes','polls','inbox']) on conflict do nothing;
create or replace function public.workshop_sections_status() returns jsonb language plpgsql security definer set search_path='' as $$begin perform workshop_private.actor_before30();return (select coalesce(jsonb_object_agg(section,disabled),'{}') from public.workshop_sections);end $$;
create or replace function workshop_private.assert_section(p_section text) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();if not coalesce((a->>'admin')::boolean,false) and exists(select 1 from public.workshop_sections where section=p_section and disabled) then raise exception 'Cette section est temporairement indisponible.' using errcode='42501';end if;end $$;
create or replace function public.workshop_section_set(p_section text,p_disabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_disabled is null or not exists(select 1 from public.workshop_sections where section=p_section) then raise exception 'Section invalide.';end if;
 update public.workshop_sections set disabled=p_disabled,updated_at=now(),updated_by=auth.uid() where section=p_section;end $$;
create or replace function public.workshop_load(p_date date default current_date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;disabled jsonb;begin
 a:=workshop_private.actor_before30();
 if coalesce((a->>'manager')::boolean,false) then
 update public.workshop_days set confirmed=now() where staff_id=a->>'self' and date=(now() at time zone 'Europe/Paris')::date and presence='present' and confirmed is null and workshop_private.in_shift(slots,now());end if;
 -- Éviter l’ancienne confirmation anticipée de MAJ58.
 r:=public.workshop_load_before58(p_date);disabled:=public.workshop_sections_status();
 r:=r||jsonb_build_object('disabled_sections',disabled,'reports_all',coalesce((a->>'manager')::boolean,false),'can_view_ratio',coalesce((a->>'manager')::boolean,false) or a->>'role'='guest');
 if not coalesce((a->>'manager')::boolean,false) and a->>'role'<>'guest' then r:=r-'selected_ratio';end if;
 if not coalesce((a->>'admin')::boolean,false) then
 if (disabled->>'tasks')::boolean then r:=r||'{"tasks":[]}'::jsonb;end if;
 if (disabled->>'team')::boolean then r:=r||'{"skills":[]}'::jsonb;end if;
 if (disabled->>'plan')::boolean then r:=r||'{"plan_draft":null,"station_status":[]}'::jsonb;end if;
 end if;return r;
end $$;
-- Séparer les demandes historiques mixtes sans perdre auteur, notes ou suivi.
alter table public.workshop_waste add column if not exists provider text;
do $$declare r public.workshop_waste%rowtype;begin
 for r in select * from public.workshop_waste where provider is null and categories ? 'filtres' and jsonb_array_length(categories)>1 for update loop
 insert into public.workshop_waste(id,author_id,author_name,categories,notes,created_at,version,validated_at,validated_name,validated_by,bin_counts,collected_at,collected_name,updated_at,updated_name,provider)
 values(gen_random_uuid(),r.author_id,r.author_name,'["filtres"]',r.notes,r.created_at,r.version,r.validated_at,r.validated_name,r.validated_by,case when r.bin_counts ? 'filtres' then jsonb_build_object('filtres',r.bin_counts->'filtres') else '{}'::jsonb end,r.collected_at,r.collected_name,r.updated_at,r.updated_name,'Chimirec');
 update public.workshop_waste set categories=categories-'filtres',bin_counts=bin_counts-'filtres',provider='Grandidier',version=version+1 where id=r.id;
 end loop;
 update public.workshop_waste set provider=case when categories ? 'filtres' then 'Chimirec' else 'Grandidier' end where provider is null;
end $$;
alter table public.workshop_waste alter column provider set not null;
create or replace function workshop_private.waste_provider(c jsonb) returns text language plpgsql immutable set search_path='' as $$
declare k text;v jsonb;p text;n text;begin
 if c is null or jsonb_typeof(c)<>'array' or jsonb_array_length(c) not between 1 and 4 then raise exception 'Sélection de déchets invalide.';end if;
 if (select count(distinct x) from jsonb_array_elements(c)x)<>jsonb_array_length(c) then raise exception 'Déchet en double.';end if;
 for v in select value from jsonb_array_elements(c) loop
 k:=v#>>'{}';if jsonb_typeof(v)<>'string' or k not in ('batteries','ferraille','fonte','aluminium','filtres','huiles') then raise exception 'Déchet invalide.';end if;
 n:=case when k in ('filtres','huiles') then 'Chimirec' else 'Grandidier' end;
 if p is not null and n<>p then raise exception 'Crée une demande séparée pour chaque prestataire.';end if;p:=n;
 end loop;return p;end $$;
create or replace function workshop_private.check_waste_counts(c jsonb,q jsonb) returns void language plpgsql set search_path='' as $$
declare k text;n numeric;begin
 perform workshop_private.waste_provider(c);
 if q is null or jsonb_typeof(q)<>'object' then raise exception 'Quantités invalides.';end if;
 for k in select jsonb_array_elements_text(c) loop
 if not q ? k or jsonb_typeof(q->k)<>'number' then raise exception 'Renseigne chaque quantité.';end if;
 n:=(q->>k)::numeric;
 if k='huiles' then if n<=0 or n>100000 or round(n,1)<>n then raise exception 'Huiles : de 0,1 à 100 000 litres, une décimale maximum.';end if;
 elsif n<1 or n>999 or trunc(n)<>n then raise exception 'Bacs : entier de 1 à 999.';end if;
 end loop;
 if (select count(*) from jsonb_object_keys(q))<>jsonb_array_length(c) then raise exception 'Quantités incohérentes.';end if;
end $$;
-- Contrainte indépendante des API : aucune demande ne mélange les prestataires.
alter table public.workshop_waste drop constraint if exists workshop_waste_provider_check;
alter table public.workshop_waste add constraint workshop_waste_provider_check check(provider=workshop_private.waste_provider(categories));
create or replace function public.workshop_create_waste(p_id uuid,p_categories jsonb,p_notes text,p_counts jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');perform workshop_private.check_waste_counts(p_categories,p_counts);
 if p_id is null or p_notes is null or length(p_notes)>2000 then raise exception 'Formulaire invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('waste:'||p_id::text,0));select * into r from public.workshop_waste where id=p_id;
 if found then if r.author_id is distinct from auth.uid() or r.categories is distinct from p_categories or r.bin_counts is distinct from p_counts or r.notes is distinct from trim(p_notes) then raise exception 'Cette demande existe déjà.';end if;return to_jsonb(r);end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_waste(id,author_id,author_name,categories,notes,bin_counts,provider) values(p_id,auth.uid(),coalesce(person,a->>'user'),p_categories,trim(p_notes),p_counts,workshop_private.waste_provider(p_categories)) returning * into r;return to_jsonb(r);end $$;
-- Le prestataire reste celui de la demande lors d’une correction.
create or replace function public.workshop_update_waste(p_id uuid,p_version integer,p_categories jsonb,p_notes text,p_counts jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 perform workshop_private.check_waste_counts(p_categories,p_counts);if p_notes is null or length(p_notes)>2000 then raise exception 'Précisions invalides.';end if;
 select * into r from public.workshop_waste where id=p_id for update;if not found then raise exception 'Demande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée entre-temps.';end if;
 if r.provider<>workshop_private.waste_provider(p_categories) then raise exception 'Le prestataire ne peut pas être changé : crée une nouvelle demande.';end if;
 if r.categories=p_categories and r.notes=trim(p_notes) and r.bin_counts=p_counts then return to_jsonb(r);end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_waste set categories=p_categories,notes=trim(p_notes),bin_counts=p_counts,version=version+1,updated_at=now(),updated_name=coalesce(person,a->>'user'),validated_at=null,validated_name=null,validated_by=null,collected_at=null,collected_name=null where id=p_id returning * into r;return to_jsonb(r);end $$;
create or replace function public.workshop_waste_by_provider(p_provider text,p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();perform workshop_private.assert_section('waste');
 if p_provider not in ('Grandidier','Chimirec') or p_provider is null or p_offset is null or p_offset<0 then raise exception 'Prestataire ou page invalide.';end if;
 if a->>'role'='guest' then return jsonb_build_object('can_manage',false,'total',0,'items','[]'::jsonb);end if;
 return jsonb_build_object('can_manage',coalesce((a->>'manager')::boolean,false),'total',(select count(*) from public.workshop_waste where provider=p_provider),'items',(select coalesce(jsonb_agg(to_jsonb(w) order by created_at desc,id),'[]') from (select * from public.workshop_waste where provider=p_provider order by created_at desc,id limit 30 offset p_offset)w));end $$;
create or replace function workshop_private.confirm_during_shift() returns trigger language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 if auth.uid() is not null and new.confirmed is not null and (tg_op='INSERT' or old.confirmed is null) then
 a:=workshop_private.actor_before30();if coalesce((a->>'manager')::boolean,false) and a->>'self'=new.staff_id and (new.date<>(now() at time zone 'Europe/Paris')::date or new.presence<>'present' or not workshop_private.in_shift(new.slots,now())) then new.confirmed:=null;end if;
 end if;return new;end $$;
drop trigger if exists workshop_confirmation_hours on public.workshop_days;
create trigger workshop_confirmation_hours before insert or update on public.workshop_days for each row execute function workshop_private.confirm_during_shift();
-- Les sections sont verrouillées aussi sur les appels directs des clients.
-- Chaque implémentation précédente reste privée ; les signatures API sont conservées.
do $migration$
declare f record;k text;backup text;call_args text;body text;begin
 for f in select p.*,pg_get_function_arguments(p.oid) args,pg_get_function_identity_arguments(p.oid) identity_args,pg_get_function_result(p.oid) result from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'workshop_%' and p.proname not like '%before%' and has_function_privilege('authenticated',p.oid,'EXECUTE') loop
 k:=case
 when f.proname ~ '(report|reports)' then 'reports'
 when f.proname ~ '_(order|orders)$' then 'orders'
 when f.proname ~ '_waste$' and f.proname not in ('workshop_create_waste','workshop_update_waste') then 'waste'
 when f.proname like 'workshop_leave_%' then 'leave'
 when f.proname like 'workshop_lunch_%' then 'lunch'
 when f.proname like 'workshop_poll_%' then 'polls'
 when f.proname ~ '(handover|recap)' then 'recap'
 when f.proname ~ '(dispute)' then 'disputes'
 when f.proname='workshop_quality_form' then 'quality'
 when f.proname ~ '(recurring_task)' then 'tasks'
 when f.proname in ('workshop_skill_save','workshop_skills_list','workshop_staff_save','workshop_admin_job','workshop_admin_photo','workshop_admin_signature','workshop_admin_birthday','workshop_admin_birthday_save') then 'team'
 when f.proname in ('workshop_assign','workshop_geometry','workshop_plan_edit','workshop_plan_suggest','workshop_replace_express','workshop_replacement_candidates','workshop_station_state','workshop_save_station') then 'plan'
 when f.proname in ('workshop_send_message','workshop_delete_notification','workshop_delete_all_notifications') then 'inbox'
 else null end;
 if k is null then continue;end if;
 backup:=f.proname||'_before59';
 if to_regprocedure(format('public.%I(%s)',backup,oidvectortypes(f.proargtypes))) is not null then continue;end if;
 select coalesce(string_agg(format('$%s',i),',' order by i),'') into call_args from generate_series(1,f.pronargs)i;
 execute format('alter function public.%I(%s) rename to %I',f.proname,f.identity_args,backup);
 execute format('revoke all on function public.%I(%s) from public,anon,authenticated',backup,f.identity_args);
 body:=format('begin perform workshop_private.assert_section(%L); ',k)||case when f.result='void' then format('perform public.%I(%s); return;',backup,call_args) else format('return public.%I(%s);',backup,call_args) end||' end';
 execute format('create function public.%I(%s) returns %s language plpgsql security definer set search_path='''' as %L',f.proname,f.args,f.result,body);
 execute format('revoke all on function public.%I(%s) from public,anon',f.proname,f.identity_args);
 execute format('grant execute on function public.%I(%s) to authenticated',f.proname,f.identity_args);
 end loop;
 -- Le chargement général peut lire les compétences avant de masquer la section Équipes.
 execute replace(pg_get_functiondef('public.workshop_load_before58(date)'::regprocedure),'public.workshop_skills_list()','public.workshop_skills_list_before59()');
end $migration$;
do $$begin if to_regprocedure('public.workshop_message_status_before59(uuid)') is null then alter function public.workshop_message_status(uuid) rename to workshop_message_status_before59;end if;end $$;
create or replace function public.workshop_message_status(p_read uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
begin if p_read is not null then perform workshop_private.assert_section('inbox');end if;return public.workshop_message_status_before59(p_read);end $$;
revoke all on function public.workshop_message_status_before59(uuid),public.workshop_message_status(uuid) from public,anon,authenticated;
grant execute on function public.workshop_message_status(uuid) to authenticated;
-- Les nouvelles implémentations ne sont pas renommées (réexécution sans récursion).
create or replace function workshop_private.waste_access() returns trigger language plpgsql security definer set search_path='' as $$begin if auth.uid() is not null then perform workshop_private.assert_section('waste');end if;return case when tg_op='DELETE' then old else new end;end $$;
drop trigger if exists workshop_waste_access on public.workshop_waste;
create trigger workshop_waste_access before insert or update or delete on public.workshop_waste for each row execute function workshop_private.waste_access();
do $$begin if to_regprocedure('public.workshop_mutate_before59(jsonb)') is null then alter function public.workshop_mutate(jsonb) rename to workshop_mutate_before59;end if;end $$;
create or replace function public.workshop_mutate(p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text;begin
 k:=case when p->>'action' in ('day','confirm') then 'plan' when p->>'action' in ('task','editTask','deleteTask','complete') then 'tasks' when p->>'action' in ('staff','createStaff','deleteStaff') then 'team' end;
 if k is not null then perform workshop_private.assert_section(k);end if;
 return public.workshop_mutate_before59(p);end $$;
revoke all on function workshop_private.in_shift(jsonb,timestamptz),workshop_private.waste_provider(jsonb),workshop_private.assert_section(text),workshop_private.confirm_during_shift(),workshop_private.waste_access(),public.workshop_mutate_before59(jsonb),public.workshop_sections_status(),public.workshop_section_set(text,boolean),public.workshop_waste_by_provider(text,integer) from public,anon,authenticated;
grant execute on function public.workshop_sections_status(),public.workshop_section_set(text,boolean),public.workshop_waste_by_provider(text,integer) to authenticated;
revoke all on function public.workshop_mutate(jsonb) from public,anon;
grant execute on function public.workshop_mutate(jsonb) to authenticated;
notify pgrst,'reload schema';commit;
