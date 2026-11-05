'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),{EventEmitter}=require('node:events');
const localRequire=require('node:module').createRequire(path.join(__dirname,'..','server.cjs'));
function serverRuntime({platform='darwin',run=async()=>({stdout:''}),env={}}={}){
 const executables=[],platformAPI=localRequire('./platform.cjs'),fakeFS={...fs,mkdirSync(){},readFileSync(){throw Object.assign(Error('no history'),{code:'ENOENT'})},promises:{realpath:async file=>file,stat:async()=>({isDirectory:()=>true})}};
 const context={__dirname:path.join(__dirname,'..'),module:{exports:{}},process:{platform,env,on(){}},Buffer,URL,console,clearTimeout(){},setTimeout(){return {unref(){}}},require(id){
  if(id==='node:fs')return fakeFS;
  if(id==='node:util')return {promisify:()=>run};
  if(id==='node:http')return {createServer(){return {on(){},listen(){}}}};
  if(id==='node:child_process')return {execFile(file,args,options,callback){run(file,args,options).then(result=>callback(null,result.stdout,''),callback)}};
  if(id==='./bridge.cjs')return {CodexBridge:class extends EventEmitter{constructor(executable){super();executables.push(executable)}}};
  if(id==='./plugins.cjs')return {PluginManager:class{constructor(executable){executables.push(executable)}}};
  if(id==='./platform.cjs')return {...platformAPI,defaultCodex:()=>platformAPI.defaultCodex(platform),sameProjectPath:(a,b)=>platformAPI.sameProjectPath(a,b,platform),pickFolder:()=>platformAPI.pickFolder({platform,run})};
  return localRequire(id);
 }};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'..','server.cjs'),'utf8')+'\nmodule.exports.action=action;',context);
 return {action:context.module.exports.action,executables};
}
const {CodexBridge}=require('../bridge.cjs'),{PluginManager}=require('../plugins.cjs'),{TerminalManager}=require('../terminal.cjs');
function terminal(options={}){
 const calls=[],manager=new TerminalManager({...options,spawn(...args){calls.push(args);return {onData(){},onExit(){},kill(){}}}});
 return {manager,calls,create(){return manager.create({id:'project',path:process.cwd()})}};
}
test('server uses platform Codex defaults and honors HACKCLAW_CODEX for bridge and plugins',()=>{
 for(const [platform,expected] of [['darwin','codex'],['win32','codex.exe']]){
  assert.deepEqual(serverRuntime({platform}).executables,[expected,expected]);
  assert.deepEqual(serverRuntime({platform,env:{HACKCLAW_CODEX:'/custom/codex'}}).executables,['/custom/codex','/custom/codex']);
 }
});
test('macOS folder route invokes osascript directly and preserves spaces and shell metacharacters',async()=>{
 const calls=[],chosen='/Users/test/My "project"; $(touch nope)',server=serverRuntime({run:async(...args)=>{calls.push(args);return {stdout:chosen+'\n'}}});
 assert.equal((await server.action('/api/pick-folder',{})).path,chosen);
 assert.equal(calls[0][0],'osascript');assert.equal(calls[0][1][0],'-e');assert.equal(calls[0][2].shell,undefined);
 assert.match(calls[0][1][1],/choose folder/);assert.match(calls[0][1][1],/POSIX path/);
});
test('macOS folder cancellation returns an empty path without hiding other errors',async()=>{
 const calls=[],cancelled=serverRuntime({run:async(file,args)=>{calls.push([file,args]);return {stdout:''}}});
 assert.equal((await cancelled.action('/api/pick-folder',{})).path,'');assert.equal(calls[0][0],'osascript');
 assert.match(calls[0][1][1],/on error[\s\S]*number -128/);
 const failure=Error('automation denied'),broken=serverRuntime({run:async()=>{throw failure}});
 await assert.rejects(broken.action('/api/pick-folder',{}),error=>error===failure);
});
test('Windows folder picker keeps the encoded PowerShell dialog',async()=>{
 const calls=[],server=serverRuntime({platform:'win32',run:async(...args)=>{calls.push(args);return {stdout:'C:\\Project'}}});
 assert.equal((await server.action('/api/pick-folder',{})).path,'C:\\Project');assert.equal(calls[0][0],'powershell.exe');assert.deepEqual(Array.from(calls[0][1]).slice(0,3),['-NoProfile','-STA','-EncodedCommand']);
 assert.match(Buffer.from(calls[0][1][3],'base64').toString('utf16le'),/FolderBrowserDialog/);
});
test('POSIX project registration keeps case-distinct directories separate and deduplicates exact paths',async()=>{
 for(const platform of ['darwin','linux']){
  const server=serverRuntime({platform}),upper=path.resolve('CaseProject'),lower=path.resolve('caseproject');
  const a=await server.action('/api/project',{path:upper}),b=await server.action('/api/project',{path:lower});
  assert.notEqual(a.id,b.id);assert.equal((await server.action('/api/project',{path:upper})).id,a.id);
 }
});
test('Windows project registration still deduplicates case variants',async()=>{
 const server=serverRuntime({platform:'win32'}),a=await server.action('/api/project',{path:path.resolve('CaseProject')}),b=await server.action('/api/project',{path:path.resolve('caseproject')});assert.equal(a.id,b.id);
});
test('bridge and plugins default to the host Codex executable and preserve explicit overrides',()=>{
 const expected=process.platform==='win32'?'codex.exe':'codex';
 assert.equal(new CodexBridge().executable,expected);assert.equal(new PluginManager().executable,expected);
 assert.equal(new CodexBridge('/custom/codex').executable,'/custom/codex');assert.equal(new PluginManager('/custom/codex').executable,'/custom/codex');
});
test('macOS terminals use the user zsh with login arguments and a truthful title',()=>{
 const env={SHELL:'/opt/homebrew/bin/zsh',PATH:'/bin',KEEP:'yes',HACKCLAW_CODEX:'private',HACKCLAW_DATA_DIR:'private',EVA_LAUNCH_READY:'private'},t=terminal({platform:'darwin',env});
 assert.equal(t.create().title,'zsh 1');const [shell,args,options]=t.calls[0];
 assert.equal(shell,env.SHELL);assert.deepEqual(args,['-l']);assert.equal(options.cwd,process.cwd());assert.equal(options.env.KEEP,'yes');
 for(const key of ['HACKCLAW_CODEX','HACKCLAW_DATA_DIR','EVA_LAUNCH_READY'])assert.equal(options.env[key],undefined);
 assert.equal(env.HACKCLAW_CODEX,'private');t.manager.stop();
});
test('macOS falls back to zsh without a configured SHELL',()=>{
 const t=terminal({platform:'darwin',env:{}});assert.equal(t.create().title,'zsh 1');assert.equal(t.calls[0][0],'/bin/zsh');assert.deepEqual(t.calls[0][1],['-l']);t.manager.stop();
});
test('macOS Bash and fish receive only their own supported arguments',()=>{
 for(const [shell,args,title] of [['/bin/bash',['--noprofile','--norc'],'bash 1'],['/opt/homebrew/bin/fish',['-l'],'fish 1']]){
  const t=terminal({platform:'darwin',env:{SHELL:shell}});assert.equal(t.create().title,title);assert.equal(t.calls[0][0],shell);assert.deepEqual(t.calls[0][1],args);t.manager.stop();
 }
});
test('Windows prefers pwsh and keeps PowerShell arguments and title',()=>{
 const t=terminal({platform:'win32',env:{PATH:'C:\\Tools;C:\\Windows',PSModulePath:'keep;C:\\Program Files\\PowerShell\\7\\Modules'},existsSync:file=>file==='C:\\Tools\\pwsh.exe'});
 assert.equal(t.create().title,'PowerShell 1');assert.equal(t.calls[0][0],'C:\\Tools\\pwsh.exe');assert.deepEqual(t.calls[0][1],['-NoLogo','-NoProfile']);assert.equal(t.calls[0][2].env.PSModulePath,'keep;C:\\Program Files\\PowerShell\\7\\Modules');t.manager.stop();
});
test('Windows shell discovery handles case-insensitive environment keys without changing their spelling',()=>{
 const env={Path:'C:\\Tools;D:\\Windows',SYSTEMROOT:'D:\\Windows',psmodulepath:'keep;C:\\Program Files\\PowerShell\\7\\Modules'};
 const modern=terminal({platform:'win32',env,existsSync:file=>file==='C:\\Tools\\pwsh.exe'});modern.create();assert.equal(modern.calls[0][0],'C:\\Tools\\pwsh.exe');assert.equal(modern.calls[0][2].env.Path,env.Path);modern.manager.stop();
 const fallback=terminal({platform:'win32',env,existsSync:()=>false});fallback.create();assert.equal(fallback.calls[0][0],'D:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe');assert.equal(fallback.calls[0][2].env.psmodulepath,'keep');assert.equal(env.psmodulepath,'keep;C:\\Program Files\\PowerShell\\7\\Modules');fallback.manager.stop();
});
test('Windows PowerShell fallback still strips incompatible PowerShell 7 modules',()=>{
 const t=terminal({platform:'win32',env:{SystemRoot:'C:\\Windows',PSModulePath:'keep;C:\\Program Files\\PowerShell\\7\\Modules'},existsSync:()=>false});
 assert.equal(t.create().title,'PowerShell 1');assert.equal(t.calls[0][0],'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe');assert.deepEqual(t.calls[0][1],['-NoLogo','-NoProfile']);assert.equal(t.calls[0][2].env.PSModulePath,'keep');t.manager.stop();
});
