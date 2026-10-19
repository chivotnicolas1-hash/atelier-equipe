-- MAJ50 : appliquer après MAJ49. Réexécutable.
begin;
create or replace function public.workshop_target_sales_history(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Historique réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null then raise exception 'Date requise.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',s.id,'user_id',s.user_id,'category',s.category,'author_name',s.author_name,'quantity',s.quantity,'created_at',s.created_at,
  'version',s.version,'updated_at',s.updated_at,'updated_name',s.updated_name,
  'edits',(select coalesce(jsonb_agg(jsonb_build_object('old_quantity',e.old_quantity,'new_quantity',e.new_quantity,'editor_name',e.editor_name,'created_at',e.created_at) order by e.created_at desc,e.id desc),'[]'::jsonb) from public.workshop_target_sale_edits e where e.sale_id=s.id)
 ) order by s.created_at desc,s.id) from public.workshop_target_sales s where s.date=p_date and s.deleted_at is null),'[]'::jsonb);
end $$;


revoke all on function public.workshop_target_sales_history(date) from public,anon,authenticated;
grant execute on function public.workshop_target_sales_history(date) to authenticated;
notify pgrst,'reload schema';
commit;
