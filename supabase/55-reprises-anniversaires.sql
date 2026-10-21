-- MAJ55 après MAJ54. Réexécutable.
begin;
create table if not exists public.workshop_birthdays(user_id uuid primary key references auth.users(id) on delete cascade,birth_date date not null,updated_at timestamptz not null default now());
alter table public.workshop_birthdays enable row level security;
revoke all on public.workshop_birthdays from public,anon,authenticated;
create or replace function public.workshop_birthday_get() returns jsonb language plpgsql security definer set search_path='' as $$
declare b date;begin perform workshop_private.actor();select birth_date into b from public.workshop_birthdays where user_id=auth.uid();return jsonb_build_object('birth_date',b,'birthday_today',coalesce(to_char(b,'MM-DD')=to_char(now() at time zone 'Europe/Paris','MM-DD'),false));end $$;
create or replace function public.workshop_birthday_save(p_date date) returns void language plpgsql security definer set search_path='' as $$
begin perform workshop_private.actor();if p_date is null then delete from public.workshop_birthdays where user_id=auth.uid();return;end if;
 if p_date<'1900-01-01' or p_date>(now() at time zone 'Europe/Paris')::date then raise exception 'Date de naissance invalide.';end if;
 insert into public.workshop_birthdays(user_id,birth_date) values(auth.uid(),p_date) on conflict(user_id) do update set birth_date=excluded.birth_date,updated_at=now();end $$;
-- Accès partagé limité à l’heure qui suit le retour prévu de déjeuner.
create or replace function workshop_private.lunch_team(p_now timestamptz) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;d date:=(p_now at time zone 'Europe/Paris')::date;back_at timestamptz;last_at timestamptz;begin
 a:=workshop_private.actor();
 select ((d::text||' '||gap.n)::timestamp at time zone 'Europe/Paris'),((d::text||' '||(select max(x->>'end') from jsonb_array_elements(dy.slots)x))::timestamp at time zone 'Europe/Paris') into back_at,last_at from public.workshop_days dy cross join lateral (select n from (select x->>'end' e,lead(x->>'start') over(order by x->>'start') n from jsonb_array_elements(dy.slots)x) z where e>='11:00' and e<'15:00' and n<='16:00' and e<n order by e limit 1) gap where dy.date=d and dy.staff_id=a->>'self' and dy.presence='present';
 if back_at is null or p_now<back_at or p_now>=least(back_at+interval '1 hour',last_at) then return '[]'::jsonb;end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'bt',h.bt,'remaining',h.remaining,'author_name',s.name,'created_at',h.created_at) order by h.created_at),'[]') from public.workshop_lunch_handoffs h join public.workshop_staff s on s.id=h.staff_id where h.date=d and h.taken_at is null and h.created_at<=back_at);
end $$;
create or replace function public.workshop_lunch_team() returns jsonb language sql security definer set search_path='' as $$ select workshop_private.lunch_team(now()) $$;
revoke all on function public.workshop_birthday_get(),public.workshop_birthday_save(date),public.workshop_lunch_team(),workshop_private.lunch_team(timestamptz) from public,anon,authenticated;
grant execute on function public.workshop_birthday_get(),public.workshop_birthday_save(date),public.workshop_lunch_team() to authenticated;
notify pgrst,'reload schema';commit;
