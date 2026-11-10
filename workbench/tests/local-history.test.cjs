'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {LocalHistory,storedState,codexItems,claudeItems,readDesktopMetadata}=require('../local-history.cjs');
const ids={desktop:'11111111-1111-4111-8111-111111111111',cli:'22222222-2222-4222-8222-222222222222',own:'33333333-3333-4333-8333-333333333333'};
const model={id:'test-model',isDefault:true,inputModalities:['text','image'],supportedReasoningEfforts:[]};
async function fixture(){
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'eva-history-')),project=path.join(root,'project');await fs.mkdir(project);
 const metadata=path.join(root,'Library/Application Support/Claude/claude-code-sessions/org/environment');await fs.mkdir(metadata,{recursive:true});
 await fs.writeFile(path.join(metadata,'local_example.json'),JSON.stringify({cliSessionId:ids.desktop,title:'Desktop title',cwd:project,createdAt:1000000000001,lastActivityAt:1000000000002}));
 const state={projects:[],threads:[{id:'own-claude',provider:'claude',sessionId:ids.own,messages:[{text:'own conversation'}],tools:[]}]},calls=[];
 const bridge={request:async(method,input)=>{calls.push({method,input});
  if(method==='thread/list')return {data:input.archived?[]:[{id:'codex-original',name:'Codex title',cwd:project,model:'test-model',createdAt:1700000000,updatedAt:1700000100}],nextCursor:null};
  if(method==='thread/turns/list')return input.cursor?{data:[{items:[{type:'userMessage',id:'old',content:[{type:'text',text:'earlier'}]}]}],nextCursor:null}:{data:[{items:[{type:'userMessage',id:'u',content:[{type:'text',text:'hello'}]},{type:'agentMessage',id:'a',text:'world'}]}],nextCursor:'older'};
  if(method==='thread/fork')return {thread:{id:'codex-fork'}};
  throw Error('Unexpected method '+method)
 }};
 const sdk={listSessions:async()=>[{sessionId:ids.desktop,summary:'CLI generated title',cwd:project,lastModified:1000000000010},{sessionId:ids.cli,summary:'CLI title',cwd:project,lastModified:1000000000011},{sessionId:ids.own,summary:'own',cwd:project,lastModified:1000000000012}],getSessionMessages:async()=>[{type:'user',uuid:'cu',message:{content:'question'}},{type:'assistant',uuid:'ca',message:{content:[{type:'text',text:'answer'}]}}],forkSession:async(id,options)=>{calls.push({method:'claude-fork',id,options});return {sessionId:'44444444-4444-4444-8444-444444444444'}}};
 const history=new LocalHistory({state,bridge,changed(){},models:()=>[model],claude:{status:{connection:'connected',account:{signedIn:true},models:[model]}},loaded:new Set(),home:root,sdkLoader:async()=>sdk});
 return {root,project,state,calls,sdk,history,async cleanup(){await fs.rm(root,{recursive:true,force:true})}};
}
test('local history sync joins Desktop titles, excludes owned sessions and deduplicates refreshes',async()=>{
 const f=await fixture();try{
  await f.history.sync();await f.history.sync();const imported=f.state.threads.filter(t=>t.localHistory);
  assert.equal(imported.length,3);assert.equal(f.state.projects.length,1);
  assert.equal(imported.find(t=>t.localHistory.id===ids.desktop).title,'Desktop title');assert.equal(imported.find(t=>t.localHistory.id===ids.desktop).localHistory.kind,'claude-desktop');
  assert(imported.every(t=>t.messages.length===0));assert(f.calls.filter(c=>c.method==='thread/list').every(c=>c.input.useStateDbOnly));
 }finally{await f.cleanup()}
});
test('Codex history is loaded without resume and older pages precede current messages',async()=>{
 const f=await fixture();try{
  await f.history.sync();const id='history-codex-codex-original';await f.history.read(id);const t=f.state.threads.find(t=>t.id===id);assert.deepEqual(t.messages.map(m=>m.text),['hello','world']);assert.equal(t.historyCursor,'older');
  await f.history.read(id,{older:true});assert.deepEqual(t.messages.map(m=>m.text),['earlier','hello','world']);assert.equal(t.historyCursor,null);assert(!f.calls.some(c=>c.method==='thread/resume'));
  const disk=storedState(f.state);assert.equal(disk.threads.find(t=>t.id===id).messages.length,0);assert.equal(disk.threads[0].messages[0].text,'own conversation');assert.equal(t.messages.length,3);
 }finally{await f.cleanup()}
});
test('continuing imports uses new forks and blocks original send/rename/archive mutations',async()=>{
 const f=await fixture();try{
  await f.history.sync();const source='history-codex-codex-original';await assert.rejects(f.history.action('/api/send',{threadId:source,text:'mutate'}),/只读/);
  const hidden=await f.history.action('/api/thread/archive',{threadId:source,archived:true});assert.equal(hidden.thread.archived,true);assert.equal(hidden.thread.archivedLocally,true);
  await f.history.action('/api/thread/archive',{threadId:source,archived:false});assert.equal(hidden.thread.archived,false);
  await assert.rejects(f.history.action('/api/thread/rename',{threadId:source,title:'changed'}),/只读/);
  const fork=await f.history.continue(source,{mode:'read-only'});assert.equal(fork.id,'codex-fork');assert.equal(fork.forkedFrom.id,'codex-original');assert(!fork.localHistory);assert.equal(fork.messages[0].text,'hello');
  const cf=await f.history.continue('history-claude-'+ids.desktop,{mode:'workspace-write'});assert.equal(cf.sessionId,'44444444-4444-4444-8444-444444444444');assert.equal(cf.mode,'workspace-write');assert.equal(f.state.threads.find(t=>t.id===source).title,'Codex title');
  assert(!f.calls.some(c=>['thread/archive','thread/name/set','turn/start'].includes(c.method)));
 }finally{await f.cleanup()}
});
test('missing project folders keep history readable while continuation stays unavailable',async()=>{
 const f=await fixture();try{
  await f.history.upsert({provider:'codex',id:'missing',title:'Moved',cwd:path.join(f.root,'not-here'),updatedAt:1,kind:'codex'});
  const t=f.state.threads.find(t=>t.localHistory?.id==='missing');assert.equal(t.localHistory.canContinue,false);await f.history.read(t.id);assert.equal(t.messages.length,2);await assert.rejects(f.history.continue(t.id),/目录已移动/);
 }finally{await f.cleanup()}
});
test('history conversion excludes tool-result payloads from visible user messages',()=>{
 const c=claudeItems([{type:'assistant',uuid:'a',message:{model:'claude-opus-4-7',content:[{type:'text',text:'result'},{type:'tool_use',id:'tool',name:'Read',input:{file_path:'example'}}]}},{type:'user',uuid:'b',message:{content:[{type:'tool_result',tool_use_id:'tool',content:'output'}]}}]);
 assert.equal(c.messages.length,1);assert.equal(c.messages[0].model,'claude-opus-4-7');assert.equal(c.tools[0].output,'output');
 const d=codexItems([{items:[{type:'userMessage',id:'u',content:[{type:'text',text:'hello'},{type:'image'}]},{type:'agentMessage',id:'a',text:'response'}]}]);assert.equal(d.messages[0].text,'hello\n[历史图片]');
});
test('malformed and unrelated desktop JSON is ignored without rewriting it',async()=>{
 const f=await fixture();try{
  const base=path.join(f.root,'Library/Application Support/Claude/claude-code-sessions');const file=path.join(base,'local_invalid.json');await fs.writeFile(file,'{broken');await fs.writeFile(path.join(base,'scheduled-tasks.json'),'{}');
  assert.equal((await readDesktopMetadata(base)).length,1);assert.equal(await fs.readFile(file,'utf8'),'{broken');
 }finally{await f.cleanup()}
});
test('history viewing keeps only three recent transcripts cached without evicting EVA messages',async()=>{
 const f=await fixture();try{
  for(let i=0;i<4;i++){await f.history.upsert({provider:'codex',id:'cache-'+i,title:'Cache',cwd:f.project,updatedAt:1,kind:'codex'});await f.history.read('history-codex-cache-'+i)}
  const first=f.state.threads.find(t=>t.localHistory?.id==='cache-0');assert.equal(first.historyLoaded,false);assert.equal(first.messages.length,0);
  assert.equal(f.state.threads.filter(t=>t.localHistory&&t.historyLoaded).length,3);assert.equal(f.state.threads[0].messages[0].text,'own conversation');
  await f.history.read(first.id);assert.equal(first.historyLoaded,true);assert.equal(first.messages[0].text,'hello');
 }finally{await f.cleanup()}
});
test('history mirrors can be archived locally without touching the official record and reappear after new official activity',async()=>{
 const state={projects:[],threads:[]},calls=[],history=new LocalHistory({state,bridge:{request:async(...a)=>{calls.push(a);return {data:[]}}},changed(){},models:()=>[],claude:{status:{}},loaded:new Set(),home:require('node:os').tmpdir(),sdkLoader:async()=>({listSessions:async()=>[]})});
 history.project=async()=>({project:{id:'p'},exists:true});
 await history.upsert({provider:'codex',id:'x',title:'测试镜像',cwd:'/tmp',updatedAt:1,archived:false,kind:'codex'});const t=state.threads[0];
 assert.deepEqual(await history.action('/api/thread/archive',{threadId:t.id,archived:true}),{thread:t});assert.equal(t.archived,true);assert.equal(calls.length,0);
 await history.upsert({provider:'codex',id:'x',title:'测试镜像',cwd:'/tmp',updatedAt:1,archived:false,kind:'codex'});assert.equal(t.archived,true,'local archive survives sync');
 await history.action('/api/thread/archive',{threadId:t.id,archived:false});assert.equal(t.archived,false);
 await history.upsert({provider:'codex',id:'x',title:'测试镜像',cwd:'/tmp',updatedAt:2,archived:true,kind:'codex'});await assert.rejects(history.action('/api/thread/archive',{threadId:t.id,archived:false}),/官方应用/);
 await assert.rejects(history.action('/api/send',{threadId:t.id}),/只读/);
 t.continuedIn={threadId:'y',provider:'claude',at:1,sourceUpdatedAt:2};await history.upsert({provider:'codex',id:'x',title:'测试镜像',cwd:'/tmp',updatedAt:2,archived:false,kind:'codex'});assert(t.continuedIn,'unchanged record stays merged');
 await history.upsert({provider:'codex',id:'x',title:'测试镜像',cwd:'/tmp',updatedAt:3,archived:false,kind:'codex'});assert.equal(t.continuedIn,undefined,'diverged record reappears');
});
