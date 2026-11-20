export type ToolId='tyres'|'electric'|'units'|'obd'|'oils'|'bulbs'|'fuses'|'fasteners'|'batteries'|'climate'|'community';
export type Source={name:string,url:string,licence?:string};
export type Card={id:string,base_key?:string|null,tool:ToolId,title:string,body:string,fields:Record<string,string>,sources:Source[],checked:string,category?:string,code?:string,manufacturer?:string,illustration?:string,has_photo?:boolean,photo?:string|null,version?:number,status?:string,author_name?:string,owner_id?:string,review_note?:string};
export const tools:{id:ToolId,title:string,description:string,tags:string}[]=[
{id:'tyres',title:'Pneumatiques',description:'Comparer deux dimensions et leur géométrie.',tags:'pneus diamètre vitesse taille'},
{id:'electric',title:'Électricité',description:'Loi d’Ohm, circuits, chute de tension et autonomie.',tags:'voltage ampère ohm puissance batterie'},
{id:'units',title:'Convertisseur',description:'Couple, pression, température et cinq autres familles.',tags:'unités PSI Nm litre fahrenheit'},
{id:'obd',title:'Codes défauts OBD',description:'Recherche locale P, B, C et U, avec sources.',tags:'diagnostic DTC moteur calculateur'},
{id:'oils',title:'Huiles moteur',description:'SAE, ACEA, API et homologations.',tags:'viscosité norme huile constructeur'},
{id:'bulbs',title:'Ampoules',description:'Références, culots et caractéristiques nominales.',tags:'phare éclairage halogène xénon H7'},
{id:'fuses',title:'Fusibles',description:'Formats, couleurs et calibres par famille.',tags:'protection circuit ATO MINI MAXI'},
{id:'fasteners',title:'Visserie et outillage',description:'Filetages, empreintes et modèles de serrage.',tags:'pas vis écrous Torx Allen XZN douille'},
{id:'batteries',title:'Batteries',description:'Technologies et interprétation prudente des mesures.',tags:'AGM EFB CCA Ah charge'},
{id:'climate',title:'Climatisation',description:'Fluides, huiles et tables de saturation.',tags:'R134a R1234yf pression température clim'},
{id:'community',title:'Bibliothèque de l’équipe',description:'Astuces et procédures validées par l’administrateur.',tags:'collaboratif expérience fiche liens'}];
export const norm=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
export function mergeCards(base:Card[],overrides:Card[]){const hidden=new Set(overrides.filter(c=>c.base_key).map(c=>c.base_key));return [...base.filter(c=>!hidden.has(c.id)),...overrides.filter(c=>c.status==='published')]}

export function isGenericOBD(code:string){return /^[PBCU][0-3][0-9A-F]{3}$/.test(code)&&(code[0]==='P'?['0','2'].includes(code[1])||(code.startsWith('P3')&&parseInt(code.slice(2),16)>=0x400):['0','3'].includes(code[1]))}

export function parsePtCard(card:Card){const rows=Object.entries(card.fields).map(([c,v])=>{const p=v.split(';').map(x=>Number(x.trim().replace(',','.')));const t=Number(c);if(!Number.isFinite(t)||t< -30||t>80||p.length!==2||p.some(n=>!Number.isFinite(n)||n<=0||n>50))throw Error('Table P/T invalide : températures de −30 à 80 °C et deux pressions absolues positives séparées par un point-virgule.');return {c:t,R134a:p[0],R1234yf:p[1]}}).sort((a,b)=>a.c-b.c);if(!rows.length||rows.some((r,i)=>i>0&&(r.c<=rows[i-1].c||r.R134a<=rows[i-1].R134a||r.R1234yf<=rows[i-1].R1234yf)))throw Error('Les températures et les pressions de saturation doivent augmenter.');return rows}
