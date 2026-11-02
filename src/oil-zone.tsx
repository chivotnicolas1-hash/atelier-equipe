const tanks=[
 ['5W30 M2C913C',210,'1 / 3','1 / 3'],['5W30 C4 RN720',210,'3 / 5','1'],['5W30 C2 PSA',210,'5 / 7','1'],['5W40 505.01 Dexos 2',210,'7 / 9','1 / 3'],['5W30 RN17',60,'4 / 6','2'],
 ['0W20 B712010 PSA',60,'8 / 10','3'],['LG',0,'10 / 12','3 / 5'],['0W30 C1 C2 PSA',60,'8 / 10','4'],['0W20 LL FE 508/509',60,'8 / 10','5'],['10W40',200,'10 / 12','5'],
 ['5W40 A3/B4',1000,'2 / 4','7'],['5W30 C3 504/507 LL04',1000,'4 / 6','7'],['5W30 RCP',1000,'6 / 8','7']
] as const;
export default function OilZone({disabled,caption,notice,add}:{disabled:boolean,caption:string,notice:string,add:(label:string)=>void}){
 return <details className="oil-zone"><summary>Divers liquides (huile, refroi, frein, …)</summary><p>{caption}</p><div className="oil-scroll"><div className="oil-map"><b className="oil-center">Zone huiles</b><b className="oil-upper">Cuves à l’étage</b>{tanks.map(([ref,litres,col,row])=>{const label=ref+(litres?' ('+litres+' L)':'');return <button key={ref} type="button" disabled={disabled} aria-label={'Ajouter '+label} onClick={()=>add(label)} style={{gridColumn:col,gridRow:row}}><strong>{ref}</strong>{litres>0&&<small>{litres} L</small>}</button>})}</div></div><p role="status">{notice}</p></details>
}
