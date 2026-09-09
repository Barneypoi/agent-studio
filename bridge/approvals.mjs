// Present only decisions offered by Codex; resolve UI choices against the pending request.
export function approvalOptions(req) {
  const p=req.params||{}, method=req.method;
  const choices=[], details=[];
  let title='需要你的审批';
  const add=(label,hint,result,kind)=>choices.push({id:String(choices.length),label,hint,result,kind});
  if(p.reason)details.push(String(p.reason));
  if(p.cwd)details.push('工作目录：'+p.cwd);
  if(method==='item/commandExecution/requestApproval') {
    title=p.networkApprovalContext?'允许访问网络？':'允许执行命令？';
    if(p.networkApprovalContext)details.unshift('访问目标：'+p.networkApprovalContext.host+'（'+p.networkApprovalContext.protocol+'）');
    else if(p.command)details.unshift(String(p.command));
    if(p.additionalPermissions)details.push('额外权限：\n'+JSON.stringify(p.additionalPermissions,null,2));
    let decisions=p.availableDecisions;
    if(!Array.isArray(decisions)) {
      decisions=['accept','acceptForSession'];
      if(p.proposedExecpolicyAmendment?.length)decisions.push({acceptWithExecpolicyAmendment:{execpolicy_amendment:p.proposedExecpolicyAmendment}});
      for(const amendment of p.proposedNetworkPolicyAmendments||[])decisions.push({applyNetworkPolicyAmendment:{network_policy_amendment:amendment}});
      decisions.push('decline','cancel');
    }
    for(const decision of decisions) {
      const result={decision};
      if(decision==='accept')add('允许这一次','只批准这次请求。',result,'once');
      else if(decision==='acceptForSession')add('始终允许（本任务）','当前任务会话内记住这项授权。',result,'session');
      else if(decision==='decline')add('拒绝','拒绝这次请求。',result,'decline');
      else if(decision==='cancel')add('取消本轮','取消当前这一轮执行。',result,'cancel');
      else if(decision?.acceptWithExecpolicyAmendment) {
        const prefix=decision.acceptWithExecpolicyAmendment.execpolicy_amendment;
        if(Array.isArray(prefix)&&prefix.length&&prefix.every(x=>typeof x==='string'&&x.length))
          add('始终允许','记住命令前缀规则：'+prefix.map(x=>JSON.stringify(x)).join(' ')+'\n由 Codex 保存；后续匹配该规则的命令无需重复审批。',result,'rule');
      } else if(decision?.applyNetworkPolicyAmendment) {
        const rule=decision.applyNetworkPolicyAmendment.network_policy_amendment;
        if(rule?.host&&['allow','deny'].includes(rule.action))add(rule.action==='allow'?'始终允许此域名':'始终拒绝此域名','由 Codex 记住域名规则：'+rule.host,result,rule.action==='allow'?'rule':'deny-rule');
      }
    }
  } else if(method==='item/fileChange/requestApproval') {
    title='允许修改文件？';
    if(p.grantRoot)details.push('申请写入目录：'+p.grantRoot);
    add('允许这一次','只批准这次文件修改。',{decision:'accept'},'once');
    add('始终允许（本任务）','向 Codex 授予当前任务会话的文件修改权限。',{decision:'acceptForSession'},'session');
    add('拒绝','拒绝这次修改。',{decision:'decline'},'decline');
  } else if(method==='item/permissions/requestApproval') {
    title='允许使用这些权限？';details.push(JSON.stringify(p.permissions||{},null,2));
    add('允许这一次','授权在当前这一轮有效。',{permissions:p.permissions||{},scope:'turn'},'once');
    add('始终允许（本任务）','这些权限在当前任务会话后续轮次继续有效。',{permissions:p.permissions||{},scope:'session'},'session');
    add('拒绝','不授予这些权限。',{permissions:{},scope:'turn'},'decline');
  } else return null;
  return {title,details:details.join('\n\n'),choices};
}

export function publicApproval(req) {
  const options=approvalOptions(req);
  return options?{title:options.title,details:options.details,choices:options.choices.map(({result,...choice})=>choice)}:null;
}

export function approvalAnswer(req,body) {
  const options=approvalOptions(req);
  if(!options)return null;
  const choice=body.choice!==undefined?options.choices.find(c=>c.id===String(body.choice)):
    options.choices.find(c=>c.kind===(body.accept?'once':'decline'))||(!body.accept?options.choices.find(c=>c.kind==='cancel'):null);
  if(!choice)throw Error('此审批选项不可用，请刷新后重新选择');
  return {result:choice.result,label:choice.label};
}
