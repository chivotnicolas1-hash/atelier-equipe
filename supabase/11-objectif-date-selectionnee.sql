-- À exécuter après la migration 10. Conserve les objectifs déjà importés.
begin;
create or replace function public.workshop_load(p_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; v_staff jsonb; v_days jsonb; v_tasks jsonb;
begin
 a:=workshop_private.actor(); v_admin:=(a->>'admin')::boolean;
 if p_date is null then raise exception 'Choisis une date.'; end if;
 select coalesce(jsonb_agg(case when v_admin then to_jsonb(s)||jsonb_build_object('photo',(select p.photo from public.workshop_profiles p join auth.users u on u.id=p.user_id where lower(u.email)=s.email limit 1)) else jsonb_build_object('id',s.id,'name',s.name,'team',s.team) end order by s.id),'[]'::jsonb)
 into v_staff from public.workshop_staff s where s.active;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.staff_id),'[]'::jsonb) into v_days
 from public.workshop_days d where d.date=p_date and exists(select 1 from public.workshop_staff s where s.id=d.staff_id and s.active);
 select coalesce(jsonb_agg(to_jsonb(t) order by t.done,t.due,t.created_at desc),'[]'::jsonb) into v_tasks
 from public.workshop_tasks t where exists(select 1 from public.workshop_staff s where s.id=t.staff_id and s.active) and ((a->>'manager')::boolean or t.staff_id=a->>'self');
 return a || jsonb_build_object('staff',v_staff,'days',v_days,'tasks',v_tasks,'date',p_date,'profile',jsonb_build_object('photo',(select photo from public.workshop_profiles where user_id=auth.uid())),'announcement',(select jsonb_build_object('message',message,'enabled',enabled,'updated_at',updated_at,'link_url',link_url,'link_label',link_label) from public.workshop_announcement where id=1),
 'selected_target',jsonb_build_object('date',p_date,'amount',(select amount from public.workshop_daily_targets where date=p_date)),
 'today_target',jsonb_build_object('date',(now() at time zone 'Europe/Paris')::date,'amount',(select amount from public.workshop_daily_targets where date=(now() at time zone 'Europe/Paris')::date)),
 'custom_buttons',(select coalesce(jsonb_agg(to_jsonb(b) order by b.position,b.label,b.id),'[]'::jsonb) from public.workshop_custom_buttons b where v_admin or (b.enabled and (b.audience='all' or (b.audience='encadrants' and (a->>'reports_all')::boolean) or (b.audience='management' and (a->>'manager')::boolean)))));
end $$;
revoke all on function public.workshop_load(date) from public, anon, authenticated;
grant execute on function public.workshop_load(date) to authenticated;

notify pgrst, 'reload schema';
commit;
