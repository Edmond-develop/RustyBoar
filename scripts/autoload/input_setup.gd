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
