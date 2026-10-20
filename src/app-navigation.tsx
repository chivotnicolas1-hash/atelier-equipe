import {useState,type ReactNode} from 'react';
import {Menu,ChevronRight} from 'lucide-react';
import {Dialog,DialogContent,DialogTitle,DialogDescription,DialogTrigger} from './components/ui/dialog';
import {Tabs} from './components/ui/tabs';
const labels:Record<string,string>={skills:'Compétences',journee:'Ma journée',plan:'Plan de l’atelier',tasks:'Tâches',reports:'Signalements',team:'Équipes',orders:'Consommables',waste:'Déchets',polls:'Sondages',recap:'Récapitulatif',quality:'F9900 contrôles qualité',disputes:'Litiges en cours',settings:'Paramètres application',inbox:'Mes notifications'};
export default function AppNavigation({value,onValueChange,children}:{value:string,onValueChange:(v:string)=>void,children:ReactNode}){
 const [open,setOpen]=useState(false);
 return <div className="app-navigation"><Dialog open={open} onOpenChange={setOpen}><DialogTrigger asChild><button className="navigation-launch" aria-label="Ouvrir le menu"><span className="navigation-menu-icon"><Menu size={21}/></span><span><small>MENU</small><strong>{labels[value]||'Atelier'}</strong></span><ChevronRight size={18}/></button></DialogTrigger><DialogContent className="app-dialog navigation-dialog"><DialogTitle>Menu de l’atelier</DialogTitle><DialogDescription>Choisis une rubrique pour y accéder.</DialogDescription><Tabs value={value} onValueChange={v=>{onValueChange(v);setOpen(false)}} onClick={e=>{if((e.target as HTMLElement).closest('[role="tab"]'))setOpen(false)}}>{children}</Tabs></DialogContent></Dialog></div>;
}
