begin;
create table if not exists workshop_private.common83(id uuid primary key,title text not null,steps jsonb not null,due_at timestamptz,version int not null default 1,deleted boolean not null default false,created_at timestamptz not null default now());
alter table workshop_private.common83 enable row level security;revoke all on workshop_private.common83 from public,anon,authenticated;
create or replace function public.workshop_common83() returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;legacy jsonb;begin
 a:=workshop_private.actor_before30();if a->>'role'='guest' then return '[{"id":"demo","title":"Préparer l’atelier","steps":[{"id":"demo-step","label":"Vérifier les postes","done":false}],"version":0}]';end if;
 legacy:=public.workshop_common76();return(select coalesce(jsonb_agg(x order by x->>'due_at' nulls last,x->>'title'),'[]') from (select v||jsonb_build_object('version',0) x from jsonb_array_elements(legacy) v where not exists(select 1 from workshop_private.common83 c where c.id::text=v->>'id') union all select to_jsonb(c) from workshop_private.common83 c where not deleted) t);
end $$;
create or replace function public.workshop_common_save83(p_id uuid,p_title text,p_steps jsonb,p_local text,p_version int,p_delete boolean default false) returns void language plpgsql security definer set search_path='' as $$declare r workshop_private.common83%rowtype;s jsonb;clean jsonb:='[]';begin
 if not workshop_private.manage83() then raise exception 'Gestion réservée aux responsables.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('common83',0));select * into r from workshop_private.common83 where id=p_id for update;
 if coalesce(r.version,0) is distinct from p_version then raise exception 'Cette tâche a changé. Rouvre-la.';end if;
 if p_delete then insert into workshop_private.common83(id,title,steps,deleted) values(p_id,'Supprimée','[]',true) on conflict(id) do update set deleted=true,version=workshop_private.common83.version+1;return;end if;
 if length(trim(coalesce(p_title,''))) not between 1 and 160 or jsonb_typeof(p_steps) is distinct from 'array' or jsonb_array_length(p_steps) not between 1 and 100 then raise exception 'Titre et actions obligatoires (100 maximum).';end if;
 for s in select value from jsonb_array_elements(p_steps) loop
  if length(trim(coalesce(s->>'label',''))) not between 1 and 300 then raise exception 'Action invalide.';end if;
  clean:=clean||jsonb_build_array(jsonb_build_object('id',coalesce(nullif(s->>'id',''),gen_random_uuid()::text),'label',trim(s->>'label'),'done',coalesce((s->>'done')::boolean,false)));
 end loop;
 if (select count(distinct x->>'id') from jsonb_array_elements(clean) x)<>jsonb_array_length(clean) then raise exception 'Identifiants d’actions dupliqués.';end if;
 insert into workshop_private.common83(id,title,steps,due_at) values(p_id,trim(p_title),clean,nullif(p_local,'')::timestamp at time zone 'Europe/Paris') on conflict(id) do update set title=excluded.title,steps=excluded.steps,due_at=excluded.due_at,version=workshop_private.common83.version+1,deleted=false;
end $$;
create or replace function public.workshop_common_tick83(p_task uuid,p_id uuid,p_done boolean) returns void language plpgsql security definer set search_path='' as $$declare r workshop_private.common83%rowtype;old_task jsonb;begin
 perform workshop_private.actor();if p_done is null then raise exception 'État requis.';end if;perform pg_advisory_xact_lock(hashtextextended('common83',0));
 select * into r from workshop_private.common83 where id=p_task for update;
 if not found then
  select t into old_task from jsonb_array_elements(public.workshop_common76()) t where t->>'id'=p_task::text;if old_task is null then raise exception 'Action indisponible.';end if;
  insert into workshop_private.common83(id,title,steps,version) values(p_task,old_task->>'title',old_task->'steps',0) returning * into r;
 end if;
 if r.deleted or not exists(select 1 from jsonb_array_elements(r.steps) s where s->>'id'=p_id::text) then raise exception 'Action indisponible.';end if;
 update workshop_private.common83 set steps=(select jsonb_agg(case when s->>'id'=p_id::text then s||jsonb_build_object('done',p_done) else s end order by n) from jsonb_array_elements(r.steps) with ordinality x(s,n)),version=version+1 where id=p_task;
end $$;
do $$declare f regprocedure;begin for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in ('workshop_common_create76','workshop_common_tick76') loop execute format('revoke all on function %s from public,anon,authenticated',f);end loop;end $$;
revoke all on function public.workshop_common83(),public.workshop_common_save83(uuid,text,jsonb,text,int,boolean),public.workshop_common_tick83(uuid,uuid,boolean) from public,anon;
grant execute on function public.workshop_common83(),public.workshop_common_save83(uuid,text,jsonb,text,int,boolean),public.workshop_common_tick83(uuid,uuid,boolean) to authenticated;
notify pgrst,'reload schema';commit;
