BEGIN;
-- MAJ88 : réautorisation des écrans PC, réservée à l'administrateur.
CREATE OR REPLACE FUNCTION public.workshop_screen_devices85(p_action text DEFAULT 'list'::text, p_id uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_token text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE a jsonb; result uuid;
BEGIN
 a:=workshop_private.actor();
 IF NOT coalesce((a->>'admin')::boolean,false) THEN
  RAISE EXCEPTION 'Réservé à l’administrateur.' USING errcode='42501';
 END IF;
 IF p_action='create' THEN
  IF p_token IS NULL OR p_token!~'^[0-9a-f]{64}$' OR length(btrim(coalesce(p_name,''))) NOT BETWEEN 1 AND 80 THEN
   RAISE EXCEPTION 'Nom du PC ou autorisation invalide.';
  END IF;
  INSERT INTO workshop_private.screen_devices85(name,token_hash,created_by)
  VALUES(btrim(p_name),sha256(convert_to(p_token,'UTF8')),auth.uid())
  RETURNING id INTO result;
  RETURN jsonb_build_object('id',result);
 ELSIF p_action='revoke' THEN
  UPDATE workshop_private.screen_devices85 SET revoked_at=coalesce(revoked_at,now()) WHERE id=p_id;
 ELSIF p_action='reauthorize' THEN
  IF p_id IS NULL THEN RAISE EXCEPTION 'Identifiant du PC obligatoire.'; END IF;
  UPDATE workshop_private.screen_devices85
  SET revoked_at=NULL, expires_at=now()+interval '1 year'
  WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PC introuvable.'; END IF;
 ELSIF p_action<>'list' THEN
  RAISE EXCEPTION 'Action inconnue.';
 END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'created_at',created_at,'expires_at',expires_at,'revoked_at',revoked_at) ORDER BY created_at DESC),'[]'::jsonb)
 FROM workshop_private.screen_devices85);
END
$function$;

REVOKE ALL ON FUNCTION public.workshop_screen_devices85(text,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.workshop_screen_devices85(text,uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
