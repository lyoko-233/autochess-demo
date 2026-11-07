extends Node3D
# Decorative geometry only. Replay age and event dimensions come from the owner.
const RECIPES={
	"taunt_armor":["war_crest",8,0],"heal":["blossom",7,4],
	"critical_knockup":["ice_fist",6,3],"attack_aura":["frost_fletching",5,3],
	"magic_damage":["coin_blades",5,0],"magic_pulse":["gear",12,6],
	"hex":["voodoo",5,5],"missiles":["rocket",3,6],
	"mana_burn":["sever",4,5],"throw":["stone_shards",6,0],
	"bounce_stun":["cask",3,5],"cold_embrace":["ice_wings",8,3],
	"frontal_reduction":["shield_fan",7,0],"mana_drain":["siphon",3,5],
	"mana_pulse":["snowflake",6,3],"call_of_the_wild":["antlers",4,0],
	"spin":["blade_cyclone",3,1],"aoe_burst":["saw_teeth",16,0],
	"line_orb":["fae_orbit",3,5],"random_stun":["chaos_flare",5,1],
	"bounce_attack":["moon_glaives",3,3],"treants":["branches",5,4],
	"waveform":["wave_crests",5,2],"firefly":["ember_wings",6,1],
	"spell_steal":["arcane_scroll",4,4],"disarm":["fate_knots",3,0],
	"multicast":["twin_flames",2,1],"transform_wolves":["wolf_fangs",6,3],
	"plague_wards":["serpent",4,4],"purification":["holy_rays",8,0],
	"powershot":["wind_arrow",4,4],"plasma_field":["electric_wave",7,6],
	"critical":["phantom_cuts",3,5],"shield":["dark_facets",6,5],
	"burrowstrike":["sand_fissure",8,0],"assassinate":["rifle_sight",4,0],
	"poison":["venom_fangs",5,4],"requiem":["soul_rays",18,5],
	"laguna_blade":["solar_lance",5,1],"metamorphosis":["demon_wings",8,5],
	"shallow_grave":["grave_runes",4,5],"hook":["iron_links",9,0],
	"leech_seed":["seed_vines",6,4],"doom":["infernal_brand",3,1],
	"ghostship":["spectral_hull",9,2],"fervor":["axe_sparks",5,0],
	"illuminate":["sun_ribbons",5,0],"death_pulse":["wraith_wave",10,4],
	"refraction":["prism",6,5],"chemical_rage":["alchemical_fumes",9,4],
	"static_storm":["storm_crown",9,6],"stone_gaze":["serpent_eye",7,4],
	"dragon_form":["dragon_scales",8,1],"spirit_bear":["bear_paw",5,4],
	"familiars":["stone_wings",4,5],"stroke_of_fate":["ink_brush",6,7],
	"spiked_carapace":["carapace",10,5],"call_down":["bombardment",4,1],
	"ravage":["sea_tendrils",16,2],"midnight_pulse":["void_tide",5,5],
	"remote_mines":["blast_debris",12,1],"exorcism":["spirit_flock",12,5],
	"gods_strength":["greatsword",3,1],"thundergods_wrath":["sky_forks",7,6],
	"wildcard_combine":["wisp_tethers",3,0],"corrosive_haze":["acid_scales",7,4],
	"scream":["sonic_fans",9,5],"pounce":["shark_jaws",4,2],
	"sacred_arrow":["lunar_arrow",3,3],"chain_frost":["frost_comet",6,3],
	"smoke_screen":["smoke_sheets",7,7]
}
const MONSTER_RECIPES={
	"single_bolt":["chaos_flare",3,6],"shockwave":["stone_shards",8,0],
	"critical_attack":["phantom_cuts",3,0],"opening_leap_and_aura":["wolf_fangs",6,3],
	"pair_aura":["bear_paw",5,4],"opening_leap_and_stun":["stone_wings",4,6],
	"splash_attack":["acid_scales",5,4],"lightning":["sky_forks",7,6],
	"breath":["ember_wings",6,1],"burn":["venom_fangs",5,1],
	"chill":["frost_comet",6,3],"stun_attack":["ice_fist",4,0],
	"stomp":["stone_shards",10,0],"heavy_blow":["greatsword",3,0]
}
static var cache: Dictionary={}
var points:=PackedVector3Array()
var uvs:=PackedVector2Array()
var colors:=PackedColorArray()
var ribbon_material: ShaderMaterial
var mote_material: ShaderMaterial
var ground_material: ShaderMaterial
var motif: String
var seed: float
var element: int
var ribbons: MeshInstance3D
var motes: MultiMeshInstance3D
var phase: String
var use_radius: float
var solid: Node3D

func ribbon(path: Array, width: float, alpha: float=.8) -> void:
	for i in range(path.size()-1):
		var tangent: Vector3=(path[mini(i+1,path.size()-1)]-path[maxi(0,i-1)]).normalized()
		var side: Vector3=tangent.cross(Vector3.UP).normalized()
		if side.length()<.5: side=Vector3.RIGHT
		var t:=float(i)/(path.size()-1)
		var q:=float(i+1)/(path.size()-1)
		var a: Vector3=path[i]; var b: Vector3=path[i+1]
		var wa:=width*(.18+.82*sin(t*PI)); var wb:=width*(.18+.82*sin(q*PI))
		var p: Array=[a-side*wa,a+side*wa,b-side*wb,b+side*wb]
		var tex: Array=[Vector2(t,0),Vector2(t,1),Vector2(q,0),Vector2(q,1)]
		for j in [0,1,2,2,1,3]:
			points.append(p[j]); uvs.append(tex[j]); colors.append(Color(1,1,1,alpha))

func arc(radius: float, y: float, start: float, sweep: float, width: float, waves: float=0) -> void:
	var path: Array=[]
	for j in 25:
		var t:=j/24.0; var a:=start+t*sweep
		path.append(Vector3(sin(a)*radius,y+sin(t*TAU*2)*waves,cos(a)*radius))
	ribbon(path,width)

func radial(count: int, radius: float, height: float, width: float, bend: float=0) -> void:
	for i in count:
		var a:=i*TAU/count
		var path: Array=[]
		for j in 13:
			var t:=j/12.0; var angle:=a+sin(t*PI)*bend
			path.append(Vector3(sin(angle)*radius*t,.08+sin(t*PI)*height,cos(angle)*radius*t))
		ribbon(path,width)

func helix(count: int, radius: float, height: float, turns: float, width: float) -> void:
	for i in count:
		var path: Array=[]
		for j in 25:
			var t:=j/24.0; var a:=t*TAU*turns+i*TAU/count
			path.append(Vector3(sin(a)*radius,t*height+.06,cos(a)*radius))
		ribbon(path,width)

func stream(count: int, length_value: float, spread: float, height: float, width: float, wave: float) -> void:
	for i in count:
		var path: Array=[]
		for j in 25:
			var t:=j/24.0
			path.append(Vector3((float(i)/(count)-.5)*spread+sin(t*TAU+i)*wave,height+sin(t*PI)*wave,-t*length_value))
		ribbon(path,width)

func build(skill: String, tint: Color, context: Dictionary, mode: String, area: bool) -> void:
	assert(RECIPES.has(skill) or MONSTER_RECIPES.has(skill),"Missing authored skill recipe: "+skill)
	var recipe: Array=RECIPES[skill] if RECIPES.has(skill) else MONSTER_RECIPES[skill]
	motif=recipe[0]; var count: int=recipe[1]; element=recipe[2]
	seed=float(RECIPES.keys().find(skill)+1) if RECIPES.has(skill) else float(RECIPES.size()+MONSTER_RECIPES.keys().find(skill)+1)
	phase=mode
	use_radius=maxf(.12,float(context.get("radius",.4))) if area else .42
	var r:=use_radius
	var length_value:=float(context.get("line_length",4))
	var distance_value:=maxf(.1,float(context.get("distance",1)))
	var key: String="%s:%s:%.3f:%.3f:%.3f"%[skill,mode,r,length_value,distance_value]
	if cache.has(key):
		_add_mesh(cache[key])
	else:
		if mode=="flight":
			match motif:
				"frost_comet": helix(3,.15,.28,1.5,.08); radial(6,.29,.10,.06)
				"cask": arc(.19,0,0,TAU,.05); helix(2,.14,.20,1,.045)
				"iron_links": arc(.19,0,.2,PI*1.65,.06); stream(1,.7,0,0,.035,0)
				"rocket": stream(3,-.65,.16,0,.06,.025)
				"lunar_arrow": stream(3,-.85,.24,0,.06,.03); arc(.17,0,0,PI*1.7,.035)
				"fae_orbit": helix(3,.23,.24,1.5,.065)
				"wind_arrow": stream(4,-1.0,.22,0,.06,.06)
				"ink_brush": stream(5,-.85,.28,0,.07,.07)
				"sun_ribbons": stream(5,-.9,.45,0,.08,.06)
				"coin_blades": radial(5,.25,.03,.06,.3)
				"venom_fangs": helix(2,.16,.25,1.5,.07)
				"chaos_flare": radial(5,.25,.1,.07,.5)
				"rifle_sight": stream(1,-1.0,0,0,.065,0)
				_: helix(2,.16,.22,1,.055)
		elif mode=="hit":
			radial(mini(count,8),.32,.22,.045,float(element)*.06)
			arc(.26,.09,seed,PI*1.5,.04)
		else:
			match motif:
				"sea_tendrils":
					for i in count:
						var a:=i*TAU/count; var path: Array=[]
						for j in 17:
							var t:=j/16.0; var reach:=r*(.60+t*.27)
							path.append(Vector3(sin(a+t*.28)*reach,.06+sin(t*PI*.82)*.95,cos(a+t*.28)*reach))
						ribbon(path,.18)
					arc(r*.86,.10,0,TAU,.12,.06)
				"soul_rays": radial(count,r,.6,.13,.12); arc(r*.42,.14,0,TAU,.05)
				"spectral_hull":
					for s in [-1,1]: ribbon([Vector3(0,.2,-1),Vector3(s*.40,.22,-.45),Vector3(s*.43,.25,.50),Vector3(0,.35,.92)],.20)
					for i in 4: ribbon([Vector3(-.42,1.1-i*.16,0),Vector3(0,1.12-i*.17,.15),Vector3(.42,1.05-i*.14,0)],.16,.5)
					stream(4,1.3,1.0,.08,.13,.06)
				"blade_cyclone":
					for i in count: arc(r*(1-i*.14),.2+i*.13,i*2,PI*1.65,.16)
				"electric_wave":
					arc(r,.15,0,TAU,.10,.045); arc(r*.87,.3,1,TAU,.055,.05)
				"void_tide":
					for i in count: arc(r*(.25+i*.14),.04+i*.016,i,TAU*.88,.13,.025)
				"spirit_flock": radial(count,r,.55,.09,.75); helix(2,r*.70,.52,1.5,.07)
				"wave_crests": stream(count,length_value,1.25,.18,.19,.22)
				"wind_arrow": stream(count,length_value,.8,.28,.10,.16)
				"sun_ribbons": stream(count,length_value,1.25,.35,.15,.12)
				"ink_brush": stream(count,length_value,1.1,.055,.15,.20)
				"sand_fissure": stream(2,length_value,.4,.10,.09,.13); radial(count,.36,.18,.08,.15)
				"sky_forks","solar_lance":
					for i in count:
						var path: Array=[]
						for j in 12: path.append(Vector3(sin(j*2.4+i)*(.035+i*.026),2.2-j*.19,cos(j*2.1+i)*.1))
						ribbon(path,.085 if motif=="solar_lance" else .045)
				"storm_crown": radial(count,r,.65,.07,.20); helix(3,r*.74,1.0,1.0,.06)
				"snowflake": radial(6,.62,.09,.05); helix(2,.35,.65,1.0,.045)
				"ice_wings","ember_wings","demon_wings","stone_wings":
					for s in [-1,1]:
						for i in count/2: ribbon([Vector3(s*.12,.5,0),Vector3(s*(.30+i*.11),.85+i*.07,.12),Vector3(s*(.36+i*.12),.38,.20)],.08)
				"frost_fletching": stream(count,.65,.55,.28,.055,.08)
				"frost_comet": radial(6,.38,.25,.055); helix(2,.25,.50,1,.06)
				"ice_fist": radial(count,.40,.8,.09,.05)
				"moon_glaives":
					for i in count: arc(.22+i*.1,.25+i*.08,i,PI*1.3,.08)
				"prism","dark_facets","carapace","dragon_scales","acid_scales":
					radial(count,.44,.70,.075,.15); helix(1,.40,.8,1,.04)
				"blossom": radial(count,.50,.55,.08,.45); helix(2,.30,.8,1.0,.05)
				"branches","seed_vines","serpent": helix(count,.30,.85,1.1,.065)
				"antlers": radial(count,.58,.6,.06,.3)
				"bear_paw": radial(count,.40,.25,.09,.15); arc(.3,.06,0,TAU,.065)
				"war_crest": radial(count,r,.25,.07,.20); arc(r*.65,.18,.2,PI*1.7,.065)
				"shield_fan": arc(.48,.4,-1,PI,.11); radial(3,.4,.3,.05)
				"gear","saw_teeth": radial(count,r,.15,.06,.08); arc(r*.70,.14,0,TAU,.07)
				"siphon": stream(count,distance_value,.2,.45,.055,.09)
				"wisp_tethers": helix(count,.3,.65,1.0,.035)
				"arcane_scroll": helix(count,.36,.75,1.4,.07)
				"fae_orbit": helix(count,.38,.55,1.6,.065)
				"voodoo": helix(count,.28,.70,.8,.06); radial(3,.36,.28,.07,.4)
				"grave_runes": helix(count,.30,1.0,.5,.055)
				"fate_knots": helix(count,.33,.7,2,.045)
				"holy_rays": radial(count,r,.35,.09); helix(2,.25,1.1,.5,.09)
				"wraith_wave": radial(count,r,.25,.11,.5)
				"sonic_fans":
					for i in 3: arc(r*(.5+i*.23),.25+i*.1,i*.3,TAU*.9,.09)
				"smoke_sheets":
					for i in count: arc(r*(.30+i*.08),.12+(i%3)*.15,i,TAU*.7,.24,.08)
				"alchemical_fumes": helix(3,.38,.75,1.3,.11); radial(count,r,.06,.09,.3)
				"serpent_eye": arc(.35,.72,0,TAU,.07); radial(count,r,.06,.035,.2)
				"venom_fangs": helix(2,.26,.72,1.8,.065)
				"infernal_brand": radial(3,.42,.55,.10,.2); helix(2,.29,.85,.7,.08)
				"rocket": stream(3,.6,.30,.35,.06,.01)
				"bombardment": radial(count,r,.06,.07); stream(2,-1.0,.25,1.0,.10,.08)
				"blast_debris": radial(count,r,.65,.10,.1)
				"twin_flames": helix(2,.25,.85,1,.13)
				"chaos_flare": radial(count,.40,.6,.10,.4)
				"stone_shards": radial(count,.40,.65,.075,.05)
				"greatsword": stream(3,-.9,.18,.22,.095,0)
				"wolf_fangs": radial(count,.40,.72,.075,.12)
				"shark_jaws": arc(.35,.26,.2,PI*1.4,.09); arc(.28,.55,PI,PI,.07)
				"phantom_cuts","sever":
					for i in count: ribbon([Vector3(-.38+i*.06,.12,0),Vector3(0,.42+i*.08,.04),Vector3(.34,.70+i*.08,0)],.08)
				"axe_sparks": radial(count,.42,.4,.055,.25)
				"coin_blades": radial(count,.36,.15,.07,.35)
				"iron_links": stream(1,distance_value,0,.38,.04,0)
				"rifle_sight": arc(.36,.4,0,TAU,.035); radial(4,.30,.05,.035)
				"lunar_arrow": stream(3,.8,.28,.4,.06,.02)
				"cask": helix(2,.22,.45,1,.06)
		var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=points; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_COLOR]=colors
		assert(not points.is_empty(),"Empty authored motif: "+motif)
		var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		if cache.size()>=128: cache.erase(cache.keys()[0])
		cache[key]=mesh; _add_mesh(mesh)
	ribbon_material.set_shader_parameter("tint",tint)
	ribbon_material.set_shader_parameter("seed",seed)
	ribbon_material.set_shader_parameter("element",element)
	solid=preload("res://scripts/authored_skill_solid.gd").new()
	add_child(solid)
	solid.build(skill,tint,context,mode)
	if mode!="hit": _motes(tint,mini(18,8+count) if mode!="flight" else 10,r if mode!="flight" else .15)
	if area and mode=="release":
		ground_material=ShaderMaterial.new()
		ground_material.shader=preload("res://assets/ui/materials/skill_ground_detail.gdshader")
		for value in [["tint",tint],["seed",seed],["element",element]]: ground_material.set_shader_parameter(value[0],value[1])
		var field:=MeshInstance3D.new(); var plane:=PlaneMesh.new()
		plane.size=Vector2(r*2,r*2); field.mesh=plane; field.position.y=.022
		field.material_override=ground_material; field.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(field)

func _add_mesh(mesh: Mesh) -> void:
	ribbon_material=ShaderMaterial.new(); ribbon_material.shader=preload("res://assets/ui/materials/skill_filament.gdshader")
	ribbons=MeshInstance3D.new(); ribbons.mesh=mesh; ribbons.material_override=ribbon_material
	ribbons.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(ribbons)

func _motes(tint: Color, count: int, radius: float) -> void:
	mote_material=ShaderMaterial.new(); mote_material.shader=preload("res://assets/ui/materials/skill_motes.gdshader")
	for value in [["tint",tint],["seed",seed],["element",element],["radius",radius*.85],["height",.85],["flight",phase=="flight"]]: mote_material.set_shader_parameter(value[0],value[1])
	var quad:=QuadMesh.new(); quad.size=Vector2(.15,.15) if element!=7 else Vector2(.32,.32)
	var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.use_custom_data=true; multi.mesh=quad; multi.instance_count=count
	for i in count:
		multi.set_instance_transform(i,Transform3D.IDENTITY)
		multi.set_instance_custom_data(i,Color((i+.5)/count,0,0,1))
	motes=MultiMeshInstance3D.new(); motes.multimesh=multi; motes.material_override=mote_material
	motes.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.custom_aabb=AABB(Vector3(-radius-1,-1,-radius-1),Vector3((radius+1)*2,3,(radius+1)*2))
	add_child(motes)

func sample(age: float, opacity: float) -> void:
	if solid:solid.sample(age,opacity)
	ribbon_material.set_shader_parameter("age",age)
	ribbon_material.set_shader_parameter("opacity",opacity)
	if mote_material!=null:
		mote_material.set_shader_parameter("age",age)
		mote_material.set_shader_parameter("opacity",opacity*.8)
	if ground_material!=null:
		ground_material.set_shader_parameter("age",age)
		ground_material.set_shader_parameter("opacity",opacity)
