// Fêtes nationales, cas général en métropole (Fayet, Aisne).
// Source : https://www.service-public.gouv.fr/particuliers/vosdroits/F2405
export function holidayName(date:string):string|null{
 if(!/^\d{4}-\d{2}-\d{2}$/.test(date))return null;
 const y=Number(date.slice(0,4));const fixed:Record<string,string>={'01-01':'Jour de l’an','05-01':'Fête du Travail','05-08':'Victoire 1945','07-14':'Fête nationale','08-15':'Assomption','11-01':'Toussaint','11-11':'Armistice 1918','12-25':'Noël'};
 if(fixed[date.slice(5)])return fixed[date.slice(5)];
 // Comput grégorien de Meeus/Jones/Butcher, calcul en UTC pour éviter les décalages saisonniers.
 const a=y%19,b=Math.floor(y/100),c=y%100,d=Math.floor(b/4),e=b%4,f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),h=(19*a+b-d-g+15)%30,i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451),month=Math.floor((h+l-7*m+114)/31),day=(h+l-7*m+114)%31+1;
 for(const [offset,label] of [[1,'Lundi de Pâques'],[39,'Ascension'],[50,'Lundi de Pentecôte']] as const){if(new Date(Date.UTC(y,month-1,day+offset)).toISOString().slice(0,10)===date)return label}return null;
}
