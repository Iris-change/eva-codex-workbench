import * as THREE from './vendor/three.module.js';
import {loadSequenceAudio} from './sequence-audio.js';
import {drawUnit02Scene} from './unified-sequence.js';
import {sCurve as smooth,loopTime} from './motion-v12.js';
import {SEQUENCE,sceneTime} from './sequence-timing.js';
import {stageLayout} from './stage-layout.js';

// Fictional identity visualization; no camera, biometric API or account changes.
const W=1920,H=1080,DURATION=SEQUENCE.duration;
const load=src=>new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=()=>reject(Error('Media unavailable: '+src));i.src=src});

export async function startIdentity(){
 await document.fonts.load('900 40px "Unit02 Mincho"','系统唤醒二号机明日香');
 const [nerv,title,knot]=await Promise.all([load('/media/eva/nerv-mark.svg'),load('/media/eva/theme-title.svg'),load('/media/official/codex-node.svg')]);
 const canvas=document.getElementById('sequence'),source=document.createElement('canvas'),target=document.createElement('canvas'),terminal=document.createElement('canvas');
 source.width=target.width=terminal.width=W;source.height=target.height=terminal.height=H;
 const c=source.getContext('2d'),tc=target.getContext('2d');tc.fillStyle='#0b0c0f';tc.fillRect(0,0,W,H);
 const renderer=new THREE.WebGLRenderer({canvas,antialias:false,alpha:true,powerPreference:'high-performance'});
 renderer.setClearColor(0x000000,0);
 let layoutHeight=H;
 function resizeBuffers(){
  layoutHeight=W*innerHeight/innerWidth;
  const pixelRatio=Math.min(devicePixelRatio,2),scale=Math.min(2,Math.max(1,innerWidth*pixelRatio/W));
  for(const [buffer,pen]of[[source,c],[target,tc],[terminal,terminal.getContext('2d')]]){
   buffer.width=Math.round(W*scale);buffer.height=Math.round(layoutHeight*scale);pen.setTransform(scale,0,0,scale,0,0);pen.imageSmoothingQuality='high';
  }
  renderer.setPixelRatio(pixelRatio);renderer.setSize(innerWidth,innerHeight);
 }
 resizeBuffers();renderer.outputColorSpace=THREE.SRGBColorSpace;
 const sourceTex=new THREE.CanvasTexture(source),targetTex=new THREE.CanvasTexture(target),terminalTex=new THREE.CanvasTexture(terminal);
 for(const texture of [sourceTex,targetTex,terminalTex]){texture.minFilter=THREE.LinearFilter;texture.generateMipmaps=false}
 const closingPen=terminal.getContext('2d');
 const uniforms={sourceImage:{value:sourceTex},targetImage:{value:terminalTex},targetIsTerminal:{value:1},progress:{value:0},logoGlitchPhase:{value:0},clock:{value:0},ready:{value:0},handoff:{value:0},ratio:{value:innerWidth/innerHeight},waveOrigin:{value:new THREE.Vector2(.5,.5)}};
 const material=new THREE.ShaderMaterial({transparent:true,uniforms,vertexShader:`varying vec2 vUv;void main(){vUv=uv;gl_Position=vec4(position.xy,0.,1.);}`,fragmentShader:`
 precision highp float;uniform sampler2D sourceImage,targetImage;uniform float progress,logoGlitchPhase,clock,ready,handoff,ratio,targetIsTerminal;uniform vec2 waveOrigin;varying vec2 vUv;
 vec3 readSource(vec2 uv){return texture2D(sourceImage,uv).rgb;}
 vec3 readTarget(vec2 uv){return texture2D(targetImage,uv).rgb;}
 float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
 void main(){
  vec2 uv=vUv;float p=progress;
  // Matrix partitions sample actual source/target pixels; never solid-color tiles.
  float band=floor(uv.y*108.);float grouping=1.+floor(hash(vec2(band,3.))*3.);
  vec2 grid=vec2(64./grouping,108.);vec2 id=floor(uv*grid),center=(id+.5)/grid;
  float travel=length((center-waveOrigin)*vec2(1.2,.78));
  float local=clamp((p*1.55-travel*.9)/.42,0.,1.);local=local*local*local*(local*(local*6.-15.)+10.);float front=sin(local*3.14159265);
  float seed=hash(id),tick=floor(clock*13.);float direction=center.x<waveOrigin.x?-1.:1.;
  float displacement=direction*(.003+seed*.012)*front;
  displacement+=floor(hash(vec2(band,tick))*3.-1.)*.001*front;
  vec2 sampleUv=clamp(uv-vec2(displacement,0.),vec2(.001),vec2(.999));
  float rewritten=smoothstep(.48,.8,local);
  vec3 color=mix(readSource(sampleUv),readTarget(sampleUv),rewritten*ready);
  color=mix(color,readSource(clamp(sampleUv+vec2(.012,0.),0.,1.)),front*.045*(1.-rewritten));
  color.r=mix(color.r,readSource(clamp(sampleUv+vec2(.0018*front,0.),0.,1.)).r,front*.06);
  vec2 edge=fract(uv*grid);float seam=step(.97,edge.y)*step(.75,seed);
  color+=vec3(.22,.065,.014)*seam*front*.45;
  color+=vec3(.025,.009,.003)*front*step(.86,fract(uv.y*540.));
  // Short horizontal packet tears and sparse cached blocks, sampled from the
  // actual images. Protect the central knot and preserve a clean base frame.
  float phase=p<.001?logoGlitchPhase:p;
  float effect=p<.001?.66:.44;
  if(phase>0. && phase<1.){
   float envelope=sin(phase*3.14159265);
   float packet=floor(phase*18.);
   float radius=length((uv-.5)*vec2(1.,1./ratio));
   float spread=1.-smoothstep(phase*.42+.04,phase*.42+.16,radius);
   float centralProtection=.18+.82*smoothstep(.025,.065,radius);
   float region=(1.-smoothstep(.35,.49,radius))*spread*centralProtection;
   float rhythm=.55+.45*max(exp(-pow((phase-.28)/.14,2.)),exp(-pow((phase-.67)/.13,2.)));
   float amount=envelope*region*effect*rhythm;
   float scanRow=floor(uv.y*240.);
   float columns=8.+floor(hash(vec2(scanRow,4.))*8.);
   float segment=floor(uv.x*columns);
   float strip=step(.91,hash(vec2(scanRow,packet)))*step(.4,hash(vec2(segment,scanRow+packet)));
   strip*=1.-smoothstep(.2,.55,fract(uv.y*240.));
   strip*=smoothstep(.02,.12,fract(uv.x*columns))*(1.-smoothstep(.78,.98,fract(uv.x*columns)));
   float horizontal=(hash(vec2(scanRow,packet+31.))-.5)*.030;
   vec2 tearUv=clamp(uv+vec2(horizontal,0.),vec2(.001),vec2(.999));
   float targetPart=p<.001?0.:rewritten*ready;
   vec3 torn=mix(readSource(tearUv),readTarget(tearUv),targetPart);
   vec3 echo=mix(readSource(clamp(tearUv+vec2(.006,0.),0.,1.)),readTarget(clamp(tearUv+vec2(.006,0.),0.,1.)),targetPart);
   torn=mix(torn,echo,.22);
   color=mix(color,torn,strip*amount*.9);
   color+=vec3(.25,.065,.015)*strip*amount;
   // A few wider packet cells briefly retain coarser image samples.
   vec2 cells=vec2(32.,72.),cell=floor(uv*cells);
   float block=step(.965,hash(cell+vec2(packet,packet*.3)));
   block*=smoothstep(.03,.15,fract(uv.x*cells.x))*(1.-smoothstep(.84,.98,fract(uv.x*cells.x)));
   vec2 cachedUv=clamp(floor((uv+vec2(horizontal*.6,0.))*vec2(480.,270.))/vec2(480.,270.),vec2(.001),vec2(.999));
   vec3 cached=mix(readSource(cachedUv),readTarget(cachedUv),targetPart);
   cached=mix(cached,echo,.15);
   color=mix(color,cached,block*amount*.75);
   // Three aligned scales: packet clusters, quantized microtiles and sorted
   // highlights. Shared seeds keep each cluster coherent for a short hold.
   for(int layer=0;layer<3;layer++){
    float layerId=float(layer),holdFrame=floor(phase*(9.+layerId*3.));
    vec2 clusterGrid=vec2(22.+layerId*16.,36.+layerId*29.);
    vec2 cluster=floor(uv*clusterGrid),inside=fract(uv*clusterGrid);
    float cellSeed=hash(cluster+vec2(holdFrame+layerId*19.,layerId*7.));
    float activeCell=step(.90+layerId*.014,cellSeed);
    float outline=smoothstep(.01,.08,inside.x)*(1.-smoothstep(.90,.99,inside.x));
    float advance=1.-smoothstep(.02,.16,abs(radius-phase*.4+layerId*.035));
    float weight=activeCell*outline*amount*(.32+.68*advance);
    float offset=(cellSeed-.95)*.28;
    vec2 resolution=vec2(240.+layerId*160.,135.+layerId*90.);
    vec2 heldUv=clamp(floor((uv+vec2(offset,0.))*resolution)/resolution,vec2(.001),vec2(.999));
    vec3 heldColor=mix(readSource(heldUv),readTarget(heldUv),targetPart);
    vec3 sorted=heldColor;
    for(int tap=1;tap<3;tap++){
     vec2 candidateUv=clamp(heldUv+vec2(float(tap)*.003,0.),vec2(.001),vec2(.999));
     vec3 candidate=mix(readSource(candidateUv),readTarget(candidateUv),targetPart);
     if(dot(candidate,vec3(.21,.72,.07))>dot(sorted,vec3(.21,.72,.07)))sorted=candidate;
    }
    heldColor=mix(heldColor,sorted,.42);
    color=mix(color,heldColor,weight*.8);
    float edgeTrace=step(.94,inside.y)*weight;
    color+=mix(vec3(.18,.045,.012),vec3(.025,.12,.16),step(.975,cellSeed))*edgeTrace*.45;
   }
   float dispersion=strip*amount*.3;
   color.b=mix(color.b,echo.b,dispersion);
   color+=vec3(.028,.012,.004)*block*amount*step(.82,fract(uv.y*1080.));
  }
  if(p>=1.)color=readTarget(uv);
  gl_FragColor=vec4(color,1.-handoff);
 }`});
 const scene=new THREE.Scene();scene.add(new THREE.Mesh(new THREE.PlaneGeometry(2,2),material));const camera=new THREE.Camera();
 const audio=await loadSequenceAudio('/media/audio-unit02-fluid/voice.wav');
 const voiceTimeline=await (await fetch('/media/audio-unit02-fluid/timeline.json')).json();
 let targetReady=false,snapshotError='',time=0,playing=false,interactive=false,held=false,frame=0,start=0,exporting=false,codexTarget=null,linkConnected=false,lastMotionPost=-1,holdStarted=0,autoStarted=false;
 const startButton=document.getElementById('playSequence'),interactiveButton=document.getElementById('interactiveStart'),confirm=document.getElementById('confirmIdentity');
 function render(t){
  time=Math.max(0,Math.min(DURATION,t));const sceneT=sceneTime(time);
  const destination=codexTarget?{x:codexTarget.x*W,y:codexTarget.y*layoutHeight,size:codexTarget.width*W}:null;
  const options={width:innerWidth,height:innerHeight,nerv,title,knot,connected:linkConnected,held,destination};
  drawUnit02Scene(c,time,options);
  const linkPose=drawUnit02Scene(closingPen,time,{...options,closing:true});terminalTex.needsUpdate=true;sourceTex.needsUpdate=true;
  const finalHandoff=sceneT>=SEQUENCE.handoffStart;uniforms.sourceImage.value=finalHandoff?terminalTex:sourceTex;uniforms.targetImage.value=finalHandoff?targetTex:terminalTex;uniforms.targetIsTerminal.value=finalHandoff?0:1;
  uniforms.logoGlitchPhase.value=0;
  uniforms.clock.value=loopTime(time,1.4)*1.4;uniforms.waveOrigin.value.set(.68,.5);uniforms.progress.value=finalHandoff?smooth((sceneT-SEQUENCE.handoffStart)/(SEQUENCE.handoffEnd-SEQUENCE.handoffStart)):smooth((sceneT-SEQUENCE.transferStart)/(SEQUENCE.transferEnd-SEQUENCE.transferStart));uniforms.handoff.value=smooth((sceneT-SEQUENCE.fadeStart)/(DURATION-SEQUENCE.fadeStart));renderer.render(scene,camera);
  document.getElementById('readout').textContent=time.toFixed(1);document.body.classList.toggle('awaiting',held);confirm.disabled=!held;
  const cue=voiceTimeline.cues.find(cue=>time>=cue.start&&time<cue.end),caption=document.getElementById('systemCaption');caption.hidden=!cue;caption.textContent=cue?cue.text||cue.zh:'';
  if(!exporting&&parent!==window&&Math.abs(time-lastMotionPost)>.075){lastMotionPost=time;parent.postMessage({type:'hackclaw:motion-clock',time,running:playing},location.origin)}
  window.identityStats={version:14,time,sceneTime:sceneT,phase:time<SEQUENCE.lclStart?'nerv-boot':time<SEQUENCE.syncStart?'lcl':time<SEQUENCE.transferStart?'sync':time<SEQUENCE.handoffStart?'transfer':'handoff',source:'single continuous viewport / full-screen LCL',unifiedLayout:true,fullViewportLCL:true,target:targetReady?'actual-workbench-snapshot':'unavailable',workbenchVisible:sceneT>=SEQUENCE.handoffStart,sceneOpacity:1-uniforms.handoff.value,audioPlaceholder:false,mechanicalSpeech:true,language:'ja-JP',syncShape:'circle',irisRemoved:true,motion:'quintic-s-curve',codexLogo:'official-unmodified',codexTarget,linkPose,codexLinked:linkConnected,snapshotError};return window.identityStats;
 }
 function setTarget(bitmap){tc.clearRect(0,0,W,layoutHeight);tc.drawImage(bitmap,0,0,W,layoutHeight);bitmap.close?.();targetTex.needsUpdate=true;targetReady=true;uniforms.ready.value=1;startButton.disabled=interactiveButton.disabled=false;document.getElementById('loadStatus').textContent='工作台已就绪 · 日文清晰系统播报';render(time);if(!autoStarted&&new URLSearchParams(location.search).get('autostart')==='interactive'){autoStarted=true;play(true).catch(error=>{document.getElementById('audioStatus').textContent=error.message})}}
 window.addEventListener('message',e=>{if(e.origin!==location.origin||e.source!==parent)return;if(e.data?.type==='hackclaw:workbench-snapshot'){codexTarget=e.data.codexTarget||null;linkConnected=!!e.data.connected;setTarget(e.data.bitmap)}if(e.data?.type==='hackclaw:snapshot-error'){snapshotError=e.data.message;document.getElementById('loadStatus').textContent='工作台采样失败，请直接进入后重试';console.error(snapshotError)}});
 if(parent!==window)parent.postMessage({type:'hackclaw:snapshot-request'},location.origin);else document.getElementById('loadStatus').textContent='请从工作台“身份入口”打开完整预览';
 function holdTick(){if(!held)return;render(SEQUENCE.hold);frame=requestAnimationFrame(holdTick)}
 function tick(now){if(!playing||exporting)return;let t=!audio.paused&&!audio.ended?audio.currentTime:(now-start)/1000;if(interactive&&t>=SEQUENCE.hold&&!held){held=true;holdStarted=performance.now();playing=false;audio.pause();audio.currentTime=SEQUENCE.hold;t=SEQUENCE.hold}render(t);if(t>=DURATION-.025){playing=false;window.exitIdentityScene();return}if(playing)frame=requestAnimationFrame(tick);else if(held)frame=requestAnimationFrame(holdTick)}
 async function play(mode){if(matchMedia('(prefers-reduced-motion: reduce)').matches){window.exitIdentityScene();return}if(!targetReady)return;interactive=mode;held=false;document.body.classList.add('playing');audio.currentTime=0;start=performance.now();playing=true;if(document.getElementById('identitySound').checked){try{await audio.play()}catch{document.getElementById('audioStatus').textContent='声音未能播放 · 当前为静音预览'}}frame=requestAnimationFrame(tick)}
 startButton.onclick=()=>play(false);interactiveButton.onclick=()=>play(true);
 confirm.onclick=async()=>{if(!held)return;cancelAnimationFrame(frame);confirm.disabled=true;held=false;interactive=false;start=performance.now()-SEQUENCE.hold*1000;render(SEQUENCE.hold);playing=true;if(document.getElementById('identitySound').checked)try{await audio.play()}catch{}frame=requestAnimationFrame(tick)};
 document.getElementById('replay').onclick=()=>{playing=false;held=false;interactive=false;exporting=false;audio.pause();audio.currentTime=0;cancelAnimationFrame(frame);document.body.classList.remove('playing','exporting');render(0)};
 function placeConfirmation(){const panel=document.getElementById('confirmLayer');panel.style.left='50%';panel.style.top='auto';panel.style.bottom=stageLayout(innerWidth,innerHeight).cardBottom+'px';panel.style.transform='translateX(-50%)'}
 placeConfirmation();
 addEventListener('resize',()=>{placeConfirmation();const saved=document.createElement('canvas');saved.width=target.width;saved.height=target.height;saved.getContext('2d').drawImage(target,0,0);resizeBuffers();tc.drawImage(saved,0,0,W,layoutHeight);for(const texture of [sourceTex,targetTex,terminalTex]){texture.dispose();texture.needsUpdate=true}uniforms.ratio.value=innerWidth/innerHeight;render(time)});
 window.renderSequence=t=>{exporting=true;playing=false;audio.pause();cancelAnimationFrame(frame);document.body.classList.add('playing','exporting');return render(t)};
 window.IDENTITY_DURATION=DURATION;window.pauseIdentityRender=()=>{playing=false;audio.pause();cancelAnimationFrame(frame)};window.identityAudio=audio;window.setIdentityTarget=setTarget;
 render(0);if(parent!==window)parent.postMessage({type:'hackclaw:intro-ready'},location.origin);return {available:true,duration:DURATION};
}
