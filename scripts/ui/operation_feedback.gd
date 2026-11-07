extends Control

const GREEN := Color(0.30, 0.85, 0.63)
const GOLD := Color(1.0, 0.76, 0.30)
const RED := Color(1.0, 0.40, 0.35)
var controller: Control
var dragging: Dictionary = {}
var last_target: Control
var last_hint: Dictionary = {}
var fade: Tween


func piece_at(kind: String, index: int) -> Dictionary:
	var player: Dictionary = controller.game.players[0]
	if kind == "battle_actor": return player["board"].get(controller._battle_actor_origin(index), {})
	if kind in ["board", "equipped_board"]: return player["board"].get(index, {})
	if kind in ["bench", "equipped_bench"]:
		var actual: int = controller.game.bench_index_at_slot(0, index)
		return player["bench"][actual] if actual >= 0 else {}
	return {}


func describe(data: Dictionary, kind: String, index: int, extra: int = -1) -> Dictionary:
	var allowed: bool = controller.can_drop(data, kind, index, extra)
	var source := str(data.get("kind", ""))
	var piece := piece_at(kind, index)
	var text := "不可放置"
	var color := GREEN if allowed else RED
	if not allowed:
		if controller.game_paused: text = "游戏已暂停"
		elif controller.viewed_seat != 0: text = "观战时不能操作"
		elif controller.game.phase == "battle" and source in ["board", "bench"]: text = "战斗中仅可整理备战席或出售"
		elif kind == "board" and (index < 0 or index >= 32): text = "只能放在己方半场"
		elif source in ["inventory", "equipped_board", "equipped_bench"]:
			text = "请拖到棋子上" if piece.is_empty() else "装备位已满或无法合成"
		elif kind == "bench": text = "备战席已满"
	elif kind == "sell":
		var selling := piece_at(source, int(data["index"]))
		if not selling.is_empty():
			text = "出售 %s · +%d 金币" % [controller.game.units[selling["id"]]["name_zh"], controller.game.units[selling["id"]]["sell_gold"][int(selling["star"]) - 1]]
			color = GOLD
	elif source in ["inventory", "equipped_board", "equipped_bench", "disassembly_tool"]:
		text = "卸下装备" if kind == "inventory" else "拆解／卸下装备" if source == "disassembly_tool" else "装备 → %s" % controller.game.units[piece["id"]]["name_zh"]
		if source == "inventory" and kind == "inventory": text = "整理装备" if index < 0 else controller.craft_preview_label.text
		elif source != "disassembly_tool" and kind != "inventory":
			var item: Dictionary = controller.game.players[0]["inventory"][int(data["index"])] if source == "inventory" else piece_at(source, int(data["index"]))["items"][int(data["extra"])]
			text = "%s → %s" % [controller.game.content["items"][item["id"]]["name"], controller.game.units[piece["id"]]["name_zh"]]
		if controller.game.phase == "battle" and kind != "inventory": text += "（下回合生效）"
	else:
		text = "放置" if piece.is_empty() else "交换 → %s" % controller.game.units[piece["id"]]["name_zh"]
		if not piece.is_empty():
			color = GOLD
			var moving := piece_at(source,int(data.get("index",-1)))
			if moving.get("id","") == "Io" and piece.id != "Io": text = "复制 → %s · 保留%s"%[controller.game.units[piece.id].name_zh,"★".repeat(int(moving.star))]
		if kind == "board" and source == "bench" and piece.is_empty() and controller.game.players[0]["board"].size() >= int(controller.game.players[0]["level"]):
			text = "上阵超限 · 开战前需调整"
			color = GOLD
	return {"allowed": allowed, "text": text, "color": color}


func message(text: String, at: Vector2, color: Color = GREEN) -> void:
	if fade != null: fade.kill()
	$Message.modulate = Color.WHITE
	$Message/Text.text = text
	$Message/Text.add_theme_color_override("font_color", color)
	$Message.visible = true
	_place_message(text, at)
	fade = create_tween()
	fade.tween_interval(2.0)
	fade.tween_property($Message, "modulate:a", 0.0, 0.3)
	fade.tween_callback(func(): $Message.hide())


func _place_message(text: String, at: Vector2) -> void:
	var width := clampf(text.length() * 16.0 + 24, 112, 300)
	$Message/Text.custom_minimum_size.x = width - 24
	$Message.custom_minimum_size.x = width
	$Message.size = Vector2(width, 44)
	$Message.position = Vector2(clampf(at.x + 18, 8, size.x - width - 8), clampf(at.y + 22, 8, size.y - 80))


func begin_drag(data: Dictionary) -> void:
	dragging = data
	last_target = null
	last_hint = {}
	if fade != null: fade.kill()
	$Message.hide()
	for cell in controller.board_buttons + controller.bench_buttons:
		cell.set_drop_hint(Color.TRANSPARENT)
	var source := piece_at(str(data["kind"]), int(data["index"]))
	controller.screen.get_node("Economy").tooltip_text = "拖到此处出售"
	if not source.is_empty():
		var price: int = controller.game.units[source["id"]]["sell_gold"][int(source["star"]) - 1]
		controller.sell_zone.text = "出售 +%d 金币" % price


func target(data: Dictionary, kind: String, index: int, extra: int, cell: Control) -> bool:
	var hint := describe(data, kind, index, extra)
	last_hint = hint
	last_target = cell
	$Message/Text.text = hint.text
	$Message/Text.add_theme_color_override("font_color", hint.color)
	$Message.modulate = Color.WHITE
	$Message.visible = true
	var at := cell.get_global_rect().get_center()
	_place_message(str(hint.text), at)
	return bool(hint.allowed)


func end_drag(successful: bool) -> void:
	if dragging.is_empty(): return
	for cell in controller.board_buttons + controller.bench_buttons: cell.set_drop_hint(Color.TRANSPARENT)
	controller.sell_zone.text = "拖到此处出售"
	if not successful and not last_hint.is_empty() and not bool(last_hint.allowed) and is_instance_valid(last_target) and last_target.get_global_rect().has_point(get_global_mouse_position()):
		message(str(last_hint.text), get_global_mouse_position(), RED)
	elif not successful: $Message.hide()
	dragging = {}
	last_target = null
	last_hint = {}


func snapshot() -> Dictionary:
	var result := {}
	var player: Dictionary = controller.game.players[0]
	for index in player["board"]: result["board:%d" % index] = player["board"][index].duplicate(true)
	for slot in range(8):
		var piece := piece_at("bench", slot)
		if not piece.is_empty(): result["bench:%d" % slot] = piece.duplicate(true)
	return result


func pulse_changes(before: Dictionary) -> String:
	var upgraded := ""
	var after := snapshot()
	for key in after:
		var kind: String = key.get_slice(":", 0)
		var index := int(key.get_slice(":", 1))
		var piece := piece_at(kind, index)
		var old: Dictionary = before.get(key, {})
		if old.get("id", "") == piece["id"] and old.get("star", 0) == piece["star"]: continue
		var visual: Node3D = controller.battle_scene.bench_pieces.get(index) if kind == "bench" else controller.battle_scene.pieces.get(-controller._game_to_visual(index) - 1)
		if is_instance_valid(visual):
			var scale: Vector3 = visual.get_meta("rest_scale", visual.scale)
			var previous_tween: Tween = visual.get_meta("feedback_tween") if visual.has_meta("feedback_tween") else null
			if previous_tween != null: previous_tween.kill()
			var tween := visual.create_tween()
			visual.set_meta("feedback_tween", tween)
			tween.tween_property(visual, "scale", scale * 1.12, 0.12)
			tween.tween_property(visual, "scale", scale, 0.2)
			controller.battle_scene.highlight_piece(visual,true)
			tween.tween_property(visual.get_meta("hit_flash"), "albedo_color", Color(GOLD,0), 0.3)
			tween.tween_callback(func():
				controller.battle_scene.set_selection(controller._game_to_visual(controller.selected_board) if controller.selected_board>=0 else -1,controller.selected_bench))
		var previous_count := 0
		var current_count := 0
		for previous in before.values():
			if previous["id"] == piece["id"] and previous["star"] == piece["star"]: previous_count += 1
		for current in after.values():
			if current["id"] == piece["id"] and current["star"] == piece["star"]: current_count += 1
		if int(piece["star"]) > 1 and current_count > previous_count:
			upgraded = "%s 升至 %s" % [controller.game.units[piece["id"]]["name_zh"], "★".repeat(int(piece["star"]))]
			if int(piece["star"]) == 3 and is_instance_valid(visual):
				var consumed_twos := 0
				for previous in before.values():
					if previous["id"] == piece["id"] and int(previous["star"]) == 2: consumed_twos += 1
				for current in after.values():
					if current["id"] == piece["id"] and int(current["star"]) == 2: consumed_twos -= 1
				if consumed_twos >= 2: visual.play_promotion()
	return upgraded
