extends Control
# Main menu and illustrated codex V3 — updated 2026-11-07.
const Assets = preload("res://scripts/ui/ui_assets.gd")
var controller: Control
var content: VBoxContainer
var heading: Label
var back_button: Button
var page := "home"
var grid: GridContainer
var search: LineEdit
var catalogue_kind := 0
var menu_panel: PanelContainer
var codex_body: VBoxContainer
var catalogue_grids := {}
var catalogue_tabs: Array[Button] = []
var empty_hint: Label
var loading_hint: Label
var hero_cards_loading := false
const GOLD := Color(0.93, 0.76, 0.39)
const MUTED := Color(0.64, 0.75, 0.79)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := TextureRect.new()
	background.texture = preload("res://assets/ui/moonlit_forest.png")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.05, 0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.08
	panel.anchor_top = 0.08
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.92
	var style = Assets.frame(Color(0.33, 0.44, 0.46), 1, Color(0.025, 0.055, 0.075, 0.97))
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	menu_panel = panel
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	heading = label("", 28, GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	back_button = button(header, "返回主菜单", show_home)
	layout.add_child(HSeparator.new())
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	layout.add_child(content)
	resized.connect(func(): _layout_panel(); _resize_grid())
	show_home()

func label(text_value: String, font_size: int = 16, color: Color = Color.WHITE) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

func paragraph(parent: Node, text_value: String, color: Color = MUTED) -> Label:
	var node := label(text_value, 16, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node

func button(parent: Node, text_value: String, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size", 17)
	node.add_theme_stylebox_override("normal", Assets.frame(GOLD if primary else Color(0.24, 0.36, 0.41), 1, Color(0.16, 0.21, 0.20) if primary else Color(0.055, 0.10, 0.13)))
	node.add_theme_stylebox_override("hover", Assets.frame(GOLD, 1, Color(0.12, 0.20, 0.23)))
	node.add_theme_stylebox_override("focus", Assets.frame(GOLD, 2, Color(0, 0, 0, 0)))
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func clear_page(title: String, key: String) -> void:
	page = key
	heading.text = title
	back_button.visible = key != "home"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if key == "home" else HORIZONTAL_ALIGNMENT_LEFT
	_layout_panel()
	grid = null
	for child in content.get_children():
		if child == codex_body:
			child.hide()
			continue
		content.remove_child(child)
		child.queue_free()

func save_summary() -> String:
	if not FileAccess.file_exists(controller.game.SAVE_PATH): return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(controller.game.SAVE_PATH))
	if not data is Dictionary or data.get("version") != controller.game.content.version: return ""
	if not data.get("players") is Array or data.players.size() != 8: return ""
	return "第 %d 回合 · 从回合起点继续" % int(data.get("round", 1))

func show_home() -> void:
	clear_page("自走棋demo", "home")
	var actions := VBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	button(actions, "新游戏", show_difficulty, true)
	var resume := button(actions, "继续游戏", func():
		if controller._continue_game(): hide())
	var summary := save_summary()
	resume.disabled = summary.is_empty()
	paragraph(actions, "暂无可继续的存档" if summary.is_empty() else summary)
	button(actions, "设置", show_settings)
	button(actions, "棋子介绍", show_codex)
	button(actions, "退出", func(): get_tree().quit())

func show_difficulty() -> void:
	clear_page("新游戏 · 选择难度", "difficulty")
	paragraph(content, "选择本局 7 名电脑对手的难度。开始后将更新自动存档。")
	for entry in [["简单", "easy", "适合熟悉商店、布阵与羁绊。"], ["中等", "medium", "均衡的对局，适合日常游玩。"], ["困难", "hard", "更强的阵容运营与对抗压力。"]]:
		var difficulty: String = entry[1]
		button(content, entry[0] + "    ·    " + entry[2], func():
			controller._new_game(difficulty)
			hide(), difficulty == "medium")

func show_settings() -> void:
	clear_page("设置 · 声音", "settings")
	paragraph(content, "调整即时生效并自动保存。音量设为 0 即静音。")
	for entry in [["Master", "总音量"], ["GameMusic", "背景音乐"], ["GameSFX", "战斗音效"], ["GameUI", "操作与提示"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		content.add_child(row)
		var caption := label(entry[1])
		caption.custom_minimum_size.x = 130
		row.add_child(caption)
		var slider := HSlider.new()
		slider.custom_minimum_size.y = 44
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.max_value = 100
		slider.step = 1
		var bus: String = entry[0]
		slider.value = float(controller.audio.volumes[bus]) * 100
		row.add_child(slider)
		var value := label("%d%%" % slider.value, 18, GOLD)
		value.custom_minimum_size.x = 60
		row.add_child(value)
		slider.value_changed.connect(func(amount):
			controller.audio.volumes[bus] = amount / 100.0
			controller.audio._apply_volume(bus)
			controller.audio.save_settings()
			value.text = "%d%%" % amount)

func _layout_panel() -> void:
	if not is_instance_valid(menu_panel): return
	if page == "codex":
		menu_panel.anchor_left = 0.08
		menu_panel.anchor_top = 0.08
		menu_panel.anchor_right = 0.92
		menu_panel.anchor_bottom = 0.92
		menu_panel.offset_left = 0
		menu_panel.offset_top = 0
		menu_panel.offset_right = 0
		menu_panel.offset_bottom = 0
	else:
		var dimensions := Vector2(440, 490) if page == "home" else Vector2(720, 430)
		dimensions.x = minf(dimensions.x, size.x - 48)
		dimensions.y = minf(dimensions.y, size.y - 48)
		menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		menu_panel.offset_left = -dimensions.x / 2
		menu_panel.offset_right = dimensions.x / 2
		menu_panel.offset_top = -dimensions.y / 2
		menu_panel.offset_bottom = dimensions.y / 2

func show_codex() -> void:
	clear_page("棋子介绍 · 羁绊与英雄", "codex")
	if is_instance_valid(codex_body):
		codex_body.show()
		grid = catalogue_grids.get(catalogue_kind)
		_select_catalogue(catalogue_kind)
		return
	codex_body = VBoxContainer.new()
	codex_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	codex_body.add_theme_constant_override("separation", 14)
	content.add_child(codex_body)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	codex_body.add_child(tabs)
	for index in range(3):
		catalogue_tabs.append(button(tabs, ["种族羁绊", "职业羁绊", "棋子图鉴"][index], _select_catalogue.bind(index)))
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、种族或职业…"
	search.custom_minimum_size.y = 42
	search.text_changed.connect(func(_value): _fill_catalogue())
	codex_body.add_child(search)
	loading_hint = label("正在载入棋子介绍…", 15, MUTED)
	loading_hint.hide()
	codex_body.add_child(loading_hint)
	empty_hint = label("没有匹配的条目，请换个关键词。", 18, MUTED)
	empty_hint.hide()
	codex_body.add_child(empty_hint)
	var scroll := ScrollContainer.new()
	scroll.name = "CatalogueScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	codex_body.add_child(scroll)
	_select_catalogue(catalogue_kind)

func _select_catalogue(index: int) -> void:
	catalogue_kind = index
	var scroll := codex_body.get_node("CatalogueScroll")
	if is_instance_valid(grid): grid.hide()
	if not catalogue_grids.has(index):
		var new_grid := GridContainer.new()
		new_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		new_grid.add_theme_constant_override("h_separation", 16)
		new_grid.add_theme_constant_override("v_separation", 16)
		catalogue_grids[index] = new_grid
	grid = catalogue_grids[index]
	if grid.get_parent() == null: scroll.add_child(grid)
	grid.show()
	loading_hint.visible = index == 2 and hero_cards_loading
	for i in range(catalogue_tabs.size()):
		catalogue_tabs[i].add_theme_color_override("font_color", GOLD if i == index else Color.WHITE)
	_resize_grid()
	_fill_catalogue()

func _resize_grid() -> void:
	if is_instance_valid(grid): grid.columns = 3 if size.x >= 1450 else 2 if size.x >= 1000 else 1

func card(target: GridContainer = null) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = Assets.frame(Color(0.20, 0.34, 0.39))
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	(grid if target == null else target).add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	return body

func _fill_catalogue() -> void:
	var query := search.text.strip_edges().to_lower()
	if grid.get_child_count() > 0:
		_filter_catalogue(query)
		return
	var units: Array = controller.game.content.units.duplicate()
	units.sort_custom(func(a, b): return a.name_en < b.name_en if a.cost == b.cost else a.cost < b.cost)
	if catalogue_kind == 2:
		if not hero_cards_loading:
			hero_cards_loading = true
			loading_hint.show()
			empty_hint.hide()
			_build_hero_cards.call_deferred(grid, units)
		return
	else:
		var field := "species" if catalogue_kind == 0 else "class"
		var tags := {}
		for unit in units:
			for tag in str(unit[field]).split("、"): tags[tag] = true
		for synergy in controller.game.content.synergies:
			if not tags.has(synergy.tag): continue
			var names: PackedStringArray = []
			for unit in units:
				if synergy.tag in str(unit[field]).split("、"): names.append(unit.name_zh)
			var body := card()
			body.get_parent().set_meta("search", (synergy.tag + " ".join(names)).to_lower())
			body.add_child(label(synergy.tag, 23, GOLD))
			var tiers: PackedStringArray = []
			for tier in synergy.tiers: tiers.append(str(int(tier)))
			paragraph(body, "激活人数  ·  " + " / ".join(tiers), Color(0.62, 0.86, 0.78))
			paragraph(body, synergy.effect_text, Color(0.87, 0.91, 0.90))
			paragraph(body, "成员  ·  " + "、".join(names))
	_filter_catalogue(query)


func _append_hero_card(unit: Dictionary, target: GridContainer) -> void:
	var body := card(target)
	body.get_parent().set_meta("search", (unit.name_zh + unit.name_en + unit.species + unit["class"]).to_lower())
	var art := TextureRect.new()
	art.texture = standing_art(unit.name_en)
	art.custom_minimum_size = Vector2(0, 170)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(art)
	body.add_child(label("%s   ·   %d 金" % [unit.name_zh, unit.cost], 21, Assets.cost_color(int(unit.cost))))
	paragraph(body, "%s  /  %s" % [unit.species, unit["class"]], GOLD)
	paragraph(body, "定位  ·  " + role(unit), Color(0.62, 0.86, 0.78))
	paragraph(body, "技能  ·  " + str(unit.ability.get("summary_zh", "暂无技能介绍")))
	var query := search.text.strip_edges().to_lower()
	body.get_parent().visible = query.is_empty() or query in str(body.get_parent().get_meta("search", ""))

func _build_hero_cards(target: GridContainer, units: Array) -> void:
	var batch_start := Time.get_ticks_usec()
	var count := 0
	for unit in units:
		if not is_instance_valid(target): return
		_append_hero_card(unit, target)
		count += 1
		if count % 3 == 0 or Time.get_ticks_usec() - batch_start >= 6000:
			await get_tree().process_frame
			batch_start = Time.get_ticks_usec()
	hero_cards_loading = false
	loading_hint.hide()
	if grid == target: _filter_catalogue(search.text.strip_edges().to_lower())


func _filter_catalogue(query: String) -> void:
	var matches := 0
	for child in grid.get_children():
		child.visible = query.is_empty() or query in str(child.get_meta("search", ""))
		if child.visible: matches += 1
	empty_hint.visible = matches == 0 and not (catalogue_kind == 2 and hero_cards_loading)

func standing_art(piece_id: String) -> Texture2D:
	return preload("res://scripts/ui/model_portraits.gd").portrait(piece_id)


func _exit_tree() -> void:
	for cached_grid in catalogue_grids.values():
		if is_instance_valid(cached_grid) and cached_grid.get_parent() == null: cached_grid.free()


func role(unit: Dictionary) -> String:
	if unit.name_en in ["Axe", "Pudge", "Treant Protector", "Mars", "Abaddon", "Tidehunter"]: return "坦克 · 前排承伤 / 控制"
	var job: String = unit["class"]
	if "刺客" in job: return "刺客 · 突袭后排"
	if "猎人" in job: return "射手 · 持续输出"
	if "法师" in job: return "法师 · 技能输出"
	if "牧师" in job or "萨满" in job or "巫师" in job: return "辅助 · 治疗 / 控制"
	if "德鲁伊" in job or "术士" in job: return "辅助 / 施法 · 续航与召唤"
	if "骑士" in job: return "骑士 · 前排 / 持续作战"
	if "战士" in job: return "战士 · 近战输出 / 承伤"
	if "工匠" in job: return "工匠 · 技能输出 / 前排"
	return "斗士 · 持续输出"

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and page != "home":
		show_home()
		get_viewport().set_input_as_handled()
