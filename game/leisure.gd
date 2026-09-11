extends RefCounted
# Ambient activities use furniture geometry only; they never start Codex turns.
const TYPES={"books":{"action":"read","label":"看书","duration":16.0},"coffee":{"action":"coffee","label":"喝咖啡","duration":12.0},"plant":{"action":"water","label":"浇花","duration":10.0},"sofa":{"action":"rest","label":"休息","duration":20.0},"piano":{"action":"piano","label":"弹琴","duration":18.0},"record":{"action":"music","label":"听唱片","duration":16.0},"arcade":{"action":"play","label":"玩街机","duration":16.0},"easel":{"action":"paint","label":"画画","duration":18.0},"aquarium":{"action":"watch","label":"赏鱼","duration":12.0},"flowerbed":{"action":"water","label":"浇花","duration":10.0},"tea":{"action":"tea","label":"喝花茶","duration":12.0},"fountain":{"action":"watch","label":"听水放空","duration":14.0}}

static func slots(model) -> Array:
	var result=[]
	var floor_cells=model.floor_map(model.data.rooms,model.data.furniture)
	for f in model.data.furniture:
		if not TYPES.has(f.kind):continue
		var rect=model.rect_of(f);var center=Vector2(rect.position)+Vector2(rect.size)/2
		var rotation=posmod(int(f.get("rot",0)),4);var angle=rotation*PI/2
		var offsets=[-.75,.75] if f.kind=="sofa" else [0.0]
		for index in range(offsets.size()):
			var entries=[];var seat={}
			var width=rect.size.x if rotation%2==0 else rect.size.y
			var depth=rect.size.y if rotation%2==0 else rect.size.x
			var local_entries=[Vector2(-.5,depth/2.0+.5),Vector2(.5,depth/2.0+.5)] if width>1 else [Vector2(0,depth/2.0+.5)]
			if f.kind=="plant":local_entries=[Vector2.DOWN,Vector2.RIGHT,Vector2.LEFT,Vector2.UP]
			if f.kind=="sofa":local_entries=[Vector2(offsets[index],1)]
			for offset in local_entries:
				var entry=Vector2i((center+offset.rotated(angle)).floor())
				if floor_cells.has(entry) and not entries.has(entry):entries.append(entry)
			if entries.is_empty():continue
			var key=str(f.id)+":"+str(index)
			if f.kind=="sofa":
				var cushion=Vector2(offsets[index],0).rotated(angle)
				seat={"id":key,"kind":"sofa","seat":center+cushion+Vector2(0,.3),"facing":posmod(rotation+2,4),"bottom":rect.end.y,"depth_offset":cushion.y*.05}
			result.append({"key":key,"kind":f.kind,"action":TYPES[f.kind].action,"label":TYPES[f.kind].label,"duration":TYPES[f.kind].duration,"entries":entries,"seat":seat,"target":center})
	return result

static func choose(model,from:Vector2i,choices:Array,reserved:Dictionary,offset:int,last_kind:String) -> Dictionary:
	# Prefer a different pastime, but allow the only available facility to be reused.
	for repeat in [false,true]:
		for step in range(choices.size()):
			var candidate=choices[posmod(offset+step,choices.size())]
			if reserved.has(candidate.key) or (not repeat and candidate.kind==last_kind):continue
			var best={}
			for entry in candidate.entries:
				if reserved.has(entry):continue
				var path=model.path_to(from,entry)
				if from!=entry and path.is_empty():continue
				if best.is_empty() or path.size()<best.path.size():best={"approach":entry,"path":path}
			if best.is_empty():continue
			var activity=candidate.duplicate(true);activity.merge(best)
			activity.phase="going";activity.remaining=candidate.duration
			if not activity.seat.is_empty():activity.seat.approach=activity.approach
			return activity
	return {}
