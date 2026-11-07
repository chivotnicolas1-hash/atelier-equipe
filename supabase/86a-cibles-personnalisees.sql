begin;
create table if not exists workshop_private.targets86(id uuid primary key,name text not null,default_goal integer not null check(default_goal between 0 and 100000),starts_on date not null,created_at timestamptz not null default now());
create unique index if not exists target_name86 on workshop_private.targets86(lower(btrim(name)));
create table if not exists workshop_private.target_goals86(target_id uuid references workshop_private.targets86(id),date date,goal integer not null check(goal between 0 and 100000),primary key(target_id,date));
create table if not exists workshop_private.sales86(id uuid primary key,target_id uuid not null references workshop_private.targets86(id),date date not null,user_id uuid not null references auth.users(id),author_name text not null,quantity integer not null default 1 check(quantity between 0 and 10000),created_at timestamptz not null default now(),version integer not null default 1,deleted_at timestamptz,updated_name text,updated_at timestamptz,edits jsonb not null default '[]',author_changes jsonb not null default '[]');
alter table workshop_private.targets86 enable row level security;alter table workshop_private.target_goals86 enable row level security;alter table workshop_private.sales86 enable row level security;
revoke all on workshop_private.targets86,workshop_private.target_goals86,workshop_private.sales86 from public,anon,authenticated;
create or replace function workshop_private.target_goals86(p_date date) returns jsonb language sql stable set search_path='' as $$select coalesce(jsonb_object_agg('custom:'||t.id,coalesce(g.goal,case when extract(isodow from p_date)=7 then 0 else t.default_goal end)),'{}') from workshop_private.targets86 t left join workshop_private.target_goals86 g on g.target_id=t.id and g.date=p_date where t.starts_on<=p_date$$;
create or replace function public.workshop_targets86(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$declare b jsonb;g jsonb;tot jsonb;nxt jsonb;begin
 b:=public.workshop_target_sales_status(p_date);g:=workshop_private.target_goals86(p_date);
 select coalesce(jsonb_object_agg(k,n),'{}') into tot from(select 'custom:'||target_id k,sum(quantity) n from workshop_private.sales86 where date=p_date and deleted_at is null group by target_id) x;
 select coalesce(jsonb_object_agg(k,n),'{}') into nxt from(select 'custom:'||target_id k,max(created_at)+interval '5 minutes' n from workshop_private.sales86 where date=p_date and user_id=auth.uid() and deleted_at is null group by target_id) x;
 if coalesce((b->>'manager')::boolean,false) then nxt:='{}';end if;
 if coalesce((b->>'guest')::boolean,false) then tot:='{}';nxt:='{}';end if;
 return b||jsonb_build_object('base_targets',b->'targets','custom_goals',g,'labels',(select coalesce(jsonb_object_agg('custom:'||id,name),'{}') from workshop_private.targets86 where starts_on<=p_date),'targets',case when g='{}' then b->'targets' else coalesce(nullif(b->'targets','null'::jsonb),'{}')||g end,'totals',coalesce(b->'totals','{}')||tot,'next_allowed_by_category',coalesce(b->'next_allowed_by_category','{}')||nxt);
end $$;
create or replace function public.workshop_target_create86(p_id uuid,p_name text,p_goal integer,p_date date) returns void language plpgsql security definer set search_path='' as $$declare a jsonb;n text;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Seul l’administrateur peut créer une cible.' using errcode='42501';end if;
 n:=btrim(regexp_replace(coalesce(p_name,''),'[[:space:]]+',' ','g'));if length(n) not between 1 and 80 or p_goal is null or p_goal not between 0 and 100000 or p_date is null or p_date<date '2020-01-01' or p_date>date '2099-12-31' then raise exception 'Nom, date ou quantité invalide.';end if;
 if lower(n)=any(array['purge de freins','batteries montées','géométrie','clim','contrôle qualité','contrôles qualité']) then raise exception 'Cette cible existe déjà.';end if;
 if exists(select 1 from workshop_private.targets86 where id=p_id and name=n and default_goal=p_goal and starts_on=p_date) then return;end if;
 insert into workshop_private.targets86(id,name,default_goal,starts_on) values(p_id,n,p_goal,p_date);
 insert into workshop_private.target_goals86(target_id,date,goal) values(p_id,p_date,p_goal);
end $$;
create or replace function public.workshop_targets_save86(p_date date,p_targets jsonb,p_expected jsonb) returns void language plpgsql security definer set search_path='' as $$declare a jsonb;k text;v jsonb;g jsonb;base jsonb;begin
 a:=workshop_private.actor();perform pg_advisory_xact_lock(hashtextextended('targets86:'||p_date,0));g:=workshop_private.target_goals86(p_date);
 if g is distinct from p_expected->'custom' then raise exception 'Les cibles ont changé. Ferme puis rouvre le formulaire.';end if;
 for k,v in select * from jsonb_each(g) loop
  if jsonb_typeof(p_targets->k) is distinct from 'number' or (p_targets->>k)::numeric not between 0 and 100000 or (p_targets->>k)::numeric<>trunc((p_targets->>k)::numeric) then raise exception 'Cible invalide.';end if;
 end loop;
 base:=jsonb_build_object('purge',p_targets->'purge','batteries',p_targets->'batteries','geometry',p_targets->'geometry','clim',p_targets->'clim');
 -- La fonction existante contrôle les droits (gestionnaires ou délégation).
 perform public.workshop_save_service_targets(p_date,base,p_expected->'base');
 for k,v in select * from jsonb_each(g) loop insert into workshop_private.target_goals86(target_id,date,goal) values(substring(k from 8)::uuid,p_date,(p_targets->>k)::integer) on conflict(target_id,date) do update set goal=excluded.goal;end loop;
end $$;
create or replace function public.workshop_target_add86(p_id uuid,p_date date,p_category text) returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;b jsonb;t uuid;r workshop_private.sales86%rowtype;n text;begin
 if p_category not like 'custom:%' then perform public.workshop_add_target_sale(p_id,p_date,p_category);return public.workshop_targets86(p_date);end if;
 a:=workshop_private.actor();b:=public.workshop_target_sales_status(p_date);if not coalesce((b->>'can_add')::boolean,false) or coalesce((b->>'guest')::boolean,false) then raise exception 'Saisie non autorisée pour cette journée.' using errcode='42501';end if;
 t:=substring(p_category from 8)::uuid;
 if not exists(select 1 from workshop_private.targets86 where id=t and starts_on<=p_date) then raise exception 'Cible introuvable.';end if;
 perform pg_advisory_xact_lock(hashtextextended('sale86:'||auth.uid()||':'||p_category,0));select * into r from workshop_private.sales86 where id=p_id;
 if found then if r.user_id=auth.uid() and r.target_id=t and r.date=p_date and r.deleted_at is null then return public.workshop_targets86(p_date);else raise exception 'Identifiant de saisie déjà utilisé.';end if;end if;
 if not coalesce((b->>'manager')::boolean,false) and exists(select 1 from workshop_private.sales86 where user_id=auth.uid() and target_id=t and date=p_date and deleted_at is null and created_at>now()-interval '5 minutes') then raise exception 'Attends 5 minutes entre deux ventes sur cette cible.';end if;
 select name into n from public.workshop_staff where id=a->>'self';if n is null then raise exception 'Collaborateur introuvable.';end if;
 insert into workshop_private.sales86(id,target_id,date,user_id,author_name) values(p_id,t,p_date,auth.uid(),n);return public.workshop_targets86(p_date);
end $$;
create or replace function public.workshop_target_history86(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not workshop_private.manage83() then raise exception 'Accès réservé aux gestionnaires.' using errcode='42501';end if;
 return (select coalesce(jsonb_agg((to_jsonb(s)-'target_id'-'deleted_at')||jsonb_build_object('category','custom:'||s.target_id) order by created_at desc),'[]') from workshop_private.sales86 s where date=p_date and deleted_at is null);
end $$;
create or replace function public.workshop_target_correct86(p_id uuid,p_version integer,p_quantity integer default null,p_staff text default null,p_delete boolean default false) returns void language plpgsql security definer set search_path='' as $$declare a jsonb;r workshop_private.sales86%rowtype;editor text;person text;uid uuid;begin
 a:=workshop_private.actor();if not workshop_private.manage83() then raise exception 'Accès réservé aux gestionnaires.' using errcode='42501';end if;
 select * into r from workshop_private.sales86 where id=p_id and deleted_at is null for update;if not found or r.version is distinct from p_version then raise exception 'Saisie modifiée. Rouvre le suivi.';end if;
 select name into editor from public.workshop_staff where id=a->>'self';editor:=coalesce(editor,'Gestionnaire');
 if p_delete then update workshop_private.sales86 set deleted_at=now(),version=version+1,updated_name=editor,updated_at=now() where id=p_id;return;end if;
 if p_staff is not null then
  select s.name,u.id into person,uid from public.workshop_staff s join auth.users u on lower(u.email)=lower(s.email) where s.id=p_staff and s.active and s.role not in ('guest','director');if uid is null then raise exception 'Collaborateur invalide.';end if;
  update workshop_private.sales86 set user_id=uid,author_name=person,author_changes=author_changes||jsonb_build_array(jsonb_build_object('old_name',r.author_name,'new_name',person,'editor_name',editor,'created_at',now())),version=version+1,updated_name=editor,updated_at=now() where id=p_id;
 else
  if p_quantity is null or p_quantity not between 0 and 10000 then raise exception 'Quantité invalide.';end if;
  update workshop_private.sales86 set quantity=p_quantity,edits=edits||jsonb_build_array(jsonb_build_object('old_quantity',r.quantity,'new_quantity',p_quantity,'editor_name',editor,'created_at',now())),version=version+1,updated_name=editor,updated_at=now() where id=p_id;
 end if;
end $$;
-- Les nouvelles catégories participent aussi au bilan mensuel existant.
do $$begin if to_regprocedure('public.workshop_monthly82_before86(date)') is null then alter function public.workshop_monthly82(date) rename to workshop_monthly82_before86;end if;end $$;
create or replace function public.workshop_monthly82(p_month date default null) returns jsonb language plpgsql security definer set search_path='' as $$declare b jsonb;m date;extra jsonb;begin
 b:=public.workshop_monthly82_before86(p_month);m:=(b->>'month')::date;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into extra from(select user_id,max(author_name) author_name,'custom:'||target_id category,sum(quantity) quantity from workshop_private.sales86 where date>=m and date<(m+interval '1 month')::date and deleted_at is null group by user_id,target_id)x;
 return b||jsonb_build_object('sales',coalesce(b->'sales','[]')||extra,'custom_labels',(select coalesce(jsonb_object_agg('custom:'||id,name),'{}') from workshop_private.targets86 where starts_on<(m+interval '1 month')::date));end $$;
revoke all on function workshop_private.target_goals86(date),public.workshop_monthly82_before86(date) from public,anon,authenticated;
revoke all on function public.workshop_targets86(date),public.workshop_target_create86(uuid,text,integer,date),public.workshop_targets_save86(date,jsonb,jsonb),public.workshop_target_add86(uuid,date,text),public.workshop_target_history86(date),public.workshop_target_correct86(uuid,integer,integer,text,boolean) from public,anon;
grant execute on function public.workshop_targets86(date),public.workshop_target_create86(uuid,text,integer,date),public.workshop_targets_save86(date,jsonb,jsonb),public.workshop_target_add86(uuid,date,text),public.workshop_target_history86(date),public.workshop_target_correct86(uuid,integer,integer,text,boolean) to authenticated;
notify pgrst,'reload schema';commit;
