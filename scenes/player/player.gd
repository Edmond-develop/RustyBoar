extends CharacterBody3D
## Курьерский дрон-шар на двух ногах (с поддержкой сети).
##
## У каждого дрона есть «хозяин» — игрок, чей номер записан в имени узла.
## Хозяин управляет дроном сам и 30 раз в секунду рассылает его состояние.
## На остальных компьютерах этот дрон — «копия»: плавно повторяет присланное.
##
## Механики (только у хозяина): бег и выносливость, переноска и устойчивость
## посылки, удары, здоровье, шум (для лавин), ветер.
##
## Вода и холод:
##  * упал в полынью — дрон тяжёлый и тонет; вверх плывёт, только пока держишь Пробел;
##  * подо льдом всплыть нельзя — течение может утащить от полыньи, выход ищут
##    по столбам света; глубже pressure_depth вода давит и бьёт по корпусу;
##  * в воде дрон обледеневает (под водой и на глубине — быстрее), а вылезшего
##    мокрого дрона ещё несколько секунд прихватывает морозом;
##  * лёд виден: корка на корпусе и ногах, сосульки, скованная походка;
##    тает долго (~минута), у жаровни — быстро; R — стряхнуть лёд за выносливость;
##  * обледенение дошло до предела — дрон вмерзает в глыбу. Жми кнопки, чтобы
##    расколоть её; друг может помочь (E рядом). В воде глыба всплывает.

signal health_changed(health: float, max_health: float)
signal died
signal respawned
signal landed(fall_speed: float)

@export_group("Движение")
@export var walk_speed := 6.0
@export var sprint_speed := 11.5
@export var quiet_speed := 2.5
@export var acceleration := 40.0
@export var deceleration := 50.0
@export var air_control := 0.35
@export var turn_speed := 12.0
@export var min_grip := 0.04
@export var ice_slide := 1.0           ## Как сильно ледяной склон тянет вниз

@export_group("Выносливость")
@export var sprint_hold_time := 0.12
@export var stamina_max := 100.0
@export var stamina_drain := 22.0
@export var stamina_regen := 28.0
@export var stamina_regen_delay := 0.7
@export var carry_stamina_mult := 1.3
@export var exhausted_duration := 2.4
@export var exhausted_pause := 0.6
@export var exhausted_speed_mult := 0.45

@export_group("Здоровье")
@export var max_health := 100.0
@export var hazard_damage := 4.0
@export var wall_damage := 3.0
@export var fall_damage_speed := 12.0
@export var fall_damage := 6.0
@export var respawn_delay := 1.8
@export var invulnerable_time := 1.5

@export_group("Вода")
@export var swim_speed := 2.4           ## Скорость плавания на поверхности
@export var float_depth := 1.0          ## Насколько ноги ниже воды (корпус наполовину в воде)
@export var climb_reach := 1.4          ## С какого расстояния до края можно выбраться
@export var sink_speed := 1.7           ## Как быстро тонет (м/с); обледеневший — быстрее
@export var rise_speed := 2.1           ## Как быстро всплывает, пока держишь Пробел
@export var dive_speed := 2.0           ## Скорость под водой
@export var pressure_depth := 6.0       ## Глубже этого (м) вода давит на корпус
@export var pressure_damage := 1.5      ## Урон в секунду за каждый метр глубже
@export var parcel_soak := 2.5          ## % цены посылки за секунду, пока её держат в воде

@export_group("Холод")
@export var freeze_rate := 0.4          ## Обледенение в секунду на поверхности воды
@export var dive_freeze_rate := 0.6     ## ...под водой
@export var dive_freeze_per_m := 0.05   ## ...и ещё столько за каждый метр глубины
@export var wet_time := 5.0             ## Сколько секунд после воды мокрый корпус обмерзает
@export var wet_freeze := 0.5           ## ...и как быстро
@export var frost_max := 12.0           ## Дошло до этого — дрон вмерзает в глыбу
@export var frost_full := 8.0           ## При таком обледенении — самая медленная ходьба
@export var thaw_rate := 0.2            ## Таяние в секунду (полный лёд тает около минуты)
@export var heat_thaw_mult := 6.0       ## Во сколько раз быстрее тает у жаровни
@export var frost_min_speed := 0.35     ## Скорость при полном обледенении (доля от обычной)
@export var shake_stamina := 30.0       ## R — стряхнуть лёд: сколько стоит выносливости
@export var shake_amount := 1.3         ## ...и сколько льда стряхивает
@export var break_presses := 16         ## Сколько нажатий, чтобы расколоть глыбу самому
@export var buddy_chip := 0.15          ## Сколько раскалывает один удар друга (E)

@export_group("Прыжок")
@export var jump_velocity := 6.5
@export var rise_gravity_mult := 1.6
@export var fall_gravity_mult := 2.2
@export var jump_cut := 0.5
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Переноска")
@export var carry_speed_mult := 0.8
@export var carry_accel_mult := 0.75
@export var carry_jump_mult := 0.85
@export var heavy_speed_mult := 0.6     ## Скорость, когда несёте тяжёлый груз вдвоём
@export var drag_speed_mult := 0.35     ## Скорость, когда тянешь тяжёлый груз один
@export var heavy_warn_distance := 2.9  ## С какого расстояния предупреждать «держитесь ближе»
@export var throw_speed := 6.0
@export var sprint_instability := 0.16
@export var turn_instability := 0.05
@export var jump_instability := 0.12
@export var landing_instability := 0.15
@export var safe_landing_speed := 7.0
@export var hit_instability := 0.14
@export var stability_recovery := 0.45
@export var fumble_damage := 10.0
@export var hit_damage := 3.0

@export_group("Столкновения")
@export var hit_threshold := 7.0
@export var wall_knockback := 0.6
@export var hazard_knockback := 1.0
@export var light_object_mass := 20.0
@export var kick_strength := 0.8
@export var push_force := 40.0

@export_group("Шум и ветер")
@export var walk_noise := 0.3
@export var run_noise := 1.0
@export var quiet_noise := 0.05
@export var wind_instability := 0.04

@export_group("Анимация и камера")
@export var stride_frequency := 1.9
@export var leg_swing := 0.6
@export var base_fov := 70.0
@export var sprint_fov := 84.0
@export var mouse_sensitivity := 0.0025
@export var joy_look_speed := 3.0
@export var min_pitch_deg := -70.0
@export var max_pitch_deg := 35.0
@export var start_pitch_deg := -18.0

@export_group("Прочее")
@export var fall_limit_y := -20.0

const BODY_HEIGHT := 0.95
const FROST_SHADER := preload("res://shaders/drone_frost.gdshader")
const BLOCK_SHADER := preload("res://shaders/ice_block.gdshader")
const BREAK_KEYS := ["jump", "move_forward", "move_back", "move_left", "move_right", "interact", "shake_ice", "sprint"]
const SEND_INTERVAL := 1.0 / 30.0

# Флаги состояния, которые рассылаются по сети
const F_FLOOR := 1
const F_SPRINT := 2
const F_EXHAUSTED := 4
const F_STAGGER := 8
const F_DEAD := 16
const F_SAFE := 32
const F_ICE := 64
const F_CARRY := 128
const F_SWIM := 256
const F_FROZEN := 512
const F_DIVE := 1024

@onready var visual: Node3D = $Visual
@onready var body: Node3D = $Visual/Body
@onready var shell: MeshInstance3D = $Visual/Body/Shell
@onready var leg_left: Node3D = $Visual/LegLeft
@onready var leg_right: Node3D = $Visual/LegRight
@onready var knee_left: Node3D = $Visual/LegLeft/Knee
@onready var knee_right: Node3D = $Visual/LegRight/Knee
@onready var arm_left: Node3D = $Visual/Body/ArmLeft
@onready var arm_right: Node3D = $Visual/Body/ArmRight
@onready var hold_point: Node3D = $Visual/Body/HoldPoint
@onready var pickup_zone: Area3D = $Visual/PickupZone
@onready var thruster_glow: MeshInstance3D = $Visual/Body/ThrusterGlow
@onready var thruster_light: OmniLight3D = $Visual/Body/ThrusterLight
@onready var sprint_trail: GPUParticles3D = $Visual/Body/SprintTrail
@onready var steam: GPUParticles3D = $Visual/Body/Steam
@onready var sparks: GPUParticles3D = $Sparks
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var carry_hud: CanvasLayer = $CarryHUD
@onready var prompt_label: Label = $CarryHUD/Panel/Prompt
@onready var parcel_label: Label = $CarryHUD/Panel/ParcelInfo
@onready var stability_row: Control = $CarryHUD/Panel/StabilityRow
@onready var stability_bar: ProgressBar = $CarryHUD/Panel/StabilityRow/Bar
@onready var stamina_row: Control = $CarryHUD/Panel/StaminaRow
@onready var stamina_caption: Label = $CarryHUD/Panel/StaminaRow/Caption
@onready var stamina_bar: ProgressBar = $CarryHUD/Panel/StaminaRow/Bar
@onready var health_bar: ProgressBar = $CarryHUD/Panel/HealthRow/Bar
@onready var damage_flash: ColorRect = $CarryHUD/DamageFlash
@onready var death_label: Label = $CarryHUD/DeathLabel

var peer_id := 1
var is_local := true
var player_name := "Курьер"
var player_color := Color(0.86, 0.45, 0.17)

var surface_grip := 1.0
var held_parcel: Parcel = null
var instability := 0.0
var stamina := 100.0
var is_sprinting := false
var health := 100.0
var is_dead := false
var noise := 0.0
var is_swimming := false        ## Плывёт на поверхности полыньи
var is_diving := false          ## Под водой
var is_frozen := false          ## Вмёрз в глыбу льда
var frost := 0.0                ## Обледенение: растёт в воде, медленно тает на суше

var _time := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _pickup_cooldown := 0.0
var _regen_timer := 0.0
var _sprint_hold := 0.0
var _exhausted_timer := 0.0
var _stagger_timer := 0.0
var _stagger_total := 1.0
var _stagger_strength := 0.0
var _hit_cooldown := 0.0
var _dead_timer := 0.0
var _invuln_timer := 0.0
var _shake := 0.0
var _spawn_position := Vector3.ZERO
var _prev_velocity := Vector3.ZERO
var _was_on_floor := true
var _stride_phase := 0.0
var _wobble_time := 0.0
var _parcel_offset := Vector3.ZERO
var _carry_basis := Basis.IDENTITY
var _thruster_power := 0.3
var _noise_burst := 0.0
var _wind := Vector3.ZERO
var _last_wind := Vector3.ZERO
var _floor_collider: Object = null
var _default_death_text := ""
var _releasing := false
var _soft_landing := false     ## После подброса гейзером — без урона от падения
var _release_timer := 0.0

# Сеть: последнее присланное состояние (для копий)
var _send_timer := 0.0
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_prev_vy := 0.0
var _net_yaw := 0.0
var _net_flags := F_FLOOR
var _net_was_floor := true
var _net_frost := 0.0
var _net_aux := 0.0

var _lake: Node = null
var _swim_anchor := Vector3.ZERO
var _edge_point := Vector3.INF
var _edge_timer := 0.0
var _soak_timer := 0.0
var _shell_mat: StandardMaterial3D
var _frost_sparkles: GPUParticles3D
var _splash_fx: GPUParticles3D
var _drips: GPUParticles3D
var _frost_row: Control
var _frost_bar: ProgressBar
var _frost_caption: Label

# Холод и глубина
var _break_progress := 0.0      ## Насколько расколота глыба (0..1)
var _wet_timer := 0.0
var _freeze_immunity := 0.0
var _pressure_timer := 0.0
var _heat := 1.0                ## 1 — обычно, больше — рядом жаровня
var _heat_timer := 0.0
var _heavy_timer := 0.0
var _shake_anim := 0.0
var _block_jolt := 0.0
var _block_grow := 0.0
var _last_frost_step := 0
var _frost_mat: ShaderMaterial
var _icicles: Array[MeshInstance3D] = []
var _icicle_info: Array[Vector3] = []   ## (с какого льда появляется, длина, высота крепления)
var _ice_block: MeshInstance3D
var _block_mat: ShaderMaterial
var _chunks_fx: GPUParticles3D
var _shatter_fx: GPUParticles3D
var _bubbles: GPUParticles3D
var _uw: Node = null


func _enter_tree() -> void:
	peer_id = name.to_int() if name.is_valid_int() else 1
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	is_local = is_multiplayer_authority()
	add_to_group("player")
	_spawn_position = global_position
	_net_pos = global_position
	stamina = stamina_max
	health = max_health
	_default_death_text = death_label.text
	_apply_identity()
	_make_water_fx()

	if is_local:
		Network.local_player = self
		spring_arm.add_excluded_object(get_rid())
		camera_pivot.rotation.x = deg_to_rad(start_pitch_deg)
		camera.fov = base_fov
		camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current = false
		carry_hud.visible = false
		_make_name_tag()


func _apply_identity() -> void:
	var info: Dictionary = Network.players.get(peer_id, {})
	player_name = info.get("name", "Курьер")
	player_color = Network.COLORS[int(info.get("color", 0)) % Network.COLORS.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	mat.metallic = 0.55
	mat.roughness = 0.38
	shell.material_override = mat
	($Visual/LegLeft/Knee/Foot as MeshInstance3D).material_override = mat
	($Visual/LegRight/Knee/Foot as MeshInstance3D).material_override = mat
	_shell_mat = mat


func _make_water_fx() -> void:
	_splash_fx = FX.particles(Color(0.8, 0.93, 1.0, 0.9), 70, 1.1, 0.1, 2.5, 6.0, Vector3(0, -12, 0), 40.0)
	_splash_fx.top_level = true
	add_child(_splash_fx)
	_drips = FX.particles(Color(0.75, 0.9, 1.0, 0.8), 30, 0.7, 0.04, 0.2, 0.6, Vector3(0, -9, 0), 60.0, false)
	FX.set_box(_drips, Vector3(0.35, 0.2, 0.35))
	_drips.position.y = 0.6
	body.add_child(_drips)
	_frost_sparkles = FX.particles(Color(0.9, 0.97, 1.0, 0.9), 24, 1.2, 0.035, 0.1, 0.4, Vector3(0, -1.5, 0), 180.0, false, true)
	FX.set_box(_frost_sparkles, Vector3(0.45, 0.45, 0.45))
	body.add_child(_frost_sparkles)
	# Пузыри под водой
	_bubbles = FX.particles(Color(0.85, 0.95, 1.0, 0.55), 18, 1.3, 0.045, 0.3, 0.9, Vector3(0, 2.5, 0), 35.0, false)
	FX.set_box(_bubbles, Vector3(0.3, 0.2, 0.3))
	_bubbles.position.y = 0.3
	body.add_child(_bubbles)
	# Куски льда, отваливающиеся при таянии
	_chunks_fx = FX.particles(Color(0.85, 0.94, 1.0, 0.95), 12, 1.0, 0.06, 0.6, 1.8, Vector3(0, -12, 0), 80.0)
	FX.set_box(_chunks_fx, Vector3(0.35, 0.3, 0.35))
	body.add_child(_chunks_fx)
	# Осколки расколотой глыбы
	_shatter_fx = FX.particles(Color(0.8, 0.93, 1.0, 0.95), 60, 1.5, 0.1, 2.5, 6.5, Vector3(0, -14, 0), 180.0)
	FX.set_box(_shatter_fx, Vector3(0.6, 0.9, 0.6))
	_shatter_fx.top_level = true
	add_child(_shatter_fx)
	_make_frost_visuals()
	if is_local:
		var row := HBoxContainer.new()
		row.visible = false
		var cap := Label.new()
		cap.text = "Обледенение"
		_frost_caption = cap
		cap.custom_minimum_size = Vector2(130, 0)
		cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		cap.add_theme_constant_override("outline_size", 6)
		row.add_child(cap)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.modulate = Color(0.6, 0.85, 1.0)
		row.add_child(bar)
		$CarryHUD/Panel.add_child(row)
		_frost_row = row
		_frost_bar = bar


## Ледяная корка (поверх всех деталей дрона), сосульки и глыба для полной заморозки
func _make_frost_visuals() -> void:
	_frost_mat = ShaderMaterial.new()
	_frost_mat.shader = FROST_SHADER
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if node != thruster_glow:
			(node as MeshInstance3D).material_overlay = _frost_mat

	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.82, 0.93, 1.0, 0.8)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.roughness = 0.08
	ice.metallic_specular = 0.9
	ice.rim_enabled = true
	ice.rim = 0.7
	var cone := CylinderMesh.new()
	cone.top_radius = 0.045
	cone.bottom_radius = 0.003
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 1
	cone.material = ice
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# по кругу под корпусом и несколько снизу
	for i in 15:
		var ic := MeshInstance3D.new()
		ic.mesh = cone
		ic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / 12.0 + rng.randf_range(-0.2, 0.2)
		var r := 0.39 if i < 12 else 0.18
		var y := -0.21 if i < 12 else -0.4
		if i >= 12:
			a = TAU * (i - 12) / 3.0 + 0.5
		ic.position = Vector3(cos(a) * r, y, sin(a) * r)
		ic.visible = false
		body.add_child(ic)
		_icicles.append(ic)
		_icicle_info.append(Vector3(rng.randf_range(0.2, 0.85), rng.randf_range(0.16, 0.36), y))

	_block_mat = ShaderMaterial.new()
	_block_mat.shader = BLOCK_SHADER
	var chunk := SphereMesh.new()
	chunk.radius = 0.85
	chunk.height = 2.1
	chunk.radial_segments = 7
	chunk.rings = 4
	chunk.material = _block_mat
	_ice_block = MeshInstance3D.new()
	_ice_block.mesh = chunk
	_ice_block.position.y = BODY_HEIGHT
	_ice_block.rotation.y = 0.4
	_ice_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ice_block.visible = false
	add_child(_ice_block)


func _make_name_tag() -> void:
	var tag := Label3D.new()
	tag.text = player_name
	tag.modulate = player_color.lightened(0.3)
	tag.font_size = 40
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.15, 0)
	add_child(tag)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_rotate_camera(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------------------
#  Главный цикл
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if not is_local:
		_puppet_process(delta)
		return

	_handle_gamepad_look(delta)
	_update_surface_grip()
	_pickup_cooldown -= delta
	_hit_cooldown -= delta
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	_invuln_timer -= delta
	if _releasing:
		_release_timer -= delta
		if _release_timer <= 0.0:
			_releasing = false

	if is_dead:
		_dead_timer -= delta
		if _dead_timer <= 0.0:
			respawn()
			return

	# --- Вода и холод ---
	if _lake == null:
		_lake = get_tree().get_first_node_in_group("ice_lake")
		if _lake:
			_uw = _lake.get_node_or_null("Underwater")
	_update_heat(delta)
	_shake_anim = maxf(_shake_anim - delta, 0.0)
	if not is_swimming and not is_diving and _lake and _lake.is_open_water(global_position):
		_enter_water()
	if is_frozen:
		_frozen_process(delta)
		return
	if is_diving:
		_dive_process(delta)
		return
	if is_swimming:
		_swim_process(delta)
		return
	_frost_tick(delta, -1.0)
	if Input.is_action_just_pressed("shake_ice") and not is_dead:
		_shake_off_ice()

	var on_floor := is_on_floor()
	var exhausted := _exhausted_timer > 0.0
	var paused := exhausted and _exhausted_timer > exhausted_duration - exhausted_pause
	var staggered := _stagger_timer > 0.0
	var mode := _carry_mode()

	# --- Гравитация ---
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		var mult := rise_gravity_mult if velocity.y > 0.0 else fall_gravity_mult
		velocity += get_gravity() * mult * delta

	# --- Прыжок (с тяжёлым грузом прыгать нельзя) ---
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	var can_jump := not paused and not staggered and not is_dead and mode < 2
	if can_jump and _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity * (carry_jump_mult if mode == 1 else 1.0) * lerpf(1.0, 0.65, _frost_ratio())
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_thruster_power = 6.0
		_noise_burst += 0.5
		if mode == 1:
			instability += jump_instability

	if Input.is_action_just_released("jump") and velocity.y > 0.0 and not _soft_landing:
		velocity.y *= jump_cut

	# --- Взять / положить / бросить ---
	if not is_dead and not _releasing:
		if Input.is_action_just_pressed("interact"):
			if held_parcel:
				_put_down()
			elif not _try_chip_buddy():
				_try_pick_up()
		elif Input.is_action_just_pressed("throw") and mode == 1:
			_throw()
	mode = _carry_mode()

	# --- Ввод относительно камеры ---
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if paused or staggered or is_dead:
		input_dir = Vector2.ZERO
	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := right * input_dir.x - forward * input_dir.y
	var has_input := direction.length() > 0.1

	# --- Выносливость и скорость ---
	_update_stamina(delta, has_input, mode > 0)
	exhausted = _exhausted_timer > 0.0

	var target_speed := walk_speed
	if is_sprinting:
		target_speed = sprint_speed
	elif Input.is_action_pressed("quiet"):
		target_speed = quiet_speed
	if exhausted:
		target_speed *= exhausted_speed_mult
	target_speed *= _frost_mult()
	match mode:
		1: target_speed *= carry_speed_mult
		2: target_speed *= drag_speed_mult
		3: target_speed *= heavy_speed_mult

	var target_velocity := direction * target_speed
	_last_wind = Vector3(_wind.x, 0.0, _wind.z)
	_wind = Vector3.ZERO
	target_velocity += _last_wind

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if (has_input or _last_wind.length() > 0.1) else deceleration
	if mode > 0:
		rate *= carry_accel_mult
	rate *= surface_grip if on_floor else air_control
	if staggered:
		rate *= 0.15
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# На скользком склоне дрон съезжает вниз (и разгоняется на ледяных спусках)
	if on_floor and surface_grip < 0.5:
		var n := get_floor_normal()
		velocity.x += n.x * 9.8 * ice_slide * delta
		velocity.z += n.z * 9.8 * ice_slide * delta

	# --- Движение и столкновения ---
	var pre_move_velocity := velocity
	move_and_slide()
	_handle_collisions(pre_move_velocity, delta)

	var now_on_floor := is_on_floor()
	var just_landed := now_on_floor and not _was_on_floor
	if just_landed and _soft_landing:
		_soft_landing = false
		pre_move_velocity.y = maxf(pre_move_velocity.y, -safe_landing_speed)
	if just_landed:
		landed.emit(-pre_move_velocity.y)
		_noise_burst += clampf(-pre_move_velocity.y * 0.08, 0.0, 1.5)
		if -pre_move_velocity.y > fall_damage_speed:
			take_damage((-pre_move_velocity.y - fall_damage_speed) * fall_damage)

	_update_carry(delta, just_landed, pre_move_velocity)
	_update_noise(delta, has_input)
	_update_visual(delta, direction, target_speed, just_landed)
	_update_camera(delta)
	_update_hud()

	_was_on_floor = now_on_floor
	_prev_velocity = velocity

	if global_position.y < fall_limit_y:
		velocity = Vector3.ZERO
		if not is_dead:
			_die()

	_send_state(delta)


# ---------------------------------------------------------------------------
#  Сеть
# ---------------------------------------------------------------------------

func _send_state(delta: float) -> void:
	if not Network.in_game or not Network.is_online():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = SEND_INTERVAL
	var flags := 0
	if is_on_floor(): flags |= F_FLOOR
	if is_sprinting: flags |= F_SPRINT
	if _exhausted_timer > 0.0: flags |= F_EXHAUSTED
	if _stagger_timer > 0.0: flags |= F_STAGGER
	if is_dead: flags |= F_DEAD
	if is_on_safe_ground(): flags |= F_SAFE
	if surface_grip < 0.5: flags |= F_ICE
	if held_parcel != null: flags |= F_CARRY
	if is_swimming: flags |= F_SWIM
	if is_frozen: flags |= F_FROZEN
	if is_diving: flags |= F_DIVE
	_net_state.rpc(global_position, velocity, visual.rotation.y, flags, noise, frost, _break_progress)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, vel: Vector3, yaw: float, flags: int, net_noise: float, net_frost: float, aux: float) -> void:
	_net_pos = pos
	_net_prev_vy = _net_vel.y
	_net_vel = vel
	_net_yaw = yaw
	_net_flags = flags
	noise = net_noise
	_net_frost = net_frost
	_net_aux = aux


## Друг ударил по моей глыбе (E рядом) — она трескается сильнее
@rpc("any_peer", "call_remote", "reliable")
func _rpc_chip_ice() -> void:
	if is_local and is_frozen:
		_break_progress += buddy_chip
		_block_jolt = 1.0


@rpc("authority", "call_remote", "reliable")
func _net_splash_fx(pos: Vector3) -> void:
	_splash_fx.global_position = pos
	_splash_fx.restart()


@rpc("authority", "call_remote", "reliable")
func _net_hit_fx(pos: Vector3) -> void:
	sparks.global_position = pos
	sparks.restart()


## Копия чужого дрона: плавно повторяем присланное состояние.
func _puppet_process(delta: float) -> void:
	if global_position.distance_to(_net_pos) > 6.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, clampf(delta * 15.0, 0.0, 1.0))
	velocity = _net_vel
	is_sprinting = (_net_flags & F_SPRINT) != 0
	is_dead = (_net_flags & F_DEAD) != 0
	_exhausted_timer = 1.0 if (_net_flags & F_EXHAUSTED) != 0 else 0.0
	if (_net_flags & F_STAGGER) != 0:
		if _stagger_timer <= 0.0:
			_stagger_total = 0.6
			_stagger_timer = 0.6
			_stagger_strength = 0.7
		_stagger_timer = maxf(_stagger_timer - delta, 0.05)
	else:
		_stagger_timer = 0.0
	surface_grip = 0.1 if (_net_flags & F_ICE) != 0 else 1.0
	is_swimming = (_net_flags & F_SWIM) != 0
	is_diving = (_net_flags & F_DIVE) != 0
	frost = _net_frost
	var was_frozen := is_frozen
	is_frozen = (_net_flags & F_FROZEN) != 0
	if is_frozen and not was_frozen:
		_block_grow = 0.0
		_chunks_fx.restart()
	elif was_frozen and not is_frozen:
		_play_shatter()
	if _net_aux > _break_progress + 0.01:
		_block_jolt = 1.0
	_break_progress = _net_aux

	var grounded := is_grounded()
	var just_landed := grounded and not _net_was_floor
	if just_landed:
		landed.emit(-_net_prev_vy)
	_net_was_floor = grounded

	_update_visual(delta, Vector3.ZERO, walk_speed, just_landed)
	visual.rotation.y = lerp_angle(visual.rotation.y, _net_yaw, clampf(delta * 15.0, 0.0, 1.0))


# ---------------------------------------------------------------------------
#  Публичные функции (для уровня, опасностей и посылок)
# ---------------------------------------------------------------------------

func is_grounded() -> bool:
	return is_on_floor() if is_local else (_net_flags & F_FLOOR) != 0


func is_carrying() -> bool:
	return held_parcel != null if is_local else (_net_flags & F_CARRY) != 0


func is_on_safe_ground() -> bool:
	if not is_local:
		return (_net_flags & F_SAFE) != 0
	return is_on_floor() and _floor_collider != null and is_instance_valid(_floor_collider) \
		and (_floor_collider as Node).is_in_group("safe_ground")


func get_floor_body() -> Object:
	return _floor_collider


func get_noise() -> float:
	return noise


func get_held_parcel() -> Parcel:
	return held_parcel


## Где держать обычную посылку (у хозяина — с покачиванием)
func get_carry_transform() -> Transform3D:
	var yaw_basis := Basis(Vector3.UP, visual.global_rotation.y)
	return Transform3D(yaw_basis * _carry_basis, hold_point.global_position + _parcel_offset)


## Точка захвата тяжёлого груза (центр корпуса)
func get_heavy_hold_point() -> Vector3:
	return body.global_position


## Куда тянуть тяжёлый груз волоком
func get_drag_point() -> Vector3:
	return global_position + (-visual.global_basis.z) * 1.2 + Vector3.UP * 0.4


## Посылка сообщает, что список носильщиков изменился
func on_parcel_holders_changed(p: Parcel) -> void:
	var mine := p.holders.has(peer_id)
	if mine and held_parcel != p:
		held_parcel = p
		instability = 0.0
		_parcel_offset = Vector3.ZERO
		_carry_basis = Basis.IDENTITY
		_releasing = false
	elif not mine and held_parcel == p:
		held_parcel = null
		instability = 0.0
		_releasing = false
		_pickup_cooldown = 0.4


func take_damage(amount: float) -> void:
	if not is_local or is_dead or _invuln_timer > 0.0 or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	damage_flash.color.a = clampf(0.15 + amount * 0.01, 0.15, 0.45)
	if health <= 0.0:
		_die()


func receive_hit(direction: Vector3, strength: float, contact: Vector3) -> void:
	if not is_local or is_dead or _invuln_timer > 0.0:
		return
	var spark_point := (global_position + Vector3.UP * BODY_HEIGHT).lerp(contact, 0.5)
	_take_impact(direction, strength, spark_point, hazard_knockback, strength * hazard_damage)


func receive_avalanche(push_dir: Vector3) -> void:
	if not is_local or is_dead or _invuln_timer > 0.0:
		return
	if held_parcel != null:
		_fumble()
	_hit_cooldown = 0.0
	_take_impact(push_dir, 13.0, global_position + Vector3.UP * BODY_HEIGHT, 1.1, 35.0)
	_stagger_total = 1.4
	_stagger_timer = 1.4
	_shake = 0.5


func kill(reason: String = "") -> void:
	if not is_local or is_dead:
		return
	if reason != "":
		death_label.text = reason + "\nВозвращаемся в лагерь..."
	_die()


## Подбросить вверх (трамплин, гейзер). Можно добавить урон и раскачку посылки.
func launch(up_speed: float, damage: float = 0.0, parcel_shake: float = 0.0, parcel_damage: float = 0.0, soft_landing: bool = false) -> void:
	if not is_local or is_dead:
		return
	velocity.y = maxf(velocity.y, up_speed)
	if soft_landing:
		_soft_landing = true
	_coyote_timer = 0.0
	_thruster_power = 5.0
	_noise_burst += 0.6
	body.scale = Vector3(0.85, 1.15, 0.85)
	if damage > 0.0:
		take_damage(damage)
		_shake = maxf(_shake, 0.2)
	if held_parcel != null:
		if parcel_shake > 0.0 and _carry_mode() != 2:
			instability += parcel_shake
		if parcel_damage > 0.0:
			held_parcel.take_damage(parcel_damage)


func apply_wind(wind_velocity: Vector3) -> void:
	if is_local:
		_wind += wind_velocity


func add_shake(amount: float) -> void:
	if is_local:
		_shake = maxf(_shake, amount)


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	is_dead = false
	health = max_health
	stamina = stamina_max
	_exhausted_timer = 0.0
	_stagger_timer = 0.0
	_invuln_timer = invulnerable_time
	body.rotation = Vector3.ZERO
	frost = 0.0
	_leave_water_state()
	is_frozen = false
	_break_progress = 0.0
	_block_grow = 0.0
	_wet_timer = 0.0
	_freeze_immunity = 0.0
	death_label.text = _default_death_text
	health_changed.emit(health, max_health)
	respawned.emit()


func _die() -> void:
	is_dead = true
	_dead_timer = respawn_delay
	is_sprinting = false
	_shake = 0.4
	sparks.global_position = global_position + Vector3.UP * BODY_HEIGHT
	sparks.restart()
	if held_parcel != null:
		_release_held(held_parcel.global_transform, Vector3(velocity.x, 1.5, velocity.z))
	died.emit()


# ---------------------------------------------------------------------------
#  Вода: плавание, выход на лёд, обледенение
# ---------------------------------------------------------------------------

func _frost_ratio() -> float:
	return clampf(frost / frost_full, 0.0, 1.0)


func _frost_mult() -> float:
	return lerpf(1.0, frost_min_speed, _frost_ratio())


## Направление ввода относительно камеры (по горизонтали)
func _camera_direction() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	return right * input_dir.x - forward * input_dir.y


## Обледенение за кадр. water_depth: глубина в воде (м) или -1 — на воздухе.
func _frost_tick(delta: float, water_depth: float) -> void:
	_freeze_immunity -= delta
	if water_depth >= 0.0:
		var rate := freeze_rate
		if is_diving:
			rate = dive_freeze_rate + dive_freeze_per_m * water_depth
		frost += rate * delta
	elif _wet_timer > 0.0 and _heat <= 1.0:
		_wet_timer -= delta          # мокрый корпус на морозе ещё обмерзает
		frost += wet_freeze * delta
	else:
		_wet_timer = 0.0
		frost -= thaw_rate * _heat * delta
	frost = clampf(frost, 0.0, frost_max)
	if frost >= frost_max:
		if _freeze_immunity > 0.0:
			frost = frost_max - 0.01   # только что вырвался из глыбы — даём время
		elif not is_frozen and not is_dead:
			_freeze_solid()


## Есть ли рядом жаровня (проверяем пару раз в секунду)
func _update_heat(delta: float) -> void:
	_heat_timer -= delta
	if _heat_timer > 0.0:
		return
	_heat_timer = 0.4
	_heat = 1.0
	for h in get_tree().get_nodes_in_group("heat_source"):
		var r: float = h.get("heat_radius") if h.get("heat_radius") != null else 6.0
		if (h as Node3D).global_position.distance_to(global_position) < r:
			_heat = heat_thaw_mult
			return


## R — стряхнуть лёд (стоит выносливости)
func _shake_off_ice() -> void:
	if frost < 0.3 or _shake_anim > 0.0 or stamina < shake_stamina * 0.5:
		return
	stamina = maxf(stamina - shake_stamina, 0.0)
	_regen_timer = stamina_regen_delay
	frost = maxf(frost - shake_amount, 0.0)
	_shake_anim = 0.45
	_chunks_fx.restart()
	_noise_burst += 0.3


## Вмёрз в глыбу
func _freeze_solid() -> void:
	is_frozen = true
	_break_progress = 0.0
	_block_grow = 0.0
	is_sprinting = false
	_wet_timer = 0.0
	_shake = maxf(_shake, 0.35)
	_noise_burst += 0.8
	_chunks_fx.restart()
	if held_parcel != null:
		_release_held(held_parcel.global_transform, Vector3(velocity.x * 0.5, 1.0, velocity.z * 0.5))
	if is_swimming:
		is_swimming = false
		is_diving = true      # в воде глыба всплывает (это делает _frozen_process)


## Глыба: стоим/скользим (на льду) или всплываем (в воде), жмём кнопки — раскалываем
func _frozen_process(delta: float) -> void:
	for a in BREAK_KEYS:
		if Input.is_action_just_pressed(a):
			_break_progress += 1.0 / maxf(break_presses, 1)
			_block_jolt = 1.0
	# сама понемногу оттаивает (у жаровни — быстро), чтобы не застрять навсегда
	_break_progress += (0.35 if _heat > 1.0 else 0.022) * delta

	if is_diving:
		# Лёд легче воды: глыба всплывает. В полынье держится на плаву, подо льдом упирается в лёд.
		var water: float = _lake.water_y(global_position.z)
		var depth := maxf(water - (global_position.y + BODY_HEIGHT), 0.0)
		velocity.y = move_toward(velocity.y, 1.3, 3.0 * delta)
		var cur := IceRiver.current_at(global_position.x, global_position.z) * smoothstep(0.8, 2.5, depth)
		var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(cur, 2.0 * delta)
		velocity.x = h.x
		velocity.z = h.z
		move_and_slide()
		var p := global_position
		if _lake.is_hole(p.x, p.z, -0.4):
			var float_y := water - 1.0 + sin(_time * 1.8) * 0.05
			if p.y > float_y:
				global_position.y = float_y
				velocity.y = 0.0
		elif p.y > water - 2.0:
			global_position.y = water - 2.0
			velocity.y = 0.0
	else:
		# На суше: глыба падает и скользит по льду
		if not is_on_floor():
			velocity += get_gravity() * fall_gravity_mult * delta
		var grip := surface_grip if is_on_floor() else 0.05
		var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 6.0 * grip * delta)
		velocity.x = h.x
		velocity.z = h.z
		move_and_slide()
		if global_position.y < fall_limit_y and not is_dead:
			velocity = Vector3.ZERO
			is_frozen = false
			_die()

	if _break_progress >= 1.0:
		_break_free()

	_update_noise(delta, false)
	_update_visual(delta, Vector3.ZERO, 0.0, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


## Глыба раскололась
func _break_free() -> void:
	is_frozen = false
	_break_progress = 0.0
	frost = frost_max * 0.6       # корка ещё осталась
	_freeze_immunity = 6.0
	_play_shatter()
	_shake = maxf(_shake, 0.3)
	body.scale = Vector3(1.25, 0.8, 1.25)
	_noise_burst += 1.0
	if not is_diving:
		velocity.y = 2.5


func _play_shatter() -> void:
	_block_grow = 0.0
	_ice_block.visible = false
	_shatter_fx.global_position = global_position + Vector3.UP * BODY_HEIGHT
	_shatter_fx.restart()


## Друг рядом вмёрз — E раскалывает его глыбу
func _find_frozen_buddy() -> Node:
	for d in get_tree().get_nodes_in_group("player"):
		if d != self and d.is_frozen and (d as Node3D).global_position.distance_to(global_position) < 2.4:
			return d
	return null


func _try_chip_buddy() -> bool:
	var buddy = _find_frozen_buddy()
	if buddy == null:
		return false
	buddy._block_jolt = 1.0
	if Network.in_game and Network.is_online():
		buddy._rpc_chip_ice.rpc_id(buddy.peer_id)
	body.scale = Vector3(0.85, 1.15, 0.85)
	arm_left.rotation.x = -1.4
	arm_right.rotation.x = -1.4
	_noise_burst += 0.3
	return true


func _enter_water() -> void:
	is_diving = true          # дрон тяжёлый — сразу уходит под воду
	is_swimming = false
	_swim_anchor = global_position
	_edge_point = Vector3.INF
	_edge_timer = 0.0
	_wet_timer = 0.0
	_heavy_timer = 0.0
	if _lake is PhysicsBody3D:
		add_collision_exception_with(_lake)
	velocity.y = clampf(velocity.y, -6.0, -1.0)
	is_sprinting = false
	_exhausted_timer = 0.0
	_stagger_timer = 0.0
	_noise_burst += 1.0
	_shake = maxf(_shake, 0.2)
	var splash_pos := Vector3(global_position.x, _lake.water_y(global_position.z) + 0.2, global_position.z)
	_splash_fx.global_position = splash_pos
	_splash_fx.restart()
	if Network.in_game and Network.is_online():
		_net_splash_fx.rpc(splash_pos)
	# Посылка выскальзывает из рук и плавает рядом
	if held_parcel != null:
		held_parcel.take_damage(5.0)
		_release_held(held_parcel.global_transform, Vector3(velocity.x * 0.3, 0.5, velocity.z * 0.3))


func _leave_water_state() -> void:
	if (is_swimming or is_diving) and _lake is PhysicsBody3D:
		remove_collision_exception_with(_lake)
	if (is_swimming or is_diving) and frost > 1.0:
		_wet_timer = wet_time
	is_swimming = false
	is_diving = false
	_edge_point = Vector3.INF


## Вынырнул в полынье
func _surface() -> void:
	is_diving = false
	is_swimming = true
	_heavy_timer = 0.0
	_swim_anchor = global_position
	velocity.y = 0.0
	var splash_pos := Vector3(global_position.x, _lake.water_y(global_position.z) + 0.2, global_position.z)
	_splash_fx.global_position = splash_pos
	_splash_fx.restart()
	if Network.in_game and Network.is_online():
		_net_splash_fx.rpc(splash_pos)


func _start_dive() -> void:
	is_swimming = false
	is_diving = true
	_heavy_timer = 0.0
	velocity.y = -1.0


## Под водой: тонем, пока не держишь Пробел. Подо льдом всплыть нельзя.
func _dive_process(delta: float) -> void:
	var water: float = _lake.water_y(global_position.z)
	var depth := maxf(water - (global_position.y + BODY_HEIGHT), 0.0)
	_frost_tick(delta, depth)
	if is_frozen:
		return
	if held_parcel != null:
		_release_held(held_parcel.global_transform, Vector3(0, 0.5, 0))

	var fr := _frost_ratio()
	var rising := Input.is_action_pressed("jump")
	var target_vy := -sink_speed * (1.0 + 0.6 * fr)
	if rising:
		target_vy = rise_speed * lerpf(1.0, 0.5, fr)
	velocity.y = move_toward(velocity.y, target_vy, (4.0 if target_vy > velocity.y else 2.5) * delta)

	var direction := _camera_direction()
	var current := IceRiver.current_at(global_position.x, global_position.z) * smoothstep(0.8, 2.5, depth)
	if is_on_floor():
		current *= 0.15   # стоящего на дне течение почти не сдвигает
	var speed := dive_speed * maxf(_frost_mult(), 0.5)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * speed + current, 4.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# В полынье — выныриваем; подо льдом упираемся в лёд
	var p := global_position
	var in_hole: bool = _lake.is_hole(p.x, p.z, -0.35)
	if in_hole and velocity.y > 0.0 and p.y >= water - float_depth - 0.05:
		_surface()   # выныриваем, только когда гребём вверх
	else:
		var ceiling := water - 1.5
		if not in_hole and p.y > ceiling:
			if velocity.y > 1.0:
				_shake = maxf(_shake, 0.12)          # стукнулся о лёд снизу
				body.scale = Vector3(1.15, 0.85, 1.15)
			global_position.y = ceiling
			velocity.y = minf(velocity.y, 0.0)

	# Давление на глубине
	if depth > pressure_depth:
		_pressure_timer -= delta
		if _pressure_timer <= 0.0:
			_pressure_timer = 0.5
			take_damage((depth - pressure_depth) * pressure_damage * 0.5)
			_shake = maxf(_shake, 0.1)
			if _uw:
				_uw.set("hurt", 1.0)
	else:
		_pressure_timer = 0.0

	_pickup_cooldown -= delta
	_update_noise(delta, false)
	_update_visual(delta, direction, speed, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


func _swim_process(delta: float) -> void:
	_frost_tick(delta, 0.0)
	if is_frozen:
		return

	# Держимся на плаву
	var water: float = _lake.water_y(global_position.z)
	var target_y := water - float_depth + sin(_time * 2.2) * 0.05
	velocity.y = lerpf(velocity.y, (target_y - global_position.y) * 5.0, clampf(6.0 * delta, 0.0, 1.0))

	# Обледеневший дрон тяжёлый: без Пробела снова уходит под воду. Ctrl — нырнуть.
	if _frost_ratio() > 0.6 and not Input.is_action_pressed("jump"):
		_heavy_timer += delta
	else:
		_heavy_timer = maxf(_heavy_timer - delta * 2.0, 0.0)
	if _heavy_timer > 1.2 or Input.is_action_just_pressed("quiet"):
		_start_dive()
		return

	# Гребём относительно камеры
	var direction := _camera_direction()
	var speed := swim_speed * maxf(_frost_mult(), 0.55)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * speed, 8.0 * delta)

	# По поверхности под лёд не заплыть: впереди лёд — останавливаемся у края
	var here := global_position
	if horizontal.length() > 0.05:
		var ahead := here + horizontal.normalized() * 0.55
		if not _lake.is_hole(ahead.x, ahead.z):
			horizontal = Vector3.ZERO
	# Если над головой оказался лёд (полынья затянулась/сдвинулись) — уходим под воду
	if not _lake.is_hole(here.x, here.z):
		_start_dive()
		return
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# Посылка в руках мокнет
	if held_parcel != null:
		_soak_timer += delta
		if _soak_timer >= 1.0:
			_soak_timer = 0.0
			held_parcel.take_damage(parcel_soak)

	# Где ближайший край льда (проверяем не каждый кадр)
	_edge_timer -= delta
	if _edge_timer <= 0.0:
		_edge_timer = 0.12
		var prefer := -visual.global_basis.z
		if direction.length() > 0.1:
			prefer = direction.normalized()
		_edge_point = _lake.nearest_ice(global_position, climb_reach, prefer)

	# Посылку можно выловить из воды (E) или отпустить; E рядом с вмёрзшим другом — разбить лёд
	if not _releasing and Input.is_action_just_pressed("interact"):
		if held_parcel:
			_release_held(held_parcel.global_transform, Vector3.ZERO)
		elif not _try_chip_buddy():
			_try_pick_up()
	if _releasing:
		_release_timer -= delta
		if _release_timer <= 0.0:
			_releasing = false
	_pickup_cooldown -= delta

	if _edge_point != Vector3.INF and Input.is_action_just_pressed("jump"):
		_climb_out()
		return

	_update_noise(delta, false)
	_update_visual(delta, direction, speed, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


func _climb_out() -> void:
	if _edge_point == Vector3.INF:
		return
	var target := _edge_point
	var to := target - global_position
	to.y = 0.0
	_leave_water_state()
	global_position = target
	velocity = to.normalized() * 1.5 + Vector3.UP * 2.0
	_was_on_floor = false
	body.scale = Vector3(0.85, 1.2, 0.85)
	_thruster_power = 4.0
	if to.length() > 0.05:
		visual.rotation.y = atan2(-to.x, -to.z)


# ---------------------------------------------------------------------------
#  Камера
# ---------------------------------------------------------------------------

func _rotate_camera(yaw: float, pitch: float) -> void:
	camera_pivot.rotation.y += yaw
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x + pitch,
		deg_to_rad(min_pitch_deg),
		deg_to_rad(max_pitch_deg)
	)


func _handle_gamepad_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		_rotate_camera(-look.x * joy_look_speed * delta, -look.y * joy_look_speed * delta)


func _update_camera(delta: float) -> void:
	var running := is_sprinting and Vector3(velocity.x, 0.0, velocity.z).length() > walk_speed
	camera.fov = lerpf(camera.fov, sprint_fov if running else base_fov, 6.0 * delta)
	var arm := 5.2 if running else 4.5
	if is_diving:
		arm = 3.0    # под водой мутно — камера ближе к дрону
	spring_arm.spring_length = lerpf(spring_arm.spring_length, arm, 4.0 * delta)
	_shake = maxf(_shake - delta * 1.2, 0.0)
	var shake := _shake
	if running and is_on_floor():
		shake += 0.012
	camera.h_offset = randf_range(-1.0, 1.0) * shake
	camera.v_offset = randf_range(-1.0, 1.0) * shake


# ---------------------------------------------------------------------------
#  Выносливость, шум
# ---------------------------------------------------------------------------

func _update_stamina(delta: float, has_input: bool, carrying: bool) -> void:
	if _exhausted_timer > 0.0:
		_exhausted_timer -= delta
		is_sprinting = false
		stamina = minf(stamina + stamina_regen * 0.5 * delta, stamina_max)
		return

	if Input.is_action_pressed("sprint"):
		_sprint_hold += delta
	else:
		_sprint_hold = 0.0
	var wants_sprint := _sprint_hold >= sprint_hold_time and has_input and stamina > 0.0 \
		and _frost_ratio() < 0.25
	if wants_sprint and not is_sprinting:
		_thruster_power = 4.0
		body.scale = Vector3(0.88, 1.12, 0.88)
	is_sprinting = wants_sprint

	if is_sprinting:
		stamina -= stamina_drain * (carry_stamina_mult if carrying else 1.0) * delta
		_regen_timer = stamina_regen_delay
		if stamina <= 0.0:
			stamina = 0.0
			is_sprinting = false
			_exhausted_timer = exhausted_duration
			body.scale = Vector3(1.15, 0.85, 1.15)
			if held_parcel:
				instability += 0.2
	else:
		_regen_timer -= delta
		if _regen_timer <= 0.0:
			stamina = minf(stamina + stamina_regen * delta, stamina_max)


func _update_noise(delta: float, has_input: bool) -> void:
	var base := 0.0
	var moving := is_on_floor() and Vector3(velocity.x, 0.0, velocity.z).length() > 0.5
	if moving and has_input:
		if is_sprinting:
			base = run_noise
		elif Input.is_action_pressed("quiet"):
			base = quiet_noise
		else:
			base = walk_noise
	_noise_burst = maxf(_noise_burst - delta * 1.5, 0.0)
	noise = clampf(base + _noise_burst, 0.0, 2.0)


# ---------------------------------------------------------------------------
#  Поверхность и столкновения
# ---------------------------------------------------------------------------

func _update_surface_grip() -> void:
	surface_grip = 1.0
	_floor_collider = null
	if not is_on_floor():
		return
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3,
		global_position + Vector3.DOWN * 0.3
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	_floor_collider = collider
	var mat: PhysicsMaterial = null
	if collider is StaticBody3D:
		mat = (collider as StaticBody3D).physics_material_override
	elif collider is RigidBody3D:
		mat = (collider as RigidBody3D).physics_material_override
	if mat:
		surface_grip = clampf(mat.friction, min_grip, 1.0)


func _handle_collisions(pre_velocity: Vector3, delta: float) -> void:
	var strongest := 0.0
	var hit_normal := Vector3.ZERO
	var hit_point := Vector3.ZERO
	var pre_h := Vector3(pre_velocity.x, 0.0, pre_velocity.z)

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.6:
			continue
		var into := -pre_h.dot(n)
		var rb := col.get_collider() as RigidBody3D
		if rb != null:
			# Физику предметов считает хост — пинать их может только он
			if multiplayer.is_server():
				var push_dir := Vector3(-n.x, 0.0, -n.z).normalized()
				var kick := 0.0
				if into > hit_threshold:
					kick = into * minf(rb.mass, 5.0) * kick_strength
				rb.apply_impulse(push_dir * (push_force * delta + kick), col.get_position() - rb.global_position)
			into *= clampf(rb.mass / light_object_mass, 0.0, 1.0)
		if into > strongest:
			strongest = into
			hit_normal = n
			hit_point = col.get_position()

	if strongest > hit_threshold:
		var dmg := (strongest - hit_threshold + 2.0) * wall_damage
		_take_impact(hit_normal, strongest, hit_point, wall_knockback, dmg)


func _take_impact(push_dir: Vector3, strength: float, contact: Vector3, knock_mult: float, health_damage: float) -> void:
	if _hit_cooldown > 0.0:
		return
	_hit_cooldown = 0.3
	_noise_burst += 1.2

	push_dir.y = 0.0
	push_dir = push_dir.normalized()
	velocity.x = push_dir.x * strength * knock_mult
	velocity.z = push_dir.z * strength * knock_mult
	velocity.y = maxf(velocity.y, minf(1.5 + strength * 0.25, 5.0))

	_stagger_total = clampf(0.2 + strength * 0.06, 0.25, 0.9)
	_stagger_timer = _stagger_total
	_stagger_strength = clampf(strength / 8.0, 0.3, 1.0)
	_shake = clampf(strength * 0.03, 0.05, 0.35)
	body.scale = Vector3(1.2, 0.8, 1.2)
	sparks.global_position = contact
	sparks.restart()
	if Network.in_game and Network.is_online():
		_net_hit_fx.rpc(contact)

	take_damage(health_damage)

	if held_parcel != null:
		held_parcel.take_damage(strength * hit_damage)
		if _carry_mode() != 2:
			instability += strength * hit_instability


# ---------------------------------------------------------------------------
#  Переноска
# ---------------------------------------------------------------------------

## 0 — ничего, 1 — обычная посылка, 2 — тяну тяжёлый груз один, 3 — несём тяжёлый вдвоём
func _carry_mode() -> int:
	if held_parcel == null:
		return 0
	if held_parcel.required_carriers <= 1:
		return 1
	return 3 if held_parcel.is_lifted() else 2


func _find_nearest_parcel() -> Parcel:
	var best: Parcel = null
	var best_dist := INF
	for node in pickup_zone.get_overlapping_bodies():
		var p := node as Parcel
		if p == null or not p.can_be_grabbed_by(peer_id):
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _try_pick_up() -> void:
	if _pickup_cooldown > 0.0 or _stagger_timer > 0.0 or is_dead or held_parcel != null:
		return
	var p := _find_nearest_parcel()
	if p == null:
		return
	_pickup_cooldown = 0.3
	p.request_pickup(peer_id)   # хост решит и сообщит всем


func _put_down() -> void:
	if _carry_mode() == 1:
		var forward := -visual.global_basis.z
		var pos := global_position + forward * 0.9 + Vector3.UP * 0.35
		_release_held(Transform3D(Basis(Vector3.UP, visual.global_rotation.y), pos),
			Vector3(velocity.x, 0.0, velocity.z) * 0.5)
	else:
		_release_held(held_parcel.global_transform, Vector3(velocity.x, 0.0, velocity.z) * 0.5)


func _throw() -> void:
	var forward := -visual.global_basis.z
	_release_held(held_parcel.global_transform, velocity + forward * throw_speed + Vector3.UP * 3.0)


func _fumble() -> void:
	var forward := -visual.global_basis.z
	var side := visual.global_basis.x * randf_range(-1.5, 1.5)
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	held_parcel.take_damage(fumble_damage + speed * 1.5)
	_release_held(held_parcel.global_transform, velocity + forward * 1.5 + side + Vector3.UP * 2.5)


func _release_held(xform: Transform3D, vel: Vector3) -> void:
	if held_parcel == null:
		return
	_releasing = true
	_release_timer = 1.0
	_pickup_cooldown = 0.4
	instability = 0.0
	held_parcel.request_release(peer_id, xform, vel)


func _update_carry(delta: float, just_landed: bool, pre_move_velocity: Vector3) -> void:
	if held_parcel == null or _releasing:
		return
	var mode := _carry_mode()
	if mode == 2:
		instability = 0.0
		return

	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	var prev_h := Vector3(_prev_velocity.x, 0.0, _prev_velocity.z)
	var accel_vec := (h_vel - prev_h) / delta
	var speed_mult := carry_speed_mult if mode == 1 else heavy_speed_mult
	var carry_walk := walk_speed * speed_mult
	var carry_sprint := sprint_speed * speed_mult

	if is_sprinting and h_vel.length() > carry_walk * 0.9:
		instability += sprint_instability * delta
	var speed_over := clampf((prev_h.length() - carry_walk) / maxf(carry_sprint - carry_walk, 0.01), 0.0, 1.0)
	if _stagger_timer <= 0.0:
		instability += accel_vec.length() * speed_over * turn_instability * delta
	instability += _last_wind.length() * wind_instability * delta
	if just_landed:
		instability += maxf(0.0, -pre_move_velocity.y - safe_landing_speed) * landing_instability
	if not is_sprinting:
		var rec := stability_recovery * (1.0 if h_vel.length() < 0.5 else 0.6)
		instability = maxf(0.0, instability - rec * delta)

	if instability >= 1.0:
		_fumble()
		return

	var target_offset := (-accel_vec * 0.012).limit_length(0.25)
	_parcel_offset = _parcel_offset.lerp(target_offset, 10.0 * delta)
	_wobble_time += delta
	var w := instability * 0.4
	_carry_basis = Basis.from_euler(Vector3(
		sin(_wobble_time * 17.0) * w, 0.0, sin(_wobble_time * 13.0 + 1.3) * w))


# ---------------------------------------------------------------------------
#  Анимация (работает и для своего дрона, и для копий)
# ---------------------------------------------------------------------------

func _update_visual(delta: float, direction: Vector3, target_speed: float, just_landed: bool) -> void:
	var on_floor := is_grounded()
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var has_input := direction.length() > 0.1
	var exhausted := _exhausted_timer > 0.0
	var staggered := _stagger_timer > 0.0
	var running := is_sprinting and on_floor and h_speed > walk_speed * 0.8
	var carrying := is_carrying()
	var in_water := is_swimming or is_diving
	var fr := clampf(frost / frost_full, 0.0, 1.0)

	_update_frost_visual(delta)
	if is_frozen:
		return   # в глыбе дрон застыл в той позе, в которой его схватило

	if has_input:
		var target_yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, turn_speed * delta)

	var lean := -(h_speed / sprint_speed) * 0.2
	if running:
		lean = -0.4
	if exhausted:
		lean = -0.3
	if staggered:
		lean = 0.3
	if is_dead:
		lean = 0.2
	body.rotation.x = lerpf(body.rotation.x, lean, 8.0 * delta)

	var stagger_z := 0.0
	if staggered:
		var fade := _stagger_timer / _stagger_total
		stagger_z = sin(_time * 28.0) * 0.45 * _stagger_strength * fade
	if is_dead:
		stagger_z = 1.3
	# Обледеневший дрон дрожит, а когда стряхивает лёд — трясётся всем корпусом
	if fr > 0.4 and not in_water and not is_dead:
		stagger_z += sin(_time * 41.0) * 0.03 * fr
	if _shake_anim > 0.0:
		stagger_z += sin(_time * 48.0) * 0.4 * (_shake_anim / 0.45)
	body.rotation.z = lerpf(body.rotation.z, stagger_z, (6.0 if is_dead else 20.0) * delta)

	var hip_l := 0.0
	var hip_r := 0.0
	var knee_l := 0.0
	var knee_r := 0.0
	var bob := 0.0

	if in_water:
		# Плывёт: ноги гребут, корпус покачивается; под водой с Пробелом гребёт чаще
		var paddle := 7.0
		if is_diving:
			paddle = 10.0 if velocity.y > 0.2 else 3.5
		_stride_phase += delta * paddle
		hip_l = sin(_stride_phase) * 0.7 + 0.4
		hip_r = -sin(_stride_phase) * 0.7 + 0.4
		knee_l = -0.6 - maxf(cos(_stride_phase), 0.0) * 0.6
		knee_r = -0.6 - maxf(-cos(_stride_phase), 0.0) * 0.6
		bob = sin(_time * 2.2) * 0.04
	elif is_dead:
		knee_l = -1.2
		knee_r = -1.2
		hip_l = 0.6
		hip_r = 0.6
		bob = -0.35
	elif not on_floor:
		hip_l = 0.5
		hip_r = -0.2
		knee_l = -1.0
		knee_r = -0.6
	elif h_speed > 0.3 or has_input:
		var stride_speed := h_speed
		if surface_grip < 0.5 and is_local:
			stride_speed = maxf(h_speed, target_speed) * 1.4 if has_input else 0.0
		_stride_phase += stride_speed * stride_frequency * delta
		var amount := clampf(stride_speed / walk_speed, 0.0, 1.3) * leg_swing
		if running:
			amount *= 1.35
		amount *= lerpf(1.0, 0.5, fr)   # во льду ноги гнутся плохо — шаги короткие и скованные
		var s := sin(_stride_phase)
		var c := cos(_stride_phase)
		hip_l = s * amount
		hip_r = -s * amount
		knee_l = -maxf(c, 0.0) * amount * 1.7
		knee_r = -maxf(-c, 0.0) * amount * 1.7
		bob = absf(c) * (0.09 if running else 0.05) * minf(amount / leg_swing, 1.3)
	elif exhausted:
		knee_l = -0.35
		knee_r = -0.35
		hip_l = 0.15
		hip_r = 0.15
		bob = -0.08 + sin(_time * 10.0) * 0.03
	else:
		bob = sin(_time * 2.0) * 0.015

	var k := 15.0 * delta * lerpf(1.0, 0.35, fr)
	leg_left.rotation.x = lerpf(leg_left.rotation.x, hip_l, k)
	leg_right.rotation.x = lerpf(leg_right.rotation.x, hip_r, k)
	knee_left.rotation.x = lerpf(knee_left.rotation.x, knee_l, k)
	knee_right.rotation.x = lerpf(knee_right.rotation.x, knee_r, k)

	var arm_l := -hip_l * 0.7
	var arm_r := -hip_r * 0.7
	if carrying:
		arm_l = 1.5
		arm_r = 1.5
	elif in_water:
		arm_l = sin(_stride_phase + 1.2) * 1.2 + 0.6   # гребёт руками
		arm_r = -sin(_stride_phase + 1.2) * 1.2 + 0.6
	elif staggered:
		arm_l = sin(_time * 22.0) * 0.9 + 0.6
		arm_r = -sin(_time * 22.0) * 0.9 + 0.6
	elif running:
		arm_l = -0.9 - hip_l * 0.4
		arm_r = -0.9 - hip_r * 0.4
	elif exhausted:
		arm_l = 0.2
		arm_r = 0.2
	arm_left.rotation.x = lerpf(arm_left.rotation.x, arm_l, 14.0 * delta)
	arm_right.rotation.x = lerpf(arm_right.rotation.x, arm_r, 14.0 * delta)

	body.position.y = lerpf(body.position.y, BODY_HEIGHT + bob, 12.0 * delta)
	if just_landed:
		body.scale = Vector3(1.15, 0.85, 1.15)
	body.scale = body.scale.lerp(Vector3.ONE, 10.0 * delta)

	var thrust_target := 0.3
	if not on_floor:
		thrust_target = 1.5
	if in_water:
		thrust_target = 0.0
	if running:
		thrust_target = 2.5
	_thruster_power = lerpf(_thruster_power, thrust_target, 10.0 * delta)
	var flicker := 1.0 + randf_range(-0.08, 0.08)
	thruster_light.light_energy = _thruster_power * flicker
	thruster_glow.scale = Vector3.ONE * (0.6 + _thruster_power * 0.15) * flicker
	sprint_trail.emitting = running
	steam.emitting = exhausted or is_dead or (_heat > 1.0 and frost > 0.5)

	visual.visible = not (_invuln_timer > 0.0 and fmod(_time, 0.2) < 0.07)


## Лёд на дроне: корка, сосульки, отваливающиеся куски, глыба
func _update_frost_visual(delta: float) -> void:
	var vis := clampf(frost / frost_max, 0.0, 1.0)
	if is_frozen:
		vis = 1.0
	_frost_mat.set_shader_parameter("amount", vis)
	if _shell_mat:
		_shell_mat.albedo_color = player_color.lerp(Color(0.82, 0.92, 1.0), vis * 0.7)
		_shell_mat.roughness = lerpf(0.38, 0.85, vis)
		_shell_mat.metallic = lerpf(0.55, 0.15, vis)

	# Сосульки отрастают по одной и покачиваются
	for i in _icicles.size():
		var info := _icicle_info[i]
		var length := info.y * clampf((vis - info.x) / 0.2, 0.0, 1.0)
		var ic := _icicles[i]
		ic.visible = length > 0.01
		if ic.visible:
			ic.scale = Vector3(1.0, length, 1.0)
			ic.position.y = info.z - length * 0.5
			ic.rotation.z = sin(_time * 3.0 + i) * 0.06

	# При таянии и стряхивании лёд отваливается кусками
	var step := int(frost)
	if step < _last_frost_step and not is_swimming and not is_diving and not is_frozen:
		_chunks_fx.restart()
	_last_frost_step = step

	var in_water := is_swimming or is_diving
	_frost_sparkles.emitting = vis > 0.15 and not in_water and not is_frozen
	_drips.emitting = (is_swimming or (vis > 0.25 and _heat > 1.0) or _wet_timer > 0.0) and not is_diving
	_bubbles.emitting = is_diving

	# Глыба: быстро нарастает, трясётся от ударов, трещины растут
	_block_grow = move_toward(_block_grow, 1.0 if is_frozen else 0.0, delta * 3.0)
	_ice_block.visible = is_frozen and _block_grow > 0.01
	if _ice_block.visible:
		_block_jolt = move_toward(_block_jolt, 0.0, delta * 4.0)
		var j := _block_jolt * 0.07
		_ice_block.position = Vector3(randf_range(-j, j), BODY_HEIGHT + randf_range(-j, j) * 0.5, randf_range(-j, j))
		var g := 1.0 - pow(1.0 - _block_grow, 3.0)
		_ice_block.scale = Vector3(g, g, g)
		_block_mat.set_shader_parameter("cracks", _break_progress)


# ---------------------------------------------------------------------------
#  Интерфейс (только свой дрон)
# ---------------------------------------------------------------------------

func _update_hud() -> void:
	var mode := _carry_mode()
	if _frost_row:
		_frost_row.visible = frost > 0.05 or is_frozen
		if is_frozen:
			_frost_caption.text = "Лёд трескается"
			_frost_bar.value = _break_progress
			_frost_bar.modulate = Color(1.0, 1.0, 1.0)
		else:
			_frost_caption.text = "Обледенение"
			var fv := clampf(frost / frost_max, 0.0, 1.0)
			_frost_bar.value = fv
			var col := Color(0.6, 0.85, 1.0)
			if fv > 0.75:   # вот-вот вмёрзнет — полоска мигает
				col = col.lerp(Color(1, 1, 1), (sin(_time * 14.0) + 1.0) * 0.5)
			_frost_bar.modulate = col
	if is_frozen or is_diving:
		if is_frozen:
			prompt_label.text = "ЗАМЁРЗ В ГЛЫБУ!  Жми Пробел и WASD, чтобы расколоть лёд"
			if _heat > 1.0:
				prompt_label.text += "\nЖаровня рядом — лёд тает"
		else:
			var p := global_position
			var depth := maxf(_lake.water_y(p.z) - (p.y + BODY_HEIGHT), 0.0)
			if _lake.is_hole(p.x, p.z):
				prompt_label.text = "Глубина %.1f м — держи Пробел, чтобы всплыть" % depth
			else:
				prompt_label.text = "Ты подо льдом! Плыви к столбам света — там полынья.  Пробел — вверх"
			if depth > pressure_depth:
				prompt_label.text += "\nДАВЛЕНИЕ! Корпус трещит — поднимайся!"
		parcel_label.visible = false
		stability_row.visible = false
		stamina_row.visible = false
		var hp0 := health / max_health
		health_bar.value = hp0
		health_bar.modulate = Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), hp0)
		death_label.visible = is_dead
		damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, get_physics_process_delta_time() * 0.8)
		return
	if is_swimming:
		prompt_label.text = "Пробел — выбраться на лёд" if _edge_point != Vector3.INF else "Ты в воде! Плыви к краю полыньи"
		if _frost_ratio() > 0.6:
			prompt_label.text += "\nТяжёлый ото льда — держи Пробел, иначе утонешь"
		parcel_label.visible = held_parcel != null
		if held_parcel != null:
			parcel_label.text = "%s мокнет — %d кр" % [held_parcel.display_name, held_parcel.price]
		stability_row.visible = false
		stamina_row.visible = false
		health_bar.value = health / max_health
		death_label.visible = false
		damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, get_physics_process_delta_time() * 0.8)
		return
	if held_parcel != null:
		parcel_label.visible = true
		parcel_label.text = "%s — %d кр" % [held_parcel.display_name, held_parcel.price]
		match mode:
			1:
				prompt_label.text = "E — положить     Q — бросить"
			2:
				prompt_label.text = "Тяжело! Нужен второй курьер — пока тянешь волоком.  E — отпустить"
			3:
				var partner_far := false
				for d in held_parcel._holder_drones():
					if d != self and d.global_position.distance_to(global_position) > heavy_warn_distance:
						partner_far = true
				prompt_label.text = "Держитесь ближе друг к другу!" if partner_far else "Несёте вдвоём.  E — поставить"
		stability_row.visible = mode != 2
		var s := 1.0 - instability
		stability_bar.value = s
		var col := Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), s)
		if s < 0.3:
			col = col.lerp(Color.WHITE, (sin(_time * 20.0) + 1.0) * 0.25)
		stability_bar.modulate = col
	else:
		var p := _find_nearest_parcel()
		if _find_frozen_buddy() != null:
			prompt_label.text = "E — разбить лёд вокруг друга"
		elif p == null:
			prompt_label.text = ""
			if _wet_timer > 0.0:
				prompt_label.text = "Мокрый корпус замерзает на морозе!"
			elif frost > 2.0:
				prompt_label.text = "R — стряхнуть лёд" + ("  (у жаровни тает быстро)" if _heat <= 1.0 else "  — жаровня греет")
		elif p.required_carriers > 1:
			prompt_label.text = "E — взяться за тяжёлый груз (нужно двое)"
		else:
			prompt_label.text = "E — взять посылку"
		parcel_label.visible = false
		stability_row.visible = false

	var exhausted := _exhausted_timer > 0.0
	stamina_row.visible = exhausted or is_sprinting or stamina < stamina_max - 0.5
	stamina_bar.value = stamina / stamina_max
	if exhausted:
		stamina_caption.text = "Выдохся!"
		stamina_bar.modulate = Color(1, 0.35, 0.3)
	else:
		stamina_caption.text = "Выносливость"
		stamina_bar.modulate = Color(1, 0.85, 0.35)

	var hp := health / max_health
	health_bar.value = hp
	health_bar.modulate = Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), hp)
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, get_physics_process_delta_time() * 0.8)
	death_label.visible = is_dead
