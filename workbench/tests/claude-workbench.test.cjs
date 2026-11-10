'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {ClaudeWorkbench,claudeEnv,permittedPath,normalizeClaudeModel}=require('../claude-workbench.cjs');
const model={id:'test-claude',isDefault:true,inputModalities:['text','image'],supportedReasoningEfforts:[]};
test('Claude model catalog preserves official version resolution without pinning a moving alias',()=>{
 const m=normalizeClaudeModel({value:'opus',resolvedModel:'claude-opus-5-5',displayName:'Opus',description:'Official description',supportedEffortLevels:['high']},1);
 assert.equal(m.id,'opus');assert.equal(m.resolvedModel,'claude-opus-5-5');assert.equal(m.name,'Opus 5.5（随官方更新）');assert.equal(m.description,'Official description');assert.equal(m.supportedReasoningEfforts[0].reasoningEffort,'high');
 assert.match(normalizeClaudeModel({...m,value:'opus',resolvedModel:'claude-opus-5-6',displayName:'Opus'},1).name,/5\.6/);
 const old=normalizeClaudeModel({value:'claude-opus-4-7',resolvedModel:'claude-opus-4-7',displayName:'Opus 4.7'},1);assert.equal(old.followsOfficial,false);assert.equal(old.name,'Opus 4.7');
});
test('Claude model name does not guess a version when SDK omits resolution',()=>{
 const m=normalizeClaudeModel({value:'opus',displayName:'Opus'},1);assert.equal(m.resolvedModel,'');assert.equal(m.name,'Opus（随官方更新）');
});
test('Claude response model uses received message metadata even when it differs from requested alias',()=>{
 const f=fixture(()=>{});try{
  const t={model:'opus',resolvedModel:'claude-opus-5-5',messages:[],tools:[]},active={streamed:new Set(),assistantStarted:false};
  f.app.event(t,{type:'system',subtype:'init',session_id:'session',model:'claude-opus-5-5'},active);assert.equal(t.lastResponseModel,undefined);
  f.app.event(t,{type:'stream_event',event:{type:'message_start',message:{id:'response',model:'claude-sonnet-5-5'}}},active);
  f.app.event(t,{type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'reply'}}},active);
  f.app.event(t,{type:'assistant',message:{id:'response',model:'claude-sonnet-5-5',content:[{type:'text',text:'reply'}]}},active);
  assert.equal(t.lastResponseModel,'claude-sonnet-5-5');assert.equal(t.messages[0].model,'claude-sonnet-5-5');assert.equal(t.messages.length,1);assert.equal(t.model,'opus');
 }finally{f.cleanup()}
});
function fixture(query){
 const state={threads:[]},approvals=new Map(),root=fs.mkdtempSync(path.join(os.tmpdir(),'eva-claude-'));
 const app=new ClaudeWorkbench({state,project:()=>({id:'p',path:root}),attachments:{resolve:async()=>[]},approvals,changed(){},notify(){},networkCheck:async()=>{},sdkLoader:async()=>({query})});
 app.status={connection:'connected',account:{signedIn:true},models:[model]};
 return {app,state,root,approvals,cleanup(){app.stop();fs.rmSync(root,{recursive:true,force:true})}};
}
async function finish(app){for(let i=0;i<100&&app.active.size;i++)await new Promise(r=>setTimeout(r,5));assert.equal(app.active.size,0)}
test('Claude streams text once, preserves session resume, and keeps providers separate',async()=>{
 const options=[];let turn=0;
 const f=fixture(({options:opt})=>{options.push(opt);const current=++turn;return Object.assign((async function*(){yield {type:'system',subtype:'init',session_id:'session-1'};yield {type:'stream_event',event:{type:'message_start',message:{id:'m'+current}}};yield {type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Hello'}}};yield {type:'assistant',message:{id:'m'+current,content:[{type:'text',text:'Hello'}]}};yield {type:'result',subtype:'success',is_error:false,session_id:'session-1',result:'Hello'}})(),{close(){}})});
 try{
  const t=await f.app.action('/api/thread',{provider:'claude',projectId:'p'});await f.app.send(t,{text:'one'});await finish(f.app);
  assert.equal(t.messages.filter(m=>m.role==='assistant').length,1);assert.equal(t.status,'completed');assert.equal(t.sessionId,'session-1');
  await f.app.send(t,{text:'two'});await finish(f.app);assert.equal(options[1].resume,'session-1');assert.equal(options[0].permissionMode,'default');assert.deepEqual(options[0].tools,['Read','Glob','Grep']);
  assert.equal(await f.app.action('/api/send',{threadId:'codex-thread',text:'unhandled'}),undefined);
  await f.app.action('/api/thread/rename',{threadId:t.id,title:'renamed'});await f.app.action('/api/thread/archive',{threadId:t.id,archived:true});assert.equal(t.title,'renamed');await assert.rejects(f.app.send(t,{text:'blocked'}),/归档/);
 }finally{f.cleanup()}
});
test('Claude approvals resolve once, refuse by default, and cancellation clears pending prompts',async()=>{
 const f=fixture(()=>{});try{
  const t={id:'t',projectId:'p'},signal=new AbortController();
  const pending=f.app.ask(t,'Bash',{command:'pwd'},{signal:signal.signal});const id=[...f.approvals.keys()][0];
  await f.app.action('/api/approval',{id,accept:false});assert.equal((await pending).behavior,'deny');assert.equal(f.approvals.size,0);
  await assert.rejects(f.app.action('/api/approval',{id,accept:true}),/失效/);
  const second=f.app.ask(t,'Write',{file_path:'a.txt'},{signal:signal.signal});signal.abort();assert.equal((await second).behavior,'deny');assert.equal(f.approvals.size,0);
  const third=f.app.ask(t,'AskUserQuestion',{questions:[{question:'Which?',options:[]}]},{signal:new AbortController().signal});const questionId=[...f.approvals.keys()][0];
  await f.app.action('/api/approval',{id:questionId,accept:true,answers:{0:'A'}});assert.deepEqual((await third).updatedInput.answers,{'Which?':'A'});
 }finally{f.cleanup()}
});
test('Claude tool boundary rejects symlink escape, credential paths and writes in read-only mode',async()=>{
 const f=fixture(()=>{}),outside=fs.mkdtempSync(path.join(os.tmpdir(),'eva-outside-'));try{
  fs.symlinkSync(outside,path.join(f.root,'escape'));assert.equal(await permittedPath(f.root,'escape/new.txt'),false);assert.equal(await permittedPath(f.root,'.env'),false);assert.equal(await permittedPath(f.root,'new/sub/file.txt'),true);
  const t={projectId:'p',mode:'read-only'};assert.match(await f.app.guard(t,'Bash',{command:'pwd'}),/只读/);assert.equal(await f.app.guard(t,'Read',{file_path:path.join(f.root,'README.md')}),null);
  assert.match(await f.app.guard({...t,mode:'workspace-write'},'Write',{file_path:path.join(outside,'oops')}),/项目/);
 }finally{f.cleanup();fs.rmSync(outside,{recursive:true,force:true})}
});
test('Claude connects directly and keeps the user\'s own proxy settings without nesting markers',()=>{
 const env=claudeEnv({HTTPS_PROXY:'http://proxy.example:8080',NO_PROXY:'localhost',CLAUDECODE:'parent',PATH:'/usr/bin'});
 assert.equal(env.HTTPS_PROXY,'http://proxy.example:8080');assert.equal(env.NO_PROXY,'localhost');assert(!('CLAUDECODE'in env));assert.equal(env.PATH,'/usr/bin');
 const direct=claudeEnv({PATH:'/usr/bin'});assert(!('HTTPS_PROXY'in direct)&&!('HTTP_PROXY'in direct)&&!('ALL_PROXY'in direct),'no proxy is forced');
});
test('Claude rejects simultaneous sends while attachment loading is pending',async()=>{
 const f=fixture(()=>{});let release;try{
  f.app.attachments.resolve=()=>new Promise(r=>{release=r});const t=await f.app.action('/api/thread',{provider:'claude',projectId:'p'});
  const first=f.app.send(t,{text:'one'});await assert.rejects(f.app.send(t,{text:'two'}),/尚未结束/);f.app.cancel(t.id);release([]);await assert.rejects(first,/停止/);assert.equal(f.app.active.size,0);
 }finally{f.cleanup()}
});
test('existing Claude conversations can change permissions while idle without reading the original session',async()=>{
 let options;
 const f=fixture(({options:opt})=>{options=opt;return Object.assign((async function*(){yield {type:'result',subtype:'success',result:'ok'}})(),{close(){}})});try{
  const t=await f.app.action('/api/thread',{provider:'claude',projectId:'p'});
  await f.app.action('/api/thread/mode',{threadId:t.id,mode:'workspace-write'});assert.equal(t.mode,'workspace-write');
  await assert.rejects(f.app.action('/api/thread/mode',{threadId:t.id,mode:'full-access'}),/确认/);
  await f.app.action('/api/thread/mode',{threadId:t.id,mode:'full-access',confirmFullAccess:true});assert.equal(await f.app.guard(t,'Write',{file_path:'/outside-project/example.txt'}),null);
  await f.app.send(t,{text:'one'});await finish(f.app);assert.equal(options.permissionMode,'bypassPermissions');assert.equal(options.allowDangerouslySkipPermissions,true);assert.equal(options.spawnClaudeCodeProcess,undefined,'the SDK spawns the CLI directly');assert(!('HTTPS_PROXY'in options.env)||options.env.HTTPS_PROXY===process.env.HTTPS_PROXY);assert.deepEqual(options.settings.permissions,{});
  await f.app.action('/api/thread/mode',{threadId:t.id,mode:'read-only'});assert.match(await f.app.guard(t,'Write',{file_path:'example.txt'}),/只读/);
  await f.app.send(t,{text:'two'});await finish(f.app);assert.equal(options.permissionMode,'default');assert.equal(options.allowDangerouslySkipPermissions,false);assert.deepEqual(options.tools,['Read','Glob','Grep']);
 }finally{f.cleanup()}
});
test('idle context inspection resumes without persistence or a generated user message',async()=>{
 let options,closed=false;
 const f=fixture(({options:opt})=>{options=opt;return {usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET:async()=>({rate_limits_available:true,rate_limits:{five_hour:{utilization:0}}}),getContextUsage:async opt=>{assert.equal(opt.detail,'summary');return {totalTokens:5000,rawMaxTokens:1000000,model:'test'}},close(){closed=true}}});
 try{
  const t={id:'idle',provider:'claude',projectId:'p',sessionId:'11111111-1111-4111-8111-111111111111',messages:[],tools:[],mode:'read-only'};f.state.threads.push(t);
  await f.app.refreshUsage(t.id);assert.equal(options.resume,t.sessionId);assert.equal(options.persistSession,false);assert.deepEqual(options.tools,[]);assert.equal(options.permissionMode,'default');assert.equal(t.messages.length,0);assert.equal(t.contextUsage.usedPercent,0.5);assert.equal(closed,true);assert.equal(f.app.status.usage.windows[0].usedPercent,0);
 }finally{f.cleanup()}
});
test('Claude completed content blocks do not overwrite earlier streamed text',()=>{
 const f=fixture(()=>{});try{
  const t={messages:[],tools:[]},active={streamed:new Set(),assistantStarted:false};
  f.app.event(t,{type:'stream_event',event:{type:'message_start',message:{id:'m'}}},active);
  for(const text of ['first',' second']){
   f.app.event(t,{type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text}}},active);
   f.app.event(t,{type:'assistant',message:{id:'m',content:[{type:'text',text}]}},active);
  }
  f.app.event(t,{type:'result',subtype:'success',result:' second'},active);
  assert.equal(t.messages.length,1);assert.equal(t.messages[0].text,'first second');
 }finally{f.cleanup()}
});
test('only explicitly attached file paths can be read outside the project, without granting writes',async()=>{
 const f=fixture(()=>{});try{
  const t={id:'t',projectId:'p',mode:'read-only'},file=path.join(os.tmpdir(),'explicit-upload.txt');f.app.active.set(t.id,{attachmentPaths:new Set([file])});
  assert.equal(await f.app.guard(t,'Read',{file_path:file}),null);assert.equal(f.app.approvedAttachment(t,'Read',{file_path:file}),true);assert.match(await f.app.guard(t,'Read',{file_path:file+'.other'}),/项目/);assert.match(await f.app.guard(t,'Write',{file_path:file}),/只读/);f.app.active.clear();
 }finally{f.cleanup()}
});
test('Claude file hooks show the executed file change in the shared Diff panel',async()=>{
 const f=fixture(()=>{});try{
  const file=path.join(f.root,'example.txt');fs.writeFileSync(file,'before\n');
  const e={tool_name:'Edit',tool_input:{file_path:file},tool_use_id:'edit-1'},active={},t={projectId:'p',tools:[]};
  await f.app.beforeFile(active,e);fs.writeFileSync(file,'after\n');await f.app.afterFile(t,active,e);
  assert.equal(t.tools[0].type,'fileChange');assert.equal(t.tools[0].changes[0].path,'example.txt');assert.match(t.tools[0].changes[0].diff,/-before\n/);assert.match(t.tools[0].changes[0].diff,/\+after\n/);
 }finally{f.cleanup()}
});
