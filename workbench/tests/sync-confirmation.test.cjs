const test=require('node:test'),assert=require('node:assert/strict');
test('ring reaches 99.2% before confirmation and smoothly finishes afterward',async()=>{
 const {drawUnit02Scene}=await import('../public/unified-sequence.js'),{SEQUENCE:S}=await import('../public/sequence-timing.js');
 function metric(time){const labels=[],c=new Proxy({fillText:s=>labels.push(s),createLinearGradient:()=>({addColorStop(){}}),createRadialGradient:()=>({addColorStop(){}})},{get:(o,k)=>k in o?o[k]:()=>{},set:(o,k,v)=>(o[k]=v,true)});drawUnit02Scene(c,time,{width:1920,height:1080,nerv:{},knot:{},connected:false});return parseFloat(labels.find(x=>/^\d+\.\d%$/.test(x)))}
 assert.equal(metric(S.syncStart+.01),0);assert.equal(metric(S.hold),99.2);
 const mid=metric((S.hold+S.syncFull)/2);assert(mid>99.2&&mid<100);
 assert.equal(metric(S.syncFull),100);assert(S.syncFull<S.transferStart);
});
