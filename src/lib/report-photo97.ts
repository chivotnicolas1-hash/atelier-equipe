// Bound decoded pixels before allocating a canvas. Never decode an unknown full-size file.
export function imageSize97(b:ArrayBuffer):[number,number]{
 const v=new DataView(b),u=new Uint8Array(b),n=u.length;
 if(n>=24&&v.getUint32(0)===0x89504e47)return [v.getUint32(16),v.getUint32(20)];
 if(n>=4&&v.getUint16(0)===0xffd8){let i=2;while(i+4<=n){if(u[i++]!==255)continue;while(u[i]===255)i++;const m=u[i++];if(m===0xda||m===0xd9)break;if(m===1||(m>=0xd0&&m<=0xd7))continue;if(i+2>n)break;const len=v.getUint16(i);if(len<2||i+len>n)break;if([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(m)&&len>=7)return [v.getUint16(i+5),v.getUint16(i+3)];i+=len;}}
 if(n>=25&&v.getUint32(0)===0x52494646&&v.getUint32(8)===0x57454250){const tag=v.getUint32(12);if(tag===0x56503858&&n>=30)return [1+u[24]+(u[25]<<8)+(u[26]<<16),1+u[27]+(u[28]<<8)+(u[29]<<16)];if(tag===0x56503820&&n>=30)return [v.getUint16(26,true)&16383,v.getUint16(28,true)&16383];if(tag===0x5650384c&&u[20]===47){const x=v.getUint32(21,true);return [(x&16383)+1,((x>>>14)&16383)+1];}}
 throw Error('Dimensions de la photo illisibles. Essaie une autre photo JPEG, PNG ou WebP.');
}
export type DecodedPhoto97={source:CanvasImageSource,width:number,height:number,close:()=>void};
export async function photoMime117(file:Blob){
 const u=new Uint8Array(await file.slice(0,32).arrayBuffer());
 if(u[0]===255&&u[1]===216&&u[2]===255)return 'image/jpeg';
 if(u.length>=24&&[137,80,78,71,13,10,26,10].every((n,i)=>u[i]===n))return 'image/png';
 if(u.length>=25&&String.fromCharCode(...u.slice(0,4))==='RIFF'&&String.fromCharCode(...u.slice(8,12))==='WEBP')return 'image/webp';
 throw Error('Format non pris en charge. Choisis une photo JPEG, PNG ou WebP. Pour une photo HEIC/HEIF, utilise le réglage « format compatible / JPEG » du téléphone ou exporte-la en JPEG.');
}
export async function boundedBitmap97(file:Blob,maxSide=1280):Promise<DecodedPhoto97>{
 const [w,h]=imageSize97(await file.slice(0,512*1024).arrayBuffer());
 if(!w||!h||w*h>100000000||Math.max(w,h)/Math.min(w,h)>20)throw Error('Photo trop grande. Choisis le mode photo standard de ton téléphone.');
 // A single width preserves aspect ratio and respects either EXIF orientation.
 const resizeWidth=Math.max(1,Math.floor(Math.min(w,h,maxSide*Math.min(w,h)/Math.max(w,h))));
 if(typeof createImageBitmap==='function'){
  try{const bitmap=await createImageBitmap(file,{resizeWidth,resizeQuality:'low'});return {source:bitmap,width:bitmap.width,height:bitmap.height,close:()=>bitmap.close()}}catch{/* Certains navigateurs ne prennent pas en charge le décodage redimensionné. */}
 }
 // Le secours est borné : aucun décodage intégral d’une photo haute résolution.
 if(w*h>12500000)throw Error('Ce navigateur ne peut pas réduire cette photo haute résolution. Prends-la en mode standard 12 Mpx ou choisis une image plus petite.');
 const url=URL.createObjectURL(file),im=new Image();im.decoding='async';
 try{await new Promise<void>((resolve,reject)=>{const timer=setTimeout(()=>{im.src='';reject(Error('Lecture de la photo trop longue. Réessaie avec une autre image.'))},20000);im.onload=()=>{clearTimeout(timer);resolve()};im.onerror=()=>{clearTimeout(timer);reject(Error('Photo illisible. Essaie une autre photo ou une copie JPEG.'))};im.src=url});
  if(!im.naturalWidth||!im.naturalHeight)throw Error('Photo vide ou illisible.');
  return {source:im,width:im.naturalWidth,height:im.naturalHeight,close:()=>{im.src='';URL.revokeObjectURL(url)}};
 }catch(e){URL.revokeObjectURL(url);throw e}
}
export function jpegBlob97(c:HTMLCanvasElement,q:number){return new Promise<Blob>((resolve,reject)=>c.toBlob(b=>b?resolve(b):reject(Error('Compression de la photo impossible.')),'image/jpeg',q));}
export function dataUrl97(b:Blob){return new Promise<string>((resolve,reject)=>{const r=new FileReader();r.onload=()=>{const value=String(r.result);if(value.length>300000||!/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(value))reject(Error('La photo préparée est invalide ou trop volumineuse.'));else resolve(value)};r.onerror=()=>reject(Error('Lecture de la photo impossible.'));r.onabort=()=>reject(Error('Lecture de la photo interrompue.'));r.readAsDataURL(b)});}
export async function encodePhoto97(c:HTMLCanvasElement){
 for(const q of [.82,.65,.45,.25]){const b=await jpegBlob97(c,q);if(b.size<=224970)return dataUrl97(b)}
 throw Error('Photo trop détaillée. Choisis une image plus petite.');
}
export async function preparePhoto97(file:File){
 if(file.size===0)throw Error('Cette photo est vide. Choisis à nouveau le fichier.');
 if(file.size>10*1024*1024)throw Error('Chaque photo doit faire moins de 10 Mo.');
 const mime=await photoMime117(file),source=file.type===mime?file:file.slice(0,file.size,mime);
 const bitmap=await boundedBitmap97(source),c=document.createElement('canvas');let released=false;
 try{const ratio=Math.min(1,1280/Math.max(bitmap.width,bitmap.height));c.width=Math.max(1,Math.round(bitmap.width*ratio));c.height=Math.max(1,Math.round(bitmap.height*ratio));const ctx=c.getContext('2d');if(!ctx)throw Error('Lecture de photo indisponible.');ctx.fillStyle='white';ctx.fillRect(0,0,c.width,c.height);ctx.drawImage(bitmap.source,0,0,c.width,c.height);bitmap.close();released=true;return await encodePhoto97(c)}finally{if(!released)bitmap.close();c.width=0;c.height=0;}
}
