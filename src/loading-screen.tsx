import {useDesign} from './design';
export default function LoadingScreen(){const {design}=useDesign();return <div className="loading-screen" role="status" aria-live="polite"><img src="/atelier-fayet-logo.png" alt="Atelier Fayet 33"/><p>{design.signature}</p><span className="muted">Chargement de l’atelier…</span></div>}
