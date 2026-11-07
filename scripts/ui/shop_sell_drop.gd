# 棋盘与出售交互 V1 · 2026-11-06
extends Control

var controller: Control
var shop: Control
var caption: Label

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	caption=Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",24)
	caption.add_theme_color_override("font_color",Color("ffe096"))
	caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	hide()
	set_process(false)

func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_BEGIN and controller!=null:
		var data: Variant=get_viewport().gui_get_drag_data()
		if typeof(data)!=TYPE_DICTIONARY or str(data.get("kind","")) not in ["board","bench"]:return
		var piece: Dictionary=controller.operation_feedback.piece_at(str(data.kind),int(data.index))
		if piece.is_empty():return
		var price: int=controller.game.units[piece.id].sell_gold[int(piece.star)-1]
		caption.text="松开出售 %s · +%d 金币"%[controller.game.units[piece.id].name_zh,price]
		_fit()
		show()
		set_process(true)
	elif what==NOTIFICATION_DRAG_END:
		hide()
		set_process(false)

func _fit() -> void:
	position=shop.position
	size=shop.size
	queue_redraw()

func _process(_delta: float) -> void:_fit()

func _can_drop_data(_at: Vector2,data: Variant) -> bool:
	if typeof(data)!=TYPE_DICTIONARY:return false
	var allowed: bool=controller.operation_feedback.target(data,"sell",-1,-1,self)
	var hint: Dictionary=controller.operation_feedback.last_hint
	caption.text=("松开"+str(hint.text)) if allowed else str(hint.text)
	caption.add_theme_color_override("font_color",hint.color)
	controller.operation_feedback.get_node("Message").hide()
	return allowed

func _drop_data(_at: Vector2,data: Variant) -> void:
	controller.handle_drop(data,"sell",-1,-1)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.025,.045,.065,.92))
	draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),Color("e7b85a"),false,2)
