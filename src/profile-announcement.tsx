import {useState} from 'react';
import {Camera,Megaphone,Trash2,UserRound} from 'lucide-react';
import {Dialog,DialogContent,DialogTitle,DialogDescription} from './components/ui/dialog';
import {supabase} from './lib/supabase';
import {Checkbox} from './simple-checkbox';
export type Announcement={message:string,enabled:boolean};
async function call(name:string,args:Record<string,unknown>){const {error}=await supabase.rpc(name,args);if(error)throw Error(error.code==='PGRST202'?'Applique le script 07-annonce-profil.sql dans Supabase.':error.message);}
async function preparePhoto(file:File){
 if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('Choisis une photo JPEG, PNG ou WebP.');
 if(file.size>8*1024*1024)throw Error('La photo doit faire moins de 8 Mo.');
 const bitmap=await createImageBitmap(file);
 try{
 const size=Math.min(bitmap.width,bitmap.height);if(!size)throw Error('Image illisible.');
 const canvas=document.createElement('canvas');canvas.width=256;canvas.height=256;const ctx=canvas.getContext('2d');if(!ctx)throw Error('Lecture des images indisponible sur ce navigateur.');
 ctx.fillStyle='#ffffff';ctx.fillRect(0,0,256,256);ctx.drawImage(bitmap,(bitmap.width-size)/2,(bitmap.height-size)/2,size,size,0,0,256,256);
 let photo=canvas.toDataURL('image/jpeg',0.82);if(photo.length>90000)photo=canvas.toDataURL('image/jpeg',0.6);if(photo.length>90000)throw Error('Cette image est trop détaillée. Choisis une autre photo.');return photo;
 }finally{bitmap.close();}
}
export function ProfileDialog({name,email,team,role,photo,onClose,onSaved}:{name:string,email:string,team?:string|null,role:string,photo?:string|null,onClose:()=>void,onSaved:()=>Promise<unknown>}){
 const [draft,setDraft]=useState(photo||null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[dirty,setDirty]=useState(false);
 async function choose(file:File){setError('');setBusy(true);try{setDraft(await preparePhoto(file));setDirty(true)}catch(e:any){setError(e.message||'Cette photo est illisible.')}finally{setBusy(false)}}
 async function save(){setError('');setBusy(true);try{await call('workshop_save_profile',{p_photo:draft});await onSaved();onClose()}catch(e:any){setError(e.message)}finally{setBusy(false)}}
 return <Dialog open onOpenChange={v=>!v&&!busy&&onClose()}><DialogContent className="app-dialog profile-dialog"><DialogTitle>Mon profil</DialogTitle><DialogDescription>Ta photo apparaît dans la barre du haut sur tes appareils connectés.</DialogDescription>{error&&<p className="error-banner" role="alert">{error}</p>}<div className="profile-photo">{draft?<img src={draft} alt="Aperçu de ma photo de profil"/>:<UserRound size={54}/>}</div><div className="profile-details"><h2>{name}</h2><p>{email}</p><span className="role-badge">{role==='admin'?'Administrateur':role==='moderator'?'Modérateur':'Collaborateur'}</span>{team&&<span className="team-badge">{team}</span>}</div><label className="photo-picker"><Camera size={18}/> Choisir une photo<input type="file" accept="image/jpeg,image/png,image/webp" disabled={busy} onChange={e=>{const f=e.target.files?.[0];if(f)void choose(f);e.target.value=''}}/></label><p className="muted">JPEG, PNG ou WebP · 8 Mo maximum. La photo est recadrée au centre au format carré.</p>{draft&&<button className="secondary danger" disabled={busy} onClick={()=>{setDraft(null);setDirty(true);setError('')}}><Trash2 size={16}/> Retirer ma photo</button>}<button className="primary full" disabled={busy||!dirty} onClick={save}>{busy?'Enregistrement…':'Enregistrer mon profil'}</button><p className="muted">Pour modifier ton nom, ton adresse ou ton équipe, contacte l’administrateur.</p></DialogContent></Dialog>
}
export function AnnouncementDialog({announcement,onClose,onSaved}:{announcement?:Announcement,onClose:()=>void,onSaved:()=>Promise<unknown>}){
 const [message,setMessage]=useState(announcement?.message||''),[enabled,setEnabled]=useState(announcement?.enabled||false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function save(){setBusy(true);setError('');try{await call('workshop_save_announcement',{p_message:message,p_enabled:enabled});await onSaved();onClose()}catch(e:any){setError(e.message)}finally{setBusy(false)}}
 return <Dialog open onOpenChange={v=>!v&&!busy&&onClose()}><DialogContent className="app-dialog"><DialogTitle>Annonce de l’atelier</DialogTitle><DialogDescription>Une bannière rouge en haut de l’application, visible par toute l’équipe connectée.</DialogDescription>{error&&<p className="error-banner" role="alert">{error}</p>}<label>Message de l’annonce<textarea rows={5} maxLength={1000} value={message} disabled={busy} onChange={e=>setMessage(e.target.value)} placeholder="Ex. Réunion d’équipe à 14 h dans l’atelier."/></label><p className="muted">{message.length} / 1000 caractères</p><Checkbox checked={enabled} onChange={setEnabled} disabled={busy} label="Afficher la bannière pour toute l’équipe"/>{message.trim()&&<div className="announcement-preview"><p className="muted">Aperçu</p><div className="announcement-banner"><Megaphone size={22}/><p>{message}</p></div></div>}<button className="primary full" disabled={busy||(enabled&&!message.trim())} onClick={save}>{busy?'Enregistrement…':'Enregistrer l’annonce'}</button><p className="muted">Décoche l’option pour retirer la bannière sans effacer son texte.</p></DialogContent></Dialog>
}
