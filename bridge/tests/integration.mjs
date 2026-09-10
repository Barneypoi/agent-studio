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
	await shutdown();
	const saved=JSON.parse(await fs.readFile(path.join(data,'tasks.json'),'utf8'));
	const legacy=saved.find(t=>t.id===done.id);delete legacy.conversation;delete legacy.conversationVersion;
	await fs.writeFile(path.join(data,'tasks.json'),JSON.stringify(saved));await launch();
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
  console.log('BRIDGE_CHECKS_OK: auth, skill forwarding, event races, input/approval, distinct children, recursive stop, end/reopen conversation, persistence');
}finally{if(proc){try{await shutdown();}catch{proc.kill();}}await fs.rm(data,{recursive:true,force:true});}
