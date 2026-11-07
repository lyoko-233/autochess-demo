extends Control

const State = preload("res://scripts/game_state.gd")
const DragCell = preload("res://scripts/drag_cell.gd")
const Assets = preload("res://scripts/ui/ui_assets.gd")
const GameAudio = preload("res://scripts/game_audio.gd")
var audio = GameAudio.new()

var game = State.new()
var viewed_seat := 0
var selected_bench := -1
var selected_board := -1
var selected_item := -1
var preparation_seconds_left := 0.0
var preparation_seconds_total := 0.0
var game_paused := false
var battle_elapsed := 0.0
var settlement_seconds_left := 0.0
var battle_frame_index := 0
var status_label: Label
var round_label: Label
var timer_label: Label
var result_label: Label
var opponent_label: Label
var seat_buttons: Array = []
var return_view_button: Button
var extend_preparation_button: Button
var start_battle_button: Button
var pause_button: Button
var economy_label: Label
var shop_lock_label: Label
var lock_button: Button
var last_battle_stats: Array = []
var last_battle_round := 0
var battle_courier_hp: Array = []
var final_panel: CenterContainer
var final_label: Label
var difficulty_panel: CenterContainer
var trait_list: VBoxContainer
var battle_layer: Control
var battle_viewport: SubViewportContainer
var battle_scene: Node3D
var over_limit_label: Label
var battle_actor_cards: Dictionary = {}
var battle_roster: RichTextLabel
var stats_panel: PanelContainer
var stats_label: RichTextLabel
var stats_detail: RichTextLabel
var craft_preview_label: Label
var equipment_hint_label: Label
var board_buttons: Array = []
var board_hp_bars: Array = []
var board_mana_bars: Array = []
var board_item_rows: Array = []
var board_item_signatures: Array = []
var shop_buttons: Array = []
var reroll_button: Button
var xp_button: Button
var bench_buttons: Array = []
var bench_item_rows: Array = []
var bench_item_signatures: Array = []
var item_list: GridContainer
var disassembly_tool: Button
var craft_select: OptionButton
var chest_row: HBoxContainer
var log_box: RichTextLabel
var preview_scene: Node3D
var piece_preview_box: SubViewportContainer
var gold_label: Label
var preview_key := ""
var screen: Control
var board_screen: Control
var phase_label: Label
var capacity_label: Label
var countdown_dial: Control
var xp_progress: ProgressBar
var xp_caption: Label
var chest_panel: Control
var round_feedback: Control
var sell_zone: Button
var activated_traits: Dictionary = {}
var trait_view_seat := -1
var level_feedback: Control
var displayed_level := -1
var displayed_level_seat := -1
var operation_feedback: Control
var main_menu: Control
var battle_wait_notice: Control
var completed_battle_cues := {}


func _ready() -> void:
	add_child(audio)
	_build_ui()
	# V2: enter an empty title screen; resume only after an explicit choice.
	screen.hide()
	main_menu = preload("res://scripts/ui/main_menu.gd").new()
	main_menu.controller = self
	add_child(main_menu)
	audio.set_phase("menu")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_instance_valid(operation_feedback):
		operation_feedback.end_drag(get_viewport().gui_is_drag_successful())


func _process(delta: float) -> void:
	if is_instance_valid(main_menu) and main_menu.visible: return
	audio.set_paused(game_paused or difficulty_panel.visible)
	if game_paused or difficulty_panel.visible: return
	match game.phase:
		"preparation":
			if game.tick_ai_preparation(delta): _refresh()
			preparation_seconds_left = maxf(0.0, preparation_seconds_left - delta)
			audio.countdown(preparation_seconds_left, game.round_number, true)
			if preparation_seconds_left <= 0.0: _battle()
			else: _update_timer_label()
		"battle":
			battle_elapsed += delta
			_show_battle_frame()
			_update_local_battle_feedback()
			if battle_elapsed >= game.battle_total_seconds():
				_finish_battle()
			else:
				_update_timer_label()
		"settlement":
			settlement_seconds_left = maxf(0.0, settlement_seconds_left - delta)
			if settlement_seconds_left <= 0.0: _next_round()
			else: _update_timer_label()


func _reset_preparation_timer() -> void:
	completed_battle_cues.clear()
	if is_instance_valid(battle_wait_notice): battle_wait_notice.set_waiting(false)
	audio.stop_combat()
	audio.countdown(0, game.round_number, false)
	preparation_seconds_total = float(game.content["economy"]["early_preparation_seconds"] if game.round_number <= 3 else game.content["economy"]["preparation_seconds"])
	preparation_seconds_left = preparation_seconds_total
	battle_elapsed = 0.0
	settlement_seconds_left = 0.0
	battle_frame_index = 0


func _update_timer_label() -> void:
	var remaining := 0.0
	var total := 1.0
	var caption := ""
	match game.phase:
		"preparation":
			remaining = preparation_seconds_left
			total = preparation_seconds_total
			caption = "备战"
		"battle":
			var replay: Dictionary = game.seat_replay(viewed_seat)
			var regular_limit := float(replay.get("regular_seconds", game.default_battle_seconds()))
			total = regular_limit
			remaining = maxf(0.0, regular_limit - battle_elapsed)
			caption = "野怪战" if not game._wave().is_empty() else "战斗"
			if replay.is_empty(): caption = "本轮轮空"
			elif battle_elapsed >= float(replay["seconds"]):
				caption = "本场结束"
				remaining = 0.0
			elif battle_elapsed >= regular_limit and float(replay.get("seconds", 0.0)) > regular_limit:
				remaining = maxf(0.0, float(replay["seconds"]) - battle_elapsed)
				total = maxf(1.0, float(replay["seconds"]) - regular_limit)
				caption = "加时"
		"settlement":
			remaining = settlement_seconds_left
			total = float(game.content["economy"]["settlement_seconds"])
			caption = "选择战利品" if not game.chest_choices.is_empty() else "结算"
		_: caption = "终局"
	timer_label.text = "%02d" % ceili(remaining)
	phase_label.text = "已暂停" if game_paused else caption
	phase_label.add_theme_color_override("font_color", Color(0.97, 0.55, 0.36) if caption in ["战斗", "野怪战", "加时"] else Color(0.49, 0.84, 0.68))
	countdown_dial.set_countdown(remaining, total)
	timer_label.tooltip_text = "%s · 剩余 %.1f 秒" % [caption, remaining]


func _button(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _drag_button(parent: Node, label: String, kind: String, index: int, extra: int = -1) -> Button:
	var button = DragCell.new()
	button.text = label
	button.controller = self
	button.kind = kind
	button.index = index
	button.extra = extra
	parent.add_child(button)
	return button


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label


func _cost_color(cost: int) -> Color:
	return Assets.cost_color(cost)


func _set_cost_font(button: Button, color: Color) -> void:
	if button.has_method("set_cost_color"):
		button.call("set_cost_color", color)
		return
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		button.add_theme_color_override(key, color)


func _set_shop_frame(button: Button, state: String) -> void:
	button.call("set_frame", state)


func _bar(parent: Control, y: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = Vector2(15, y)
	bar.size = Vector2(44, 5)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _build_ui() -> void:
	theme = preload("res://assets/ui/game_theme.tres")
	screen = preload("res://scenes/ui/game_screen.tscn").instantiate()
	add_child(screen)
	status_label = screen.get_node("Status")
	round_label = screen.get_node("TopBar/Round")
	phase_label = screen.get_node("TopBar/Phase")
	timer_label = screen.get_node("TopBar/Dial/Timer")
	countdown_dial = screen.get_node("TopBar/Dial")
	capacity_label = screen.get_node("TopBar/Capacity")
	result_label = screen.get_node("Result")
	opponent_label = screen.get_node("Opponent")
	board_screen = screen.get_node("Board")
	board_screen.configure(self)
	board_buttons = board_screen.cells
	board_hp_bars = board_screen.hp_bars
	board_mana_bars = board_screen.mana_bars
	board_item_rows = board_screen.item_rows
	for index in range(64): board_item_signatures.append("")
	battle_viewport = board_screen.get_node("View")
	battle_scene = board_screen.get_node("View/World/BattleScene")
	battle_layer = board_screen.get_node("Actors")
	over_limit_label = board_screen.get_node("OverLimit")
	trait_list = screen.get_node("Traits/Content/Scroll/Traits")
	var shop: Control = screen.get_node("Shop")
	shop_lock_label = shop.get_node("Heading/LockState")
	lock_button = shop.get_node("Heading/Lock")
	lock_button.icon = Assets.icon("lock")
	lock_button.pressed.connect(_toggle_lock)
	var cards: Control = shop.get_node("Cards")
	var toggle: Button = shop.get_node("Heading/Toggle")
	toggle.icon = Assets.icon("chevron")
	toggle.pressed.connect(func():
		cards.visible = not cards.visible
		toggle.text = "收起商店" if cards.visible else "展开商店"
		shop.offset_top = -186.0 if cards.visible else -38.0
		board_screen.offset_bottom = -188.0 if cards.visible else -40.0
		screen.get_node("DockShade").offset_top = -190.0 if cards.visible else -42.0)
	shop.offset_top = -186.0
	board_screen.offset_bottom = -188.0
	screen.get_node("DockShade").offset_top = -190.0
	for index in range(5):
		var card = preload("res://scenes/ui/shop_card.tscn").instantiate()
		card.controller = self
		card.kind = "shop"
		card.index = index
		cards.add_child(card)
		card.pressed.connect(_buy.bind(index))
		shop_buttons.append(card)
	for index in range(8):
		var cell = preload("res://scenes/ui/bench_slot.tscn").instantiate()
		cell.controller = self
		cell.kind = "bench"
		cell.index = index
		board_screen.get_node("BenchInteraction").add_child(cell)
		cell.pressed.connect(_bench_pressed.bind(index))
		bench_buttons.append(cell)
		bench_item_rows.append(cell.get_node("Items"))
		bench_item_signatures.append("")
	var economy: Control = screen.get_node("Economy/Content")
	economy_label = economy.get_node("Summary")
	xp_progress = economy.get_node("Experience")
	xp_caption = economy.get_node("XPLabel")
	xp_button = economy.get_node("BuyXP")
	xp_button.icon = Assets.icon("xp")
	xp_button.pressed.connect(_buy_xp)
	level_feedback = preload("res://scripts/ui/level_up_feedback.gd").new()
	level_feedback.target = screen.get_node("Shop")
	screen.add_child(level_feedback)
	reroll_button = economy.get_node("Refresh")
	reroll_button.icon = Assets.icon("refresh")
	reroll_button.pressed.connect(_reroll)
	var inventory: Control = screen.get_node("Inventory")
	inventory.controller = self
	gold_label = inventory.get_node("Content/Gold")
	item_list = inventory.get_node("Content/ItemsScroll/Items")
	equipment_hint_label = inventory.get_node("Content/Hint")
	var tools: PopupPanel = screen.get_node("EquipmentTools")
	inventory.get_node("Content/Heading/Tools").pressed.connect(func(): tools.popup_centered())
	disassembly_tool = _drag_button(inventory.get_node("Content/Heading"), "", "disassembly_tool", -1)
	disassembly_tool.icon = Assets.icon("hammer")
	disassembly_tool.theme_type_variation = &"CompactButton"
	disassembly_tool.custom_minimum_size = Vector2(30, 26)
	disassembly_tool.tooltip_text = "装备拆卸工具：拖到棋子卸下全部装备；拖到装备拆解"
	craft_preview_label = tools.get_node("Content/Preview")
	craft_select = tools.get_node("Content/Recipes/Select")
	tools.get_node("Content/Actions/Use").pressed.connect(_use_selected_item)
	tools.get_node("Content/Actions/Dismantle").pressed.connect(_dismantle_selected_item)
	tools.get_node("Content/Recipes/Craft").pressed.connect(_craft_selected)
	chest_panel = screen.get_node("ChestPanel")
	chest_row = screen.get_node("ChestPanel/Panel/Content/Choices")
	var players: Control = screen.get_node("Players/Content")
	for seat in range(8):
		var button = preload("res://scenes/ui/player_row.tscn").instantiate()
		players.get_node("Players").add_child(button)
		button.pressed.connect(_view_seat.bind(seat))
		seat_buttons.append(button)
	return_view_button = players.get_node("Return")
	return_view_button.pressed.connect(_view_seat.bind(0))
	stats_panel = players.get_node("Stats")
	stats_label = players.get_node("Stats/Content/Text")
	var stats_toggle: Button = players.get_node("StatsToggle")
	stats_toggle.pressed.connect(func():
		stats_panel.visible = not stats_panel.visible
		stats_toggle.text = "收起上一战统计 ▴" if stats_panel.visible else "展开上一战统计 ▾")
	var records: PopupPanel = screen.get_node("Records")
	players.get_node("Records").pressed.connect(func(): records.popup_centered())
	battle_roster = records.get_node("Content/Tabs/Roster")
	stats_detail = records.get_node("Content/Tabs/Statistics")
	log_box = records.get_node("Content/Tabs/Log")
	for index in range(3): records.get_node("Content/Tabs").set_tab_title(index, ["阵容状态", "战后统计", "事件日志"][index])
	var menu: PopupPanel = screen.get_node("UtilityMenu")
	screen.get_node("Toolbar/Menu").icon = Assets.icon("menu")
	screen.get_node("Toolbar/Menu").pressed.connect(func(): menu.popup_centered())
	pause_button = screen.get_node("Toolbar/Pause")
	pause_button.icon = Assets.icon("pause")
	pause_button.pressed.connect(_toggle_pause)
	start_battle_button = menu.get_node("Content/Time/Start")
	var shop_heading: HBoxContainer = shop.get_node("Heading")
	gold_label.reparent(shop_heading)
	gold_label.add_theme_font_size_override("font_size", 20)
	shop_heading.move_child(gold_label, 3)
	start_battle_button.reparent(shop_heading)
	shop_heading.move_child(start_battle_button, 4)
	start_battle_button.custom_minimum_size = Vector2(112, 30)
	start_battle_button.add_theme_font_size_override("font_size", 14)
	start_battle_button.tooltip_text = "完成布阵后立即开始本轮战斗"
	start_battle_button.pressed.connect(_battle)
	extend_preparation_button = menu.get_node("Content/Time/Extend")
	extend_preparation_button.pressed.connect(_extend_preparation_time)
	for slot in range(1, 4):
		_button(menu.get_node("Content/Saves"), "存档 %d" % slot, _save.bind(slot))
		_button(menu.get_node("Content/Saves"), "读档 %d" % slot, _load.bind(slot))
	menu.get_node("Content/NewGame").pressed.connect(_open_new_game_choice)
	menu.get_node("Content/PreviewToggle").pressed.connect(_toggle_piece_preview)
	var audio_settings = audio.settings_panel()
	add_child(audio_settings)
	_button(menu.get_node("Content"), "声音设置", func():
		menu.hide()
		audio_settings.popup_centered())
	_button(menu.get_node("Content"), "返回主菜单", func():
		menu.hide()
		screen.hide()
		audio.stop_combat()
		audio.countdown(0, game.round_number, false)
		audio.set_paused(false)
		main_menu.show_home()
		main_menu.show()
		audio.set_phase("menu"))
	piece_preview_box = menu.get_node("Content/Preview")
	preview_scene = preload("res://scenes/piece_preview_3d.tscn").instantiate()
	piece_preview_box.get_node("World").add_child(preview_scene)
	sell_zone = _drag_button(screen, "拖到此处出售", "sell", -1)
	sell_zone.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	sell_zone.position = Vector2(16, size.y - 248)
	sell_zone.size = Vector2(186, 30)
	sell_zone.icon = Assets.icon("coin")
	sell_zone.add_theme_font_size_override("font_size", 12)
	var shop_sell=preload("res://scripts/ui/shop_sell_drop.gd").new()
	shop_sell.name="ShopSellDrop"
	shop_sell.controller=self
	shop_sell.shop=shop
	screen.add_child(shop_sell)
	final_panel = CenterContainer.new()
	final_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	final_panel.visible = false
	final_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(final_panel)
	var final_box := PanelContainer.new()
	final_box.custom_minimum_size = Vector2(460, 240)
	var final_style := StyleBoxFlat.new()
	final_style.bg_color = Color(0.08, 0.12, 0.18, 0.96)
	final_style.border_color = Color(0.90, 0.72, 0.32)
	final_style.set_border_width_all(2)
	final_style.set_content_margin_all(24)
	final_box.add_theme_stylebox_override("panel", final_style)
	final_panel.add_child(final_box)
	var final_content := VBoxContainer.new()
	final_content.alignment = BoxContainer.ALIGNMENT_CENTER
	final_box.add_child(final_content)
	final_label = _label("")
	final_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_label.add_theme_font_size_override("font_size", 23)
	final_content.add_child(final_label)
	_button(final_content, "重新开局", _open_new_game_choice)
	difficulty_panel = CenterContainer.new()
	difficulty_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	difficulty_panel.visible = false
	difficulty_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(difficulty_panel)
	var difficulty_box := PanelContainer.new()
	difficulty_box.custom_minimum_size = Vector2(420, 210)
	difficulty_panel.add_child(difficulty_box)
	var difficulty_content := VBoxContainer.new()
	difficulty_box.add_child(difficulty_content)
	difficulty_content.add_child(_label("选择本局 7 名电脑的难度"))
	for choice in [["简单", "easy"], ["中等", "medium"], ["困难", "hard"]]:
		_button(difficulty_content, choice[0], _new_game.bind(choice[1]))
	for item_id in game.content["items"]:
		var item: Dictionary = game.content["items"][item_id]
		if not item["recipe"].is_empty():
			craft_select.add_item(item["name"])
			craft_select.set_item_metadata(craft_select.item_count - 1, item_id)
	operation_feedback = preload("res://scenes/ui/operation_feedback.tscn").instantiate()
	operation_feedback.controller = self
	screen.add_child(operation_feedback)
	round_feedback = preload("res://scenes/ui/round_feedback.tscn").instantiate()
	screen.add_child(round_feedback)
	battle_wait_notice = preload("res://scripts/ui/battle_wait_notice.gd").new()
	screen.add_child(battle_wait_notice)


func make_drag_preview(data: Dictionary) -> Control:
	var preview := Control.new()
	preview.name = "DragPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.size = Vector2(128, 145)
	var piece: Dictionary = operation_feedback.piece_at(str(data["kind"]), int(data["index"])) if data["kind"] in ["board", "bench"] else {}
	var caption := ""
	if not piece.is_empty():
		var container := SubViewportContainer.new()
		container.position = Vector2(-64, -145)
		container.size = Vector2(128, 120)
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(128, 120)
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var world = preload("res://scenes/piece_preview_3d.tscn").instantiate()
		world.piece_id = piece["id"]
		world.star = int(piece["star"])
		world.ready.connect(func():
			for child in world.get_children():
				if child is MeshInstance3D and child.mesh is CylinderMesh: child.hide()
			var camera: Camera3D = world.get_viewport().get_camera_3d()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 3.4
			camera.look_at(Vector3(0, 1.4, 0)))
		viewport.add_child(world)
		caption = "%s %s" % [game.units[piece["id"]]["name_zh"], "★".repeat(int(piece["star"]))]
	else:
		var item: Dictionary = {}
		if data["kind"] == "inventory": item = game.players[0]["inventory"][int(data["index"])]
		elif data["kind"] in ["equipped_board", "equipped_bench"]: item = operation_feedback.piece_at(data["kind"], int(data["index"]))["items"][int(data["extra"])]
		var icon := TextureRect.new()
		icon.position = Vector2(-24, -76)
		icon.size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = Assets.icon("hammer") if item.is_empty() else _icon_texture(item["id"])
		preview.add_child(icon)
		caption = "拆卸工具" if item.is_empty() else game.content["items"][item["id"]]["name"]
	var label := Label.new()
	label.text = caption
	label.position = Vector2(-90, -25)
	label.size = Vector2(180, 25)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(label)
	return preview


func _visual_to_game(visual_index: int) -> int:
	var row := visual_index / 8
	return (7 - row) * 8 + visual_index % 8 if row >= 4 else -1


func _game_to_visual(game_index: int) -> int:
	return (7 - game_index / 8) * 8 + game_index % 8


func _monster_name(monster_id: String) -> String:
	for monster in game.content["monsters"]:
		if monster["id"] == monster_id: return monster["name_zh"]
	return monster_id


func _toggle_piece_preview() -> void:
	piece_preview_box.visible = not piece_preview_box.visible
	var menu: PopupPanel = screen.get_node("UtilityMenu")
	menu.size = Vector2i(460, 520 if piece_preview_box.visible else 370)
	menu.popup_centered()


func _buy(index: int) -> void:
	if viewed_seat != 0 or game_paused: return
	var before: Dictionary = operation_feedback.snapshot()
	var name: String = game.players[0]["shop"][index]
	var bought: bool = game.buy(0, index)
	_refresh()
	var at: Vector2 = shop_buttons[index].get_global_rect().get_center()
	if bought:
		audio.ui("buy")
		var upgraded: String = operation_feedback.pulse_changes(before)
		if upgraded != "": audio.ui("upgrade")
		operation_feedback.message(upgraded if upgraded != "" else "已购买 %s" % game.units[name]["name_zh"], at)
	else:
		var reason := "该商品已售出"
		if name != "":
			reason = "金币不足 · 还差 %d" % (int(game.units[name]["cost"]) - int(game.players[0]["gold"])) if int(game.players[0]["gold"]) < int(game.units[name]["cost"]) else "备战席已满" if not game._buy_fits_bench(game.players[0], name) else "当前阶段不能购买"
		operation_feedback.message(reason, at, operation_feedback.RED)


func _reroll() -> void:
	if viewed_seat == 0 and not game_paused and game.reroll(0): audio.ui("refresh")
	_refresh()


func _buy_xp() -> void:
	if viewed_seat == 0 and not game_paused: game.buy_xp(0)
	_refresh()


func _toggle_lock() -> void:
	if viewed_seat == 0 and not game_paused: game.toggle_lock(0)
	_refresh()


func _extend_preparation_time() -> void:
	if viewed_seat == 0 and game.phase == "preparation" and not game_paused:
		var increase := mini(int(game.content["economy"]["preparation_extension_step_seconds"]),
			int(game.content["economy"]["max_preparation_seconds"] - preparation_seconds_total))
		preparation_seconds_total += increase
		preparation_seconds_left += increase
		audio.countdown(preparation_seconds_left, game.round_number, true)
	_refresh()


func _toggle_pause() -> void:
	game_paused = not game_paused
	audio.set_paused(game_paused)
	_refresh()


func _view_seat(seat: int) -> void:
	audio.stop_combat()
	viewed_seat = clampi(seat, 0, 7)
	battle_scene.reset()
	battle_frame_index = 0
	selected_bench = -1
	selected_board = -1
	selected_item = -1
	if game.phase == "battle": _show_battle_frame()
	_refresh()


func _bench_pressed(index: int) -> void:
	if viewed_seat != 0 or game_paused or game.phase != "preparation": return
	if selected_item >= 0:
		handle_drop({"kind": "inventory", "index": selected_item}, "bench", index, -1)
		return
	if selected_board >= 0:
		handle_drop({"kind": "board", "index": selected_board}, "bench", index, -1)
		return
	if game.bench_index_at_slot(0, index) < 0: return
	selected_bench = index
	selected_board = -1
	_refresh()


func _board_pressed(index: int) -> void:
	if viewed_seat != 0 or game_paused or game.phase != "preparation" or index < 0: return
	var player: Dictionary = game.players[0]
	if selected_item >= 0 and player["board"].has(index):
		handle_drop({"kind": "inventory", "index": selected_item}, "board", index, -1)
		return
	elif selected_bench >= 0:
		handle_drop({"kind": "bench", "index": selected_bench}, "board", index, -1)
		return
	elif player["board"].has(index):
		selected_board = index
	_refresh()


func _item_pressed(index: int) -> void:
	selected_item = index
	selected_bench = -1
	selected_board = -1
	_refresh()


func _use_selected_item() -> void:
	if game_paused: return
	if selected_item >= 0 and game.use_item(0, selected_item): selected_item = -1
	_refresh()


func _dismantle_selected_item() -> void:
	if game_paused: return
	if selected_item >= 0 and game.dismantle(0, selected_item): selected_item = -1
	_refresh()


func _craft_selected() -> void:
	if game_paused: return
	if craft_select.item_count == 0: return
	var item_id: String = craft_select.get_item_metadata(craft_select.selected)
	game.craft(0, item_id)
	_refresh()


func _battle() -> void:
	if game_paused or game.phase != "preparation": return
	completed_battle_cues.clear()
	screen.get_node("UtilityMenu").hide()
	battle_courier_hp.clear()
	for courier in game.players: battle_courier_hp.append(int(courier["hp"]))
	if not game.resolve_round(true): return
	audio.countdown(0, game.round_number, false)
	audio.stop_combat()
	battle_scene.reset()
	preparation_seconds_left = 0.0
	battle_elapsed = 0.0
	battle_frame_index = 0
	selected_bench = -1
	selected_board = -1
	selected_item = -1
	_refresh()


func _finish_battle() -> void:
	_update_local_battle_feedback()
	if not game.complete_battle(): return
	audio.stop_combat()
	last_battle_stats = game.battle_replay.get("stats", []).duplicate(true)
	last_battle_round = game.round_number
	settlement_seconds_left = float(game.content["economy"]["settlement_seconds"])
	_refresh()


func _next_round() -> void:
	if game.phase != "settlement": return
	if not game.chest_choices.is_empty(): _pick_chest(0)
	if game.advance_round(true): _reset_preparation_timer()
	_refresh()


func _open_new_game_choice() -> void:
	screen.get_node("UtilityMenu").hide()
	difficulty_panel.visible = true


func _new_game(difficulty: String = "medium") -> void:
	if is_instance_valid(main_menu): main_menu.hide()
	screen.show()
	displayed_level = -1
	trait_view_seat = -1
	game.new_game(-1, true, true, difficulty)
	difficulty_panel.visible = false
	game_paused = false
	viewed_seat = 0
	last_battle_stats.clear()
	last_battle_round = 0
	_reset_preparation_timer()
	selected_bench = -1
	selected_board = -1
	selected_item = -1
	_refresh()


func _continue_game() -> bool:
	if not game.load_round_start(): return false
	main_menu.hide()
	screen.show()
	difficulty_panel.hide()
	game_paused = false
	viewed_seat = 0
	selected_bench = -1
	selected_board = -1
	selected_item = -1
	last_battle_stats.clear()
	last_battle_round = 0
	displayed_level = -1
	trait_view_seat = -1
	_reset_preparation_timer()
	_refresh()
	return true


func _save(slot: int) -> void:
	game.save_slot(slot)
	_refresh()


func _load(slot: int) -> void:
	if game.load_slot(slot):
		game_paused = false
		viewed_seat = 0
		last_battle_stats.clear()
		last_battle_round = 0
		_reset_preparation_timer()
		selected_bench = -1
		selected_board = -1
		selected_item = -1
	_refresh()


func _pick_chest(index: int) -> void:
	if game_paused: return
	var item_id := str(game.chest_choices[index]) if index >= 0 and index < game.chest_choices.size() else ""
	if game.pick_chest(index):
		operation_feedback.message("已获得 %s · 已放入装备栏" % game.content["items"][item_id]["name"], screen.get_node("Inventory").global_position, Color(1, 0.78, 0.3))
	_refresh()


func _unit_tags(unit: Dictionary) -> Array:
	var tags: Array = Array(str(unit["species"]).split("、"))
	tags.append_array(Array(str(unit["class"]).split("、")))
	return tags


func _skill_value(value: Variant, star: int) -> String:
	if typeof(value) == TYPE_ARRAY and value.size() == 3: value = value[clampi(star - 1, 0, 2)]
	return str(value) if typeof(value) not in [TYPE_ARRAY, TYPE_DICTIONARY] else JSON.stringify(value)


func _piece_tooltip(piece: Dictionary, detailed: bool = false) -> String:
	var unit: Dictionary = game.units[piece["id"]]
	var star := int(piece["star"])
	var sell_gold := int(unit["sell_gold"][clampi(star - 1, 0, unit["sell_gold"].size() - 1)])
	var lines := ["%s ★%d" % [unit["name_zh"], piece["star"]], "种族/职业：%s" % " · ".join(_unit_tags(unit)),
		"出售价格：%d 金币" % sell_gold]
	var ability: Dictionary = unit["ability"]
	lines.append("技能：%s" % ("拖到其他棋子上复制身份，保留自身星级与装备" if piece["id"]=="Io" else str(ability.get("summary_zh", ability.get("kind", "无")))))
	if detailed:
		lines.append("—— ★%d 技能运行参数 ——" % star)
		var names := {"values": "效果值", "duration_s": "持续秒数", "cooldown_s": "冷却秒数", "mana_cost": "耗蓝", "cast_point_s": "施法前摇秒数",
			"radius_grids": "范围格数", "damage_type": "伤害类型", "projectile_speed_units_per_s": "弹速/秒", "charge_time_s": "蓄力秒数",
			"travel_distance_grids": "位移格数", "proc_chance_percent": "触发概率%", "trigger": "触发方式", "target": "目标"}
		for key in ability:
			if key in ["summary_zh", "source", "source_by_field", "source_urls", "research_url", "early_vpk_numeric_kv"] or str(key).begins_with("early_vpk"): continue
			var value: Variant = ability[key]
			if key == "effect" and typeof(value) == TYPE_DICTIONARY:
				for effect_key in value:
					lines.append("%s：%s" % [names.get(effect_key, effect_key), _skill_value(value[effect_key], star)])
			else:
				lines.append("%s：%s" % [names.get(key, key), _skill_value(value, star)])
	else:
		lines.append("按住 Ctrl 查看当前星级技能数值")
	for item in piece["items"]: lines.append("装备：%s" % game.content["items"][item["id"]]["name"])
	return "\n".join(lines)


func dynamic_tooltip(kind: String, index: int, _extra: int, fallback: String) -> String:
	var player: Dictionary = game.players[viewed_seat]
	var detailed := Input.is_key_pressed(KEY_CTRL)
	match kind:
		"board":
			if player["board"].has(index): return _piece_tooltip(player["board"][index], detailed)
		"bench":
			var bench_index := game.bench_index_at_slot(viewed_seat, index)
			if bench_index >= 0: return _piece_tooltip(player["bench"][bench_index], detailed)
		"shop":
			if viewed_seat == 0 and index >= 0 and index < player["shop"].size() and player["shop"][index] != "":
				return _piece_tooltip({"id": player["shop"][index], "star": 1, "items": []}, detailed)
		"battle_actor":
			var frames: Array = game.seat_replay(viewed_seat).get("frames", [])
			if not frames.is_empty():
				for actor in frames[mini(battle_frame_index, frames.size() - 1)]["actors"]:
					if int(actor["uid"]) == index and game.units.has(actor["id"]):
						return fallback + "\n" + _piece_tooltip({"id": actor["id"], "star": actor["star"], "items": actor["items"]}, detailed)
	return fallback


func _item_tooltip(item: Dictionary) -> String:
	var definition: Dictionary = game.content["items"][item["id"]]
	return "%s\n%s" % [definition["name"], definition.get("effect_text", "")]


func _recipe_matches_pair(recipe: Array, first_id: String, second_id: String) -> bool:
	var needed: Dictionary = {}
	for part in recipe:
		needed[part["item_id"]] = int(needed.get(part["item_id"], 0)) + int(part["count"])
	var provided: Dictionary = {}
	provided[first_id] = 1
	provided[second_id] = int(provided.get(second_id, 0)) + 1
	return needed == provided


func _craft_candidates(first: Dictionary, second: Dictionary) -> Array:
	var candidates: Array = []
	var first_id: String = first["id"]
	var second_id: String = second["id"]
	for item_id in game.content["items"]:
		var item: Dictionary = game.content["items"][item_id]
		if _recipe_matches_pair(item["recipe"], first_id, second_id):
			candidates.append({"id": item_id, "level": 1, "name": item["name"]})
	if _recipe_matches_pair(game.content["items"]["dagon_1_5"]["upgrade_recipe"], first_id, second_id):
		var old: Dictionary = first if first_id == "dagon_1_5" else second
		var next_level := int(old.get("level", 1)) + 1
		if next_level <= 5:
			candidates.append({"id": "dagon_1_5", "level": next_level, "name": "达贡 %d 级" % next_level})
	return candidates


func _tier_effect(synergy: Dictionary, tier_index: int) -> String:
	var full_text := str(synergy["effect_text"])
	var tier := int(synergy["tiers"][tier_index])
	var marker := "%d：" % tier
	var start := full_text.find(marker)
	if start >= 0:
		start += marker.length()
		var end := full_text.find("；", start)
		return full_text.substr(start, end - start if end >= 0 else -1)
	var simplified := full_text
	var pattern := RegEx.create_from_string("[+-]?[0-9]+%?(/[+-]?[0-9]+%?)+")
	for found in pattern.search_all(full_text):
		var choices := found.get_string().split("/")
		if choices.size() == synergy["tiers"].size(): simplified = simplified.replace(found.get_string(), choices[tier_index])
	return simplified


func _refresh_traits() -> void:
	activated_traits.clear()
	for node in trait_list.get_children(): node.queue_free()
	var species_list := VBoxContainer.new()
	trait_list.add_child(species_list)
	var species_heading := _label("种族")
	species_heading.add_theme_font_size_override("font_size", 11)
	species_list.add_child(species_heading)
	var class_list := VBoxContainer.new()
	trait_list.add_child(class_list)
	var class_heading := _label("职业")
	class_heading.add_theme_font_size_override("font_size", 11)
	class_list.add_child(class_heading)
	var species_tags: Dictionary = {}
	for unit in game.content["units"]:
		for species in str(unit["species"]).split("、"): species_tags[species] = true
	var counts: Dictionary = {}
	for piece in game.players[viewed_seat]["board"].values():
		for tag in _unit_tags(game.units[piece["id"]]):
			if not counts.has(tag): counts[tag] = {}
			counts[tag][piece["id"]] = true
	for piece in game.players[viewed_seat]["bench"]:
		if "德鲁伊" in _unit_tags(game.units[piece["id"]]):
			if not counts.has("德鲁伊"): counts["德鲁伊"] = {}
			counts["德鲁伊"][piece["id"]] = true
	var effective: Dictionary = {}
	for tag in counts: effective[tag] = counts[tag].size()
	if int(effective.get("巫师", 0)) >= 2:
		var best_tag := ""
		var best_gap := 100
		for synergy in game.content["synergies"]:
			var tag: String = synergy["tag"]
			if tag in ["巫师", "德鲁伊"] or int(effective.get(tag, 0)) == 0: continue
			for tier in synergy["tiers"]:
				var gap := int(tier) - int(effective[tag])
				if gap > 0 and (gap < best_gap or (gap == best_gap and (best_tag == "" or tag < best_tag))):
					best_gap = gap
					best_tag = tag
				break
		if best_tag != "": effective[best_tag] += 1
	var enemy_demon_hunter := false
	var frames: Array = game.seat_replay(viewed_seat).get("frames", [])
	if viewed_seat == 0 and game.phase == "battle" and not frames.is_empty():
		for actor in frames[0]["actors"]:
			if int(actor["team"]) == int(game.seat_replay(viewed_seat)["player_team"]): continue
			if game.units.has(actor["id"]) and "恶魔猎手" in _unit_tags(game.units[actor["id"]]):
				enemy_demon_hunter = true
				break
	var other_species_active := false
	for synergy in game.content["synergies"]:
		var tag: String = synergy["tag"]
		if tag == "神" or not species_tags.has(tag) or int(effective.get(tag, 0)) < int(synergy["tiers"][0]): continue
		if tag == "恶魔" and (enemy_demon_hunter or (int(counts.get("恶魔", {}).size()) != 1 and int(effective.get("恶魔猎手", 0)) < 2)):
			continue
		other_species_active = true
		break
	for synergy in game.content["synergies"]:
		var count := int(counts.get(synergy["tag"], {}).size())
		if count == 0: continue
		var current := 0
		var next := 0
		var tiers: Array = synergy["tiers"]
		for tier in tiers:
			if int(effective[synergy["tag"]]) >= int(tier): current = int(tier)
			elif next == 0: next = int(tier)
		var inactive_reason := ""
		if synergy["tag"] == "恶魔" and (count != 1 and int(effective.get("恶魔猎手", 0)) < 2 or enemy_demon_hunter):
			current = 0
			inactive_reason = "不同恶魔共存，或敌方恶魔猎手压制"
		if synergy["tag"] == "神" and other_species_active:
			current = 0
			inactive_reason = "其他种族羁绊已生效"
		if current > 0: activated_traits[str(synergy["tag"])] = current
		var shown_count := "%d+1" % count if int(effective[synergy["tag"]]) > count else str(count)
		var caption := "%s  %s/%d" % [synergy["tag"], shown_count, current if current > 0 else next]
		if inactive_reason != "": caption = "%s  %s/%d" % [synergy["tag"], shown_count, int(tiers[0])]
		var entry := _label(caption)
		entry.add_theme_font_size_override("font_size", 15)
		entry.mouse_filter = Control.MOUSE_FILTER_STOP
		entry.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3) if current > 0 else Color(0.62, 0.67, 0.74))
		var lines := ["%s：当前 %d 种不同%s棋子" % [synergy["tag"], count,
			"场上及备战席" if synergy["tag"] == "德鲁伊" else "上场"]]
		for tier in tiers:
			lines.append("%s %d 种" % ["✓" if current >= int(tier) else "○", int(tier)])
		if inactive_reason != "": lines.append("未激活：" + inactive_reason)
		lines.append("各档效果：%s" % synergy["effect_text"])
		entry.tooltip_text = "\n".join(lines)
		var group: VBoxContainer = species_list if species_tags.has(synergy["tag"]) else class_list
		var trait_row := HBoxContainer.new()
		group.add_child(trait_row)
		var emblem := TextureRect.new()
		emblem.texture = Assets.icon("shield" if synergy["tag"] in ["战士", "骑士", "兽人"] else "sword" if synergy["tag"] in ["刺客", "猎人", "恶魔"] else "orb")
		emblem.custom_minimum_size = Vector2(24, 24)
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem.modulate = Assets.GOLD if current > 0 else Color(0.48, 0.59, 0.64)
		trait_row.add_child(emblem)
		trait_row.set_meta("active", current > 0)
		trait_row.add_theme_constant_override("separation", 8)
		var detail := VBoxContainer.new()
		detail.add_theme_constant_override("separation", 0)
		trait_row.add_child(detail)
		detail.add_child(entry)
		var tier_row := HBoxContainer.new()
		detail.add_child(tier_row)
		for tier_index in range(tiers.size()):
			var tier: int = int(tiers[tier_index])
			var tier_label := _label(str(tier))
			tier_label.add_theme_font_size_override("font_size", 12)
			tier_label.mouse_filter = Control.MOUSE_FILTER_STOP
			tier_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3) if current >= tier else Color(0.55, 0.59, 0.66))
			tier_label.tooltip_text = "%s · %d 种\n%s" % [synergy["tag"], tier, _tier_effect(synergy, tier_index)]
			tier_row.add_child(tier_label)
	for group in [species_list, class_list]:
		var entries: Array = []
		for child in group.get_children():
			if child.has_meta("active"): entries.append(child)
		entries.sort_custom(func(a, b): return bool(a.get_meta("active")) and not bool(b.get_meta("active")))
		for index in range(entries.size()): group.move_child(entries[index], index + 1)


func _icon_texture(item_id: String) -> Texture2D:
	return Assets.equipment_icon(item_id)


func _set_bars(index: int, hp: float, max_hp: float, mana: float, max_mana: float) -> void:
	board_hp_bars[index].visible = max_hp > 0
	board_mana_bars[index].visible = max_hp > 0
	board_hp_bars[index].max_value = maxf(1.0, max_hp)
	board_hp_bars[index].value = maxf(0.0, hp)
	board_mana_bars[index].max_value = maxf(1.0, max_mana)
	board_mana_bars[index].value = maxf(0.0, mana)


func _set_board_items(index: int, items: Array, piece_index: int, draggable: bool) -> void:
	var signature := "D%d" % piece_index if draggable else "S"
	for item in items: signature += str(item["id"]) + ":" + str(item.get("level", 1)) + ";"
	if signature == board_item_signatures[index]: return
	board_item_signatures[index] = signature
	var row: HBoxContainer = board_item_rows[index]
	for node in row.get_children(): node.queue_free()
	for item_index in range(mini(6, items.size())):
		var item: Dictionary = items[item_index]
		var icon: Button = _drag_button(row, "", "equipped_board" if draggable else "display_item", piece_index, item_index)
		icon.theme_type_variation = &"EquipmentPip"
		icon.icon = _icon_texture(item["id"])
		icon.custom_minimum_size = Vector2(10, 10)
		icon.expand_icon = true
		icon.tooltip_text = _item_tooltip(item)


func _set_bench_items(index: int, items: Array) -> void:
	var signature := ""
	for item in items: signature += str(item["id"]) + ":" + str(item.get("level", 1)) + ";"
	if signature == bench_item_signatures[index]: return
	bench_item_signatures[index] = signature
	var row: HBoxContainer = bench_item_rows[index]
	for node in row.get_children(): node.queue_free()
	for item_index in range(mini(6, items.size())):
		var item: Dictionary = items[item_index]
		var icon: Button = _drag_button(row, "", "equipped_bench", index, item_index)
		icon.theme_type_variation = &"EquipmentPip"
		icon.icon = _icon_texture(item["id"])
		icon.custom_minimum_size = Vector2(13, 13)
		icon.expand_icon = true
		icon.tooltip_text = _item_tooltip(item)


func _show_battle_frame() -> void:
	var frames: Array = game.seat_replay(viewed_seat).get("frames", [])
	if frames.is_empty(): return
	while battle_frame_index + 1 < frames.size() and float(frames[battle_frame_index + 1]["time"]) <= battle_elapsed:
		battle_frame_index += 1
	var replay: Dictionary = game.seat_replay(viewed_seat)
	var index := mini(battle_frame_index, frames.size()-1)
	if battle_elapsed < float(replay.get("seconds", 0.0)):
		audio.sync(replay, frames[index], battle_elapsed, "%d:%d" % [game.round_number, viewed_seat])
	battle_scene.sync(frames[index],frames[mini(index+1,frames.size()-1)],replay.get("visual_events",[]),battle_elapsed,int(replay["player_team"]))
	_refresh_battle_actors(frames[index],int(replay["player_team"]))


func _update_local_battle_feedback() -> void:
	if not is_instance_valid(battle_wait_notice): return
	if game.phase != "battle":
		battle_wait_notice.set_waiting(false)
		return
	var replay: Dictionary = game.seat_replay(viewed_seat)
	var ended := replay.is_empty() or battle_elapsed >= float(replay.get("seconds", 0.0))
	var key := "%d:%d" % [game.round_number, viewed_seat]
	if ended and not replay.is_empty() and not completed_battle_cues.has(key):
		completed_battle_cues[key] = true
		audio.stop_combat()
		var outcome: Dictionary = game.last_results.get(viewed_seat, game.last_results.get(str(viewed_seat), {}))
		if not outcome.is_empty() and not bool(outcome.get("tie", false)):
			audio.ui("victory" if bool(outcome.get("win", false)) else "defeat")
	battle_wait_notice.set_waiting(ended and battle_elapsed < game.battle_total_seconds())


func _actor_visual_index(actor: Dictionary, player_team: int) -> int:
	var pos: Vector2 = actor["pos"]
	var x := clampi(roundi(pos.x), 0, 7)
	var y := clampi(roundi(pos.y), 0, 7)
	if player_team == 0: y = 7 - y
	else: x = 7 - x
	return y * 8 + x


func _battle_card(uid: int) -> Dictionary:
	if battle_actor_cards.has(uid): return battle_actor_cards[uid]
	var root = preload("res://scenes/ui/battle_unit_hud.tscn").instantiate()
	root.controller = self
	root.kind = "battle_actor"
	root.index = uid
	root.flat = true
	root.size = Vector2(64, 40)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	battle_layer.add_child(root)
	var card := {"root": root, "background": root.get_node("Background"), "name": root.get_node("Name"),
		"hp": root.get_node("HP/Fill"), "shield": root.get_node("HP/Shield"), "mana": root.get_node("Mana/Fill"),
		"items": root.get_node("Items"), "item_signature": ""}
	battle_actor_cards[uid] = card
	return card


func _set_battle_items(card: Dictionary, items: Array, origin: int, own: bool) -> void:
	var signature := "%d:%d" % [origin, int(own)]
	for item in items: signature += ":%s:%d" % [item["id"], int(item.get("level", 1))]
	if signature == card["item_signature"]: return
	card["item_signature"] = signature
	var row: HBoxContainer = card["items"]
	for node in row.get_children(): node.queue_free()
	for index in range(mini(6, items.size())):
		var icon: Button = _drag_button(row, "", "equipped_board" if own and origin >= 0 else "display_item", origin, index)
		icon.theme_type_variation = &"EquipmentPip"
		icon.icon = _icon_texture(items[index]["id"])
		icon.custom_minimum_size = Vector2(8, 8)
		icon.add_theme_constant_override("icon_max_width", 8)
		icon.expand_icon = true
		icon.flat = true
		icon.tooltip_text = _item_tooltip(items[index])


func _refresh_battle_actors(frame: Dictionary, player_team: int) -> void:
	var groups: Dictionary = {}
	var anchors := {}
	var active: Dictionary = {}
	var own_lines: Array = []
	var enemy_lines: Array = []
	for actor in frame["actors"]:
		var line := "%s%s  HP %.0f/%.0f  MP %.0f/%.0f" % [
			"✖ " if float(actor["hp"]) <= 0 else "", actor["name"], actor["hp"], actor["max_hp"], actor["mana"], actor["max_mana"]]
		if int(actor["team"]) == player_team: own_lines.append(line)
		else: enemy_lines.append(line)
		if float(actor["hp"]) <= 0:
			if battle_actor_cards.has(int(actor["uid"])): battle_actor_cards[int(actor["uid"])]["hp"].size.x = 0.0
			continue
		var visual_index := _actor_visual_index(actor, player_team)
		if not groups.has(visual_index): groups[visual_index] = []
		groups[visual_index].append(actor)
	var viewport_scale := battle_layer.size/Vector2(battle_viewport.get_node("World").size)
	for group in groups.values():
		for actor in group:
			var uid := int(actor.uid)
			anchors[uid]=(battle_scene.project_actor(uid) if battle_scene.pieces.has(uid) else battle_scene.project_position(actor.pos,player_team,.6))*viewport_scale
	for visual_index in groups:
		var group: Array = groups[visual_index]
		for slot in range(group.size()):
			var actor: Dictionary = group[slot]
			var uid := int(actor["uid"])
			active[uid] = true
			var card: Dictionary = _battle_card(uid)
			var own: bool = int(actor["team"]) == player_team
			card["root"].visible = true
			card["root"].scale = Vector2.ONE
			var pilot: bool = battle_scene.pieces.has(uid)
			var anchor: Vector2 = anchors[uid]
			var width := 48.0
			for other_uid in anchors:
				if other_uid==uid: continue
				var separation: Vector2=anchor-anchors[other_uid]
				if absf(separation.y)<9 and absf(separation.x)<52: width=minf(width,maxf(28,absf(separation.x)-4))
			card.root.set_bar_width(width)
			var hud_position := anchor + Vector2(-32, -34)
			card["root"].position = hud_position
			card["root"].set_model_anchor(anchor - hud_position)
			card["root"].z_index = slot
			card["root"].set_actor(actor, own, battle_scene.cues.get(uid, {}), battle_elapsed, str(battle_scene.pieces[uid].get_meta("battle_clip", "")) if pilot else "")
			card["background"].color = Color(0.15, 0.27, 0.20, 0.9) if own else Color(0.36, 0.18, 0.20, 0.9)
			card["background"].visible = not pilot
			var name_color := _cost_color(int(game.units[actor["id"]]["cost"])) if game.units.has(actor["id"]) else Color.WHITE
			if card["name"].get_theme_color("font_color") != name_color: card["name"].add_theme_color_override("font_color", name_color)
			var origin := int(actor.get("origin", -1))
			var shown_items: Array = actor["items"]
			if own and viewed_seat == 0 and game.players[0]["board"].has(origin): shown_items = game.players[0]["board"][origin]["items"]
			_set_battle_items(card, shown_items, origin, own and viewed_seat == 0 and not actor["summon"])
			if own and viewed_seat == 0 and not actor["summon"]: card["root"].tooltip_text += "\n战斗中调整装备，下回合生效"
	var widths := {}
	for uid in anchors: widths[uid]=battle_actor_cards[uid].root.bar_width
	var offsets: Dictionary=preload("res://scripts/ui/battle_hud_layout.gd").offsets(anchors,widths)
	for uid in anchors:
		var hud: Control=battle_actor_cards[uid].root
		hud.position=anchors[uid]+Vector2(-32,-34)+offsets[uid]
		hud.set_model_anchor(anchors[uid]-hud.position)
	for uid in battle_actor_cards:
		if not active.has(uid): battle_actor_cards[uid]["root"].visible = false
	battle_roster.visible = true
	battle_roster.text = "己方棋子\n%s\n对手棋子\n%s" % ["\n".join(own_lines), "\n".join(enemy_lines)]
	if game.phase == "battle":
		var own_alive := 0
		var enemy_alive := 0
		for actor in frame["actors"]:
			if float(actor["hp"]) <= 0: continue
			if int(actor["team"]) == player_team: own_alive += 1
			else: enemy_alive += 1
		stats_panel.tooltip_text = "本轮剩余：己方 %d / 对手 %d" % [own_alive, enemy_alive]


func _refresh_board() -> void:
	var player: Dictionary = game.players[viewed_seat]
	var replay: Dictionary = game.seat_replay(viewed_seat)
	var frames: Array = replay.get("frames", [])
	var show_replay: bool = game.phase in ["battle", "settlement", "finished"] and not frames.is_empty()
	battle_viewport.visible = true
	board_screen.set_replay(show_replay)
	over_limit_label.visible = viewed_seat == 0 and game.phase == "preparation" and player["board"].size() > int(player["level"])
	over_limit_label.text = "超员 %d/%d" % [player["board"].size(), int(player["level"])] if over_limit_label.visible else ""
	var monsters: Dictionary = {}
	if not show_replay:
		var wave: Dictionary = game._wave()
		if not wave.is_empty():
			for spawn in wave["spawns"]: monsters[(7 - int(spawn["row"])) * 8 + int(spawn["col"])] = spawn["monster_id"]
	for visual_index in range(0 if show_replay else 64):
		var button: Button = board_buttons[visual_index]
		var game_index := _visual_to_game(visual_index)
		button.text = "·"
		board_screen.set_caption(visual_index, "", false)
		button.tooltip_text = "己方布阵区" if game_index >= 0 else "对手半场"
		button.self_modulate = Color.WHITE
		_set_cost_font(button, Color.WHITE)
		_set_bars(visual_index, 0, 0, 0, 0)
		if not show_replay and game_index >= 0 and player["board"].has(game_index):
			var piece: Dictionary = player["board"][game_index]
			var unit: Dictionary = game.units[piece["id"]]
			button.text = "%s\n★%d" % [unit["name_zh"], piece["star"]]
			board_screen.set_caption(visual_index, "%s %s" % ["★".repeat(int(piece["star"])), unit["name_zh"]], selected_board == game_index)
			button.tooltip_text = _piece_tooltip(piece)
			button.self_modulate = Color.WHITE
			_set_cost_font(button, _cost_color(int(unit["cost"])))
			_set_board_items(visual_index, piece["items"], game_index, viewed_seat == 0)
		elif not show_replay and monsters.has(visual_index):
			button.text = _monster_name(str(monsters[visual_index]))
			board_screen.set_caption(visual_index, button.text, false)
			button.tooltip_text = "本回合野怪：" + button.text
			button.self_modulate = Color(1.0, 0.78, 0.78)
			_set_board_items(visual_index, [], -1, false)
		else:
			_set_board_items(visual_index, [], -1, false)
	if show_replay:
		var index := mini(battle_frame_index, frames.size() - 1)
		battle_scene.sync(frames[index], frames[mini(index + 1, frames.size() - 1)], replay.get("visual_events", []),
			battle_elapsed, int(replay["player_team"]))
		_refresh_battle_actors(frames[index], int(replay["player_team"]))
	else:
		battle_scene.sync_preparation(player["board"], monsters)
		if trait_view_seat != viewed_seat: battle_scene.clear_trait_activations()
		trait_view_seat = viewed_seat
		battle_scene.sync_trait_activations(player["board"],game.units,activated_traits)
		for card in battle_actor_cards.values(): card["root"].visible = false
		battle_roster.visible = false


func _refresh_stats_panel() -> void:
	stats_panel.set_statistics(last_battle_round, last_battle_stats)
	if last_battle_round == 0:
		stats_label.text = "战斗统计\n完成一场战斗后显示"
		stats_detail.text = stats_label.text
		return
	var rows: Array = last_battle_stats
	if rows.is_empty():
		stats_label.text = "第 %d 回合最终统计\n无上场棋子" % last_battle_round
		stats_detail.text = stats_label.text
		return
	var lines := ["上一战 · 回合 %d" % last_battle_round]
	var details: Array = lines.duplicate()
	for metric in [{"key": "damage", "name": "输出"}, {"key": "taken", "name": "承伤"}, {"key": "healing", "name": "治疗"}]:
		var sorted_rows := rows.duplicate()
		var key: String = metric["key"]
		sorted_rows.sort_custom(func(a, b): return float(a[key]) > float(b[key]))
		var places: Array = []
		for index in range(sorted_rows.size()):
			var entry: Dictionary = sorted_rows[index]
			places.append("%d.%s★%d %.0f" % [index + 1, entry["name"], entry["star"], entry[key]])
		lines.append("\n%s\n%s" % [metric["name"], "\n".join(places.slice(0, 3))])
		details.append("\n%s排行\n%s" % [metric["name"], "\n".join(places)])
	stats_label.text = "\n".join(lines)
	stats_detail.text = "\n".join(details)


func _refresh_final_panel() -> void:
	final_panel.visible = game.phase == "finished"
	if not final_panel.visible: return
	var rank := 8
	for entry in game.rankings():
		if int(entry["seat"]) == 0:
			rank = int(entry["rank"])
			break
	final_label.text = "%s\n最终排名：第 %d 名\n坚持到第 %d 回合\n信使剩余生命：%d" % [
		"胜利！" if rank == 1 else "棋局结束", rank, game.round_number, game.players[0]["hp"]]


func _refresh() -> void:
	_update_local_battle_feedback()
	audio.set_phase("menu" if difficulty_panel.visible else game.phase)
	var player: Dictionary = game.players[viewed_seat]
	_update_timer_label()
	status_label.visible = false
	round_label.text = "回合 %d" % game.round_number
	capacity_label.text = "%d / %d" % [player["board"].size(), int(player["level"])]
	var result: Dictionary = game.last_results.get(0, game.last_results.get("0", {}))
	var outcome := "平局" if result.get("tie", false) else "胜利" if result.get("win", false) else "失败"
	round_feedback.visible = game.phase == "settlement" and not result.is_empty() and viewed_seat == 0
	if round_feedback.visible:
		round_feedback.get_node("Content/Title").text = outcome
		round_feedback.get_node("Content/Title").modulate = Color(0.45, 0.95, 0.68) if result.get("win", false) else Color(0.95, 0.55, 0.40) if not result.get("tie", false) else Color(0.80, 0.85, 0.90)
		round_feedback.get_node("Content/Detail").text = "回合 %d · 损失 %d HP · 剩余 %d HP%s" % [game.round_number, int(result.get("damage", 0)), int(result.get("hp", 0)), "\n宝箱可选装备，请在结算结束前领取" if not game.chest_choices.is_empty() else ""]
	result_label.text = "上一战：%s · 损失 %d HP" % [outcome, int(result.get("damage", 0))] if not result.is_empty() and game.phase != "battle" else "战斗进行中" if game.phase == "battle" else "准备中"
	if game.phase == "finished":
		var summary: Array = []
		for entry in game.rankings(): summary.append("第 %d 名：席位 %d" % [entry["rank"], int(entry["seat"]) + 1])
		result_label.text = "棋局结束 | " + "，".join(summary)
	if viewed_seat != 0: result_label.text = "正在查看席位 %d 的阵容和经济" % (viewed_seat + 1)
	var viewed_replay: Dictionary = game.seat_replay(viewed_seat)
	opponent_label.text = "对战 · %s" % str(viewed_replay.get("opponent", "待匹配")) if game.phase == "battle" else "我的棋盘" if viewed_seat == 0 else "观战 · 电脑 %d" % viewed_seat
	_refresh_traits()
	_refresh_board()
	_refresh_stats_panel()
	_refresh_final_panel()
	equipment_hint_label.text = "观战中：对手的装备库不展示" if viewed_seat != 0 else "战斗中可整理装备、给棋子佩戴；下回合才生效" if game.phase == "battle" else "拖到棋子佩戴；拖回装备栏卸下"
	screen.get_node("Inventory").tooltip_text = equipment_hint_label.text
	var xp_threshold := 0
	if int(player["level"]) < 10:
		xp_threshold = int(game.content["economy"]["xp_thresholds"][int(player["level"]) - 1])
	if displayed_level_seat == viewed_seat and displayed_level > 0 and int(player["level"]) > displayed_level:
		level_feedback.trigger(int(player["level"]))
	displayed_level_seat = viewed_seat
	displayed_level = int(player["level"])
	economy_label.text = "等级 %d" % int(player["level"])
	xp_caption.text = "经验 %d/%d" % [player["xp"], xp_threshold] if xp_threshold > 0 else "经验已满级"
	xp_progress.max_value = maxf(1.0, xp_threshold)
	xp_progress.value = player["xp"] if xp_threshold > 0 else 1.0
	gold_label.text = "金币 %d" % int(player["gold"])
	var odds_lines := ["商店各等级：1～5 金棋子出现概率"]
	for level in range(1, 11):
		var odds: Array = game.content["shop_odds_by_level"][str(level)]
		odds_lines.append("%s%d 级：%d%% / %d%% / %d%% / %d%% / %d%%" % [
			"▶ " if level == int(player["level"]) else "", level,
			int(odds[0]), int(odds[1]), int(odds[2]), int(odds[3]), int(odds[4])])
	economy_label.tooltip_text = "\n".join(odds_lines)
	screen.get_node("Shop/Heading/Streak").set_streak(int(player["streak"]))
	extend_preparation_button.text = "延长备战 15 秒"
	extend_preparation_button.disabled = viewed_seat != 0 or game.phase != "preparation" or game_paused or preparation_seconds_total >= 60
	start_battle_button.disabled = viewed_seat != 0 or game.phase != "preparation" or game_paused
	pause_button.text = "继续" if game_paused else "暂停"
	var hp_values: Array = battle_courier_hp if game.phase == "battle" and battle_courier_hp.size() == 8 else []
	for seat in range(8):
		var seat_hp := int(hp_values[seat]) if hp_values.size() == 8 else int(game.players[seat]["hp"])
		seat_buttons[seat].text = "%s%s  ·  Lv %d  ·  %d HP" % ["▶ " if viewed_seat == seat else "", "玩家" if seat == 0 else "电脑 %d" % seat, int(game.players[seat]["level"]), seat_hp]
		seat_buttons[seat].set_player(seat, int(game.players[seat]["level"]), seat_hp, viewed_seat == seat)
	return_view_button.visible = viewed_seat != 0
	var locked: bool = player["shop_locked"]
	shop_lock_label.text = "已锁定 · 下回合保留" if locked else "下回合自动刷新"
	shop_lock_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3) if locked else Color(0.64, 0.69, 0.75))
	lock_button.text = "解锁" if locked else "锁店"
	lock_button.disabled = viewed_seat != 0 or game_paused or game.phase not in ["preparation", "battle"]
	reroll_button.disabled = viewed_seat != 0 or game_paused or game.phase not in ["preparation", "battle"]
	xp_button.disabled = viewed_seat != 0 or game_paused or game.phase not in ["preparation", "battle"]
	disassembly_tool.disabled = viewed_seat != 0 or game_paused or game.phase not in ["preparation", "battle"]
	for index in range(5):
		var name: String = player["shop"][index] if viewed_seat == 0 else ""
		var can_merge := name != "" and game._can_merge_with(name, player)
		var owned := false
		if name != "":
			for piece in player["bench"]:
				if piece["id"] == name: owned = true
			for piece in player["board"].values():
				if piece["id"] == name: owned = true
		shop_buttons[index].text = "%d. 已售" % [index + 1] if name == "" else "%s\n%s\n● %d 金" % [
			game.units[name]["name_zh"], " · ".join(_unit_tags(game.units[name])), game.units[name]["cost"]]
		if viewed_seat != 0: shop_buttons[index].text = "对手商店不展示"
		if can_merge: shop_buttons[index].text += "\n★ 可升星"
		elif owned: shop_buttons[index].text += "\n◇ 已拥有"
		if locked: shop_buttons[index].text = "🔒 " + shop_buttons[index].text
		shop_buttons[index].self_modulate = Color.WHITE
		_set_cost_font(shop_buttons[index], _cost_color(int(game.units[name]["cost"])) if name != "" else Color.WHITE)
		_set_shop_frame(shop_buttons[index], "merge" if can_merge else "owned" if owned else "normal")
		shop_buttons[index].tooltip_text = "" if name == "" else _piece_tooltip({"id": name, "star": 1, "items": []})
		shop_buttons[index].disabled = viewed_seat != 0 or game_paused or game.phase not in ["preparation", "battle"] or name == ""
		var affordable := name != "" and int(player["gold"]) >= int(game.units[name]["cost"])
		shop_buttons[index].set_offer(game.units[name] if name != "" else {}, _unit_tags(game.units[name]) if name != "" else [],
			"可升星" if can_merge else "已拥有" if owned else "", affordable and not shop_buttons[index].disabled)
	var bench_player: Dictionary = player
	battle_scene.sync_bench(bench_player["bench"], game._bench_layout(bench_player))
	battle_scene.set_selection(_game_to_visual(selected_board) if selected_board >= 0 else -1, selected_bench)
	board_screen._schedule_layout()
	for index in range(8):
		var label := "%d. 空" % [index + 1]
		bench_buttons[index].tooltip_text = "空备战位"
		var bench_index := game.bench_index_at_slot(viewed_seat, index)
		if bench_index >= 0:
			var piece: Dictionary = bench_player["bench"][bench_index]
			label = "%s\n★%d · 装备%d" % [game.units[piece["id"]]["name_zh"], piece["star"], piece["items"].size()]
			bench_buttons[index].tooltip_text = _piece_tooltip(piece)
		bench_buttons[index].text = ("▶ " if selected_bench == index else "") + label
		bench_buttons[index].set_selected(selected_bench == index)
		bench_buttons[index].set_piece(str(bench_player["bench"][bench_index]["id"]) if bench_index >= 0 else "",
			str(game.units[bench_player["bench"][bench_index]["id"]]["name_zh"]) if bench_index >= 0 else "", int(bench_player["bench"][bench_index]["star"]) if bench_index >= 0 else 0)
		_set_cost_font(bench_buttons[index], _cost_color(int(game.units[bench_player["bench"][bench_index]["id"]]["cost"])) if bench_index >= 0 else Color.WHITE)
		bench_buttons[index].self_modulate = Color.WHITE
		bench_buttons[index].disabled = game.phase not in ["preparation", "battle"]
		_set_bench_items(index, bench_player["bench"][bench_index]["items"] if bench_index >= 0 else [])
	for node in item_list.get_children(): node.queue_free()
	for index in range(bench_player["inventory"].size() if viewed_seat == 0 else 0):
		var item: Dictionary = bench_player["inventory"][index]
		var icon: Button = _drag_button(item_list, "▶" if selected_item == index else "", "inventory", index)
		icon.icon = _icon_texture(item["id"])
		icon.expand_icon = true
		icon.custom_minimum_size = Vector2(43, 43)
		icon.add_theme_constant_override("icon_max_width", 32)
		icon.add_theme_stylebox_override("normal", Assets.frame(Color(0.29, 0.40, 0.45)))
		icon.tooltip_text = _item_tooltip(item)
		icon.pressed.connect(_item_pressed.bind(index))
	if viewed_seat == 0:
		for index in range(maxi(0, 8 - bench_player["inventory"].size())):
			var empty_slot := PanelContainer.new()
			empty_slot.custom_minimum_size = Vector2(43, 43)
			empty_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_slot.add_theme_stylebox_override("panel", Assets.frame(Color(0.20, 0.29, 0.34), 1, Color(0.02, 0.04, 0.06, 0.5)))
			item_list.add_child(empty_slot)
	for node in chest_row.get_children(): node.queue_free()
	chest_panel.visible = game.phase != "battle" and not game.chest_choices.is_empty()
	for index in range(0 if game.phase == "battle" else game.chest_choices.size()):
		var item_id: String = game.chest_choices[index]
		var button := _button(chest_row, "宝箱：%s" % game.content["items"][item_id]["name"], _pick_chest.bind(index))
		button.tooltip_text = _item_tooltip({"id": item_id})
	log_box.text = "\n".join(game.event_log.slice(0, int(game.battle_replay.get("starting_log_size", game.event_log.size())))) if game.phase == "battle" else "\n".join(game.event_log)
	var preview_id := "Axe"
	var preview_star := 1
	if selected_board >= 0 and player["board"].has(selected_board):
		preview_id = player["board"][selected_board]["id"]
		preview_star = int(player["board"][selected_board]["star"])
	elif selected_bench >= 0 and game.bench_index_at_slot(viewed_seat, selected_bench) >= 0:
		var bench_index := game.bench_index_at_slot(viewed_seat, selected_bench)
		preview_id = player["bench"][bench_index]["id"]
		preview_star = int(player["bench"][bench_index]["star"])
	var current_key := "%s:%d" % [preview_id, preview_star]
	if current_key != preview_key:
		preview_scene.call("set_piece", preview_id, preview_star)
		preview_key = current_key


func drag_data(kind: String, index: int, extra: int) -> Dictionary:
	if viewed_seat != 0 or game_paused or game.phase not in ["preparation", "battle"]: return {}
	var player: Dictionary = game.players[0]
	match kind:
		"disassembly_tool":
			return {"kind": kind, "index": -1}
		"board":
			if player["board"].has(index): return {"kind": kind, "index": index}
		"bench":
			if game.bench_index_at_slot(0, index) >= 0: return {"kind": kind, "index": index}
		"battle_actor":
			var origin := _battle_actor_origin(index)
			if origin >= 0 and player["board"].has(origin): return {"kind": "board", "index": origin}
		"inventory":
			if index >= 0 and index < player["inventory"].size():
				craft_preview_label.text = "将装备拖到另一件装备上查看合成结果"
				return {"kind": kind, "index": index}
		"equipped_board":
			if player["board"].has(index) and extra >= 0 and extra < player["board"][index]["items"].size():
				return {"kind": kind, "index": index, "extra": extra}
		"equipped_bench":
			var bench_index := game.bench_index_at_slot(0, index)
			if bench_index >= 0 and extra >= 0 and extra < player["bench"][bench_index]["items"].size():
				return {"kind": kind, "index": index, "extra": extra}
	return {}


func _battle_actor_origin(uid: int) -> int:
	var frames: Array = game.battle_replay.get("frames", [])
	if frames.is_empty(): return -1
	for actor in frames[mini(battle_frame_index, frames.size() - 1)]["actors"]:
		if int(actor["uid"]) == uid and int(actor["team"]) == int(game.battle_replay["player_team"]) and not actor["summon"]:
			return int(actor.get("origin", -1))
	return -1


func can_drop(data: Dictionary, target_kind: String, target_index: int, _extra: int) -> bool:
	if viewed_seat != 0 or game_paused or game.phase not in ["preparation", "battle"]: return false
	var player: Dictionary = game.players[0]
	var source_kind := str(data.get("kind", ""))
	var source_index := int(data.get("index", -1))
	if source_kind == "disassembly_tool":
		if target_kind == "battle_actor":
			target_kind = "board"
			target_index = _battle_actor_origin(target_index)
		if target_kind == "inventory":
			return target_index >= 0 and target_index < player["inventory"].size() and game._base_parts(player["inventory"][target_index]).size() > 1
		if target_kind in ["board", "equipped_board"]:
			if not player["board"].has(target_index): return false
			var items: Array = player["board"][target_index]["items"]
			return _extra >= 0 and _extra < items.size() if target_kind == "equipped_board" else not items.is_empty()
		if target_kind in ["bench", "equipped_bench"]:
			var actual := game.bench_index_at_slot(0, target_index)
			if actual < 0: return false
			var items: Array = player["bench"][actual]["items"]
			return _extra >= 0 and _extra < items.size() if target_kind == "equipped_bench" else not items.is_empty()
		return false
	if game.phase == "battle" and source_kind in ["board", "bench"] and target_kind != "sell":
		if source_kind != "bench" or target_kind not in ["bench", "equipped_bench"]: return false
	if target_kind == "sell": return source_kind in ["board", "bench"]
	if target_kind == "battle_actor":
		target_kind = "board"
		target_index = _battle_actor_origin(target_index)
	if target_kind == "inventory":
		if source_kind == "inventory" and source_index >= 0 and source_index < player["inventory"].size() and target_index >= 0 and target_index < player["inventory"].size():
			var candidates := _craft_candidates(player["inventory"][source_index], player["inventory"][target_index]) if source_index != target_index else []
			var names: Array = []
			for candidate in candidates: names.append(candidate["name"])
			craft_preview_label.text = "可合成：" + "、".join(names) if not names.is_empty() else "无合成路线；松开可调整装备位置"
		return source_kind in ["inventory", "equipped_board", "equipped_bench"]
	if target_kind == "equipped_board": target_kind = "board"
	if target_kind == "equipped_bench": target_kind = "bench"
	if target_kind not in ["board", "bench"]: return false
	if target_kind == "board" and (target_index < 0 or target_index >= 32): return false
	if target_kind == "bench" and (target_index < 0 or target_index >= 8): return false
	var target_bench_index := game.bench_index_at_slot(0, target_index) if target_kind == "bench" else -1
	var target_has_piece: bool = player["board"].has(target_index) if target_kind == "board" else target_bench_index >= 0
	if source_kind in ["inventory", "equipped_board", "equipped_bench"]:
		if not target_has_piece: return false
		var piece: Dictionary = player["board"][target_index] if target_kind == "board" else player["bench"][target_bench_index]
		if (source_kind == "equipped_board" and target_kind == "board" and source_index == target_index) or \
			(source_kind == "equipped_bench" and target_kind == "bench" and source_index == target_index):
			var moving_index := int(data.get("extra", -1))
			if moving_index < 0 or moving_index >= piece["items"].size(): return false
			for existing_index in range(piece["items"].size()):
				if existing_index != moving_index and not game._pair_product(piece["items"][existing_index], piece["items"][moving_index]).is_empty(): return true
			return false
		if piece["items"].size() < 6: return true
		var moving: Dictionary = {}
		if source_kind == "inventory" and source_index >= 0 and source_index < player["inventory"].size(): moving = player["inventory"][source_index]
		elif source_kind == "equipped_board" and player["board"].has(source_index) and int(data.get("extra", -1)) >= 0 and int(data.get("extra", -1)) < player["board"][source_index]["items"].size(): moving = player["board"][source_index]["items"][int(data["extra"])]
		elif source_kind == "equipped_bench":
			var actual := game.bench_index_at_slot(0, source_index)
			if actual >= 0 and int(data.get("extra", -1)) >= 0 and int(data.get("extra", -1)) < player["bench"][actual]["items"].size(): moving = player["bench"][actual]["items"][int(data["extra"])]
		if moving.is_empty(): return false
		for existing in piece["items"]:
			if not game._pair_product(existing, moving).is_empty(): return true
		return false
	if source_kind not in ["board", "bench"]: return false
	if source_kind == "board" and not player["board"].has(source_index): return false
	if source_kind == "bench" and game.bench_index_at_slot(0, source_index) < 0: return false
	if target_kind == "bench" and not target_has_piece and source_kind == "board" and player["bench"].size() >= 8: return false
	return true


func handle_drop(data: Dictionary, target_kind: String, target_index: int, extra: int) -> void:
	var hint: Dictionary = operation_feedback.describe(data, target_kind, target_index, extra)
	var at: Vector2 = get_global_mouse_position()
	if not hint["allowed"]:
		operation_feedback.message(hint["text"], at, operation_feedback.RED)
		return
	var before: Dictionary = operation_feedback.snapshot()
	if data["kind"] == "disassembly_tool":
		if target_kind == "battle_actor":
			target_kind = "board"
			target_index = _battle_actor_origin(target_index)
		if target_kind == "inventory": game.dismantle(0, target_index)
		elif target_kind == "equipped_board":
			if not game.dismantle_equipped(0, true, target_index, extra): game.unequip(0, true, target_index, extra)
		elif target_kind == "equipped_bench":
			var actual := game.bench_index_at_slot(0, target_index)
			if not game.dismantle_equipped(0, false, actual, extra): game.unequip(0, false, actual, extra)
		elif target_kind == "board": game.unequip_all(0, true, target_index)
		elif target_kind == "bench": game.unequip_all(0, false, game.bench_index_at_slot(0, target_index))
		_refresh()
		operation_feedback.message(str(hint["text"]), at, hint["color"])
		return
	if target_kind == "battle_actor":
		target_kind = "board"
		target_index = _battle_actor_origin(target_index)
	var source_kind := str(data["kind"])
	var source_index := int(data["index"])
	var copied_io := false
	if target_kind == "sell":
		if game.sell(0, source_kind == "board", game.bench_index_at_slot(0, source_index) if source_kind == "bench" else source_index): audio.ui("sell")
	elif target_kind == "inventory":
		if source_kind == "equipped_board": game.unequip(0, true, source_index, int(data["extra"]))
		elif source_kind == "equipped_bench": game.unequip(0, false, game.bench_index_at_slot(0, source_index), int(data["extra"]))
		elif source_kind == "inventory" and source_index != target_index:
			var inventory: Array = game.players[0]["inventory"]
			var candidates := _craft_candidates(inventory[source_index], inventory[target_index])
			if not candidates.is_empty() and game.craft(0, candidates[0]["id"], candidates[0]["level"]):
				craft_preview_label.text = "已合成：%s" % candidates[0]["name"]
			else:
				var item: Dictionary = inventory.pop_at(source_index)
				inventory.insert(mini(target_index, inventory.size()), item)
	else:
		if target_kind == "equipped_board": target_kind = "board"
		if target_kind == "equipped_bench": target_kind = "bench"
		if source_kind in ["board", "bench"]:
			var from_actual := game.bench_index_at_slot(0,source_index) if source_kind == "bench" else source_index
			var to_actual := game.bench_index_at_slot(0,target_index) if target_kind == "bench" else target_index
			if game.can_copy_io(0,source_kind=="board",from_actual,target_kind=="board",to_actual):
				copied_io = game.copy_io(0,source_kind=="board",from_actual,target_kind=="board",to_actual)
			else: game.move_piece_slot(0, source_kind == "board", source_index, target_kind == "board", target_index)
		elif source_kind == "inventory":
			game.equip(0, source_index, target_kind == "board", game.bench_index_at_slot(0, target_index) if target_kind == "bench" else target_index)
		elif source_kind in ["equipped_board", "equipped_bench"]:
			if (source_kind == "equipped_board" and target_kind == "board" and source_index == target_index) or \
				(source_kind == "equipped_bench" and target_kind == "bench" and source_index == target_index):
				game.combine_equipped(0, target_kind == "board", game.bench_index_at_slot(0, target_index) if target_kind == "bench" else target_index,
					int(data["extra"]))
			else:
				game.transfer_item(0, source_kind == "equipped_board", game.bench_index_at_slot(0, source_index) if source_kind == "equipped_bench" else source_index,
					int(data["extra"]), target_kind == "board", game.bench_index_at_slot(0, target_index) if target_kind == "bench" else target_index)
	selected_board = -1
	selected_bench = -1
	selected_item = -1
	_refresh()
	var upgraded: String = operation_feedback.pulse_changes(before)
	if copied_io: audio.skill("io", "combine", Vector2(3.5,3.5), float(Time.get_ticks_msec()) / 1000)
	if upgraded != "" and not copied_io: audio.ui("upgrade")
	operation_feedback.message(upgraded if upgraded != "" and not copied_io else str(hint["text"]), at, hint["color"])
