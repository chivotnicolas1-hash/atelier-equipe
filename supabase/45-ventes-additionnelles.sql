-- MAJ45 : nécessite MAJ44. Réexécutable. Aucun effacement des données.
begin;
create table if not exists public.workshop_target_sales(
 id uuid primary key,
 date date not null,
 category text not null check(category in ('purge','batteries','beg','geometry','clim')),
 user_id uuid references auth.users(id) on delete set null,
 author_name text not null,
 quantity integer not null default 1 check(quantity between 0 and 10000),
 created_at timestamptz not null default clock_timestamp(),
 version integer not null default 0,
 updated_at timestamptz,
 updated_name text
);
create index if not exists workshop_target_sales_day_idx on public.workshop_target_sales(date);
create index if not exists workshop_target_sales_user_idx on public.workshop_target_sales(user_id,created_at desc);
create table if not exists public.workshop_target_sale_edits(
 id bigint generated always as identity primary key,
 sale_id uuid not null references public.workshop_target_sales(id),
 old_quantity integer not null,
 new_quantity integer not null,
 editor_id uuid references auth.users(id) on delete set null,
 editor_name text not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table public.workshop_target_sales enable row level security;
alter table public.workshop_target_sale_edits enable row level security;
revoke all on public.workshop_target_sales,public.workshop_target_sale_edits from public,anon,authenticated;
revoke all on sequence public.workshop_target_sale_edits_id_seq from public,anon,authenticated;

create or replace function public.workshop_target_sales_status(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;manager boolean;t timestamptz:=clock_timestamp();next_at timestamptz;
begin
 a:=workshop_private.actor_before30();
 manager:=coalesce((a->>'manager')::boolean,false);
 if p_date is null then raise exception 'Date requise.';end if;
 if not manager then select max(created_at)+interval '10 minutes' into next_at from public.workshop_target_sales where user_id=auth.uid();end if;
 return jsonb_build_object(
  'targets',public.workshop_service_targets(p_date),
  'totals',(select coalesce(jsonb_object_agg(category,total),'{}'::jsonb) from (select category,sum(quantity) total from public.workshop_target_sales where date=p_date group by category)s),
  'manager',manager,'guest',a->>'role'='guest',
  'can_add',a->>'role'<>'guest' and (manager or p_date=(t at time zone 'Europe/Paris')::date),
  'server_now',t,'next_allowed_at',next_at);
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
  if r.user_id is distinct from auth.uid() or r.date is distinct from p_date or r.category is distinct from p_category then raise exception 'Identifiant déjà utilisé.';end if;
  return public.workshop_target_sales_status(p_date);
 end if;
 t:=clock_timestamp();
 if not manager then
  if p_date<>(t at time zone 'Europe/Paris')::date then raise exception 'Les ventes se saisissent uniquement pour aujourd’hui.';end if;
  select max(created_at) into last_at from public.workshop_target_sales where user_id=auth.uid();
  if last_at+interval '10 minutes'>t then raise exception 'Patiente 10 minutes entre deux ventes, toutes catégories confondues.' using errcode='P0001';end if;
 end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_target_sales(id,date,category,user_id,author_name,created_at)
 values(p_id,p_date,p_category,auth.uid(),coalesce(person,'Utilisateur'),t);
 return public.workshop_target_sales_status(p_date);
end $$;

create or replace function public.workshop_target_sales_history(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Historique réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null then raise exception 'Date requise.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',s.id,'category',s.category,'author_name',s.author_name,'quantity',s.quantity,'created_at',s.created_at,
  'version',s.version,'updated_at',s.updated_at,'updated_name',s.updated_name,
  'edits',(select coalesce(jsonb_agg(jsonb_build_object('old_quantity',e.old_quantity,'new_quantity',e.new_quantity,'editor_name',e.editor_name,'created_at',e.created_at) order by e.created_at desc,e.id desc),'[]'::jsonb) from public.workshop_target_sale_edits e where e.sale_id=s.id)
 ) order by s.created_at desc,s.id) from public.workshop_target_sales s where s.date=p_date),'[]'::jsonb);
end $$;

create or replace function public.workshop_update_target_sale(p_id uuid,p_quantity integer,p_version integer)
returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_target_sales%rowtype;person text;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Correction réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_quantity is null or p_quantity not between 0 and 10000 then raise exception 'Quantité entière comprise entre 0 et 10000 requise.';end if;
 select * into r from public.workshop_target_sales where id=p_id for update;
 if not found then raise exception 'Vente introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Cette vente a été modifiée ailleurs. Actualise l’historique.';end if;
 if p_quantity=r.quantity then return;end if;
 select name into person from public.workshop_staff where id=a->>'self';
 person:=coalesce(person,'Gestionnaire');
 insert into public.workshop_target_sale_edits(sale_id,old_quantity,new_quantity,editor_id,editor_name)
 values(p_id,r.quantity,p_quantity,auth.uid(),person);
 update public.workshop_target_sales set quantity=p_quantity,version=version+1,updated_at=clock_timestamp(),updated_name=person where id=p_id;
end $$;
revoke all on function public.workshop_target_sales_status(date),public.workshop_add_target_sale(uuid,date,text),public.workshop_target_sales_history(date),public.workshop_update_target_sale(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.workshop_target_sales_status(date),public.workshop_add_target_sale(uuid,date,text),public.workshop_target_sales_history(date),public.workshop_update_target_sale(uuid,integer,integer) to authenticated;
notify pgrst,'reload schema';
commit;
