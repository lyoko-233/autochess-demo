extends RefCounted

var _battle_ref: WeakRef
var battle: RefCounted:
	get: return _battle_ref.get_ref()


func _init(simulator: RefCounted) -> void:
	_battle_ref = weakref(simulator)


func _value(actor: Dictionary, key: String = "values", fallback: float = 0.0) -> float:
	return battle._star_value(actor["ability"], key, actor["star"], fallback)


func _duration(actor: Dictionary) -> float:
	return _value(actor, "duration_s")


func _enemy(actor: Dictionary, target: Dictionary) -> Dictionary:
	return target if not target.is_empty() and target.get("team", actor["team"]) != actor["team"] else battle.choose_target(actor, "nearest_enemy")


func _weakest_ally(actor: Dictionary) -> Dictionary:
	var group: Array = battle.allies(actor)
	group.sort_custom(func(a, b): return a["hp"] / a["max_hp"] < b["hp"] / b["max_hp"])
	return group[0] if not group.is_empty() else actor


func _damage(actor: Dictionary, target: Dictionary, amount: float, damage_type: String = "magic", extra_delay: float = 0.0) -> void:
	if target.is_empty():
		return
	var speed := float(actor["ability"].get("projectile_speed_units_per_s", 0))
	var travel: float = actor["pos"].distance_to(target["pos"]) * 100.0 / speed if speed > 0 else 0.0
	battle.schedule_damage(actor, target, amount, damage_type, travel + extra_delay, false, false,
		speed > 0 and extra_delay == 0)


func _start_bounce(actor: Dictionary, target: Dictionary, amount: float, damage_type: String) -> void:
	if target.is_empty(): return
	var speed := float(actor["ability"].get("projectile_speed_units_per_s", 0))
	var travel: float = actor["pos"].distance_to(target["pos"]) * 100.0 / speed if speed > 0 else 0.0
	var event := {"kind": "bounce", "at": battle.time + travel, "source": actor, "target": target,
		"damage": amount, "type": damage_type, "remaining": int(_value(actor, "bounce_count"))}
	_bounce_flight(event,actor["pos"])
	battle.events.append(event)

func _bounce_flight(event: Dictionary, from: Vector2, from_uid: int = -1) -> void:
	if not battle.capture_frames or float(event["at"]) <= battle.time: return
	var flight_id: int = battle.visual_events.size()
	battle.visual_event("projectile",event["source"],event["target"],{"flight_id":flight_id,"from":from,"from_uid":from_uid,
		"to":event["target"]["pos"],"arrive_time":ceil((float(event["at"])-.00001)/battle.TICK)*battle.TICK,"basic":false})
	event["flight_id"] = flight_id


func resolve_bounce(event: Dictionary) -> void:
	var actor: Dictionary = event["source"]
	var current: Dictionary = event["target"]
	if current["hp"] <= 0: return
	battle.damage(actor, current, float(event["damage"]), str(event["type"]))
	if actor["ability"]["kind"] == "bounce_stun":
		battle.status(current, "stun", _duration(actor))
	else:
		var slow_duration := float(actor["ability"].get("slow_duration_s", 2.5))
		battle.status(current, "move_slow", slow_duration, float(actor["ability"].get("movement_slow_flat", 65)))
		battle.status(current, "attack_slow", slow_duration, float(actor["ability"].get("attack_speed_slow_flat", 65)))
	if int(event["remaining"]) <= 0: return
	var radius := float(actor["ability"].get("bounce_range_units", 0)) / 100.0
	var candidates: Array = []
	for enemy in battle.enemies(actor):
		if enemy != current and current["pos"].distance_to(enemy["pos"]) <= radius:
			candidates.append(enemy)
	if candidates.is_empty(): return
	candidates.sort_custom(func(a, b):
		var a_distance: float = current["pos"].distance_to(a["pos"])
		var b_distance: float = current["pos"].distance_to(b["pos"])
		return a_distance < b_distance if not is_equal_approx(a_distance, b_distance) else int(a["uid"]) < int(b["uid"]))
	var next_target: Dictionary = candidates[0]
	var speed := float(actor["ability"].get("projectile_speed_units_per_s", 0))
	var travel: float = current["pos"].distance_to(next_target["pos"]) * 100.0 / speed if speed > 0 else 0.0
	event["target"] = next_target
	event["remaining"] = int(event["remaining"]) - 1
	event["at"] = float(event["at"]) + float(actor["ability"].get("bounce_delay_s", 0)) + travel
	_bounce_flight(event,current["pos"],int(current["uid"]))
	battle.events.append(event)


func _area(actor: Dictionary, center: Vector2, radius: float, amount: float, damage_type: String = "magic") -> void:
	for victim in battle.enemies(actor):
		if center.distance_to(victim["pos"]) <= radius:
			_damage(actor, victim, amount, damage_type)


func _dot(source: Dictionary, target: Dictionary, amount_per_tick: float, duration: float,
		interval: float, damage_type: String = "magic", heal_source: bool = false) -> void:
	if target.is_empty():
		return
	if not target["ability_state"].has("dots"):
		target["ability_state"]["dots"] = []
	target["ability_state"]["dots"].append({"source": source, "next": battle.time + interval,
		"end": battle.time + duration, "interval": interval, "amount": amount_per_tick,
		"type": damage_type, "heal_source": heal_source})


func _summon(actor: Dictionary, count: int) -> void:
	var panels: Array = actor["ability"].get("summon_stats_by_star", [])
	if panels.is_empty():
		return
	var panel: Dictionary = panels[actor["star"] - 1]
	var offsets := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for offset in offsets:
		if count <= 0:
			break
		var position: Vector2 = actor["pos"].round() + offset
		if position.x < 0 or position.x > 7 or position.y < 0 or position.y > 7:
			continue
		if not battle.cell_is_free(position):
			continue
		var child: Dictionary = actor.duplicate(false)
		child["uid"] = battle.actors.size()
		child["owner_uid"] = actor["uid"]
		child["damage_dealt"] = 0.0
		child["damage_taken"] = 0.0
		child["healing_done"] = 0.0
		child["move_progress"] = 0.0
		child["id"] = panel["kind"]
		var summon_name: String = panel["kind"]
		for prefix in ["fur_tree", "ld_bear", "lyc_wolf", "veno_ward"]:
			if summon_name.begins_with(prefix):
				summon_name = {"fur_tree": "树人", "ld_bear": "灵熊", "lyc_wolf": "化狼战士之狼", "veno_ward": "瘟疫守卫"}[prefix] + summon_name.trim_prefix(prefix) + "级"
				break
		child["name"] = {"bear": "熊", "boar": "豪猪", "familiar": "佣兽", "hawk": "战鹰"}.get(summon_name, summon_name)
		child["summon"] = true
		child["monster"] = false
		child["pos"] = position
		child["hp"] = float(panel["hp"])
		child["max_hp"] = float(panel["hp"])
		if actor["ability_state"].get("summoning_stone", false): child["max_hp"] += 250
		child["hp"] = child["max_hp"]
		child["attack_min"] = float(panel["attack_min"])
		child["attack_max"] = float(panel["attack_max"])
		child["armor"] = float(panel["armor"])
		child["mr"] = float(panel["magic_resistance_percent"])
		child["bat"] = float(panel["base_attack_time_s"])
		child["attack_point"] = float(panel["attack_point_s"])
		child["range"] = float(panel["attack_range_units"]) / 100.0
		child["speed"] = float(panel["movement_speed_units_per_s"])
		child["projectile"] = float(panel["attack_projectile_speed_units_per_s"])
		child["mana"] = 0.0
		child["max_mana"] = 0.0
		child["mana_attack"] = 0.0
		child["mana_damage"] = 0.0
		child["ability"] = {"kind": "none", "trigger": "none"}
		child["ability_state"] = {}
		child["statuses"] = {}
		child["items"] = []
		child["item_stats"] = {}
		child["tags"] = []
		child["next_attack"] = battle.time
		child["attack_release"] = -1.0
		child["cast_release"] = -1.0
		child["pending_attack"] = {}
		child["ability_target"] = {}
		if actor["ability_state"].get("summoning_stone", false): child["ability_state"]["summoning_stone"] = true
		battle.actors.append(child)
		count -= 1


func _line_targets(actor: Dictionary, target: Dictionary, width: float = 1.0) -> Array:
	if target.is_empty():
		return []
	var direction: Vector2 = (target["pos"] - actor["pos"]).normalized()
	var result: Array = []
	for victim in battle.enemies(actor):
		var delta: Vector2 = victim["pos"] - actor["pos"]
		if delta.dot(direction) >= 0 and abs(delta.cross(direction)) <= width:
			result.append(victim)
	return result


func on_battle_start(actor: Dictionary) -> void:
	var kind: String = str(actor["ability"].get("kind", "none"))
	if kind == "attack_aura":
		for ally in battle.allies(actor, float(actor["ability"].get("radius_grids", 4))):
			ally["bonus_attack"] += _value(actor)
	elif kind == "mana_pulse":
		actor["ability_state"]["next_pulse"] = 2.0
	elif kind == "frontal_reduction":
		actor["ability_state"]["next_bash"] = 0.0
	elif kind == "exorcism":
		actor["ability_state"]["exorcism_damage"] = 0.0
	elif kind == "opening_leap_and_aura":
		for ally in battle.allies(actor, float(actor["ability"].get("radius_grids", 2))):
			if ally["id"] in ["wolf", "alpha_wolf"]:
				ally["attack_speed"] += float(actor["ability"]["effect"]["allied_wolf_attack_speed_bonus_percent"])
	elif kind == "opening_leap_and_stun":
		var leap_target: Dictionary = battle.choose_target(actor, "farthest_enemy")
		if not leap_target.is_empty():
			battle.place_near(actor, leap_target["pos"] + Vector2(0, 1 if actor["team"] == 0 else -1))
			battle.status(actor, "invulnerable", float(actor["ability"]["effect"]["leap_invulnerability_s"]))
	elif kind == "pair_aura":
		var pair_count := 0
		for ally in battle.allies(actor):
			if ally["id"] == "bear": pair_count += 1
		if pair_count >= 2: actor["attack_speed"] += float(actor["ability"]["effect"]["attack_speed_bonus_percent"])
	if actor["id"] in ["wolf", "alpha_wolf"]:
		var enemies: Array = battle.enemies(actor)
		enemies.sort_custom(func(a, b):
			if not is_equal_approx(a.pos.y, b.pos.y): return a.pos.y > b.pos.y if actor.team == 0 else a.pos.y < b.pos.y
			return actor.pos.distance_squared_to(a.pos) < actor.pos.distance_squared_to(b.pos))
		if not enemies.is_empty():
			var target: Dictionary = enemies[0]
			var departure: Vector2 = actor.pos
			battle.place_near(actor, target.pos + Vector2(0, 1 if actor.team == 0 else -1))
			battle.status(actor, "invulnerable", .3)
			battle.visual_event("leap", actor, target, {"from":departure, "to":actor.pos, "duration":.3})
			battle.battle_log.append("%s 跳向敌方后排" % actor.name)
	elif "刺客" in actor["tags"] or kind == "critical":
		var target: Dictionary = battle.choose_target(actor, "farthest_enemy")
		if not target.is_empty():
			var landing: Vector2 = (target["pos"] + Vector2(0, 1 if actor["team"] == 0 else -1)).clamp(Vector2.ZERO, Vector2(7, 7))
			var departure: Vector2 = actor["pos"]
			battle.place_near(actor, landing)
			battle.visual_event("leap", actor, target, {"from": departure, "to": actor["pos"]})
			battle.battle_log.append("%s 跳向敌方后排" % actor["name"])
	for item in actor["items"]:
		var item_id: String = item["id"] if typeof(item) == TYPE_DICTIONARY else str(item)
		match item_id:
			"black_king_bar": battle.status(actor, "spell_immune", 8.0)
			"mask_madness":
				actor["armor"] -= 8
				battle.status(actor, "silence", 8.0)
			"energy_booster", "arcane_boots": actor["mana"] = min(actor["max_mana"], actor["mana"] + 40)
			"blink_dagger":
				var jump_position: Vector2 = actor["pos"]
				jump_position.y = clampf(jump_position.y + (3 if actor["team"] == 0 else -3), 0.0, 7.0)
				battle.place_near(actor, jump_position)
			"dagon_1_5": actor["ability_state"]["dagon_next"] = float([5, 4, 3, 2, 1][clampi(int(item.get("level", 1)) - 1, 0, 4)])
			"scythe_vyse": actor["ability_state"]["vyse_next"] = 8.0
			"shivas_guard": actor["ability_state"]["shiva_next"] = 4.0
			"pipe_insight": actor["ability_state"]["pipe_next"] = 3.0
			"monkey_king_bar": actor["ability_state"]["true_strike"] = true
			"heart_tarrasque": actor["ability_state"]["heart_next"] = 2.0
			"arcane_boots": actor["ability_state"]["arcane_next"] = 5.0
			"summoning_stone": actor["ability_state"]["summoning_stone"] = true
			"assault_cuirass":
				for ally in battle.allies(actor, 1.0):
					ally["armor"] += 10
					ally["attack_speed"] += 10
				for victim in battle.enemies(actor, 1.0):
					victim["armor"] -= 10
					victim["attack_speed"] -= 10


func on_tick(actor: Dictionary, delta: float) -> void:
	var state: Dictionary = actor["ability_state"]
	if state.has("dots"):
		for dot in state["dots"].duplicate():
			if battle.time >= dot["next"] and battle.time <= dot["end"] + 0.001:
				var actual: float = battle.damage(dot["source"], actor, dot["amount"], dot["type"])
				if dot["heal_source"]:
					battle.heal(dot["source"], actual)
				dot["next"] += dot["interval"]
			if battle.time > dot["end"]:
				state["dots"].erase(dot)
	if actor["hp"] <= 0:
		return
	if state.has("heals"):
		for heal_event in state["heals"].duplicate():
			if battle.time >= heal_event["next"] and battle.time <= heal_event["end"]:
				battle.heal(actor, heal_event["amount"])
				heal_event["next"] += heal_event["interval"]
			if battle.time > heal_event["end"]:
				state["heals"].erase(heal_event)
	var kind: String = str(actor["ability"].get("kind", "none"))
	if kind == "mana_pulse" and battle.time >= float(state.get("next_pulse", INF)):
		var recipients := []
		var restored := 0.0
		for ally in battle.allies(actor):
			var before: float = ally["mana"]
			ally["mana"] = min(ally["max_mana"], ally["mana"] + _value(actor))
			restored += float(ally["mana"]) - before
			if float(ally["mana"])>before:recipients.append(int(ally.uid))
		if restored > 0: battle.visual_event("mana_pulse", actor, {}, {"mana_restored": restored,"recipient_uids":recipients})
		state["next_pulse"] = battle.time + float(actor["ability"].get("pulse_interval_s", 2.0))
	if kind == "frontal_reduction" and battle.time >= float(state.get("next_bash", INF)):
		_area(actor, actor["pos"] + Vector2(0, 1 if actor["team"] == 0 else -1),
			float(actor["ability"].get("shield_bash_radius_grids", 1)),
			_value(actor, "shield_bash_damage"), "physical")
		for victim in battle.enemies(actor):
			var center: Vector2 = actor["pos"] + Vector2(0, 1 if actor["team"] == 0 else -1)
			if center.distance_to(victim["pos"]) <= float(actor["ability"].get("shield_bash_radius_grids", 1)):
				battle.visual_event("skill_proc", actor, victim)
				break
		state["next_bash"] = battle.time + float(actor["ability"].get("shield_bash_cooldown_s", 5))
	if state.has("dagon_next") and battle.time >= state["dagon_next"]:
		var target: Dictionary = battle.choose_target(actor, "lowest_hp_enemy")
		if not target.is_empty() and actor["pos"].distance_to(target["pos"]) <= 5:
			var level := 1
			for item in actor["items"]:
				if typeof(item) == TYPE_DICTIONARY and item["id"] == "dagon_1_5":
					level = int(item.get("level", 1))
			battle.status(target, "mr_reduction", 5.0, float([30, 40, 50, 60, 70][level - 1]))
			_damage(actor, target, float([400, 500, 600, 700, 800][level - 1]))
			state["dagon_next"] = battle.time + float([15, 12, 9, 6, 3][level - 1])
	if state.has("vyse_next") and battle.time >= state["vyse_next"]:
		var target: Dictionary = battle.choose_target(actor, "highest_attack_enemy")
		if not target.is_empty():
			battle.status(target, "hex", 8.0)
		state.erase("vyse_next")
	if state.has("shiva_next") and battle.time >= state["shiva_next"]:
		_area(actor, actor["pos"], 3.0, 200.0)
		for victim in battle.enemies(actor, 3.0): battle.status(victim, "attack_slow", 4.0, 50.0)
		state.erase("shiva_next")
	if state.has("pipe_next") and battle.time >= state["pipe_next"]:
		for ally in battle.allies(actor, 3.0):
			battle.status(ally, "mr_bonus", 10.0, 30.0)
			battle.status(ally, "regen_bonus", 10.0, 15.0)
		state.erase("pipe_next")
	if state.has("heart_next") and battle.time >= state["heart_next"]:
		battle.heal(actor, actor["max_hp"] * 0.01)
		state["heart_next"] += 2.0
	if state.has("arcane_next") and battle.time >= state["arcane_next"]:
		for ally in battle.allies(actor, 2.0):
			ally["mana"] = min(ally["max_mana"], ally["mana"] + 20)
		state.erase("arcane_next")


func on_basic_attack(actor: Dictionary, target: Dictionary, raw: float) -> float:
	var kind: String = str(actor["ability"].get("kind", "none"))
	if kind == "critical":
		actor["ability_state"]["visual_critical"] = battle._roll_percent(_value(actor, "proc_chance_percent", 10))
		if actor["ability_state"]["visual_critical"]: raw *= _value(actor) / 100.0
	if kind == "critical_knockup" and actor["ability_state"].get("next_crit", false):
		battle.visual_event("skill_proc", actor, target, {"stage":"release", "replace_basic":true})
		raw *= _value(actor) / 100.0
		battle.status(target, "stun", _duration(actor))
		actor["ability_state"].erase("next_crit")
	if actor["ability_state"].get("assassin_crit", 0) > 0 and battle._roll_percent(15):
		raw *= float(actor["ability_state"]["assassin_crit"]) / 100.0
	if kind == "mana_burn":
		var burned: float = min(target["mana"], _value(actor))
		target["mana"] -= burned
		if burned > 0: battle.visual_event("skill_proc", actor, target)
		battle.schedule_damage(actor, target, burned * float(actor["ability"].get("damage_per_mana_burned", 0.5)), "pure")
	if kind == "fervor":
		if actor["last_target"] != target["id"]: actor["stacks"] = 0
		actor["last_target"] = target["id"]
		actor["stacks"] = mini(actor["stacks"] + 1, int(_value(actor, "maximum_stacks", 8)))
		actor["attack_speed"] += _value(actor)
	if kind in ["critical_attack", "stun_attack", "splash_attack"]:
		var monster_effect: Dictionary = actor["ability"].get("effect", {})
		if kind == "critical_attack" and battle._roll_percent(float(monster_effect.get("chance_percent", 0))):
			raw *= float(monster_effect.get("critical_multiplier_percent", 100)) / 100.0
		if kind == "stun_attack" and battle._roll_percent(float(monster_effect.get("chance_percent", 0))):
			battle.status(target, "stun", float(monster_effect.get("stun_duration_s", 0)))
		if kind == "splash_attack":
			for victim in battle.enemies(actor):
				if victim != target and victim["pos"].distance_to(target["pos"]) <= float(actor["ability"].get("radius_grids", 1)):
					battle.schedule_damage(actor, victim, raw * float(monster_effect.get("splash_percent", 0)) / 100.0, "physical")
	if kind == "bounce_attack":
		var other_targets: Array = battle.enemies(actor)
		other_targets.erase(target)
		other_targets.sort_custom(func(a, b): return target["pos"].distance_to(a["pos"]) < target["pos"].distance_to(b["pos"]))
		for index in range(mini(int(_value(actor)), other_targets.size())):
			battle.schedule_damage(actor, other_targets[index], raw * float(actor["ability"].get("bounce_damage_percent", 70)) / 100.0, "physical", 0.1 * (index + 1))
	var item_critical := 1.0
	for item in actor["items"]:
		var item_id: String = item["id"] if typeof(item) == TYPE_DICTIONARY else str(item)
		if item_id == "crystalys" and battle._roll_percent(15): item_critical = max(item_critical, 1.5)
		if item_id == "daedalus" and battle._roll_percent(10): item_critical = max(item_critical, 4.0)
		if item_id == "blight_stone": battle.status(target, "armor_reduction", 5.0, 3.0)
		if item_id == "desolator": battle.status(target, "armor_reduction", 5.0, 12.0)
		if item_id == "kaya": battle.status(target, "mr_reduction", 5.0, 60.0)
		if item_id == "staff_wizardry": battle.status(target, "mr_reduction", 5.0, 30.0)
		if item_id == "mystic_staff": battle.status(target, "mr_reduction", 5.0, 40.0)
		if item_id == "monkey_king_bar": actor["ability_state"]["true_strike"] = true
		if item_id == "scythe_vyse": battle.status(target, "mr_reduction", 5.0, 20.0)
		if item_id == "summoning_stone": battle.status(target, "armor_reduction", 5.0, 3.0)
		if item_id in ["maelstrom", "mjollnir"] and battle._roll_percent(25):
			var victims: Array = battle.enemies(actor)
			victims.sort_custom(func(a, b): return target["pos"].distance_to(a["pos"]) < target["pos"].distance_to(b["pos"]))
			for index in range(mini(5 if item_id == "mjollnir" else 3, victims.size())):
				battle.schedule_damage(actor, victims[index], 200 if item_id == "mjollnir" else 100, "magic", 0.1 * index)
	return raw * item_critical


func on_damage(source: Dictionary, target: Dictionary, actual: float, basic: bool, reflected: bool = false) -> void:
	if actual <= 0:
		return
	if basic and float(source["range"]) <= 1.0:
		var axis: Vector2 = (target["pos"] - source["pos"]).normalized()
		for item in source["items"]:
			var item_id: String = item["id"] if typeof(item) == TYPE_DICTIONARY else str(item)
			if item_id != "battle_fury": continue
			for victim in battle.enemies(source):
				if victim == target: continue
				var offset: Vector2 = victim["pos"] - target["pos"]
				if offset.length_squared() > 0 and offset.length_squared() <= 9.0 and axis.dot(offset.normalized()) >= 0.70710678:
					battle.schedule_damage(source, victim, actual * 0.3, "pure", 0.0, false, false, false, "battle_fury")
	if target["ability"].get("kind", "") == "spiked_carapace" and target["statuses"].get("carapace", {}).get("end", 0.0) > battle.time:
		battle.visual_event("skill_proc", target, source, {"stage":"hit"})
		battle.status(source, "stun", _value(target, "stun_duration_s", 1))
		battle.schedule_damage(target, source, actual * _value(target) / 100.0, "pure", 0.1)
	for item in target["items"]:
		var item_id: String = item["id"] if typeof(item) == TYPE_DICTIONARY else str(item)
		if item_id == "blade_mail" and not target["ability_state"].get("blade_mail_used", false):
			target["ability_state"]["blade_mail_used"] = true
			battle.status(target, "blade_mail", 4.0)
		if item_id == "blade_mail" and not reflected and target["statuses"].get("blade_mail", {}).get("end", 0.0) > battle.time:
			battle.schedule_damage(target, source, actual, "pure", 0.1, false, true, false, "blade_mail")


func on_death(actor: Dictionary) -> void:
	actor["ability_state"]["dead_at"] = battle.time
	if actor["range"] <= 1 and not actor["summon"]:
		for ally in battle.allies(actor):
			if ally == actor or not ally["ability_state"].has("ogre_stack"): continue
			if int(ally["ability_state"]["ogre_stack"]) >= 8: continue
			ally["ability_state"]["ogre_stack"] += 1
			ally["max_hp"] *= 1.25
			ally["hp"] *= 1.25
			ally["attack_min"] *= 1.25
			ally["attack_max"] *= 1.25
	var insect_tier := int(actor["ability_state"].get("insect_tier", 0))
	if insect_tier < 2 or (insect_tier < 4 and "虫族" in actor["tags"]): return
	var same_name_alive := false
	for ally in battle.allies(actor):
		if ally != actor and ally["id"] == actor["id"]: same_name_alive = true
	if not same_name_alive: return
	var insects: Array = []
	for unit in battle.content["units"]:
		if "虫族" in str(unit["species"]): insects.append(unit["name_en"])
	if insects.is_empty(): return
	var chosen: String = insects[battle.rng.randi_range(0, insects.size() - 1)]
	var child: Dictionary = battle._make_actor({"id": chosen, "star": actor["star"], "position": 0, "items": []}, actor["team"])
	child["owner_uid"] = actor["uid"]
	if not battle.place_near(child, actor["pos"]): return
	child["summon"] = true
	battle.actors.append(child)


func cast(actor: Dictionary, selected: Dictionary) -> void:
	var ability: Dictionary = actor["ability"]
	var kind: String = str(ability.get("kind", "none"))
	var target: Dictionary = _enemy(actor, selected)
	var amount := _value(actor)
	var duration := _duration(actor)
	var radius := float(ability.get("radius_grids", 1))
	var damage_type: String = str(ability.get("damage_type", "magic"))
	battle.battle_log.append("%.1f %s 施放 %s" % [battle.time, actor["name"], kind])
	var visual_target := target
	if kind in ["heal", "cold_embrace", "multicast", "purification", "shield", "shallow_grave"]: visual_target = _weakest_ally(actor)
	battle.visual_event("cast_release", actor, visual_target, {
		"origin": actor["pos"], "destination": visual_target.get("pos", actor["pos"]),
		"radius": float(ability.get("acid_spray_radius_units", 400)) / 100.0 if kind == "chemical_rage" else radius,
		"duration": duration, "delay": float(ability.get("effect_delay_s", 0)),
		"speed": float(ability.get("projectile_speed_units_per_s", 0)), "line_half_width": 1.0})
	if kind in ["transform_wolves","metamorphosis","dragon_form","chemical_rage"]: actor["visual_form"] = kind
	match kind:
		"none", "wildcard_combine": pass
		"critical_knockup": actor["ability_state"]["next_crit"] = true
		"single_bolt", "lightning": _damage(actor, target, float(ability["effect"].get("damage", 0)), damage_type)
		"shockwave", "breath", "stomp", "heavy_blow":
			_area(actor, actor["pos"], radius, float(ability["effect"].get("damage", 0)), damage_type)
			if kind in ["stomp", "heavy_blow"]:
				for victim in battle.enemies(actor, radius): battle.status(victim, "stun", float(ability["effect"].get("stun_duration_s", 0)))
		"burn":
			var effect: Dictionary = ability["effect"]
			var interval := float(effect["tick_interval_s"])
			_dot(actor, target, float(effect["damage_per_second"]) * interval, float(effect["duration_s"]), interval)
		"chill": battle.status(target, "attack_slow", float(ability["effect"]["duration_s"]), float(ability["effect"]["attack_speed_slow_percent"]))
		"opening_leap_and_stun": battle.status(target, "stun", float(ability["effect"]["stun_duration_s"]))
		"taunt_armor":
			actor["armor"] += amount
			battle.status(actor, "taunt", duration)
		"heal":
			var ally := _weakest_ally(actor)
			battle.heal(ally, amount * float(ability.get("wisp_count", [3, 5, 7])[actor["star"] - 1]), actor)
		"magic_damage", "assassinate", "laguna_blade", "sniper", "mana_burn": _damage(actor, target, amount, damage_type)
		"magic_pulse", "spin":
			for victim in battle.enemies(actor, radius): _dot(actor, victim, amount * 0.5, duration, 0.5)
		"hex": battle.status(target, "hex", duration)
		"missiles":
			var victims: Array = battle.enemies(actor)
			victims.sort_custom(func(a, b): return a["hp"] < b["hp"])
			for index in range(mini(int(_value(actor, "missile_count", 2)), victims.size())): _damage(actor, victims[index], amount)
		"throw":
			_damage(actor, target, amount)
			battle.status(target, "stun", duration)
			if not target.is_empty(): battle.place_near(target, actor["pos"] + Vector2(0, 2 if actor["team"] == 0 else -2))
		"bounce_stun", "chain_frost":
			_start_bounce(actor, target, amount, damage_type)
		"cold_embrace":
			var ally := _weakest_ally(actor)
			battle.status(ally, "physical_immune", duration)
			battle.status(ally, "regen_bonus", duration, ally["max_hp"] * amount / 100.0 + float(ability.get("base_heal_per_second", 0)))
		"mana_drain":
			if not target.is_empty():
				var drained: float = min(target["mana"], amount * duration)
				target["mana"] -= drained
				actor["mana"] = min(actor["max_mana"], actor["mana"] + drained)
		"call_of_the_wild", "treants", "spirit_bear", "familiars", "plague_wards": _summon(actor, int(amount))
		"aoe_burst", "scream", "plasma_field", "requiem": _area(actor, actor["pos"], radius, amount, damage_type)
		"line_orb", "powershot", "illuminate", "stroke_of_fate":
			for victim in _line_targets(actor, target): _damage(actor, victim, amount, damage_type)
		"random_stun":
			_damage(actor, target, amount)
			battle.status(target, "stun", duration)
		"waveform", "burrowstrike":
			for victim in _line_targets(actor, target):
				_damage(actor, victim, amount)
				if kind == "burrowstrike": battle.status(victim, "stun", duration)
			if not target.is_empty(): battle.place_near(actor, target["pos"])
		"firefly":
			for victim in battle.enemies(actor, radius): _dot(actor, victim, amount * 0.5, duration, 0.5)
		"spell_steal":
			if (not target.is_empty() and target["ability"].get("kind", "") != "spell_steal"
				and str(target["ability"].get("trigger", "none")) in ["mana_full_auto", "cooldown_auto"]):
				var original: Dictionary = actor["ability"]
				actor["ability"] = target["ability"]
				cast(actor, target)
				actor["ability"] = original
		"disarm": battle.status(target, "disarm", duration)
		"multicast":
			var ally := _weakest_ally(actor)
			ally["ability_state"]["multicast"] = int(amount)
		"transform_wolves":
			actor["max_hp"] *= 1.0 + amount / 100.0
			actor["hp"] *= 1.0 + amount / 100.0
			_summon(actor, int(_value(actor, "wolf_count", 2)))
		"purification":
			var ally := _weakest_ally(actor)
			battle.heal(ally, amount, actor)
			_area(actor, ally["pos"], radius, amount, "pure")
		"shield":
			var ally := _weakest_ally(actor)
			ally["shield"] += amount
		"poison", "leech_seed", "doom":
			_dot(actor, target, amount * 0.5, duration, 0.5, "pure" if kind == "doom" else "magic", kind == "leech_seed")
			if kind == "doom": battle.status(target, "silence", duration)
		"metamorphosis", "dragon_form":
			actor["bonus_attack"] += amount
			actor["range"] = float(ability.get("transformed_attack_range_grids", ability.get("dragon_attack_range_grids", actor["range"])))
		"shallow_grave": battle.status(_weakest_ally(actor), "grave", duration)
		"hook", "pounce":
			_damage(actor, target, amount, damage_type)
			battle.status(target, "stun", duration)
			if not target.is_empty(): battle.place_near(actor, target["pos"])
		"ghostship", "static_storm", "call_down", "remote_mines":
			var center: Vector2 = target["pos"] if not target.is_empty() else actor["pos"]
			for victim in battle.enemies(actor):
				if center.distance_to(victim["pos"]) <= radius:
					_damage(actor, victim, amount, damage_type, float(ability.get("effect_delay_s", 0)))
					if kind in ["ghostship", "static_storm"]: battle.status(victim, "stun" if kind == "ghostship" else "silence", duration)
		"death_pulse":
			_area(actor, actor["pos"], radius, amount)
			for ally in battle.allies(actor, radius): battle.heal(ally, amount, actor)
		"refraction":
			actor["blocks"] += int(amount)
			actor["bonus_attack"] += _value(actor, "bonus_attack_damage")
		"chemical_rage":
			actor["regen"] += amount
			actor["bat"] = _value(actor, "transformed_base_attack_time_s", actor["bat"])
			for victim in battle.enemies(actor, float(ability.get("acid_spray_radius_units", 400)) / 100.0):
				battle.status(victim, "armor_reduction", duration, _value(actor, "acid_spray_armor_reduction", 4))
		"stone_gaze":
			for victim in battle.enemies(actor, radius):
				battle.status(victim, "petrify", duration)
				battle.visual_event("skill_proc", actor, victim, {"stage":"hit"})
		"spiked_carapace": battle.status(actor, "carapace", duration)
		"ravage":
			_area(actor, actor["pos"], radius, amount)
			for victim in battle.enemies(actor, radius): battle.status(victim, "stun", duration)
		"midnight_pulse":
			for victim in battle.enemies(actor, radius): _dot(actor, victim, victim["max_hp"] * amount / 100.0 * 0.5, duration, 0.5, "pure")
		"exorcism":
			for victim in battle.enemies(actor, radius): _dot(actor, victim, amount * _value(actor, "spirit_damage", 40) * 0.5, duration, 0.5, "physical", true)
		"gods_strength":
			for ally in battle.allies(actor):
				if ally == actor or "战士" in ally["tags"]: ally["bonus_attack"] += ally["attack_max"] * amount / 100.0
		"thundergods_wrath":
			for victim in battle.enemies(actor): _damage(actor, victim, amount + victim["hp"] * _value(actor, "percent_current_hp_magic_damage") / 100.0)
		"corrosive_haze": battle.status(target, "armor_reduction", duration, amount)
		"sacred_arrow":
			if not target.is_empty():
				var arrow_distance: float = actor["pos"].distance_to(target["pos"]) * 100.0
				var ratio: float = min(1.0, arrow_distance / float(ability.get("maximum_arrow_distance_units", 6000)))
				_damage(actor, target, amount + (_value(actor, "maximum_magic_damage") - amount) * ratio)
				battle.status(target, "stun", duration + (_value(actor, "maximum_stun_s") - duration) * ratio)
		"smoke_screen":
			for victim in battle.enemies(actor, radius):
				battle.status(victim, "silence", duration)
				battle.status(victim, "miss", duration, amount)
		_: push_error("Unhandled ability kind: %s" % kind)
	for item in actor["items"]:
		var item_id: String = item["id"] if typeof(item) == TYPE_DICTIONARY else str(item)
		if item_id == "refresher_orb" and not actor["ability_state"].get("refresher_used", false):
			actor["ability_state"]["refresher_used"] = true
			actor["next_cast"] = battle.time
			break
