'use strict';
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const files=fs.readdirSync(path.join(__dirname,'tests')).filter(x=>x.endsWith('.test.cjs')).sort().map(x=>path.join(__dirname,'tests',x));
// Tests talk to their own loopback servers; keep an inherited HTTP(S)_PROXY + NODE_USE_ENV_PROXY from routing them through the proxy.
const loopback=['127.0.0.1','localhost','::1'],noProxy=[...new Set([...(process.env.NO_PROXY||process.env.no_proxy||'').split(',').map(x=>x.trim()).filter(Boolean),...loopback])].join(',');
const result=spawnSync(process.execPath,['--test',...files],{stdio:'inherit',env:{...process.env,NO_PROXY:noProxy,no_proxy:noProxy}});process.exitCode=result.status??1;
