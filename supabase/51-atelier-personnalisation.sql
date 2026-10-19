-- MAJ51 : après MAJ50. Réexécutable.
begin;
create or replace function public.workshop_target_sales_status(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;manager boolean;t timestamptz:=clock_timestamp();next_by_category jsonb:='{}'::jsonb;
begin
 a:=workshop_private.actor_before30();
 manager:=coalesce((a->>'manager')::boolean,false);
 if p_date is null then raise exception 'Date requise.';end if;
 if not manager then
 select coalesce(jsonb_object_agg(category,next_at),'{}'::jsonb) into next_by_category from
 (select category,max(created_at)+interval '5 minutes' next_at from public.workshop_target_sales s where user_id=auth.uid() and deleted_at is null and created_at>coalesce((select max(d.deleted_at) from public.workshop_target_sales d where d.user_id=s.user_id and d.category=s.category),'-infinity'::timestamptz) group by category)s;
 end if;
 return jsonb_build_object(
  'targets',public.workshop_service_targets(p_date),
  'totals',(select coalesce(jsonb_object_agg(category,total),'{}'::jsonb) from (select category,sum(quantity) total from public.workshop_target_sales where date=p_date and deleted_at is null group by category)s),
  'manager',manager,'guest',a->>'role'='guest',
  'can_add',a->>'role'<>'guest' and (manager or p_date=(t at time zone 'Europe/Paris')::date),
  'server_now',t,'next_allowed_at',null,'next_allowed_by_category',next_by_category);
end $$;

create or replace function public.workshop_add_target_sale(p_id uuid,p_date date,p_category text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;manager boolean;r public.workshop_target_sales%rowtype;last_at timestamptz;t timestamptz;person text;
begin
 a:=workshop_private.actor();manager:=coalesce((a->>'manager')::boolean,false);
 if p_id is null or p_date is null or p_category is null or p_category not in ('purge','batteries','beg','geometry','clim') then raise exception 'Vente invalide.';end if;
 -- Sérialise aussi les requêtes provenant de plusieurs téléphones/onglets.
 perform pg_advisory_xact_lock(hashtextextended('target-sale:'||auth.uid()::text,0));
 select * into r from public.workshop_target_sales where id=p_id;
 if found then
  if r.deleted_at is not null then raise exception 'Cette vente a été supprimée.';end if;
  if r.user_id is distinct from auth.uid() or r.date is distinct from p_date or r.category is distinct from p_category then raise exception 'Identifiant déjà utilisé.';end if;
  return public.workshop_target_sales_status(p_date);
 end if;
 t:=clock_timestamp();
 if not manager then
  if p_date<>(t at time zone 'Europe/Paris')::date then raise exception 'Les ventes se saisissent uniquement pour aujourd’hui.';end if;
  select max(created_at) into last_at from public.workshop_target_sales s where user_id=auth.uid() and deleted_at is null and created_at>coalesce((select max(d.deleted_at) from public.workshop_target_sales d where d.user_id=s.user_id and d.category=s.category),'-infinity'::timestamptz) and category=p_category;
  if last_at+interval '5 minutes'>t then raise exception 'Patiente 5 minutes avant une nouvelle vente pour cette cible.' using errcode='P0001';end if;
 end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_target_sales(id,date,category,user_id,author_name,created_at)
 values(p_id,p_date,p_category,auth.uid(),coalesce(person,'Utilisateur'),t);
 return public.workshop_target_sales_status(p_date);
end $$;



create or replace function public.workshop_delete_target_sale(p_id uuid,p_version integer)
returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_target_sales%rowtype;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Suppression réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_target_sales where id=p_id;
 if found then perform pg_advisory_xact_lock(hashtextextended('target-sale:'||r.user_id::text,0));end if;
 select * into r from public.workshop_target_sales where id=p_id for update;
 if not found then raise exception 'Vente introuvable.';end if;
 if r.deleted_at is not null then return;end if;
 if p_version is distinct from r.version then raise exception 'Cette vente a été modifiée ailleurs. Actualise l’historique.';end if;
 update public.workshop_target_sales set deleted_at=clock_timestamp(),deleted_by=auth.uid(),version=version+1 where id=p_id;
end $$;
revoke all on function public.workshop_delete_target_sale(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_delete_target_sale(uuid,integer) to authenticated;


create table if not exists public.workshop_stations(
 id text primary key,name text not null check(length(trim(name)) between 1 and 80),number text not null check(length(trim(number)) between 1 and 8),
 col integer not null check(col between 1 and 12),row integer not null check(row between 1 and 12),
 office boolean not null default false,rotate boolean not null default false,active boolean not null default true,version integer not null default 0);
alter table public.workshop_stations enable row level security;
revoke all on public.workshop_stations from public,anon,authenticated;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'pneus1',coalesce(settings->'stations'->'pneus1'->>'name','Pneus · 1'),coalesce(settings->'stations'->'pneus1'->>'number','01'),1,1,false,true from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'attelage',coalesce(settings->'stations'->'attelage'->>'name','Attelage & méca légère'),coalesce(settings->'stations'->'attelage'->>'number','02'),1,2,false,true from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'vidange1',coalesce(settings->'stations'->'vidange1'->>'name','Vidange · 1'),coalesce(settings->'stations'->'vidange1'->>'number','03'),1,3,false,true from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'vidange2',coalesce(settings->'stations'->'vidange2'->>'name','Vidange · 2'),coalesce(settings->'stations'->'vidange2'->>'number','04'),1,4,false,true from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'mecalegere',coalesce(settings->'stations'->'mecalegere'->>'name','Méca légère'),coalesce(settings->'stations'->'mecalegere'->>'number','05'),1,5,false,true from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'mecalourde',coalesce(settings->'stations'->'mecalourde'->>'name','Méca lourde'),coalesce(settings->'stations'->'mecalourde'->>'number','06'),1,6,false,true from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'distribution',coalesce(settings->'stations'->'distribution'->>'name','Distribution'),coalesce(settings->'stations'->'distribution'->>'number','07'),1,7,false,true from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'pneus2',coalesce(settings->'stations'->'pneus2'->>'name','Pneus · 2'),coalesce(settings->'stations'->'pneus2'->>'number','08'),2,1,false,false from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'geometrie',coalesce(settings->'stations'->'geometrie'->>'name','Géométrie'),coalesce(settings->'stations'->'geometrie'->>'number','09'),3,1,false,false from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'elec',coalesce(settings->'stations'->'elec'->>'name','Électricité'),coalesce(settings->'stations'->'elec'->>'number','10'),4,1,false,false from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'organisation',coalesce(settings->'stations'->'organisation'->>'name','Organisation'),coalesce(settings->'stations'->'organisation'->>'number','11'),2,3,true,false from public.workshop_design where id=1 on conflict(id) do nothing;
insert into public.workshop_stations(id,name,number,col,row,office,rotate) select 'devis',coalesce(settings->'stations'->'devis'->>'name','Gestion devis'),coalesce(settings->'stations'->'devis'->>'number','12'),2,4,true,false from public.workshop_design where id=1 on conflict(id) do nothing;

alter table public.workshop_days drop constraint if exists workshop_days_station_check;
do $$ begin if not exists(select 1 from pg_constraint where conname='workshop_days_station_fk') then
 alter table public.workshop_days add constraint workshop_days_station_fk foreign key(station) references public.workshop_stations(id);end if;end $$;
create or replace function public.workshop_get_stations() returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(s) order by row,col,id),'[]') from public.workshop_stations s where active
$$;
revoke all on function public.workshop_get_stations() from public,anon,authenticated;
grant execute on function public.workshop_get_stations() to anon,authenticated;
create or replace function public.workshop_save_station(p_id text,p_version integer,p_name text,p_number text,p_col integer,p_row integer,p_office boolean,p_rotate boolean,p_delete boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_stations%rowtype;
begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_id is null or p_id !~ '^[a-z0-9-]{1,60}$' or p_version is null or p_delete is null then raise exception 'Poste invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-stations',0));
 select * into r from public.workshop_stations where id=p_id for update;
 if (found and (r.version<>p_version or not r.active)) or (not found and p_version<>0) then raise exception 'Le plan a changé. Ferme puis rouvre la gestion des postes.';end if;
 if p_delete then
  if r.id is null then raise exception 'Poste introuvable.';end if;
  if (select count(*) from public.workshop_stations where active)<=1 then raise exception 'Conserve au moins un poste.';end if;
  update public.workshop_stations set active=false,version=version+1 where id=p_id;
  update public.workshop_days set station=case when station=p_id then null else station end,geometry=case when p_id='geometrie' then false else geometry end
  where date>=(now() at time zone 'Europe/Paris')::date and (station=p_id or (p_id='geometrie' and geometry));
 else
  if nullif(trim(p_name),'') is null or length(trim(p_name))>80 or nullif(trim(p_number),'') is null or length(trim(p_number))>8 or p_col is null or p_row is null or p_col not between 1 and 12 or p_row not between 1 and 12 or p_office is null or p_rotate is null then raise exception 'Nom, numéro et emplacement requis (1 à 12).';end if;
  if exists(select 1 from public.workshop_stations where active and col=p_col and row=p_row and id<>p_id) then raise exception 'Cet emplacement est occupé. Choisis une case libre.';end if;
  insert into public.workshop_stations(id,name,number,col,row,office,rotate) values(p_id,trim(p_name),trim(p_number),p_col,p_row,p_office,p_rotate)
  on conflict(id) do update set name=excluded.name,number=excluded.number,col=excluded.col,row=excluded.row,office=excluded.office,rotate=excluded.rotate,version=workshop_stations.version+1;
 end if;
 return public.workshop_get_stations();
end $$;
revoke all on function public.workshop_save_station(text,integer,text,text,integer,integer,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function public.workshop_save_station(text,integer,text,text,integer,integer,boolean,boolean,boolean) to authenticated;
create or replace function workshop_private.check_active_station() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.station is not null and (tg_op='INSERT' or new.station is distinct from old.station) and not exists(select 1 from public.workshop_stations where id=new.station and active) then raise exception 'Ce poste a été supprimé. Actualise le plan.';end if;
 if new.geometry and (tg_op='INSERT' or new.geometry is distinct from old.geometry) and not exists(select 1 from public.workshop_stations where id='geometrie' and active) then raise exception 'Le poste géométrie a été supprimé.';end if;
 return new;
end $$;
revoke all on function workshop_private.check_active_station() from public,anon,authenticated;
drop trigger if exists workshop_check_active_station on public.workshop_days;
create trigger workshop_check_active_station before insert or update on public.workshop_days for each row execute function workshop_private.check_active_station();
create or replace function public.workshop_save_design(p_settings jsonb,p_name text,p_revision integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; k text; palette text; v jsonb; entry jsonb; current_revision integer;
begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_settings is null or jsonb_typeof(p_settings)<>'object' or length(p_settings::text)>30000 or length(trim(coalesce(p_name,''))) not between 1 and 80 then raise exception 'Paramètres invalides.';end if;
 for k in select jsonb_object_keys(p_settings) loop
  if k not in ('appName','subtitle','loginTitle','loginDescription','loginNote','signature','light','dark','fontSize','radius','spacing','stations','season') then raise exception 'Paramètre inconnu : %',k;end if;
 end loop;
 foreach k in array array['appName','subtitle','loginTitle','loginDescription','loginNote','signature'] loop
  if p_settings ? k and (jsonb_typeof(p_settings->k)<>'string' or length(trim(p_settings->>k)) not between 1 and 500) then raise exception 'Texte invalide : %',k;end if;
 end loop;
 foreach palette in array array['light','dark'] loop
  if p_settings ? palette then
   if jsonb_typeof(p_settings->palette)<>'object' then raise exception 'Palette invalide.';end if;
   for k,v in select * from jsonb_each(p_settings->palette) loop
    if k not in ('background','surface','text','primary','header') or jsonb_typeof(v)<>'string' or (v#>>'{}') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Couleur invalide.';end if;
   end loop;
  end if;
 end loop;
 foreach k in array array['fontSize','radius','spacing'] loop
  if p_settings ? k and (jsonb_typeof(p_settings->k)<>'number' or (p_settings->>k)::numeric<>trunc((p_settings->>k)::numeric)) then raise exception 'Dimension invalide.';end if;
 end loop;
 if coalesce((p_settings->>'fontSize')::integer,16) not between 14 and 20 or coalesce((p_settings->>'radius')::integer,12) not between 0 and 24 or coalesce((p_settings->>'spacing')::integer,20) not between 12 and 36 then raise exception 'Dimension hors limites.';end if;
 if p_settings ? 'stations' then
  if jsonb_typeof(p_settings->'stations')<>'object' then raise exception 'Postes invalides.';end if;
  for k,entry in select * from jsonb_each(p_settings->'stations') loop
   if k not in ('pneus1','pneus2','attelage','vidange1','vidange2','mecalegere','mecalourde','distribution','geometrie','elec','organisation','devis') or jsonb_typeof(entry)<>'object' then raise exception 'Poste inconnu.';end if;
   if jsonb_typeof(entry->'name') is distinct from 'string' or length(trim(entry->>'name')) not between 1 and 80 or jsonb_typeof(entry->'number') is distinct from 'string' or length(trim(entry->>'number')) not between 1 and 8 then raise exception 'Nom ou numéro de poste invalide.';end if;
   if exists(select 1 from jsonb_object_keys(entry) x where x not in ('name','number')) then raise exception 'Paramètre de poste inconnu.';end if;
  end loop;
 end if;
 if p_settings ? 'season' and (jsonb_typeof(p_settings->'season')<>'string' or p_settings->>'season' not in ('none','halloween','christmas')) then raise exception 'Décor inconnu.';end if;
 select revision into current_revision from public.workshop_design where id=1 for update;
 if current_revision is distinct from p_revision then raise exception 'Le design a changé. Ferme puis rouvre les paramètres.';end if;
 update public.workshop_design set settings=p_settings,revision=revision+1 where id=1;
 insert into public.workshop_design_history(name,settings) values(trim(p_name),p_settings);
 return public.workshop_get_design();
end $$;
alter table public.workshop_design_history add column if not exists season_key text;
create unique index if not exists workshop_season_unique on public.workshop_design_history(season_key) where season_key is not null;
insert into public.workshop_design_history(name,settings,season_key) select 'Halloween · Citrouilles et toiles',settings||'{"season": "halloween", "light": {"background": "#fff7ed", "surface": "#fffdf9", "text": "#482c44", "primary": "#ad490e", "header": "#35203f"}, "dark": {"background": "#201827", "surface": "#34253d", "text": "#fff0dd", "primary": "#f1a04b", "header": "#291c33"}}'::jsonb,'halloween' from public.workshop_design where id=1 on conflict do nothing;
insert into public.workshop_design_history(name,settings,season_key) select 'Noël · Neige et guirlandes',settings||'{"season": "christmas", "light": {"background": "#f1f8f5", "surface": "#ffffff", "text": "#204b41", "primary": "#276b55", "header": "#153d34"}, "dark": {"background": "#102921", "surface": "#1d3d33", "text": "#f2f8ee", "primary": "#79c5a2", "header": "#13392e"}}'::jsonb,'christmas' from public.workshop_design where id=1 on conflict do nothing;
notify pgrst,'reload schema';
commit;
