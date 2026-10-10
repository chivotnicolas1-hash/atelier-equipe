-- Mise à jour 07 : appliquer après 06. Profils privés et annonce commune.
begin;
create table if not exists public.workshop_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 photo text check(photo is null or (length(photo)<=90000 and photo ~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$')),
 updated_at timestamptz not null default now()
);
create table if not exists public.workshop_announcement (
 id integer primary key check(id=1),
 message text not null default '' check(length(message)<=1000),
 enabled boolean not null default false,
 updated_at timestamptz not null default now(),
 check(not enabled or length(trim(message))>0)
);
insert into public.workshop_announcement(id) values(1) on conflict(id) do nothing;
alter table public.workshop_profiles enable row level security;
alter table public.workshop_announcement enable row level security;
revoke all on public.workshop_profiles,public.workshop_announcement from public,anon,authenticated;
create or replace function public.workshop_save_profile(p_photo text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform workshop_private.actor();
 if p_photo is not null and (length(p_photo)>90000 or p_photo !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$') then
  raise exception 'Photo invalide : utilise une image JPEG, PNG ou WebP depuis le formulaire.';
 end if;
 insert into public.workshop_profiles(user_id,photo) values(auth.uid(),p_photo)
 on conflict(user_id) do update set photo=excluded.photo,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_save_profile(text) from public,anon,authenticated;
grant execute on function public.workshop_save_profile(text) to authenticated;
create or replace function public.workshop_save_announcement(p_message text,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin
 a:=workshop_private.actor();
 if (a->>'admin')::boolean is not true then raise exception 'Seul l’administrateur peut modifier l’annonce.' using errcode='42501';end if;
 if p_message is null or p_enabled is null or length(p_message)>1000 or (p_enabled and length(trim(p_message))=0) then raise exception 'Renseigne une annonce de 1 à 1000 caractères avant de l’activer.';end if;
 update public.workshop_announcement set message=trim(p_message),enabled=p_enabled,updated_at=now() where id=1;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_save_announcement(text,boolean) from public,anon,authenticated;
grant execute on function public.workshop_save_announcement(text,boolean) to authenticated;
create or replace function public.workshop_load(p_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; v_staff jsonb; v_days jsonb; v_tasks jsonb;
begin
 a:=workshop_private.actor(); v_admin:=(a->>'admin')::boolean;
 if p_date is null then raise exception 'Choisis une date.'; end if;
 select coalesce(jsonb_agg(case when v_admin then to_jsonb(s) else jsonb_build_object('id',s.id,'name',s.name,'team',s.team) end order by s.id),'[]'::jsonb)
 into v_staff from public.workshop_staff s where s.active;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.staff_id),'[]'::jsonb) into v_days
 from public.workshop_days d where d.date=p_date and exists(select 1 from public.workshop_staff s where s.id=d.staff_id and s.active);
 select coalesce(jsonb_agg(to_jsonb(t) order by t.done,t.due,t.created_at desc),'[]'::jsonb) into v_tasks
 from public.workshop_tasks t where exists(select 1 from public.workshop_staff s where s.id=t.staff_id and s.active) and ((a->>'manager')::boolean or t.staff_id=a->>'self');
 return a || jsonb_build_object('staff',v_staff,'days',v_days,'tasks',v_tasks,'date',p_date,'profile',jsonb_build_object('photo',(select photo from public.workshop_profiles where user_id=auth.uid())),'announcement',(select jsonb_build_object('message',message,'enabled',enabled,'updated_at',updated_at) from public.workshop_announcement where id=1));
end $$;
revoke all on function public.workshop_load(date) from public, anon, authenticated;
grant execute on function public.workshop_load(date) to authenticated;

notify pgrst,'reload schema';
commit;
