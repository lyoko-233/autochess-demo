extends Node3D

@export_range(0, 2) var theme := 0

const STONE = preload("res://assets/ui/materials/stone.tres")
const BRONZE = preload("res://assets/ui/materials/bronze.tres")
const SLATE = preload("res://assets/ui/materials/moonlit_stone.tres")
const StoneMesh = preload("res://scripts/stone_mesh.gd")


func _box(parent: Node3D, label: String, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := StoneMesh.beveled_box(dimensions,0.06)
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node


func _ready() -> void:
	var palettes := [
		[Color(0.43, 0.49, 0.49), Color(0.445, 0.50, 0.50)],
		[Color(0.24, 0.24, 0.31), Color(0.32, 0.33, 0.41)],
		[Color(0.35, 0.25, 0.20), Color(0.45, 0.32, 0.24)]]
	for row in range(8):
		for col in range(8):
			var material: Material = SLATE.duplicate() if theme == 0 else STONE.duplicate()
			var tint: Color = palettes[theme][(row + col) % 2].lightened(float((row * 7 + col * 13) % 5) * 0.010)
			if theme == 0: material.set_shader_parameter("stone_color",tint)
			else: material.albedo_color=tint
			_box(self, "Tile_%d_%d" % [row, col], Vector3(0.988, 0.12, 0.988), Vector3(col - 3.5, -0.06, row - 3.5), material)
	var decoration := Node3D.new()
	decoration.name = "StoneFrame"
	add_child(decoration)
	var rim: ShaderMaterial = SLATE.duplicate()
	rim.set_shader_parameter("stone_color",Color(0.34,0.40,0.38))
	var metal: StandardMaterial3D = BRONZE.duplicate()
	metal.albedo_color = Color(0.17,0.20,0.19)
	metal.roughness = .70
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1,.57,.17)
	glow.emission_enabled = true
	glow.emission = Color(1,.40,.07)
	glow.emission_energy_multiplier = .6
	_box(decoration,"Foundation",Vector3(8.9,.23,8.9),Vector3(0,-.26,0),rim)
	_box(decoration,"FoundationPlinth",Vector3(8.98,.08,8.98),Vector3(0,-.42,0),rim)
	_box(decoration,"BenchBridge",Vector3(8.1,.12,.25),Vector3(0,-.13,4.43),rim)
	_box(decoration,"BenchFoundation",Vector3(8.15,.15,1.10),Vector3(0,-.23,5.03),rim)
	_box(decoration,"BenchLip",Vector3(8.15,.08,.10),Vector3(0,-.08,5.61),rim)
	for side in [-1,1]:
		for block in range(9):
			_box(decoration,"RimX%d_%d"%[side,block],Vector3(.30,.14,.97),Vector3(side*4.16,-.02,block-4),rim)
			_box(decoration,"RimZ%d_%d"%[side,block],Vector3(.97,.14,.30),Vector3(block-4,-.02,side*4.16),rim)
	for x in [-1,1]:
		for z in [-1,1]:
			var at := Vector3(x*4.25,0,z*4.25)
			_box(decoration,"CornerFoot",Vector3(.67,.13,.67),at+Vector3(0,.015,0),rim)
			_box(decoration,"Corner",Vector3(.52,.15,.52),at+Vector3(0,.15,0),rim)
			_box(decoration,"CornerCap",Vector3(.62,.075,.62),at+Vector3(0,.265,0),rim)
			_box(decoration,"CornerInset",Vector3(.38,.025,.38),at+Vector3(0,.315,0),metal)
			# Small pagoda lantern: narrow illuminated panes inside a dark metal cage.
			_box(decoration,"LanternFoot",Vector3(.27,.045,.27),at+Vector3(0,.36,0),metal)
			_box(decoration,"LanternGlass",Vector3(.135,.22,.135),at+Vector3(0,.50,0),glow)
			for u in [-1,1]:
				for v in [-1,1]:
					_box(decoration,"LanternPost",Vector3(.02,.24,.02),at+Vector3(u*.09,.50,v*.09),metal)
			_box(decoration,"LanternBelt",Vector3(.21,.018,.21),at+Vector3(0,.50,0),metal)
			_box(decoration,"LanternLintel",Vector3(.23,.035,.23),at+Vector3(0,.63,0),metal)
			var roof := MeshInstance3D.new()
			roof.name = "LanternRoof"
			var roof_mesh := CylinderMesh.new()
			roof_mesh.bottom_radius = .24
			roof_mesh.top_radius = .035
			roof_mesh.height = .14
			roof_mesh.radial_segments = 4
			roof.mesh = roof_mesh
			roof.material_override = metal
			roof.position = at+Vector3(0,.72,0)
			roof.rotation.y = PI/4
			decoration.add_child(roof)
			_box(decoration,"LanternFinial",Vector3(.035,.065,.035),at+Vector3(0,.82,0),metal)
			var lamp := OmniLight3D.new()
			lamp.name = "LanternLight"
			lamp.position = at+Vector3(0,.50,0)
			lamp.light_color = Color(1,.64,.28)
			lamp.light_energy = .45
			lamp.omni_range = 1.7
			lamp.shadow_enabled = false
			decoration.add_child(lamp)
	# Static ornamentation shares materials; retain authoring parts while reducing submissions.
	set_meta("frame_batch",preload("res://scripts/model_mesh_batch.gd").apply(decoration,"moonlit_frame_v3"))
	set_meta("art_revision","20261011_painted_slate")
