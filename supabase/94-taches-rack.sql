begin;
-- Les anciennes attributions individuelles restent conservées.
alter table workshop_private.common_assign86 add column if not exists staff_ids text[];
update workshop_private.common_assign86 set staff_ids=case when staff_id is null then '{}'::text[] else array[staff_id] end where staff_ids is null;
alter table workshop_private.common_assign86 alter column staff_ids set default '{}';
alter table workshop_private.common_assign86 alter column staff_ids set not null;
create or replace function workshop_private.common_can_tick86(p_task uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare a jsonb;ids text[];begin
 a:=workshop_private.actor_before30();if a->>'role'='guest' then return false;end if;
 select staff_ids into ids from workshop_private.common_assign86 where task_id=p_task;
 return coalesce(cardinality(ids),0)=0 or a->>'self'=any(ids) or workshop_private.encadrant86() or workshop_private.manage83();
end $$;
create or replace function public.workshop_common86() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;rows jsonb;can_assign boolean;begin
 a:=workshop_private.actor_before30();rows:=public.workshop_common83();can_assign:=(workshop_private.encadrant86() or workshop_private.manage83()) and coalesce(a->>'role','')<>'guest';
 return jsonb_build_object('can_assign',can_assign,'people',case when can_assign then(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from public.workshop_staff where active and coalesce(role,'employee') not in ('guest','director')) else '[]'::jsonb end,
 'items',(select coalesce(jsonb_agg(t||jsonb_build_object('assigned_staff',x.staff_id,'assigned_people',coalesce((select jsonb_agg(jsonb_build_object('id',i,'name',coalesce(s.name,'Ancien collaborateur')) order by s.name,i) from unnest(x.staff_ids) i left join public.workshop_staff s on s.id=i),'[]'),'assignment_version',coalesce(x.version,0),'can_tick',workshop_private.common_can_tick86((t->>'id')::uuid))),'[]') from jsonb_array_elements(rows) t left join workshop_private.common_assign86 x on x.task_id=(t->>'id')::uuid));
end $$;
create or replace function public.workshop_common_assign94(p_task uuid,p_staff text[],p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;v int;ids text[];begin
 a:=workshop_private.actor();if not(workshop_private.encadrant86() or workshop_private.manage83()) then raise exception 'Attribution réservée aux encadrants, administrateur et modérateurs.' using errcode='42501';end if;
 if p_staff is null or cardinality(p_staff)>100 then raise exception 'Sélection invalide.';end if;
 if exists(select 1 from unnest(p_staff) i where i is null or not exists(select 1 from public.workshop_staff s where s.id=i and s.active and coalesce(s.role,'employee') not in ('guest','director'))) then raise exception 'Choisis uniquement des collaborateurs actifs.';end if;
 select coalesce(array_agg(distinct i order by i),'{}') into ids from unnest(p_staff) i;
 perform pg_advisory_xact_lock(hashtextextended('common86:'||p_task,0));
 if not exists(select 1 from jsonb_array_elements(public.workshop_common83()) t where t->>'id'=p_task::text) then raise exception 'Tâche introuvable.';end if;
 select version into v from workshop_private.common_assign86 where task_id=p_task for update;
 if coalesce(v,0) is distinct from p_version then raise exception 'L’attribution a changé. Ferme puis rouvre la sélection.';end if;
 insert into workshop_private.common_assign86(task_id,staff_id,staff_ids) values(p_task,ids[1],ids)
 on conflict(task_id) do update set staff_id=excluded.staff_id,staff_ids=excluded.staff_ids,version=common_assign86.version+1,updated_at=now();
end $$;
-- Empêche un ancien écran à sélection unique d’écraser une attribution multiple.
create or replace function public.workshop_common_assign86(p_task uuid,p_staff text,p_version integer) returns void language plpgsql security definer set search_path='' as $$
begin
 perform workshop_private.actor();perform pg_advisory_xact_lock(hashtextextended('common86:'||p_task,0));
 if exists(select 1 from workshop_private.common_assign86 where task_id=p_task and cardinality(staff_ids)>1) then raise exception 'Cette tâche a plusieurs destinataires. Ferme et rouvre l’application pour utiliser la sélection multiple.';end if;
 perform public.workshop_common_assign94(p_task,case when p_staff is null then '{}'::text[] else array[p_staff] end,p_version);
end $$;
create table if not exists workshop_private.waste_rack94(
 id integer primary key check(id between 1 and 12),contents text not null default '' check(length(contents)<=500),
 locked boolean not null default false,version integer not null default 0,
 updated_at timestamptz,updated_name text,locked_at timestamptz,locked_name text
);
insert into workshop_private.waste_rack94(id,contents)
 select i,case i when 7 then E'Bac batteries\n600 L' when 9 then E'Bac aluminium\n600 L' when 10 then E'Bac ferraille\n600 L' when 11 then E'Bac fonte\n600 L' when 12 then E'Bac anciens filtres\n600 L' else '' end from generate_series(1,12) i on conflict do nothing;
alter table workshop_private.waste_rack94 enable row level security;
revoke all on workshop_private.waste_rack94 from public,anon,authenticated;
create or replace function public.workshop_rack94() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();perform workshop_private.assert_section('waste');
 return jsonb_build_object('can_manage',coalesce((a->>'admin')::boolean,false) or a->>'role'='moderator','can_edit',coalesce(a->>'role','employee') not in ('guest','director'),'items',(select jsonb_agg(to_jsonb(r) order by id) from workshop_private.waste_rack94 r));
end $$;
create or replace function public.workshop_rack_save94(p_id integer,p_version integer,p_contents text default null,p_locked boolean default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;manager boolean;r workshop_private.waste_rack94%rowtype;n text;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');manager:=coalesce((a->>'admin')::boolean,false) or coalesce(a->>'role'='moderator',false);
 if not manager and coalesce(a->>'role','employee') in ('guest','director') then raise exception 'Compte en lecture seule.' using errcode='42501';end if;
 if p_contents is null and p_locked is null then raise exception 'Aucune modification.';end if;
 if p_contents is not null and length(p_contents)>500 then raise exception 'Maximum 500 caractères par case.';end if;
 select * into r from workshop_private.waste_rack94 where id=p_id for update;
 if not found then raise exception 'Case introuvable.';end if;
 if p_locked is not null and not manager or r.locked and not manager then raise exception 'Case verrouillée : modification réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if r.version is distinct from p_version then raise exception 'Cette case a changé. Ferme puis rouvre-la avant de modifier son contenu.';end if;
 select name into n from public.workshop_staff where id=a->>'self';n:=coalesce(n,a->>'user');
 update workshop_private.waste_rack94 set contents=coalesce(p_contents,contents),locked=coalesce(p_locked,locked),version=version+1,
 updated_at=case when p_contents is not null then now() else updated_at end,updated_name=case when p_contents is not null then n else updated_name end,
 locked_at=case when p_locked is not null then now() else locked_at end,locked_name=case when p_locked is not null then n else locked_name end where id=p_id returning * into r;
 return to_jsonb(r);
end $$;
revoke all on function public.workshop_common_assign94(uuid,text[],integer),public.workshop_rack94(),public.workshop_rack_save94(integer,integer,text,boolean) from public,anon;
grant execute on function public.workshop_common_assign94(uuid,text[],integer),public.workshop_rack94(),public.workshop_rack_save94(integer,integer,text,boolean) to authenticated;
notify pgrst,'reload schema';commit;
