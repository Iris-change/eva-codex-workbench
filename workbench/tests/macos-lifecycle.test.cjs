'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),net=require('node:net'),{spawn}=require('node:child_process');
const {probeHealth}=require('../start-macos.cjs'),root=path.resolve(__dirname,'../..');
function freePort(){return new Promise((resolve,reject)=>{const server=net.createServer();server.on('error',reject);server.listen(0,'127.0.0.1',()=>{const port=server.address().port;server.close(()=>resolve(port))})})}
function launch(file,args,env){const child=spawn(file,args,{cwd:os.tmpdir(),env:{...process.env,...env},stdio:['ignore','pipe','pipe']});let output='';child.stdout.on('data',data=>{output+=data});child.stderr.on('data',data=>{output+=data});const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',(code,signal)=>resolve({code,signal}))});done.catch(()=>{});return {child,done,output:()=>output}}
async function bounded(promise,ms=10000){let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('launcher lifecycle timed out')),ms)})])}finally{clearTimeout(timer)}}
async function ready(process){let timer;try{await bounded(new Promise((resolve,reject)=>{const check=()=>{if(process.output().includes('Workbench ready at '))resolve()};timer=setInterval(check,30);process.done.then(()=>reject(Error(process.output())),reject);check()}))}finally{clearInterval(timer)}}
async function shutdown(url){const page=await fetch(url,{signal:AbortSignal.timeout(2000)}),cookie=page.headers.get('set-cookie').split(';')[0];await page.text();const response=await fetch(url+'/api/shutdown',{method:'POST',headers:{Cookie:cookie,Origin:url,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(2000)});await response.text();return response.status}
async function stop(process){if(process.child.exitCode===null&&process.child.signalCode===null){process.child.kill('SIGTERM');await bounded(process.done)}}
test('macOS launcher owns fresh servers, reuses existing EVA, and exits cleanly on SIGINT and UI shutdown',{skip:process.platform!=='darwin',timeout:30000},async()=>{
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'eva mac lifecycle ')),env={HACKCLAW_DATA_DIR:path.join(temporary,'data'),CODEX_HOME:path.join(temporary,'codex'),HACKCLAW_CODEX:process.execPath};let primary,secondary,cleanupURL;
 fs.mkdirSync(env.CODEX_HOME);
 try{
  let port=await freePort(),url='http://127.0.0.1:'+port;
  // Node stands in for Codex: readiness/lifecycle must not require an account or real CLI calls.
  primary=launch(process.execPath,[path.join(root,'workbench/start-macos.cjs'),'--port',String(port),'--no-browser'],env);await ready(primary);assert.equal(await probeHealth(url),true);
  secondary=launch(process.execPath,[path.join(root,'workbench/start-macos.cjs'),'--port',String(port),'--no-browser'],{...env,HACKCLAW_CODEX:'/does/not/exist'});assert.equal((await bounded(secondary.done)).code,0,secondary.output());assert.equal(await probeHealth(url),true);assert.equal(primary.child.exitCode,null,'reuse must not stop the existing service');
  primary.child.kill('SIGINT');assert.equal((await bounded(primary.done)).code,0,primary.output());assert.equal(await probeHealth(url),false);
  port=await freePort();url='http://127.0.0.1:'+port;
  primary=launch(path.join(root,'Start-EVA.command'),['--port',String(port),'--no-browser'],env);await ready(primary);cleanupURL=url;
  assert.equal(await shutdown(url),200);assert.equal((await bounded(primary.done)).code,0,primary.output());assert.equal(await probeHealth(url),false);cleanupURL=null;
 }finally{if(cleanupURL)await shutdown(cleanupURL).catch(()=>{});if(secondary)await stop(secondary);if(primary)await stop(primary);fs.rmSync(temporary,{recursive:true,force:true})}
});
