extends Control
const Model=preload("res://studio_model.gd")
const World=preload("res://world.gd")
const Avatar=preload("res://avatar.gd")
const ACTIVE=["starting","running","working","waiting","approval","stopping"]
const INK=Color("2d4745")
const MUTED=Color("7d897d")
const PAPER=Color("f2eddf")
var model=Model.new()
var world
var side:VBoxContainer
var side_scroll:ScrollContainer
var workspace_split:HSplitContainer
var sidebar:PanelContainer
var sidebar_width=358.0
var conversation_width=490.0
var active_task_id=""
var root_dir=""
var data_dir=""
var bridge_info=""
var bridge_url=""
var bridge_token=""
var bridge_pid=-1
var owns_bridge=false
var poll:HTTPRequest
var polling=false
var bridge_failures=0
var connected=false
var tasks:Array=[]
var skills:Array=[]
var skills_requested=false
var submitting=false
var tab="studio"
var selected_profile="lead"
var selected_furniture=""
var selected_room="r1"
var status_label:Label
var footer_label:Label
var workspace_label:Button
var header_count:Label
var toast_label:Label
var nav_buttons={}
var task_panels={}
var live_labels={}
var profile_draft={}
var skill_draft:Array=[]
var task_prompt:TextEdit
var team_checkbox:CheckBox
var task_role_picker:OptionButton
var last_signature=""
var poll_timer:Timer
var build_kind="desk"
var build_rotation=0
var started=false

func _ready() -> void:
	Engine.max_fps=30
	get_tree().auto_accept_quit=false
	var screen_scale=maxf(1.0,DisplayServer.screen_get_scale())
	var usable=DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_min_size(Vector2i(Vector2(1100,700)*screen_scale))
	var desired=Vector2i(Vector2(1380,860)*screen_scale)
	desired.x=mini(desired.x,int(usable.size.x*.94));desired.y=mini(desired.y,int(usable.size.y*.91))
	DisplayServer.window_set_size(desired)
	DisplayServer.window_set_position(usable.position+(usable.size-desired)/2)
	root_dir=OS.get_environment("AGENT_STUDIO_ROOT")
	if root_dir=="":root_dir=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	data_dir=OS.get_environment("AGENT_STUDIO_DATA")
	if data_dir=="":data_dir=root_dir.path_join("data")
	DirAccess.make_dir_recursive_absolute(data_dir)
	bridge_info=data_dir.path_join("bridge.json")
	model.load_data(data_dir.path_join("studio.json"))
	if model.data.workspace=="":
		var sample=data_dir.path_join("sample-project")
		DirAccess.make_dir_recursive_absolute(sample)
		for filename in ["README.md","welcome.md"]:
			if not FileAccess.file_exists(sample.path_join(filename)):DirAccess.copy_absolute(root_dir.path_join("sample-project").path_join(filename),sample.path_join(filename))
		model.data.workspace=sample
	_make_theme();_build_shell();_refresh_characters();_render_panel()
	world.call_deferred("center_map")
	if model.last_error!="":toast(model.last_error)
	poll=HTTPRequest.new();add_child(poll);poll.timeout=10;poll.request_completed.connect(_poll_complete)
	poll_timer=Timer.new();poll_timer.wait_time=.8;poll_timer.timeout.connect(_poll_bridge);add_child(poll_timer)
	if "--no-bridge" not in OS.get_cmdline_user_args():_start_bridge();poll_timer.start()
	else:status_label.text="离线编辑模式";started=true
	if "--self-test" in OS.get_cmdline_user_args():call_deferred("_self_test")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):call_deferred("_capture",argument.trim_prefix("--capture="))

func _make_theme() -> void:
	var t=Theme.new();var f=load("res://assets/NotoSansCJKsc-Regular.otf")
	t.default_font=f;t.default_font_size=15
	t.set_color("font_readonly_color","TextEdit",INK)
	t.set_stylebox("read_only","TextEdit",box("fffaf0",7,10))
	for type in ["Label","Button","LineEdit","TextEdit","CheckBox","CheckButton","OptionButton","SpinBox"]:
		t.set_color("font_color",type,INK)
		t.set_color("font_hover_color",type,INK)
		t.set_color("font_pressed_color",type,INK)
		t.set_color("font_hover_pressed_color",type,INK)
		t.set_color("font_focus_color",type,INK)
	t.set_color("font_disabled_color","Button",Color("a5aca0"))
	for type in ["Button","OptionButton"]:
		t.set_stylebox("normal",type,box("e6e3d5",7,10))
		t.set_stylebox("hover",type,box("d7dfcf",7,10))
		t.set_stylebox("pressed",type,box("b8cfbb",7,10))
		t.set_stylebox("disabled",type,box("e6e5dc",7,10))
		t.set_stylebox("focus",type,border("8aa791",7))
	for type in ["LineEdit","TextEdit"]:
		t.set_stylebox("normal",type,box("fffaf0",7,10))
		t.set_stylebox("focus",type,border("8aa791",7))
		t.set_color("caret_color",type,INK);t.set_color("selection_color",type,Color("c7d9c6"))
		t.set_color("font_placeholder_color",type,Color("89958a"))
	t.set_stylebox("panel","PopupMenu",box("f2eddf",8,8))
	t.set_color("font_color","PopupMenu",INK)
	t.set_stylebox("panel","AcceptDialog",box("f2eddf",10,16))
	t.set_stylebox("panel","Window",box("f2eddf",10,16))
	t.set_constant("separation","VBoxContainer",12);t.set_constant("separation","HBoxContainer",10)
	t.set_constant("separation","HSplitContainer",10)
	t.set_stylebox("split_bar_background","HSplitContainer",box("d6d9c9",0,0))
	t.set_color("font_color","RichTextLabel",INK)
	t.set_color("default_color","RichTextLabel",INK)
	t.set_stylebox("scroll","VScrollBar",box("e6e3d5",3,0))
	t.set_stylebox("grabber","VScrollBar",box("a6b8a5",3,0))
	t.set_stylebox("grabber_highlight","VScrollBar",box("809a85",3,0))
	theme=t

func box(color:String,radius:int=8,pad:int=12) -> StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=Color(color);s.set_corner_radius_all(radius)
	s.content_margin_left=pad;s.content_margin_right=pad;s.content_margin_top=pad;s.content_margin_bottom=pad
	return s

func border(color:String,radius:int) -> StyleBoxFlat:
	var s=box("00000000",radius,10);s.border_color=Color(color);s.set_border_width_all(2);return s

func label(text:String,size_value:int=15,color:Color=INK) -> Label:
	var n=Label.new();n.text=text;n.add_theme_font_size_override("font_size",size_value);n.add_theme_color_override("font_color",color)
	return n

func wrapped(text:String,size_value:int=14,color:Color=MUTED) -> Label:
	var n=label(text,size_value,color);n.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;n.size_flags_horizontal=Control.SIZE_EXPAND_FILL;return n

func button(text:String,fn:Callable,primary:bool=false) -> Button:
	var n=Button.new();n.text=text;n.custom_minimum_size.y=38;n.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;n.pressed.connect(fn)
	if primary:
		n.add_theme_stylebox_override("normal",box("315950",7,11));n.add_theme_stylebox_override("hover",box("426e60",7,11));n.add_theme_stylebox_override("pressed",box("26483f",7,11))
		n.add_theme_color_override("font_color",Color("f7edda"));n.add_theme_color_override("font_hover_color",Color("ffffff"));n.add_theme_color_override("font_pressed_color",Color("ffffff"))
	return n

func row(parent:Node) -> HBoxContainer:
	var n=HBoxContainer.new();parent.add_child(n);return n

func spacer(parent:Node) -> void:
	var n=Control.new();n.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(n)

func section(text:String) -> void:
	side.add_child(label(text,20))

func note(text:String) -> void:
	side.add_child(wrapped(text))

func _build_shell() -> void:
	var bg=ColorRect.new();bg.color=PAPER;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	var shell=VBoxContainer.new();shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shell.add_theme_constant_override("separation",0);add_child(shell)
	var top=PanelContainer.new();top.custom_minimum_size.y=76;top.add_theme_stylebox_override("panel",box("f2eddf",0,18));shell.add_child(top)
	var header=row(top);var brand=VBoxContainer.new();brand.add_theme_constant_override("separation",0);header.add_child(brand)
	brand.add_child(label("栖点工作室",25));brand.add_child(label("A G E N T   S T U D I O",10,MUTED))
	var motto=label("给灵感一个开工的地方",14,MUTED);header.add_child(motto);spacer(header)
	header_count=label("",13,MUTED);header.add_child(header_count)
	status_label=label("连接 Codex…",13);header.add_child(status_label)
	header.add_child(button("重连",func():_api("/connect",{},func(_r):toast("已重新连接 Codex"))))
	header.add_child(button("使用说明",_help))
	workspace_split=HSplitContainer.new();workspace_split.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(workspace_split)
	workspace_split.get_drag_area_control().tooltip_text="拖动分隔线，调整房间与侧栏的宽度"
	workspace_split.resized.connect(_resize_sidebar)
	workspace_split.dragged.connect(func(offset):
		var width=workspace_split.size.x*.5-offset-5
		if active_task_id=="":sidebar_width=width
		else:conversation_width=width)
	var left=VBoxContainer.new();left.add_theme_constant_override("separation",0);left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;workspace_split.add_child(left)
	var mapbar=PanelContainer.new();mapbar.add_theme_stylebox_override("panel",box("203a3c",0,12));left.add_child(mapbar)
	var tools=row(mapbar);tools.add_child(label("01  /  WORKSHOP",12,Color("b6c9b6")))
	spacer(tools);tools.add_child(button("−",func():world.zoom=maxf(.4,world.zoom/1.15)))
	tools.add_child(button("居中",func():world.center_map()));tools.add_child(button("＋",func():world.zoom=minf(2.1,world.zoom*1.15)))
	var pin=CheckBox.new();pin.text="窗口置顶";pin.toggled.connect(func(v):DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,v));tools.add_child(pin)
	world=World.new();world.model=model;world.size_flags_vertical=Control.SIZE_EXPAND_FILL;world.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.add_child(world)
	world.selected.connect(_world_selected);world.placed.connect(_world_placed);world.notification.connect(toast)
	world.resized.connect(func():world.call_deferred("center_map"))
	var foot=PanelContainer.new();foot.add_theme_stylebox_override("panel",box("203a3c",0,13));left.add_child(foot)
	var fr=row(foot);footer_label=label("点击伙伴交流 · 滚轮缩放 · 中键拖动画布",12,Color("b6c9b6"));fr.add_child(footer_label);spacer(fr)
	fr.add_child(button("撤销",_undo));fr.add_child(button("保存",func():if model.save():toast("工作室已保存")))
	sidebar=PanelContainer.new();sidebar.custom_minimum_size.x=358;sidebar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sidebar.add_theme_stylebox_override("panel",box("f2eddf",0,18));workspace_split.add_child(sidebar)
	side_scroll=ScrollContainer.new();side_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;side_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sidebar.add_child(side_scroll)
	side=VBoxContainer.new();side.size_flags_horizontal=Control.SIZE_EXPAND_FILL;side.custom_minimum_size.x=310;side_scroll.add_child(side)
	var bottom=PanelContainer.new();bottom.add_theme_stylebox_override("panel",box("e3dfcf",0,12));shell.add_child(bottom)
	var nav=row(bottom)
	for entry in [["studio","工作室"],["build","布置"],["people","伙伴"],["skills","技能"],["tasks","任务与成果"]]:
		var key=entry[0];var b=button(entry[1],func():_switch_tab(key));b.custom_minimum_size.x=116;nav.add_child(b);nav_buttons[key]=b
	spacer(nav);workspace_label=button("项目 · "+model.data.workspace.get_file(),_workspace_dialog);workspace_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;workspace_label.custom_minimum_size.x=180;nav.add_child(workspace_label)
	toast_label=label("",14,Color("fff4d7"));toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;toast_label.add_theme_stylebox_override("normal",box("3c6255",8,12));toast_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);toast_label.offset_left=-300;toast_label.offset_right=300;toast_label.offset_top=88;toast_label.offset_bottom=134;toast_label.visible=false;add_child(toast_label)

func _switch_tab(value:String) -> void:
	_close_task();tab=value;_cancel_placement();_render_panel()

func _resize_sidebar() -> void:
	var width=sidebar_width if active_task_id=="" else conversation_width
	workspace_split.split_offset=roundi(workspace_split.size.x*.5-width-5)

func _close_task() -> void:
	if active_task_id=="":return
	task_panels[active_task_id].hide();active_task_id="";side_scroll.show()
	sidebar.custom_minimum_size.x=358;_cancel_placement();_resize_sidebar()

func _clear_panel() -> void:
	for n in side.get_children():side.remove_child(n);n.queue_free()
	side_scroll.scroll_vertical=0;live_labels.clear()
	for key in nav_buttons:
		nav_buttons[key].add_theme_stylebox_override("normal",box("b8cfbb" if key==tab else "e6e3d5",7,10))

func _render_panel() -> void:
	_clear_panel()
	match tab:
		"studio":_studio_panel()
		"build":_build_panel()
		"people":_people_panel()
		"skills":_skills_panel()
		"tasks":_tasks_panel()

func _profile(id:String) -> Dictionary:
	for p in model.data.profiles:
		if p.id==id:return p
	return model.data.profiles[0]

func _task_for(id:String) -> Dictionary:
	var found={}
	for t in tasks:
		if t.profileId==id and _prefer_task(t,found):found=t
	return {} if _task_ended(found) else found

func _task_ended(t:Dictionary) -> bool:
	return t.get("endedAt",0)!=0 and t.get("status","") in ["completed","failed","interrupted"]

func _task_family(id:String) -> Array:
	var ids=[id];var index=0
	while index<ids.size():
		for t in tasks:
			if t.get("parentId")==ids[index] and not ids.has(t.id):ids.append(t.id)
		index+=1
	return tasks.filter(func(t):return ids.has(t.id))

func _prefer_task(candidate:Dictionary,current:Dictionary) -> bool:
	if current.is_empty():return true
	if ACTIVE.has(candidate.status)!=ACTIVE.has(current.status):return ACTIVE.has(candidate.status)
	return float(candidate.get("updated",candidate.created))>float(current.get("updated",current.created))

func _status_text(t:Dictionary) -> String:
	if t.is_empty():return "待命 · 随时可以开工"
	if _task_ended(t):return "对话已结束"+({"failed":" · 执行失败","interrupted":" · 已停止"}.get(t.status,""))
	return {"starting":"准备开始","running":"正在工作","working":"正在工作","approval":"等待审批","waiting":"需要你的回答","completed":"完成 · 待验收","failed":"执行失败","interrupted":"已停止","stopping":"正在停止","disconnected":"连接中断 · 状态未知"}.get(t.status,t.status)

func _studio_panel() -> void:
	section("今天，做点什么？")
	note("把一个真实任务交给伙伴。你可以随时回来查看进展、补充信息。")
	task_role_picker=OptionButton.new();task_role_picker.custom_minimum_size.y=40;side.add_child(task_role_picker)
	for i in range(model.data.profiles.size()):
		var p=model.data.profiles[i];task_role_picker.add_item(p.name+" · "+str(p.role).split("：")[0],i)
		if p.id==selected_profile:task_role_picker.select(i)
	task_role_picker.item_selected.connect(func(i):selected_profile=model.data.profiles[i].id;world.selected_id=selected_profile)
	task_prompt=TextEdit.new();task_prompt.custom_minimum_size.y=168;task_prompt.placeholder_text="例如：检查这个项目的结构，找出最值得改进的一处，并给出有依据的建议。";task_prompt.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;side.add_child(task_prompt)
	team_checkbox=CheckBox.new();team_checkbox.text="允许负责人分配给子 agent";team_checkbox.button_pressed=true;side.add_child(team_checkbox)
	note("角色使用已保存的职责与技能；子 agent 出现后会自动加入房间。")
	side.add_child(button("交给伙伴  →",_submit_task,true))
	side.add_child(HSeparator.new());side.add_child(label("我的伙伴",17))
	for p in model.data.profiles:
		var t=_task_for(p.id)
		var h=row(side);var av=Avatar.new();av.profile=p;av.pixel_scale=1.4;av.custom_minimum_size=Vector2(48,58);h.add_child(av)
		var v=VBoxContainer.new();v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.add_theme_constant_override("separation",3);h.add_child(v)
		v.add_child(button(p.name,func():selected_profile=p.id;world.selected_id=p.id;_switch_tab("people")))
		var state=label(_status_text(t),12,MUTED);v.add_child(state);live_labels[p.id]=state
		if not t.is_empty():h.add_child(button("查看",func():_open_task(t.id)))

func _build_panel() -> void:
	section("布置你的工作室")
	note("家具按格摆放。绿色可放置，红色表示重叠或堵住了通路。")
	var grid=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);side.add_child(grid)
	for kind in Model.CATALOG:
		var c=Model.CATALOG[kind];var b=button(c.name+"\n"+str(c.w)+" × "+str(c.h),func():_begin_furniture(kind));b.custom_minimum_size=Vector2(146,62);grid.add_child(b)
	side.add_child(HSeparator.new());side.add_child(label("房间扩建",17))
	var r=row(side);r.add_child(button("＋ 新房间",_new_room));r.add_child(button("取消放置",_cancel_placement))
	for room in model.data.rooms:
		side.add_child(button(room.name+"  ·  "+str(int(room.w))+" × "+str(int(room.h)),func():_room_dialog(room.id)))
	if selected_furniture!="":
		var f={}
		for item in model.data.furniture:
			if item.id==selected_furniture:f=item
		if not f.is_empty():
			side.add_child(HSeparator.new());side.add_child(label("选中 · "+Model.CATALOG[f.kind].name,17))
			var edit=row(side);edit.add_child(button("移动",func():_move_furniture(f)));edit.add_child(button("旋转 R",_rotate));edit.add_child(button("删除",_delete_furniture))
			if f.kind=="desk":
				var pick=OptionButton.new();pick.add_item("未绑定工位")
				for i in range(model.data.profiles.size()):
					var p=model.data.profiles[i];pick.add_item(p.name)
					if p.id==f.get("owner",""):pick.select(i+1)
				pick.item_selected.connect(func(i):
					model.checkpoint();var owner="" if i==0 else model.data.profiles[i-1].id
					for item in model.data.furniture:
						if item.get("owner","")==owner and owner!="":item.owner=""
					f.owner=owner;model.save();world.layout_changed();toast("工位绑定已保存"))
				side.add_child(pick)
	footer_label.text="编辑模式 · 点击家具选中 · R 旋转 · Delete 删除 · Ctrl/Cmd Z 撤销"

func _begin_furniture(kind:String) -> void:
	build_kind=kind;build_rotation=0;world.mode="furniture";world.moving_id="";world.placement={"id":model.new_id("f"),"kind":kind,"x":0,"y":0,"rot":0,"owner":""}
	toast("选择位置放置「"+Model.CATALOG[kind].name+"」")

func _move_furniture(f:Dictionary) -> void:
	world.mode="furniture";world.moving_id=f.id;world.placement=f.duplicate(true);build_rotation=int(f.rot);toast("点击新的位置，右键取消")

func _cancel_placement() -> void:
	world.mode="build" if tab=="build" and active_task_id=="" else "inspect";world.placement={};world.moving_id="";world.last_hover_error=""
	footer_label.text="点击伙伴交流 · 滚轮缩放 · 中键拖动画布" if world.mode=="inspect" else "点击家具选中 · R 旋转 · Delete 删除 · Ctrl/Cmd Z 撤销"

func _world_placed(cell:Vector2i) -> void:
	var item=world.placement.duplicate(true);item.x=cell.x;item.y=cell.y
	var ok=model.put_furniture(item,world.moving_id) if world.mode=="furniture" else model.put_room(item)
	if not ok:toast(model.last_error);return
	var room_mode=world.mode=="room"
	selected_furniture=item.id if not room_mode else "";world.selected_id=item.id
	world.layout_changed();_cancel_placement();_render_panel();toast("房间已扩建，连接门已就位" if room_mode else "布置已保存")
	if room_mode:world.center_map()

func _world_selected(kind:String,id:String) -> void:
	if kind=="cancel":_cancel_placement();return
	if kind=="profile":
		selected_profile=id;world.selected_id=id
		var t=_task_for(id)
		if not t.is_empty():_open_task(t.id)
		else:_switch_tab("people")
	elif kind=="furniture":
		selected_furniture=id
		if tab=="build":_render_panel();return
		var f={}
		for item in model.data.furniture:
			if item.id==id:f=item
		match f.get("kind",""):
			"board":_switch_tab("tasks")
			"books":_switch_tab("skills")
			"cabinet":OS.shell_open(model.data.workspace)
			"desk":
				if f.get("owner","")!="":selected_profile=f.owner;_switch_tab("people")
			_:toast(Model.CATALOG[f.kind].desc)
	elif kind=="room" and tab=="build":selected_room=id;_room_dialog(id)

func _rotate() -> void:
	if world.mode=="furniture":world.placement.rot=(int(world.placement.rot)+1)%4;return
	for f in model.data.furniture:
		if f.id==selected_furniture:
			var updated=f.duplicate(true);updated.rot=(int(f.rot)+1)%4
			if model.put_furniture(updated,f.id):world.layout_changed();toast("已旋转")
			else:toast(model.last_error)
			return

func _delete_furniture() -> void:
	if selected_furniture=="":return
	model.remove_furniture(selected_furniture);selected_furniture="";world.selected_id="";world.layout_changed();_render_panel();toast("家具已移除，可以撤销")

func _undo() -> void:
	if model.undo():world.layout_changed();_refresh_characters();_render_panel();toast("已撤销上一步")
	else:toast("没有可以撤销的操作")

func _new_room() -> void:
	var dialog=_dialog("扩建房间",Vector2i(430,380));var v=dialog.get_meta("body")
	v.add_child(wrapped("设置尺寸后，在地图上点击房间左上角。贴着现有房间边缘放置，连接门会自动生成。"))
	var name_input=LineEdit.new();name_input.text="新工作间";v.add_child(name_input)
	var w=_spin(v,"宽度（格）",7,4,24);var h=_spin(v,"深度（格）",7,4,20)
	v.add_child(button("选择房间位置",func():world.mode="room";world.moving_id="";world.placement={"id":model.new_id("room"),"name":name_input.text if name_input.text.strip_edges()!="" else "新工作间","x":0,"y":0,"w":int(w.value),"h":int(h.value),"floor":model.data.rooms.size()%3};dialog.queue_free();toast("点击地图，放置房间左上角"),true))

func _spin(parent:Node,title:String,value:float,minimum:float,maximum:float) -> SpinBox:
	var h=row(parent);h.add_child(label(title));spacer(h);var s=SpinBox.new();s.min_value=minimum;s.max_value=maximum;s.value=value;s.custom_minimum_size.x=100;h.add_child(s);return s

func _room_dialog(id:String) -> void:
	var room={}
	for r in model.data.rooms:
		if r.id==id:room=r
	if room.is_empty():return
	var dialog=_dialog("房间设置",Vector2i(440,400));var v=dialog.get_meta("body")
	var name_input=LineEdit.new();name_input.text=room.name;v.add_child(name_input)
	var w=_spin(v,"宽度（格）",room.w,4,24);var h=_spin(v,"深度（格）",room.h,4,20)
	var floor_pick=OptionButton.new();for title in ["蜂蜜木地板","鼠尾草地板","浅胡桃地板"]:floor_pick.add_item(title)
	floor_pick.select(int(room.get("floor",0)));v.add_child(floor_pick)
	v.add_child(wrapped("以左上角为基准调整尺寸。已有家具和相邻房间通路会自动检查。"))
	v.add_child(button("保存房间",func():
		var updated=room.duplicate(true);updated.name=name_input.text;updated.w=int(w.value);updated.h=int(h.value);updated.floor=floor_pick.selected
		if model.put_room(updated,id):world.layout_changed();world.center_map();_render_panel();dialog.queue_free();toast("房间已更新")
		else:toast(model.last_error),true))

func _people_panel() -> void:
	section("认识你的伙伴")
	var select=OptionButton.new();select.custom_minimum_size.y=40
	for i in range(model.data.profiles.size()):
		var p=model.data.profiles[i];select.add_item(p.name)
		if p.id==selected_profile:select.select(i)
	select.item_selected.connect(func(i):selected_profile=model.data.profiles[i].id;world.selected_id=selected_profile;_render_panel());side.add_child(select)
	profile_draft=_profile(selected_profile).duplicate(true)
	var preview=PanelContainer.new();preview.add_theme_stylebox_override("panel",box("e0e5d4",9,0));side.add_child(preview)
	var avatar=Avatar.new();avatar.profile=profile_draft;avatar.custom_minimum_size=Vector2(300,152);avatar.pixel_scale=3.4;preview.add_child(avatar)
	var name_input=LineEdit.new();name_input.text=profile_draft.name;name_input.placeholder_text="角色名字";name_input.max_length=16;name_input.text_changed.connect(func(text):profile_draft.name=text);side.add_child(name_input)
	_option(side,"发型",["利落短发","蓬松短发","齐肩长发","双髻"],int(profile_draft.hair),func(i):profile_draft.hair=i;avatar.queue_redraw())
	_option(side,"发色",["深棕","栗色","亚麻金","银灰","黑紫"],int(profile_draft.hair_color),func(i):profile_draft.hair_color=i;avatar.queue_redraw())
	_option(side,"衣服",["鼠尾草绿","焦糖橙","丁香紫","珊瑚粉","雾蓝","苔藓黄"],int(profile_draft.shirt),func(i):profile_draft.shirt=i;avatar.queue_redraw())
	_option(side,"肤色",["浅杏","暖沙","蜜棕","深棕"],int(profile_draft.skin),func(i):profile_draft.skin=i;avatar.queue_redraw())
	_option(side,"配件",["无配件","眼镜","耳机","围巾"],int(profile_draft.accessory),func(i):profile_draft.accessory=i;avatar.queue_redraw())
	side.add_child(label("职责说明",15));var role=TextEdit.new();role.text=profile_draft.role;role.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;role.custom_minimum_size.y=105;role.text_changed.connect(func():profile_draft.role=role.text);side.add_child(role)
	side.add_child(button("保存角色",func():
		if str(profile_draft.name).strip_edges()=="":toast("请给伙伴起个名字");return
		model.checkpoint()
		for i in range(model.data.profiles.size()):
			if model.data.profiles[i].id==selected_profile:model.data.profiles[i]=profile_draft.duplicate(true)
		model.save();_refresh_characters();_render_panel();toast("外观已更新，职责用于下一次任务"),true))
	var actions=row(side);actions.add_child(button("配置技能",func():_switch_tab("skills")));actions.add_child(button("＋ 新伙伴",_new_profile))
	if model.data.profiles.size()>1:side.add_child(button("移除这位伙伴",_remove_profile))

func _option(parent:Node,title:String,options:Array,index:int,callback:Callable) -> void:
	var h=row(parent);h.add_child(label(title,14));spacer(h);var pick=OptionButton.new();pick.custom_minimum_size=Vector2(180,36)
	for name_value in options:pick.add_item(name_value)
	pick.select(index);pick.item_selected.connect(callback);h.add_child(pick)

func _new_profile() -> void:
	model.checkpoint();var p=model.defaults().profiles[0].duplicate(true);p.id=model.new_id("p");p.name="新伙伴";p.role="协助完成分配的任务，说明依据和结果。";p.shirt=model.data.profiles.size()%Model.SHIRTS.size();p.skills=[]
	model.data.profiles.append(p);selected_profile=p.id;model.save();_refresh_characters();_render_panel();toast("新伙伴加入了工作室")

func _remove_profile() -> void:
	var t=_task_for(selected_profile)
	if not t.is_empty() and ACTIVE.has(t.status):toast("请先停止这位伙伴的任务");return
	var dialog=ConfirmationDialog.new();dialog.title="移除伙伴";dialog.dialog_text="移除角色档案和工位绑定。历史任务仍会保留。";add_child(dialog)
	dialog.confirmed.connect(func():
		model.checkpoint();model.data.profiles=model.data.profiles.filter(func(p):return p.id!=selected_profile)
		for f in model.data.furniture:
			if f.get("owner","")==selected_profile:f.owner=""
		selected_profile=model.data.profiles[0].id;model.save();_refresh_characters();_render_panel();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(440,190))

func _skills_panel() -> void:
	section("技能书架")
	var profile=_profile(selected_profile)
	var pick=OptionButton.new();pick.custom_minimum_size.y=38
	for i in range(model.data.profiles.size()):
		pick.add_item(model.data.profiles[i].name)
		if model.data.profiles[i].id==profile.id:pick.select(i)
	pick.item_selected.connect(func(i):selected_profile=model.data.profiles[i].id;_render_panel());side.add_child(pick)
	note("读取本机和当前项目中的真实 Skills。保存的组合会在角色下一次开工时启用。")
	skill_draft=profile.skills.duplicate()
	var actions=row(side);actions.add_child(button("保存技能组合",func():model.checkpoint();profile.skills=skill_draft.duplicate();model.save();toast("已为 "+profile.name+" 保存 "+str(skill_draft.size())+" 项技能"),true));actions.add_child(button("刷新",func():_load_skills(true)))
	var search=LineEdit.new();search.placeholder_text="搜索技能名称或说明";side.add_child(search)
	var results=VBoxContainer.new();side.add_child(results)
	search.text_changed.connect(func(text):_skill_results(results,text));_skill_results(results,"")
	if skills.is_empty() and not skills_requested:_load_skills(false)

func _skill_results(parent:VBoxContainer,query:String) -> void:
	for n in parent.get_children():parent.remove_child(n);n.queue_free()
	if skills.is_empty():parent.add_child(wrapped("等待 Codex 技能列表。连接成功后可点击刷新。"));return
	var shown=0
	for s in skills:
		if query!="" and not (str(s.name)+" "+str(s.description)).to_lower().contains(query.to_lower()):continue
		shown+=1
		var c=VBoxContainer.new();c.add_theme_constant_override("separation",5);parent.add_child(c)
		var check=CheckBox.new();check.text=str(s.name);check.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;check.custom_minimum_size.x=280
		check.button_pressed=skill_draft.has(s.path);check.disabled=not s.get("enabled",true) and not skill_draft.has(s.path)
		check.toggled.connect(func(on):if on and not skill_draft.has(s.path):skill_draft.append(s.path)
		else:skill_draft.erase(s.path))
		c.add_child(check);c.add_child(wrapped(str(s.get("shortDescription",s.description)).left(110)+( " · 已禁用" if not s.get("enabled",true) else ""),12))
		c.add_child(button("查看说明",func():_skill_detail(s)));c.add_child(HSeparator.new())
	parent.add_child(label(str(shown)+" 项技能",12,MUTED))
	for p in skill_draft:
		if not skills.any(func(s):return s.path==p):
			parent.add_child(button("移除失效技能 · "+str(p).get_base_dir().get_file(),func():skill_draft.erase(p);_skill_results(parent,query)))

func _skill_detail(skill:Dictionary) -> void:
	var d=_dialog(str(skill.name),Vector2i(720,590));var v=d.get_meta("body")
	v.add_child(wrapped(str(skill.description),15,INK));v.add_child(wrapped(str(skill.path),12))
	var text=TextEdit.new();text.editable=false;text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;text.size_flags_vertical=Control.SIZE_EXPAND_FILL;text.custom_minimum_size.y=350
	var f=FileAccess.open(str(skill.path),FileAccess.READ);text.text=f.get_as_text() if f else "无法读取技能文件";v.add_child(text)

func _tasks_panel() -> void:
	section("任务与成果")
	note("这里保留真实任务、子 agent 的协作记录和交付。执行完成后仍需要你验收。")
	if tasks.is_empty():note("暂时没有任务。回到工作室，把第一项工作交给伙伴吧。");return
	var ordered=tasks.duplicate();ordered.sort_custom(func(a,b):return a.created>b.created)
	for t in ordered:
		var panel=PanelContainer.new();panel.add_theme_stylebox_override("panel",box("e7e6d8",7,12));side.add_child(panel)
		var v=VBoxContainer.new();v.add_theme_constant_override("separation",6);panel.add_child(v)
		v.add_child(label(("↳ " if t.get("parentId") else "")+t.name,16))
		v.add_child(wrapped(str(t.prompt).left(90),13,INK))
		var live=label(_status_text(t),12,MUTED);v.add_child(live);live_labels[t.id]=live
		v.add_child(button("查看任务与成果",func():_open_task(t.id)))

func _dialog(title:String,dimensions:Vector2i) -> Window:
	var d=Window.new();d.title=title;d.size=dimensions;d.min_size=Vector2i(380,240);d.transient=true;d.exclusive=false;d.unresizable=false;add_child(d)
	var bg=ColorRect.new();bg.color=PAPER;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);d.add_child(bg)
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for n in ["margin_left","margin_right","margin_top","margin_bottom"]:margin.add_theme_constant_override(n,20)
	d.add_child(margin)
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;margin.add_child(scroll)
	var v=VBoxContainer.new();v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.add_child(v);d.set_meta("body",v)
	d.close_requested.connect(d.queue_free);d.popup_centered(dimensions);return d

func _open_task(id:String) -> void:
	var task={}
	for t in tasks:
		if t.id==id:task=t
	if task.is_empty():return
	if active_task_id!="":task_panels[active_task_id].hide()
	active_task_id=id;selected_profile=task.profileId;world.selected_id=task.profileId
	_cancel_placement();side_scroll.hide();sidebar.custom_minimum_size.x=420;_resize_sidebar()
	if not task_panels.has(id):task_panels[id]=_create_task_panel(task)
	var panel=task_panels[id];panel.show();_update_task_panel(panel,task)
	panel.get_meta("input").grab_focus()

func _create_task_panel(task:Dictionary) -> VBoxContainer:
	var id=str(task.id)
	# Keep each panel while switching partners so drafts and reading positions survive.
	var v=VBoxContainer.new();v.add_theme_constant_override("separation",10);sidebar.add_child(v)
	var head=row(v);var identity=VBoxContainer.new();identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL;identity.add_theme_constant_override("separation",3);head.add_child(identity)
	var title=label(task.name+" · 对话",20);title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.tooltip_text=title.text;identity.add_child(title)
	var status=wrapped(_status_text(task),13);status.max_lines_visible=2;identity.add_child(status)
	var close=button("收起",_close_task);close.tooltip_text="返回侧栏，保留尚未发送的内容";head.add_child(close)
	var prompt=label(task.prompt.replace("\n"," "),13,MUTED);prompt.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;prompt.tooltip_text=task.prompt;v.add_child(prompt)
	var mode=row(v);var content_mode=OptionButton.new();content_mode.fit_to_longest_item=false;content_mode.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content_mode.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	for title_value in ["回复与成果","工具记录","任务计划","本次角色与技能"]:content_mode.add_item(title_value)
	mode.add_child(content_mode)
	var output=TextEdit.new();output.editable=false;output.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;output.size_flags_vertical=Control.SIZE_EXPAND_FILL;output.custom_minimum_size.y=100;v.add_child(output)
	mode.add_child(button("复制",func():DisplayServer.clipboard_set(output.text);toast("内容已复制")))
	var directory=button("工作目录",func():OS.shell_open(task.workspace));directory.tooltip_text=task.workspace;mode.add_child(directory)
	var file_row=row(v);var files=OptionButton.new();files.fit_to_longest_item=false;files.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;files.size_flags_horizontal=Control.SIZE_EXPAND_FILL;file_row.add_child(files)
	file_row.add_child(button("打开文件",func():
		if files.selected>=0 and files.get_item_metadata(files.selected)!=null:OS.shell_open(str(files.get_item_metadata(files.selected)))))
	var request_scroll=ScrollContainer.new();request_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;request_scroll.custom_minimum_size.y=170;request_scroll.visible=false;v.add_child(request_scroll)
	var request_box=VBoxContainer.new();request_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;request_scroll.add_child(request_box)
	var text_input=TextEdit.new();text_input.placeholder_text="补充指令，或继续这个任务…";text_input.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;text_input.custom_minimum_size.y=80;v.add_child(text_input)
	var actions=row(v);actions.add_child(button("发送补充 / 继续",func():_api("/message",{"id":id,"text":text_input.text},func(r):text_input.text="";toast("指令已交给负责人转达" if r.has("routedTo") else "指令已送达")),true))
	actions.get_child(0).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var stop=button("停止任务",func():_api("/stop",{"id":id,"children":true},func(_r):toast("已请求停止任务和它的子任务")));actions.add_child(stop)
	var finish=button("结束对话",func():_finish_task(id));actions.add_child(finish)
	var hint=wrapped("追加指令沿用本次角色与技能。",12);hint.tooltip_text="修改角色或技能后，请回工作室创建新任务。";v.add_child(hint)
	v.set_meta("output",output);v.set_meta("status",status);v.set_meta("mode",content_mode);v.set_meta("files",files);v.set_meta("file_row",file_row);v.set_meta("request_box",request_box);v.set_meta("request_scroll",request_scroll);v.set_meta("request_id","");v.set_meta("input",text_input)
	v.set_meta("stop",stop);v.set_meta("finish",finish)
	content_mode.item_selected.connect(func(_i):v.set_meta("last_content","");_update_task_panel(v,v.get_meta("task")))
	return v

func _update_task_panel(d:Control,t:Dictionary) -> void:
	if not is_instance_valid(d):return
	d.set_meta("task",t)
	var unsettled=_task_family(t.id).any(func(member):return member.status not in ["completed","failed","interrupted"])
	d.get_meta("stop").visible=unsettled
	d.get_meta("finish").visible=t.status in ["completed","failed","interrupted"] and not _task_ended(t)
	d.get_meta("finish").disabled=unsettled
	d.get_meta("finish").tooltip_text="还有子任务未结束，请先等待完成或停止任务" if unsettled else "清除完成标记，让伙伴恢复待命；对话记录仍然保留"
	d.get_meta("status").text=_status_text(t)+(" · "+str(t.get("activity","")) if ACTIVE.has(t.status) else "")
	d.get_meta("status").tooltip_text=d.get_meta("status").text
	var content=""
	match d.get_meta("mode").selected:
		0:content=str(t.get("result","")) if not ACTIVE.has(t.status) else str(t.get("messages",""));if content=="":content=str(t.get("messages",""))
		1:
			for l in t.get("logs",[]):content+="[ "+str(l.label)+" ]\n"+str(l.text)+"\n\n"
		2:content=str(t.get("plan","尚无公开任务计划"))
		3:
			var p=t.get("snapshot",{});content="角色："+str(p.get("name",t.name))+"\n职责："+str(p.get("role","由主 agent 分配"))+"\n\n本次技能：\n"+"\n".join(p.get("skills",[]))+"\n\n任务 ID："+t.id+"\n工作目录："+t.workspace
	if t.get("error","")!="":content+="\n\n错误："+str(t.error)
	if content=="":content="正在等待第一条工作记录…" if ACTIVE.has(t.status) else "没有文本输出。请检查工具记录。"
	if content!=d.get_meta("last_content",""):
		var edit=d.get_meta("output");var scroll=edit.scroll_vertical;var at_end=scroll>=edit.get_v_scroll_bar().max_value-edit.get_v_scroll_bar().page-3
		edit.text=content;edit.scroll_vertical=edit.get_v_scroll_bar().max_value if at_end else scroll;d.set_meta("last_content",content)
	var pick=d.get_meta("files")
	d.get_meta("file_row").visible=not t.get("files",[]).is_empty()
	if pick.item_count!=t.get("files",[]).size():
		pick.clear()
		for file in t.get("files",[]):pick.add_item(str(file).get_file());pick.set_item_metadata(pick.item_count-1,str(file) if str(file).is_absolute_path() else str(t.workspace).path_join(str(file)))
	var request=t.get("request");var request_id=str(request.id) if request is Dictionary else ""
	if request_id!=d.get_meta("request_id"):
		d.set_meta("request_id",request_id);var area=d.get_meta("request_box")
		for child in area.get_children():area.remove_child(child);child.queue_free()
		d.get_meta("request_scroll").visible=request is Dictionary
		d.get_meta("request_scroll").custom_minimum_size.y=250 if request is Dictionary and request.get("approval") is Dictionary else 170
		if request is Dictionary:_request_controls(area,request)

func _finish_task(id:String) -> void:
	_api("/finish",{"id":id},func(r):
		for t in tasks:
			if r.ids.has(t.id):t.endedAt=r.endedAt
		if r.ids.has(active_task_id):_close_task()
		_refresh_characters();_render_panel()
		for t in tasks:
			if task_panels.has(t.id):_update_task_panel(task_panels[t.id],t)
		toast("对话已结束，记录保留在「任务与成果」"))

func _request_controls(area:VBoxContainer,request:Dictionary) -> void:
	var params=request.params;var method=str(request.method)
	if request.get("approval") is Dictionary:
		var approval=request.approval
		area.add_child(wrapped(approval.title,14,INK))
		if str(approval.details)!="":
			var details=TextEdit.new();details.text=approval.details;details.editable=false;details.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;details.custom_minimum_size.y=90;area.add_child(details)
		var actions=HFlowContainer.new();actions.add_theme_constant_override("h_separation",8);actions.add_theme_constant_override("v_separation",8);area.add_child(actions)
		var scopes=[]
		for choice in approval.choices:
			var action=button(choice.label,func():_api("/answer",{"id":request.id,"choice":choice.id},func(_r):toast("已提交："+str(choice.label))),choice.kind=="rule")
			action.tooltip_text=choice.hint;actions.add_child(action)
			if choice.kind in ["rule","session","deny-rule"]:scopes.append(str(choice.label)+"："+str(choice.hint))
		if not scopes.is_empty():area.add_child(wrapped("\n\n".join(scopes),12,MUTED))
	elif method=="item/tool/requestUserInput":
		var fields={}
		for q in params.get("questions",[]):
			area.add_child(wrapped(q.question,14,INK));var input_value=LineEdit.new();input_value.placeholder_text="输入回答";area.add_child(input_value);fields[q.id]=input_value
			if q.get("options") is Array:
				var opts=VBoxContainer.new();area.add_child(opts)
				for option in q.options:
					var choice=button(str(option.label),func():input_value.text=option.label);choice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;opts.add_child(choice)
		area.add_child(button("提交回答",func():
			var answers={};for key in fields:answers[key]=fields[key].text
			_api("/answer",{"id":request.id,"answers":answers},func(_r):toast("回答已提交")),true))
	else:
		area.add_child(wrapped("需要你的审批："+str(params.get("reason",params.get("command",method))),14,INK))
		var details=TextEdit.new();details.text=JSON.stringify(params,"  ");details.editable=false;details.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;details.custom_minimum_size.y=105;area.add_child(details)
		var actions=row(area);actions.add_child(button("允许这一次",func():_api("/answer",{"id":request.id,"accept":true},func(_r):toast("已允许"))))
		actions.add_child(button("拒绝",func():_api("/answer",{"id":request.id,"accept":false},func(_r):toast("已拒绝"))))

func _workspace_dialog() -> void:
	var d=_dialog("选择工作项目",Vector2i(620,330));var v=d.get_meta("body")
	v.add_child(wrapped("伙伴会在这个目录中读取资料和修改文件。切换项目只影响下一次创建的任务。"))
	var input_value=LineEdit.new();input_value.text=model.data.workspace;v.add_child(input_value)
	v.add_child(button("浏览文件夹…",func():
		var fd=FileDialog.new();fd.file_mode=FileDialog.FILE_MODE_OPEN_DIR;fd.access=FileDialog.ACCESS_FILESYSTEM;fd.current_dir=model.data.workspace;fd.use_native_dialog=true;add_child(fd)
		fd.dir_selected.connect(func(p):input_value.text=p;fd.queue_free());fd.canceled.connect(fd.queue_free);fd.popup_centered(Vector2i(800,550))))
	v.add_child(button("使用这个目录",func():
		if not DirAccess.dir_exists_absolute(input_value.text) or not input_value.text.is_absolute_path():toast("请选择存在的绝对目录路径");return
		model.data.workspace=input_value.text;model.save();skills=[];skills_requested=false;workspace_label.text="项目 · "+input_value.text.get_file();d.queue_free();_load_skills(true);toast("工作目录已更新"),true))

func _help() -> void:
	var d=_dialog("欢迎来到栖点工作室",Vector2i(700,550));var v=d.get_meta("body")
	var help_text=TextEdit.new();help_text.editable=false;help_text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;help_text.size_flags_vertical=Control.SIZE_EXPAND_FILL
	help_text.text="这是一个连接真实 Codex 的 2D 工作室。\n\n1. 右下角选择工作目录；默认附带一个可安全体验的小项目。\n2. 在「伙伴」里设置名字、外观与职责。\n3. 在「技能」里配置本机已有 Skills，保存后用于新任务。\n4. 在「工作室」中输入任务并交给伙伴；勾选团队模式允许原生子 agent。\n5. 点击角色，在右侧边聊边看房间。拖动分隔线调宽；切换角色保留未发送草稿。可看记录、回答问题、审批、追加指令或停止。\n6. 在「布置」中放家具、绑定工位、新增和调整房间。\n\n地图：滚轮缩放，中键拖动，顶部居中。\n布置：R 旋转，Delete 删除，Ctrl/Cmd Z 撤销，右键取消放置。\n\n小人的工作状态来自实际执行事件；待命散步只是场景表现。完成表示执行已结束，成果需要你验收。看完后点击「结束对话」，伙伴恢复待命，完成标记消失；记录保留在「任务与成果」，可以再次继续。\n\n首次接入需已安装并登录 Codex（终端运行 codex login）。游戏可以离线布置，真实任务需要联网和可用的 Codex 额度。关闭游戏时会停止本应用启动的任务。"
	v.add_child(help_text);v.add_child(button("打开存档文件夹",func():OS.shell_open(data_dir)))

func toast(text:String) -> void:
	toast_label.text=text;toast_label.visible=true
	var captured=text;get_tree().create_timer(4).timeout.connect(func():if is_instance_valid(toast_label) and toast_label.text==captured:toast_label.visible=false)

func _start_bridge() -> void:
	if FileAccess.file_exists(bridge_info):
		var file=FileAccess.open(bridge_info,FileAccess.READ);var info=JSON.parse_string(file.get_as_text()) if file else null
		if info is Dictionary and int(info.get("port",0))>0 and str(info.get("token",""))!="":
			bridge_url="http://127.0.0.1:"+str(int(info.port));bridge_token=info.token;bridge_pid=int(info.pid);started=true;return
	_spawn_bridge()

func _spawn_bridge() -> void:
	var node=OS.get_environment("AGENT_STUDIO_NODE")
	if node=="":
		var bundled=root_dir.path_join("runtime/node")
		if FileAccess.file_exists(bundled):node=bundled
		else:
			var out=[];OS.execute("/bin/zsh",["-lc","command -v node"],out);node=str(out[0]).strip_edges() if not out.is_empty() else ""
	if node=="":status_label.text="找不到 Node.js";toast("请使用随附启动入口，或安装 Node.js");return
	bridge_pid=OS.create_process(node,[root_dir.path_join("bridge/server.mjs"),"--data",data_dir,"--info",bridge_info]);owns_bridge=true
	if bridge_pid<0:status_label.text="桥接启动失败"

func _poll_bridge() -> void:
	if bridge_url=="":
		if FileAccess.file_exists(bridge_info):
			var f=FileAccess.open(bridge_info,FileAccess.READ);var info=JSON.parse_string(f.get_as_text()) if f else null
			if info is Dictionary:bridge_url="http://127.0.0.1:"+str(int(info.port));bridge_token=info.token;started=true
		return
	if polling:return
	polling=true
	var err=poll.request(bridge_url+"/state",["Authorization: Bearer "+bridge_token])
	if err!=OK:polling=false;status_label.text="连接中断"

func _poll_complete(_result:int,code:int,_headers:PackedStringArray,body:PackedByteArray) -> void:
	polling=false
	if code!=200:
		bridge_failures=bridge_failures+1 if _result==HTTPRequest.RESULT_CANT_CONNECT else 0
		connected=false;status_label.text="桥接未连接"
		for t in tasks:
			if ACTIVE.has(t.status):t.status="disconnected";t.activity="连接中断，执行状态尚未确认"
		_refresh_characters()
		for t in tasks:
			if task_panels.has(t.id):_update_task_panel(task_panels[t.id],t)
		if bridge_failures>=2:
			bridge_failures=0;bridge_url="";bridge_token=""
			DirAccess.remove_absolute(bridge_info);_spawn_bridge()
		return
	bridge_failures=0
	var state=JSON.parse_string(body.get_string_from_utf8())
	if not state is Dictionary:return
	connected=state.connected;status_label.text="● Codex 已连接" if connected else "○ Codex 未连接"
	status_label.tooltip_text=str(state.get("account",""))+"\n"+str(state.get("error",""))
	tasks=state.get("tasks",[])
	var count=0
	for t in tasks:
		if ACTIVE.has(t.status):count+=1
	header_count.text=str(model.data.profiles.size())+" 位伙伴  ·  "+str(count)+" 项进行中"
	_refresh_characters()
	for key in live_labels:
		if not is_instance_valid(live_labels[key]):continue
		var target=_task_for(key)
		for t in tasks:
			if t.id==key:target=t
		live_labels[key].text=_status_text(target)
	for t in tasks:
		if task_panels.has(t.id):_update_task_panel(task_panels[t.id],t)
	var signature=""
	for t in tasks:signature+=t.id
	if last_signature!=signature:
		last_signature=signature
		if tab=="tasks":_render_panel()

func _refresh_characters() -> void:
	var cast=model.data.profiles.duplicate(true);var task_states={}
	var running=0
	for t in tasks:
		if ACTIVE.has(t.status):running+=1
	header_count.text=str(model.data.profiles.size())+" 位伙伴  ·  "+str(running)+" 项进行中"
	for t in tasks:
		var pid=str(t.profileId)
		if _prefer_task(t,task_states.get(pid,{})):task_states[pid]=t
		if t.get("parentId") and not _task_ended(t) and not cast.any(func(p):return p.id==pid) and (ACTIVE.has(t.status) or t.status=="completed"):
			var p=model.defaults().profiles[0].duplicate(true)
			p.merge(t.get("snapshot",{}),true);p.id=pid;p.name=t.name;p.role="子 agent";cast.append(p)
	for pid in task_states.keys():
		if _task_ended(task_states[pid]):task_states.erase(pid)
	world.update_characters(cast,task_states)

func _load_skills(reload:bool) -> void:
	if bridge_url=="":return
	skills_requested=true
	_api("/skills?cwd="+str(model.data.workspace).uri_encode()+("&reload=1" if reload else ""),{},func(r):skills=r.get("skills",[]);if tab=="skills":_render_panel(),HTTPClient.METHOD_GET)

func _api(endpoint:String,payload:Dictionary,callback:Callable,method:int=HTTPClient.METHOD_POST) -> void:
	if bridge_url=="":toast("桥接尚未启动，请稍候");return
	var request=HTTPRequest.new();request.timeout=90;add_child(request)
	request.request_completed.connect(func(_result,code,_headers,body):
		if endpoint=="/task":submitting=false
		var result=JSON.parse_string(body.get_string_from_utf8());request.queue_free()
		if not result is Dictionary:toast("连接失败，请查看右上角连接状态");return
		if code!=200:toast(str(result.get("error","请求失败")));return
		callback.call(result))
	var err=request.request(bridge_url+endpoint,["Authorization: Bearer "+bridge_token,"Content-Type: application/json"],method,"" if method==HTTPClient.METHOD_GET else JSON.stringify(payload))
	if err!=OK:
		if endpoint=="/task":submitting=false
		request.queue_free();toast("请求无法发出："+error_string(err))

func _submit_task() -> void:
	if submitting:toast("正在准备上一项任务，请稍候");return
	if not connected:toast("Codex 尚未连接：请先确认已运行 codex login");return
	if task_prompt.text.strip_edges()=="":toast("先写下想交给伙伴的任务吧");return
	var profile=model.data.profiles[task_role_picker.selected]
	var prompt=task_prompt.text
	var roster=model.data.profiles.filter(func(p):return p.id!=profile.id)
	submitting=true
	_api("/task",{"profile":profile,"prompt":prompt,"workspace":model.data.workspace,"team":team_checkbox.button_pressed,"roster":roster},func(r):
		tasks.append(r.task);_refresh_characters();toast(profile.name+" 已开始工作");_open_task(r.task.id))
	toast("正在为 "+profile.name+" 准备任务…")

func _unhandled_key_input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	var focus=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return
	if event.keycode==KEY_ESCAPE:_cancel_placement()
	if tab=="build" and active_task_id=="":
		if event.keycode==KEY_R:_rotate()
		if event.keycode in [KEY_DELETE,KEY_BACKSPACE]:_delete_furniture()
	if event.keycode==KEY_Z and (event.ctrl_pressed or event.meta_pressed):_undo()

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if tasks.any(func(t):return ACTIVE.has(t.status)):
			var d=ConfirmationDialog.new();d.title="离开工作室";d.dialog_text="还有任务在执行。退出会保存工作室并停止本应用的任务。";d.ok_button_text="保存并退出";add_child(d);d.confirmed.connect(_quit);d.canceled.connect(d.queue_free);d.popup_centered(Vector2i(470,190))
		else:_quit()

func _quit() -> void:
	model.save()
	if owns_bridge and bridge_url!="":
		_api("/shutdown",{},func(_r):get_tree().quit())
		get_tree().create_timer(2).timeout.connect(func():get_tree().quit())
	else:get_tree().quit()

func _self_test() -> void:
	await get_tree().process_frame
	for name_value in ["studio","build","people","skills","tasks"]:_switch_tab(name_value);await get_tree().process_frame
	_switch_tab("studio")
	print("UI_SELF_TEST_OK")

func _capture(destination:String) -> void:
	for i in range(20):await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image=get_viewport().get_texture().get_image()
	image.save_png(destination)
	print("CAPTURE_SAVED ",destination)
	if "--capture-quit" in OS.get_cmdline_user_args():get_tree().quit()
