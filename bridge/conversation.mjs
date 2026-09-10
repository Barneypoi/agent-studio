import {randomUUID} from 'node:crypto';

export function conversation(t) {
  if(Array.isArray(t.conversation))return t.conversation;
  const entries=[];
  if(t.prompt)entries.push({id:'legacy-prompt',role:'user',text:t.prompt,speaker:t.parentId?'负责人':'你'});
  for(const [id,text] of Object.entries(t.messages||{}))if(text)entries.push({id:'legacy-'+id,role:'assistant',text});
  if(t.result&&!entries.some(e=>e.role==='assistant'&&e.text===t.result))entries.push({id:'legacy-result',role:'assistant',text:t.result});
  for(const [i,l] of (t.logs||[]).entries())if(l.label?.startsWith('你的补充'))entries.push({id:'legacy-input-'+i,role:'user',text:l.text,speaker:'你 · 旧版补充（顺序未保存）'});
  t.conversation=entries;
  t.conversationNotice='旧版记录正在等待同步完整对话。';
  return entries;
}

export function userEntry(t,text) {
  const entry={id:randomUUID(),role:'user',text,speaker:'你',pending:true,awaitingEcho:true};
  conversation(t).push(entry);return entry;
}

export function cancelEntry(t,entry) {
  if(!entry.nativeId)t.conversation=conversation(t).filter(e=>e!==entry);
}

export function recordItem(t,item,turnId='',delta=false) {
  if(!['userMessage','agentMessage'].includes(item.type))return;
  const text=item.type==='userMessage'?(item.content||[]).filter(c=>c.type==='text').map(c=>c.text).join('\n'):item.text||'';
  if(item.type==='userMessage'&&!text)return;
  const entries=conversation(t),nativeId=String(turnId)+':'+item.id,role=item.type==='userMessage'?'user':'assistant';
  let entry=entries.find(e=>e.nativeId===nativeId||(item.clientId&&e.id===item.clientId));
  if(!entry&&role==='user'&&!item.clientId)entry=entries.find(e=>e.awaitingEcho&&!e.nativeId&&e.role==='user'&&e.text===text);
  if(!entry){entry={id:item.clientId||nativeId,role,text:'',speaker:role==='user'?(t.parentId?'负责人':'你'):undefined};entries.push(entry);}
  entry.nativeId=nativeId;entry.turnId=turnId;entry.pending=false;entry.awaitingEcho=false;entry.text=delta?entry.text+text:text;
}

export function restoreConversation(t,turns) {
  const restored={parentId:t.parentId,conversation:[]};
  for(const turn of turns||[])for(const item of turn.items||[])recordItem(restored,item,turn.id);
  if(!restored.conversation.length)return false;
  const current=conversation(t),merged=restored.conversation;
  for(const entry of current) {
    const existing=merged.find(e=>e.id===entry.id||(entry.nativeId&&e.nativeId===entry.nativeId));
    if(existing){if(entry.text.length>existing.text.length)existing.text=entry.text;continue;}
    if(entry.id.startsWith('legacy-')) {
      if(entry.id.startsWith('legacy-input-')&&!merged.some(e=>e.role==='user'&&e.text===entry.text))merged.push(entry);
    } else merged.push(entry);
  }
  t.conversation=merged;t.conversationVersion=1;delete t.conversationNotice;return true;
}
