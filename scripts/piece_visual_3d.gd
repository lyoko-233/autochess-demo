extends Node3D

@export var piece_id := "Axe"
@export_range(1, 3) var star := 1
@export var monster := false
@export var form := ""
@export var use_runtime := false

var rig: Node3D
var weapon_pivot: Node3D
var animation_player: AnimationPlayer
var promotion_player: AnimationPlayer
static var visual_content: Dictionary = {}
static var roster_scenes: Dictionary = {}
static var scene_cache: Dictionary = {}

const PILOT_SCENES := {"Axe": "axe", "Phantom Assassin": "phantom_assassin", "Tidehunter": "tidehunter",
	"Sniper": "sniper", "Crystal Maiden": "crystal_maiden"}


func _ready() -> void:
	build()

func _exit_tree() -> void:
	# Detach render proxies before cached geometry is released during scene teardown.
	if rig == null: return
	for mesh in rig.find_children("*","MeshInstance3D",true,false):
		if not bool(mesh.get_meta("render_proxy",false)): continue
		mesh.material_overlay = null
		mesh.material_override = null
		mesh.mesh = null


func _box(name_value: String, parent: Node3D, size_value: Vector3, offset: Vector3, color_value: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	var mesh := BoxMesh.new()
	mesh.size = size_value
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.metallic = 0.3
	material.roughness = 0.55
	instance.material_override = material
	instance.position = offset
	parent.add_child(instance)
	return instance


func _sphere(name_value: String, parent: Node3D, radius: float, offset: Vector3, color_value: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.metallic = 0.15
	instance.material_override = material
	instance.position = offset
	parent.add_child(instance)
	return instance


func build() -> void:
	for child in get_children(): child.queue_free()
	if visual_content.is_empty():
		var file := FileAccess.open("res://data/content.json", FileAccess.READ)
		if file == null: return
		visual_content = JSON.parse_string(file.get_as_text())
	var content: Dictionary = visual_content
	var definition: Dictionary = {}
	for candidate in content["monsters" if monster else "units"]:
		if str(candidate["id" if monster else "name_en"]) == piece_id:
			definition = candidate
			break
	if definition.is_empty(): definition = {"cost": 1}
	if roster_scenes.is_empty():
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/roster/visual_catalog.json"))
		for kind in ["units","monsters"]:
			for entry in catalog[kind]:
				roster_scenes[entry.id] = "res://assets/models/roster/%s/%s.tscn" % ["monsters" if kind=="monsters" else "heroes",entry.slug]
	var model_path: String = "res://assets/models/pilots/%s.tscn" % PILOT_SCENES[piece_id] if not monster and PILOT_SCENES.has(piece_id) else str(roster_scenes.get(piece_id,""))
	if not form.is_empty(): model_path = "res://assets/models/forms/%s_%d.tscn"%[form,star]
	if not model_path.is_empty():
		var runtime_path := "res://assets/models/runtime/%s_%d.scn"%[model_path.get_file().get_basename(),star]
		var blender_path := "res://assets/models/blender/%s_%d.scn"%[model_path.get_file().get_basename(),star]
		if ResourceLoader.exists(blender_path) and not "--authoring-models" in OS.get_cmdline_user_args(): model_path=blender_path
		var baked := use_runtime and ResourceLoader.exists(runtime_path) and FileAccess.get_modified_time(model_path)<=FileAccess.get_modified_time(runtime_path) and not "--authoring-models" in OS.get_cmdline_user_args()
		if baked: model_path=runtime_path
		if not scene_cache.has(model_path): scene_cache[model_path]=load(model_path)
		rig = scene_cache[model_path].instantiate()
		add_child(rig)
		weapon_pivot = rig.get_node("WeaponPivot")
		if rig.has_meta("skinned_pilot"):
			var grips: Dictionary={"Axe":Vector3(.56,.86,.11),"Phantom Assassin":Vector3(.52,.96,.12),"Tidehunter":Vector3(1.01,.80,.12),"Sniper":Vector3(.34,1.03,.27),"Crystal Maiden":Vector3(.51,.96,.12)}
			set_meta("skin_grip_rest",grips[piece_id])
			set_meta("weapon_grip_local",weapon_pivot.transform.affine_inverse()*grips[piece_id])
		if not baked and not rig.has_meta("blender_asset"): weapon_pivot.scale = Vector3.ONE * (1.0 if piece_id == "Axe" and rig.has_meta("axe_art_sample") else 1.0 + 0.08 * (star - 1))
		for node in rig.find_children("*", "MeshInstance3D", true, false):
			if baked: continue
			node.visible = star >= int(node.get_meta("min_star", 1)) and star <= int(node.get_meta("max_star", 3))
			if star == 3 and not rig.has_meta("blender_asset") and bool(node.get_meta("star_metal", false)):
				node.material_override = load("res://assets/models/pilots/materials/gold.tres")
			if str(node.name).begins_with("Brow") and node.mesh is CapsuleMesh:
				node.rotation.z = signf(node.rotation.z) * [1.48,1.27,1.10][star-1]
		_build_animations()
		return
	var code: int = abs(piece_id.hash())
	var accent := Color.from_hsv(float(code % 360) / 360.0, 0.52, 0.8)
	match piece_id:
		"Axe": accent = Color(0.72, 0.18, 0.14)
		"Phantom Assassin": accent = Color(0.38, 0.25, 0.58)
		"Tidehunter": accent = Color(0.12, 0.56, 0.50)
	var dark := accent.darkened(0.38)
	var metal := Color(0.56, 0.61, 0.67) if star == 1 else Color(0.75, 0.77, 0.82) if star == 2 else Color(0.95, 0.72, 0.27)
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var height := 1.0 + 0.08 * int(definition.get("cost", 2)) + 0.12 * (star - 1)
	_box("Body", rig, Vector3(1.0 if piece_id == "Tidehunter" else 0.62 if piece_id == "Phantom Assassin" else 0.75,
		height, 0.48), Vector3(0, 0.55 + height / 2, 0), accent)
	_sphere("Head", rig, 0.34 + 0.025 * star, Vector3(0, 0.7 + height, 0), metal)
	_box("LeftLeg", rig, Vector3(0.2, 0.58, 0.24), Vector3(-0.22, 0.30, 0), dark)
	_box("RightLeg", rig, Vector3(0.2, 0.58, 0.24), Vector3(0.22, 0.30, 0), dark)
	_box("LeftArm", rig, Vector3(0.2, 0.68, 0.24), Vector3(-0.48, 0.7 + height * 0.45, 0), dark)
	_box("RightArm", rig, Vector3(0.2, 0.68, 0.24), Vector3(0.48, 0.7 + height * 0.45, 0), dark)
	if code % 3 == 0:
		_box("Helm", rig, Vector3(0.7, 0.18, 0.68), Vector3(0, 1.1 + height, 0), dark)
	elif code % 3 == 1:
		_sphere("Crest", rig, 0.18, Vector3(0, 1.1 + height, 0), accent.lightened(0.2))
	else:
		_box("Horns", rig, Vector3(0.9, 0.16, 0.18), Vector3(0, 1.04 + height, 0), dark)
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.58, 0.85 + height * 0.45, 0)
	rig.add_child(weapon_pivot)
	var weapon_length := 0.7 + 0.23 * star
	_box("WeaponShaft", weapon_pivot, Vector3(0.11, weapon_length, 0.11), Vector3(0, weapon_length * 0.35, 0), dark)
	var weapon_style := 0 if piece_id == "Axe" else 1 if piece_id == "Phantom Assassin" else 2 if piece_id == "Tidehunter" else code % 4
	if weapon_style == 0:
		_box("WeaponHead", weapon_pivot, Vector3(0.55 + 0.1 * star, 0.26, 0.2), Vector3(0, weapon_length * 0.85, 0), metal)
	elif weapon_style == 1:
		_box("WeaponHead", weapon_pivot, Vector3(0.16, 0.38 + 0.12 * star, 0.16), Vector3(0, weapon_length * 0.9, 0), metal)
	elif weapon_style == 2:
		_sphere("WeaponHead", weapon_pivot, 0.15 + 0.05 * star, Vector3(0, weapon_length * 0.85, 0), metal)
	else:
		_box("WeaponHead", weapon_pivot, Vector3(0.28 + 0.08 * star, 0.24, 0.26), Vector3(0, weapon_length * 0.9, 0), metal)
	if star >= 2:
		_box("StarArmor", rig, Vector3(1.05 + 0.07 * star, 0.25, 0.65), Vector3(0, 0.55 + height * 0.8, 0), metal)
	if star == 3:
		_sphere("StarEmblem", rig, 0.16, Vector3(0, 1.12 + height, -0.28), accent.lightened(0.3))
	_build_animations()


func _track(animation: Animation, path: NodePath, keys: Array) -> void:
	var index := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(index, path)
	for key in keys:
		animation.track_insert_key(index, key[0], key[1])

func sync_skin_weapon() -> void:
	if not rig.has_meta("skinned_pilot"): return
	var skeleton: Skeleton3D=rig.get_node(rig.get_meta("skeleton_path"))
	var bone:=skeleton.find_bone("ForearmR")
	skeleton.force_update_all_bone_transforms()
	var point: Vector3=get_meta("skin_grip_rest")
	var rest_point:=skeleton.to_local(rig.to_global(point))
	var posed: Vector3=skeleton.get_bone_global_pose(bone)*(skeleton.get_bone_global_rest(bone).affine_inverse()*rest_point)
	var target:=rig.to_local(skeleton.to_global(posed))
	weapon_pivot.position=target-weapon_pivot.basis*Vector3(get_meta("weapon_grip_local"))


func _clip(name_value: String, duration: float, looped: bool, position_keys: Array, weapon_keys: Array) -> Animation:
	var animation := Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	_track(animation, NodePath("Rig:position"), position_keys)
	_track(animation, NodePath("Rig/WeaponPivot:rotation"), weapon_keys)
	return animation


func _build_animations() -> void:
	if rig.has_meta("authored_skeletal"):
		var style: String=rig.get_meta("motion_profile",{}).get("attack_style","")
		if style in ["bite","breath","orb"]:
			var muzzle: Node3D=rig.get_node(rig.get_meta("muzzle_node_path"))
			var attachment: BoneAttachment3D=muzzle.get_parent()
			var skeleton: Skeleton3D=attachment.get_parent()
			attachment.bone_name="Chest" if style=="orb" else "HeadPivot" if skeleton.find_bone("HeadPivot")>=0 else "Head"
			muzzle.position=Vector3.ZERO if style=="orb" else Vector3(0,0,-.12)
		animation_player = rig.find_children("*", "AnimationPlayer", true, false)[0]
		for clip in ["idle", "walk"]:
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		if animation_player.has_animation("ascension"):
			promotion_player = AnimationPlayer.new()
			promotion_player.name = "PromotionPlayer"
			animation_player.get_parent().add_child(promotion_player)
			promotion_player.root_node = animation_player.root_node
			var effects := AnimationLibrary.new()
			effects.add_animation("ascension", animation_player.get_animation("ascension"))
			promotion_player.add_animation_library("", effects)
		animation_player.play("idle")
		return
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	add_child(animation_player)
	animation_player.root_node = NodePath("..")
	if not form.is_empty():
		var form_library: AnimationLibrary=load("res://assets/models/forms/%s_%d_animations.tres"%[form,star]).duplicate(true)
		_scale_root_translation(form_library,true)
		animation_player.add_animation_library("",form_library)
		animation_player.play("idle")
		return
	if not monster and PILOT_SCENES.has(piece_id):
		var path := "res://assets/models/pilots/animations/%s.tres" % PILOT_SCENES[piece_id]
		if ResourceLoader.exists(path):
			var library: AnimationLibrary=load(path)
			if rig.has_meta("skinned_pilot"):
				library=preload("res://scripts/pilot_skeletal_animation.gd").build(rig,library,piece_id)
			animation_player.add_animation_library("",library)
			animation_player.play("idle")
			return
	var library := AnimationLibrary.new()
	library.add_animation("idle", _clip("idle", 1.4, true,
		[[0.0, Vector3.ZERO], [0.7, Vector3(0, 0.08, 0)], [1.4, Vector3.ZERO]],
		[[0.0, Vector3.ZERO], [1.4, Vector3.ZERO]]))
	library.add_animation("walk", _clip("walk", 0.7, true,
		[[0.0, Vector3.ZERO], [0.35, Vector3(0, 0.12, 0)], [0.7, Vector3.ZERO]],
		[[0.0, Vector3(0, 0, -0.22)], [0.35, Vector3(0, 0, 0.22)], [0.7, Vector3(0, 0, -0.22)]]))
	library.add_animation("attack", _clip("attack", 0.65, false,
		[[0.0, Vector3.ZERO], [0.3, Vector3(0, 0, -0.12)], [0.65, Vector3.ZERO]],
		[[0.0, Vector3.ZERO], [0.3, Vector3(0, 0, -1.1)], [0.65, Vector3.ZERO]]))
	library.add_animation("cast", _clip("cast", 0.8, false,
		[[0.0, Vector3.ZERO], [0.4, Vector3(0, 0.15, 0)], [0.8, Vector3.ZERO]],
		[[0.0, Vector3.ZERO], [0.4, Vector3(0, 0, 1.3)], [0.8, Vector3.ZERO]]))
	library.add_animation("hit", _clip("hit", 0.45, false,
		[[0.0, Vector3.ZERO], [0.15, Vector3(0, 0, 0.22)], [0.45, Vector3.ZERO]],
		[[0.0, Vector3.ZERO], [0.45, Vector3.ZERO]]))
	library.add_animation("die", _clip("die", 0.95, false,
		[[0.0, Vector3.ZERO], [0.95, Vector3(0, -0.55, 0)]],
		[[0.0, Vector3.ZERO], [0.95, Vector3(0, 0, -1.5)]]))
	if PILOT_SCENES.has(piece_id) or roster_scenes.has(piece_id): _pilot_joints(library)
	_scale_root_translation(library)
	animation_player.add_animation_library("", library)
	animation_player.play("idle")


func play_promotion() -> void:
	if star!=3:return
	var accent=preload("res://scripts/promotion_accent_3d.gd").new()
	add_child(accent)
	accent.configure(preload("res://scripts/combat_visual_profiles.gd").tint(piece_id),float(get_meta("fitted_width",.82)),float(get_meta("head_height",.8))*.85)
	if promotion_player != null:
		var ascending=rig.find_children("*AscensionMotif*","MeshInstance3D",true,false)
		for effect in ascending:effect.show()
		promotion_player.play("ascension")
		var tween=create_tween()
		tween.tween_interval(promotion_player.get_animation("ascension").length)
		tween.tween_callback(func():
			for effect in ascending:
				if is_instance_valid(effect):effect.hide())


func _scale_root_translation(library: AnimationLibrary, scale_track: bool = false) -> void:
	if not rig.has_meta("authored_translation_scale"): return
	var factor: float=rig.get_meta("authored_translation_scale")
	var rest_position := rig.position
	for clip in library.get_animation_list():
		var animation:=library.get_animation(clip)
		for track in animation.get_track_count():
			var path := str(animation.track_get_path(track))
			if path != "Rig:position" and not (scale_track and path == "Rig:scale"): continue
			for key in animation.track_get_key_count(track):
				var value: Vector3=animation.track_get_key_value(track,key)*factor
				animation.track_set_key_value(track,key,value+rest_position if path=="Rig:position" else value)


func _pilot_joints(library: AnimationLibrary) -> void:
	for clip in library.get_animation_list():
		var animation := library.get_animation(clip)
		var duration := animation.length
		var peak := 0.4 if clip == "cast" else 0.3 if clip == "attack" else duration * 0.5
		var rotation := Vector3.ZERO
		if clip == "cast" and piece_id == "Axe": rotation.y = TAU
		elif clip == "attack": rotation.y = -0.08 if piece_id == "Sniper" else -0.38
		elif clip == "hit": rotation.x = -0.18
		elif clip == "die": rotation.x = 1.45
		_track(animation, NodePath("Rig:rotation"), [[0.0,Vector3.ZERO],[peak,rotation],[duration,rotation if clip == "die" or (clip == "cast" and piece_id == "Axe") else Vector3.ZERO]])
		var rest: Vector3=rig.scale
		_track(animation, NodePath("Rig:scale"), [[0.0,rest],[peak,rest * (1.06 if clip == "cast" and piece_id == "Tidehunter" else 1.0)],[duration,rest]])
		for side in [-1,1]:
			var arm_path := NodePath("Rig/%sArmPivot:rotation" % ("Left" if side < 0 else "Right"))
			var leg_path := NodePath("Rig/%sLegPivot:rotation" % ("Left" if side < 0 else "Right"))
			if clip == "walk":
				_track(animation,arm_path,[[0.0,Vector3(side*0.25,0,0)],[0.35,Vector3(-side*0.25,0,0)],[duration,Vector3(side*0.25,0,0)]])
				_track(animation,leg_path,[[0.0,Vector3(-side*0.38,0,0)],[0.35,Vector3(side*0.38,0,0)],[duration,Vector3(-side*0.38,0,0)]])
			else:
				var arm := Vector3(-0.80,0,side*0.20) if clip in ["attack","cast"] else Vector3(0,0,side*0.12) if clip == "idle" else Vector3.ZERO
				_track(animation,arm_path,[[0.0,Vector3.ZERO],[peak,arm],[duration,Vector3.ZERO]])
				_track(animation,leg_path,[[0.0,Vector3.ZERO],[duration,Vector3.ZERO]])
		# Quadrupeds use the four root pivots; mounted riders have their own arm joints.
		if rig.has_node("Rider"):
			for side in [-1,1]:
				var path := NodePath("Rig/Rider/%sArmPivot:rotation" % ("Left" if side<0 else "Right"))
				_track(animation,path,[[0.0,Vector3.ZERO],[peak,Vector3(-.65,0,side*.12) if clip in ["attack","cast"] else Vector3.ZERO],[duration,Vector3.ZERO]])
