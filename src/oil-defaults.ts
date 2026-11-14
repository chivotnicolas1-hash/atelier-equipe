const tanks=[
 ['5W30 M2C913C',210,'1 / 3','1 / 3'],['5W30 C4 RN720',210,'3 / 5','1'],['5W30 C2 PSA',210,'5 / 7','1'],['5W40 505.01 Dexos 2',210,'7 / 9','1 / 3'],['5W30 RN17',60,'4 / 6','2'],
 ['0W20 B712010 PSA',60,'8 / 10','3'],['LG',0,'10 / 12','3 / 5'],['0W30 C1 C2 PSA',60,'8 / 10','4'],['0W20 LL FE 508/509',60,'8 / 10','5'],['10W40',200,'10 / 12','5'],
 ['5W40 A3/B4',1000,'2 / 4','7'],['5W30 C3 504/507 LL04',1000,'4 / 6','7'],['5W30 RCP',1000,'6 / 8','7']
] as const;
export type Oil={managers_only?:boolean,photo?:string,unavailable?:boolean,id:string,name:string,pack:string,kind:'oil'|'tank'|'extra',x:number,y:number,w:number,h:number,color:string,end:string};
const extras=[['Refroid Renault','60 L','#ffe442',''],['Refroid PSA','60 L','#143e85','#075544'],['Refroid FORD','60 L','#ff9937',''],['G11','poche 20 L','#175439',''],['G12','poche 20 L','#ffcedd',''],['G13','poche 20 L','#a02460',''],['75W80','','',''],['75W90','','',''],['Liquide de frein','','','']];
export const defaults:Oil[]=[...tanks.map(([name,l,col,row],i)=>{const [x,x2]=col.split(' / ').map(Number),[y,y2]=row.split(' / ').map(Number);return {id:'t'+i,name,pack:l?l+' L':'',kind:row==='7'?'tank' as const:'oil' as const,x,y,w:x2-x,h:(y2||y+1)-y,color:'',end:''}}),...extras.map(([name,pack,color,end],i)=>({id:'e'+i,name,pack,color,end,kind:'extra' as const,x:i%2+1,y:Math.floor(i/2)+1,w:1,h:1}))];
