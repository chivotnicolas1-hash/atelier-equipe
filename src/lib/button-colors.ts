export function customButtonStyle(color?:string|null){
 if(!color||!/^#[0-9a-f]{6}$/i.test(color))return undefined;
 const rgb=[1,3,5].map(i=>parseInt(color.slice(i,i+2),16)/255).map(c=>c<=.04045?c/12.92:((c+.055)/1.055)**2.4);
 const luminance=.2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];
 return {backgroundColor:color,borderColor:color,color:luminance>.179?'#000000':'#ffffff'};
}
