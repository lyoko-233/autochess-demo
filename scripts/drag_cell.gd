extends Button

var controller: Control
var kind := ""
var index := -1
var extra := -1
var drop_hint := Color.TRANSPARENT


func set_drop_hint(color: Color) -> void:
	drop_hint = color
	queue_redraw()


func _get_tooltip(_at_position: Vector2) -> String:
	return controller.dynamic_tooltip(kind, index, extra, tooltip_text) if controller != null else tooltip_text


func _get_drag_data(_at_position: Vector2) -> Variant:
	if controller == null: return null
	var data: Dictionary = controller.drag_data(kind, index, extra)
	if data.is_empty(): return null
	controller.operation_feedback.begin_drag(data)
	set_drag_preview(controller.make_drag_preview(data))
	return data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return controller != null and typeof(data) == TYPE_DICTIONARY and controller.operation_feedback.target(data, kind, index, extra, self)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if controller != null: controller.handle_drop(data, kind, index, extra)
