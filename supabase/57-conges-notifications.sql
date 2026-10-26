-- MAJ57, après la MAJ56. Réexécutable.
begin;
-- Enregistrement atomique de la fiche et de ses informations administratives.
create or replace function public.workshop_staff_save(p jsonb,p_job text,p_birth date,p_job_version integer,p_birth_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p->>'action' is distinct from 'staff' or p->>'id' is null then raise exception 'Fiche existante requise.';end if;
 perform public.workshop_mutate(p);
 if p_job_version>=0 then perform public.workshop_admin_job(p->>'id',p_job,p_job_version);
 elsif p_job_version is distinct from -1 or exists(select 1 from public.workshop_staff s join auth.users u on lower(u.email)=s.email where s.id=p->>'id') then raise exception 'Recharge la fiche pour modifier la fonction.';end if;
 perform public.workshop_admin_birthday_save(p->>'id',p_birth,p_birth_version);
end $$;
-- Les modifications de tâches restent visibles dans la boîte de réception,
-- mais ne produisent plus de push immédiat. Les annonces ne changent pas.
create or replace function workshop_private.enqueue_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_TABLE_NAME='workshop_announcement' then
  if not new.enabled then return new;end if;
  if TG_OP='UPDATE' then if old.enabled and (new.message,new.link_url,new.link_label,new.audience) is not distinct from (old.message,old.link_url,old.link_label,old.audience) then return new;end if;end if;
  delete from public.workshop_push_queue where kind='announcement';
  insert into public.workshop_push_queue(subscription_id,kind) select p.id,'announcement' from public.workshop_push_subscriptions p where workshop_private.announcement_matches(p.user_id,new.audience);
 end if;return new;
end $$;
delete from public.workshop_push_queue where kind='task' and sent_at is null;
do $$begin if to_regprocedure('workshop_private.schedule_messages_before57(timestamptz)') is null then alter function workshop_private.schedule_messages(timestamptz) rename to schedule_messages_before57;end if;end $$;
create or replace function workshop_private.schedule_messages(p_now timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare d date:=(p_now at time zone 'Europe/Paris')::date;r record;v_body text;
begin
 if p_now is null then return;end if;
 perform workshop_private.schedule_messages_before57(p_now);
 for r in select s.id staff_id,u.id user_id,((d::text||' '||b.start)::timestamp at time zone 'Europe/Paris') starts,(select count(*) from public.workshop_tasks t where t.staff_id=s.id and t.done=0) n
 from public.workshop_days dy join public.workshop_staff s on s.id=dy.staff_id and s.active and s.role<>'guest' join auth.users u on lower(u.email)=s.email
 cross join lateral(select min(x->>'start') start from jsonb_array_elements(dy.slots)x)b
 where dy.date=d and dy.presence='present' and b.start is not null loop
  if r.n>0 and p_now>=r.starts and p_now<r.starts+interval '5 minutes' then
   v_body:='Prise de poste : '||r.n||case when r.n=1 then ' tâche à consulter.' else ' tâches à consulter.' end;
   perform workshop_private.message(r.user_id,v_body,'/?notifications=tasks','task-start:'||d::text);
   update public.workshop_push_queue q set expires_at=r.starts+interval '5 minutes' from public.workshop_push_subscriptions sub where q.subscription_id=sub.id and sub.user_id=r.user_id and q.sent_at is null and q.kind='message' and q.body=v_body and q.url='/?notifications=tasks' and q.created_at>=date_trunc('day',p_now at time zone 'Europe/Paris') at time zone 'Europe/Paris';
  end if;
 end loop;
end $$;
revoke all on function workshop_private.schedule_messages_before57(timestamptz),workshop_private.schedule_messages(timestamptz),workshop_private.enqueue_push() from public,anon,authenticated;
-- Demandes privées : auteur et administrateur uniquement.
create table if not exists public.workshop_leave_requests(
 id uuid primary key,author_id uuid not null references auth.users(id),staff_id text not null references public.workshop_staff(id),
 first_name text not null,last_name text not null,centre text not null,periods jsonb not null,
 signature text not null,created_at timestamptz not null default now(),signed_at timestamptz not null default now(),
 status text not null default 'pending' check(status in ('pending','accepted','refused','proposal')),
 decision_note text not null default '',proposal_start date,proposal_end date,decided_at timestamptz,decided_name text,decided_by uuid references auth.users(id),
 history jsonb not null default '[]',version integer not null default 1
);
alter table public.workshop_leave_requests enable row level security;
revoke all on public.workshop_leave_requests from public,anon,authenticated;
create or replace function public.workshop_leave_list(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();if a->>'role'='guest' then raise exception 'Indisponible en mode invité.' using errcode='42501';end if;
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return (select coalesce(jsonb_agg(v order by v.created_at desc),'[]') from (select id,first_name,last_name,centre,periods,status,created_at,signed_at,decision_note,proposal_start,proposal_end,decided_at,decided_name,version,author_id=auth.uid() own from public.workshop_leave_requests where author_id=auth.uid() or coalesce((a->>'admin')::boolean,false) order by created_at desc limit 30 offset p_offset)v);
end $$;
create or replace function public.workshop_leave_get(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_leave_requests%rowtype;begin
 a:=workshop_private.actor();select * into r from public.workshop_leave_requests where id=p_id;
 if a->>'role'='guest' or r.id is null or not (r.author_id=auth.uid() or coalesce((a->>'admin')::boolean,false)) then raise exception 'Demande inaccessible.' using errcode='42501';end if;
 return to_jsonb(r)-'author_id'-'staff_id'-'decided_by';
end $$;
create or replace function public.workshop_leave_save(p_id uuid,p_first text,p_last text,p_centre text,p_periods jsonb,p_version integer,p_certified boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_leave_requests%rowtype;item jsonb;k text;sd date;ed date;sig text;recipient uuid;seen text[]:='{}';
begin
 a:=workshop_private.actor();if a->>'role'='guest' or a->>'self' is null then raise exception 'Compte collaborateur requis.' using errcode='42501';end if;
 if p_certified is distinct from true or p_id is null or p_version is null then raise exception 'Confirme la demande et l’apposition de ta signature.';end if;
 if p_first is null or length(trim(p_first)) not between 1 and 60 or p_last is null or length(trim(p_last)) not between 1 and 80 or p_centre is null or length(trim(p_centre)) not between 1 and 100 then raise exception 'Prénom, nom et centre requis.';end if;
 if jsonb_typeof(p_periods) is distinct from 'array' or jsonb_array_length(p_periods) not between 1 and 10 then raise exception 'Renseigne au moins une période (10 maximum).';end if;
 for item in select * from jsonb_array_elements(p_periods) loop
  k:=item->>'kind';if k is null or k not in ('cp2','cp1','unpaid','rtt','fraction','marriage','birth','death','parent','other') or k=any(seen) then raise exception 'Motif invalide ou en double.';end if;seen:=array_append(seen,k);
  if coalesce(item->>'start','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(item->>'end','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Dates requises.';end if;
  sd:=(item->>'start')::date;ed:=(item->>'end')::date;
  if sd<date '2020-01-01' or ed>date '2100-12-31' or ed<sd or ed-sd>366 then raise exception 'Période invalide (366 jours maximum).';end if;
  if k in ('cp2','cp1','unpaid') and (coalesce(item->>'rest','') !~ '^\d{1,3}$' or (item->>'rest')::integer>ed-sd+1) then raise exception 'Nombre de jours de repos invalide.';end if;
  if length(coalesce(item->>'detail',''))>150 or (k='other' and length(trim(coalesce(item->>'detail','')))=0) then raise exception 'Précise le motif (150 caractères maximum).';end if;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('leave:'||p_id::text,0));select * into r from public.workshop_leave_requests where id=p_id for update;
 if r.id is not null and r.author_id<>auth.uid() then raise exception 'Seul l’auteur peut modifier sa demande.' using errcode='42501';end if;
 select signature into sig from public.workshop_signatures where user_id=auth.uid();if sig is null then raise exception 'Enregistre d’abord ta signature dans Mon profil.';end if;
 if r.id is not null then
  if r.author_id<>auth.uid() then raise exception 'Seul l’auteur peut modifier sa demande.' using errcode='42501';end if;
  if r.status<>'pending' then raise exception 'Une demande ayant reçu une réponse ne peut plus être modifiée. Crée une nouvelle demande si nécessaire.';end if;
  if r.version<>p_version then raise exception 'Demande modifiée ailleurs. Actualise la page.';end if;
  update public.workshop_leave_requests set first_name=trim(p_first),last_name=trim(p_last),centre=trim(p_centre),periods=p_periods,signature=sig,signed_at=now(),version=version+1 where id=p_id;
 else
  if p_version<>0 then raise exception 'Demande introuvable.';end if;
  insert into public.workshop_leave_requests(id,author_id,staff_id,first_name,last_name,centre,periods,signature) values(p_id,auth.uid(),a->>'self',trim(p_first),trim(p_last),trim(p_centre),p_periods,sig);
 end if;
 select id into recipient from auth.users where lower(email)='nchivot@norauto.fr';
 if recipient is not null then perform workshop_private.message(recipient,'Demande de congé : '||trim(p_first)||' '||trim(p_last),'/?notifications=leave','leave:'||p_id::text||':'||(p_version+1)::text);end if;
end $$;
create or replace function public.workshop_leave_decide(p_id uuid,p_version integer,p_status text,p_note text,p_start date default null,p_end date default null) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_leave_requests%rowtype;v_name text;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Décision réservée à l’administrateur.' using errcode='42501';end if;
 if p_status is null or p_status not in ('accepted','refused','proposal') or p_note is null or length(trim(p_note))>2000 or (p_status<>'accepted' and length(trim(p_note))=0) then raise exception 'Choisis une décision et précise un motif pour un refus ou une proposition.';end if;
 if p_status='proposal' and (p_start is null or p_end is null or p_end<p_start or p_start<date '2020-01-01' or p_end>date '2100-12-31') then raise exception 'Dates proposées invalides.';end if;
 select * into r from public.workshop_leave_requests where id=p_id for update;if r.id is null then raise exception 'Demande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée ailleurs. Actualise la page.';end if;
 select name into v_name from public.workshop_staff where id=a->>'self';
 update public.workshop_leave_requests set status=p_status,decision_note=trim(p_note),proposal_start=case when p_status='proposal' then p_start end,proposal_end=case when p_status='proposal' then p_end end,decided_at=now(),decided_name=v_name,decided_by=auth.uid(),history=history||jsonb_build_array(jsonb_build_object('status',p_status,'note',trim(p_note),'start',case when p_status='proposal' then p_start end,'end',case when p_status='proposal' then p_end end,'at',now(),'by',v_name)),version=version+1 where id=p_id;
 perform workshop_private.message(r.author_id,'Demande de congé : '||case p_status when 'accepted' then 'acceptée' when 'refused' then 'refusée' else 'autre proposition à consulter' end||'.','/?notifications=leave','leave-decision:'||p_id::text||':'||(r.version+1)::text);
end $$;
revoke all on function public.workshop_staff_save(jsonb,text,date,integer,integer),public.workshop_leave_list(integer),public.workshop_leave_get(uuid),public.workshop_leave_save(uuid,text,text,text,jsonb,integer,boolean),public.workshop_leave_decide(uuid,integer,text,text,date,date) from public,anon,authenticated;
grant execute on function public.workshop_staff_save(jsonb,text,date,integer,integer),public.workshop_leave_list(integer),public.workshop_leave_get(uuid),public.workshop_leave_save(uuid,text,text,text,jsonb,integer,boolean),public.workshop_leave_decide(uuid,integer,text,text,date,date) to authenticated;
notify pgrst,'reload schema';commit;
