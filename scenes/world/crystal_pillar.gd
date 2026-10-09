extends Node3D
## Ледяной кристалл-столб. Если дрон подходит близко (или шумит неподалёку),
## кристалл трещит, светится, с него сыплются осколки — и он рушится в сторону дрона.
## Кто под ним — получает удар. Упавший кристалл остаётся лежать новой преградой.
## Когда и куда падать, решает хост; попадание по своему дрону проверяет каждый сам.

@export var height := 7.0
@export var radius := 0.7
@export var trigger_radius := 5.0
@export var noisy_trigger_radius := 9.0
@export var crack_time := 1.3
@export var fall_time := 1.0
@export var hit_strength := 10.0
@export var seed_value := 1

enum State { STANDING, CRACKING, FALLING, FALLEN }

var state := State.STANDING
var _timer := 0.0
var _dir := Vector3.FORWARD
var _body: AnimatableBody3D
var _mat: StandardMaterial3D
var _chips: GPUParticles3D
var _shatter: GPUParticles3D
var _hit_done := false
var _yaw := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.55, 0.85, 1.0, 0.88)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.04
	_mat.metallic_specular = 0.9
	_mat.rim_enabled = true
	_mat.rim = 0.7
	_mat.emission_enabled = true
	_mat.emission = Color(0.3, 0.7, 1.0)
	_mat.emission_energy_multiplier = 0.4

	# Падающий кристалл: тело вращается вокруг основания
	_body = AnimatableBody3D.new()
	_yaw = rng.randf() * TAU
	_body.rotation.y = _yaw
	add_child(_body)
	var prism := CylinderMesh.new()
	prism.top_radius = radius * 0.75
	prism.bottom_radius = radius
	prism.height = height
	prism.radial_segments = 6
	prism.rings = 1
	prism.material = _mat
	var pm := MeshInstance3D.new()
	pm.mesh = prism
	pm.position.y = height * 0.5
	_body.add_child(pm)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = radius * 0.75
	tip.height = radius * 2.2
	tip.radial_segments = 6
	tip.rings = 1
	tip.material = _mat
	var tm := MeshInstance3D.new()
	tm.mesh = tip
	tm.position.y = height + radius * 1.1
	_body.add_child(tm)
	var shape := BoxShape3D.new()
	shape.size = Vector3(radius * 1.6, height, radius * 1.6)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = height * 0.5
	_body.add_child(col)

	# Неподвижные кристаллики у основания
	for i in rng.randi_range(2, 4):
		var h := rng.randf_range(0.8, 2.2)
		var small := CylinderMesh.new()
		small.top_radius = 0.0
		small.bottom_radius = rng.randf_range(0.18, 0.35)
		small.height = h
		small.radial_segments = 6
		small.rings = 1
		small.material = _mat
		var sm := MeshInstance3D.new()
		sm.mesh = small
		var ang := rng.randf() * TAU
		sm.position = Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(0.9, 1.5) + Vector3(0, h * 0.4, 0)
		sm.rotation = Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
		add_child(sm)

	_chips = FX.particles(Color(0.8, 0.95, 1.0), 30, 1.0, 0.07, 0.5, 2.0, Vector3(0, -12, 0), 60.0, false)
	FX.set_box(_chips, Vector3(radius, height * 0.4, radius))
	_chips.position.y = height * 0.6
	add_child(_chips)
	_shatter = FX.particles(Color(0.75, 0.93, 1.0), 120, 1.6, 0.12, 2.0, 7.0, Vector3(0, -14, 0), 70.0)
	_shatter.top_level = true
	add_child(_shatter)


func _physics_process(delta: float) -> void:
	match state:
		State.STANDING:
			if multiplayer.is_server():
				_server_check_trigger()
		State.CRACKING:
			_timer -= delta
			var k := 1.0 - _timer / crack_time
			_mat.emission_energy_multiplier = 0.4 + k * 3.0 + sin(_timer * 40.0) * 0.8
			_body.position = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.04 * k
			if _timer <= 0.0:
				state = State.FALLING
				_timer = 0.0
				_chips.emitting = false
				_body.position = Vector3.ZERO
		State.FALLING:
			_timer += delta
			var k := clampf(_timer / fall_time, 0.0, 1.0)
			var axis := Vector3.UP.cross(_dir).normalized()
			_body.basis = Basis(axis, k * k * PI * 0.48) * Basis(Vector3.UP, _yaw)
			if k > 0.7 and not _hit_done:
				_check_local_hit()
			if k >= 1.0:
				_land()


func _server_check_trigger() -> void:
	var best: Node = null
	var best_d := INF
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead:
			continue
		var dp: Vector3 = d.global_position
		var dist := Vector2(dp.x - global_position.x, dp.z - global_position.z).length()
		var r := noisy_trigger_radius if d.get_noise() > 0.6 else trigger_radius
		if dist < r and dist < best_d:
			best_d = dist
			best = d
	if best:
		var to: Vector3 = best.global_position - global_position
		to.y = 0.0
		var dir := to.normalized().rotated(Vector3.UP, randf_range(-0.4, 0.4))
		_start.rpc(dir)


@rpc("authority", "call_local", "reliable")
func _start(dir: Vector3) -> void:
	if state != State.STANDING:
		return
	_dir = dir
	state = State.CRACKING
	_timer = crack_time
	_chips.emitting = true
	var me = Network.local_player
	if me and me.global_position.distance_to(global_position) < 20.0:
		me.add_shake(0.05)


func _check_local_hit() -> void:
	var me = Network.local_player
	if me == null or me.is_dead:
		return
	var rel: Vector3 = me.global_position - global_position
	rel.y = 0.0
	var along := rel.dot(_dir)
	var lateral := (rel - _dir * along).length()
	if along > 0.3 and along < height + 1.0 and lateral < radius * 1.3 + 0.5:
		_hit_done = true
		var side := (rel - _dir * along).normalized() if lateral > 0.05 else _dir
		me.receive_hit(side, hit_strength, me.global_position + Vector3.UP)


func _land() -> void:
	state = State.FALLEN
	_mat.emission_energy_multiplier = 0.4
	_shatter.global_position = global_position + _dir * (height * 0.8) + Vector3.UP * 0.5
	_shatter.restart()
	var me = Network.local_player
	if me and me.global_position.distance_to(global_position) < 25.0:
		me.add_shake(0.2)
