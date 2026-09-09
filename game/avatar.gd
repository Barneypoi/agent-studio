extends Control
const Art=preload("res://pixel_art.gd")
var profile={}
var pixel_scale=3.0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	if profile.is_empty():return
	Art.person(self,profile,Vector2(size.x/2,size.y/2+43),pixel_scale)
