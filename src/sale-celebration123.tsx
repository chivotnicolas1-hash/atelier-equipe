import {useEffect,useState,type CSSProperties}from'react';
import {createPortal}from'react-dom';
import './update123.css';
export default function SaleCelebration123({event}:{event:number}){
 const [visible,V]=useState(false);
 useEffect(()=>{if(!event||window.matchMedia?.('(prefers-reduced-motion: reduce)').matches)return;V(true);const timer=window.setTimeout(()=>V(false),1700);return()=>window.clearTimeout(timer)},[event]);
 if(!visible)return null;
 const colors=['#1477c9','#3baf4c','#f7bd46','#76c7ef','#f48295'];
 return createPortal(<div className="sale-confetti123" aria-hidden="true" key={event}>{Array.from({length:42},(_,i)=><i key={i} style={{'--x':((i%14)-6.5)*28+'px','--y':(180+(i*37)%300)+'px','--spin':((i%2?-1:1)*(180+i*31))+'deg','--delay':(i%7)*18+'ms',background:colors[i%colors.length]} as CSSProperties}/>)}</div>,document.body);
}
