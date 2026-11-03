export type TargetPiece={text:string,x:number,y:number,width:number};
export type DailyTargets={date:string,purge:number,batteries:number,geometry:number,clim:number};
export const targetLabels={purge:'Purge de freins',batteries:'Batteries montées',geometry:'Géométrie',clim:'Clim'} as const;
const normalize=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/\s+/g,' ').trim();
export function parseDailyTargets(pieces:TargetPiece[],year:number){
 if(!Number.isInteger(year)||year<2020||year>2099)throw Error('Indique une année entre 2020 et 2099.');
 const expected=['qtes prestations huile','qtes purge','qtes clim','qtes batteries montees','qtes beg','qtes pneus','qtes geometrie hors controle'];
 const titles=pieces.filter(p=>expected.includes(normalize(p.text))).sort((a,b)=>a.x-b.x);
 const presentExpected=expected.filter(t=>t!=='qtes beg'||titles.some(p=>normalize(p.text)===t));
 if(titles.length!==presentExpected.length||titles.some((t,i)=>normalize(t.text)!==presentExpected[i]))throw Error('Tableau A4 centre non reconnu : les groupes de colonnes doivent être visibles.');
 const labels=pieces.filter(p=>normalize(p.text)==='cible'&&Math.abs(p.y-titles[0].y)<30).sort((a,b)=>a.x-b.x);
 if(labels.length!==presentExpected.length)throw Error('Colonnes Cible incomplètes ou ambiguës. Réexporte le tableau complet.');
 const step=Math.min(...labels.slice(1).map((p,i)=>p.x-labels[i].x));if(step<=0)throw Error('Colonnes illisibles.');
 const dates=pieces.flatMap(p=>{const m=normalize(p.text).match(/^(lun|mar|mer|jeu|ven|sam|dim)\.?\s+(\d{2})\/(\d{2})(?:\/(\d{4}))?$/);return m?[{p,m}]:[]});
 if(!dates.length)throw Error('Aucune date lisible. Utilise un PDF texte et non une photo.');
 const rows:DailyTargets[]=[];
 for(const {p,m} of dates){const day=Number(m[2]),month=Number(m[3]),yr=m[4]?Number(m[4]):year;const d=new Date(Date.UTC(yr,month-1,day));if(yr!==year||d.getUTCFullYear()!==yr||d.getUTCMonth()!==month-1||d.getUTCDate()!==day||['dim','lun','mar','mer','jeu','ven','sam'][d.getUTCDay()]!==m[1])throw Error('Le jour '+m[0]+' ne correspond pas à l’année '+year+'. Vérifie l’année du document.');
 const values=labels.map((label,index)=>{if(presentExpected[index]==='qtes beg')return 0;const center=label.x+label.width/2;const cells=pieces.filter(t=>Math.abs(t.y-p.y)<2&&Math.abs(t.x+t.width/2-center)<step/6&&/^\d+$/.test(t.text.trim()));if(cells.length!==1)throw Error('Cible manquante ou ambiguë le '+m[2]+'/'+m[3]+'. Réexporte le PDF.');return Number(cells[0].text)});
 rows.push({date:yr+'-'+m[3]+'-'+m[2],purge:values[presentExpected.indexOf('qtes purge')],batteries:values[presentExpected.indexOf('qtes batteries montees')],geometry:values[presentExpected.indexOf('qtes geometrie hors controle')],clim:values[presentExpected.indexOf('qtes clim')]});
 }
 if(new Set(rows.map(r=>r.date)).size!==rows.length)throw Error('Dates en double dans le tableau.');
 const unknown=pieces.filter(p=>/^\d+$/.test(p.text.trim())&&Math.abs(p.x+p.width/2-(labels[0].x+labels[0].width/2))<step/6&&p.y<labels[0].y-3&&!dates.some(d=>Math.abs(d.p.y-p.y)<2)&&!pieces.some(t=>normalize(t.text)==='total'&&Math.abs(t.y-p.y)<2));
 return {rows:rows.sort((a,b)=>a.date.localeCompare(b.date)),warning:unknown.length?'Des lignes sans date lisible sont ignorées. Réexporte le tableau complet pour les jours manquants.':''};
}
