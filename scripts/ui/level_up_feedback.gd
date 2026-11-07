extends Control

var age := 2.0
var level := 0
var triggers := 0
var caption: Label
var target: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	caption = Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_color",Color("ffe59b"))
	caption.add_theme_constant_override("outline_size",3)
	add_child(caption)
	hide()
	set_process(false)

func trigger(new_level: int) -> void:
	position = target.position
	size = target.size
	level = new_level
	triggers += 1
	age = 0.0
	caption.text = "商店升级  Lv.%d"%level
	show()
	set_process(true)

func _process(delta: float) -> void:
	position = target.position
	size = target.size
	age += delta
	if age >= 1.2:
		hide()
		set_process(false)
		return
	caption.position = Vector2(0,-26-age*12)
	caption.size.x = size.x
	caption.modulate.a = minf(1,(1.2-age)/.3)
	queue_redraw()

func _draw() -> void:
	var alpha := clampf((1.2-age)/.4,0,1)
	var color := Color(1,.79,.3,alpha)
	draw_rect(Rect2(Vector2.ZERO,size).grow(2+age*4),color,false,2)
	for i in 12:
		var x := size.x*(i+.5)/12
		var height := sin(i*2.3+age*6)*4+12
		draw_line(Vector2(x,0),Vector2(x,-height-age*10),Color(color,.4*alpha),2,true)
