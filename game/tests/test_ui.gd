extends SceneTree
var app
var checks=0
func verify(value:bool,description:String) -> void:
	if not value:push_error("FAIL "+description);quit(1);assert(value,description)
	checks+=1
func find_button(node:Node,text:String) -> Button:
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var found=find_button(child,text)
		if found:return found
	return null
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var test_dir=OS.get_environment("AGENT_STUDIO_DATA")
	if not test_dir.contains("ui-test"):push_error("Use an isolated ui-test data directory");quit(1);return
	if FileAccess.file_exists(test_dir.path_join("studio.json")):DirAccess.remove_absolute(test_dir.path_join("studio.json"))
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	verify(app.tab=="studio","opens at studio")
	verify(app.poll_timer.is_stopped(),"offline mode never polls an existing bridge")
	app._switch_tab("tasks");find_button(app,"导入 Codex 会话").pressed.emit();await process_frame
	verify(app.tab=="imports" and find_button(app,"搜索")!=null and find_button(app,"导入并查看").disabled,"import opens a read-only browser and cannot submit before preview")
	find_button(app,"返回任务与成果").pressed.emit();app._switch_tab("studio")
	var before_greeting=JSON.stringify([app.tasks,app.model.data])
	find_button(app,"挥挥手").pressed.emit()
	verify(not app.world.social.effects.is_empty() and JSON.stringify([app.tasks,app.model.data])==before_greeting and app.poll_timer.is_stopped(),"greeting is local and leaves tasks, configuration and bridge polling untouched")
	app.nav_buttons.build.pressed.emit();await process_frame
	verify(app.world.mode=="build","build tab changes map interaction")
	var before=app.model.data.furniture.size()
	app._begin_furniture("plant");app.world.placed.emit(Vector2i(7,7));await process_frame
	verify(app.model.data.furniture.size()==before+1,"map placement signal commits furniture")
	app._undo();verify(app.model.data.furniture.size()==before,"undo button restores world")
	app._new_room();await process_frame
	verify(find_button(app,"选择房间位置")!=null,"room creation dialog is functional")
	find_button(app,"选择房间位置").pressed.emit();app.world.placed.emit(Vector2i(16,2));await process_frame
	verify(app.model.data.rooms.size()==2,"room dialog and map placement expand studio")
	var theme_button=find_button(app,"＋ 玻璃花园  ·  8 × 7")
	theme_button.pressed.emit()
	verify(app.world.mode=="room" and app.world.placement.template=="garden","theme button starts a furnished room preview")
	var furniture_before=app.model.data.furniture.size()
	app.world.placed.emit(Vector2i(23,2));await process_frame
	verify(app.model.data.rooms.size()==3 and app.model.data.furniture.size()>furniture_before,"theme preview places a complete furnished expansion")
	app._undo();verify(app.model.data.rooms.size()==2 and app.model.data.furniture.size()==furniture_before,"one UI undo removes the furnished expansion")
	app.nav_buttons.people.pressed.emit();await process_frame
	find_button(app,"＋ 新伙伴").pressed.emit();await process_frame
	verify(app.model.data.profiles.size()==4,"new character button creates profile")
	var name_input
	for n in app.side.get_children():
		if n is LineEdit:name_input=n
	name_input.text="晴川";name_input.text_changed.emit("晴川")
	var picks=[]
	for n in app.side.get_children():
		if n is HBoxContainer:
			for c in n.get_children():
				if c is OptionButton:picks.append(c)
	picks[0].select(3);picks[0].item_selected.emit(3)
	picks[2].select(4);picks[2].item_selected.emit(4)
	find_button(app,"保存角色").pressed.emit();await process_frame
	var p=app._profile(app.selected_profile)
	verify(p.name=="晴川" and int(p.hair)==3 and int(p.shirt)==4,"appearance controls persist selected values")
	app.skills=[{"name":"测试用本地技能","description":"UI 验证资料，不连接外部服务。","path":"/fixture/SKILL.md","enabled":true}]
	app.nav_buttons.skills.pressed.emit();await process_frame
	var skill_button=find_button(app,"测试用本地技能")
	verify(skill_button!=null,"skill list presents metadata")
	skill_button.button_pressed=true
	find_button(app,"保存技能组合").pressed.emit()
	verify(app._profile(app.selected_profile).skills==["/fixture/SKILL.md"],"skill checkbox and save persist selection")
	app.tasks=[{"id":"fixture-task","profileId":p.id,"name":"晴川","prompt":"离线界面验证","workspace":app.model.data.workspace,"status":"completed","activity":"执行完成","messages":"这是一条用于界面验证的离线记录。","result":"","files":[],"logs":[{"label":"离线记录","text":"fixture"}],"snapshot":p,"created":1,"parentId":null}]
	var newer=app.tasks[0].duplicate(true);newer.id="newer-stopped-task";newer.created=2;newer.status="interrupted"
	app.tasks[0].status="running";app.tasks.append(newer)
	verify(app._task_for(p.id).id=="fixture-task","resuming an older task takes priority over a newer stopped task")
	app.tasks.pop_back();app.tasks[0].status="completed"
	app.nav_buttons.tasks.pressed.emit();await process_frame
	find_button(app,"查看任务与成果").pressed.emit();await process_frame
	verify(app.active_task_id=="fixture-task" and not app.side_scroll.visible,"task button opens docked conversation")
	var panel=app.task_panels["fixture-task"]
	verify(panel.get_meta("finish").visible and not panel.get_meta("stop").visible,"completed conversation offers End instead of Stop")
	verify(panel.get_meta("output").text.contains("离线记录"),"task output is rendered")
	app.tasks[0].conversation=[{"id":"user-1","role":"user","text":"请布置一个阅读角。"},{"id":"agent-1","role":"assistant","text":"保留窗边光线，书架靠墙。\n".repeat(40)},{"id":"user-2","role":"user","text":"再加一盆绿植。"},{"id":"agent-2","role":"assistant","text":"好的，放在书架旁。"}]
	app._update_task_panel(panel,app.tasks[0])
	for i in range(8):await process_frame
	var chat=panel.get_meta("chat")
	verify(chat.visible and not panel.get_meta("output").visible and chat.bubbles.size()==4,"conversation presents both inputs and both replies as bubbles")
	verify(chat.bubbles["user-2"].panel.position.x>chat.bubbles["agent-2"].panel.position.x,"user bubbles align right and partner replies left")
	verify(panel.get_meta("output").text.contains("你\n再加一盆绿植。\n\n晴川\n好的"),"copy transcript includes speakers and interleaved messages")
	verify(chat.scroll_vertical>=chat.get_v_scroll_bar().max_value-chat.get_v_scroll_bar().page-4,"new conversation opens at its latest message")
	chat.scroll_vertical=0
	app.tasks[0].conversation[3].text+=" 我继续整理。"
	var first_bubble=chat.bubbles["user-1"].body
	app._update_task_panel(panel,app.tasks[0])
	for i in range(8):await process_frame
	verify(chat.scroll_vertical==0 and chat.bubbles["user-1"].body==first_bubble,"stream updates preserve an earlier reading position and existing message nodes")
	panel.get_meta("mode").select(1);panel.get_meta("mode").item_selected.emit(1)
	verify(panel.get_meta("output").text.contains("fixture") and not chat.visible and panel.get_meta("output").visible,"tool log tab renders records")
	for i in range(3):await process_frame
	verify(panel.get_parent()==app.sidebar and not app.world.get_global_rect().intersects(panel.get_global_rect()),"conversation occupies its own column without covering the room")
	var time_before=app.world.elapsed
	panel.get_meta("input").text="保留这条尚未发送的补充"
	panel.get_meta("input").grab_focus();await process_frame;await process_frame
	verify(app.world.elapsed>time_before and not paused,"room continues animating while composing")
	newer.profileId="lead";app.tasks.append(newer)
	app.world.selected.emit("profile","lead");await process_frame
	verify(app.active_task_id==newer.id and not panel.visible,"clicking another character switches the dock")
	app.world.selected.emit("profile",p.id);await process_frame
	verify(panel.visible and panel.get_meta("input").text=="保留这条尚未发送的补充","switching characters preserves unsent drafts")
	var width_before=app.world.size.x
	app.workspace_split.split_offset-=70
	app.workspace_split.dragged.emit(app.workspace_split.split_offset)
	for i in range(3):await process_frame
	verify(app.world.size.x<width_before and not app.world.get_global_rect().intersects(panel.get_global_rect()),"resizing the divider reallocates space without an overlay")
	find_button(panel,"收起").pressed.emit();await process_frame
	verify(app.active_task_id=="" and app.side_scroll.visible,"collapsing the conversation restores the sidebar")
	var older=app.tasks[0].duplicate(true);older.id="older-completed-task";older.created=0;app.tasks.append(older)
	app.tasks[0].endedAt=123;app._refresh_characters()
	verify(app._task_for(p.id).is_empty() and not app.world.states.has(p.id),"ending the current conversation returns the character to idle without resurfacing old checkmarks")
	app._open_task("fixture-task");await process_frame
	verify(panel.get_meta("status").text=="对话已结束" and not panel.get_meta("finish").visible and panel.get_meta("output").text.contains("fixture"),"ended history remains readable")
	app.tasks[0].erase("endedAt");app.tasks[0].status="running";app._refresh_characters();app._update_task_panel(panel,app.tasks[0])
	verify(app.world.states[p.id].status=="running" and panel.get_meta("stop").visible and not panel.get_meta("finish").visible,"continuing a conversation restores live character state and Stop")
	var delegated=app.tasks[0].duplicate(true);delegated.id="delegated-task";delegated.profileId="sub-fixture";delegated.name="临时伙伴";delegated.parentId="fixture-task";delegated.status="completed"
	app.tasks.append(delegated);app._refresh_characters();app._open_task(delegated.id);await process_frame
	var delegated_panel=app.task_panels[delegated.id]
	verify(delegated_panel.get_meta("status").text=="完成 · 待晴川确认" and not delegated_panel.get_meta("finish").visible,"delegated work waits for its assigning agent, without a user End button")
	verify(app.world.actors.has("sub-fixture"),"completed delegated character remains until owner releases it")
	delegated.endedAt=456;delegated.endedBy="fixture-task";app._refresh_characters();app._update_task_panel(delegated_panel,delegated)
	verify(not app.world.actors.has("sub-fixture") and delegated_panel.get_meta("status").text=="已由晴川释放" and delegated_panel.get_meta("output").text.contains("再加一盆绿植"),"owner release removes temporary actor and preserves readable history")
	delegated.erase("endedAt");delegated.erase("endedBy");delegated.completionOwnerId=null;app._refresh_characters();app._update_task_panel(delegated_panel,delegated)
	verify(not delegated_panel.get_meta("finish").visible and delegated_panel.get_meta("status").text=="完成 · 待晴川确认","legacy inferred user ownership cannot override the original delegator")
	var reloaded=load("res://studio_model.gd").new();reloaded.load_data(app.model.save_path)
	verify(reloaded.data.profiles.size()==4 and reloaded.data.rooms.size()==2,"UI changes survive reload")
	print("UI_CHECKS_OK ",checks)
	quit(0)
