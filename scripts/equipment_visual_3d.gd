extends Node3D

@export var item_id := "attack_blades"


func _ready() -> void:
	var file := FileAccess.open("res://data/content.json", FileAccess.READ)
	if file == null: return
	var content: Dictionary = JSON.parse_string(file.get_as_text())
	if not content["items"].has(item_id): return
	var item: Dictionary = content["items"][item_id]
	var code: int = abs(item_id.hash())
	var color_value := Color.from_hsv(float(code % 360) / 360.0, 0.65, 0.88)
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.metallic = 0.68
	material.roughness = 0.3
	var stem := MeshInstance3D.new()
	stem.name = "Handle"
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.075
	handle_mesh.bottom_radius = 0.09
	handle_mesh.height = 1.0
	stem.mesh = handle_mesh
	stem.material_override = material
	stem.position.y = 0.65
	add_child(stem)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	var tier := 0 if item["source_section"] == "A" else 1 if item["source_section"] == "B" else 2
	match code % 4:
		0: head_mesh.size = Vector3(0.7, 0.18 + 0.06 * tier, 0.18)
		1: head_mesh.size = Vector3(0.18, 0.55 + 0.12 * tier, 0.18)
		2: head_mesh.size = Vector3(0.4, 0.4 + 0.06 * tier, 0.25)
		_: head_mesh.size = Vector3(0.25, 0.55 + 0.08 * tier, 0.3)
	head.mesh = head_mesh
	head.material_override = material
	head.position.y = 1.25
	add_child(head)
	if tier >= 1:
		var ring := MeshInstance3D.new()
		ring.name = "Core"
		var core := SphereMesh.new()
		core.radius = 0.15 + 0.04 * tier
		core.height = core.radius * 2
		ring.mesh = core
		ring.material_override = material
		ring.position.y = 1.25
		add_child(ring)
