extends Node3D
## Метель над плато. Внутри зоны: туман сгущается, валит снег,
## постоянный ветер сносит дрона, а иногда налетают сильные порывы.
## Перед порывом появляется предупреждение со стрелкой.

@export var zone_z_max := -46.0
@export var zone_z_min := -104.0
@export var zone_half_width := 70.0
@export var environment_path: NodePath   ## WorldEnvironment
@export var max_fog := 0.06              ## Плотность тумана в самой метели
@export var base_wind := 1.2             ## Постоянный ветер (м/с сноса)
@export var gust_wind := 6.5             ## Порыв
@export var gust_interval_min := 4.5
@export var gust_interval_max := 8.0
@export var gust_warning := 1.0
@export var gust_duration := 1.8

var intensity := 0.0

var _env: Environment
var _base_fog := 0.0
var _base_fog_color := Color.WHITE
var _snow: GPUParticles3D
var _player: Node3D
var _gust_timer := 5.0
var _gust_state := 0      # 0 — тихо, 1 — предупреждение, 2 — порыв
var _gust_dir := 1.0
var _wind_dir := 1.0
var _label: Label


func _ready() -> void:
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we:
		_env = we.environment
		_base_fog = _env.fog_density
		_base_fog_color = _env.fog_light_color

	_snow = FX.particles(Color(1, 1, 1, 0.85), 2000, 1.4, 0.035, 8.0, 14.0,
		Vector3(0, -3, 0), 12.0, false)
	FX.set_box(_snow, Vector3(18.0, 8.0, 18.0))
	add_child(_snow)

	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 10)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -300.0
	_label.offset_right = 300.0
	_label.offset_top = 120.0
	_label.offset_bottom = 170.0
	_label.visible = false
	hud.add_child(_label)


func _physics_process(delta: float) -> void:
	# Метель у каждого своя: туман, снег и ветер — только для своего дрона
	_player = Network.local_player
	if _player == null:
		return

	var p := _player.global_position
	var inside := p.z < zone_z_max and p.z > zone_z_min and absf(p.x) < zone_half_width
	intensity = move_toward(intensity, 1.0 if inside else 0.0, 0.5 * delta)

	if _env:
		_env.fog_density = lerpf(_base_fog, max_fog, intensity)
		_env.fog_light_color = _base_fog_color.lerp(Color(0.9, 0.93, 0.97), intensity)

	_snow.global_position = p + Vector3(-_wind_dir * 8.0, 5.0, 0.0)
	_snow.emitting = intensity > 0.05
	_snow.amount_ratio = intensity

	# --- Порывы ветра ---
	var wind := _wind_dir * base_wind
	_label.visible = false
	if intensity > 0.3:
		_gust_timer -= delta
		match _gust_state:
			0:
				if _gust_timer <= 0.0:
					_gust_state = 1
					_gust_timer = gust_warning
					_gust_dir = 1.0 if randf() > 0.5 else -1.0
			1:
				_label.visible = fmod(_gust_timer, 0.3) < 0.2
				_label.text = "ПОРЫВ ВЕТРА  →" if _gust_dir > 0.0 else "←  ПОРЫВ ВЕТРА"
				if _gust_timer <= 0.0:
					_gust_state = 2
					_gust_timer = gust_duration
			2:
				_label.visible = true
				_label.text = "ПОРЫВ ВЕТРА  →" if _gust_dir > 0.0 else "←  ПОРЫВ ВЕТРА"
				wind = _gust_dir * gust_wind
				_player.add_shake(0.04)
				if _gust_timer <= 0.0:
					_gust_state = 0
					_gust_timer = randf_range(gust_interval_min, gust_interval_max)
					_wind_dir = _gust_dir

	# Снег летит по ветру
	var pm := _snow.process_material as ParticleProcessMaterial
	pm.direction = Vector3(signf(wind) if wind != 0.0 else 1.0, -0.35, 0.0)

	if intensity > 0.01:
		_player.apply_wind(Vector3(wind * intensity, 0.0, 0.0))
