extends Control
## Главное меню: имя курьера, игра одному, создание игры (хост),
## подключение по IP и лобби со списком игроков.
## Интерфейс собирается из кода, чтобы его было легко менять.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _menu_box: VBoxContainer
var _lobby_box: VBoxContainer
var _players_list: VBoxContainer
var _start_button: Button
var _lobby_info: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	Network.players_changed.connect(_refresh_lobby)
	Network.joined_lobby.connect(_show_lobby)
	Network.connection_failed.connect(_on_connection_failed)
	if Network.last_message != "":
		_status.text = Network.last_message
		Network.last_message = ""


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(420, 0)
	root.add_theme_constant_override("separation", 14)
	center.add_child(root)

	var title := Label.new()
	title.text = "RUSTY BOAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1, 0.62, 0.25))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Межпланетная служба доставки"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	root.add_child(subtitle)

	# --- Главное меню ---
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	root.add_child(_menu_box)

	_menu_box.add_child(_caption("Имя курьера"))
	_name_edit = LineEdit.new()
	_name_edit.text = Network.local_name
	_name_edit.max_length = 16
	_menu_box.add_child(_name_edit)

	_menu_box.add_child(_button("Играть одному", _on_solo))
	_menu_box.add_child(_button("Создать игру (хост)", _on_host))

	_menu_box.add_child(_caption("IP хоста (для подключения)"))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_menu_box.add_child(_ip_edit)
	_menu_box.add_child(_button("Подключиться", _on_join))
	_menu_box.add_child(_button("Выход", func(): get_tree().quit()))

	# --- Лобби ---
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	_lobby_box.visible = false
	root.add_child(_lobby_box)

	_lobby_box.add_child(_caption("Курьеры в команде (до 4)"))
	_players_list = VBoxContainer.new()
	_lobby_box.add_child(_players_list)
	_lobby_info = Label.new()
	_lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lobby_info.modulate = Color(1, 1, 1, 0.7)
	_lobby_box.add_child(_lobby_info)
	_start_button = _button("Начать доставку", _on_start)
	_lobby_box.add_child(_start_button)
	_lobby_box.add_child(_button("Выйти из лобби", func(): Network.leave_to_menu()))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
	root.add_child(_status)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.75)
	return l


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(callback)
	return b


func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	Network.local_name = n if n != "" else "Курьер"


func _on_solo() -> void:
	_apply_name()
	Network.play_offline()


func _on_host() -> void:
	_apply_name()
	var err: Error = Network.host()
	if err != OK:
		_status.text = "Не удалось создать игру (порт %d занят?)" % Network.DEFAULT_PORT
		return
	_show_lobby()


func _on_join() -> void:
	_apply_name()
	var err: Error = Network.join(_ip_edit.text.strip_edges())
	if err != OK:
		_status.text = "Неверный адрес"
		return
	_status.text = "Подключаемся..."


func _on_start() -> void:
	Network.start_game()


func _on_connection_failed(reason: String) -> void:
	_status.text = reason


func _show_lobby() -> void:
	_menu_box.visible = false
	_lobby_box.visible = true
	_status.text = ""
	_refresh_lobby()


func _refresh_lobby() -> void:
	if _players_list == null:
		return
	for c in _players_list.get_children():
		c.queue_free()
	var ids: Array = Network.players.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = Network.players[id]
		var l := Label.new()
		var host_mark := "  (хост)" if id == 1 else ""
		l.text = "●  %s%s" % [info["name"], host_mark]
		l.add_theme_color_override("font_color", Network.COLORS[int(info["color"]) % Network.COLORS.size()])
		l.add_theme_font_size_override("font_size", 20)
		_players_list.add_child(l)

	var is_host := multiplayer.is_server()
	_start_button.visible = is_host
	if is_host:
		_lobby_info.text = "Друзья подключаются по твоему IP: %s\n(порт %d). Для теста на одном ПК — 127.0.0.1" % [_local_ip(), Network.DEFAULT_PORT]
	else:
		_lobby_info.text = "Ждём, пока хост начнёт доставку..."


func _local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"
