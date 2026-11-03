begin;
create table if not exists workshop_private.oil_catalog72(id int primary key check(id=1),items jsonb not null,version int not null);
alter table workshop_private.oil_catalog72 enable row level security;
revoke all on workshop_private.oil_catalog72 from public,anon,authenticated;
create or replace function public.workshop_oils72(p_items jsonb default null,p_version int default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r workshop_private.oil_catalog72%rowtype;t jsonb;begin a:=workshop_private.actor_before30();
if p_items is not null then
if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur';end if;
perform pg_advisory_xact_lock(720072);select * into r from workshop_private.oil_catalog72 where id=1;
if coalesce(r.version,0) is distinct from p_version then raise exception 'Le plan a changé. Ferme puis rouvre l’éditeur.';end if;
if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100 then raise exception 'Plan invalide';end if;
for t in select value from jsonb_array_elements(p_items) loop
if coalesce(t->>'kind','') not in ('oil','tank','extra') or coalesce(length(trim(t->>'name')),0) not between 1 and 90 or length(t->>'pack')>60 or (t->>'x')::int not between 1 and 11 or (t->>'y')::int not between 1 and 99 then raise exception 'Référence ou position invalide';end if;end loop;
insert into workshop_private.oil_catalog72 values(1,p_items,1) on conflict(id) do update set items=excluded.items,version=workshop_private.oil_catalog72.version+1;
end if;select * into r from workshop_private.oil_catalog72 where id=1;return jsonb_build_object('items',r.items,'version',coalesce(r.version,0));end $$;
alter table public.workshop_waste add column if not exists pickups72 jsonb not null default '[]';
create or replace function public.workshop_partial72(p_id uuid,p_version int,p_amounts jsonb) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;k text;n numeric;v numeric;lefts jsonb:='{}';cats jsonb:='[]';person text;begin a:=workshop_private.actor();
if not coalesce((a->>'manager')::boolean,false) then raise exception 'Accès réservé aux gestionnaires';end if;
select * into r from public.workshop_waste where id=p_id for update;
if not found or r.version is distinct from p_version or r.validated_at is null or r.collected_at is not null then raise exception 'Demande modifiée ou non validée';end if;
if jsonb_typeof(p_amounts) is distinct from 'object' or p_amounts='{}'::jsonb then raise exception 'Indique les quantités enlevées';end if;
for k in select jsonb_object_keys(p_amounts) loop
if not (r.categories ? k) or jsonb_typeof(p_amounts->k)<>'number' then raise exception 'Élément invalide';end if;
n:=(p_amounts->>k)::numeric;if n<=0 or (k<>'huiles' and n<>trunc(n)) then raise exception 'Quantité invalide';end if;end loop;
for k in select jsonb_array_elements_text(r.categories) loop
v:=(r.bin_counts->>k)::numeric;n:=coalesce((p_amounts->>k)::numeric,0);if v is null or n>v then raise exception 'Quantité supérieure au restant';end if;
if v>n then lefts:=lefts||jsonb_build_object(k,v-n);cats:=cats||jsonb_build_array(k);end if;end loop;
if cats='[]'::jsonb then perform public.workshop_collect_waste(p_id,p_version);return;end if;
select name into person from public.workshop_staff where id=a->>'self';
update public.workshop_waste set categories=cats,bin_counts=lefts,version=version+1,pickups72=pickups72||jsonb_build_array(jsonb_build_object('at',now(),'by',coalesce(person,a->>'user'),'amounts',p_amounts)) where id=p_id;
end $$;
revoke all on function public.workshop_oils72(jsonb,int),public.workshop_partial72(uuid,int,jsonb) from public,anon;
grant execute on function public.workshop_oils72(jsonb,int),public.workshop_partial72(uuid,int,jsonb) to authenticated;
notify pgrst,'reload schema';commit;
