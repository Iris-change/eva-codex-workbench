'use strict';
const fs=require('node:fs'),fsp=fs.promises,path=require('node:path'),crypto=require('node:crypto');
const {execFile}=require('node:child_process'),{promisify}=require('node:util');
const {turnOptions}=require('./model-options.cjs');
const {permissionMode,ensureModeChangeAllowed}=require('./permission-modes.cjs');
const {claudeUsage,contextUsage,staleUsage}=require('./usage-metrics.cjs');
const {isImage}=require('./attachments.cjs');
const {transferInput}=require('./conversation-transfer.cjs');
const run=promisify(execFile);
const READ_TOOLS=['Read','Glob','Grep'];
const WRITE_TOOLS=[...READ_TOOLS,'Edit','Write','NotebookEdit','Bash','WebFetch','WebSearch','AskUserQuestion'];
// Claude Code connects directly with the official CLI. The user's own proxy variables (HTTPS_PROXY / NO_PROXY…)
// are passed through unchanged; nothing is forced. CLAUDECODE is removed so the child does not think it is nested.
function claudeEnv(env=process.env){
 const result={...env,DISABLE_AUTOUPDATER:'1'};
 delete result.CLAUDECODE;return result;
}
function executable(){return process.env.EVA_CLAUDE||path.join(__dirname,'node_modules', '@anthropic-ai','claude-agent-sdk-'+process.platform+'-'+process.arch,process.platform==='win32'?'claude.exe':'claude')}
function normalizeClaudeModel(m,i=0){
 const resolvedModel=typeof m.resolvedModel==='string'?m.resolvedModel:'';
 const version=resolvedModel.match(/^claude-(opus|sonnet|haiku|fable)-(\d+)(?:-(\d+))?(?:$|\[|-)/i);
 const concreteName=version?version[1][0].toUpperCase()+version[1].slice(1)+' '+version[2]+(version[3]?'.'+version[3]:''):resolvedModel||m.displayName;
 const followsOfficial=['default','opus','sonnet','haiku','fable','best'].includes(m.value);
 const name=m.value==='default'?'官方默认 · '+concreteName:followsOfficial?concreteName+'（随官方更新）':concreteName;
 return {id:m.value,name,resolvedModel,description:m.description||'',followsOfficial,isDefault:m.value==='default'||i===0,inputModalities:['text','image'],supportedReasoningEfforts:(m.supportedEffortLevels||[]).map(e=>({reasoningEffort:e,description:e}))};
}
function within(root,file){const r=path.relative(root,file);return r===''||(!r.startsWith('..'+path.sep)&&r!=='..'&&!path.isAbsolute(r))}
async function permittedPath(root,target){
 if(typeof target!=='string')return false;
 const full=path.resolve(root,target);
 if(!within(root,full)||full.split(path.sep).some(x=>/^\.env(?:\.|$)/i.test(x)||/^(auth\.json|credentials|\.ssh)$/i.test(x)))return false;
 let probe=full;while(true){try{return within(await fsp.realpath(root),await fsp.realpath(probe))}catch(e){if(e.code!=='ENOENT')return false;const next=path.dirname(probe);if(next===probe)return false;probe=next}}
}
class ClaudeWorkbench{
 constructor({state,project,attachments,approvals,changed,notify,networkCheck=async()=>{},sdkLoader=()=>import('@anthropic-ai/claude-agent-sdk')}){
  Object.assign(this,{state,project,attachments,approvals,changed,notify,networkCheck,sdkLoader});this.active=new Map();this.decisions=new Map();this.loginProcess=null;
  this.status={connection:'disconnected',connectionError:null,account:{signedIn:false,type:null},models:[]};
 }
 async refresh(){
  if(this.refreshing)return this.refreshing;
  this.status.connection='connecting';this.notify();
  this.refreshing=(async()=>{
   let probe,release;const held=new Promise(r=>{release=r});
   try{
    await this.networkCheck();
    const {stdout}=await run(executable(),['auth','status'],{env:claudeEnv(),timeout:15000,maxBuffer:65536}).catch(e=>{if(e.code===1&&e.stdout)return {stdout:e.stdout};throw e});
    const auth=JSON.parse(stdout);this.status.account={signedIn:!!auth.loggedIn,type:auth.authMethod||null};
    const {query}=await this.sdkLoader();
    probe=query({prompt:(async function*(){await held})(),options:{cwd:__dirname,env:claudeEnv(),pathToClaudeCodeExecutable:executable(),settingSources:[],tools:[],permissionMode:'default',persistSession:false}});
    const list=await Promise.race([probe.supportedModels(),new Promise((_,reject)=>{const t=setTimeout(()=>reject(Error('Claude 初始化超时')),20000);t.unref()})]);
    this.status.models=list.map(normalizeClaudeModel);
    await this.readUsage(probe);
    this.status.connection='connected';this.status.connectionError=null;
   }catch(e){this.status.connection='disconnected';this.status.connectionError='Claude 连接失败：'+e.message}
   finally{release();probe?.close();this.refreshing=null;this.notify()}
  })();return this.refreshing;
 }
 async action(url,input){
  if(url==='/api/usage/refresh'&&input.provider==='claude'){await this.refreshUsage(input.threadId);return this.status.usage}
  if(['/api/login','/api/refresh-account','/api/reconnect'].includes(url)&&input.provider==='claude'){
   if(url==='/api/login')return this.login();await this.refresh();return this.status.account;
  }
  if(url==='/api/thread'&&input.provider==='claude'){
   if(this.status.connection!=='connected'||!this.status.account.signedIn)throw Error('请先登录 Claude Code 并刷新连接');
   const p=this.project(input.projectId),choice=turnOptions(this.status.models,input.model,input.effort);
   const t={id:'claude-'+crypto.randomUUID(),provider:'claude',projectId:p.id,title:'新任务',mode:permissionMode('claude',input),model:choice.model.id,effort:input.effort||'',messages:[],tools:[],status:'idle',activeTurn:null,error:null,diff:'',createdAt:Date.now()};
   this.state.threads.push(t);this.changed();return t;
  }
  if(url==='/api/approval'&&String(input.id).startsWith('claude-')){
   const decision=this.decisions.get(String(input.id));if(!decision)throw Error('Claude 授权请求已经失效');decision(input);return {ok:true};
  }
  const t=this.state.threads.find(x=>x.id===input.threadId);if(t?.provider!=='claude')return;
  if(url==='/api/thread/mode'){ensureModeChangeAllowed(t,this.active.has(t.id));t.mode=permissionMode('claude',input);this.changed();return {thread:t}}
  if(url==='/api/thread/rename'){
   if(typeof input.title!=='string'||!input.title.trim()||input.title.trim().length>100)throw Error('对话名称需为 1–100 个字符');
   t.title=input.title.trim();this.changed();return {thread:t};
  }
  if(url==='/api/thread/archive'){
   if(typeof input.archived!=='boolean')throw Error('归档状态无效');if(this.active.has(t.id))throw Error('请先停止当前任务');t.archived=input.archived;this.changed();return {thread:t};
  }
  if(url==='/api/cancel'){this.cancel(t.id);return {ok:true}}
  if(url==='/api/send')return this.send(t,input);
 }
 async readUsage(query){
  try{
   const method=query.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET;
   if(typeof method!=='function')throw Error('当前 Claude SDK 不支持额度查询');
   const raw=await Promise.race([method.call(query,{skipBehaviors:true}),new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error('额度查询超时')),15000);timer.unref()})]);
   this.status.usage=claudeUsage(raw);
  }catch(e){this.status.usage=staleUsage(this.status.usage,e)}
  this.notify();return this.status.usage;
 }
 async readContext(t,query){
  if(typeof query.getContextUsage!=='function')return;
  try{const raw=await Promise.race([query.getContextUsage({detail:'summary'}),new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error('上下文查询超时')),5000);timer.unref()})]);const value=contextUsage(raw);if(value){t.contextUsage=value;this.changed()}}catch{}
 }
 async refreshUsage(threadId){
  if(this.usageRefreshing)return this.usageRefreshing;
  this.usageRefreshing=(async()=>{
   await this.networkCheck();const active=this.active.get(threadId),t=this.state.threads.find(t=>t.id===threadId);
   if(active?.query){await Promise.allSettled([this.readUsage(active.query),this.readContext(t,active.query)]);return}
   const {query}=await this.sdkLoader();let release;const held=new Promise(r=>release=r);let probe;
   const sessionId=t?.localHistory?.provider==='claude'?t.localHistory.id:t?.sessionId;
   const inspectContext=!!t&&!t.contextUsage&&typeof sessionId==='string'&&/^[a-f0-9-]{36}$/i.test(sessionId)&&fs.existsSync(this.project(t.projectId).path);
   const options={cwd:inspectContext?this.project(t.projectId).path:__dirname,env:claudeEnv(),pathToClaudeCodeExecutable:executable(),settingSources:[],tools:[],permissionMode:'default',persistSession:false};
   if(inspectContext)options.resume=sessionId;
   try{probe=query({prompt:(async function*(){await held})(),options});this.usageProbe=probe;await Promise.allSettled([this.readUsage(probe),...(inspectContext?[this.readContext(t,probe)]:[])])}finally{release();probe?.close();if(this.usageProbe===probe)this.usageProbe=null}
  })().catch(e=>{this.status.usage=staleUsage(this.status.usage,e);this.notify()}).finally(()=>{this.usageRefreshing=null});return this.usageRefreshing;
 }
 async login(){
  if(this.status.account.signedIn)return {alreadySignedIn:true};
  await this.networkCheck();
  if(this.loginProcess) return {message:'Claude Code 登录窗口已打开，完成后点击“刷新”'};
  const script=path.join(__dirname,'..','Claude-Login.command');
  if(process.platform==='darwin'){
   await run('/usr/bin/open',['-a','Terminal',script]);return {message:'请在打开的终端中完成 Claude Code 官方登录，然后点击“刷新”'};
  }
  throw Error('请在系统终端运行 Claude Code auth login，完成后刷新');
 }
 ask(t,name,input,context){
  return new Promise(resolve=>{
   const id='claude-'+crypto.randomUUID();let done=false;
   const finish=answer=>{if(done)return;done=true;context.signal?.removeEventListener('abort',abort);this.decisions.delete(id);this.approvals.delete(id);this.notify();resolve(answer)};
   const abort=()=>finish({behavior:'deny',message:'任务已停止'});
   this.decisions.set(id,answer=>{
    if(!answer.accept)return finish({behavior:'deny',message:'用户拒绝本次操作'});
    if(name==='AskUserQuestion'){
     const answers={};for(const [i,q] of (input.questions||[]).entries()){const value=answer.answers?.[String(i)];if(typeof value!=='string'||!value.trim())return finish({behavior:'deny',message:'问题尚未回答'});answers[q.question]=value}
     return finish({behavior:'allow',updatedInput:{...input,answers}});
    }
    finish({behavior:'allow',updatedInput:input});
   });
   const questions=name==='AskUserQuestion'?(input.questions||[]).map((q,i)=>({id:String(i),question:q.question,options:q.options})):undefined;
   this.approvals.set(id,{id,provider:'claude',method:name==='AskUserQuestion'?'item/tool/requestUserInput':'claude/tool/requestApproval',params:{threadId:t.id,toolUseId:context?.toolUseID||null,cwd:this.project(t.projectId).path,reason:'Claude Code 请求执行 '+name,command:JSON.stringify({tool:name,input},null,2),questions}});
   context.signal?.addEventListener('abort',abort,{once:true});if(context.signal?.aborted)abort();this.notify();
  });
 }
 approvedAttachment(t,name,input){const target=input.file_path??input.path;return ['Read','Grep'].includes(name)&&typeof target==='string'&&!!this.active.get(t.id)?.attachmentPaths?.has(path.resolve(this.project(t.projectId).path,target))}
 async guard(t,name,input){
  if(t.mode==='full-access')return null;
  const cwd=this.project(t.projectId).path;
  if(t.mode==='read-only'&&!READ_TOOLS.includes(name))return '当前会话只允许 Read、Glob、Grep 只读工具';
  const target=input.file_path??input.notebook_path??(['Glob','Grep'].includes(name)?input.path||cwd:undefined);
  if(this.approvedAttachment(t,name,input))return null;
  if(target!==undefined&&!await permittedPath(cwd,target))return '文件工具只允许访问所选项目内的普通文件，排除凭据路径和越界符号链接';
  return null;
 }
 async beforeFile(active,e){
  if(!['Write','Edit'].includes(e.tool_name))return;
  const filename=e.tool_input.file_path;if(typeof filename!=='string')return;
  let before='';try{const stat=await fsp.stat(filename);if(stat.size>512*1024)return;before=await fsp.readFile(filename,'utf8')}catch(error){if(error.code!=='ENOENT')return}
  active.files??=new Map();active.files.set(e.tool_use_id,{filename,before});
 }
 async afterFile(t,active,e){
  const entry=active.files?.get(e.tool_use_id);if(!entry)return;active.files.delete(e.tool_use_id);
  if(!await permittedPath(this.project(t.projectId).path,entry.filename))return;
  const stat=await fsp.stat(entry.filename);if(stat.size>512*1024)return;
  const after=await fsp.readFile(entry.filename,'utf8');if(after===entry.before)return;
  const filename=path.relative(this.project(t.projectId).path,entry.filename);
  const old=entry.before.split('\n'),next=after.split('\n');
  // A complete-file replacement hunk remains exact for repeated strings and multi-edit operations.
  const diff='--- a/'+filename+'\n+++ b/'+filename+'\n@@ -1,'+old.length+' +1,'+next.length+' @@\n'+old.map(x=>'-'+x).join('\n')+'\n'+next.map(x=>'+'+x).join('\n');
  t.tools.push({id:'change-'+e.tool_use_id,type:'fileChange',status:'completed',changes:[{path:filename,diff}],at:(t.messages||[]).length,startedAt:Date.now(),endedAt:Date.now()});this.changed();
 }
 async send(t,input){
  if(this.status.connection!=='connected'||!this.status.account.signedIn)throw Error('请先登录 Claude Code 并刷新');
  if(t.archived)throw Error('请先恢复已归档对话');if(this.active.has(t.id))throw Error('当前任务尚未结束');
  if(typeof input.text!=='string'||input.text.length>60000)throw Error('文字不能超过 60000 字符');
  const choice=turnOptions(this.status.models,input.model??t.model,input.effort??t.effort);
  // Reserve the thread before resolving attachments: simultaneous HTTP requests cannot start two turns.
  const active={controller:new AbortController(),cancelled:false,query:null,streamed:new Set(),assistantStarted:false};this.active.set(t.id,active);
  try{
   await this.networkCheck();
   const files=await this.attachments.resolve(input.attachments||[]);if(!input.text.trim()&&!files.length)throw Error('请输入消息或添加文件');
   const handoff=await transferInput(t,this.attachments),contextFiles=handoff?[...files,handoff.file]:files;
   active.attachmentPaths=this.attachments.authorizedPaths?await this.attachments.authorizedPaths(t,contextFiles):new Set(contextFiles.map(f=>f.file));active.transferInjected=!!handoff;
   const fileText=this.attachments.prompt?await this.attachments.prompt(files):'',content=[];
   for(const text of [handoff?.text,fileText])if(text)content.push({type:'text',text});
   if(input.text.trim())content.push({type:'text',text:'本次用户请求：\n'+input.text});
   for(const f of files.filter(f=>isImage(f.item)))content.push({type:'image',source:{type:'base64',media_type:f.item.mime,data:(await fsp.readFile(f.file)).toString('base64')}});
   const {query}=await this.sdkLoader();
   if(active.cancelled)throw Error('任务已停止');
   t.status='inProgress';t.error=null;t.activeTurn=crypto.randomUUID();t.model=choice.model.id;t.effort=input.effort??t.effort;t.requestedModel=choice.model.id;t.resolvedModel=choice.model.resolvedModel||null;
   t.messages.push({id:crypto.randomUUID(),role:'user',text:input.text,attachments:files.map(f=>f.item)});if(t.title==='新任务')t.title=input.text.trim().slice(0,34)||'图片分析';
   let release;const held=new Promise(r=>{release=r});active.release=release;
   const full=t.mode==='full-access';
   const options={cwd:this.project(t.projectId).path,env:claudeEnv(),pathToClaudeCodeExecutable:executable(),model:t.model,includePartialMessages:true,permissionMode:full?'bypassPermissions':'default',allowDangerouslySkipPermissions:full,settingSources:[],tools:full?{type:'preset',preset:'claude_code'}:t.mode==='read-only'?READ_TOOLS:WRITE_TOOLS,abortController:active.controller,
    systemPrompt:{type:'preset',preset:'claude_code',append:t.mode==='read-only'?'本次任务只读分析，不允许修改文件。':full?'用户已为本会话选择完全访问。本机文件与命令按用户权限执行。':'仅在选定项目内工作。命令执行需要用户逐次确认。'},
    settings:{permissions:full?{}:{ask:['Bash','Edit','Write','NotebookEdit','WebFetch','WebSearch']}},
    hooks:{PreToolUse:[{hooks:[async e=>{const reason=await this.guard(t,e.tool_name,e.tool_input);if(reason)return {hookSpecificOutput:{hookEventName:'PreToolUse',permissionDecision:'deny',permissionDecisionReason:reason}};await this.beforeFile(active,e);return {}}]}],PostToolUse:[{hooks:[async e=>{try{await this.afterFile(t,active,e)}catch{}return {}}]}]},
    canUseTool:async(name,toolInput,context)=>{const reason=await this.guard(t,name,toolInput);return reason?{behavior:'deny',message:reason}:this.approvedAttachment(t,name,toolInput)?{behavior:'allow',updatedInput:toolInput}:this.ask(t,name,toolInput,context)}
   };
   if(t.sessionId)options.resume=t.sessionId;if(t.effort)options.effort=t.effort;
   active.query=query({prompt:(async function*(){yield {type:'user',message:{role:'user',content},parent_tool_use_id:null,session_id:t.sessionId||''};await held})(),options});
   this.changed();this.consume(t,active).catch(()=>{});return {turnId:t.activeTurn};
  }catch(e){this.active.delete(t.id);if(t.status==='inProgress'){t.status='failed';t.activeTurn=null;t.error=e.message;this.changed()}throw e}
 }
 event(t,m,active){
  if(m.context_usage){const value=contextUsage(m.context_usage);if(value)t.contextUsage=value}
  if(m.type==='system'&&m.subtype==='init'){t.sessionId=m.session_id;if(m.model)t.initializedModel=m.model}
  if(m.type==='stream_event'){
   const e=m.event;
   if(e.type==='message_start'){active.messageId=e.message.id;active.responseModel=e.message.model||null;active.text='';if(active.responseModel)t.lastResponseModel=active.responseModel}
   if(e.type==='content_block_delta'&&e.delta.type==='text_delta'){
    const id=active.messageId||m.uuid;active.streamed.add(id);active.assistantStarted=true;let msg=t.messages.find(x=>x.id===id);if(!msg){msg={id,role:'assistant',text:'',...(active.responseModel?{model:active.responseModel}:{})};t.messages.push(msg)}msg.text+=e.delta.text;
   }
  }
  if(m.type==='assistant'){
   if(active.transferInjected&&t.transfer)t.transfer.pending=false;
   const msg=m.message,id=msg.id||m.uuid,text=msg.content.filter(c=>c.type==='text').map(c=>c.text).join('\n');
   if(msg.model){t.lastResponseModel=msg.model;active.responseModel=msg.model;const existing=t.messages.find(x=>x.id===id);if(existing)existing.model=msg.model}
   if(text&&!active.streamed.has(id)){active.assistantStarted=true;const existing=t.messages.find(x=>x.id===id);if(existing)existing.text+=text;else t.messages.push({id,role:'assistant',text,...(msg.model?{model:msg.model}:{})})}
   for(const c of msg.content.filter(c=>c.type==='tool_use'))if(!t.tools.some(x=>x.id===c.id))t.tools.push({id:c.id,type:'claudeTool',name:c.name,input:c.input,status:'inProgress',at:(t.messages||[]).length,startedAt:Date.now()});
  }
  if(m.type==='user'&&Array.isArray(m.message?.content))for(const c of m.message.content.filter(c=>c.type==='tool_result')){const tool=t.tools.find(x=>x.id===c.tool_use_id);if(tool){tool.endedAt=Date.now();tool.status=c.is_error?'failed':'completed';tool.output=typeof c.content==='string'?c.content:JSON.stringify(c.content)}}
  if(m.type==='result'){
   if(m.subtype==='success'&&!m.is_error&&active.transferInjected&&t.transfer)t.transfer.pending=false;
   if(m.session_id)t.sessionId=m.session_id;t.usage=m.usage;
   if(m.is_error||m.subtype!=='success'){t.status='failed';t.error=(m.errors||[]).join('\n')||m.result||'Claude 任务未完成'}else t.status='completed';
   if(m.result&&!active.assistantStarted)t.messages.push({id:m.uuid||crypto.randomUUID(),role:'assistant',text:m.result});
   return true;
  }
  return false;
 }
 async consume(t,active){
  try{for await(const m of active.query){const done=this.event(t,m,active);this.changed();if(done){await this.readContext(t,active.query);break}}if(t.status==='inProgress'){t.status='failed';t.error='Claude 连接结束，未收到任务结果'}}
  catch(e){t.status=active.cancelled?'interrupted':'failed';t.error=active.cancelled?null:e.message}
  finally{
   active.release?.();active.query?.close();this.active.delete(t.id);t.activeTurn=null;
   for(const [id,r] of this.approvals)if(r.provider==='claude'&&r.params.threadId===t.id)this.decisions.get(id)?.({accept:false});
   for(const tool of t.tools)if(tool.status==='inProgress')tool.status=active.cancelled?'interrupted':t.status==='failed'?'failed':'completed';
   if(active.cancelled){t.status='interrupted';t.error=null}this.changed();
  }
 }
 cancel(id){const active=this.active.get(id);if(!active)return;active.cancelled=true;active.controller.abort();active.release?.();active.query?.close()}
 stop(){this.usageProbe?.close();for(const id of this.active.keys())this.cancel(id);for(const decide of this.decisions.values())decide({accept:false})}
}
module.exports={ClaudeWorkbench,claudeEnv,executable,permittedPath,normalizeClaudeModel,READ_TOOLS,WRITE_TOOLS};
