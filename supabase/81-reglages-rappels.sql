begin;
create table if not exists workshop_private.settings81(id int primary key check(id=1),settings jsonb not null,version int not null default 1);
alter table workshop_private.settings81 enable row level security;
revoke all on workshop_private.settings81 from public,anon,authenticated;
insert into workshop_private.settings81(id,settings) values(1,'{"sections":{},"reminders":{"orders":{"enabled":true,"mode":"weekly","weekday":2,"time":"09:00","date":""},"waste":{"enabled":false,"mode":"weekly","weekday":5,"time":"09:00","date":""}}}') on conflict(id) do nothing;
create or replace function public.workshop_settings81(p_settings jsonb default null,p_version int default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;k text;v jsonb;begin
 a:=workshop_private.actor_before30();
 if p_settings is not null then
  a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
  if jsonb_typeof(p_settings->'sections') is distinct from 'object' or jsonb_typeof(p_settings->'reminders') is distinct from 'object' or octet_length(p_settings::text)>30000 then raise exception 'Réglages invalides.';end if;
  for k,v in select * from jsonb_each(p_settings->'sections') loop
   if not k=any(array['journee','plan','tasks','reports','team','orders','waste','polls','recap','quality','disputes','settings','inbox','leave','lunch','skills','catalog.oil','catalog.pneus','catalog.gaz','catalog.freins','waste.Grandidier','waste.Chimirec','waste.Gurdebeke']) then raise exception 'Section inconnue.';end if;
   if jsonb_typeof(v->'title') is distinct from 'string' or length(trim(v->>'title')) not between 1 and 90 or jsonb_typeof(v->'description') is distinct from 'string' or length(v->>'description')>300 then raise exception 'Nom ou description invalide.';end if;
  end loop;
  foreach k in array array['orders','waste'] loop
   r:=p_settings->'reminders'->k;
   if jsonb_typeof(r->'enabled') is distinct from 'boolean' or coalesce(r->>'mode','') not in ('weekly','once') or coalesce(r->>'time','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(r->>'weekday','') !~ '^[1-7]$' then raise exception 'Jour, heure ou fréquence invalide.';end if;
   if r->>'mode'='once' and (r->>'enabled')::boolean then
    if coalesce(r->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or (r->>'date')::date<(now() at time zone 'Europe/Paris')::date then raise exception 'Choisis aujourd’hui ou une date future.';end if;
   end if;
  end loop;
  update workshop_private.settings81 set settings=p_settings,version=version+1 where id=1 and version=p_version;
  if not found then raise exception 'Ces réglages ont changé. Ferme puis rouvre la configuration.';end if;
 end if;
 return (select jsonb_build_object('settings',settings,'version',version) from workshop_private.settings81 where id=1);
end $$;
revoke all on function public.workshop_settings81(jsonb,int) from public,anon;
grant execute on function public.workshop_settings81(jsonb,int) to authenticated;

-- Garde les autres rappels existants ; remplace seulement les rappels automatiques
-- Consommables/Déchets émis par l’ancien ordonnanceur.
create or replace function workshop_private.legacy_reminder81() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb:=to_jsonb(new);begin
 if current_setting('workshop.legacy_schedule81',true)='on' and
 (coalesce(j->>'url','') ~ '[?&](page|notifications)=(orders|waste)(&|$)' or coalesce(j->>'body','') ~* '^Pense.*(consommables|déchets|dechets)') then return null;end if;
 return new;
end $$;
drop trigger if exists legacy_reminder81 on public.workshop_messages;
create trigger legacy_reminder81 before insert on public.workshop_messages for each row execute function workshop_private.legacy_reminder81();
drop trigger if exists legacy_reminder81 on public.workshop_push_queue;
create trigger legacy_reminder81 before insert on public.workshop_push_queue for each row execute function workshop_private.legacy_reminder81();

do $$begin
 if to_regprocedure('workshop_private.schedule_messages_before81(timestamp with time zone)') is null then
  alter function workshop_private.schedule_messages(timestamptz) rename to schedule_messages_before81;
 end if;
end $$;
create or replace function workshop_private.schedule_messages(p_now timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare cfg jsonb;r jsonb;k text;person record;d date:=(p_now at time zone 'Europe/Paris')::date;t time:=(p_now at time zone 'Europe/Paris')::time;previous text;due boolean;begin
 previous:=current_setting('workshop.legacy_schedule81',true);
 perform set_config('workshop.legacy_schedule81','on',true);
 perform workshop_private.schedule_messages_before81(p_now);
 perform set_config('workshop.legacy_schedule81',coalesce(previous,''),true);
 select settings into cfg from workshop_private.settings81 where id=1;
 foreach k in array array['orders','waste'] loop
  r:=cfg->'reminders'->k;
  if not coalesce((r->>'enabled')::boolean,false) then continue;end if;
  due:=case when r->>'mode'='weekly' then extract(isodow from d)::int=(r->>'weekday')::int else d=nullif(r->>'date','')::date end;
  if not coalesce(due,false) or t<(r->>'time')::time then continue;end if;
  if k='orders' and not exists(select 1 from public.workshop_order_requests where status='pending' and deleted_at is null) then continue;end if;
  if k='waste' and not exists(select 1 from public.workshop_waste where collected_at is null) then continue;end if;
  for person in select distinct u.id from auth.users u left join public.workshop_staff s on s.email=lower(u.email) and s.active where lower(u.email)='nchivot@norauto.fr' or s.role='moderator' loop
   perform workshop_private.message(person.id,case when k='orders' then 'Pense à passer la commande des consommables' else 'Pense à vérifier les demandes d’enlèvement des déchets' end,'/?page='||k||'&mode=admin','settings81:'||k||':'||d::text);
  end loop;
 end loop;
exception when others then
 perform set_config('workshop.legacy_schedule81',coalesce(previous,''),true);raise;
end $$;
revoke all on function workshop_private.legacy_reminder81(),workshop_private.schedule_messages(timestamptz),workshop_private.schedule_messages_before81(timestamptz) from public,anon,authenticated;
notify pgrst,'reload schema';commit;
