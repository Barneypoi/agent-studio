import http from 'node:http';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {publicApproval,approvalAnswer} from './approvals.mjs';
import {conversation,userEntry,cancelEntry,recordItem,restoreConversation} from './conversation.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const arg = (name, fallback) => { const i = process.argv.indexOf(name); return i < 0 ? fallback : process.argv[i + 1]; };
const dataDir = path.resolve(arg('--data', path.join(here, '../data')));
fs.mkdirSync(dataDir, {recursive: true});
const infoPath = arg('--info', path.join(dataDir, 'bridge.json'));
const token = crypto.randomBytes(24).toString('hex');
const tasksPath = path.join(dataDir, 'tasks.json');
const active = new Set(['starting', 'running', 'working', 'waiting', 'approval', 'stopping']);
const tasks = new Map();
let revision = 0, rpcId = 0, proc, initialized, connected = false, lastError = '', account = '', stopping = false;
let persistTimer;
const pending = new Map();
const requests = new Map();
const skillCache = new Map();
const discovery = new Set();
const loaded = new Set();
const startingProfiles = new Set();
const historyLoads = new Map();
try { for (const t of JSON.parse(fs.readFileSync(tasksPath, 'utf8'))) { if (active.has(t.status)) {t.status = 'interrupted'; t.activity = '应用已重新启动，可继续此任务';} t.request = null; tasks.set(t.id, t); } } catch {}
function atomic(file, value) { const tmp = file + '.tmp'; fs.writeFileSync(tmp, JSON.stringify(value, null, 2), {mode: 0o600}); fs.renameSync(tmp, file); }
function save() { clearTimeout(persistTimer); persistTimer = setTimeout(() => atomic(tasksPath, [...tasks.values()]), 300); }
function changed(t) { revision++; if(t) {t.updated = Date.now();if(active.has(t.status))delete t.endedAt;} save(); }
function log(t, label, text = '') { if(!t) return; t.logs.push({time: Date.now(), label, text: String(text).slice(-12000)}); if(t.logs.length > 200) t.logs.shift(); changed(t); }
function write(msg) { if(!proc?.stdin.writable) throw Error('Codex 进程尚未连接'); proc.stdin.write(JSON.stringify(msg) + '\n'); }
function rpc(method, params = {}, timeout = 60000) { return new Promise((resolve, reject) => {const id=++rpcId; const timer=setTimeout(()=>{pending.delete(id);reject(Error(method+' 请求超时'));},timeout);pending.set(id,{resolve,reject,timer});try {write({id,method,params});} catch(e){clearTimeout(timer);pending.delete(id);reject(e);} }); }
function codexBinary() { const candidates=[process.env.AGENT_STUDIO_CODEX, '/Applications/ChatGPT.app/Contents/Resources/codex', '/Applications/Codex.app/Contents/Resources/codex', path.join(os.homedir(), '.local/bin/codex')]; return candidates.find(p=>p&&fs.existsSync(p)) || 'codex'; }
async function connect() {
  if(initialized) return initialized;
  initialized = (async()=>{
    proc=spawn(codexBinary(),['app-server','--listen','stdio://','-c','sqlite_home='+JSON.stringify(path.join(dataDir,'codex-state')),'-c','log_dir='+JSON.stringify(path.join(dataDir,'codex-logs'))],{cwd:dataDir,stdio:['pipe','pipe','pipe'],env:process.env});
    proc.on('error',e=>{lastError=e.message; connected=false; revision++;});
    proc.stderr.on('data',b=>{fs.appendFileSync(path.join(dataDir,'codex-stderr.log'),b);});
    proc.on('exit',(code)=>{
      connected=false; initialized=null; lastError='Codex 连接已结束 ('+code+')';
      for(const p of pending.values()){clearTimeout(p.timer);p.reject(Error(lastError));}pending.clear();
      loaded.clear(); for(const t of tasks.values()) if(active.has(t.status)){t.status='interrupted';t.activity=lastError;t.request=null;}
      requests.clear();changed();
    });
    createInterface({input:proc.stdout}).on('line',line=>{try{const m=JSON.parse(line);onMessage(m).catch(e=>{lastError=e.message;revision++;});}catch{}});
    await rpc('initialize',{clientInfo:{name:'agent_studio',title:'Agent Studio',version:'1.0.0'},capabilities:{experimentalApi:true}},30000);
    write({method:'initialized',params:{}}); connected=true;lastError='';revision++;
    try {const a=await rpc('account/read',{});account=a.account?.type==='chatgpt'?'ChatGPT 已登录':a.account?'API 已连接':'尚未登录：请在终端运行 codex login';}catch(e){account=e.message;}
    for(const t of tasks.values())if(t.parentId&&!t.snapshot?.id)await discover(t.id,t.parentId,t.prompt);
  })().catch(e=>{initialized=null;throw e;});
  return initialized;
}
function input(text, skills=[]) {return [{type:'text',text,text_elements:[]},...skills.map(s=>({type:'skill',name:s.name,path:s.path}))];}
function refreshRequest(t) {
  const req=[...requests.values()].find(r=>r.params.threadId===t.id);
  t.request=req?{id:String(req.id),method:req.method,params:req.params,approval:publicApproval(req)}:null;
  if(req){t.status=req.method.includes('requestUserInput')?'waiting':'approval';t.activity=t.status==='approval'?'等待你的审批':'等待你的回答';}
  else if(['approval','waiting'].includes(t.status)){t.status='running';t.activity='继续执行';}
  changed(t);
}
function clearRequests(threadId) {for(const [id,req] of requests)if(req.params.threadId===threadId)requests.delete(id);}
function agentKey(profile){return profile.id.toLowerCase().replace(/[^a-z0-9_]/g,'_');}
function bindProfile(t,hint='') {
  if(!t.parentId||t.snapshot?.id)return;
  const roster=tasks.get(t.parentId)?.roster||[];
  const tagged=roster.find(p=>hint.includes('[studio-profile:'+p.id+']')||hint.split('/').at(-1)===agentKey(p));
  const named=roster.filter(p=>hint.includes(p.name));
  const profile=tagged||(named.length===1?named[0]:null);
  if(!profile)return;
  const occupied=[...tasks.values()].some(other=>other.id!==t.id&&other.profileId===profile.id&&active.has(other.status));
  t.profileId=occupied?'sub-'+t.id:profile.id;t.name=profile.name;t.snapshot=structuredClone(profile);changed(t);
}
function resultItem(t,item,turnId=t?.turnId||'') {
  if(!item||!t)return;
  recordItem(t,item,turnId);
  if(item.type==='userMessage'&&t.parentId){
    const prompt=(item.content||[]).filter(c=>c.type==='text').map(c=>c.text).join('\n');
    bindProfile(t,prompt);if(prompt)t.prompt=prompt;
  } else if(item.type==='agentMessage') {
    bindProfile(t,item.text||'');
    t.messages[item.id]=item.text||'';
    if(item.phase==='final_answer'||!item.phase) t.result=item.text||t.result;
    if(item.questions?.length){t.questions=item.questions;t.activity='需要补充信息';}
  } else if(item.type==='fileChange') {for(const f of item.changes||[]) {if(!t.files.includes(f.path)) t.files.push(f.path);} log(t,'文件修改',(item.changes||[]).map(f=>f.path).join('\n'));}
  else if(item.type==='commandExecution') log(t,item.exitCode===0?'命令完成':'命令结果',item.command+'\n'+(item.aggregatedOutput||''));
  else if(item.type==='mcpToolCall') log(t,'工具 · '+item.tool,item.error?.message||JSON.stringify(item.result||{}));
  else if(item.type==='plan') t.plan=item.text;
  else if(item.type==='collabAgentToolCall') {
    for(const id of item.receiverThreadIds||[]) {
      if(id!==t.id) discover(id,t.id,item.prompt||'').catch(()=>{});
      const child=tasks.get(id), state=item.agentsStates?.[id];
      if(child&&state){if(state.message)child.result=state.message; if(state.status==='completed')child.status='completed'; if(['errored','shutdown'].includes(state.status))child.status=state.status==='errored'?'failed':'interrupted';changed(child);}
    }
    log(t,'团队协作',item.tool+' · '+(item.prompt||''));
  } else if(item.type==='subAgentActivity'&&item.agentThreadId) discover(item.agentThreadId,t.id,item.agentPath||'').catch(()=>{});
  changed(t);
}
async function discover(id,parentId,hint='') {
  if(tasks.has(id))bindProfile(tasks.get(id),hint);
  if(discovery.has(id))return;
  if(tasks.has(id)&&loaded.has(id))return;
  const parent=tasks.get(parentId); if(!parent)return;
  discovery.add(id);
  try {
    const r=await rpc('thread/read',{threadId:id,includeTurns:true});const th=r.thread;
    const roster=parent.roster||[];const text=hint+' '+(th.agentNickname||'')+' '+(th.agentRole||'')+' '+(th.preview||'');
    const matches=roster.filter(p=>text.includes(p.name));const profile=matches.length===1?matches[0]:null;
    const t=tasks.get(id)||{id,profileId:profile&&!([...tasks.values()].some(other=>other.profileId===profile.id&&active.has(other.status)))?profile.id:('sub-'+id),name:profile?.name||th.agentNickname||th.agentRole||'新伙伴',parentId,workspace:parent.workspace,prompt:hint||th.preview||'子任务',status:'running',activity:'正在协作',result:'',messages:{},logs:[],files:[],created:Date.now(),updated:Date.now(),snapshot:profile||{},roster:[],turnId:null,request:null};
    tasks.set(id,t);
    bindProfile(t,text);
    restoreConversation(t,th.turns);
    for(const turn of th.turns||[]){t.turnId=turn.id;for(const item of turn.items||[])resultItem(t,item);t.status=({completed:'completed',failed:'failed',interrupted:'interrupted',inProgress:'running'})[turn.status]||t.status;if(turn.error)t.error=turn.error.message;}
    if(active.has(t.status)){await rpc('thread/resume',{threadId:id,excludeTurns:true});loaded.add(id);}changed(t);
  } catch(e){log(parent,'子任务同步',e.message);} finally{discovery.delete(id);}
}
async function onMessage(m) {
  if(m.id!==undefined&&!m.method){const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}return;}
  const p=m.params||{}, t=tasks.get(p.threadId);
  if(m.id!==undefined&&m.method){
    if(m.method==='currentTime/read'){write({id:m.id,result:{currentTimeAt:Math.floor(Date.now()/1000)}});return;}
    if(!t){write({id:m.id,error:{code:-32601,message:'此客户端不支持该请求'}});return;}
    requests.set(String(m.id),m);
    if(m.method==='item/tool/requestUserInput')recordItem(t,{type:'agentMessage',id:'question-'+m.id,text:(p.questions||[]).map(q=>q.question).join('\n\n')},p.turnId);
    refreshRequest(t);return;
  }
  if(m.method==='thread/started') {const th=p.thread; if(th?.parentThreadId&&tasks.has(th.parentThreadId)) await discover(th.id,th.parentThreadId,th.preview||'');return;}
  if(!t)return;
  switch(m.method){
    case 'turn/started': t.turnId=p.turn.id;t.status='running';t.activity='正在思考';t.result='';t.request=null;break;
    case 'turn/completed': t.turnId=p.turn.id;t.status=({completed:'completed',failed:'failed',interrupted:'interrupted'})[p.turn.status]||'failed';t.activity=({completed:'执行完成 · 待你验收',failed:'执行失败',interrupted:'已停止'})[t.status];if(p.turn.error)t.error=p.turn.error.message||JSON.stringify(p.turn.error);for(const i of p.turn.items||[])resultItem(t,i);clearRequests(t.id);t.request=null;break;
    case 'item/agentMessage/delta': t.messages[p.itemId]=(t.messages[p.itemId]||'')+p.delta;recordItem(t,{type:'agentMessage',id:p.itemId,text:p.delta},p.turnId||t.turnId,true);t.activity='正在回复';break;
    case 'item/started': {const i=p.item;if(i.type==='userMessage'){resultItem(t,i,p.turnId||t.turnId);break;}t.status='working';t.activity=({commandExecution:'执行命令',fileChange:'修改文件',webSearch:'查阅资料',reasoning:'分析中',mcpToolCall:'使用工具',collabAgentToolCall:'协调伙伴',contextCompaction:'整理上下文'})[i.type]||'正在工作';if(i.type==='commandExecution')log(t,'运行命令',i.command);if(['collabAgentToolCall','subAgentActivity','userMessage'].includes(i.type))resultItem(t,i,p.turnId||t.turnId);break;}
    case 'item/completed': resultItem(t,p.item,p.turnId||t.turnId);break;
    case 'thread/status/changed': if(p.status.type==='active'){if(p.status.activeFlags?.includes('waitingOnApproval'))t.status='approval';else if(p.status.activeFlags?.includes('waitingOnUserInput'))t.status='waiting';else if(!['approval','waiting','stopping'].includes(t.status))t.status='running';}else if(p.status.type==='systemError'){t.status='failed';t.activity='运行异常';} break;
    case 'turn/plan/updated': t.plan=(p.plan||[]).map(x=>(x.status==='completed'?'✓ ':'· ')+x.step).join('\n');break;
    case 'error': t.error=p.error?.message||JSON.stringify(p);log(t,'错误',t.error);break;
    case 'serverRequest/resolved': requests.delete(String(p.requestId));refreshRequest(t);break;
    case 'thread/tokenUsage/updated': t.tokens=p.tokenUsage?.total?.totalTokens||0;break;
  }
  if(t.request)refreshRequest(t);else changed(t);
}
async function skills(cwd,reload=false){
  await connect();cwd=validWorkspace(cwd);
  if(!reload&&skillCache.has(cwd))return skillCache.get(cwd);
  const r=await rpc('skills/list',{cwds:[cwd],forceReload:reload});const list=(r.data||[]).flatMap(d=>d.skills||[]);skillCache.set(cwd,list);return list;
}
function validWorkspace(p){if(!p||!path.isAbsolute(p))throw Error('请选择绝对路径的工作目录');const resolved=fs.realpathSync(p);if(!fs.statSync(resolved).isDirectory())throw Error('工作目录不存在');return resolved;}
async function startTask(body){
  const key=body.profile?.id;if(!key)throw Error('角色 ID 缺失');
  if(startingProfiles.has(key))throw Error('正在准备这位伙伴的任务');
  startingProfiles.add(key);
  try{return await startTaskUnlocked(body);}finally{startingProfiles.delete(key);}
}
async function startTaskUnlocked(body){
  await connect();const workspace=validWorkspace(body.workspace);const profile=body.profile||{};
  if(!String(body.prompt||'').trim())throw Error('请先填写任务');
  if([...tasks.values()].some(t=>t.profileId===profile.id&&active.has(t.status)))throw Error('这位伙伴正在工作，请追加指令或等它完成');
  const all=await skills(workspace,true);const chosen=(profile.skills||[]).map(p=>all.find(s=>s.path===p&&s.enabled));if(chosen.some(s=>!s))throw Error('角色配置中有已移除或禁用的技能，请重新配置');
  const roster=body.team?body.roster||[]:[];
  let instructions=`You are ${profile.name||'工作室伙伴'}. Role: ${profile.role||'完成分配的任务'}. Respond in Simplified Chinese. Work only within the selected project and use minimal risk-based verification. Report actual results and file paths. Never fabricate tool activity or completion.\n`;
  if(roster.length) instructions+='The user has enabled team delegation. Delegate suitable independent subtasks to native subagents. Available character profiles:\n'+roster.map(r=>`${r.name}: ${r.role}. Use task_name "${agentKey(r)}" when the spawn tool supports task_name. Skills (explicitly invoke when relevant): ${(r.skills||[]).join(', ')}. Include [studio-profile:${r.id}] verbatim, the character name, and these role/skill instructions in each corresponding delegated prompt. Do not create redundant work merely to keep characters busy.`).join('\n');
  for(const member of roster)for(const p of member.skills||[])if(!all.some(s=>s.path===p&&s.enabled))throw Error(member.name+' 配置了失效或禁用技能，请先修改');
  const config={'skills.config':all.map(s=>({path:s.path.endsWith('SKILL.md')?path.dirname(s.path):s.path,enabled:chosen.some(c=>c.path===s.path)||roster.some(r=>(r.skills||[]).includes(s.path))}))};
  const r=await rpc('thread/start',{cwd:workspace,sandbox:'workspace-write',approvalPolicy:'on-request',approvalsReviewer:'user',developerInstructions:instructions,config});
  const id=r.thread.id;loaded.add(id);
  const t={id,profileId:profile.id,name:profile.name||'伙伴',parentId:null,workspace,prompt:body.prompt,status:'starting',activity:'准备任务',result:'',messages:{},conversation:[],conversationVersion:1,logs:[],files:[],created:Date.now(),updated:Date.now(),snapshot:structuredClone(profile),roster:structuredClone(roster),turnId:null,request:null};tasks.set(id,t);
  const entry=userEntry(t,body.prompt);changed(t);
  try {const turn=await rpc('turn/start',{threadId:id,clientUserMessageId:entry.id,input:input(body.prompt,chosen)});entry.pending=false;t.turnId=turn.turn.id;if(t.status==='starting')t.status='running';changed(t);}catch(e){entry.pending=false;t.status='failed';t.error=e.message;changed(t);throw e;}
  return {task:t};
}
async function loadTask(t){
  if(loaded.has(t.id))return;
  if(t.parentId&&tasks.has(t.parentId))await loadTask(tasks.get(t.parentId));
  const r=await rpc('thread/resume',{threadId:t.id,excludeTurns:true});loaded.add(t.id);t.canAcceptDirectInput=r.thread?.canAcceptDirectInput;
}
async function loadConversation(t) {
  if(t.conversationVersion===1)return;
  if(historyLoads.has(t.id))return historyLoads.get(t.id);
  const loading=(async()=>{
    try{await connect();const r=await rpc('thread/read',{threadId:t.id,includeTurns:true},10000);
      if(!restoreConversation(t,r.thread?.turns))t.conversationNotice='原始历史暂不可用，以下展示旧版保存的记录。';
    }catch{conversation(t);t.conversationNotice='原始历史暂不可用，以下展示旧版保存的记录。';}
    revision++;save();
  })();historyLoads.set(t.id,loading);
  try{await loading;}finally{historyLoads.delete(t.id);}
}
async function relayMessage(t,text){
  await messageTask({id:t.parentId,text:`请将以下补充指令转达给子 agent ${t.id}（${t.name}），必要时恢复该子 agent：${text}`});
  const entry=userEntry(t,text);entry.pending=false;entry.awaitingEcho=false;
  log(t,'你的补充（经负责人转达）',text);return {ok:true,routedTo:t.parentId};
}
async function messageTask(body){const t=tasks.get(body.id);if(!t)throw Error('任务不存在');if(!body.text?.trim())throw Error('请输入指令');await connect();
  if(t.request)throw Error('请先处理角色当前的问题或审批');
  await loadConversation(t);
  try{await loadTask(t);}catch(e){if(t.parentId)return relayMessage(t,body.text);throw e;}
  if(t.parentId&&t.canAcceptDirectInput===false)return relayMessage(t,body.text);
  const entry=userEntry(t,body.text);const previous=t.status;changed(t);
  try{
    if(active.has(t.status)&&t.turnId)await rpc('turn/steer',{threadId:t.id,expectedTurnId:t.turnId,clientUserMessageId:entry.id,input:input(body.text)});
    else{t.status='starting';const r=await rpc('turn/start',{threadId:t.id,clientUserMessageId:entry.id,input:input(body.text)});t.turnId=r.turn.id;if(!['completed','failed','interrupted'].includes(t.status))t.status='running';}
    entry.pending=false;
  }catch(e){cancelEntry(t,entry);if(t.status==='starting')t.status=previous;changed(t);if(t.parentId)return relayMessage(t,body.text);throw e;}
  log(t,'你的补充',body.text);return {ok:true};}
async function stopTask(body){const t=tasks.get(body.id);if(!t)throw Error('任务不存在');
  if(active.has(t.status)){
  while(t.request){await answerRequest({id:t.request.id,accept:false,answer:''});}
  const previous=t.status;t.status='stopping';t.activity='正在停止';changed(t);
  try{await rpc('turn/interrupt',{threadId:t.id,turnId:t.turnId});}catch(e){t.status=previous;changed(t);if(t.parentId)await messageTask({id:t.parentId,text:`请立即停止子 agent ${t.id}（${t.name}）。`});else throw e;}
  }
  if(body.children)for(const c of tasks.values())if(c.parentId===t.id)await stopTask({id:c.id,children:true});return {ok:true};}
function finishTask(body){
  const t=tasks.get(body.id);if(!t)throw Error('任务不存在');
  const family=new Set([t.id]);
  for(const id of family)for(const child of tasks.values())if(child.parentId===id)family.add(child.id);
  const members=[...family].map(id=>tasks.get(id));
  if(members.some(member=>!['completed','failed','interrupted'].includes(member.status)))throw Error('还有任务未结束，请先等待完成或停止任务');
  const endedAt=Date.now();
  for(const member of members)member.endedAt ||= endedAt;
  // Ending is a presentation acknowledgement; preserve execution results and task recency.
  changed();atomic(tasksPath,[...tasks.values()]);
  return {ok:true,ids:[...family],endedAt};
}
async function answerRequest(body){const req=requests.get(String(body.id));if(!req)throw Error('请求已结束');const method=req.method;let result;
  const approval=approvalAnswer(req,body);
  if(approval)result=approval.result;
  else if(body.choice!==undefined)throw Error('此请求不支持记住授权');
  else if(method==='item/tool/requestUserInput'){const answers={};for(const q of req.params.questions||[])answers[q.id]={answers:[body.answers?.[q.id]||body.answer||'请停止并说明缺少的信息']};result={answers};}
  else if(method==='mcpServer/elicitation/request') result={action:body.accept?'accept':'decline',content:body.content||null};
  else if(method==='execCommandApproval'||method==='applyPatchApproval')result={decision:body.accept?'approved':'denied'};
  else if(method.includes('requestApproval'))result={decision:body.accept?'accept':'decline'};
  else {write({id:req.id,error:{code:-32601,message:'此客户端暂不支持这个交互'}});requests.delete(String(body.id));const t=tasks.get(req.params.threadId);if(t)refreshRequest(t);return{ok:true};}
  write({id:req.id,result});requests.delete(String(body.id));const t=tasks.get(req.params.threadId);if(t){
    if(method==='item/tool/requestUserInput'&&(body.answers||body.answer)){const entry=userEntry(t,(req.params.questions||[]).map(q=>q.question+'\n'+(body.answers?.[q.id]||body.answer||'')).join('\n\n'));entry.pending=false;entry.awaitingEcho=false;}
    refreshRequest(t);log(t,'用户回应',approval?.label||(body.accept?'已允许':body.answers?'已提交回答':body.answer||'已拒绝'));}return{ok:true};}
function publicTask(t){const entries=conversation(t);return {...t,conversation:entries,messages:Object.values(t.messages).join('\n\n').slice(-48000),logs:t.logs.slice(-60)};}
function publicState(){return {revision,connected,account,error:lastError,tasks:[...tasks.values()].map(publicTask)};}
const server=http.createServer(async(req,res)=>{
  res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');
  const respond=(code,data)=>{res.writeHead(code);res.end(JSON.stringify(data));};
  if(req.headers.origin||req.headers.authorization!==`Bearer ${token}`){respond(403,{error:'拒绝未授权连接'});return;}
  try{
    const url=new URL(req.url,'http://localhost');
    if(req.method==='GET'&&url.pathname==='/state'){respond(200,publicState());return;}
    if(req.method==='GET'&&url.pathname==='/conversation'){const t=tasks.get(url.searchParams.get('id'));if(!t)throw Error('任务不存在');await loadConversation(t);respond(200,{task:publicTask(t)});return;}
    if(req.method==='GET'&&url.pathname==='/skills'){respond(200,{skills:await skills(url.searchParams.get('cwd'),url.searchParams.has('reload'))});return;}
    let text='';for await(const c of req){text+=c;if(text.length>1024*1024)throw Error('请求过大');}const body=text?JSON.parse(text):{};
    let result;
    switch(url.pathname){case'/connect':await connect();result={ok:true};break;case'/task':result=await startTask(body);break;case'/message':result=await messageTask(body);break;case'/stop':result=await stopTask(body);break;case'/finish':result=finishTask(body);break;case'/answer':result=await answerRequest(body);break;
      case'/shutdown':result={ok:true};setTimeout(shutdown,100);break;default:respond(404,{error:'未知操作'});return;}
    respond(200,result);
  }catch(e){respond(400,{error:e.message});}
});
function shutdown(){if(stopping)return;stopping=true;clearTimeout(persistTimer);for(const t of tasks.values())if(active.has(t.status)){t.status='interrupted';t.activity='应用已关闭';t.request=null;}atomic(tasksPath,[...tasks.values()]);proc?.kill('SIGTERM');server.close();try{fs.unlinkSync(infoPath);}catch{}setTimeout(()=>process.exit(0),300).unref();}
process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);
server.listen(Number(arg('--port','0')),'127.0.0.1',()=>{atomic(infoPath,{port:server.address().port,token,pid:process.pid});console.log('Agent Studio bridge ready on localhost:'+server.address().port);connect().catch(e=>{lastError=e.message;revision++;});});
