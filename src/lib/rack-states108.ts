export type Fill108='unknown'|'full'|'empty';
export function states108(n:number,values:unknown,fallback:Fill108='unknown'):Fill108[]{const a=Array.isArray(values)?values:[];return Array.from({length:n},(_,i)=>['full','empty','unknown'].includes(a[i])?a[i]:fallback)}
export function summary108(a:Fill108[]){const full=a.filter(x=>x==='full').length,empty=a.filter(x=>x==='empty').length,unknown=a.length-full-empty;return [full?`${full} plein${full>1?'s':''}`:'',empty?`${empty} vide${empty>1?'s':''}`:'',unknown?`${unknown} non précisé${unknown>1?'s':''}`:''].filter(Boolean).join(' · ')}
