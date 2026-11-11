'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
test('macOS install makes only the selected node-pty spawn helpers executable',{skip:process.platform==='win32'},()=>{
 const script=path.resolve(__dirname,'../prepare-terminal.cjs');assert(fs.existsSync(script),'macOS terminal preparation must exist');const {prepareTerminal}=require(script),root=fs.mkdtempSync(path.join(os.tmpdir(),'eva-pty-install-'));
 try{const helper=path.join(root,'prebuilds/darwin-arm64/spawn-helper'),other=path.join(root,'prebuilds/darwin-x64/spawn-helper');for(const file of [helper,other]){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,'helper');fs.chmodSync(file,0o644)}
  prepareTerminal(root,'win32','arm64');assert.equal(fs.statSync(helper).mode&0o777,0o644);prepareTerminal(root,'darwin','arm64');assert.equal(fs.statSync(helper).mode&0o777,0o755);assert.equal(fs.statSync(other).mode&0o777,0o644);prepareTerminal(root,'darwin','arm64');
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
test('installed macOS PTY can spawn a real zsh process',{skip:process.platform!=='darwin',timeout:10000},async()=>{
 const pty=require('node-pty');let child;
 try{await new Promise((resolve,reject)=>{let output='';const timer=setTimeout(()=>reject(Error('PTY smoke test timed out')),5000);try{child=pty.spawn('/bin/zsh',['-f','-c','printf EVA_MACOS_PTY_OK'],{cwd:os.tmpdir(),env:process.env,name:'xterm-256color'});child.onData(data=>{output+=data});child.onExit(({exitCode})=>{clearTimeout(timer);try{assert.equal(exitCode,0);assert.match(output,/EVA_MACOS_PTY_OK/);resolve()}catch(error){reject(error)}})}catch(error){clearTimeout(timer);reject(error)}})}finally{child?.kill()}
});
