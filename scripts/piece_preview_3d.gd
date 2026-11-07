extends Node3D

const Piece = preload("res://scripts/piece_visual_3d.gd")

@export var piece_id := "Axe"
@export_range(1, 3) var star := 1
@export var monster := false
var piece_visual: Node3D


func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(3, 3.2, 5)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0, 1.1, 0))
	var base := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.25
	mesh.bottom_radius = 1.35
	mesh.height = 0.14
	base.mesh = mesh
	base.position.y = -0.08
	add_child(base)
	set_piece(piece_id, star, monster)


func set_piece(new_id: String, new_star: int, is_monster: bool = false) -> void:
	if piece_visual != null: piece_visual.free()
	piece_id = new_id
	star = new_star
	monster = is_monster
	var piece = Piece.new()
	piece.piece_id = piece_id
	piece.star = star
	piece.monster = monster
	add_child(piece)
	piece_visual = piece
