begin;
create table if not exists workshop_private.common_assign86(task_id uuid primary key,staff_id text references public.workshop_staff(id),version integer not null default 1,updated_at timestamptz not null default now());
alter table workshop_private.common_assign86 enable row level security;revoke all on workshop_private.common_assign86 from public,anon,authenticated;
create or replace function workshop_private.encadrant86() returns boolean language plpgsql stable security definer set search_path='' as $$declare a jsonb;begin a:=workshop_private.actor_before30();return exists(select 1 from public.workshop_staff where id=a->>'self' and active and role not in ('guest','director') and lower(btrim(team))='encadrants');end $$;
create or replace function workshop_private.common_can_tick86(p_task uuid) returns boolean language plpgsql stable security definer set search_path='' as $$declare a jsonb;s text;begin
 a:=workshop_private.actor_before30();if a->>'role'='guest' or exists(select 1 from public.workshop_staff where id=a->>'self' and role='guest') then return false;end if;
 select staff_id into s from workshop_private.common_assign86 where task_id=p_task;
 return s is null or s=a->>'self' or workshop_private.encadrant86();
end $$;
create or replace function public.workshop_common86() returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;rows jsonb;assignable boolean;begin
 a:=workshop_private.actor_before30();rows:=public.workshop_common83();assignable:=workshop_private.encadrant86() or workshop_private.manage83();
 if a->>'role'='guest' or exists(select 1 from public.workshop_staff where id=a->>'self' and role='guest') then return jsonb_build_object('items',rows,'people','[]','can_assign',false);end if;
 return jsonb_build_object('can_assign',assignable,'people',case when assignable then(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name),'[]') from public.workshop_staff s where s.active and s.role not in ('guest','director') and lower(btrim(coalesce(s.team,'')))<>'encadrants') else '[]'::jsonb end,
 'items',(select coalesce(jsonb_agg(t||jsonb_build_object('assigned_staff',x.staff_id,'assigned_name',s.name,'assignment_version',coalesce(x.version,0),'can_tick',workshop_private.common_can_tick86((t->>'id')::uuid))),'[]') from jsonb_array_elements(rows) t left join workshop_private.common_assign86 x on x.task_id=(t->>'id')::uuid left join public.workshop_staff s on s.id=x.staff_id));
end $$;
create or replace function public.workshop_common_assign86(p_task uuid,p_staff text,p_version integer) returns void language plpgsql security definer set search_path='' as $$declare a jsonb;v int;begin
 a:=workshop_private.actor();if not(workshop_private.encadrant86() or workshop_private.manage83()) then raise exception 'Attribution réservée aux encadrants.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('common86:'||p_task,0));
 if not exists(select 1 from jsonb_array_elements(public.workshop_common83()) t where t->>'id'=p_task::text) then raise exception 'Tâche introuvable.';end if;
 if p_staff is not null and not exists(select 1 from public.workshop_staff where id=p_staff and active and role not in ('guest','director') and lower(btrim(coalesce(team,'')))<>'encadrants') then raise exception 'Choisis un technicien actif.';end if;
 select version into v from workshop_private.common_assign86 where task_id=p_task for update;if coalesce(v,0) is distinct from p_version then raise exception 'Attribution modifiée. Rouvre la tâche.';end if;
 insert into workshop_private.common_assign86(task_id,staff_id) values(p_task,p_staff) on conflict(task_id) do update set staff_id=excluded.staff_id,version=common_assign86.version+1,updated_at=now();
end $$;
-- Ferme aussi les anciennes routes : un client ancien ne peut pas valider
-- une tâche désormais attribuée à quelqu’un d’autre.
do $$begin
 if to_regprocedure('public.workshop_common_tick83_before86(uuid,uuid,boolean)') is null then alter function public.workshop_common_tick83(uuid,uuid,boolean) rename to workshop_common_tick83_before86;end if;
 if to_regprocedure('public.workshop_common_save83_before86(uuid,text,jsonb,text,integer,boolean)') is null then alter function public.workshop_common_save83(uuid,text,jsonb,text,integer,boolean) rename to workshop_common_save83_before86;end if;
end $$;
create or replace function public.workshop_common_tick83(p_task uuid,p_id uuid,p_done boolean) returns void language plpgsql security definer set search_path='' as $$begin
 perform workshop_private.actor();perform pg_advisory_xact_lock(hashtextextended('common86:'||p_task,0));if not workshop_private.common_can_tick86(p_task) then raise exception 'Seuls le technicien désigné et les encadrants peuvent valider cette tâche.' using errcode='42501';end if;
 perform public.workshop_common_tick83_before86(p_task,p_id,p_done);
end $$;
create or replace function public.workshop_common_save83(p_id uuid,p_title text,p_steps jsonb,p_local text,p_version integer,p_delete boolean default false) returns void language plpgsql security definer set search_path='' as $$declare old_task jsonb;x jsonb;begin
 perform workshop_private.actor();perform pg_advisory_xact_lock(hashtextextended('common86:'||p_id,0));
 if not p_delete and not workshop_private.common_can_tick86(p_id) then
  select t into old_task from jsonb_array_elements(public.workshop_common83()) t where t->>'id'=p_id::text;
  for x in select * from jsonb_array_elements(p_steps) loop
   if coalesce((x->>'done')::boolean,false) is distinct from coalesce((select (s->>'done')::boolean from jsonb_array_elements(old_task->'steps') s where s->>'id'=x->>'id'),false) then raise exception 'Validation réservée au technicien désigné et aux encadrants.' using errcode='42501';end if;
  end loop;
 end if;
 perform public.workshop_common_save83_before86(p_id,p_title,p_steps,p_local,p_version,p_delete);
end $$;
revoke all on function workshop_private.encadrant86(),workshop_private.common_can_tick86(uuid),public.workshop_common_tick83_before86(uuid,uuid,boolean),public.workshop_common_save83_before86(uuid,text,jsonb,text,integer,boolean) from public,anon,authenticated;
revoke all on function public.workshop_common86(),public.workshop_common_assign86(uuid,text,integer),public.workshop_common_tick83(uuid,uuid,boolean),public.workshop_common_save83(uuid,text,jsonb,text,integer,boolean) from public,anon;
grant execute on function public.workshop_common86(),public.workshop_common_assign86(uuid,text,integer),public.workshop_common_tick83(uuid,uuid,boolean),public.workshop_common_save83(uuid,text,jsonb,text,integer,boolean) to authenticated;
notify pgrst,'reload schema';commit;
