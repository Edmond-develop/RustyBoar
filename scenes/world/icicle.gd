extends Node3D
## Сосулька на потолке пещеры. Когда дрон подходит близко (или шумит неподалёку),
## она дрожит и падает. Попадание ранит дрона. Через время отрастает снова.
## Узел ставится в точку потолка, остриё смотрит вниз.
## По сети: когда падать, решает хост; попадание проверяет каждый игрок по своему дрону.

@export var floor_y := 0.0               ## Высота пола под сосулькой
@export var length := 1.6
@export var trigger_radius := 2.4        ## Падает, если дрон ближе (по горизонтали)
@export var noisy_trigger_radius := 6.0  ## …или ближе, но шумит (бег, прыжки)
@export var hit_strength := 7.5
@export var respawn_time := 20.0

enum State { HANGING, SHAKING, FALLING, GONE }

var state := State.HANGING
var _timer := 0.0
var _fall_speed := 0.0
var _drop := 0.0
var _mesh: MeshInstance3D
var _shards: GPUParticles3D
var _player: Node3D

static var _mat: StandardMaterial3D


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.75, 0.92, 1.0)
		_mat.roughness = 0.05
		_mat.metallic = 0.2
		_mat.emission_enabled = true
		_mat.emission = Color(0.35, 0.7, 1.0)
		_mat.emission_energy_multiplier = 0.5
	var cone := CylinderMesh.new()
	cone.top_radius = 0.28
	cone.bottom_radius = 0.0
	cone.height = length
	cone.radial_segments = 7
	cone.rings = 1
	cone.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cone
	_mesh.position.y = -length * 0.5
	add_child(_mesh)

	_shards = FX.particles(Color(0.8, 0.94, 1.0), 40, 1.0, 0.08, 2.0, 5.0, Vector3(0, -14, 0))
	_shards.top_level = true
	add_child(_shards)


func _physics_process(delta: float) -> void:
	_player = Network.local_player

	match state:
		State.HANGING:
			# Решает хост: кто-то из дронов подошёл близко или шумит неподалёку
			if multiplayer.is_server():
				for d in get_tree().get_nodes_in_group("player"):
					if d.is_dead:
						continue
					var dp: Vector3 = d.global_position
					var dist := Vector2(dp.x - global_position.x, dp.z - global_position.z).length()
					var r := noisy_trigger_radius if d.get_noise() > 0.6 else trigger_radius
					if dist < r:
						_start_fall.rpc()
						break
		State.SHAKING:
			_timer -= delta
			_mesh.position.x = sin(_timer * 70.0) * 0.05
			if _timer <= 0.0:
				state = State.FALLING
				_fall_speed = 0.0
				_drop = 0.0
				_mesh.position.x = 0.0
		State.FALLING:
			_fall_speed += 22.0 * delta
			_drop += _fall_speed * delta
			_mesh.position.y = -length * 0.5 - _drop
			var tip_y := global_position.y - length - _drop
			if _player and not _player.is_dead:
				var p := _player.global_position
				var flat_dist := Vector2(p.x - global_position.x, p.z - global_position.z).length()
				if flat_dist < 0.9 and tip_y < p.y + 1.6 and tip_y > p.y - 0.2:
					var dir := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
					if dir.length() < 0.05:
						dir = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
					_player.receive_hit(dir.normalized(), hit_strength, Vector3(global_position.x, tip_y, global_position.z))
					_shatter(tip_y)
					return
			if tip_y <= floor_y:
				_shatter(floor_y)
		State.GONE:
			_timer -= delta
			if multiplayer.is_server() and _timer <= 0.0 and not _anyone_below():
				_respawn.rpc()


func _anyone_below() -> bool:
	for d in get_tree().get_nodes_in_group("player"):
		var dp: Vector3 = d.global_position
		if Vector2(dp.x - global_position.x, dp.z - global_position.z).length() < 4.0:
			return true
	return false


@rpc("authority", "call_local", "reliable")
func _start_fall() -> void:
	if state != State.HANGING:
		return
	state = State.SHAKING
	_timer = 0.7


@rpc("authority", "call_local", "reliable")
func _respawn() -> void:
	state = State.HANGING
	_mesh.position = Vector3(0.0, -length * 0.5, 0.0)
	_mesh.visible = true


func _shatter(at_y: float) -> void:
	state = State.GONE
	_timer = respawn_time
	_mesh.visible = false
	_shards.global_position = Vector3(global_position.x, at_y + 0.2, global_position.z)
	_shards.restart()
