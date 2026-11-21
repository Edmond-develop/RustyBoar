extends CanvasLayer
## Шаг 74: настройки графики (F2) и автонастройка.
##   Авто — игра сама снижает качество, если кадров мало (< 40 в секунду), и возвращает, когда снова легко;
##   Высокое / Среднее / Низкое — вручную. Сохраняется в user://graphics.cfg.
## Что меняется: разрешение 3D (с FSR-сглаживанием), тени солнца (дальность, точность), SSAO, свечение,
## снежинки и частицы, дальность мелких предметов, детализация дальних моделей.

const CFG := "user://graphics.cfg"
const NAMES := ["Низкое", "Среднее", "Высокое"]
const SCALE := [0.67, 0.83, 1.0]
const SHADOW := [40.0, 65.0, 90.0]
const PARTS := [0.4, 0.7, 1.0]
const LOD_T := [8.0, 5.0, 3.0]

var auto := true
var level := 2
var show_fps := false
var _panel: PanelContainer
var _buttons := {}
var _fps_label: Label
var _toast: Label
var _toast_t := 0.0
var _acc := 0.0
var _frames := 0
var _bad := 0
var _good := 0
var _cooldown := 0.0
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _base_ssao := true
var _base_glow := true
var _env: Environment
var _sun: DirectionalLight3D
var _part_base := {}


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_ui()
	_apply.call_deferred()


func _load() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		auto = bool(c.get_value("g", "auto", true))
		level = clampi(int(c.get_value("g", "level", 2)), 0, 2)
		show_fps = bool(c.get_value("g", "fps", false))


func _save() -> void:
	var c := ConfigFile.new()
	c.set_value("g", "auto", auto)
	c.set_value("g", "level", level)
	c.set_value("g", "fps", show_fps)
	c.save(CFG)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.3
	_panel.offset_left = -170
	_panel.offset_right = 170
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var t := Label.new()
	t.text = "ГРАФИКА  (F2 — закрыть)"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 20)
	v.add_child(t)
	for key in ["auto", "2", "1", "0"]:
		var b := Button.new()
		b.text = "Авто (по скорости кадров)" if key == "auto" else NAMES[int(key)]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(300, 38)
		b.pressed.connect(_pick.bind(key))
		v.add_child(b)
		_buttons[key] = b
	var cb := CheckBox.new()
	cb.text = "Показывать кадры в секунду"
	cb.button_pressed = show_fps
	cb.toggled.connect(func(on: bool) -> void:
		show_fps = on
		_fps_label.visible = on
		_save())
	v.add_child(cb)
	var hint := Label.new()
	hint.text = "Если игра идёт рывками — «Среднее» или «Низкое».\nАвто само снижает, когда кадров мало."
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.85, 0.9, 1.0)
	v.add_child(hint)
	_fps_label = Label.new()
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -150
	_fps_label.offset_top = 6
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.visible = show_fps
	add_child(_fps_label)
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -200
	_toast.offset_right = 200
	_toast.offset_top = 70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.visible = false
	add_child(_toast)
	_refresh_buttons()


func _refresh_buttons() -> void:
	for key in _buttons:
		var on: bool = (key == "auto" and auto) or (not auto and key == str(level))
		(_buttons[key] as Button).set_pressed_no_signal(on)
	if auto:
		(_buttons["auto"] as Button).text = "Авто (сейчас: %s)" % NAMES[level].to_lower()


func _pick(key: String) -> void:
	if key == "auto":
		auto = true
	else:
		auto = false
		level = int(key)
	_cooldown = 3.0
	_apply()
	_save()
	_refresh_buttons()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F2:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_mouse_before = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = _mouse_before
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		_panel.visible = false
		Input.mouse_mode = _mouse_before
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if show_fps:
		_fps_label.text = "%d кадр/с" % Engine.get_frames_per_second()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.visible = _toast_t > 0.0
	if not auto or get_tree().paused:
		return
	_cooldown -= delta
	_acc += delta
	_frames += 1
	if _acc < 2.0:
		return
	var fps := _frames / _acc
	_acc = 0.0
	_frames = 0
	if _cooldown > 0.0:
		return
	if fps < 40.0 and level > 0:
		_bad += 1
		_good = 0
		if _bad >= 2:
			_bad = 0
			level -= 1
			_cooldown = 6.0
			_apply()
			_say("Графика снижена: %s (авто, F2 — настройки)" % NAMES[level].to_lower())
	elif fps > 72.0 and level < 2:
		_good += 1
		_bad = 0
		if _good >= 8:
			_good = 0
			level += 1
			_cooldown = 20.0
			_apply()
			_say("Графика: %s (авто)" % NAMES[level].to_lower())
	else:
		_bad = 0
		_good = maxi(_good - 1, 0)


func _say(t: String) -> void:
	_toast.text = t
	_toast_t = 3.0
	_toast.visible = true
	_refresh_buttons()


func _apply() -> void:
	var vp := get_viewport()
	var compat := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) == "gl_compatibility" \
		or RenderingServer.get_current_rendering_method() == "gl_compatibility"
	vp.scaling_3d_scale = SCALE[level]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if compat or level == 2 else Viewport.SCALING_3D_MODE_FSR
	vp.mesh_lod_threshold = LOD_T[level]
	var we := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if not we.is_empty() and _env == null:
		_env = (we[0] as WorldEnvironment).environment
		if _env:
			_base_ssao = _env.ssao_enabled
			_base_glow = _env.glow_enabled
	if _env:
		_env.ssao_enabled = _base_ssao and level == 2
		_env.glow_enabled = _base_glow and level >= 1
	if _sun == null:
		for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			_sun = n as DirectionalLight3D
			break
	if _sun:
		_sun.directional_shadow_max_distance = SHADOW[level]
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if level == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(4096 if level == 2 else 2048, true)
	# постоянные частицы (снег, дым, пар) — поменьше на слабом
	for p in get_tree().root.find_children("*", "GPUParticles3D", true, false):
		var gp := p as GPUParticles3D
		if gp.one_shot:
			continue
		gp.amount_ratio = PARTS[level]
	# точечные лампы без теней на низком
	for l in get_tree().root.find_children("*", "OmniLight3D", true, false):
		var ol := l as OmniLight3D
		if not ol.has_meta("g_shadow"):
			ol.set_meta("g_shadow", ol.shadow_enabled)
		ol.shadow_enabled = bool(ol.get_meta("g_shadow")) and level >= 1
	# шаг 84: кто сам упрощает себя (выступы пропасти)
	get_tree().call_group("gfx_listeners", "set_gfx_level", level)
	_refresh_buttons()
