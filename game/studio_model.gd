extends RefCounted

const CATALOG = {
	"desk": {"name":"研究工位", "w":2, "h":2, "solid":true, "desc":"绑定伙伴，作为它的日常工位。"},
	"books": {"name":"知识书架", "w":2, "h":1, "solid":true, "desc":"整理工作室的技能与知识。"},
	"plant": {"name":"龟背竹", "w":1, "h":1, "solid":true, "desc":"给工位留一点绿色。"},
	"sofa": {"name":"休息沙发", "w":3, "h":1, "solid":true, "desc":"伙伴待命时的休息角。"},
	"rug": {"name":"编织地毯", "w":3, "h":2, "solid":false, "desc":"可行走的软装，不阻挡通路。"},
	"board": {"name":"任务白板", "w":2, "h":1, "solid":true, "desc":"点击白板查看任务与交付。"},
	"coffee": {"name":"咖啡吧台", "w":2, "h":1, "solid":true, "desc":"工作之间，补充一点灵感。"},
	"lamp": {"name":"落地灯", "w":1, "h":1, "solid":true, "desc":"一盏温暖的小灯。"},
	"cabinet": {"name":"成果柜", "w":2, "h":1, "solid":true, "desc":"点击打开工作目录。"}
}
const SHIRTS = ["6b9d96", "d29a6a", "9b8cbd", "ca7780", "658bad", "a2a368"]
const HAIRS = ["493b3b", "82573e", "d6b976", "b9c3c4", "44394e"]
const SKINS = ["efc3a1", "d9a079", "ad7559", "835743"]
var data = {}
var undo_stack: Array = []
var save_path = ""
var last_error = ""

func defaults() -> Dictionary:
	return {"version":1,"workspace":"", "rooms":[{"id":"r1","name":"灵感工作室","x":0,"y":0,"w":16,"h":11,"floor":0}],"furniture":[
		{"id":"d1","kind":"desk","x":2,"y":3,"rot":0,"owner":"lead"},
		{"id":"d2","kind":"desk","x":7,"y":3,"rot":0,"owner":"research"},
		{"id":"d3","kind":"desk","x":12,"y":3,"rot":0,"owner":"review"},
		{"id":"b1","kind":"books","x":1,"y":0,"rot":0,"owner":""},
		{"id":"b2","kind":"books","x":4,"y":0,"rot":0,"owner":""},
		{"id":"w1","kind":"board","x":9,"y":0,"rot":0,"owner":""},
		{"id":"p1","kind":"plant","x":0,"y":0,"rot":0,"owner":""},
		{"id":"p2","kind":"plant","x":15,"y":0,"rot":0,"owner":""},
		{"id":"c1","kind":"coffee","x":13,"y":8,"rot":0,"owner":""},
		{"id":"s1","kind":"sofa","x":2,"y":9,"rot":0,"owner":""},
		{"id":"l1","kind":"lamp","x":0,"y":9,"rot":0,"owner":""},
		{"id":"r1","kind":"rug","x":2,"y":7,"rot":0,"owner":""},
		{"id":"a1","kind":"cabinet","x":9,"y":9,"rot":0,"owner":""}],
		"profiles":[
			{"id":"lead","name":"小夏","role":"负责人：拆解目标，协调伙伴，整合并检查最终交付。","hair":0,"hair_color":0,"shirt":0,"skin":0,"accessory":0,"skills":[]},
			{"id":"research","name":"阿森","role":"研究员：阅读资料和代码，寻找证据，给出可靠结论。","hair":1,"hair_color":1,"shirt":1,"skin":1,"accessory":1,"skills":[]},
			{"id":"review","name":"米拉","role":"审查员：检查实现、关键风险和验证结果。","hair":2,"hair_color":0,"shirt":2,"skin":0,"accessory":2,"skills":[]}],"doors":[]}

func load_data(path_value: String) -> void:
	save_path = path_value
	data = defaults()
	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text()) if file else null
		if parsed is Dictionary and parsed.get("version") == 1 and parsed.get("rooms") is Array and parsed.get("profiles") is Array:
			data = parsed
		else:
			last_error = "存档无法读取，已保留原文件并载入初始布局"
			DirAccess.copy_absolute(save_path, save_path + ".invalid")
	data["doors"] = make_doors(data.rooms, data.furniture)

func save() -> bool:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var file = FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if not file:
		last_error = "无法写入存档：" + error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var result = DirAccess.rename_absolute(save_path + ".tmp", save_path)
	if result != OK:
		last_error = "保存失败：" + error_string(result)
		return false
	return true

func checkpoint() -> void:
	undo_stack.append(data.duplicate(true))
	if undo_stack.size() > 30: undo_stack.pop_front()

func undo() -> bool:
	if undo_stack.is_empty(): return false
	data = undo_stack.pop_back()
	return save()

func rect_of(item: Dictionary) -> Rect2i:
	if item.has("kind"):
		var c = CATALOG[item.kind]
		return Rect2i(int(item.x),int(item.y), int(c.w) if int(item.rot)%2==0 else int(c.h), int(c.h) if int(item.rot)%2==0 else int(c.w))
	return Rect2i(int(item.x),int(item.y),int(item.w),int(item.h))

func cells(rect: Rect2i) -> Array:
	var out = []
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x): out.append(Vector2i(x,y))
	return out

func room_at(cell: Vector2i, rooms = null) -> String:
	for r in (data.rooms if rooms == null else rooms):
		if rect_of(r).has_point(cell): return r.id
	return ""

func furniture_at(cell: Vector2i) -> Dictionary:
	for i in range(data.furniture.size()-1,-1,-1):
		var f = data.furniture[i]
		if rect_of(f).has_point(cell): return f
	return {}

func floor_map(rooms: Array, furniture: Array) -> Dictionary:
	var result = {}
	for r in rooms:
		for p in cells(rect_of(r)): result[p] = r.id
	for f in furniture:
		if CATALOG[f.kind].solid:
			for p in cells(rect_of(f)): result.erase(p)
	return result

func make_doors(rooms: Array, furniture: Array) -> Array:
	var floor_cells = floor_map(rooms,furniture)
	var doors = []
	for a in range(rooms.size()):
		for b in range(a+1,rooms.size()):
			var ra=rect_of(rooms[a]);var rb=rect_of(rooms[b]);var candidates=[]
			for p in cells(ra):
				if not floor_cells.has(p):continue
				for d in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
					var q=p+d
					if rb.has_point(q) and floor_cells.has(q):candidates.append([p,q])
			if not candidates.is_empty():
				var pair=candidates[int(candidates.size()/2)]
				doors.append({"a":[pair[0].x,pair[0].y],"b":[pair[1].x,pair[1].y]})
	return doors

func door_edges(doors: Array) -> Dictionary:
	var edges={}
	for d in doors:
		var a=Vector2i(int(d.a[0]),int(d.a[1]));var b=Vector2i(int(d.b[0]),int(d.b[1]))
		edges[str(a)+":"+str(b)]=true;edges[str(b)+":"+str(a)]=true
	return edges

func connected(rooms: Array, furniture: Array) -> bool:
	var floor_cells=floor_map(rooms,furniture)
	if floor_cells.is_empty():return false
	var doors=door_edges(make_doors(rooms,furniture))
	var queue=[floor_cells.keys()[0]];var visited={queue[0]:true};var n=0
	while n<queue.size():
		var p=queue[n];n+=1
		for d in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
			var q=p+d
			if not floor_cells.has(q) or visited.has(q):continue
			if floor_cells[p]!=floor_cells[q] and not doors.has(str(p)+":"+str(q)):continue
			visited[q]=true;queue.append(q)
	return visited.size()==floor_cells.size()

func validate_furniture(item: Dictionary, ignore_id: String="") -> String:
	var rect=rect_of(item)
	for p in cells(rect):
		if room_at(p)=="":return "请把家具完整放在房间地板上"
	for f in data.furniture:
		if f.id==ignore_id:continue
		if rect.intersects(rect_of(f)) and CATALOG[f.kind].solid and CATALOG[item.kind].solid:return "这里已经有家具了"
	var next=data.furniture.filter(func(f):return f.id!=ignore_id).duplicate(true)
	next.append(item)
	if not connected(data.rooms,next):return "这会堵住通道，请给伙伴留出至少一格路"
	return ""

func put_furniture(item: Dictionary, ignore_id: String="") -> bool:
	last_error=validate_furniture(item,ignore_id)
	if last_error!="":return false
	checkpoint()
	data.furniture=data.furniture.filter(func(f):return f.id!=ignore_id)
	data.furniture.append(item.duplicate(true));data.doors=make_doors(data.rooms,data.furniture)
	return save()

func remove_furniture(id: String) -> void:
	checkpoint();data.furniture=data.furniture.filter(func(f):return f.id!=id)
	data.doors=make_doors(data.rooms,data.furniture);save()

func validate_room(room: Dictionary, ignore_id: String="") -> String:
	var rect=rect_of(room)
	if rect.size.x<4 or rect.size.y<4:return "房间最小为 4 × 4 格"
	if rect.size.x>24 or rect.size.y>20:return "单个房间最大为 24 × 20 格"
	if absi(rect.position.x)>80 or absi(rect.position.y)>80:return "请在工作室附近扩建"
	for r in data.rooms:
		if r.id!=ignore_id and rect.intersects(rect_of(r)):return "房间不能重叠，请贴着现有房间边缘扩建"
	var next=data.rooms.filter(func(r):return r.id!=ignore_id).duplicate(true);next.append(room)
	for f in data.furniture:
		for p in cells(rect_of(f)):
			if room_at(p,next)=="":return "缩小房间前，请先移走边缘的家具"
	if not connected(next,data.furniture):return "请让房间边缘相邻，并留出可以连接门的通路"
	return ""

func put_room(room: Dictionary, ignore_id: String="") -> bool:
	last_error=validate_room(room,ignore_id)
	if last_error!="":return false
	checkpoint();data.rooms=data.rooms.filter(func(r):return r.id!=ignore_id);data.rooms.append(room.duplicate(true))
	data.doors=make_doors(data.rooms,data.furniture);return save()

func path_to(from: Vector2i,to: Vector2i) -> Array:
	var floor_cells=floor_map(data.rooms,data.furniture)
	if not floor_cells.has(from) or not floor_cells.has(to):return []
	var edges=door_edges(data.doors);var queue=[from];var previous={from:from};var n=0
	while n<queue.size():
		var p=queue[n];n+=1
		if p==to:break
		for d in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
			var q=p+d
			if not floor_cells.has(q) or previous.has(q):continue
			if floor_cells[p]!=floor_cells[q] and not edges.has(str(p)+":"+str(q)):continue
			previous[q]=p;queue.append(q)
	if not previous.has(to):return []
	var result=[];var cursor=to
	while cursor!=from:result.push_front(cursor);cursor=previous[cursor]
	return result

func desk_seat(desk:Dictionary) -> Vector2:
	var rect=rect_of(desk)
	var facing=posmod(int(desk.get("rot",0)),4)
	return Vector2(rect.position)+Vector2(rect.size)/2+Vector2(0,.9 if facing==2 else .7).rotated(facing*PI/2)

func workstation(profile_id:String) -> Dictionary:
	var floor_cells=floor_map(data.rooms,data.furniture)
	for desk in data.furniture:
		if desk.kind!="desk" or desk.get("owner","")!=profile_id:continue
		var rect=rect_of(desk);var facing=posmod(int(desk.get("rot",0)),4)
		var center=Vector2(rect.position)+Vector2(rect.size)/2
		# The desk stays solid. Walk to the chair side, then visually settle into the seat.
		for offset in [Vector2(-.5,1.5),Vector2(.5,1.5)]:
			var entry=Vector2i((center+offset.rotated(facing*PI/2)).floor())
			if floor_cells.has(entry):return {"id":desk.id,"approach":entry,"seat":desk_seat(desk),"facing":facing,"bottom":rect.end.y}
	return {}

func station(profile_id: String,index: int=0) -> Vector2i:
	var seat=workstation(profile_id)
	if not seat.is_empty():return seat.approach
	var floor_cells=floor_map(data.rooms,data.furniture)
	for f in data.furniture:
		if f.kind=="desk" and f.get("owner","")==profile_id:
			var rect=rect_of(f)
			for p in [Vector2i(rect.position.x,rect.end.y),Vector2i(rect.end.x,rect.position.y),rect.position+Vector2i.UP,rect.position+Vector2i.LEFT]:
				if floor_cells.has(p):return p
	var keys=floor_cells.keys()
	return keys[posmod(index*9+15,keys.size())] if not keys.is_empty() else Vector2i.ZERO

func new_id(prefix: String) -> String:
	return prefix+str(Time.get_ticks_usec())
