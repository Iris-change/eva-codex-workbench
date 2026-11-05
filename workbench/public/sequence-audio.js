// Decode the complete local track once. Playback and seeking do not depend on HTTP ranges.
export async function loadSequenceAudio(url){
 const response=await fetch(url);if(!response.ok)throw Error('Sequence audio unavailable');
 const context=new AudioContext(),buffer=await context.decodeAudioData(await response.arrayBuffer());
 let node=null,position=0,began=0;
 const audio={
  get currentTime(){return node?Math.min(buffer.duration,position+context.currentTime-began):position},
  set currentTime(value){const resume=!!node;this.pause();position=Math.max(0,Math.min(buffer.duration,Number(value)||0));if(resume)this.play().catch(()=>{})},
  get duration(){return buffer.duration},get paused(){return node===null},get ended(){return this.currentTime>=buffer.duration},
  async play(){await context.resume();if(node)return;if(position>=buffer.duration)position=0;node=context.createBufferSource();node.buffer=buffer;node.connect(context.destination);began=context.currentTime;node.onended=()=>{position=buffer.duration;node=null};node.start(0,position)},
  pause(){if(!node)return;position=this.currentTime;node.onended=null;node.stop();node.disconnect();node=null},
  close(){this.pause();return context.close()}
 };
 addEventListener('pagehide',()=>audio.close(),{once:true});return audio;
}
