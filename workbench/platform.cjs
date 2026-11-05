'use strict';
const {execFile}=require('node:child_process'),{promisify}=require('node:util');
const execute=promisify(execFile);
function defaultCodex(platform=process.platform){return platform==='win32'?'codex.exe':'codex'}
function sameProjectPath(a,b,platform=process.platform){return platform==='win32'?a.toLowerCase()===b.toLowerCase():a===b}
async function pickFolder({platform=process.platform,run=execute}={}){
 let executable,args;
 if(platform==='darwin'){
  const script='try\nreturn POSIX path of (choose folder with prompt "UNIT-02 - Select project folder")\non error number -128\nreturn ""\nend try';
  executable='osascript';args=['-e',script];
 }else if(platform==='win32'){
  const script="Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.FolderBrowserDialog; $dialog.Description = 'UNIT-02 - Select project folder'; if ($dialog.ShowDialog() -eq 'OK') { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; [Console]::Write($dialog.SelectedPath) }";
  executable='powershell.exe';args=['-NoProfile','-STA','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')];
 }else throw Error('此平台不支持原生文件夹选择，请输入绝对目录路径');
 const {stdout}=await run(executable,args,{windowsHide:true,timeout:120000});
 return platform==='darwin'?stdout.replace(/\r?\n$/,''):stdout.trim();
}
module.exports={defaultCodex,sameProjectPath,pickFolder};
