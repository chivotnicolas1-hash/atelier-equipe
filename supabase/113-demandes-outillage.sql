begin;

-- Module isolé : aucune donnée ni fonction des autres rubriques n’est remplacée.
insert into public.workshop_sections(section,disabled) values('tools',false) on conflict(section) do nothing;
create table if not exists public.workshop_tool_poles113(
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 100),
 active boolean not null default true, position integer not null default 0, version integer not null default 1
);
create unique index if not exists tool_pole_name113 on public.workshop_tool_poles113(lower(btrim(name))) where active;
-- Les pôles sont initialisés une seule fois depuis les postes existants.
do $$begin
 if not exists(select 1 from public.workshop_tool_poles113) then
  insert into public.workshop_tool_poles113(name,position)
   select name,min("row"*20+col) from public.workshop_stations where active group by name;
  if not found then insert into public.workshop_tool_poles113(name) values('Atelier');end if;
 end if;
end $$;
create table if not exists public.workshop_tool_requests113(
 id uuid primary key, author_id uuid not null references auth.users(id), author_staff text,
 author_name text not null, title text not null check(length(btrim(title)) between 1 and 160),
 pole_id uuid not null references public.workshop_tool_poles113(id), pole_name text not null,
 quantity integer not null check(quantity between 1 and 999), unit_price numeric(12,2) check(unit_price between 0 and 1000000),
 product_url text not null default '', comment text not null default '' check(length(comment)<=2000),
 priority text not null default 'normal' check(priority in ('normal','important','urgent')),
 status text not null default 'pending' check(status in ('pending','accepted','refused','ordered','received')),
 refusal_reason text not null default '' check(length(refusal_reason)<=2000),
 actual_unit_price numeric(12,2) check(actual_unit_price between 0 and 1000000), purchase_date date,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 deleted_at timestamptz, version integer not null default 1,
 check(status<>'refused' or length(btrim(refusal_reason))>0),
 check(length(product_url)<=2048 and (product_url='' or product_url ~* '^https?://[^[:space:]@]+$'))
);
create index if not exists tool_author113 on public.workshop_tool_requests113(author_id,created_at desc);
create index if not exists tool_status113 on public.workshop_tool_requests113(status,created_at desc) where deleted_at is null;
create table if not exists public.workshop_tool_photos113(
 request_id uuid primary key references public.workshop_tool_requests113(id) on delete cascade,
 photo text not null check(length(photo)<=300000)
);
create table if not exists public.workshop_tool_events113(
 id bigint generated always as identity primary key,
 request_id uuid not null references public.workshop_tool_requests113(id) on delete cascade,
 actor_id uuid not null, actor_name text not null, at timestamptz not null default now(),
 action text not null, before_data jsonb, after_data jsonb
);
create index if not exists tool_events113 on public.workshop_tool_events113(request_id,id);

create or replace function workshop_private.tool_actor113(p_admin boolean default false,p_write boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();perform workshop_private.assert_section('tools');
 if a->>'role'='guest' or (p_write and a->>'role'='director') or (p_admin and not coalesce((a->>'admin')::boolean,false)) then
  raise exception 'Accès non autorisé aux demandes d’outillage.' using errcode='42501';end if;
 return a;
end $$;
create or replace function workshop_private.tool_can_read113(p_author uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.tool_actor113();return coalesce((a->>'admin')::boolean,false) or p_author=auth.uid();end $$;
alter table public.workshop_tool_poles113 enable row level security;
alter table public.workshop_tool_requests113 enable row level security;
alter table public.workshop_tool_photos113 enable row level security;
alter table public.workshop_tool_events113 enable row level security;
drop policy if exists tool_poles_read113 on public.workshop_tool_poles113;
create policy tool_poles_read113 on public.workshop_tool_poles113 for select to authenticated using(workshop_private.tool_can_read113(auth.uid()));
drop policy if exists tool_requests_read113 on public.workshop_tool_requests113;
create policy tool_requests_read113 on public.workshop_tool_requests113 for select to authenticated using(workshop_private.tool_can_read113(author_id) and (deleted_at is null or coalesce((workshop_private.tool_actor113()->>'admin')::boolean,false)));
drop policy if exists tool_photos_read113 on public.workshop_tool_photos113;
create policy tool_photos_read113 on public.workshop_tool_photos113 for select to authenticated using(exists(select 1 from public.workshop_tool_requests113 r where r.id=request_id and r.deleted_at is null));
drop policy if exists tool_events_read113 on public.workshop_tool_events113;
create policy tool_events_read113 on public.workshop_tool_events113 for select to authenticated using(exists(select 1 from public.workshop_tool_requests113 r where r.id=request_id));
revoke all on public.workshop_tool_poles113,public.workshop_tool_requests113,public.workshop_tool_photos113,public.workshop_tool_events113 from public,anon,authenticated;
grant select on public.workshop_tool_poles113,public.workshop_tool_requests113,public.workshop_tool_photos113,public.workshop_tool_events113 to authenticated;

create or replace function public.workshop_tool_pole_save113(p_id uuid,p_version integer,p_name text,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform workshop_private.tool_actor113(true,true);
 if length(btrim(coalesce(p_name,''))) not between 1 and 100 or p_active is null then raise exception 'Renseigne un nom de pôle (100 caractères maximum).';end if;
 if p_id is null then
  insert into public.workshop_tool_poles113(name,active,position) select btrim(p_name),p_active,coalesce(max(position),0)+1 from public.workshop_tool_poles113;
 else
  update public.workshop_tool_poles113 set name=btrim(p_name),active=p_active,version=version+1 where id=p_id and version=p_version;
  if not found then raise exception 'Ce pôle a changé. Ferme puis rouvre sa fiche.';end if;
 end if;
exception when unique_violation then raise exception 'Un pôle actif porte déjà ce nom.';
end $$;

create or replace function public.workshop_tools_meta113() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.tool_actor113();return jsonb_build_object(
 'admin',coalesce((a->>'admin')::boolean,false),'can_create',coalesce(a->>'role','employee')<>'director',
 'poles',(select coalesce(jsonb_agg(to_jsonb(p) order by position,name),'[]') from public.workshop_tool_poles113 p),
 'pending',case when coalesce((a->>'admin')::boolean,false) then (select count(*) from public.workshop_tool_requests113 where status='pending' and deleted_at is null) else 0 end,
 'authors',case when coalesce((a->>'admin')::boolean,false) then (select coalesce(jsonb_agg(x order by x->>'name'),'[]') from (select jsonb_build_object('id',author_id,'name',min(author_name)) x from public.workshop_tool_requests113 group by author_id)t) else '[]'::jsonb end);
end $$;
create or replace function workshop_private.tool_snapshot113(r public.workshop_tool_requests113) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('title',r.title,'pole_name',r.pole_name,'quantity',r.quantity,'unit_price',r.unit_price,'product_url',r.product_url,'comment',r.comment,'priority',r.priority,'status',r.status,'refusal_reason',r.refusal_reason,'actual_unit_price',r.actual_unit_price,'purchase_date',r.purchase_date,'deleted_at',r.deleted_at);
$$;
create or replace function public.workshop_tool_save113(p_id uuid,p_version integer,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare a jsonb;old public.workshop_tool_requests113%rowtype;r public.workshop_tool_requests113%rowtype;
 p public.workshop_tool_poles113%rowtype;who text;photo text;bytes bytea;is_admin boolean;msg text;
begin
 a:=workshop_private.tool_actor113(false,true);is_admin:=coalesce((a->>'admin')::boolean,false);
 if p_id is null or p_version is null or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'Demande invalide.';end if;
 select * into old from public.workshop_tool_requests113 where id=p_id for update;
 if found then
  if old.deleted_at is not null or (not is_admin and (old.author_id<>auth.uid() or old.status<>'pending')) then raise exception 'Seule une demande personnelle en attente peut être modifiée.' using errcode='42501';end if;
  if old.version is distinct from p_version then raise exception 'Cette demande a changé sur un autre appareil. Ferme puis rouvre-la avant de réessayer.';end if;
 elsif p_version<>0 then raise exception 'Demande introuvable.';end if;
 if not is_admin and p_data ?| array['status','refusal_reason','actual_unit_price','purchase_date'] then raise exception 'La décision et le prix réel sont réservés à l’administrateur.' using errcode='42501';end if;
 select * into p from public.workshop_tool_poles113 where id=(p_data->>'pole_id')::uuid for share;
 if not found or (not p.active and (old.id is null or old.pole_id<>p.id)) then raise exception 'Choisis un pôle d’utilisation actif.';end if;
 r:=old;
 r.title:=btrim(coalesce(p_data->>'title',''));r.pole_id:=p.id;r.pole_name:=p.name;
 if jsonb_typeof(p_data->'quantity') is distinct from 'number' or (p_data->>'quantity')::numeric<>trunc((p_data->>'quantity')::numeric) then raise exception 'La quantité doit être un entier.';end if;
 r.quantity:=(p_data->>'quantity')::integer;
 if p_data->>'unit_price' is not null and (jsonb_typeof(p_data->'unit_price')<>'number' or round((p_data->>'unit_price')::numeric,2)<>(p_data->>'unit_price')::numeric) then raise exception 'Prix estimé invalide (2 décimales maximum).';end if;
 r.unit_price:=(p_data->>'unit_price')::numeric;r.product_url:=btrim(coalesce(p_data->>'product_url',''));r.comment:=btrim(coalesce(p_data->>'comment',''));r.priority:=coalesce(p_data->>'priority','normal');
 r.status:=coalesce(old.status,'pending');r.refusal_reason:=coalesce(old.refusal_reason,'');
 if is_admin then
  r.status:=coalesce(p_data->>'status',r.status);r.refusal_reason:=btrim(coalesce(p_data->>'refusal_reason',r.refusal_reason));
  if p_data ? 'actual_unit_price' then
   if p_data->>'actual_unit_price' is not null and (jsonb_typeof(p_data->'actual_unit_price')<>'number' or round((p_data->>'actual_unit_price')::numeric,2)<>(p_data->>'actual_unit_price')::numeric) then raise exception 'Prix réel invalide (2 décimales maximum).';end if;
   r.actual_unit_price:=(p_data->>'actual_unit_price')::numeric;
  end if;
  if p_data ? 'purchase_date' then r.purchase_date:=(p_data->>'purchase_date')::date;end if;
  if r.actual_unit_price is not null and r.status in ('ordered','received') and r.purchase_date is null then r.purchase_date:=(now() at time zone 'Europe/Paris')::date;end if;
 end if;
 if r.purchase_date is not null and (r.purchase_date<date '2020-01-01' or r.purchase_date>date '2100-12-31') then raise exception 'Date d’achat invalide.';end if;
 if length(r.title) not between 1 and 160 or r.quantity not between 1 and 999 or r.unit_price<0 or r.unit_price>1000000 or length(r.comment)>2000 or r.priority not in ('normal','important','urgent') or r.status not in ('pending','accepted','refused','ordered','received') or r.actual_unit_price<0 or r.actual_unit_price>1000000 or length(r.refusal_reason)>2000 then raise exception 'Vérifie le titre, la quantité, les prix, la priorité et le statut.';end if;
 if r.status='refused' and length(r.refusal_reason)=0 then raise exception 'Un motif est obligatoire pour refuser une demande.';end if;
 if r.product_url<>'' and (length(r.product_url)>2048 or r.product_url !~* '^https?://[^[:space:]@]+$') then raise exception 'Utilise un lien http:// ou https:// sans identifiants.';end if;
 photo:=p_data->>'photo';
 if photo is not null then
  if coalesce((p_data->>'clear_photo')::boolean,false) or length(photo)>300000 or photo !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' then raise exception 'Photo JPEG invalide ou trop volumineuse.';end if;
  bytes:=decode(split_part(photo,',',2),'base64');if octet_length(bytes)<4 or substring(bytes from 1 for 2)<>decode('ffd8','hex') then raise exception 'Photo illisible.';end if;
 end if;
 select name into who from public.workshop_staff where id=a->>'self';who:=coalesce(who,'Administrateur');
 if old.id is null then
  insert into public.workshop_tool_requests113(id,author_id,author_staff,author_name,title,pole_id,pole_name,quantity,unit_price,product_url,comment,priority,status,refusal_reason,actual_unit_price,purchase_date)
  values(p_id,auth.uid(),a->>'self',who,r.title,r.pole_id,r.pole_name,r.quantity,r.unit_price,r.product_url,r.comment,r.priority,r.status,r.refusal_reason,r.actual_unit_price,r.purchase_date) returning * into r;
 else
  update public.workshop_tool_requests113 set title=r.title,pole_id=r.pole_id,pole_name=r.pole_name,quantity=r.quantity,unit_price=r.unit_price,product_url=r.product_url,comment=r.comment,priority=r.priority,status=r.status,refusal_reason=r.refusal_reason,actual_unit_price=r.actual_unit_price,purchase_date=r.purchase_date,version=version+1,updated_at=now() where id=p_id returning * into r;
 end if;
 if coalesce((p_data->>'clear_photo')::boolean,false) then delete from public.workshop_tool_photos113 where request_id=p_id;
 elsif photo is not null then insert into public.workshop_tool_photos113 values(p_id,photo) on conflict(request_id) do update set photo=excluded.photo;end if;
 insert into public.workshop_tool_events113(request_id,actor_id,actor_name,action,before_data,after_data)
 values(p_id,auth.uid(),who,case when old.id is null then 'created' when old.status<>r.status then 'status' else 'edited' end,case when old.id is null then null else workshop_private.tool_snapshot113(old) end,workshop_private.tool_snapshot113(r)||jsonb_build_object('photo_changed',photo is not null or coalesce((p_data->>'clear_photo')::boolean,false)));
 if old.id is not null and old.status<>r.status then
  msg:='Demande d’outillage « '||left(r.title,100)||' » : '||case r.status when 'pending' then 'en attente' when 'accepted' then 'acceptée' when 'refused' then 'refusée' when 'ordered' then 'commandée' else 'réceptionnée' end||'.';
  perform workshop_private.message(r.author_id,msg,'/?notifications=tools','tool-status113:'||r.id::text||':'||r.version::text);
 end if;
 return r.id;
end $$;

create or replace function public.workshop_tool_delete113(p_id uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_tool_requests113%rowtype;who text;begin
 a:=workshop_private.tool_actor113(false,true);select * into r from public.workshop_tool_requests113 where id=p_id for update;
 if not found or r.deleted_at is not null or r.version is distinct from p_version then raise exception 'Cette demande a changé ou a déjà été supprimée.';end if;
 if not coalesce((a->>'admin')::boolean,false) and (r.author_id<>auth.uid() or r.status<>'pending') then raise exception 'Seule une demande personnelle en attente peut être supprimée.' using errcode='42501';end if;
 select name into who from public.workshop_staff where id=a->>'self';
 update public.workshop_tool_requests113 set deleted_at=now(),version=version+1,updated_at=now() where id=p_id;
 delete from public.workshop_tool_photos113 where request_id=p_id;
 insert into public.workshop_tool_events113(request_id,actor_id,actor_name,action,before_data) values(p_id,auth.uid(),coalesce(who,'Administrateur'),'deleted',workshop_private.tool_snapshot113(r));
end $$;
create or replace function public.workshop_tools_list113(p_all boolean default false,p_author uuid default null,p_pole uuid default null,p_status text default '',p_priority text default '',p_from date default null,p_to date default null,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;all_rows boolean;result jsonb;begin
 a:=workshop_private.tool_actor113(p_all);all_rows:=p_all and coalesce((a->>'admin')::boolean,false);
 if p_offset is null or p_offset<0 or p_offset>100000 or (p_from is not null and p_to is not null and p_to<p_from) then raise exception 'Filtres invalides.';end if;
 with filtered as (
 select r.*,exists(select 1 from public.workshop_tool_photos113 ph where ph.request_id=r.id) has_photo from public.workshop_tool_requests113 r
 where (all_rows or author_id=auth.uid()) and (case when p_status='deleted' then all_rows and deleted_at is not null else deleted_at is null end)
 and (p_author is null or author_id=p_author) and (p_pole is null or pole_id=p_pole)
 and (coalesce(p_status,'') in ('','deleted') or status=p_status) and (coalesce(p_priority,'')='' or priority=p_priority)
 and (p_from is null or created_at >= (p_from::timestamp at time zone 'Europe/Paris')) and (p_to is null or created_at < ((p_to+1)::timestamp at time zone 'Europe/Paris'))
 ) select jsonb_build_object('total',(select count(*) from filtered),'items',(select coalesce(jsonb_agg(to_jsonb(s) order by created_at desc,id),'[]') from (select * from filtered order by created_at desc,id limit 30 offset p_offset)s)) into result;return result;
end $$;
create or replace function public.workshop_tool_get113(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_tool_requests113%rowtype;begin
 a:=workshop_private.tool_actor113();select * into r from public.workshop_tool_requests113 where id=p_id;
 if not found or (not coalesce((a->>'admin')::boolean,false) and (r.author_id<>auth.uid() or r.deleted_at is not null)) then raise exception 'Demande inaccessible.' using errcode='42501';end if;
 return jsonb_build_object('request',to_jsonb(r),'photo',(select photo from public.workshop_tool_photos113 where request_id=p_id),'events',(select coalesce(jsonb_agg(to_jsonb(e) order by e.id desc),'[]') from public.workshop_tool_events113 e where request_id=p_id));
end $$;
create or replace function workshop_private.tool_norm113(t text) returns text language sql immutable set search_path='' as $$
 select btrim(regexp_replace(translate(lower(coalesce(t,'')),'àâäéèêëîïôöùûüç','aaaeeeeiioouuuc'),'[^a-z0-9]+',' ','g'));
$$;
create or replace function public.workshop_tools_duplicates113(p_title text,p_pole uuid,p_exclude uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;n text;begin a:=workshop_private.tool_actor113();n:=workshop_private.tool_norm113(p_title);
 if length(n)<4 then return '[]';end if;
 return (select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (select id,title,author_name,quantity,status from public.workshop_tool_requests113 r where (coalesce((a->>'admin')::boolean,false) or author_id=auth.uid()) and deleted_at is null and (p_exclude is null or id<>p_exclude) and pole_id=p_pole and created_at>now()-interval '90 days' and status in ('pending','accepted','ordered') and (workshop_private.tool_norm113(title)=n or (length(n)>=5 and (strpos(workshop_private.tool_norm113(title),n)>0 or strpos(n,workshop_private.tool_norm113(title))>0))) order by created_at desc limit 5)s);
end $$;
create or replace function public.workshop_tool_spend113(p_year integer) returns jsonb language plpgsql security definer set search_path='' as $$
begin perform workshop_private.tool_actor113(true);if p_year is null or p_year not between 2020 and 2100 then raise exception 'Année invalide.';end if;
 return (with purchases as(select * from public.workshop_tool_requests113 where deleted_at is null and status in ('ordered','received') and actual_unit_price is not null and purchase_date>=make_date(p_year,1,1) and purchase_date<make_date(p_year+1,1,1)),
 monthly as(select extract(month from purchase_date)::int "month",sum(quantity*actual_unit_price) amount,count(*) requests from purchases group by 1),
 by_pole as(select pole_id,min(pole_name) pole,sum(quantity*actual_unit_price) amount from purchases group by pole_id)
 select jsonb_build_object('total',coalesce((select sum(amount) from monthly),0),'months',(select coalesce(jsonb_agg(to_jsonb(m) order by "month"),'[]') from monthly m),'poles',(select coalesce(jsonb_agg(to_jsonb(p) order by amount desc),'[]') from by_pole p),'missing_prices',(select count(*) from public.workshop_tool_requests113 where deleted_at is null and status in ('ordered','received') and actual_unit_price is null)));
end $$;

-- Lecture seule directe par RLS ; toutes les écritures passent par les fonctions contrôlées.
do $$declare f record;begin
 for f in select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','workshop_private') and p.proname in ('tool_actor113','tool_can_read113','tool_snapshot113','tool_norm113','workshop_tool_pole_save113','workshop_tools_meta113','workshop_tool_save113','workshop_tool_delete113','workshop_tools_list113','workshop_tool_get113','workshop_tools_duplicates113','workshop_tool_spend113') loop
  execute format('revoke all on function %I.%I(%s) from public,anon,authenticated',f.nspname,f.proname,f.args);
  if f.nspname='public' or f.proname in ('tool_can_read113','tool_actor113') then execute format('grant execute on function %I.%I(%s) to authenticated',f.nspname,f.proname,f.args);end if;
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
