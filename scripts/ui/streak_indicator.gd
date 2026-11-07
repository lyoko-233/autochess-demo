extends HBoxContainer

const Assets = preload("res://scripts/ui/ui_assets.gd")


func set_streak(value: int) -> void:
	visible = value != 0
	$Flame.texture = Assets.icon("flame")
	$Flame.modulate = Color(0.30, 0.72, 1.0) if value > 0 else Color(1.0, 0.32, 0.24)
	$Count.text = str(absi(value))
	tooltip_text = "%s %d 场" % ["连胜" if value > 0 else "连败", absi(value)]
