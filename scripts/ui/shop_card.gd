extends "res://scripts/drag_cell.gd"

const Assets = preload("res://scripts/ui/ui_assets.gd")


func _ready() -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	resized.connect(_fit_details)


func set_offer(unit: Dictionary, tags: Array, badge: String, available: bool) -> void:
	var empty := unit.is_empty()
	$Portrait.visible = not empty
	$PortraitBackdrop.visible = not empty
	$Details/Name.text = "已售出" if empty else str(unit["name_zh"])
	$Details/Tags.text = "等待下次刷新" if empty else " · ".join(tags)
	$Details/PriceRow/Price.text = "" if empty else str(int(unit["cost"]))
	$Details/PriceRow.visible = not empty
	$Details/PriceRow/Icon.texture = Assets.icon("coin")
	$Badge.text = "拥有" if badge == "已拥有" else badge
	$Badge.visible = badge != ""
	$Badge.add_theme_font_size_override("font_size", 12 if badge == "已拥有" else 15)
	$Badge.add_theme_color_override("font_color", Color(0.72, 0.80, 0.83) if badge == "已拥有" else Assets.GOLD)
	if not empty: $Portrait.texture = Assets.portrait(str(unit["name_en"]))
	$Portrait.modulate = Color.WHITE if available else Color(0.45, 0.49, 0.52)
	_fit_details()
	_fit_details.call_deferred()


func _fit_details() -> void:
	var labels := [$Details/Name, $Details/Tags, $Details/PriceRow/Price]
	var sizes := [16, 12, 16]
	var text_width := 0.0
	for index in range(labels.size()):
		text_width += labels[index].get_theme_font("font").get_string_size(labels[index].text, HORIZONTAL_ALIGNMENT_LEFT, -1, sizes[index]).x
	var scale_value := minf(1.0, maxf(1.0, size.x - 46.0) / maxf(1.0, text_width))
	for index in range(labels.size()):
		labels[index].add_theme_font_size_override("font_size", maxi(1, int(sizes[index] * scale_value)))


func set_cost_color(color: Color) -> void:
	$Details/Name.add_theme_color_override("font_color", color)
	$Details/Tags.add_theme_color_override("font_color", color)


func set_frame(state: String) -> void:
	var color := Assets.GOLD if state == "merge" else Assets.COSTS[2] if state == "owned" else Color(0.34, 0.44, 0.49)
	add_theme_stylebox_override("normal", Assets.frame(color, 3 if state == "merge" else 2 if state == "owned" else 1))
	add_theme_stylebox_override("hover", Assets.frame(color.lightened(0.3), 4 if state == "merge" else 2, Color(0.09, 0.16, 0.21)))
	add_theme_stylebox_override("pressed", Assets.frame(color, 3 if state == "merge" else 2, Color(0.03, 0.06, 0.09)))
	add_theme_stylebox_override("disabled", Assets.frame(color.darkened(0.5), 1, Color(0.025, 0.045, 0.065)))
