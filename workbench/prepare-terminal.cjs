'use strict';
const fs=require('node:fs'),path=require('node:path');
function prepareTerminal(root=path.join(__dirname,'node_modules/node-pty'),platform=process.platform,arch=process.arch){
 if(platform!=='darwin')return;
 // node-pty 1.1.0 ships its macOS prebuilt spawn-helper without the execute bit.
 // The addon loads successfully, but spawning a PTY then fails with posix_spawnp.
 for(const file of [path.join(root,'prebuilds',platform+'-'+arch,'spawn-helper'),path.join(root,'build/Release/spawn-helper')]){
  try{const stat=fs.statSync(file);if(stat.isFile())fs.chmodSync(file,(stat.mode&0o777)|0o111)}catch(error){if(error.code!=='ENOENT')throw error}
 }
}
if(require.main===module)prepareTerminal();
module.exports={prepareTerminal};
