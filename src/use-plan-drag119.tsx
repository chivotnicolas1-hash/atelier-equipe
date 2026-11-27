import {useEffect,useRef,useState,type PointerEvent as ReactPointerEvent,type RefObject} from 'react';
import {createPortal} from 'react-dom';
import type {PlanMove119} from './lib/plan-move119';
export type MoveOptions119={busy:boolean,reason:(move:PlanMove119)=>string|null,request:(move:PlanMove119)=>void};
type Gesture={pointer:number,element:HTMLElement,staffId:string,from:string|null,name:string,startX:number,startY:number,x:number,y:number,active:boolean,to:string|null};
export default function usePlanDrag119(root:RefObject<HTMLElement|null>,enabled:boolean,options:MoveOptions119|undefined){
 const current=useRef({enabled,options});current.current={enabled,options};
 const gesture=useRef<Gesture|null>(null),frame=useRef(0),blockClick=useRef(false);
 const [visual,V]=useState<{x:number,y:number,name:string,to:string|null,reason:string|null}|null>(null),[message,M]=useState('');
 function end(){cancelAnimationFrame(frame.current);const g=gesture.current;gesture.current=null;V(null);if(g?.element.hasPointerCapture(g.pointer))g.element.releasePointerCapture(g.pointer)}
 function target(g:Gesture){const node=document.elementFromPoint(g.x,g.y)?.closest<HTMLElement>('[data-station]');return node&&root.current?.contains(node)?node.dataset.station||null:null}
 function show(g:Gesture){g.to=target(g);const reason=g.to?current.current.options?.reason({staffId:g.staffId,from:g.from,to:g.to})||null:'Dépose sur un poste du plan.';V({x:g.x,y:g.y,name:g.name,to:g.to,reason})}
 function scroll(){const g=gesture.current;if(!g)return;if(g.active){const el=root.current?.querySelector<HTMLElement>('.atelier-map-scroll');if(el){const b=el.getBoundingClientRect();if(g.y>=b.top&&g.y<=b.bottom){if(g.x<b.left+40)el.scrollLeft-=7;else if(g.x>b.right-40)el.scrollLeft+=7}}if(g.y<65)window.scrollBy(0,-7);else if(g.y>window.innerHeight-65)window.scrollBy(0,7);show(g)}frame.current=requestAnimationFrame(scroll)}
 useEffect(()=>{if(!enabled||options?.busy)end()},[enabled,options?.busy]);
 useEffect(()=>{const stop=()=>end();window.addEventListener('blur',stop);return()=>{window.removeEventListener('blur',stop);cancelAnimationFrame(frame.current)}},[]);
 function down(e:ReactPointerEvent<HTMLElement>,staffId:string,from:string|null,name:string){if(!current.current.enabled||!current.current.options||current.current.options.busy||e.button!==0||!e.isPrimary)return;M('');const element=e.currentTarget;gesture.current={pointer:e.pointerId,element,staffId,from,name,startX:e.clientX,startY:e.clientY,x:e.clientX,y:e.clientY,active:false,to:null};element.setPointerCapture(e.pointerId);frame.current=requestAnimationFrame(scroll)}
 function move(e:ReactPointerEvent<HTMLElement>){const g=gesture.current;if(!g||g.pointer!==e.pointerId)return;g.x=e.clientX;g.y=e.clientY;if(!g.active&&Math.hypot(g.x-g.startX,g.y-g.startY)>=8){g.active=true;blockClick.current=true}if(g.active){e.preventDefault();show(g)}}
 function up(e:ReactPointerEvent<HTMLElement>){const g=gesture.current;if(!g||g.pointer!==e.pointerId)return;const active=g.active;g.x=e.clientX;g.y=e.clientY;const to=target(g);const action=to?{staffId:g.staffId,from:g.from,to}:null;const reason=action?current.current.options?.reason(action):'Aucun poste choisi.';end();if(!active)return;e.preventDefault();e.stopPropagation();if(action&&!reason)current.current.options?.request(action);else M(reason||'Déplacement annulé.')}
 return {visual,message,handlers:{onPointerMove:move,onPointerUp:up,onPointerCancel:()=>{end();blockClick.current=false},onLostPointerCapture:()=>{if(gesture.current)end()},onKeyDownCapture:(e:React.KeyboardEvent)=>{if(e.key==='Escape'&&gesture.current){blockClick.current=true;end();M('Déplacement annulé.')}},onClickCapture:(e:React.MouseEvent)=>{if(blockClick.current){blockClick.current=false;e.preventDefault();e.stopPropagation()}}},down,
 ghost:visual?createPortal(<div className={'plan-drag-ghost119'+(visual.reason?' invalid':'')} style={{left:visual.x+12,top:visual.y+12}} aria-hidden="true">{visual.name}<small>{visual.reason||'Relâche pour choisir ce poste'}</small></div>,document.body):null};
}
