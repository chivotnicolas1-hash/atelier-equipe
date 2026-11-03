export function suggestRestDays(start:string,end:string){
 if(!start||!end||end<start)return 0;
 const d=new Date(start+'T12:00:00Z'),last=new Date(end+'T12:00:00Z');let days=0;
 for(let i=0;i<367&&d<=last;i++,d.setUTCDate(d.getUTCDate()+1))if(d.getUTCDay()!==0)days++;
 return Math.floor(days/6);
}
