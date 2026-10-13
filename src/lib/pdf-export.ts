const when=(value:string)=>new Date(value).toLocaleString('fr-FR',{timeZone:'Europe/Paris'});
let font:Promise<string>|undefined;
async function fontData(){return font??=(async()=>{const response=await fetch('/fonts/export-sans.ttf');if(!response.ok)throw Error('Police PDF indisponible. Recharge l’application.');const bytes=new Uint8Array(await response.arrayBuffer());let str='';for(let i=0;i<bytes.length;i+=8192)str+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(str)})().catch(e=>{font=undefined;throw e})}
async function document(title:string){
 const {jsPDF}=await import('jspdf');const doc=new jsPDF({compress:true});doc.addFileToVFS('export.ttf',await fontData());doc.addFont('export.ttf','Export','normal');doc.setFont('Export');
 let y=38;
 function header(){doc.setFillColor(20,43,67);doc.rect(0,0,210,25,'F');doc.setTextColor(255);doc.setFontSize(14);doc.text('ATELIER FAYET 33',16,16);doc.setTextColor(30,53,73);doc.setFontSize(10)}
 header();
 function line(text:string,size=10){doc.setFontSize(size);const lines=doc.splitTextToSize(text||'—',178) as string[];for(const textLine of lines){if(y>275){doc.addPage();header();y=37}doc.text(textLine,16,y);y+=size*.48+1.5}y+=2}
 line(title,17);
 function finish(){const n=doc.getNumberOfPages();for(let i=1;i<=n;i++){doc.setPage(i);doc.setFontSize(8);doc.setTextColor(90);doc.text(`Atelier Fayet 33 · ${i} / ${n}`,16,288)}return doc}
 return {doc,line,finish,newPhoto(photo:string,label:string){doc.addPage();header();y=38;line(label,12);const props=doc.getImageProperties(photo);const scale=Math.min(178/props.width,218/props.height);doc.addImage(photo,'JPEG',16,y,props.width*scale,props.height*scale);y+=props.height*scale+5}};
}
type OrderPdf={id:string,week_number:number,week_year:number,items:{label:string,quantity:number,out_of_stock?:boolean}[],status:string,created_at:string,updated_at:string,validated_at:string|null,validated_name:string|null};
export async function orderDocument(order:OrderPdf){const p=await document(`Consommables semaine ${order.week_number} - ${order.week_year}`);p.line(`${order.items.length} article(s) · ${order.status==='validated'?'Validée':'En attente de validation'}`);if(order.validated_at)p.line(`Validée par ${order.validated_name||'Administration'} le ${when(order.validated_at)} (Paris)`);p.line(`Créée le ${when(order.created_at)} · Modifiée le ${when(order.updated_at)}`);p.line(`Identifiant : ${order.id}`,8);if(!order.items.length)p.line('Aucun article.');order.items.forEach((item,i)=>p.line(`${i+1}. ${item.label}\nQuantité : ${item.quantity}${item.out_of_stock?' · EN RUPTURE':''}`,11));return p.finish()}
export async function exportOrderPdf(order:OrderPdf){(await orderDocument(order)).save(`Consommables-semaine-${order.week_number}-${order.week_year}.pdf`)}
type ReportPdf={id:string,registration:string,author_name:string,created_at:string,updated_at?:string|null,notes:string,photos?:string[]};
export async function reportDocument(report:ReportPdf){const p=await document(`Signalement - ${report.registration}`);p.line(`Auteur : ${report.author_name}`);p.line(`Saisi le ${when(report.created_at)} (heure de Paris)`);if(report.updated_at)p.line(`Modifié le ${when(report.updated_at)} (heure de Paris)`);p.line(`Identifiant : ${report.id}`,8);p.line('Informations complémentaires',12);p.line(report.notes||'Aucune information complémentaire.');p.line(`${report.photos?.length||0} photo(s) jointe(s)`);for(const [i,photo] of (report.photos||[]).entries())p.newPhoto(photo,`${report.registration} · Photo ${i+1} / ${report.photos!.length}`);return p.finish()}
export async function exportReportPdf(report:ReportPdf){(await reportDocument(report)).save(`Signalement-${report.registration.replace(/[^A-Za-z0-9-]/g,'')}.pdf`)}
