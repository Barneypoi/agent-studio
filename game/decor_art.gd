extends RefCounted
const KINDS=["piano","record","arcade","aquarium","easel","flowerbed","tea","lantern","display","screen","round_rug","stone_path","fountain"]

static func r(c:CanvasItem,p:Vector2,s:float,x:float,y:float,w:float,h:float,color) -> void:
	c.draw_rect(Rect2(p+Vector2(x,y)*s,Vector2(w,h)*s),Color(color) if color is String else color)

static func point(p:Vector2,s:float,rot:int,local:Vector2,height:float=0) -> Vector2:
	return p+(local.rotated(rot*PI/2).round()-Vector2(0,height))*s

static func plane(c:CanvasItem,p:Vector2,s:float,rot:int,rect:Rect2,height:float,color:String) -> void:
	var points=PackedVector2Array()
	for v in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:points.append(point(p,s,rot,v,height))
	c.draw_colored_polygon(points,Color(color))

static func block(c:CanvasItem,p:Vector2,s:float,rot:int,rect:Rect2,height:float,top:String,front:String) -> void:
	var a=point(p,s,rot,rect.position);var b=point(p,s,rot,rect.end)
	var left=minf(a.x,b.x);var right=maxf(a.x,b.x);var bottom=maxf(a.y,b.y)
	c.draw_rect(Rect2(left,bottom-height*s,right-left,height*s),Color(front))
	plane(c,p,s,rot,rect,height,top)

static func flower(c:CanvasItem,p:Vector2,s:float,color:String) -> void:
	r(c,p,s,-1,-2,2,13,"597b53");r(c,p,s,-5,3,4,2,"84a96c")
	r(c,p,s,-5,-7,10,5,color);r(c,p,s,-3,-9,6,9,color);r(c,p,s,-1,-6,3,3,"f7da86")

static func draw(c:CanvasItem,kind:String,p:Vector2,s:float=1,rot:int=0,phase:float=0) -> void:
	rot=posmod(rot,4)
	match kind:
		"round_rug":
			c.draw_circle(p,56*s,Color("b88077"));c.draw_circle(p,51*s,Color("e3ba96"));c.draw_circle(p,46*s,Color("687f87"))
			for i in range(12):
				var star=p+Vector2(cos(i*TAU/12),sin(i*TAU/12))*35*s
				r(c,star,s,-3,-1,6,2,"e9cda2");r(c,star,s,-1,-3,2,6,"e9cda2")
			c.draw_circle(p,17*s,Color("8ca29b"));c.draw_circle(p,11*s,Color("b9bf9c"))
		"stone_path":
			for i in range(4):
				var offset=Vector2(-19+(i%2)*37,-23+int(i/2)*39)
				var q=point(p,s,rot,offset)
				r(c,q,s,-15,-8,30,19,"6e8b76");r(c,q,s,-14,-10,28,18,"c6c6ad");r(c,q,s,-10,-12,20,3,"dbd6bc")
				r(c,q,s,-8,-6,2,3,"a8b69d");r(c,q,s,7,4,5,2,"a8b69d")
		"piano":
			block(c,p,s,rot,Rect2(-39,-16,78,29),34,"96705a","5a4b45")
			block(c,p,s,rot,Rect2(-39,11,78,8),15,"c6a078","765647")
			plane(c,p,s,rot,Rect2(-34,11,68,7),16,"efe6d0")
			for x in range(-31,32,5):plane(c,p,s,rot,Rect2(x,11,2,4),17,"394949")
			plane(c,p,s,rot,Rect2(-12,-6,24,9),35,"ecdbba")
			for x in [-8,1]:plane(c,p,s,rot,Rect2(x,-4,6,1),35,"b29b7d")
		"record":
			block(c,p,s,rot,Rect2(-39,-16,78,33),20,"bc8e64","89644c")
			plane(c,p,s,rot,Rect2(-34,-13,42,27),21,"d4ac7f")
			var disc=point(p,s,rot,Vector2(-13,0),23)
			c.draw_circle(disc,13*s,Color("34474b"));c.draw_circle(disc,9*s,Color("4d5e5d"));c.draw_circle(disc,4*s,Color("d1a273"))
			var groove=Vector2(cos(phase),sin(phase))*10*s;c.draw_line(disc+groove*.6,disc+groove,Color("82938a"),s)
			var arm=point(p,s,rot,Vector2(4,-10),24);c.draw_line(arm,disc+Vector2(6,4)*s,Color("dfccab"),2*s)
			block(c,p,s,rot,Rect2(17,-12,18,25),35,"667c77","3f5859")
			var speaker=point(p,s,rot,Vector2(26,11),22);c.draw_circle(speaker,5*s,Color("213f47"));c.draw_circle(speaker,2*s,Color("95afa0"))
		"arcade":
			block(c,p,s,rot,Rect2(-16,-14,32,30),19,"be7972","865467")
			var q=point(p,s,rot,Vector2(0,-2),18)
			r(c,q,s,-17,-38,34,38,"514b68");r(c,q,s,-15,-36,30,6,"d4a573");r(c,q,s,-13,-27,26,22,"8bb1a6");r(c,q,s,-11,-25,22,18,"284b56")
			for i in range(3):r(c,q,s,-7+i*6,-22,3,3,["d9b778","ca8c8b","97b9a4"][i])
			r(c,q,s,-7+round(sin(phase*2)*5),-10,9,2,"eed9a8");r(c,q,s,round(cos(phase*2.3)*7),-17,2,2,"b9d8c2")
			r(c,q,s,-17,0,34,7,"dba77e");r(c,q,s,-9,-3,3,5,"44545c");r(c,q,s,-11,-5,7,3,"c97b7c");r(c,q,s,6,1,4,3,"96b29a")
		"aquarium":
			block(c,p,s,rot,Rect2(-39,-17,78,34),10,"bda77e","827967")
			block(c,p,s,rot,Rect2(-36,-14,72,28),38,"afd8cb","659e9f")
			plane(c,p,s,rot,Rect2(-34,-12,68,24),39,"c0e0cb")
			for i in range(3):
				var q=point(p,s,rot,Vector2(-24+i*23+sin(phase*.7+i)*5,7),16+i*5)
				r(c,q,s,-4,-2,9,5,["ecc384","e6a48d","d5dcb1"][i]);r(c,q,s,-7,-3,3,6,"eee0ad");r(c,q,s,2,-1,1,1,"446972")
			for i in range(4):
				var bubble=point(p,s,rot,Vector2(-28+i*17,10),12+fmod(phase*5+i*6,22))
				c.draw_circle(bubble,1.3*s,Color("d5eddb"))
			for x in [-28,25]:
				var grass=point(p,s,rot,Vector2(x,12),10);r(c,grass,s,-1,-12,2,13,"b1cc9e");r(c,grass,s,-5,-8,4,2,"8fbb8c")
		"easel":
			r(c,p,s,-13,-8,4,23,"8b684f");r(c,p,s,9,-8,4,23,"8b684f");r(c,p,s,-2,-42,4,56,"9c7653")
			r(c,p,s,-17,-39,34,40,"be9570");r(c,p,s,-14,-36,28,33,"f5e5c8");r(c,p,s,-12,-34,24,18,"a7c3be")
			r(c,p,s,3,-30,6,6,"ecc78a");r(c,p,s,-12,-16,24,10,"a0b695");r(c,p,s,-8,-21,8,7,"6f9986")
			r(c,p,s,-19,0,38,4,"977553");r(c,p,s,14,-3,4,3,"c28279")
		"flowerbed":
			block(c,p,s,rot,Rect2(-38,-16,76,32),8,"cea17d","9c7458");plane(c,p,s,rot,Rect2(-34,-12,68,24),9,"807754")
			for i in range(6):
				var q=point(p,s,rot,Vector2(-27+(i%3)*25,-5+int(i/3)*14),14)
				flower(c,q,s,["d89091","e1b46c","c1abd1"][i%3])
		"tea":
			block(c,p,s,rot,Rect2(-37,-16,74,31),14,"dbb18a","9a785e")
			plane(c,p,s,rot,Rect2(-29,-12,58,23),15,"ded8b1")
			var pot=point(p,s,rot,Vector2(-12,0),15)
			r(c,pot,s,-8,-12,17,12,"779d90");r(c,pot,s,-6,-15,12,3,"abc2a4");r(c,pot,s,-1,-18,4,3,"779d90");r(c,pot,s,9,-9,5,3,"779d90");r(c,pot,s,-12,-9,4,6,"adc7b1")
			for offset in [Vector2(17,-5),Vector2(8,8)]:
				var cup=point(p,s,rot,offset,16);r(c,cup,s,-4,-5,8,6,"f3e4c3");r(c,cup,s,-3,-4,6,2,"bda774")
			var cake=point(p,s,rot,Vector2(27,7),16);r(c,cake,s,-5,-3,10,4,"d69b75");r(c,cake,s,-4,-5,8,3,"efd5a1")
		"lantern":
			c.draw_circle(p+Vector2(0,-31)*s,(20+sin(phase)*1.5)*s,Color(.99,.82,.44,.12))
			r(c,p,s,-10,12,20,4,"6b7466");r(c,p,s,-2,-18,4,31,"778572");r(c,p,s,-9,-40,18,23,"637768")
			r(c,p,s,-6,-37,12,16,"e9c87e");r(c,p,s,-4,-36,7,12,"ffedaf");r(c,p,s,-11,-42,22,4,"879780");r(c,p,s,-7,-46,14,4,"879780")
		"display":
			block(c,p,s,rot,Rect2(-39,-15,78,31),26,"cba77a","9d815f")
			var front=p+Vector2(0,16 if rot%2==0 else 39)*s
			for i in range(2 if rot%2==0 else 1):
				var x=-34+i*36 if rot%2==0 else -11
				r(c,front,s,x,-22,31 if rot%2==0 else 22,17,"786a55")
				for j in range(4):r(c,front,s,x+3+j*4,-18+j%2,3,11,["abc0a5","c59b7e","9aafba","d6bc91"][j])
			for i in range(3):
				var q=point(p,s,rot,Vector2(-25+i*24,0),27)
				if i==0:r(c,q,s,-8,-17,16,18,"7c7464");r(c,q,s,-6,-15,12,13,"d7c69e");r(c,q,s,-4,-8,8,6,"96aa91")
				elif i==1:r(c,q,s,-7,-10,14,12,"ca927c");r(c,q,s,-4,-16,8,7,"ca927c");r(c,q,s,-6,-7,12,3,"ead2a3")
				else:r(c,q,s,-7,-12,14,14,"809b9a");r(c,q,s,-4,-16,8,4,"b9c4a3");r(c,q,s,-3,-7,6,5,"e4c887")
		"screen":
			block(c,p,s,rot,Rect2(-38,-4,76,8),44,"d1b990","a98d6a")
			for x in [-36,-12,12,36]:
				var q=point(p,s,rot,Vector2(x,0));r(c,q,s,-2,-46,4,53,"967d60")
			for y in range(10,43,8):plane(c,p,s,rot,Rect2(-35,-4,70,2),y,"e1c9a0")
		"fountain":
			block(c,p,s,rot,Rect2(-36,-33,72,66),7,"acbdb3","7e9c95")
			plane(c,p,s,rot,Rect2(-30,-27,60,54),8,"71a6a5")
			for i in range(3):c.draw_arc(p+Vector2(0,-7)*s,(6+fmod(phase*4+i*7,20))*s,0,TAU,32,Color("b0d4c4"),s)
			block(c,p,s,rot,Rect2(-8,-8,16,16),30,"d0d8bd","a2b9ac")
			for i in [-1,1]:
				var points=PackedVector2Array()
				for j in range(9):points.append(p+Vector2(i*j*2,-34+float(j*j)*.43)*s)
				c.draw_polyline(points,Color("d0e6d0"),2*s)
				var t=fmod(phase*3,8);c.draw_circle(p+Vector2(i*t*2,-34+t*t*.43)*s,2*s,Color("eff1d5"))
