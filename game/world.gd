extends Control
const Art=preload("res://pixel_art.gd")
const Model=preload("res://studio_model.gd")
const Leisure=preload("res://leisure.gd")
const Themes=preload("res://room_themes.gd")
const Decor=preload("res://decor_art.gd")
const SocialLife=preload("res://social_life.gd")
const CELL=40.0
const AT_DESK=["starting","running","working","waiting","approval","stopping","completed"]
signal selected(kind:String,id:String)
signal placed(cell:Vector2i)
signal notification(text:String)
var model
var profiles:Array=[]
var states={}
var actors={}
var workstations={}
var leisure_slots:Array=[]
var social=SocialLife.new()
var zoom=1.1
var pan=Vector2.ZERO
var origin=Vector2.ZERO
var mode="inspect"
var placement={}
var moving_id=""
var selected_id=""
var hover=Vector2i(-999,-999)
var elapsed=0.0
var dragging=false
var font:Font
var last_hover_error=""

func _ready() -> void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	font=load("res://assets/NotoSansCJKsc-Regular.otf")
	resized.connect(queue_redraw)

func center_map() -> void:
	if model==null:return
	var bounds=Rect2(model.rect_of(model.data.rooms[0]))
	for room in model.data.rooms:bounds=bounds.merge(Rect2(model.rect_of(room)))
	zoom=clampf(minf((size.x-120)/(bounds.size.x*CELL),(size.y-180)/(bounds.size.y*CELL)),.45,1.35)
	pan=-bounds.get_center()*CELL*zoom
	queue_redraw()

func update_characters(items:Array,task_states:Dictionary) -> void:
	profiles=items;states=task_states
	var valid={}
	for i in range(profiles.size()):
		var p=profiles[i];valid[p.id]=true
		if not actors.has(p.id):actors[p.id]={"pos":Vector2(model.station(p.id,i)),"path":[],"timer":4.0+float(i)*2,"state":"idle","seat":{},"seated":0.0,"activity":{},"visits":0,"last_kind":""}
	for id in actors.keys():
		if not valid.has(id):social.cancel(self,id);actors.erase(id)
	_refresh_workstations();queue_redraw()

func _refresh_workstations() -> void:
	workstations.clear()
	for p in profiles:workstations[p.id]=model.workstation(p.id)
	leisure_slots=Leisure.slots(model)

func layout_changed() -> void:
	social.reset(self)
	var floor_cells=model.floor_map(model.data.rooms,model.data.furniture)
	_refresh_workstations()
	for i in range(profiles.size()):
		var id=profiles[i].id
		if not actors.has(id):continue
		actors[id].path=[];actors[id].timer=0.0;actors[id].seated=0.0;actors[id].seat={}
		actors[id].activity={}
		if not floor_cells.has(Vector2i(actors[id].pos.round())):actors[id].pos=Vector2(model.station(id,i))
	queue_redraw()

func _process(delta:float) -> void:
	if model==null:return
	elapsed+=delta
	origin=size/2+pan+Vector2(0,18)
	social.tick(self,delta)
	for i in range(profiles.size()):
		var p=profiles[i];var a=actors.get(p.id,{})
		if a.is_empty():continue
		var state=states.get(p.id,{}).get("status","idle")
		if a.state!=state:
			a.state=state;a.timer=0.0;a.path=[];a.activity={}
		if state=="idle" and social.controls(p.id):social.advance_actor(self,p.id,delta);continue
		if not a.activity.is_empty() and a.activity.phase=="using":
			a.activity.remaining-=delta
			if a.activity.remaining<=0:a.activity={};a.timer=4.0+float(i)
		var slot=workstations.get(p.id,{}) if AT_DESK.has(state) else {}
		if not a.activity.is_empty() and a.activity.phase=="using":slot=a.activity.seat
		var wants_seat=not slot.is_empty()
		if a.seated>0:
			if wants_seat and a.seat.id==slot.id:
				a.seated=move_toward(a.seated,1.0,delta*3.5);continue
			a.seated=move_toward(a.seated,0.0,delta*3.5)
			if a.seated>0:continue
			a.seat={}
		if wants_seat and a.path.is_empty() and a.pos.distance_to(Vector2(slot.approach))<.01:
			a.seat=slot;a.seated=minf(1.0,delta*3.5);continue
		a.timer-=delta
		if not a.activity.is_empty():
			if a.activity.phase=="using":continue
			if a.path.is_empty() and a.pos.distance_to(Vector2(a.activity.approach))<.01:
				a.activity.phase="using";continue
		elif a.path.is_empty() and a.timer<=0:
			if state=="idle":_choose_activity(p.id,i,a)
			var target=model.station(p.id,i)
			if a.activity.is_empty() and not AT_DESK.has(state):
				var floor_cells=model.floor_map(model.data.rooms,model.data.furniture)
				var nearby=[]
				var social_cells=social.reserved_cells()
				for q in floor_cells:
					if Vector2(q).distance_to(a.pos)<4.0 and not social_cells.has(q):nearby.append(q)
				if not nearby.is_empty():target=nearby[(int(elapsed/8)+i*7)%nearby.size()]
			if a.activity.is_empty():a.path=model.path_to(Vector2i(a.pos.round()),target)
			if not a.path.is_empty() and a.pos.distance_to(a.pos.round())>.01:a.path.push_front(Vector2i(a.pos.round()))
			a.timer=10.0+float(i)*2
		_move_actor(a,delta)
	queue_redraw()

func _move_actor(actor:Dictionary,delta:float) -> void:
	if actor.path.is_empty():return
	var target=Vector2(actor.path[0]);actor.pos=actor.pos.move_toward(target,delta*2.0)
	if actor.pos.distance_to(target)<.01:actor.path.pop_front()

func greet() -> void:
	var count=social.greet(self)
	notification.emit("伙伴向你挥手回应。这是本地互动，不消耗额度。" if count>0 else "大家正忙，等空闲时再打招呼吧。")
	queue_redraw()

func _choose_activity(id:String,index:int,actor:Dictionary) -> void:
	var reserved=social.reserved_cells()
	for other_id in actors:
		if other_id==id:continue
		var activity=actors[other_id].activity
		if not activity.is_empty():reserved[activity.key]=true;reserved[activity.approach]=true
	var activity=Leisure.choose(model,Vector2i(actor.pos.round()),leisure_slots,reserved,index*3+actor.visits,actor.last_kind)
	if activity.is_empty():return
	actor.activity=activity;actor.path=activity.path;activity.erase("path")
	actor.last_kind=activity.kind;actor.visits+=1

func _person_position(actor:Dictionary) -> Vector2:
	var standing=(actor.pos+Vector2(.5,.8))*CELL
	if not actor.activity.is_empty() and actor.activity.phase=="using" and actor.activity.action in ["music","piano"]:standing.x+=round(sin(elapsed*2.5)*2)
	return standing.lerp(actor.seat.seat*CELL,actor.seated) if actor.seated>0 else standing

func _gui_input(event:InputEvent) -> void:
	if event is InputEventMouseMotion:
		if dragging:pan+=event.relative;queue_redraw()
		hover=Vector2i(((event.position-origin)/zoom/CELL).floor())
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:dragging=event.pressed
		if not event.pressed:return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var old=zoom;zoom=clampf(zoom*(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.1),.4,2.1)
			pan=(pan-(event.position-size/2-Vector2(0,18)))*(zoom/old)+(event.position-size/2-Vector2(0,18))
			accept_event();return
		if event.button_index==MOUSE_BUTTON_RIGHT:selected.emit("cancel","");return
		if event.button_index==MOUSE_BUTTON_LEFT:
			var world_pos=(event.position-origin)/zoom
			var cell=Vector2i((world_pos/CELL).floor())
			if mode in ["furniture","room"]:placed.emit(cell);return
			if mode=="inspect":
				for id in actors:
					var pos=_person_position(actors[id])
					if Rect2(pos-Vector2(22,58),Vector2(44,66)).has_point(world_pos):selected.emit("profile",id);return
			var f=model.furniture_at(cell)
			if not f.is_empty():selected_id=f.id;selected.emit("furniture",f.id);return
			var room=model.room_at(cell)
			if room!="":selected.emit("room",room)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("172e32"))
	if model==null:return
	origin=size/2+pan+Vector2(0,18)
	draw_set_transform(origin,0,Vector2.ONE*zoom)
	var bounds=Rect2(model.rect_of(model.data.rooms[0]))
	for room in model.data.rooms:bounds=bounds.merge(Rect2(model.rect_of(room)))
	var extent=Rect2(bounds.position*CELL-Vector2(70,100),bounds.size*CELL+Vector2(140,160))
	draw_rect(extent,Color("294644"))
	for y in range(int(extent.position.y/20),int(extent.end.y/20)):
		for x in range(int(extent.position.x/20),int(extent.end.x/20)):
			if posmod(x*31+y*13,11)==0:
				draw_rect(Rect2(x*20,y*20,4,3),Color("3e5b50"));draw_rect(Rect2(x*20+5,y*20-2,3,4),Color("375746"))
	for room in model.data.rooms:_draw_room(room)
	for f in model.data.furniture:
		if not Model.CATALOG[f.kind].solid:_draw_item(f)
	var drawables=[]
	for f in model.data.furniture:
		if Model.CATALOG[f.kind].solid:drawables.append({"y":float(model.rect_of(f).end.y)*CELL-5,"kind":"f","value":f})
		if f.kind=="desk":
			drawables.append({"y":float(model.rect_of(f).end.y)*CELL-4.6,"kind":"chair","value":f})
			if posmod(int(f.get("rot",0)),4) in [1,3]:drawables.append({"y":float(model.rect_of(f).end.y)*CELL-4.8,"kind":"surface","value":f})
		elif f.kind=="sofa":drawables.append({"y":float(model.rect_of(f).end.y)*CELL-4.6,"kind":"sofa_front","value":f})
	for p in profiles:
		if actors.has(p.id):
			var a=actors[p.id];var depth=a.seat.bottom*CELL-4.7+float(a.seat.get("depth_offset",0)) if a.seated>0 else (a.pos.y+.8)*CELL
			if _split_seated_actor(a):drawables.append({"y":a.seat.bottom*CELL-4.9,"kind":"legs","value":p})
			drawables.append({"y":depth,"kind":"p","value":p})
	drawables.sort_custom(func(a,b):return a.y<b.y)
	for d in drawables:
		if d.kind=="f":_draw_item(d.value)
		elif d.kind=="chair":_draw_desk_front(d.value)
		elif d.kind=="surface":_draw_desk_surface(d.value)
		elif d.kind=="sofa_front":_draw_sofa(d.value,true)
		elif d.kind=="legs":_draw_person(d.value,"lower")
		else:
			var a=actors[d.value.id]
			_draw_person(d.value,"upper" if _split_seated_actor(a) else "all")
	for p in profiles:
		if actors.has(p.id):_draw_person_labels(p)
	_draw_social_bubbles()
	if mode in ["furniture","room"] and hover.x>-999:
		var item=placement.duplicate(true);item.x=hover.x;item.y=hover.y
		var err=model.validate_furniture(item,moving_id) if mode=="furniture" else model.validate_room(item)
		var rect=Rect2(model.rect_of(item));rect.position*=CELL;rect.size*=CELL
		if mode=="room" and item.has("template") and err=="":
			_draw_room(item)
			var contents=Themes.furniture(item)
			contents.sort_custom(func(a,b):
				if Model.CATALOG[a.kind].solid!=Model.CATALOG[b.kind].solid:return not Model.CATALOG[a.kind].solid
				return model.rect_of(a).end.y<model.rect_of(b).end.y)
			for f in contents:
				_draw_item(f)
				if f.kind=="sofa":_draw_sofa(f,true)
		draw_rect(rect,Color(.55,.82,.69,.23) if err=="" else Color(.86,.38,.34,.24))
		draw_rect(rect,Color("a4d5b5") if err=="" else Color("e68f7f"),false,2)
		if mode=="furniture":
			_draw_item(item)
			if item.kind=="desk":
				if posmod(int(item.get("rot",0)),4) in [1,3]:_draw_desk_surface(item)
				_draw_desk_front(item)
			elif item.kind=="sofa":_draw_sofa(item,true)
		last_hover_error=err
	draw_set_transform(Vector2.ZERO)
	if mode in ["furniture","room"]:
		var text=last_hover_error if last_hover_error!="" else ("点击扩建整间主题房间 · 右键取消" if mode=="room" else "点击放置 · R 旋转 · 右键取消")
		draw_string(font,Vector2(24,size.y-24),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e1d9b9"))

func _draw_room(room:Dictionary) -> void:
	var rect=model.rect_of(room);var pos=Vector2(rect.position)*CELL;var dims=Vector2(rect.size)*CELL
	draw_rect(Rect2(pos+Vector2(8,10),dims+Vector2(8,0)),Color(.04,.1,.13,.35))
	var style=Themes.FLOORS[posmod(int(room.get("floor",0)),Themes.FLOORS.size())];var floors=style.colors
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var p=Vector2(x,y)*CELL
			draw_rect(Rect2(p,Vector2.ONE*CELL),Color(floors[posmod(x+y*3,3)]))
			if style.pattern=="garden":
				for i in range(3):
					var blade=p+Vector2(posmod(x*13+y*7+i*11,35)+2,posmod(x*3+y*19+i*7,34)+2)
					draw_rect(Rect2(blade,Vector2(2,4)),Color("aac392"));draw_rect(Rect2(blade+Vector2(3,2),Vector2(2,2)),Color("a0bd8f"))
			elif style.pattern=="tile":
				draw_rect(Rect2(p+Vector2(1,1),Vector2(38,38)),Color("98ada9"),false,1)
				if posmod(x+y,3)==0:draw_rect(Rect2(p+Vector2(18,18),Vector2(4,4)),Color("a9bbb1"))
			else:
				draw_line(p+Vector2(0,39),p+Vector2(40,39),Color("b59878"),1)
				draw_line(p+Vector2(0,19),p+Vector2(40,19),Color(.55,.46,.36,.16),1)
				draw_line(p+Vector2(20 if y%2==0 else 0,0),p+Vector2(20 if y%2==0 else 0,19),Color(.55,.46,.36,.19),1)
			if mode!="inspect":draw_rect(Rect2(p,Vector2.ONE*CELL),Color(.2,.32,.3,.18),false,1)
	for x in range(rect.position.x,rect.end.x):
		if not _has_door(Vector2i(x,rect.position.y),Vector2i.UP):
			var p=Vector2(x,rect.position.y)*CELL
			draw_rect(Rect2(p+Vector2(0,-36),Vector2(CELL,36)),Color(style.wall))
			draw_rect(Rect2(p+Vector2(0,-39),Vector2(CELL,5)),Color(style.trim))
			draw_rect(Rect2(p+Vector2(0,-5),Vector2(CELL,7)),Color("806a54"))
			if posmod(x-rect.position.x,6)==3 or style.pattern=="garden":
				draw_rect(Rect2(p+Vector2(1,-30),Vector2(35,23)),Color("8d9d8d"));draw_rect(Rect2(p+Vector2(4,-28),Vector2(29,18)),Color("a9ccc3"))
				draw_line(p+Vector2(18,-28),p+Vector2(18,-10),Color("eee0c0"),2);draw_line(p+Vector2(4,-19),p+Vector2(33,-19),Color("eee0c0"),2)
			if int(room.get("floor",0)) in [4,5]:
				draw_line(p+Vector2(0,-30),p+Vector2(20,-25),Color("596c66"),1);draw_line(p+Vector2(20,-25),p+Vector2(40,-30),Color("596c66"),1)
				draw_circle(p+Vector2(20,-23),7,Color(.98,.82,.53,.13));draw_rect(Rect2(p+Vector2(18,-25),Vector2(4,6)),Color("f3d997"))
		if not _has_door(Vector2i(x,rect.end.y-1),Vector2i.DOWN):draw_rect(Rect2(Vector2(x,rect.end.y)*CELL,Vector2(CELL,8)),Color("957754"))
	for y in range(rect.position.y,rect.end.y):
		if not _has_door(Vector2i(rect.position.x,y),Vector2i.LEFT):draw_rect(Rect2(Vector2(rect.position.x,y)*CELL-Vector2(6,0),Vector2(7,CELL)),Color("ede0bf"))
		if not _has_door(Vector2i(rect.end.x-1,y),Vector2i.RIGHT):draw_rect(Rect2(Vector2(rect.end.x,y)*CELL,Vector2(7,CELL)),Color("aa8a65"))
	for d in model.data.doors:
		var a=Vector2i(int(d.a[0]),int(d.a[1]));var b=Vector2i(int(d.b[0]),int(d.b[1]))
		var mid=(Vector2(a+b)/2+Vector2(.5,.5))*CELL
		draw_rect(Rect2(mid-Vector2(13,13),Vector2(26,26)),Color("e2c596"))
	var name_text=room.name
	draw_string(font,pos+Vector2(6,-53),name_text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("e9dfbe"))

func _has_door(cell:Vector2i,direction:Vector2i) -> bool:
	for d in model.data.doors:
		var a=Vector2i(int(d.a[0]),int(d.a[1]));var b=Vector2i(int(d.b[0]),int(d.b[1]))
		if (a==cell and b==cell+direction) or (b==cell and a==cell+direction):return true
	return false

func _draw_item(f:Dictionary) -> void:
	var rect=model.rect_of(f)
	if f.get("id","")==selected_id:
		draw_rect(Rect2(Vector2(rect.position)*CELL,Vector2(rect.size)*CELL),Color(.95,.8,.49,.2))
		draw_rect(Rect2(Vector2(rect.position)*CELL,Vector2(rect.size)*CELL),Color("f0ca82"),false,2)
	var base=Vector2(float(Model.CATALOG[f.kind].w),float(Model.CATALOG[f.kind].h))*CELL
	var center=(Vector2(rect.position)+Vector2(rect.size)/2)*CELL
	if f.kind=="desk":
		Art.desk(self,center,int(f.get("rot",0)));Art.chair(self,model.desk_seat(f)*CELL,int(f.get("rot",0)))
	elif f.kind=="sofa":_draw_sofa(f)
	elif Decor.KINDS.has(f.kind):Decor.draw(self,f.kind,center,1,int(f.get("rot",0)),elapsed)
	else:
		draw_set_transform(origin+center*zoom,float(f.get("rot",0))*PI/2,Vector2.ONE*zoom)
		Art.furniture(self,f.kind,-base/2,2)
		draw_set_transform(origin,0,Vector2.ONE*zoom)
	if f.kind=="desk" and f.get("owner","")!="" and mode!="inspect":
		var owner=""
		for p in profiles:
			if p.id==f.owner:owner=p.name
		if owner!="":draw_string(font,Vector2(rect.position)*CELL+Vector2(6,27),owner,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("f9efdc"))

func _draw_desk_front(f:Dictionary) -> void:
	if posmod(int(f.get("rot",0)),4)==2:_draw_desk_surface(f)
	Art.chair(self,model.desk_seat(f)*CELL,int(f.get("rot",0)),true)

func _draw_desk_surface(f:Dictionary) -> void:
	var rect=model.rect_of(f);var center=(Vector2(rect.position)+Vector2(rect.size)/2)*CELL
	Art.desk(self,center,int(f.get("rot",0)),true)

func _draw_sofa(f:Dictionary,foreground:bool=false) -> void:
	var rect=model.rect_of(f);var center=(Vector2(rect.position)+Vector2(rect.size)/2)*CELL
	Art.sofa(self,center,int(f.get("rot",0)),foreground)

func _split_seated_actor(actor:Dictionary) -> bool:
	return actor.seated>=.5 and actor.seat.get("kind","")!="sofa" and actor.seat.facing in [1,3]

func _draw_person(p:Dictionary,part:String="all") -> void:
	var a=actors[p.id];var pos=_person_position(a)
	var life=social.presentation(self,p.id)
	var state=states.get(p.id,{}).get("status","idle")
	if p.id==selected_id and part!="upper":
		draw_circle(pos+Vector2(0,-2),22,Color(.95,.8,.49,.17));draw_arc(pos+Vector2(0,-2),22,0,TAU,32,Color("edc784"),1.5)
	var facing=int(a.seat.get("facing",2));var oriented=false
	if not a.activity.is_empty() and a.activity.phase=="using" and a.activity.action in ["piano","paint","play","watch"]:
		var direction=a.activity.target-(a.pos+Vector2(.5,.5))
		facing=(1 if direction.x>0 else 3) if absf(direction.x)>absf(direction.y) else (2 if direction.y>0 else 0)
		oriented=true;state=a.activity.action
	if life.has("facing") and a.seated==0:facing=life.facing;oriented=true;state="chat"
	Art.person(self,p,pos,1.65,elapsed+float(pos.x),state,not a.path.is_empty(),a.seated>=.5,facing,part,oriented,life.get("kind",""))
	if part!="lower" and not a.activity.is_empty() and a.activity.phase=="using" and life.get("kind","") not in ["wave","highfive","stretch","tidy"]:
		Art.pastime(self,p,pos,a.activity.action,elapsed,a.activity.target*CELL)
	if part!="lower" and life.get("kind","")=="hum":Art.pastime(self,p,pos,"music",elapsed,pos)

func _draw_person_labels(p:Dictionary) -> void:
	var a=actors[p.id];var pos=_person_position(a)
	var state=states.get(p.id,{}).get("status","idle")
	var name_pos=pos
	if a.seated>0 and a.seat.get("kind","")!="sofa":name_pos.y=lerpf(pos.y,float(a.seat.bottom)*CELL+2,a.seated)
	var side_label=a.seated>0 and a.seat.get("kind","")=="sofa" and a.seat.facing in [1,3]
	if side_label:name_pos+=Vector2(52 if a.seat.facing==1 else -52,-22)*a.seated
	var label=p.name
	var tw=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
	draw_rect(Rect2(name_pos+Vector2(-tw/2-6,6),Vector2(tw+12,19)),Color(.12,.23,.23,.92))
	draw_string(font,name_pos+Vector2(-tw/2,20),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("eee7cd"))
	var symbol=""
	var col=Color("a6c6b3")
	if state in ["running","working","starting"]:symbol="…"
	elif state in ["waiting","approval"]:symbol="?";col=Color("edc784")
	elif state=="completed":symbol="✓"
	elif state in ["failed","disconnected"]:symbol="!";col=Color("e39b86")
	elif state=="idle" and not a.activity.is_empty() and social.presentation(self,p.id).get("caption","")=="":
		var caption=("去" if a.activity.phase=="going" else "")+a.activity.label
		var width=font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		var caption_pos=name_pos+Vector2(0,-21) if side_label else pos+Vector2(0,-83)
		draw_rect(Rect2(caption_pos+Vector2(-width/2-6,6),Vector2(width+12,19)),Color("eae0c5"))
		draw_string(font,caption_pos+Vector2(-width/2,20),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("526d62"))
	if symbol!="":
		draw_rect(Rect2(pos+Vector2(-13,-76),Vector2(26,22)),col)
		draw_rect(Rect2(pos+Vector2(-3,-55),Vector2(6,4)),col)
		var symbol_width=font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		draw_string(font,pos+Vector2(-symbol_width/2,-60),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("284540"))

func _draw_social_bubbles() -> void:
	# Alternate short local lines above the room, leaving actual task/chat UI untouched.
	var view=Rect2(-origin/zoom,size/zoom).grow(-6)
	var occupied:Array[Rect2]=[]
	for id in actors:
		var life=social.presentation(self,id);var caption=life.get("caption","")
		if caption=="":continue
		var pos=_person_position(actors[id]);var width=font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+16
		var bubble=Rect2(pos+Vector2(-width/2,-102),Vector2(width,24))
		bubble.position.x=clampf(bubble.position.x,view.position.x,view.end.x-width)
		bubble.position.y=maxf(bubble.position.y,view.position.y)
		for attempt in range(4):
			var overlaps=false
			for other in occupied:
				if bubble.grow(3).intersects(other):overlaps=true;break
			if not overlaps:break
			bubble.position.y-=28
		if not view.encloses(bubble):continue
		occupied.append(bubble)
		draw_rect(Rect2(bubble.position+Vector2(2,3),bubble.size),Color(.1,.2,.2,.18))
		draw_rect(bubble,Color("fbf2d9"));draw_rect(bubble,Color("cbb480"),false,1)
		var tail_x=clampf(pos.x,bubble.position.x+7,bubble.end.x-7)
		draw_colored_polygon(PackedVector2Array([Vector2(tail_x-4,bubble.end.y-1),Vector2(tail_x+4,bubble.end.y-1),Vector2(tail_x,bubble.end.y+5)]),Color("fbf2d9"))
		draw_string(font,bubble.position+Vector2(8,16),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("415d56"))
	for pair in social.pairs.values():
		if pair.phase!="chat" or not social.idle(self,pair.ids[0]) or not social.idle(self,pair.ids[1]):continue
		var age=social.time-pair.started
		var a=_person_position(actors[pair.ids[0]]);var b=_person_position(actors[pair.ids[1]])
		if pair.style=="snack" and age>=3 and age<4.6:
			var t=(age-3)/1.6;var biscuit=b.lerp(a,t)+Vector2(0,-25-sin(t*PI)*13)
			draw_rect(Rect2(biscuit-Vector2(4,3),Vector2(8,6)),Color("d6a468"))
			draw_rect(Rect2(biscuit-Vector2(2,2),Vector2(5,3)),Color("f4d7a0"))
		elif pair.style=="highfive" and age>=3.2 and age<4.2:
			var spark=(a+b)/2+Vector2(0,-45);var radius=6+(age-3.2)*7
			for direction in [Vector2.UP,Vector2.LEFT,Vector2.RIGHT]:draw_line(spark+direction*radius,spark+direction*(radius+4),Color("f8d786"),2)
