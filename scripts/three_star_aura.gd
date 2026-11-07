extends Node3D

const Profiles = preload("res://scripts/combat_visual_profiles.gd")
const Effect = preload("res://scripts/combat_effect_3d.gd")

const THEMES := {
	"Axe": [Color(1.0,0.40,0.08),"cast_release"],
	"Phantom Assassin": [Color(0.64,0.39,1.0),"critical_hit"],
	"Tidehunter": [Color(0.15,0.75,0.85),"cast_release"],
	"Sniper": [Color(0.90,0.65,0.28),"cast_release"],
	"Crystal Maiden": [Color(0.45,0.75,1.0),"mana_pulse"]}
static var materials: Dictionary = {}
var piece: Node3D
var color: Color
var trigger: String
var dots: Array[MeshInstance3D] = []
var pulse: Node3D
var world_scale: float
var attack_fallback := false
var last_elapsed := -100.0
var last_pulse := -100.0
var ambient_form := "mote"
var preparation_time := 0.0
var body_glints: MultiMeshInstance3D
var veil: MeshInstance3D
var veil_material: ShaderMaterial
var skin_material: ShaderMaterial
var signature: Node3D

const BodyMesh=preload("res://scripts/star_body_mesh.gd")
const BODY_JOINTS=BodyMesh.JOINTS
static var body_meshes: Dictionary = {}

func _body_effects() -> void:
	if piece.rig.has_meta("skinned_pilot") or piece.rig.has_meta("authored_skeletal"):
		skin_material=ShaderMaterial.new()
		skin_material.shader=preload("res://assets/ui/materials/pilot_star_skin.gdshader")
		skin_material.set_shader_parameter("tint",color)
		skin_material.set_shader_parameter("family",maxi(0,THEMES.keys().find(piece.piece_id)) if THEMES.has(piece.piece_id) else {"ember":0,"rune":1,"leaf":2,"spark":3,"crystal":4}.get(ambient_form,2))
		for mesh in piece.rig.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree(): continue
			mesh.material_overlay=skin_material
			mesh.set_meta("star_overlay",skin_material)
		return
	body_glints=MultiMeshInstance3D.new()
	body_glints.name="BodyGlints"
	body_glints.multimesh=MultiMesh.new()
	body_glints.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	body_glints.multimesh.mesh=dots[0].mesh
	body_glints.multimesh.instance_count=6
	body_glints.material_override=materials[piece.piece_id]
	body_glints.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body_glints)
	var key: String="%s:%d:%s:%s"%[piece.piece_id,piece.star,piece.form,piece.rig.scene_file_path]
	if not body_meshes.has(key):
		if body_meshes.size()>=32: body_meshes.clear()
		body_meshes[key]=piece.rig.get_meta("star_body_surface") if piece.rig.has_meta("star_body_surface") else BodyMesh.build(piece.rig)
	veil=MeshInstance3D.new()
	veil.name="BodyVeil"
	veil.mesh=body_meshes[key]
	# Animated vertices can move outside the unposed merged AABB.
	var extent:=3.5/world_scale
	veil.custom_aabb=AABB(Vector3.ONE*-extent,Vector3.ONE*extent*2)
	veil_material=ShaderMaterial.new()
	veil_material.shader=preload("res://assets/ui/materials/star_body_surface.gdshader")
	veil_material.set_shader_parameter("tint",color)
	veil_material.set_shader_parameter("family",1 if ambient_form=="ember" else 3 if ambient_form=="crystal" else 4 if ambient_form=="leaf" else 6 if ambient_form=="spark" else 5 if ambient_form=="rune" else 2)
	veil_material.set_shader_parameter("shell_width",.006/world_scale)
	veil.material_override=veil_material
	veil.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(veil)

func _sample_body(elapsed: float, strength: float) -> void:
	if skin_material!=null:
		skin_material.set_shader_parameter("age",elapsed)
		skin_material.set_shader_parameter("strength",strength)
		return
	var height:=float(piece.get_meta("head_height"))/world_scale
	var anchors: Array[Vector3]=[piece.to_local(piece.rig.global_position)+Vector3(0,height*.82,.12/world_scale),piece.to_local(piece.rig.global_position)+Vector3(0,height*.49,.20/world_scale)]
	for path in ["LeftArmPivot","RightArmPivot","LeftLegPivot","RightLegPivot"]:
		var joint: Node3D=piece.rig.get_node(path)
		anchors.append(piece.to_local(joint.global_position)+Vector3(0,-.09/world_scale,.075/world_scale))
	for i in anchors.size():
		var angle:=elapsed*.65+i*1.9
		var at: Vector3=anchors[i]+Vector3(cos(angle)*.012,sin(angle*1.3)*.020,sin(angle)*.010)/piece.scale
		body_glints.multimesh.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3.ONE*(.85+strength*.65)),at))
	for j in BODY_JOINTS.size():
		if j>0 and not piece.rig.has_node(BODY_JOINTS[j]): continue
		var joint: Node3D=piece.rig if j==0 else piece.rig.get_node(BODY_JOINTS[j])
		veil_material.set_shader_parameter("pose%d"%j,piece.global_transform.affine_inverse()*joint.global_transform)
	veil_material.set_shader_parameter("age",elapsed)
	veil_material.set_shader_parameter("strength",strength)


func _process(delta: float) -> void:
	# Preparation has no replay clock; combat is sampled exclusively by board.sync.
	if not piece.has_meta("battle_clip"):
		preparation_time += delta
		update({},preparation_time,true)

func setup(owner_piece: Node3D) -> void:
	piece=owner_piece
	name="StarAura"
	var profile := Profiles.get_profile(piece.piece_id)
	color = THEMES[piece.piece_id][0] if THEMES.has(piece.piece_id) else Profiles.tint(piece.piece_id)
	trigger = str(profile.trigger)
	ambient_form = "rune" if piece.piece_id=="Phantom Assassin" else str(profile.ambient)
	attack_fallback = trigger == "attack"
	world_scale=piece.scale.y
	if not materials.has(piece.piece_id):
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color=Color(color,0.32)
		material.emission_enabled=true
		material.emission=color
		material.emission_energy_multiplier=0.30
		materials[piece.piece_id]=material
	for index in 3:
		var dot:=MeshInstance3D.new()
		if ambient_form in ["crystal","ember","spark"]:
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0
			mesh.bottom_radius = .016/world_scale
			mesh.height = .035/world_scale
			mesh.radial_segments = 4 if ambient_form == "crystal" else 5
			dot.mesh = mesh
		elif ambient_form == "rune":
			var mesh := TorusMesh.new()
			mesh.inner_radius = .011/world_scale
			mesh.outer_radius = .019/world_scale
			mesh.rings = 12
			mesh.ring_segments = 4
			dot.mesh = mesh
		else:
			var mesh:=SphereMesh.new()
			mesh.radius=.019/world_scale
			mesh.height=mesh.radius*(.65 if ambient_form == "leaf" else 2)
			mesh.radial_segments=8
			mesh.rings=4
			dot.mesh=mesh
		dot.material_override=materials[piece.piece_id]
		dot.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dot)
		dots.append(dot)
	_body_effects()
	if piece.rig.has_meta("skinned_pilot"):
		signature=preload("res://scripts/pilot_star_signature.gd").new()
		add_child(signature)
		signature.setup(piece.piece_id,color,world_scale)
	elif preload("res://scripts/roster_star_signature.gd").DESIGNS.has(piece.piece_id):
		signature=preload("res://scripts/roster_star_signature.gd").new()
		add_child(signature)
		signature.setup(piece.piece_id,color,world_scale)
	pulse=Effect.new()
	pulse.name="ReleasePulse"
	pulse.setup("star_" + ambient_form, Color(color,.45), .22)
	pulse.visible=false
	add_child(pulse)
	update({},0.0,true)

func update(state: Dictionary, elapsed: float, alive: bool) -> void:
	visible=alive
	if not alive:
		pulse.visible=false
		return
	var weapon: Node3D=piece.rig.get_node("WeaponPivot")
	var anchor:=piece.to_local(weapon.global_position)
	if piece.rig.has_meta("muzzle_node_path"):anchor=piece.to_local(piece.rig.get_node(piece.rig.get_meta("muzzle_node_path")).global_position)
	elif weapon.has_node("Muzzle"): anchor=piece.to_local(weapon.get_node("Muzzle").global_position)
	elif weapon.has_node("BladeTip"): anchor=piece.to_local(weapon.get_node("BladeTip").global_position)
	else: anchor.y+=.30/world_scale
	if elapsed<last_elapsed:
		last_pulse=-100.0
	last_elapsed=elapsed
	var event: Dictionary = state.get(trigger,{})
	if attack_fallback: event=state.get("attack_release",event)
	var released: float = float(event.get("release_time",-100.0)) if attack_fallback else float(event.get("time",-100.0))
	if elapsed >= released and released-last_pulse >= 2.0 and (not attack_fallback or bool(event.get("released",false))):
		last_pulse = released
	var age := elapsed-last_pulse
	var strength:=1.0-age/.35 if age>=0.0 and age<.35 else 0.0
	_sample_body(elapsed,strength)
	if signature!=null:
		signature.position=anchor
		signature.sample(elapsed,strength)
	for index in dots.size():
		var angle:=elapsed*.8+index*TAU/3.0
		dots[index].position=anchor+Vector3(cos(angle)*.065,.025*sin(angle*1.7),sin(angle)*.045)/piece.scale
		if ambient_form == "ember": dots[index].position.y += fposmod(elapsed*.025+index*.02,.065)/world_scale
		dots[index].scale=Vector3(world_scale/piece.scale.x,1.0,world_scale/piece.scale.z)*(1.0+strength*.7)
	pulse.visible=strength>0
	if pulse.visible:
		pulse.position = Vector3.ZERO
		pulse.scale = Vector3.ONE
		pulse.sample(age)
		pulse.position += anchor
		pulse.scale /= piece.scale
