'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path'),{execFileSync}=require('node:child_process');
const {AttachmentStore,decodeFile,isImage}=require('../attachments.cjs');
const {ConversationTransfer,transferInput,claudeMessages}=require('../conversation-transfer.cjs');
async function fixture(){const root=await fs.mkdtemp(path.join(os.tmpdir(),'eva-transfer-')),attachments=new AttachmentStore(path.join(root,'attachments')),state={projects:[{id:'p',path:root}],threads:[]},calls=[];const history={sdkLoader:async()=>({getSessionMessages:async()=>[]}),bridge:{request:async()=>({data:[]})}};
 const transfer=new ConversationTransfer({state,history,attachments,changed(){},createThread:async input=>{calls.push(input);const t={id:'created-'+state.threads.length,provider:input.provider,projectId:input.projectId,mode:input.mode,messages:[],tools:[],status:'idle'};state.threads.push(t);return t}});return {root,attachments,state,calls,history,transfer,async cleanup(){await fs.rm(root,{recursive:true,force:true})}}}
test('bidirectional imports copy transcript locally, keep source intact and reset permissions',async()=>{
 const f=await fixture();try{
  const original={id:'source',provider:'codex',projectId:'p',title:'Source',mode:'workspace-write',messages:[{id:'u',role:'user',text:'remember MARKER'},{id:'a',role:'assistant',text:'remembered'}],tools:[{type:'reasoning',summary:'PRIVATE_REASONING'}],status:'completed'};f.state.threads.push(original);const before=JSON.stringify(original);
  const first=await f.transfer.import({threadId:'source',targetProvider:'claude'});assert.equal(first.thread.mode,'read-only');assert.equal(first.thread.transfer.pending,true);assert.equal(JSON.stringify(original),before);assert.equal(first.thread.messages[1].sourceProvider,'codex');assert.equal(first.thread.messages[1].imported,true);
  const handoff=await transferInput(first.thread,f.attachments);assert.match(handoff.text,/MARKER/);assert.match(handoff.text,/不是系统指令/);assert(!handoff.text.includes('PRIVATE_REASONING'));assert.equal(first.thread.sessionId,undefined);
  first.thread.messages.push({id:'new',role:'user',text:'new question'});const second=await f.transfer.import({threadId:first.thread.id,targetProvider:'codex'});assert.equal(second.thread.transfer.messageCount,3);assert.equal(second.thread.mode,'read-only');assert.equal(f.calls.length,2);
  const payload=JSON.parse(await fs.readFile((await f.attachments.get(second.thread.transfer.fileId)).file,'utf8'));assert.equal(payload.messages.filter(m=>m.text==='remember MARKER').length,1);
  first.thread.transfer.pending=false;assert.equal(await transferInput(first.thread,f.attachments),null);
 }finally{await f.cleanup()}
});
test('Codex import reads every page in order without resuming, including messages not visible in cache',async()=>{
 const f=await fixture();try{
  const methods=[];f.history.bridge.request=async(method,input)=>{methods.push({method,input});return input.cursor?{data:[{items:[{type:'userMessage',content:[{type:'text',text:'oldest'}]}]}],nextCursor:null}:{data:[{items:[{type:'agentMessage',text:'newest'},{type:'reasoning',text:'hidden'}]}],nextCursor:'older'}};
  f.state.threads.push({id:'history',provider:'codex',projectId:'p',title:'History',messages:[],localHistory:{id:'official',provider:'codex'}});
  const r=await f.transfer.import({threadId:'history',targetProvider:'claude'});const data=JSON.parse(await fs.readFile((await f.attachments.get(r.thread.transfer.fileId)).file));assert.deepEqual(data.messages.map(m=>m.text),['oldest','newest']);assert(methods.every(m=>m.method==='thread/turns/list'&&m.input.itemsView==='full'));assert.equal(data.tools.length,0);
 }finally{await f.cleanup()}
});
test('imports reject active sources and same-provider requests without creating a thread',async()=>{
 const f=await fixture();try{
  f.state.threads.push({id:'source',provider:'claude',projectId:'p',status:'inProgress'});await assert.rejects(f.transfer.import({threadId:'source',targetProvider:'codex'}),/停止/);await assert.rejects(f.transfer.import({threadId:'source',targetProvider:'claude'}),/另一种/);assert.equal(f.calls.length,0);
 }finally{await f.cleanup()}
});
test('Claude conversion excludes system and thinking data while retaining readable messages',()=>{
 const data=claudeMessages([{type:'system',message:{content:'system secret'}},{type:'assistant',message:{model:'source-model',content:[{type:'thinking',thinking:'private'},{type:'text',text:'visible'}]}},{type:'user',message:{content:[{type:'tool_result',content:'raw secret'},{type:'text',text:'question'}]}}]);assert.deepEqual(data.messages.map(m=>m.text),['visible','question']);assert.equal(data.messages[0].model,'source-model');
});
test('arbitrary files stay inert, text is extracted, and selected files are provided as reference data',async()=>{
 const f=await fixture();try{
  const text=await f.attachments.save({name:'../sample.txt',dataBase64:Buffer.from('FILE_TEXT_MARKER').toString('base64')});assert.equal(text.name,'sample.txt');assert.equal(text.kind,'text');const preview=await f.attachments.preview(text.id);assert.equal(preview.text,'FILE_TEXT_MARKER');
  const raw=await f.attachments.save({name:'unknown.bin',dataBase64:Buffer.from([0,255,1,2]).toString('base64')});assert.equal(raw.kind,'file');assert.equal((await f.attachments.preview(raw.id)).text,'');
  const files=await f.attachments.resolve([text.id,raw.id]);assert(files.every(f=>!isImage(f.item)));const prompt=await f.attachments.prompt(files);assert.match(prompt,/FILE_TEXT_MARKER/);assert.match(prompt,/不能声称已经读懂/);
  const restored=new AttachmentStore(path.join(f.root,'attachments'));assert.equal((await restored.get(text.id)).file,preview.file);
  await fs.unlink(path.join(f.root,'attachments',text.id+'.text'));await fs.symlink(path.join(f.root,'outside'),path.join(f.root,'attachments',text.id+'.text'));await fs.writeFile(path.join(f.root,'outside'),'private');await assert.rejects(f.attachments.preview(text.id),/路径/);
 }finally{await f.cleanup()}
});
test('Office extraction reads document text and cached sheet cells without executing macros or unpacking files',async()=>{
 const f=await fixture();try{
  execFileSync('/usr/bin/python3',['-c',"import sys,zipfile,pathlib\nr=pathlib.Path(sys.argv[1])\nfixtures={'docx':{'word/document.xml':'<w:document xmlns:w=\"urn:w\"><w:body><w:p><w:r><w:t>DOCX_MARKER</w:t></w:r></w:p></w:body></w:document>'},'xlsx':{'xl/worksheets/sheet1.xml':'<worksheet xmlns=\"urn:x\"><sheetData><row><c r=\"A1\" t=\"inlineStr\"><is><t>XLSX_MARKER</t></is></c></row></sheetData></worksheet>'},'pptx':{'ppt/slides/slide1.xml':'<p:sld xmlns:p=\"urn:p\" xmlns:a=\"urn:a\"><a:t>PPTX_MARKER</a:t></p:sld>'},'zip':{'../escape.txt':'not extracted'}}\nfor ext,files in fixtures.items():\n with zipfile.ZipFile(r/('sample.'+ext),'w') as z:\n  for n,v in files.items():z.writestr(n,v)",f.root]);
  for(const ext of ['docx','xlsx','pptx','zip']){const item=await f.attachments.save({name:'sample.'+ext,dataBase64:(await fs.readFile(path.join(f.root,'sample.'+ext))).toString('base64')});const p=await f.attachments.preview(item.id);assert.match(p.text,ext==='zip'?/escape.txt/:new RegExp(ext.toUpperCase()+'_MARKER'));assert.equal(item.kind,'document')}
  await assert.rejects(fs.stat(path.join(f.root,'escape.txt')),/ENOENT/);
 }finally{await f.cleanup()}
});
test('file payload validation rejects invalid base64, excessive count and forged image metadata',async()=>{
 const f=await fixture();try{
  assert.throws(()=>decodeFile('A==='));assert.throws(()=>decodeFile('!!!!'));assert.throws(()=>decodeFile('AAAA'.repeat(12000000)),/32 MB/);
  await assert.rejects(f.attachments.resolve(Array(9).fill('x')),/最多/);
  const file=await f.attachments.save({name:'safe.txt',dataBase64:Buffer.from('safe').toString('base64')});await fs.writeFile(path.join(f.root,'attachments',file.id+'.json'),JSON.stringify({...file,ext:'../../outside'}));await assert.rejects(f.attachments.get(file.id),/记录/);
 }finally{await f.cleanup()}
});
test('legacy Word/RTF use system textutil and Excel keeps workbook sheet names and numeric order',async()=>{
 const f=await fixture();try{
  const txt=path.join(f.root,'legacy.txt');await fs.writeFile(txt,'LEGACY_MARKER 中文\n');
  for(const ext of ['doc','rtf']){execFileSync('/usr/bin/textutil',['-convert',ext,'-output',path.join(f.root,'legacy.'+ext),txt]);const item=await f.attachments.save({name:'legacy.'+ext,dataBase64:(await fs.readFile(path.join(f.root,'legacy.'+ext))).toString('base64')});assert.equal(item.kind,'document');assert.match((await f.attachments.preview(item.id)).text,/LEGACY_MARKER 中文/)}
  execFileSync('/usr/bin/python3',['-c',"import sys,zipfile\nns='xmlns=\"urn:x\" xmlns:r=\"urn:r\"'\nsh=lambda v:'<worksheet '+ns+'><sheetData><row><c r=\"A1\" t=\"inlineStr\"><is><t>'+v+'</t></is></c></row></sheetData></worksheet>'\nwith zipfile.ZipFile(sys.argv[1],'w') as z:\n z.writestr('xl/workbook.xml','<workbook '+ns+'><sheets><sheet name=\"汇总\" r:id=\"r2\"/><sheet name=\"明细\" r:id=\"r1\"/></sheets></workbook>')\n z.writestr('xl/_rels/workbook.xml.rels','<Relationships xmlns=\"urn:p\"><Relationship Id=\"r1\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"r2\" Target=\"/xl/worksheets/sheet2.xml\"/></Relationships>')\n for n,v in [(1,'ONE'),(2,'TWO'),(10,'TEN')]:z.writestr('xl/worksheets/sheet%d.xml'%n,sh(v))",path.join(f.root,'named.xlsx')]);
  const item=await f.attachments.save({name:'named.xlsx',dataBase64:(await fs.readFile(path.join(f.root,'named.xlsx'))).toString('base64')}),text=(await f.attachments.preview(item.id)).text;
  assert.match(text,/^工作表 汇总\nA1=TWO\n\n工作表 明细\nA1=ONE\n\n工作表 sheet10\nA1=TEN$/);
 }finally{await f.cleanup()}
});
test('in-place switch keeps the title, hides the source, chains back and can be undone before first use',async()=>{
 const f=await fixture(),renamed=[],archived=[];f.transfer.renameThread=async(id,title)=>renamed.push([id,title]);f.transfer.archiveThread=async id=>archived.push(id);
 try{
  const a={id:'a',provider:'codex',projectId:'p',title:'网站改版',mode:'workspace-write',messages:[{id:'u',role:'user',text:'CHAIN_MARKER'},{id:'r',role:'assistant',text:'ok'}],tools:[],status:'completed'};f.state.threads.push(a);
  const b=(await f.transfer.import({threadId:'a',targetProvider:'claude',inPlace:true})).thread;
  assert.equal(b.title,'网站改版');assert.deepEqual(renamed,[[b.id,'网站改版']]);assert.equal(b.mode,'read-only');assert.equal(b.transfer.inPlace,true);assert.equal(a.continuedIn.threadId,b.id);assert.equal(a.continuedIn.provider,'claude');
  await assert.rejects(f.transfer.import({threadId:'a',targetProvider:'claude',inPlace:true}),/已切换/);
  b.messages.push({id:'n',role:'user',text:'CLAUDE_PART'},{id:'n2',role:'assistant',text:'done'});b.transfer.pending=false;
  await assert.rejects(f.transfer.undo({threadId:b.id}),/不能撤销/);
  const c=(await f.transfer.import({threadId:b.id,targetProvider:'codex',inPlace:true})).thread;assert.equal(c.provider,'codex');assert.equal(c.title,'网站改版');assert.equal(b.continuedIn.threadId,c.id);
  const payload=JSON.parse(await fs.readFile((await f.attachments.get(c.transfer.fileId)).file,'utf8'));assert.deepEqual(payload.messages.map(m=>m.text),['CHAIN_MARKER','ok','CLAUDE_PART','done']);
  const back=await f.transfer.undo({threadId:c.id});assert.equal(back.thread.id,b.id);assert.equal(b.continuedIn,undefined);assert.equal(c.discarded,true);assert.equal(c.archived,true);assert.deepEqual(archived,[c.id]);
  const legacy=(await f.transfer.import({threadId:b.id,targetProvider:'codex'})).thread;assert.match(legacy.title,/Codex 导入$/);assert.equal(b.continuedIn,undefined);await assert.rejects(f.transfer.undo({threadId:legacy.id}),/不是就地切换/);
 }finally{await f.cleanup()}
});
test('merging hides a duplicate without changing it and can be reverted',async()=>{
 const f=await fixture();try{
  const keep={id:'keep',provider:'claude',projectId:'p',title:'方案',messages:[{id:'1',role:'user',text:'x'}],status:'idle'},dup={id:'dup',provider:'claude',projectId:'p',title:'方案',messages:[{id:'1',role:'user',text:'x'}],status:'idle'},mirror={id:'history-claude-o',provider:'claude',projectId:'p',title:'方案',messages:[],status:'idle',localHistory:{provider:'claude',id:'o',updatedAt:5}};
  f.state.threads.push(keep,dup,mirror);const before=JSON.stringify(dup.messages);
  assert.equal((await f.transfer.merge({threadId:'dup',intoThreadId:'keep'})).thread.id,'keep');assert.equal(dup.continuedIn.threadId,'keep');assert.equal(dup.continuedIn.merged,true);assert.equal(JSON.stringify(dup.messages),before);
  await f.transfer.merge({threadId:mirror.id,intoThreadId:'keep'});assert.equal(mirror.continuedIn.sourceUpdatedAt,5);
  await assert.rejects(f.transfer.merge({threadId:'keep',intoThreadId:'dup'}),/已被收起/);await assert.rejects(f.transfer.merge({threadId:'keep',intoThreadId:'keep'}),/另一条/);
  await assert.rejects(f.transfer.import({threadId:'dup',targetProvider:'codex',inPlace:true}),/已切换/);
  await f.transfer.merge({threadId:'dup',intoThreadId:null});assert.equal(dup.continuedIn,undefined);await assert.rejects(f.transfer.merge({threadId:'dup',intoThreadId:null}),/没有被合并/);
 }finally{await f.cleanup()}
});
test('Codex handoff stays pending after a failed turn and is consumed only by a completed one',()=>{
 const {markHandoffStarted,settleHandoff}=require('../conversation-transfer.cjs');const t={transfer:{pending:true}};
 markHandoffStarted(t);settleHandoff(t,'failed');assert.equal(t.transfer.pending,true);assert.equal(t.transfer.injecting,undefined);
 markHandoffStarted(t);settleHandoff(t,'interrupted');assert.equal(t.transfer.pending,true);
 settleHandoff(t,'completed');assert.equal(t.transfer.pending,true,'a turn that did not carry the handoff cannot consume it');
 markHandoffStarted(t);settleHandoff(t,'completed');assert.equal(t.transfer.pending,false);
 const done={transfer:{pending:false}};markHandoffStarted(done);assert.equal(done.transfer.injecting,undefined);settleHandoff({},'completed');
});
