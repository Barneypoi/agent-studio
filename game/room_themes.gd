extends RefCounted

const FLOORS=[
	{"name":"蜂蜜木地板","colors":["d0b08a","d8b993","c7a37f"],"wall":"ead8b4","trim":"fff0ce","pattern":"wood"},
	{"name":"鼠尾草地板","colors":["9bac9f","a4b4a6","90a394"],"wall":"ead8b4","trim":"fff0ce","pattern":"wood"},
	{"name":"浅胡桃地板","colors":["c2ad9c","cdb9a7","b9a28f"],"wall":"ead8b4","trim":"fff0ce","pattern":"wood"},
	{"name":"庭院草地","colors":["87a984","8eaf87","82a27e"],"wall":"c8ddca","trim":"eef3d4","pattern":"garden"},
	{"name":"暮蓝地砖","colors":["6b878e","728f96","66818a"],"wall":"879eaa","trim":"c9d4d1","pattern":"tile"},
	{"name":"樱桃木地板","colors":["bb8c79","c69983","b58777"],"wall":"dfc4b7","trim":"f8dfc4","pattern":"wood"}
]
const PRESETS={
	"reading":{"name":"午后书房","desc":"书香、茶点和一处柔软的靠窗座位。","w":8,"h":7,"floor":5,"items":[["round_rug",1,3],["books",1,0],["books",4,0],["lamp",0,0],["sofa",1,4],["tea",5,4],["aquarium",5,2],["display",1,6]]},
	"music":{"name":"音乐游艺室","desc":"唱片、钢琴与街机，给工作留一点玩心。","w":8,"h":7,"floor":4,"items":[["round_rug",3,2],["piano",1,0],["record",4,0],["arcade",6,1],["easel",1,3],["sofa",3,4],["lantern",0,0],["display",5,6],["plant",7,4]]},
	"garden":{"name":"玻璃花园","desc":"沿石径听水声，照料花圃，喝一杯热茶。","w":8,"h":7,"floor":3,"items":[["stone_path",3,0],["stone_path",3,4],["flowerbed",1,1],["flowerbed",5,1],["fountain",3,2],["tea",5,4],["plant",1,4],["aquarium",1,5],["lantern",0,6],["screen",1,0]]}
}

static func furniture(room:Dictionary) -> Array:
	var preset=PRESETS.get(room.get("template",""),{})
	var result=[]
	for item in preset.get("items",[]):
		result.append({"id":str(room.id)+"-decor-"+str(result.size()),"kind":item[0],"x":int(room.x)+item[1],"y":int(room.y)+item[2],"rot":0,"owner":""})
	return result
