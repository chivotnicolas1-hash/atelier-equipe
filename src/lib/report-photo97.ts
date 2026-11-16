// Bound decoded pixels before allocating a canvas. Never decode an unknown full-size file.
export function imageSize97(b:ArrayBuffer):[number,number]{
 const v=new DataView(b),u=new Uint8Array(b),n=u.length;
 if(n>=24&&v.getUint32(0)===0x89504e47)return [v.getUint32(16),v.getUint32(20)];
 if(n>=4&&v.getUint16(0)===0xffd8){let i=2;while(i+4<=n){if(u[i++]!==255)continue;while(u[i]===255)i++;const m=u[i++];if(m===0xda||m===0xd9)break;if(m===1||(m>=0xd0&&m<=0xd7))continue;if(i+2>n)break;const len=v.getUint16(i);if(len<2||i+len>n)break;if([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(m)&&len>=7)return [v.getUint16(i+5),v.getUint16(i+3)];i+=len;}}
 if(n>=30&&v.getUint32(0)===0x52494646&&v.getUint32(8)===0x57454250){const tag=v.getUint32(12);if(tag===0x56503858)return [1+u[24]+(u[25]<<8)+(u[26]<<16),1+u[27]+(u[28]<<8)+(u[29]<<16)];if(tag===0x56503820)return [v.getUint16(26,true)&16383,v.getUint16(28,true)&16383];if(tag===0x5650384c&&u[20]===47){const x=v.getUint32(21,true);return [(x&16383)+1,((x>>>14)&16383)+1];}}
 throw Error('Dimensions de la photo illisibles. Essaie une autre photo JPEG, PNG ou WebP.');
}
export async function boundedBitmap97(file:Blob){
 const [w,h]=imageSize97(await file.slice(0,512*1024).arrayBuffer());
 if(!w||!h||w*h>100000000||Math.max(w,h)/Math.min(w,h)>20)throw Error('Photo trop grande. Choisis le mode photo standard de ton téléphone.');
 // A single width preserves aspect ratio and respects either EXIF orientation.
 const resizeWidth=Math.max(1,Math.floor(Math.min(w,h,1280*Math.min(w,h)/Math.max(w,h))));
 return createImageBitmap(file,{resizeWidth,resizeQuality:'low'});
}
export function jpegBlob97(c:HTMLCanvasElement,q:number){return new Promise<Blob>((resolve,reject)=>c.toBlob(b=>b?resolve(b):reject(Error('Compression de la photo impossible.')),'image/jpeg',q));}
export function dataUrl97(b:Blob){return new Promise<string>((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result));r.onerror=()=>reject(Error('Lecture de la photo impossible.'));r.readAsDataURL(b)});}
export async function encodePhoto97(c:HTMLCanvasElement){
 for(const q of [.82,.65,.45,.25]){const b=await jpegBlob97(c,q);if(b.size<=224970)return dataUrl97(b)}
 throw Error('Photo trop détaillée. Choisis une image plus petite.');
}
export async function preparePhoto97(file:File){
 if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('Utilise des photos JPEG, PNG ou WebP.');
 if(file.size>10*1024*1024)throw Error('Chaque photo doit faire moins de 10 Mo.');
 const bitmap=await boundedBitmap97(file),c=document.createElement('canvas');
 try{const ratio=Math.min(1,1280/Math.max(bitmap.width,bitmap.height));c.width=Math.max(1,Math.round(bitmap.width*ratio));c.height=Math.max(1,Math.round(bitmap.height*ratio));const ctx=c.getContext('2d');if(!ctx)throw Error('Lecture de photo indisponible.');ctx.fillStyle='white';ctx.fillRect(0,0,c.width,c.height);ctx.drawImage(bitmap,0,0,c.width,c.height);bitmap.close();return await encodePhoto97(c)}finally{bitmap.close();c.width=0;c.height=0;}
}
