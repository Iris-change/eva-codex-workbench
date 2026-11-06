'use strict';
const number=v=>typeof v==='number'&&Number.isFinite(v)?v:null;
function resetTime(v){if(typeof v==='number'&&Number.isFinite(v))return new Date(v<1e12?v*1000:v).toISOString();return typeof v==='string'&&Number.isFinite(Date.parse(v))?new Date(v).toISOString():null}
function claudeUsage(raw){
 const r=raw?.rate_limits,windows=[];
 for(const [id,label] of [['five_hour','5 小时'],['seven_day','本周'],['seven_day_opus','Opus 周额度'],['seven_day_sonnet','Sonnet 周额度']]){
  const row=r?.[id];if(row)windows.push({id,label,usedPercent:number(row.utilization),resetsAt:resetTime(row.resets_at)});
 }
 if(Array.isArray(r?.limits))for(const row of r.limits){
  const id=row.kind==='session'?'five_hour':row.kind==='weekly_all'?'seven_day':null;
  if(id&&!windows.some(x=>x.id===id))windows.push({id,label:id==='five_hour'?'5 小时':'本周',usedPercent:number(row.percent),resetsAt:resetTime(row.resets_at)});
 }
 return {available:raw?.rate_limits_available===true&&windows.length>0,windows,updatedAt:Date.now(),source:'Claude Code 官方 /usage（实验接口）',error:raw?.rate_limits_available===true?(windows.length?null:'官方尚未返回额度窗口'):'当前登录方式暂未提供订阅额度',stale:false};
}
function codexUsage(raw){
 const r=raw?.rateLimitsByLimitId?.codex||raw?.rateLimits,windows=[];
 for(const key of ['primary','secondary']){const row=r?.[key];if(!row)continue;const minutes=number(row.windowDurationMins),id=minutes===300?'five_hour':minutes===10080?'seven_day':key;
  windows.push({id,label:id==='five_hour'?'5 小时':id==='seven_day'?'本周':minutes?minutes+' 分钟':'官方额度窗口',usedPercent:number(row.usedPercent),resetsAt:resetTime(row.resetsAt)});
 }
 return {available:windows.length>0,windows,updatedAt:Date.now(),source:'Codex 官方 account/rateLimits',error:windows.length?null:'当前账号尚未返回额度窗口',stale:false};
}
function contextUsage(raw,source='claude'){
 if(!raw)return null;
 const snake=raw.total_tokens!==undefined,usedTokens=number(snake?raw.total_tokens:raw.totalTokens),maxTokens=number(snake?raw.raw_max_tokens:raw.rawMaxTokens??raw.maxTokens);
 if(usedTokens===null||maxTokens===null||maxTokens<=0)return null;
 return {usedTokens,maxTokens,usedPercent:usedTokens/maxTokens*100,model:raw.model||null,estimated:source==='claude',source:source==='claude'?'Claude SDK 上下文估计 / 自动压缩窗口':'Codex 最近一轮 token 使用',updatedAt:Date.now()};
}
function codexContext(usage){return usage?.last&&contextUsage({totalTokens:usage.last.totalTokens,maxTokens:usage.modelContextWindow},'codex')}
function staleUsage(previous,error){return {...(previous||{available:false,windows:[],updatedAt:null}),stale:true,error:String(error?.message||error||'额度刷新失败').slice(0,300)}}
module.exports={claudeUsage,codexUsage,contextUsage,codexContext,staleUsage};
