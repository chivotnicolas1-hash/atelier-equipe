export const screenKey123=(login:string)=>'atelier-screen-lock:'+login.trim().toLowerCase();
export function managementEntry123(href=location.href){return new URL(href).searchParams.has('connexion')}
export function screenLocked123(login:string){try{return localStorage.getItem(screenKey123(login))==='1'}catch{return false}}
export function clearScreenEntry123(login:string,keepLoginIntent=false){
 try{localStorage.removeItem(screenKey123(login))}catch{}
 try{sessionStorage.removeItem('atelier-screen-return')}catch{}
 const url=new URL(location.href);
 for(const k of ['display','page','mode','day','notifications','poll'])url.searchParams.delete(k);
 if(keepLoginIntent)url.searchParams.set('connexion','1');else url.searchParams.delete('connexion');
 history.replaceState({},'',url);
}
