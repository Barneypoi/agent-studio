extends Button
const Art=preload("res://pixel_art.gd")
const Model=preload("res://studio_model.gd")
var kind="plant"
func _ready() -> void:
	custom_minimum_size=Vector2(146,106)
	tooltip_text=Model.CATALOG[kind].desc
	accessibility_name=Model.CATALOG[kind].name
func _draw() -> void:
	var item=Model.CATALOG[kind];var scale_value=.7 if item.h>=3 else .95
	Art.furniture(self,kind,Vector2(size.x/2-float(item.w)*10*scale_value,25),scale_value)
	var font=get_theme_default_font();var ink=get_theme_color("font_color")
	for line in [[item.name,83,13],[str(item.w)+" × "+str(item.h),99,11]]:
		var width=font.get_string_size(line[0],HORIZONTAL_ALIGNMENT_LEFT,-1,line[2]).x
		draw_string(font,Vector2((size.x-width)/2,line[1]),line[0],HORIZONTAL_ALIGNMENT_LEFT,-1,line[2],ink)
