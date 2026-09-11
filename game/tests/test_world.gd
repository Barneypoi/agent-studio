extends SceneTree
const Model=preload("res://studio_model.gd")
const World=preload("res://world.gd")
var checks=0
var failures=0
func verify(ok:bool,description:String) -> void:
	if not ok:push_error("FAIL "+description);failures+=1
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

	# Activities must be reached on foot and interrupted by real task state changes.
	for kind in ["books","coffee","plant","sofa","piano","record","arcade","aquarium","easel","flowerbed","tea","fountain"]:
		var facility={"id":"pastime","kind":kind,"x":8,"y":7,"rot":0}
		model.data.furniture=[desk,facility];world.states={};world.layout_changed();actor.pos=Vector2(2,7)
		advance(world,1)
		verify(actor.activity.get("phase","")=="going" and actor.pos.distance_to(Vector2(2,7))<.1,"walk to "+kind+" without teleporting")
		for frame in range(600):
			advance(world,1)
			if actor.activity.get("phase","")=="using":break
		advance(world,15)
		verify(actor.activity.get("phase","")=="using" and actor.activity.kind==kind and model.floor_map(model.data.rooms,model.data.furniture).has(Vector2i(actor.pos)),"use reachable "+kind+" from walkable ground")
		world.states={"lead":{"status":"working"}};advance(world,1)
		verify(actor.activity.is_empty(),"a task immediately cancels "+kind)
		advance(world,400)
		verify(actor.seated==1 and actor.seat.id==desk.id,"return from "+kind+" to assigned work chair")

	# Two sofa places can be reserved; a third actor must not overlap either sitter.
	var sofa={"id":"shared-sofa","kind":"sofa","x":7,"y":6,"rot":0}
	for rotation in range(4):
		sofa.rot=rotation;model.data.furniture=[sofa];world.update_characters(model.data.profiles,{})
		world.layout_changed()
		for i in range(model.data.profiles.size()):world.actors[model.data.profiles[i].id].pos=Vector2(2+i,6)
		advance(world,330)
		var lead=world.actors.lead;var research=world.actors.research
		verify(lead.seated==1 and research.seated==1 and lead.activity.key!=research.activity.key and lead.activity.approach!=research.activity.approach and world.actors.review.activity.is_empty(),"reserve distinct sofa places, rotation "+str(rotation))
		verify(lead.seat.facing==posmod(rotation+2,4),"sofa occupant faces the open side, rotation "+str(rotation))
		world.update_characters([model.data.profiles[0],model.data.profiles[2]],{})
		world.actors.review.path=[];world.actors.review.timer=0;advance(world,1)
		# A local chat may finish before the newly vacant facility is selected.
		for frame in range(240):
			if not world.actors.review.activity.is_empty():break
			advance(world,1)
		verify(not world.actors.review.activity.is_empty(),"removing an actor frees its facility reservation")
		world.update_characters([model.data.profiles[0]],{})

	# Expiry and changes to the room must release occupancy, not retain ghost seats.
	actor=world.actors.lead;actor.activity.remaining=.01;advance(world,1)
	verify(actor.activity.is_empty(),"rest ends after its duration")
	advance(world,240)
	verify(not actor.activity.is_empty(),"an idle actor can start another activity")
	model.data.furniture=[];world.layout_changed()
	verify(actor.activity.is_empty() and actor.seated==0 and actor.path.is_empty(),"removing furniture cancels its activity and seat")
	advance(world,300)
	verify(actor.activity.is_empty() and model.floor_map(model.data.rooms,model.data.furniture).has(Vector2i(actor.pos.round())),"a room without leisure facilities still supports wandering")

	model.data.rooms.append({"id":"isolated","name":"Isolated","x":20,"y":0,"w":6,"h":6,"floor":0})
	model.data.furniture=[{"id":"unreachable","kind":"books","x":22,"y":1,"rot":0}]
	world.layout_changed();actor.pos=Vector2(2,6);advance(world,300)
	verify(actor.activity.is_empty() and actor.pos.x<16,"skip facilities in a room without a connecting door")
	print("WORLD_CHECKS_OK " if failures==0 else "WORLD_CHECKS_FAILED ",checks);quit(0 if failures==0 else 1)
