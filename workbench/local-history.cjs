'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const {turnOptions}=require('./model-options.cjs');
const SOURCE_KINDS=['cli','vscode','appServer','unknown'];
const uuid=value=>typeof value==='string'&&/^[a-f0-9-]{36}$/i.test(value);
const {permissionMode}=require('./permission-modes.cjs');
const timestamp=value=>typeof value==='number'?(value<1e12?value*1000:value):(Date.parse(value)||0);
const cleanTitle=value=>String(value||'本机会话').replace(/[\x00-\x1f]/g,' ').trim().slice(0,200);
const previewText=value=>String(value||'').slice(0,100000);
function textContent(content){
 if(typeof content==='string')return previewText(content);
 if(!Array.isArray(content))return '';
 return content.map(block=>block.type==='text'||block.type==='inputText'||block.type==='outputText'?block.text||'':block.type==='image'||block.type==='localImage'||block.type==='inputImage'?'[历史图片]':'').filter(Boolean).join('\n').slice(0,100000);
}
function storedState(state){
 return {...state,threads:state.threads.map(t=>{
  if(!t.localHistory)return t;
  const {messages,tools,historyLoaded,historyCursor,historyError,...metadata}=t;
  return {...metadata,messages:[],tools:[]};
 })};
}
async function desktopFiles(root,depth=0){
 if(depth>3)return [];
 let entries;try{entries=await fs.readdir(root,{withFileTypes:true})}catch(e){if(e.code==='ENOENT')return [];throw e}
 const files=[];
 for(const entry of entries){
  if(entry.isSymbolicLink())continue;
  const file=path.join(root,entry.name);
  if(entry.isDirectory())files.push(...await desktopFiles(file,depth+1));
  else if(entry.isFile()&&/^local_.*\.json$/.test(entry.name))files.push(file);
 }
 return files;
}
async function readDesktopMetadata(root){
 const rows=[];
 for(const file of await desktopFiles(root)){
  try{
   if((await fs.stat(file)).size>512*1024)continue;
   const d=JSON.parse(await fs.readFile(file,'utf8'));
   if(!uuid(d.cliSessionId))continue;
   rows.push({sessionId:d.cliSessionId,title:cleanTitle(d.title),cwd:d.cwd||d.originCwd,archived:!!d.isArchived,createdAt:timestamp(d.createdAt),updatedAt:timestamp(d.lastActivityAt||d.lastFocusedAt||d.createdAt),model:d.model||'',kind:'claude-desktop'});
  }catch(e){if(!['ENOENT','EACCES'].includes(e.code)&&!(e instanceof SyntaxError))throw e}
 }
 return rows;
}
function codexItems(turns){
 const messages=[],tools=[];
 for(const turn of turns)for(const item of turn.items||[]){
  if(item.type==='userMessage'){
   const text=textContent(item.content);if(text)messages.push({id:item.id,role:'user',text});
  }else if(item.type==='agentMessage'){
   if(item.text)messages.push({id:item.id,role:'assistant',text:previewText(item.text)});
  }else if(['commandExecution','fileChange','mcpToolCall'].includes(item.type)){
   const tool={...item};if(tool.aggregatedOutput)tool.aggregatedOutput=tool.aggregatedOutput.slice(0,20000);tools.push(tool);
  }
 }
 return {messages,tools:tools.slice(-100)};
}
function claudeItems(frames){
 const messages=[],tools=[],byTool=new Map();
 for(const frame of frames){
  const message=frame.message||{};
  if(frame.type==='user'||frame.type==='assistant'){
   const text=textContent(message.content);if(text)messages.push({id:frame.uuid,role:frame.type,text,...(frame.type==='assistant'&&typeof message.model==='string'?{model:message.model}:{})});
  }
  if(Array.isArray(message.content))for(const block of message.content){
   if(block.type==='tool_use'){
    const tool={id:block.id,type:'claudeTool',name:block.name,input:block.input,status:'completed'};byTool.set(block.id,tool);tools.push(tool);
   }else if(block.type==='tool_result'){
    const tool=byTool.get(block.tool_use_id);if(tool){tool.output=previewText(typeof block.content==='string'?block.content:JSON.stringify(block.content));tool.status=block.is_error?'failed':'completed'}
   }
  }
 }
 return {messages,tools:tools.slice(-100)};
}
class LocalHistory{
 constructor({state,bridge,changed,models,claude,loaded,home=os.homedir(),sdkLoader=()=>import('@anthropic-ai/claude-agent-sdk')}){
  Object.assign(this,{state,bridge,changed,models,claude,loaded,home,sdkLoader});this.summary={loading:false,error:null,counts:{codex:0,claudeDesktop:0,claudeCli:0},updatedAt:null};this.reading=new Map();this.cacheOrder=[];
  for(const t of state.threads)if(t.localHistory){t.messages=[];t.tools=[];t.historyLoaded=false;t.status='idle';t.activeTurn=null}
 }
 async project(cwd){
  if(typeof cwd!=='string'||!path.isAbsolute(cwd))return null;
  let real=path.resolve(cwd),exists=false;
  try{real=await fs.realpath(real);exists=(await fs.stat(real)).isDirectory()}catch{}
  let project=this.state.projects.find(p=>p.path===real);
  if(!project){project={id:crypto.randomUUID(),name:path.basename(real)||real,path:real,fromLocalHistory:true,missing:!exists};this.state.projects.push(project)}
  return {project,exists};
 }
 async upsert(source){
  const provider=source.provider,id=source.id;
  const own=this.state.threads.find(t=>!t.localHistory&&((provider==='codex'&&t.provider!=='claude'&&t.id===id)||(provider==='claude'&&t.provider==='claude'&&t.sessionId===id)));
  if(own)return;
  const location=await this.project(source.cwd);if(!location)return;
  const key='history-'+provider+'-'+id;let t=this.state.threads.find(t=>t.id===key);
  if(!t){t={id:key,provider,projectId:location.project.id,title:source.title,mode:'read-only',model:source.model||'',effort:'',messages:[],tools:[],status:'idle',activeTurn:null,error:null,diff:'',createdAt:source.createdAt||Date.now()};this.state.threads.push(t)}
  if(t.localHistory?.updatedAt!==source.updatedAt){t.messages=[];t.tools=[];t.historyLoaded=false;t.historyCursor=null;delete t.contextUsage}
  // New activity in the official app after an in-place switch means the record diverged: show it again.
  if(t.continuedIn&&'sourceUpdatedAt' in t.continuedIn&&t.continuedIn.sourceUpdatedAt!==source.updatedAt)delete t.continuedIn;
  Object.assign(t,{title:source.title,projectId:location.project.id,officialArchived:!!source.archived,archived:!!source.archived||!!t.archivedLocally,updatedAt:source.updatedAt,localHistory:{provider,id,kind:source.kind,updatedAt:source.updatedAt,cwd:source.cwd,canContinue:location.exists},historyError:null});
 }
 async sync(){
  if(this.syncing)return this.syncing;
  this.summary.loading=true;this.summary.error=null;this.changed();
  this.syncing=(async()=>{
   const errors=[],counts={codex:0,claudeDesktop:0,claudeCli:0};
   try{
    let cursor;
    do{
     const page=await this.bridge.request('thread/list',{limit:100,sortKey:'updated_at',sourceKinds:SOURCE_KINDS,modelProviders:[],useStateDbOnly:true,...(cursor?{cursor}:{})});
     for(const t of page.data||[]){await this.upsert({provider:'codex',id:t.id,title:cleanTitle(t.name||t.preview),cwd:t.cwd,createdAt:timestamp(t.createdAt),updatedAt:timestamp(t.updatedAt),model:t.model,archived:false,kind:'codex'});counts.codex++}
     cursor=page.nextCursor;
    }while(cursor);
    let archiveCursor;
    do{
     const page=await this.bridge.request('thread/list',{limit:100,sortKey:'updated_at',sourceKinds:SOURCE_KINDS,modelProviders:[],useStateDbOnly:true,archived:true,...(archiveCursor?{cursor:archiveCursor}:{})});
     for(const t of page.data||[]){await this.upsert({provider:'codex',id:t.id,title:cleanTitle(t.name||t.preview),cwd:t.cwd,createdAt:timestamp(t.createdAt),updatedAt:timestamp(t.updatedAt),model:t.model,archived:true,kind:'codex'});counts.codex++}
     archiveCursor=page.nextCursor;
    }while(archiveCursor);
   }catch(e){errors.push('Codex: '+e.message)}
   try{
    const sdk=await this.sdkLoader(),desktop=await readDesktopMetadata(path.join(this.home,'Library/Application Support/Claude/claude-code-sessions'));
    const desktopById=new Map(desktop.map(t=>[t.sessionId,t]));let offset=0;
    while(true){
     const rows=await sdk.listSessions({limit:100,offset,includeProgrammatic:true});
     for(const row of rows){
      if(!uuid(row.sessionId))continue;
      const native=desktopById.get(row.sessionId);
      const source={provider:'claude',id:row.sessionId,title:cleanTitle(native?.title||row.customTitle||row.summary||row.firstPrompt),cwd:native?.cwd||row.cwd,model:native?.model||'',archived:native?.archived||false,createdAt:native?.createdAt||row.createdAt||row.lastModified,updatedAt:Math.max(native?.updatedAt||0,row.lastModified||0),kind:native?'claude-desktop':'claude-cli'};
      await this.upsert(source);native?counts.claudeDesktop++:counts.claudeCli++;desktopById.delete(row.sessionId);
     }
     if(rows.length<100)break;offset+=rows.length;
    }
    // Desktop titles can survive after a transcript is moved. Keep those entries visible.
    for(const row of desktopById.values()){await this.upsert({...row,provider:'claude',id:row.sessionId,kind:'claude-desktop'});counts.claudeDesktop++}
   }catch(e){errors.push('Claude: '+e.message)}
   this.summary={loading:false,error:errors.join('；')||null,counts,updatedAt:Date.now()};this.changed();return this.summary;
  })().finally(()=>{this.syncing=null});return this.syncing;
 }
 thread(id){const t=this.state.threads.find(t=>t.id===id);if(!t?.localHistory)throw Error('不是本机历史会话');return t}
 async read(id,{older=false}={}){
  if(this.reading.has(id))return this.reading.get(id);
  const t=this.thread(id);
  const job=(async()=>{
   try{
    t.historyError=null;
    const source=t.localHistory;let page;
    if(source.provider==='codex'){
     const result=await this.bridge.request('thread/turns/list',{threadId:source.id,limit:12,sortDirection:'desc',itemsView:'summary',...(older&&t.historyCursor?{cursor:t.historyCursor}:{})});
     page=codexItems((result.data||[]).slice().reverse());t.historyCursor=result.nextCursor||null;
    }else{
     const sdk=await this.sdkLoader();const frames=await sdk.getSessionMessages(source.id,{dir:source.cwd});
     const end=older&&Number.isInteger(t.historyCursor)?t.historyCursor:frames.length,start=Math.max(0,end-100);
     page=claudeItems(frames.slice(start,end));t.historyCursor=start>0?start:null;
     if(!frames.length)t.historyError='尚未找到该会话的本机转录内容';
    }
    const old=older?t.messages:[],seen=new Set(old.map(m=>m.id));t.messages=[...page.messages.filter(m=>!seen.has(m.id)),...old];
    const oldTools=older?t.tools:[],toolIds=new Set(oldTools.map(x=>x.id));t.tools=[...page.tools.filter(x=>!toolIds.has(x.id)),...oldTools].slice(-200);t.historyLoaded=true;
    this.cacheOrder=this.cacheOrder.filter(key=>key!==id);this.cacheOrder.push(id);
    while(this.cacheOrder.length>3){const oldest=this.cacheOrder.shift(),old=this.state.threads.find(row=>row.id===oldest);if(old?.localHistory){old.messages=[];old.tools=[];old.historyLoaded=false;old.historyCursor=null}}
    t.historyError=t.historyError||null;this.changed();return {thread:t};
   }catch(e){t.historyError='历史读取失败：'+e.message;this.changed();throw e}
  })();this.reading.set(id,job);try{return await job}finally{this.reading.delete(id)}
 }
 async continue(id,input={}){
  const source=this.thread(id);if(!source.localHistory.canContinue)throw Error('原项目目录已移动，当前只能查看历史');
  const p=this.state.projects.find(p=>p.id===source.projectId);if(!p||(await fs.stat(p.path)).isDirectory()===false)throw Error('原项目目录不存在');
  if(!source.historyLoaded)await this.read(id);
  const mode=permissionMode(source.provider,input);let idNew,sessionId,model;
  if(source.provider==='codex'){
   const choice=turnOptions(this.models(),input.model||'',input.effort||'');model=choice.model.id;
   const result=await this.bridge.request('thread/fork',{threadId:source.localHistory.id,cwd:p.path,excludeTurns:true,sandbox:mode,approvalPolicy:'on-request',approvalsReviewer:'user',model});idNew=result.thread.id;
  }else{
   if(!this.claude.status.account.signedIn||this.claude.status.connection!=='connected')throw Error('请先连接并登录 Claude Code');
   const choice=turnOptions(this.claude.status.models,input.model||'',input.effort||'');model=choice.model.id;
   const sdk=await this.sdkLoader(),result=await sdk.forkSession(source.localHistory.id,{dir:source.localHistory.cwd,title:source.title+' · EVA 分支'});sessionId=result.sessionId;idNew='claude-'+crypto.randomUUID();
  }
  const t={id:idNew,provider:source.provider,projectId:p.id,title:source.title+' · EVA 分支',mode,model,effort:input.effort||'',messages:source.messages.map(m=>({...m})),tools:[],status:'idle',activeTurn:null,error:null,diff:'',createdAt:Date.now(),forkedFrom:{provider:source.provider,id:source.localHistory.id,title:source.title}};
  if(sessionId)t.sessionId=sessionId;this.state.threads.push(t);this.changed();return t;
 }
 async action(url,input){
  if(url==='/api/history/sync')return this.sync();
  if(url==='/api/history/read')return this.read(input.threadId,{older:!!input.older});
  if(url==='/api/history/continue')return this.continue(input.threadId,input);
  const mirror=input.threadId?this.state.threads.find(t=>t.id===input.threadId&&t.localHistory):null;
  // Archiving a mirror only hides it in EVA; the official Codex / Claude record is not changed.
  if(mirror&&url==='/api/thread/archive'){
   if(typeof input.archived!=='boolean')throw Error('归档状态无效');
   if(!input.archived&&mirror.officialArchived)throw Error('这条会话已在官方应用中归档，请在官方应用中恢复');
   mirror.archivedLocally=input.archived;mirror.archived=input.archived||!!mirror.officialArchived;this.changed();return {thread:mirror};
  }
  if(mirror&&['/api/send','/api/thread/rename','/api/thread/mode'].includes(url))throw Error('原会话按只读方式展示，请点击“继续此会话”创建 EVA 分支');
 }
}
module.exports={LocalHistory,storedState,readDesktopMetadata,codexItems,claudeItems,textContent};
