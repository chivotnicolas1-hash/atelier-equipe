begin;
insert into public.workshop_sections(section,disabled) values('toolbox',false) on conflict(section) do nothing;
create table if not exists public.workshop_toolbox_config114(id integer primary key check(id=1),revision integer not null default 1,tools jsonb not null default '{}',categories jsonb not null default '["Astuce","Procédure","Retour d’expérience","Fiche technique","Lien utile"]');
insert into public.workshop_toolbox_config114(id) values(1) on conflict do nothing;
create table if not exists public.workshop_toolbox_cards114(
 id text primary key,base_key text unique,tool text not null check(tool in ('obd','oils','bulbs','fuses','fasteners','batteries','climate','community')),
 owner_id uuid not null references auth.users(id),author_name text not null,title text not null check(length(title) between 1 and 180),
 body text not null check(length(body)<=12000),fields jsonb not null default '{}',sources jsonb not null default '[]',checked date,
 category text not null default '',code text,manufacturer text not null default '',status text not null check(status in ('pending','published','refused','deleted')),
 review_note text not null default '',version integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),updated_name text not null
);
create index if not exists toolbox_status114 on public.workshop_toolbox_cards114(status,tool);
create index if not exists toolbox_owner114 on public.workshop_toolbox_cards114(owner_id);
create table if not exists public.workshop_toolbox_photos114(id text primary key references public.workshop_toolbox_cards114(id) on delete cascade,photo text not null check(length(photo)<=300000));
create or replace function workshop_private.toolbox_actor114(p_admin boolean default false,p_write boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();perform workshop_private.assert_section('toolbox');
 if a->>'role'='guest' or (p_write and a->>'role'='director') or (p_admin and not coalesce((a->>'admin')::boolean,false)) then raise exception 'Accès Toolbox non autorisé.' using errcode='42501';end if;return a;end $$;
create or replace function workshop_private.toolbox_can_read114(p_owner uuid,p_status text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.toolbox_actor114();return coalesce((a->>'admin')::boolean,false) or p_status='published' or (p_owner=auth.uid() and p_status<>'deleted');end $$;
alter table public.workshop_toolbox_config114 enable row level security;
alter table public.workshop_toolbox_cards114 enable row level security;
alter table public.workshop_toolbox_photos114 enable row level security;
drop policy if exists toolbox_config114 on public.workshop_toolbox_config114;
create policy toolbox_config114 on public.workshop_toolbox_config114 for select to authenticated using(workshop_private.toolbox_can_read114(auth.uid(),'published'));
drop policy if exists toolbox_cards114 on public.workshop_toolbox_cards114;
create policy toolbox_cards114 on public.workshop_toolbox_cards114 for select to authenticated using(workshop_private.toolbox_can_read114(owner_id,status));
drop policy if exists toolbox_photos114 on public.workshop_toolbox_photos114;
create policy toolbox_photos114 on public.workshop_toolbox_photos114 for select to authenticated using(exists(select 1 from public.workshop_toolbox_cards114 c where c.id=workshop_toolbox_photos114.id and c.status<>'deleted'));
revoke all on public.workshop_toolbox_config114,public.workshop_toolbox_cards114,public.workshop_toolbox_photos114 from public,anon,authenticated;
grant select on public.workshop_toolbox_config114,public.workshop_toolbox_cards114,public.workshop_toolbox_photos114 to authenticated;
create or replace function public.workshop_toolbox_sync114(p_known integer default -1) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;c public.workshop_toolbox_config114%rowtype;adm boolean;begin a:=workshop_private.toolbox_actor114();adm:=coalesce((a->>'admin')::boolean,false);select * into c from public.workshop_toolbox_config114 where id=1;
 if p_known=c.revision then return jsonb_build_object('revision',c.revision,'unchanged',true);end if;
 return jsonb_build_object('revision',c.revision,'self_id',auth.uid(),'tools',c.tools,'categories',c.categories,'can_write',a->>'role'<>'director','admin',adm,'pending',(select count(*) from public.workshop_toolbox_cards114 where status='pending' and adm),
 'cards',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('has_photo',exists(select 1 from public.workshop_toolbox_photos114 ph where ph.id=r.id)) order by r.updated_at desc),'[]') from public.workshop_toolbox_cards114 r where status='published' or (adm and status<>'deleted') or (owner_id=auth.uid() and status in ('pending','refused'))),
 'hidden',(select coalesce(jsonb_agg(base_key),'[]') from public.workshop_toolbox_cards114 where base_key is not null and status='deleted'));
end $$;
create or replace function public.workshop_toolbox_config_save114(p_revision integer,p_tools jsonb,p_categories jsonb) returns void language plpgsql security definer set search_path='' as $$
declare k text;v jsonb;begin perform workshop_private.toolbox_actor114(true,true);
 if jsonb_typeof(p_tools) is distinct from 'object' or jsonb_typeof(p_categories) is distinct from 'array' or jsonb_array_length(p_categories) not between 1 and 30 then raise exception 'Réglages invalides.';end if;
 for k,v in select * from jsonb_each(p_tools) loop if k not in ('tyres','electric','units','obd','oils','bulbs','fuses','fasteners','batteries','climate','community') or jsonb_typeof(v)<>'boolean' then raise exception 'Outil inconnu.';end if;end loop;
 if exists(select 1 from jsonb_array_elements(p_categories) elem where jsonb_typeof(elem.value)<>'string' or length(btrim(elem.value#>>'{}')) not between 1 and 80) or (select count(distinct lower(btrim(elem.value#>>'{}'))) from jsonb_array_elements(p_categories) elem)<>jsonb_array_length(p_categories) then raise exception 'Catégories vides ou en doublon.';end if;
 update public.workshop_toolbox_config114 set tools=p_tools,categories=p_categories,revision=revision+1 where id=1 and revision=p_revision;if not found then raise exception 'Les réglages ont changé. Ferme puis rouvre le panneau.';end if;
end $$;
create or replace function public.workshop_toolbox_card_save114(p_id text,p_version integer,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;adm boolean;r public.workshop_toolbox_cards114%rowtype;who text;f record;s jsonb;pic text;b bytea;st text;prev_t numeric;prev_a numeric;prev_y numeric;cur_t numeric;cur_a numeric;cur_y numeric;begin
 a:=workshop_private.toolbox_actor114(false,true);adm:=coalesce((a->>'admin')::boolean,false);
 perform 1 from public.workshop_toolbox_config114 where id=1 for update;
 select * into r from public.workshop_toolbox_cards114 where id=p_id for update;
 if p_id is null or length(p_id)>200 or p_version is null or (r.id is null and p_version<>0) or (r.id is not null and r.version is distinct from p_version) then raise exception 'Fiche modifiée ailleurs. Rouvre-la avant de réessayer.';end if;
 if not adm and ((r.id is not null and (r.owner_id<>auth.uid() or r.status not in ('pending','refused'))) or coalesce(p_data->>'tool','')<>'community' or p_data->>'base_key' is not null or p_data->>'status' is distinct from 'pending') then raise exception 'Seules tes propositions non publiées peuvent être modifiées.' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or length(btrim(coalesce(p_data->>'title',''))) not between 1 and 180 or length(coalesce(p_data->>'body',''))>12000 or length(coalesce(p_data->>'category',''))>80 or length(coalesce(p_data->>'manufacturer',''))>80 or jsonb_typeof(p_data->'fields') is distinct from 'object' or octet_length((p_data->'fields')::text)>16000 or jsonb_typeof(p_data->'sources') is distinct from 'array' or jsonb_array_length(p_data->'sources')>8 then raise exception 'Titre, texte, caractéristiques ou sources invalides.';end if;
 for f in select * from jsonb_each(p_data->'fields') loop if length(f.key) not between 1 and 100 or jsonb_typeof(f.value)<>'string' or length(f.value#>>'{}')>4000 then raise exception 'Caractéristique invalide.';end if;end loop;
 for s in select value from jsonb_array_elements(p_data->'sources') loop if length(coalesce(s->>'name','')) not between 1 and 160 or length(coalesce(s->>'licence','')) not between 1 and 200 or coalesce(s->>'url','') !~* '^https?://[^[:space:]@]+$' or length(s->>'url')>2048 then raise exception 'Chaque source doit avoir un nom, un lien http(s) et une indication de droits.';end if;end loop;
 st:=coalesce(p_data->>'status','pending');
 if st not in ('pending','published','refused','deleted') or length(coalesce(p_data->>'review_note',''))>1000 then raise exception 'Statut ou motif invalide.';end if;
 if st='published' and (jsonb_array_length(p_data->'sources')=0 or p_data->>'checked' is null or coalesce((p_data->>'rights')::boolean,false) is not true) then raise exception 'Pour publier : source, date de vérification et confirmation des droits obligatoires.';end if;
 if (p_data->>'checked')::date > (now() at time zone 'Europe/Paris')::date then raise exception 'La date de vérification ne peut pas être future.';end if;
 if not adm and (select tools->>'community'='false' from public.workshop_toolbox_config114 where id=1) then raise exception 'Les contributions sont temporairement désactivées.' using errcode='42501';end if;
 if not adm and coalesce((p_data->>'rights')::boolean,false) is not true then raise exception 'Confirme les droits de partage de ta proposition.';end if;
 if st='refused' and length(btrim(coalesce(p_data->>'review_note','')))=0 then raise exception 'Précise le motif du refus.';end if;
 if p_data->>'tool'='obd' and coalesce(p_data->>'code','') !~ '^[PBCU][0-3][0-9A-F]{3}$' then raise exception 'Code OBD invalide, exemple P0420.';end if;
 if p_data->>'tool'='obd' and not (case when left(p_data->>'code',1)='P' then substring(p_data->>'code',2,1) in ('0','2') or (left(p_data->>'code',2)='P3' and ('x'||substring(p_data->>'code',3))::bit(12)::int>=1024) else substring(p_data->>'code',2,1) in ('0','3') end) and length(btrim(coalesce(p_data->>'manufacturer','')))=0 then raise exception 'Ce code est dans une plage constructeur : précise la marque et une source correspondante.';end if;
 if p_data->>'base_key'='climate-pt' and st='published' then
  if p_data->>'tool'<>'climate' or p_data->'fields'='{}'::jsonb or exists(select 1 from jsonb_object_keys(p_data->'fields') k where k !~ '^[+-]?[0-9]+([.][0-9]+)?$') then raise exception 'Table P/T : températures numériques et rubrique Climatisation requises.';end if;
  for f in select key,value from jsonb_each_text(p_data->'fields') order by key::numeric loop
   cur_t:=f.key::numeric;if array_length(string_to_array(f.value,';'),1)<>2 then raise exception 'Table P/T : deux pressions séparées par un point-virgule.';end if;
   cur_a:=replace(btrim(split_part(f.value,';',1)),',','.')::numeric;cur_y:=replace(btrim(split_part(f.value,';',2)),',','.')::numeric;
   if cur_t not between -30 and 80 or cur_a<=0 or cur_a>50 or cur_y<=0 or cur_y>50 or (prev_t is not null and (cur_t<=prev_t or cur_a<=prev_a or cur_y<=prev_y)) then raise exception 'Table P/T : températures et pressions hors limites ou non croissantes.';end if;
   prev_t:=cur_t;prev_a:=cur_a;prev_y:=cur_y;
  end loop;
 end if;
 if r.id is null and (select count(*) from public.workshop_toolbox_cards114)>=500 then raise exception 'Limite de 500 fiches administrées atteinte. Retire les anciennes fiches pour libérer de la place.';end if;
 pic:=p_data->>'photo';if pic is not null then
  if (select coalesce(sum(octet_length(photo)),0) from public.workshop_toolbox_photos114 where id<>p_id)+octet_length(pic)>20971520 then raise exception 'Budget photos Toolbox atteint (20 Mio). Retire une ancienne photo avant d’en ajouter une.';end if;
  if length(pic)>300000 or pic !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' then raise exception 'Photo JPEG trop volumineuse ou invalide.';end if;b:=decode(split_part(pic,',',2),'base64');if octet_length(b)<4 or substring(b from 1 for 2)<>decode('ffd8','hex') then raise exception 'Photo illisible.';end if;
 end if;
 select name into who from public.workshop_staff where id=a->>'self';who:=coalesce(who,'Administrateur');
 insert into public.workshop_toolbox_cards114(id,base_key,tool,owner_id,author_name,title,body,fields,sources,checked,category,code,manufacturer,status,review_note,updated_name)
 values(p_id,p_data->>'base_key',p_data->>'tool',auth.uid(),who,btrim(p_data->>'title'),coalesce(p_data->>'body',''),p_data->'fields',p_data->'sources',(p_data->>'checked')::date,coalesce(p_data->>'category',''),p_data->>'code',coalesce(p_data->>'manufacturer',''),st,case when adm then coalesce(p_data->>'review_note','') else '' end,who)
 on conflict(id) do update set base_key=excluded.base_key,tool=excluded.tool,title=excluded.title,body=excluded.body,fields=excluded.fields,sources=excluded.sources,checked=excluded.checked,category=excluded.category,code=excluded.code,manufacturer=excluded.manufacturer,status=excluded.status,review_note=excluded.review_note,version=workshop_toolbox_cards114.version+1,updated_at=now(),updated_name=who;
 if coalesce((p_data->>'clear_photo')::boolean,false) or st='deleted' then delete from public.workshop_toolbox_photos114 where id=p_id;elsif pic is not null then insert into public.workshop_toolbox_photos114 values(p_id,pic) on conflict(id) do update set photo=excluded.photo;end if;
 update public.workshop_toolbox_config114 set revision=revision+1 where id=1;
end $$;
create or replace function public.workshop_toolbox_photo114(p_id text) returns text language plpgsql security definer set search_path='' as $$
declare r public.workshop_toolbox_cards114%rowtype;begin perform workshop_private.toolbox_actor114();select * into r from public.workshop_toolbox_cards114 where id=p_id;if r.id is null or not workshop_private.toolbox_can_read114(r.owner_id,r.status) or r.status='deleted' then raise exception 'Photo inaccessible.' using errcode='42501';end if;return(select photo from public.workshop_toolbox_photos114 where id=p_id);end $$;
create or replace function public.workshop_toolbox_remove114(p_id text,p_version integer) returns void language plpgsql security definer set search_path='' as $$
begin perform workshop_private.toolbox_actor114(true,true);perform 1 from public.workshop_toolbox_config114 where id=1 for update;
 delete from public.workshop_toolbox_cards114 where id=p_id and version=p_version and base_key is null;
 if not found then update public.workshop_toolbox_cards114 set status='deleted',version=version+1,updated_at=now() where id=p_id and version=p_version and base_key is not null;if not found then raise exception 'Fiche modifiée ou introuvable.';end if;delete from public.workshop_toolbox_photos114 where id=p_id;end if;
 update public.workshop_toolbox_config114 set revision=revision+1 where id=1;
end $$;
do $$declare f record;begin for f in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','workshop_private') and p.proname in ('toolbox_actor114','toolbox_can_read114','workshop_toolbox_sync114','workshop_toolbox_config_save114','workshop_toolbox_card_save114','workshop_toolbox_photo114','workshop_toolbox_remove114') loop
 execute format('revoke all on function %I.%I(%s) from public,anon,authenticated',f.nspname,f.proname,f.args);execute format('grant execute on function %I.%I(%s) to authenticated',f.nspname,f.proname,f.args);end loop;end $$;
notify pgrst,'reload schema';commit;
