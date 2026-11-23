// Chiffrement au repos des sessions mobiles. La clé ne quitte pas cet appareil.
// Une clé non exportable n'empêche pas un script malveillant d'utiliser la session :
// les contrôles serveur et la protection contre les XSS restent indispensables.
type Record121={version:1,iv:Uint8Array<ArrayBuffer>,cipher:ArrayBuffer};
type Legacy121=Pick<Storage,'getItem'|'setItem'|'removeItem'>;
type Options121={project:string,indexedDB?:IDBFactory,crypto?:Crypto,legacy?:Legacy121,onFallback?:()=>void,database?:string};
export function createSessionStorage121(options:Options121){
 const factory=options.indexedDB??globalThis.indexedDB,crypt=options.crypto??globalThis.crypto;
 const memory=new Map<string,string>();let fallback=false,queue:Promise<unknown>=Promise.resolve();
 const encoder=new TextEncoder(),prefix='atelier-session-closed121:'+options.project+':';
 const warn=()=>{if(!fallback){fallback=true;options.onFallback?.()}};
 const readLegacy=(key:string)=>{try{return options.legacy?.getItem(key)??null}catch{return null}};
 const clearLegacy=(key:string)=>{try{options.legacy?.removeItem(key)}catch{}};
 const closed=(key:string)=>readLegacy(prefix+key)!==null;
 const markClosed=(key:string)=>{try{options.legacy?.setItem(prefix+key,'1');return !!options.legacy}catch{return false}};
 const reopen=(key:string)=>clearLegacy(prefix+key);
 const run=<T>(fn:()=>Promise<T>):Promise<T>=>{const result=queue.then(fn);queue=result.catch(()=>{});return result};
 const request=<T>(value:IDBRequest<T>)=>new Promise<T>((resolve,reject)=>{value.onsuccess=()=>resolve(value.result);value.onerror=()=>reject(value.error)});
 const completed=(tx:IDBTransaction)=>new Promise<void>((resolve,reject)=>{tx.oncomplete=()=>resolve();tx.onerror=tx.onabort=()=>reject(tx.error||new Error('Stockage indisponible'))});
 let connection:Promise<{db:IDBDatabase,key:CryptoKey}>|null=null;
 function open(){if(connection)return connection;connection=(async()=>{
  if(!factory||!crypt?.subtle)throw Error('Stockage sécurisé indisponible');
  const opening=factory.open(options.database||'atelier-auth121',1);
  opening.onupgradeneeded=()=>{for(const name of ['keys','sessions'])if(!opening.result.objectStoreNames.contains(name))opening.result.createObjectStore(name)};
  const db=await new Promise<IDBDatabase>((resolve,reject)=>{let abandoned=false;opening.onsuccess=()=>{if(abandoned)opening.result.close();else resolve(opening.result)};opening.onerror=()=>reject(opening.error);opening.onblocked=()=>{abandoned=true;reject(Error('Stockage occupé'))}});
  db.onversionchange=()=>{db.close();connection=null};
  const candidate=await crypt.subtle.generateKey({name:'AES-GCM',length:256},false,['encrypt','decrypt']);
  // La sélection/création est atomique entre onglets. Une clé existante n'est pas remplacée.
  const tx=db.transaction('keys','readwrite'),done=completed(tx),store=tx.objectStore('keys');
  const current=store.get(options.project);let key:CryptoKey=candidate;
  current.onsuccess=()=>{if(current.result)key=current.result;else store.put(candidate,options.project)};
  await done;
  if(key.type!=='secret'||key.extractable!==false||key.algorithm.name!=='AES-GCM'||(key.algorithm as AesKeyAlgorithm).length!==256||!key.usages.includes('encrypt')||!key.usages.includes('decrypt'))throw Error('Clé locale invalide');
  return {db,key};
 })();return connection}
 const aad=(key:string)=>encoder.encode('atelier-fayet-33:session121:'+options.project+':'+key);
 async function write(key:string,value:string){
  if(value.length>1000000)throw Error('Session trop volumineuse');
  const plain=encoder.encode(value);if(plain.byteLength>1000000)throw Error('Session trop volumineuse');
  if(fallback){markClosed(key);memory.set(key,value);return}
  try{
   const {db,key:secret}=await open(),iv=crypt.getRandomValues(new Uint8Array(12));
   const cipher=await crypt.subtle.encrypt({name:'AES-GCM',iv,additionalData:aad(key)},secret,plain);
   const tx=db.transaction('sessions','readwrite'),done=completed(tx);tx.objectStore('sessions').put({version:1,iv,cipher} satisfies Record121,options.project+':'+key);await done;
   memory.delete(key);reopen(key);
  }catch{warn();markClosed(key);memory.set(key,value)}
 }
 async function removeEncrypted(key:string){const {db}=await open(),tx=db.transaction('sessions','readwrite'),done=completed(tx);tx.objectStore('sessions').delete(options.project+':'+key);await done}
 const storage={
  getItem:(key:string)=>run(async()=>{
   if(memory.has(key))return memory.get(key)!;
   if(closed(key)){clearLegacy(key);return null}
   if(!fallback){
    let stored:Record121|undefined;
    try{const {db}=await open(),tx=db.transaction('sessions','readonly'),done=completed(tx);stored=await request(tx.objectStore('sessions').get(options.project+':'+key));await done}
    catch{warn()}
    if(stored){
     try{
      if(stored.version!==1||!(stored.iv instanceof Uint8Array)||stored.iv.length!==12||!(stored.cipher instanceof ArrayBuffer)||stored.cipher.byteLength>1000016)throw Error('Session invalide');
      const {key:secret}=await open();const result=new TextDecoder('utf-8',{fatal:true}).decode(await crypt.subtle.decrypt({name:'AES-GCM',iv:stored.iv,additionalData:aad(key)},secret,stored.cipher));
      clearLegacy(key);return result;
     }catch{
      // Ne jamais réactiver une ancienne copie en clair après une erreur d'intégrité.
      markClosed(key);clearLegacy(key);try{await removeEncrypted(key)}catch{warn()}return null;
     }
    }
   }
   const legacy=readLegacy(key);if(legacy===null)return null;
   await write(key,legacy);clearLegacy(key);return legacy;
  }),
  setItem:(key:string,value:string)=>run(async()=>{await write(key,value);clearLegacy(key)}),
  removeItem:(key:string)=>run(async()=>{
   memory.delete(key);clearLegacy(key);const marked=markClosed(key);
   try{await removeEncrypted(key)}catch{warn();if(!marked)throw Error('Impossible d’effacer la session locale. Ferme cette fenêtre et vérifie le stockage de l’appareil.')}
  }),
  isTemporary:()=>fallback,
 };
 return storage;
}
