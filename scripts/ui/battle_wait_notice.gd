extends PanelContainer
# Non-interactive local-battle waiting state V5 — updated 2026-11-07.
const Assets = preload("res://scripts/ui/ui_assets.gd")
var caption: Label
var elapsed := 0.0
var entrance: Tween

func _ready() -> void:
	name = "BattleWaitNotice"
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -200
	offset_right = 200
	offset_top = 82
	offset_bottom = 118
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = Assets.frame(Color(0.30, 0.49, 0.48), 1, Color(0.025, 0.075, 0.09, 0.96))
	style.set_content_margin_all(9)
	add_theme_stylebox_override("panel", style)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(0.83, 0.94, 0.91))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	hide()

func set_waiting(value: bool) -> void:
	if value == visible: return
	if entrance != null: entrance.kill()
	if not value:
		hide()
		return
	elapsed = 0
	caption.text = "正在等待其他玩家战斗结束......"
	show()
	modulate.a = 0
	position.y = 76
	entrance = create_tween().set_parallel(true)
	entrance.tween_property(self, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	entrance.tween_property(self, "position:y", 82.0, 0.24).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	elapsed += delta
	caption.text = "正在等待其他玩家战斗结束" + ".".repeat(1 + int(elapsed / 0.35) % 6)
