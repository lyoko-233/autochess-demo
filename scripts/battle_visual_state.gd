extends RefCounted

const CONTROL_LABELS := {"stun": "眩晕", "petrify": "石化", "hex": "变形", "silence": "沉默", "disarm": "缴械"}


static func active_statuses(actor: Dictionary, cues: Dictionary, elapsed: float) -> Dictionary:
	var statuses: Dictionary = actor.get("statuses", {}).duplicate()
	statuses.merge(cues.get("statuses", {}), true)
	var active := {}
	for kind in statuses:
		if float(statuses[kind].get("end", 0.0)) > elapsed:
			active[kind] = statuses[kind]
	return active
