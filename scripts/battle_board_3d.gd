extends Node3D

const Piece = preload("res://scripts/piece_visual_3d.gd")
const CONTACT_SHADOW = preload("res://assets/ui/materials/contact_shadow.tres")
const VisualState = preload("res://scripts/battle_visual_state.gd")
const STAR_WIDTHS := [0.28, 0.52, 0.82]
var size_policy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/visual_size_policy.json"))
const STAR_HEIGHTS := [0.90, 1.30, 2.0]
const Effect = preload("res://scripts/combat_effect_3d.gd")
const SkillEffect = preload("res://scripts/hero_skill_effect_3d.gd")
const Profiles = preload("res://scripts/combat_visual_profiles.gd")
const MODEL_HEIGHT_SCALE := {"Sniper": 0.82}
@export var batch_models := true
@export var runtime_models := true

var camera: Camera3D
var pieces: Dictionary = {}
var bench_pieces: Dictionary = {}
var cues: Dictionary = {}
var bursts: Array = []
var flights: Dictionary = {}
var event_index := 0
var last_elapsed := -1.0
var trait_tiers: Dictionary = {}
var trait_members: Dictionary = {}
var preparation_effects: Array = []
var activation_count := 0

func _exit_tree() -> void:
	preload("res://scripts/model_mesh_batch.gd").cache.clear()

func _process(delta: float) -> void:
	for entry in preparation_effects.duplicate():
		entry.age += delta
		if entry.age >= entry.visual.lifetime or not pieces.has(entry.uid):
			entry.node.free()
			preparation_effects.erase(entry)
			continue
		entry.node.position = pieces[entry.uid].position
		entry.visual.sample(entry.age)

func sync_trait_activations(board: Dictionary, units: Dictionary, tiers: Dictionary) -> void:
	var members := {}
	for index in board:
		var source: Dictionary = board[index]
		var uid := -((7-int(index)/8)*8+int(index)%8)-1
		if not pieces.has(uid): continue
		var tags := (str(units[source.id].species)+"、"+str(units[source.id]["class"])).split("、")
		for tag in tags:
			if int(tiers.get(tag,0)) <= 0: continue
			var key := "%s:%d:%s:%d"%[tag,index,source.id,source.star]
			members[key] = true
			if int(tiers[tag]) <= int(trait_tiers.get(tag,0)) and trait_members.has(key): continue
			var holder := Node3D.new()
			var visual := preload("res://scripts/trait_activation_3d.gd").new()
			holder.add_child(visual)
			visual.configure_tag(tag)
			add_child(holder)
			holder.position = pieces[uid].position
			preparation_effects.append({"node":holder,"visual":visual,"uid":uid,"age":0.0,"tag":tag})
			activation_count += 1
	trait_tiers = tiers.duplicate()
	trait_members = members

func clear_trait_activations() -> void:
	for entry in preparation_effects: entry.node.free()
	preparation_effects.clear()
	trait_tiers.clear()
	trait_members.clear()


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.65, 0.76, 0.90)
	environment.environment.ambient_light_energy = 0.55
	add_child(environment)
	# The full-screen backdrop already contains the visible chessboard.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 25, 0)
	light.light_color = Color(1.0, 0.90, 0.71)
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-35, -140, 0)
	fill_light.light_color = Color(0.45, 0.67, 1.0)
	fill_light.light_energy = 0.25
	add_child(fill_light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 48.0
	camera.position = Vector3(0, 12, 16)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	for index in range(8):
		var tile := MeshInstance3D.new()
		tile.name = "BenchTile%d" % index
		tile.mesh = preload("res://scripts/stone_mesh.gd").beveled_box(Vector3(0.988, 0.14, 0.46), 0.025)
		tile.position = Vector3(index - 3.5, -0.09, 4.25)
		var material: ShaderMaterial = preload("res://assets/ui/materials/moonlit_stone.tres").duplicate()
		material.set_shader_parameter("stone_color",Color(.35,.41,.39))
		tile.material_override = material
		add_child(tile)


func reset() -> void:
	clear_trait_activations()
	for piece in pieces.values(): piece.free()
	for burst in bursts: burst["node"].free()
	for flight in flights.values(): flight["node"].free()
	flights.clear()
	pieces.clear()
	bursts.clear()
	cues.clear()
	event_index = 0
	last_elapsed = -1.0


func _make_piece(actor: Dictionary, player_team: int) -> Node3D:
	var profile_start := Time.get_ticks_usec()
	var piece = Piece.new()
	piece.piece_id = str(actor["id"])
	piece.star = int(actor["star"])
	piece.monster = bool(actor.get("monster", false))
	piece.form = str(actor.get("form",""))
	piece.use_runtime = runtime_models and batch_models and not "--unbatched" in OS.get_cmdline_user_args()
	add_child(piece)
	var load_us := Time.get_ticks_usec()-profile_start
	var bounds := AABB()
	var first := true
	for mesh in piece.rig.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		var local_bounds: AABB = (piece.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
	if piece.rig.has_meta("fit_bounds"): bounds=piece.rig.get_meta("fit_bounds")
	var tier := clampi(piece.star - 1, 0, 2)
	var width: float = STAR_WIDTHS[tier]
	if tier==0 and (piece.piece_id in size_policy.nonhuman_ids or piece.form in size_policy.nonhuman_forms):width=float(size_policy.nonhuman_star1)
	var height: float = STAR_HEIGHTS[tier] * float(MODEL_HEIGHT_SCALE.get(piece.piece_id, 1.0))
	# Preserve authored proportions; width and height are independent upper limits.
	var fit := minf(width / maxf(maxf(bounds.size.x, bounds.size.z), 0.1), height / maxf(bounds.size.y, 0.1))
	piece.scale = Vector3.ONE * (.55 if piece.monster else fit)
	var ground_offset := minf(0,.10/piece.scale.y-bounds.position.y)
	piece.set_meta("ground_offset",ground_offset)
	piece.set_meta("rest_rig_y",piece.rig.position.y)
	piece.rig.position.y+=ground_offset
	piece.set_meta("head_height", (bounds.end.y+ground_offset) * piece.scale.y + 0.12)
	var hud_anchor := Node3D.new()
	hud_anchor.name = "HUDAnchor"
	hud_anchor.position = piece.rig.transform.affine_inverse()*Vector3(0,bounds.end.y+ground_offset+.12/piece.scale.y,0)
	piece.rig.add_child(hud_anchor)
	if piece.rig.has_meta("authored_skeletal"):
		var skeleton: Skeleton3D=piece.rig.find_children("*","Skeleton3D",true,false)[0]
		var bone := skeleton.find_bone("HeadPivot")
		if bone<0:bone=skeleton.find_bone("Head")
		if bone>=0:
			piece.set_meta("hud_skeleton",piece.get_path_to(skeleton))
			piece.set_meta("hud_bone",bone)
			piece.set_meta("hud_bind_position",hud_anchor.position)
	var bounds_us := Time.get_ticks_usec()-profile_start-load_us
	if piece.rig.has_meta("render_batch"):
		piece.set_meta("render_batch",piece.rig.get_meta("render_batch"))
	elif batch_models and not "--unbatched" in OS.get_cmdline_user_args():
		piece.set_meta("render_batch",preload("res://scripts/model_mesh_batch.gd").apply(piece.rig,"%s:%d:%s"%[piece.piece_id,piece.star,piece.form]))
	var batch_us := Time.get_ticks_usec()-profile_start-load_us-bounds_us
	piece.set_meta("rest_scale", piece.scale)
	piece.set_meta("fitted_width",maxf(bounds.size.x,bounds.size.z)*piece.scale.x)
	if piece.star==3 and not piece.monster and not Profiles.get_profile(piece.piece_id).is_empty():
		var aura:=preload("res://scripts/three_star_aura.gd").new()
		piece.add_child(aura)
		aura.setup(piece)
	piece.set_meta("appearance", "%s:%d" % [piece.piece_id, piece.star])
	var hit_flash := StandardMaterial3D.new()
	hit_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hit_flash.albedo_color = Color(1, 1, 1, 0)
	var flash_mesh_paths: Array[NodePath] = []
	for mesh in piece.rig.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree(): flash_mesh_paths.append(piece.get_path_to(mesh))
	piece.set_meta("flash_mesh_paths",flash_mesh_paths)
	piece.set_meta("flash_active",false)
	piece.set_meta("hit_flash", hit_flash)
	var halo := Node3D.new()
	halo.name = "ControlHalo"
	halo.position.y = float(piece.get_meta("head_height")) / piece.scale.y + 0.12
	halo.visible = false
	piece.add_child(halo)
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.albedo_color = Color(1, 0.78, 0.2)
	for index in 3:
		var orb := MeshInstance3D.new()
		var orb_mesh := SphereMesh.new()
		orb_mesh.radius = 0.05 / piece.scale.y
		orb_mesh.height = orb_mesh.radius * 2
		orb.mesh = orb_mesh
		orb.material_override = halo_material
		orb.position = Vector3(cos(index * TAU / 3), 0, sin(index * TAU / 3)) * (0.24 / piece.scale.y)
		halo.add_child(orb)
	piece.get("animation_player").speed_scale = 0.0
	var shadow := MeshInstance3D.new()
	shadow.name="ContactShadow"
	var shadow_mesh:=PlaneMesh.new()
	shadow_mesh.size=Vector2(2.0,1.4)
	if not piece.monster: shadow_mesh.size=Vector2(width/piece.scale.x,width*.75/piece.scale.z)
	shadow.mesh=shadow_mesh
	shadow.material_override=CONTACT_SHADOW
	shadow.position.y=0.015
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.add_child(shadow)
	if "--profile" in OS.get_cmdline_user_args(): print("MODEL ",piece.piece_id," load=",load_us/1000.0," bounds=",bounds_us/1000.0," batch=",batch_us/1000.0," remainder=",(Time.get_ticks_usec()-profile_start-load_us-bounds_us-batch_us)/1000.0)
	return piece


func highlight_piece(piece: Node3D, selected: bool) -> void:
	var flash: StandardMaterial3D=piece.get_meta("hit_flash")
	flash.albedo_color=Color(1,.78,.32,.13 if selected else 0)
	for path in piece.get_meta("flash_mesh_paths"):
		var mesh: MeshInstance3D=piece.get_node(path)
		mesh.material_overlay=flash if selected else mesh.get_meta("star_overlay") if mesh.has_meta("star_overlay") else null
	piece.set_meta("flash_active",selected)

func set_selection(board_index: int, bench_slot: int) -> void:
	for uid in pieces: highlight_piece(pieces[uid],board_index>=0 and uid==-board_index-1)
	for slot in bench_pieces: highlight_piece(bench_pieces[slot],slot==bench_slot)


func sync_bench(bench: Array, layout: Array) -> void:
	var occupied: Dictionary = {}
	for slot in range(8):
		var index := int(layout[slot]) if slot < layout.size() else slot if slot < bench.size() else -1
		if index < 0 or index >= bench.size(): continue
		var source: Dictionary = bench[index]
		var appearance := "%s:%d" % [source["id"], int(source["star"])]
		if bench_pieces.has(slot) and bench_pieces[slot].get_meta("appearance") != appearance:
			bench_pieces[slot].free()
			bench_pieces.erase(slot)
		if not bench_pieces.has(slot):
			bench_pieces[slot] = _make_piece({"id": source["id"], "star": source["star"], "team": 0}, 0)
		var piece: Node3D = bench_pieces[slot]
		piece.position = Vector3(slot - 3.5, 0, 4.25)
		piece.animation_player.play("idle")
		piece.animation_player.seek(0, true)
		piece.rig.position.y+=float(piece.get_meta("ground_offset",0))
		occupied[slot] = true
	for slot in bench_pieces.keys():
		if not occupied.has(slot):
			bench_pieces[slot].free()
			bench_pieces.erase(slot)


func sync_preparation(board: Dictionary, monsters: Dictionary) -> void:
	var present: Dictionary = {}
	for index in range(64):
		var game_index := (7 - index / 8) * 8 + index % 8
		var is_monster := monsters.has(index)
		if not is_monster and (index < 32 or not board.has(game_index)): continue
		var source: Dictionary = {"id": monsters[index], "star": 1} if is_monster else board[game_index]
		var uid := -index - 1
		var actor := {"id": source["id"], "star": source["star"], "team": 1 if is_monster else 0, "monster": is_monster}
		var appearance := "%s:%d" % [source["id"], int(source["star"])]
		if pieces.has(uid) and pieces[uid].get_meta("appearance") != appearance:
			pieces[uid].free()
			pieces.erase(uid)
		if not pieces.has(uid): pieces[uid] = _make_piece(actor, 0)
		present[uid] = true
		pieces[uid].position = Vector3(index % 8 - 3.5, 0, float(index / 8) - 3.5)
		pieces[uid].rotation.y = PI if is_monster else 0.0
		pieces[uid].visible = true
		pieces[uid].get("animation_player").play("idle")
		pieces[uid].get("animation_player").seek(0.0, true)
		pieces[uid].rig.position.y+=float(pieces[uid].get_meta("ground_offset",0))
	for uid in pieces.keys():
		if not present.has(uid):
			pieces[uid].free()
			pieces.erase(uid)


func _world(pos: Vector2, player_team: int) -> Vector3:
	return Vector3(pos.x - 3.5, 0, 3.5 - pos.y) if player_team == 0 else Vector3(3.5 - pos.x, 0, pos.y - 3.5)


func project_position(pos: Vector2, player_team: int, height: float = 0.0) -> Vector2:
	return camera.unproject_position(_world(pos, player_team) + Vector3(0, height, 0))


func project_actor(uid: int) -> Vector2:
	return camera.unproject_position(pieces[uid].get_node("Rig/HUDAnchor").global_position) if pieces.has(uid) else Vector2.ZERO


func _actor(events_frame: Dictionary, uid: int) -> Dictionary:
	for actor in events_frame.get("actors", []):
		if int(actor["uid"]) == uid: return actor
	return {}


func _burst(position: Vector3, color: Color, radius: float, ring: bool, started: float, effect: String = "") -> void:
	if effect in ["Axe", "Tidehunter", "critical_hit", "impact", "ice_impact", "bullet_impact", "mana_pulse"]:
		_pilot_burst(position, color, radius, started, effect)
		return
	var instance := MeshInstance3D.new()
	if ring:
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.72
		mesh.outer_radius = 0.88
		instance.mesh = mesh
		instance.position = position + Vector3(0, 0.10, 0)
	else:
		var mesh := SphereMesh.new()
		mesh.radius = 0.32
		mesh.height = 0.64
		instance.mesh = mesh
		instance.position = position + Vector3(0, 0.85, 0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	instance.material_override = material
	if effect == "Tidehunter":
		var wave := MeshInstance3D.new()
		var wave_mesh := TorusMesh.new()
		wave_mesh.inner_radius = 0.48
		wave_mesh.outer_radius = 0.53
		wave.mesh = wave_mesh
		wave.material_override = material
		wave.position.y = 0.08
		instance.add_child(wave)
		for index in 12:
			var spray := MeshInstance3D.new()
			var spray_mesh := CylinderMesh.new()
			spray_mesh.top_radius = 0.0
			spray_mesh.bottom_radius = 0.06
			spray_mesh.height = 0.46
			spray_mesh.radial_segments = 5
			spray.mesh = spray_mesh
			spray.material_override = material
			var angle := TAU * index / 12.0
			spray.position = Vector3(cos(angle) * 0.8, 0.17, sin(angle) * 0.8)
			instance.add_child(spray)
	elif effect in ["Axe", "critical_hit"]:
		for index in 2:
			var slash := MeshInstance3D.new()
			var slash_mesh := CylinderMesh.new()
			slash_mesh.top_radius = 0.0
			slash_mesh.bottom_radius = 0.06
			slash_mesh.height = 1.5
			slash_mesh.radial_segments = 5
			slash.mesh = slash_mesh
			slash.material_override = material
			slash.rotation = Vector3(PI / 2 if ring else 0.0, index * PI / 2.0, 0.7 if index == 0 else -0.7)
			instance.add_child(slash)
	add_child(instance)
	bursts.append({"node": instance, "material": material, "color": color, "radius": radius,
		"ring": ring, "time": started})


func _pilot_burst(position: Vector3, color: Color, radius: float, started: float, effect: String, facing: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.position = position
	holder.rotation.y = facing
	var visual := Effect.new()
	holder.add_child(visual)
	visual.setup(effect, color, radius)
	add_child(holder)
	bursts.append({"node": holder, "visual": visual, "time": started})
	return holder

func _attack_feedback(piece: Node3D, actor: Dictionary, elapsed: float) -> void:
	var profile := Profiles.get_profile(str(actor["id"]))
	if profile.is_empty(): return
	var state: Dictionary=cues.get(int(actor["uid"]), {})
	var attack: Dictionary = state.get("attack_release",state.get("attack", {}))
	if not bool(attack.get("released", false)): return
	var released := float(attack.get("release_time", -100.0))
	if released == float(piece.get_meta("attack_fx_time", -100.0)): return
	var age := elapsed - released
	if age < 0 or age > .24: return
	piece.set_meta("attack_fx_time", released)
	var effect: String = str(profile.attack)
	if piece.form in ["transform_wolves","metamorphosis"]: effect = "claw_attack"
	elif piece.form == "chemical_rage": effect = "pa_attack"
	elif piece.form == "dragon_form": effect = "spit_release"
	var color := Color(Profiles.tint(str(actor["id"])),.65)
	var source := piece.position + Vector3(0, float(piece.get_meta("head_height")) * .52, 0)
	var muzzle := piece.get_node_or_null("Rig/WeaponPivot/Muzzle")
	if muzzle != null: source = muzzle.global_position
	var blade_tip := piece.get_node_or_null("Rig/WeaponPivot/BladeTip")
	if actor["id"] == "Axe" and blade_tip != null: source = blade_tip.global_position
	_pilot_burst(source, color, .28 if actor["id"] == "Phantom Assassin" else .32, released, effect, piece.rotation.y)
	if str(profile.ability) in ["attack_aura","mana_burn","frontal_reduction","bounce_attack","fervor"]:
		var holder := Node3D.new()
		holder.position = piece.position
		var visual := SkillEffect.new()
		holder.add_child(visual)
		visual.configure(str(profile.ability),Profiles.tint(str(actor.id)),{"radius":float(profile.radius)},"hit")
		add_child(holder)
		bursts.append({"node":holder,"visual":visual,"time":released})


func _signature(event: Dictionary, actor: Dictionary, frame: Dictionary, player_team: int, hit: bool = false) -> void:
	var ability := str(event.get("ability",Profiles.get_profile(str(actor.id)).get("ability","")))
	var profile := Profiles.get_profile(str(actor.id))
	if profile.is_empty(): return
	var origin: Vector2 = event.get("origin",actor.pos)
	var target := _actor(frame,int(event.target_uid))
	var destination: Vector2 = event.get("destination",target.get("pos",origin))
	var at := _world(origin,player_team)
	if hit or ability in ["hex","cold_embrace","disarm","multicast","purification","shield","shallow_grave","poison","leech_seed","doom","ghostship","static_storm","call_down","remote_mines","corrosive_haze"]: at = _world(destination,player_team)
	var holder := Node3D.new()
	holder.position = at
	var direction := _world(destination,player_team)-_world(origin,player_team)
	if direction.length() > .01: holder.rotation.y = atan2(-direction.x,-direction.z)
	var visual: Node3D
	if ability in ["transform_wolves","dragon_form","metamorphosis","chemical_rage"] and not hit:
		visual=preload("res://scripts/transformation_effect_3d.gd").new()
		holder.add_child(visual)
		var model: Node3D=pieces.get(int(actor.uid))
		visual.configure_form(ability,float(model.get_meta("fitted_width")) if model!=null else STAR_WIDTHS[int(actor.star)-1],float(model.get_meta("head_height")) if model!=null else STAR_HEIGHTS[int(actor.star)-1])
		add_child(holder)
		bursts.append({"node":holder,"visual":visual,"time":event.time,"follow_uid":int(actor.uid)})
		return
	visual=SkillEffect.new()
	holder.add_child(visual)
	var context := event.duplicate()
	context["star"]=int(actor.star)
	context["radius"] = float(event.get("radius",profile.radius))
	context["distance"] = direction.length()
	# Runtime line attacks affect every forward enemy within one tile of the axis.
	var grid_direction := (destination-origin).normalized()
	var length_to_edge := 11.32
	if absf(grid_direction.x) > .0001: length_to_edge = minf(length_to_edge,((7.5 if grid_direction.x > 0 else -.5)-origin.x)/grid_direction.x)
	if absf(grid_direction.y) > .0001: length_to_edge = minf(length_to_edge,((7.5 if grid_direction.y > 0 else -.5)-origin.y)/grid_direction.y)
	context["line_length"] = maxf(.1,length_to_edge)
	visual.configure(ability,Profiles.tint(str(actor.id)),context,"hit" if hit else "release")
	add_child(holder)
	var burst := {"node":holder,"visual":visual,"time":float(event.time)}
	if not hit:
		if ability in ["magic_pulse", "spin", "firefly", "exorcism", "taunt_armor", "refraction", "stone_gaze", "spiked_carapace", "gods_strength", "mana_drain"]:
			burst["follow_uid"] = int(actor.uid)
			if ability == "mana_drain":
				burst["link_target_uid"] = int(event.target_uid)
				burst["link_distance"] = maxf(.01,direction.length())
		elif ability in ["hex", "cold_embrace", "disarm", "multicast", "shield", "shallow_grave", "poison", "leech_seed", "doom", "corrosive_haze"]:
			burst["follow_uid"] = int(event.target_uid)
	bursts.append(burst)

func _skill_feedback(event: Dictionary, actor: Dictionary, frame: Dictionary, player_team: int) -> void:
	_signature(event,actor,frame,player_team)

func _skill_prepare(event: Dictionary,actor: Dictionary,player_team: int,elapsed: float) -> void:
	var end := float(event.get("release_time",event.time))
	if end<=elapsed or end-float(event.time)<.12:return
	var skill := str(event.get("ability",""))
	if skill.is_empty() or skill=="wildcard_combine":return
	var piece: Node3D=pieces.get(int(actor.uid))
	var holder=Node3D.new()
	add_child(holder)
	holder.position=_world(actor.pos,player_team)
	var visual=preload("res://scripts/skill_prepare_3d.gd").new()
	holder.add_child(visual)
	visual.position.y=float(piece.get_meta("head_height",.45))*.55 if piece else .35
	visual.configure(skill,Profiles.tint(str(actor.id)),end-float(event.time),float(piece.get_meta("fitted_width",.28)) if piece else .28,int(actor.star))
	bursts.append({"node":holder,"visual":visual,"time":float(event.time),"follow_uid":int(actor.uid),"prepare":true})

func _skill_hit_feedback(event: Dictionary, actor: Dictionary, frame: Dictionary, player_team: int) -> void:
	# Only confirmed skill hits produce the compact impact; AOE release is drawn once.
	var ability := str(event.get("ability",""))
	if Profiles.skill_style(ability) not in ["line","bolt","storm"]: return
	var impact := event.duplicate()
	impact["radius"] = .32
	_signature(impact,actor,frame,player_team,true)


func _consume_events(events: Array, frame: Dictionary, elapsed: float, player_team: int) -> void:
	# The next wind-up can start on the same tick as the preceding release.
	for uid in cues:
		var pending: Dictionary=cues[uid].get("attack",{})
		if bool(pending.get("released",false)) and float(pending.get("release_time",INF))<=elapsed:
			cues[uid]["attack_release"]=pending
	while event_index < events.size() and float(events[event_index]["time"]) <= elapsed:
		var event: Dictionary = events[event_index]
		event_index += 1
		var uid := int(event["uid"])
		var kind := str(event["kind"])
		var actor := _actor(frame, uid)
		if actor.is_empty(): continue
		if not cues.has(uid): cues[uid] = {}
		cues[uid][kind] = event
		if kind=="attack" and bool(event.get("released",false)) and float(event.get("release_time",INF))<=elapsed:
			cues[uid]["attack_release"]=event
		if kind == "status":
			if not cues[uid].has("statuses"): cues[uid]["statuses"] = {}
			cues[uid]["statuses"][event["status"]] = {"end": event["end"]}
		if kind == "projectile": _launch_projectile(event, actor, player_team, elapsed)
		elif kind == "projectile_end":
			var flight_id := int(event["flight_id"])
			if flights.has(flight_id):
				flights[flight_id]["node"].free()
				flights.erase(flight_id)
		if kind in ["attack", "cast"]: cues[uid]["facing"] = int(event["target_uid"])
		var age := elapsed - float(event["time"])
		if age > 0.55:
			if kind=="cast" and float(event.get("release_time",0))>elapsed:
				_skill_prepare(event,actor,player_team,elapsed)
				continue
			if kind != "cast_release": continue
			if age > maxf(.85,float(event.get("duration",0)))+float(event.get("delay",0)): continue
		var position := _world(actor["pos"], player_team)
		if kind == "cast":
			_skill_prepare(event,actor,player_team,elapsed)
		elif kind == "equipment_trigger":
			var victim := _actor(frame, int(event["target_uid"]))
			if not victim.is_empty():
				var color := Color(0.25, 0.95, 0.48, 0.65) if event["item"] == "lifesteal" else Color(1, 0.3, 0.3, 0.7) if event["item"] == "blade_mail" else Color(1, 0.70, 0.22, 0.7)
				_burst(_world(victim["pos"], player_team), color, 0.45, true, float(event["time"]))
		elif kind == "mana_pulse":
			_skill_feedback(event,actor,frame,player_team)
			for recipient in event.get("recipient_uids",[]):
				var ally := _actor(frame,int(recipient))
				if ally.is_empty():continue
				var pulse=event.duplicate()
				pulse["target_uid"]=int(recipient)
				pulse["destination"]=ally.pos
				pulse["radius"]=.28
				_signature(pulse,actor,frame,player_team,true)
		elif kind == "cast_release":
			_skill_feedback(event,actor,frame,player_team)
		elif kind == "skill_hit":
			_skill_hit_feedback(event,actor,frame,player_team)
		elif kind == "heal":
			var healer := _actor(frame,int(event.target_uid))
			if healer.is_empty():_pilot_burst(position,Color(.55,1,.65,.5),.30,float(event.time),"skill_healing")
			else:
				var healing=event.duplicate()
				healing["target_uid"]=int(actor.uid)
				healing["ability"]=str(healer.ability.kind) if healer.has("ability") else str(Profiles.get_profile(str(healer.id)).get("ability","heal"))
				healing["origin"]=healer.pos
				healing["destination"]=actor.pos
				healing["radius"]=.28
				_signature(healing,healer,frame,player_team,true)
		elif kind == "hit":
			var source := _actor(frame, int(event["target_uid"]))
			var source_id := str(source.get("id", ""))
			var impact := "ice_impact" if source_id == "Crystal Maiden" else "bullet_impact" if source_id == "Sniper" else "impact"
			var hit_height := float(pieces[uid].get_meta("head_height")) * .5 if pieces.has(uid) else .35
			_burst(position + Vector3(0,hit_height,0), Color(Profiles.tint(source_id),.65), .15, false, float(event["time"]), impact)
		elif kind == "critical_hit":
			_signature(event,actor,frame,player_team,true)
			var target := _actor(frame, int(event["target_uid"]))
			if not target.is_empty():
				var target_piece: Node3D = pieces.get(int(event["target_uid"]))
				var hit_height: float = float(target_piece.get_meta("head_height")) * .5 if target_piece != null else .4
				_pilot_burst(_world(target["pos"], player_team) + Vector3(0,hit_height,0), Color(.80,.65,1,.85), .24, float(event["time"]), "critical_hit")



func _pose(piece: Node3D, actor: Dictionary, moving: bool, elapsed: float) -> void:
	var uid := int(actor["uid"])
	var state: Dictionary = cues.get(uid, {})
	var clip := "walk" if moving else "idle"
	var started := 0.0
	var selected: Dictionary = {}
	if float(actor["hp"]) <= 0:
		started = float(state.get("die", {}).get("time", elapsed))
		piece.visible = elapsed - started < 0.95
		clip = "die"
	else:
		piece.visible = true
		for candidate in ["attack", "cast", "hit"]:
			# Confirmed hits still flash; do not replace an active release pose.
			if candidate=="hit" and clip in ["attack","cast"]:continue
			var event: Dictionary = state.get(candidate, {})
			var age := elapsed - float(event.get("time", -100.0))
			var authored_player: AnimationPlayer=piece.animation_player
			var length: float=authored_player.get_animation(candidate).length
			var peak: float=piece.rig.get_meta("animation_peaks",{}).get(candidate,.3 if candidate=="attack" else .4 if candidate=="cast" else 0.0)
			var release_delay := maxf(0.0, float(event.get("release_time", event.get("time", 0.0))) - float(event.get("time", 0.0)))
			var duration := maxf(length, release_delay + length - peak)
			if age >= 0 and age < duration and float(event.get("time", -100.0)) >= started:
				clip = candidate
				started = float(event["time"])
				selected = event
	var active := VisualState.active_statuses(actor, state, elapsed)
	var controlled := active.has("stun") or active.has("petrify") or active.has("hex")
	if controlled and float(actor["hp"]) > 0: clip = "idle"
	if (clip=="cast" and active.has("silence")) or (clip=="attack" and active.has("disarm")):clip="idle"
	var halo: Node3D = piece.get_node("ControlHalo")
	halo.visible = controlled and float(actor["hp"]) > 0
	halo.rotation.y = elapsed * 3.0
	var player: AnimationPlayer = piece.get("animation_player")
	if piece.rig.has_meta("authored_skeletal"):
		var motion_skeleton: Skeleton3D=piece.get_node(piece.get_meta("hud_skeleton"))
		motion_skeleton.reset_bone_poses()
	if player.current_animation != clip: player.play(clip)
	var length: float = player.current_animation_length
	var sample := fposmod(maxf(0.0, elapsed - started), length) if clip in ["idle", "walk"] else minf(length, maxf(0.0, elapsed - started))
	if clip in ["attack", "cast"]:
		var peak: float = piece.rig.get_meta("animation_peaks", {}).get(clip, 0.3 if clip == "attack" else 0.4)
		var release_delay := maxf(0.0, float(selected["release_time"]) - started)
		var duration := maxf(length, release_delay + length - peak)
		var age := elapsed - started
		sample = peak * age / release_delay if age < release_delay and release_delay > 0 else peak + (length - peak) * clampf((age - release_delay) / (duration - release_delay), 0.0, 1.0)
	player.seek(0.0 if controlled and clip != "die" else sample, true)
	piece.sync_skin_weapon()
	if piece.has_meta("hud_skeleton"):
		var skeleton: Skeleton3D=piece.get_node(piece.get_meta("hud_skeleton"))
		skeleton.force_update_all_bone_transforms()
		var bone: int=piece.get_meta("hud_bone")
		var local: Transform3D=piece.rig.global_transform.affine_inverse()*skeleton.global_transform
		piece.get_node("Rig/HUDAnchor").position=local*skeleton.get_bone_global_pose(bone)*skeleton.get_bone_global_rest(bone).affine_inverse()*local.affine_inverse()*Vector3(piece.get_meta("hud_bind_position"))
	if piece.rig.has_meta("authored_skeletal"):
		piece.rig.position.y=float(piece.get_meta("rest_rig_y",0))+float(piece.get_meta("ground_offset",0))
	else:piece.rig.position.y+=float(piece.get_meta("ground_offset",0))
	piece.set_meta("battle_clip", clip)
	if piece.has_node("StarAura"): piece.get_node("StarAura").update(state,elapsed,float(actor["hp"])>0)
	var hit_age := elapsed - float(state.get("hit", {}).get("time", -100.0))
	var flash: StandardMaterial3D = piece.get_meta("hit_flash")
	flash.albedo_color.a = 0.28 * (1.0 - hit_age / 0.09) if hit_age >= 0 and hit_age < 0.09 else 0.0
	var flash_active := flash.albedo_color.a > 0.0
	if flash_active != bool(piece.get_meta("flash_active",false)):
		for path in piece.get_meta("flash_mesh_paths"):
			var mesh: MeshInstance3D=piece.get_node(path)
			mesh.material_overlay=flash if flash_active else mesh.get_meta("star_overlay") if mesh.has_meta("star_overlay") else null
		piece.set_meta("flash_active",flash_active)
	piece.get_node("ContactShadow").visible = float(actor["hp"])>0


func sync(frame: Dictionary, next_frame: Dictionary, events: Array, elapsed: float, player_team: int) -> void:
	if elapsed < last_elapsed: reset()
	last_elapsed = elapsed
	_consume_events(events, frame, elapsed, player_team)
	var next_actors: Dictionary = {}
	for actor in next_frame["actors"]: next_actors[int(actor["uid"])] = actor
	var span := float(next_frame["time"]) - float(frame["time"])
	var blend := clampf((elapsed - float(frame["time"])) / span, 0.0, 1.0) if span > 0 else 0.0
	var present: Dictionary = {}
	for actor in frame["actors"]:
		var uid := int(actor["uid"])
		present[uid] = true
		if pieces.has(uid) and pieces[uid].form != str(actor.get("form","")):
			pieces[uid].free()
			pieces.erase(uid)
		if not pieces.has(uid):
			pieces[uid] = _make_piece(actor, player_team)
		var next_actor: Dictionary = next_actors.get(uid, actor)
		var position: Vector2 = actor["pos"].lerp(next_actor["pos"], blend)
		var moving: bool = actor["pos"].distance_to(next_actor["pos"]) > 0.01
		var leap: Dictionary = cues.get(uid, {}).get("leap", {})
		var leap_age := elapsed - float(leap.get("time", -100.0))
		var height := 0.0
		var leap_duration := float(leap.get("duration", .4))
		if leap_age >= 0 and leap_age < leap_duration:
			position = leap["from"].lerp(leap["to"], leap_age / leap_duration)
			height = sin(PI * leap_age / leap_duration) * 0.9
			moving = true
		var piece: Node3D = pieces[uid]
		piece.position = _world(position, player_team) + Vector3(0, height, 0)
		var facing := int(cues.get(uid, {}).get("facing", -1))
		var target := _actor(frame, facing)
		if not target.is_empty():
			var direction: Vector3 = _world(target["pos"], player_team) - piece.position
			piece.rotation.y = atan2(direction.x, direction.z)
		if float(actor["hp"]) <= 0 and not cues.get(uid, {}).has("die"):
			if not cues.has(uid): cues[uid] = {}
			cues[uid]["die"] = {"time": frame["time"]}
		_pose(piece, actor, moving, elapsed)
		if float(actor["hp"]) > 0: _attack_feedback(piece, actor, elapsed)
	for uid in pieces:
		if not present.has(uid): pieces[uid].visible = false
	_sync_projectiles(elapsed, player_team)
	for burst in bursts.duplicate():
		var age := elapsed - float(burst["time"])
		if burst.has("visual"):
			if burst.has("follow_uid"):
				var attached := _actor(frame, int(burst.follow_uid))
				if attached.is_empty() or float(attached.hp) <= 0:
					burst.node.free()
					bursts.erase(burst)
					continue
				if burst.get("prepare",false):
					var statuses := VisualState.active_statuses(attached,cues.get(int(burst.follow_uid),{}),elapsed)
					if statuses.has("stun") or statuses.has("petrify") or statuses.has("hex") or statuses.has("silence"):
						burst.node.free()
						bursts.erase(burst)
						continue
				if pieces.has(int(burst.follow_uid)): burst.node.position = pieces[int(burst.follow_uid)].position
			if burst.has("link_target_uid"):
				var receiver := _actor(frame,int(burst.link_target_uid))
				if receiver.is_empty() or float(receiver.hp) <= 0 or not pieces.has(int(burst.link_target_uid)):
					burst.node.free()
					bursts.erase(burst)
					continue
				var link: Vector3 = pieces[int(burst.link_target_uid)].position-burst.node.position
				burst.node.rotation.y = atan2(-link.x,-link.z)
				burst["link_scale"] = link.length()/float(burst.link_distance)
			if age >= burst["visual"].lifetime:
				burst["node"].free()
				bursts.erase(burst)
			else:
				burst["visual"].sample(age)
				if burst.has("link_scale"): burst.visual.scale.z *= float(burst.link_scale)
			continue
		if age >= 0.55:
			burst["node"].free()
			bursts.erase(burst)
			continue
		burst["node"].scale = Vector3.ONE * (0.2 + float(burst["radius"]) * age / 0.55)
		var color: Color = burst["color"]
		color.a *= 1.0 - age / 0.55
		burst["material"].albedo_color = color


func _launch_projectile(event: Dictionary, actor: Dictionary, player_team: int, elapsed: float) -> void:
	if elapsed >= float(event["arrive_time"]): return
	var node := Node3D.new()
	add_child(node)
	var shot := Effect.new()
	node.add_child(shot)
	var profile := Profiles.get_profile(str(actor["id"]))
	var style := str(profile.get("projectile","arcane_bolt"))
	if actor["id"] == "Sniper" and not bool(event["basic"]): style = "assassinate"
	if bool(event.basic) and actor.get("form","") == "dragon_form": style = "fire_bolt"
	elif bool(event.basic) and actor.get("form","") == "metamorphosis": style = "arcane_bolt"
	if bool(event["basic"]): shot.setup(style, Color(Profiles.tint(str(actor["id"])),.75))
	else:
		shot.free()
		var skill_shot := SkillEffect.new()
		node.add_child(skill_shot)
		skill_shot.configure_flight(str(event.ability),Profiles.tint(str(actor.id)),{"star":int(actor.star)})
	flights[int(event["flight_id"])] = {"node": node, "event": event, "from": _world(event["from"], player_team) + Vector3(0, 0.65, 0)}
	if int(event.get("from_uid",-1)) >= 0:
		var bounce_from := int(event["from_uid"])
		if pieces.has(bounce_from): flights[int(event["flight_id"])]["from"] = _world(event["from"],player_team)+Vector3(0,float(pieces[bounce_from].get_meta("head_height"))*.52,0)
	else:
		# Resolve after this frame's bone poses, including actors created on frame zero.
		flights[int(event["flight_id"])]["pending_socket"]=int(actor.uid)


func _sync_projectiles(elapsed: float, player_team: int) -> void:
	for flight_id in flights.keys():
		var flight: Dictionary = flights[flight_id]
		var event: Dictionary = flight["event"]
		if elapsed >= float(event["arrive_time"]):
			flight["node"].free()
			flights.erase(flight_id)
			continue
		if flight.has("pending_socket") and pieces.has(int(flight.pending_socket)):
			var piece: Node3D=pieces[int(flight.pending_socket)]
			var muzzle: Node3D=piece.rig.get_node(piece.rig.get_meta("muzzle_node_path")) if piece.rig.has_meta("muzzle_node_path") else piece.get_node_or_null("Rig/WeaponPivot/Muzzle")
			if muzzle!=null:
				var point := muzzle.global_position
				if piece.rig.has_meta("authored_skeletal"):
					var attachment: BoneAttachment3D=muzzle.get_parent()
					var skeleton: Skeleton3D=attachment.get_parent()
					point=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(attachment.bone_name))*muzzle.position)
				flight["from"]=_world(event["from"],player_team)+point-piece.position
				flight["from"].y=point.y
			flight.erase("pending_socket")
		var target_uid := int(event["target_uid"])
		var destination := _world(event["to"], player_team) + Vector3(0, 0.65, 0)
		if pieces.has(target_uid): destination = pieces[target_uid].position + Vector3(0, float(pieces[target_uid].get_meta("head_height")) * .52, 0)
		var progress := clampf((elapsed - float(event["time"])) / maxf(0.001, float(event["arrive_time"]) - float(event["time"])), 0, 1)
		var start: Vector3 = flight["from"]
		flight["node"].position = start.lerp(destination, progress)
		if not bool(event.basic):
			var ability := str(event.ability)
			if ability in ["bounce_stun","missiles"]: flight["node"].position.y += sin(progress*PI)*(.45 if ability == "bounce_stun" else .7)
			var mesh: Node3D = flight["node"].get_child(0)
			mesh.sample(elapsed-float(event.time))
			if ability in ["chain_frost","magic_damage","line_orb"]: mesh.rotation.z = progress*TAU*2
		if flight["node"].position.distance_to(destination) > 0.01: flight["node"].look_at(destination)
