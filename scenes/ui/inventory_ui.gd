extends CanvasLayer
## Окно инвентаря (клавиша I). Только у своего дрона.
## Клик по предмету — взять в руки / убрать на пояс. Пока окно открыто,
## дрон стоит, мышь свободна. I или Esc — закрыть.

const ITEMS := {
	"rope": {
		"name": "Верёвка",
		"desc": "Прочный трос, 14 м. Спасти друга из полыньи, связаться в связку, заарканить и подтащить груз, тащить тяжёлый ящик волоком.",
		"keys": "ЛКМ (держать и отпустить) — раскрутить и бросить\nПКМ (держать) — тянуть\nЛКМ — отвязать",
	},
}
const SLOTS := 15
const COLS := 5

var player: Node            ## player.gd
var is_open := false
var _root: Control
var _grid: GridContainer
var _slots: Array[Control] = []
var _title: Label
var _desc: Label
var _keys: Label
var _state: Label
var _button: Button
var _selected := ""


func _ready() -> void:
	layer = 30
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.96)
	sb.border_color = Color(0.85, 0.55, 0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860, 430)
	panel.position = Vector2(-430, -215)
	_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "ИНВЕНТАРЬ"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var hint := Label.new()
	hint.text = "I / Esc — закрыть"
	hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	head.add_child(hint)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	v.add_child(body)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(_grid)
	for i in SLOTS:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(92, 92)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.draw.connect(_draw_slot.bind(slot, i))
		slot.gui_input.connect(_slot_input.bind(i))
		_grid.add_child(slot)
		_slots.append(slot)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(300, 0)
	info.add_theme_constant_override("separation", 10)
	body.add_child(info)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	info.add_child(_title)
	_state = Label.new()
	_state.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	info.add_child(_state)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(300, 0)
	_desc.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	info.add_child(_desc)
	_keys = Label.new()
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys.custom_minimum_size = Vector2(300, 0)
	_keys.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	info.add_child(_keys)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, 40)
	_button.pressed.connect(_toggle_selected)
	info.add_child(_button)
	_refresh()


func _input(event: InputEvent) -> void:
	if player == null or not player.is_local:
		return
	if event.is_action_pressed("inventory"):
		_set_open(not is_open)
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _set_open(on: bool) -> void:
	is_open = on
	_root.visible = on
	player.input_blocked = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if on:
		if _selected == "" and not player.items.is_empty():
			_selected = player.items[0]
		_refresh()


func _slot_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if i < player.items.size():
			var id: String = player.items[i]
			if _selected == id:
				_toggle_selected()
			_selected = id
			_refresh()


func _toggle_selected() -> void:
	if _selected == "rope" and player.rope:
		player.rope.set_equipped(not player.rope.equipped)
	_refresh()


func _equipped(id: String) -> bool:
	return id == "rope" and player.rope != null and player.rope.equipped


func _refresh() -> void:
	for s in _slots:
		s.queue_redraw()
	if player == null or _selected == "" or not ITEMS.has(_selected):
		_title.text = "Пусто"
		_desc.text = "Подбирай полезные вещи — они появятся здесь."
		_keys.text = ""
		_state.text = ""
		_button.visible = false
		return
	var it: Dictionary = ITEMS[_selected]
	_title.text = it["name"]
	_desc.text = it["desc"]
	_keys.text = it["keys"]
	var eq := _equipped(_selected)
	_state.text = "В руках" if eq else "На поясе"
	_state.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6) if eq else Color(0.7, 0.75, 0.85))
	_button.visible = true
	_button.text = "Убрать на пояс" if eq else "Взять в руки"


func _draw_slot(slot: Control, i: int) -> void:
	var r := Rect2(Vector2.ZERO, slot.size)
	var id: String = player.items[i] if player and i < player.items.size() else ""
	var sel := id != "" and id == _selected
	var eq := id != "" and _equipped(id)
	var bg := Color(0.13, 0.16, 0.21) if id == "" else Color(0.18, 0.21, 0.28)
	slot.draw_rect(r, bg)
	var border := Color(0.25, 0.3, 0.38)
	if eq:
		border = Color(0.45, 1.0, 0.55)
	elif sel:
		border = Color(1.0, 0.75, 0.35)
	slot.draw_rect(r, border, false, 3.0 if (sel or eq) else 1.5)
	if id == "rope":
		_draw_rope_icon(slot, r)
		var font := ThemeDB.fallback_font
		slot.draw_string(font, Vector2(6, r.size.y - 8), "Верёвка", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.92, 1.0))
		if eq:
			slot.draw_string(font, Vector2(r.size.x - 24, 18), "✋", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 1.0, 0.6))


func _draw_rope_icon(slot: Control, r: Rect2) -> void:
	var c := r.get_center() + Vector2(0, -8)
	var col := Color(0.82, 0.58, 0.3)
	var dark := Color(0.55, 0.36, 0.17)
	for k in 4:
		var rad := 12.0 + k * 5.0
		slot.draw_arc(c, rad, 0.0, TAU, 32, dark if k % 2 == 0 else col, 3.5)
	# хвост с петлёй
	var tail := PackedVector2Array([c + Vector2(30, 4), c + Vector2(36, 16), c + Vector2(32, 26)])
	slot.draw_polyline(tail, col, 3.5)
	slot.draw_arc(c + Vector2(30, 31), 6.0, 0.0, TAU, 16, col, 3.0)
