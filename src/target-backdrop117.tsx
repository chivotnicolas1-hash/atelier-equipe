import {BatteryCharging,Snowflake,CarFront,ClipboardCheck,Target,Droplets,Wrench} from 'lucide-react';
import {BrakeDiscIcon80} from './section-icons79';
export default function TargetBackdrop117({category,label=''}:{category:string,label?:string}){
 const key=(category+' '+label).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 const Icon=/quality|qualite/.test(key)?ClipboardCheck:/purge|frein/.test(key)?BrakeDiscIcon80:/batter/.test(key)?BatteryCharging:/geometr|parallel/.test(key)?CarFront:/clim/.test(key)?Snowflake:/huile|vidange/.test(key)?Droplets:/meca|atelier/.test(key)?Wrench:Target;
 return <span className="cible-backdrop117" aria-hidden="true"><Icon size={72}/></span>;
}
