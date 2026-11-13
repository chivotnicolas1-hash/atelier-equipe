begin;
create table if not exists workshop_private.oil_codes89(id text primary key,code text not null check(length(code)<=100));
alter table workshop_private.oil_codes89 enable row level security;
revoke all on workshop_private.oil_codes89 from public,anon,authenticated;
create or replace function public.workshop_oil_codes89() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 return(select coalesce(jsonb_object_agg(id,code),'{}') from workshop_private.oil_codes89);end $$;
create or replace function public.workshop_oil_editor89() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 perform 1 from workshop_private.oil_catalog72 where id=1 for share;
 return public.workshop_oils72()||jsonb_build_object('codes',public.workshop_oil_codes89());end $$;
create or replace function public.workshop_oils_save89(p_items jsonb,p_version integer,p_codes jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;k text;v jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 if jsonb_typeof(p_codes) is distinct from 'object' or octet_length(p_codes::text)>30000 then raise exception 'Codes invalides';end if;
 if jsonb_typeof(p_items) is distinct from 'array' or exists(select 1 from jsonb_array_elements(p_items) x where coalesce(x->>'id','')='' or x ? 'code') or exists(select 1 from jsonb_array_elements(p_items) x group by x->>'id' having count(*)>1) then raise exception 'Références invalides';end if;
 for k,v in select * from jsonb_each(p_codes) loop
  if jsonb_typeof(v) is distinct from 'string' or length(v#>>'{}')>100 or not exists(select 1 from jsonb_array_elements(p_items) x where x->>'id'=k) then raise exception 'Code ou référence invalide';end if;end loop;
 r:=public.workshop_oils72(p_items,p_version);
 for k,v in select * from jsonb_each(p_codes) loop
  insert into workshop_private.oil_codes89(id,code) values(k,btrim(v#>>'{}')) on conflict(id) do update set code=excluded.code;end loop;
 delete from workshop_private.oil_codes89 c where not exists(select 1 from jsonb_array_elements(p_items) x where x->>'id'=c.id);
 return r;end $$;
do $$ begin
 if to_regprocedure('public.workshop_order_codes83_before89(uuid)') is null then alter function public.workshop_order_codes83(uuid) rename to workshop_order_codes83_before89;end if;end $$;
create or replace function public.workshop_order_codes83(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare base jsonb;rows jsonb;begin
 base:=public.workshop_order_codes83_before89(p_id);
 select coalesce(jsonb_agg(case when c.code is not null then b||jsonb_build_object('code',c.code) else b end order by ord),'[]') into rows
 from jsonb_array_elements(base) with ordinality q(b,ord)
 left join lateral (select oc.code from workshop_private.match_product79(b) m join workshop_private.oil_codes89 oc on oc.id=m.id where m.kind='oil' and (select count(*) from workshop_private.match_product79(b))=1) c on true;
 return rows;end $$;
revoke all on function public.workshop_order_codes83_before89(uuid) from public,anon,authenticated;
revoke all on function public.workshop_order_codes83(uuid),public.workshop_oil_codes89(),public.workshop_oil_editor89(),public.workshop_oils_save89(jsonb,integer,jsonb) from public,anon;
grant execute on function public.workshop_order_codes83(uuid),public.workshop_oil_codes89(),public.workshop_oil_editor89(),public.workshop_oils_save89(jsonb,integer,jsonb) to authenticated;
notify pgrst,'reload schema';commit;
