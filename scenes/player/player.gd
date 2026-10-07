extends CharacterBody3D
## Курьерский дрон-шар.
## Парит над землёй, прыгает импульсом двигателя и может планировать,
## если удерживать прыжок в падении (пока есть заряд).
##
## Сцепление с поверхностью берётся из PhysicsMaterial пола (friction).
## Благодаря этому лёд — это просто пол с маленьким трением, и
## на будущей снежной планете ничего переписывать не придётся.

@export_group("Движение")
@export var walk_speed := 6.0
@export var sprint_speed := 10.0
@export var quiet_speed := 2.5          ## Тихий ход — пригодится для механики шума
@export var acceleration := 40.0
@export var deceleration := 50.0
@export var air_control := 0.35         ## Насколько можно рулить в воздухе (0..1)
@export var turn_speed := 10.0

@export_group("Прыжок и парение")
@export var jump_velocity := 7.0
@export var hover_fall_speed := -1.2    ## Максимальная скорость падения при парении
@export var hover_fuel_max := 1.2       ## Секунд парения на одном заряде
@export var hover_refill_rate := 2.0    ## Как быстро заряд восполняется на земле
@export var coyote_time := 0.12         ## Можно прыгнуть чуть позже края платформы
@export var jump_buffer_time := 0.12    ## Нажатие прыжка чуть раньше приземления засчитывается

@export_group("Камера")
@export var mouse_sensitivity := 0.0025
@export var joy_look_speed := 3.0
@export var min_pitch_deg := -70.0
@export var max_pitch_deg := 35.0
@export var start_pitch_deg := -18.0

@export_group("Прочее")
@export var push_force := 40.0          ## Сила толкания ящиков
@export var fall_limit_y := -20.0       ## Ниже этой высоты — возврат на старт

const BODY_HEIGHT := 0.9                ## Высота центра шара над землёй

@onready var visual: Node3D = $Visual
@onready var body: Node3D = $Visual/Body
@onready var thruster_glow: MeshInstance3D = $Visual/Body/ThrusterGlow
@onready var thruster_light: OmniLight3D = $Visual/Body/ThrusterLight
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D

var hover_fuel := 0.0
var is_hovering := false
var surface_grip := 1.0

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _spawn_position := Vector3.ZERO
var _bob_time := 0.0
var _thruster_power := 1.0
var _was_on_floor := true


func _ready() -> void:
	_spawn_position = global_position
	hover_fuel = hover_fuel_max
	spring_arm.add_excluded_object(get_rid())
	camera_pivot.rotation.x = deg_to_rad(start_pitch_deg)
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
	_handle_gamepad_look(delta)
	_update_surface_grip()

	var on_floor := is_on_floor()

	# --- Гравитация и заряд парения ---
	if on_floor:
		_coyote_timer = coyote_time
		hover_fuel = minf(hover_fuel + hover_refill_rate * delta, hover_fuel_max)
	else:
		_coyote_timer -= delta
		velocity += get_gravity() * delta

	# --- Прыжок ---
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_thruster_power = 6.0  # вспышка двигателя

	# --- Парение: держим прыжок во время падения ---
	is_hovering = false
	if not on_floor and Input.is_action_pressed("jump") and velocity.y < 0.0 and hover_fuel > 0.0:
		is_hovering = true
		hover_fuel -= delta
		if velocity.y < hover_fall_speed:
			velocity.y = move_toward(velocity.y, hover_fall_speed, 40.0 * delta)

	# --- Движение относительно камеры ---
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := right * input_dir.x - forward * input_dir.y

	var target_speed := walk_speed
	if Input.is_action_pressed("sprint"):
		target_speed = sprint_speed
	elif Input.is_action_pressed("quiet"):
		target_speed = quiet_speed

	var target_velocity := direction * target_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if direction.length() > 0.01 else deceleration
	rate *= surface_grip if on_floor else air_control
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	_push_rigid_bodies(delta)
	_update_visual(delta, direction)

	if global_position.y < fall_limit_y:
		respawn()


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	hover_fuel = hover_fuel_max


# ---------------------------------------------------------------------------
#  Вспомогательные функции
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


## Берём трение у того, на чём стоим. Нет материала — обычное сцепление.
func _update_surface_grip() -> void:
	surface_grip = 1.0
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < 0.7:
			continue  # это стена, а не пол
		var collider := col.get_collider()
		var mat: PhysicsMaterial = null
		if collider is StaticBody3D:
			mat = (collider as StaticBody3D).physics_material_override
		elif collider is RigidBody3D:
			mat = (collider as RigidBody3D).physics_material_override
		if mat:
			surface_grip = clampf(mat.friction, 0.05, 1.0)
		return


## Дрон может толкать физические ящики.
func _push_rigid_bodies(delta: float) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb == null:
			continue
		var normal := col.get_normal()
		if normal.y > 0.7:
			continue  # стоим на ящике сверху — не вдавливаем его
		var push_dir := -normal
		push_dir.y = 0.0
		rb.apply_central_impulse(push_dir.normalized() * push_force * delta)


## Анимация «живого» дрона: поворот, наклон, покачивание, двигатель.
func _update_visual(delta: float, direction: Vector3) -> void:
	var on_floor := is_on_floor()

	# Поворот глазом туда, куда игрок хочет ехать
	if direction.length() > 0.1:
		var target_yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, turn_speed * delta)

	# Наклон вперёд от скорости
	var speed_ratio := Vector3(velocity.x, 0.0, velocity.z).length() / sprint_speed
	body.rotation.x = lerpf(body.rotation.x, -speed_ratio * 0.3, 8.0 * delta)

	# Покачивание в воздухе
	_bob_time += delta
	var bob := sin(_bob_time * 3.0) * 0.05 if on_floor else 0.0
	body.position.y = lerpf(body.position.y, BODY_HEIGHT + bob, 10.0 * delta)

	# Сплющивание при приземлении
	if on_floor and not _was_on_floor:
		body.scale = Vector3(1.18, 0.82, 1.18)
	_was_on_floor = on_floor
	body.scale = body.scale.lerp(Vector3.ONE, 12.0 * delta)

	# Двигатель снизу
	var thrust_target := 1.0
	if not on_floor:
		thrust_target = 2.0
	if is_hovering:
		thrust_target = 4.0
	_thruster_power = lerpf(_thruster_power, thrust_target, 10.0 * delta)
	var flicker := 1.0 + randf_range(-0.08, 0.08)
	thruster_light.light_energy = _thruster_power * flicker
	thruster_glow.scale = Vector3.ONE * (0.8 + _thruster_power * 0.15) * flicker
