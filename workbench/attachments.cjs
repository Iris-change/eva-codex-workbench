'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const MAX_IMAGE_BYTES=8*1024*1024,MAX_IMAGES=4,MAX_TOTAL_BYTES=16*1024*1024;
const validId=id=>typeof id==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id);
function decodeImage(dataUrl){
 if(typeof dataUrl!=='string')throw Error('请选择 PNG 或 JPG 图片');
 const match=/^data:(image\/(?:png|jpeg));base64,([A-Za-z0-9+/]+={0,2})$/.exec(dataUrl);
 if(!match||match[2].length%4!==0)throw Error('仅支持有效的 PNG 或 JPG 图片');
 const data=Buffer.from(match[2],'base64');
 if(!data.length||data.length>MAX_IMAGE_BYTES)throw Error('每张图片不能超过 8 MB');
 const png=data.length>=24&&data.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))&&data.toString('ascii',12,16)==='IHDR';
 const jpg=data.length>=4&&data[0]===255&&data[1]===216&&data[2]===255&&data[data.length-2]===255&&data[data.length-1]===217;
 if(match[1]==='image/png'&&!png||match[1]==='image/jpeg'&&!jpg)throw Error('图片内容与格式不匹配');
 if(png){const w=data.readUInt32BE(16),h=data.readUInt32BE(20);if(!w||!h||w>16384||h>16384||w*h>40000000)throw Error('图片尺寸过大，请缩小后再发送')}
 return {data,mime:match[1]};
}
class AttachmentStore{
 constructor(root){this.root=path.resolve(root)}
 async save(input){
  const {data,mime}=decodeImage(input.dataUrl),id=crypto.randomUUID();
  const name=path.basename(String(input.name||'截图').replaceAll('\\','/')).replace(/[\x00-\x1f]/g,'').slice(0,120)||'截图';
  const item={id,name,mime,bytes:data.length,url:'/api/attachment/'+id};
  await fs.mkdir(this.root,{recursive:true});
  const file=path.join(this.root,id+(mime==='image/png'?'.png':'.jpg'));
  await fs.writeFile(file,data,{flag:'wx'});await fs.writeFile(path.join(this.root,id+'.json'),JSON.stringify(item),{flag:'wx'});
  return item;
 }
 async get(id){
  if(!validId(id))throw Error('附件编号无效');
  const item=JSON.parse(await fs.readFile(path.join(this.root,id+'.json'),'utf8'));
  if(item.id!==id||!['image/png','image/jpeg'].includes(item.mime))throw Error('附件记录无效');
  const file=path.join(this.root,id+(item.mime==='image/png'?'.png':'.jpg'));
  const real=await fs.realpath(file);if(path.dirname(real).toLowerCase()!==(await fs.realpath(this.root)).toLowerCase())throw Error('附件路径无效');
  const stat=await fs.stat(real);if(!stat.isFile()||stat.size>MAX_IMAGE_BYTES||stat.size!==item.bytes)throw Error('附件文件无效');
  return {item,file:real};
 }
 async resolve(ids=[]){
  if(!Array.isArray(ids)||ids.length>MAX_IMAGES||new Set(ids).size!==ids.length)throw Error('每条消息最多附带 4 张不同图片');
  const files=await Promise.all(ids.map(id=>this.get(id)));
  if(files.reduce((sum,x)=>sum+x.item.bytes,0)>MAX_TOTAL_BYTES)throw Error('每条消息的图片总大小不能超过 16 MB');
  return files;
 }
}
module.exports={AttachmentStore,decodeImage,MAX_IMAGE_BYTES,MAX_IMAGES};
