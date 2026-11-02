begin;
create table if not exists workshop_private.quality_link70(id integer primary key check(id=1),url text not null);
revoke all on workshop_private.quality_link70 from public, anon, authenticated;
alter table workshop_private.quality_link70 enable row level security;
create or replace function public.workshop_quality_link70(p_url text default null) returns text language plpgsql security definer set search_path='' as $$
declare a jsonb;link text;begin a:=workshop_private.actor();
if not coalesce((a->>'manager')::boolean,false) then raise exception 'Accès réservé aux gestionnaires';end if;
if p_url is not null then
 if length(p_url)>2048 or p_url !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?([/?#][^[:space:]]*)?$' then raise exception 'Lien HTTPS invalide';end if;
 insert into workshop_private.quality_link70 values(1,p_url) on conflict(id) do update set url=excluded.url;
end if;
select url into link from workshop_private.quality_link70 where id=1;
if link is null then link:=public.workshop_quality_form()->>'url';end if;
return coalesce(link,'');end $$;
create or replace function public.workshop_lunch_candidates70(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if a->>'role'='guest' then raise exception 'Lecture seule';end if;
return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'slots',d.slots) order by s.name),'[]') from public.workshop_staff s join public.workshop_days d on d.staff_id=s.id and d.date=p_date join auth.users u on lower(u.email)=lower(s.email) where s.active and not s.suspended and s.role<>'guest' and d.presence='present' and jsonb_array_length(d.slots)>0 and u.id<>auth.uid());end $$;
create or replace function public.workshop_lunch_candidates(p_date date) returns jsonb language sql security definer set search_path='' as $$select public.workshop_lunch_candidates70(p_date)$$;
create or replace function public.workshop_lunch_send70(p_id uuid,p_date date,p_bt text,p_remaining text,p_version integer,p_assigned text) returns void language plpgsql security definer set search_path='' as $$
declare prev text;recipient record;dest text;begin
if p_assigned is not null and not exists(select 1 from jsonb_array_elements(public.workshop_lunch_candidates70(p_date)) x where x->>'id'=p_assigned) then raise exception 'Choisis un collaborateur présent à la date indiquée.';end if;
select to_jsonb(h)->>'assigned_staff' into prev from public.workshop_lunch_handoffs h where id=p_id for update;
-- Réutilise les contrôles de droits, de date et de version du formulaire existant.
perform public.workshop_lunch_save_v63(p_id,p_date,p_bt,p_remaining,p_version,p_assigned);
dest:='/?notifications=lunch&date='||p_date::text;
for recipient in select distinct u.id,s.id as staff from auth.users u left join public.workshop_staff s on lower(s.email)=lower(u.email) and s.active where u.id<>auth.uid() and (lower(u.email)='nchivot@norauto.fr' or s.role='moderator' or lower(s.team)='encadrants' or s.id=p_assigned) loop
if (p_version=0 or (recipient.staff=p_assigned and prev is distinct from p_assigned)) and not exists(select 1 from public.workshop_messages m where m.user_id=recipient.id and m.url=dest and m.created_at>=transaction_timestamp() and m.body like '%'||trim(p_bt)||'%') then
perform workshop_private.message(recipient.id,'BT à reprendre : '||trim(p_bt),dest,'bt70:'||p_id::text||':'||p_version::text);end if;end loop;end $$;
create or replace function public.workshop_lunch_list70(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; rows jsonb;begin a:=workshop_private.actor();rows:=public.workshop_lunch_list(p_date);
if exists(select 1 from public.workshop_staff where id=a->>'self' and active and lower(team)='encadrants' and role<>'guest') then
rows:=rows||(select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'date',h.date,'bt',h.bt,'remaining',h.remaining,'version',h.version,'author_name',s.name,'created_at',h.created_at,'taken_at',h.taken_at,'taken_name',h.taken_name,'assigned_staff',(to_jsonb(h)->>'assigned_staff'),'assigned_name',t.name,'own',false,'can_take',false) order by h.created_at desc),'[]') from public.workshop_lunch_handoffs h left join public.workshop_staff s on s.id=h.staff_id left join public.workshop_staff t on t.id=(to_jsonb(h)->>'assigned_staff') where h.date=p_date and not exists(select 1 from jsonb_array_elements(rows) x where x->>'id'=h.id::text));end if;return rows;end $$;
revoke all on function public.workshop_quality_link70(text),public.workshop_lunch_candidates70(date),public.workshop_lunch_send70(uuid,date,text,text,integer,text),public.workshop_lunch_list70(date) from public,anon;
grant execute on function public.workshop_quality_link70(text),public.workshop_lunch_candidates70(date),public.workshop_lunch_send70(uuid,date,text,text,integer,text),public.workshop_lunch_list70(date) to authenticated;
notify pgrst,'reload schema';commit;
