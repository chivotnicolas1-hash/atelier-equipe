-- Appliquer après 01-installation.sql. Aucune donnée effacée.
begin;
create or replace function workshop_private.actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text; v_staff text; v_admin boolean;
begin
 if auth.uid() is null then raise exception 'Connexion requise.' using errcode='42501'; end if;
 if coalesce(auth.jwt()->'app_metadata'->>'provider','') <> 'email' or not exists (select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb)) m where m->>'method'='password') then
  raise exception 'Connecte-toi avec les identifiants fournis par ton administrateur.' using errcode='42501';
 end if;
 select lower(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'Une adresse e-mail vérifiée est nécessaire.' using errcode='42501'; end if;
 v_admin := v_email='nchivot@norauto.fr';
 select id into v_staff from public.workshop_staff where email=v_email;
 if not v_admin and v_staff is null then
  raise exception 'Cette adresse n’est pas autorisée. Demande à l’administrateur de renseigner ton adresse e-mail dans Équipe.' using errcode='42501';
 end if;
 return jsonb_build_object('admin',v_admin,'self',v_staff,'user',v_email);
end $$;
revoke all on function workshop_private.actor() from public, anon, authenticated;


-- Fonction réservée au serveur de création des comptes, jamais au navigateur.
create or replace function public.workshop_account_id(p_staff_id text)
returns uuid language sql security definer set search_path = '' as $$
 select u.id from auth.users u join public.workshop_staff s on s.email=lower(u.email) where s.id=p_staff_id limit 1;
$$;
revoke all on function public.workshop_account_id(text) from public,anon,authenticated;
grant execute on function public.workshop_account_id(text) to service_role;

notify pgrst, 'reload schema';
commit;
