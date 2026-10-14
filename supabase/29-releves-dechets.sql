-- MAJ29 : après les migrations précédentes. Réexécutable.
begin;
create table if not exists public.workshop_handover(
 date date primary key,vehicles text not null,anomalies text not null,missing_parts text not null,tasks jsonb not null,
 version integer not null default 1,author_name text not null,updated_at timestamptz not null default now(),release_at timestamptz not null
);
create table if not exists public.workshop_waste(
 id uuid primary key,author_id uuid references auth.users(id) on delete set null,author_name text not null,
 categories jsonb not null,notes text not null default '',created_at timestamptz not null default now(),version integer not null default 1,
 validated_at timestamptz,validated_name text,validated_by uuid references auth.users(id) on delete set null
);
alter table public.workshop_handover enable row level security;
alter table public.workshop_waste enable row level security;
revoke all on public.workshop_handover,public.workshop_waste from public,anon,authenticated;
create or replace function public.workshop_list_handovers(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; manage boolean;
begin
 a:=workshop_private.actor();manage:=coalesce((a->>'manager')::boolean,false);
 if not (manage or coalesce((a->>'reports_all')::boolean,false)) then raise exception 'Récapitulatifs réservés aux encadrants.' using errcode='42501';end if;
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('can_manage',manage,'total',(select count(*) from public.workshop_handover where manage or release_at<=now()),'items',(select coalesce(jsonb_agg(to_jsonb(h)||jsonb_build_object('published',h.release_at<=now(),'can_edit',manage and h.release_at>now()) order by date desc),'[]') from (select * from public.workshop_handover where manage or release_at<=now() order by date desc limit 30 offset p_offset) h));
end $$;
create or replace function public.workshop_save_handover(p_date date,p_version integer,p_vehicles text,p_anomalies text,p_missing_parts text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_handover%rowtype; release_time timestamptz; todo jsonb; person text;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Préparation réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null or p_version is null or p_date>(now() at time zone 'Europe/Paris')::date or p_vehicles is null or p_anomalies is null or p_missing_parts is null or greatest(length(p_vehicles),length(p_anomalies),length(p_missing_parts))>6000 then raise exception 'Date ou contenu invalide (6000 caractères par rubrique).';end if;
 release_time:=((p_date+1)::timestamp+interval '7 hours 30 minutes') at time zone 'Europe/Paris';
 if release_time<=now() then raise exception 'Ce récapitulatif est déjà publié : il ne peut plus être modifié.';end if;
 perform pg_advisory_xact_lock(hashtextextended('handover:'||p_date::text,0));
 select * into r from public.workshop_handover where date=p_date for update;
 if (found and r.version is distinct from p_version) or (not found and p_version<>0) then raise exception 'Récapitulatif modifié entre-temps. Ferme puis actualise la liste.';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'details',t.details,'due',t.due,'priority',t.priority,'name',s.name) order by t.due,t.created_at),'[]') into todo from public.workshop_tasks t join public.workshop_staff s on s.id=t.staff_id and s.active where t.done=0 and t.due<=p_date;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_handover(date,vehicles,anomalies,missing_parts,tasks,author_name,release_at) values(p_date,trim(p_vehicles),trim(p_anomalies),trim(p_missing_parts),todo,coalesce(person,a->>'user'),release_time)
 on conflict(date) do update set vehicles=excluded.vehicles,anomalies=excluded.anomalies,missing_parts=excluded.missing_parts,tasks=excluded.tasks,author_name=excluded.author_name,updated_at=now(),version=workshop_handover.version+1;
 return (select to_jsonb(h) from public.workshop_handover h where date=p_date);
end $$;
create or replace function public.workshop_list_waste(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin
 a:=workshop_private.actor();if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('can_manage',(a->>'manager')::boolean,'total',(select count(*) from public.workshop_waste),'items',(select coalesce(jsonb_agg(to_jsonb(w) order by created_at desc,id),'[]') from (select * from public.workshop_waste order by created_at desc,id limit 30 offset p_offset) w));
end $$;
create or replace function public.workshop_create_waste(p_id uuid,p_categories jsonb,p_notes text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; person text; item jsonb; r public.workshop_waste%rowtype;
begin
 a:=workshop_private.actor();
 if p_id is null or p_categories is null or jsonb_typeof(p_categories)<>'array' or p_notes is null or length(p_notes)>2000 then raise exception 'Formulaire invalide.';end if;
 if jsonb_array_length(p_categories) not between 1 and 5 then raise exception 'Sélectionne au moins un type de déchet.';end if;
 for item in select value from jsonb_array_elements(p_categories) loop
  if jsonb_typeof(item)<>'string' or item#>>'{}' not in ('batteries','ferraille','fonte','aluminium','filtres') then raise exception 'Type de déchet invalide.';end if;
 end loop;
 if (select count(distinct x) from jsonb_array_elements(p_categories) x)<>jsonb_array_length(p_categories) then raise exception 'Type de déchet en double.';end if;
 perform pg_advisory_xact_lock(hashtextextended('waste:'||p_id::text,0));
 select * into r from public.workshop_waste where id=p_id;
 if found then
  if r.author_id is distinct from auth.uid() or r.categories is distinct from p_categories or r.notes is distinct from trim(p_notes) then raise exception 'Cette demande existe déjà.';end if;
  return to_jsonb(r);
 end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_waste(id,author_id,author_name,categories,notes) values(p_id,auth.uid(),coalesce(person,a->>'user'),p_categories,trim(p_notes)) returning * into r;
 return to_jsonb(r);
end $$;
create or replace function public.workshop_validate_waste(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_waste%rowtype; person text;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Validation réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_waste where id=p_id for update;
 if not found then raise exception 'Demande introuvable.';end if;
 if r.validated_at is not null then return to_jsonb(r);end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée : actualise la liste.';end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_waste set validated_at=now(),validated_by=auth.uid(),validated_name=coalesce(person,a->>'user'),version=version+1 where id=p_id returning * into r;
 return to_jsonb(r);
end $$;
revoke all on function public.workshop_list_handovers(integer),public.workshop_save_handover(date,integer,text,text,text),public.workshop_list_waste(integer),public.workshop_create_waste(uuid,jsonb,text),public.workshop_validate_waste(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_list_handovers(integer),public.workshop_save_handover(date,integer,text,text,text),public.workshop_list_waste(integer),public.workshop_create_waste(uuid,jsonb,text),public.workshop_validate_waste(uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
