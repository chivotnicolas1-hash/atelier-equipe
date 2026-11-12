/** Rend les erreurs réseau Supabase compréhensibles sans les masquer. */
export function consumablesError88(error: unknown): string {
 const e = error as {message?:string;code?:string;details?:string;hint?:string}|null;
 if(e?.code==='PGRST202'||e?.code==='42883')return 'Fonction Supabase introuvable : vérifie que les scripts SQL de la mise à jour ont été exécutés.';
 const message=String(e?.message||error||'Erreur inconnue');
 if(/failed to fetch|fetch failed|networkerror|load failed|network request failed/i.test(message)){
  return 'Connexion momentanément indisponible. Les dernières données chargées restent affichées. Nouvelle tentative automatique au retour du réseau ou dans 20 secondes. Si tu enregistrais une modification, vérifie la liste avant de réessayer.';
 }
 return message;
}
