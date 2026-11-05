'use strict';
const {execFile}=require('node:child_process'),{promisify}=require('node:util'),{launchCommand}=require('./bridge.cjs');
const run=promisify(execFile);
class PluginManager{
 constructor(executable){this.executable=executable;this.catalog=new Map();this.busy=false}
 async command(args,cwd){const cmd=launchCommand(this.executable);try{const {stdout}=await run(cmd.executable,[...cmd.args,'plugin',...args],{cwd,windowsHide:true,timeout:90000,maxBuffer:20*1024*1024});return JSON.parse(stdout)}catch(e){if(e.code==='ETIMEDOUT'||e.killed)throw Error('插件操作超时，可能仍有后台处理；请刷新列表确认状态');throw Error('官方插件命令未成功。请确认 Codex CLI 支持 plugin 命令并已完成登录；需要授权的插件请在官方客户端完成连接。')}}
 async list(cwd){const result=await this.command(['list','--available','--json'],cwd),all=new Map();for(const p of [...(result.available||[]),...(result.installed||[])]){if(typeof p.pluginId!=='string'||!p.name||!p.marketplaceName)continue;all.set(p.pluginId,{id:p.pluginId,name:p.name,marketplace:p.marketplaceName,version:p.version||'',installed:!!p.installed,enabled:!!p.enabled,installPolicy:p.installPolicy||'',authPolicy:p.authPolicy||''})}this.catalog=all;return {plugins:[...all.values()].sort((a,b)=>Number(b.installed)-Number(a.installed)||a.name.localeCompare(b.name))}}
 async change(id,operation,cwd){if(this.busy)throw Error('插件操作进行中，请稍候');const p=this.catalog.get(id);if(!p)throw Error('请先刷新插件列表并选择插件');if(!['install','remove'].includes(operation))throw Error('插件操作无效');if(operation==='install'&&p.installPolicy==='NOT_AVAILABLE')throw Error('此插件不允许安装');if(operation==='remove'&&(!p.installed||p.installPolicy==='INSTALLED_BY_DEFAULT'))throw Error('此插件不可卸载');this.busy=true;
  try{const r=await this.command([operation==='install'?'add':'remove',p.name,'--marketplace',p.marketplace,'--json'],cwd);return {ok:true,needsAuth:p.authPolicy==='ON_INSTALL',message:operation==='install'?'安装命令已完成，请刷新列表确认。需要账号授权时，请在官方客户端连接。':'卸载命令已完成，请刷新列表确认。'}}finally{this.busy=false}
 }
}
module.exports={PluginManager};
