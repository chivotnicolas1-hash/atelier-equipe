// Les fiches utilisent le format « Prénom Nom ». Les noms en capitales en tête sont aussi reconnus.
export function shortName(value:string){const parts=value.trim().split(/\s+/).filter(Boolean);if(parts.length<2)return parts[0]||'Collaborateur';
 const upper=(s:string)=>s===s.toLocaleUpperCase('fr')&&s!==s.toLocaleLowerCase('fr');
 if(upper(parts[0])&&!upper(parts[parts.length-1]))return parts.slice(1).join(' ')+'.'+Array.from(parts[0])[0].toLocaleUpperCase('fr');
 return parts.slice(0,-1).join(' ')+'.'+Array.from(parts[parts.length-1])[0].toLocaleUpperCase('fr');
}
