import {createRoot} from 'react-dom/client';
import Toolbox from './index';
import {ThemeToggle} from '../theme';
import '../globals.css';import '../professional.css';
try{const saved=JSON.parse(localStorage.getItem('tb114-style')||'null');if(saved){document.documentElement.dataset.season=saved.season||'none';document.documentElement.dataset.themeScope=saved.scope||'mobile';for(const[k,v]of Object.entries(saved.variables||{}))if(k.startsWith('--design-')&&typeof v==='string')document.documentElement.style.setProperty(k,v)}}catch{}
createRoot(document.getElementById('root')!).render(<main className="tb-offline-page"><header className="tb-offline-header"><img src="/icon-fayet-v34-192.png" alt="Atelier Fayet 33"/><strong>Atelier Toolbox 33</strong><ThemeToggle/><a className="secondary" href="/">Retour à l’application</a></header><Toolbox standalone/></main>);
