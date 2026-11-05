'use strict';
const crypto=require('node:crypto'),path=require('node:path'),fs=require('node:fs');
class TerminalManager{
 constructor({spawn}={}){this.spawn=spawn;this.sessions=new Map()}
 list(projectId){return [...this.sessions.values()].filter(s=>s.projectId===projectId).map(({id,projectId,title,exitCode})=>({id,projectId,title,exitCode}))}
 get(id){const s=this.sessions.get(id);if(!s)throw Error('终端已关闭，请新建终端');return s}
 create(project){if(this.sessions.size>=8)throw Error('最多同时打开 8 个终端，请先关闭不用的终端');
  let spawn=this.spawn;try{spawn||=require('node-pty').spawn}catch{throw Error('缺少终端依赖，请在 workbench 目录运行 npm ci')}
  const modernShell=(process.env.PATH||'').split(path.delimiter).map(dir=>path.join(dir,'pwsh.exe')).find(file=>fs.existsSync(file));
  const shell=process.platform==='win32'?(modernShell||path.join(process.env.SystemRoot||'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe')):'/bin/bash';
  const env={...process.env};delete env.HACKCLAW_CODEX;delete env.HACKCLAW_DATA_DIR;delete env.EVA_LAUNCH_READY;
  if(process.platform==='win32'&&!modernShell&&env.PSModulePath)env.PSModulePath=env.PSModulePath.split(';').filter(dir=>!/PowerShell[\\/]7[\\/]Modules[\\/]?$/i.test(dir)).join(';');
  const child=spawn(shell,process.platform==='win32'?['-NoLogo','-NoProfile']:['--noprofile','--norc'],{name:'xterm-256color',cols:100,rows:24,cwd:project.path,env});
  const s={id:crypto.randomUUID(),projectId:project.id,title:'PowerShell '+(this.sessions.size+1),exitCode:null,child,buffer:'',sequence:0,chunks:[],clients:new Set()};this.sessions.set(s.id,s);
  child.onData(data=>{s.buffer=(s.buffer+data).slice(-512*1024);const event={seq:++s.sequence,data};s.chunks.push(event);while(s.chunks.length>1500)s.chunks.shift();for(const c of s.clients){if(c.writableLength>1024*1024){c.end();s.clients.delete(c)}else c.write('id: '+event.seq+'\ndata: '+JSON.stringify(event)+'\n\n')}});
  child.onExit(({exitCode})=>{s.exitCode=exitCode;for(const c of s.clients)c.write('event: ended\ndata: '+JSON.stringify({exitCode})+'\n\n')});return {id:s.id,projectId:s.projectId,title:s.title,exitCode:s.exitCode};
 }
 input(id,data){const s=this.get(id);if(s.exitCode!==null)throw Error('终端进程已经退出');if(typeof data!=='string'||data.length>16384)throw Error('终端输入过长');s.child.write(data)}
 resize(id,cols,rows){if(!Number.isInteger(cols)||cols<2||cols>500||!Number.isInteger(rows)||rows<2||rows>200)throw Error('终端尺寸无效');const s=this.get(id);if(s.exitCode===null)s.child.resize(cols,rows)}
 subscribe(id,res,lastId){const s=this.get(id);res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-store','Connection':'keep-alive'});
  const last=Number(lastId);if(lastId&&Number.isInteger(last)&&last>=s.chunks[0]?.seq-1){for(const e of s.chunks)if(e.seq>last)res.write('id: '+e.seq+'\ndata: '+JSON.stringify(e)+'\n\n')}
  else res.write('id: '+s.sequence+'\ndata: '+JSON.stringify({reset:true,seq:s.sequence,data:s.buffer})+'\n\n');
  if(s.exitCode!==null)res.write('event: ended\ndata: '+JSON.stringify({exitCode:s.exitCode})+'\n\n');
  s.clients.add(res);const ping=setInterval(()=>res.write(': ping\n\n'),15000);res.on('close',()=>{s.clients.delete(res);clearInterval(ping)});
 }
 close(id){const s=this.get(id);this.sessions.delete(id);if(s.exitCode===null)s.child.kill();for(const c of s.clients)c.end()}
 stop(){for(const id of [...this.sessions.keys()])this.close(id)}
}
module.exports={TerminalManager};
