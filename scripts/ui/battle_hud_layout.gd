extends RefCounted
# Small local offsets only; the HUD draws a tether to its true model anchor.
static func offsets(anchors: Dictionary, widths: Dictionary) -> Dictionary:
	var ids: Array=anchors.keys()
	ids.sort_custom(func(a,b): return anchors[a].y>anchors[b].y if not is_equal_approx(anchors[a].y,anchors[b].y) else int(a)<int(b))
	var placed: Array[Rect2]=[]
	var result := {}
	for uid in ids:
		var best := Vector2.ZERO
		for candidate in [Vector2.ZERO,Vector2(0,-8),Vector2(0,8),Vector2(0,-16),Vector2(0,16),Vector2(-8,-8),Vector2(8,-8),Vector2(-8,8),Vector2(8,8)]:
			var rect:=Rect2(anchors[uid]+candidate+Vector2(-widths[uid]*.5,-18),Vector2(widths[uid],6)).grow(1)
			var clear := true
			for other in placed:
				if other.intersects(rect): clear=false; break
			if clear: best=candidate; break
		result[uid]=best
		placed.append(Rect2(anchors[uid]+best+Vector2(-widths[uid]*.5,-18),Vector2(widths[uid],6)).grow(1))
	return result
