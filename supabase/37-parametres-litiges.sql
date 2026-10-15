-- MAJ37 : après 36. Réexécutable.
begin;
alter table public.workshop_reports add column if not exists before_intervention boolean not null default false;
create or replace function public.workshop_create_report(p_id uuid,p_registration text,p_notes text,p_photos jsonb,p_location text,p_before_intervention boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform workshop_private.actor();if p_before_intervention is null then raise exception 'Choix requis.';end if;
 perform pg_advisory_xact_lock(hashtextextended('report-location:'||p_id::text,0));
 if exists(select 1 from public.workshop_reports where id=p_id and before_intervention is distinct from p_before_intervention) then raise exception 'Signalement déjà enregistré avec un autre contexte.';end if;
 result:=public.workshop_create_report(p_id,p_registration,p_notes,p_photos,p_location);update public.workshop_reports set before_intervention=p_before_intervention where id=p_id;return result;end $$;
create or replace function public.workshop_update_report(p_id uuid,p_version integer,p_registration text,p_notes text,p_photos jsonb,p_location text,p_before_intervention boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform workshop_private.actor();if p_before_intervention is null then raise exception 'Choix requis.';end if;result:=public.workshop_update_report(p_id,p_version,p_registration,p_notes,p_photos,p_location);update public.workshop_reports set before_intervention=p_before_intervention where id=p_id;return result;end $$;
create or replace function public.workshop_get_report(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;result jsonb;r public.workshop_reports%rowtype;begin
 a:=workshop_private.actor_before30();
 if a->>'role'='guest' then
 select x.* into r from public.workshop_reports x join public.workshop_guest_settings g on g.report_id=x.id join auth.users u on u.id=x.author_id where x.id=p_id and lower(u.email)='nchivot@norauto.fr';
 if not found then raise exception 'Signalement non autorisé.' using errcode='42501';end if;
 result:=jsonb_build_object('id',r.id,'registration',r.registration,'author_name',r.author_name,'notes',r.notes,'created_at',r.created_at,'photos',(select coalesce(jsonb_agg(photo order by position),'[]') from public.workshop_report_photos where report_id=p_id),'can_edit',false,'can_delete',false);
 else result:=public.workshop_get_report_before30(p_id);end if;
 return result||jsonb_build_object('before_intervention',(select before_intervention from public.workshop_reports where id=p_id),'location',(select location from public.workshop_reports where id=p_id),'guest_example',(select report_id=p_id from public.workshop_guest_settings where id=1),'can_share_guest',(a->>'admin')::boolean and exists(select 1 from public.workshop_reports rr join auth.users u on u.id=rr.author_id where rr.id=p_id and lower(u.email)='nchivot@norauto.fr'));
end $$;

create or replace function workshop_private.task_inbox() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.done=1 then return new;end if;
 if TG_OP='UPDATE' then if (new.title,new.details,new.staff_id,new.due,new.priority,new.done) is not distinct from (old.title,old.details,old.staff_id,old.due,old.priority,old.done) then return new;end if;end if;
 insert into public.workshop_messages(user_id,body,url) select u.id,'Tâche : '||left(new.title,400)||' · échéance '||to_char(new.due,'DD/MM/YYYY'),'/?notifications=tasks' from auth.users u join public.workshop_staff s on s.email=lower(u.email) where s.active and s.id=new.staff_id;
 return new;
end $$;
revoke all on function workshop_private.task_inbox() from public,anon,authenticated;
drop trigger if exists workshop_task_inbox on public.workshop_tasks;
create trigger workshop_task_inbox after insert or update on public.workshop_tasks for each row execute function workshop_private.task_inbox();
create table if not exists public.workshop_disputes(id uuid primary key,client text not null,registration text not null,description text not null,followup text not null default '',status text not null check(status in ('open','resolved')),version integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),updated_name text not null);
alter table public.workshop_disputes enable row level security;
revoke all on public.workshop_disputes from public,anon,authenticated;
create or replace function public.workshop_list_disputes(p_status text default 'open',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Litiges réservés aux gestionnaires.' using errcode='42501';end if;if p_status is null or p_status not in ('open','resolved') or p_offset is null or p_offset<0 then raise exception 'Filtre invalide.';end if;
 return jsonb_build_object('total',(select count(*) from public.workshop_disputes where status=p_status),'items',(select coalesce(jsonb_agg(to_jsonb(d) order by updated_at desc,id),'[]') from (select * from public.workshop_disputes where status=p_status order by updated_at desc,id limit 30 offset p_offset)d));end $$;
create or replace function public.workshop_save_dispute(p_id uuid,p_version integer,p_client text,p_registration text,p_description text,p_followup text,p_status text) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_disputes%rowtype;person text;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Litiges réservés aux gestionnaires.' using errcode='42501';end if;
 if p_id is null or p_version is null or p_client is null or length(trim(p_client)) not between 1 and 120 or p_registration is null or length(trim(p_registration)) not between 1 and 20 or p_description is null or length(trim(p_description)) not between 1 and 4000 or p_followup is null or length(p_followup)>6000 or p_status is null or p_status not in ('open','resolved') then raise exception 'Vérifie le client, la plaque et la description.';end if;
 perform pg_advisory_xact_lock(hashtextextended('dispute:'||p_id::text,0));select * into r from public.workshop_disputes where id=p_id for update;
 if (found and r.version is distinct from p_version) or (not found and p_version<>0) then raise exception 'Fiche modifiée entre-temps. Actualise la liste.';end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_disputes(id,client,registration,description,followup,status,updated_name) values(p_id,trim(p_client),upper(trim(p_registration)),trim(p_description),trim(p_followup),p_status,coalesce(person,a->>'user')) on conflict(id) do update set client=excluded.client,registration=excluded.registration,description=excluded.description,followup=excluded.followup,status=excluded.status,version=workshop_disputes.version+1,updated_at=now(),updated_name=excluded.updated_name;
end $$;
revoke all on function public.workshop_create_report(uuid,text,text,jsonb,text,boolean),public.workshop_update_report(uuid,integer,text,text,jsonb,text,boolean),public.workshop_list_disputes(text,integer),public.workshop_save_dispute(uuid,integer,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.workshop_create_report(uuid,text,text,jsonb,text,boolean),public.workshop_update_report(uuid,integer,text,text,jsonb,text,boolean),public.workshop_list_disputes(text,integer),public.workshop_save_dispute(uuid,integer,text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
