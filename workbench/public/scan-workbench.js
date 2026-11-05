import {scanPosition,loopTime,breathe} from './motion-v12.js';
(()=>{
 const layer=document.getElementById('workbenchScan'),main=document.querySelector('main'),space=document.querySelector('.workspace'),beam=layer.querySelector('.scan-beam');
 let settings={enabled:true,period:8.5,brightness:.35};try{settings={...settings,...JSON.parse(localStorage.getItem('hc-scan-settings')||'{}')}}catch{}
 // Restore the workspace-only beam after the opening-beam removal. Later user toggles remain persistent.
 if(localStorage.getItem('hc-scan-preference-version')!=='workspace-on-1'){settings.enabled=true;localStorage.setItem('hc-scan-preference-version','workspace-on-1')}
 settings.period=Math.min(10,Math.max(7,Number(settings.period)||8.5));settings.brightness=Math.min(.7,Math.max(.1,Number(settings.brightness)||.35));
 const enabled=document.getElementById('scanEnabled'),period=document.getElementById('scanPeriod'),brightness=document.getElementById('scanBrightness');
 let targets=[],height=0,started=performance.now(),last=0,refreshTimer,frozen=false,sceneAnchor=null;
 const wave=main.querySelector('.wave'),baseline=main.querySelector('.baseline');
 wave.setAttribute('fill','none');wave.setAttribute('stroke','#af8872');wave.setAttribute('stroke-width','1.2');baseline.setAttribute('fill','none');baseline.setAttribute('stroke','#423332');
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 function cache(){const m=main.getBoundingClientRect(),s=space.getBoundingClientRect();height=s.height;layer.style.top=s.top-m.top+'px';layer.style.height=height+'px';layer.style.setProperty('--scan-distance',height+72+'px');targets=[...main.querySelectorAll('.decoder,.composer,.override-register,.inspector-tabs')].filter(node=>node.getBoundingClientRect().height>0).map(node=>{node.classList.add('scan-reactive');const box=node.getBoundingClientRect();return {node,y:box.top-s.top+box.height*.5}})}
 function apply(){enabled.checked=!!settings.enabled;period.value=settings.period;brightness.value=settings.brightness;document.getElementById('scanPeriodLabel').textContent=settings.period.toFixed(1)+' 秒';document.getElementById('scanBrightnessLabel').textContent=Math.round(settings.brightness*100)+'%';layer.style.setProperty('--scan-opacity',settings.brightness);layer.hidden=!settings.enabled||reduced.matches;started=performance.now();beam.style.animation='none';for(const {node} of targets)node.style.setProperty('--scan-response',0);localStorage.setItem('hc-scan-settings',JSON.stringify(settings));window.workbenchScanSettings={...settings};paint(0);}
 enabled.onchange=()=>{settings.enabled=enabled.checked;apply()};period.oninput=()=>{settings.period=+period.value;apply()};brightness.oninput=()=>{settings.brightness=+brightness.value;apply()};reduced.addEventListener('change',apply);
 function frame(seconds){if(reduced.matches)return;beam.style.transform=`translate3d(0,${scanPosition(seconds,height,settings.period)}px,0)`;main.style.setProperty('--codex-angle',loopTime(seconds,6)*360+'deg');main.style.setProperty('--codex-breathe',1+.035*breathe(seconds,3.8))}
 function paint(seconds){frame(seconds);const y=scanPosition(seconds,height,settings.period)+44;for(const target of targets){const response=layer.hidden?0:Math.exp(-Math.pow((target.y-y)/85,2))*settings.brightness;target.node.style.setProperty('--scan-response',response.toFixed(3))}if(!reduced.matches){const active=main.dataset.codexActivity==='active',phase=loopTime(seconds,2.8)*2.8,points=Array.from({length:71},(_,i)=>{const x=i*4,envelope=Math.sin(i*.23+phase*.77)*Math.sin(i*.61-phase*1.15),amp=active?24:15;return `${i?'L':'M'}${x} ${(42+envelope*amp).toFixed(2)}`});wave.setAttribute('d',points.join(' '))}}
 const clock=now=>sceneAnchor?sceneAnchor.time+(sceneAnchor.running?(now-sceneAnchor.at)/1000:0):(now-started)/1000;
 function tick(now){requestAnimationFrame(tick);if(frozen||document.hidden)return;const seconds=clock(now);frame(seconds);if(now-last>=80){last=now;paint(seconds)}}
 window.syncWorkbenchMotion=(time,running)=>{if(frozen)return;sceneAnchor={time,running,at:performance.now()}};
 window.releaseWorkbenchMotion=()=>{started=performance.now()-clock(performance.now())*1000;sceneAnchor=null};
 window.renderWorkbenchScan=seconds=>{frozen=true;paint(seconds)};
 new ResizeObserver(cache).observe(space);new MutationObserver(()=>{clearTimeout(refreshTimer);refreshTimer=setTimeout(cache,250)}).observe(main,{childList:true,subtree:true});cache();apply();requestAnimationFrame(tick);
})();
