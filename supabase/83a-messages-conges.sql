begin;
create or replace function workshop_private.manage83() returns boolean language plpgsql security definer set search_path='' as $$declare a jsonb;begin a:=workshop_private.actor();return coalesce((a->>'admin')::boolean,false) or coalesce(a->>'role'='moderator',false);end $$;
create or replace function workshop_private.encadrant83() returns boolean language plpgsql security definer set search_path='' as $$declare a jsonb;begin a:=workshop_private.actor();return coalesce((a->>'admin')::boolean,false) or exists(select 1 from public.workshop_staff where id=a->>'self' and active and lower(trim(team))='encadrants' and role<>'guest');end $$;
create table if not exists workshop_private.scheduled83(id uuid primary key,author_id uuid not null,author_name text not null,recipients uuid[] not null,body text not null,due_at timestamptz not null,sent_at timestamptz,version int not null default 1,created_at timestamptz not null default now());
alter table workshop_private.scheduled83 enable row level security;revoke all on workshop_private.scheduled83 from public,anon,authenticated;
create or replace function public.workshop_scheduled83() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not workshop_private.encadrant83() then raise exception 'Réservé aux encadrants.' using errcode='42501';end if;
 return jsonb_build_object('people',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',s.name) order by s.name),'[]') from auth.users u join public.workshop_staff s on lower(s.email)=lower(u.email) where s.active and (lower(trim(s.team))='encadrants' or lower(u.email)='nchivot@norauto.fr') and coalesce(s.role,'employee')<>'guest'),
 'items',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('own',author_id=auth.uid()) order by due_at desc),'[]') from workshop_private.scheduled83 x where author_id=auth.uid() or (auth.uid()=any(recipients) and sent_at is not null)));
end $$;
create or replace function public.workshop_schedule83(p_id uuid,p_body text,p_recipients uuid[],p_local text,p_version int default 0,p_delete boolean default false) returns void language plpgsql security definer set search_path='' as $$declare r workshop_private.scheduled83%rowtype;due timestamptz;n text;begin
 if not workshop_private.encadrant83() then raise exception 'Réservé aux encadrants.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('scheduled83:'||p_id,0));select * into r from workshop_private.scheduled83 where id=p_id for update;
 if found and (r.author_id<>auth.uid() or r.sent_at is not null) then raise exception 'Seul l’auteur peut modifier un message non envoyé.';end if;
 if coalesce(r.version,0) is distinct from p_version then raise exception 'Le message a changé. Rouvre-le.';end if;
 if p_delete then delete from workshop_private.scheduled83 where id=p_id and author_id=auth.uid() and sent_at is null;return;end if;
 due:=p_local::timestamp at time zone 'Europe/Paris';
 if due is null or due<=now() or length(trim(coalesce(p_body,''))) not between 1 and 500 or coalesce(cardinality(p_recipients),0)<1 then raise exception 'Indique un message, des destinataires et une date future.';end if;
 if exists(select 1 from unnest(p_recipients) u where not exists(select 1 from auth.users au join public.workshop_staff s on lower(s.email)=lower(au.email) where au.id=u and s.active and coalesce(s.role,'employee')<>'guest' and (lower(trim(s.team))='encadrants' or lower(au.email)='nchivot@norauto.fr'))) then raise exception 'Destinataire non autorisé.';end if;
 select name into n from public.workshop_staff where id=workshop_private.actor()->>'self';
 insert into workshop_private.scheduled83 values(p_id,auth.uid(),coalesce(n,'Encadrant'),p_recipients,trim(p_body),due,null,1,now()) on conflict(id) do update set body=excluded.body,recipients=excluded.recipients,due_at=excluded.due_at,version=workshop_private.scheduled83.version+1;
end $$;
do $$begin if to_regprocedure('workshop_private.schedule_messages_before83(timestamptz)') is null then alter function workshop_private.schedule_messages(timestamptz) rename to schedule_messages_before83;end if;end $$;
create or replace function workshop_private.schedule_messages(p_now timestamptz) returns void language plpgsql security definer set search_path='' as $$declare r record;u uuid;begin
 perform workshop_private.schedule_messages_before83(p_now);
 for r in select * from workshop_private.scheduled83 where sent_at is null and due_at<=p_now order by due_at for update skip locked loop
  foreach u in array r.recipients loop
   if exists(select 1 from auth.users au join public.workshop_staff s on lower(s.email)=lower(au.email) where au.id=u and s.active and coalesce(s.role,'employee')<>'guest' and (lower(trim(s.team))='encadrants' or lower(au.email)='nchivot@norauto.fr')) then perform workshop_private.message(u,r.author_name||' : '||r.body,'/?notifications=inbox','scheduled83:'||r.id);end if;
  end loop;
  update workshop_private.scheduled83 set sent_at=p_now,version=version+1 where id=r.id;
 end loop;
end $$;
create or replace function workshop_private.signature_notice83() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.signature is not null and new.signature is null and new.invalidated_at is distinct from old.invalidated_at then perform workshop_private.message(new.user_id,'Signature non conforme, merci de renouveler','/?notifications=inbox','signature83:'||new.user_id||':'||new.version);end if;return new;
end $$;
drop trigger if exists signature_notice83 on public.workshop_signatures;
create trigger signature_notice83 after update on public.workshop_signatures for each row execute function workshop_private.signature_notice83();
create or replace function public.workshop_leave_calendar83(p_month date) returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;start_d date:=date_trunc('month',p_month)::date;end_d date:=(start_d+interval '1 month')::date;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Calendrier réservé à l’administrateur.' using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',first_name||' '||last_name,'status',status,'periods',periods) order by last_name,first_name),'[]') from public.workshop_leave_requests l where exists(select 1 from jsonb_array_elements(l.periods) p where (p->>'start')::date<end_d and (p->>'end')::date>=start_d));
end $$;
create or replace function workshop_private.leave_identity83() returns trigger language plpgsql security definer set search_path='' as $$declare a jsonb;n text;parts text[];begin
 a:=workshop_private.actor();if coalesce((a->>'admin')::boolean,false) then return new;end if;
 if tg_op='UPDATE' then new.first_name:=old.first_name;new.last_name:=old.last_name;new.centre:=old.centre;return new;end if;
 select name into n from public.workshop_staff where id=a->>'self' and active;if n is null then raise exception 'Profil introuvable.';end if;
 parts:=regexp_split_to_array(trim(n),'\s+');
 select string_agg(w,' ' order by ord) filter(where w<>upper(w)),string_agg(w,' ' order by ord) filter(where w=upper(w)) into new.first_name,new.last_name from unnest(parts) with ordinality x(w,ord);
 if new.first_name is null or new.last_name is null then new.first_name:=parts[1];new.last_name:=array_to_string(parts[2:cardinality(parts)],' ');end if;
 new.centre:='Norauto Fayet · Centre 0033';return new;
end $$;
drop trigger if exists leave_identity83 on public.workshop_leave_requests;
create trigger leave_identity83 before insert or update on public.workshop_leave_requests for each row execute function workshop_private.leave_identity83();
revoke all on function workshop_private.manage83(),workshop_private.encadrant83(),workshop_private.signature_notice83(),workshop_private.leave_identity83(),workshop_private.schedule_messages(timestamptz),workshop_private.schedule_messages_before83(timestamptz) from public,anon,authenticated;
revoke all on function public.workshop_scheduled83(),public.workshop_schedule83(uuid,text,uuid[],text,int,boolean),public.workshop_leave_calendar83(date) from public,anon;
grant execute on function public.workshop_scheduled83(),public.workshop_schedule83(uuid,text,uuid[],text,int,boolean),public.workshop_leave_calendar83(date) to authenticated;
do $$begin
 if to_regprocedure('public.workshop_signature_gate_before83()') is null then alter function public.workshop_signature_gate() rename to workshop_signature_gate_before83;end if;
 if to_regprocedure('public.workshop_required_buttons_before83()') is null then alter function public.workshop_required_buttons() rename to workshop_required_buttons_before83;end if;
end $$;
create or replace function public.workshop_signature_gate() returns jsonb language plpgsql security definer set search_path='' as $$begin if workshop_private.actor_before30()->>'role'='guest' then return '{"required":false,"admin":false}'::jsonb;end if;return public.workshop_signature_gate_before83();end $$;
create or replace function public.workshop_required_buttons() returns jsonb language plpgsql security definer set search_path='' as $$begin if workshop_private.actor_before30()->>'role'='guest' then return '[]'::jsonb;end if;return public.workshop_required_buttons_before83();end $$;
revoke all on function public.workshop_signature_gate_before83(),public.workshop_required_buttons_before83() from public,anon,authenticated;
revoke all on function public.workshop_signature_gate(),public.workshop_required_buttons() from public,anon;
grant execute on function public.workshop_signature_gate(),public.workshop_required_buttons() to authenticated;
notify pgrst,'reload schema';commit;
