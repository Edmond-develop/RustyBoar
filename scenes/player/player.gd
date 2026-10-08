extends CharacterBody3D
## Курьерский дрон-шар на двух ногах (с поддержкой сети).
##
## У каждого дрона есть «хозяин» — игрок, чей номер записан в имени узла.
## Хозяин управляет дроном сам и 30 раз в секунду рассылает его состояние.
## На остальных компьютерах этот дрон — «копия»: плавно повторяет присланное.
##
## Механики (только у хозяина): бег и выносливость, переноска и устойчивость
## посылки, удары, здоровье, шум (для лавин), ветер.

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
@export var min_grip := 0.06

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
var _release_timer := 0.0

# Сеть: последнее присланное состояние (для копий)
var _send_timer := 0.0
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_prev_vy := 0.0
var _net_yaw := 0.0
var _net_flags := F_FLOOR
var _net_was_floor := true


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
		velocity.y = jump_velocity * (carry_jump_mult if mode == 1 else 1.0)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_thruster_power = 6.0
		_noise_burst += 0.5
		if mode == 1:
			instability += jump_instability

	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	# --- Взять / положить / бросить ---
	if not is_dead and not _releasing:
		if Input.is_action_just_pressed("interact"):
			if held_parcel:
				_put_down()
			else:
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

	# --- Движение и столкновения ---
	var pre_move_velocity := velocity
	move_and_slide()
	_handle_collisions(pre_move_velocity, delta)

	var now_on_floor := is_on_floor()
	var just_landed := now_on_floor and not _was_on_floor
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
	_net_state.rpc(global_position, velocity, visual.rotation.y, flags, noise)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, vel: Vector3, yaw: float, flags: int, net_noise: float) -> void:
	_net_pos = pos
	_net_prev_vy = _net_vel.y
	_net_vel = vel
	_net_yaw = yaw
	_net_flags = flags
	noise = net_noise


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
	spring_arm.spring_length = lerpf(spring_arm.spring_length, 5.2 if running else 4.5, 4.0 * delta)
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
	var wants_sprint := _sprint_hold >= sprint_hold_time and has_input and stamina > 0.0
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
	body.rotation.z = lerpf(body.rotation.z, stagger_z, (6.0 if is_dead else 20.0) * delta)

	var hip_l := 0.0
	var hip_r := 0.0
	var knee_l := 0.0
	var knee_r := 0.0
	var bob := 0.0

	if is_dead:
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

	var k := 15.0 * delta
	leg_left.rotation.x = lerpf(leg_left.rotation.x, hip_l, k)
	leg_right.rotation.x = lerpf(leg_right.rotation.x, hip_r, k)
	knee_left.rotation.x = lerpf(knee_left.rotation.x, knee_l, k)
	knee_right.rotation.x = lerpf(knee_right.rotation.x, knee_r, k)

	var arm_l := -hip_l * 0.7
	var arm_r := -hip_r * 0.7
	if carrying:
		arm_l = 1.5
		arm_r = 1.5
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
	if running:
		thrust_target = 2.5
	_thruster_power = lerpf(_thruster_power, thrust_target, 10.0 * delta)
	var flicker := 1.0 + randf_range(-0.08, 0.08)
	thruster_light.light_energy = _thruster_power * flicker
	thruster_glow.scale = Vector3.ONE * (0.6 + _thruster_power * 0.15) * flicker
	sprint_trail.emitting = running
	steam.emitting = exhausted or is_dead

	visual.visible = not (_invuln_timer > 0.0 and fmod(_time, 0.2) < 0.07)


# ---------------------------------------------------------------------------
#  Интерфейс (только свой дрон)
# ---------------------------------------------------------------------------

func _update_hud() -> void:
	var mode := _carry_mode()
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
		if p == null:
			prompt_label.text = ""
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
