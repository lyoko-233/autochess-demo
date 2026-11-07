extends Node3D

@export_range(0, 2) var appearance := 0


func _mesh(name_value: String, primitive: Mesh, offset: Vector3, color_value: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = name_value
	part.mesh = primitive
	part.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	part.material_override = material
	add_child(part)


func _ready() -> void:
	match appearance:
		0:
			_mesh("FoxBody", SphereMesh.new(), Vector3(0, 0.55, 0), Color(0.75, 0.38, 0.18))
			_mesh("ScrollPack", BoxMesh.new(), Vector3(0, 0.65, 0.4), Color(0.53, 0.36, 0.2))
			_mesh("FoxEars", BoxMesh.new(), Vector3(0, 1.18, 0), Color(0.88, 0.53, 0.22))
		1:
			_mesh("GolemBody", BoxMesh.new(), Vector3(0, 0.55, 0), Color(0.44, 0.49, 0.43))
			_mesh("MossTop", BoxMesh.new(), Vector3(0, 1.12, 0), Color(0.26, 0.45, 0.29))
		2:
			_mesh("DragonBody", SphereMesh.new(), Vector3(0, 0.55, 0), Color(0.30, 0.63, 0.69))
			_mesh("DragonCrest", BoxMesh.new(), Vector3(0, 1.18, 0), Color(0.47, 0.33, 0.71))
			_mesh("Harness", BoxMesh.new(), Vector3(0, 0.52, -0.4), Color(0.36, 0.26, 0.45))
