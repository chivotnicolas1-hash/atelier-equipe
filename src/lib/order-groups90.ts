const sections=['Divers liquides','Pneus','5gaz','Freins, transmissions, roulements','Hygiène, protection et nettoyage','Divers'];
export const sectionText90:Record<string,string>={'Divers liquides':'catalog.oil','Pneus':'catalog.pneus','5gaz':'catalog.gaz','Freins, transmissions, roulements':'catalog.freins','Hygiène, protection et nettoyage':'catalog.hygiene'};
export function orderGroups90<T extends {section90?:string}>(items:T[]){
 const groups=new Map<string,T[]>();for(const item of items){const section=item.section90||'Divers';groups.set(section,[...(groups.get(section)||[]),item]);}
 return [...groups].sort(([a],[b])=>(sections.includes(a)?sections.indexOf(a):99)-(sections.includes(b)?sections.indexOf(b):99));
}
