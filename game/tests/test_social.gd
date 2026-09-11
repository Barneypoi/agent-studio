extends SceneTree
const Model=preload("res://studio_model.gd")
const World=preload("res://world.gd")
const Social=preload("res://social_life.gd")
var checks=0
var failures=0
var world
var model
func verify(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL "+message)
func advance(seconds:float) -> void:
	for frame in range(int(seconds*30)):world._process(1.0/30)
func reset() -> void:
	model.data=model.defaults();model.data.furniture=[]
	world.social=Social.new();world.actors.clear();world.update_characters(model.data.profiles,{})
	for i in range(model.data.profiles.size()):
		var actor=world.actors[model.data.profiles[i].id];actor.pos=Vector2(3+i*3,5);actor.timer=100
func _initialize() -> void:call_deferred("run")
func run() -> void:
	model=Model.new();model.data=model.defaults()
	world=World.new();world.model=model;root.add_child(world);world.set_process(false);world.size=Vector2(900,700)
	reset()
	verify(world.social.start_pair(world,"lead","research"),"idle neighbors can arrange a reachable meeting")
	var initial=world.actors.lead.pos;advance(.1)
	verify(world.actors.lead.pos.distance_to(initial)>0 and world.actors.lead.pos.distance_to(initial)<.3,"meeting begins by walking without teleporting")
	advance(1.1)
	verify(world.social.pairs.lead.phase=="chat" and world.actors.lead.pos.distance_to(world.actors.research.pos)<1.01,"conversation starts only after reaching the neighbor")
	verify(world.social.presentation(world,"lead").caption!="" and world.social.presentation(world,"research").caption=="","only the first speaker shows a bubble")
	advance(3)
	verify(world.social.presentation(world,"lead").caption=="" and world.social.presentation(world,"research").caption!="","the reply follows in the other character's bubble")
	advance(4)
	verify(world.social.pairs.is_empty() and world.social.members.is_empty() and world.social.reserved_cells().is_empty(),"a finished conversation releases both actors and its meeting place")
	for worker in ["lead","research"]:
		reset();model.data.furniture=[{"id":"desk","kind":"desk","x":8,"y":2,"rot":0,"owner":worker}];world.layout_changed()
		world.social.start_pair(world,"lead","research");world.states[worker]={"status":"working"};advance(.1)
		verify(world.social.pairs.is_empty() and world.social.members.is_empty() and world.actors[worker].activity.is_empty(),"work immediately interrupts either participant: "+worker)
		advance(6)
		verify(world.actors[worker].seated==1 and world.actors[worker].seat.id=="desk","interrupted participant reaches the assigned work chair: "+worker)
	reset();model.data.furniture=[{"id":"coffee","kind":"coffee","x":5,"y":2,"rot":0}];world.layout_changed()
	var buddy=world.actors.research;world._choose_activity("research",0,buddy)
	buddy.pos=Vector2(buddy.activity.approach);buddy.path=[];buddy.activity.phase="using"
	world.actors.lead.pos=buddy.pos+Vector2(-3,0);world.actors.review.pos=Vector2(12,8)
	var claim=buddy.activity.key;var remaining=buddy.activity.remaining
	verify(world.social.start_pair(world,"lead","research") and world.social.pairs.lead.style=="snack","a coffee break offers a contextual snack exchange")
	advance(2)
	verify(buddy.activity.key==claim and buddy.activity.remaining==remaining,"conversation preserves a partner's facility reservation")
	world.states.lead={"status":"approval"};advance(.1)
	verify(world.social.pairs.is_empty() and buddy.activity.key==claim and buddy.activity.remaining<remaining,"the idle buddy resumes its facility when the other participant needs approval")
	reset();world.social.start_pair(world,"lead","research");world.update_characters([model.data.profiles[0],model.data.profiles[2]],{})
	verify(world.social.members.is_empty() and world.social.reserved_cells().is_empty(),"removing a delegated character releases its partner immediately")
	advance(.1)
	reset();world.social.start_pair(world,"lead","research");world.social.gesture("review","stretch","",true);world.layout_changed()
	verify(world.social.members.is_empty() and world.social.effects.is_empty() and world.actors.lead.path.is_empty(),"editing the layout clears social routes and gestures")
	reset();model.data.rooms.append({"id":"other","x":16,"y":0,"w":4,"h":10});world.actors.lead.pos=Vector2(14,5);world.actors.research.pos=Vector2(16,5)
	verify(not world.social.start_pair(world,"lead","research"),"nearby actors in separate rooms cannot chat through walls")
	model.data.rooms=[{"id":"corridor","x":0,"y":0,"w":12,"h":1}];world.actors.lead.pos=Vector2(3,0);world.actors.research.pos=Vector2(6,0)
	verify(not world.social.start_pair(world,"lead","research"),"meetings do not occupy a narrow passage")
	reset();world.states={"lead":{"status":"completed"},"research":{"status":"working"}}
	world.actors.review.path=[Vector2i(10,5)];var state_before=world.states.duplicate(true);var path_before=world.actors.review.path.duplicate()
	verify(world.social.greet(world)==1 and world.social.effects.has("review") and not world.social.controls("review") and world.states==state_before and world.actors.review.path==path_before,"greetings only animate idle actors without interrupting movement or changing task states")
	reset();world.states={"lead":{"status":"completed"}};advance(.1)
	verify(world.social.effects.is_empty(),"restoring an old completed task never replays a celebration")
	world.states.lead.status="working";advance(.1);world.states.lead.status="completed";advance(.1)
	verify(world.social.effects.size()==1 and world.social.effects.values()[0].caption=="辛苦啦！","an idle neighbor acknowledges a newly completed task")
	advance(4)
	verify(world.social.effects.is_empty(),"the celebration expires without repeating for a completed task")
	reset();var observed_pair=false;var observed_gesture=false
	for frame in range(1800):
		world._process(1.0/30);observed_pair=observed_pair or not world.social.pairs.is_empty();observed_gesture=observed_gesture or not world.social.effects.is_empty()
	verify(observed_pair and observed_gesture and world.states.is_empty(),"local time alone drives social meetings and gestures, without a task")
	print("SOCIAL_CHECKS_OK " if failures==0 else "SOCIAL_CHECKS_FAILED ",checks);quit(0 if failures==0 else 1)
