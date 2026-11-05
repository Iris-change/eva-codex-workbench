import {stage} from './motion-v12.js';

// Fixed geometry and scene time keep the peripheral lamps stable across replay.
export function drawBootAtmosphere(c,time,w,h,{liquid=false}={}){
 const mobile=w<900,fade=stage(time,.3,1.8)*(1-stage(time,18.2,19.4));
 if(fade<=0)return;
 const size=Math.min(w*(mobile?.09:.065),h*.095,Math.max(12,(h*.5-110)/4.1)),ink=liquid?'#ffb05c':'#c52b2e';
 c.save();c.globalAlpha*=fade;c.strokeStyle=ink;c.fillStyle=ink;c.lineWidth=.9;
 for(let side=0;side<2;side++)for(let row=0;row<5;row++){
  const x=w*(side?.87:.13),y=h*.5+(row-2)*size*1.65,phase=time/(2.7+row*.3)+row*.29+side*.43;
  const pulse=Math.pow((1+Math.sin(phase*Math.PI*2))/2,5),a=(liquid?.045:.035)+pulse*(liquid?.20:.22);
  c.save();c.translate(x,y);c.globalAlpha*=a;
  c.beginPath();for(let i=0;i<6;i++){const angle=Math.PI/3*i,px=Math.cos(angle)*size,py=Math.sin(angle)*size*.72;if(i)c.lineTo(px,py);else c.moveTo(px,py)}c.closePath();c.fill();
  c.globalAlpha*=1.5;c.beginPath();for(let i=0;i<6;i++){const angle=Math.PI/3*i,px=Math.cos(angle)*(size+5),py=Math.sin(angle)*(size+5)*.72;if(i)c.lineTo(px,py);else c.moveTo(px,py)}c.closePath();c.stroke();
  // Thin gaps give the illuminated panels a monitor texture.
  c.save();c.globalCompositeOperation='source-over';c.globalAlpha=a*.5*fade;c.strokeStyle='#090b0c';for(let yy=-size*.55;yy<size*.56;yy+=4){const half=size*(1-Math.abs(yy)/(size*1.45));c.beginPath();c.moveTo(-half,yy);c.lineTo(half,yy);c.stroke()}c.restore();
  for(let j=0;j<5;j++){c.globalAlpha=fade*a*(.35+.65*((j+row+side)%3===Math.floor(time*.8)%3));c.fillRect(-size+j*size*.43,size*.78,size*.30,2)}
  const label=(Math.floor(time/1.4)+row+side)%2===0?'WARNING':'EMERGENCY';
  c.globalAlpha=fade*(liquid?.35+pulse*.45:.15+pulse*.5);c.fillStyle=liquid?'#582115':'#f07864';
  c.font=`700 ${Math.max(9,Math.min(25,size*.26))}px Bahnschrift,Arial,sans-serif`;c.textAlign='center';c.textBaseline='middle';c.fillText(label,0,0,size*1.65);
  c.restore();
 }
 c.restore();
}
