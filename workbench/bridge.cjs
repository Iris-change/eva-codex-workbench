'use strict';
const {spawn}=require('node:child_process');
const {EventEmitter}=require('node:events');
const readline=require('node:readline');
const fs=require('node:fs');
const path=require('node:path');

function launchCommand(executable){
  if(!/\.(?:ps1|cmd|bat)$/i.test(executable))return {executable,args:[]};
  // npm shims cannot be spawned directly on Windows. Run the official JS entry without a shell.
  const entry=path.join(path.dirname(executable),'node_modules','@openai','codex','bin','codex.js');
  if(!fs.existsSync(entry))throw Error('无法启动 Codex：检测到命令脚本，但未找到官方 npm 入口。请重新安装 @openai/codex 后重启工作台。');
  return {executable:process.execPath,args:[entry]};
}

class CodexBridge extends EventEmitter {
  constructor(executable='codex.exe',spawnProcess=spawn) {super();this.executable=executable;this.spawnProcess=spawnProcess;this.pending=new Map();this.nextId=1;this.connected=false;}
  async start(){
    if(this.child)throw Error('Bridge already started');
    const command=launchCommand(this.executable);
    const child=this.spawnProcess(command.executable,[...command.args,'app-server','--listen','stdio://','-c','analytics.enabled=false'],{stdio:['pipe','pipe','pipe'],windowsHide:true});this.child=child;
    const failed=error=>{if(this.child===child)this.fail(error)};
    child.on('error',failed);
    child.stdin.on('error',failed);
    child.on('exit',code=>failed(Error('Codex process exited ('+code+')')));
    // Stderr is intentionally not forwarded: startup logs may include private account details.
    child.stderr.resume();
    this.lines=readline.createInterface({input:child.stdout});
    this.lines.on('line',line=>{if(this.child!==child)return;try{this.receive(JSON.parse(line))}catch(e){this.emit('diagnostic','Invalid app-server message: '+e.message)}});
    await this.request('initialize',{clientInfo:{name:'eva_unit02_workbench',title:'EVA Unit-02 Workbench',version:'0.2.0'},capabilities:{experimentalApi:false}},60000);
    if(this.child!==child)throw Error('Codex initialization interrupted');
    this.send({method:'initialized',params:{}});this.connected=true;
  }
  receive(msg){
    if(msg.id!==undefined&&!msg.method){const p=this.pending.get(msg.id);if(!p)return;this.pending.delete(msg.id);clearTimeout(p.timer);msg.error?p.reject(Error(msg.error.message)):p.resolve(msg.result);return;}
    if(msg.id!==undefined&&msg.method)this.emit('approval',msg);
    else if(msg.method)this.emit('notification',msg);
  }
  send(msg){if(!this.child||this.child.killed||!this.child.stdin.writable)throw Error('Codex is disconnected');this.child.stdin.write(JSON.stringify(msg)+'\n');}
  request(method,params={},timeout=60000){return new Promise((resolve,reject)=>{const id=this.nextId++;const timer=setTimeout(()=>{this.pending.delete(id);reject(Error(method+' timed out; operation may still be running'))},timeout);this.pending.set(id,{resolve,reject,timer});try{this.send({id,method,params})}catch(e){clearTimeout(timer);this.pending.delete(id);reject(e)}})}
  respond(id,result){this.send({id,result})}
  fail(error){this.stop(error);this.emit('disconnected',error.message)}
  stop(error=Error('Codex connection stopped')){
    const child=this.child;this.child=null;this.connected=false;this.lines?.close();this.lines=null;
    for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(error)}this.pending.clear();
    child?.stdin.end();if(child&&!child.killed)child.kill();
  }
}
module.exports={CodexBridge,launchCommand};
