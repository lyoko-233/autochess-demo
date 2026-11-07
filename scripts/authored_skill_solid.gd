extends Node3D
# Small, recognizable objects complement the soft energy layers.
static var cache: Dictionary={}
var builder: SurfaceTool
var mesh_node: MeshInstance3D
var material: ShaderMaterial
var skill := ""
var phase := ""

func _vertex(p: Vector3, uv: Vector2, color: Color) -> void:
	builder.set_uv(uv)
	builder.set_color(color)
	builder.add_vertex(p)
func _quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color) -> void:
	for entry in [[a,Vector2(0,0)],[b,Vector2(1,0)],[c,Vector2(0,1)],[c,Vector2(0,1)],[b,Vector2(1,0)],[d,Vector2(1,1)]]:_vertex(entry[0],entry[1],color)
func _box(at: Vector3,size: Vector3,color: Color,rotation: Vector3=Vector3.ZERO) -> void:
	var transform=Transform3D(Basis.from_euler(rotation),at)
	var p := []
	for z in [-1,1]:
		for y in [-1,1]:
			for x in [-1,1]:p.append(transform*(Vector3(x,y,z)*size*.5))
	for q in [[0,1,2,3],[4,6,5,7],[0,4,1,5],[2,3,6,7],[0,2,4,6],[1,5,3,7]]:_quad(p[q[0]],p[q[1]],p[q[2]],p[q[3]],color)
func _tube(at: Vector3,axis: Vector3,radius: float,length: float,color: Color,tip: float=-1) -> void:
	var transform=Transform3D(Basis(Quaternion(Vector3.UP,axis.normalized())),at)
	var top := radius if tip<0 else tip
	for i in 12:
		var a=i*TAU/12;var b=(i+1)*TAU/12
		var p=Vector3(sin(a)*radius,-length*.5,cos(a)*radius)
		var q=Vector3(sin(b)*radius,-length*.5,cos(b)*radius)
		var r=Vector3(sin(a)*top,length*.5,cos(a)*top)
		var s=Vector3(sin(b)*top,length*.5,cos(b)*top)
		_quad(transform*p,transform*q,transform*r,transform*s,color.lightened(.05 if i%3==0 else 0))
		_vertex(transform*Vector3(0,-length*.5,0),Vector2(.5,.5),color);_vertex(transform*q,Vector2(1,0),color);_vertex(transform*p,Vector2(0,0),color)
		_vertex(transform*Vector3(0,length*.5,0),Vector2(.5,.5),color);_vertex(transform*r,Vector2(0,1),color);_vertex(transform*s,Vector2(1,1),color)
func _crystal(at: Vector3,length: float,width: float,color: Color) -> void:
	_tube(at,Vector3.UP,width,length,color,0)
func _petal(at: Vector3,angle: float,length: float,width: float,color: Color) -> void:
	var axis=Vector3(sin(angle),.15,cos(angle))
	var side=Vector3(cos(angle),0,-sin(angle))*width
	_quad(at,at+axis*length*.45+side,at+axis*length*.45-side,at+axis*length,color)
func _arc(radius: float,height: float,start: float,sweep: float,width: float,color: Color) -> void:
	for i in 20:
		var a=start+sweep*i/20;var b=start+sweep*(i+1)/20
		var p=Vector3(sin(a)*radius,height,cos(a)*radius);var q=Vector3(sin(b)*radius,height,cos(b)*radius)
		var direction=q-p
		_tube((p+q)*.5,direction,width,direction.length(),color)

func build(ability: String,tint: Color,context: Dictionary,mode: String) -> void:
	skill=ability;phase=mode
	var radius: float=maxf(.12,float(context.get("radius",.4)))
	var length: float=maxf(.1,float(context.get("line_length",3)))
	var key := "%s:%s:%.2f:%.2f"%[skill,phase,radius,length]
	material=ShaderMaterial.new()
	material.shader=preload("res://assets/ui/materials/authored_skill_solid.gdshader")
	material.set_shader_parameter("tint",tint)
	material.set_shader_parameter("tier",float(context.get("star",1)))
	mesh_node=MeshInstance3D.new()
	mesh_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.material_override=material
	add_child(mesh_node)
	if cache.has(key):mesh_node.mesh=cache[key];return
	builder=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal=Color(.72,.80,.86)
	var pale=Color(.88,.96,1)
	var dark=Color(.12,.16,.22)
	var y := .0 if mode=="flight" else .32
	match skill:
		"bounce_stun":
			_tube(Vector3(0,y,0),Vector3.UP,.105,.23,Color(.38,.22,.09))
			for h in [-.085,.085]:_arc(.109,y+h,0,TAU,.013,metal)
			for i in 6:_box(Vector3(sin(i*TAU/6)*.103,y,cos(i*TAU/6)*.103),Vector3(.009,.20,.013),Color(.12,.07,.03),Vector3(0,i*TAU/6,0))
		"missiles":
			_tube(Vector3(0,y,0),Vector3.FORWARD,.065,.34,metal)
			_tube(Vector3(0,y,-.23),Vector3.FORWARD,.065,.16,Color(.72,.12,.06),0)
			for i in 4:_box(Vector3(sin(i*PI/2)*.10,y+cos(i*PI/2)*.10,.10),Vector3(.09,.012,.12),dark,Vector3(0,0,i*PI/2))
		"magic_damage":
			for i in 5:_petal(Vector3(0,y,0),i*TAU/5,.23,.055,metal)
			_crystal(Vector3(0,y+.035,0),.08,.045,Color(1,.72,.2))
		"sacred_arrow","powershot","bounce_attack":
			if skill=="bounce_attack":_arc(.16,y,.3,PI*1.55,.025,metal)
			else:
				_tube(Vector3(0,y,.02),Vector3.FORWARD,.014,.65,metal)
				_tube(Vector3(0,y,-.38),Vector3.FORWARD,.06,.16,pale,0)
				for side in [-1,1]:_box(Vector3(side*.06,y,.26),Vector3(.11,.006,.17),Color(.62,.82,.95),Vector3(0,side*.3,0))
		"hook":
			_arc(.13,y,.2,PI*1.65,.025,metal)
			_tube(Vector3(0,y,.18),Vector3.FORWARD,.02,.24,metal)
			for i in 3:_arc(.035,y,0,TAU,.009,dark);y+=.075
		"assassinate":_tube(Vector3(0,y,0),Vector3.FORWARD,.026,.19,Color(.90,.67,.25),0)
		"chain_frost","cold_embrace","mana_pulse":
			var count := 8 if skill=="cold_embrace" else 6
			for i in count:
				var a=i*TAU/count
				_crystal(Vector3(sin(a)*.18,y+.18,cos(a)*.18),.26,.028,pale)
		"ravage":
			for i in 10:
				var a=i*TAU/10;var base=Vector3(sin(a)*radius*.70,.02,cos(a)*radius*.70)
				for j in 5:
					var p=base+Vector3(sin(a)*j*.035,j*.09,cos(a)*j*.035)
					_tube(p,Vector3(sin(a)*.3,1,cos(a)*.3),.055*(1-j*.15),.13,Color(.16,.50,.43),.04*(1-j*.15))
		"ghostship":
			_box(Vector3(0,y,0),Vector3(.44,.12,.85),Color(.24,.60,.64))
			_tube(Vector3(0,y+.4,0),Vector3.UP,.025,.8,metal)
			_box(Vector3(.12,y+.55,0),Vector3(.42,.40,.015),Color(.65,.88,.92))
			for side in [-1,1]:_box(Vector3(side*.22,y+.08,0),Vector3(.035,.14,.75),metal)
		"heal","leech_seed","treants","spirit_bear","call_of_the_wild","plague_wards":
			var n := 5 if skill in ["spirit_bear","call_of_the_wild"] else 7
			for i in n:
				var a=i*TAU/n
				if skill in ["spirit_bear","call_of_the_wild"]:_crystal(Vector3(sin(a)*.25,.12,cos(a)*.25),.13,.025,Color(.55,.42,.24))
				else:_petal(Vector3(0,y,0),a,.28,.07,Color(.35,.74,.32))
		"poison","corrosive_haze","chemical_rage","firefly","doom":
			for i in 5:_crystal(Vector3(sin(i*2.4)*.18,y+(i%2)*.08,cos(i*2.4)*.18),.16,.025,tint)
		"requiem","death_pulse","exorcism","midnight_pulse":
			for i in (10 if skill=="requiem" else 5):
				var a=i*TAU/(10 if skill=="requiem" else 5);var p=Vector3(sin(a)*radius*.65,y,cos(a)*radius*.65)
				_crystal(p,.21,.05,Color(.68,.76,.81))
				for side in [-1,1]:_box(p+Vector3(side*.025,.045,-.05),Vector3(.014,.025,.012),dark)
		"frontal_reduction","shield","refraction","spiked_carapace","stone_gaze":
			for i in 6:
				var a=i*TAU/6;_petal(Vector3(sin(a)*.21,y,cos(a)*.21),a,.24,.08,pale if skill=="refraction" else metal)
		"spin","aoe_burst","magic_pulse":
			var count := 16 if skill=="aoe_burst" else 12 if skill=="magic_pulse" else 3
			for i in count:_petal(Vector3.ZERO,i*TAU/count,minf(radius,.65),.06,metal)
		"remote_mines","call_down":
			for i in (4 if skill=="call_down" else 1):
				var at=Vector3(sin(i*2.4)*radius*.35,y,cos(i*2.4)*radius*.35)
				_box(at,Vector3(.22,.12,.18),Color(.36,.30,.15));_tube(at+Vector3(0,.11,0),Vector3.UP,.012,.10,Color(1,.42,.08))
		"gods_strength","critical_knockup","critical","mana_burn","fervor","taunt_armor":
			for i in 3:_crystal(Vector3((i-1)*.14,y+.14,0),.22,.025,metal if skill=="taunt_armor" else tint)
		"line_orb","illuminate","stroke_of_fate","waveform","burrowstrike":
			for i in 7:
				var z := -.1-i*length/7
				if skill=="burrowstrike":_crystal(Vector3(0,.04,z),.15,.06,Color(.48,.36,.19))
				elif skill=="stroke_of_fate":_petal(Vector3(0,.03,z),float(i)*.2,.22,.09,dark)
				else:_crystal(Vector3(sin(i)*.12,y,z),.12,.025,pale)
		"static_storm","thundergods_wrath","laguna_blade","plasma_field","random_stun":
			for i in 6:_crystal(Vector3(sin(i*TAU/6)*.25,y+.35,cos(i*TAU/6)*.25),.20,.018,pale)
		"hex","shallow_grave","spell_steal","multicast","disarm","purification":
			for i in (2 if skill=="multicast" else 4):_box(Vector3(sin(i*PI/2)*.2,y+.18,cos(i*PI/2)*.2),Vector3(.065,.13,.018),pale,Vector3(0,i*PI/2,0))
		"transform_wolves","dragon_form","metamorphosis":
			for side in [-1,1]:_crystal(Vector3(side*.20,y+.25,0),.27,.04,metal)
		"attack_aura":
			for i in 3:_petal(Vector3((i-1)*.10,y,0),PI,.26,.035,pale)
		"mana_drain":_arc(.12,y,.2,PI*1.7,.018,tint)
		"scream","pounce","smoke_screen","wildcard_combine":
			for i in 5:_petal(Vector3(0,y,0),i*TAU/5,.24,.045,tint)
		_:_crystal(Vector3(0,y,0),.20,.04,tint)
	builder.generate_normals()
	mesh_node.mesh=builder.commit()
	if cache.size()>=256:cache.erase(cache.keys()[0])
	cache[key]=mesh_node.mesh

func sample(age: float,opacity: float) -> void:
	material.set_shader_parameter("age",age)
	material.set_shader_parameter("opacity",opacity)
	if skill in ["bounce_stun","magic_damage","bounce_attack"] and phase=="flight":mesh_node.rotation.z=age*8.0
