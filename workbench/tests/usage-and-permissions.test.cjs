'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {claudeUsage,codexUsage,contextUsage,codexContext,staleUsage}=require('../usage-metrics.cjs');
const {permissionMode,ensureModeChangeAllowed}=require('../permission-modes.cjs');
test('full access requires explicit acknowledgement and is scoped to the supported provider',()=>{
 assert.throws(()=>permissionMode('claude',{mode:'full-access'}),/确认/);assert.throws(()=>permissionMode('codex',{mode:'full-access',confirmFullAccess:true}),/不支持/);
 assert.equal(permissionMode('claude',{mode:'full-access',confirmFullAccess:true}),'full-access');assert.equal(permissionMode('claude',{}),'read-only');
 assert.throws(()=>ensureModeChangeAllowed({status:'inProgress'}),/停止/);assert.throws(()=>ensureModeChangeAllowed({localHistory:{}}),/原会话/);assert.throws(()=>ensureModeChangeAllowed({archived:true}),/恢复/);assert.doesNotThrow(()=>ensureModeChangeAllowed({status:'completed'}));
});
test('subscription metrics preserve real zero, missing utilization and server reset dates',()=>{
 const value=claudeUsage({rate_limits_available:true,rate_limits:{five_hour:{utilization:1,resets_at:'2026-11-06T05:30:00+00:00'},seven_day:{utilization:0,resets_at:null},seven_day_opus:{utilization:null,resets_at:null}}});
 assert.equal(value.available,true);assert.equal(value.windows[0].usedPercent,1);assert.equal(value.windows[1].usedPercent,0);assert.equal(value.windows[2].usedPercent,null);assert.equal(value.windows[0].resetsAt,'2026-11-06T05:30:00.000Z');
 const unavailable=claudeUsage({rate_limits_available:false,rate_limits:null});assert.equal(unavailable.available,false);assert.deepEqual(unavailable.windows,[]);
 const next=claudeUsage({rate_limits_available:true,rate_limits:{limits:[{kind:'session',percent:4},{kind:'weekly_all',percent:0}]}});assert.deepEqual(next.windows.map(x=>x.usedPercent),[4,0]);
});
test('Codex meters keep the actual duration and do not label a short window as five hours',()=>{
 const data=codexUsage({rateLimits:{primary:{usedPercent:8,windowDurationMins:15,resetsAt:1900000000},secondary:{usedPercent:0,windowDurationMins:10080}}});assert.equal(data.windows[0].label,'15 分钟');assert.equal(data.windows[0].id,'primary');assert.equal(data.windows[1].id,'seven_day');
 const current=codexUsage({rateLimitsByLimitId:{codex:{primary:{usedPercent:20,windowDurationMins:300}}}});assert.equal(current.windows[0].id,'five_hour');
});
test('context uses recent window occupancy rather than lifetime token totals and retains over-limit values',()=>{
 const value=codexContext({last:{totalTokens:8000},total:{totalTokens:9999999},modelContextWindow:100000});assert.equal(value.usedPercent,8);assert.equal(value.estimated,false);
 assert.equal(contextUsage({total_tokens:110,raw_max_tokens:100}).usedPercent,110.00000000000001);assert.equal(contextUsage({totalTokens:8,maxTokens:null}),null);
 const old=staleUsage({available:true,windows:[{usedPercent:5}],updatedAt:123},Error('offline'));assert.equal(old.windows[0].usedPercent,5);assert.equal(old.updatedAt,123);assert.equal(old.stale,true);assert.equal(old.error,'offline');
});
