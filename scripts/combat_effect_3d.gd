extends Node3D

# Replay-driven effects: no wall-clock timers, damage or random state.
static var geometry_cache: Dictionary = {}
var material: StandardMaterial3D
var tint: Color
var kind := ""
var lifetime := 0.22
var reach := 0.4
var parts: Array[MeshInstance3D] = []

func _mesh(mesh: Mesh, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.position = at
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	parts.append(item)
	return item

func _arc(radius: float, thickness: float, sweep: float, height: float) -> void:
	var surface := ImmediateMesh.new()
	surface.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		var a := -sweep / 2 + sweep * i / 24
		var b := -sweep / 2 + sweep * (i + 1) / 24
		var points := [Vector3(sin(a) * radius, height, cos(a) * radius),
			Vector3(sin(a) * (radius - thickness), height, cos(a) * (radius - thickness)),
			Vector3(sin(b) * radius, height, cos(b) * radius),
			Vector3(sin(b) * (radius - thickness), height, cos(b) * (radius - thickness))]
		for index in [0, 1, 2, 2, 1, 3]: surface.surface_add_vertex(points[index])
	surface.surface_end()
	_mesh(surface)

func _spike(radius: float, length: float, at: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 5
	return _mesh(mesh, at)

func setup(effect: String, color: Color, size: float = 0.4) -> void:
	kind = effect
	tint = color
	reach = size
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	var cache_key := "%s:%s"%[kind,size]
	if kind!="beam" and geometry_cache.has(cache_key):
		var cached: Dictionary=geometry_cache[cache_key]
		lifetime=cached.lifetime
		rotation=cached.rotation
		_mesh(cached.mesh)
		return
	if kind in ["Axe", "Tidehunter", "mana_pulse"]:
		lifetime = 0.45 if kind == "Tidehunter" else 0.32
		_arc(1, 0.035, TAU if kind != "Axe" else PI * 1.65, 0.055 if kind != "Axe" else 0.30)
		if kind == "Tidehunter":
			_arc(0.78, 0.018, TAU, 0.065)
			for i in 8:
				var angle := i * TAU / 8
				_spike(0.035, 0.26, Vector3(sin(angle), 0.16, cos(angle)) * 0.85)
	elif kind in ["axe_attack", "pa_attack", "tide_attack", "critical_hit"]:
		lifetime = 0.18 if kind == "pa_attack" else 0.24
		_arc(size, 0.018 if kind == "pa_attack" else 0.035, PI * 0.80, 0)
		rotation.z = 0.45 if kind != "tide_attack" else -0.25
		if kind == "critical_hit": _arc(size * 0.70, 0.025, PI * 0.65, 0.035)
	elif kind in ["thrust", "heavy_attack", "claw_attack", "bow_release", "cast_spark", "spit_release"]:
		lifetime = .18
		if kind in ["claw_attack", "bow_release"]:
			for i in (3 if kind == "claw_attack" else 1): _arc(size, .015, PI * .55, i*.035)
		elif kind == "thrust":
			var point := _spike(.025,.30,Vector3(0,0,.12))
			point.rotation.x = PI / 2
		elif kind == "heavy_attack":
			_arc(size,.04,PI*.7,0)
			for i in 3: _spike(.022,.11,Vector3((i-1)*.08,0,0))
		else:
			for i in 4:
				var spark := _spike(.018,.12,Vector3.ZERO)
				spark.rotation.z = i * TAU / 4
	elif kind in ["skill_wave", "skill_guard", "skill_healing", "skill_summon", "skill_transform", "skill_hex", "skill_storm", "skill_line", "skill_bolt", "star_rune", "star_ember", "star_crystal", "star_leaf", "star_spark", "star_mote"]:
		lifetime = .35 if kind.begins_with("star_") else .38
		if kind in ["skill_wave", "skill_storm", "star_rune", "star_mote"]:
			_arc(1,.022,TAU,.03)
			if kind == "skill_storm": _arc(.7,.015,TAU,.045)
		elif kind in ["skill_guard", "skill_hex"]:
			_arc(.32,.025,TAU,.18)
			_arc(.32,.018,TAU,.45)
		else:
			for i in 6:
				var angle := i * TAU / 6
				var shard := _spike(.018 if kind.begins_with("star_") else .032,.12 if kind.begins_with("star_") else .25,Vector3(sin(angle)*.16,.08,cos(angle)*.16))
				shard.rotation.z = .55 if kind in ["star_leaf","skill_summon"] else 0
	elif kind == "beam":
		lifetime = .16
		var ray := _spike(.016,size,Vector3(0,0,-size*.5))
		ray.rotation.x = -PI / 2
	elif kind in ["bullet", "assassinate", "ice_bolt", "arrow", "poison_bolt", "fire_bolt", "water_bolt", "arcane_bolt", "glaive"]:
		if kind == "ice_bolt":
			var crystal := _spike(0.055, 0.19, Vector3.ZERO)
			crystal.rotation.x = -PI / 2
			var back := _spike(0.055, 0.10, Vector3(0, 0, 0.13))
			back.rotation.x = PI / 2
		elif kind == "glaive":
			_arc(.065,.022,TAU,0)
			parts[-1].rotation.x = PI / 2
		elif kind == "arrow":
			var tip := _spike(.034,.10,Vector3(0,0,-.04))
			tip.rotation.x = -PI / 2
		elif kind in ["poison_bolt", "fire_bolt", "water_bolt", "arcane_bolt"]:
			var orb := SphereMesh.new()
			orb.radius = .037
			orb.height = .074
			orb.radial_segments = 8
			orb.rings = 4
			_mesh(orb)
		var trail := _spike(0.012 if kind == "bullet" else 0.023, 0.25 if kind == "bullet" else 0.48, Vector3(0, 0, 0.16))
		trail.rotation.x = -PI / 2
	elif kind == "muzzle":
		lifetime = 0.075
		for i in 3:
			var spark := _spike(0.025, 0.14, Vector3.ZERO)
			spark.rotation = Vector3(PI / 2, 0, i * TAU / 3)
	else:
		lifetime = 0.16 if kind == "impact" else 0.24
		for i in 5:
			var angle := i * TAU / 5
			var shard := _spike(0.012 if kind == "impact" else 0.022, 0.10 if kind == "impact" else 0.17, Vector3(sin(angle), 0, cos(angle)) * 0.04)
			shard.rotation = Vector3(0.4, angle, 0.8)
	_merge_parts()
	if kind!="beam": geometry_cache[cache_key]={"mesh":parts[0].mesh,"lifetime":lifetime,"rotation":rotation}

func _merge_parts() -> void:
	# All parts share one translucent material; submit one mesh per effect.
	var vertices := PackedVector3Array()
	for item in parts:
		for surface in item.mesh.get_surface_count():
			var arrays := item.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices != null and indices.size() > 0:
				for index in indices: vertices.append(item.transform * points[index])
			else:
				for point in points: vertices.append(item.transform * point)
		item.free()
	parts.clear()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var combined := ArrayMesh.new()
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh(combined)

func sample(age: float) -> void:
	var progress := clampf(age / lifetime, 0, 1)
	material.albedo_color = Color(tint, tint.a * (1 - progress))
	if kind in ["Axe", "Tidehunter", "mana_pulse", "skill_wave", "skill_storm", "star_rune", "star_mote"]:
		var size := lerpf(0.18, reach, ease(progress, 0.6))
		scale = Vector3(size, 1, size)
	elif kind in ["axe_attack", "pa_attack", "tide_attack", "critical_hit"]:
		rotation.y = lerpf(-0.7, 0.7, progress)
	elif kind in ["skill_healing", "skill_summon", "skill_transform", "star_ember", "star_crystal", "star_leaf", "star_spark"]:
		position.y = progress * (.08 if kind.begins_with("star_") else .15)
	else:
		for item in parts:
			if kind not in ["bullet", "assassinate", "ice_bolt"]: item.scale = Vector3.ONE * (1 + progress * 0.6)
