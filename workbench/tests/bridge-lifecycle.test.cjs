'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),{EventEmitter}=require('node:events'),{PassThrough}=require('node:stream');
const {CodexBridge}=require('../bridge.cjs');
test('npm shims resolve to the official entry without invoking a shell',()=>{
 const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
 const {launchCommand}=require('../bridge.cjs');
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'eva-codex-launch-'));
 try{
  const shim=path.join(root,'codex.ps1');
  assert.throws(()=>launchCommand(shim),/npm/);
  const entry=path.join(root,'node_modules','@openai','codex','bin','codex.js');
  fs.mkdirSync(path.dirname(entry),{recursive:true});fs.writeFileSync(entry,'');
  for(const extension of ['ps1','cmd','bat'])assert.deepEqual(launchCommand(path.join(root,'codex.'+extension)),{executable:process.execPath,args:[entry]});
  assert.deepEqual(launchCommand('codex.exe'),{executable:'codex.exe',args:[]});
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
function runtime(){const children=[];return {children,spawn(){
 const child=new EventEmitter();child.stdin=new PassThrough();child.stdout=new PassThrough();child.stderr=new PassThrough();child.killed=false;
 child.kill=()=>{child.killed=true;child.emit('exit',0)};
 child.stdin.on('data',chunk=>{const msg=JSON.parse(chunk.toString());if(msg.method==='initialize')queueMicrotask(()=>child.stdout.write(JSON.stringify({id:msg.id,result:{}})+'\n'))});
 children.push(child);return child;
}}}
test('stop settles pending calls; a delayed old-process exit cannot break a new connection',async()=>{
 const fake=runtime(),bridge=new CodexBridge('codex.exe',()=>fake.spawn());let disconnected=0;bridge.on('disconnected',()=>disconnected++);
 await bridge.start();const old=fake.children[0];const pending=bridge.request('slow',{},1000);const rejection=assert.rejects(pending,/connection stopped/);
 bridge.stop();await rejection;assert.equal(bridge.pending.size,0);assert.equal(bridge.child,null);
 await bridge.start();old.emit('exit',9);old.emit('error',Error('late error'));assert(bridge.connected);assert.equal(disconnected,0);bridge.stop();
});
test('a real current-process failure clears ownership and permits a fresh initialization',async()=>{
 const fake=runtime(),bridge=new CodexBridge('codex.exe',()=>fake.spawn());const errors=[];bridge.on('disconnected',e=>errors.push(e));
 await bridge.start();fake.children[0].emit('error',Error('transport gone'));assert.equal(bridge.child,null);assert.equal(bridge.connected,false);assert.deepEqual(errors,['transport gone']);
 await bridge.start();assert(bridge.connected);assert.equal(fake.children.length,2);bridge.stop();
});
