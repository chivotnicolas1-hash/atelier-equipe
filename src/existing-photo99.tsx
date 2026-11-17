import {useEffect,useState} from 'react';
import {Images,Check,Search} from 'lucide-react';
import {publishPhotos88,useExistingPhotos99} from './lib/product-photos88';
import {readConsumables88} from './lib/consumables-read88';
import './existing-photo99.css';
const catalogs=['Pneus','5gaz','Freins, transmissions, roulements','Hygiène, protection et nettoyage','Vidange','Phare, ampoule, Pare brise, élec'];
const norm=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('fr');
export default function ExistingPhoto99({onSelect,disabled=false}:{onSelect:(photo:string)=>void,disabled?:boolean}){
 const [open,O]=useState(false),[query,Q]=useState(''),[section,S]=useState(''),[loading,L]=useState(false),[error,E]=useState(''),[selected,T]=useState<string|null>(null);
 const photos=useExistingPhotos99();
 useEffect(()=>{if(!open)return;let active=true;L(true);E('');void(async()=>{
 const failed:string[]=[];
 for(const name of ['oil',...catalogs]){if(!active)break;try{const r=await readConsumables88(name==='oil'?'workshop_oils72':'workshop_catalog89',name==='oil'?undefined:{p_section:name,p_known:-1});if(active&&Array.isArray(r?.items))publishPhotos88(name,r.items);else if(active)failed.push(name)}catch{failed.push(name==='oil'?'Divers liquides':name)}}
 if(active){L(false);if(failed.length)E('Certaines sections n’ont pas pu être chargées : '+failed.join(', ')+'. Les images disponibles restent utilisables. Ferme puis rouvre la galerie pour réessayer.')}
 })();return()=>{active=false}},[open]);
 const visible=photos.filter(p=>(!section||p.section===section)&&norm(p.name).includes(norm(query))),choice=visible.find(p=>p.id===selected);
 return <div className="existing-photo99"><button type="button" className="secondary" disabled={disabled} onClick={()=>{O(v=>!v);T(null)}} aria-expanded={open}><Images size={18}/> {open?'Fermer la galerie':'Choisir une image existante'}</button>{open&&<section aria-label="Images des consommables"><h4>Images des consommables</h4><p className="muted">Choisis une photo déjà utilisée. Elle sera copiée sur cet article après enregistrement, sans modifier le produit d’origine.</p><label><Search size={16}/> Rechercher un produit<input type="search" value={query} onChange={e=>{Q(e.target.value);T(null)}} placeholder="Ex. joint, ampoule, bidon…"/></label><label>Section<select value={section} onChange={e=>{S(e.target.value);T(null)}}><option value="">Toutes les sections</option>{[...new Set(photos.map(p=>p.section))].map(s=><option key={s}>{s}</option>)}</select></label>{loading&&<p role="status">Chargement des images…</p>}{error&&<p role="alert">{error}</p>}<p className="muted">{visible.length} image(s) · les photos identiques sont regroupées.</p><div className="existing-photo99-grid">{visible.map(p=><button type="button" key={p.id} disabled={disabled} aria-pressed={selected===p.id} onClick={()=>T(p.id)}><img src={p.photo} alt="" loading="lazy" decoding="async"/><span>{p.name}<small>{p.section}</small></span>{selected===p.id&&<Check size={18}/>}</button>)}</div>{!loading&&!visible.length&&<p>Aucune image disponible pour cette recherche. Tu peux toujours importer une photo depuis ton appareil.</p>}<button type="button" className="primary" disabled={disabled||!choice} onClick={()=>{if(choice){onSelect(choice.photo);O(false);T(null)}}}>Utiliser cette image</button></section>}</div>
}
