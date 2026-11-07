extends Button

const Assets = preload("res://scripts/ui/ui_assets.gd")
const FACES := ["Axe", "Phantom Assassin", "Tidehunter", "Drow Ranger", "Sniper", "Lina", "Juggernaut", "Crystal Maiden"]


func _ready() -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)


func set_player(seat: int, level: int, hp: int, current: bool) -> void:
	$Face.texture = Assets.portrait(FACES[seat])
	$Name.text = "玩家" if seat == 0 else "电脑 %d" % seat
	$Level.text = "Lv %d" % level
	$HP.text = "%d%%" % hp
	add_theme_stylebox_override("normal", Assets.frame(Assets.GOLD if current else Color(0.20, 0.29, 0.33), 1))
