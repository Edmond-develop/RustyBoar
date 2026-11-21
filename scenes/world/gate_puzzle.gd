extends CanvasLayer
## Окно головоломки ворот: три сцепленных кольца со знаками.
## Поверни кольца так, чтобы в рамке встали знаки трёх печатей (порядок — как гнёзда).
## Кольца сцеплены: кольцо 2 при повороте тянет за собой кольцо 1, кольцо 3 — кольцо 2.
## Клавиши 1, 2, 3 (или кнопки мышью) — повернуть кольцо; Esc — закрыть.

signal solved
signal closed

const SYM := preload("res://scenes/world/gate_symbols.gd")

var target: Array = [0, 0, 0]
var rings: Array = [3, 1, 4]
var _view: Control
var _info: Label
var _anim := [0.0, 0.0, 0.0]
var _done := false
var _done_t := 0.0


func _ready() -> void:
	layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.08, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 470)
	panel.position = Vector2(-360, -235)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.17, 0.95)
	sb.border_color = Color(0.45, 0.75, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Замок ворот"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.8, 0.93, 1.0))
	box.add_child(title)
	_info = Label.new()
	_info.text = "Выставь в рамке знаки трёх печатей (верхний ряд).\nКольца сцеплены: кольцо 2 тянет за собой кольцо 1, кольцо 3 — кольцо 2.\nКлавиши 1, 2, 3 или кнопки — повернуть кольцо.   Esc — отойти."
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 17)
	_info.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	box.add_child(_info)
	_view = Control.new()
	_view.custom_minimum_size = Vector2(700, 280)
	_view.draw.connect(_draw_view)
	box.add_child(_view)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 90)
	box.add_child(row)
	for i in 3:
		var b := Button.new()
		b.text = "  Повернуть %d  " % (i + 1)
		b.add_theme_font_size_override("font_size", 20)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(rotate_ring.bind(i))
		row.add_child(b)


func _process(delta: float) -> void:
	for i in 3:
		_anim[i] = move_toward(_anim[i], 0.0, delta * 4.0)
	if _done:
		_done_t += delta
		if _done_t > 1.2:
			solved.emit()
			queue_free()
	_view.queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if _done:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_1:
				rotate_ring(0)
			KEY_2:
				rotate_ring(1)
			KEY_3:
				rotate_ring(2)
			KEY_ESCAPE:
				closed.emit()
				queue_free()
		get_viewport().set_input_as_handled()


## Повернуть кольцо i (и сцепленное с ним соседнее слева)
func rotate_ring(i: int) -> void:
	if _done:
		return
	rings[i] = (rings[i] + 1) % 6
	_anim[i] = 1.0
	if i > 0:
		rings[i - 1] = (rings[i - 1] + 1) % 6
		_anim[i - 1] = 1.0
	if rings == target:
		_done = true
		_info.text = "Знаки совпали! Замок щёлкает…"
		_info.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))


func _draw_view() -> void:
	var w := _view.size.x
	var cx := [w * 0.5 - 220.0, w * 0.5, w * 0.5 + 220.0]
	for i in 3:
		var x: float = cx[i]
		# цель
		_view.draw_string(ThemeDB.fallback_font, Vector2(x - 40, 18), "печать %d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, 80, 15, Color(0.7, 0.8, 0.9))
		SYM.draw(_view, int(target[i]), Vector2(x, 52), 22.0, SYM.COLORS[int(target[i])])
		# кольцо: соседние знаки тусклые, текущий — в рамке
		var ok: bool = rings[i] == target[i]
		var frame_col := Color(0.4, 1.0, 0.5) if ok else Color(0.5, 0.75, 1.0)
		_view.draw_rect(Rect2(x - 52, 112, 104, 104), Color(0.08, 0.15, 0.25), true)
		_view.draw_rect(Rect2(x - 52, 112, 104, 104), frame_col, false, 3.0)
		var off: float = _anim[i] * 60.0
		for k: int in [-1, 0, 1]:
			var sym: int = (int(rings[i]) + k + 6) % 6
			var y: float = 164.0 + k * 70.0 + off
			var r: float = 36.0 if k == 0 else 20.0
			var col: Color = SYM.COLORS[sym]
			if k != 0:
				col = col.darkened(0.55)
			if y > 80.0 and y < 270.0:
				SYM.draw(_view, sym, Vector2(x, y), r, col)
		_view.draw_string(ThemeDB.fallback_font, Vector2(x - 40, 262), "кольцо %d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(0.75, 0.85, 1.0))
		# сцепка
		if i > 0:
			var x0: float = cx[i - 1] + 60.0
			var x1: float = x - 60.0
			_view.draw_line(Vector2(x1, 164), Vector2(x0, 164), Color(0.9, 0.7, 0.3), 3.0)
			_view.draw_colored_polygon(PackedVector2Array([Vector2(x0, 164), Vector2(x0 + 12, 156), Vector2(x0 + 12, 172)]), Color(0.9, 0.7, 0.3))
