'use strict';
if(new URLSearchParams(location.search).get('autostart')==='interactive')document.body.classList.add('playing');
window.exitIdentityScene=()=>{
 if(parent!==window)parent.postMessage({type:'hackclaw:intro-close',confirmed:true},location.origin);
 else {sessionStorage.setItem('hc-identity-admitted','1');location.href='/'}
};
document.getElementById('skipTransition').onclick=window.exitIdentityScene;
document.getElementById('emergencyExit').onclick=window.exitIdentityScene;
window.identityReady=import('./intro-cg.js').then(module=>module.startIdentity()).catch(error=>{
 document.body.classList.add('load-failed');
 document.getElementById('startupError').textContent='视觉场景未能加载，可直接进入工作台。';
 document.getElementById('emergencyExit').hidden=false;
 console.error('Identity scene failed:',error.message);
 return {available:false};
});
