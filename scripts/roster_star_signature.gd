extends Node3D

const DESIGNS := {
	"Enchantress":["leaf",5],"Tusk":["ice",3],"Drow Ranger":["feather",3],"Bounty Hunter":["blade",2],
	"Clockwerk":["gear",3],"Shadow Shaman":["serpent",2],"Tinker":["cube",4],"Anti-Mage":["arc",2],
	"Tiny":["shard",4],"Witch Doctor":["soul",3],"Winter Wyvern":["ice",6],"Mars":["star",3],
	"Lion":["spine",5],"Beastmaster":["paw",2],"Juggernaut":["blade",5],"Timbersaw":["gear",5],
	"Puck":["butterfly",3],"Chaos Knight":["flame",3],"Luna":["arc",3],"Nature's Prophet":["leaf",6],
	"Morphling":["wave",4],"Batrider":["flame",5],"Rubick":["cube",3],"Oracle":["star",5],
	"Ogre Magi":["flame",2],"Lycan":["paw",3],"Venomancer":["drop",5],"Omniknight":["cross",3],
	"Razor":["lightning",4],"Windranger":["feather",5],"Abaddon":["soul",2],"Sand King":["shard",6],
	"Viper":["drop",3],"Shadow Fiend":["soul",6],"Lina":["flame",6],"Terrorblade":["blade",4],
	"Dazzle":["cross",5],"Pudge":["hook",3],"Treant Protector":["leaf",4],"Doom":["spine",3],
	"Kunkka":["wave",3],"Troll Warlord":["blade",3],"Keeper of the Light":["star",6],"Necrophos":["soul",4],
	"Templar Assassin":["rune",4],"Alchemist":["drop",4],"Disruptor":["lightning",3],"Medusa":["serpent",3],
	"Dragon Knight":["scale",5],"Lone Druid":["paw",4],"Visage":["feather",4],"Grimstroke":["ink",3],
	"Nyx Assassin":["spine",6],"Gyrocopter":["gear",4],"Enigma":["arc",5],"Techies":["spark",5],
	"Death Prophet":["soul",5],"Sven":["blade",6],"Zeus":["lightning",6],"Io":["orb",4],
	"Slardar":["wave",5],"Queen of Pain":["hook",4],"Slark":["hook",2],"Mirana":["feather",6],
	"Lich":["ice",4],"Riki":["ink",4]}

var motif: String
var instances: MultiMeshInstance3D
var material: StandardMaterial3D
var seed: float
var factor: float
var count: int
var description: String
static var meshes: Dictionary = {}

func _polygon(points: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(PackedVector2Array(points))
	assert(not indices.is_empty(),"Signature motif must triangulate")
	for index in indices:
		var p: Vector2=points[index]
		surface.set_normal(Vector3(0,0,1))
		surface.add_vertex(Vector3(p.x,p.y,0))
	return surface.commit()

func _shape() -> Mesh:
	if motif=="cube":
		var mesh := BoxMesh.new(); mesh.size=Vector3.ONE*.8; return mesh
	if motif=="orb":
		var mesh := SphereMesh.new(); mesh.radius=.45; mesh.height=.9; mesh.radial_segments=12; mesh.rings=6; return mesh
	var points: Array=[]
	match motif:
		"leaf": points=[Vector2(0,-.65),Vector2(-.3,-.15),Vector2(-.28,.2),Vector2(.1,.7),Vector2(.35,.15)]
		"flame": points=[Vector2(-.3,-.5),Vector2(-.4,0),Vector2(-.1,.75),Vector2(.04,.1),Vector2(.3,.45),Vector2(.42,-.1),Vector2(.2,-.5)]
		"ice": points=[Vector2(-.42,-.5),Vector2(-.4,.3),Vector2(-.15,.12),Vector2(0,.85),Vector2(.2,.2),Vector2(.42,.45),Vector2(.4,-.5)]
		"feather": points=[Vector2(-.2,-.7),Vector2(-.35,.1),Vector2(-.05,.8),Vector2(.25,.45),Vector2(.18,.05),Vector2(.04,-.1)]
		"lightning": points=[Vector2(-.1,.8),Vector2(-.4,0),Vector2(-.03,.05),Vector2(-.2,-.8),Vector2(.4,.15),Vector2(.02,.1)]
		"blade": points=[Vector2(-.12,-.7),Vector2(-.3,.1),Vector2(.2,.9),Vector2(.33,.5),Vector2(.09,-.7)]
		"spine","shard": points=[Vector2(-.25,-.6),Vector2(-.3,.25),Vector2(.04,1),Vector2(.3,-.25),Vector2(.2,-.6)]
		"drop":
			for i in 12:
				var a:=i*TAU/12; points.append(Vector2(cos(a)*.40,sin(a)*.50+.32*pow(maxf(0,sin(a)),4)))
		"cross": points=[Vector2(-.12,-.6),Vector2(.12,-.6),Vector2(.12,-.12),Vector2(.5,-.12),Vector2(.5,.12),Vector2(.12,.12),Vector2(.12,.6),Vector2(-.12,.6),Vector2(-.12,.12),Vector2(-.5,.12),Vector2(-.5,-.12),Vector2(-.12,-.12)]
		"soul": points=[Vector2(-.35,-.6),Vector2(-.1,-.35),Vector2(.05,-.65),Vector2(.22,-.35),Vector2(.4,-.6),Vector2(.4,.3),Vector2(.18,.6),Vector2(-.18,.6),Vector2(-.4,.3)]
		"ink": points=[Vector2(-.35,-.7),Vector2(-.12,.5),Vector2(.3,.85),Vector2(.18,.25),Vector2(.42,.2),Vector2(.12,-.6)]
		"butterfly": points=[Vector2(0,-.4),Vector2(-.5,-.55),Vector2(-.65,-.1),Vector2(-.55,.65),Vector2(-.1,.25),Vector2(0,.6),Vector2(.1,.25),Vector2(.55,.65),Vector2(.65,-.1),Vector2(.5,-.55)]
		"paw": points=[Vector2(-.3,-.5),Vector2(-.55,-.05),Vector2(-.4,.45),Vector2(-.22,.2),Vector2(-.2,.7),Vector2(0,.75),Vector2(.16,.2),Vector2(.34,.6),Vector2(.5,.4),Vector2(.32,0),Vector2(.4,-.5)]
		"scale": points=[Vector2(0,-.7),Vector2(-.5,0),Vector2(-.3,.5),Vector2(.3,.5),Vector2(.5,0)]
		"wave","serpent","hook","arc":
			for i in 14:
				var a:float=-.6+i*4.6/13; points.append(Vector2(cos(a),sin(a))*.65)
			for i in range(13,-1,-1):
				var a:float=-.6+i*4.6/13; points.append(Vector2(cos(a),sin(a))*(.40 if motif=="arc" else .49))
		_:
			var teeth:=12 if motif=="gear" else 8 if motif in ["star","spark"] else 4
			for i in teeth*2:
				var a:=i*PI/teeth; var radius:=.7 if i%2==0 else .37
				points.append(Vector2(cos(a),sin(a))*radius)
	return _polygon(points)

func setup(id: String, color: Color, fitted_scale: float) -> void:
	name="RosterSignature"
	motif=DESIGNS[id][0]; count=DESIGNS[id][1]; factor=fitted_scale
	seed=float(DESIGNS.keys().find(id))/66.0
	description=str(preload("res://scripts/combat_visual_profiles.gd").get_profile(id).signature)
	material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(color,.14)
	material.emission_enabled=true; material.emission=color
	instances=MultiMeshInstance3D.new()
	instances.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instances.material_override=material
	instances.multimesh=MultiMesh.new()
	instances.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	if not meshes.has(motif): meshes[motif]=_shape()
	instances.multimesh.mesh=meshes[motif]
	instances.multimesh.instance_count=count
	add_child(instances)
	sample(0,0)

func sample(age: float, strength: float) -> void:
	material.albedo_color.a=.10+strength*.52
	material.emission_energy_multiplier=.18+strength*.65
	for i in count:
		var angle:=i*TAU/count+seed*TAU
		var radius:float=.055+strength*.025
		var at:=Vector3(cos(angle)*radius,sin(angle)*radius,0)/factor
		var rotation:=seed*PI+i*.35
		if motif in ["flame","soul","drop","ink","spark"]:
			at.y+=fposmod(age*(.025+seed*.015)+i*.02,.07)/factor
		elif motif in ["arc","wave","gear","cube","orb","serpent"]:
			rotation+=age*(.25+seed*.30)
		elif motif in ["blade","feather","lightning"]:
			at.z+=sin(age+i)*.015/factor
		var size:float=(.030+seed*.012)*(1+strength*.8)/factor
		var basis:=Basis(Vector3(0,0,1),rotation).scaled(Vector3.ONE*size)
		instances.multimesh.set_instance_transform(i,Transform3D(basis,at))
