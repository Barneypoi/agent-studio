extends Control
const Art=preload("res://pixel_art.gd")
const Model=preload("res://studio_model.gd")
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
		if not actors.has(p.id):actors[p.id]={"pos":Vector2(model.station(p.id,i)),"path":[],"timer":4.0+float(i)*2,"state":"idle","seat":{},"seated":0.0}
	for id in actors.keys():
		if not valid.has(id):actors.erase(id)
	_refresh_workstations();queue_redraw()

func _refresh_workstations() -> void:
	workstations.clear()
	for p in profiles:workstations[p.id]=model.workstation(p.id)

func layout_changed() -> void:
	var floor_cells=model.floor_map(model.data.rooms,model.data.furniture)
	_refresh_workstations()
	for i in range(profiles.size()):
		var id=profiles[i].id
		if not actors.has(id):continue
		actors[id].path=[];actors[id].timer=0.0;actors[id].seated=0.0;actors[id].seat={}
		if not floor_cells.has(Vector2i(actors[id].pos.round())):actors[id].pos=Vector2(model.station(id,i))
	queue_redraw()

func _process(delta:float) -> void:
	if model==null:return
	elapsed+=delta
	origin=size/2+pan+Vector2(0,18)
	for i in range(profiles.size()):
		var p=profiles[i];var a=actors.get(p.id,{})
		if a.is_empty():continue
		var state=states.get(p.id,{}).get("status","idle")
		if a.state!=state:
			a.state=state;a.timer=0.0;a.path=[]
		var slot=workstations.get(p.id,{})
		var wants_seat=AT_DESK.has(state) and not slot.is_empty()
		if a.seated>0:
			if wants_seat and a.seat.id==slot.id:
				a.seated=move_toward(a.seated,1.0,delta*3.5);continue
			a.seated=move_toward(a.seated,0.0,delta*3.5)
			if a.seated>0:continue
			a.seat={};a.timer=0.0
		if wants_seat and a.path.is_empty() and a.pos.distance_to(Vector2(slot.approach))<.01:
			a.seat=slot;a.seated=minf(1.0,delta*3.5);continue
		a.timer-=delta
		if a.path.is_empty() and a.timer<=0:
			var target=model.station(p.id,i)
			if not AT_DESK.has(state):
				var floor_cells=model.floor_map(model.data.rooms,model.data.furniture)
				var nearby=[]
				for q in floor_cells:
					if Vector2(q).distance_to(a.pos)<4.0:nearby.append(q)
				if not nearby.is_empty():target=nearby[(int(elapsed/8)+i*7)%nearby.size()]
			a.path=model.path_to(Vector2i(a.pos.round()),target)
			if not a.path.is_empty() and a.pos.distance_to(a.pos.round())>.01:a.path.push_front(Vector2i(a.pos.round()))
			a.timer=10.0+float(i)*2
		if not a.path.is_empty():
			var target=Vector2(a.path[0]);a.pos=a.pos.move_toward(target,delta*2.0)
			if a.pos.distance_to(target)<.01:a.path.pop_front()
	queue_redraw()

func _person_position(actor:Dictionary) -> Vector2:
	var standing=(actor.pos+Vector2(.5,.8))*CELL
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
		if f.kind=="rug":_draw_item(f)
	var drawables=[]
	for f in model.data.furniture:
		if f.kind!="rug":drawables.append({"y":float(model.rect_of(f).end.y)*CELL-5,"kind":"f","value":f})
		if f.kind=="desk":
			drawables.append({"y":float(model.rect_of(f).end.y)*CELL-4.6,"kind":"chair","value":f})
			if posmod(int(f.get("rot",0)),4) in [1,3]:drawables.append({"y":float(model.rect_of(f).end.y)*CELL-4.8,"kind":"surface","value":f})
	for p in profiles:
		if actors.has(p.id):
			var a=actors[p.id];var depth=a.seat.bottom*CELL-4.7 if a.seated>0 else (a.pos.y+.8)*CELL
			if a.seated>=.5 and a.seat.facing in [1,3]:drawables.append({"y":a.seat.bottom*CELL-4.9,"kind":"legs","value":p})
			drawables.append({"y":depth,"kind":"p","value":p})
	drawables.sort_custom(func(a,b):return a.y<b.y)
	for d in drawables:
		if d.kind=="f":_draw_item(d.value)
		elif d.kind=="chair":_draw_desk_front(d.value)
		elif d.kind=="surface":_draw_desk_surface(d.value)
		elif d.kind=="legs":_draw_person(d.value,"lower")
		else:
			var a=actors[d.value.id]
			_draw_person(d.value,"upper" if a.seated>=.5 and a.seat.facing in [1,3] else "all")
	for p in profiles:
		if actors.has(p.id):_draw_person_labels(p)
	if mode in ["furniture","room"] and hover.x>-999:
		var item=placement.duplicate(true);item.x=hover.x;item.y=hover.y
		var err=model.validate_furniture(item,moving_id) if mode=="furniture" else model.validate_room(item)
		var rect=Rect2(model.rect_of(item));rect.position*=CELL;rect.size*=CELL
		draw_rect(rect,Color(.55,.82,.69,.23) if err=="" else Color(.86,.38,.34,.24))
		draw_rect(rect,Color("a4d5b5") if err=="" else Color("e68f7f"),false,2)
		if mode=="furniture":
			_draw_item(item)
			if item.kind=="desk":
				if posmod(int(item.get("rot",0)),4) in [1,3]:_draw_desk_surface(item)
				_draw_desk_front(item)
		last_hover_error=err
	draw_set_transform(Vector2.ZERO)
	if mode in ["furniture","room"]:
		var text=last_hover_error if last_hover_error!="" else "点击放置 · R 旋转 · 右键取消"
		draw_string(font,Vector2(24,size.y-24),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e1d9b9"))

func _draw_room(room:Dictionary) -> void:
	var rect=model.rect_of(room);var pos=Vector2(rect.position)*CELL;var dims=Vector2(rect.size)*CELL
	draw_rect(Rect2(pos+Vector2(8,10),dims+Vector2(8,0)),Color(.04,.1,.13,.35))
	var floors=[["d0b08a","d8b993","c7a37f"],["9bac9f","a4b4a6","90a394"],["c2ad9c","cdb9a7","b9a28f"]][int(room.get("floor",0))%3]
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var p=Vector2(x,y)*CELL
			draw_rect(Rect2(p,Vector2.ONE*CELL),Color(floors[posmod(x+y*3,3)]))
			draw_line(p+Vector2(0,39),p+Vector2(40,39),Color("b59878"),1)
			draw_line(p+Vector2(0,19),p+Vector2(40,19),Color(.55,.46,.36,.16),1)
			draw_line(p+Vector2(20 if y%2==0 else 0,0),p+Vector2(20 if y%2==0 else 0,19),Color(.55,.46,.36,.19),1)
			if mode!="inspect":draw_rect(Rect2(p,Vector2.ONE*CELL),Color(.2,.32,.3,.18),false,1)
	for x in range(rect.position.x,rect.end.x):
		if not _has_door(Vector2i(x,rect.position.y),Vector2i.UP):
			var p=Vector2(x,rect.position.y)*CELL
			draw_rect(Rect2(p+Vector2(0,-36),Vector2(CELL,36)),Color("ead8b4"))
			draw_rect(Rect2(p+Vector2(0,-39),Vector2(CELL,5)),Color("fff0ce"))
			draw_rect(Rect2(p+Vector2(0,-5),Vector2(CELL,7)),Color("806a54"))
			if posmod(x-rect.position.x,6)==3:
				draw_rect(Rect2(p+Vector2(1,-30),Vector2(35,23)),Color("8d9d8d"));draw_rect(Rect2(p+Vector2(4,-28),Vector2(29,18)),Color("a9ccc3"))
				draw_line(p+Vector2(18,-28),p+Vector2(18,-10),Color("eee0c0"),2);draw_line(p+Vector2(4,-19),p+Vector2(33,-19),Color("eee0c0"),2)
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

func _draw_person(p:Dictionary,part:String="all") -> void:
	var a=actors[p.id];var pos=_person_position(a)
	var state=states.get(p.id,{}).get("status","idle")
	if p.id==selected_id and part!="upper":
		draw_circle(pos+Vector2(0,-2),22,Color(.95,.8,.49,.17));draw_arc(pos+Vector2(0,-2),22,0,TAU,32,Color("edc784"),1.5)
	Art.person(self,p,pos,1.65,elapsed+float(pos.x),state,not a.path.is_empty(),a.seated>=.5,int(a.seat.get("facing",2)),part)

func _draw_person_labels(p:Dictionary) -> void:
	var a=actors[p.id];var pos=_person_position(a)
	var state=states.get(p.id,{}).get("status","idle")
	var name_pos=pos
	if a.seated>0:name_pos.y=lerpf(pos.y,float(a.seat.bottom)*CELL+2,a.seated)
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
	if symbol!="":
		draw_rect(Rect2(pos+Vector2(-13,-76),Vector2(26,22)),col)
		draw_rect(Rect2(pos+Vector2(-3,-55),Vector2(6,4)),col)
		var symbol_width=font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		draw_string(font,pos+Vector2(-symbol_width/2,-60),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("284540"))
