import {Package,Boxes} from 'lucide-react';
import {DrumIcon81,OilCanIcon80} from './section-icons79';
export function TankIcon90(){return <svg viewBox="0 0 32 32" width="32" height="32" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="4" y="8" width="24" height="19" rx="3"/><path d="M4 14h24M4 21h24M11 8v19M21 8v19M13 8V4h6v4M16 27v3h6M6 30h4M24 30h3"/><path d="M14 4h4"/></svg>}
export default function OrderProduct90({icon,photo}:{icon?:string,photo?:string}){
 const content=icon==='tank'?<TankIcon90/>:icon==='drum'?<DrumIcon81 size={30}/>:icon==='can'?<OilCanIcon80 size={30}/>:icon==='oil'?<OilCanIcon80 size={28}/>:icon==='photo'?<Package size={25}/>:<Boxes size={27}/>;
 if(icon==='photo'&&photo)return <img className="order-product-photo88" src={photo} alt="" loading="lazy"/>;
 return <span className="order-icon90" title={icon==='tank'?'Cuve':icon==='drum'?'Fût':icon==='can'?'Bidon de 20 L':icon==='oil'?'Liquide':icon==='photo'?'Produit':'Divers'}>{content}</span>;
}
