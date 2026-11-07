extends PanelContainer

var controller: Control


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return controller != null and typeof(data) == TYPE_DICTIONARY and controller.operation_feedback.target(data, "inventory", -1, -1, self)


func _drop_data(_at: Vector2, data: Variant) -> void:
	if controller != null: controller.handle_drop(data, "inventory", -1, -1)
