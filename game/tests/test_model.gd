extends SceneTree
const Model=preload("res://studio_model.gd")
var checks=0
var failures=0
func verify(condition:bool,description:String) -> void:
	if not condition:
		failures+=1
		push_error("FAIL: "+description);quit(1)
		assert(condition,description)
	checks+=1
func _initialize() -> void:
	var m=Model.new()
	var test_dir=OS.get_environment("AGENT_STUDIO_TEST_DIR")
	if test_dir=="":test_dir=ProjectSettings.globalize_path("res://").get_base_dir().path_join("../test-data")
	DirAccess.make_dir_recursive_absolute(test_dir)
	m.save_path=test_dir.path_join("layout.json");m.data=m.defaults()
	verify(m.connected(m.data.rooms,m.data.furniture),"initial floor is connected")
	verify(m.path_to(Vector2i(2,5),Vector2i(12,5)).size()>0,"agents can reach another station")
	var plant={"id":"test-plant","kind":"plant","x":7,"y":7,"rot":0,"owner":""}
	verify(m.put_furniture(plant),"place furniture in free area")
	verify(not m.put_furniture({"id":"collision","kind":"plant","x":2,"y":3,"rot":0,"owner":""}),"occupied desk rejects furniture")
	verify(m.data.furniture.size()==14,"rejected placement does not mutate save")
	var room={"id":"east","name":"研究室","x":16,"y":2,"w":7,"h":7,"floor":1}
	verify(m.put_room(room),"adjacent room can be added")
	verify(m.data.doors.size()==1,"adjacent room has connecting doorway")
	verify(m.path_to(Vector2i(12,5),Vector2i(20,5)).size()>0,"agents can cross doorway")
	verify(not m.put_room({"id":"island","name":"孤岛","x":30,"y":2,"w":5,"h":5,"floor":0}),"disconnected room rejected")
	var rotated={"id":"rotated","kind":"sofa","x":21,"y":4,"rot":1,"owner":""}
	verify(m.put_furniture(rotated),"rotated footprint fits inside room")
	verify(m.rect_of(rotated).size==Vector2i(1,3),"rotated sofa occupies 1 by 3 cells")
	var before=m.data.duplicate(true)
	var too_small=m.data.rooms[0].duplicate(true);too_small.w=5
	verify(not m.put_room(too_small,too_small.id),"resize cannot discard existing furniture")
	verify(m.data==before,"failed resize preserves complete state")
	m.data.profiles[0].name="测试伙伴";m.data.profiles[0].skills=["/example/skill/SKILL.md"]
	m.data.profiles[0].shirt=4;verify(m.save(),"atomic save succeeds")
	var restored=Model.new();restored.load_data(m.save_path)
	verify(restored.data.rooms.size()==2 and restored.data.furniture.size()==15,"layout restored")
	verify(restored.data.profiles[0].name=="测试伙伴" and restored.data.profiles[0].shirt==4,"appearance restored")
	verify(restored.data.profiles[0].skills==["/example/skill/SKILL.md"],"skill selection restored")
	m.undo();verify(not m.data.furniture.any(func(f):return f.id=="rotated"),"undo restores previous placement")
	# A one-cell corridor cannot be sealed by a new solid object.
	var narrow=Model.new();narrow.data={"rooms":[{"id":"hall","x":0,"y":0,"w":5,"h":1}],"furniture":[],"doors":[]};narrow.save_path=test_dir.path_join("narrow.json")
	verify(narrow.validate_furniture({"id":"block","kind":"plant","x":2,"y":0,"rot":0})!="","blocking a corridor rejected")
	# A furnished expansion is one operation, including save/reload and undo.
	for key in Model.Themes.PRESETS:
		var themed=Model.new();themed.data=themed.defaults();themed.save_path=test_dir.path_join(key+".json")
		var original=themed.data.duplicate(true);var preset=Model.Themes.PRESETS[key]
		var expansion={"id":"theme-room","name":preset.name,"x":16,"y":2,"w":preset.w,"h":preset.h,"floor":preset.floor,"template":key}
		verify(themed.put_room(expansion) and themed.connected(themed.data.rooms,themed.data.furniture) and themed.data.furniture.size()==original.furniture.size()+preset.items.size(),"place connected furnished "+key+" as one change")
		var stored_room=themed.data.rooms[-1].duplicate(true);stored_room.name="自定义房间"
		verify(not stored_room.has("template") and themed.put_room(stored_room,stored_room.id) and themed.data.furniture.size()==original.furniture.size()+preset.items.size(),"editing a themed room never re-adds its furniture")
		var saved=Model.new();saved.load_data(themed.save_path)
		verify(JSON.parse_string(JSON.stringify(saved.data))==JSON.parse_string(JSON.stringify(themed.data)),"themed furniture and floor survive reload")
		verify(themed.undo() and themed.undo() and themed.data==original,"undo room edit, then remove the entire expansion in one step")
		expansion.x=0;expansion.y=0
		verify(not themed.put_room(expansion) and themed.data==original and themed.undo_stack.is_empty(),"invalid themed placement cannot partially change a room")
	if failures==0:print("MODEL_CHECKS_OK ",checks)
	quit(1 if failures>0 else 0)
