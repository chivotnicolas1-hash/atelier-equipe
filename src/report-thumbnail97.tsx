import {useEffect,useState} from 'react';
import {jpegBlob97} from './lib/report-photo97';
// Queue thumbnail generation as well: five mounted previews must not decode together.
let queue:Promise<unknown>=Promise.resolve();
export default function ReportThumbnail97({src,alt}:{src:string,alt:string}){
 const [url,setUrl]=useState('');
 useEffect(()=>{let active=true,objectUrl='';setUrl('');queue=queue.catch(()=>{}).then(async()=>{
 if(!active)return;let bitmap:ImageBitmap|undefined;const c=document.createElement('canvas');
 try{const blob=await (await fetch(src)).blob();if(!active)return;bitmap=await createImageBitmap(blob,{resizeWidth:240,resizeQuality:'low'});if(!active)return;const scale=Math.min(1,320/Math.max(bitmap.width,bitmap.height));c.width=Math.max(1,Math.round(bitmap.width*scale));c.height=Math.max(1,Math.round(bitmap.height*scale));c.getContext('2d')!.drawImage(bitmap,0,0,c.width,c.height);bitmap.close();const small=await jpegBlob97(c,.7);if(active){objectUrl=URL.createObjectURL(small);setUrl(objectUrl)}}catch{/* Keep the original attached, even if its preview cannot be generated. */}finally{bitmap?.close();c.width=0;c.height=0;}
 });return()=>{active=false;if(objectUrl)URL.revokeObjectURL(objectUrl)}},[src]);
 return url?<img src={url} alt={alt} decoding="async"/>:<span className="muted">Photo jointe · aperçu en préparation</span>;
}
