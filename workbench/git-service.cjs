'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),{execFile}=require('node:child_process'),{promisify}=require('node:util');
const exec=promisify(execFile);
function cleanError(text){return String(text).replace(/https?:\/\/[^\s/]*@/gi,'https://[redacted]@').replace(/(?:gh[pousr]_[\w]+|github_pat_[\w]+)/g,'[redacted]').slice(0,1600)}
class GitService{
 constructor(){this.busy=new Set()}
 async run(cwd,args){try{return (await exec('git',['--no-pager','--literal-pathspecs',...args],{cwd,windowsHide:true,timeout:60000,maxBuffer:4*1024*1024,env:{...process.env,GIT_TERMINAL_PROMPT:'0',GCM_INTERACTIVE:'never'}})).stdout}catch(e){throw Error(cleanError(e.stderr||e.message))}}
 async root(project){const root=await fs.realpath(project.path),gitRoot=await this.run(root,['rev-parse','--show-toplevel']);if(path.relative(root,await fs.realpath(gitRoot.trim()))!=='')throw Error('请将 Git 仓库根目录添加为项目，再使用 Git 面板');return root}
 async status(project){const cwd=await this.root(project),raw=await this.run(cwd,['status','--porcelain=v1','-z','--untracked-files=normal']),parts=raw.split('\0'),files=[];
  for(let i=0;i<parts.length;i++){const p=parts[i];if(!p)continue;const x=p[0],y=p[1],name=p.slice(3),rename=x==='R'||x==='C'||y==='R'||y==='C';files.push({path:name,originalPath:rename?parts[++i]:null,index:x,worktree:y,conflict:['DD','AU','UD','UA','DU','AA','UU'].includes(x+y)})}
  const branch=(await this.run(cwd,['branch','--show-current'])).trim()||'(分离 HEAD)';const branches=(await this.run(cwd,['for-each-ref','--format=%(refname:short)','refs/heads/'])).trim().split('\n').filter(Boolean);
  const log=await this.run(cwd,['log','-8','--format=%h %s']).catch(()=> '');return {branch,branches,files,log,busy:this.busy.has(cwd)};
 }
 async file(cwd,name){if(typeof name!=='string'||!name||name.includes('\0')||path.isAbsolute(name)||name.split(/[\\/]/).some(p=>p==='..'||p==='.git'))throw Error('Git 文件路径无效');return name}
 async diff(project,input){const cwd=await this.root(project),name=await this.file(cwd,input.path);return {text:await this.run(cwd,['diff',...(input.staged?['--cached']:[]),'--no-ext-diff','--no-textconv','--',name])}}
 async mutate(project,input){const cwd=await this.root(project);if(this.busy.has(cwd))throw Error('Git 操作尚未完成，请稍候');this.busy.add(cwd);try{
  let args;switch(input.operation){
   case 'stage':args=['add','--',await this.file(cwd,input.path)];break;
   case 'unstage':{const name=await this.file(cwd,input.path),entry=(await this.status(project)).files.find(f=>f.path===name),names=[name];if(entry?.originalPath)names.push(await this.file(cwd,entry.originalPath));const head=await this.run(cwd,['rev-parse','--verify','HEAD']).catch(()=>null);args=head?['restore','--staged','--',...names]:['rm','--cached','-f','--',...names];break}
   case 'commit':if(typeof input.message!=='string'||!input.message.trim()||input.message.length>2000)throw Error('请输入提交说明（最多 2000 字）');args=['commit','-m',input.message.trim()];break;
   case 'fetch':args=['fetch'];break;case 'pull':args=['pull','--ff-only'];break;case 'push':args=['push'];break;
   case 'switch':case 'branch':if(typeof input.branch!=='string'||!input.branch||input.branch.startsWith('-')||input.branch.length>200)throw Error('分支名称无效');await this.run(cwd,['check-ref-format','--branch',input.branch]);args=['switch',...(input.operation==='branch'?['-c']:[]),input.branch];break;
   default:throw Error('不支持的 Git 操作');
  }return {output:await this.run(cwd,args)};
 }finally{this.busy.delete(cwd)}}
}
module.exports={GitService,cleanError};
