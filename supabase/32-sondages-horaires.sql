-- MAJ32 : après les scripts 30. Réexécutable.
begin;
-- Conserver la confidentialité des anciens sondages : tous restent anonymes.
alter table public.workshop_polls add column if not exists anonymous boolean not null default true;
alter table public.workshop_votes add column if not exists voter_name text;
create or replace function public.workshop_poll_create(p_title text,p_options jsonb,p_anonymous boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare a jsonb;pid uuid;begin
 a:=workshop_private.actor();if p_anonymous is null then raise exception 'Choisis le mode du sondage.';end if;
 if not (a->>'admin')::boolean and not p_anonymous then raise exception 'Seul l’administrateur choisit le mode nominatif.' using errcode='42501';end if;
 pid:=public.workshop_poll_create(p_title,p_options);
 update public.workshop_polls set anonymous=p_anonymous where id=pid;
 return pid;
end $$;
create or replace function public.workshop_poll_anonymity(p_id uuid,p_anonymous boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_polls%rowtype;begin
 a:=workshop_private.actor();if not (a->>'admin')::boolean then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_anonymous is null then raise exception 'Choisis le mode du sondage.';end if;
 select * into r from public.workshop_polls where id=p_id for update;
 if not found then raise exception 'Sondage introuvable.';end if;
 if r.anonymous=p_anonymous then return;end if;
 if exists(select 1 from public.workshop_votes where poll_id=p_id) then raise exception 'Le mode ne peut plus changer après la première réponse. Crée un nouveau sondage.';end if;
 update public.workshop_polls set anonymous=p_anonymous where id=p_id;
end $$;
create or replace function public.workshop_poll_get(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_polls%rowtype;vote integer;answered boolean;begin
 a:=workshop_private.actor_before30();select * into r from public.workshop_polls where id=p_id;if not found then raise exception 'Sondage introuvable.';end if;
 select choice into vote from public.workshop_votes where poll_id=p_id and user_id=auth.uid();
 answered:=exists(select 1 from public.workshop_votes where poll_id=p_id);
 return to_jsonb(r)-'created_by'||jsonb_build_object('my_vote',vote,'readonly',a->>'role'='guest','can_manage',(a->>'manager')::boolean,'can_change_mode',(a->>'admin')::boolean and not answered,
 'responses',case when (a->>'manager')::boolean and not r.anonymous then (select coalesce(jsonb_agg(jsonb_build_object('name',coalesce(v.voter_name,'Collaborateur'),'choice',v.choice) order by v.voter_name,v.user_id),'[]') from public.workshop_votes v where v.poll_id=p_id) else '[]'::jsonb end,
 'results',case when (a->>'manager')::boolean or vote is not null or r.closed or a->>'role'='guest' then (select coalesce(jsonb_agg(jsonb_build_object('choice',c,'count',(select count(*) from public.workshop_votes where poll_id=p_id and choice=c)) order by c),'[]') from generate_series(0,jsonb_array_length(r.options)-1) c) else '[]'::jsonb end);
end $$;
create or replace function public.workshop_poll_vote(p_id uuid,p_choice integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_polls%rowtype;person text;begin
 a:=workshop_private.actor();select * into r from public.workshop_polls where id=p_id for update;
 if not found or r.closed then raise exception 'Ce sondage est fermé ou introuvable.';end if;
 if p_choice is null or p_choice<0 or p_choice>=jsonb_array_length(r.options) then raise exception 'Choix invalide.';end if;
 if not r.anonymous then select name into person from public.workshop_staff where id=a->>'self';person:=coalesce(person,a->>'user');end if;
 insert into public.workshop_votes(poll_id,user_id,choice,voter_name) values(p_id,auth.uid(),p_choice,person) on conflict(poll_id,user_id) do update set choice=excluded.choice,voter_name=excluded.voter_name;
end $$;
create or replace function public.workshop_my_week(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;monday date;begin
 a:=workshop_private.actor_before30();if p_date is null then raise exception 'Choisis une date.';end if;
 monday:=p_date-(extract(isodow from p_date)::integer-1);
 return jsonb_build_object('start',monday,'days',(select jsonb_agg(jsonb_build_object('date',monday+n,'presence',coalesce(d.presence,'unknown'),'slots',coalesce(d.slots,'[]'::jsonb)) order by n) from generate_series(0,6) n left join public.workshop_days d on d.date=monday+n and d.staff_id=a->>'self' and a->>'role'<>'guest'));
end $$;
revoke all on function public.workshop_poll_create(text,jsonb,boolean),public.workshop_poll_anonymity(uuid,boolean),public.workshop_my_week(date) from public,anon,authenticated;
grant execute on function public.workshop_poll_create(text,jsonb,boolean),public.workshop_poll_anonymity(uuid,boolean),public.workshop_my_week(date) to authenticated;
-- Le mode présenté au votant doit toujours correspondre au mode enregistré.
create or replace function public.workshop_poll_vote(p_id uuid,p_choice integer,p_anonymous boolean) returns void language plpgsql security definer set search_path='' as $$
declare r public.workshop_polls%rowtype;begin
 perform workshop_private.actor();select * into r from public.workshop_polls where id=p_id for update;
 if not found then raise exception 'Sondage introuvable.';end if;
 if p_anonymous is distinct from r.anonymous then raise exception 'Le mode du sondage a changé. Actualise le sondage avant de répondre.';end if;
 perform public.workshop_poll_vote(p_id,p_choice);
end $$;
revoke all on function public.workshop_poll_vote(uuid,integer),public.workshop_poll_vote(uuid,integer,boolean) from public,anon,authenticated;
grant execute on function public.workshop_poll_vote(uuid,integer,boolean) to authenticated;
notify pgrst,'reload schema';commit;
