extends Node
## Регистрирует все кнопки управления при запуске игры.
## Используем physical_keycode — привязку к физическому положению клавиши,
## поэтому управление работает и при включённой русской раскладке.

const STICK_DEADZONE := 0.2


func _ready() -> void:
	# --- Клавиатура ---
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("quiet", [KEY_CTRL, KEY_C])
	_bind_keys("interact", [KEY_E])
	_bind_keys("throw", [KEY_Q])
	_bind_keys("shake_ice", [KEY_R])
	_bind_keys("rip", [KEY_F])             # держать рядом с другом — оторвать ему руку/ногу
	# ВРЕМЕННО, для проверки: боты-курьеры в скафандрах
	_bind_keys("bot_add", [KEY_KP_ADD])
	_bind_keys("bot_remove", [KEY_MINUS, KEY_KP_SUBTRACT])
	_bind_keys("bot_panel", [KEY_B])
	_bind_keys("possess", [KEY_G])
	for i in 9:
		_bind_keys("cmd_%d" % (i + 1), [KEY_1 + i])
	# ВРЕМЕННО, для проверки: следующая локация (Shift — предыдущая)
	_bind_keys("teleport", [KEY_EQUAL])
	# Инвентарь и предмет в руках
	_bind_keys("inventory", [KEY_I])
	_ensure_action("use_item")
	var lmb_use := InputEventMouseButton.new()
	lmb_use.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("use_item", lmb_use)
	_ensure_action("use_alt")
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("use_alt", rmb)
	# ВРЕМЕННО: карта лабиринта, пока держишь Tab
	_bind_keys("map", [KEY_TAB])
	# Хоккей: бросок шайбы (левая кнопка мыши / правый курок)
	_ensure_action("shoot")
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("shoot", lmb)
	_bind_axis("shoot", JOY_AXIS_TRIGGER_RIGHT, 1.0)

	# --- Геймпад: левый стик — движение ---
	_bind_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)

	# --- Геймпад: правый стик — камера ---
	_bind_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)

	# --- Геймпад: кнопки ---
	_bind_button("jump", JOY_BUTTON_A)
	_bind_button("interact", JOY_BUTTON_X)
	_bind_button("throw", JOY_BUTTON_Y)
	_bind_button("sprint", JOY_BUTTON_LEFT_STICK)
	_bind_button("quiet", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_button("shake_ice", JOY_BUTTON_B)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, STICK_DEADZONE)


func _bind_keys(action: StringName, keys: Array) -> void:
	_ensure_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _bind_axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)


func _bind_button(action: StringName, button: JoyButton) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
