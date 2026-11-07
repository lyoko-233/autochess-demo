extends RefCounted

static var content: Dictionary = {}

static func all() -> Dictionary:
	if content.is_empty():
		content = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/combat_visual_profiles.json"))
	return content.units

static func get_profile(id: String) -> Dictionary:
	return all().get(id,{})

static func skill_style(ability: String) -> String:
	all()
	return str(content.ability_styles.get(ability,"bolt"))

static func tint(id: String) -> Color:
	return Color(str(get_profile(id).get("color","eac18b")))
