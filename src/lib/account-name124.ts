// La fiche de l'équipe est la source du nom, jamais l'adresse technique Auth.
export function accountDisplayName124(name?:string|null){
 const clean=(name||'').trim().replace(/\s+/g,' ');if(!clean)return 'Mon compte';
 const parts=clean.split(' ');let end=parts.length;
 const surname=(part:string)=>part===part.toLocaleUpperCase('fr-FR')&&part!==part.toLocaleLowerCase('fr-FR');
 while(end>0&&surname(parts[end-1]))end--;
 // Réordonne seulement un nom de famille déjà distingué en majuscules.
 // Sans cette information (ou si tout est en majuscules), conserve la fiche.
 return end>0&&end<parts.length?[...parts.slice(end),...parts.slice(0,end)].join(' '):clean;
}
