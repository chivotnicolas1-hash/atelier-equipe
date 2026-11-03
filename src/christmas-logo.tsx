import type {ImgHTMLAttributes} from 'react';
import {useDesign} from './design';
export default function ChristmasLogo({src,...attrs}:ImgHTMLAttributes<HTMLImageElement>){const {christmasLogo}=useDesign();return <img {...attrs} src={christmasLogo?'/logo-noel.png':src}/>}
