#!/usr/bin/env node
// Offline protocol peer. Never contacts Codex, a model, or the network.
import {createInterface} from 'node:readline';
import fs from 'node:fs';
const send=m=>process.stdout.write(JSON.stringify(m)+'\n');
const event=(method,params)=>send({method,params});
let sequence=0;
const turns=new Map();
createInterface({input:process.stdin}).on('line',line=>{
  const m=JSON.parse(line);fs.appendFileSync(process.env.FIXTURE_TRACE,JSON.stringify(m)+'\n');
  if(m.id===undefined||!m.method)return;
  const p=m.params||{};let result={};
  switch(m.method){
    case 'initialize':break;
    case 'account/read':result={account:{type:'chatgpt'}};break;
    case 'skills/list':result={data:[{skills:[{name:'fixture',path:'/fixture/skill/SKILL.md',enabled:true,description:'Offline test skill'}]}]};break;
    case 'thread/start':result={thread:{id:'task-'+(++sequence)}};break;
    case 'thread/read':result={thread:{id:p.threadId,agentNickname:'Generated nickname',turns:[{id:'child-turn',status:'inProgress',items:[]}]}};break;
    case 'thread/resume':if(p.threadId.startsWith('child-'))setTimeout(()=>event('item/started',{threadId:p.threadId,item:{type:'userMessage',id:'delegation',content:[{type:'text',text:'[studio-profile:research] 你是阿森，执行独立测试子任务。'}]}}),10);break;
    case 'turn/start':{
      const id='turn-'+(++sequence);turns.set(p.threadId,id);result={turn:{id}};
      event('turn/started',{threadId:p.threadId,turn:{id}});
      const prompt=p.input.find(x=>x.type==='text').text;
      if(prompt.includes('complete'))event('turn/completed',{threadId:p.threadId,turn:{id,status:'completed',items:[{type:'agentMessage',id:'result',phase:'final_answer',text:'Offline completed output'},{type:'fileChange',id:'file',changes:[{path:'result.txt'}]}]}});
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
      if(prompt.includes('children'))event('item/completed',{threadId:p.threadId,item:{type:'collabAgentToolCall',tool:'spawnAgent',prompt:'',receiverThreadIds:['child-a','child-b'],agentsStates:{}}});
      send({id:'clock-'+sequence,method:'currentTime/read',params:{}});
      break;
    }
    case 'turn/steer':result={turnId:p.expectedTurnId};break;
    case 'turn/interrupt':event('turn/completed',{threadId:p.threadId,turn:{id:turns.get(p.threadId)||'child-turn',status:'interrupted',items:[]}});break;
    default:send({id:m.id,error:{code:-32601,message:'Unknown fixture method '+m.method}});return;
  }
  send({id:m.id,result});
});
