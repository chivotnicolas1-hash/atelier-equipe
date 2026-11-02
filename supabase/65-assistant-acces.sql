begin;
create or replace function public.workshop_pc_access() returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null and (lower(u.email)='nchivot@norauto.fr' or exists(select 1 from public.workshop_staff s where s.active and not s.suspended and lower(s.email)=lower(u.email) and s.role in ('moderator','director'))))
$$;
-- Préserver la logique d'annonce et de confidentialité existante pour les gestionnaires.
create or replace function public.workshop_screen_read65() returns jsonb language plpgsql security definer set search_path='' as $$
begin
if not public.workshop_pc_access() then raise exception 'Accès écran refusé' using errcode='42501';end if;
if not exists(select 1 from public.workshop_staff s join auth.users u on lower(s.email)=lower(u.email) where u.id=auth.uid() and s.role='director') then return public.workshop_screen_info();end if;
return jsonb_build_object('settings',(select to_jsonb(s)-'id' from public.workshop_screen_settings s where id=1),'birthdays',(select coalesce(jsonb_agg(jsonb_build_object('name',s.name,'id',s.id)),'[]') from public.workshop_staff_birthdays b join public.workshop_staff s on s.id=b.staff_id where s.active and s.role<>'guest' and to_char(b.birth_date,'MM-DD')=to_char(now() at time zone 'Europe/Paris','MM-DD')),'announcement',public.workshop_load((now() at time zone 'Europe/Paris')::date)->'announcement');
end $$;
create or replace function public.workshop_assistant65(p_week boolean default false) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a jsonb; t timestamp:=now() at time zone 'Europe/Paris'; d date; e date; l timestamptz; h timestamptz; events jsonb;
begin
a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
if p_week then e:=date_trunc('week',t)::date;if t<e+time '08:30' then e:=e-7;end if;d:=e-7;else e:=t::date;d:=e-1;end if;
l:=d::timestamp at time zone 'Europe/Paris';h:=e::timestamp at time zone 'Europe/Paris';
select coalesce(jsonb_agg(jsonb_build_object('group',g,'text',msg,'at',dt,'action',act) order by dt desc),'[]') into events from (
select 'Signalements' g, registration||' · '||coalesce(nullif(notes,''),'Signalement enregistré') msg,created_at dt,false act from public.workshop_reports where created_at>=l and created_at<h
union all select 'Consommables','Liste de '||jsonb_array_length(items)||' article(s) · '||case status when 'validated' then 'validée' else 'à valider' end||coalesce(' : '||(select string_agg(x->>'label',', ') from jsonb_array_elements(items) x),''),case when updated_at>=l and updated_at<h then updated_at else created_at end,status='pending' from public.workshop_order_requests where (created_at>=l and created_at<h or updated_at>=l and updated_at<h)
union all select 'Déchets',concat_ws(' · ',provider,(select string_agg(x,', ') from jsonb_array_elements_text(categories) x),case when collected_at is not null then 'ramassage effectué' when validated_at is not null then 'en attente de ramassage' else 'demande à valider' end),created_at,collected_at is null from public.workshop_waste where created_at>=l and created_at<h
union all select 'Congés',concat_ws(' ',first_name,last_name)||' · '||case status when 'pending' then 'toujours en attente d’accord' when 'accepted' then 'accordée' when 'refused' then 'refusée' else 'autre proposition' end,created_at,status='pending' from public.workshop_leave_requests where created_at>=l and created_at<h
union all select 'BT à reprendre','BT '||bt||' · '||case when taken_at is null then 'à reprendre' else 'repris' end||' · '||remaining,created_at,taken_at is null from public.workshop_lunch_handoffs where date>=d and date<e
) z;
return jsonb_build_object('start',d,'end',e-1,'events',events,'pending',(select count(*) from public.workshop_leave_requests where status='pending'));
end $$;
revoke all on function public.workshop_pc_access(),public.workshop_screen_read65(),public.workshop_assistant65(boolean) from public,anon;
grant execute on function public.workshop_pc_access(),public.workshop_screen_read65(),public.workshop_assistant65(boolean) to authenticated;
notify pgrst,'reload schema';commit;
