export type Rect128={x:number,y:number,width:number,height:number};
// Correspondance exacte entre l'image du capteur et le cadre CSS (cover caméra, contain photo).
export function frameCrop128(sw:number,sh:number,vw:number,vh:number,frame:Rect128,fit:'cover'|'contain'='cover'):Rect128{
 if([sw,sh,vw,vh,frame.width,frame.height].some(n=>!Number.isFinite(n)||n<=0)||![frame.x,frame.y].every(Number.isFinite))throw Error('Cadrage indisponible.');
 const scale=fit==='cover'?Math.max(vw/sw,vh/sh):Math.min(vw/sw,vh/sh),dx=(vw-sw*scale)/2,dy=(vh-sh*scale)/2;
 const x=Math.max(0,(frame.x-dx)/scale),y=Math.max(0,(frame.y-dy)/scale),right=Math.min(sw,(frame.x+frame.width-dx)/scale),bottom=Math.min(sh,(frame.y+frame.height-dy)/scale);
 if(right-x<80||bottom-y<18)throw Error('Place le cadre sur la plaque et rapproche la photo.');
 return{x,y,width:right-x,height:bottom-y};
}
export function plateOptions128(text:string){
 const normalized=text.toUpperCase().replace(/[–—−]/g,'-'),out=new Map<string,{plate:string,corrected:boolean}>();
 for(const m of normalized.matchAll(/(?:^|[^A-Z0-9])([A-Z]{2})[ \t-]*([0-9OQILSZBG]{3})[ \t-]*([A-Z]{2})(?=$|[^A-Z0-9])/gm)){
  const map:Record<string,string>={O:'0',Q:'0',I:'1',L:'1',S:'5',Z:'2',B:'8',G:'6'},digits=m[2].replace(/[OQILSZBG]/g,c=>map[c]),plate=m[1]+'-'+digits+'-'+m[3],corrected=digits!==m[2];
  const previous=out.get(plate);if(!previous||!corrected)out.set(plate,{plate,corrected});
 }
 return [...out.values()].slice(0,6);
}
export function enhancePlate128(c:HTMLCanvasElement,threshold=false){
 const ctx=c.getContext('2d',{willReadFrequently:true});if(!ctx)throw Error('Préparation de photo indisponible.');
 const image=ctx.getImageData(0,0,c.width,c.height),a=image.data,hist=new Uint32Array(256);
 for(let i=0;i<a.length;i+=4){const g=Math.round(a[i]*.299+a[i+1]*.587+a[i+2]*.114);hist[g]++;a[i]=g;}
 const pixels=a.length/4;let low=0,high=255,sum=0;
 for(let i=0;i<256;i++){sum+=hist[i];if(sum>=pixels*.02){low=i;break}}
 sum=0;for(let i=255;i>=0;i--){sum+=hist[i];if(sum>=pixels*.02){high=i;break}}
 let cut=128;if(threshold){let total=0,left=0,weight=0,best=-1;for(let i=0;i<256;i++)total+=i*hist[i];for(let i=0;i<255;i++){weight+=hist[i];left+=i*hist[i];if(!weight||weight===pixels)continue;const diff=left/weight-(total-left)/(pixels-weight),score=weight*(pixels-weight)*diff*diff;if(score>best){best=score;cut=i}}}
 for(let i=0;i<a.length;i+=4){const g=threshold?(a[i]>cut?255:0):Math.round(Math.max(0,Math.min(255,(a[i]-low)*255/Math.max(1,high-low))));a[i]=a[i+1]=a[i+2]=g;a[i+3]=255}ctx.putImageData(image,0,0);
}
export function ocrCanvas128(source:HTMLCanvasElement,pass:number){
 const c=document.createElement('canvas'),trim=.065,w=source.width*(1-2*trim),h=source.height*.92;
 c.width=1280;c.height=Math.max(80,Math.min(420,Math.round(1280*h/w)));const ctx=c.getContext('2d');if(!ctx)throw Error('Préparation de photo indisponible.');
 ctx.fillStyle='white';ctx.fillRect(0,0,c.width,c.height);ctx.translate(c.width/2,c.height/2);if(pass>=2)ctx.rotate((pass===2?-3:3)*Math.PI/180);
 ctx.drawImage(source,source.width*trim,source.height*.04,w,h,-c.width/2,-c.height/2,c.width,c.height);ctx.setTransform(1,0,0,1,0,0);enhancePlate128(c,pass===1);return c;
}
