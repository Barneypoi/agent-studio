extends VBoxContainer
# Browsing and preview are read-only. Only the final import button registers a task.
var app
var search_area:VBoxContainer
var detail_area:VBoxContainer
var query:LineEdit
var archived:CheckBox
var project_only:CheckBox
var results:VBoxContainer
var more:Button
var info:Label
var intro:Label
var preview:TextEdit
var title_label:Label
var details:Label
var warnings:Label
var mode:OptionButton
var people:OptionButton
var workspace:LineEdit
var browse:Button
var submit:Button
var back:Button
var cursor=""
var generation=0
var selected={}
var request_id=""
var busy=false

func setup(owner_app) -> void:
	app=owner_app
	add_child(app.label("导入 Codex 会话",20))
	intro=app.wrapped("读取本机已有会话。浏览和导入不会启动模型，发送新消息时才开始执行。");add_child(intro)
	info=app.wrapped("",12);add_child(info)
	search_area=VBoxContainer.new();add_child(search_area)
	var search_row=app.row(search_area);query=LineEdit.new();query.placeholder_text="搜索会话标题";query.size_flags_horizontal=Control.SIZE_EXPAND_FILL;search_row.add_child(query)
	search_row.add_child(app.button("搜索",func():_load_list(true)));query.text_submitted.connect(func(_text):_load_list(true))
	var filters=app.row(search_area);archived=CheckBox.new();archived.text="已归档";filters.add_child(archived);archived.toggled.connect(func(_v):_load_list(true))
	project_only=CheckBox.new();project_only.text="当前项目";filters.add_child(project_only);project_only.toggled.connect(func(_v):_load_list(true))
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.custom_minimum_size.y=300;search_area.add_child(scroll)
	results=VBoxContainer.new();results.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(results)
	more=app.button("加载更多",func():_load_list(false));more.hide();search_area.add_child(more)
	search_area.add_child(app.button("返回任务与成果",func():app._switch_tab("tasks")))
	detail_area=VBoxContainer.new();detail_area.hide();add_child(detail_area)
	back=app.button("← 返回会话列表",func():generation+=1;selected={};detail_area.hide();search_area.show();intro.show();info.hide();app.side_scroll.scroll_vertical=0);detail_area.add_child(back)
	title_label=app.wrapped("",17,app.INK);title_label.max_lines_visible=2;title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;detail_area.add_child(title_label)
	details=app.wrapped("",12);detail_area.add_child(details)
	preview=TextEdit.new();preview.editable=false;preview.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;preview.custom_minimum_size.y=150;detail_area.add_child(preview)
	mode=OptionButton.new();mode.add_item("复制后继续 · 独立会话");mode.add_item("继续原会话 · 共用历史");detail_area.add_child(mode);mode.item_selected.connect(func(_i):_options_changed())
	var who=app.row(detail_area);who.add_child(app.label("承接伙伴",14));people=OptionButton.new();people.size_flags_horizontal=Control.SIZE_EXPAND_FILL;who.add_child(people)
	for p in app.model.data.profiles:people.add_item(p.name);people.set_item_metadata(people.item_count-1,p.id)
	people.item_selected.connect(func(_i):request_id="")
	var location=app.row(detail_area);workspace=LineEdit.new();workspace.size_flags_horizontal=Control.SIZE_EXPAND_FILL;workspace.placeholder_text="原工作目录";location.add_child(workspace)
	browse=app.button("目录…",_browse);location.add_child(browse);workspace.text_changed.connect(func(_t):request_id="")
	submit=app.button("导入并查看",_submit,true);submit.disabled=true;detail_area.add_child(submit)
	warnings=app.wrapped("",12);detail_area.add_child(warnings)
	_load_list(true)

func _load_list(reset:bool) -> void:
	if reset:
		generation+=1;cursor=""
		for node in results.get_children():results.remove_child(node);node.queue_free()
	var version=generation;more.disabled=true;info.show();info.text="正在读取本机会话…"
	var endpoint="/sessions?q="+query.text.uri_encode()+"&archived="+("1" if archived.button_pressed else "0")
	if project_only.button_pressed:endpoint+="&cwd="+str(app.model.data.workspace).uri_encode()
	if cursor!="":endpoint+="&cursor="+cursor.uri_encode()
	app._api(endpoint,{},func(r):
		if not is_instance_valid(self) or version!=generation:return
		for session in r.get("sessions",[]):
			var text=str(session.title).replace("\n"," ").left(90)
			var date=Time.get_date_string_from_unix_time(int(session.updatedAt))
			text+="\n"+str(session.workspace).get_file()+" · "+date+(" · 已在工作室" if session.imported else "")
			var item=app.button(text,func():_select(session));item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;item.alignment=HORIZONTAL_ALIGNMENT_LEFT;results.add_child(item)
		cursor=str(r.get("nextCursor","") if r.get("nextCursor")!=null else "");more.visible=cursor!="";more.disabled=false
		info.text="没有找到会话，可以换个关键词或切换归档筛选。" if results.get_child_count()==0 else "选择一条会话，先预览再导入。",HTTPClient.METHOD_GET,func(error):
			if is_instance_valid(self) and version==generation:info.text=error;more.disabled=false)

func _select(session:Dictionary) -> void:
	generation+=1;var version=generation;selected={};request_id="";search_area.hide();intro.hide();info.hide();detail_area.show();submit.disabled=true;app.side_scroll.scroll_vertical=0
	title_label.text=session.title;title_label.tooltip_text=session.title;details.text="";preview.text="正在读取历史…";info.text="";warnings.text=""
	app._api("/session-preview?id="+str(session.id).uri_encode(),{},func(r):
		if not is_instance_valid(self) or version!=generation:return
		selected=r;var source=r.session;title_label.text=source.title
		details.text=("模型："+source.model+" · " if source.model!="" else "")+"来源："+source.source
		preview.text=preload("res://conversation_view.gd").transcript(r.conversation,"Codex")
		if preview.text=="":preview.text="这条会话没有可显示的文字记录。"
		preview.tooltip_text=r.get("notice","");workspace.text=source.workspace;workspace.tooltip_text=source.workspace;mode.select(0);_options_changed(),HTTPClient.METHOD_GET,func(error):
			if is_instance_valid(self) and version==generation:preview.text="";info.text=error;info.show())

func _options_changed() -> void:
	request_id=""
	if selected.is_empty():return
	var source=selected.session;var original=mode.selected==1
	workspace.editable=not original;browse.disabled=original
	if original:workspace.text=source.workspace
	var text="导入后待命，发送新消息才执行。\n"
	people.tooltip_text="角色绑定只改变场景呈现；续聊沿用原会话上下文与可用技能。"
	text+=("共用原会话历史，请先在原客户端结束执行，避免两边同时续聊。" if original else "副本有独立的会话历史；项目文件不会被复制。")
	if not source.workspaceExists:text+="\n原工作目录不存在：可先导入查看，或在复制模式中选择现有目录。"
	if not selected.get("dependencies",[]).is_empty():text+="\n历史使用过原客户端工具，部分工具在工作室里可能不可用。"
	if source.active:text+="\n原会话正在执行，请先完成或停止后重新选择。"
	if source.get("parentId"):text+="\n这是委派子会话，请从主会话导入。"
	warnings.text=text;submit.disabled=busy or source.active or source.get("parentId")!=null

func _browse() -> void:
	var dialog=FileDialog.new();dialog.file_mode=FileDialog.FILE_MODE_OPEN_DIR;dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.use_native_dialog=true;app.add_child(dialog)
	dialog.dir_selected.connect(func(p):if is_instance_valid(self):workspace.text=p;request_id=""
	);dialog.dir_selected.connect(func(_p):dialog.queue_free());dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(800,550))

func _submit() -> void:
	if busy or selected.is_empty():return
	if request_id=="":request_id="import-"+Crypto.new().generate_random_bytes(16).hex_encode()
	var profile=app._profile(str(people.get_item_metadata(people.selected))).duplicate(true)
	var payload={"id":selected.session.id,"requestId":request_id,"mode":"fork" if mode.selected==0 else "resume","profile":profile,"workspace":workspace.text}
	busy=true;submit.disabled=true;back.disabled=true;mode.disabled=true;people.disabled=true;workspace.editable=false;browse.disabled=true;info.show();info.text="正在导入历史，请稍候…"
	var owner_app=app
	app._api("/import-session",payload,func(r):
		owner_app._receive_import(r.task,r.get("alreadyImported",false)),HTTPClient.METHOD_POST,func(error):
			if not is_instance_valid(self):return
			var retry_id=request_id
			busy=false;back.disabled=false;mode.disabled=false;people.disabled=false;_options_changed();request_id=retry_id;info.text=error;info.show())
