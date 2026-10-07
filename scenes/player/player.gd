extends CharacterBody3D
## Курьерский дрон-шар на двух ногах.
##
## Бег тратит выносливость. Кончилась — дрон выдыхается: короткая пауза,
## пар из корпуса, потом медленный шаг, пока не отдышится.
##
## Устойчивость посылки падает от: бега с посылкой, резких манёвров на скорости,
## прыжков, жёстких приземлений и ударов. Сильный удар сразу роняет посылку.
##
## Столкновения: дрон отскакивает, шатается, летят искры, трясётся камера.

@export_group("Движение")
@export var walk_speed := 6.0
@export var sprint_speed := 11.5
@export var quiet_speed := 2.5
@export var acceleration := 40.0
@export var deceleration := 50.0
@export var air_control := 0.35
@export var turn_speed := 12.0
@export var min_grip := 0.06            ## Минимальное сцепление (на самом скользком льду)

@export_group("Выносливость")
@export var stamina_max := 100.0
@export var stamina_drain := 22.0       ## Расход в секунду при беге
@export var stamina_regen := 28.0       ## Восстановление в секунду
@export var stamina_regen_delay := 0.7  ## Пауза перед восстановлением после бега
@export var carry_stamina_mult := 1.3   ## С посылкой выдыхается быстрее
@export var exhausted_duration := 2.4   ## Сколько длится «выдохся»
@export var exhausted_pause := 0.6      ## Первые секунды — стоит на месте
@export var exhausted_speed_mult := 0.45

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
@export var throw_speed := 6.0
@export var sprint_instability := 0.16   ## В секунду, пока бежишь с посылкой
@export var turn_instability := 0.05     ## Резкие манёвры на скорости
@export var jump_instability := 0.12     ## За каждый прыжок
@export var landing_instability := 0.15  ## За каждый м/с жёсткого приземления
@export var safe_landing_speed := 7.0
@export var hit_instability := 0.14      ## За каждый м/с удара
@export var stability_recovery := 0.45   ## Как быстро посылка успокаивается
@export var fumble_damage := 10.0        ## % цены, теряемый при падении из рук
@export var hit_damage := 3.0            ## % цены за каждый м/с удара

@export_group("Столкновения")
@export var impact_threshold := 2.5      ## Удары слабее (м/с) не считаются
@export var wall_knockback := 0.6        ## Отскок от стен
@export var hazard_knockback := 1.0      ## Отлёт от маятников и толкателей
@export var light_object_mass := 20.0    ## Предметы легче почти не тормозят дрона
@export var kick_strength := 0.8         ## Как сильно дрон пинает предметы
@export var push_force := 40.0

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

@onready var visual: Node3D = $Visual
@onready var body: Node3D = $Visual/Body
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
@onready var prompt_label: Label = $CarryHUD/Panel/Prompt
@onready var parcel_label: Label = $CarryHUD/Panel/ParcelInfo
@onready var stability_row: Control = $CarryHUD/Panel/StabilityRow
@onready var stability_bar: ProgressBar = $CarryHUD/Panel/StabilityRow/Bar
@onready var stamina_row: Control = $CarryHUD/Panel/StaminaRow
@onready var stamina_caption: Label = $CarryHUD/Panel/StaminaRow/Caption
@onready var stamina_bar: ProgressBar = $CarryHUD/Panel/StaminaRow/Bar

var surface_grip := 1.0
var held_parcel: Parcel = null
var instability := 0.0
var stamina := 100.0
var is_sprinting := false

var _time := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _pickup_cooldown := 0.0
var _regen_timer := 0.0
var _exhausted_timer := 0.0
var _stagger_timer := 0.0
var _stagger_total := 1.0
var _stagger_strength := 0.0
var _hit_cooldown := 0.0
var _shake := 0.0
var _spawn_position := Vector3.ZERO
var _prev_velocity := Vector3.ZERO
var _was_on_floor := true
var _stride_phase := 0.0
var _wobble_time := 0.0
var _parcel_offset := Vector3.ZERO
var _thruster_power := 0.3


func _ready() -> void:
	_spawn_position = global_position
	stamina = stamina_max
	spring_arm.add_excluded_object(get_rid())
	camera_pivot.rotation.x = deg_to_rad(start_pitch_deg)
	camera.fov = base_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_rotate_camera(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_time += delta
	_handle_gamepad_look(delta)
	_update_surface_grip()
	_pickup_cooldown -= delta
	_hit_cooldown -= delta
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)

	var on_floor := is_on_floor()
	var exhausted := _exhausted_timer > 0.0
	var paused := exhausted and _exhausted_timer > exhausted_duration - exhausted_pause
	var staggered := _stagger_timer > 0.0

	# --- Гравитация ---
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		var mult := rise_gravity_mult if velocity.y > 0.0 else fall_gravity_mult
		velocity += get_gravity() * mult * delta

	# --- Прыжок (нельзя, пока выдохся или шатается) ---
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	var can_jump := not paused and not staggered
	if can_jump and _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity * (carry_jump_mult if held_parcel else 1.0)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_thruster_power = 6.0
		if held_parcel:
			instability += jump_instability

	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	# --- Взять / положить / бросить ---
	if Input.is_action_just_pressed("interact"):
		if held_parcel:
			_put_down()
		else:
			_try_pick_up()
	elif Input.is_action_just_pressed("throw") and held_parcel:
		_throw()
	var carrying := held_parcel != null

	# --- Ввод относительно камеры ---
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if paused or staggered:
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

	# --- Выносливость и бег ---
	_update_stamina(delta, has_input, carrying)
	exhausted = _exhausted_timer > 0.0

	var target_speed := walk_speed
	if is_sprinting:
		target_speed = sprint_speed
	elif Input.is_action_pressed("quiet"):
		target_speed = quiet_speed
	if exhausted:
		target_speed *= exhausted_speed_mult
	if carrying:
		target_speed *= carry_speed_mult

	var target_velocity := direction * target_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if has_input else deceleration
	if carrying:
		rate *= carry_accel_mult
	rate *= surface_grip if on_floor else air_control
	if staggered:
		rate *= 0.15  # после удара дрон по инерции отлетает
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# --- Движение и столкновения ---
	var pre_move_velocity := velocity
	move_and_slide()
	_handle_collisions(pre_move_velocity, delta)

	var now_on_floor := is_on_floor()
	var just_landed := now_on_floor and not _was_on_floor

	_update_carry(delta, just_landed, pre_move_velocity)
	_update_visual(delta, direction, target_speed, just_landed)
	_update_camera(delta)
	_update_hud()

	_was_on_floor = now_on_floor
	_prev_velocity = velocity

	if global_position.y < fall_limit_y:
		respawn()


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO


## Вызывается препятствиями (маятник, толкатель), когда они бьют дрона.
func receive_hit(direction: Vector3, strength: float, contact: Vector3) -> void:
	var spark_point := (global_position + Vector3.UP * BODY_HEIGHT).lerp(contact, 0.5)
	_take_impact(direction, strength, spark_point, hazard_knockback)


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
		shake += 0.012  # лёгкая тряска на бегу
	camera.h_offset = randf_range(-1.0, 1.0) * shake
	camera.v_offset = randf_range(-1.0, 1.0) * shake


# ---------------------------------------------------------------------------
#  Выносливость
# ---------------------------------------------------------------------------

func _update_stamina(delta: float, has_input: bool, carrying: bool) -> void:
	if _exhausted_timer > 0.0:
		_exhausted_timer -= delta
		is_sprinting = false
		stamina = minf(stamina + stamina_regen * 0.5 * delta, stamina_max)
		return

	var wants_sprint := Input.is_action_pressed("sprint") and has_input and stamina > 0.0
	if wants_sprint and not is_sprinting:
		# Рывок на старте бега
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


# ---------------------------------------------------------------------------
#  Поверхность и столкновения
# ---------------------------------------------------------------------------

## Короткий луч вниз: узнаём, на чём стоим, и берём его трение.
func _update_surface_grip() -> void:
	surface_grip = 1.0
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
	var mat: PhysicsMaterial = null
	if collider is StaticBody3D:
		mat = (collider as StaticBody3D).physics_material_override
	elif collider is RigidBody3D:
		mat = (collider as RigidBody3D).physics_material_override
	if mat:
		surface_grip = clampf(mat.friction, min_grip, 1.0)


## Ищем самый сильный удар за кадр. Лёгкие предметы отлетают, тяжёлые — бьют дрона.
func _handle_collisions(pre_velocity: Vector3, delta: float) -> void:
	var strongest := 0.0
	var hit_normal := Vector3.ZERO
	var hit_point := Vector3.ZERO
	var pre_h := Vector3(pre_velocity.x, 0.0, pre_velocity.z)

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.6:
			continue  # пол или потолок
		var into := -pre_h.dot(n)  # скорость, с которой влетели в препятствие
		var rb := col.get_collider() as RigidBody3D
		if rb != null:
			var push_dir := Vector3(-n.x, 0.0, -n.z).normalized()
			var impulse := push_dir * (push_force * delta + maxf(into, 0.0) * minf(rb.mass, 5.0) * kick_strength)
			rb.apply_impulse(impulse, col.get_position() - rb.global_position)
			into *= clampf(rb.mass / light_object_mass, 0.0, 1.0)
		if into > strongest:
			strongest = into
			hit_normal = n
			hit_point = col.get_position()

	if strongest > impact_threshold:
		_take_impact(hit_normal, strongest, hit_point, wall_knockback)


func _take_impact(push_dir: Vector3, strength: float, contact: Vector3, knock_mult: float) -> void:
	if _hit_cooldown > 0.0:
		return
	_hit_cooldown = 0.3

	# Отскок
	push_dir.y = 0.0
	push_dir = push_dir.normalized()
	velocity.x = push_dir.x * strength * knock_mult
	velocity.z = push_dir.z * strength * knock_mult
	velocity.y = maxf(velocity.y, minf(1.5 + strength * 0.25, 5.0))

	# Шатание, сплющивание, искры, тряска камеры
	_stagger_total = clampf(0.2 + strength * 0.06, 0.25, 0.9)
	_stagger_timer = _stagger_total
	_stagger_strength = clampf(strength / 8.0, 0.3, 1.0)
	_shake = clampf(strength * 0.03, 0.05, 0.35)
	body.scale = Vector3(1.2, 0.8, 1.2)
	sparks.global_position = contact
	sparks.restart()

	# Посылке достаётся
	if held_parcel != null:
		held_parcel.take_damage(strength * hit_damage)
		instability += strength * hit_instability


# ---------------------------------------------------------------------------
#  Переноска посылок
# ---------------------------------------------------------------------------

func _find_nearest_parcel() -> Parcel:
	var best: Parcel = null
	var best_dist := INF
	for node in pickup_zone.get_overlapping_bodies():
		var p := node as Parcel
		if p == null or p.is_held:
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _try_pick_up() -> void:
	if _pickup_cooldown > 0.0 or _stagger_timer > 0.0:
		return
	var p := _find_nearest_parcel()
	if p == null:
		return
	held_parcel = p
	p.pick_up()
	instability = 0.0
	_parcel_offset = Vector3.ZERO


func _put_down() -> void:
	var forward := -visual.global_basis.z
	var pos := global_position + forward * 0.9 + Vector3.UP * 0.35
	held_parcel.global_transform = Transform3D(Basis(Vector3.UP, visual.global_rotation.y), pos)
	_drop_parcel(Vector3(velocity.x, 0.0, velocity.z) * 0.5)


func _throw() -> void:
	var forward := -visual.global_basis.z
	_drop_parcel(velocity + forward * throw_speed + Vector3.UP * 3.0)


func _fumble() -> void:
	var forward := -visual.global_basis.z
	var side := visual.global_basis.x * randf_range(-1.5, 1.5)
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	held_parcel.take_damage(fumble_damage + speed * 1.5)
	_drop_parcel(velocity + forward * 1.5 + side + Vector3.UP * 2.5)


func _drop_parcel(release_velocity: Vector3) -> void:
	var p := held_parcel
	held_parcel = null
	instability = 0.0
	_pickup_cooldown = 0.4
	p.release(release_velocity)


func _update_carry(delta: float, just_landed: bool, pre_move_velocity: Vector3) -> void:
	if held_parcel == null:
		return

	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	var prev_h := Vector3(_prev_velocity.x, 0.0, _prev_velocity.z)
	var accel_vec := (h_vel - prev_h) / delta
	var carry_walk := walk_speed * carry_speed_mult
	var carry_sprint := sprint_speed * carry_speed_mult

	# 1. Бег с посылкой постоянно её раскачивает
	if is_sprinting and h_vel.length() > carry_walk * 0.9:
		instability += sprint_instability * delta

	# 2. Резкие повороты и торможения на скорости
	var speed_over := clampf((prev_h.length() - carry_walk) / maxf(carry_sprint - carry_walk, 0.01), 0.0, 1.0)
	if _stagger_timer <= 0.0:
		instability += accel_vec.length() * speed_over * turn_instability * delta

	# 3. Жёсткое приземление
	if just_landed:
		instability += maxf(0.0, -pre_move_velocity.y - safe_landing_speed) * landing_instability

	# 4. Успокаивается, только если не бежишь (стоя — быстрее)
	if not is_sprinting:
		var rec := stability_recovery * (1.0 if h_vel.length() < 0.5 else 0.6)
		instability = maxf(0.0, instability - rec * delta)

	if instability >= 1.0:
		_fumble()
		return

	# Посылка отстаёт от рук при разгоне и торможении
	var target_offset := (-accel_vec * 0.012).limit_length(0.25)
	_parcel_offset = _parcel_offset.lerp(target_offset, 10.0 * delta)

	# Чем выше раскачка — тем сильнее посылка ходит в руках
	_wobble_time += delta
	var w := instability * 0.4
	var wobble := Basis.from_euler(Vector3(
		sin(_wobble_time * 17.0) * w,
		0.0,
		sin(_wobble_time * 13.0 + 1.3) * w
	))
	var yaw_basis := Basis(Vector3.UP, visual.global_rotation.y)
	held_parcel.global_transform = Transform3D(yaw_basis * wobble, hold_point.global_position + _parcel_offset)


# ---------------------------------------------------------------------------
#  Анимация
# ---------------------------------------------------------------------------

func _update_visual(delta: float, direction: Vector3, target_speed: float, just_landed: bool) -> void:
	var on_floor := is_on_floor()
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var has_input := direction.length() > 0.1
	var exhausted := _exhausted_timer > 0.0
	var staggered := _stagger_timer > 0.0
	var running := is_sprinting and on_floor and h_speed > walk_speed * 0.8

	if has_input:
		var target_yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, turn_speed * delta)

	# --- Наклон корпуса ---
	var lean := -(h_speed / sprint_speed) * 0.2
	if running:
		lean = -0.4            # на бегу сильно наклоняется вперёд
	if exhausted:
		lean = -0.3            # согнулся, отдыхивается
	if staggered:
		lean = 0.3             # откинуло назад
	body.rotation.x = lerpf(body.rotation.x, lean, 8.0 * delta)

	# Шатание после удара (затухает)
	var stagger_z := 0.0
	if staggered:
		var fade := _stagger_timer / _stagger_total
		stagger_z = sin(_time * 28.0) * 0.45 * _stagger_strength * fade
	body.rotation.z = lerpf(body.rotation.z, stagger_z, 20.0 * delta)

	# --- Ноги ---
	var hip_l := 0.0
	var hip_r := 0.0
	var knee_l := 0.0
	var knee_r := 0.0
	var bob := 0.0

	if not on_floor:
		hip_l = 0.5
		hip_r = -0.2
		knee_l = -1.0
		knee_r = -0.6
	elif h_speed > 0.3 or has_input:
		var stride_speed := h_speed
		if surface_grip < 0.5:
			stride_speed = maxf(h_speed, target_speed) * 1.4 if has_input else 0.0
		_stride_phase += stride_speed * stride_frequency * delta
		var amount := clampf(stride_speed / walk_speed, 0.0, 1.3) * leg_swing
		if running:
			amount *= 1.35     # широкие шаги на бегу
		var s := sin(_stride_phase)
		var c := cos(_stride_phase)
		hip_l = s * amount
		hip_r = -s * amount
		knee_l = -maxf(c, 0.0) * amount * 1.7
		knee_r = -maxf(-c, 0.0) * amount * 1.7
		bob = absf(c) * (0.09 if running else 0.05) * minf(amount / leg_swing, 1.3)
	elif exhausted:
		knee_l = -0.35         # подогнул колени
		knee_r = -0.35
		hip_l = 0.15
		hip_r = 0.15
		bob = -0.08 + sin(_time * 10.0) * 0.03   # тяжело дышит
	else:
		bob = sin(_time * 2.0) * 0.015

	var k := 15.0 * delta
	leg_left.rotation.x = lerpf(leg_left.rotation.x, hip_l, k)
	leg_right.rotation.x = lerpf(leg_right.rotation.x, hip_r, k)
	knee_left.rotation.x = lerpf(knee_left.rotation.x, knee_l, k)
	knee_right.rotation.x = lerpf(knee_right.rotation.x, knee_r, k)

	# --- Руки ---
	var arm_l := -hip_l * 0.7
	var arm_r := -hip_r * 0.7
	if held_parcel != null:
		arm_l = 1.5
		arm_r = 1.5
	elif staggered:
		arm_l = sin(_time * 22.0) * 0.9 + 0.6   # машет руками, ловит равновесие
		arm_r = -sin(_time * 22.0) * 0.9 + 0.6
	elif running:
		arm_l = -0.9 - hip_l * 0.4               # руки отведены назад
		arm_r = -0.9 - hip_r * 0.4
	elif exhausted:
		arm_l = 0.2
		arm_r = 0.2
	arm_left.rotation.x = lerpf(arm_left.rotation.x, arm_l, 14.0 * delta)
	arm_right.rotation.x = lerpf(arm_right.rotation.x, arm_r, 14.0 * delta)

	# --- Корпус: высота и сплющивание ---
	body.position.y = lerpf(body.position.y, BODY_HEIGHT + bob, 12.0 * delta)
	if just_landed:
		body.scale = Vector3(1.15, 0.85, 1.15)
	body.scale = body.scale.lerp(Vector3.ONE, 10.0 * delta)

	# --- Двигатель, шлейф бега, пар ---
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
	steam.emitting = exhausted


func _update_hud() -> void:
	# Подсказка и посылка
	if held_parcel != null:
		prompt_label.text = "E — положить     Q — бросить"
		parcel_label.visible = true
		parcel_label.text = "%s — %d кр" % [held_parcel.display_name, held_parcel.price]
		stability_row.visible = true
		var s := 1.0 - instability
		stability_bar.value = s
		var col := Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), s)
		if s < 0.3:
			col = col.lerp(Color.WHITE, (sin(_time * 20.0) + 1.0) * 0.25)  # мигает
		stability_bar.modulate = col
	else:
		prompt_label.text = "E — взять посылку" if _find_nearest_parcel() != null else ""
		parcel_label.visible = false
		stability_row.visible = false

	# Выносливость
	var exhausted := _exhausted_timer > 0.0
	stamina_row.visible = exhausted or is_sprinting or stamina < stamina_max - 0.5
	stamina_bar.value = stamina / stamina_max
	if exhausted:
		stamina_caption.text = "Выдохся!"
		stamina_bar.modulate = Color(1, 0.35, 0.3)
	else:
		stamina_caption.text = "Выносливость"
		stamina_bar.modulate = Color(1, 0.85, 0.35)
