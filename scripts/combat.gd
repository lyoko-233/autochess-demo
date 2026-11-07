extends RefCounted

const Effects = preload("res://scripts/ability_effects.gd")
const TICK := 0.1

var content: Dictionary
var units: Dictionary = {}
var monsters: Dictionary = {}
var actors: Array = []
var events: Array = []
var battle_log: Array = []
var rng := RandomNumberGenerator.new()
var time := 0.0
var effects: RefCounted
var in_overtime := false
var capture_frames := false
var frames: Array = []
var visual_events: Array = []
var visual_frame_due := false


func _init(runtime_content: Dictionary) -> void:
	content = runtime_content
	for unit in content["units"]:
		units[unit["name_en"]] = unit
	for monster in content["monsters"]:
		monsters[monster["id"]] = monster
	effects = Effects.new(self)


func _roll_percent(chance: float) -> bool:
	return rng.randf() * 100.0 < chance


func _star_value(source: Dictionary, key: String, star: int, fallback: float = 0.0) -> float:
	if not source.has(key):
		return fallback
	var value = source[key]
	if typeof(value) == TYPE_ARRAY:
		return float(value[clampi(star - 1, 0, value.size() - 1)]) if not value.is_empty() else fallback
	return float(value)


func _make_actor(piece: Dictionary, team: int) -> Dictionary:
	var monster := piece.has("monster_id")
	var definition: Dictionary = monsters[piece["monster_id"]] if monster else units[piece["id"]]
	var star := 1 if monster else int(piece.get("star", 1))
	var hp := float(definition["hp"] if monster else definition["hp"][star - 1])
	var position: Vector2
	if piece.has("col"):
		position = Vector2(piece["col"], piece["row"])
	else:
		var index := int(piece["position"])
		position = Vector2(index % 8, index / 8) if team == 0 else Vector2(7 - index % 8, 7 - index / 8)
	var actor := {"uid": actors.size(), "name": definition["name_zh"], "id": piece["monster_id"] if monster else piece["id"],
		"team": team, "monster": monster, "summon": false, "star": star, "pos": position,
		"origin": int(piece.get("position", -1)),
		"hp": hp, "max_hp": hp,
		"attack_min": float(definition["attack_damage"] if monster else definition["attack_min"][star - 1]),
		"attack_max": float(definition["attack_damage"] if monster else definition["attack_max"][star - 1]),
		"armor": float(definition["armor"] if monster else definition["armor"][star - 1]),
		"mr": float(definition["magic_resistance_percent"] if monster else definition["magic_resistance_percent"][star - 1]),
		"bat": float(definition["base_attack_time_s"]), "attack_point": float(definition["attack_point_s"]),
		"range": float(definition["attack_range_grids"]),
		"speed": float(definition["movement_speed_units_per_s"] if monster else definition["movement_speed"]),
		"projectile": float(definition["attack_projectile_speed_units_per_s"]),
		"mana": float(definition["initial_mana"]) + float(piece.get("opening_mana_bonus", 0)), "max_mana": float(definition["max_mana"]),
		"mana_attack": 0.0 if monster else float(definition["mana_gain_on_attack"]),
		"mana_damage": 0.0 if monster else float(definition["mana_gain_on_damage"]),
		"ability": definition["ability"], "tags": [] if monster else (Array(str(definition["species"]).split("、")) + [definition["class"]]),
		"items": piece.get("items", []).duplicate(true), "item_stats": {}, "statuses": {}, "pending_attack": {},
		"attack_release": -1.0, "next_attack": 0.0, "cast_release": -1.0,
		"next_cast": float(definition["ability"].get("initial_cooldown_s", 0.0)), "ability_target": {}, "last_target": "", "stacks": 0,
		"ability_state": {}, "regen": 0.0, "attack_speed": 0.0, "bonus_attack": 0.0,
		"damage_dealt": 0.0, "damage_taken": 0.0, "healing_done": 0.0,
		"shield": 0.0, "blocks": 0, "alive_counted": true, "move_progress": 0.0}
	for item in actor["items"]:
		var item_id: String = item["id"] if typeof(item) == TYPE_DICTIONARY else str(item)
		if not content["items"].has(item_id):
			continue
		for key in content["items"][item_id]["stats"]:
			actor["item_stats"][key] = float(actor["item_stats"].get(key, 0.0)) + float(content["items"][item_id]["stats"][key])
	var stats: Dictionary = actor["item_stats"]
	actor["attack_min"] += float(stats.get("attack_flat", 0))
	actor["attack_max"] += float(stats.get("attack_flat", 0))
	actor["armor"] += float(stats.get("armor_flat", 0))
	actor["mr"] += float(stats.get("magic_resistance_percent", 0))
	actor["attack_speed"] += float(stats.get("attack_speed_percent", 0))
	actor["regen"] += float(stats.get("regen_per_s", 0))
	actor["max_hp"] = (actor["max_hp"] + float(stats.get("health_flat", 0))) * (1.0 + float(stats.get("health_percent", 0)) / 100.0)
	actor["hp"] = actor["max_hp"]
	actor["mana"] = min(actor["mana"], actor["max_mana"])
	return actor


func simulate(home: Array, away: Array, seed_value: int, limit_s: float = 60.0,
		monster_wave: int = 0, allow_overtime: bool = false, record_frames: bool = false) -> Dictionary:
	rng.seed = seed_value
	time = 0.0
	in_overtime = false
	capture_frames = record_frames
	frames.clear()
	visual_events.clear()
	visual_frame_due = false
	actors.clear()
	events.clear()
	battle_log.clear()
	for piece in home:
		actors.append(_make_actor(piece, 0))
	for piece in away:
		var enemy: Dictionary = _make_actor(piece, 1)
		if enemy["monster"] and monster_wave > 0:
			enemy["max_hp"] = floor(enemy["max_hp"] * pow(1.15, monster_wave) + 0.5)
			enemy["hp"] = enemy["max_hp"]
			enemy["attack_min"] = floor(enemy["attack_min"] * pow(1.1, monster_wave) + 0.5)
			enemy["attack_max"] = enemy["attack_min"]
			enemy["armor"] += 2 * monster_wave
			enemy["mr"] = min(75.0, enemy["mr"] + 2 * monster_wave)
			if enemy["ability"].has("effect"):
				var scaled_effect: Dictionary = enemy["ability"]["effect"].duplicate(true)
				for key in ["damage", "damage_per_second"]:
					if scaled_effect.has(key): scaled_effect[key] = floor(float(scaled_effect[key]) * pow(1.1, monster_wave) + 0.5)
				enemy["ability"] = enemy["ability"].duplicate(true)
				enemy["ability"]["effect"] = scaled_effect
		actors.append(enemy)
	_apply_start_effects()
	var steps := int(ceil(limit_s / TICK))
	for step in range(steps + 1):
		time = step * TICK
		_process_events()
		for actor in actors.duplicate():
			if actor["hp"] > 0:
				_tick_actor(actor)
		_process_events()
		if capture_frames and (step % 2 == 0 or visual_frame_due): _capture_frame()
		var remaining := _remaining()
		if remaining[0] == 0 or remaining[1] == 0:
			if capture_frames and step % 2 != 0: _capture_frame()
			return _result(remaining)
	if allow_overtime:
		var before_hp := [0.0, 0.0]
		for actor in actors:
			if actor["hp"] > 0: before_hp[actor["team"]] += actor["hp"]
		in_overtime = true
		var overtime_steps := int(round(minf(float(content["economy"]["overtime_seconds"]),
			float(content["economy"]["max_battle_seconds"]) - limit_s) / TICK))
		for step in range(1, overtime_steps + 1):
			time = limit_s + step * TICK
			for actor in actors.duplicate():
				if actor["hp"] > 0: _tick_actor(actor)
			_process_events()
			if step % 10 == 0:
				for actor in actors:
					if actor["hp"] > 0:
						var overtime_damage := minf(float(actor["hp"]), float(actor["max_hp"]) * 0.05)
						actor["hp"] -= overtime_damage
						actor["damage_taken"] += overtime_damage
			if capture_frames and (step % 2 == 0 or visual_frame_due): _capture_frame()
			var remaining := _remaining()
			if remaining[0] == 0 or remaining[1] == 0:
				if capture_frames and step % 2 != 0: _capture_frame()
				var result := _result(remaining)
				if result["winner"] == -1:
					result["winner"] = 0 if before_hp[0] > before_hp[1] else 1 if before_hp[1] > before_hp[0] else rng.randi_range(0, 1)
				return result
		if capture_frames and (frames.is_empty() or float(frames.back()["time"]) < time): _capture_frame()
		var final_result := _result(_remaining())
		if final_result["winner"] == -1:
			final_result["winner"] = 0 if before_hp[0] > before_hp[1] else 1 if before_hp[1] > before_hp[0] else rng.randi_range(0, 1)
		return final_result
	return _result(_remaining())


func _result(remaining: Array) -> Dictionary:
	var winner := -1
	if remaining[0] > 0 and remaining[1] == 0:
		winner = 0
	elif remaining[1] > 0 and remaining[0] == 0:
		winner = 1
	return {"winner": winner, "seconds": time, "survivors": remaining,
		"actors": actors, "log": battle_log.duplicate(), "frames": frames.duplicate() if capture_frames else [],
		"visual_events": visual_events.duplicate() if capture_frames else []}


func visual_event(kind: String, actor: Dictionary, target: Dictionary = {}, extra: Dictionary = {}) -> void:
	if not capture_frames: return
	var event := {"time": time, "kind": kind, "uid": actor["uid"],
		"target_uid": target.get("uid", -1), "ability": actor["ability"].get("kind", "")}
	event.merge(extra)
	visual_events.append(event)
	if kind in ["hit", "die", "projectile_end", "status", "mana_pulse", "heal"]: visual_frame_due = true
	if kind in ["attack", "cast"]: actor["visual_%s_event_index" % kind] = visual_events.size() - 1


func _visual_release(kind: String, actor: Dictionary) -> void:
	if not capture_frames: return
	var index := int(actor.get("visual_%s_event_index" % kind, -1))
	if index >= 0:
		visual_events[index]["release_time"] = time
		visual_events[index]["released"] = true


func _capture_frame() -> void:
	visual_frame_due = false
	if not frames.is_empty() and is_equal_approx(float(frames.back()["time"]), time): return
	var snapshot: Array = []
	for actor in actors:
		snapshot.append({"uid": actor["uid"], "id": actor["id"], "name": actor["name"], "team": actor["team"],
			"pos": actor["pos"], "star": actor["star"], "hp": actor["hp"], "max_hp": actor["max_hp"],
			"mana": actor["mana"], "max_mana": actor["max_mana"], "shield": actor["shield"], "items": actor["items"],
			"monster": actor["monster"], "summon": actor["summon"], "origin": actor["origin"],
			"statuses": actor["statuses"].duplicate(true), "form":str(actor.get("visual_form","")), "range":actor["range"]})
	frames.append({"time": time, "actors": snapshot})


func _remaining() -> Array:
	var counts := [0, 0]
	for actor in actors:
		if actor["hp"] > 0:
			counts[actor["team"]] += 1
	return counts


func cell_is_free(cell: Vector2, moving: Dictionary = {}) -> bool:
	if cell.x < 0 or cell.x > 7 or cell.y < 0 or cell.y > 7: return false
	for actor in actors:
		if (moving.is_empty() or int(actor["uid"]) != int(moving["uid"])) and actor["hp"] > 0 and actor["pos"].round() == cell:
			return false
	return true


func place_near(actor: Dictionary, wanted: Vector2) -> bool:
	var center := wanted.round().clamp(Vector2.ZERO, Vector2(7, 7))
	var best := Vector2(-1, -1)
	var distance := INF
	for y in range(8):
		for x in range(8):
			var cell := Vector2(x, y)
			if not cell_is_free(cell, actor): continue
			var gap := cell.distance_squared_to(center)
			if gap < distance:
				best = cell
				distance = gap
	if best.x < 0: return false
	actor["pos"] = best
	return true


func _move_toward(actor: Dictionary, target: Dictionary) -> void:
	actor["move_progress"] = minf(1.0, float(actor["move_progress"]) + float(actor["speed"]) / 100.0 * TICK)
	if float(actor["move_progress"]) < 1.0: return
	var current: Vector2 = actor["pos"]
	var best := current
	var gap := current.distance_squared_to(target["pos"])
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var cell := current + Vector2(dx, dy)
			if not cell_is_free(cell, actor): continue
			var next_gap := cell.distance_squared_to(target["pos"])
			if next_gap < gap:
				best = cell
				gap = next_gap
	if best != current:
		actor["pos"] = best
		actor["move_progress"] -= 1.0


func _apply_start_effects() -> void:
	var species_tags: Dictionary = {}
	for unit in content["units"]:
		for species in str(unit["species"]).split("、"):
			species_tags[species] = true
	for team in [0, 1]:
		var unique_tags: Dictionary = {}
		for actor in actors:
			if actor["team"] == team and not actor["monster"]:
				for tag in actor["tags"]:
					if not unique_tags.has(tag):
						unique_tags[tag] = []
					if not unique_tags[tag].has(actor["id"]):
						unique_tags[tag].append(actor["id"])
		var counts: Dictionary = {}
		for tag in unique_tags: counts[tag] = unique_tags[tag].size()
		if int(counts.get("巫师", 0)) >= 2:
			var best_tag := ""
			var best_gap := 100
			for synergy in content["synergies"]:
				var tag: String = synergy["tag"]
				if tag == "巫师" or int(counts.get(tag, 0)) == 0: continue
				for tier in synergy["tiers"]:
					var gap := int(tier) - int(counts[tag])
					if gap > 0 and (gap < best_gap or (gap == best_gap and (best_tag == "" or tag < best_tag))):
						best_gap = gap
						best_tag = tag
					break
			if best_tag != "": counts[best_tag] += 1
		var demon_ids: Dictionary = {}
		var enemy_demon_hunters: Dictionary = {}
		for actor in actors:
			if actor["team"] == team and "恶魔" in actor["tags"]: demon_ids[actor["id"]] = true
			if actor["team"] != team and "恶魔猎手" in actor["tags"]: enemy_demon_hunters[actor["id"]] = true
		var active_other_species := false
		for synergy in content["synergies"]:
			var tag: String = synergy["tag"]
			if tag == "神" or not species_tags.has(tag) or int(counts.get(tag, 0)) < int(synergy["tiers"][0]): continue
			if tag == "恶魔" and (not enemy_demon_hunters.is_empty() or (demon_ids.size() != 1 and int(counts.get("恶魔猎手", 0)) < 2)):
				continue
			active_other_species = true
			break
		var team_allies: Array = actors.filter(func(a): return a["team"] == team and a["hp"] > 0)
		var chosen_goblin: Dictionary = team_allies[rng.randi_range(0, team_allies.size() - 1)] if not team_allies.is_empty() else {}
		var chosen_shaman_enemy: Dictionary = {}
		var enemy_list: Array = actors.filter(func(a): return a["team"] != team and a["hp"] > 0)
		if not enemy_list.is_empty(): chosen_shaman_enemy = enemy_list[rng.randi_range(0, enemy_list.size() - 1)]
		for enemy in actors:
			if enemy["team"] == team: continue
			if int(counts.get("亡灵", 0)) >= 2:
				enemy["armor"] -= 14 if int(counts["亡灵"]) >= 6 else 8 if int(counts["亡灵"]) >= 4 else 4
			if int(counts.get("法师", 0)) >= 3:
				enemy["mr"] -= 100 if int(counts["法师"]) >= 9 else 65 if int(counts["法师"]) >= 6 else 30
		for actor in actors:
			if actor["team"] != team:
				continue
			if int(counts.get("地精", 0)) >= 3:
				if int(counts["地精"]) >= 6 or actor == chosen_goblin:
					actor["armor"] += 12
					actor["regen"] += 10
			if int(counts.get("精灵", 0)) >= 3:
				if "精灵" in actor["tags"]: actor["ability_state"]["evasion"] = 25
				if int(counts["精灵"]) >= 6: actor["ability_state"]["evasion"] = int(actor["ability_state"].get("evasion", 0)) + 15
				if int(counts["精灵"]) >= 9: actor["ability_state"]["evasion"] = min(75, int(actor["ability_state"].get("evasion", 0)) + 45)
			if int(counts.get("人类", 0)) >= 2 and ("人类" in actor["tags"] or int(counts["人类"]) >= 6):
				actor["ability_state"]["human_silence_chance"] = 40 if int(counts["人类"]) >= 6 else 30 if int(counts["人类"]) >= 4 else 20
			if "恶魔" in actor["tags"] and enemy_demon_hunters.is_empty() and (demon_ids.size() == 1 or int(counts.get("恶魔猎手", 0)) >= 2):
				actor["ability_state"]["demon_pure"] = true
			if int(counts.get("元素", 0)) >= 2 and ("元素" in actor["tags"] or int(counts["元素"]) >= 4):
				actor["ability_state"]["element_retaliate"] = true
			if int(counts.get("矮人", 0)) >= 2 and "矮人" in actor["tags"]:
				actor["range"] += 3
				actor["ability_state"]["target_lowest_hp"] = true
			if int(counts.get("食人魔", 0)) >= 2 and "食人魔" in actor["tags"]:
				actor["ability_state"]["ogre_stack"] = 0
			if int(counts.get("虫族", 0)) >= 2:
				actor["ability_state"]["insect_tier"] = 4 if int(counts["虫族"]) >= 4 else 2
			if int(counts.get("刺客", 0)) >= 3 and "刺客" in actor["tags"]:
				actor["ability_state"]["assassin_crit"] = 700 if int(counts["刺客"]) >= 9 else 500 if int(counts["刺客"]) >= 6 else 300
			if int(counts.get("萨满", 0)) >= 2 and actor == team_allies.front() and not chosen_shaman_enemy.is_empty():
				status(chosen_shaman_enemy, "hex", 6.0)
			if unique_tags.get("野兽", []).size() >= 2:
				actor["bonus_attack"] += actor["attack_max"] * (0.4 if unique_tags["野兽"].size() >= 4 else 0.15)
			if unique_tags.get("骑士", []).size() >= 2 and ("骑士" in actor["tags"] or unique_tags["骑士"].size() >= 6):
				actor["ability_state"]["knight_chance"] = 85 if unique_tags["骑士"].size() >= 6 else 60 if unique_tags["骑士"].size() >= 4 else 35
			if unique_tags.get("战士", []).size() >= 3 and "战士" in actor["tags"]:
				actor["armor"] += 23 if unique_tags["战士"].size() >= 9 else 12 if unique_tags["战士"].size() >= 6 else 7
			if unique_tags.get("娜迦", []).size() >= 2:
				actor["mr"] += 45 if unique_tags["娜迦"].size() >= 4 else 30
			if unique_tags.get("工匠", []).size() >= 2 and "工匠" in actor["tags"]:
				actor["regen"] += 35 if unique_tags["工匠"].size() >= 4 else 15
			if unique_tags.get("术士", []).size() >= 2:
				actor["ability_state"]["warlock_lifesteal"] = 60 if unique_tags["术士"].size() >= 6 else 30 if unique_tags["术士"].size() >= 4 else 15
			if unique_tags.get("龙", []).size() >= 3 and ("龙" in actor["tags"] or unique_tags["龙"].size() >= 5):
				actor["mana"] = actor["max_mana"]
			if unique_tags.get("兽人", []).size() >= 2 and "兽人" in actor["tags"]:
				var hp_extra := 600 if unique_tags["兽人"].size() >= 4 else 250
				actor["max_hp"] += hp_extra
				actor["hp"] += hp_extra
			if unique_tags.get("猎人", []).size() >= 3 and "猎人" in actor["tags"]:
				actor["bonus_attack"] += 55 if unique_tags["猎人"].size() >= 6 else 25
				actor["ability_state"]["accuracy_bonus"] = 40 if unique_tags["猎人"].size() >= 6 else 20
			if unique_tags.get("巨魔", []).size() >= 2 and "巨魔" in actor["tags"]:
				actor["attack_speed"] += 35
			if unique_tags.get("巨魔", []).size() >= 4:
				actor["attack_speed"] += 70 if unique_tags["巨魔"].size() >= 6 else 30
			if int(counts.get("神", 0)) >= 2 and not active_other_species:
				actor["ability_state"]["cooldown_scale"] = 0.25 if unique_tags["神"].size() >= 4 else 0.5
			effects.on_battle_start(actor)


func _tick_actor(actor: Dictionary) -> void:
	if actor["regen"] > 0:
		heal(actor, actor["regen"] * TICK)
	if actor["statuses"].get("regen_bonus", {}).get("end", 0.0) > time:
		heal(actor, float(actor["statuses"]["regen_bonus"]["strength"]) * TICK)
	if actor["statuses"].get("stun", {}).get("end", 0.0) > time or actor["statuses"].get("petrify", {}).get("end", 0.0) > time or actor["statuses"].get("hex", {}).get("end", 0.0) > time:
		actor["attack_release"] = -1.0
		return
	effects.on_tick(actor, TICK)
	if actor["attack_release"] >= 0 and time >= actor["attack_release"]:
		_visual_release("attack", actor)
		var target: Dictionary = actor["pending_attack"]
		if not target.is_empty() and target["hp"] > 0:
			var raw: float = rng.randi_range(int(actor["attack_min"]), int(actor["attack_max"])) + actor["bonus_attack"]
			raw = effects.on_basic_attack(actor, target, raw)
			var travel: float = actor["pos"].distance_to(target["pos"]) * 100.0 / actor["projectile"] if actor["projectile"] > 0 else 0.0
			schedule_damage(actor, target, raw, "physical", travel, true)
		actor["attack_release"] = -1.0
	if actor["cast_release"] >= 0 and time >= actor["cast_release"]:
		_visual_release("cast", actor)
		effects.cast(actor, actor["ability_target"])
		actor["cast_release"] = -1.0
		return
	if actor["cast_release"] >= 0 or actor["attack_release"] >= 0:
		return
	var ability: Dictionary = actor["ability"]
	var trigger: String = str(ability.get("trigger", "none"))
	var silenced: bool = actor["statuses"].get("silence", {}).get("end", 0.0) > time
	if not silenced and trigger in ["mana_full_auto", "cooldown_auto", "battle_start_then_cooldown"] and time >= actor["next_cast"]:
		if trigger == "cooldown_auto" or actor["mana"] >= float(ability.get("mana_cost", actor["max_mana"])):
			var target := choose_target(actor, str(ability.get("target", "nearest_enemy")))
			actor["ability_target"] = target
			actor["mana"] -= float(ability.get("mana_cost", 0))
			actor["cast_release"] = time + float(ability.get("cast_point_s", 0))
			visual_event("cast", actor, target, {"release_time": actor["cast_release"]})
			actor["next_cast"] = time + _star_value(ability, "cooldown_s", actor["star"], 0) * float(actor["ability_state"].get("cooldown_scale", 1.0))
			if actor["cast_release"] <= time:
				_visual_release("cast", actor)
				effects.cast(actor, target)
				actor["cast_release"] = -1.0
			return
	var target := choose_target(actor, "lowest_hp_enemy" if actor["ability_state"].get("target_lowest_hp", false) else "nearest_enemy")
	if target.is_empty():
		return
	var range_value: float = actor["range"]
	var distance: float = actor["pos"].distance_to(target["pos"])
	if distance > range_value and actor["speed"] > 0:
		_move_toward(actor, target)
	elif time >= actor["next_attack"] and actor["statuses"].get("disarm", {}).get("end", 0.0) <= time:
		actor["pending_attack"] = target
		actor["attack_release"] = time + actor["attack_point"]
		visual_event("attack", actor, target, {"release_time": actor["attack_release"]})
		var speed_value := clampf(100.0 + actor["attack_speed"], 20.0, 700.0)
		actor["next_attack"] = time + actor["bat"] * 100.0 / speed_value


func choose_target(actor: Dictionary, rule: String) -> Dictionary:
	var candidates: Array = []
	for candidate in actors:
		if candidate["team"] != actor["team"] and candidate["hp"] > 0 and candidate["statuses"].get("invisible", {}).get("end", 0.0) <= time:
			candidates.append(candidate)
	if candidates.is_empty():
		return {}
	var taunter: Dictionary = {}
	for candidate in candidates:
		if candidate["statuses"].get("taunt", {}).get("end", 0.0) > time:
			taunter = candidate
	if not taunter.is_empty():
		return taunter
	if "lowest_hp" in rule:
		candidates.sort_custom(func(a, b): return a["hp"] < b["hp"])
	elif "highest_hp" in rule:
		candidates.sort_custom(func(a, b): return a["hp"] > b["hp"])
	elif "highest_attack" in rule:
		candidates.sort_custom(func(a, b): return a["attack_max"] > b["attack_max"])
	elif "highest_cost" in rule:
		candidates.sort_custom(func(a, b): return int(units.get(a["id"], {}).get("cost", 0)) > int(units.get(b["id"], {}).get("cost", 0)))
	elif "farthest" in rule:
		candidates.sort_custom(func(a, b): return actor["pos"].distance_to(a["pos"]) > actor["pos"].distance_to(b["pos"]))
	else:
		candidates.sort_custom(func(a, b): return actor["pos"].distance_to(a["pos"]) < actor["pos"].distance_to(b["pos"]))
	return candidates[0]


func allies(actor: Dictionary, radius: float = INF) -> Array:
	var result: Array = []
	for other in actors:
		if other["team"] == actor["team"] and other["hp"] > 0 and actor["pos"].distance_to(other["pos"]) <= radius:
			result.append(other)
	return result


func enemies(actor: Dictionary, radius: float = INF) -> Array:
	var result: Array = []
	for other in actors:
		if other["team"] != actor["team"] and other["hp"] > 0 and actor["pos"].distance_to(other["pos"]) <= radius:
			result.append(other)
	return result


func heal(actor: Dictionary, amount: float, source: Dictionary = {}) -> void:
	if in_overtime: return
	var restored := maxf(0.0, minf(float(actor["max_hp"]) - float(actor["hp"]), amount))
	actor["hp"] += restored
	var healer: Dictionary = actor if source.is_empty() else source
	healer["healing_done"] = float(healer.get("healing_done", 0.0)) + restored
	if restored > 0 and not source.is_empty(): visual_event("heal", actor, source, {"amount":restored})


func status(actor: Dictionary, kind: String, duration: float, strength: float = 1.0) -> void:
	var old: Dictionary = actor["statuses"].get(kind, {})
	actor["statuses"][kind] = {"end": max(time + duration, float(old.get("end", 0))),
		"strength": max(strength, float(old.get("strength", 0)))}
	visual_event("status", actor, {}, {"status": kind, "end": actor["statuses"][kind]["end"]})


func schedule_damage(source: Dictionary, target: Dictionary, amount: float, damage_type: String,
		delay_s: float = 0.0, basic: bool = false, reflected: bool = false, visual_projectile: bool = false, feedback_item: String = "") -> void:
	var event := {"at": time + max(0.0, delay_s), "source": source, "target": target,
		"damage": amount, "type": damage_type, "basic": basic, "reflected": reflected, "feedback_item": feedback_item, "visual_ability":str(source.get("ability",{}).get("kind",""))}
	if capture_frames and delay_s > 0 and not reflected and (basic or visual_projectile):
		var flight_id := visual_events.size()
		visual_event("projectile", source, target, {"flight_id": flight_id, "from": source["pos"],
			"to": target["pos"], "arrive_time": ceil((float(event["at"]) - 0.00001) / TICK) * TICK,
			"basic": basic})
		event["flight_id"] = flight_id
	events.append(event)


func _process_events() -> void:
	var due: Array = []
	for event in events:
		if event["at"] <= time + 0.00001:
			due.append(event)
	for event in due:
		events.erase(event)
		if event.has("flight_id"):
			visual_event("projectile_end", event["source"], event["target"],
				{"flight_id": event["flight_id"], "to": event["target"]["pos"]})
		if event.get("kind", "") == "bounce":
			effects.resolve_bounce(event)
		elif event["target"]["hp"] > 0:
			var actual := damage(event["source"], event["target"], event["damage"], event["type"], event["basic"], event.get("reflected", false), str(event.get("feedback_item", "")),str(event.get("visual_ability","")))
			if actual > 0 and not str(event.get("feedback_item", "")).is_empty():
				visual_event("equipment_trigger", event["source"], event["target"], {"item": event["feedback_item"], "amount": actual})


func damage(source: Dictionary, target: Dictionary, amount: float, damage_type: String,
		basic: bool = false, reflected: bool = false, feedback_item: String = "", visual_ability: String = "") -> float:
	if target["hp"] <= 0 or target["statuses"].get("invulnerable", {}).get("end", 0.0) > time:
		return 0.0
	if damage_type == "magic" and target["statuses"].get("spell_immune", {}).get("end", 0.0) > time:
		return 0.0
	if basic and not source["ability_state"].get("true_strike", false):
		if target["ability_state"].get("evasion", 0) > 0 and _roll_percent(max(0.0, float(target["ability_state"]["evasion"]) - float(source["ability_state"].get("accuracy_bonus", 0)))):
			return 0.0
		if target["statuses"].get("miss", {}).get("end", 0.0) > time and _roll_percent(float(target["statuses"]["miss"]["strength"])):
			return 0.0
	var actual := amount
	if damage_type == "physical":
		if target["statuses"].get("physical_immune", {}).get("end", 0.0) > time:
			return 0.0
		var armor: float = target["armor"] - target["statuses"].get("armor_reduction", {}).get("strength", 0.0)
		actual *= 1.0 - (0.06 * armor) / (1.0 + 0.06 * armor) if armor >= 0 else 1.0 - 0.06 * armor
	elif damage_type == "magic":
		var resistance := clampf(target["mr"] + target["statuses"].get("mr_bonus", {}).get("strength", 0.0) - target["statuses"].get("mr_reduction", {}).get("strength", 0.0), -100.0, 90.0)
		actual *= 1.0 - resistance / 100.0
	if target["statuses"].get("damage_reduction", {}).get("end", 0.0) > time:
		actual *= 1.0 - target["statuses"]["damage_reduction"]["strength"] / 100.0
	if basic and target["ability_state"].get("knight_chance", 0) > 0 and _roll_percent(target["ability_state"]["knight_chance"]):
		status(target, "damage_reduction", 3.0, 50)
		actual *= 0.5
	if target["blocks"] > 0 and actual > 0:
		target["blocks"] -= 1
		visual_event("skill_proc", target, source, {"stage":"hit"})
		return 0.0
	if damage_type == "physical":
		var best_block := 0
		for item in target["items"]:
			var item_id: String = item["id"] if typeof(item) == TYPE_DICTIONARY else str(item)
			if item_id == "poor_mans_shield" and basic and _roll_percent(50): best_block = maxi(best_block, 20)
			if item_id == "stout_shield" and basic and _roll_percent(50): best_block = maxi(best_block, 10)
			if item_id == "vanguard" and _roll_percent(50): best_block = maxi(best_block, 50)
		actual = max(0.0, actual - best_block)
	if target["shield"] > 0:
		var absorbed: float = min(target["shield"], actual)
		target["shield"] -= absorbed
		actual -= absorbed
		if target["shield"] <= 0 and absorbed > 0: visual_event("skill_proc", target, source, {"ability":"shield", "stage":"hit"})
	actual = max(0.0, round(actual))
	if target["statuses"].get("grave", {}).get("end", 0.0) > time:
		actual = min(actual, target["hp"] - 1.0)
	actual = min(target["hp"], actual)
	target["hp"] -= actual
	if actual > 0:
		visual_event("hit", target, source, {"basic":basic})
		if not basic and not reflected and feedback_item.is_empty(): visual_event("skill_hit", source, target, {"ability": visual_ability if not visual_ability.is_empty() else str(source.get("ability",{}).get("kind",""))})
		if basic and source["id"] == "Phantom Assassin" and source["ability_state"].get("visual_critical", false):
			visual_event("critical_hit", source, target)
	source["damage_dealt"] += actual
	target["damage_taken"] += actual
	if actual > 0:
		source["mana"] = min(source["max_mana"], source["mana"] + actual * float(source["item_stats"].get("damage_mana_percent", 0)) / 100.0)
	if basic:
		source["mana"] = min(source["max_mana"], source["mana"] + source["mana_attack"] * (1.0 + float(source["item_stats"].get("attack_mana_percent", 0)) / 100.0))
		if actual > 0 and source["ability_state"].get("human_silence_chance", 0) > 0 and _roll_percent(float(source["ability_state"]["human_silence_chance"])):
			status(target, "silence", 4.0)
		if actual > 0 and source["ability_state"].get("demon_pure", false):
			schedule_damage(source, target, amount * 0.5, "pure", 0.01)
		if actual > 0 and target["ability_state"].get("element_retaliate", false) and source["range"] <= 1 and _roll_percent(20):
			status(source, "petrify", 2.0)
	target["mana"] = min(target["max_mana"], target["mana"] + min(20.0, target["mana_damage"] * (1.0 + float(target["item_stats"].get("incoming_mana_percent", 0)) / 100.0)))
	var lifesteal := float(source["item_stats"].get("lifesteal_percent", 0)) + float(source["ability_state"].get("warlock_lifesteal", 0))
	if actual > 0 and lifesteal > 0:
		var before_heal: float = source["hp"]
		heal(source, actual * lifesteal / 100.0)
		if source["hp"] > before_heal:
			visual_event("equipment_trigger", source, source, {"item": "lifesteal", "amount": source["hp"] - before_heal})
	effects.on_damage(source, target, actual, basic, reflected)
	if target["hp"] <= 0:
		visual_event("die", target, source)
		battle_log.append("%.1f %s 击败 %s" % [time, source["name"], target["name"]])
		effects.on_death(target)
	return actual
