export type PdfPiece78={text:string,x:number,y:number};
export function groupCatalog78(pieces:PdfPiece78[],width:number,left:number,right:number,gap:number){
 const tokens=pieces.filter(p=>p.text.trim()&&p.x>=width*left/100&&p.x<width*right/100).sort((a,b)=>a.y-b.y||a.x-b.x);
 const lines:{text:string,y:number}[]=[];
 for(const p of tokens){const l=lines.at(-1);if(l&&Math.abs(l.y-p.y)<4)l.text+=' '+p.text.trim();else lines.push({text:p.text.trim(),y:p.y})}
 const rows:string[]=[];let y=-Infinity;for(const l of lines){if(l.y-y<gap&&rows.length)rows[rows.length-1]+=' '+l.text;else rows.push(l.text);y=l.y}return rows;
}
export async function photo78(file:File){if(file.size>10*1024*1024)throw Error('Photo limitée à 10 Mo.');const im=await createImageBitmap(file),c=document.createElement('canvas');try{const k=Math.min(1,480/Math.max(im.width,im.height));c.width=Math.max(1,Math.round(im.width*k));c.height=Math.max(1,Math.round(im.height*k));const ctx=c.getContext('2d');if(!ctx)throw Error('Préparation de photo indisponible.');ctx.drawImage(im,0,0,c.width,c.height);return c.toDataURL('image/webp',.82)}finally{im.close();c.width=0;c.height=0}}
