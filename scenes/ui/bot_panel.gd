extends CanvasLayer
## ВРЕМЕННАЯ панель ботов-курьеров (клавиша B). Создаёт test_tools.gd.
## Слева — боты (выбрать, позвать, отпустить), справа — команды выбранному боту,
## внизу — «переселиться» в бота. Пока панель открыта, мышь свободна.

var tools: Node                  ## test_tools.gd
var is_open := false
var _root: Control
var _bots_box: VBoxContainer
var _cmd_grid: GridContainer
var _status: Label
var _possess_btn: Button


func _ready() -> void:
	layer = 31
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.1, 0.13, 0.96)
	sb.border_color = Color(0.4, 0.85, 0.55)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 440)
	panel.position = Vector2(-450, -220)
	_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "БОТЫ-КУРЬЕРЫ"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var hint := Label.new()
	hint.text = "B / Esc — закрыть"
	hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	head.add_child(hint)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	v.add_child(body)
	# боты
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	var lt := Label.new()
	lt.text = "Кому команда:"
	lt.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	left.add_child(lt)
	_bots_box = VBoxContainer.new()
	_bots_box.add_theme_constant_override("separation", 6)
	left.add_child(_bots_box)
	var add := _button("＋ Позвать бота", Color(0.3, 0.75, 0.4))
	add.pressed.connect(func(): tools.add_courier(); refresh())
	left.add_child(add)
	var rem := _button("－ Отпустить выбранного", Color(0.75, 0.35, 0.3))
	rem.pressed.connect(func(): tools.remove_courier())
	left.add_child(rem)
	# команды
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rt := Label.new()
	rt.text = "Команды (или клавиши 1–9 в игре):"
	rt.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	right.add_child(rt)
	_cmd_grid = GridContainer.new()
	_cmd_grid.columns = 3
	_cmd_grid.add_theme_constant_override("h_separation", 8)
	_cmd_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_cmd_grid)
	var cols := [Color(0.3, 0.55, 0.85), Color(0.45, 0.5, 0.6), Color(0.3, 0.55, 0.85), Color(0.3, 0.55, 0.85),
		Color(0.75, 0.6, 0.25), Color(0.2, 0.55, 0.9), Color(0.85, 0.45, 0.2), Color(0.55, 0.45, 0.7), Color(0.5, 0.8, 0.95)]
	for i in tools.COMMANDS.size():
		var b := _button("%d  %s" % [i + 1, tools.COMMAND_NAMES[i]], cols[i])
		b.custom_minimum_size = Vector2(195, 46)
		var idx: int = i
		b.pressed.connect(func(): tools.command(idx); _set_open(false))
		_cmd_grid.add_child(b)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	# переселиться
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)
	_possess_btn = _button("Переселиться в выбранного бота (G)", Color(0.85, 0.55, 0.15))
	_possess_btn.custom_minimum_size = Vector2(380, 46)
	_possess_btn.pressed.connect(func():
		var b = tools.courier(tools.selected)
		if b:
			tools.possess(b)
		_set_open(false))
	bottom.add_child(_possess_btn)
	var home := _button("Вернуться в себя", Color(0.4, 0.5, 0.6))
	home.custom_minimum_size = Vector2(220, 46)
	home.pressed.connect(func():
		if tools._home:
			tools.possess(tools._home)
		_set_open(false))
	bottom.add_child(home)


func _button(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	var n := StyleBoxFlat.new()
	n.bg_color = col.darkened(0.45)
	n.border_color = col
	n.set_border_width_all(2)
	n.set_corner_radius_all(8)
	n.set_content_margin_all(8)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = col.darkened(0.2)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	return b


func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("bot_panel") or event.is_action_pressed("ui_cancel")):
		_set_open(false)
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_set_open(not is_open)


func _set_open(on: bool) -> void:
	is_open = on
	_root.visible = on
	var me = Network.local_player
	if me:
		me.input_blocked = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if on:
		refresh()


func refresh() -> void:
	if _bots_box == null:
		return
	for c in _bots_box.get_children():
		c.queue_free()
	var list: Array = tools._couriers()
	if list.is_empty():
		var l := Label.new()
		l.text = "Ботов пока нет"
		l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		_bots_box.add_child(l)
	for b in list:
		var idx := int(b.get_node("Brain").index)
		var sel: bool = idx == tools.selected
		var col: Color = b.get("player_color")
		var mark := "▶ " if sel else "   "
		var me_mark := "  (ты в нём)" if b == Network.local_player else ""
		var btn := _button(mark + str(b.get("player_name")) + me_mark, col if sel else col.darkened(0.3))
		btn.pressed.connect(func(): tools.selected = idx; refresh())
		_bots_box.add_child(btn)
	var cur = tools.courier(tools.selected)
	if cur:
		var st := "команда: %s" % _cmd_name(cur.get_node("Brain").command)
		if cur.is_swimming or cur.is_diving:
			st += " · в воде"
		if cur.is_frozen:
			st += " · вмёрз"
		if cur.downed:
			st += " · без сил"
		if cur.carried_by != null:
			st += " · его держат"
		_status.text = "%s — %s" % [cur.player_name, st]
	else:
		_status.text = "Позови бота кнопкой слева или «+» на цифровой клавиатуре."
	_possess_btn.disabled = cur == null


func _cmd_name(c: String) -> String:
	var i: int = tools.COMMANDS.find(c)
	return tools.COMMAND_NAMES[i] if i >= 0 else c
