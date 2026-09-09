extends SceneTree
const Model=preload("res://studio_model.gd")
const World=preload("res://world.gd")
var checks=0
func verify(ok:bool,description:String) -> void:
	if not ok:push_error("FAIL "+description);quit(1);assert(ok,description)
	checks+=1
func advance(world,frames:int) -> void:
	for i in range(frames):world._process(1.0/30)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var model=Model.new();model.data=model.defaults()
	var desk={"id":"work-desk","kind":"desk","x":4,"y":3,"rot":0,"owner":"lead"};model.data.furniture=[desk]
	var world=World.new();world.model=model;root.add_child(world);world.set_process(false);world.size=Vector2(900,700)
	world.update_characters([model.data.profiles[0]],{"lead":{"status":"working"}})
	var actor=world.actors.lead;actor.pos=Vector2(10,6);advance(world,1)
	verify(actor.seated==0 and actor.pos.distance_to(Vector2(10,6))<.1,"work begins by walking, without teleporting to the chair")
	var approaches=[Vector2i(4,5),Vector2i(3,3),Vector2i(5,2),Vector2i(6,4)]
	for rotation in range(4):
		desk.rot=rotation;world.layout_changed();actor.pos=Vector2(10,6);advance(world,300)
		var slot=model.workstation("lead");var floor_cells=model.floor_map(model.data.rooms,model.data.furniture)
		verify(slot.approach==approaches[rotation] and actor.seated==1 and actor.seat.facing==rotation and floor_cells.has(Vector2i(actor.pos)) and not floor_cells.has(Vector2i(slot.seat.floor())),"reach the correct chair side while the desk stays solid, rotation "+str(rotation))
	var clicked=[];world.selected.connect(func(kind,id):clicked.append([kind,id]))
	var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=world.origin+(world._person_position(actor)-Vector2(0,20))*world.zoom;world._gui_input(click)
	verify(clicked==[["profile","lead"]],"seated character remains clickable at its visible position")
	for state in ["approval","completed"]:
		world.states={"lead":{"status":state}};advance(world,30)
	verify(actor.seated==1,"waiting and completion retain the seated pose")
	world.states={};advance(world,30)
	verify(actor.seated==0,"ending the conversation releases the seat")
	desk.owner="";world.layout_changed();world.states={"lead":{"status":"working"}};advance(world,300)
	verify(actor.seated==0,"an unassigned agent never sits in someone else's chair")
	desk.owner="lead";desk.rot=0
	model.data.furniture.append({"id":"obstacle-a","kind":"plant","x":4,"y":5,"rot":0})
	verify(model.workstation("lead").approach==Vector2i(5,5),"use the other approach when one side is blocked")
	model.data.furniture.append({"id":"obstacle-b","kind":"plant","x":5,"y":5,"rot":0});world.layout_changed();advance(world,300)
	verify(model.workstation("lead").is_empty() and actor.seated==0,"blocked chair access does not allow walking through furniture")
	print("WORLD_CHECKS_OK ",checks);quit(0)
