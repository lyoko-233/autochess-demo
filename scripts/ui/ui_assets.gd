extends RefCounted

const GOLD := Color(0.93, 0.76, 0.39)
const COSTS := [Color.WHITE, Color(0.36, 0.79, 0.51), Color(0.38, 0.69, 0.97), Color(0.72, 0.48, 0.91), GOLD]
static var icons: Dictionary = {}
static var equipment: Dictionary = {}


static func icon(name_value: String) -> Texture2D:
	if not icons.has(name_value): icons[name_value] = load("res://assets/ui/icons/%s.svg" % name_value)
	return icons[name_value]


static func portrait(piece_id: String) -> Texture2D:
	return preload("res://scripts/ui/model_portraits.gd").portrait(piece_id)


static func cost_color(cost: int) -> Color:
	return COSTS[clampi(cost - 1, 0, 4)]


static func equipment_icon(item_id: String) -> Texture2D:
	if equipment.has(item_id): return equipment[item_id]
	var painted := "res://assets/ui/equipment/painted/%s.png" % item_id
	equipment[item_id] = load(painted if ResourceLoader.exists(painted) else "res://assets/ui/equipment/%s.svg" % item_id)
	return equipment[item_id]


static func frame(color: Color, width: int = 1, background: Color = Color(0.035, 0.055, 0.07, 0.98)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = color
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0,0,0,.30)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0,2)
	style.set_content_margin_all(5)
	return style
