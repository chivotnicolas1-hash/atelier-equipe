export const stations = [
 {
  "id": "pneus1",
  "name": "Pneus · 1",
  "short": "Pneus · 1",
  "col": 1,
  "row": 1
 },
 {
  "id": "attelage",
  "name": "Attelage & méca légère",
  "short": "Attelage & méca légère",
  "col": 1,
  "row": 2
 },
 {
  "id": "vidange1",
  "name": "Vidange · 1",
  "short": "Vidange · 1",
  "col": 1,
  "row": 3
 },
 {
  "id": "vidange2",
  "name": "Vidange · 2",
  "short": "Vidange · 2",
  "col": 1,
  "row": 4
 },
 {
  "id": "mecalegere",
  "name": "Méca légère",
  "short": "Méca légère",
  "col": 1,
  "row": 5
 },
 {
  "id": "mecalourde",
  "name": "Méca lourde",
  "short": "Méca lourde",
  "col": 1,
  "row": 6
 },
 {
  "id": "distribution",
  "name": "Distribution",
  "short": "Distribution",
  "col": 1,
  "row": 7
 },
 {
  "id": "pneus2",
  "name": "Pneus · 2",
  "short": "Pneus · 2",
  "col": 2,
  "row": 1
 },
 {
  "id": "geometrie",
  "name": "Géométrie",
  "short": "Géométrie",
  "col": 3,
  "row": 1
 },
 {
  "id": "elec",
  "name": "Électricité",
  "short": "Électricité",
  "col": 4,
  "row": 1
 },
 {
  "id": "organisation",
  "name": "Organisation",
  "short": "Organisation",
  "col": 2,
  "row": 3
 },
 {
  "id": "devis",
  "name": "Gestion devis",
  "short": "Gestion devis",
  "col": 2,
  "row": 4
 }
];
export const parisToday=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Paris',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export const presenceLabels:Record<string,string>={unknown:"À renseigner",rest:"Non travaillé",present:"Présent",absent:"Absent",leave:"Congé"};
export const priorityLabels:Record<string,string>={normal:"Normale",high:"Prioritaire",urgent:"Urgente"};
