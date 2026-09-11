// Import presentation records without replaying historical tool or lifecycle events.
import fs from 'node:fs';
import {recordItem} from './conversation.mjs';

const sourceKinds=['cli','vscode','exec','appServer','unknown'];
const busy=new Set(['starting','running','working','waiting','approval','stopping']);
const checkId=id=>{if(typeof id!=='string'||!/^[-\w]{1,160}$/.test(id))throw Error('会话 ID 无效');return id;};
const directoryExists=p=>{try{return fs.statSync(p).isDirectory();}catch{return false;}};
const isActive=th=>th.status?.type==='active'||th.turns?.some(t=>t.status==='inProgress');

export function createSessionImports({rpc,tasks,changed,profileLocks,validWorkspace}) {
  const pending=new Map();
  async function read(id,preview=false) {
    const th=(await rpc('thread/read',{threadId:checkId(id),includeTurns:false})).thread;
    if(!th||th.id!==id)throw Error('无法读取这条会话');
    if(th.historyMode!=='paginated'){
      const full=(await rpc('thread/read',{threadId:id,includeTurns:true})).thread;
      if(!full||full.id!==id)throw Error('无法读取这条会话');
      if(JSON.stringify(full).length>20*1024*1024)throw Error('历史记录过大，请在 Codex 中整理后再导入');
      return full;
    }
    const turns=[],seen=new Set();let cursor=null,bytes=0;
    do {
      const page=await rpc('thread/turns/list',{threadId:id,limit:preview?12:100,itemsView:'full',sortDirection:preview?'desc':'asc',...(cursor?{cursor}:{})});
      if(!Array.isArray(page.data))throw Error('Codex 返回的历史格式不受支持');
      if(page.data.some(t=>t.itemsView&&t.itemsView!=='full'))throw Error('Codex 未返回完整历史，请更新 Codex 后重试');
      turns.push(...page.data);bytes+=JSON.stringify(page.data).length;
      if(bytes>20*1024*1024||seen.size>=200)throw Error('历史记录过大，请在 Codex 中整理后再导入');
      cursor=page.nextCursor;
      if(cursor&&seen.has(cursor))throw Error('历史分页没有继续前进，请重试');
      if(cursor)seen.add(cursor);
    }while(cursor&&!preview);
    if(preview)turns.reverse();
    return {...th,turns,previewPartial:preview&&!!cursor};
  }
  function summary(th) {
    return {id:th.id,title:th.name||th.preview||'未命名会话',preview:th.preview||'',workspace:th.cwd||'',updatedAt:th.updatedAt||th.createdAt||0,model:th.model||'',source:typeof th.source==='string'?th.source:'subAgent',parentId:th.parentThreadId||null,active:isActive(th),imported:tasks.has(th.id),workspaceExists:directoryExists(th.cwd)};
  }
  function history(th) {
    const t={conversation:[],conversationVersion:1,messages:{},result:'',files:[],logs:[],turnId:null};
    const dependencies=new Set();
    for(const turn of th.turns||[]) {
      t.turnId=turn.id;
      for(const item of turn.items||[]) {
        recordItem(t,item,turn.id);
        if(item.type==='userMessage')for(const content of item.content||[])if(content.type!=='text'&&content.type!=='skill'){
          // Retain attachment presence without pretending this text view renders media.
          const entry=t.conversation.find(e=>e.nativeId===turn.id+':'+item.id);
          if(entry)entry.text+='\n[附件：'+content.type+'，请在原会话查看]';
          else t.conversation.push({id:turn.id+':'+item.id,nativeId:turn.id+':'+item.id,turnId:turn.id,role:'user',text:'[附件消息，请在原会话查看]'});
        }
        if(item.type==='agentMessage'){t.messages[turn.id+':'+item.id]=item.text||'';if(item.phase==='final_answer'||!item.phase)t.result=item.text||t.result;}
        if(item.type==='fileChange')for(const file of item.changes||[])if(!t.files.includes(file.path))t.files.push(file.path);
        if(item.type==='plan')t.plan=item.text;
        if(item.type==='dynamicToolCall')dependencies.add((item.namespace?item.namespace+'.':'')+item.tool);
        const label={commandExecution:'历史命令',mcpToolCall:'历史 MCP 工具',dynamicToolCall:'历史客户端工具',collabAgentToolCall:'历史团队协作',subAgentActivity:'历史子 agent',fileChange:'历史文件修改'}[item.type];
        if(label)t.logs.push({time:(turn.startedAt||th.createdAt||0)*1000,label,text:String(item.command||item.tool||item.agentPath||(item.changes||[]).map(f=>f.path).join('\n'))+'\n'+String(item.aggregatedOutput||'')});
      }
    }
    // Match normal task log retention; the native session remains the complete source.
    t.logs=t.logs.slice(-200).map(l=>({...l,text:l.text.slice(-12000)}));
    const last=th.turns?.at(-1);
    t.status=({completed:'completed',failed:'failed',interrupted:'interrupted'})[last?.status]||'interrupted';
    if(last?.error)t.error=last.error.message;
    return {...t,dependencies:[...dependencies]};
  }
  async function list(query) {
    const r=await rpc('thread/list',{limit:20,sortKey:'updated_at',sortDirection:'desc',modelProviders:[],sourceKinds,useStateDbOnly:true,archived:query.archived==='1',...(query.cursor?{cursor:String(query.cursor).slice(0,2000)}:{}),...(query.q?.trim()?{searchTerm:query.q.trim().slice(0,200)}:{}),...(query.cwd?{cwd:query.cwd}:{})});
    return {sessions:(r.data||[]).map(summary),nextCursor:r.nextCursor||null};
  }
  async function preview(id) {
    const th=await read(id,true),record=history(th);
    return {session:summary(th),conversation:record.conversation.slice(-40),dependencies:record.dependencies,partial:!!th.previewPartial||record.conversation.length>40,notice:'预览最近的对话。导入会保留可读取的完整文字历史；附件在原会话查看。旧子 agent 调用仅作为记录展示。'};
  }
  async function importSession(body) {
    const id=checkId(body.id),requestId=checkId(body.requestId),profile=body.profile;
    if(!profile?.id||!profile.name)throw Error('请选择承接会话的伙伴');
    if(!['resume','fork'].includes(body.mode))throw Error('请选择导入方式');
    const existing=[...tasks.values()].find(t=>t.imported?.requestId===requestId)||(body.mode==='resume'?tasks.get(id):null);
    if(existing)return {task:existing,alreadyImported:true};
    if(pending.has(requestId))return pending.get(requestId);
    if(profileLocks.has(profile.id))throw Error('正在准备这位伙伴的任务');
    if([...tasks.values()].some(t=>t.profileId===profile.id&&busy.has(t.status)))throw Error('这位伙伴正在工作，请先等待完成或选择其他伙伴');
    profileLocks.add(profile.id);
    const job=(async()=>{
      const source=await read(id);
      if(source.parentThreadId)throw Error('这是委派的子会话，请导入它的主会话；子任务仍由原委派者管理');
      if(source.ephemeral)throw Error('临时会话没有可持久化的历史，无法导入');
      if(isActive(source))throw Error('原会话仍在执行，请先在原客户端完成或停止任务，再导入');
      const record=history(source);let nativeId=id;
      let workspace=source.cwd||'';
      if(body.mode==='fork') {
        workspace=validWorkspace(body.workspace||source.cwd);
        const fork=await rpc('thread/fork',{threadId:id,cwd:workspace,excludeTurns:true,deferGoalContinuation:true,sandbox:'workspace-write',approvalPolicy:'on-request',approvalsReviewer:'user'});
        nativeId=fork.thread?.id;
        if(!nativeId||nativeId===id)throw Error('Codex 未返回新会话 ID，请刷新后检查导入结果');
      }
      const now=Date.now();
      const t={...record,id:nativeId,nativeStore:'native',profileId:profile.id,name:profile.name,parentId:null,completionOwnerId:null,workspace,prompt:source.preview||record.conversation.find(e=>e.role==='user')?.text||source.name||'导入的会话',title:source.name||source.preview||'导入的会话',activity:'已导入，等待继续',created:now,updated:now,endedAt:now,snapshot:structuredClone(profile),roster:[],request:null,imported:{sourceId:id,mode:body.mode,requestId,at:now,sourceCreatedAt:source.createdAt,sourceUpdatedAt:source.updatedAt,sourceTitle:source.name||'',model:source.model||'',dependencies:record.dependencies,continued:false}};
      delete t.dependencies;tasks.set(nativeId,t);changed(t);
      return {task:t};
    })();
    pending.set(requestId,job);
    try{return await job;}finally{profileLocks.delete(profile.id);pending.delete(requestId);}
  }
  async function prepare(t) {
    if([...tasks.values()].some(other=>other.id!==t.id&&other.profileId===t.profileId&&busy.has(other.status)))throw Error('这位伙伴正在执行另一项任务，请等它完成后继续');
    const workspace=validWorkspace(t.workspace);
    const th=await read(t.id);
    if(th.cwd&&validWorkspace(th.cwd)!==workspace)throw Error('原会话的工作目录已改变，请重新复制导入或在原客户端继续');
    if(isActive(th))throw Error('会话仍在其他客户端执行，请先停止或等待完成');
    const record=history(th);delete record.dependencies;
    // Refresh original-session imports before continuing, including messages added elsewhere.
    Object.assign(t,record);changed(t);
  }
  return {list,preview,importSession,prepare};
}
