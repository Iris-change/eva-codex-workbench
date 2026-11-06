'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {AttachmentStore,decodeImage}=require('../attachments.cjs');const {normalizeModel,turnOptions}=require('../model-options.cjs');
const {reduceEvent}=require('../state.cjs');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6ksAAAAASUVORK5CYII=','base64');
test('image uploads reject active content, MIME spoofing, huge dimensions and traversal ids',async()=>{
 assert.throws(()=>decodeImage('data:image/svg+xml;base64,PHN2Zz4='));
 assert.throws(()=>decodeImage('data:image/jpeg;base64,'+png.toString('base64')),/格式/);
 const huge=Buffer.from(png);huge.writeUInt32BE(20000,16);assert.throws(()=>decodeImage('data:image/png;base64,'+huge.toString('base64')),/尺寸/);
 const store=new AttachmentStore(path.join(__dirname,'sandbox','image-policy'));await assert.rejects(store.get('../auth.json'),/编号/);
 await assert.rejects(store.resolve(Array(9).fill('bad')),/最多/);
});
test('image metadata and attachment paths survive a store restart without trusting the filename',async()=>{
 const sandbox=path.join(__dirname,'sandbox');await fs.mkdir(sandbox,{recursive:true});const root=await fs.mkdtemp(path.join(sandbox,'attachments-'));
 const store=new AttachmentStore(root),item=await store.save({name:'..\\outside.png',dataUrl:'data:image/png;base64,'+png.toString('base64')});
 assert.equal(item.name,'outside.png');assert.equal(item.mime,'image/png');assert(!JSON.stringify(item).includes(root));
 const reopened=new AttachmentStore(root),files=await reopened.resolve([item.id]);assert.equal(path.dirname(files[0].file),root);assert.deepEqual(await fs.readFile(files[0].file),png);
 await assert.rejects(store.resolve([item.id,item.id]),/不同图片/);
});
test('multi-page TIFF and animated GIF labels say only the first page or frame was sent',async()=>{
 const sandbox=path.join(__dirname,'sandbox');await fs.mkdir(sandbox,{recursive:true});const root=await fs.mkdtemp(path.join(sandbox,'attachments-')),store=new AttachmentStore(root),dataUrl='data:image/png;base64,'+png.toString('base64');
 try{
  const scan=await store.save({name:'扫描件.TIF',dataUrl,frames:3});assert.equal(scan.readability,'图片 · 仅第 1 页（共 3 页）');assert.match(scan.warning,/第 1 页/);assert.equal(scan.frames,3);
  const gif=await store.save({name:'动图.gif',dataUrl,frames:12});assert.equal(gif.readability,'图片 · 仅首帧（共 12 帧）');assert.match(gif.warning,/第 1 帧/);
  for(const frames of [undefined,1,0,-2,2.5,'3',1e9]){const plain=await store.save({name:'普通.png',dataUrl,frames});assert.equal(plain.readability,'图片 · 可直接识图');assert.equal(plain.warning,undefined);assert.equal(plain.frames,undefined)}
  assert.equal((await new AttachmentStore(root).get(scan.id)).item.readability,scan.readability);
 }finally{await fs.rm(root,{recursive:true,force:true})}
});
test('model and reasoning choices are catalog-driven and default clears a previous effort',()=>{
 const model=normalizeModel({model:'test-model',displayName:'Test',isDefault:true,supportedReasoningEfforts:[{reasoningEffort:'high',description:'deep'}],defaultReasoningEffort:'high'});
 assert.deepEqual(model.inputModalities,['text','image']);assert.deepEqual(turnOptions([model],'','').params,{model:'test-model',effort:null});
 assert.equal(turnOptions([model],'test-model','high').params.effort,'high');assert.throws(()=>turnOptions([model],'test-model','unavailable'));assert.throws(()=>turnOptions([model],'other',''));
});
test('official thread name updates update the local title without removing messages',()=>{const thread={title:'old',messages:[{text:'keep'}]};reduceEvent(thread,'thread/name/updated',{threadName:'renamed'});assert.equal(thread.title,'renamed');assert.equal(thread.messages[0].text,'keep')});
