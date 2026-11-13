begin;
create or replace function workshop_private.screen_performance89(d date) returns jsonb language plpgsql security definer set search_path='' as $$
declare g jsonb;tot jsonb;custom_tot jsonb;labels jsonb;q jsonb;begin
 select jsonb_build_object('purge',purge,'batteries',batteries,'geometry',geometry,'clim',clim)
 into g from public.workshop_service_targets where date=d;
 g:=coalesce(g,'{}'::jsonb)||workshop_private.target_goals86(d);
 select coalesce(jsonb_object_agg(category,n),'{}'::jsonb) into tot from
 (select category,sum(quantity) n from public.workshop_target_sales
 where date=d and deleted_at is null and category in ('purge','batteries','geometry','clim') group by category)x;
 select coalesce(jsonb_object_agg('custom:'||target_id,n),'{}'::jsonb) into custom_tot from
 (select target_id,sum(quantity) n from workshop_private.sales86
 where date=d and deleted_at is null group by target_id)x;
 select coalesce(jsonb_object_agg('custom:'||id,name),'{}'::jsonb) into labels
 from workshop_private.targets86 where starts_on<=d;
 q:=jsonb_build_object('goal',coalesce((select goal from public.workshop_quality_goals where date=d),
 case when extract(isodow from d) between 1 and 6 then 2 else 0 end),
 'total',(select count(*) from public.workshop_quality_results where date=d and deleted_at is null));

return jsonb_build_object('targets',g,'totals',tot||custom_tot,'labels',labels,'quality',q);end $$;
CREATE OR REPLACE FUNCTION public.workshop_screen_read89(p_token text, p_date date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare device workshop_private.screen_devices85%rowtype;d date:=coalesce(p_date,(now() at time zone 'Europe/Paris')::date);people jsonb;days jsonb;ann jsonb;begin
 if p_token is null or p_token!~'^[0-9a-f]{64}$' then raise exception 'Autorisation du PC invalide.' using errcode='42501';end if;
 select * into device from workshop_private.screen_devices85 where token_hash=sha256(convert_to(p_token,'UTF8')) and revoked_at is null and expires_at>now() for share;
 if not found then raise exception 'Autorisation du PC expirée ou retirée. Reconnecte un administrateur.' using errcode='42501';end if;
 if exists(select 1 from public.workshop_maintenance where id=1 and enabled) then return jsonb_build_object('unavailable','Application en maintenance');end if;
 if exists(select 1 from public.workshop_sections where section='plan' and disabled) then return jsonb_build_object('unavailable','Plan temporairement indisponible');end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'team',s.team,'role',s.role,'photo',(select p.photo from public.workshop_profiles p join auth.users u on u.id=p.user_id where lower(u.email)=lower(s.email) limit 1)) order by s.name),'[]') into people from public.workshop_staff s where s.active and coalesce(s.role,'employee') not in ('guest','director');
 select coalesce(jsonb_agg(jsonb_build_object('staff_id',x.staff_id,'presence',x.presence,'station',x.station,'geometry',x.geometry,'confirmed',x.confirmed,'slots',x.slots)),'[]') into days from public.workshop_days x join public.workshop_staff s on s.id=x.staff_id where x.date=d and s.active and coalesce(s.role,'employee') not in ('guest','director') and not exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods) p where l.staff_id=s.id and l.status='accepted' and d between (p->>'start')::date and (p->>'end')::date);
 select jsonb_build_object('enabled',enabled,'message',message,'audience',audience,'link_label',link_label) into ann from public.workshop_announcement where id=1 and enabled and audience<>'encadrants';
 return jsonb_build_object('performance',workshop_private.screen_performance89(d),'date',d,'device_name',device.name,'generated_at',now(),
 'data',jsonb_build_object('staff',people,'days',days,'selected_target',jsonb_build_object('amount',(select amount from public.workshop_daily_targets where date=d)),'station_status',(select coalesce(jsonb_agg(jsonb_build_object('station_id',station_id,'status',status,'reason',reason)),'[]') from public.workshop_station_status)),
 'info',jsonb_build_object('settings',(select to_jsonb(s)-'id' from public.workshop_screen_settings s where id=1),'announcement',ann,'birthdays',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',split_part(s.name,' ',1))),'[]') from public.workshop_staff_birthdays b join public.workshop_staff s on s.id=b.staff_id where s.active and coalesce(s.role,'employee') not in ('guest','director') and to_char(b.birth_date,'MM-DD')=to_char(d,'MM-DD'))),
 'design',(select settings from public.workshop_design where id=1),'stations',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'number',number,'col',col,'row',row,'office',office,'rotate',rotate,'version',version) order by col,row),'[]') from public.workshop_stations where active));
end $function$
;

create or replace function public.workshop_screen_info89(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin
 r:=public.workshop_screen_read65();if p_date is null then raise exception 'Date requise';end if;
 return r||jsonb_build_object('birthdays',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',split_part(s.name,' ',1))),'[]')
 from public.workshop_staff_birthdays b join public.workshop_staff s on s.id=b.staff_id where s.active and coalesce(s.role,'employee') not in ('guest','director') and to_char(b.birth_date,'MM-DD')=to_char(p_date,'MM-DD')));
end $$;
revoke all on function workshop_private.screen_performance89(date) from public,anon,authenticated;
revoke all on function public.workshop_screen_read89(text,date) from public;
grant execute on function public.workshop_screen_read89(text,date) to anon,authenticated;
revoke all on function public.workshop_screen_info89(date) from public,anon;
grant execute on function public.workshop_screen_info89(date) to authenticated;
notify pgrst,'reload schema';commit;
