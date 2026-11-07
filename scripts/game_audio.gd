extends Node

signal cue_played(path: String, category: String)

const BASE := "res://assets/combat_audio_v2/"
const UI_BASE := "res://assets/audio_preview_v3/"
const SETTINGS := "user://audio_settings_v1.cfg"
const SKILL_GAIN_DB := 4.0
const VICTORY_DB := -10.0
const VICTORY_SHORT := "res://assets/audio_v5/victory_short.wav"
const MUSIC := ["bgm_moonlit_forest.ogg", "bgm_floating_ruins.ogg", "bgm_volcanic_forge.ogg"]
const UI_FILES := {"refresh":"sfx_shop_refresh.wav", "buy":"sfx_piece_buy.wav", "sell":"sfx_piece_sell.wav", "upgrade":"sfx_piece_upgrade.wav", "defeat":"sfx_battle_defeat.wav"}
var catalog: Dictionary = {}
var by_name: Dictionary = {}
var by_ability: Dictionary = {}
var attacks: Dictionary = {}
var cache: Dictionary = {}
var rotation: Dictionary = {}
var voices: Array = []
var bodies: Dictionary = {}
var throttle: Dictionary = {}
var queue: Array = []
var critical_hits: Dictionary = {}
var cursor := 0
var replay_key := ""
var music_player: AudioStreamPlayer
var countdown_player: AudioStreamPlayer
var music_track := ""
var music_mode := 0
var phase := "menu"
var paused := false
var countdown_round := -1
var countdown_started := false
var volumes := {"Master":0.8, "GameMusic":0.35, "GameSFX":0.8, "GameUI":0.85}
var debug_events: Array = []


func _ready() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(BASE + "manifest.json"))
	for unit in data["units"]:
		catalog[unit.id] = unit
		by_ability[unit.kind] = unit.id
		var stages: Dictionary = {}
		for event in unit.events:
			if not stages.has(event.stage): stages[event.stage] = []
			stages[event.stage].append(BASE + str(event.file))
		unit["stages"] = stages
	var content = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	for unit in content.units:
		var ident := str(unit.name_en).to_lower().replace("'", "_").replace(" ", "_").replace("-", "_")
		by_name[unit.name_en] = ident
	for event in data.basic_attacks:
		var key: String = str(event.file).get_base_dir().get_file() + "/" + str(event.stage)
		if not attacks.has(key): attacks[key] = []
		attacks[key].append(BASE + str(event.file))
	for bus in ["GameMusic", "GameSFX", "GameUI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	if ClassDB.class_exists("AudioEffectHardLimiter"):
		AudioServer.add_bus_effect(AudioServer.get_bus_index("GameSFX"), ClassDB.instantiate("AudioEffectHardLimiter"))
		var limiter = ClassDB.instantiate("AudioEffectHardLimiter")
		limiter.resource_name = "GameAudioSafety"
		var installed := false
		for effect in range(AudioServer.get_bus_effect_count(0)):
			if AudioServer.get_bus_effect(0,effect).resource_name == "GameAudioSafety": installed = true
		if not installed: AudioServer.add_bus_effect(0,limiter)
	music_player = AudioStreamPlayer.new()
	music_player.bus = &"GameMusic"
	add_child(music_player)
	countdown_player = AudioStreamPlayer.new()
	countdown_player.bus = &"GameUI"
	add_child(countdown_player)
	var settings := ConfigFile.new()
	if settings.load(SETTINGS) == OK:
		for bus in volumes: volumes[bus] = clampf(float(settings.get_value("volume", bus, volumes[bus])), 0, 1)
		music_mode = clampi(int(settings.get_value("music", "mode", 0)), 0, 3)
	for bus in volumes: _apply_volume(bus)
	set_phase("menu")


func stream(path: String) -> AudioStream:
	if cache.has(path): return cache[path]
	var sound: AudioStream
	if FileAccess.file_exists(path):
		sound = AudioStreamOggVorbis.load_from_file(path) if path.ends_with(".ogg") else AudioStreamWAV.load_from_file(path)
	else:
		# Exported projects use Godot's imported resource remaps instead of raw source WAVs.
		sound = load(path) as AudioStream
	if sound != null:
		if cache.size() >= 96: cache.erase(cache.keys()[0])
		cache[path] = sound
	return sound


func _exit_tree() -> void:
	for player in voices:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player in [music_player, countdown_player]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	bodies.clear()
	voices.clear()
	cache.clear()


func _record(path: String, category: String) -> void:
	debug_events.append({"path":path, "category":category})
	if debug_events.size() > 256: debug_events.pop_front()
	cue_played.emit(path, category)


func _play(path: String, category: String, position: Vector2 = Vector2(-1,-1), db: float = -5.0, offset: float = 0.0) -> AudioStreamPlayer2D:
	var sound := stream(path)
	if sound == null: return null
	for voice in voices.duplicate():
		if not is_instance_valid(voice) or not voice.playing:
			voices.erase(voice)
			if is_instance_valid(voice): voice.queue_free()
	var limit := 24 if category == "attack" else 12
	var same: Array = voices.filter(func(v): return is_instance_valid(v) and str(v.get_meta("category", "")) == category)
	if same.size() >= limit:
		var old = same[0]
		old.stop()
		voices.erase(old)
		old.queue_free()
	var player := AudioStreamPlayer2D.new()
	player.stream = sound
	player.bus = &"GameUI" if category == "ui" else &"GameSFX"
	player.volume_db = db
	player.max_distance = 1800
	player.panning_strength = 0.55
	player.position = get_viewport().get_visible_rect().size * .5
	if position.x >= 0: player.position += Vector2((position.x-3.5)*65, (position.y-3.5)*35)
	player.set_meta("category", category)
	add_child(player)
	voices.append(player)
	player.play(offset)
	player.stream_paused = paused
	_record(path, category)
	return player


func ui(name: String) -> void:
	if name == "victory":
		_play(VICTORY_SHORT, "ui", Vector2(-1,-1), VICTORY_DB)
		return
	if UI_FILES.has(name): _play(UI_BASE + UI_FILES[name], "ui", Vector2(-1,-1), -2)


func _variant(paths: Array, key: String) -> String:
	if paths.is_empty(): return ""
	var index := int(rotation.get(key, 0)) % paths.size()
	rotation[key] = index + 1
	return str(paths[index])


func skill(ident: String, stage: String, pos: Vector2, time: float, uid: int = -1, star: int = 1) -> void:
	if not catalog.has(ident): return
	var stages: Dictionary = catalog[ident].stages
	if ident == "beastmaster" and stage == "release": stage = "summon_s%d" % clampi(star,1,3)
	if not stages.has(stage): return
	var key := ident + "/" + stage
	# Merge simultaneous AoE hits and short repeated status/damage ticks.
	if time - float(throttle.get(key, -INF)) < (0.13 if stage == "hit" else 0.06): return
	throttle[key] = time
	var body := stage.begins_with("body_s")
	if body:
		stop_body(uid)
		if bodies.size() >= 4: return
	var player = _play(_variant(stages[stage], key), "body" if body else "skill", pos, (-12 if body else -5) + SKILL_GAIN_DB)
	if body and player != null:
		bodies[uid] = {"player":player, "end":time + player.stream.get_length(), "id":ident}


func stop_body(uid: int) -> void:
	if not bodies.has(uid): return
	var player = bodies[uid].player
	if is_instance_valid(player): player.stop()
	bodies.erase(uid)


func stop_combat() -> void:
	for player in voices:
		if is_instance_valid(player) and str(player.get_meta("category", "")) != "ui": player.stop()
	bodies.clear()
	queue.clear()
	critical_hits.clear()
	cursor = 0
	replay_key = ""
	throttle.clear()


func set_paused(value: bool) -> void:
	paused = value
	for player in voices:
		if is_instance_valid(player): player.stream_paused = value
	music_player.stream_paused = value
	countdown_player.stream_paused = value


func set_phase(value: String) -> void:
	phase = value
	var index := music_mode - 1 if music_mode > 0 else 2 if value == "battle" else 0 if value == "preparation" else 1
	var path: String = UI_BASE + MUSIC[index]
	if music_track == path: return
	music_track = path
	var music = stream(path)
	if music is AudioStreamOggVorbis: music.loop = true
	music_player.stream = music
	music_player.volume_db = -6
	music_player.play()
	music_player.stream_paused = paused


func countdown(remaining: float, round_id: int, enabled: bool) -> void:
	if round_id != countdown_round or remaining > 5 or not enabled:
		countdown_player.stop()
		countdown_started = false
		countdown_round = round_id
	if enabled and remaining > 0 and remaining <= 5 and not countdown_started:
		countdown_started = true
		var path := UI_BASE + "sfx_prepare_countdown_5s.wav"
		countdown_player.stream = stream(path)
		countdown_player.play(maxf(0, 5-remaining))
		countdown_player.stream_paused = paused
		_record(path, "countdown")


func begin_replay(key: String, replay: Dictionary, elapsed: float) -> void:
	stop_combat()
	replay_key = key
	for raw in replay.get("visual_events", []):
		var event: Dictionary = raw.duplicate()
		if event.kind == "critical_hit" or bool(event.get("replace_basic",false)):
			critical_hits["%d:%d:%d" % [int(event.uid),int(event.target_uid),roundi(float(event.time)*1000)]] = true
		if event.kind == "cast_release" and str(event.get("ability","")) == "cold_embrace":
			var thaw: Dictionary = event.duplicate()
			thaw.kind = "audio_thaw"
			thaw.time = float(event.time) + float(event.get("duration",0))
			queue.append(thaw)
		if event.kind == "attack":
			if not bool(event.get("released", false)): continue
			event.time = float(event.release_time)
		elif event.kind == "cast":
			if not bool(event.get("released", false)): continue
			var actor: Dictionary = {}
			if not replay.get("frames", []).is_empty(): actor = _actor(replay.frames[0], int(event.uid))
			var ident := _ident(actor, event)
			if not catalog.has(ident) or not catalog[ident].stages.has("prepare"): continue
			var duration := stream(catalog[ident].stages.prepare[0]).get_length()
			event.time = maxf(float(event.time), float(event.release_time) - duration)
			event.kind = "prepare"
		queue.append(event)
	queue.sort_custom(func(a,b): return float(a.time) < float(b.time))
	# On view switching do not replay historical sounds or start historical bodies.
	while cursor < queue.size() and float(queue[cursor].time) < elapsed - 0.05: cursor += 1


func _actor(frame: Dictionary, uid: int) -> Dictionary:
	for actor in frame.get("actors", []):
		if int(actor.uid) == uid: return actor
	return {}


func _ident(actor: Dictionary, event: Dictionary = {}) -> String:
	var ident: String = by_name.get(str(actor.get("id", "")), "")
	var ability := str(event.get("ability", ""))
	if ability != "" and catalog.has(ident) and str(catalog[ident].kind) != ability:
		return str(by_ability.get(ability, ident))
	return ident


func _attack(actor: Dictionary, stage: String, pos: Vector2, time: float) -> void:
	var range_value := float(actor.get("range", 1))
	var family := "melee" if range_value <= 1 else "ranged"
	var name := str(actor.get("id", ""))
	var material := "blade" if family == "melee" else "arrow"
	if name in ["Tusk", "Tiny", "Treant Protector", "Tidehunter", "Ogre Magi", "Alchemist"]: material = "blunt"
	if bool(actor.get("monster",false)) or bool(actor.get("summon",false)) or name in ["Slark", "Nyx Assassin", "Sand King"]: material = "claw" if family == "melee" else "element"
	if name in ["Sniper", "Gyrocopter", "Techies"]: material = "gun"
	if family == "ranged" and name in ["Morphling", "Viper", "Venomancer", "Puck", "Lich", "Crystal Maiden", "Terrorblade", "Dragon Knight", "Zeus", "Lina", "Shadow Fiend"]: material = "element"
	var key := "attack_" + family + "_" + material + "/" + stage
	if not attacks.has(key) or time - float(throttle.get(key, -INF)) < .045: return
	throttle[key] = time
	_play(_variant(attacks[key], key), "attack", pos, -13)


func sync(replay: Dictionary, frame: Dictionary, elapsed: float, key: String) -> void:
	if replay_key != key: begin_replay(key, replay, elapsed)
	for uid in bodies.keys():
		var body: Dictionary = bodies[uid]
		var actor := _actor(frame, int(uid))
		var controlled: bool = body.id in ["lion", "clockwerk", "juggernaut", "batrider", "death_prophet", "morphling", "sand_king", "pudge"]
		var dead := actor.is_empty() or float(actor.get("hp",0)) <= 0
		var interrupted := false
		if body.id == "lion":
			for status in ["silence", "stun", "petrify", "hex"]:
				if float(actor.get("statuses",{}).get(status,{}).get("end",0)) > elapsed: interrupted = true
		if elapsed >= float(body.end) or (controlled and dead) or interrupted: stop_body(int(uid))
	while cursor < queue.size() and float(queue[cursor].time) <= elapsed:
		var event: Dictionary = queue[cursor]
		cursor += 1
		if elapsed - float(event.time) > .20: continue
		var actor := _actor(frame, int(event.uid))
		if actor.is_empty(): continue
		var pos: Vector2 = actor.pos
		var ident := _ident(actor, event)
		var star := int(actor.get("star",1))
		match str(event.kind):
			"attack":
				if ident == "troll_warlord": skill(ident,"proc",pos,float(event.time))
				else: _attack(actor,"release",pos,float(event.time))
			"hit":
				if not bool(event.get("basic",false)): continue
				var source := _actor(frame,int(event.target_uid))
				var critical_key := "%d:%d:%d" % [int(event.target_uid),int(event.uid),roundi(float(event.time)*1000)]
				if not source.is_empty() and not (str(source.id) in ["Phantom Assassin","Tusk"] and critical_hits.has(critical_key)):
					_attack(source,"hit",pos,float(event.time))
			"prepare": skill(ident,"prepare",pos,float(event.time))
			"cast_release":
				if ident != "tusk": skill(ident,"release",pos,float(event.time),int(actor.uid),star)
				# Instantaneous runtime effects do not acquire the audition's invented travel bed.
				if float(event.get("duration",0)) > 0 and ident not in ["morphling","sand_king","pudge","kunkka","razor"]:
					skill(ident,"body_s%d" % star,pos,float(event.time),int(actor.uid),star)
			"skill_hit":
				if ident == "mars": skill(ident,"proc",pos,float(event.time))
				elif ident == "luna": skill(ident,"proc",pos,float(event.time))
				elif ident not in ["abaddon","templar_assassin","nyx_assassin","medusa"]: skill(ident,"hit",pos,float(event.time))
			"mana_pulse": skill(ident,"pulse",pos,float(event.time))
			"critical_hit":
				if ident == "phantom_assassin": skill(ident,"proc",pos,float(event.time))
			"skill_proc":
				if ident == "medusa":
					var target := _actor(frame,int(event.target_uid))
					if not target.is_empty(): pos = target.pos
				skill(ident,str(event.get("stage","proc")),pos,float(event.time))
			"audio_thaw":
				var target := _actor(frame,int(event.target_uid))
				if not target.is_empty() and float(target.hp) > 0 and float(target.get("statuses",{}).get("physical_immune",{}).get("end",0)) <= elapsed:
					skill("winter_wyvern","hit",target.pos,float(event.time))
			"die":
				if bodies.has(int(actor.uid)) and str(bodies[int(actor.uid)].id) not in ["enigma","disruptor"]: stop_body(int(actor.uid))


func _apply_volume(bus: String) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), linear_to_db(maxf(.00001,float(volumes[bus]))))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), float(volumes[bus]) <= 0)


func save_settings() -> void:
	var settings := ConfigFile.new()
	for bus in volumes: settings.set_value("volume",bus,volumes[bus])
	settings.set_value("music","mode",music_mode)
	settings.save(SETTINGS)


func settings_panel() -> PopupPanel:
	var panel := PopupPanel.new()
	panel.name = "AudioSettingsV1"
	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(420,280)
	panel.add_child(layout)
	var heading := Label.new()
	heading.text = "声音设置"
	layout.add_child(heading)
	for entry in [["Master","总音量"],["GameMusic","背景音乐"],["GameSFX","战斗音效"],["GameUI","操作与提示"]]:
		var label := Label.new()
		label.text = str(entry[1]) + "（0 为静音）"
		layout.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.value = float(volumes[entry[0]]) * 100
		layout.add_child(slider)
		var bus := str(entry[0])
		slider.value_changed.connect(func(value): volumes[bus] = value / 100.0; _apply_volume(bus); save_settings())
	var choice := OptionButton.new()
	for title in ["音乐：按阶段自动切换", "音乐：月夜森林", "音乐：浮空遗迹", "音乐：火山锻炉"]: choice.add_item(title)
	choice.select(music_mode)
	choice.item_selected.connect(func(index): music_mode = index; set_phase(phase); save_settings())
	layout.add_child(choice)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(panel.hide)
	layout.add_child(close)
	return panel
