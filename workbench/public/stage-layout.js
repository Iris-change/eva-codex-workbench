// Shared anchors keep every startup phase centered and the confirmation card clear.
export function stageLayout(width,height){
 const mobile=width<900;
 return {
  cx:width/2,cy:height*.45,
  logoSize:Math.min(width*(mobile?.46:.22),height*.3,mobile?190:300),
  ringRadius:Math.min(width*(mobile?.27:.14),height*(height<650?.15:.19),mobile?150:195),
  linkSize:mobile?58:68,
  cardBottom:height<600?28:height<700?40:height<800?54:height<1050?64:144,
 };
}
