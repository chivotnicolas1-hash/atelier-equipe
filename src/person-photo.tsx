export const DEFAULT_PHOTO='/norauto-avatar.jpg';
export default function PersonPhoto({photo,alt=''}:{photo?:string|null,alt?:string}){
 return <img className={'header-photo person-photo'+(!photo?' default-person-photo':'')} src={photo||DEFAULT_PHOTO} alt={alt} onError={e=>{if(!e.currentTarget.src.endsWith(DEFAULT_PHOTO)){e.currentTarget.src=DEFAULT_PHOTO;e.currentTarget.classList.add('default-person-photo')}}}/>;
}
