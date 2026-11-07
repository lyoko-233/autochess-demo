extends "res://scripts/drag_cell.gd"

const VisualState = preload("res://scripts/battle_visual_state.gd")

var model_anchor := Vector2(32, 34)
var bar_width := 48.0
var detailed := false
var mana_ratio := 0.0
var has_mana := false


func set_model_anchor(value: Vector2) -> void:
	if model_anchor.is_equal_approx(value): return
	model_anchor = value
	queue_redraw()


func _draw() -> void:
	if model_anchor.distance_to(Vector2(32, 34)) > .5:
		draw_line(Vector2(32, 24), model_anchor, Color(0.75, 0.85, 0.92, 0.5), 1.0, true)


func _ready() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(func(): set_detailed(true))
	mouse_exited.connect(func(): set_detailed(false))
	focus_entered.connect(func(): set_detailed(true))
	focus_exited.connect(func(): set_detailed(false))
	set_bar_width(48.0)
	set_detailed(false)

func set_detailed(value: bool) -> void:
	detailed=value
	$Name.visible=value
	$State.visible=value
	$Items.visible=value
	$Mana.visible=has_mana and (value or mana_ratio>=.9)

func set_bar_width(value: float) -> void:
	bar_width=value
	$HP.position.x=32-value*.5
	$HP.size.x=value
	$Mana.position.x=32-value*.5
	$Mana.size.x=value



func set_actor(actor: Dictionary, own: bool, cues: Dictionary, elapsed: float, clip: String = "") -> void:
	$Name.text = str(actor["name"])
	$Stars.text = "★".repeat(int(actor["star"]))
	$Stars.modulate = Color(1.0, 0.78, 0.3) if int(actor["star"]) == 3 else Color.WHITE
	$HP/Fill.color = Color(0.23, 0.82, 0.43) if own else Color(0.95, 0.30, 0.23)
	var shield := maxf(0.0, float(actor.get("shield", 0.0)))
	var total := maxf(1.0, float(actor["max_hp"]) + shield)
	$HP/Fill.size.x = bar_width * clampf(float(actor["hp"]) / total, 0, 1)
	$HP/Shield.position.x = $HP/Fill.size.x
	$HP/Shield.size.x = bar_width * clampf(shield / total, 0, 1)
	$Mana/Fill.size.x = bar_width * clampf(float(actor["mana"]) / maxf(1.0, float(actor["max_mana"])), 0, 1)
	has_mana=float(actor["max_mana"])>0
	mana_ratio=float(actor["mana"])/maxf(1,float(actor["max_mana"]))
	$Mana.visible=has_mana and (detailed or mana_ratio>=.9)
	$State.text = ""
	var casting: Dictionary = cues.get("cast", {})
	var cast_age := elapsed - float(casting.get("time", -100))
	if clip == "cast" and cast_age >= 0 and elapsed <= float(casting.get("release_time", -100)) + 0.2:
		$State.text = "施法"
		$State.modulate = Color(0.40, 0.80, 1.0)
	var critical: Dictionary = cues.get("critical_hit", {})
	var critical_age := elapsed - float(critical.get("time", -100))
	if critical_age >= 0 and critical_age < 0.35:
		$State.text = "暴击"
		$State.modulate = Color(1.0, 0.75, 0.28)
	tooltip_text = "%s %s\n生命 %.0f / %.0f\n魔法 %.0f / %.0f%s" % [actor["name"], $Stars.text, actor["hp"], actor["max_hp"], actor["mana"], actor["max_mana"], "\n护盾 %.0f" % shield if shield > 0 else ""]
	var pulse: Dictionary = cues.get("mana_pulse", {})
	var pulse_age := elapsed - float(pulse.get("time", -100))
	if $State.text.is_empty() and pulse_age >= 0 and pulse_age < 0.45:
		$State.text = "回魔"
		$State.modulate = Color(0.40, 0.80, 1.0)
	var active := VisualState.active_statuses(actor, cues, elapsed)
	var equipment: Dictionary = cues.get("equipment_trigger", {})
	var equipment_age := elapsed - float(equipment.get("time", -100))
	if $State.text.is_empty() and equipment_age >= 0 and equipment_age < 0.35:
		$State.text = {"blade_mail": "反伤", "battle_fury": "溅射", "lifesteal": "吸血"}.get(equipment.get("item", ""), "")
		$State.modulate = Color(0.3, 0.95, 0.55) if equipment.get("item", "") == "lifesteal" else Color(1, 0.65, 0.25)
	var labels: Array = []
	for kind in VisualState.CONTROL_LABELS:
		if active.has(kind): labels.append(VisualState.CONTROL_LABELS[kind])
	if not labels.is_empty():
		$State.text = str(labels[0])
		$State.modulate = Color(1.0, 0.78, 0.3) if active.has("stun") else Color(0.83, 0.64, 1.0)
		tooltip_text += "\n状态：%s" % "、".join(labels)
