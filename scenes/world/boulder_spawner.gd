extends Node3D
## Глыбы на вершине ледяного холма. Время от времени одна из них срывается
## и скатывается по настоящей физике: разгоняется на склоне, катится по льду,
## сбивает посылки, может свалиться в полынью.
##
## По сети: физику считает только хост и рассылает положения глыб остальным.
## Попадание по своему дрону проверяет каждый игрок сам.

@export var pool_size := 2
@export var radius := 1.1
@export var interval_min := 6.0
@export var interval_max := 10.0
@export var lifetime := 14.0
@export var seed_value := 1

static var _mesh: ArrayMesh

var _boulders: Array[RigidBody3D] = []
var _alive: Array[float] = []      # сколько ещё живёт (0 — спрятана)
var _net_pos: Array[Vector3] = []
var _net_rot: Array[Quaternion] = []
var _net_on: Array[bool] = []
var _net_speed: Array[float] = []
var _hit_cooldown: Array[float] = []
var _timer := 0.0
var _send_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _dust: GPUParticles3D


func _ready() -> void:
	_rng.seed = seed_value
	_timer = _rng.randf_range(1.0, interval_max)
	if _mesh == null:
		_mesh = _make_rock_mesh(radius)

	var mat := PhysicsMaterial.new()
	mat.friction = 0.3
	mat.bounce = 0.15
	for i in pool_size:
		var b := RigidBody3D.new()
		b.name = "B%d" % i
		b.mass = 60.0
		b.physics_material_override = mat
		b.continuous_cd = true
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		b.add_child(mi)
		var shape := SphereShape3D.new()
		shape.radius = radius
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

	_dust = FX.particles(Color(0.95, 0.97, 1.0, 0.85), 40, 1.0, 0.14, 1.5, 3.5, Vector3(0, -6, 0), 70.0)
	add_child(_dust)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_update(delta)
	else:
		for i in _boulders.size():
			var b := _boulders[i]
			if _net_on[i]:
				var t := clampf(delta * 15.0, 0.0, 1.0)
				if b.global_position.distance_to(_net_pos[i]) > 5.0:
					b.global_position = _net_pos[i]
				else:
					b.global_position = b.global_position.lerp(_net_pos[i], t)
				b.quaternion = b.quaternion.slerp(_net_rot[i], t)
			elif b.global_position.y > -50.0:
				_park(i)
	_check_local_hits(delta)


func _server_update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = _rng.randf_range(interval_min, interval_max)
		for i in _boulders.size():
			if _alive[i] <= 0.0:
				_release(i)
				break

	for i in _boulders.size():
		if _alive[i] <= 0.0:
			continue
		_alive[i] -= delta
		var b := _boulders[i]
		# Провалилась в воду или время вышло — убираем
		if _alive[i] <= 0.0 or b.global_position.y < IceRiver.river_y(b.global_position.z) - 1.5:
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


func _release(i: int) -> void:
	var b := _boulders[i]
	_alive[i] = lifetime
	b.freeze = false
	b.global_position = global_position + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))
	var dir := Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU)
	b.linear_velocity = dir * _rng.randf_range(1.5, 3.0)
	b.angular_velocity = Vector3.ZERO
	_fx_release.rpc()


@rpc("authority", "call_local", "reliable")
func _fx_release() -> void:
	_dust.global_position = global_position
	_dust.restart()
	var me = Network.local_player
	if me and me.global_position.distance_to(global_position) < 30.0:
		me.add_shake(0.05)


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


## Свой дрон: попала ли в него катящаяся глыба
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
		if to_me.length() > radius + 0.6:
			continue
		var speed: float = b.linear_velocity.length() if multiplayer.is_server() else _net_speed[i]
		if speed < 2.0:
			continue   # лежащая глыба не бьёт
		_hit_cooldown[i] = 1.0
		var push := Vector3(to_me.x, 0.0, to_me.z).normalized()
		me.receive_hit(push, clampf(speed * 1.2, 7.0, 12.0), b.global_position + to_me * 0.5)


## Угловатая ледяная глыба: сфера, вершины которой сдвинуты шумом
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
		var n := v.normalized()
		verts[i] = v * (1.0 + noise.get_noise_3dv(n * 2.0) * 0.35)
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
