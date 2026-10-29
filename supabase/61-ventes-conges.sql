-- MAJ61 — après MAJ60. Réexécutable.
begin;
create table if not exists public.workshop_target_sale_authors(
 id bigint generated always as identity primary key,
 sale_id uuid not null references public.workshop_target_sales(id) on delete cascade,
 old_user_id uuid references auth.users(id) on delete set null,
 new_user_id uuid references auth.users(id) on delete set null,
 old_name text not null,new_name text not null,
 editor_id uuid references auth.users(id) on delete set null,
 editor_name text not null,created_at timestamptz not null default clock_timestamp()
);
alter table public.workshop_target_sale_authors enable row level security;
revoke all on public.workshop_target_sale_authors from public,anon,authenticated;
create index if not exists workshop_target_sale_authors_sale_idx on public.workshop_target_sale_authors(sale_id,created_at desc);
create or replace function public.workshop_target_sale_people() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('staff_id',s.id,'user_id',u.id,'name',s.name,'team',s.team) order by s.name,s.id),'[]') from public.workshop_staff s join auth.users u on lower(u.email)=lower(s.email) and u.email_confirmed_at is not null where s.active and s.role<>'guest');end $$;
create or replace function public.workshop_reassign_target_sale(p_id uuid,p_staff text,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_target_sales%rowtype;target_user uuid;target_name text;editor text;lock_user text;begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Correction réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select u.id,s.name into target_user,target_name from public.workshop_staff s join auth.users u on lower(u.email)=lower(s.email) and u.email_confirmed_at is not null where s.id=p_staff and s.active and s.role<>'guest';
 if target_user is null then raise exception 'Choisis un collaborateur actif disposant d’un compte de connexion.';end if;
 select * into r from public.workshop_target_sales where id=p_id;if r.id is null or r.deleted_at is not null then raise exception 'Vente introuvable ou supprimée.';end if;
 -- Même verrou que la saisie et la suppression ; ordre stable pour deux comptes.
 for lock_user in select distinct x from unnest(array[r.user_id::text,target_user::text]) x where x is not null order by x loop perform pg_advisory_xact_lock(hashtextextended('target-sale:'||lock_user,0));end loop;
 select * into r from public.workshop_target_sales where id=p_id for update;
 if r.id is null or r.deleted_at is not null then raise exception 'Vente introuvable ou supprimée.';end if;
 if p_version is distinct from r.version then raise exception 'Cette vente a été modifiée ailleurs. Actualise l’historique.';end if;
 if r.user_id=target_user then return;end if;
 select name into editor from public.workshop_staff where id=a->>'self';editor:=coalesce(editor,'Gestionnaire');
 insert into public.workshop_target_sale_authors(sale_id,old_user_id,new_user_id,old_name,new_name,editor_id,editor_name) values(p_id,r.user_id,target_user,r.author_name,target_name,auth.uid(),editor);
 update public.workshop_target_sales set user_id=target_user,author_name=target_name,version=version+1,updated_at=clock_timestamp(),updated_name=editor where id=p_id;
end $$;
create or replace function public.workshop_target_sales_history(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Historique réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null then raise exception 'Date requise.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
 'id',s.id,'user_id',s.user_id,'category',s.category,'author_name',s.author_name,'quantity',s.quantity,'created_at',s.created_at,'version',s.version,'updated_at',s.updated_at,'updated_name',s.updated_name,
 'author_changes',(select coalesce(jsonb_agg(jsonb_build_object('old_name',h.old_name,'new_name',h.new_name,'editor_name',h.editor_name,'created_at',h.created_at) order by h.created_at desc,h.id desc),'[]') from public.workshop_target_sale_authors h where h.sale_id=s.id),
 'edits',(select coalesce(jsonb_agg(jsonb_build_object('old_quantity',e.old_quantity,'new_quantity',e.new_quantity,'editor_name',e.editor_name,'created_at',e.created_at) order by e.created_at desc,e.id desc),'[]') from public.workshop_target_sale_edits e where e.sale_id=s.id)) order by s.created_at desc,s.id) from public.workshop_target_sales s where s.date=p_date and s.deleted_at is null),'[]');
end $$;
-- L’export demandé par un collaborateur est limité à sa propre demande acceptée.
create or replace function public.workshop_leave_download(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_leave_requests%rowtype;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('leave');
 select * into r from public.workshop_leave_requests where id=p_id for share;
 if r.id is null or (not coalesce((a->>'admin')::boolean,false) and (r.author_id is distinct from auth.uid() or r.status<>'accepted')) then raise exception 'Le téléchargement est disponible uniquement pour ta demande acceptée.' using errcode='42501';end if;
 return to_jsonb(r)-'author_id'-'staff_id'-'decided_by';end $$;
revoke all on function public.workshop_target_sale_people(),public.workshop_reassign_target_sale(uuid,text,integer),public.workshop_target_sales_history(date),public.workshop_leave_download(uuid) from public,anon,authenticated;
grant execute on function public.workshop_target_sale_people(),public.workshop_reassign_target_sale(uuid,text,integer),public.workshop_target_sales_history(date),public.workshop_leave_download(uuid) to authenticated;
notify pgrst,'reload schema';commit;
