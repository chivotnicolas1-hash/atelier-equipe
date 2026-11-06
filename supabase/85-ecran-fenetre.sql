begin;
create table if not exists workshop_private.screen_devices85(id uuid primary key default gen_random_uuid(),name text not null,token_hash bytea not null unique,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '1 year',revoked_at timestamptz);
alter table workshop_private.screen_devices85 enable row level security;
revoke all on workshop_private.screen_devices85 from public,anon,authenticated;
create or replace function public.workshop_screen_devices85(p_action text default 'list',p_id uuid default null,p_name text default null,p_token text default null) returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;result uuid;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_action='create' then
  if p_token is null or p_token!~'^[0-9a-f]{64}$' or length(btrim(coalesce(p_name,''))) not between 1 and 80 then raise exception 'Nom du PC ou autorisation invalide.';end if;
  insert into workshop_private.screen_devices85(name,token_hash,created_by) values(btrim(p_name),sha256(convert_to(p_token,'UTF8')),auth.uid()) returning id into result;return jsonb_build_object('id',result);
 elsif p_action='revoke' then update workshop_private.screen_devices85 set revoked_at=coalesce(revoked_at,now()) where id=p_id;
 elsif p_action<>'list' then raise exception 'Action inconnue.';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'created_at',created_at,'expires_at',expires_at,'revoked_at',revoked_at) order by created_at desc),'[]') from workshop_private.screen_devices85);
end $$;
create or replace function public.workshop_screen_read85(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$declare device workshop_private.screen_devices85%rowtype;d date:=(now() at time zone 'Europe/Paris')::date;people jsonb;days jsonb;ann jsonb;begin
 if p_token is null or p_token!~'^[0-9a-f]{64}$' then raise exception 'Autorisation du PC invalide.' using errcode='42501';end if;
 select * into device from workshop_private.screen_devices85 where token_hash=sha256(convert_to(p_token,'UTF8')) and revoked_at is null and expires_at>now() for share;
 if not found then raise exception 'Autorisation du PC expirée ou retirée. Reconnecte un administrateur.' using errcode='42501';end if;
 if exists(select 1 from public.workshop_maintenance where id=1 and enabled) then return jsonb_build_object('unavailable','Application en maintenance');end if;
 if exists(select 1 from public.workshop_sections where section='plan' and disabled) then return jsonb_build_object('unavailable','Plan temporairement indisponible');end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'team',s.team,'role',s.role,'photo',(select p.photo from public.workshop_profiles p join auth.users u on u.id=p.user_id where lower(u.email)=lower(s.email) limit 1)) order by s.name),'[]') into people from public.workshop_staff s where s.active and coalesce(s.role,'employee') not in ('guest','director');
 select coalesce(jsonb_agg(jsonb_build_object('staff_id',x.staff_id,'presence',x.presence,'station',x.station,'geometry',x.geometry,'confirmed',x.confirmed,'slots',x.slots)),'[]') into days from public.workshop_days x join public.workshop_staff s on s.id=x.staff_id where x.date=d and s.active and coalesce(s.role,'employee') not in ('guest','director') and not exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods) p where l.staff_id=s.id and l.status='accepted' and d between (p->>'start')::date and (p->>'end')::date);
 select jsonb_build_object('enabled',enabled,'message',message,'audience',audience,'link_label',link_label) into ann from public.workshop_announcement where id=1 and enabled and audience<>'encadrants';
 return jsonb_build_object('date',d,'device_name',device.name,'generated_at',now(),
 'data',jsonb_build_object('staff',people,'days',days,'selected_target',jsonb_build_object('amount',(select amount from public.workshop_daily_targets where date=d)),'station_status',(select coalesce(jsonb_agg(jsonb_build_object('station_id',station_id,'status',status,'reason',reason)),'[]') from public.workshop_station_status)),
 'info',jsonb_build_object('settings',(select to_jsonb(s)-'id' from public.workshop_screen_settings s where id=1),'announcement',ann,'birthdays',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',split_part(s.name,' ',1))),'[]') from public.workshop_staff_birthdays b join public.workshop_staff s on s.id=b.staff_id where s.active and coalesce(s.role,'employee') not in ('guest','director') and to_char(b.birth_date,'MM-DD')=to_char(d,'MM-DD'))),
 'design',(select settings from public.workshop_design where id=1),'stations',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'number',number,'col',col,'row',row,'office',office,'rotate',rotate,'version',version) order by col,row),'[]') from public.workshop_stations where active));
end $$;
revoke all on function public.workshop_screen_devices85(text,uuid,text,text),public.workshop_screen_read85(text) from public,anon,authenticated;
grant execute on function public.workshop_screen_devices85(text,uuid,text,text) to authenticated;
grant execute on function public.workshop_screen_read85(text) to anon,authenticated;
-- Suppression personnelle : on garde uniquement la clé technique pour
-- empêcher la recréation d’un rappel déjà traité. Aucun autre compte touché.
create or replace function public.workshop_clear_notifications85() returns integer language plpgsql security definer set search_path='' as $$declare a jsonb;n integer;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('inbox');
 if auth.uid() is null or a->>'role'='guest' or exists(select 1 from public.workshop_staff where id=a->>'self' and role='guest') then raise exception 'Compte invité : lecture seule.' using errcode='42501';end if;
 update public.workshop_messages set deleted_at=now(),read_at=coalesce(read_at,now()),body='',url='/' where user_id=auth.uid() and deleted_at is null;get diagnostics n=row_count;return n;
end $$;
revoke all on function public.workshop_clear_notifications85() from public,anon;
grant execute on function public.workshop_clear_notifications85() to authenticated;
notify pgrst,'reload schema';commit;
