extends "res://scripts/drag_cell.gd"

var hit_polygon := PackedVector2Array()
var selected := false


func _ready() -> void:
	flat = true
	for state in ["normal", "hover", "pressed", "disabled", "focus"]: add_theme_stylebox_override(state, StyleBoxEmpty.new())
	set_cost_color(Color.WHITE)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_cost_color(color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	if has_node("Caption"): $Caption.add_theme_color_override("font_color", color)


func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, hit_polygon) if hit_polygon.size() > 2 else false


func _draw() -> void:
	pass # Keep polygon hit testing without a visual cell overlay.
