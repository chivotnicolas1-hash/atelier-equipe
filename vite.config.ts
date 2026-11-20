import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath,URL } from 'node:url';
import {readdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
function toolboxOffline(){return {name:'toolbox-offline-manifest',closeBundle(){
 const root=fileURLToPath(new URL('./dist',import.meta.url));
 const files=['/toolbox.html','/icon-fayet-v34-192.png',...readdirSync(join(root,'assets')).filter(f=>/\.(js|css)$/.test(f)).map(f=>'/assets/'+f),...readdirSync(join(root,'toolbox')).filter(f=>/\.(json|txt)$/.test(f)&&f!=='offline-manifest.json').map(f=>'/toolbox/'+f)];
 const hash=createHash('sha256');for(const f of files)hash.update(readFileSync(join(root,f)));
 const version=hash.digest('hex').slice(0,16);writeFileSync(join(root,'toolbox/offline-manifest.json'),JSON.stringify({version,files}));
 const sw=join(root,'sw.js');writeFileSync(sw,readFileSync(sw,'utf8').replaceAll('__TOOLBOX_CACHE_VERSION__',version));
}}}
export default defineConfig({plugins:[react(),toolboxOffline()],build:{rollupOptions:{input:{app:fileURLToPath(new URL('./index.html',import.meta.url)),toolbox:fileURLToPath(new URL('./toolbox.html',import.meta.url))}}},resolve:{alias:{'@':fileURLToPath(new URL('./src',import.meta.url))}}});
