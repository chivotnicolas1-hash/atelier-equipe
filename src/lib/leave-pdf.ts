import type {LeaveRequest} from '../leave-requests';
import {fontData} from './pdf-export';
const labels:Record<string,string>={cp2:'CP2 acquis',cp1:'CP1 anticipés',unpaid:'Absence non payée',rtt:'Congés spécifiques RTT',fraction:'Jours de fractionnement',marriage:'Congés mariage',birth:'Congés naissance',death:'Congés décès',parent:'Congés parents -21 ans',other:'Autres'};
const statuses:Record<string,string>={awaiting_signature:'Signature à renouveler',pending:'En attente de réponse',accepted:'Accord',refused:'Refus',proposal:'Autre proposition - à confirmer'};
const date=(d:string)=>d.split('-').reverse().join('/');
const when=(d:string)=>new Date(d).toLocaleString('fr-FR',{timeZone:'Europe/Paris'});
export async function exportLeave(r:LeaveRequest,save=true){
 const {jsPDF}=await import('jspdf');const doc=new jsPDF({compress:true});doc.addFileToVFS('export.ttf',await fontData());doc.addFont('export.ttf','Export','normal');doc.setFont('Export');
 const response=await fetch('/leave-template.png');if(!response.ok)throw Error('Modèle de congé indisponible. Recharge l’application.');doc.addImage(new Uint8Array(await response.arrayBuffer()),'PNG',0,0,210,297);
 // Coordonnées repérées sur le modèle Norauto original (991 × 1400).
 const x=(v:number)=>v*210/991,y=(v:number)=>v*297/1400;
 function fit(text:string,px:number,py:number,width:number,size=9){doc.setFontSize(size);const scale=Math.min(1,x(width)/Math.max(doc.getTextWidth(text),1));doc.setFontSize(Math.max(6,size*scale));let shown=text;while(doc.getTextWidth(shown)>x(width)&&shown.length>1)shown=shown.slice(0,-2)+'…';doc.text(shown,x(px),y(py));}
 fit(r.first_name,195,174,680,10);fit(r.last_name.toLocaleUpperCase('fr-FR'),170,194,700,10);fit(r.centre,255,219,620,10);
 const rowY:Record<string,number>={cp2:462,cp1:490,unpaid:531,rtt:737,fraction:762,marriage:788,birth:813,death:838,parent:863,other:888};
 for(const p of r.periods){const paid=['cp2','cp1','unpaid'].includes(p.kind);doc.setFontSize(9);doc.text(date(p.start),x(paid?402:498),y(rowY[p.kind]),{align:'center'});doc.text(date(p.end),x(paid?595:754),y(rowY[p.kind]),{align:'center'});if(paid)doc.text(String(p.rest),x(788),y(rowY[p.kind]),{align:'center'});if(p.kind==='other'){doc.setFillColor(255,255,255);doc.rect(x(119),y(897),x(248),y(19),'F');fit(p.detail.length>30?'Voir le motif ci-dessous':p.detail,126,912,237,8);if(p.detail.length>30){doc.setFontSize(8);doc.text(doc.splitTextToSize('Autre motif : '+p.detail,x(760)),x(118),y(952));}}}
 fit(new Date(r.created_at).toLocaleDateString('fr-FR',{timeZone:'Europe/Paris'}),285,996,123,8);
 if(r.signature){const img=doc.getImageProperties(r.signature);const w=Math.min(52,16*img.width/img.height),h=w*img.height/img.width;doc.addImage(r.signature,'PNG',x(124),y(1028),w,h)}else fit('Signature à renouveler',124,1050,260,9);
 doc.setFillColor(255,255,255);doc.rect(x(413),y(974),x(472),y(253),'F');doc.setTextColor(25,46,69);fit('Le Directeur de centre / Responsable de service',418,992,450,9);fit(r.decided_name||'Réponse en attente',418,1015,450,9);
 fit(r.decided_at?'Réponse du '+when(r.decided_at):'Demande en attente de validation',418,1036,450,8);
 fit(statuses[r.status],418,1063,450,10);
 if(r.status==='proposal')fit('Du '+date(r.proposal_start!)+' au '+date(r.proposal_end!)+' inclus',418,1086,450,9);
 if(r.status==='accepted'){
  if(r.decided_signature){const image=doc.getImageProperties(r.decided_signature);const w=Math.min(48,12*image.width/image.height);doc.addImage(r.decided_signature,'PNG',x(418),y(1076),w,w*image.height/image.width)}else fit('Signature du valideur non enregistrée',418,1090,450,8);
 }
 doc.setFontSize(8);const noteLines=doc.splitTextToSize(r.decision_note||'',x(445));const noteY=r.status==='accepted'?1150:1110;doc.text(noteLines.slice(0,4),x(418),y(noteY));if(noteLines.length>4)fit('Commentaire complet dans l’application.',418,1220,450,7);
 if(save)doc.save('Demande-conge-'+r.id.slice(0,8)+'.pdf');return doc;
}
