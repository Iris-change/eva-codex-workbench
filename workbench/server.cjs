'use strict';
const http=require('node:http'),fs=require('node:fs'),fsp=fs.promises,path=require('node:path'),crypto=require('node:crypto');
const {defaultCodex,sameProjectPath,pickFolder}=require('./platform.cjs');
const CODEX=process.env.HACKCLAW_CODEX||defaultCodex();
const {ClaudeWorkbench}=require('./claude-workbench.cjs');
const {LocalHistory,storedState}=require('./local-history.cjs');
const {permissionMode,ensureModeChangeAllowed}=require('./permission-modes.cjs');
const {codexUsage,codexContext,staleUsage}=require('./usage-metrics.cjs');
const {CodexBridge}=require('./bridge.cjs');const {reduceEvent}=require('./state.cjs');
const {AttachmentStore,isImage}=require('./attachments.cjs');const {ConversationTransfer,transferInput,markHandoffStarted,settleHandoff}=require('./conversation-transfer.cjs');const {normalizeModel,turnOptions}=require('./model-options.cjs');
const {TerminalManager}=require('./terminal.cjs'),{GitService}=require('./git-service.cjs'),{PluginManager}=require('./plugins.cjs');
const terminals=new TerminalManager(),git=new GitService(),plugins=new PluginManager(CODEX);
const ROOT=__dirname,DATA=path.resolve(process.env.HACKCLAW_DATA_DIR||path.join(ROOT,'data')),PORT=Number(process.env.HACKCLAW_PORT||43137),ORIGIN=`http://127.0.0.1:${PORT}`;
const attachments=new AttachmentStore(path.join(DATA,'attachments')),sendingThreads=new Set();
const token=crypto.randomBytes(32).toString('hex'),subscribers=new Set(),approvals=new Map(),loaded=new Set();
const terminalStyleNonce=crypto.randomBytes(18).toString('base64');
let state={projects:[],threads:[]},account={signedIn:false,type:null},models=[],connection='connecting',connectionError=null,connectionAttempt=null,saveTimer,notifyTimer,usage=null,usageRefresh;
fs.mkdirSync(DATA,{recursive:true});
try{state=JSON.parse(fs.readFileSync(path.join(DATA,'state.json'),'utf8'))}catch(e){if(e.code!=='ENOENT')throw Error('Cannot load local history; original file preserved: '+e.message)}
for(const t of state.threads){if(t.activeTurn||t.status==='inProgress'){t.activeTurn=null;t.status='interrupted';t.error='工作台上次关闭时任务未完成，请确认文件状态后重试。'}}
function snapshot(){return {...state,connection,connectionError,account,models,usage,approvals:[...approvals.values()],providers:{claude:claude.status},localHistory:history.summary,version:'0.11.0-native'}}
function persist(){clearTimeout(saveTimer);saveTimer=setTimeout(()=>{try{const tmp=path.join(DATA,'state.tmp');fs.writeFileSync(tmp,JSON.stringify(storedState(state)));fs.renameSync(tmp,path.join(DATA,'state.json'))}catch(e){connectionError='History save failed: '+e.message;notify()}},200)}
function notify(){if(notifyTimer)return;notifyTimer=setTimeout(()=>{notifyTimer=null;const s='data: '+JSON.stringify(snapshot())+'\n\n';for(const client of subscribers)client.write(s)},40)}
function changed(){persist();notify()}
const bridge=new CodexBridge(CODEX);
const claude=new ClaudeWorkbench({state,project,attachments,approvals,changed,notify});
const history=new LocalHistory({state,bridge,changed,models:()=>models,claude,loaded});
const transfer=new ConversationTransfer({state,history,attachments,changed,createThread:input=>action('/api/thread',input),renameThread:(threadId,title)=>action('/api/thread/rename',{threadId,title}),archiveThread:threadId=>action('/api/thread/archive',{threadId,archived:true})});
bridge.on('notification',m=>{
  const p=m.params||{};const t=state.threads.find(x=>x.id===p.threadId);
  if(t){reduceEvent(t,m.method,p);if(m.method==='thread/tokenUsage/updated'){const value=codexContext(t.usage);if(value)t.contextUsage=value}if(m.method==='turn/completed'){settleHandoff(t,p.turn?.status)}if(m.method==='turn/completed')for(const [id,r] of approvals)if(r.params.threadId===t.id)approvals.delete(id);changed()}
  if(m.method==='account/rateLimits/updated'){usage=codexUsage(p);notify()}
  if(m.method==='serverRequest/resolved'){approvals.delete(String(p.requestId));notify()}
  if(m.method==='account/login/completed'||m.method==='account/updated')refreshAccount().catch(e=>{connectionError=e.message;notify()});
});
bridge.on('approval',m=>{
  const known=['item/commandExecution/requestApproval','item/fileChange/requestApproval','item/permissions/requestApproval','item/tool/requestUserInput'];
  if(known.includes(m.method)&&state.threads.some(t=>t.id===m.params?.threadId)){approvals.set(String(m.id),m);notify()}
  else{bridge.send({id:m.id,error:{code:-32601,message:'This request is not supported by UNIT-02 v0.2; no permission granted'}});const t=state.threads.find(x=>x.id===m.params?.threadId);if(t){t.error='尚不支持的交互请求已拒绝：'+m.method;changed()}}
});
bridge.on('disconnected',message=>{connection='disconnected';connectionError=message;loaded.clear();for(const [id,r] of approvals)if(r.provider!=='claude')approvals.delete(id);for(const t of state.threads)if(t.provider!=='claude'&&t.activeTurn){t.activeTurn=null;t.status='interrupted';t.error=message}changed()});
async function refreshAccount(){const r=await bridge.request('account/read',{refreshToken:false});account={signedIn:!!r.account,type:r.account?.type||null};notify()}
async function refreshUsage(){if(usageRefresh)return usageRefresh;usageRefresh=bridge.request('account/rateLimits/read',{}).then(r=>{usage=codexUsage(r)}).catch(e=>{usage=staleUsage(usage,e)}).finally(()=>{usageRefresh=null;notify()});await usageRefresh;return usage}
async function connect(){
  if(connectionAttempt)return connectionAttempt;
  connection='connecting';connectionError=null;notify();
  connectionAttempt=(async()=>{try{
    await bridge.start();await refreshAccount();const result=await bridge.request('model/list',{});
    models=result.data.filter(x=>!x.hidden).map(normalizeModel);connection='connected';notify();history.sync().catch(()=>{});refreshUsage();
  }catch(e){bridge.stop();connection='disconnected';connectionError=e.message;account={signedIn:false,type:null};models=[];notify()}})();
  try{await connectionAttempt}finally{connectionAttempt=null}
}
function thread(id){const t=state.threads.find(x=>x.id===id);if(!t)throw Error('Unknown workbench conversation');return t}
function project(id){const p=state.projects.find(x=>x.id===id);if(!p)throw Error('Unknown project');return p}
function inside(root,target){const relative=path.relative(root,target);return !relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative)}
async function safeFile(projectId,relative=''){
  const p=project(projectId),root=await fsp.realpath(p.path),target=await fsp.realpath(path.resolve(root,relative));
  if(!inside(root,target))throw Error('Path is outside the selected project');
  if(path.relative(root,target).split(path.sep).some(x=>/^\.env(?:\.|$)/i.test(x)||/^(auth\.json|credentials|\.ssh)$/i.test(x)))throw Error('Credential files are excluded from the viewer');
  return target;
}
async function body(req,limit=128*1024){const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>limit)throw Error('请求内容过大');chunks.push(chunk)}return JSON.parse(Buffer.concat(chunks).toString('utf8')||'{}')}
function json(res,value,code=200){res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(value))}
async function action(url,input){
  if(input.provider!==undefined&&!['codex','claude'].includes(input.provider))throw Error('未知后端');
  if(url==='/api/thread/transfer')return transfer.import(input);
  if(url==='/api/thread/transfer/undo')return transfer.undo(input);
  if(url==='/api/thread/merge')return transfer.merge(input);
  const historical=await history.action(url,input);if(historical!==undefined)return historical;
  const handled=await claude.action(url,input);if(handled!==undefined)return handled;
  if(url==='/api/usage/refresh')return refreshUsage();
  if(url==='/api/thread/mode'){
    const t=thread(input.threadId);ensureModeChangeAllowed(t,sendingThreads.has(t.id)||[...approvals.values()].some(r=>r.params.threadId===t.id));t.mode=permissionMode('codex',input);loaded.delete(t.id);changed();return {thread:t};
  }
  if(url.startsWith('/api/dev/')){
    const operation=url.slice('/api/dev/'.length);
    if(operation==='terminal-input'){terminals.input(input.id,input.data);return {ok:true}}
    if(operation==='terminal-resize'){terminals.resize(input.id,input.cols,input.rows);return {ok:true}}
    if(operation==='terminal-close'){terminals.close(input.id);return {ok:true}}
    const p=project(input.projectId);
    if(operation==='terminal-list')return {terminals:terminals.list(p.id)};
    if(operation==='terminal-create'){await fsp.access(p.path);return terminals.create(p)}
    if(operation==='git-status')return git.status(p);
    if(operation==='git-diff')return git.diff(p,input);
    if(operation==='git-action'){
      if(state.threads.some(t=>t.projectId===p.id&&t.status==='inProgress'))throw Error('Codex 正在执行此项目的任务，请结束后再操作 Git');
      return git.mutate(p,input);
    }
    if(operation==='plugins-list')return plugins.list(p.path);
    if(operation==='plugins-change'){
      if(state.threads.some(t=>t.status==='inProgress'))throw Error('请先结束正在执行的 Codex 任务，再修改插件');
      return plugins.change(input.id,input.operation,p.path);
    }
    throw Error('未知开发工具操作');
  }
  if(url==='/api/attachment')return attachments.save(input);
  if(url==='/api/thread/rename'){
    const t=thread(input.threadId);if(typeof input.title!=='string'||!input.title.trim()||input.title.trim().length>100)throw Error('对话名称需为 1–100 个字符');
    await bridge.request('thread/name/set',{threadId:t.id,name:input.title.trim()});t.title=input.title.trim();changed();return {thread:t};
  }
  if(url==='/api/thread/archive'){
    const t=thread(input.threadId);if(typeof input.archived!=='boolean')throw Error('归档状态无效');
    if(t.activeTurn||t.status==='inProgress'||sendingThreads.has(t.id)||[...approvals.values()].some(r=>r.params.threadId===t.id))throw Error('请先完成或停止这条对话的任务');
    if(!!t.archived===input.archived)return {thread:t};
    await bridge.request(input.archived?'thread/archive':'thread/unarchive',{threadId:t.id});t.archived=input.archived;loaded.delete(t.id);changed();return {thread:t};
  }
  if(url==='/api/reconnect'){
    if(state.threads.some(t=>t.activeTurn||t.status==='inProgress')||approvals.size)throw Error('请先停止或完成当前任务，再重新连接');
    if(connectionAttempt)await connectionAttempt;else{loaded.clear();bridge.stop();await connect()}
    if(connection!=='connected')throw Error(connectionError||'Codex 连接失败');return {connection,signedIn:account.signedIn};
  }
  if(url==='/api/project'){
    if(typeof input.path!=='string'||!path.isAbsolute(input.path))throw Error('请输入绝对目录路径');
    const real=await fsp.realpath(input.path);if(!(await fsp.stat(real)).isDirectory())throw Error('不是文件夹');
    let p=state.projects.find(x=>sameProjectPath(x.path,real));if(!p){p={id:crypto.randomUUID(),name:path.basename(real),path:real};state.projects.push(p);changed()}return p;
  }
  if(url==='/api/pick-folder')return {path:await pickFolder()};
  if(url==='/api/thread'){
    if(connection!=='connected')throw Error('Codex 未连接');if(!account.signedIn)throw Error('请先通过官方流程登录');
    const p=project(input.projectId);const mode=permissionMode('codex',input);const choice=turnOptions(models,input.model,input.effort);
    const result=await bridge.request('thread/start',{cwd:p.path,sandbox:mode,approvalPolicy:'on-request',approvalsReviewer:'user',model:choice.model.id});
    const t={id:result.thread.id,projectId:p.id,title:'新任务',mode,model:result.model||choice.model.id,effort:input.effort||'',messages:[],tools:[],status:'idle',activeTurn:null,error:null,diff:'',createdAt:Date.now()};state.threads.push(t);loaded.add(t.id);changed();return t;
  }
  if(url==='/api/send'){
    const t=thread(input.threadId);if(connection!=='connected'||!account.signedIn)throw Error('请先连接并登录 Codex');if(t.archived)throw Error('请先恢复这条已归档对话');if(t.activeTurn||t.status==='inProgress'||sendingThreads.has(t.id))throw Error('当前任务尚未结束');
    if(typeof input.text!=='string'||input.text.length>60000)throw Error('文字不能超过 60000 字符');
    const choice=turnOptions(models,input.model??t.model,input.effort??t.effort);
    sendingThreads.add(t.id);
    try{
      const files=await attachments.resolve(input.attachments||[]);if(!input.text.trim()&&!files.length)throw Error('请输入消息或添加文件');
      if(files.some(f=>isImage(f.item))&&!choice.model.inputModalities.includes('image'))throw Error('当前模型不支持图片，请切换模型');
      const handoff=await transferInput(t,attachments),fileText=await attachments.prompt(files);
      if(!loaded.has(t.id)){await bridge.request('thread/resume',{threadId:t.id,cwd:project(t.projectId).path,sandbox:t.mode,approvalPolicy:'on-request',approvalsReviewer:'user',excludeTurns:true});loaded.add(t.id)}
      const message={id:crypto.randomUUID(),role:'user',text:input.text,attachments:files.map(x=>x.item)};
      t.status='inProgress';t.error=null;t.messages.push(message);if(t.title==='新任务')t.title=input.text.trim().slice(0,34)||'图片分析';t.model=choice.model.id;t.effort=input.effort??t.effort??'';changed();
      const prompt=[...[handoff?.text,fileText].filter(Boolean).map(text=>({type:'text',text,text_elements:[]})),...(input.text.trim()?[{type:'text',text:'本次用户请求：\n'+input.text,text_elements:[]}]:[]),...files.filter(f=>isImage(f.item)).map(x=>({type:'localImage',path:x.file}))];
      if(handoff)markHandoffStarted(t);let r;try{r=await bridge.request('turn/start',{threadId:t.id,input:prompt,...choice.params})}catch(e){if(t.transfer)delete t.transfer.injecting;throw e}if(t.status==='inProgress')t.activeTurn=r.turn.id;changed();return {turnId:r.turn.id};
    }catch(e){if(t.status==='inProgress'){t.status='failed';t.error=e.message;changed()}throw e}finally{sendingThreads.delete(t.id)}
  }
  if(url==='/api/cancel'){const t=thread(input.threadId);if(t.activeTurn)await bridge.request('turn/interrupt',{threadId:t.id,turnId:t.activeTurn});return {ok:true}}
  if(url==='/api/approval'){
    const r=approvals.get(String(input.id));if(!r)throw Error('授权请求已经失效');let result;
    if(r.method==='item/tool/requestUserInput'){
      const answers={};for(const q of r.params.questions||[]){const answer=input.answers?.[q.id];if(typeof answer!=='string'||!answer.trim())throw Error('请回答所有问题');answers[q.id]={answers:[answer]}}result={answers};
    }else if(r.method==='item/permissions/requestApproval')result={permissions:input.accept?r.params.permissions:{},scope:'turn'};
    else{const decision=input.accept?'accept':'decline';if(r.params.availableDecisions&&!r.params.availableDecisions.includes(decision))throw Error('当前请求不支持此决定');result={decision}}
    bridge.respond(r.id,result);approvals.delete(String(r.id));notify();return {ok:true};
  }
  if(url==='/api/login'){if(account.signedIn)return {alreadySignedIn:true};const r=await bridge.request('account/login/start',{type:'chatgpt'});return {authUrl:r.authUrl,loginId:r.loginId}}
  if(url==='/api/refresh-account'){await refreshAccount();return account}
  if(url==='/api/shutdown'){setTimeout(shutdown,100);return {ok:true}}
  throw Error('Unknown action');
}
const publicRoot=path.join(ROOT,'public');
const server=http.createServer(async(req,res)=>{
 try{
  if(req.headers.host!==`127.0.0.1:${PORT}`){json(res,{error:'Invalid host'},403);return}
  res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');
  res.setHeader('Content-Security-Policy',`default-src 'self'; script-src 'self'; style-src 'self' 'nonce-${terminalStyleNonce}'; img-src 'self' data:; connect-src 'self'; media-src 'self'; frame-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`);
  const u=new URL(req.url,ORIGIN);
  if(u.pathname==='/health'){json(res,{app:'EVA-UNIT02',version:'0.11.0-native'});return}
  if(u.pathname==='/native-session'){
    if(req.method!=='GET'){json(res,{error:'Method not allowed'},405);return}
    res.setHeader('Set-Cookie',`unit02_session=${token}; HttpOnly; SameSite=Strict; Path=/`);
    json(res,{app:'EVA-UNIT02',version:'0.11.0-native'});return;
  }
  if(u.pathname.startsWith('/api/')){
    if(!req.headers.cookie?.split(';').map(x=>x.trim()).includes('unit02_session='+token)){json(res,{error:'Open the workbench first'},403);return}
    if(req.method==='POST'){
      if(req.headers.origin!==ORIGIN||!req.headers['content-type']?.startsWith('application/json')){json(res,{error:'Invalid origin or content type'},403);return}
      json(res,await action(u.pathname,await body(req,u.pathname==='/api/attachment'?48*1024*1024:128*1024)));return;
    }
    if(req.method!=='GET'){json(res,{error:'Method not allowed'},405);return}
    if(u.pathname==='/api/events'){
      res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-store','Connection':'keep-alive'});res.write('data: '+JSON.stringify(snapshot())+'\n\n');subscribers.add(res);const ping=setInterval(()=>res.write(': keepalive\n\n'),15000);req.on('close',()=>{clearInterval(ping);subscribers.delete(res)});return;
    }
    if(u.pathname==='/api/state'){json(res,snapshot());return}
    if(u.pathname==='/api/dev/terminal-events'){terminals.subscribe(u.searchParams.get('id'),res,req.headers['last-event-id']);return}
    if(u.pathname==='/api/attachment-info'){json(res,await attachments.preview(u.searchParams.get('id')));return}
    if(u.pathname.startsWith('/api/attachment/')){const {item,file}=await attachments.get(u.pathname.slice('/api/attachment/'.length));const data=await fsp.readFile(file);res.writeHead(200,{'Content-Type':item.mime,'Cache-Control':'private, no-store',...(!isImage(item)?{'Content-Disposition':"attachment; filename*=UTF-8''"+encodeURIComponent(item.name).replace(/['()*]/g,c=>'%'+c.charCodeAt(0).toString(16))}:{})});res.end(data);return}
    if(u.pathname==='/api/files'){
      const file=await safeFile(u.searchParams.get('projectId'),u.searchParams.get('path')||'');
      const entries=await fsp.readdir(file,{withFileTypes:true});json(res,entries.filter(x=>!['node_modules','.git','.env','auth.json'].includes(x.name)&&!x.isSymbolicLink()).slice(0,300).map(x=>({name:x.name,directory:x.isDirectory()})));return;
    }
    if(u.pathname==='/api/file'){
      const file=await safeFile(u.searchParams.get('projectId'),u.searchParams.get('path'));const stat=await fsp.stat(file);if(!stat.isFile()||stat.size>512*1024)throw Error('仅预览不超过 512 KB 的文本文件');const buf=await fsp.readFile(file);if(buf.includes(0))throw Error('二进制文件不能作为文本显示');json(res,{text:buf.toString('utf8'),path:path.relative(project(u.searchParams.get('projectId')).path,file).split(path.sep).join('/')});return;
    }
    json(res,{error:'Not found'},404);return;
  }
  if(req.method!=='GET'){json(res,{error:'Method not allowed'},405);return}
  let file;
  const terminalAssets={'/vendor/xterm.js':'@xterm/xterm','/vendor/xterm.css':'@xterm/xterm/css/xterm.css','/vendor/xterm-addon-fit.js':'@xterm/addon-fit'};
  if(terminalAssets[u.pathname]){const data=await fsp.readFile(require.resolve(terminalAssets[u.pathname]));res.writeHead(200,{'Content-Type':u.pathname.endsWith('.css')?'text/css':'text/javascript','Cache-Control':'no-store'});res.end(data);return}
  if(u.pathname==='/intro.html')res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'self'");
  file=path.resolve(publicRoot,u.pathname==='/'?'index.html':'.'+decodeURIComponent(u.pathname));if(!inside(publicRoot,file))throw Error('Invalid path');
  if(u.pathname==='/')res.setHeader('Set-Cookie',`unit02_session=${token}; HttpOnly; SameSite=Strict; Path=/`);
  let data=await fsp.readFile(file);if(u.pathname==='/')data=data.toString('utf8').replace('<head>',`<head><meta name="terminal-style-nonce" content="${terminalStyleNonce}">`);const type={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.ico':'image/x-icon','.jpg':'image/jpeg','.wav':'audio/wav'}[path.extname(file)]||'application/octet-stream';res.writeHead(200,{'Content-Type':type,'Cache-Control':'no-store'});res.end(data);
 }catch(e){json(res,{error:e.message},e.code==='ENOENT'?404:400)}
});
function shutdown(){clearTimeout(saveTimer);fs.writeFileSync(path.join(DATA,'state.json'),JSON.stringify(storedState(state)));terminals.stop();claude.stop();bridge.stop();for(const r of subscribers)r.end();server.close(()=>process.exit(0));setTimeout(()=>process.exit(0),1500).unref()}
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
server.on('error',e=>{console.error('Workbench server: '+e.message);bridge.stop();process.exitCode=1});
server.listen(PORT,'127.0.0.1',()=>{console.log(`HACKCLAW ${ORIGIN}`);connect();claude.refresh()});
module.exports={inside,reduceEvent};
