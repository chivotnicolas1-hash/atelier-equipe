export type Piece={text:string,x:number,y:number,width:number};
export type Slot={start:string,end:string};
export type ImportDay={date:string,status:string,slots:Slot[],raw:string,review:boolean,include:boolean,slotText?:string};
export type ImportPerson={name:string,staffId:string,days:ImportDay[]};
export const normalizedName=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim().split(/\s+/).sort().join(' ');
const norm=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const months:Record<string,string>={jan:'01',janv:'01',fev:'02',fevr:'02',mars:'03',avr:'04',avril:'04',mai:'05',juin:'06',juil:'07',juillet:'07',aout:'08',sep:'09',sept:'09',oct:'10',nov:'11',dec:'12'};
function headerDate(s:string){const m=norm(s).match(/(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+(\d{1,2})\s+([a-z]+)\.?\s+(\d{4})/);if(!m||!months[m[2]])return null;return `${m[3]}-${months[m[2]]}-${m[1].padStart(2,'0')}`;}
export function readCell(raw:string,date:string):ImportDay{
 const text=norm(raw);const slots:Slot[]=[];
 for(const m of raw.matchAll(/(\d{1,2}[:h]\d{2})\s*[-–—]\s*(\d{1,2}[:h]\d{2})/g))slots.push({start:m[1].replace('h',':').padStart(5,'0'),end:m[2].replace('h',':').padStart(5,'0')});
 let status='unknown',review=false;
 if(/maladie|absence|absent/.test(text)){status='absent';review=true;}
 else if(/formation/.test(text)){status='unknown';review=true;}
 else if(/conge|vacances/.test(text)){status='leave';review=true;}
 else if(/non affecte|libre|repos/.test(text)){status='rest';review=slots.length>0;}
 else if(slots.length){status='present';review=/ead|s4j/.test(text);}
 else review=true;
 if(slots.some((s,i)=>!/^([01]\d|2[0-3]):[0-5]\d$/.test(s.start)||!/^([01]\d|2[0-3]):[0-5]\d$/.test(s.end)||s.end<=s.start||(i>0&&s.start<slots[i-1].end)))review=true;
 return {date,status,slots,raw,review,include:!review};
}
export function parsePage(pieces:Piece[],staff:{id:string,name:string}[]):ImportPerson[]{
 const headers=pieces.map(p=>({...p,date:headerDate(p.text)})).filter(p=>p.date).sort((a,b)=>a.x-b.x);
 if(headers.length!==7)throw Error('Ce PDF ne présente pas les 7 colonnes de dates du planning hebdomadaire attendu. Aucun import effectué.');
 const centers=headers.map(p=>p.x+p.width/2);const gap=(centers[6]-centers[0])/6;const left=centers[0]-gap/2;
 for(let i=1;i<7;i++){if(new Date(headers[i].date!+'T12:00:00Z').getTime()-new Date(headers[i-1].date!+'T12:00:00Z').getTime()!==86400000)throw Error('Les dates du planning ne sont pas consécutives.');}
 const names=pieces.filter(p=>p.x<left-10&&p.y<headers[0].y-10&&p.text.trim().length>4&&p.text===p.text.toUpperCase()&&/^[\p{L}\s'’.-]+$/u.test(p.text)&&p.text.trim().includes(' ')).sort((a,b)=>b.y-a.y);
 if(!names.length)throw Error('Aucun nom lisible dans le PDF. Utilise l’export Orquest original, pas une photo ou un PDF scanné.');
 return names.map((name,r)=>{
 const top=r===0?headers[0].y-12:(names[r-1].y+name.y)/2;const bottom=r===names.length-1?name.y-16:(name.y+names[r+1].y)/2;
 const matches=staff.filter(s=>normalizedName(s.name)===normalizedName(name.text));
 return {name:name.text,staffId:matches.length===1?matches[0].id:'',days:headers.map((h,i)=>{
 const lo=i===0?left:(centers[i-1]+centers[i])/2;const hi=i===6?centers[i]+gap/2:(centers[i]+centers[i+1])/2;
 const cell=pieces.filter(p=>p.y<top&&p.y>bottom&&p.x+p.width/2>=lo&&p.x+p.width/2<hi).sort((a,b)=>Math.abs(a.y-b.y)>3?b.y-a.y:a.x-b.x);
 return readCell(cell.map(p=>p.text).join(' '),h.date!);
 })};
 });
}
export function validSlots(slots:Slot[]){return slots.length<=4&&slots.every((s,i)=>/^([01]\d|2[0-3]):[0-5]\d$/.test(s.start)&&/^([01]\d|2[0-3]):[0-5]\d$/.test(s.end)&&s.end>s.start&&(i===0||s.start>=slots[i-1].end));}
