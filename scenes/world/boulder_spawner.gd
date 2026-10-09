extends Node3D
## Глыбы на вершине ледяного холма. Сходят ВОЛНАМИ: все холмы одновременно,
## с каждого по несколько глыб в разные стороны. Перед волной — гул и снег с вершин.
## Глыбы катятся по настоящей физике: разгоняются на склоне, сбивают посылки,
## могут свалиться в полынью.
##
## По сети: физику считает хост и рассылает положения глыб остальным;
## время волн общее для всех. Попадание по своему дрону проверяет каждый сам.

@export var per_wave := 5
@export var radius := 1.1
@export var wave_period := 12.0       ## Как часто сходят волны
@export var warning_time := 1.8       ## Сколько длится гул перед волной
@export var first_wave_at := 8.0      ## Первая волна (сек от начала уровня)
@export var lifetime := 22.0
@export var launch_speed := Vector2(7.0, 10.0)   ## Начальная скорость (от, до)
@export var max_travel := 90.0        ## Дальше этого от холма — убираем
@export var seed_value := 1

static var _mesh: ArrayMesh

var _boulders: Array[RigidBody3D] = []
var _alive: Array[float] = []
var _net_pos: Array[Vector3] = []
var _net_rot: Array[Quaternion] = []
var _net_on: Array[bool] = []
var _net_speed: Array[float] = []
var _hit_cooldown: Array[float] = []
var _last_wave := -1
var _send_timer := 0.0
var _local_t := 0.0
var _rng := RandomNumberGenerator.new()
var _dust: GPUParticles3D
var _rumble: GPUParticles3D


func _ready() -> void:
	_rng.seed = seed_value
	if _mesh == null:
		_mesh = _make_rock_mesh(radius)

	var mat := PhysicsMaterial.new()
	mat.friction = 0.12
	mat.bounce = 0.2
	for i in per_wave:
		var b := RigidBody3D.new()
		b.name = "B%d" % i
		b.mass = 60.0
		b.physics_material_override = mat
		b.continuous_cd = true
		# Без сопротивления — катится далеко по скользкому льду
		b.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		b.linear_damp = 0.02
		b.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		b.angular_damp = 0.02
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.scale = Vector3.ONE * _rng.randf_range(0.85, 1.25)
		b.add_child(mi)
		var shape := SphereShape3D.new()
		shape.radius = radius * mi.scale.x
		var col := CollisionShape3D.new()
		col.shape = shape
		b.add_child(col)
		b.top_level = true
		add_child(b)
		_boulders.append(b)
		_alive.append(0.0)
		_net_pos.append(Vector3.ZERO)
		_net_rot.append(Quaternion.IDENTITY)
		_net_on.append(false)
		_net_speed.append(0.0)
		_hit_cooldown.append(0.0)
		_park(i)

	_dust = FX.particles(Color(0.95, 0.97, 1.0, 0.85), 60, 1.2, 0.16, 2.0, 4.5, Vector3(0, -6, 0), 80.0)
	add_child(_dust)
	_rumble = FX.particles(Color(0.95, 0.97, 1.0, 0.7), 40, 1.5, 0.1, 0.5, 1.5, Vector3(0, -3, 0), 60.0, false)
	FX.set_box(_rumble, Vector3(2.0, 0.5, 2.0))
	add_child(_rumble)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var since := t - first_wave_at
	var cycle := fposmod(since, wave_period)
	var wave := int(floor(since / wave_period)) if since >= 0.0 else -1
	# Гул перед волной: снег сыплется с вершины
	_rumble.emitting = since >= -warning_time and cycle > wave_period - warning_time

	if multiplayer.is_server():
		if wave > _last_wave and wave >= 0:
			_last_wave = wave
			_release_wave(wave)
		_server_update(delta)
	else:
		_client_update(delta)
	_check_local_hits(delta)


func _release_wave(wave: int) -> void:
	# Направления разлёта: равномерно по кругу, поворот зависит от номера волны
	var base := fposmod(float(wave) * 2.39 + float(seed_value) * 0.7, TAU)
	for i in _boulders.size():
		var b := _boulders[i]
		_alive[i] = lifetime
		var angle := base + TAU * i / _boulders.size() + _rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		b.freeze = false
		b.global_position = global_position + dir * 0.9 + Vector3(0, 0.2 * i, 0)
		b.linear_velocity = dir * _rng.randf_range(launch_speed.x, launch_speed.y) + Vector3.UP * 1.5
		b.angular_velocity = Vector3(dir.z, 0.0, -dir.x) * 6.0
	_fx_release.rpc()


func _server_update(delta: float) -> void:
	for i in _boulders.size():
		if _alive[i] <= 0.0:
			continue
		_alive[i] -= delta
		var b := _boulders[i]
		var far := Vector2(b.global_position.x - global_position.x, b.global_position.z - global_position.z).length() > max_travel
		if _alive[i] <= 0.0 or far or b.global_position.y < IceRiver.river_y(b.global_position.z) - 1.5:
			_alive[i] = 0.0
			_park(i)

	_send_timer -= delta
	if _send_timer <= 0.0 and Network.in_game and Network.is_online():
		_send_timer = 1.0 / 15.0
		var positions: Array = []
		var rotations: Array = []
		var on: Array = []
		var speeds: Array = []
		for i in _boulders.size():
			positions.append(_boulders[i].global_position)
			rotations.append(_boulders[i].quaternion)
			on.append(_alive[i] > 0.0)
			speeds.append(_boulders[i].linear_velocity.length())
		_net_state.rpc(positions, rotations, on, speeds)


func _client_update(delta: float) -> void:
	for i in _boulders.size():
		var b := _boulders[i]
		if _net_on[i]:
			var k := clampf(delta * 15.0, 0.0, 1.0)
			if b.global_position.distance_to(_net_pos[i]) > 5.0:
				b.global_position = _net_pos[i]
			else:
				b.global_position = b.global_position.lerp(_net_pos[i], k)
			b.quaternion = b.quaternion.slerp(_net_rot[i], k)
		elif b.global_position.y > -50.0:
			_park(i)


@rpc("authority", "call_local", "reliable")
func _fx_release() -> void:
	_dust.global_position = global_position
	_dust.restart()
	var me = Network.local_player
	if me and me.global_position.distance_to(global_position) < 35.0:
		me.add_shake(0.08)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(positions: Array, rotations: Array, on: Array, speeds: Array) -> void:
	for i in mini(positions.size(), _boulders.size()):
		_net_pos[i] = positions[i]
		_net_rot[i] = rotations[i]
		_net_on[i] = on[i]
		_net_speed[i] = speeds[i]


func _park(i: int) -> void:
	var b := _boulders[i]
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	b.linear_velocity = Vector3.ZERO
	b.global_position = global_position + Vector3(i * 5.0, -80.0, 0.0)


func _check_local_hits(delta: float) -> void:
	var me = Network.local_player
	for i in _boulders.size():
		_hit_cooldown[i] -= delta
	if me == null or me.is_dead:
		return
	for i in _boulders.size():
		var b := _boulders[i]
		if b.global_position.y < -40.0 or _hit_cooldown[i] > 0.0:
			continue
		var to_me: Vector3 = me.global_position + Vector3.UP * 0.9 - b.global_position
		if to_me.length() > radius * 1.25 + 0.6:
			continue
		var speed: float = b.linear_velocity.length() if multiplayer.is_server() else _net_speed[i]
		if speed < 2.0:
			continue
		_hit_cooldown[i] = 1.0
		var push := Vector3(to_me.x, 0.0, to_me.z).normalized()
		me.receive_hit(push, clampf(speed * 1.0, 7.0, 13.0), b.global_position + to_me * 0.5)


static func _make_rock_mesh(r: float) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 1.6
	for i in verts.size():
		var v := verts[i]
		verts[i] = v * (1.0 + noise.get_noise_3dv(v.normalized() * 2.0) * 0.35)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var temp := ArrayMesh.new()
	temp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(temp, 0)
	st.deindex()
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.8, 0.95)
	mat.roughness = 0.25
	mat.clearcoat_enabled = true
	mat.rim_enabled = true
	mat.rim = 0.5
	st.set_material(mat)
	return st.commit()
