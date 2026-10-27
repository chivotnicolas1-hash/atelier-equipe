-- MAJ58, après MAJ57. Réexécutable.
begin;
alter table public.workshop_leave_requests add column if not exists decided_signature text;
alter table public.workshop_leave_requests add column if not exists edited_at timestamptz;
alter table public.workshop_leave_requests add column if not exists edited_name text;
alter table public.workshop_leave_requests alter column signature drop not null;
alter table public.workshop_leave_requests drop constraint if exists workshop_leave_requests_status_check;
alter table public.workshop_leave_requests add constraint workshop_leave_requests_status_check check(status in ('pending','accepted','refused','proposal','awaiting_signature'));
create or replace function workshop_private.validate_leave(p_first text,p_last text,p_centre text,p_periods jsonb) returns void language plpgsql set search_path='' as $$
declare item jsonb;k text;sd date;ed date;seen text[]:='{}';begin
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
  if r.status not in ('pending','awaiting_signature') then raise exception 'Une demande ayant reçu une réponse ne peut plus être modifiée. Crée une nouvelle demande si nécessaire.';end if;
  if r.version<>p_version then raise exception 'Demande modifiée ailleurs. Actualise la page.';end if;
  update public.workshop_leave_requests set first_name=trim(p_first),last_name=trim(p_last),centre=trim(p_centre),periods=p_periods,signature=sig,signed_at=now(),status='pending',decision_note='',proposal_start=null,proposal_end=null,decided_at=null,decided_name=null,decided_by=null,decided_signature=null,version=version+1 where id=p_id;
 else
  if p_version<>0 then raise exception 'Demande introuvable.';end if;
  insert into public.workshop_leave_requests(id,author_id,staff_id,first_name,last_name,centre,periods,signature) values(p_id,auth.uid(),a->>'self',trim(p_first),trim(p_last),trim(p_centre),p_periods,sig);
 end if;
 select id into recipient from auth.users where lower(email)='nchivot@norauto.fr';
 if recipient is not null then perform workshop_private.message(recipient,'Demande de congé : '||trim(p_first)||' '||trim(p_last),'/?notifications=leave','leave:'||p_id::text||':'||(p_version+1)::text);end if;
end $$;
create or replace function public.workshop_leave_decide(p_id uuid,p_version integer,p_status text,p_note text,p_start date default null,p_end date default null) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_leave_requests%rowtype;v_name text;sig text;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Décision réservée à l’administrateur.' using errcode='42501';end if;
 if p_status is null or p_status not in ('accepted','refused','proposal') or p_note is null or length(trim(p_note))>2000 or (p_status<>'accepted' and length(trim(p_note))=0) then raise exception 'Choisis une décision et précise un motif pour un refus ou une proposition.';end if;
 if p_status='proposal' and (p_start is null or p_end is null or p_end<p_start or p_start<date '2020-01-01' or p_end>date '2100-12-31') then raise exception 'Dates proposées invalides.';end if;
 select * into r from public.workshop_leave_requests where id=p_id for update;if r.id is null then raise exception 'Demande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée ailleurs. Actualise la page.';end if;
 if r.status='awaiting_signature' or r.signature is null then raise exception 'Le collaborateur doit confirmer et signer la demande modifiée.';end if;
 if p_status='accepted' then select signature into sig from public.workshop_signatures where user_id=auth.uid();if sig is null then raise exception 'Enregistre ta signature dans Mon profil avant de valider.';end if;end if;
 select name into v_name from public.workshop_staff where id=a->>'self';
 update public.workshop_leave_requests set status=p_status,decision_note=trim(p_note),proposal_start=case when p_status='proposal' then p_start end,proposal_end=case when p_status='proposal' then p_end end,decided_at=now(),decided_name=v_name,decided_by=auth.uid(),decided_signature=sig,history=history||jsonb_build_array(jsonb_build_object('status',p_status,'note',trim(p_note),'start',case when p_status='proposal' then p_start end,'end',case when p_status='proposal' then p_end end,'at',now(),'by',v_name)),version=version+1 where id=p_id;
 perform workshop_private.message(r.author_id,'Demande de congé : '||case p_status when 'accepted' then 'acceptée' when 'refused' then 'refusée' else 'autre proposition à consulter' end||'.','/?notifications=leave','leave-decision:'||p_id::text||':'||(r.version+1)::text);
end $$;
create or replace function public.workshop_leave_admin_edit(p_id uuid,p_version integer,p_first text,p_last text,p_centre text,p_periods jsonb) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_leave_requests%rowtype;n text;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Modification réservée à l’administrateur.' using errcode='42501';end if;
 perform workshop_private.validate_leave(p_first,p_last,p_centre,p_periods);
 select * into r from public.workshop_leave_requests where id=p_id for update;if r.id is null then raise exception 'Demande introuvable.';end if;
 if r.version is distinct from p_version then raise exception 'Demande modifiée ailleurs. Actualise la page.';end if;
 if (r.first_name,r.last_name,r.centre,r.periods) is not distinct from (trim(p_first),trim(p_last),trim(p_centre),p_periods) then return;end if;
 select name into n from public.workshop_staff where id=a->>'self';
 update public.workshop_leave_requests set first_name=trim(p_first),last_name=trim(p_last),centre=trim(p_centre),periods=p_periods,status='awaiting_signature',signature=null,decided_signature=null,decision_note='',proposal_start=null,proposal_end=null,decided_at=null,decided_name=null,decided_by=null,edited_at=now(),edited_name=n,version=version+1,history=history||jsonb_build_array(jsonb_build_object('status','awaiting_signature','note','Demande modifiée par l’administrateur : nouvelle signature requise.','at',now(),'by',n)) where id=p_id;
 perform workshop_private.message(r.author_id,'Ta demande de congé a été modifiée. Vérifie les informations et signe-la à nouveau.','/?notifications=leave','leave-edit:'||p_id::text||':'||(r.version+1)::text);
end $$;
create or replace function public.workshop_leave_delete(p_id uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_leave_requests%rowtype;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Suppression réservée à l’administrateur.' using errcode='42501';end if;
 select * into r from public.workshop_leave_requests where id=p_id for update;if r.id is null then raise exception 'Demande introuvable.';end if;
 if r.version is distinct from p_version then raise exception 'Demande modifiée ailleurs. Actualise la page.';end if;
 delete from public.workshop_push_queue q using public.workshop_push_subscriptions s,public.workshop_messages m where q.subscription_id=s.id and s.user_id=m.user_id and q.body=m.body and q.url=m.url and q.created_at=m.created_at and q.sent_at is null and m.event_key like 'leave%:'||p_id::text||':%';
 delete from public.workshop_messages where event_key like 'leave%:'||p_id::text||':%';
 delete from public.workshop_leave_requests where id=p_id;
end $$;
-- Conserver les droits historiques hors signalements/consommables.
do $$begin
 if to_regprocedure('public.workshop_list_reports_before58(integer,boolean,text)') is null then alter function public.workshop_list_reports(integer,boolean,text) rename to workshop_list_reports_before58;end if;
 if to_regprocedure('public.workshop_get_report_before58(uuid)') is null then alter function public.workshop_get_report(uuid) rename to workshop_get_report_before58;end if;
 if to_regprocedure('public.workshop_load_before58(date)') is null then alter function public.workshop_load(date) rename to workshop_load_before58;end if;
 if to_regprocedure('public.workshop_screen_info_before58()') is null then alter function public.workshop_screen_info() rename to workshop_screen_info_before58;end if;
end $$;
create or replace function public.workshop_list_reports(p_offset integer default 0,p_own boolean default true,p_search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();return public.workshop_list_reports_before58(p_offset,case when coalesce((a->>'manager')::boolean,false) then p_own else true end,p_search);end $$;
create or replace function public.workshop_get_report(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();if a->>'role'<>'guest' and not coalesce((a->>'manager')::boolean,false) and not exists(select 1 from public.workshop_reports where id=p_id and author_id=auth.uid()) then raise exception 'Signalement inaccessible.' using errcode='42501';end if;
 return public.workshop_get_report_before58(p_id);
end $$;
create or replace function public.workshop_load(p_date date default current_date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;result jsonb;begin
 a:=workshop_private.actor_before30();
 if a->>'role'<>'guest' and exists(select 1 from public.workshop_staff s where s.id=a->>'self' and s.active and lower(trim(coalesce(s.team,'')))='encadrants') then
  update public.workshop_days set confirmed=now() where staff_id=a->>'self' and date=(now() at time zone 'Europe/Paris')::date and presence='present' and jsonb_array_length(slots)>0 and confirmed is null;
 end if;
 result:=public.workshop_load_before58(p_date);return result||jsonb_build_object('reports_all',coalesce((a->>'manager')::boolean,false));
end $$;
create or replace function public.workshop_screen_info() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 result:=public.workshop_screen_info_before58();
 return result||jsonb_build_object('announcement',(select jsonb_build_object('message',message,'enabled',enabled,'audience',audience,'link_url',link_url,'link_label',link_label) from public.workshop_announcement where id=1 and enabled and audience<>'encadrants'));
end $$;
revoke all on function workshop_private.validate_leave(text,text,text,jsonb),public.workshop_leave_admin_edit(uuid,integer,text,text,text,jsonb),public.workshop_leave_delete(uuid,integer),public.workshop_list_reports_before58(integer,boolean,text),public.workshop_get_report_before58(uuid),public.workshop_load_before58(date),public.workshop_screen_info_before58(),public.workshop_list_reports(integer,boolean,text),public.workshop_get_report(uuid),public.workshop_load(date),public.workshop_screen_info() from public,anon,authenticated;
grant execute on function public.workshop_leave_admin_edit(uuid,integer,text,text,text,jsonb),public.workshop_leave_delete(uuid,integer),public.workshop_list_reports(integer,boolean,text),public.workshop_get_report(uuid),public.workshop_load(date),public.workshop_screen_info() to authenticated;
notify pgrst,'reload schema';commit;
