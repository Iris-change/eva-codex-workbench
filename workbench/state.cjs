'use strict';
function reduceEvent(thread,method,p){
  if(method==='thread/name/updated'&&p.threadName)thread.title=p.threadName;
  if(method==='turn/started'){thread.activeTurn=p.turn.id;thread.status='inProgress';thread.error=null;}
  if(method==='turn/completed'){thread.status=p.turn.status;thread.error=p.turn.error?.message||null;thread.activeTurn=null;}
  if(method==='error')thread.error=p.error?.message||p.message||'Codex error';
  if(method==='turn/diff/updated')thread.diff=p.diff;
  if(method==='turn/plan/updated')thread.plan=p.plan;
  if(method==='item/agentMessage/delta'){
    let msg=thread.messages.find(x=>x.id===p.itemId);
    if(!msg){msg={id:p.itemId,role:'assistant',text:''};thread.messages.push(msg)}
    msg.text+=p.delta;
  }
  if(method==='item/started'||method==='item/completed'){
    const item=p.item;
    if(item.type==='agentMessage'){
      let msg=thread.messages.find(x=>x.id===item.id);
      if(!msg){msg={id:item.id,role:'assistant',text:''};thread.messages.push(msg)}
      if(item.text)msg.text=item.text;
    }else if(item.type!=='userMessage'){
      const index=thread.tools.findIndex(x=>x.id===item.id);
      if(index<0)thread.tools.push(item);else thread.tools[index]={...thread.tools[index],...item};
    }
  }
  if(method==='item/commandExecution/outputDelta'){
    let item=thread.tools.find(x=>x.id===p.itemId);
    if(!item){item={id:p.itemId,type:'commandExecution',status:'inProgress',aggregatedOutput:''};thread.tools.push(item)}
    item.aggregatedOutput=(item.aggregatedOutput||'')+p.delta;
  }
  if(method==='thread/tokenUsage/updated')thread.usage=p.tokenUsage;
  return thread;
}
module.exports={reduceEvent};
