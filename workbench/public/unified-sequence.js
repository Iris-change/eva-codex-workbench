import {stage} from './motion-v12.js';
import {drawCodexLink} from './codex-link.js';
import {SEQUENCE as S} from './sequence-timing.js';
import {stageLayout} from './stage-layout.js';
import {drawBootAtmosphere} from './boot-atmosphere.js';

// One continuous stage: liquid is a viewport transition, never a diagram in a panel.
export function drawUnit02Scene(c,time,{width:w,height:h,nerv,knot,connected,closing=false,destination}){
 const mobile=w<900,pad=mobile?25:Math.max(45,w*.045),scale=1920/w,layout=stageLayout(w,h),{cx,cy}=layout;
 const ink='#e8e2d7',red='#b62026',orange='#f06a22',yellow='#e7bc35';
 c.save();c.scale(scale,scale);c.fillStyle='#090b0c';c.fillRect(0,0,w,h);
 const text=(s,x,y,size=12,color=ink,align='left',mincho=false)=>{c.font=`${mincho||size>=25?900:500} ${size}px ${mincho||size>=25?'"Unit02 Mincho","SimSun",serif':'Bahnschrift,"Microsoft YaHei",sans-serif'}`;c.fillStyle=color;c.textAlign=align;c.fillText(s,x,y)};
 const line=(x,y,x2,y2,color='#5a2527',width=1)=>{c.beginPath();c.strokeStyle=color;c.lineWidth=width;c.moveTo(x,y);c.lineTo(x2,y2);c.stroke()};
 for(let x=pad;x<w-pad;x+=46)line(x,92,x,h-70,'#e8e2d705');
 for(let y=92;y<h-70;y+=46)line(pad,y,w-pad,y,'#e8e2d705');
 drawBootAtmosphere(c,time,w,h);
 // The same centered anchor persists from the NERV mark to the synchronization ring.
 // Fade up at boot, then disappear with the same curve that raises the LCL surface.
 const wakeAlpha=stage(time,0,1.8)*(1-stage(time,S.lclStart,S.lclEnd));
 if(wakeAlpha>0){c.save();c.globalAlpha=wakeAlpha;const size=Math.min(w*(mobile?.46:.27),h*.36,mobile?210:390),top=(h-size-(mobile?132:168))/2;if(nerv)c.drawImage(nerv,cx-size/2,top,size,size);text('系统唤醒',cx,top+size+(mobile?78:108),mobile?46:76,ink,'center');text('EVANGELION-02 / ASUKA PRIVATE WORKSTATION',cx,top+size+(mobile?117:155),mobile?11:17,orange,'center');c.restore()}
 const syncAlpha=stage(time,S.syncStart,S.syncStart+.7)*(closing?1-stage(time,S.transferStart,S.transferEnd):1);
 if(syncAlpha>0){c.save();c.globalAlpha=syncAlpha;
  const metric=99.2*stage(time,S.syncStart,S.hold)+.8*stage(time,S.hold,S.syncFull),p=metric/100,r=layout.ringRadius,color=p>.98?yellow:orange,end=-Math.PI/2+Math.PI*2*metric/100;
  c.lineWidth=mobile?5:7;c.strokeStyle='#452126';c.beginPath();c.arc(cx,cy,r,0,Math.PI*2);c.stroke();c.lineCap='round';c.strokeStyle=color;
  for(const [blur,width,alpha]of[[32,15,.24],[16,9,.5],[8,4,1]]){c.save();c.globalAlpha*=alpha;c.shadowColor=color;c.shadowBlur=blur;c.lineWidth=width;c.beginPath();c.arc(cx,cy,r,-Math.PI/2,end);c.stroke();c.restore()}
  c.shadowBlur=0;c.strokeStyle='#fff0d4';c.lineWidth=1.2;c.beginPath();c.arc(cx,cy,r-1,-Math.PI/2,end);c.stroke();c.lineCap='butt';
  if(p>0){c.shadowColor=color;c.shadowBlur=18;c.fillStyle='#fff0d4';c.beginPath();c.arc(cx+Math.cos(end)*r,cy+Math.sin(end)*r,2.8,0,Math.PI*2);c.fill();c.shadowBlur=0}
  text(metric.toFixed(1)+'%',cx,cy+10,mobile?35:53,ink,'center');text('同步率',cx,cy+(mobile?58:68),mobile?14:18,'#baa18d','center',true);
  c.restore();
 }
 let pose=null;
 if(closing){const a=stage(time,S.transferStart,S.transferEnd);c.save();c.globalAlpha=a;text('EVANGELION-02',cx,cy-45,mobile?30:52,red,'center');text(time<16?'正在连接工作台':'工作台已就绪',cx,cy+58,mobile?43:80,ink,'center');text(connected?'CODEX / 本地连接已建立':'CODEX / 等待连接',cx,cy+112,mobile?11:14,'#c69a73','center');const p=stage(time,S.handoffStart,S.handoffEnd),target=destination?{x:destination.x/scale,y:destination.y/scale,size:destination.size/scale}:{x:w-pad,y:45,size:16},x=cx*(1-p)+target.x*p,y=Math.min(h-90,cy+215)*(1-p)+target.y*p,size=layout.linkSize*(1-p)+target.size*p;drawCodexLink(c,knot,{x,y,size,progress:1,time,connected});pose={x:x*scale,y:y*scale,size:size*scale};c.restore()}
 // LCL covers the entire viewport, including the existing typography, then clears.
 const fill=stage(time,S.lclStart,S.lclEnd),clarity=1-stage(time,S.lclClearStart,S.lclClearEnd),liquid=fill>0?clarity:0;
 if(liquid>0){c.save();const level=h*(1-fill);c.beginPath();c.moveTo(0,h);c.lineTo(0,level);for(let i=0;i<=100;i++){const x=w*i/100,y=level+Math.sin(i*.115+time*.65)*5+Math.sin(i*.26-time*.4)*2;c.lineTo(x,y)}c.lineTo(w,h);c.closePath();c.clip();
  const tint=c.createLinearGradient(0,Math.max(0,level),0,h);tint.addColorStop(0,'#f6a343');tint.addColorStop(.35,'#c76523');tint.addColorStop(1,'#8c321a');c.globalAlpha=.72*liquid;c.fillStyle=tint;c.fillRect(0,0,w,h);
  c.globalAlpha=.12*liquid;const light=c.createLinearGradient(0,0,w,h);light.addColorStop(0,'transparent');light.addColorStop(.45,'#ffd195');light.addColorStop(.65,'transparent');c.fillStyle=light;c.fillRect(0,0,w,h);
  c.globalAlpha=.27*liquid;for(let i=0;i<17;i++){const x=w*((i*.137+.08)%1),y=h-((time*.045+i*.161)%1)*h;c.strokeStyle='#ffdbad';c.lineWidth=1;c.beginPath();c.arc(x,y,1.5+i%4,0,Math.PI*2);c.stroke()}
  c.save();c.globalAlpha=liquid;drawBootAtmosphere(c,time,w,h,{liquid:true});c.restore();
  c.restore();c.save();c.globalAlpha=.65*liquid;c.beginPath();for(let i=0;i<=100;i++){const x=w*i/100,y=level+Math.sin(i*.115+time*.65)*5+Math.sin(i*.26-time*.4)*2;if(i)c.lineTo(x,y);else c.moveTo(x,y)}c.strokeStyle='#ffd49a';c.lineWidth=1.4;c.stroke();c.restore();
 }
 // Shared armour perimeter, with no side dashboard or separate scene columns.
 // Repeat the workbench's NERV mark and Mincho wordmark in the boot frame.
 const brandSize=mobile?43:58,brandX=pad+brandSize+(mobile?10:16);
 if(nerv)c.drawImage(nerv,pad,19,brandSize,brandSize);
 text('EVANGELION-02',brandX,mobile?44:46,mobile?16:22,ink,'left',true);
 text('私人工作台',brandX,mobile?63:66,mobile?9:10,'#d6aaa0');
 text('二号机',w-pad,47,19,orange,'right');text('ASUKA / 明日香',w-pad,67,10,'#b39b8a','right');line(pad,85,w-pad,85);
 const phase=time<S.lclStart?'系统唤醒':time<S.syncStart?'环境准备':time<S.transferStart?'驾驶员同步':'进入工作台';text(phase,pad,h-30,11,'#b39b8a');text('本地私人界面',w-pad,h-30,10,'#b39b8a','right');
 for(const right of [false,true]){c.save();if(right){c.translate(w,0);c.scale(-1,1)}c.fillStyle=red;c.fillRect(0,0,mobile?6:10,h);c.beginPath();c.rect(mobile?10:16,106,mobile?7:11,h-185);c.clip();for(let y=70;y<h;y+=28){c.fillStyle='#9a1c25';c.beginPath();c.moveTo(5,y);c.lineTo(33,y-20);c.lineTo(33,y-9);c.lineTo(5,y+11);c.fill()}c.restore()}
 for(const bottom of [false,true]){c.save();if(bottom){c.translate(0,h);c.scale(1,-1)}for(let i=0;i<(mobile?6:14);i++){c.save();c.translate(pad+i*14,9);c.transform(1,0,-.65,1,0,0);c.fillStyle=i%4===0?orange:yellow;c.fillRect(0,0,7,5);c.restore()}line(pad+(mobile?94:206),12,w-pad,12);c.restore()}
 c.restore();return pose;
}
