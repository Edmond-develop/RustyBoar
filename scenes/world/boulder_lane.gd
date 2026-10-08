extends Node3D
## Катящаяся ледяная глыба. Периодически вываливается из берега
## и катится поперёк реки. Перед появлением из берега сыплется снег.
## Время общее для всех игроков. Попадание по своему дрону проверяет каждый сам.

@export var from_x := 19.0
@export var to_x := -19.0
@export var speed := 8.0
@export var period := 7.0
@export_range(0.0, 1.0) var phase := 0.0
@export var radius := 1.3
@export var warning_time := 1.0
@export var hit_strength := 9.0

var _body: AnimatableBody3D
var _mesh: MeshInstance3D
var _puff: GPUParticles3D
var _spray: GPUParticles3D
var _local_t := 0.0
var _was_rolling := false
var _was_warning := false
var _hit_this_roll := false
var _pushed: Array = []


func _ready() -> void:
	_body = AnimatableBody3D.new()
	add_child(_body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.85, 0.95)
	mat.roughness = 0.35
	mat.clearcoat_enabled = true
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_body.add_child(_mesh)
	var shape := SphereShape3D.new()
	shape.radius = radius
	var col := CollisionShape3D.new()
	col.shape = shape
	_body.add_child(col)

	_puff = FX.particles(Color(0.95, 0.97, 1.0, 0.85), 40, 1.2, 0.12, 1.0, 3.0, Vector3(0, -6, 0), 50.0, false)
	_puff.top_level = true
	add_child(_puff)
	_spray = FX.particles(Color(0.95, 0.97, 1.0, 0.8), 60, 0.8, 0.1, 1.0, 3.0, Vector3(0, -6, 0), 70.0, false)
	add_child(_spray)
	_hide()


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var cycle := fposmod(t + phase * period, period)
	var roll_time := absf(to_x - from_x) / speed
	var dir := signf(to_x - from_x)

	var warning := cycle < warning_time
	var rolling := cycle >= warning_time and cycle < warning_time + roll_time

	_puff.global_position = global_position + Vector3(from_x - dir * 2.0, 2.5, 0.0)
	_puff.emitting = warning
	if warning and not _was_warning and Network.local_player:
		var d: float = Network.local_player.global_position.distance_to(global_position + Vector3(from_x, 0, 0))
		if d < 25.0:
			Network.local_player.add_shake(0.06)
	_was_warning = warning

	if not rolling:
		if _was_rolling:
			_hide()
		_was_rolling = false
		return

	if not _was_rolling:
		_hit_this_roll = false
		_pushed.clear()
		_spray.emitting = true
	_was_rolling = true

	var x := from_x + dir * speed * (cycle - warning_time)
	var y := IceRiver.river_y(global_position.z) + radius
	_body.global_position = Vector3(global_position.x + x, y, global_position.z)
	_mesh.rotation.z = -dir * (x / radius)
	_spray.global_position = _body.global_position + Vector3(0, -radius + 0.2, 0)

	_check_hits(dir)


func _check_hits(dir: float) -> void:
	var me = Network.local_player
	if me and not _hit_this_roll and not me.is_dead:
		var to_me: Vector3 = me.global_position + Vector3.UP * 0.9 - _body.global_position
		if to_me.length() < radius + 0.55:
			_hit_this_roll = true
			var push := Vector3(dir, 0.0, signf(to_me.z) * 0.6)
			me.receive_hit(push.normalized(), hit_strength, _body.global_position + to_me * 0.5)

	if multiplayer.is_server():
		for node in get_tree().get_nodes_in_group("parcel"):
			var p := node as Parcel
			if p == null or p.is_held or _pushed.has(p):
				continue
			if p.global_position.distance_to(_body.global_position) < radius + 0.6:
				_pushed.append(p)
				p.linear_velocity = Vector3(dir * speed, 3.0, randf_range(-2.0, 2.0))


func _hide() -> void:
	_body.global_position = global_position + Vector3(0, -30, 0)
	_spray.emitting = false
