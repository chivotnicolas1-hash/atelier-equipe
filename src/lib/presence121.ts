type Person121={id:string,role?:string,active?:boolean,suspended?:boolean};
type Day121={staff_id:string,presence:string,confirmed:string|null,slots?:{start:string,end:string}[]};
export function hasSchedule121(day:Pick<Day121,'slots'>|null|undefined){
 return !!day?.slots?.some(s=>/^([01]\d|2[0-3]):[0-5]\d$/.test(s.start)&&/^([01]\d|2[0-3]):[0-5]\d$/.test(s.end)&&s.start<s.end);
}
export function presenceSummary121<S extends Person121,D extends Day121>(staff:S[],days:D[]){
 const allowed=new Set(staff.filter(s=>s.active!==false&&!s.suspended&&s.role!=='guest'&&s.role!=='director').map(s=>s.id));
 const unique=new Map<string,D>();for(const day of days)if(allowed.has(day.staff_id))unique.set(day.staff_id,day);
 const present=[...unique.values()].filter(d=>d.presence==='present'&&hasSchedule121(d));
 const confirmed=present.filter(d=>!!d.confirmed&&Number.isFinite(Date.parse(d.confirmed)));
 return {present,confirmed};
}
