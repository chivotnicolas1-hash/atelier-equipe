-- MAJ123 — à examiner avant exécution. Transaction unique, aucune donnée métier existante réécrite.
begin;
do $$begin
 if to_regprocedure('public.workshop_screen_read89(text,date)') is null
 or to_regprocedure('public.workshop_pc_access()') is null
 or to_regprocedure('workshop_private.actor_before30()') is null
 or to_regclass('workshop_private.sales86') is null then
  raise exception 'Prérequis écran89/cibles86/identité absents : vérifier la version installée.';
 end if;
end $$;
create table if not exists workshop_private.waste_contacts123(
 provider text primary key check(provider in('Grandidier','Chimirec','Gurdebeke')),
 contact_name text not null default'',phone text not null default'',email text not null default'',address text not null default'',
 version integer not null default 1,updated_at timestamptz not null default now(),updated_by uuid,updated_name text not null
);
alter table workshop_private.waste_contacts123 enable row level security;
revoke all on workshop_private.waste_contacts123 from public,anon,authenticated;

create or replace function public.workshop_waste_contact123(p_provider text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');
 if not exists(select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self' and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now()))then
  raise exception 'Compte suspendu ou accès indisponible.' using errcode='42501';
 end if;
 if not(coalesce((a->>'admin')::boolean,false)or coalesce((a->>'manager')::boolean,false))then raise exception 'Contacts réservés à l’administration et à la modération.' using errcode='42501';end if;
 if p_provider is null or p_provider not in('Grandidier','Chimirec','Gurdebeke')then raise exception 'Prestataire inconnu.';end if;
 select to_jsonb(c)-'updated_by' into r from workshop_private.waste_contacts123 c where provider=p_provider;
 return coalesce(r,jsonb_build_object('provider',p_provider,'contact_name','','phone','','email','','address','','version',0));
end $$;
create or replace function public.workshop_waste_contact_save123(p_provider text,p_version integer,p_contact_name text,p_phone text,p_email text,p_address text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r workshop_private.waste_contacts123%rowtype;n text:=btrim(coalesce(p_contact_name,''));
 phone_value text:=btrim(coalesce(p_phone,''));email_value text:=btrim(coalesce(p_email,''));address_value text:=btrim(coalesce(p_address,''));editor text;
begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');
 if not exists(select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self' and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now()))then
  raise exception 'Compte suspendu ou accès indisponible.' using errcode='42501';
 end if;
 if not(coalesce((a->>'admin')::boolean,false)or coalesce((a->>'manager')::boolean,false))then raise exception 'Contacts réservés à l’administration et à la modération.' using errcode='42501';end if;
 if p_provider is null or p_provider not in('Grandidier','Chimirec','Gurdebeke')then raise exception 'Prestataire inconnu.';end if;
 if length(n)>120 or length(phone_value)>40 or length(email_value)>254 or length(address_value)>600 then raise exception 'Coordonnées trop longues.';end if;
 if phone_value<>'' and phone_value!~'^[0-9+ ()./-]+$'then raise exception 'Numéro de téléphone invalide.';end if;
 if email_value<>'' and email_value!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'then raise exception 'Adresse e-mail invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('waste-contact123:'||p_provider,0));
 select * into r from workshop_private.waste_contacts123 where provider=p_provider for update;
 if p_version is distinct from coalesce(r.version,0)then raise exception 'Cette fiche a changé. Ferme puis rouvre-la avant de réessayer.';end if;
 if r.provider is not null and r.contact_name=n and r.phone=phone_value and r.email=email_value and r.address=address_value then return public.workshop_waste_contact123(p_provider);end if;
 select name into editor from public.workshop_staff where id=a->>'self';
 insert into workshop_private.waste_contacts123(provider,contact_name,phone,email,address,version,updated_at,updated_by,updated_name)
 values(p_provider,n,phone_value,email_value,address_value,1,now(),auth.uid(),coalesce(editor,'Responsable atelier'))
 on conflict(provider)do update set contact_name=excluded.contact_name,phone=excluded.phone,email=excluded.email,address=excluded.address,
 version=workshop_private.waste_contacts123.version+1,updated_at=excluded.updated_at,updated_by=excluded.updated_by,updated_name=excluded.updated_name;
 return public.workshop_waste_contact123(p_provider);
end $$;
revoke all on function public.workshop_waste_contact123(text),public.workshop_waste_contact_save123(text,integer,text,text,text,text) from public,anon,authenticated;
grant execute on function public.workshop_waste_contact123(text),public.workshop_waste_contact_save123(text,integer,text,text,text,text) to authenticated;

-- Données minimales pour l'écran : noms et sommes par personne/cible, aucune identité Auth ni historique détaillé.
create or replace function workshop_private.screen_sales123(p_date date)
returns jsonb language sql stable security definer set search_path='' as $$
 with sales as(
  select category,user_id,author_name,quantity,created_at,id::text id
   from public.workshop_target_sales where date=p_date and deleted_at is null and quantity>0 and category in('purge','batteries','geometry','clim')
  union all
  select 'custom:'||s.target_id,s.user_id,s.author_name,s.quantity,s.created_at,s.id::text
   from workshop_private.sales86 s join workshop_private.targets86 t on t.id=s.target_id and t.starts_on<=p_date
   where s.date=p_date and s.deleted_at is null and s.quantity>0
 ),people as(
  select category,case when user_id is null then'legacy:'||id else'user:'||user_id::text end person,
   (array_agg(author_name order by created_at desc nulls last,id))[1]name,sum(quantity)quantity
  from sales group by category,case when user_id is null then'legacy:'||id else'user:'||user_id::text end
 ),categories as(
  select category,jsonb_agg(jsonb_build_object('name',coalesce(nullif(btrim(name),''),'Collaborateur'),'quantity',quantity)
   order by quantity desc,name,person)people from people group by category
 )
 select jsonb_build_object('contributors123',(select coalesce(jsonb_object_agg(category,people),'{}')from categories),
 'last_sale_at123',(select max(created_at)from sales));
$$;
revoke all on function workshop_private.screen_sales123(date) from public,anon,authenticated;

create or replace function public.workshop_screen_sales123(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();
 if not exists(select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self' and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now()))then
  raise exception 'Compte suspendu ou accès indisponible.' using errcode='42501';
 end if;
 if not public.workshop_pc_access()then raise exception 'Accès écran refusé.' using errcode='42501';end if;
 perform workshop_private.assert_section('plan');
 if p_date is null then raise exception 'Date requise.';end if;
 return workshop_private.screen_sales123(p_date);
end $$;
revoke all on function public.workshop_screen_sales123(date) from public,anon,authenticated;
grant execute on function public.workshop_screen_sales123(date) to authenticated;

create or replace function public.workshop_screen_read123(p_token text,p_date date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;d date;begin
 -- La fonction existante valide le jeton, son expiration, la révocation, la maintenance et la rubrique.
 r:=public.workshop_screen_read89(p_token,p_date);
 if r is null or r?'unavailable'then return r;end if;
 d:=(r->>'date')::date;
 if d is null then raise exception 'Journée de l’écran indisponible.';end if;
 return r||jsonb_build_object('sales_details123',workshop_private.screen_sales123(d));
end $$;
revoke all on function public.workshop_screen_read123(text,date) from public,anon,authenticated;
-- L'accès sans session exige toujours le jeton secret du PC déjà autorisé.
grant execute on function public.workshop_screen_read123(text,date) to anon,authenticated;
notify pgrst,'reload schema';
commit;
