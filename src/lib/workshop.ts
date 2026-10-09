export const stations = [
{id:"pneus1", name:"Pneus · 1", short:"Pneus", x:0,y:0,w:37,h:10},
{id:"attelage",name:"Attelage & méca légère",short:"Attelage & méca légère",note:"Mardi : autre",x:0,y:14,w:37,h:10},
{id:"vidange1",name:"Vidange · 1",short:"Vidange · 1",x:0,y:28,w:37,h:10},
{id:"vidange2",name:"Vidange · 2",short:"Vidange · 2",x:0,y:42,w:37,h:10},
{id:"mecalegere",name:"Méca légère",short:"Méca légère",note:"Pont utilitaire",x:0,y:56,w:37,h:10},
{id:"mecalourde",name:"Méca lourde",short:"Méca lourde",x:0,y:70,w:37,h:10},
{id:"distribution",name:"Distribution",short:"Distribution",x:0,y:84,w:37,h:10},
{id:"pneus2",name:"Pneus · 2",short:"Pneus · 2",x:43,y:0,w:16,h:28},
{id:"geometrie",name:"Géométrie",short:"Géométrie",x:63,y:0,w:15,h:28},
{id:"elec",name:"Électricité",short:"Électricité",note:"Mardi : autre",x:85,y:0,w:15,h:28},
{id:"clim",name:"Tente clim",short:"Tente clim",x:51,y:32,w:42,h:10},
{id:"organisation",name:"Organisation",short:"Organisation",x:43,y:46,w:23,h:8},
{id:"devis",name:"Gestion devis",short:"Gestion devis",x:43,y:58,w:23,h:8},
];
export const parisToday=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export const presenceLabels:Record<string,string>={unknown:"À renseigner",rest:"Non travaillé",present:"Présent",absent:"Absent",leave:"Congé"};
export const priorityLabels:Record<string,string>={normal:"Normale",high:"Prioritaire",urgent:"Urgente"};
