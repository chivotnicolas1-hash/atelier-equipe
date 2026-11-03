export function safeLink(value:string|null|undefined):string|null{
 if(!value||value.length>2048)return null;
 try{const url=new URL(value.trim());if(!['https:','http:'].includes(url.protocol)||url.username||url.password||!url.hostname)return null;return url.href}catch{return null}
}
