-- MAJ121 — à relire avant exécution ; aucune donnée métier réécrite à l'installation.
-- Après MAJ120. Une transaction ; ancienne définition sauvegardée une seule fois.
begin;
do $$begin
 if to_regprocedure('public.workshop_plan_automatic_status120(date)') is null
 or to_regprocedure('public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)') is null
 or to_regclass('workshop_private.waste_types112') is null then
  raise exception 'Prérequis MAJ120 / déchets112 absent : arrêter et vérifier la version installée.';
 end if;
end $$;
create table if not exists workshop_private.code_backup121(
 signature text primary key,definition text not null,saved_at timestamptz not null default now()
);
alter table workshop_private.code_backup121 enable row level security;
revoke all on workshop_private.code_backup121 from public,anon,authenticated;
insert into workshop_private.code_backup121(signature,definition)
select 'public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)',
 pg_get_functiondef('public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)'::regprocedure)
on conflict(signature)do nothing;

create or replace function public.workshop_update_waste_v60(p_id uuid,p_version integer,p_categories jsonb,p_notes text,p_counts jsonb,p_full boolean,p_expected date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;
begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');
 if not(coalesce((a->>'admin')::boolean,false)or coalesce((a->>'manager')::boolean,false)) then
  raise exception 'Réservé à l’administrateur et aux modérateurs.' using errcode='42501';
 end if;
 perform workshop_private.check_waste_counts(p_categories,p_counts);
 perform workshop_private.check_tyre_status(p_categories,p_full,p_expected);
 if p_notes is null or length(p_notes)>2000 then raise exception 'Précisions invalides.';end if;
 select * into r from public.workshop_waste where id=p_id for update;
 if not found then raise exception 'Demande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée entre-temps. Ferme puis rouvre-la avant de réessayer.';end if;
 if r.provider is distinct from workshop_private.waste_provider(p_categories) then
  raise exception 'Le prestataire ne peut pas être changé : crée une nouvelle demande.';
 end if;
 if r.categories=p_categories and r.notes=btrim(p_notes) and r.bin_counts=p_counts
 and r.is_full is not distinct from p_full and r.full_expected is not distinct from p_expected then return to_jsonb(r);end if;
 select name into person from public.workshop_staff where id=a->>'self';
 -- Une correction ne revalide pas la demande, ne repousse pas son délai et ne la rouvre pas.
 -- Auteur/création, validation, collecte, relances et date annoncée restent intacts.
 update public.workshop_waste set categories=p_categories,notes=btrim(p_notes),bin_counts=p_counts,
 is_full=p_full,full_expected=p_expected,version=version+1,updated_at=now(),updated_name=coalesce(person,a->>'user')
 where id=p_id returning * into r;
 return to_jsonb(r);
end $$;
revoke all on function public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date) from public,anon;
grant execute on function public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date) to authenticated;
notify pgrst,'reload schema';
commit;
