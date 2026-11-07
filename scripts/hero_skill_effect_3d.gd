extends "res://scripts/combat_effect_3d.gd"

# Geometry is sampled from replay time. These cues never schedule gameplay.
var ability := ""
var effective_radius := 0.0
var delay := 0.0
var sustain := false
var motion := "burst"
var phase := "release"
var distance := 0.0
var spread_time := .22
var baked_colors := PackedColorArray()
var vertices := PackedVector3Array()
var component_color := Color.WHITE
var surface: ShaderMaterial
var is_area := false
static var signature_cache: Dictionary = {}
var art_context: Dictionary = {}
var art: Node3D

func _reuse_geometry(key: String) -> bool:
	if not signature_cache.has(key): return false
	var entry: Dictionary=signature_cache[key]
	vertices=entry.vertices
	baked_colors=entry.colors
	motion=entry.motion
	material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	_mesh(entry.mesh)
	_finish_surface()
	return true

func _remember_geometry(key: String) -> void:
	if signature_cache.size()>=128: signature_cache.erase(signature_cache.keys()[0])
	signature_cache[key]={"mesh":parts[0].mesh,"vertices":vertices,"colors":baked_colors,"motion":motion}


func _surface_family(skill: String) -> int:
	if skill in ["spin","firefly","laguna_blade","doom","metamorphosis","dragon_form","remote_mines"]: return 1
	if skill in ["waveform","ravage","ghostship","leech_seed"]: return 2
	if skill in ["cold_embrace","mana_pulse","chain_frost","refraction"]: return 3
	if skill in ["heal","treants","poison","chemical_rage","plague_wards","spirit_bear","call_of_the_wild"]: return 4
	if skill in ["requiem","death_pulse","midnight_pulse","exorcism","spell_steal","shallow_grave","soulbind"]: return 5
	if skill in ["lightning","random_stun","plasma_field","static_storm","thundergods_wrath"]: return 6
	if skill in ["smoke_screen","transform_wolves","throw","burrowstrike"]: return 7
	return 0

func _finish_surface() -> void:
	surface = ShaderMaterial.new()
	surface.shader = preload("res://assets/ui/materials/skill_surface.gdshader")
	surface.set_shader_parameter("family",_surface_family(ability))
	parts[0].material_override = surface
	art=preload("res://scripts/advanced_skill_art.gd").new()
	add_child(art)
	art.build(ability,tint,art_context,phase,is_area)

func _fine_details(skill: String, r: float, length_value: float) -> void:
	var color := component_color
	component_color = Color(tint.lightened(.35),.45)
	match skill:
		"ravage":
			for i in 16:
				var a := i*TAU/16
				var base := Vector3(sin(a)*r*.77,.08,cos(a)*r*.77)
				for j in 5:
					var p := j/5.0
					var q := (j+1)/5.0
					bar(base+Vector3(sin(a)*p*.22,sin(p*PI*.65)*.65,cos(a)*p*.22),base+Vector3(sin(a)*q*.22,sin(q*PI*.65)*.65,cos(a)*q*.22),.045*(1-p)+.009)
			ring(r*.60,.06,.014)
		"ghostship":
			for i in 9: bar(Vector3(-.22,.23,-.6+i*.15),Vector3(.22,.23,-.6+i*.15),.015)
			for side in [-1,1]: bar(Vector3(side*.29,.35,-.4),Vector3(side*.29,.35,.6),.015)
		"requiem","exorcism","death_pulse":
			for i in (10 if skill=="exorcism" else 6):
				var angle := i*TAU/(10 if skill=="exorcism" else 6)
				var at := Vector3(sin(angle)*r*.65,.45,cos(angle)*r*.65)
				for side in [-1,1]: orb(at+Vector3(side*.022,.035,.08),.018)
				bar(at,at+Vector3(0,-.10,-.15),.017)
		"laguna_blade","thundergods_wrath","static_storm":
			for side in [-1,1]: lightning(Vector3(0,.95,0),Vector3(side*.3,.2,.12),5,.014)
		"spin","aoe_burst","plasma_field": ring(r*.93,.07,.012,PI*1.8); ring(r*.67,.20,.010,PI*1.5)
		"chain_frost","cold_embrace","refraction","mana_pulse":
			for i in 6:
				var a := i*TAU/6
				var at := Vector3(sin(a)*.28,.35,cos(a)*.28)
				shard(at,.13,.018,Vector3(.4,a,.3))
		"firefly","doom","remote_mines":
			for i in 8: shard(Vector3(sin(i*2.4)*r*.55,.30+(i%3)*.09,cos(i*2.4)*r*.55),.16,.022)
		"powershot","illuminate","stroke_of_fate","waveform","burrowstrike":
			for i in 12:
				var t := i/11.0
				bar(Vector3(sin(t*TAU)*.10,.11,-t*length_value),Vector3(sin((t+.035)*TAU)*.10,.15,-(t+.035)*length_value),.016)
		"heal","treants","poison","chemical_rage","plague_wards","spirit_bear","call_of_the_wild":
			for i in 6: petals(2,.10,.15+i*.08)
		"critical","critical_knockup","taunt_armor","gods_strength","fervor","pounce","frontal_reduction":
			for i in 5: bar(Vector3(-.22+i*.10,.18,0),Vector3(-.14+i*.10,.38,.04),.012)
		"shield","purification","shallow_grave","multicast","disarm","stone_gaze":
			ring(.27,.22,.009)
			for i in 4: cross(Vector3(sin(i*PI/2)*.27,.30,cos(i*PI/2)*.27),.035)
		"line_orb","spell_steal","magic_damage","wildcard_combine","hex","mana_burn","mana_drain": spiral(.15,1,.42)
		"bounce_stun","missiles","assassinate","hook","sacred_arrow","bounce_attack": ring(.16,.32,.009,PI*1.5)
		"smoke_screen","midnight_pulse","corrosive_haze": ring(r*.62,.045,.012,PI*1.7)
		"metamorphosis","dragon_form","transform_wolves": spiral(.23,1.5,.80)
		_: ring(.18,.2,.009,PI)
	component_color = color


func configure_flight(skill: String, color: Color, context: Dictionary = {}) -> void:
	ability = skill
	phase = "flight"
	lifetime = 60.0
	kind = "flight_"+skill
	tint = color
	component_color = Color(color,.95)
	art_context=context
	var cache_key := "flight:%s:%s"%[skill,color]
	if _reuse_geometry(cache_key): return
	match skill:
		"line_orb": orb(Vector3.ZERO,.19); spiral(.21,2,.25); wings(.35,3)
		"missiles": shard(Vector3.ZERO,.35,.075,Vector3(-PI/2,0,0)); bar(Vector3(-.13,0,.12),Vector3(.13,0,.12),.035)
		"bounce_stun": orb(Vector3.ZERO,.12,Vector3(1,1.4,1)); ring(.16,0,.02); petals(3,.13,0)
		"chain_frost": orb(Vector3.ZERO,.17); spokes(6,.25,0,.06)
		"magic_damage": spokes(5,.19,0); ring(.13,0,.04)
		"sacred_arrow": bar(Vector3(0,0,.4),Vector3(0,0,-.25),.025); shard(Vector3(0,0,-.3),.25,.065,Vector3(-PI/2,0,0)); wings(.25,3)
		"hook": bar(Vector3(0,0,.35),Vector3(0,0,-.1),.035); ring(.14,0,.035,PI*1.4)
		"poison": orb(Vector3.ZERO,.12,Vector3(1,1,1.8)); petals(4,.11,0)
		"random_stun": lightning(Vector3(0,0,-.18),Vector3(0,0,.18),6,.07)
		"assassinate": bar(Vector3(0,0,.55),Vector3(0,0,-.15),.024); orb(Vector3.ZERO,.06)
		"powershot": bar(Vector3(0,0,.65),Vector3(0,0,-.3),.035); shard(Vector3(0,0,-.25),.18,.05,Vector3(-PI/2,0,0))
		"illuminate": orb(Vector3.ZERO,.19,Vector3(1.8,.6,2)); wings(.45,4)
		"stroke_of_fate": orb(Vector3.ZERO,.14,Vector3(1.8,.5,2.2)); spiral(.16,2,.15)
		"ravage": shard(Vector3.ZERO,.45,.11); spiral(.12,2,.3)
		"requiem": orb(Vector3.ZERO,.12,Vector3(1,.7,2.4)); wings(.3,2)
		"death_pulse": orb(Vector3.ZERO,.14); spiral(.2,2,.15)
		_: orb(Vector3.ZERO,.11); shard(Vector3(0,0,.22),.35,.045,Vector3(-PI/2,0,0))
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = baked_colors
	var combined := ArrayMesh.new()
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_mesh(combined)
	_finish_surface()
	_remember_geometry(cache_key)

func _bake(mesh: Mesh, transform: Transform3D) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			for index in indices:
				vertices.append(transform * points[index])
				baked_colors.append(component_color)
		else:
			for point in points:
				vertices.append(transform * point)
				baked_colors.append(component_color)

func bar(a: Vector3, b: Vector3, width: float = .035) -> void:
	if a.distance_to(b) < .001: return
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = width*.5
	mesh.top_radius = width*.35
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	var basis := Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	_bake(mesh,Transform3D(basis,(a+b)*.5))

func ring(r: float, height: float = .05, width: float = .035, sweep: float = TAU) -> void:
	for i in 64:
		var a := float(i)*sweep/64
		var b := float(i+1)*sweep/64
		var inner_a := Vector3(sin(a)*(r-width*.5),height,cos(a)*(r-width*.5))
		var outer_a := Vector3(sin(a)*(r+width*.5),height,cos(a)*(r+width*.5))
		var inner_b := Vector3(sin(b)*(r-width*.5),height,cos(b)*(r-width*.5))
		var outer_b := Vector3(sin(b)*(r+width*.5),height,cos(b)*(r+width*.5))
		triangle(inner_a,outer_a,inner_b)
		triangle(inner_b,outer_a,outer_b)

func orb(at: Vector3, size: float, stretch: Vector3 = Vector3.ONE) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size*2
	mesh.radial_segments = 12
	mesh.rings = 6
	_bake(mesh,Transform3D(Basis.from_scale(stretch),at))

func shard(at: Vector3, length: float, width: float, tilt: Vector3 = Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0
	mesh.bottom_radius = width
	mesh.height = length
	mesh.radial_segments = 6
	_bake(mesh,Transform3D(Basis.from_euler(tilt),at))

func spokes(count: int, r: float, height: float = .08, bend: float = .0) -> void:
	for i in count:
		var a := i*TAU/count
		var direction := Vector3(sin(a),0,cos(a))
		bar(direction*.18+Vector3.UP*height,direction*r+Vector3.UP*(height+bend),.045)

func petals(count: int, r: float, height: float = .15) -> void:
	for i in count:
		var a := i*TAU/count
		orb(Vector3(sin(a)*r,height,cos(a)*r),.09,Vector3(.45,1,1.8))

func cage(r: float, count: int, height: float) -> void:
	ring(r,.08,.028)
	for i in count:
		var a := i*TAU/count
		bar(Vector3(sin(a)*r,.08,cos(a)*r),Vector3(sin(a)*r*.35,height,cos(a)*r*.35),.032)

func spiral(r: float, turns: float, height: float) -> void:
	for i in 64:
		var p := float(i)/64
		var q := float(i+1)/64
		bar(Vector3(sin(p*TAU*turns)*r,p*height,cos(p*TAU*turns)*r),Vector3(sin(q*TAU*turns)*r,q*height,cos(q*TAU*turns)*r),.026)

func lightning(a: Vector3, b: Vector3, segments: int = 9, width: float = .05) -> void:
	var previous := a
	for i in range(1,segments+1):
		var p := float(i)/segments
		var at := a.lerp(b,p)
		if i < segments: at.x += (.10 if i%2==0 else -.10)
		bar(previous,at,width)
		previous = at

func cross(at: Vector3, size: float) -> void:
	bar(at+Vector3(-size,0,0),at+Vector3(size,0,0),.065)
	bar(at+Vector3(0,-size,0),at+Vector3(0,size,0),.065)

func triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	for point in [a,b,c]:
		vertices.append(point)
		baked_colors.append(component_color)

func wings(size: float, feathers: int) -> void:
	for side in [-1,1]:
		for i in feathers:
			bar(Vector3(side*.14,.4,0),Vector3(side*(.35+i*.08)*size,.65+i*.09, .1+i*.055),.045)

func configure(skill: String, color: Color, context: Dictionary, mode: String = "release") -> void:
	if mode == "hit" and skill in ["line_orb","powershot","illuminate","stroke_of_fate","waveform","burrowstrike","hook"]:
		configure_flight(skill,color)
		kind = "signature_"+skill
		lifetime = .32
		return
	ability = skill
	kind = "signature_"+skill
	phase = mode
	art_context=context
	tint = color
	component_color = Color(color, .8)
	effective_radius = float(context.get("radius",1))
	delay = float(context.get("delay",0)) if mode == "release" else 0.0
	distance = float(context.get("distance",1))
	var r := effective_radius
	var line_length := float(context.get("line_length",11.32))
	var speed := float(context.get("speed",0))
	spread_time = r*100.0/speed if speed > 0 else .22
	var target := Vector3(0,.4,-distance)
	var area := skill in ["magic_pulse","spin","aoe_burst","plasma_field","requiem","firefly","purification","death_pulse","chemical_rage","stone_gaze","ravage","midnight_pulse","exorcism","smoke_screen","ghostship","static_storm","call_down","remote_mines"]
	is_area=area
	sustain = skill in ["magic_pulse","spin","firefly","chemical_rage","static_storm","midnight_pulse","exorcism","smoke_screen", "taunt_armor", "hex", "cold_embrace", "disarm", "multicast", "shield", "shallow_grave", "poison", "leech_seed", "doom", "corrosive_haze", "refraction", "stone_gaze", "spiked_carapace", "gods_strength", "mana_drain"] and mode == "release"
	lifetime = maxf(.7,float(context.get("duration",0))) if sustain else .85
	lifetime += delay
	if mode == "hit": lifetime = .32
	var cache_key := "%s:%s:%s:%s:%s:%s:%s"%[skill,mode,color,r,distance,line_length,float(context.get("line_half_width",1))]
	if _reuse_geometry(cache_key): return
	# Single target skills have a local footprint; their cast range is not an AOE.
	if area:
		component_color = Color(color,.36)
		ring(r,.035,.027)
		component_color = Color(color,.88)
	if skill in ["line_orb","powershot","illuminate","stroke_of_fate","waveform","burrowstrike"]:
		var half_width := float(context.get("line_half_width",1))
		component_color = Color(color,.22)
		for side in [-1,1]: bar(Vector3(side*half_width,.03,0),Vector3(side*half_width,.03,-line_length),.018)
		component_color = Color(color,.88)
	match skill:
		"taunt_armor": ring(r,.24,.06); spokes(8,r,.3,.18); motion="expand"
		"heal": petals(7,.45,.65); spiral(.35,2,.8); cross(Vector3(0,.45,0),.12); motion="orbit"
		"critical_knockup": shard(Vector3(0,.55,0),1.1,.18); ring(.35,.12); spokes(6,.5,.06); motion="rise"
		"attack_aura": wings(.7,3); ring(.28,.08,.018,PI); motion="rise"
		"magic_damage": spokes(5,.36,.35); ring(.27,.35,.055); motion="spin"
		"magic_pulse": spokes(12,r,.2); petals(6,r*.72,.24); motion="flicker"
		"missiles":
			for i in 3: shard(Vector3((i-1)*.18,.38,-.15),.35,.065,Vector3(-PI/2,0,0))
			ring(.35,.09,.02); motion="rise"
		"hex": cage(.35,5,.75); orb(Vector3(0,.5,0),.16,Vector3(1.3,.7,1)); motion="spin"
		"mana_burn": lightning(Vector3(-.3,.3,0),Vector3(.3,.6,0),5,.035); spokes(4,.3,.3); motion="flicker"
		"throw": petals(5,.38,.22); shard(Vector3(0,.45,0),.5,.22); motion="rise"
		"bounce_stun": orb(Vector3(0,.4,0),.14); ring(.23,.4,.025); petals(3,.23,.4); motion="hop"
		"cold_embrace": cage(.4,8,.9); wings(.75,5); motion="breathe"
		"frontal_reduction": ring(.4,.38,.075,PI); shard(Vector3(0,.38,.3),.4,.12); motion="breathe"
		"mana_drain": spiral(.15,4,.7); lightning(Vector3(0,.4,0),target,12,.026); motion="flicker"
		"mana_pulse": ring(r,.05,.025); petals(8,.4,.5); spokes(8,.6,.5); motion="expand"
		"call_of_the_wild": spokes(4,.6); petals(4,.35,.12); shard(Vector3(0,.15,0),.25,.17); motion="rise"
		"spin": ring(r,.28,.075); ring(r*.78,.46,.045,PI*1.6); spokes(3,r,.3); motion="spin"
		"aoe_burst": ring(r,.18,.08); spokes(16,r,.18); petals(8,r*.9,.18); motion="spin"
		"line_orb": orb(Vector3(0,.45,-.2),.23); spiral(.3,2,.4); motion="breathe"
		"random_stun": lightning(Vector3(0,.2,0),Vector3(0,.9,0),6,.09); cage(.25,3,.65); motion="flicker"
		"bounce_attack": ring(.28,.38,.075,PI*1.65); shard(Vector3(.23,.38,0),.25,.045,Vector3(0,0,PI/2)); motion="spin"
		"treants": spiral(.36,2,.7); petals(5,.4,.5); spokes(5,.5,.1); motion="rise"
		"waveform":
			# Continuous crests are authored in the soft ribbon layer.
			motion="surge"
		"firefly":
			for i in 12: shard(Vector3(sin(i*2.4)*r*.8,.2,cos(i*2.4)*r*.8),.4,.08)
			wings(1,4); motion="flicker"
		"spell_steal": spiral(.4,3,.65); cross(Vector3(0,.65,0),.15); motion="spin"
		"disarm": cross(Vector3(0,.6,0),.32); ring(.35,.4,.028); motion="breathe"
		"multicast": petals(2,.24,.65); spokes(2,.4,.35,.3); motion="hop"
		"transform_wolves": wings(1.1,3); shard(Vector3(-.22,.5,0),.5,.09); shard(Vector3(.22,.5,0),.5,.09); motion="rise"
		"plague_wards": spiral(.3,2,.55); shard(Vector3(0,.45,0),.6,.16); petals(3,.3,.12); motion="rise"
		"purification": cross(Vector3(0,.65,0),.32); ring(r,.1,.065); spokes(8,r,.1); motion="expand"
		"powershot": bar(Vector3(0,.32,0),Vector3(0,.32,-line_length),.085); wings(.8,3); motion="surge"
		"plasma_field": ring(r,.15,.06); ring(r*.85,.25,.027); motion="return"
		"critical": bar(Vector3(-.4,.05,0),Vector3(.4,.8,0),.07); bar(Vector3(-.24,.05,.1),Vector3(.3,.65,.1),.035); motion="flash"
		"shield": cage(.43,12,.85); ring(.4,.45,.04); motion="breathe"
		"burrowstrike":
			for i in 12: shard(Vector3(0,.18,-i*line_length/11),.38,.14)
			motion="surge"
		"assassinate": ring(.38,.4,.018); cross(Vector3(0,.4,0),.16); motion="flash"
		"poison": spiral(.24,3,.7); orb(Vector3(0,.3,0),.17,Vector3(1,.6,1)); motion="breathe"
		"requiem": spokes(20,r,.26,.25); petals(20,r*.82,.5); motion="expand"
		"laguna_blade": lightning(Vector3(0,1.8,0),Vector3(0,.15,0),12,.12); spokes(7,.45,.08); motion="flash"
		"metamorphosis": wings(1.8,6); spiral(.32,2,.95); motion="rise"
		"shallow_grave": cross(Vector3(0,.75,0),.28); cage(.35,4,1.1); motion="rise"
		"hook":
			for i in 8: ring(.07,.35+i*.02,.025,PI*1.5)
			bar(Vector3(0,.4,0),target,.025); motion="flash"
		"leech_seed": spiral(.3,3,.75); petals(6,.25,.65); motion="orbit"
		"doom": cage(.4,3,.95); spokes(3,.4,.5); shard(Vector3(0,.9,0),.42,.14); motion="flicker"
		"ghostship":
			for side in [-1,1]:
				bar(Vector3(0,.24,-.9),Vector3(side*.3,.16,-.4),.07)
				bar(Vector3(side*.3,.16,-.4),Vector3(side*.3,.16,.6),.07)
				bar(Vector3(side*.3,.16,.6),Vector3(0,.24,.9),.07)
			bar(Vector3(0,.2,0),Vector3(0,1.25,0),.055)
			bar(Vector3(-.45,1,0),Vector3(.45,1,0),.10)
			component_color = Color(color,.35)
			triangle(Vector3(-.45,1,0),Vector3(.45,1,0),Vector3(.35,.4,.08))
			triangle(Vector3(-.45,1,0),Vector3(.35,.4,.08),Vector3(-.35,.4,.08))
			component_color = Color(color,.88)
			ring(r*.8,.1,.045,PI); motion="ship"
		"fervor": bar(Vector3(-.22,.2,0),Vector3(-.1,.75,0),.05); bar(Vector3(.1,.2,0),Vector3(.22,.75,0),.05); petals(3,.3,.25); motion="rise"
		"illuminate":
			for i in 5: bar(Vector3((i-2)*.32,.25,0),Vector3((i-2)*.32,.25,-line_length),.045)
			ring(.6,.6,.04); motion="surge"
		"death_pulse": ring(r,.25,.055); petals(12,r*.72,.3); spiral(.28,2,.55); motion="expand"
		"refraction": cage(.42,6,.85); spokes(6,.42,.35,.3); motion="spin"
		"chemical_rage":
			for i in 15: orb(Vector3(sin(i*2.4)*r*.8,.06,cos(i*2.4)*r*.8),.12,Vector3(2,.4,2))
			spiral(.38,2,.8); motion="breathe"
		"static_storm":
			for i in 7: lightning(Vector3(sin(i)*r*.8,1.3,cos(i)*r*.8),Vector3(sin(i)*r*.8,.1,cos(i)*r*.8),7,.035)
			ring(r,1.2,.03); motion="flicker"
		"stone_gaze": spokes(12,r,.15); orb(Vector3(0,.7,0),.22,Vector3(1.8,.5,1)); cage(.4,3,.8); motion="expand"
		"dragon_form": wings(2,7); shard(Vector3(0,.8,0),.75,.18); motion="rise"
		"spirit_bear": petals(4,.3,.1); orb(Vector3(0,.15,.18),.21,Vector3(1.3,.5,1)); spiral(.45,1,.55); motion="rise"
		"familiars": wings(.7,5); petals(2,.45,.55); ring(.5,.05,.025); motion="hop"
		"stroke_of_fate":
			for i in 8: bar(Vector3(sin(i)*.6,.06,-i*line_length/8),Vector3(sin(i+1)*.6,.06,-(i+1)*line_length/8),.18)
			motion="surge"
		"spiked_carapace":
			for i in 10: shard(Vector3(sin(i)*.38,.38,cos(i)*.38),.5,.08,Vector3(.6,i,0))
			motion="breathe"
		"call_down": cross(Vector3(0,.06,0),r*.7); ring(r*.55,.05,.035); shard(Vector3(0,1.2,0),.65,.2,Vector3(PI,0,0)); motion="fall"
		"ravage":
			for i in 16:
				var a := i*TAU/16
				var at := Vector3(sin(a)*r*.86,.1,cos(a)*r*.86)
				bar(at,at+Vector3(sin(a)*.15,.5,cos(a)*.15),.07)
				shard(at+Vector3(0,.65,0),.4,.09,Vector3(.25,a,0))
			ring(r*.72,.1,.08); motion="expand"
		"midnight_pulse": spiral(r*.65,3,.18); ring(r*.9,.1,.055); petals(8,r*.8,.12); motion="spin"
		"remote_mines": spokes(8,r,.1,.15); orb(Vector3(0,.15,0),.23); shard(Vector3(0,.6,0),.8,.22); motion="explode"
		"exorcism": petals(18,r*.8,.55); spiral(r*.6,2,.45); motion="orbit"
		"gods_strength": shard(Vector3(0,.7,0),1.3,.25); wings(1.2,2); ring(.5,.1,.065); motion="rise"
		"thundergods_wrath": lightning(Vector3(0,2.4,0),Vector3(0,.05,0),14,.10); ring(.45,.05,.065); motion="flash"
		"wildcard_combine": orb(Vector3(0,.4,0),.14); spiral(.26,3,.6); ring(.32,.35,.018); motion="orbit"
		"corrosive_haze": cage(.32,7,.7); petals(4,.3,.45); motion="breathe"
		"scream": ring(r,.35,.045); ring(r*.65,.55,.025,PI*1.8); spokes(9,r,.25,.15); motion="expand"
		"pounce": cage(.38,4,.65); spokes(4,.45,.1); motion="hop"
		"sacred_arrow": bar(Vector3(0,.4,.3),Vector3(0,.4,-.5),.025); shard(Vector3(0,.4,-.48),.25,.08,Vector3(-PI/2,0,0)); petals(3,.12,.4); motion="flash"
		"chain_frost": orb(Vector3(0,.4,0),.22); spokes(6,.34,.4,.12); cage(.26,6,.65); motion="spin"
		"smoke_screen":
			# Moving smoke sheets replace the visible low-poly spheres.
			motion="breathe"
		_: spokes(5,.35,.3)
	_fine_details(skill,r,line_length)
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color.WHITE
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = baked_colors
	var combined := ArrayMesh.new()
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_mesh(combined)
	_finish_surface()
	_remember_geometry(cache_key)

func sample(age: float) -> void:
	var active := maxf(0,age-delay)
	var p := clampf(active/maxf(.08,spread_time),0,1)
	var fade := 1.0 if phase=="flight" else clampf((lifetime-age)/.3,0,1)
	var strength:=fade*(.48 if sustain and active>.8 else .88)
	if art!=null: art.sample(active,strength if age>=delay else 0.0)
	if surface != null:
		surface.set_shader_parameter("age",active)
		surface.set_shader_parameter("opacity",fade*(.27 if sustain and active>.8 else .55 if is_area and phase=="release" else .72))
	if age < delay:
		if surface != null: surface.set_shader_parameter("opacity",.25)
		material.albedo_color = Color(1,1,1,.25)
		scale = Vector3.ONE*.2
		return
	material.albedo_color = Color(1,1,1,fade*(.40 if sustain and active > .8 else .80 if is_area and phase=="release" else 1.0))
	scale = Vector3.ONE
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	match motion:
		"expand": scale = Vector3(lerpf(.15,1,p),1,lerpf(.15,1,p))
		"return": scale = Vector3.ONE*maxf(.1,sin(p*PI))
		"spin", "orbit": rotation.y = active*(1.7 if sustain else 5.0)
		"rise": position.y = minf(.25,active*.4)
		"fall": position.y = maxf(0,.9-active*2)
		"hop": position.y = sin(p*PI)*.3
		"ship": position.z = lerpf(1.4,-.3,p)
		"breathe": scale = Vector3.ONE*(1+sin(active*5)*.04)
		"surge": scale.z = lerpf(.1,1,p)
		"explode": scale = Vector3.ONE*lerpf(.2,1,p)
		"flicker", "flash": material.albedo_color.a *= .72+.28*absf(sin(active*35))
