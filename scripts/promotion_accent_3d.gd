extends Node3D
var age := 0.0
var material: StandardMaterial3D
var shards: MultiMeshInstance3D
var width := .5
var height := .8
func configure(color: Color,w: float,h: float) -> void:
	width=w;height=h
	material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(color,.7)
	material.emission_enabled=true
	material.emission=color
	material.emission_energy_multiplier=.65
	var mesh=CylinderMesh.new()
	mesh.top_radius=0
	mesh.bottom_radius=.008
	mesh.height=.055
	mesh.radial_segments=4
	var multi=MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.mesh=mesh
	multi.instance_count=12
	shards=MultiMeshInstance3D.new()
	shards.multimesh=multi
	shards.material_override=material
	shards.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shards)
func _process(delta: float) -> void:
	age+=delta
	if age>=.8:queue_free();return
	var p=age/.8
	material.albedo_color.a=sin(p*PI)*.75
	for i in 12:
		var a=i*TAU/12+p*.8
		var at=Vector3(sin(a)*width*.30,height*(.18+p*.65)+(i%3)*.025,cos(a)*width*.30)
		shards.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,at))
