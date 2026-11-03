// Propose only complete modern French registrations, never invent a missing character.
export function plateCandidates(text:string):string[]{
 const normalized=text.toUpperCase().replace(/[–—−]/g,'-');
 const found=new Set<string>();
 for(const match of normalized.matchAll(/(?:^|[^A-Z0-9])([A-Z]{2})[ \t-]*([0-9]{3})[ \t-]*([A-Z]{2})(?=$|[^A-Z0-9])/gm))found.add(`${match[1]}-${match[2]}-${match[3]}`);
 return [...found];
}
