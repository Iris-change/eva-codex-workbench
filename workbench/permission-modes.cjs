'use strict';
function permissionMode(provider,input={},current='read-only'){
 const mode=input.mode??current,allowed=provider==='claude'?['read-only','workspace-write','full-access']:['read-only','workspace-write'];
 if(!allowed.includes(mode))throw Error('此后端不支持所选权限模式');
 if(mode==='full-access'&&input.confirmFullAccess!==true)throw Error('完全访问需要在界面中明确确认本机会话的权限范围');
 return mode;
}
function ensureModeChangeAllowed(t,active=false){
 if(t.localHistory)throw Error('原会话只读展示，请先继续为 EVA 分支');
 if(t.archived)throw Error('请先恢复已归档会话');
 if(active||t.activeTurn||t.status==='inProgress')throw Error('请先停止或完成当前任务，再切换权限');
}
module.exports={permissionMode,ensureModeChangeAllowed};
