extends ScrollContainer

var list:VBoxContainer
var notice:Label
var bubbles={}
var entry_ids:Array=[]
var layout_revision=0

func _init() -> void:
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	custom_minimum_size.y=100
	list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12);add_child(list)
	notice=Label.new();notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size",12);notice.add_theme_color_override("font_color",Color("7d8a7d"));list.add_child(notice)

func _bubble(entry:Dictionary) -> Dictionary:
	var user=entry.get("role")=="user"
	var line=HBoxContainer.new();line.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_child(line)
	var space=Control.new();space.custom_minimum_size.x=30
	if user:line.add_child(space)
	var panel=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(panel)
	if not user:line.add_child(space)
	var style=StyleBoxFlat.new();style.bg_color=Color("dce8df") if user else Color("fffaf0")
	style.set_corner_radius_all(7);style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=10;style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",6);panel.add_child(column)
	var speaker=Label.new();speaker.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;speaker.add_theme_font_size_override("font_size",12);speaker.add_theme_color_override("font_color",Color("6b8074"));column.add_child(speaker)
	var body=RichTextLabel.new();body.bbcode_enabled=false;body.selection_enabled=true
	body.fit_content=true;body.scroll_active=false;body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("default_color",Color("304e4b"));body.add_theme_font_size_override("normal_font_size",16);column.add_child(body)
	return {"row":line,"panel":panel,"speaker":speaker,"body":body}

func set_messages(entries:Array,agent_name:String,notice_text:String="") -> void:
	var bar=get_v_scroll_bar();var old_scroll=scroll_vertical
	var follow=entry_ids.is_empty() or old_scroll>=bar.max_value-bar.page-4
	var ids=entries.map(func(e):return str(e.id))
	var changed=notice.text!=notice_text
	notice.text=notice_text;notice.visible=notice_text!=""
	# Append/update in place so streaming and polling preserve text selection.
	if ids.slice(0,entry_ids.size())!=entry_ids:
		for bubble in bubbles.values():list.remove_child(bubble.row);bubble.row.queue_free()
		bubbles.clear();changed=true
	for entry in entries:
		var id=str(entry.id)
		if not bubbles.has(id):bubbles[id]=_bubble(entry);changed=true
		var bubble=bubbles[id]
		var speaker=str(entry.get("speaker","你")) if entry.get("role")=="user" else agent_name
		if entry.get("pending",false):speaker+=" · 发送中"
		if bubble.body.text!=str(entry.get("text","")):bubble.body.text=str(entry.get("text",""));changed=true
		if bubble.speaker.text!=speaker:bubble.speaker.text=speaker;changed=true
	entry_ids=ids
	if changed:
		layout_revision+=1
		_restore_scroll.call_deferred(layout_revision,follow,old_scroll)

func _restore_scroll(revision:int,follow:bool,position:int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if revision!=layout_revision:return
	# Do not override a scroll gesture made while the new content was laying out.
	if scroll_vertical!=position:return
	scroll_vertical=int(get_v_scroll_bar().max_value) if follow else position

static func transcript(entries:Array,agent_name:String) -> String:
	var parts=PackedStringArray()
	for entry in entries:
		var speaker=str(entry.get("speaker","你")) if entry.get("role")=="user" else agent_name
		parts.append(speaker+"\n"+str(entry.get("text","")))
	return "\n\n".join(parts)
