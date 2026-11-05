'use strict';
// Only visual partition reconstruction. No actual protocol or permission changes.
window.ProtocolFX=(()=>{
 let active=null;
 const ease=value=>{const x=Math.max(0,Math.min(1,value));return x*x*x*(x*(x*6-15)+10)};
 function reconstruct(target,label='PARTITION / REWRITE'){
  if(!target||matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  active?.finish();const bounds=target.getBoundingClientRect();if(bounds.width<1||bounds.height<1)return;
  const layer=document.createElement('div');layer.className='protocol-reconstruction';layer.setAttribute('aria-hidden','true');
  Object.assign(layer.style,{left:bounds.left+'px',top:bounds.top+'px',width:bounds.width+'px',height:bounds.height+'px'});
  const cols=6,rows=8,cw=bounds.width/cols,ch=bounds.height/rows,cells=[];
  for(let row=0;row<rows;row++)for(let col=0;col<cols;col++){
   const cell=document.createElement('div');cell.className='protocol-cell';
   Object.assign(cell.style,{left:col*cw+'px',top:row*ch+'px',width:(cw+.2)+'px',height:(ch+.2)+'px'});
   const clone=target.cloneNode(true);clone.removeAttribute('id');clone.querySelectorAll('[id]').forEach(n=>n.removeAttribute('id'));clone.inert=true;
   Object.assign(clone.style,{position:'absolute',left:-col*cw+'px',top:-row*ch+'px',width:bounds.width+'px',height:bounds.height+'px',margin:'0',visibility:'visible'});
   cell.append(clone);layer.append(cell);cells.push({cell,row,col,index:row*cols+col});
  }
  const note=document.createElement('div');note.className='protocol-note';layer.append(note);document.body.append(layer);
  const original=target.style.visibility;target.style.visibility='hidden';let frameId;
  const finish=()=>{cancelAnimationFrame(frameId);target.style.visibility=original;layer.remove();if(active?.layer===layer)active=null};active={finish,layer};
  function render(progress){
   const p=ease(progress);note.textContent=(p<.22?'01 / PARTITION LOCK':p<.65?'02 / BLOCK REMAP':'03 / RECONSTRUCT')+'   '+label;
   cells.forEach(({cell,row,col,index})=>{
    const selected=(index*7+row)%5<3;let dx=0,dy=0;
    if(selected&&p>.17&&p<.82){const strength=p<.36?ease((p-.17)/.19):1-ease((p-.57)/(.25+col*.01));dx=Math.round(((col%3)-1)*32*strength/8)*8;dy=Math.round(((row%3)-1)*16*strength/8)*8;}
    cell.style.transform=`translate(${dx}px,${dy}px)`;
    cell.classList.toggle('rewritten',selected&&p>.18&&p<.7);
    cell.classList.toggle('locked',p<.21&&(row+col)%4===0);
    cell.style.zIndex=selected?'2':'1';
   });
  }
  const start=performance.now();function tick(now){const p=(now-start)/960;render(p);if(p<1)frameId=requestAnimationFrame(tick);else finish()}frameId=requestAnimationFrame(tick);
  return {render,finish,pause(){cancelAnimationFrame(frameId)}};
 }
 return {reconstruct};
})();
