extends "res://scripts/drag_cell.gd"

const Assets = preload("res://scripts/ui/ui_assets.gd")


func _ready() -> void:
	set_selected(false)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)


func set_piece(piece_id: String, caption: String, star_value: int) -> void:
	$Portrait.visible = false
	$Name.text = ""
	$Stars.text = "★".repeat(star_value) if piece_id != "" else ""


func set_cost_color(color: Color) -> void:
	$Name.add_theme_color_override("font_color", color)
	$Stars.add_theme_color_override("font_color", Assets.GOLD)


func set_selected(_value: bool) -> void:
	for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())


func _draw() -> void:
	pass # Bench models indicate occupied slots; no drag grid outline.
