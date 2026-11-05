'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.join(__dirname,'../public/media/audio-unit02-fluid');
test('original Japanese announcements contain speech in every cue and silence around pilot hold',async()=>{
 const wav=fs.readFileSync(path.join(root,'voice.wav')),meta=JSON.parse(fs.readFileSync(path.join(root,'timeline.json'))),{SEQUENCE:S}=await import('../public/sequence-timing.js');
 assert.equal(wav.toString('ascii',0,4),'RIFF');assert.equal(wav.toString('ascii',8,12),'WAVE');assert.equal(wav.readUInt16LE(20),1);assert.equal(wav.readUInt16LE(22),1);assert.equal(wav.readUInt32LE(24),48000);assert.equal(wav.readUInt16LE(34),16);
 let offset=12,data;while(offset+8<=wav.length){const size=wav.readUInt32LE(offset+4);if(wav.toString('ascii',offset,offset+4)==='data'){data=wav.subarray(offset+8,offset+8+size);break}offset+=8+size+(size%2)}assert(data);
 const rate=48000;assert.equal(data.length/2/rate,S.duration);assert.equal(meta.placeholder,false);assert.equal(meta.voice,'ja-JP-NanamiNeural');assert.equal(meta.cues.length,6);
 let prior=0;for(const cue of meta.cues){assert(cue.start>=prior&&cue.end>cue.start&&cue.end<=S.duration);assert(cue.ja&&cue.zh);assert(!(cue.start<S.hold&&cue.end>S.hold));let energy=0;for(let i=Math.floor(cue.start*rate);i<Math.floor(cue.end*rate);i++){const v=data.readInt16LE(i*2);assert(Math.abs(v)<32767);energy+=v*v}assert(energy>1e8,'cue must contain non-silent speech');prior=cue.end}
 for(let i=Math.floor((S.hold-.1)*rate);i<Math.floor((S.hold+.1)*rate);i++)assert.equal(data.readInt16LE(i*2),0,'confirmation must not cut a spoken sentence');
});
