extends RefCounted
# This module only sees scene actors and status enums. No prompts, task output or APIs.
const CHATS=[
	["歇一小会儿？","好呀，慢慢来。"],
	["窗边的光真好。","适合发一会儿呆。"],
	["击个掌？","好耶！"]
]
var time=0.0
var scan_due=1.0
var serial=0
var pairs={}
var members={}
var effects={}
var due={}
var last_states={}

func idle(world,id:String) -> bool:
	return world.actors.has(id) and world.states.get(id,{}).get("status","idle")=="idle"

func available(world,id:String,initiator:bool=false) -> bool:
	if not idle(world,id) or members.has(id) or effects.has(id):return false
	var a=world.actors[id]
	if a.state!="idle":return false
	if a.seated>0 and a.seated<1:return false
	if initiator:return a.activity.is_empty() and a.seated==0
	return a.path.is_empty() and (a.activity.is_empty() or a.activity.phase=="using")

func cancel(world,id:String) -> void:
	if not members.has(id):return
	var key=members[id];var pair=pairs[key]
	for actor_id in pair.ids:
		members.erase(actor_id)
		if world.actors.has(actor_id):
			if actor_id==pair.ids[0]:world.actors[actor_id].path=[]
			world.actors[actor_id].timer=1.5 if idle(world,actor_id) else 0.0
		if due.has(actor_id):due[actor_id].social=time+28
	pairs.erase(key)

func reset(world) -> void:
	for key in pairs.keys():cancel(world,key)
	effects.clear();scan_due=time+3

func meeting(world,from_id:String,to_id:String) -> Dictionary:
	if not available(world,from_id,true) or not available(world,to_id):return {}
	var a=world.actors[from_id];var b=world.actors[to_id]
	var start=Vector2i(a.pos.round());var anchor=Vector2i(b.pos.round())
	if a.pos.distance_to(b.pos)>7:return {}
	var floor_cells=world.model.floor_map(world.model.data.rooms,world.model.data.furniture)
	if not floor_cells.has(start) or not floor_cells.has(anchor) or floor_cells[start]!=floor_cells[anchor]:return {}
	var blocked=reserved_cells()
	for actor_id in world.actors:
		if actor_id!=from_id:blocked[Vector2i(world.actors[actor_id].pos.round())]=true
	for actor in world.actors.values():
		if not actor.activity.is_empty():blocked[actor.activity.approach]=true
	for door in world.model.data.doors:
		blocked[Vector2i(door.a[0],door.a[1])]=true;blocked[Vector2i(door.b[0],door.b[1])]=true
	var result={}
	for direction in [Vector2i.LEFT,Vector2i.RIGHT]:
		var cell=anchor+direction
		if not floor_cells.has(cell) or floor_cells[cell]!=floor_cells[anchor] or blocked.has(cell):continue
		var exits=0
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if floor_cells.has(cell+step) and floor_cells[cell+step]==floor_cells[cell]:exits+=1
		if exits<3:continue
		var path=world.model.path_to(start,cell)
		if (start!=cell and path.is_empty()) or path.size()>12:continue
		if result.is_empty() or path.size()<result.path.size():result={"cell":cell,"path":path}
	return result

func start_pair(world,from_id:String,to_id:String) -> bool:
	var plan=meeting(world,from_id,to_id)
	if plan.is_empty():return false
	var lines=CHATS[serial%CHATS.size()].duplicate();var style="highfive" if serial%3==2 else "chat"
	var activity=world.actors[to_id].activity
	if not activity.is_empty():
		style="chat";lines=CHATS[0].duplicate()
		match activity.kind:
			"books":lines=["这本书怎么样？","想再看一会儿。"];style="chat"
			"tea","coffee":lines=["闻到香味啦。","分你一块点心。"] ;style="snack"
			"record","piano":lines=["这段旋律真好听。","一起听一会儿吧。"];style="chat"
	serial+=1
	pairs[from_id]={"ids":[from_id,to_id],"phase":"going","started":time,"cell":plan.cell,"lines":lines,"style":style}
	members[from_id]=from_id;members[to_id]=from_id
	var a=world.actors[from_id];a.path=plan.path
	if a.pos.distance_to(a.pos.round())>.01:a.path.push_front(Vector2i(a.pos.round()))
	return true

func reserved_cells() -> Dictionary:
	var result={}
	for pair in pairs.values():result[pair.cell]=true
	return result

func gesture(id:String,kind:String,caption:String="",lock:bool=false) -> void:
	effects[id]={"kind":kind,"caption":caption,"start":time,"end":time+(2.2 if lock else 2.8),"lock":lock}

func greet(world) -> int:
	var ids=world.actors.keys()
	if ids.has(world.selected_id):ids.erase(world.selected_id);ids.push_front(world.selected_id)
	var count=0
	for id in ids:
		if not idle(world,id):continue
		gesture(id,"wave","嗨，见到你啦！" if count==0 else "")
		count+=1
		if count==3:break
	return count

func cheer(world,finished_id:String) -> void:
	var location=world.actors[finished_id].pos
	for id in world.actors:
		if not available(world,id) or world.actors[id].pos.distance_to(location)>6:continue
		if world.model.room_at(Vector2i(world.actors[id].pos.round()))!=world.model.room_at(Vector2i(location.round())):continue
		gesture(id,"wave","辛苦啦！");return

func tick(world,delta:float) -> void:
	time+=delta
	for key in pairs.keys():
		if not idle(world,pairs[key].ids[0]) or not idle(world,pairs[key].ids[1]):cancel(world,key)
	for id in due.keys():
		if world.actors.has(id):continue
		cancel(world,id);due.erase(id);last_states.erase(id);effects.erase(id)
	var index=0
	for id in world.actors:
		if not due.has(id):due[id]={"social":time+12+index*2,"gesture":time+18+index*4,"wave":time+4}
		var state=world.states.get(id,{}).get("status","idle")
		if last_states.get(id,"") in ["starting","running","working"] and state=="completed":cheer(world,id)
		last_states[id]=state
		if state!="idle":cancel(world,id);effects.erase(id)
		index+=1
	for key in pairs.keys():
		var pair=pairs[key];var a=world.actors[pair.ids[0]]
		if pair.phase=="going":
			if time-pair.started>10:cancel(world,key)
			elif a.path.is_empty() and a.pos.distance_to(Vector2(pair.cell))<.01:pair.phase="chat";pair.started=time
		elif time-pair.started>6.4:cancel(world,key)
	for id in effects.keys():
		if effects[id].end>time:continue
		if effects[id].lock and world.actors.has(id):world.actors[id].timer=minf(world.actors[id].timer,1.2)
		effects.erase(id)
	if time<scan_due:return
	scan_due=time+.8
	var ids=world.actors.keys()
	for id in ids:
		if available(world,id,true) and due[id].social<=time:
			for buddy in ids:
				if id==buddy or due[buddy].social>time:continue
				if start_pair(world,id,buddy):break
	# Passing greetings never replace movement or facility reservations.
	for i in range(ids.size()):
		var id=ids[i]
		if not idle(world,id) or members.has(id) or effects.has(id) or due[id].wave>time:continue
		for j in range(i+1,ids.size()):
			var buddy=ids[j];var a=world.actors[id];var b=world.actors[buddy]
			if not idle(world,buddy) or members.has(buddy) or effects.has(buddy) or due[buddy].wave>time:continue
			if a.path.is_empty() and b.path.is_empty():continue
			if a.pos.distance_to(b.pos)>1.6:continue
			var route=world.model.path_to(Vector2i(a.pos.round()),Vector2i(b.pos.round()))
			if route.is_empty() or route.size()>2:continue
			gesture(id,"wave","嗨～");gesture(buddy,"wave");due[id].wave=time+20;due[buddy].wave=time+20;break
	for i in range(ids.size()):
		var id=ids[i];var a=world.actors[id]
		if not available(world,id,true) or not a.path.is_empty() or due[id].gesture>time:continue
		var choice=(serial+i)%3;serial+=1
		gesture(id,["stretch","tidy","hum"][choice],["舒展一下","整理衣领","哼首小曲"][choice],true)
		due[id].gesture=time+26+i*3

func controls(id:String) -> bool:
	return members.has(id) or effects.get(id,{}).get("lock",false)

func advance_actor(world,id:String,delta:float) -> void:
	if members.has(id) and members[id]==id and pairs[id].phase=="going":world._move_actor(world.actors[id],delta)

func presentation(world,id:String) -> Dictionary:
	if not idle(world,id):return {}
	if effects.has(id):return effects[id]
	if not members.has(id):return {}
	var pair=pairs[members[id]];var first=pair.ids[0]==id
	if pair.phase=="going":return {"kind":"","caption":"去找伙伴" if first else "","start":time}
	var age=time-pair.started;var text=""
	if first and age<2.8:text=pair.lines[0]
	if not first and age>=3 and age<6:text=pair.lines[1]
	var buddy=pair.ids[1] if first else pair.ids[0]
	if not idle(world,buddy):return {}
	return {"kind":"highfive" if pair.style=="highfive" and age>3 else "chat","caption":text,"start":pair.started,"facing":1 if world.actors[buddy].pos.x>world.actors[id].pos.x else 3}
