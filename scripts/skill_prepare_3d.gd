extends Node3D
var lifetime := .5
var art: Node3D
func configure(skill: String,color: Color,duration: float,width: float,star: int) -> void:
	lifetime=maxf(.05,duration)
	art=preload("res://scripts/advanced_skill_art.gd").new()
	add_child(art)
	art.build(skill,color,{"radius":.20,"line_length":.30,"distance":.30,"star":star},"prepare",false)
	scale=Vector3.ONE*clampf(width*.65,.10,.40)
func sample(age: float) -> void:
	var progress=clampf(age/lifetime,0,1)
	art.sample(age,.15+.65*progress)
