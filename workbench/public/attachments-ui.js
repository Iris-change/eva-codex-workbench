'use strict';
window.AttachmentComposer=class{
 constructor({upload,onError,onChange}){
  this.upload=upload;this.onError=onError;this.onChange=onChange;this.items=[];this.pending=0;this.epoch=0;this.supported=true;
  this.input=document.getElementById('imageInput');this.button=document.getElementById('attachImage');this.list=document.getElementById('attachments');
  this.button.onclick=()=>this.input.click();this.input.onchange=()=>{this.addFiles([...this.input.files]);this.input.value=''};
  const composer=document.getElementById('composer');
  composer.addEventListener('paste',event=>{const files=[...(event.clipboardData?.items||[])].filter(x=>x.kind==='file').map(x=>x.getAsFile()).filter(Boolean);if(files.length){event.preventDefault();this.addFiles(files)}});
  const main=document.querySelector('main');
  main.addEventListener('dragover',event=>{if(event.dataTransfer?.types.includes('Files')){event.preventDefault();composer.classList.add('drop-ready')}});
  main.addEventListener('dragleave',event=>{if(!main.contains(event.relatedTarget))composer.classList.remove('drop-ready')});
  main.addEventListener('drop',event=>{if(event.dataTransfer?.files.length){event.preventDefault();composer.classList.remove('drop-ready');this.addFiles([...event.dataTransfer.files])}});
 }
 clear(){this.epoch++;this.items=[];this.pending=0;this.render();this.onChange()}
 removeSent(ids){this.items=this.items.filter(x=>!ids.includes(x.id));this.render();this.onChange()}
 setSupported(value){this.supported=value;this.button.disabled=!value;this.button.title=value?'选择、拖入或粘贴图片；每条最多 4 张':'当前模型不支持图片'}
 async normalize(file){
  if(!['image/png','image/jpeg','image/webp'].includes(file.type))throw Error('请选择 PNG、JPG 或 WebP 图片');
  if(file.size>16*1024*1024)throw Error('原始图片不能超过 16 MB');
  const bitmap=await createImageBitmap(file);
  try{
   const scale=Math.min(1,4096/Math.max(bitmap.width,bitmap.height));
   if(scale===1&&file.size<=8*1024*1024&&file.type!=='image/webp')return await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error('读取图片失败'));reader.readAsDataURL(file)});
   const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));const c=canvas.getContext('2d');c.drawImage(bitmap,0,0,canvas.width,canvas.height);
   let data=canvas.toDataURL(file.type==='image/jpeg'?'image/jpeg':'image/png',.92);
   if(data.length>11*1024*1024){c.globalCompositeOperation='destination-over';c.fillStyle='#fff';c.fillRect(0,0,canvas.width,canvas.height);data=canvas.toDataURL('image/jpeg',.9)}
   return data;
  }finally{bitmap.close()}
 }
 async addFiles(files){
  if(!this.supported){this.onError('当前模型不支持图片，请先切换模型');return}
  if(this.items.length+this.pending+files.length>4){this.onError('每条消息最多添加 4 张图片');return}
  const epoch=this.epoch;this.pending+=files.length;this.render();this.onChange();
  for(const file of files){
   try{const dataUrl=await this.normalize(file);if(epoch!==this.epoch)return;const item=await this.upload({name:file.name||'粘贴的截图.png',dataUrl});if(epoch!==this.epoch)return;this.items.push(item)}
   catch(error){if(epoch===this.epoch)this.onError(error.message||'图片上传失败')}
   finally{if(epoch===this.epoch){this.pending--;this.render();this.onChange()}}
  }
 }
 render(){
  this.list.replaceChildren();
  for(const item of this.items){const box=document.createElement('div');box.className='attachment-chip';const image=document.createElement('img');image.src=item.url;image.alt=item.name;const title=document.createElement('span');title.textContent=item.name;const remove=document.createElement('button');remove.type='button';remove.textContent='×';remove.setAttribute('aria-label','移除图片 '+item.name);remove.onclick=()=>{this.items=this.items.filter(x=>x.id!==item.id);this.render();this.onChange()};box.append(image,title,remove);this.list.append(box)}
  if(this.pending){const pending=document.createElement('span');pending.className='attachment-pending';pending.textContent='正在准备 '+this.pending+' 张图片…';this.list.append(pending)}
  this.list.hidden=!this.items.length&&!this.pending;
 }
};
