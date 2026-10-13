begin;
create or replace function public.workshop_save_order(p_id uuid,p_version integer,p_items jsonb,p_notes text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_order_requests%rowtype; item jsonb; clean jsonb:='[]'; person text; item_id uuid; old_item jsonb; manager boolean; out_stock boolean;
begin
 a:=workshop_private.order_actor();manager:=coalesce((a->>'manager')::boolean,false);select name into person from public.workshop_staff where id=a->>'self';
 perform pg_advisory_xact_lock(hashtextextended('order:'||p_id::text,0));
 select * into r from public.workshop_order_requests where id=p_id for update;
 if not found or r.deleted_at is not null then raise exception 'Commande introuvable.';end if;
 if r.status='validated' and not manager then raise exception 'Cette commande est validée. Seuls l’administrateur et les modérateurs peuvent la modifier.' using errcode='42501';end if;
 if p_id is null or p_version is null then raise exception 'Demande invalide.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Liste d’articles invalide.';end if;
 if jsonb_array_length(p_items) not between 0 and 100 then raise exception 'Maximum 100 articles.';end if;
 if p_notes is null or length(p_notes)>2000 then raise exception 'Commentaire limité à 2000 caractères.';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(item)<>'object' or length(trim(coalesce(item->>'label',''))) not between 1 and 200 or length(coalesce(item->>'reference',''))>120 or length(coalesce(item->>'supplier',''))>150 then raise exception 'Renseigne un article valide (200 caractères maximum).';end if;
  if jsonb_typeof(item->'quantity') is distinct from 'number' or coalesce(item->>'quantity','') !~ '^[0-9]{1,3}$' or (item->>'quantity')::integer not between 1 and 999 then raise exception 'Quantité entière de 1 à 999 attendue.';end if;
  item_id:=coalesce(nullif(item->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from jsonb_array_elements(clean) x where x->>'id'=item_id::text) then raise exception 'Article en double.';end if;
  select x into old_item from jsonb_array_elements(r.items) x where x->>'id'=item_id::text;
  if item ? 'out_of_stock' and jsonb_typeof(item->'out_of_stock')<>'boolean' then raise exception 'État de rupture invalide.';end if;
  out_stock:=coalesce((item->>'out_of_stock')::boolean,false);
  if not manager and out_stock is distinct from coalesce((old_item->>'out_of_stock')::boolean,false) then raise exception 'Seuls l’administrateur et les modérateurs renseignent les ruptures.' using errcode='42501';end if;
  clean:=clean||jsonb_build_array(jsonb_build_object('id',item_id,'label',trim(item->>'label'),'quantity',(item->>'quantity')::integer,'out_of_stock',out_stock,'added_by',case when old_item is not null then old_item->>'added_by' else auth.uid()::text end,'added_name',case when old_item is not null then old_item->>'added_name' else coalesce(person,a->>'user') end));
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('order:'||p_id::text,0));
 select * into r from public.workshop_order_requests where id=p_id for update;
 if found then
  if r.deleted_at is not null then raise exception 'Cette commande a été supprimée.';end if;
  if p_version is distinct from r.version then raise exception 'La demande a changé entre-temps. Ferme puis rouvre-la.';end if;
  update public.workshop_order_requests set items=clean,version=version+1,updated_at=now(),status='pending',validated_at=null,validated_by=null,validated_name=null where id=p_id;
 else
  raise exception 'Commande introuvable. Les nouvelles commandes sont créées automatiquement chaque semaine.';
 end if;
 return (select to_jsonb(o) from public.workshop_order_requests o where id=p_id);
end $$;

create or replace function public.workshop_list_reports(p_offset integer default 0,p_own boolean default true,p_search text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; v_all boolean; result jsonb; total bigint; q text;
begin
 a:=workshop_private.actor();v_all:=((a->>'reports_all')::boolean or (a->>'manager')::boolean) and not coalesce(p_own,true);
 if p_search is null or length(p_search)>30 then raise exception 'Recherche limitée à 30 caractères.';end if;
 q:=regexp_replace(upper(p_search),'[^A-Z0-9]','','g');
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 select count(*) into total from public.workshop_reports where (v_all or author_id=auth.uid()) and strpos(regexp_replace(upper(registration),'[^A-Z0-9]','','g'),q)>0;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]'::jsonb) into result from (
  select id,author_name,registration,notes,created_at,(select count(*) from public.workshop_report_photos where report_id=x.id) as photo_count
  from public.workshop_reports x where (v_all or author_id=auth.uid()) and strpos(regexp_replace(upper(registration),'[^A-Z0-9]','','g'),q)>0 order by created_at desc,id desc limit 30 offset p_offset
 ) r;
 return jsonb_build_object('items',result,'total',total);
end $$;
create or replace function public.workshop_get_report(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_reports%rowtype; photos jsonb;
begin
 a:=workshop_private.actor();
 select * into r from public.workshop_reports where id=p_id and ((a->>'reports_all')::boolean or (a->>'manager')::boolean or author_id=auth.uid());
 if not found then raise exception 'Signalement introuvable ou non autorisé.' using errcode='42501';end if;
 select coalesce(jsonb_agg(photo order by position),'[]'::jsonb) into photos from public.workshop_report_photos where report_id=p_id;
 return jsonb_build_object('id',r.id,'author_name',r.author_name,'registration',r.registration,'notes',r.notes,'created_at',r.created_at,'photos',photos,'version',r.version,'updated_at',r.updated_at,'can_delete',(a->>'manager')::boolean,'can_edit',(a->>'admin')::boolean or r.author_id=auth.uid());
end $$;

create or replace function public.workshop_delete_report(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_reports%rowtype;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Suppression réservée à l’administration et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_reports where id=p_id for update;
 if not found then raise exception 'Signalement introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Signalement modifié entre-temps : ferme puis rouvre sa fiche.';end if;
 delete from public.workshop_reports where id=p_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_delete_report(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_delete_report(uuid,integer) to authenticated;

create or replace function public.workshop_preview(p_staff text,p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; result jsonb; person public.workshop_staff%rowtype; target_uid uuid; full_reports boolean;
begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Aperçu réservé à l’administrateur.' using errcode='42501';end if;
 select * into person from public.workshop_staff where id=p_staff and active;
 if not found then raise exception 'Collaborateur introuvable.';end if;
 select id into target_uid from auth.users where lower(email)=person.email;
 result:=public.workshop_load(p_date);
 full_reports:=person.team='Encadrants' or person.role='moderator' or person.email='nchivot@norauto.fr';
 return jsonb_build_object('person',jsonb_build_object('id',person.id,'name',person.name,'email',person.email,'team',person.team,'role',person.role,'photo',(select photo from public.workshop_profiles where user_id=target_uid)),
 'days',result->'days','staff',result->'staff','announcement',result->'announcement','selected_target',result->'selected_target',
 'selected_ratio',case when person.team='Encadrants' then (select ratio from public.workshop_daily_ratios where date=p_date) else null end,'can_view_ratio',coalesce(person.team='Encadrants',false),
 'tasks',(select coalesce(jsonb_agg(to_jsonb(t) order by t.due),'[]') from public.workshop_tasks t where staff_id=p_staff),
 'reports',(select coalesce(jsonb_agg(to_jsonb(q)),'[]') from (select id,author_name,registration,created_at,notes from public.workshop_reports where full_reports or author_id=target_uid order by created_at desc limit 100) q),
 'orders',(select coalesce(jsonb_agg(to_jsonb(q)),'[]') from (select id,items,status,week_start,created_at,validated_name,validated_at from public.workshop_order_requests where deleted_at is null order by created_at desc limit 100) q));
end $$;
revoke all on function public.workshop_preview(text,date) from public,anon,authenticated;
grant execute on function public.workshop_preview(text,date) to authenticated;
create table if not exists public.workshop_design(id integer primary key check(id=1),revision integer not null default 0,settings jsonb not null default '{}');
insert into public.workshop_design(id) values(1) on conflict do nothing;
create table if not exists public.workshop_design_history(id bigint generated always as identity primary key,name text not null,settings jsonb not null,created_at timestamptz not null default now());
alter table public.workshop_design enable row level security;
alter table public.workshop_design_history enable row level security;
revoke all on public.workshop_design,public.workshop_design_history from public,anon,authenticated;
insert into public.workshop_design_history(name,settings) select 'Design initial - MAJ25','{}'::jsonb where not exists(select 1 from public.workshop_design_history);
create or replace function public.workshop_get_design() returns jsonb language sql security definer set search_path='' as $$ select jsonb_build_object('revision',revision,'settings',settings) from public.workshop_design where id=1 $$;
create or replace function public.workshop_design_history_list() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(h) order by id desc),'[]') from (select * from public.workshop_design_history order by id desc limit 100) h);
end $$;
create or replace function public.workshop_save_design(p_settings jsonb,p_name text,p_revision integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; k text; palette text; v jsonb; entry jsonb; current_revision integer;
begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_settings is null or jsonb_typeof(p_settings)<>'object' or length(p_settings::text)>30000 or length(trim(coalesce(p_name,''))) not between 1 and 80 then raise exception 'Paramètres invalides.';end if;
 for k in select jsonb_object_keys(p_settings) loop
  if k not in ('appName','subtitle','loginTitle','loginDescription','loginNote','signature','light','dark','fontSize','radius','spacing','stations') then raise exception 'Paramètre inconnu : %',k;end if;
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
 select revision into current_revision from public.workshop_design where id=1 for update;
 if current_revision is distinct from p_revision then raise exception 'Le design a changé. Ferme puis rouvre les paramètres.';end if;
 update public.workshop_design set settings=p_settings,revision=revision+1 where id=1;
 insert into public.workshop_design_history(name,settings) values(trim(p_name),p_settings);
 return public.workshop_get_design();
end $$;
revoke all on function public.workshop_get_design(),public.workshop_design_history_list(),public.workshop_save_design(jsonb,text,integer) from public,anon,authenticated;
grant execute on function public.workshop_get_design() to anon,authenticated;
grant execute on function public.workshop_design_history_list(),public.workshop_save_design(jsonb,text,integer) to authenticated;
notify pgrst,'reload schema';
commit;
