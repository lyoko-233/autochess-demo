extends Control

const Cell = preload("res://scripts/ui/board_cell.gd")
var cells: Array = []
var hp_bars: Array = []
var mana_bars: Array = []
var item_rows: Array = []
var captions: Array = []
var mode := ""
var controller: Control


func _ready() -> void:
	resized.connect(_schedule_layout)
	$View/World.size_changed.connect(_schedule_layout)


func configure(owner_controller: Control) -> void:
	controller = owner_controller
	for index in range(64):
		var cell = Cell.new()
		cell.controller = controller
		cell.kind = "board"
		cell.index = controller._visual_to_game(index)
		cell.pressed.connect(controller._board_pressed.bind(cell.index))
		$Interaction.add_child(cell)
		cells.append(cell)
		cell.mouse_entered.connect(_update_caption.bind(index))
		cell.mouse_exited.connect(_update_caption.bind(index))
		hp_bars.append(controller._bar(cell, 0, Color(0.23, 0.8, 0.42)))
		mana_bars.append(controller._bar(cell, 7, Color(0.3, 0.61, 0.95)))
		var caption := Label.new()
		caption.name = "Caption"
		caption.add_theme_font_size_override("font_size", 12)
		caption.add_theme_color_override("font_outline_color", Color(0.015, 0.035, 0.05))
		caption.add_theme_constant_override("outline_size", 2)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(caption)
		captions.append(caption)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		cell.add_child(row)
		item_rows.append(row)
	_schedule_layout()


func set_caption(index: int, value: String, is_selected: bool) -> void:
	cells[index].set_meta("caption", value)
	cells[index].selected = is_selected
	_update_caption(index)
	cells[index].queue_redraw()


func _update_caption(index: int) -> void:
	var value: String = cells[index].get_meta("caption", "")
	captions[index].text = value if cells[index].selected or cells[index].is_hovered() else value.get_slice(" ", 0) if value.begins_with("★") else ""


func set_replay(active: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	$Interaction.visible = not active
	$Actors.visible = active
	var next_mode := "battle" if active else "preparation"
	if next_mode != mode:
		$View/World/BattleScene.reset()
		mode = next_mode


# Pick the visible body's projected bounds, rather than its old deployment tile.
func battle_actor_at(at: Vector2) -> int:
	if mode != "battle" or controller == null: return -1
	var scene = $View/World/BattleScene
	var view_scale := size / Vector2($View/World.size)
	var picked := -1
	var nearest := INF
	for uid in scene.pieces:
		var piece: Node3D = scene.pieces[uid]
		if not piece.visible or controller._battle_actor_origin(int(uid)) < 0: continue
		var foot: Vector2 = scene.camera.unproject_position(piece.global_position) * view_scale
		var head: Vector2 = scene.project_actor(int(uid)) * view_scale
		var radius := maxf(12, absf(foot.y - head.y) * .42)
		var rect := Rect2(Vector2(minf(foot.x,head.x)-radius, minf(foot.y,head.y)-5), Vector2(absf(foot.x-head.x)+radius*2,absf(foot.y-head.y)+10))
		if rect.has_point(at):
			var distance := at.distance_squared_to(rect.get_center())
			if distance < nearest:
				nearest = distance
				picked = int(uid)
	return picked


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	var uid := battle_actor_at(at)
	return uid >= 0 and typeof(data) == TYPE_DICTIONARY and controller.operation_feedback.target(data,"battle_actor",uid,-1,self)


func _drop_data(at: Vector2, data: Variant) -> void:
	var uid := battle_actor_at(at)
	if uid >= 0: controller.handle_drop(data,"battle_actor",uid,-1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and controller != null and controller.selected_item >= 0:
		var uid := battle_actor_at(event.position)
		if uid >= 0:
			controller.handle_drop({"kind":"inventory","index":controller.selected_item},"battle_actor",uid,-1)
			accept_event()


func _schedule_layout() -> void:
	_layout_cells.call_deferred()


func _layout_cells() -> void:
	if cells.is_empty() or not is_inside_tree(): return
	var camera: Camera3D = $View/World/BattleScene.camera
	# Match the four inner board corners painted into the 1536x1024 backdrop.
	var backdrop: Control=get_parent().get_node("Horizon")
	var cover := maxf(backdrop.size.x/1536.0,backdrop.size.y/1024.0)
	var crop := (backdrop.size-Vector2(1536,1024)*cover)/2.0
	var origin := backdrop.global_position+crop-global_position
	var top := Vector2(415,226)*cover+origin
	var bottom := Vector2(300,742)*cover+origin
	var top_width := (1120.0-415.0)*cover
	var bottom_width := (1232.0-300.0)*cover
	var viewport_size := Vector2($View/World.size)
	if viewport_size.x < 1 or viewport_size.y < 1 or top_width < 1: return
	var ratio := bottom_width/top_width
	var k := 4.0*(ratio+1.0)/(ratio-1.0)
	var sine := ((bottom.y-viewport_size.y/2.0)*(k-4.0)-(top.y-viewport_size.y/2.0)*(k+4.0))/(top_width*(k+4.0))
	sine=clampf(sine,.1,.95)
	var cosine := sqrt(1.0-sine*sine)
	var distance := k*cosine
	var focal := top_width*cosine*(k+4.0)/8.0
	camera.fov=rad_to_deg(2.0*atan(viewport_size.x/(2.0*focal)))
	camera.position=Vector3(0,distance*sine,distance*cosine)
	camera.look_at(Vector3.ZERO)
	camera.v_offset=8.0*(top.y-viewport_size.y/2.0)/top_width+4.0*sine
	camera.h_offset=-8.0*(top.x+top_width/2.0-viewport_size.x/2.0)/top_width
	for index in range(64):
		var col := index % 8
		var row := index / 8
		var points := PackedVector2Array()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			points.append(camera.unproject_position(Vector3(float(col) - 4 + corner.x, 0.02, float(row) - 4 + corner.y)))
		var rect := Rect2(points[0], Vector2.ZERO)
		for point in points: rect = rect.expand(point)
		var cell: Control = cells[index]
		cell.position = rect.position
		cell.size = rect.size
		var local := PackedVector2Array()
		for point in points: local.append(point - rect.position)
		cell.hit_polygon = local
		var piece: Node3D = $View/World/BattleScene.pieces.get(-index - 1)
		var height := float(piece.get_meta("head_height", 1.2)) if piece != null else 1.2
		var head := camera.unproject_position(Vector3(float(col) - 3.5, height, float(row) - 3.5)) - rect.position
		captions[index].position = head - Vector2(60, 20)
		captions[index].size = Vector2(120, 25)
		for bar_index in range(2):
			var bar: ProgressBar = hp_bars[index] if bar_index == 0 else mana_bars[index]
			bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
			bar.position = head + Vector2(-22, 3 + 6 * bar_index)
			bar.size = Vector2(44, 4)
		item_rows[index].position = head + Vector2(-20, 7)
		cell.queue_redraw()
	for index in range($BenchInteraction.get_child_count()):
		var slot: Control = $BenchInteraction.get_child(index)
		var left := camera.unproject_position(Vector3(index - 4.0, 0, 4.02))
		var right := camera.unproject_position(Vector3(index - 3.0, 0, 4.48))
		slot.position = left
		slot.size = right - left
		slot.custom_minimum_size = Vector2.ZERO
		slot.get_node("Items").scale = Vector2.ONE * minf(1.0, slot.size.x / 90.0)
	if mode == "battle": cells[0].controller._show_battle_frame()
