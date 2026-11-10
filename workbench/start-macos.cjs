'use strict';
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),http=require('node:http');
const {spawn,execFile}=require('node:child_process'),{promisify}=require('node:util');
const run=promisify(execFile);
function parseArgs(args){
 const options={port:43137,noBrowser:false};
 for(let i=0;i<args.length;i++){
  if(args[i]==='--no-browser')options.noBrowser=true;
  else if(args[i]==='--port'){const value=args[++i];if(!/^\d+$/.test(value||'')||Number(value)<1024||Number(value)>65535)throw Error('--port must be an integer from 1024 to 65535');options.port=Number(value)}
  else throw Error('Unknown option: '+args[i]);
 }
 return options;
}
function findExecutable(name,env=process.env){
 const candidates=path.isAbsolute(name)?[name]:(env.PATH||'').split(path.delimiter).filter(Boolean).map(dir=>path.join(dir,name));
 for(const file of candidates)try{fs.accessSync(file,fs.constants.X_OK);if(fs.statSync(file).isFile())return file}catch{}
 throw Error('Cannot find '+name+'. Install the official Codex CLI and ensure it is on PATH.');
}
function findBrowser(exists=fs.existsSync,home=os.homedir()){
 for(const app of ['Microsoft Edge.app','Google Chrome.app'])for(const dir of ['/Applications',path.join(home,'Applications')]){const file=path.join(dir,app);if(exists(file))return file}
 throw Error('Microsoft Edge or Google Chrome is required for an isolated workbench browser profile. Install one in /Applications or ~/Applications.');
}
function browserArgs(browser,url,profile){return ['-na',browser,'--args','--app='+url,'--user-data-dir='+profile,'--autoplay-policy=no-user-gesture-required','--no-first-run','--no-default-browser-check','--window-size=1500,950']}
function probeHealth(url){
 return new Promise((resolve,reject)=>{
  const request=http.get(url+'/health',res=>{
   let data='';res.setEncoding('utf8');res.on('data',chunk=>{data+=chunk;if(data.length>8192)request.destroy(Error('Port is occupied by another program.'))});
   res.on('error',reject);res.on('end',()=>{try{if(res.statusCode!==200||JSON.parse(data).app!=='EVA-UNIT02')throw Error();resolve(true)}catch{reject(Error('Port is occupied by another program.'))}});
  });
  request.setTimeout(1500,()=>request.destroy(Error('Port is occupied or did not respond.')));
  request.on('error',error=>error.code==='ECONNREFUSED'?resolve(false):reject(error));
 });
}
async function main(args=process.argv.slice(2)){
 if(process.platform!=='darwin')throw Error('This launcher is for macOS. On Windows, use Start-EVA.cmd.');
 if(Number(process.versions.node.split('.')[0])<20)throw Error('Node.js 20 or newer is required.');
 const {port,noBrowser}=parseArgs(args),url='http://127.0.0.1:'+port;
 const browser=noBrowser?null:findBrowser(),data=path.resolve(process.env.HACKCLAW_DATA_DIR||path.join(__dirname,'data'));
 let child,exited=false,exitCode=0,stopping=false,killTimer;
 const stop=()=>{if(!child||exited||stopping)return;stopping=true;child.kill('SIGTERM');killTimer=setTimeout(()=>{if(!exited)child.kill('SIGKILL')},5000);killTimer.unref()};
 try{
  let running=await probeHealth(url),done;
  if(!running){
   const codex=findExecutable(process.env.HACKCLAW_CODEX||'codex');
   try{require('node-pty');require.resolve('@xterm/xterm');require.resolve('@xterm/addon-fit')}catch{throw Error('Missing terminal dependencies. Run npm run setup in the project root first.')}
   fs.mkdirSync(data,{recursive:true});
   child=spawn(process.execPath,[path.join(__dirname,'server.cjs')],{cwd:__dirname,env:{...process.env,HACKCLAW_PORT:String(port),HACKCLAW_CODEX:codex,HACKCLAW_DATA_DIR:data},stdio:'inherit'});
   done=new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',(code,signal)=>{exited=true;exitCode=code??(stopping?0:1);clearTimeout(killTimer);resolve({code,signal})})});
   // Observe spawn errors immediately, even while readiness is being checked.
   done.catch(()=>{});process.on('SIGINT',stop);process.on('SIGTERM',stop);
   for(let attempt=0;attempt<30;attempt++){
    await new Promise(resolve=>setTimeout(resolve,300));
    if(exited||stopping)break;
    if(await probeHealth(url)){running=true;break}
   }
   if(!running){await Promise.race([done,Promise.resolve()]);throw Error('Workbench could not start. See the server error above.')}
  }
  console.log('Workbench ready at '+url);
  if(browser)await run('/usr/bin/open',browserArgs(browser,url+'/?boot=interactive&launch='+require('node:crypto').randomUUID(),path.join(data,'unit02-browser')));
  if(child){console.log('Keep this Terminal window open. Use the workbench Exit button or Control+C to stop the service.');await done;process.exitCode=exitCode}
 }finally{stop();process.removeListener('SIGINT',stop);process.removeListener('SIGTERM',stop)}
}
if(require.main===module)main().catch(error=>{console.error('EVA: '+error.message);process.exitCode=1});
module.exports={parseArgs,findExecutable,findBrowser,browserArgs,probeHealth,main};
