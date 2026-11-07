extends RefCounted

const Combat = preload("res://scripts/combat.gd")
const SAVE_PATH := "user://full_game_round_start.json"

var content: Dictionary = {}
var units: Dictionary = {}
var monster_courier_damage: Dictionary = {}
var players: Array = []
var pool: Dictionary = {}
var round_number := 1
var phase := "preparation"
var random_state := 9252019
var event_log: Array = []
var match_history: Dictionary = {}
var last_results: Dictionary = {}
var chest_choices: Array = []
var battle_replay: Dictionary = {}
var seat_replays: Dictionary = {}
var battle_pending_phase := ""
var pending_ai_actions: Array = []
var ai_preparation_elapsed := 0.0
var ai_difficulty := "medium"


func _init() -> void:
	var file := FileAccess.open("res://data/content.json", FileAccess.READ)
	if file == null:
		push_error("Missing runtime content.json")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid runtime content.json")
		return
	content = parsed
	for unit in content["units"]:
		units[unit["name_en"]] = unit
	for monster in content["monsters"]:
		monster_courier_damage[monster["id"]] = int(monster["courier_damage"])


func _random(max_exclusive: int) -> int:
	random_state = (random_state * 1103515245 + 12345) & 0x7fffffff
	return random_state % max_exclusive if max_exclusive > 0 else 0


func _log(message: String) -> void:
	event_log.append(message)
	if event_log.size() > 200:
		event_log.pop_front()


func new_game(seed_value: int = -1, include_return_pool: bool = true, defer_ai: bool = false,
		difficulty: String = "medium") -> void:
	ai_difficulty = difficulty if difficulty in ["easy", "medium", "hard"] else "medium"
	if seed_value == -1:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		seed_value = rng.randi_range(0, 0x7fffffff)
	random_state = seed_value & 0x7fffffff
	round_number = 1
	phase = "preparation"
	pool.clear()
	players.clear()
	event_log.clear()
	match_history.clear()
	last_results.clear()
	chest_choices.clear()
	battle_replay.clear()
	seat_replays.clear()
	battle_pending_phase = ""
	pending_ai_actions.clear()
	ai_preparation_elapsed = 0.0
	for name in units:
		var cost := int(units[name]["cost"])
		pool[name] = 0 if not include_return_pool and units[name]["return_pool"] else 10 if name == "Io" else int(content["economy"]["pool_by_cost"][str(cost)])
	for seat in range(8):
		players.append({"seat": seat, "hp": 100, "gold": 0, "level": 1, "xp": 0,
			"bench": [], "bench_layout": [], "board": {}, "inventory": [], "shop": [], "shop_locked": false,
			"streak": 0, "pending_interest": 0, "pending_win_gold": 0,
			"pending_streak_gold": 0, "alive": true, "eliminated_round": 0,
			"last_opponents": [], "undropped_monster_kills": 0,
			"ai_style": "human" if seat == 0 else ai_difficulty})
	start_round(defer_ai)


func save_round_start() -> bool:
	return _save_to(SAVE_PATH)


func _save_to(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": content["version"], "round": round_number,
		"phase": "preparation", "random_state": random_state,
		"players": players, "pool": pool, "match_history": match_history,
		"last_results": last_results, "chest_choices": chest_choices,
		"pending_ai_actions": pending_ai_actions, "ai_preparation_elapsed": ai_preparation_elapsed,
		"ai_difficulty": ai_difficulty}))
	return true


func load_round_start() -> bool:
	return _load_from(SAVE_PATH)


func _load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("version", "") != content.get("version", ""):
		return false
	round_number = int(parsed["round"])
	random_state = int(parsed["random_state"])
	players = parsed["players"]
	pool = parsed["pool"]
	match_history = parsed.get("match_history", {})
	last_results = parsed.get("last_results", {})
	chest_choices = parsed.get("chest_choices", []).filter(func(id): return id not in ["tango", "mango"])
	pending_ai_actions = parsed.get("pending_ai_actions", [])
	ai_preparation_elapsed = float(parsed.get("ai_preparation_elapsed", 0.0))
	ai_difficulty = str(parsed.get("ai_difficulty", players[1].get("ai_style", "medium")))
	if ai_difficulty not in ["easy", "medium", "hard"]: ai_difficulty = "medium"
	for seat in range(1, players.size()): players[seat]["ai_style"] = ai_difficulty
	battle_replay.clear()
	seat_replays.clear()
	battle_pending_phase = ""
	event_log.clear()
	for player in players:
		var board_fixed := {}
		for index in player["board"]:
			board_fixed[int(index)] = player["board"][index]
		player["board"] = board_fixed
		# Removed consumables from older saves cannot remain as dangling equipment IDs.
		player.inventory = player.inventory.filter(func(item): return item.id not in ["tango", "mango"])
		for piece in player.bench + player.board.values():
			piece.items = piece.items.filter(func(item): return item.id not in ["tango", "mango"])
	phase = "preparation"
	_log("恢复第 %d 回合起点" % round_number)
	return true


func save_slot(slot: int) -> bool:
	if slot < 1 or slot > 3 or phase != "preparation":
		return false
	var source := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if source == null: return false
	var target := FileAccess.open("user://manual_%d.json" % slot, FileAccess.WRITE)
	if target == null: return false
	target.store_string(source.get_as_text())
	return true


func load_slot(slot: int) -> bool:
	if slot < 1 or slot > 3:
		return false
	return _load_from("user://manual_%d.json" % slot)


func _base_income() -> int:
	return min(round_number, 5)


func start_round(defer_ai: bool = false) -> void:
	phase = "preparation"
	battle_replay.clear()
	seat_replays.clear()
	battle_pending_phase = ""
	pending_ai_actions.clear()
	ai_preparation_elapsed = 0.0
	var draw_order: Array = []
	for player in players:
		if not player["alive"]:
			continue
		draw_order.append(int(player["seat"]))
		player["gold"] += _base_income() + int(player["pending_interest"]) + int(player["pending_win_gold"]) + int(player["pending_streak_gold"])
		player["pending_interest"] = 0
		player["pending_win_gold"] = 0
		player["pending_streak_gold"] = 0
		if not player["shop_locked"]:
			_return_shop(player)
	for index in range(draw_order.size() - 1, 0, -1):
		var other := _random(index + 1)
		var temp = draw_order[index]
		draw_order[index] = draw_order[other]
		draw_order[other] = temp
	for seat in draw_order:
		if not players[seat]["shop_locked"]: _draw_shop(players[seat])
	_log("第 %d 回合开始" % round_number)
	for seat in range(1, 8):
		if defer_ai:
			pending_ai_actions.append({"seat": seat, "step": "buy", "at": float(seat * 2)})
			pending_ai_actions.append({"seat": seat, "step": "place", "at": float(seat * 2 + 1)})
		else: _ai_prepare(seat)
	save_round_start()


func tick_ai_preparation(delta: float) -> bool:
	if phase != "preparation" or pending_ai_actions.is_empty(): return false
	ai_preparation_elapsed += delta
	var changed := false
	while not pending_ai_actions.is_empty() and ai_preparation_elapsed >= float(pending_ai_actions[0]["at"]):
		_run_ai_action(pending_ai_actions.pop_front())
		changed = true
	return changed


func _finish_ai_preparation() -> void:
	while not pending_ai_actions.is_empty(): _run_ai_action(pending_ai_actions.pop_front())


func _run_ai_action(action: Dictionary) -> void:
	var seat := int(action["seat"])
	if action["step"] == "buy": _ai_prepare_buy(seat)
	else: _ai_prepare_place(seat)


func _return_shop(player: Dictionary) -> void:
	for name in player["shop"]:
		if name != "":
			pool[name] += 1
	player["shop"] = []


func _weighted_cost(level: int) -> int:
	var weights: Array = content["shop_odds_by_level"][str(clampi(level, 1, 10))]
	var roll := _random(100)
	for index in range(5):
		roll -= int(weights[index])
		if roll < 0:
			return index + 1
	return 5


func _draw_name(cost: int) -> String:
	var candidates: Array = []
	var total := 0
	for name in pool:
		if int(units[name]["cost"]) == cost and int(pool[name]) > 0:
			candidates.append(name)
			total += int(pool[name])
	if total == 0:
		return ""
	candidates.sort()
	var roll := _random(total)
	for name in candidates:
		roll -= int(pool[name])
		if roll < 0:
			pool[name] -= 1
			return name
	return ""


func _draw_shop(player: Dictionary) -> void:
	for _slot in range(5):
		var cost := _weighted_cost(int(player["level"]))
		var name := _draw_name(cost)
		if name == "":
			for fallback_cost in range(1, 6):
				name = _draw_name(fallback_cost)
				if name != "":
					break
		player["shop"].append(name)


func reroll(seat: int) -> bool:
	var player: Dictionary = players[seat]
	if phase not in ["preparation", "battle"] or not player["alive"] or player["gold"] < 2:
		return false
	player["gold"] -= 2
	_return_shop(player)
	_draw_shop(player)
	return true


func toggle_lock(seat: int) -> bool:
	if phase not in ["preparation", "battle"]:
		return false
	players[seat]["shop_locked"] = not players[seat]["shop_locked"]
	return true


func default_battle_seconds() -> int:
	return int(content["economy"]["battle_seconds"])


func seat_replay(seat: int) -> Dictionary:
	return seat_replays.get(seat, {})


func battle_total_seconds() -> float:
	var maximum := 0.0
	for replay in seat_replays.values(): maximum = maxf(maximum, float(replay.get("seconds", 0.0)))
	return maximum if maximum > 0.0 else float(battle_replay.get("seconds", 0.0))


func buy_xp(seat: int) -> bool:
	var player: Dictionary = players[seat]
	if phase not in ["preparation", "battle"] or player["gold"] < 5 or player["level"] >= 10:
		return false
	player["gold"] -= 5
	_gain_xp(player, 4)
	return true


func _gain_xp(player: Dictionary, amount: int) -> void:
	player["xp"] += amount
	var thresholds: Array = content["economy"]["xp_thresholds"]
	while player["level"] < 10 and player["xp"] >= int(thresholds[player["level"] - 1]):
		player["xp"] -= int(thresholds[player["level"] - 1])
		player["level"] += 1


func _can_merge_with(name: String, player: Dictionary) -> bool:
	var count := 0
	for piece in player["bench"]:
		if piece["id"] == name and piece["star"] == 1:
			count += 1
	for piece in player["board"].values():
		if piece["id"] == name and piece["star"] == 1:
			count += 1
	var druid: bool = "德鲁伊" in str(units[name]["class"])
	var distinct_after := _druid_count(player)
	if druid and not _owns_piece(player, name): distinct_after += 1
	return count >= (1 if druid and distinct_after >= 2 else 2)


func _owns_piece(player: Dictionary, name: String) -> bool:
	for piece in player["bench"]:
		if piece["id"] == name: return true
	for piece in player["board"].values():
		if piece["id"] == name: return true
	return false


func _druid_count(player: Dictionary) -> int:
	var ids: Dictionary = {}
	for piece in player["board"].values():
		if "德鲁伊" in str(units[piece["id"]]["class"]): ids[piece["id"]] = true
	for piece in player["bench"]:
		if "德鲁伊" in str(units[piece["id"]]["class"]): ids[piece["id"]] = true
	return ids.size()


func _buy_fits_bench(player: Dictionary, name: String) -> bool:
	if player["bench"].size() < 8: return true
	var preview: Dictionary = player.duplicate(true)
	_bench_put(preview, {"id": name, "star": 1, "items": []})
	_merge_all(preview)
	return preview["bench"].size() <= 8


func buy(seat: int, slot: int) -> bool:
	var player: Dictionary = players[seat]
	if phase not in ["preparation", "battle"] or slot < 0 or slot >= player["shop"].size():
		return false
	var name: String = player["shop"][slot]
	if name == "" or player["gold"] < int(units[name]["cost"]):
		return false
	if not _buy_fits_bench(player, name):
		return false
	player["gold"] -= int(units[name]["cost"])
	player["shop"][slot] = ""
	_bench_put(player, {"id": name, "star": 1, "items": []})
	_merge_all(player)
	return true


func _bench_layout(player: Dictionary) -> Array:
	var layout: Array = player.get("bench_layout", [])
	if layout.size() != 8:
		layout = [-1, -1, -1, -1, -1, -1, -1, -1]
		player["bench_layout"] = layout
	var seen: Dictionary = {}
	for slot in range(8):
		var index := int(layout[slot])
		if index < 0 or index >= player["bench"].size() or seen.has(index): layout[slot] = -1
		else: seen[index] = true
	for index in range(player["bench"].size()):
		if seen.has(index): continue
		for slot in range(8):
			if int(layout[slot]) < 0:
				layout[slot] = index
				break
	return layout


func bench_index_at_slot(seat: int, slot: int) -> int:
	if seat < 0 or seat >= players.size() or slot < 0 or slot >= 8: return -1
	return int(_bench_layout(players[seat])[slot])


func _bench_take(player: Dictionary, index: int) -> Dictionary:
	var layout := _bench_layout(player)
	var piece: Dictionary = player["bench"].pop_at(index)
	for slot in range(8):
		if int(layout[slot]) == index: layout[slot] = -1
		elif int(layout[slot]) > index: layout[slot] = int(layout[slot]) - 1
	return piece


func _bench_put(player: Dictionary, piece: Dictionary, preferred_slot: int = -1) -> void:
	var layout := _bench_layout(player)
	player["bench"].append(piece)
	if preferred_slot >= 0 and preferred_slot < 8 and int(layout[preferred_slot]) < 0:
		layout[preferred_slot] = player["bench"].size() - 1
		return
	for slot in range(8):
		if int(layout[slot]) < 0:
			layout[slot] = player["bench"].size() - 1
			return


func move_piece_slot(seat: int, from_board: bool, from_index: int, to_board: bool, to_index: int) -> bool:
	if phase not in ["preparation", "battle"]: return false
	if phase == "battle" and (from_board or to_board): return false
	if from_board and to_board: return move_piece(seat, true, from_index, true, to_index)
	var player: Dictionary = players[seat]
	if not from_board and (from_index < 0 or from_index >= 8): return false
	if not to_board and (to_index < 0 or to_index >= 8): return false
	var layout := _bench_layout(player)
	if not from_board and not to_board:
		if int(layout[from_index]) < 0: return false
		var other = layout[to_index]
		layout[to_index] = layout[from_index]
		layout[from_index] = other
		return true
	if from_board:
		if not player["board"].has(from_index): return false
		var target := int(layout[to_index])
		if target >= 0: return move_piece(seat, true, from_index, false, target)
		if player["bench"].size() >= 8: return false
		_bench_put(player, player["board"][from_index], to_index)
		player["board"].erase(from_index)
		return true
	var actual := int(layout[from_index])
	return move_piece(seat, false, actual, true, to_index) if actual >= 0 else false


func can_copy_io(seat: int, from_board: bool, from_index: int, to_board: bool, to_index: int) -> bool:
	if phase not in ["preparation","battle"] or (phase == "battle" and (from_board or to_board)): return false
	if from_board == to_board and from_index == to_index: return false
	var player: Dictionary = players[seat]
	var source: Dictionary = player.board.get(from_index,{}) if from_board else player.bench[from_index] if from_index >= 0 and from_index < player.bench.size() else {}
	var target: Dictionary = player.board.get(to_index,{}) if to_board else player.bench[to_index] if to_index >= 0 and to_index < player.bench.size() else {}
	return source.get("id","") == "Io" and not target.is_empty() and target.id != "Io"

func copy_io(seat: int, from_board: bool, from_index: int, to_board: bool, to_index: int) -> bool:
	if not can_copy_io(seat,from_board,from_index,to_board,to_index): return false
	var player: Dictionary = players[seat]
	var source: Dictionary = player.board[from_index] if from_board else player.bench[from_index]
	var target: Dictionary = player.board[to_index] if to_board else player.bench[to_index]
	source["pool_returns"] = _pool_parts(source)
	source.id = target.id
	# The source star and equipment remain; the target is never consumed or duplicated.
	_merge_all(player)
	return true

func _pool_parts(piece: Dictionary) -> Dictionary:
	return piece.get("pool_returns",{piece.id:int(pow(3,int(piece.star)-1))}).duplicate()

func _return_piece_pool(piece: Dictionary) -> void:
	var counts := _pool_parts(piece)
	for id in counts: pool[id] += int(counts[id])


func _merge_all(player: Dictionary) -> void:
	var changed := true
	while changed:
		changed = false
		for name in units:
			for star in [1, 2]:
				var found: Array = []
				var positions: Array = player["board"].keys()
				positions.sort()
				for position in positions:
					var piece: Dictionary = player["board"][position]
					if piece["id"] == name and int(piece["star"]) == star:
						found.append({"place": "board", "index": position, "piece": piece})
				for index in range(player["bench"].size()):
					var piece: Dictionary = player["bench"][index]
					if piece["id"] == name and int(piece["star"]) == star:
						found.append({"place": "bench", "index": index, "piece": piece})
				var required := 2 if "德鲁伊" in str(units[name]["class"]) and _druid_count(player) >= (2 if star == 1 else 4) else 3
				if found.size() < required:
					continue
				var materials: Array = found.slice(0, required)
				var combined_items: Array = []
				for material in materials:
					combined_items.append_array(material["piece"]["items"])
				var product := {"id": name, "star": star + 1, "items": combined_items.slice(0, 6)}
				if materials.any(func(entry): return entry.piece.has("pool_returns")):
					var counts := {}
					for entry in materials:
						var parts := _pool_parts(entry.piece)
						for id in parts: counts[id] = int(counts.get(id,0))+int(parts[id])
					product["pool_returns"] = counts
				if combined_items.size() > 6:
					player["inventory"].append_array(combined_items.slice(6))
				var destination = materials[0]
				for material in materials:
					if material["place"] == "board":
						destination = material
						break
				var destination_slot := -1
				if destination["place"] == "bench":
					var layout := _bench_layout(player)
					for slot in range(8):
						if int(layout[slot]) == int(destination["index"]): destination_slot = slot
				var bench_indexes: Array = []
				for material in materials:
					if material["place"] == "board":
						player["board"].erase(material["index"])
					else:
						bench_indexes.append(material["index"])
				bench_indexes.sort()
				bench_indexes.reverse()
				for index in bench_indexes:
					_bench_take(player, index)
				if destination["place"] == "board":
					player["board"][destination["index"]] = product
				else:
					_bench_put(player, product, destination_slot)
				changed = true
				break
			if changed:
				break


func place(seat: int, bench_index: int, board_index: int) -> bool:
	var player: Dictionary = players[seat]
	if phase != "preparation" or bench_index < 0 or bench_index >= player["bench"].size():
		return false
	if board_index < 0 or board_index >= 32 or player["board"].has(board_index):
		return false
	player["board"][board_index] = _bench_take(player, bench_index)
	return true


func unplace(seat: int, board_index: int) -> bool:
	var player: Dictionary = players[seat]
	if phase != "preparation" or not player["board"].has(board_index) or player["bench"].size() >= 8:
		return false
	_bench_put(player, player["board"][board_index])
	player["board"].erase(board_index)
	return true


func sell(seat: int, from_board: bool, index: int) -> bool:
	var player: Dictionary = players[seat]
	var collection: Variant = player["board"] if from_board else player["bench"]
	if phase not in ["preparation", "battle"] or (not collection.has(index) if from_board else index < 0 or index >= collection.size()):
		return false
	var piece: Dictionary = collection[index]
	player["gold"] += int(units[piece["id"]]["sell_gold"][int(piece["star"]) - 1])
	_return_piece_pool(piece)
	player["inventory"].append_array(piece["items"])
	if from_board:
		collection.erase(index)
	else:
		_bench_take(player, index)
	return true


func equip(seat: int, item_index: int, from_board: bool, piece_index: int) -> bool:
	var player: Dictionary = players[seat]
	var collection: Variant = player["board"] if from_board else player["bench"]
	if phase not in ["preparation", "battle"] or item_index < 0 or item_index >= player["inventory"].size():
		return false
	if (not collection.has(piece_index) if from_board else piece_index < 0 or piece_index >= collection.size()):
		return false
	var items: Array = collection[piece_index]["items"]
	var moving: Dictionary = player["inventory"][item_index]
	for existing_index in range(items.size()):
		var product := _pair_product(items[existing_index], moving)
		if not product.is_empty():
			player["inventory"].remove_at(item_index)
			items[existing_index] = product
			return true
	if items.size() >= 6: return false
	items.append(player["inventory"].pop_at(item_index))
	return true


func _recipe_matches_pair(recipe: Array, first_id: String, second_id: String) -> bool:
	var needed: Dictionary = {}
	for part in recipe: needed[part["item_id"]] = int(needed.get(part["item_id"], 0)) + int(part["count"])
	var provided := {first_id: 1}
	provided[second_id] = int(provided.get(second_id, 0)) + 1
	return needed == provided


func _pair_product(first: Dictionary, second: Dictionary) -> Dictionary:
	var ids: Array = content["items"].keys()
	ids.sort()
	for item_id in ids:
		var definition: Dictionary = content["items"][item_id]
		if _recipe_matches_pair(definition["recipe"], first["id"], second["id"]):
			return {"id": item_id, "level": 1, "crafted": true, "materials": [first, second]}
	var dagon: Dictionary = content["items"]["dagon_1_5"]
	if _recipe_matches_pair(dagon["upgrade_recipe"], first["id"], second["id"]):
		var old: Dictionary = first if first["id"] == "dagon_1_5" else second
		if int(old.get("level", 1)) < 5:
			return {"id": "dagon_1_5", "level": int(old.get("level", 1)) + 1,
				"crafted": true, "materials": [first, second]}
	return {}


func move_piece(seat: int, from_board: bool, from_index: int, to_board: bool, to_index: int) -> bool:
	if phase != "preparation": return false
	var player: Dictionary = players[seat]
	var board: Dictionary = player["board"]
	var bench: Array = player["bench"]
	if from_board and not board.has(from_index): return false
	if not from_board and (from_index < 0 or from_index >= bench.size()): return false
	if to_board and (to_index < 0 or to_index >= 32): return false
	if not to_board and (to_index < 0 or to_index >= 8): return false
	if from_board == to_board and from_index == to_index: return true
	if not to_board and to_index >= bench.size() and from_board and bench.size() >= 8: return false
	var moving: Dictionary = board[from_index] if from_board else bench[from_index]
	if from_board and to_board:
		if board.has(to_index): board[from_index] = board[to_index]
		else: board.erase(from_index)
		board[to_index] = moving
	elif not from_board and not to_board:
		if to_index < bench.size():
			bench[from_index] = bench[to_index]
			bench[to_index] = moving
		else:
			_bench_take(player, from_index)
			_bench_put(player, moving)
	elif from_board:
		if to_index < bench.size():
			board[from_index] = bench[to_index]
			bench[to_index] = moving
		else:
			board.erase(from_index)
			_bench_put(player, moving)
	else:
		if board.has(to_index): bench[from_index] = board[to_index]
		else: _bench_take(player, from_index)
		board[to_index] = moving
	return true


func unequip(seat: int, from_board: bool, piece_index: int, item_index: int) -> bool:
	if phase not in ["preparation", "battle"]: return false
	var player: Dictionary = players[seat]
	var collection: Variant = player["board"] if from_board else player["bench"]
	if (not collection.has(piece_index) if from_board else piece_index < 0 or piece_index >= collection.size()): return false
	var items: Array = collection[piece_index]["items"]
	if item_index < 0 or item_index >= items.size(): return false
	player["inventory"].append(items.pop_at(item_index))
	return true


func transfer_item(seat: int, source_board: bool, source_index: int, item_index: int,
		target_board: bool, target_index: int) -> bool:
	if phase not in ["preparation", "battle"]: return false
	var player: Dictionary = players[seat]
	var source: Variant = player["board"] if source_board else player["bench"]
	var target: Variant = player["board"] if target_board else player["bench"]
	if (not source.has(source_index) if source_board else source_index < 0 or source_index >= source.size()): return false
	if (not target.has(target_index) if target_board else target_index < 0 or target_index >= target.size()): return false
	if source_board == target_board and source_index == target_index: return false
	var source_items: Array = source[source_index]["items"]
	var target_items: Array = target[target_index]["items"]
	if item_index < 0 or item_index >= source_items.size(): return false
	for existing_index in range(target_items.size()):
		var product := _pair_product(target_items[existing_index], source_items[item_index])
		if not product.is_empty():
			source_items.remove_at(item_index)
			target_items[existing_index] = product
			return true
	if target_items.size() >= 6: return false
	target_items.append(source_items.pop_at(item_index))
	return true


func combine_equipped(seat: int, from_board: bool, piece_index: int, item_index: int) -> bool:
	if phase not in ["preparation", "battle"]: return false
	var player: Dictionary = players[seat]
	var collection: Variant = player["board"] if from_board else player["bench"]
	if (not collection.has(piece_index) if from_board else piece_index < 0 or piece_index >= collection.size()): return false
	var items: Array = collection[piece_index]["items"]
	if item_index < 0 or item_index >= items.size(): return false
	for existing_index in range(items.size()):
		if existing_index == item_index: continue
		var product := _pair_product(items[existing_index], items[item_index])
		if not product.is_empty():
			items[existing_index] = product
			items.remove_at(item_index)
			return true
	return false


func craft(seat: int, item_id: String, level: int = 1) -> bool:
	var player: Dictionary = players[seat]
	if phase not in ["preparation", "battle"] or not content["items"].has(item_id):
		return false
	if item_id == "dagon_1_5" and (level < 1 or level > 5):
		return false
	var recipe: Array = content["items"][item_id]["recipe"]
	if item_id == "dagon_1_5" and level > 1:
		recipe = content["items"][item_id]["upgrade_recipe"]
	if recipe.is_empty():
		return false
	var needed: Dictionary = {}
	var used_materials: Array = []
	for part in recipe:
		needed[part["item_id"]] = int(needed.get(part["item_id"], 0)) + int(part["count"])
	for material in needed:
		var owned := 0
		for item in player["inventory"]:
			if item["id"] == material and (material != "dagon_1_5" or int(item.get("level", 1)) == level - 1):
				owned += 1
		if owned < needed[material]:
			return false
	for material in needed:
		for _piece in range(needed[material]):
			for index in range(player["inventory"].size() - 1, -1, -1):
				var item: Dictionary = player["inventory"][index]
				if item["id"] == material and (material != "dagon_1_5" or int(item.get("level", 1)) == level - 1):
					used_materials.append(player["inventory"].pop_at(index))
					break
	player["inventory"].append({"id": item_id, "level": level, "crafted": true, "materials": used_materials})
	return true


func dismantle(seat: int, index: int) -> bool:
	var player: Dictionary = players[seat]
	if phase not in ["preparation", "battle"] or index < 0 or index >= player["inventory"].size(): return false
	var item: Dictionary = player["inventory"][index]
	var parts := _base_parts(item)
	if parts.size() == 1: return false
	player["inventory"].remove_at(index)
	player["inventory"].append_array(parts)
	return true


func _base_parts(item: Dictionary) -> Array:
	var materials: Array = item.get("materials", [])
	if materials.is_empty():
		var definition: Dictionary = content["items"][item["id"]]
		materials = definition["upgrade_recipe"] if item["id"] == "dagon_1_5" and int(item.get("level", 1)) > 1 else definition["recipe"]
		if materials.is_empty(): return [item]
		var expanded: Array = []
		for part in materials:
			for _count in range(int(part["count"])):
				expanded.append({"id": part["item_id"], "level": int(item.get("level", 1)) - 1 if part["item_id"] == "dagon_1_5" else 1})
		materials = expanded
	var result: Array = []
	for part in materials: result.append_array(_base_parts(part))
	return result


func dismantle_equipped(seat: int, from_board: bool, piece_index: int, item_index: int) -> bool:
	if phase not in ["preparation", "battle"]: return false
	var player: Dictionary = players[seat]
	var collection: Variant = player["board"] if from_board else player["bench"]
	if not collection.has(piece_index) if from_board else piece_index < 0 or piece_index >= collection.size(): return false
	var items: Array = collection[piece_index]["items"]
	if item_index < 0 or item_index >= items.size(): return false
	var parts := _base_parts(items[item_index])
	if parts.size() == 1: return false
	items.remove_at(item_index)
	player["inventory"].append_array(parts)
	return true


func unequip_all(seat: int, from_board: bool, piece_index: int) -> bool:
	if phase not in ["preparation", "battle"]: return false
	var player: Dictionary = players[seat]
	var collection: Variant = player["board"] if from_board else player["bench"]
	if not collection.has(piece_index) if from_board else piece_index < 0 or piece_index >= collection.size(): return false
	var items: Array = collection[piece_index]["items"]
	if items.is_empty(): return false
	player["inventory"].append_array(items)
	collection[piece_index]["items"] = []
	return true


func use_item(seat: int, index: int) -> bool:
	return false # No usable consumables remain; treasure uses the choice panel.


func _ai_prepare(seat: int) -> void:
	_ai_prepare_buy(seat)
	_ai_prepare_place(seat)


func _ai_economy_mode(player: Dictionary) -> String:
	if int(player["hp"]) <= 20 or (int(player["hp"]) <= 35 and int(player["streak"]) <= -2): return "止血"
	if int(player["streak"]) >= 3: return "连胜推进"
	if int(player["streak"]) <= -3: return "连败积累"
	return "发育"


func _ai_prepare_buy(seat: int) -> void:
	var player: Dictionary = players[seat]
	if not player["alive"]:
		return
	var difficulty: String = player["ai_style"]
	var mode := _ai_economy_mode(player)
	var protection := 0 if int(player["hp"]) <= 20 else 10 if int(player["hp"]) <= 40 else 30
	if difficulty == "easy": protection = 10 if int(player["hp"]) <= 35 else 25
	if difficulty == "medium": protection = 0 if mode == "止血" else 10 if mode == "连胜推进" else 30
	if difficulty == "hard": protection = 0 if mode == "止血" else 10 if mode == "连胜推进" else 25 if mode == "连败积累" else 20
	_log("AI 席位 %d：%s，%s，经验/刷新保留 %d 金" % [seat + 1, difficulty, mode, protection])
	_ai_buy_available(seat)
	var thresholds: Array = content["economy"]["xp_thresholds"]
	if int(player["level"]) < 10 and (player["board"].size() >= int(player["level"]) or round_number >= int(player["level"]) * 2):
		var xp_short := int(thresholds[int(player["level"]) - 1]) - int(player["xp"])
		var buy_count := 2 if difficulty == "hard" and int(player["hp"]) <= 30 and player["board"].size() >= int(player["level"]) else 1
		if xp_short <= 4 or buy_count == 2:
			for _buy in range(buy_count):
				if int(player["gold"]) - 5 >= protection: buy_xp(seat)
	if round_number >= 6:
		for _reroll in range(1 if difficulty == "easy" else 3 if difficulty == "hard" else 2):
			if player["bench"].size() >= 8 or int(player["gold"]) - 2 < protection or _ai_best_shop(player)["slot"] >= 0: break
			reroll(seat)
			_ai_buy_available(seat)
	if difficulty != "easy":
		var hold_shop := false
		for name in player["shop"]:
			if name == "" or int(units[name]["cost"]) <= int(player["gold"]): continue
			if _buy_fits_bench(player, name) and _ai_score(player, name) >= (45 if difficulty == "hard" else 60):
				hold_shop = true
				break
		if bool(player["shop_locked"]) != hold_shop: toggle_lock(seat)


func _ai_prepare_place(seat: int) -> void:
	var player: Dictionary = players[seat]
	if not player["alive"]: return
	_ai_place(seat)
	_ai_equip(player)


func _ai_tags(name: String) -> Array:
	var tags: Array = Array(str(units[name]["species"]).split("、"))
	tags.append_array(Array(str(units[name]["class"]).split("、")))
	return tags


func _ai_piece_count(player: Dictionary, name: String, star: int) -> int:
	var count := 0
	for piece in player["bench"]:
		if piece["id"] == name and int(piece["star"]) == star: count += 1
	for piece in player["board"].values():
		if piece["id"] == name and int(piece["star"]) == star: count += 1
	return count


func _ai_score(player: Dictionary, name: String) -> int:
	var score := int(units[name]["cost"]) * 2
	var difficulty: String = player["ai_style"]
	if _ai_piece_count(player, name, 2) >= 2: score += 100
	elif _ai_piece_count(player, name, 1) >= 2: score += 50
	var tag_members: Dictionary = {}
	var own_pieces: Array = player["board"].values()
	if difficulty != "easy": own_pieces += player["bench"]
	for piece in own_pieces:
		for tag in _ai_tags(piece["id"]):
			if not tag_members.has(tag): tag_members[tag] = {}
			tag_members[tag][piece["id"]] = true
	var common_tag := ""
	var common_size := -1
	for tag in tag_members:
		var size_value: int = tag_members[tag].size()
		if size_value > common_size or (size_value == common_size and (common_tag == "" or tag < common_tag)):
			common_tag = tag
			common_size = size_value
	var crosses_tier := false
	for tag in _ai_tags(name):
		if tag == common_tag: score += 4 if difficulty == "easy" else 18 if difficulty == "hard" else 12
		var member_count := int(tag_members.get(tag, {}).size())
		if tag_members.get(tag, {}).has(name): continue
		for synergy in content["synergies"]:
			if synergy["tag"] != tag: continue
			for tier in synergy["tiers"]:
				if member_count + 1 == int(tier): crosses_tier = true
	if crosses_tier: score += 10 if difficulty == "easy" else 40 if difficulty == "hard" else 30
	if difficulty == "hard":
		for other in players:
			if other["seat"] == player["seat"] or not other["alive"]: continue
			for visible in other["board"].values():
				if visible["id"] == name: score -= 3
	var has_front := false
	var has_back := false
	for piece in player["board"].values():
		if float(units[piece["id"]]["attack_range_grids"]) <= 1: has_front = true
		else: has_back = true
	if not has_front and float(units[name]["attack_range_grids"]) <= 1: score += 8
	if not has_back and float(units[name]["attack_range_grids"]) > 1: score += 8
	return score


func _ai_best_shop(player: Dictionary) -> Dictionary:
	var best := {"slot": -1, "score": -1, "cost": 99}
	for slot in range(player["shop"].size()):
		var name: String = player["shop"][slot]
		if name == "": continue
		var cost := int(units[name]["cost"])
		var after_buy := int(player["gold"]) - cost
		if after_buy < 0 or not _buy_fits_bench(player, name): continue
		var immediate_merge := _can_merge_with(name, player) or _ai_piece_count(player, name, 2) >= 2
		var needs_piece: bool = player["board"].size() + player["bench"].size() < int(player["level"])
		var mode := _ai_economy_mode(player)
		var minimum_gold := 0 if needs_piece or round_number <= 5 or mode == "止血" or immediate_merge else \
			20 if player["ai_style"] == "easy" else \
			5 if mode == "连胜推进" or player["ai_style"] == "hard" else 20 if mode == "连败积累" else 10
		if after_buy < minimum_gold: continue
		var score := _ai_score(player, name)
		if score < 10: continue
		if score > best["score"] or (score == best["score"] and (cost < best["cost"] or (cost == best["cost"] and slot < best["slot"]))):
			best = {"slot": slot, "score": score, "cost": cost}
	return best


func _ai_buy_available(seat: int) -> void:
	var player: Dictionary = players[seat]
	for _buy in range(5):
		var option: Dictionary = _ai_best_shop(player)
		if int(option["slot"]) < 0: break
		var name: String = player["shop"][int(option["slot"])]
		_log("AI %d 购买 %s 分数 %d 种子 %d" % [seat, name, option["score"], random_state])
		buy(seat, int(option["slot"]))


func _ai_place(seat: int) -> void:
	var player: Dictionary = players[seat]
	var difficulty: String = player["ai_style"]
	player["bench"].append_array(player["board"].values())
	player["bench_layout"] = []
	player["board"].clear()
	var guard_assassins := false
	if difficulty == "hard" and not player["last_opponents"].is_empty():
		var opponent: Dictionary = players[int(player["last_opponents"].back())]
		for visible in opponent["board"].values():
			if "刺客" in _ai_tags(visible["id"]): guard_assassins = true
	while player["bench"].size() > 0 and player["board"].size() < int(player["level"]):
		player["bench"].sort_custom(func(a, b):
			var score_a := _ai_deploy_score(player, a, difficulty)
			var score_b := _ai_deploy_score(player, b, difficulty)
			return score_a > score_b if score_a != score_b else str(a["id"]) < str(b["id"]))
		var piece: Dictionary = player["bench"][0]
		var rows: Array = [3, 2, 1, 0]
		var cols: Array = [3, 4, 2, 5, 1, 6, 0, 7]
		if float(units[piece["id"]]["attack_range_grids"]) > 1:
			rows = [0, 1, 2, 3]
			if guard_assassins: cols = [6, 5, 7, 4, 3, 2, 1, 0]
		if "刺客" in _ai_tags(piece["id"]):
			rows = [0, 1, 2, 3]
			cols = [0, 7, 1, 6, 2, 5, 3, 4]
		var placed := false
		for row in rows:
			for col in cols:
				if place(seat, 0, row * 8 + col):
					placed = true
					break
			if placed: break
		if not placed: break


func _ai_deploy_score(player: Dictionary, piece: Dictionary, difficulty: String) -> int:
	var score := int(piece["star"]) * 20 + int(units[piece["id"]]["cost"]) * 2
	if difficulty == "easy": return score
	for tag in _ai_tags(piece["id"]):
		var members: Dictionary = {}
		for deployed in player["board"].values():
			if tag in _ai_tags(deployed["id"]): members[deployed["id"]] = true
		if members.has(piece["id"]): continue
		if not members.is_empty(): score += 6 if difficulty == "medium" else 10
		for synergy in content["synergies"]:
			if synergy["tag"] == tag and members.size() + 1 in synergy["tiers"]:
				score += 12 if difficulty == "medium" else 22
	var race_members: Dictionary = {}
	for deployed in player["board"].values() + [piece]:
		for race in str(units[deployed["id"]]["species"]).split("、"):
			if not race_members.has(race): race_members[race] = {}
			race_members[race][deployed["id"]] = true
	if race_members.has("神"):
		for synergy in content["synergies"]:
			var race: String = synergy["tag"]
			if race == "神" or not race_members.has(race): continue
			if race_members[race].size() >= int(synergy["tiers"][0]):
				score -= 40 if difficulty == "medium" else 60
				break
	return score


func _ai_equip(player: Dictionary) -> void:
	if player["board"].is_empty(): return
	for index in range(player["inventory"].size() - 1, -1, -1):
		var item: Dictionary = player["inventory"][index]
		if item["id"] == "loot_treasure": continue
		var stats: Dictionary = content["items"][item["id"]]["stats"]
		var candidates: Array = player["board"].keys()
		candidates = candidates.filter(func(position): return player["board"][position]["items"].size() < 6)
		if candidates.is_empty(): return
		candidates.sort_custom(func(a, b):
			var piece_a: Dictionary = player["board"][a]
			var piece_b: Dictionary = player["board"][b]
			var score_a := int(units[piece_a["id"]]["attack_max"][int(piece_a["star"]) - 1])
			var score_b := int(units[piece_b["id"]]["attack_max"][int(piece_b["star"]) - 1])
			if stats.has("armor_flat") or stats.has("health_flat"):
				score_a = int(units[piece_a["id"]]["hp"][int(piece_a["star"]) - 1])
				score_b = int(units[piece_b["id"]]["hp"][int(piece_b["star"]) - 1])
			return score_a > score_b if score_a != score_b else str(piece_a["id"]) < str(piece_b["id"]))
		player["board"][candidates[0]]["items"].append(player["inventory"].pop_at(index))


func _wave() -> Dictionary:
	for candidate in content["waves"]:
		if int(candidate["round"]) == round_number:
			return candidate
	var later: Dictionary = content["post_50"]
	if round_number >= int(later["first_round"]) and (round_number - int(later["first_round"])) % int(later["interval_rounds"]) == 0:
		return {"spawns": [{"monster_id": later["monster_id"], "col": later["spawn_col"], "row": later["spawn_row"]}],
			"scale": 1 + (round_number - int(later["first_round"])) / int(later["interval_rounds"])}
	return {}


func _army(player: Dictionary) -> Array:
	var result: Array = []
	var positions: Array = player["board"].keys()
	positions.sort()
	for position in positions:
		var piece: Dictionary = player["board"][position].duplicate(true)
		piece["position"] = int(position)
		result.append(piece)
	return result


func _survivor_damage(actors: Array, team: int, monster_round: bool) -> int:
	var loss := 0 if monster_round else 1
	for actor in actors:
		if actor["team"] == team and actor["hp"] > 0 and not actor["summon"]:
			loss += int(monster_courier_damage[actor["id"]]) if monster_round else int(actor["star"])
	return mini(loss, 15) if monster_round else loss


func _apply_result(seat: int, winner: bool, damage_amount: int, battle_result: Dictionary,
		monster_round: bool = false, tie: bool = false, home_battle: bool = false) -> void:
	var player: Dictionary = players[seat]
	var priest_ids: Dictionary = {}
	for piece in player["board"].values():
		if "牧师" in str(units[piece["id"]]["class"]): priest_ids[piece["id"]] = true
	var raw_damage := damage_amount
	if not winner and priest_ids.size() >= 1: damage_amount = maxi(1, int(floor(damage_amount * 0.8)))
	if tie:
		player["streak"] = 0
	elif winner:
		if not monster_round:
			player["streak"] = max(1, int(player["streak"]) + 1)
			player["pending_win_gold"] = 1
	else:
		if not monster_round:
			if home_battle: _transfer_rapiers(seat)
			player["streak"] = min(-1, int(player["streak"]) - 1)
		player["hp"] = max(0, int(player["hp"]) - damage_amount)
		if home_battle and not monster_round and priest_ids.size() >= 2 and raw_damage > 8 and player["hp"] > 0:
			_award_common_item(seat)
		if player["hp"] == 0:
			player["alive"] = false
			player["eliminated_round"] = round_number
			_return_shop(player)
			for piece in player["bench"]:
				_return_piece_pool(piece)
			for piece in player["board"].values():
				_return_piece_pool(piece)
	var streak_length: int = abs(int(player["streak"]))
	if not monster_round:
		player["pending_streak_gold"] = 3 if streak_length >= 9 else 2 if streak_length >= 6 else 1 if streak_length >= 3 else 0
	last_results[seat] = {"win": winner, "tie": tie, "damage": 0 if winner or tie else damage_amount,
		"hp": player["hp"], "seconds": battle_result["seconds"]}


func _transfer_rapiers(seat: int) -> void:
	var opponents: Array = []
	for other in range(8):
		if other != seat and players[other]["alive"]: opponents.append(other)
	for piece in players[seat]["board"].values():
		for index in range(piece["items"].size() - 1, -1, -1):
			if piece["items"][index]["id"] != "divine_rapier": continue
			var item = piece["items"].pop_at(index)
			var receiver: int = opponents[_random(opponents.size())] if not opponents.is_empty() else seat
			players[receiver]["inventory"].append(item)


func _drop_row() -> Dictionary:
	for candidate in content["drop_table"]:
		if str(candidate["round_text"]) == str(round_number) or (round_number <= 3 and str(candidate["round_text"]) == "1/2/3"):
			return candidate
	return content["drop_table"].back() if round_number >= 55 else content["drop_table"][0]


func _drop_rarity(weights: Array) -> String:
	var roll := _random(100)
	if roll < int(weights[0]): return "common"
	if roll < int(weights[0]) + int(weights[1]): return "advanced"
	return "rare"


func _drop_for_monster(seat: int, killed: int) -> void:
	var row := _drop_row()
	for _kill in range(killed):
		if _random(100) >= int(row["chance_percent"]):
			players[seat]["undropped_monster_kills"] += 1
			_compensate_drop(seat)
			continue
		var rarity := _drop_rarity(row["rarity_weights"])
		var pool_items: Array = content["drop_pools"][rarity]
		var item_id: String = pool_items[_random(pool_items.size())]
		for _retry in range(pool_items.size()):
			if _owned_item_count(item_id) < 99: break
			item_id = pool_items[_random(pool_items.size())]
		if _owned_item_count(item_id) >= 99: continue
		players[seat]["inventory"].append({"id": item_id, "level": 1})
		players[seat]["undropped_monster_kills"] = 0
		_log("席位 %d 获得 %s" % [seat + 1, content["items"][item_id]["name"]])


func _owned_item_count(item_id: String) -> int:
	var count := 0
	for player in players:
		for item in player["inventory"]:
			if item["id"] == item_id: count += 1
		for piece in player["bench"]:
			for item in piece["items"]:
				if item["id"] == item_id: count += 1
		for piece in player["board"].values():
			for item in piece["items"]:
				if item["id"] == item_id: count += 1
	return count


func _compensate_drop(seat: int) -> void:
	if int(players[seat]["undropped_monster_kills"]) < 5: return
	_award_common_item(seat)
	players[seat]["undropped_monster_kills"] = 0


func _award_common_item(seat: int) -> void:
	var available: Array = content["drop_pools"]["common"].filter(func(id): return _owned_item_count(id) < 99)
	if not available.is_empty(): players[seat]["inventory"].append({"id":available[_random(available.size())], "level":1})


func _assign_chest(seat: int) -> void:
	var choice: Array = []
	var row := _drop_row()
	for _draw in range(3):
		var rarity := _drop_rarity(row["rarity_weights"])
		var names: Array = content["drop_pools"][rarity]
		choice.append(names[_random(names.size())])
	if seat == 0:
		chest_choices = choice
	else:
		players[seat]["inventory"].append({"id": choice[_random(3)], "level": 1})


func pick_chest(index: int) -> bool:
	if phase != "settlement" or index < 0 or index >= chest_choices.size():
		return false
	players[0]["inventory"].append({"id": chest_choices[index], "level": 1})
	chest_choices.clear()
	return true


func _battle_stats(actors: Array, player_team: int) -> Array:
	var rows: Array = []
	var by_uid: Dictionary = {}
	for actor in actors:
		if int(actor["team"]) != player_team or actor["monster"] or actor["summon"]: continue
		var row := {"id": actor["id"], "name": actor["name"], "star": actor["star"],
			"origin": actor["origin"], "damage": actor["damage_dealt"],
			"taken": actor["damage_taken"], "healing": actor["healing_done"]}
		rows.append(row)
		by_uid[actor["uid"]] = row
	for actor in actors:
		if int(actor["team"]) != player_team or not actor["summon"]: continue
		if by_uid.has(actor.get("owner_uid", -1)):
			by_uid[actor["owner_uid"]]["damage"] += actor["damage_dealt"]
			by_uid[actor["owner_uid"]]["healing"] += actor["healing_done"]
	return rows


func _trim_over_limit(seat: int) -> void:
	var player: Dictionary = players[seat]
	while player["board"].size() > int(player["level"]):
		var counts: Dictionary = {}
		for piece in player["board"].values(): counts[piece["id"]] = int(counts.get(piece["id"], 0)) + 1
		var candidates: Array = []
		var best_duplicate := -1
		var best_star := 99
		var best_cost := 99
		for position in player["board"]:
			var piece: Dictionary = player["board"][position]
			var duplicate := 1 if int(counts[piece["id"]]) > 1 else 0
			var star := int(piece["star"])
			var cost := int(units[piece["id"]]["cost"])
			if duplicate > best_duplicate or (duplicate == best_duplicate and (star < best_star or (star == best_star and cost < best_cost))):
				best_duplicate = duplicate
				best_star = star
				best_cost = cost
				candidates = [position]
			elif duplicate == best_duplicate and star == best_star and cost == best_cost:
				candidates.append(position)
		var chosen: int = candidates[_random(candidates.size())]
		var name: String = player["board"][chosen]["id"]
		if player["bench"].size() < 8:
			_bench_put(player, player["board"][chosen])
			player["board"].erase(chosen)
			_log("席位 %d 超员：%s 退回备战席" % [seat + 1, name])
		else:
			sell(seat, true, chosen)
			_log("席位 %d 超员且备战席已满：%s 自动出售" % [seat + 1, name])


func resolve_round(defer_settlement: bool = false) -> bool:
	if phase != "preparation":
		return false
	_finish_ai_preparation()
	for seat in range(players.size()):
		if players[seat]["alive"]: _trim_over_limit(seat)
	phase = "battle"
	last_results.clear()
	battle_replay.clear()
	seat_replays.clear()
	battle_pending_phase = ""
	var player_start_snapshot: Dictionary = players[0].duplicate(true) if defer_settlement else {}
	var start_log_size := event_log.size()
	var simulator = Combat.new(content)
	var wave: Dictionary = _wave()
	if not wave.is_empty():
		for seat in range(8):
			if not players[seat]["alive"]:
				continue
			var away: Array = []
			for spawn in wave["spawns"]: away.append(spawn)
			var limit_s := float(default_battle_seconds())
			var result: Dictionary = simulator.simulate(_army(players[seat]), away, random_state + seat,
				limit_s, int(wave.get("scale", 0)), false, defer_settlement)
			if defer_settlement:
				seat_replays[seat] = {"frames": result.get("frames", []), "visual_events": result.get("visual_events", []), "seconds": result["seconds"],
					"regular_seconds": limit_s, "player_team": 0, "opponent": "第 %d 回合野怪" % round_number,
					"starting_hp": int(players[seat]["hp"]), "stats": _battle_stats(result["actors"], 0)}
			if seat == 0: battle_replay = seat_replays.get(0, {"frames": [], "seconds": result["seconds"]})
			var won: bool = int(result["winner"]) == 0
			_apply_result(seat, won, _survivor_damage(result["actors"], 1, true), result, true)
			var killed := 0
			for actor in result["actors"]:
				if actor["team"] == 1 and actor["hp"] <= 0: killed += 1
			_drop_for_monster(seat, killed)
			if won and round_number % 10 == 0 and round_number >= 10: _assign_chest(seat)
	else:
		var alive_seats: Array = []
		for seat in range(8):
			if players[seat]["alive"]: alive_seats.append(seat)
		for index in range(alive_seats.size() - 1, 0, -1):
			var other := _random(index + 1)
			var temp = alive_seats[index]
			alive_seats[index] = alive_seats[other]
			alive_seats[other] = temp
		for index in range(0, alive_seats.size() - 1, 2):
			var home_seat: int = alive_seats[index]
			var away_seat: int = alive_seats[index + 1]
			var pair_key := "%d-%d" % [mini(home_seat, away_seat), maxi(home_seat, away_seat)]
			var overtime := alive_seats.size() == 2 and int(match_history.get(pair_key, 0)) >= 3
			var limit_s := float(default_battle_seconds())
			var result: Dictionary = simulator.simulate(_army(players[home_seat]), _army(players[away_seat]), random_state + index,
				limit_s, 0, overtime, defer_settlement)
			if defer_settlement:
				seat_replays[home_seat] = {"frames": result.get("frames", []), "visual_events": result.get("visual_events", []), "seconds": result["seconds"], "regular_seconds": limit_s,
					"player_team": 0, "opponent": "席位 %d" % (away_seat + 1),
					"starting_hp": int(players[home_seat]["hp"]), "stats": _battle_stats(result["actors"], 0)}
				seat_replays[away_seat] = {"frames": result.get("frames", []), "visual_events": result.get("visual_events", []), "seconds": result["seconds"], "regular_seconds": limit_s,
					"player_team": 1, "opponent": "席位 %d" % (home_seat + 1),
					"starting_hp": int(players[away_seat]["hp"]), "stats": _battle_stats(result["actors"], 1)}
			if home_seat == 0 or away_seat == 0: battle_replay = seat_replays.get(0, {})
			var tied: bool = int(result["winner"]) == -1
			match_history[pair_key] = int(match_history.get(pair_key, 0)) + 1 if tied else 0
			_apply_result(home_seat, result["winner"] == 0, _survivor_damage(result["actors"], 1, false), result, false, tied, true)
			_apply_result(away_seat, result["winner"] == 1, _survivor_damage(result["actors"], 0, false), result, false, tied, false)
			players[home_seat]["last_opponents"].append(away_seat)
			players[away_seat]["last_opponents"].append(home_seat)
		if alive_seats.size() % 2 == 1 and alive_seats.size() > 1:
			var ghost_seat: int = alive_seats.back()
			var ghost_opponent: int = alive_seats[0]
			var limit_s := float(default_battle_seconds())
			var ghost_result: Dictionary = simulator.simulate(_army(players[ghost_seat]), _army(players[ghost_opponent]), random_state + 99,
				limit_s, 0, false, defer_settlement)
			if defer_settlement:
				seat_replays[ghost_seat] = {"frames": ghost_result.get("frames", []), "visual_events": ghost_result.get("visual_events", []), "seconds": ghost_result["seconds"], "regular_seconds": limit_s,
					"player_team": 0, "opponent": "镜像席位 %d" % (ghost_opponent + 1),
					"starting_hp": int(players[ghost_seat]["hp"]), "stats": _battle_stats(ghost_result["actors"], 0)}
			if ghost_seat == 0: battle_replay = seat_replays.get(0, {})
			_apply_result(ghost_seat, ghost_result["winner"] == 0,
				_survivor_damage(ghost_result["actors"], 1, false), ghost_result, false, ghost_result["winner"] == -1, true)
	for player in players:
		if player["alive"]:
			player["pending_interest"] = mini(5, int(player["gold"]) / 10)
	_log("第 %d 回合结算" % round_number)
	var alive_count := 0
	for player in players:
		if player["alive"]: alive_count += 1
	var final_phase := "finished" if not players[0]["alive"] or alive_count <= 1 else "settlement"
	if defer_settlement:
		battle_replay["pending_inventory"] = players[0]["inventory"].slice(player_start_snapshot["inventory"].size())
		players[0]["inventory"] = player_start_snapshot["inventory"].duplicate(true)
		battle_pending_phase = final_phase
		battle_replay["starting_player"] = player_start_snapshot
		battle_replay["starting_log_size"] = start_log_size
	else:
		phase = final_phase
	return true


func complete_battle() -> bool:
	if phase != "battle" or battle_pending_phase == "": return false
	players[0]["inventory"].append_array(battle_replay.get("pending_inventory", []))
	battle_replay.erase("pending_inventory")
	phase = battle_pending_phase
	battle_pending_phase = ""
	return true


func rankings() -> Array:
	var order: Array = players.duplicate()
	order.sort_custom(func(a, b):
		if a["alive"] != b["alive"]: return a["alive"]
		if int(a["eliminated_round"]) != int(b["eliminated_round"]):
			return int(a["eliminated_round"]) > int(b["eliminated_round"])
		return int(a["seat"]) < int(b["seat"]))
	var ranking: Array = []
	for index in range(order.size()):
		var current: Dictionary = order[index]
		var rank := index + 1
		if index > 0 and current["alive"] == order[index - 1]["alive"] and current["eliminated_round"] == order[index - 1]["eliminated_round"]:
			rank = ranking[index - 1]["rank"]
		ranking.append({"rank": rank, "seat": current["seat"], "alive": current["alive"],
			"eliminated_round": current["eliminated_round"], "hp": current["hp"]})
	return ranking


func advance_round(defer_ai: bool = false) -> bool:
	if phase != "settlement" or not chest_choices.is_empty() or not players[0]["alive"]:
		return false
	var alive_count := 0
	for player in players:
		if player["alive"]: alive_count += 1
	if alive_count <= 1:
		phase = "finished"
		return false
	for player in players:
		if player["alive"]: _gain_xp(player, 1)
	round_number += 1
	start_round(defer_ai)
	return true
