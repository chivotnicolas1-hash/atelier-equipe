-- MAJ33 : après 32-sondages-horaires.sql. Réexécutable.
begin;
alter table public.workshop_votes add column if not exists response_id uuid not null default gen_random_uuid();
create unique index if not exists workshop_response_unique on public.workshop_votes(response_id);
alter table public.workshop_votes add column if not exists version integer not null default 1;
alter table public.workshop_votes add column if not exists corrected_name text;
alter table public.workshop_votes add column if not exists corrected_at timestamptz;
alter table public.workshop_polls add column if not exists has_received_votes boolean not null default false;
update public.workshop_polls p set has_received_votes=true where not has_received_votes and exists(select 1 from public.workshop_votes where poll_id=p.id);
alter table public.workshop_custom_buttons add column if not exists color text check(color is null or color ~ '^#[0-9a-fA-F]{6}$');
create or replace function public.workshop_save_button(p_id uuid,p_label text,p_url text,p_audience text,p_enabled boolean,p_position integer,p_color text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 perform workshop_private.actor();if p_color is not null and p_color !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Couleur invalide : format HEX #RRGGBB attendu.';end if;
 result:=public.workshop_save_button(p_id,p_label,p_url,p_audience,p_enabled,p_position);
 update public.workshop_custom_buttons set color=lower(p_color) where id=(result->>'id')::uuid;
 return result;end $$;

create or replace function public.workshop_poll_get(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_polls%rowtype;vote integer;answered boolean;begin
 a:=workshop_private.actor_before30();select * into r from public.workshop_polls where id=p_id;if not found then raise exception 'Sondage introuvable.';end if;
 select choice into vote from public.workshop_votes where poll_id=p_id and user_id=auth.uid();
 answered:=r.has_received_votes;
 return to_jsonb(r)-'created_by'||jsonb_build_object('my_vote',vote,'my_correction',(select jsonb_build_object('name',v.corrected_name,'at',v.corrected_at) from public.workshop_votes v where v.poll_id=p_id and v.user_id=auth.uid() and v.corrected_at is not null),'readonly',a->>'role'='guest','can_manage',(a->>'manager')::boolean,'can_change_mode',(a->>'admin')::boolean and not answered,
 'responses',case when (a->>'manager')::boolean and not r.anonymous then (select coalesce(jsonb_agg(jsonb_build_object('id',v.response_id,'version',v.version,'name',coalesce(v.voter_name,'Collaborateur'),'choice',v.choice,'corrected_name',v.corrected_name,'corrected_at',v.corrected_at) order by v.voter_name,v.user_id),'[]') from public.workshop_votes v where v.poll_id=p_id) else '[]'::jsonb end,
 'results',case when (a->>'manager')::boolean or vote is not null or r.closed or a->>'role'='guest' then (select coalesce(jsonb_agg(jsonb_build_object('choice',c,'count',(select count(*) from public.workshop_votes where poll_id=p_id and choice=c)) order by c),'[]') from generate_series(0,jsonb_array_length(r.options)-1) c) else '[]'::jsonb end);
end $$;
create or replace function public.workshop_poll_vote(p_id uuid,p_choice integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_polls%rowtype;person text;begin
 a:=workshop_private.actor();select * into r from public.workshop_polls where id=p_id for update;
 if not found or r.closed then raise exception 'Ce sondage est fermé ou introuvable.';end if;
 if p_choice is null or p_choice<0 or p_choice>=jsonb_array_length(r.options) then raise exception 'Choix invalide.';end if;
 if not r.anonymous then select name into person from public.workshop_staff where id=a->>'self';person:=coalesce(person,a->>'user');end if;
 insert into public.workshop_votes(poll_id,user_id,choice,voter_name) values(p_id,auth.uid(),p_choice,person) on conflict(poll_id,user_id) do update set choice=excluded.choice,voter_name=excluded.voter_name,version=workshop_votes.version+1,corrected_name=null,corrected_at=null;
 update public.workshop_polls set has_received_votes=true where id=p_id;
end $$;

create or replace function public.workshop_poll_anonymity(p_id uuid,p_anonymous boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_polls%rowtype;begin
 a:=workshop_private.actor();if not (a->>'admin')::boolean then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_anonymous is null then raise exception 'Choisis le mode du sondage.';end if;
 select * into r from public.workshop_polls where id=p_id for update;
 if not found then raise exception 'Sondage introuvable.';end if;
 if r.anonymous=p_anonymous then return;end if;
 if r.has_received_votes then raise exception 'Le mode ne peut plus changer après la première réponse. Crée un nouveau sondage.';end if;
 update public.workshop_polls set anonymous=p_anonymous where id=p_id;
end $$;

create or replace function public.workshop_poll_response(p_response uuid,p_version integer,p_choice integer,p_delete boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;v public.workshop_votes%rowtype;r public.workshop_polls%rowtype;person text;begin
 a:=workshop_private.actor();if not (a->>'manager')::boolean then raise exception 'Réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_delete is null then raise exception 'Action invalide.';end if;
 select * into v from public.workshop_votes where response_id=p_response;
 if not found then raise exception 'Réponse introuvable. Actualise le sondage.';end if;
 select * into r from public.workshop_polls where id=v.poll_id for update;
 if not found then raise exception 'Sondage introuvable.';end if;
 if r.anonymous then raise exception 'Les réponses anonymes ne peuvent pas être modifiées individuellement.' using errcode='42501';end if;
 select * into v from public.workshop_votes where response_id=p_response for update;
 if not found or p_version is distinct from v.version then raise exception 'Réponse modifiée entre-temps. Actualise le sondage.';end if;
 if p_delete then delete from public.workshop_votes where response_id=p_response;return;end if;
 if p_choice is null or p_choice<0 or p_choice>=jsonb_array_length(r.options) then raise exception 'Choix invalide.';end if;
 if v.choice=p_choice then return;end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_votes set choice=p_choice,version=version+1,corrected_name=coalesce(person,a->>'user'),corrected_at=now() where response_id=p_response;
end $$;
create or replace function public.workshop_poll_delete(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();if not (a->>'manager')::boolean then raise exception 'Réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 delete from public.workshop_polls where id=p_id;
 if not found then raise exception 'Sondage introuvable ou déjà supprimé.';end if;
 -- Masquer les raccourcis qui ciblent exactement le sondage supprimé.
 update public.workshop_custom_buttons set enabled=false,updated_at=now() where url ~ ('[?&]poll='||p_id::text||'([&#]|$)');
end $$;
revoke all on function public.workshop_save_button(uuid,text,text,text,boolean,integer,text),public.workshop_poll_response(uuid,integer,integer,boolean),public.workshop_poll_delete(uuid) from public,anon,authenticated;
grant execute on function public.workshop_save_button(uuid,text,text,text,boolean,integer,text),public.workshop_poll_response(uuid,integer,integer,boolean),public.workshop_poll_delete(uuid) to authenticated;
notify pgrst,'reload schema';commit;
