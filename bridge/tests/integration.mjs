// Risk-focused offline lifecycle integration. This is not real Codex E2E proof.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const data=await fs.mkdtemp(path.join(os.tmpdir(),'agent-studio-bridge-test-'));
const infoPath=path.join(data,'bridge.json'),tracePath=path.join(data,'trace.jsonl');
const fixture=path.join(here,'fixture-codex.mjs');await fs.chmod(fixture,0o755);
let proc,info;let output='';
const delay=()=>new Promise(r=>setTimeout(r,30));
async function until(fn){for(let i=0;i<200;i++){try{const value=await fn();if(value)return value;}catch{}await delay();}throw Error('Timed out\n'+output);}
async function launch(){
  proc=spawn(process.execPath,[path.join(here,'../server.mjs'),'--data',data],{env:{...process.env,AGENT_STUDIO_CODEX:fixture,FIXTURE_TRACE:tracePath,PATH:path.dirname(process.execPath)+':'+process.env.PATH},stdio:['ignore','pipe','pipe']});
  proc.stdout.on('data',b=>output+=b);proc.stderr.on('data',b=>output+=b);
  info=await until(async()=>JSON.parse(await fs.readFile(infoPath,'utf8')));
  await until(async()=>(await api('/state')).connected);
}
async function api(route,body){const r=await fetch('http://127.0.0.1:'+info.port+route,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+info.token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});const value=await r.json();if(!r.ok)throw Error(value.error);return value;}
const profile={id:'lead',name:'小夏',role:'Test',skills:['/fixture/skill/SKILL.md']};
async function task(prompt,extra={}){return(await api('/task',{workspace:data,profile,prompt,...extra})).task;}
async function state(id){return(await api('/state')).tasks.find(t=>t.id===id);}
async function shutdown(){if(!proc)return;const p=proc;await api('/shutdown',{});await new Promise(r=>p.once('exit',r));proc=null;}
try{
  await launch();
  const denied=await fetch('http://127.0.0.1:'+info.port+'/state');assert.equal(denied.status,403);
  const originDenied=await fetch('http://127.0.0.1:'+info.port+'/state',{headers:{Authorization:'Bearer '+info.token,Origin:'http://example.com'}});assert.equal(originDenied.status,403);
  const done=await task('complete');assert.equal((await state(done.id)).status,'completed');assert.deepEqual((await state(done.id)).files,['result.txt']);
  assert.deepEqual((await state(done.id)).conversation.map(e=>[e.role,e.text]),[['user','complete'],['assistant','Offline completed output']],'initial input precedes streamed reply; native duplicate events do not repeat bubbles');
	const beforeFinish=await state(done.id);
	await api('/finish',{id:done.id});
	const finished=await state(done.id);
	assert(finished.endedAt>0);assert.equal(finished.status,'completed');assert.equal(finished.result,beforeFinish.result);assert.deepEqual(finished.files,beforeFinish.files);
	assert.equal(finished.updated,beforeFinish.updated,'ending history must not replace a newer task as the current task');
	assert.equal(JSON.parse(await fs.readFile(path.join(data,'tasks.json'),'utf8')).find(t=>t.id===done.id).endedAt,finished.endedAt,'acknowledgement is durable before responding');
  await api('/message',{id:done.id,text:'complete again'});assert.equal((await state(done.id)).status,'completed','completion before RPC reply must not become running');
  const completedConversation=(await state(done.id)).conversation;
  assert.deepEqual(completedConversation.map(e=>e.text),['complete','Offline completed output','complete again','Offline completed output'],'continuing retains both turns even when the fixture reuses assistant item IDs');
	assert.equal((await state(done.id)).endedAt,undefined,'continuing an ended conversation restores its completion notification');
  let trace=(await fs.readFile(tracePath,'utf8')).trim().split('\n').map(JSON.parse);
  const start=trace.find(m=>m.method==='thread/start');assert.equal(start.params.config['skills.config'][0].path,'/fixture/skill');
  assert.deepEqual(trace.find(m=>m.method==='turn/start').params.input[1],{type:'skill',name:'fixture',path:'/fixture/skill/SKILL.md'});
  assert.equal(typeof trace.find(m=>String(m.id).startsWith('clock-')&&m.result)?.result.currentTimeAt,'number');
  const approval=await task('approve');await until(async()=>(await state(approval.id)).request);await api('/answer',{id:'approval-1',accept:false});
  await api('/message',{id:approval.id,text:'steering fixture'});await api('/stop',{id:approval.id,children:true});assert.equal((await state(approval.id)).status,'interrupted');
  await until(async()=>(await state(approval.id)).conversation.some(e=>e.text==='steering fixture'&&e.nativeId));
  assert.equal((await state(approval.id)).conversation.filter(e=>e.text==='steering fixture').length,1,'delayed native echo merges with accepted input');
  const question=await task('question');await api('/answer',{id:'question-1',answers:{color:'green'}});await api('/stop',{id:question.id});
  assert.deepEqual((await state(question.id)).conversation.map(e=>e.role),['user','assistant','user']);
  assert((await state(question.id)).conversation.at(-1).text.endsWith('green'),'question answers remain in the conversation');
  const queued=await task('queued');assert.equal((await state(queued.id)).request.id,'queued-1');
  await api('/answer',{id:'queued-1',accept:false});assert.equal((await state(queued.id)).request.id,'queued-2','parallel approvals must remain available in order');
  await api('/stop',{id:queued.id});assert.equal((await state(queued.id)).request,null);assert.equal((await state(queued.id)).status,'interrupted');
  const expectedPolicies={
    rule:{decision:{acceptWithExecpolicyAmendment:{execpolicy_amendment:['fixture','read']}}},
    session:{decision:'acceptForSession'},
    network:{decision:{applyNetworkPolicyAmendment:{network_policy_amendment:{host:'fixture.example',action:'allow'}}}},
    files:{decision:'acceptForSession'},
    permissions:{permissions:{network:{enabled:true}},scope:'session'},
  };
  for(const [type,expected] of Object.entries(expectedPolicies)) {
    const t=await task('policy-'+type),request=(await state(t.id)).request;
    const choice=request.approval.choices.find(c=>c.label.startsWith('始终允许'));
    assert(choice?.hint);assert.equal(choice.result,undefined,'UI cannot invent a protocol payload');
    await api('/answer',{id:request.id,choice:choice.id});
    const records=(await fs.readFile(tracePath,'utf8')).trim().split('\n').map(JSON.parse);
    assert.deepEqual(records.find(m=>m.id===request.id&&m.result).result,expected,'forward exact native approval scope: '+type);
    await api('/stop',{id:t.id});
  }
  const once=await task('policy-once'),onceRequest=(await state(once.id)).request;
  assert(!onceRequest.approval.choices.some(c=>c.label.startsWith('始终允许')),'do not fabricate unavailable persistent approval');
  await assert.rejects(api('/answer',{id:onceRequest.id,choice:'unknown'}),/此审批选项不可用/);
  assert.equal((await state(once.id)).request.id,onceRequest.id,'invalid approval keeps the request pending');
  await api('/answer',{id:onceRequest.id,accept:true});await api('/stop',{id:once.id});
  const networkStop=await task('policy-network');await api('/stop',{id:networkStop.id});
  const parent=await task('children complete',{team:true,roster:[{id:'research',name:'阿森',role:'Test',skills:[]}]});
  assert.equal((await state(parent.id)).status,'completed');
  const children=await until(async()=>{const ts=(await api('/state')).tasks.filter(t=>t.parentId===parent.id);return ts.length===2&&ts.every(t=>t.snapshot.id==='research')?ts:null;});
  assert(children.every(t=>t.name==='阿森'),'late delegated instructions replace generated native nicknames');
  assert.equal(new Set(children.map(t=>t.profileId)).size,2,'each simultaneous native agent gets a distinct actor');
	await assert.rejects(api('/finish',{id:parent.id}),/还有任务未结束/,'cannot dismiss a completed parent while a child is running');
	assert((await api('/state')).tasks.filter(t=>t.id===parent.id||t.parentId===parent.id).every(t=>!t.endedAt),'rejection does not partially end the family');
  await api('/stop',{id:parent.id,children:true});assert((await api('/state')).tasks.filter(t=>t.parentId===parent.id).every(t=>t.status==='interrupted'));
	await api('/finish',{id:parent.id});
	assert((await api('/state')).tasks.filter(t=>t.id===parent.id||t.parentId===parent.id).every(t=>t.endedAt),'ending a settled team clears all its completion markers');
  const manager=await task('lifecycle:'+JSON.stringify({spawn:'managed-a'}),{team:true,roster:[{id:'research',name:'阿森',role:'Test',skills:[]}]});
  const driver=await task('hold',{profile:{...profile,id:'fixture-driver'}});
  async function lifecycle(op,sender=manager.id){await api('/message',{id:driver.id,text:'lifecycle:'+JSON.stringify({actor:sender,...op})});await delay();}
  await until(()=>state('managed-a'));
  await lifecycle({finish:'managed-a'});
  assert.equal((await state('managed-a')).endedAt,undefined,'child completion alone waits for its delegator');
  await assert.rejects(api('/finish',{id:'managed-a'}),/委派 agent/);
  for(const status of ['inProgress','failed']){
    await lifecycle({close:'managed-a',status});assert.equal((await state('managed-a')).endedAt,undefined,'unsuccessful native close must not release a character');
  }
  await lifecycle({close:done.id});assert.equal((await state(done.id)).status,'completed','delegator cannot release an unrelated user task');assert.equal((await state(done.id)).endedAt,undefined);
  const childResult=(await state('managed-a')).result;
  await lifecycle({close:'managed-a'});
  const released=await until(async()=>{const t=await state('managed-a');return t.endedAt?t:null;});
  assert.equal(released.endedBy,manager.id);assert.equal(released.status,'completed');assert.equal(released.result,childResult,'closing a completed child retains its success and output');
  await lifecycle({lateStop:'managed-a'});assert.equal((await state('managed-a')).status,'completed','late close interruption does not turn successful work into stopped work');
  await lifecycle({resume:'managed-a'});assert.equal((await state('managed-a')).endedAt,undefined,'delegator can reactivate a released child');
  await lifecycle({close:'managed-a'});assert.equal((await state('managed-a')).status,'running','duplicate historical close does not close resumed work again');
  await lifecycle({spawn:'managed-b'});await until(()=>state('managed-b'));
  await lifecycle({finish:'managed-b'});
  await api('/message',{id:'managed-b',text:'complete user follow-up'});
  assert.equal((await state('managed-b')).completionOwnerId,manager.id,'supplementing a delegated task must not change its original delegator');
  await lifecycle({spawn:'nested-child'},'managed-a');await until(()=>state('nested-child'));
  await lifecycle({spawn:'managed-c'});await until(()=>state('managed-c'));
  await lifecycle({finish:'managed-c'});
  await lifecycle({finish:manager.id});
  assert((await state('managed-c')).endedAt,'parent final delivery releases completed delegated children');
  assert.equal((await state('managed-b')).endedBy,manager.id,'parent delivery releases delegated tasks even after a user supplement');
  assert.equal((await state('nested-child')).endedAt,undefined,'running descendants remain active');
  await lifecycle({finish:'managed-a'});
  assert.equal((await state('nested-child')).endedAt,undefined,'parent completion never releases a running child');
  await lifecycle({finish:'nested-child'});
  assert.equal((await state('nested-child')).endedBy,'managed-a','nested task is released by its direct delegator');
  assert.equal((await state('managed-a')).endedBy,manager.id,'delegator release waits for active descendants to settle');
  await api('/stop',{id:manager.id,children:true});
  await assert.rejects(api('/finish',{id:'managed-b'}),/委派 agent/);
  const racing=await Promise.allSettled([task('hold'),task('hold')]);assert.equal(racing.filter(x=>x.status==='fulfilled').length,1);
  const held=racing.find(x=>x.status==='fulfilled').value;
  for(let i=0;i<2;i++){
    await api('/message',{id:held.id,text:'legacy echo'});
    await until(async()=>(await state(held.id)).conversation.filter(e=>e.text==='legacy echo'&&e.nativeId).length===i+1);
  }
  assert.equal((await state(held.id)).conversation.filter(e=>e.text==='legacy echo').length,2,'identical intentional inputs remain distinct without client IDs');
  await assert.rejects(api('/message',{id:held.id,text:'reject this input'}),/Fixture rejected input/);
  assert(!(await state(held.id)).conversation.some(e=>e.text==='reject this input'),'failed send does not leave a delivered-looking message');
  await shutdown();await launch();assert((await api('/state')).tasks.every(t=>!['running','starting','working'].includes(t.status)));
  assert.deepEqual((await state(done.id)).conversation,completedConversation,'full conversation survives restart');
  assert.equal((await state('managed-c')).endedBy,manager.id,'delegated release survives restart');
  assert.equal((await state('managed-b')).completionOwnerId,manager.id,'delegated ownership survives restart');
	await shutdown();
	const saved=JSON.parse(await fs.readFile(path.join(data,'tasks.json'),'utf8'));
	const legacy=saved.find(t=>t.id===done.id);delete legacy.conversation;delete legacy.conversationVersion;
	const legacyChild=saved.find(t=>t.id==='managed-c');delete legacyChild.endedAt;delete legacyChild.endedBy;delete legacyChild.completionOwnerId;
	const relayedChild=saved.find(t=>t.id==='managed-b');relayedChild.completionOwnerId=null;delete relayedChild.endedAt;delete relayedChild.endedBy;relayedChild.logs=[{label:'你的补充（经负责人转达）',text:'离线补充'}];
	await fs.writeFile(path.join(data,'tasks.json'),JSON.stringify(saved));await launch();
	assert.equal((await state('managed-c')).endedBy,manager.id,'saved delegated work is released on startup when its parent already delivered');
	assert.equal((await state('managed-b')).completionOwnerId,manager.id,'legacy inferred user ownership is repaired from the original delegation');
	assert.equal((await state('managed-b')).endedBy,manager.id,'relayed legacy supplement must not leave a completed child unreleased');
	const recovered=(await api('/conversation?id='+done.id)).task;
	assert.deepEqual(recovered.conversation.map(e=>[e.role,e.text]),completedConversation.map(e=>[e.role,e.text]),'old tasks recover interleaving from original thread history');
	assert.equal(recovered.conversationVersion,1);assert.equal(recovered.conversationNotice,undefined);
	assert((await api('/state')).tasks.filter(t=>t.id===parent.id||t.parentId===parent.id).every(t=>t.endedAt),'ended state survives bridge restart');
  trace=(await fs.readFile(tracePath,'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(trace.find(m=>m.id==='approval-1'&&m.result).result.decision,'decline');
  assert.equal(trace.find(m=>m.id==='queued-2'&&m.result).result.decision,'decline','stopping rejects remaining pending approvals');
  assert.deepEqual(trace.find(m=>m.id==='question-1'&&m.result).result.answers.color.answers,['green']);
  assert.deepEqual(trace.find(m=>m.id==='policy-once'&&m.result).result,{decision:'accept'},'one-time approval is unchanged');
  assert.deepEqual(trace.filter(m=>m.id==='policy-network'&&m.result).at(-1).result,{decision:'decline'},'stop never creates a persistent deny rule');
  assert(trace.some(m=>m.method==='turn/steer'));
  // Native imports use the original catalog connection, never replaying old tools.
  const importProfile={id:'import-person',name:'米拉',role:'Visual identity',skills:[]};
  const importRequest=(id,mode='resume',extra={})=>({id,mode,profile:importProfile,requestId:'request-'+id+'-'+mode,workspace:data,...extra});
  const taskCount=(await api('/state')).tasks.length;
  const firstPage=await api('/sessions'),nextPage=await api('/sessions?cursor='+firstPage.nextCursor);
  assert.equal(firstPage.sessions.length,20);assert(nextPage.sessions.length>0);
  assert.equal((await api('/sessions?q='+encodeURIComponent('阅读角'))).sessions[0].id,'native-paged');
  assert.deepEqual((await api('/sessions?archived=1')).sessions.map(t=>t.id),['native-archived']);
  assert((await api('/sessions?cwd='+encodeURIComponent(data))).sessions.every(t=>t.workspace===data));
  const nativePreview=await api('/session-preview?id=native-paged');
  assert(nativePreview.conversation.length>0);assert.equal(nativePreview.dependencies[0],'desktop.fixtureOnly');
  assert.equal((await api('/state')).tasks.length,taskCount,'read-only browsing creates no Studio task');
  for(const id of ['native-busy','native-child'])await assert.rejects(api('/import-session',importRequest(id)),/执行|子会话/);
  await assert.rejects(api('/import-session',importRequest('native-paged','invalid')),/导入方式/);
  const imported=(await api('/import-session',importRequest('native-paged'))).task;
  assert.equal(imported.id,'native-paged');assert(imported.endedAt);assert.equal(imported.nativeStore,'native');
  assert.equal(imported.conversation.length,4,'all native pages are hydrated in chronological order');
  assert.deepEqual(imported.conversation.map(e=>e.text),['请整理阅读角。','书架靠墙，给窗边留出光线。','再加一盏灯。','加好了，保留了通往书架的通道。']);
  assert.equal((await api('/state')).tasks.length,taskCount+1,'old child-spawn records do not create live characters');
  assert.equal((await api('/import-session',importRequest('native-paged','resume',{requestId:'duplicate'}))).alreadyImported,true);
  const legacyImported=(await api('/import-session',importRequest('native-legacy'))).task;
  assert.equal(legacyImported.conversation.length,4,'legacy history imports use native full-history read');
  const concurrent=await Promise.all([api('/import-session',importRequest('native-archived','fork')),api('/import-session',importRequest('native-archived','fork'))]);
  assert.equal(concurrent[0].task.id,concurrent[1].task.id);assert.notEqual(concurrent[0].task.id,'native-archived');
  const copied=concurrent[0].task;
  assert.equal((await api('/import-session',importRequest('native-archived','fork'))).task.id,copied.id,'retry reuses the saved import');
  const beforeExecution=(await fs.readFile(tracePath,'utf8')).trim().split('\n').map(JSON.parse).filter(m=>m._store==='native');
  assert(!beforeExecution.some(m=>['turn/start','turn/steer','thread/resume','turn/interrupt'].includes(m.method)),'import never starts, resumes or interrupts a model turn');
  const forks=beforeExecution.filter(m=>m.method==='thread/fork');assert.equal(forks.length,1);assert.equal(forks[0].params.deferGoalContinuation,true,'fork cannot automatically continue an inherited goal');
  await api('/message',{id:imported.id,text:'approve client-tool'});
  const pendingNative=await until(async()=>{const t=await state(imported.id);return t.request?t:null;});
  assert.equal(pendingNative.request.id,'native:approval-1');
  await assert.rejects(api('/import-session',importRequest('native-extra-0')),/正在工作/);
  await api('/answer',{id:'native:approval-1',accept:false});await api('/stop',{id:imported.id});
  assert.equal((await state(imported.id)).status,'interrupted');
  const nativeTrace=(await fs.readFile(tracePath,'utf8')).trim().split('\n').map(JSON.parse).filter(m=>m._store==='native');
  assert(nativeTrace.some(m=>m.method==='thread/resume'&&m.params.threadId===imported.id&&m.params.approvalsReviewer==='user'));
  assert(nativeTrace.some(m=>m.id==='approval-1'&&m.result?.decision==='decline'));
  assert(nativeTrace.some(m=>m.id==='client-tool-1'&&m.result?.success===false),'unsupported original-client tools fail clearly instead of hanging in approval');
  assert(nativeTrace.some(m=>m.method==='turn/interrupt'&&m.params.threadId===imported.id),'stop reaches the native session process');
  const missing=(await api('/import-session',importRequest('native-missing'))).task;
  await assert.rejects(api('/message',{id:missing.id,text:'do not run'}));
  await shutdown();await launch();
  assert.equal((await state(copied.id)).imported.sourceId,'native-archived');assert((await state(copied.id)).endedAt);
  await api('/message',{id:copied.id,text:'complete the imported example'});
  assert.equal((await state(copied.id)).status,'completed');assert.equal((await state(copied.id)).conversation.length,6,'copy resumes through the native store after a bridge restart');
  console.log('IMPORT_CHECKS_OK: paginated/legacy history, filtering, no-turn import, duplicate/fork idempotency, native routing, approvals, unavailable tools, restart');
  console.log('BRIDGE_CHECKS_OK: auth, skill forwarding, event races, input/approval, distinct children, recursive stop, end/reopen conversation, persistence');
}finally{if(proc){try{await shutdown();}catch{proc.kill();}}await fs.rm(data,{recursive:true,force:true});}
