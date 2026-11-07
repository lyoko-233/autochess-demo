extends "res://scripts/hero_skill_effect_3d.gd"
# Four short body transitions, driven only by the actual successful release event.
func configure_form(form: String, width: float, height: float) -> void:
	ability=form
	kind="transform_"+form
	phase="transition"
	lifetime=.66
	var colors := {"transform_wolves":Color("85c5e8"),"dragon_form":Color("e5a95a"),"metamorphosis":Color("af83e3"),"chemical_rage":Color("afd969")}
	tint=colors[form]
	component_color=Color(tint,.75)
	var r := width*.46
	var h := height*.83
	art_context={"radius":r}
	var key := "transform:%s:%s:%s"%[form,width,height]
	if _reuse_geometry(key):
		art.scale=Vector3(width,height,width)
		return
	match form:
		"transform_wolves":
			for side in [-1,1]:
				for i in 7: shard(Vector3(side*r*(.45+i*.07),h*(.30+i*.065),.08),h*.15,r*.045,Vector3(.3,0,side*.5))
			for i in 9: bar(Vector3(sin(i*2.1)*r,.1+i*h*.05,cos(i*2.1)*r),Vector3(sin(i*2.1)*r*.65,.22+i*h*.05,cos(i*2.1)*r*.65),.012)
		"dragon_form":
			for side in [-1,1]:
				for i in 6: shard(Vector3(side*r*(.6+i*.07),h*(.35+i*.055),.03),h*.12,r*.09,Vector3(.2,0,side*.8))
			for i in 10: shard(Vector3(sin(i*2.0)*r*.7,h*.25+(i%4)*h*.14,cos(i*2.0)*r*.7),h*.12,.015,Vector3(.4,0,.3))
		"metamorphosis":
			for side in [-1,1]:
				for i in 3:
					var at:=Vector3(side*r*(.45+i*.2),h*.2,0)
					bar(at,at+Vector3(side*r*.13,h*.55,.08),.018)
					bar(at+Vector3(side*r*.13,h*.55,.08),at+Vector3(side*r*.20,h*.7,0),.012)
			for i in 10: shard(Vector3(sin(i*2.1)*r*.8,h*.3+(i%3)*h*.18,cos(i*2.1)*r*.8),h*.11,r*.075,Vector3(.5,i,0))
		"chemical_rage":
			for i in 14:
				var at:=Vector3(sin(i*2.4)*r*.8,h*.18+(i%5)*h*.12,cos(i*2.4)*r*.8)
				orb(at,.022+(i%3)*.007)
			for side in [-1,1]:
				for i in 3: bar(Vector3(side*r*.65,h*.52,i*.04),Vector3(side*r*.80,h*.75,i*.04),.013)
	material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_COLOR]=baked_colors
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_mesh(mesh)
	_finish_surface()
	art.scale=Vector3(width,height,width)
	_remember_geometry(key)
func sample(age: float) -> void:
	var p:=clampf(age/lifetime,0,1)
	var opacity:=sin(p*PI)*.9
	art.sample(age,opacity)
	material.albedo_color=Color(1,1,1,opacity)
	surface.set_shader_parameter("opacity",opacity)
	surface.set_shader_parameter("age",age)
	surface.set_shader_parameter("family",3 if ability=="transform_wolves" else 1 if ability=="dragon_form" else 5 if ability=="metamorphosis" else 4)
	position=Vector3(0,p*.12,0)
	rotation.y=age*(.4 if ability=="chemical_rage" else -.7 if ability=="metamorphosis" else .3)
	scale=Vector3.ONE*(.82+p*.24)
