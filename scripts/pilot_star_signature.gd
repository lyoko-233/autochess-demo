extends Node3D
# Small equipment-bound ambient geometry; stronger geometry only on replay events.
var id: String
var parts: Array[MeshInstance3D]=[]
var material: StandardMaterial3D
var scale_factor:=1.0
func _mesh(mesh: Mesh, at: Vector3, rotation_value:=Vector3.ZERO) -> void:
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.position=at
	node.rotation=rotation_value
	node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	parts.append(node)
func setup(value: String, color: Color, fitted_scale: float) -> void:
	id=value
	scale_factor=fitted_scale
	name="PilotSignature"
	material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(color,.15)
	material.emission_enabled=true
	material.emission=color
	material.emission_energy_multiplier=.3
	if id=="Axe":
		for i in 5:
			var flame:=PrismMesh.new()
			flame.size=Vector3(.022,.055,.014)/fitted_scale
			_mesh(flame,Vector3((i-2)*.018,.025,0)/fitted_scale)
	elif id=="Phantom Assassin":
		for i in 3:
			var rune:=PrismMesh.new()
			rune.size=Vector3(.055,.055,.008)/fitted_scale
			_mesh(rune,Vector3((i-1)*.045,0,0)/fitted_scale,Vector3(0,0,PI*.25))
	elif id=="Tidehunter":
		for i in 3:
			var wave:=TorusMesh.new()
			wave.inner_radius=(.03+i*.015)/fitted_scale
			wave.outer_radius=(.034+i*.015)/fitted_scale
			wave.rings=20
			wave.ring_segments=4
			_mesh(wave,Vector3(0,i*.025,0)/fitted_scale)
	elif id=="Sniper":
		for i in 4:
			var ray:=BoxMesh.new()
			ray.size=Vector3(.012,.012,.07)/fitted_scale
			_mesh(ray,Vector3((i-1.5)*.02,0,0)/fitted_scale)
	else:
		for i in 6:
			var frost:=CylinderMesh.new()
			frost.top_radius=0
			frost.bottom_radius=.009/fitted_scale
			frost.height=.085/fitted_scale
			frost.radial_segments=4
			_mesh(frost,Vector3.ZERO,Vector3(0,0,i*TAU/6))
func sample(age: float, strength: float) -> void:
	material.albedo_color.a=.12+strength*.55
	material.emission_energy_multiplier=.18+strength*.65
	for i in parts.size():
		parts[i].scale=Vector3.ONE*(.85+strength*.8)
		if id=="Axe": parts[i].position.y=(.02+fposmod(age*.025+i*.01,.055))/scale_factor
		elif id=="Phantom Assassin": parts[i].rotation.z=PI*.25+sin(age*.7+i)*.1
		elif id=="Tidehunter": parts[i].scale=Vector3.ONE*(.8+fposmod(age*.25+i*.2,1)*.6+strength*.4)
		elif id=="Sniper": parts[i].scale.z=.7+strength*2
		else: parts[i].rotation.y=age*.2
