extends Control

const TEST_ROSTER := ["Axe", "Phantom Assassin", "Tidehunter"]
const XP_TO_NEXT := [1, 1, 2]
const SEED := 9252019
const SAVE_PATH := "user://round_start.json"

var content: Dictionary
var unit_defs: Dictionary = {}
var monster_defs: Dictionary = {}
var round_number := 1
var level := 1
var xp := 0
var gold := 0
var courier_hp := 100
var shop: Array = []
var bench: Array = []
var board: Dictionary = {}
var selected_bench := -1
var inventory: Array = []
var equipped: Dictionary = {}
var phase := "preparation"
var rng := RandomNumberGenerator.new()
var event_log: Array = []

var title_label: Label
var message_label: Label
var shop_buttons: Array = []
var bench_buttons: Array = []
var board_buttons: Array = []
var battle_button: Button
var next_button: Button
var equip_button: Button
var restart_button: Button
var log_box: RichTextLabel


func _ready() -> void:
	var file := FileAccess.open("res://data/content.json", FileAccess.READ)
	if file == null:
		push_error("Missing data/content.json. Run python godot/tools/build_content.py from the workspace root.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid content.json")
		return
	content = parsed
	for unit in content["units"]:
		unit_defs[unit["name_en"]] = unit
	for monster in content["monsters"]:
		monster_defs[monster["id"]] = monster
	_build_ui()
	if FileAccess.file_exists(SAVE_PATH):
		_load_snapshot()
	else:
		_start_round()


func _build_ui() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	title_label = Label.new()
	layout.add_child(title_label)
	message_label = Label.new()
	layout.add_child(message_label)
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(middle)
	var grid := GridContainer.new()
	grid.columns = 8
	middle.add_child(grid)
	for i in range(64):
		var button := Button.new()
		button.custom_minimum_size = Vector2(90, 65)
		button.pressed.connect(_on_board_pressed.bind(i))
		grid.add_child(button)
		board_buttons.append(button)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 470
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(side)
	var shop_title := Label.new()
	shop_title.text = "测试商店（赤斧／幽刃／怒潮海卫）"
	side.add_child(shop_title)
	for i in range(3):
		var button := Button.new()
		button.pressed.connect(_on_shop_pressed.bind(i))
		side.add_child(button)
		shop_buttons.append(button)
	var bench_title := Label.new()
	bench_title.text = "候场：先点棋子，再点己方四行的空格"
	side.add_child(bench_title)
	for i in range(8):
		var button := Button.new()
		button.pressed.connect(_on_bench_pressed.bind(i))
		side.add_child(button)
		bench_buttons.append(button)
	equip_button = Button.new()
	equip_button.text = "给最早上场棋子装备攻击之爪"
	equip_button.pressed.connect(_on_equip_pressed)
	side.add_child(equip_button)
	battle_button = Button.new()
	battle_button.text = "开始战斗"
	battle_button.pressed.connect(_on_battle_pressed)
	side.add_child(battle_button)
	next_button = Button.new()
	next_button.text = "下一回合"
	next_button.pressed.connect(_on_next_pressed)
	side.add_child(next_button)
	restart_button = Button.new()
	restart_button.text = "重开三回合测试"
	restart_button.pressed.connect(_on_restart_pressed)
	side.add_child(restart_button)
	log_box = RichTextLabel.new()
	log_box.custom_minimum_size.y = 165
	layout.add_child(log_box)


func _start_round() -> void:
	phase = "preparation"
	selected_bench = -1
	gold += int(content["prototype_rules"]["round_income"][round_number - 1])
	shop = TEST_ROSTER.duplicate()
	_note("第 %d 回合：收入发放后金币 %d；商店刷新" % [round_number, gold])
	_save_snapshot()
	_refresh_ui()


func _save_snapshot() -> void:
	var snapshot := {"version": content["version"], "round": round_number, "level": level,
		"xp": xp, "gold": gold, "courier_hp": courier_hp, "shop": shop,
		"bench": bench, "board": board, "inventory": inventory, "equipped": equipped}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))


func _load_snapshot() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_start_round()
		return
	var snapshot: Dictionary = parsed
	if snapshot.get("version", "") != content["version"]:
		_start_round()
		return
	round_number = int(snapshot["round"])
	level = int(snapshot["level"])
	xp = int(snapshot["xp"])
	gold = int(snapshot["gold"])
	courier_hp = int(snapshot["courier_hp"])
	shop = snapshot["shop"]
	bench = snapshot["bench"]
	inventory = snapshot["inventory"]
	for key in snapshot["board"]:
		board[int(key)] = snapshot["board"][key]
	for key in snapshot["equipped"]:
		equipped[int(key)] = snapshot["equipped"][key]
	phase = "preparation"
	_note("已恢复第 %d 回合起点；本回合上次操作需重做" % round_number)
	_refresh_ui()


func _on_restart_pressed() -> void:
	round_number = 1
	level = 1
	xp = 0
	gold = 0
	courier_hp = 100
	shop.clear()
	bench.clear()
	board.clear()
	inventory.clear()
	equipped.clear()
	event_log.clear()
	_start_round()


func _on_shop_pressed(index: int) -> void:
	if phase != "preparation" or shop[index] == "":
		return
	var name: String = shop[index]
	var cost := int(unit_defs[name]["cost"])
	if cost > gold or bench.size() >= 8:
		_note("购买失败：金币不足或候场已满")
		return
	gold -= cost
	bench.append(name)
	shop[index] = ""
	_note("购买 %s，花费 %d" % [unit_defs[name]["name_zh"], cost])
	_refresh_ui()


func _on_bench_pressed(index: int) -> void:
	if phase == "preparation" and index < bench.size():
		selected_bench = index
		_refresh_ui()


func _on_board_pressed(index: int) -> void:
	if phase != "preparation" or index / 8 >= 4:
		return
	if selected_bench >= 0 and selected_bench < bench.size():
		if board.has(index):
			_note("目标格已有棋子")
			return
		if board.size() >= level:
			_note("上场人数不能超过等级 %d" % level)
			return
		board[index] = bench.pop_at(selected_bench)
		selected_bench = -1
	elif board.has(index):
		if bench.size() >= 8:
			_note("候场已满")
			return
		if equipped.has(index):
			inventory.append(equipped[index])
			equipped.erase(index)
		bench.append(board[index])
		board.erase(index)
	_refresh_ui()


func _on_equip_pressed() -> void:
	if phase != "preparation" or inventory.is_empty() or board.is_empty():
		return
	var positions := board.keys()
	positions.sort()
	var position: int = positions[0]
	if equipped.has(position):
		_note("该棋子已有测试装备")
		return
	var item: String = inventory.pop_front()
	equipped[position] = item
	_note("%s 装备 %s，攻击 +10；外观不改变" % [unit_defs[board[position]]["name_zh"], item])
	_refresh_ui()


func _on_battle_pressed() -> void:
	if phase != "preparation" or board.is_empty():
		_note("先购买并布置至少一名棋子")
		return
	phase = "battle"
	rng.seed = SEED + round_number
	var result := _simulate_battle()
	phase = "settlement"
	if result["win"]:
		_note("第 %d 回合胜利，战斗用时 %.1f 秒" % [round_number, result["seconds"]])
	else:
		var loss := int(result["courier_loss"])
		courier_hp = max(0, courier_hp - loss)
		_note("第 %d 回合失败，剩余野怪 %d，只扣信使 %d HP" % [round_number, result["enemy_survivors"], loss])
	for _i in range(int(result["monster_kills"])):
		if rng.randf() < 0.15:
			inventory.append("attack_blades")
			_note("野怪掉落：攻击之爪（测试掉落池）")
	_refresh_ui()


func _on_next_pressed() -> void:
	if phase != "settlement" or round_number >= 3:
		return
	xp += 1
	while level <= XP_TO_NEXT.size() and xp >= XP_TO_NEXT[level - 1]:
		xp -= XP_TO_NEXT[level - 1]
		level += 1
	round_number += 1
	_start_round()


func _make_actor(definition: Dictionary, team: int, position: Vector2, star: int = 1) -> Dictionary:
	var index := star - 1
	var monster := team == 1
	return {
		"name": definition["name_zh"], "team": team, "pos": position,
		"hp": float(definition["hp"] if monster else definition["hp"][index]),
		"attack_min": float(definition["attack_damage"] if monster else definition["attack_min"][index]),
		"attack_max": float(definition["attack_damage"] if monster else definition["attack_max"][index]),
		"armor": float(definition["armor"] if monster else definition["armor"][index]),
		"magic_resist": float(definition["magic_resistance_percent"] if monster else definition["magic_resistance_percent"][index]),
		"attack_interval": float(definition["base_attack_time_s"]),
		"attack_point": float(definition["attack_point_s"]),
		"range": float(definition["attack_range_grids"]),
		"speed": float(definition["movement_speed_units_per_s"] if monster else definition["movement_speed"]),
		"ability": definition["ability"], "mana": 0.0 if monster else float(definition["initial_mana"]),
		"max_mana": 0.0 if monster else float(definition["max_mana"]),
		"mana_attack": 0.0 if monster else float(definition["mana_gain_on_attack"]),
		"mana_damage": 0.0 if monster else float(definition["mana_gain_on_damage"]),
		"next_attack": 0.0, "windup_until": -1.0, "attack_target": {},
		"cast_until": -1.0, "next_cast": 0.0, "stunned_until": 0.0,
		"taunt_until": 0.0, "armor_bonus": 0.0, "armor_bonus_until": 0.0,
		"item_attack": 0.0, "star": star, "monster_id": ""
	}


func _simulate_battle() -> Dictionary:
	var actors: Array = []
	var positions := board.keys()
	positions.sort()
	for index in positions:
		var actor := _make_actor(unit_defs[board[index]], 0, Vector2(index % 8, index / 8))
		if equipped.get(index, "") == "attack_blades":
			actor["item_attack"] = 10.0
		actors.append(actor)
	var wave: Dictionary = {}
	for candidate in content["waves"]:
		if int(candidate["round"]) == round_number:
			wave = candidate
			break
	for spawn in wave["spawns"]:
		var monster_actor := _make_actor(monster_defs[spawn["monster_id"]], 1, Vector2(spawn["col"], spawn["row"]))
		monster_actor["monster_id"] = spawn["monster_id"]
		actors.append(monster_actor)
	_assassin_jump(actors)
	var tick := float(content["prototype_rules"]["tick_s"])
	var limit := float(content["prototype_rules"]["battle_limit_s"])
	var time := 0.0
	var monster_kills := 0
	while time < limit:
		var hits: Array = []
		for actor in actors:
			if actor["hp"] <= 0:
				continue
			if actor["stunned_until"] > time:
				actor["windup_until"] = -1.0
				continue
			if actor["windup_until"] >= 0 and time >= actor["windup_until"]:
				var old_target: Dictionary = actor["attack_target"]
				if not old_target.is_empty() and old_target["hp"] > 0:
					var damage: float = rng.randf_range(actor["attack_min"], actor["attack_max"]) + actor["item_attack"]
					if actor["name"] == unit_defs["Phantom Assassin"]["name_zh"]:
						var chance := float(actor["ability"]["proc_chance_percent"][0]) / 100.0
						if rng.randf() < chance:
							damage *= float(actor["ability"]["values"][0]) / 100.0
							_note("幽刃触发暴击")
					hits.append({"source": actor, "target": old_target, "damage": damage, "type": "physical", "basic": true})
				actor["windup_until"] = -1.0
			if actor["cast_until"] >= 0 and time >= actor["cast_until"]:
				_release_ability(actor, actors, time, hits)
				actor["cast_until"] = -1.0
				continue
			if actor["cast_until"] >= 0:
				continue
			var ability: Dictionary = actor["ability"]
			if actor["team"] == 0 and ability["kind"] in ["taunt_armor", "ravage"] and actor["mana"] >= actor["max_mana"] and time >= actor["next_cast"]:
				actor["mana"] -= float(ability["mana_cost"])
				actor["cast_until"] = time + float(ability["cast_point_s"])
				actor["next_cast"] = time + float(ability["cooldown_s"][0])
				continue
			if actor["windup_until"] >= 0:
				continue
			var target := _choose_target(actor, actors, time)
			if target.is_empty():
				continue
			var distance: float = actor["pos"].distance_to(target["pos"])
			if distance > actor["range"]:
				var movement: float = min(distance - actor["range"], actor["speed"] / 100.0 * tick)
				actor["pos"] += (target["pos"] - actor["pos"]).normalized() * movement
			elif time >= actor["next_attack"]:
				actor["attack_target"] = target
				actor["windup_until"] = time + actor["attack_point"]
				actor["next_attack"] = time + actor["attack_interval"]
		for hit in hits:
			var victim: Dictionary = hit["target"]
			var attacker: Dictionary = hit["source"]
			if victim["hp"] <= 0:
				continue
			var armor: float = victim["armor"] + (victim["armor_bonus"] if victim["armor_bonus_until"] > time else 0.0)
			var multiplier: float = 1.0 - (0.06 * armor) / (1.0 + 0.06 * abs(armor)) if hit["type"] == "physical" else 1.0 - victim["magic_resist"] / 100.0
			var actual: float = min(victim["hp"], max(0.0, round(hit["damage"] * multiplier)))
			victim["hp"] -= actual
			if hit["basic"]:
				attacker["mana"] = min(attacker["max_mana"], attacker["mana"] + attacker["mana_attack"])
			victim["mana"] = min(victim["max_mana"], victim["mana"] + victim["mana_damage"])
			if victim["hp"] <= 0:
				_note("%.1f 秒：%s 击败 %s" % [time, attacker["name"], victim["name"]])
				if victim["team"] == 1:
					monster_kills += 1
		var friendly := 0
		var enemy := 0
		for actor in actors:
			if actor["hp"] > 0:
				if actor["team"] == 0:
					friendly += 1
				else:
					enemy += 1
		if enemy == 0 or friendly == 0:
			return {"win": enemy == 0, "seconds": time, "enemy_survivors": enemy,
				"courier_loss": _monster_loss(actors), "monster_kills": monster_kills}
		time += tick
	var survivors := 0
	for actor in actors:
		if actor["team"] == 1 and actor["hp"] > 0:
			survivors += 1
	return {"win": false, "seconds": limit, "enemy_survivors": survivors,
		"courier_loss": _monster_loss(actors), "monster_kills": monster_kills}


func _monster_loss(actors: Array) -> int:
	var loss := 0
	for actor in actors:
		if actor["team"] == 1 and actor["hp"] > 0:
			loss += 2 if actor["monster_id"] == "enhanced_creep" else 1
	return int(min(15, loss))


func _choose_target(actor: Dictionary, actors: Array, time: float) -> Dictionary:
	var nearest: Dictionary = {}
	var best := INF
	var has_taunt := false
	for candidate in actors:
		if candidate["team"] == actor["team"] or candidate["hp"] <= 0:
			continue
		var distance: float = actor["pos"].distance_to(candidate["pos"])
		var taunting: bool = candidate["taunt_until"] > time and distance <= 1.0
		if taunting and not has_taunt:
			has_taunt = true
			best = INF
			nearest = {}
		if has_taunt and not taunting:
			continue
		if distance < best:
			best = distance
			nearest = candidate
	return nearest


func _assassin_jump(actors: Array) -> void:
	for actor in actors:
		if actor["team"] != 0 or actor["name"] != unit_defs["Phantom Assassin"]["name_zh"]:
			continue
		var target := _choose_target(actor, actors, 0.0)
		if target.is_empty():
			continue
		for offset in [Vector2(0, 1), Vector2(-1, 1), Vector2(1, 1)]:
			var landing: Vector2 = target["pos"] + offset
			if landing.x < 0 or landing.x > 7 or landing.y > 7:
				continue
			var occupied := false
			for other in actors:
				if other["pos"] == landing:
					occupied = true
			if not occupied:
				actor["pos"] = landing
				_note("开战：幽刃跳至敌方后排")
				break


func _release_ability(actor: Dictionary, actors: Array, time: float, hits: Array) -> void:
	var ability: Dictionary = actor["ability"]
	if ability["kind"] == "taunt_armor":
		actor["armor_bonus"] = float(ability["values"][0])
		actor["armor_bonus_until"] = time + float(ability["duration_s"][0])
		actor["taunt_until"] = actor["armor_bonus_until"]
		_note("%.1f 秒：赤斧施放嘲讽" % time)
	elif ability["kind"] == "ravage":
		for victim in actors:
			if victim["team"] != actor["team"] and victim["hp"] > 0 and actor["pos"].distance_to(victim["pos"]) <= float(ability["radius_grids"]):
				victim["stunned_until"] = time + float(ability["duration_s"][0])
				hits.append({"source": actor, "target": victim, "damage": float(ability["values"][0]), "type": "magic", "basic": false})
		_note("%.1f 秒：怒潮海卫施放毁灭" % time)


func _note(message: String) -> void:
	event_log.append(message)
	if event_log.size() > 80:
		event_log.pop_front()
	if log_box != null:
		log_box.text = "\n".join(event_log)
		log_box.scroll_to_line(event_log.size() - 1)


func _refresh_ui() -> void:
	title_label.text = "2019 自走棋纵向原型 | 回合 %d/3 | 等级 %d | 金币 %d | 信使 %d HP | 阶段 %s" % [round_number, level, gold, courier_hp, phase]
	message_label.text = "固定种子 %d；本原型只开放 3 名棋子、1～3 回合野怪。攻击之爪库存：%d" % [SEED, inventory.size()]
	for i in range(3):
		var name: String = shop[i]
		shop_buttons[i].text = "已购买" if name == "" else "%s · %d 金" % [unit_defs[name]["name_zh"], unit_defs[name]["cost"]]
		shop_buttons[i].disabled = phase != "preparation" or name == ""
	for i in range(8):
		bench_buttons[i].text = "%d. %s" % [i + 1, unit_defs[bench[i]]["name_zh"]] if i < bench.size() else "%d. 空" % [i + 1]
		bench_buttons[i].disabled = phase != "preparation" or i >= bench.size()
	var enemy_markers: Dictionary = {}
	for wave in content["waves"]:
		if int(wave["round"]) == round_number:
			for spawn in wave["spawns"]:
				enemy_markers[int(spawn["row"]) * 8 + int(spawn["col"])] = monster_defs[spawn["monster_id"]]["name_zh"]
			break
	for i in range(64):
		var row := i / 8
		var label: String = "·" if row < 4 else str(enemy_markers.get(i, "·"))
		if board.has(i):
			label = unit_defs[board[i]]["name_zh"] + (" +爪" if equipped.get(i, "") == "attack_blades" else "")
		board_buttons[i].text = label
		board_buttons[i].disabled = phase != "preparation" or row >= 4
	battle_button.disabled = phase != "preparation" or board.is_empty()
	next_button.disabled = phase != "settlement" or round_number >= 3
	equip_button.disabled = phase != "preparation" or inventory.is_empty() or board.is_empty()
