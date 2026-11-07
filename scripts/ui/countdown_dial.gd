extends Control

var fraction := 1.0
var urgent := false


func set_countdown(remaining: float, total: float) -> void:
	fraction = clampf(remaining / maxf(total, 1.0), 0.0, 1.0)
	urgent = remaining <= 5.0
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 5.0
	draw_circle(center, radius + 3, Color(0.025,0.035,0.045,.98))
	draw_arc(center,radius+3,0,TAU,96,Color(.47,.43,.31,.85),1,true)
	draw_circle(center, radius, Color(0.025, 0.055, 0.08, 0.98))
	for index in 12:
		var direction := Vector2.from_angle(index*TAU/12-PI*.5)
		draw_line(center+direction*(radius-8),center+direction*(radius-5),Color(.62,.66,.61,.45),1,true)
	draw_arc(center, radius, 0, TAU, 96, Color(0.20, 0.30, 0.33), 4.0, true)
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction, 96,
		Color(0.95, 0.48, 0.31) if urgent else Color(0.45, 0.82, 0.68), 4.0, true)
