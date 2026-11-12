BEGIN;
-- MAJ88 : lecture et modification du code d'un article de catalogue.
-- Ne change ni l'identifiant ni le nom de l'article.
CREATE OR REPLACE FUNCTION public.workshop_catalog_code88(
 p_section text, p_id uuid, p_code text DEFAULT NULL,
 p_action text DEFAULT 'get', p_expected_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE a jsonb; current_code text; new_code text; result jsonb;
BEGIN
 a := workshop_private.actor();
 IF NOT coalesce((a->>'admin')::boolean,false) THEN
  RAISE EXCEPTION 'Réservé à l’administrateur.' USING errcode='42501';
 END IF;
 IF p_action NOT IN ('get','set') THEN RAISE EXCEPTION 'Action inconnue.'; END IF;
 -- Verrouillage de la section puis du produit, comme pour le renommage.
 PERFORM 1 FROM workshop_private.catalog75_rev WHERE section=p_section FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Section de catalogue introuvable.'; END IF;
 PERFORM 1 FROM workshop_private.catalog75 WHERE section=p_section AND id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Produit introuvable.'; END IF;
 SELECT coalesce((SELECT code FROM workshop_private.product_codes83 WHERE product_id=p_id),(SELECT min(x.code) FROM workshop_private.codes83 x JOIN workshop_private.catalog75 c ON c.id=p_id WHERE workshop_private.norm83(x.name)=workshop_private.norm83(c.name) HAVING count(distinct x.code)=1)) INTO current_code;
 IF p_action='get' THEN RETURN jsonb_build_object('id',p_id,'code',current_code); END IF;
 new_code:=nullif(btrim(coalesce(p_code,'')),'');
 IF new_code IS NULL OR length(new_code)>100 THEN RAISE EXCEPTION 'Le code doit contenir entre 1 et 100 caractères.'; END IF;
 IF current_code IS DISTINCT FROM nullif(btrim(coalesce(p_expected_code,'')),'')
    AND current_code IS DISTINCT FROM new_code THEN
  RAISE EXCEPTION 'Le code a été modifié entre-temps. Rouvre le catalogue avant de réessayer.';
 END IF;
 IF new_code IS NULL THEN
  DELETE FROM workshop_private.product_codes83 WHERE product_id=p_id;
 ELSE
  INSERT INTO workshop_private.product_codes83(product_id,code) VALUES(p_id,new_code)
  ON CONFLICT(product_id) DO UPDATE SET code=excluded.code;
 END IF;
 UPDATE workshop_private.catalog75_rev SET rev=rev+1 WHERE section=p_section;
 RETURN jsonb_build_object('id',p_id,'code',new_code);
END $function$;
REVOKE ALL ON FUNCTION public.workshop_catalog_code88(text,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.workshop_catalog_code88(text,uuid,text,text,text) TO authenticated;

-- Une seule lecture des codes par section, plutôt qu’une requête par article.
CREATE OR REPLACE FUNCTION public.workshop_catalog_codes88(p_section text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a jsonb;BEGIN
 a:=workshop_private.actor();
 IF NOT coalesce((a->>'admin')::boolean,false) THEN RAISE EXCEPTION 'Réservé à l’administrateur.' USING errcode='42501';END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'code',coalesce(pc.code,(SELECT min(x.code) FROM workshop_private.codes83 x WHERE workshop_private.norm83(x.name)=workshop_private.norm83(c.name) HAVING count(distinct x.code)=1)))),'[]') FROM workshop_private.catalog75 c LEFT JOIN workshop_private.product_codes83 pc ON pc.product_id=c.id WHERE c.section=p_section);
END$$;
REVOKE ALL ON FUNCTION public.workshop_catalog_codes88(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.workshop_catalog_codes88(text) TO authenticated;
NOTIFY pgrst,'reload schema';

COMMIT;
