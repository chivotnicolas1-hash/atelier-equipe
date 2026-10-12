-- MAJ22 : appliquer après les migrations précédentes. Réexécutable.
begin;
create or replace function public.workshop_admin_photo(p_staff text,p_photo text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; u uuid;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administration.' using errcode='42501';end if;
 if p_photo is not null and (length(p_photo)>90000 or p_photo !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$') then raise exception 'Photo invalide.';end if;
 select users.id into u from public.workshop_staff s join auth.users users on lower(users.email)=s.email where s.id=p_staff and s.active for update of s;
 if u is null then raise exception 'Crée d’abord le compte de connexion du collaborateur.';end if;
 insert into public.workshop_profiles(user_id,photo) values(u,p_photo) on conflict(user_id) do update set photo=excluded.photo,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
create or replace function public.workshop_admin_target(p_date date,p_amount numeric,p_expected numeric)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; old_amount numeric;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administration.' using errcode='42501';end if;
 if p_date is null or p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<0 or p_amount>99999999 or round(p_amount,2)<>p_amount then raise exception 'Date ou montant invalide.';end if;
 -- Même verrou que l’import PDF : compare et écrit sans écrasement concurrent.
 lock table public.workshop_daily_targets in share row exclusive mode;
 select amount into old_amount from public.workshop_daily_targets where date=p_date;
 if old_amount is distinct from p_expected then raise exception 'Cet objectif a changé. Ferme cette fenêtre et recharge la journée avant de le modifier.';end if;
 insert into public.workshop_daily_targets(date,amount) values(p_date,p_amount) on conflict(date) do update set amount=excluded.amount,updated_at=now();
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_admin_photo(text,text),public.workshop_admin_target(date,numeric,numeric) from public,anon,authenticated;
grant execute on function public.workshop_admin_photo(text,text),public.workshop_admin_target(date,numeric,numeric) to authenticated;
commit;
