#!/usr/bin/env node
// Offline protocol peer. Never contacts Codex, a model, or the network.
import {createInterface} from 'node:readline';
import fs from 'node:fs';
import path from 'node:path';
const send=m=>process.stdout.write(JSON.stringify(m)+'\n');
const event=(method,params)=>send({method,params});
let sequence=0;
const turns=new Map();
const store=process.argv.some(a=>a.startsWith('sqlite_home='))?'studio':'native';
const historyPath=process.env.FIXTURE_TRACE+(store==='native'?'.native':'')+'.history.json';
const history=new Map(fs.existsSync(historyPath)?JSON.parse(fs.readFileSync(historyPath,'utf8')):[]);
const parents=new Map();
const catalogPath=historyPath+'.catalog.json';
const catalog=new Map(fs.existsSync(catalogPath)?JSON.parse(fs.readFileSync(catalogPath,'utf8')):[]);
const cwd=path.dirname(process.env.FIXTURE_TRACE);
if(!catalog.size){
  const seeds=[['native-paged','工作室阅读角','paginated'],['native-legacy','旧版项目笔记','legacy'],['native-archived','已归档的方案','paginated'],['native-busy','仍在进行的工作','paginated'],['native-missing','目录已迁移的项目','legacy'],['native-child','委派的子会话','legacy']];
  for(let i=0;i<21;i++)seeds.push(['native-extra-'+i,'离线会话 '+i,'legacy']);
  for(const [id,name,historyMode] of seeds){
    catalog.set(id,{id,name,historyMode,cwd:id==='native-missing'?path.join(cwd,'does-not-exist'):cwd,model:'fixture-model',source:id==='native-child'?'subAgent':'cli',parentThreadId:id==='native-child'?'native-paged':null,createdAt:1700000000,updatedAt:1700000120,status:{type:id==='native-busy'?'active':'notLoaded'},ephemeral:false,preview:'请整理阅读角，留下通道。',archived:id==='native-archived'});
    if(!history.has(id))history.set(id,[{id:'old-1',status:'completed',items:[{type:'userMessage',id:'u1',content:[{type:'text',text:'请整理阅读角。'}]},{type:'agentMessage',id:'a1',text:'书架靠墙，给窗边留出光线。',phase:'final_answer'},{type:'collabAgentToolCall',id:'historical-spawn',tool:'spawnAgent',receiverThreadIds:['historical-child'],status:'completed'}]},{id:'old-2',status:id==='native-busy'?'inProgress':'completed',items:[{type:'userMessage',id:'u2',content:[{type:'text',text:'再加一盏灯。'}]},{type:'agentMessage',id:'a2',text:'加好了，保留了通往书架的通道。',phase:'final_answer'},{type:'dynamicToolCall',id:'old-tool',namespace:'desktop',tool:'fixtureOnly',status:'completed'}]}]);
  }
  fs.writeFileSync(catalogPath,JSON.stringify([...catalog]));fs.writeFileSync(historyPath,JSON.stringify([...history]));
}
function nativeThread(id,includeTurns=false){const th=catalog.get(id);return th?{...th,turns:includeTurns?(history.get(id)||[]):[]}:null;}
function remember(threadId,turnId,item){
  if(!history.has(threadId))history.set(threadId,[]);
  const thread=history.get(threadId);let turn=thread.find(t=>t.id===turnId);
  if(!turn){turn={id:turnId,status:'completed',items:[]};thread.push(turn);}
  turn.items.push(item);fs.writeFileSync(historyPath,JSON.stringify([...history]));
}
function userEcho(p,turnId){
  const item={type:'userMessage',id:'user-'+(++sequence),clientId:p.clientUserMessageId,content:p.input.filter(i=>i.type==='text')};
  remember(p.threadId,turnId,item);
  for(const name of ['item/started','item/completed'])event(name,{threadId:p.threadId,turnId,item});
}
function reply(threadId,turnId,text,id='result-'+(++sequence)){
  const item={type:'agentMessage',id,phase:'final_answer',text};
  remember(threadId,turnId,item);
  for(const delta of [text.slice(0,4),text.slice(4)])event('item/agentMessage/delta',{threadId,turnId,itemId:item.id,delta});
  event('item/completed',{threadId,turnId,item});return item;
}
function lifecycle(sender,op){
  sender=op.actor||sender;
  if(op.spawn){
    parents.set(op.spawn,sender);turns.set(op.spawn,'delegated-turn');
    history.set(op.spawn,[{id:'delegated-turn',status:'inProgress',items:[{type:'userMessage',id:'delegation',content:[{type:'text',text:'[studio-profile:research] 阿森，请核对离线示例。'}]}]}]);
    event('item/completed',{threadId:sender,item:{type:'collabAgentToolCall',id:'spawn-'+op.spawn,tool:'spawnAgent',status:'completed',senderThreadId:sender,receiverThreadIds:[op.spawn],agentsStates:{}}});
  }
  if(op.finish){const threadId=op.finish,id=turns.get(threadId);const item=reply(threadId,id,'离线子任务已完成，记录保留。');event('turn/completed',{threadId,turn:{id,status:'completed',items:[item]}});}
  if(op.close)event('item/completed',{threadId:sender,turnId:turns.get(sender),item:{type:'collabAgentToolCall',id:op.callId||'close-'+op.close,tool:'closeAgent',status:op.status||'completed',senderThreadId:op.sender||sender,receiverThreadIds:[op.close],agentsStates:{[op.close]:{status:'shutdown'}}}});
  if(op.resume){turns.set(op.resume,'resumed-delegated-turn');event('turn/started',{threadId:op.resume,turn:{id:'resumed-delegated-turn'}});}
  if(op.lateStop)event('turn/completed',{threadId:op.lateStop,turn:{id:turns.get(op.lateStop),status:'interrupted',items:[]}});
}
createInterface({input:process.stdin}).on('line',line=>{
  const m=JSON.parse(line);fs.appendFileSync(process.env.FIXTURE_TRACE,JSON.stringify({...m,_store:store})+'\n');
  if(m.id===undefined||!m.method)return;
  const p=m.params||{};let result={};
  switch(m.method){
    case 'initialize':break;
    case 'account/read':result={account:{type:'chatgpt'}};break;
    case 'skills/list':result={data:[{skills:[{name:'fixture',path:'/fixture/skill/SKILL.md',enabled:true,description:'Offline test skill'}]}]};break;
    case 'thread/start':result={thread:{id:'task-'+(++sequence)}};break;
    case 'thread/list':{
      const rows=[...catalog.values()].filter(t=>!!t.archived===!!p.archived&&(!p.searchTerm||t.name.includes(p.searchTerm))&&(!p.cwd||t.cwd===p.cwd)&&(!p.sourceKinds?.length||p.sourceKinds.includes(t.source)));
      const offset=Number(p.cursor)||0;result={data:rows.slice(offset,offset+p.limit).map(t=>nativeThread(t.id)),nextCursor:offset+p.limit<rows.length?String(offset+p.limit):null};break;
    }
    case 'thread/read':result={thread:nativeThread(p.threadId,p.includeTurns)||{id:p.threadId,...(parents.has(p.threadId)?{parentThreadId:parents.get(p.threadId)}:{}),agentNickname:'Generated nickname',turns:history.get(p.threadId)||[{id:'child-turn',status:'inProgress',items:[]}]}};break;
    case 'thread/turns/list':{
      let rows=[...(history.get(p.threadId)||[])];if(p.sortDirection==='desc')rows.reverse();const offset=Number(p.cursor)||0;
      result={data:rows.slice(offset,offset+1).map(t=>({...t,itemsView:'full'})),nextCursor:offset+1<rows.length?String(offset+1):null};break;
    }
    case 'thread/fork':{
      const source=nativeThread(p.threadId);const id='import-copy-'+Date.now()+'-'+(++sequence);
      catalog.set(id,{...source,id,cwd:p.cwd,source:'appServer',archived:false});history.set(id,structuredClone(history.get(p.threadId)));
      fs.writeFileSync(catalogPath,JSON.stringify([...catalog]));fs.writeFileSync(historyPath,JSON.stringify([...history]));result={thread:nativeThread(id)};break;
    }
    case 'thread/resume':result={thread:nativeThread(p.threadId)||{id:p.threadId}};if(p.threadId.startsWith('child-'))setTimeout(()=>event('item/started',{threadId:p.threadId,item:{type:'userMessage',id:'delegation',content:[{type:'text',text:'[studio-profile:research] 你是阿森，执行独立测试子任务。'}]}}),10);break;
    case 'turn/start':{
      const id='turn-'+(++sequence);turns.set(p.threadId,id);result={turn:{id}};
      event('turn/started',{threadId:p.threadId,turn:{id}});
      const prompt=p.input.find(x=>x.type==='text').text;
      userEcho(p,id);
      if(prompt.startsWith('lifecycle:'))lifecycle(p.threadId,JSON.parse(prompt.slice(10)));
      if(prompt.includes('complete'))event('turn/completed',{threadId:p.threadId,turn:{id,status:'completed',items:[reply(p.threadId,id,'Offline completed output','result'),{type:'fileChange',id:'file',changes:[{path:'result.txt'}]}]}});
      if(prompt.includes('对话演示'))reply(p.threadId,id,'好的，我先整理阅读角的布置方案。窗边放一张书桌，留出通往书架的走道。');
      if(prompt.startsWith('补充：'))event('turn/completed',{threadId:p.threadId,turn:{id,status:'completed',items:[reply(p.threadId,id,'已经加上绿植，并把灯光调整为暖色。你可以继续补充想法。')]}});
      if(prompt.includes('approve'))send({id:'approval-1',method:'item/commandExecution/requestApproval',params:{threadId:p.threadId,turnId:id,command:'fixture only'}});
      if(prompt.startsWith('policy-')) {
        const type=prompt.slice(7),params={threadId:p.threadId,turnId:id,command:'fixture read document',reason:'离线审批测试',cwd:p.cwd||'/fixture'};
        let method='item/commandExecution/requestApproval';
        if(type==='rule')params.availableDecisions=['accept',{acceptWithExecpolicyAmendment:{execpolicy_amendment:['fixture','read']}},'decline'];
        if(type==='once')params.availableDecisions=['accept','decline'];
        if(type==='session')params.availableDecisions=['accept','acceptForSession','decline'];
        if(type==='network')params.availableDecisions=['accept',{applyNetworkPolicyAmendment:{network_policy_amendment:{host:'fixture.example',action:'allow'}}},{applyNetworkPolicyAmendment:{network_policy_amendment:{host:'fixture.example',action:'deny'}}},'decline'];
        if(type==='files')method='item/fileChange/requestApproval';
        if(type==='permissions'){method='item/permissions/requestApproval';params.permissions={network:{enabled:true}};}
        send({id:'policy-'+type,method,params});
      }
      if(prompt.includes('queued'))for(const requestId of ['queued-1','queued-2'])send({id:requestId,method:'item/commandExecution/requestApproval',params:{threadId:p.threadId,turnId:id,command:'fixture only'}});
      if(prompt.includes('question'))send({id:'question-1',method:'item/tool/requestUserInput',params:{threadId:p.threadId,turnId:id,questions:[{id:'color',question:'Choose a color',options:[]}]}});
      if(prompt.includes('client-tool'))send({id:'client-tool-1',method:'item/tool/call',params:{threadId:p.threadId,turnId:id,callId:'call-client',namespace:'desktop',tool:'fixtureOnly',arguments:{}}});
      if(prompt.includes('children'))event('item/completed',{threadId:p.threadId,item:{type:'collabAgentToolCall',tool:'spawnAgent',prompt:'',receiverThreadIds:['child-a','child-b'],agentsStates:{}}});
      send({id:'clock-'+sequence,method:'currentTime/read',params:{}});
      break;
    }
    case 'turn/steer':{
      const text=p.input.find(x=>x.type==='text').text;
      if(text==='reject this input'){send({id:m.id,error:{code:-32000,message:'Fixture rejected input'}});return;}
      result={turnId:p.expectedTurnId};
      if(text.startsWith('lifecycle:'))lifecycle(p.threadId,JSON.parse(text.slice(10)));
      // Echo after the RPC acknowledgement, including an older peer without clientId.
      setTimeout(()=>userEcho(text==='legacy echo'?{...p,clientUserMessageId:null}:p,p.expectedTurnId),15);
      if(text.startsWith('补充：'))setTimeout(()=>event('turn/completed',{threadId:p.threadId,turn:{id:p.expectedTurnId,status:'completed',items:[reply(p.threadId,p.expectedTurnId,'已经加上绿植，并把灯光调整为暖色。你可以继续补充想法。')]}}),25);
      break;
    }
    case 'turn/interrupt':event('turn/completed',{threadId:p.threadId,turn:{id:turns.get(p.threadId)||'child-turn',status:'interrupted',items:[]}});break;
    default:send({id:m.id,error:{code:-32601,message:'Unknown fixture method '+m.method}});return;
  }
  send({id:m.id,result});
});
