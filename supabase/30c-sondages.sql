-- Après 30b-equipe-invites.sql. Sondage à choix unique ; un vote modifiable par personne.
begin;
create table if not exists public.workshop_polls(id uuid primary key default gen_random_uuid(),title text not null,options jsonb not null,closed boolean not null default false,created_at timestamptz not null default now(),created_by uuid references auth.users(id));
create table if not exists public.workshop_votes(poll_id uuid references public.workshop_polls(id) on delete cascade,user_id uuid references auth.users(id) on delete cascade,choice integer not null,primary key(poll_id,user_id));
alter table public.workshop_polls enable row level security;
alter table public.workshop_votes enable row level security;
revoke all on public.workshop_polls,public.workshop_votes from public,anon,authenticated;
create or replace function public.workshop_poll_list() returns jsonb language plpgsql security definer set search_path='' as $$ declare a jsonb;begin
 a:=workshop_private.actor();if not (a->>'manager')::boolean then raise exception 'Réservé à la gestion.' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(p) order by created_at desc),'[]') from public.workshop_polls p);end $$;
create or replace function public.workshop_poll_create(p_title text,p_options jsonb) returns uuid language plpgsql security definer set search_path='' as $$ declare a jsonb;k jsonb;pid uuid;begin
 a:=workshop_private.actor();if not (a->>'manager')::boolean then raise exception 'Réservé à la gestion.' using errcode='42501';end if;
 if p_title is null or length(trim(p_title)) not between 1 and 200 or p_options is null or jsonb_typeof(p_options)<>'array' then raise exception 'Question ou choix invalides.';end if;
 if jsonb_array_length(p_options) not between 2 and 10 then raise exception 'Prévois entre 2 et 10 réponses.';end if;
 for k in select value from jsonb_array_elements(p_options) loop if jsonb_typeof(k)<>'string' or length(trim(k#>>'{}')) not between 1 and 150 then raise exception 'Réponse invalide.';end if;end loop;
 if (select count(distinct lower(trim(x))) from jsonb_array_elements_text(p_options) x)<>jsonb_array_length(p_options) then raise exception 'Les choix doivent être différents.';end if;
 insert into public.workshop_polls(title,options,created_by) values(trim(p_title),p_options,auth.uid()) returning id into pid;return pid;end $$;
create or replace function public.workshop_poll_get(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$ declare a jsonb;r public.workshop_polls%rowtype;vote integer;begin
 a:=workshop_private.actor_before30();select * into r from public.workshop_polls where id=p_id;if not found then raise exception 'Sondage introuvable.';end if;
 select choice into vote from public.workshop_votes where poll_id=p_id and user_id=auth.uid();
 return to_jsonb(r)-'created_by'||jsonb_build_object('my_vote',vote,'readonly',a->>'role'='guest','can_manage',(a->>'manager')::boolean,'results',case when (a->>'manager')::boolean or vote is not null or r.closed or a->>'role'='guest' then (select coalesce(jsonb_agg(jsonb_build_object('choice',c,'count',(select count(*) from public.workshop_votes where poll_id=p_id and choice=c)) order by c),'[]') from generate_series(0,jsonb_array_length(r.options)-1) c) else '[]'::jsonb end);
 end $$;
create or replace function public.workshop_poll_vote(p_id uuid,p_choice integer) returns void language plpgsql security definer set search_path='' as $$ declare r public.workshop_polls%rowtype;begin
 perform workshop_private.actor();select * into r from public.workshop_polls where id=p_id for update;
 if not found or r.closed then raise exception 'Ce sondage est fermé ou introuvable.';end if;
 if p_choice is null or p_choice<0 or p_choice>=jsonb_array_length(r.options) then raise exception 'Choix invalide.';end if;
 insert into public.workshop_votes(poll_id,user_id,choice) values(p_id,auth.uid(),p_choice) on conflict(poll_id,user_id) do update set choice=excluded.choice;end $$;
create or replace function public.workshop_poll_close(p_id uuid,p_closed boolean) returns void language plpgsql security definer set search_path='' as $$ declare a jsonb;begin
 a:=workshop_private.actor();if not (a->>'manager')::boolean then raise exception 'Réservé à la gestion.' using errcode='42501';end if;
 if p_closed is null then raise exception 'État invalide.';end if;update public.workshop_polls set closed=p_closed where id=p_id;if not found then raise exception 'Sondage introuvable.';end if;end $$;
revoke all on function public.workshop_poll_list(),public.workshop_poll_create(text,jsonb),public.workshop_poll_get(uuid),public.workshop_poll_vote(uuid,integer),public.workshop_poll_close(uuid,boolean) from public,anon,authenticated;
grant execute on function public.workshop_poll_list(),public.workshop_poll_create(text,jsonb),public.workshop_poll_get(uuid),public.workshop_poll_vote(uuid,integer),public.workshop_poll_close(uuid,boolean) to authenticated;
notify pgrst,'reload schema';commit;
