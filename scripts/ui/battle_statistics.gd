extends PanelContainer

var round_number := 0
var rows: Array = []
var metric := "damage"


func _ready() -> void:
	for key in ["damage", "taken", "healing"]:
		$Content/Tabs.get_node(key).pressed.connect(_select.bind(key))


func _select(key: String) -> void:
	metric = key
	_render()


func set_statistics(round_value: int, values: Array) -> void:
	round_number = round_value
	rows = values
	_render()


func _render() -> void:
	$Content/Title.text = "上一战 · 回合 %d" % round_number if round_number > 0 else "上一战"
	$Content/Empty.visible = rows.is_empty()
	$Content/Ranking.visible = not rows.is_empty()
	for key in ["damage", "taken", "healing"]:
		$Content/Tabs.get_node(key).button_pressed = key == metric
	for child in $Content/Ranking.get_children(): child.queue_free()
	var ordered := rows.duplicate()
	ordered.sort_custom(func(a, b): return float(a[metric]) > float(b[metric]))
	for index in range(mini(3, ordered.size())):
		var row: Dictionary = ordered[index]
		var name_label := Label.new()
		name_label.text = "%s %s" % [row["name"], "★".repeat(int(row["star"]))]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 80
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.tooltip_text = "%s · %s星" % [row["name"], row["star"]]
		$Content/Ranking.add_child(name_label)
		var number := Label.new()
		number.text = "%.0f" % float(row[metric])
		number.theme_type_variation = &"HUDNumber"
		number.add_theme_font_size_override("font_size", 16)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		$Content/Ranking.add_child(number)
