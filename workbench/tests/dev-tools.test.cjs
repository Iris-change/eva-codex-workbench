'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),{execFileSync}=require('node:child_process');
const {GitService}=require('../git-service.cjs'),{TerminalManager}=require('../terminal.cjs'),{PluginManager}=require('../plugins.cjs');
test('real Git operations preserve unstaged changes, support commits and branches, and reject unsafe paths',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'eva-git-')),p={id:'test',path:root},git=new GitService();
 try{
  execFileSync('git',['init'],{cwd:root,stdio:'ignore'});execFileSync('git',['config','user.name','EVA Test'],{cwd:root});execFileSync('git',['config','user.email','test@example.invalid'],{cwd:root});
  fs.writeFileSync(path.join(root,'a file.txt'),'first\n');let s=await git.status(p);assert.equal(s.files[0].index,'?');
  await git.mutate(p,{operation:'stage',path:'a file.txt'});await git.mutate(p,{operation:'unstage',path:'a file.txt'});assert(fs.existsSync(path.join(root,'a file.txt')));
  await git.mutate(p,{operation:'stage',path:'a file.txt'});assert((await git.diff(p,{path:'a file.txt',staged:true})).text.includes('+first'));
  fs.appendFileSync(path.join(root,'a file.txt'),'second\n');await git.mutate(p,{operation:'commit',message:'first commit'});
  assert((await git.diff(p,{path:'a file.txt'})).text.includes('+second'));await git.mutate(p,{operation:'branch',branch:'feature/test'});assert.equal((await git.status(p)).branch,'feature/test');
  await assert.rejects(()=>git.diff(p,{path:'../outside'}),/路径/);await assert.rejects(()=>git.mutate(p,{operation:'switch',branch:'--orphan'}),/分支/);
  const sub=path.join(root,'sub');fs.mkdirSync(sub);await assert.rejects(()=>git.status({id:'sub',path:sub}),/根目录/);
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
test('terminal validates input and sizes, owns multiple sessions and kills them on shutdown',()=>{
 const children=[];const manager=new TerminalManager({spawn(){const child={killed:false,onData(fn){this.data=fn},onExit(fn){this.exit=fn},write(value){this.last=value},resize(cols,rows){this.size=[cols,rows]},kill(){this.killed=true}};children.push(child);return child}});
 const a=manager.create({id:'p',path:process.cwd()}),b=manager.create({id:'q',path:process.cwd()});assert.equal(manager.list('p').length,1);manager.input(a.id,'echo test\r');assert.equal(children[0].last,'echo test\r');
 assert.throws(()=>manager.resize(a.id,0,24),/尺寸/);assert.throws(()=>manager.input(a.id,'a'.repeat(17000)),/过长/);manager.resize(a.id,120,30);assert.deepEqual(children[0].size,[120,30]);manager.close(a.id);assert(children[0].killed);manager.stop();assert(children[1].killed);assert.throws(()=>manager.get(b.id),/关闭/);
});
test('Git fetch, fast-forward pull and push operate on an isolated local remote',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'eva-git-remote-')),remote=path.join(root,'remote.git'),work=path.join(root,'work'),other=path.join(root,'other'),git=new GitService();
 const command=(cwd,args)=>execFileSync('git',args,{cwd,encoding:'utf8',stdio:['ignore','pipe','pipe']});
 try{
  command(root,['init','--bare',remote]);command(root,['clone',remote,work]);for(const dir of [work]){command(dir,['config','user.name','EVA Test']);command(dir,['config','user.email','test@example.invalid'])}
  fs.writeFileSync(path.join(work,'sample.txt'),'one\n');command(work,['add','.']);command(work,['commit','-m','initial']);command(work,['push','-u','origin','HEAD']);
  command(root,['clone',remote,other]);command(other,['config','user.name','EVA Test']);command(other,['config','user.email','test@example.invalid']);fs.appendFileSync(path.join(other,'sample.txt'),'two\n');command(other,['commit','-am','remote change']);command(other,['push']);
  await git.mutate({path:work},{operation:'fetch'});await git.mutate({path:work},{operation:'pull'});assert(fs.readFileSync(path.join(work,'sample.txt'),'utf8').includes('two'));
  fs.appendFileSync(path.join(work,'sample.txt'),'three\n');await git.mutate({path:work},{operation:'stage',path:'sample.txt'});await git.mutate({path:work},{operation:'commit',message:'local change'});await git.mutate({path:work},{operation:'push'});
  assert.equal(command(remote,['log','-1','--format=%s']).trim(),'local change');
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
test('plugin operations only accept catalog selections and use explicit official command arguments',async()=>{
 const manager=new PluginManager('codex.exe'),calls=[];
 manager.command=async args=>{calls.push(args);if(args[0]==='list')return {installed:[],available:[{pluginId:'sample@local',name:'sample',marketplaceName:'local',installed:false,enabled:false,installPolicy:'AVAILABLE',authPolicy:'ON_USE'}]};return {}};
 await assert.rejects(()=>manager.change('unknown','install',process.cwd()),/刷新/);await manager.list(process.cwd());await manager.change('sample@local','install',process.cwd());assert.deepEqual(calls[1],['add','sample','--marketplace','local','--json']);await assert.rejects(()=>manager.change('sample@local','remove',process.cwd()),/卸载/);
});
