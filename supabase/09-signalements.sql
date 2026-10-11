-- Après 07 (08 ne comporte pas de migration SQL).
begin;
create table if not exists public.workshop_reports (
 id uuid primary key,
 author_id uuid references auth.users(id) on delete set null,
 author_name text not null,
 registration text not null check(length(registration) between 3 and 20 and registration ~ '^[A-Z0-9][A-Z0-9 -]+[A-Z0-9]$'),
 notes text not null default '' check(length(notes)<=2000),
 created_at timestamptz not null default now()
);
create table if not exists public.workshop_report_photos (
 report_id uuid not null references public.workshop_reports(id) on delete cascade,
 position smallint not null check(position between 0 and 4),
 photo text not null check(length(photo)<=300000 and photo ~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$'),
 primary key(report_id,position)
);
create index if not exists workshop_reports_author_date on public.workshop_reports(author_id,created_at desc);
create index if not exists workshop_reports_date on public.workshop_reports(created_at desc);
alter table public.workshop_reports enable row level security;
alter table public.workshop_report_photos enable row level security;
revoke all on public.workshop_reports,public.workshop_report_photos from public,anon,authenticated;
create or replace function public.workshop_create_report(p_id uuid,p_registration text,p_notes text,p_photos jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; v_registration text; v_name text; item jsonb; i integer:=0; existing public.workshop_reports%rowtype; old_photos jsonb;
begin
 a:=workshop_private.actor();
 v_registration:=upper(trim(p_registration));
 if p_id is null or v_registration is null or length(v_registration) not between 3 and 20 or v_registration !~ '^[A-Z0-9][A-Z0-9 -]+[A-Z0-9]$' then raise exception 'Renseigne une immatriculation de 3 à 20 caractères (lettres, chiffres, espaces ou tirets).';end if;
 if p_notes is null or length(p_notes)>2000 then raise exception 'Commentaire limité à 2000 caractères.';end if;
 if p_photos is null or jsonb_typeof(p_photos)<>'array' then raise exception 'Liste de photos invalide.';end if;
 if jsonb_array_length(p_photos)>5 then raise exception 'Maximum 5 photos par signalement.';end if;
 for item in select value from jsonb_array_elements(p_photos) loop
  if jsonb_typeof(item)<>'string' or length(item#>>'{}')>300000 or (item#>>'{}') !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$' then raise exception 'Photo invalide ou trop volumineuse.';end if;
 end loop;
 -- Une nouvelle tentative réseau avec le même identifiant ne crée pas de doublon.
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into existing from public.workshop_reports where id=p_id;
 if found then
  if existing.author_id is distinct from auth.uid() then raise exception 'Identifiant de signalement indisponible.' using errcode='42501';end if;
  select coalesce(jsonb_agg(photo order by position),'[]'::jsonb) into old_photos from public.workshop_report_photos where report_id=p_id;
  if existing.registration<>v_registration or existing.notes<>trim(p_notes) or old_photos<>p_photos then raise exception 'Ce signalement a déjà été enregistré. Consulte ton historique avant de recommencer.';end if;
  return jsonb_build_object('id',existing.id,'created_at',existing.created_at);
 end if;
 select name into v_name from public.workshop_staff where id=a->>'self';
 insert into public.workshop_reports(id,author_id,author_name,registration,notes) values(p_id,auth.uid(),coalesce(v_name,a->>'user'),v_registration,trim(p_notes));
 for item in select value from jsonb_array_elements(p_photos) loop
  insert into public.workshop_report_photos(report_id,position,photo) values(p_id,i,item#>>'{}');i:=i+1;
 end loop;
 return (select jsonb_build_object('id',id,'created_at',created_at) from public.workshop_reports where id=p_id);
end $$;
create or replace function public.workshop_list_reports(p_offset integer default 0,p_own boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; v_all boolean; result jsonb; total bigint;
begin
 a:=workshop_private.actor();v_all:=(a->>'admin')::boolean and not coalesce(p_own,true);
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 select count(*) into total from public.workshop_reports where v_all or author_id=auth.uid();
 select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]'::jsonb) into result from (
  select id,author_name,registration,notes,created_at,(select count(*) from public.workshop_report_photos where report_id=x.id) as photo_count
  from public.workshop_reports x where v_all or author_id=auth.uid() order by created_at desc,id desc limit 30 offset p_offset
 ) r;
 return jsonb_build_object('items',result,'total',total);
end $$;
create or replace function public.workshop_get_report(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_reports%rowtype; photos jsonb;
begin
 a:=workshop_private.actor();
 select * into r from public.workshop_reports where id=p_id and ((a->>'admin')::boolean or author_id=auth.uid());
 if not found then raise exception 'Signalement introuvable ou non autorisé.' using errcode='42501';end if;
 select coalesce(jsonb_agg(photo order by position),'[]'::jsonb) into photos from public.workshop_report_photos where report_id=p_id;
 return jsonb_build_object('id',r.id,'author_name',r.author_name,'registration',r.registration,'notes',r.notes,'created_at',r.created_at,'photos',photos);
end $$;
revoke all on function public.workshop_create_report(uuid,text,text,jsonb),public.workshop_list_reports(integer,boolean),public.workshop_get_report(uuid) from public,anon,authenticated;
grant execute on function public.workshop_create_report(uuid,text,text,jsonb),public.workshop_list_reports(integer,boolean),public.workshop_get_report(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
