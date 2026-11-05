'use strict';
window.WorkbenchDev={init({getProject,api,notify}){
 const node=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n};
 const dialog=node('dialog',undefined,'dev-dialog'),heading=node('div',undefined,'dev-heading'),title=node('h2','项目开发工具'),close=node('button','关闭');close.onclick=()=>dialog.close();heading.append(title,close);
 const tabs=node('nav',undefined,'dev-tabs'),hint=node('p','', 'dev-hint'),body=node('section',undefined,'dev-body');dialog.append(heading,tabs,hint,body);document.body.append(dialog);
 const entry=node('button','终端 · Git · 插件');entry.id='openDevTools';document.querySelector('.session-right').append(entry);
 let project=null,active='terminal',terminal=null,fit=null,events=null,terminalId='',inputQueue=Promise.resolve(),pluginRows=[],query='',busy=false,operationNote='';
 async function call(name,data={}){return api('/api/dev/'+name,{projectId:project.id,...data})}
 function error(e){hint.textContent=e.message;hint.classList.add('dev-error')}
 function button(label,fn){const b=node('button',label);b.type='button';b.onclick=async()=>{if(busy){hint.textContent='上一步操作尚未完成，请稍候。';return}busy=true;dialog.setAttribute('aria-busy','true');b.disabled=true;hint.classList.remove('dev-error');try{await fn()}catch(e){error(e)}finally{busy=false;dialog.setAttribute('aria-busy','false');b.disabled=false}};return b}
 function detach(){events?.close();events=null;terminal?.dispose();terminal=null;fit=null;terminalId=''}
 function measure(){if(!terminal||!fit||!dialog.open||active!=='terminal')return;try{fit.fit();call('terminal-resize',{id:terminalId,cols:terminal.cols,rows:terminal.rows}).catch(error)}catch{}}
 const observer=new ResizeObserver(()=>measure());observer.observe(body);dialog.addEventListener('close',detach);
 async function attach(id,container){detach();terminalId=id;const nonce=document.querySelector('meta[name="terminal-style-nonce"]').content;
  const terminalDocument=new Proxy(document,{get(target,key){if(key==='createElement')return(tag,...rest)=>{const element=target.createElement(tag,...rest);if(tag==='style')element.nonce=nonce;return element};const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value}});
  terminal=new window.Terminal({documentOverride:terminalDocument,cursorBlink:true,scrollback:5000,fontSize:13,fontFamily:'Menlo, Monaco, Consolas, monospace',theme:{background:'#090b0c',foreground:'#e8e0d1',cursor:'#f06a22',selectionBackground:'#81352d'}});fit=new window.FitAddon.FitAddon();terminal.loadAddon(fit);terminal.open(container);fit.fit();
  terminal.onData(data=>{const selectedId=id;inputQueue=inputQueue.then(()=>call('terminal-input',{id:selectedId,data})).catch(error)});
  events=new EventSource('/api/dev/terminal-events?'+new URLSearchParams({id}));const current=terminal;
  events.onmessage=e=>{const v=JSON.parse(e.data);if(v.reset)current.reset();current.write(v.data)};events.addEventListener('ended',e=>current.writeln('\r\n[终端已退出：'+JSON.parse(e.data).exitCode+']'));
  events.onerror=()=>{hint.textContent='终端连接中断，正在重连。若服务已关闭，请重新打开工作台。'};measure();terminal.focus();
 }
 async function terminals(preferred){detach();body.replaceChildren();hint.textContent='终端直接操作本机，以当前项目为初始目录；聊天的只读设置不限制你手动输入的命令。';const toolbar=node('div',undefined,'dev-toolbar'),select=node('select'),screen=node('div',undefined,'dev-terminal');screen.id='devTerminalScreen';body.append(toolbar,screen);
  const r=await call('terminal-list');for(const s of r.terminals){const o=node('option',s.title+(s.exitCode!==null?' · 已退出':''));o.value=s.id;select.append(o)}
  const id=r.terminals.find(s=>s.id===preferred)?.id||r.terminals[0]?.id;if(id)select.value=id;
  toolbar.append(select,button('新建终端',async()=>{const s=await call('terminal-create');await terminals(s.id)}),button('结束所选终端',async()=>{if(!select.value)return;if(!confirm('结束此终端及其运行中的命令？'))return;await call('terminal-close',{id:select.value});await terminals()}));
  select.onchange=()=>attach(select.value,screen).catch(error);if(id)await attach(id,screen);else screen.append(node('p','点击“新建终端”开始。关闭面板后终端仍会运行；退出工作台服务时会结束。','dev-empty'));
 }
 async function git(){detach();body.replaceChildren();hint.textContent='仅操作当前项目仓库；提交只包含已暂存的变更。拉取使用快进模式，不自动合并。';const r=await call('git-status'),toolbar=node('div',undefined,'dev-toolbar'),branches=node('select');for(const name of r.branches){const o=node('option',name);o.value=name;branches.append(o)}branches.value=r.branch;
  const refresh=button('刷新',git);toolbar.append(node('strong',r.branch),refresh,branches,button('切换分支',async()=>{if(!branches.value||!confirm('切换到 '+branches.value+'？Git 会检查本地未提交变更。'))return;await call('git-action',{operation:'switch',branch:branches.value});await git()}),button('新建分支',async()=>{const name=prompt('新分支名称');if(!name)return;await call('git-action',{operation:'branch',branch:name});await git()}));
  for(const [op,label]of [['fetch','获取远端'],['pull','拉取'],['push','推送']])toolbar.append(button(label,async()=>{if(!confirm('对当前仓库执行“'+label+'”？'))return;const result=await call('git-action',{operation:op});operationNote=result.output||label+'完成';await git()}));body.append(toolbar);
  if(operationNote)body.append(node('pre',operationNote,'dev-output'));
  const files=node('div',undefined,'dev-git-files'),diff=node('pre','选择文件查看差异。','dev-output dev-diff');diff.id='devGitDiff';for(const f of r.files){const row=node('div',undefined,'dev-file-row');row.append(node('code',f.index+f.worktree),node('span',f.path+(f.conflict?' · 冲突':'')));
   row.append(button('工作区差异',async()=>{diff.textContent=(await call('git-diff',{path:f.path,staged:false})).text||'没有文本差异（新文件、二进制文件或仅暂存变更）。'}));
   if(f.index!==' '&&f.index!=='?')row.append(button('暂存区差异',async()=>{diff.textContent=(await call('git-diff',{path:f.path,staged:true})).text||'没有文本差异。'}),button('取消暂存',async()=>{await call('git-action',{operation:'unstage',path:f.path});await git()}));
   if(f.worktree!==' '||f.index==='?')row.append(button('暂存',async()=>{await call('git-action',{operation:'stage',path:f.path});await git()}));files.append(row)}
  if(!r.files.length)files.append(node('p','工作区干净。'));const commit=node('div',undefined,'dev-toolbar'),message=node('input');message.placeholder='提交说明（只提交已暂存文件）';message.id='devCommitMessage';commit.append(message,button('提交暂存内容',async()=>{if(!message.value.trim())throw Error('请输入提交说明');if(!confirm('使用这条说明提交已暂存的内容？\n'+message.value))return;const result=await call('git-action',{operation:'commit',message:message.value});operationNote=result.output;await git()}));body.append(files,commit,diff,node('pre',r.log||'尚无提交记录','dev-output'));
 }
 async function plugins(refresh=true){detach();body.replaceChildren();hint.textContent='管理本机 Codex CLI 的插件，不保证与 ChatGPT 桌面插件同步。安装后在新建 Codex 对话中使用；账号连接请在官方客户端完成。';if(refresh)pluginRows=(await call('plugins-list')).plugins;
  const search=node('input'),toolbar=node('div',undefined,'dev-toolbar'),list=node('div');search.placeholder='搜索插件名称或市场';search.value=query;search.id='devPluginSearch';toolbar.append(search,button('刷新插件',()=>plugins(true)));body.append(toolbar,list);
  function render(){list.replaceChildren();const matches=pluginRows.filter(p=>(p.name+' '+p.marketplace).toLowerCase().includes(query.toLowerCase()));list.append(node('p','共 '+matches.length+' 个匹配项，显示前 100 个；可输入名称缩小范围。'));for(const p of matches.slice(0,100)){const row=node('article',undefined,'dev-plugin');row.append(node('strong',p.name),node('small',p.marketplace+' · '+p.version),node('p',p.installed?(p.enabled?'已安装 · 已启用':'已安装 · 未启用'):'未安装'));
    const action=button(p.installed?'卸载':'安装',async()=>{if(!confirm((p.installed?'卸载':'安装')+' '+p.name+'？\n市场：'+p.marketplace+'\n这会修改本机 Codex CLI 插件配置。'))return;const result=await call('plugins-change',{id:p.id,operation:p.installed?'remove':'install'});operationNote=result.message;await plugins(true);hint.textContent=result.message});action.disabled=p.installed?p.installPolicy==='INSTALLED_BY_DEFAULT':p.installPolicy==='NOT_AVAILABLE';row.append(action);list.append(row)}}search.oninput=()=>{query=search.value;render()};render();
 }
 async function show(name){active=name;for(const b of tabs.children)b.classList.toggle('selected',b.dataset.name===name);hint.classList.remove('dev-error');body.replaceChildren(node('p','正在加载…'));if(name==='terminal')await terminals();else if(name==='git')await git();else await plugins()}
 for(const [name,label]of [['terminal','终端'],['git','Git'],['plugins','插件']]){const b=button(label,()=>show(name));b.dataset.name=name;tabs.append(b)}
 entry.onclick=async()=>{if(busy)return;const p=getProject();if(!p){notify('请先添加或选择一个本地项目');return}project=p;operationNote='';title.textContent=p.name+' / 开发工具';dialog.showModal();try{await show(active)}catch(e){error(e)}};
}};
