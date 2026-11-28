import {Monitor,CarFront} from 'lucide-react';
import LiftModel125 from './lift-model125';
import type {Station} from './design';
import './update128.css';
export default function MyPostBackdrop128({stations}:{stations:Station[]}){
 if(!stations.length)return null;
 return <div className="my-post-mark128" aria-hidden="true">{stations.slice(0,2).map(s=><span key={s.id}>{s.office?<Monitor strokeWidth={1.1}/>:s.lift_kind==='scissor'||s.lift_kind==='two_post'?<LiftModel125 kind={s.lift_kind} rotate={s.rotate}/>:<CarFront strokeWidth={1.1}/>}</span>)}</div>;
}
