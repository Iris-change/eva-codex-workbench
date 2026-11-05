'use strict';
const artworkEnabled=document.getElementById('lineArtEnabled');artworkEnabled.checked=localStorage.getItem('hc-line-art')!=='false';document.body.classList.toggle('artwork-off',!artworkEnabled.checked);artworkEnabled.onchange=()=>{document.body.classList.toggle('artwork-off',!artworkEnabled.checked);localStorage.setItem('hc-line-art',String(artworkEnabled.checked))};
const $=id=>document.getElementById(id);
let state={projects:[],threads:[],models:[],approvals:[]},projectId=localStorage.getItem('hc-project')||'',threadId=localStorage.getItem('hc-thread')||'',sending=false,approvalId=null,lastStatus='',fileDir='',messageSignature='',toolSignature='',showArchived=false,fileEntries=[],fileContents='';
let fx=localStorage.getItem('hc-fx')!=='false';$('fxEnabled').checked=fx;$('contrast').checked=localStorage.getItem('hc-contrast')==='true';document.body.classList.toggle('contrast',$('contrast').checked);
const selected=()=>state.threads.find(x=>x.id===threadId);
function el(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n}
function notify(message){$('notice').textContent=message;$('notice').hidden=!message}
async function api(url,data){const response=await fetch(url,{method:data===undefined?'GET':'POST',headers:data===undefined?{}:{'Content-Type':'application/json'},body:data===undefined?undefined:JSON.stringify(data)});const result=await response.json();if(!response.ok)throw Error(result.error||'Request failed');return result}
function guarded(fn){return async(...args)=>{try{await fn(...args)}catch(e){notify(e.message)}}}
const attachmentComposer=new window.AttachmentComposer({upload:input=>api('/api/attachment',input),onError:notify,onChange:()=>paint()});
function chooseProject(id){projectId=id;threadId='';localStorage.setItem('hc-project',id);localStorage.removeItem('hc-thread');fileDir='';fileContents='';$('fileText').replaceChildren();$('copyFile').disabled=true;messageSignature='';attachmentComposer.clear();paint();loadFiles().catch(()=>{});glitch('PROJECT / MOUNTED')}
function chooseThread(t,keepDraft=false){if(projectId!==t.projectId){fileDir='';fileContents='';$('fileText').replaceChildren();$('copyFile').disabled=true}threadId=t.id;projectId=t.projectId;localStorage.setItem('hc-thread',threadId);localStorage.setItem('hc-project',projectId);messageSignature='';toolSignature='';if(!keepDraft)attachmentComposer.clear();paint();loadFiles().catch(()=>{})}
const effortLabel=value=>({none:'快速',minimal:'简短',low:'轻量',medium:'标准',high:'深入',xhigh:'更深入',max:'最高',ultra:'超强'})[value]||value;
function paintModelControls(t,busy){
 const picker=$('model'),catalog=JSON.stringify(state.models);if(picker.dataset.catalog!==catalog){const prior=picker.value;picker.replaceChildren(el('option','','官方默认模型'));picker.firstChild.value='';for(const m of state.models){const option=el('option','',m.name);option.value=m.id;picker.append(option)}picker.value=prior;picker.dataset.catalog=catalog}
 const selection=t?.id||'',changedThread=picker.dataset.thread!==selection;
 const desired=changedThread?(t?.effort||''):$('effort').value;
 if(changedThread){picker.value=t?.model||picker.value;picker.dataset.thread=selection}
 const model=state.models.find(m=>m.id===picker.value)||state.models.find(m=>m.isDefault)||state.models[0];
 const effort=$('effort'),effortKey=JSON.stringify(model?.supportedReasoningEfforts||[]);
 if(effort.dataset.catalog!==effortKey||changedThread){effort.replaceChildren(el('option','',model?.defaultReasoningEffort?'默认 · '+effortLabel(model.defaultReasoningEffort):'默认思考强度'));effort.firstChild.value='';for(const option of model?.supportedReasoningEfforts||[]){const node=el('option','',effortLabel(option.reasoningEffort));node.value=option.reasoningEffort;node.title=option.description;effort.append(node)}effort.value=[...effort.options].some(o=>o.value===desired)?desired:'';effort.dataset.catalog=effortKey}
 picker.disabled=busy||!!t?.archived;effort.disabled=busy||!!t?.archived||!model?.supportedReasoningEfforts?.length;
 attachmentComposer.setSupported(!model||model.inputModalities?.includes('image')!==false);
}
function richText(container,text){
 const chunks=text.split(/```([^\n]*)\n([\s\S]*?)(?:```|$)/g);
 for(let i=0;i<chunks.length;i+=3){if(chunks[i])container.append(el('div','text',chunks[i]));if(chunks[i+2]!==undefined){const label=el('div','code-label',chunks[i+1]||'CODE');const copy=el('button','','复制');copy.onclick=guarded(async()=>{await navigator.clipboard.writeText(chunks[i+2]);copy.textContent='已复制'});label.append(copy);container.append(label,el('pre','',chunks[i+2]))}}
}
function emptyMessages(){
 const box=el('div','empty');box.append(el('div','eyebrow','ASUKA / EVANGELION-02 · PRIVATE WORKSTATION'));
 box.append(el('h2','','准备好了，就开始。'));
 box.append(el('p','',state.account?.signedIn?'项目已待命。把下一步交给 Codex。':'连接官方 Codex 账号，开始你的工作。'));
 const list=el('div','suggestions');let n=0;for(const [title,prompt] of [['分析项目','请只读查看当前项目，简要说明结构、运行方式和下一步建议。'],['审查代码','请检查当前项目中值得优先修复的问题。先说明发现和建议，不要修改文件。'],['开始构建','请帮我实现以下功能：\n']]){const b=el('button');b.append(el('small','',String(++n).padStart(2,'0')+' / OPERATION'),el('span','',title));b.onclick=()=>{$('prompt').value=prompt;$('prompt').focus()};list.append(b)}box.append(list);return box;
}
function paint(){
 if(!state.projects.some(p=>p.id===projectId))projectId=state.projects[0]?.id||'';
 if(threadId&&!state.threads.some(t=>t.id===threadId))threadId='';
 const t=selected(),p=state.projects.find(x=>x.id===projectId);if(t)projectId=t.projectId;
 document.body.classList.toggle('has-session',!!t?.messages.length);
 document.body.classList.toggle('empty-session',!t?.messages.length);
 $('projectName').textContent=p?.name||'未选择项目';$('sessionTitle').textContent=t?.title||'新对话';
 $('connection').textContent=state.connection==='connected'?'● Codex 已连接':state.connection==='connecting'?'◌ 连接中':'○ 已断开';
 $('accountStatus').textContent=state.connection!=='connected'?(state.connection==='connecting'?'正在连接 Codex…':'Codex 连接已断开'):(state.account?.signedIn?'● 官方 '+state.account.type+' 已登录':'○ 尚未登录');$('login').textContent=state.connection==='disconnected'?'重新连接':state.account?.signedIn?'刷新':'登录';$('login').disabled=state.connection==='connecting';
 $('projects').replaceChildren();for(const p of state.projects){const b=el('button','project'+(p.id===projectId?' active':''),p.name);b.title=p.path;b.onclick=()=>chooseProject(p.id);$('projects').append(b)}if(!state.projects.length)$('projects').append(el('small','','点击 + 添加你的第一个项目'));
 $('threads').replaceChildren();const query=$('threadSearch').value.trim().toLocaleLowerCase();const ts=state.threads.filter(t=>t.projectId===projectId&&!!t.archived===showArchived&&(!query||t.title.toLocaleLowerCase().includes(query)||t.messages.some(m=>m.text?.toLocaleLowerCase().includes(query)))).slice().reverse();$('sessionCount').textContent=String(ts.length).padStart(2,'0');$('threadListLabel').textContent=showArchived?'归档对话':'最近对话';$('toggleArchived').textContent=showArchived?'返回':'归档';$('toggleArchived').setAttribute('aria-pressed',String(showArchived));for(const item of ts){const b=el('button','thread'+(item.id===threadId?' active':''),(item.status==='inProgress'?'◌ ':'')+item.title);b.title=item.title;b.onclick=()=>chooseThread(item);$('threads').append(b)}if(!ts.length)$('threads').append(el('p','thread-empty',query?'没有找到匹配的对话':showArchived?'暂无归档对话':'从一条新对话开始'));
 if(t)$('mode').value=t.mode;$('mode').disabled=!!t;
 $('modeBadge').textContent=(t?.mode||$('mode').value)==='workspace-write'?'项目写入':'只读模式';
 $('protocolMode').textContent=(t?.mode||$('mode').value)==='workspace-write'?'WORKSPACE WRITE':'READ ONLY';
 const ms=JSON.stringify(t?.messages||[]);if(messageSignature!==ms+threadId){const area=$('messages'),atBottom=area.scrollHeight-area.scrollTop-area.clientHeight<100;area.replaceChildren();if(!t?.messages.length)area.append(emptyMessages());else for(const m of t.messages){if(!m.text&&!m.attachments?.length)continue;const box=el('article','message '+m.role);box.append(el('div','message-role',m.role==='user'?'你':'Codex'));if(m.attachments?.length){const images=el('div','message-attachments');for(const item of m.attachments){const link=el('a');link.href=item.url;link.target='_blank';link.rel='noopener';const image=el('img');image.src=item.url;image.alt=item.name;image.loading='lazy';link.append(image);images.append(link)}box.append(images)}richText(box,m.text||'');area.append(box)}if(atBottom||messageSignature==='')area.scrollTop=area.scrollHeight;messageSignature=ms+threadId}
 const busy=sending||t?.status==='inProgress';$('send').disabled=busy||attachmentComposer.pending>0||!!t?.archived||state.connection!=='connected'||!state.account?.signedIn;$('cancel').hidden=!busy;$('cancel').disabled=!t?.activeTurn;$('retry').disabled=busy||!!t?.archived||!t?.messages.some(m=>m.role==='user');
 paintModelControls(t,busy);$('threadActions').hidden=!t;$('archiveThread').disabled=busy;$('archiveThread').textContent=t?.archived?'恢复':'归档';$('renameThread').disabled=busy;
 $('composerHint').textContent=t?.archived?'这条对话已归档，点击“恢复”后可以继续。':'Ctrl + Enter 发送 · 支持粘贴或拖入图片 · 额外权限由你确认';
 document.querySelector('main').dataset.codexActivity=busy?'active':(t?.status||'idle');
 document.querySelector('main').dataset.codexConnection=state.connection||'connecting';
 const status={idle:'就绪',inProgress:'Codex 正在执行…',completed:'任务完成',failed:'任务失败',interrupted:'已停止'}[t?.status]||'就绪';
 $('taskProgress').textContent=t?.error?'错误：'+t.error:status;$('footerStatus').textContent=state.connectionError||'本地连接 / '+status;
 $('signalLabel').textContent=busy?'RECEIVING / LIVE CODEX EVENTS':'OFFICIAL APP-SERVER / STDIO';
 if(t&&lastStatus===t.id+':inProgress'&&t.status==='completed')glitch('TASK / COMPLETE');lastStatus=t?t.id+':'+t.status:'';
 paintTools(t);paintApprovals();
}
function paintTools(t){
 const sig=JSON.stringify([t?.tools,t?.plan,t?.diff]);if(sig===toolSignature)return;toolSignature=sig;const box=$('toolsPanel');const opened=new Set([...box.querySelectorAll('details[open]')].map(x=>x.dataset.id));box.replaceChildren();
 if(t?.plan?.length){const plan=el('div','tool');for(const step of t.plan)plan.append(el('p','hint',(step.status==='completed'?'✓ ':'◌ ')+step.step));box.append(plan)}
 for(const tool of t?.tools||[]){const details=el('details','tool');details.dataset.id=tool.id;details.open=opened.has(tool.id);const title=tool.type==='commandExecution'?tool.command||'命令执行':tool.type==='fileChange'?'文件变更':tool.type==='mcpToolCall'?`${tool.server} / ${tool.tool}`:tool.type;details.append(el('summary','',title),el('span','tool-status',tool.status||'event'));if(tool.type==='commandExecution')details.append(el('pre','',tool.aggregatedOutput||'等待输出…'));else if(tool.type==='fileChange')details.append(el('pre','',tool.changes.map(x=>x.path+'\n'+x.diff).join('\n')));else if(tool.type==='reasoning')details.append(el('pre','',(tool.summary||[]).join('\n')));else details.append(el('pre','',JSON.stringify(tool,null,2)));box.append(details)}
 if(!box.childNodes.length)box.append(el('p','hint','等待任务执行。命令输出与文件变更将在此按事件顺序记录。'));
 const changes=(t?.tools||[]).filter(x=>x.type==='fileChange').flatMap(x=>x.changes||[]),diff=t?.diff||changes.map(c=>c.path+'\n'+c.diff).join('\n')||'';
 $('diffText').replaceChildren();let added=0,removed=0;for(const value of (diff||'尚无代码变更').split('\n')){const cls=value.startsWith('@@')?'diff-hunk':value.startsWith('+')&&!value.startsWith('+++')?'diff-add':value.startsWith('-')&&!value.startsWith('---')?'diff-remove':'diff-context';if(cls==='diff-add')added++;if(cls==='diff-remove')removed++;const row=el('span',cls,value+'\n');$('diffText').append(row)}
 $('diffSummary').textContent=diff?`+${added} / −${removed} · ${new Set(changes.map(c=>c.path)).size} 个文件`:'尚无代码变更';$('copyDiff').disabled=!diff;$('diffFiles').replaceChildren();for(const filename of new Set(changes.map(c=>c.path))){const b=el('button','diff-file',filename);b.title='查看文件';b.onclick=guarded(async()=>{await selectInspectorTab('files');await showFile(filename)});$('diffFiles').append(b)}
}
function paintApprovals(){const r=state.approvals[0];if(!r){approvalId=null;if($('approvalDialog').open)$('approvalDialog').close();return}if(approvalId===String(r.id))return;approvalId=String(r.id);const box=$('approvalDetails');box.replaceChildren();const p=r.params;
 $('approvalTitle').textContent=r.method==='item/tool/requestUserInput'?'Codex 需要你的回答':'Codex 请求额外授权';box.append(el('p','',p.reason||'请检查具体操作后决定。'));
 if(r.method==='item/tool/requestUserInput'){for(const q of p.questions){const label=el('label','',q.question),input=el('input');input.dataset.question=q.id;if(q.options?.length){const hints=el('p','',q.options.map(x=>x.label+': '+x.description).join('\n'));label.append(hints)}label.append(input);box.append(label)}$('approve').textContent='提交回答';$('deny').textContent='停止任务'}
 else{box.append(el('pre','',JSON.stringify({method:r.method,cwd:p.cwd,command:p.command,reason:p.reason,permissions:p.permissions,grantRoot:p.grantRoot},null,2)));const t=state.threads.find(t=>t.id===p.threadId);const changes=t?.tools.filter(x=>x.type==='fileChange');if(changes?.length)box.append(el('pre','',JSON.stringify(changes,null,2)));$('approve').textContent='仅允许本次';$('deny').textContent='拒绝'}
 if(!$('approvalDialog').open)$('approvalDialog').showModal();
}
async function send(text,providedAttachments){if(sending||attachmentComposer.pending)return;if(!projectId){$('projectDialog').showModal();return}const images=providedAttachments||attachmentComposer.items.slice();if(!text.trim()&&!images.length)return;const model=$('model').value,effort=$('effort').value;sending=true;notify('');paint();try{if(!threadId){const t=await api('/api/thread',{projectId,mode:$('mode').value,model,effort});if(!state.threads.some(x=>x.id===t.id))state.threads.push(t);chooseThread(t,true)}await api('/api/send',{threadId,text,attachments:images.map(x=>x.id),model,effort});$('prompt').value='';attachmentComposer.removeSent(images.map(x=>x.id))}finally{sending=false;paint()}}
$('composer').onsubmit=guarded(async e=>{e.preventDefault();await send($('prompt').value)});
$('prompt').onkeydown=e=>{if(e.ctrlKey&&e.key==='Enter'){e.preventDefault();$('composer').requestSubmit()}};
$('newTask').onclick=()=>{threadId='';localStorage.removeItem('hc-thread');messageSignature='';$('mode').disabled=false;attachmentComposer.clear();paint();$('prompt').focus()};
$('model').onchange=()=>{$('effort').value='';$('effort').dataset.catalog='';paintModelControls(selected(),sending||selected()?.status==='inProgress')};
$('threadSearch').oninput=()=>paint();$('toggleArchived').onclick=()=>{showArchived=!showArchived;paint()};
$('renameThread').onclick=()=>{if(!selected())return;$('threadName').value=selected().title;$('threadDialog').showModal();$('threadName').focus()};
$('threadRenameForm').onsubmit=guarded(async event=>{event.preventDefault();const id=threadId;await api('/api/thread/rename',{threadId:id,title:$('threadName').value});const t=state.threads.find(x=>x.id===id);if(t)t.title=$('threadName').value.trim();$('threadDialog').close();paint()});
$('archiveThread').onclick=guarded(async()=>{const t=selected();if(!t)return;const archived=!t.archived;await api('/api/thread/archive',{threadId:t.id,archived});t.archived=archived;showArchived=false;if(archived)$('newTask').click();paint()});
$('addProject').onclick=()=>$('projectDialog').showModal();
$('browse').onclick=guarded(async()=>{$('browse').disabled=true;try{const r=await api('/api/pick-folder',{});if(r.path)$('projectPath').value=r.path}finally{$('browse').disabled=false}});
$('projectForm').onsubmit=guarded(async e=>{e.preventDefault();const p=await api('/api/project',{path:$('projectPath').value});if(!state.projects.some(x=>x.id===p.id))state.projects.push(p);chooseProject(p.id);$('projectDialog').close()});
$('cancel').onclick=guarded(()=>api('/api/cancel',{threadId}));$('retry').onclick=guarded(async()=>{const last=selected()?.messages.filter(x=>x.role==='user').at(-1);if(last)await send(last.text,last.attachments||[])});
$('login').onclick=guarded(async()=>{if(state.connection==='disconnected'){notify('正在恢复连接…');const opened=await fetch('/',{cache:'no-store'});if(!opened.ok)throw Error('请重新打开工作台');state=await api('/api/state');if(state.connection!=='connected')await api('/api/reconnect',{});state=await api('/api/state');paint();notify('');return}if(state.account?.signedIn){await api('/api/refresh-account',{});return}const r=await api('/api/login',{});if(r.authUrl){const url=new URL(r.authUrl);if(url.protocol!=='https:')throw Error('Unexpected authentication URL');const a=el('a','', '打开官方登录页面');a.href=url.href;a.target='_blank';a.rel='noopener noreferrer';$('notice').replaceChildren(a);$('notice').hidden=false}});
$('settings').onclick=()=>$('settingsDialog').showModal();$('fxEnabled').onchange=e=>{fx=e.target.checked;localStorage.setItem('hc-fx',fx)};$('contrast').onchange=e=>{document.body.classList.toggle('contrast',e.target.checked);localStorage.setItem('hc-contrast',e.target.checked)};
for(const b of document.querySelectorAll('[data-close]'))b.onclick=()=>$(b.dataset.close).close();
function openIdentity(autoStart=false){if($('animationDialog').open)return;document.documentElement.classList.add('boot-pending');$('animationDialog').classList.add('identity-opening','identity-loading');$('animationFrame').src=autoStart?'/intro.html?autostart=interactive':'/intro.html';$('animationDialog').showModal()}
$('animation').onclick=$('replayIntro').onclick=()=>{$('settingsDialog').close();openIdentity(true)};
const navButton=el('button','nav-toggle','☰');navButton.type='button';navButton.setAttribute('aria-label','项目与会话导航');navButton.setAttribute('aria-expanded','false');document.querySelector('header').prepend(navButton);
navButton.onclick=()=>{const open=document.body.classList.toggle('nav-open');navButton.setAttribute('aria-expanded',String(open))};
document.querySelector('.sidebar').addEventListener('click',event=>{if(event.target.closest('.project,.thread,#newTask')){document.body.classList.remove('nav-open');navButton.setAttribute('aria-expanded','false')}});
document.addEventListener('keydown',event=>{if(event.key==='Escape'){document.body.classList.remove('nav-open');navButton.setAttribute('aria-expanded','false')}});
$('animationDialog').addEventListener('close',()=>{document.documentElement.classList.remove('boot-pending');$('animationFrame').src='about:blank';$('animationDialog').classList.remove('identity-opening','identity-loading');window.releaseWorkbenchMotion?.()});
window.addEventListener('message',event=>{if(event.origin===location.origin&&event.source===$('animationFrame').contentWindow&&event.data?.type==='hackclaw:intro-ready'){$('animationDialog').classList.remove('identity-loading');document.documentElement.classList.remove('boot-pending')}});
window.addEventListener('message',event=>{if(event.origin===location.origin&&event.source===$('animationFrame').contentWindow&&event.data?.type==='hackclaw:intro-close'){sessionStorage.setItem('hc-identity-admitted','1');$('animationDialog').close()}});
let snapshotBusy=false,snapshotFontCSS='';
async function workbenchSnapshotFont(){
 if(snapshotFontCSS)return snapshotFontCSS;
 const response=await fetch('/fonts/unit02-mincho-black.woff2');
 if(!response.ok)throw Error('Workbench snapshot font unavailable');
 const blob=await response.blob();
 const fontURL=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error('Workbench snapshot font unreadable'));reader.readAsDataURL(blob)});
 snapshotFontCSS=`@font-face{font-family:'Unit02 Mincho';src:url('${fontURL}') format('woff2');font-weight:900;font-style:normal}`;
 return snapshotFontCSS;
}
window.addEventListener('message',async event=>{
 if(event.origin!==location.origin||event.source!==$('animationFrame').contentWindow||event.data?.type!=='hackclaw:snapshot-request'||snapshotBusy)return;
 const receiver=event.source,frameSource=$('animationFrame').src;
 const stillOpen=()=>$('animationDialog').open&&$('animationFrame').src===frameSource&&$('animationFrame').contentWindow===receiver;
 snapshotBusy=true;
 try{
  await document.fonts.ready;
  // The SVG snapshot must carry the same local font or the title wraps at handoff.
  const fontEmbedCSS=await workbenchSnapshotFont();
  if(!stillOpen())return;
  const captured=await htmlToImage.toCanvas(document.body,{width:innerWidth,height:innerHeight,pixelRatio:1,fontEmbedCSS,backgroundColor:'#0b0c0f',filter:node=>!['DIALOG','SCRIPT'].includes(node.tagName)&&!['glitch','workbenchScan'].includes(node.id)});
  const node=$('codexNode')?.querySelector('img')?.getBoundingClientRect();
  const codexTarget=node?{x:(node.x+node.width/2)/innerWidth,y:(node.y+node.height/2)/innerHeight,width:node.width/innerWidth}:null;
  const bitmap=await createImageBitmap(captured);if(!stillOpen()){bitmap.close();return}receiver.postMessage({type:'hackclaw:workbench-snapshot',bitmap,width:captured.width,height:captured.height,codexTarget,connected:state.connection==='connected'},location.origin,[bitmap]);
 }catch(error){if(stillOpen())receiver.postMessage({type:'hackclaw:snapshot-error',message:error.message},location.origin)}finally{snapshotBusy=false}
});
window.addEventListener('message',event=>{if(event.origin===location.origin&&event.source===$('animationFrame').contentWindow&&event.data?.type==='hackclaw:motion-clock'&&Number.isFinite(event.data.time))window.syncWorkbenchMotion?.(event.data.time,!!event.data.running)});
$('toggleInspector').onclick=()=>{const open=$('inspector').hidden;$('inspector').hidden=!open;$('inspector').classList.toggle('mobile-open',open);$('toggleInspector').setAttribute('aria-expanded',String(open))};
$('approve').onclick=guarded(async()=>{const answers={};for(const input of $('approvalDetails').querySelectorAll('input'))answers[input.dataset.question]=input.value;await api('/api/approval',{id:approvalId,accept:true,answers})});
$('deny').onclick=guarded(async()=>{const r=state.approvals.find(x=>String(x.id)===approvalId);if(r?.method==='item/tool/requestUserInput')await api('/api/cancel',{threadId:r.params.threadId});else await api('/api/approval',{id:approvalId,accept:false})});
$('approvalDialog').addEventListener('cancel',e=>e.preventDefault());
async function selectInspectorTab(tab){for(const other of document.querySelectorAll('[data-tab]'))other.classList.toggle('selected',other.dataset.tab===tab);for(const name of ['tools','diff','files'])$(name+'Panel').hidden=name!==tab;$('inspector').classList.toggle('wide-view',tab!=='tools');if(tab==='files')await loadFiles()}
for(const b of document.querySelectorAll('[data-tab]'))b.onclick=guarded(()=>selectInspectorTab(b.dataset.tab));
function paintFiles(){$('files').replaceChildren();const query=$('fileFilter').value.toLocaleLowerCase();for(const item of fileEntries.filter(x=>!query||x.name.toLocaleLowerCase().includes(query)).sort((a,b)=>Number(b.directory)-Number(a.directory)||a.name.localeCompare(b.name))){const b=el('button','file-entry',(item.directory?'▱ ':'· ')+item.name);b.onclick=guarded(async()=>{const next=[fileDir,item.name].filter(Boolean).join('/');if(item.directory){fileDir=next;$('fileFilter').value='';await loadFiles()}else await showFile(next)});$('files').append(b)}}
async function loadFiles(){if(!projectId)return;const project=projectId,dir=fileDir;const entries=await api('/api/files?'+new URLSearchParams({projectId:project,path:dir}));if(project!==projectId||dir!==fileDir)return;fileEntries=entries;$('filePath').textContent=fileDir||'/';paintFiles()}
async function showFile(filename){const project=projectId;const r=await api('/api/file?'+new URLSearchParams({projectId:project,path:filename}));if(project!==projectId)return;fileContents=r.text;$('filePath').textContent=r.path||filename;$('fileText').replaceChildren();const lines=r.text.split('\n');for(const [index,value] of lines.slice(0,5000).entries()){const row=el('span','code-line',value+'\n');row.dataset.line=index+1;$('fileText').append(row)}if(lines.length>5000)$('fileText').append(el('span','code-line','…仅展示前 5000 行，复制按钮可复制完整文件。'));$('copyFile').disabled=false}
$('fileFilter').oninput=paintFiles;$('rootDir').onclick=guarded(async()=>{fileDir='';$('fileFilter').value='';await loadFiles()});
$('copyFile').onclick=guarded(async()=>{await navigator.clipboard.writeText(fileContents);notify('文件内容已复制')});$('copyDiff').onclick=guarded(async()=>{await navigator.clipboard.writeText($('diffText').textContent);notify('Diff 已复制')});
$('upDir').onclick=guarded(async()=>{fileDir=fileDir.split('/').slice(0,-1).join('/');await loadFiles()});
$('shutdown').onclick=guarded(async()=>{await api('/api/shutdown',{});notify('工作台服务已停止，可以关闭此窗口。')});
function glitch(text){if(!fx||matchMedia('(prefers-reduced-motion: reduce)').matches)return;window.ProtocolFX.reconstruct(document.querySelector('.decoder'),text)}
const stream=new EventSource('/api/events');stream.onmessage=e=>{state=JSON.parse(e.data);paint()};stream.onerror=()=>{state.connection='disconnected';state.connectionError='本地连接中断，正在尝试恢复…';paint()};
// Restore the saved selection only after the first real state snapshot arrives.
const desktopBoot=new URLSearchParams(location.search).get('boot')==='interactive';
if(desktopBoot||!sessionStorage.getItem('hc-identity-admitted'))openIdentity(desktopBoot);else document.documentElement.classList.remove('boot-pending');
window.WorkbenchDev.init({getProject:()=>state.projects.find(p=>p.id===projectId),api,notify});
