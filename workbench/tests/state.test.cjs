const test=require('node:test'),assert=require('node:assert/strict');
const {reduceEvent}=require('../state.cjs');const {CodexBridge}=require('../bridge.cjs');
const fixture=()=>({messages:[],tools:[],status:'idle'});
test('interleaved streams are joined by item id; final item replaces deltas',()=>{const t=fixture();reduceEvent(t,'item/agentMessage/delta',{itemId:'a',delta:'Hel'});reduceEvent(t,'item/agentMessage/delta',{itemId:'b',delta:'Other'});reduceEvent(t,'item/agentMessage/delta',{itemId:'a',delta:'lo'});reduceEvent(t,'item/completed',{item:{id:'a',type:'agentMessage',text:'Hello!'}});assert.deepEqual(t.messages.map(x=>x.text),['Hello!','Other'])});
test('failed and interrupted turns never become completed',()=>{for(const status of ['failed','interrupted']){const t=fixture();reduceEvent(t,'turn/started',{turn:{id:'turn'}});reduceEvent(t,'turn/completed',{turn:{id:'turn',status,error:{message:'failure'}}});assert.equal(t.status,status);assert.equal(t.activeTurn,null);assert.equal(t.error,'failure')}});
test('command output and diff are preserved',()=>{const t=fixture();reduceEvent(t,'item/started',{item:{id:'cmd',type:'commandExecution',command:'node --test',status:'inProgress'}});reduceEvent(t,'item/commandExecution/outputDelta',{itemId:'cmd',delta:'passed'});reduceEvent(t,'turn/diff/updated',{diff:'+added'});assert.equal(t.tools[0].aggregatedOutput,'passed');assert.equal(t.diff,'+added')});
test('bridge routes approvals separately and does not auto approve',()=>{const b=new CodexBridge();let request;let writes=0;b.send=()=>writes++;b.on('approval',r=>request=r);b.receive({id:7,method:'item/fileChange/requestApproval',params:{threadId:'test'}});assert.equal(request.id,7);assert.equal(writes,0)});
test('protocol errors reject matching request',async()=>{const b=new CodexBridge();b.send=()=>{};const pending=b.request('test',{},100);b.receive({id:1,error:{message:'rejected'}});await assert.rejects(pending,/rejected/);assert.equal(b.pending.size,0)});
test('tool steps record where they happened in the transcript and when they finished',()=>{
 const t={messages:[{id:'u',role:'user',text:'run it'}],tools:[]};
 reduceEvent(t,'item/agentMessage/delta',{itemId:'a1',delta:'先看一下'});
 reduceEvent(t,'item/started',{item:{id:'c1',type:'commandExecution',command:'ls',status:'inProgress'}});
 assert.equal(t.tools[0].at,2);assert.equal(typeof t.tools[0].startedAt,'number');assert.equal(t.tools[0].endedAt,undefined);
 reduceEvent(t,'item/commandExecution/outputDelta',{itemId:'c1',delta:'a.txt\n'});
 reduceEvent(t,'item/completed',{item:{id:'c1',type:'commandExecution',command:'ls',status:'completed',aggregatedOutput:'a.txt\n'}});
 assert.equal(t.tools[0].at,2,'position survives completion');assert.equal(t.tools[0].status,'completed');assert.equal(typeof t.tools[0].endedAt,'number');
 reduceEvent(t,'item/commandExecution/outputDelta',{itemId:'c2',delta:'x'});assert.equal(t.tools[1].at,2);
});
