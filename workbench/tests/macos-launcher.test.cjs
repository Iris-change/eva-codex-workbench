'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http'),vm=require('node:vm');
const root=path.resolve(__dirname,'../..'),launcher=path.join(root,'workbench/start-macos.cjs');
function load(){assert(fs.existsSync(launcher),'macOS launcher must exist');return require(launcher)}
test('macOS launch arguments validate ports and reject unknown options',()=>{
 const {parseArgs}=load();assert.deepEqual(parseArgs([]),{port:43137,noBrowser:false});assert.deepEqual(parseArgs(['--port','45123','--no-browser']),{port:45123,noBrowser:true});
 for(const args of [['--port','0'],['--port','65536'],['--port','43137x'],['--port'],['--unknown']])assert.throws(()=>parseArgs(args));
});
test('macOS browser launch uses an isolated Chromium app profile without a shell',()=>{
 const {findBrowser,browserArgs}=load(),home='/Users/test person';
 const chrome=path.join(home,'Applications','Google Chrome.app');assert.equal(findBrowser(file=>file===chrome,home),chrome);assert.throws(()=>findBrowser(()=>false,home),/Edge|Chrome/);
 const args=browserArgs(chrome,'http://127.0.0.1:43137/?boot=interactive','/tmp/EVA test/data/unit02-browser');
 assert.deepEqual(args.slice(0,4),['-na',chrome,'--args','--app=http://127.0.0.1:43137/?boot=interactive']);assert(args.includes('--user-data-dir=/tmp/EVA test/data/unit02-browser'));assert(args.includes('--autoplay-policy=no-user-gesture-required'));
});
test('launcher resolves executables from PATH including paths with spaces',()=>{
 const {findExecutable}=load(),dir=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'eva tools '));
 try{const file=path.join(dir,'codex');fs.writeFileSync(file,'#!/bin/sh\n');fs.chmodSync(file,0o755);assert.equal(findExecutable('codex',{PATH:dir}),file);assert.equal(findExecutable(file,{PATH:''}),file);assert.throws(()=>findExecutable('missing',{PATH:dir}),/missing/)}finally{fs.rmSync(dir,{recursive:true,force:true})}
});
test('launcher health check only reuses EVA and rejects occupied or unresponsive ports',async()=>{
 const {probeHealth}=load();let mode='eva';const server=http.createServer((req,res)=>{if(mode==='hang')return;if(mode==='other'){res.end('not EVA');return}res.setHeader('Content-Type','application/json');res.end(JSON.stringify({app:'EVA-UNIT02'}))});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const url='http://127.0.0.1:'+server.address().port;
 try{assert.equal(await probeHealth(url),true);mode='other';await assert.rejects(()=>probeHealth(url),/occupied/);mode='hang';await assert.rejects(()=>probeHealth(url),/occupied|respond/)}finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve))}
 assert.equal(await probeHealth(url),false);
});
test('macOS double-click entry points are executable and use location-independent quoted paths',()=>{
 for(const name of ['Start-EVA.command','Install-Dependencies.command']){const file=path.join(root,name);assert(fs.existsSync(file),name+' must exist');if(process.platform!=='win32')assert(fs.statSync(file).mode&0o111,name+' must be executable');const text=fs.readFileSync(file,'utf8');assert(text.startsWith('#!/bin/bash\n'));assert.match(text,/\$\(dirname "\$0"\)/);assert.match(text,/\/opt\/homebrew\/bin/)}
});
test('composer accepts Command or Control Enter but never sends during IME composition',()=>{
 const source=fs.readFileSync(path.join(root,'workbench/public/app.js'),'utf8');const handler=source.split(/\r?\n/).find(line=>line.startsWith("$('prompt').onkeydown="));assert(handler);const prompt={},composer={requestSubmit(){calls++}};let calls=0,prevented=0;
 vm.runInNewContext(handler,{$:id=>id==='prompt'?prompt:composer});
 const key=extra=>({key:'Enter',preventDefault(){prevented++},...extra});
 prompt.onkeydown(key({metaKey:true}));assert.equal(calls,1);prompt.onkeydown(key({ctrlKey:true}));assert.equal(calls,2);prompt.onkeydown(key({}));assert.equal(calls,2);
 prompt.onkeydown(key({metaKey:true,isComposing:true}));prompt.onkeydown(key({ctrlKey:true,keyCode:229}));assert.equal(calls,2);assert.equal(prevented,2);
});
test('terminal UI does not advertise a Windows-only shell',()=>{const source=fs.readFileSync(path.join(root,'workbench/public/dev-tools.js'),'utf8');assert(!source.includes('新建 PowerShell'));assert(source.includes('新建终端'))});
