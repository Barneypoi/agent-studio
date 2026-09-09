extends RefCounted
const Model = preload("res://studio_model.gd")

static func r(c:CanvasItem,p:Vector2,s:float,x:float,y:float,w:float,h:float,col) -> void:
	c.draw_rect(Rect2(p+Vector2(x,y)*s,Vector2(w,h)*s),Color(col) if col is String else col)

static func side_rect(c:CanvasItem,p:Vector2,s:float,facing:int,x:float,y:float,w:float,h:float,col) -> void:
	r(c,p,s,24-x-w if facing==3 else x,y,w,h,col)

static func person(c:CanvasItem,p:Dictionary,pos:Vector2,s:float=1.0,phase:float=0.0,state:String="idle",moving:bool=false,seated:bool=false,facing:int=2,part:String="all") -> void:
	var shirt=Color(Model.SHIRTS[posmod(int(p.get("shirt",0)),Model.SHIRTS.size())])
	var hair=Color(Model.HAIRS[posmod(int(p.get("hair_color",0)),Model.HAIRS.size())])
	var skin=Color(Model.SKINS[posmod(int(p.get("skin",0)),Model.SKINS.size())])
	var bob=round(sin(phase*9.0)) if moving else 0.0
	var origin=pos+Vector2(-12,(-28 if seated else -32)+bob)*s
	if part!="upper":r(c,pos,s,-10,-2,20,4,Color(0.12,0.19,0.20,0.23))
	var stride=round(sin(phase*9.0)*2) if moving else 0.0
	if seated:
		if facing in [1,3]:
			# Thigh across the cushion, bent knee in front, lower leg hanging down.
			if part!="upper":
				side_rect(c,origin,s,facing,8,22,14,4,"3b4756")
				side_rect(c,origin,s,facing,19,25,4,5,"3b4756")
				side_rect(c,origin,s,facing,19,29,7,2,"303948")
			if part=="lower":return
			side_rect(c,origin,s,facing,6,15,11,8,shirt.darkened(.22));side_rect(c,origin,s,facing,7,15,9,7,shirt)
		else:
			r(c,origin,s,5,22,6,4,"3b4756");r(c,origin,s,14,22,6,4,"3b4756")
			r(c,origin,s,6,25,4,4,"3b4756");r(c,origin,s,15,25,4,4,"3b4756")
			r(c,origin,s,4,29,7,2,"303948");r(c,origin,s,14,29,7,2,"303948")
			r(c,origin,s,5,15,15,8,shirt.darkened(.22));r(c,origin,s,6,15,12,7,shirt)
	else:
		r(c,origin,s,6,25,5,6+stride,"3b4756");r(c,origin,s,14,25,5,6-stride,"3b4756")
		r(c,origin,s,5,30+stride,6,2,"303948");r(c,origin,s,14,30-stride,6,2,"303948")
		r(c,origin,s,5,15,15,12,shirt.darkened(.22));r(c,origin,s,6,15,12,11,shirt)
	r(c,origin,s,9,15,5,2,"f4dec1");r(c,origin,s,9,17,5,2,shirt.lightened(.2))
	if seated:
		var typing=state in ["starting","running","working"]
		var tap=1.0 if typing and sin(phase*12)>0 else 0.0
		if facing==0:
			r(c,origin,s,2,12,4,9,shirt.darkened(.12));r(c,origin,s,19,12,4,9,shirt.darkened(.12))
			r(c,origin,s,2,8+tap,3,5,skin);r(c,origin,s,20,9-tap,3,5,skin)
		elif facing in [1,3]:
			side_rect(c,origin,s,facing,13,16,5,4,shirt.darkened(.12))
			side_rect(c,origin,s,facing,16,13,4,5,shirt)
			side_rect(c,origin,s,facing,19,12+tap,4,3,skin)
		else:
			r(c,origin,s,2,18,4,5,shirt.darkened(.12));r(c,origin,s,19,18,4,5,shirt.darkened(.12))
			r(c,origin,s,3,22+tap,3,3,skin);r(c,origin,s,19,23-tap,3,3,skin)
	else:
		r(c,origin,s,3,17,3,8,shirt.darkened(.12));r(c,origin,s,19,17,3,8,shirt.darkened(.12))
		r(c,origin,s,3,24,3,3,skin);r(c,origin,s,19,24,3,3,skin)
	r(c,origin,s,7,3,11,13,skin.darkened(.08));r(c,origin,s,6,5,14,8,skin)
	r(c,origin,s,7,4,11,9,skin.lightened(.06));r(c,origin,s,8,12,8,3,skin)
	r(c,origin,s,10,13,3,1,"bb7d6c")
	r(c,origin,s,8,8,2,2,"403c43");r(c,origin,s,15,8,2,2,"403c43")
	r(c,origin,s,7,11,2,1,"de9d8d");r(c,origin,s,16,11,2,1,"de9d8d")
	var style=int(p.get("hair",0))
	r(c,origin,s,7,0,11,3,hair);r(c,origin,s,5,2,15,4,hair);r(c,origin,s,5,5,3,5,hair)
	r(c,origin,s,17,4,3,5,hair);r(c,origin,s,8,3,6,3,hair.lightened(.12))
	if style==1:
		r(c,origin,s,13,-2,5,3,hair);r(c,origin,s,4,4,3,3,hair);r(c,origin,s,10,4,4,3,hair)
	elif style==2:
		r(c,origin,s,3,5,3,11,hair);r(c,origin,s,19,5,3,11,hair);r(c,origin,s,20,8,2,9,hair.darkened(.15))
	elif style==3:
		r(c,origin,s,3,1,5,4,hair);r(c,origin,s,19,1,4,4,hair);r(c,origin,s,18,4,4,12,hair)
	if seated and facing==0:
		r(c,origin,s,5,4,15,10,hair);r(c,origin,s,7,4,11,3,hair.lightened(.08))
		r(c,origin,s,8,13,9,2,hair.darkened(.1));r(c,origin,s,10,15,5,2,skin)
	elif seated and facing in [1,3]:
		r(c,origin,s,5 if facing==1 else 13,4,7,10,hair)
		r(c,origin,s,19 if facing==1 else 4,9,2,3,skin)
	var accessory=int(p.get("accessory",0))
	if accessory==1:
		if seated and facing==0:
			r(c,origin,s,4,8,2,2,"526075");r(c,origin,s,20,8,2,2,"526075")
		elif seated and facing in [1,3]:
			var lens=14 if facing==1 else 6;r(c,origin,s,lens,8,5,3,"526075");r(c,origin,s,lens+1,9,3,1,"bad7d2")
		else:
			r(c,origin,s,7,8,5,3,"526075");r(c,origin,s,14,8,5,3,"526075");r(c,origin,s,8,9,3,1,"bad7d2");r(c,origin,s,15,9,3,1,"bad7d2");r(c,origin,s,12,8,2,1,"526075")
	elif accessory==2:
		r(c,origin,s,4,6,2,6,"dfaa65");r(c,origin,s,20,6,2,6,"dfaa65");r(c,origin,s,18,12,4,1,"4c4c5a")
	elif accessory==3:
		r(c,origin,s,8,15,9,3,"bf6970");r(c,origin,s,14,18,3,6,"bf6970")
	if not seated and state in ["approval","waiting"]:
		r(c,origin,s,20,14,3,10,shirt);r(c,origin,s,20,10,3,4,skin)

static func chair(c:CanvasItem,pos:Vector2,facing:int=0,foreground:bool=false) -> void:
	facing=posmod(facing,4)
	if foreground:
		if facing==0:
			r(c,pos,1,-14,-11,28,10,"668e87");r(c,pos,1,-16,-14,32,8,"85b0a0");r(c,pos,1,-13,-13,26,2,"aed0b4")
		return
	r(c,pos,1,-16,5,32,5,Color(.12,.19,.20,.18));r(c,pos,1,-2,-1,4,9,"62594e")
	r(c,pos,1,-13,6,26,3,"62594e");r(c,pos,1,-15,8,5,3,"3d4949");r(c,pos,1,10,8,5,3,"3d4949")
	r(c,pos,1,-13,-9,26,7,"668e87");r(c,pos,1,-12,-11,24,5,"85b0a0")
	if facing==2:
		r(c,pos,1,-16,-34,32,22,"668e87");r(c,pos,1,-14,-33,28,15,"85b0a0")
	elif facing in [1,3]:
		var x=-16 if facing==1 else 11
		r(c,pos,1,x,-32,6,25,"668e87");r(c,pos,1,x,-32,4,20,"85b0a0")

static func desk_plane(c:CanvasItem,center:Vector2,facing:int,rect:Rect2,height:float,color:String) -> void:
	var points=PackedVector2Array()
	for point in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:
		points.append(center+point.rotated(facing*PI/2).round()-Vector2(0,height))
	c.draw_colored_polygon(points,Color(color))

static func desk(c:CanvasItem,center:Vector2,facing:int,foreground:bool=false) -> void:
	facing=posmod(facing,4)
	# Rotate the floor plan, keeping every vertical part upright in the room's camera.
	if not foreground:
		for leg in [Vector2(-34,-25),Vector2(34,-25),Vector2(-34,18),Vector2(34,18)]:
			var base=center+leg.rotated(facing*PI/2).round()
			r(c,base,1,-3,-26,6,28,"735447");r(c,base,1,-2,-24,2,24,"a37852")
	if foreground!=(facing!=0):return
	desk_plane(c,center,facing,Rect2(-40,-32,80,56),20,"805848")
	desk_plane(c,center,facing,Rect2(-40,-32,80,56),26,"ce9d68")
	desk_plane(c,center,facing,Rect2(-38,-30,76,2),26,"e1b982")
	desk_plane(c,center,facing,Rect2(-18,14,36,8),26,"e6d3b4")
	for x in range(-15,16,5):
		for y in [15,18]:desk_plane(c,center,facing,Rect2(x,y,3,2),26,"b9b9a5")
	var cup=center+Vector2(29,7).rotated(facing*PI/2).round()-Vector2(0,26)
	r(c,cup,1,-4,-8,8,8,"f3e6cc");r(c,cup,1,4,-6,3,5,"d6b98f");r(c,cup,1,-2,-7,4,2,"b88862")
	var monitor=center+Vector2(0,-17).rotated(facing*PI/2).round()-Vector2(0,26)
	desk_plane(c,center,facing,Rect2(-7,-20,14,6),26,"465356")
	r(c,monitor,1,-2,-7,4,8,"465356")
	if facing in [0,2]:
		r(c,monitor,1,-23,-34,46,28,"374c51")
		if facing==0:
			r(c,monitor,1,-20,-32,40,22,"7ea9a1")
			r(c,monitor,1,-16,-28,30,2,"c0d9c3");r(c,monitor,1,-16,-22,15,2,"d9e9cb");r(c,monitor,1,-16,-16,24,2,"bfd4a9")
		else:
			r(c,monitor,1,-21,-32,42,23,"4f6564");r(c,monitor,1,-3,-23,6,5,"8aa397")
	else:
		var flip=1 if facing==1 else -1
		var frame=PackedVector2Array();var screen=PackedVector2Array()
		for point in [Vector2(-8,-34),Vector2(8,-29),Vector2(8,-4),Vector2(-8,-9)]:frame.append(monitor+Vector2(point.x*flip,point.y))
		for point in [Vector2(-5,-30),Vector2(5,-27),Vector2(5,-8),Vector2(-5,-11)]:screen.append(monitor+Vector2(point.x*flip,point.y))
		c.draw_colored_polygon(frame,Color("374c51"));c.draw_colored_polygon(screen,Color("7ea9a1"))
		for y in [-25,-20,-15]:c.draw_line(monitor+Vector2(-3*flip,y),monitor+Vector2(3*flip,y+2),Color("c0d9c3"),1)

static func furniture(c:CanvasItem,kind:String,pos:Vector2,s:float=1.0,include_chair:bool=true) -> void:
	var f=Model.CATALOG[kind];var w=float(f.w)*20;var h=float(f.h)*20
	if kind=="rug":
		r(c,pos,s,0,0,w,h,"c18770");r(c,pos,s,2,2,w-4,h-4,"e0b799");r(c,pos,s,5,5,w-10,h-10,"a4b6a0")
		for x in range(7,int(w)-6,6):r(c,pos,s,x,8,2,h-16,"cdd1b0")
		return
	r(c,pos,s,2,h-4,w,5,Color(0.17,.22,.2,.18))
	match kind:
		"desk":
			r(c,pos,s,3,12,4,25,"735447");r(c,pos,s,33,12,4,25,"735447")
			r(c,pos,s,0,5,40,20,"805848");r(c,pos,s,0,3,40,19,"ce9d68");r(c,pos,s,2,4,36,2,"e1b982")
			r(c,pos,s,6,0,23,15,"374c51");r(c,pos,s,8,1,19,11,"7ea9a1");r(c,pos,s,10,3,15,1,"c0d9c3")
			r(c,pos,s,10,6,7,1,"d9e9cb");r(c,pos,s,10,8,12,1,"bfd4a9");r(c,pos,s,16,15,4,3,"465356")
			r(c,pos,s,10,18,17,4,"e6d3b4");r(c,pos,s,31,14,4,5,"f3e6cc");r(c,pos,s,35,15,2,3,"d6b98f")
			if include_chair:
				r(c,pos,s,13,30,14,8,"668e87");r(c,pos,s,12,28,16,6,"85b0a0");r(c,pos,s,14,37,2,3,"62594e");r(c,pos,s,24,37,2,3,"62594e")
		"books":
			r(c,pos,s,0,-15,40,32,"805e4b");r(c,pos,s,2,-13,36,28,"b3865d")
			for row in [-11,1]:
				for i in range(8):r(c,pos,s,4+i*4,row,3,9,["779d91","bc7c67","d5b982","7b8caa","a694ab"][i%5])
				r(c,pos,s,2,row+9,36,2,"e1bd86")
			r(c,pos,s,0,15,40,3,"614e42")
		"plant":
			r(c,pos,s,4,8,13,9,"b97557");r(c,pos,s,3,6,15,3,"dcac79");r(c,pos,s,6,16,9,2,"98614f")
			r(c,pos,s,9,-7,2,13,"547b58")
			for v in [Vector2(1,-10),Vector2(10,-14),Vector2(12,-5),Vector2(0,-2),Vector2(7,-8)]:
				r(c,pos,s,v.x,v.y,8,6,"5d9170");r(c,pos,s,v.x+1,v.y+1,5,2,"8cad75")
		"sofa":
			r(c,pos,s,2,-6,56,24,"597d78");r(c,pos,s,4,-5,52,13,"80a59b");r(c,pos,s,5,7,50,10,"70938a")
			r(c,pos,s,0,0,6,18,"9bb9a6");r(c,pos,s,54,0,6,18,"9bb9a6");r(c,pos,s,29,-4,2,19,"567d76")
			r(c,pos,s,9,0,9,7,"e0c292");r(c,pos,s,42,1,8,6,"d5a58f")
		"board":
			r(c,pos,s,4,-20,33,33,"9e7854");r(c,pos,s,6,-18,29,27,"e6e0ba");r(c,pos,s,7,-17,27,25,"eceacf")
			r(c,pos,s,9,-13,8,6,"d6a17c");r(c,pos,s,21,-12,9,7,"93b4a7");r(c,pos,s,12,-2,13,1,"9aaf9d")
			r(c,pos,s,9,11,3,8,"8d7257");r(c,pos,s,29,11,3,8,"8d7257")
		"coffee":
			r(c,pos,s,0,1,40,17,"a1785c");r(c,pos,s,0,-1,40,5,"e5c899");r(c,pos,s,2,5,17,10,"bd9973");r(c,pos,s,21,5,17,10,"bd9973")
			r(c,pos,s,4,-14,15,13,"4b5b57");r(c,pos,s,6,-12,11,5,"768e82");r(c,pos,s,8,-5,6,3,"eee4cb")
			r(c,pos,s,27,-5,6,5,"f0d9ae");r(c,pos,s,32,-4,3,2,"d5ad80")
		"lamp":
			r(c,pos,s,5,15,11,3,"66685c");r(c,pos,s,9,-13,2,28,"8d8666");r(c,pos,s,3,-13,15,9,"e5be72");r(c,pos,s,5,-17,11,5,"f1d797");r(c,pos,s,4,-12,13,2,"ffebae")
		"cabinet":
			r(c,pos,s,0,-5,40,22,"6b7e74");r(c,pos,s,1,-7,38,3,"9aae91")
			for i in range(2):
				r(c,pos,s,3+i*19,-2,15,15,"94a391");r(c,pos,s,9+i*19,2,5,2,"e4c793")
