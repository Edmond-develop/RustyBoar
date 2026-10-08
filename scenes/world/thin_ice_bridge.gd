extends StaticBody3D
## Тонкий ледяной мост над пропастью.
## Пока на нём стоят дроны, лёд трещит: сильнее с посылкой, на бегу и от прыжков.
## Мост темнеет и дрожит, потом ломается и через время нарастает снова.
## Треск считает хост (по всем дронам) и рассылает остальным.

@export var length := 9.0
@export var width := 2.6
@export var stress_rate := 0.25
@export var carry_mult := 1.6
@export var run_mult := 1.3
@export var landing_stress := 0.35
@export var recovery := 0.15
@export var respawn_time := 8.0

var stress := 0.0
var broken := false

var _timer := 0.0
var _send_timer := 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _mat: StandardMaterial3D
var _area: Area3D
var _shards: GPUParticles3D
var _connected: Array = []


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.8, 0.93, 1.0, 0.85)
	_mat.roughness = 0.05
	_mat.metallic = 0.15
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.35, length)
	box.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	add_child(_mesh)

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.35, length)
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	add_child(_shape)

	_area = Area3D.new()
	var area_shape := BoxShape3D.new()
	area_shape.size = Vector3(width, 1.6, length)
	var area_col := CollisionShape3D.new()
	area_col.shape = area_shape
	area_col.position.y = 0.95
	_area.add_child(area_col)
	add_child(_area)

	_shards = FX.particles(Color(0.8, 0.93, 1.0), 60, 1.5, 0.12, 1.0, 4.0, Vector3(0, -14, 0))
	FX.set_box(_shards, Vector3(width * 0.5, 0.2, length * 0.5))
	add_child(_shards)


func _physics_process(delta: float) -> void:
	_update_look()
	if not multiplayer.is_server():
		return

	# Подписываемся на приземления всех дронов
	for d in get_tree().get_nodes_in_group("player"):
		if not _connected.has(d):
			_connected.append(d)
			d.landed.connect(_on_drone_landed.bind(d))

	if broken:
		_timer -= delta
		if _timer <= 0.0:
			if _anyone_on_bridge():
				_timer = 0.5
			else:
				_restore.rpc()
		return

	var loaded := false
	for d in get_tree().get_nodes_in_group("player"):
		if _area.overlaps_body(d) and d.is_grounded() and not d.is_dead:
			loaded = true
			var rate := stress_rate
			if d.is_carrying():
				rate *= carry_mult
			if d.is_sprinting:
				rate *= run_mult
			stress += rate * delta
	if not loaded:
		stress = maxf(stress - recovery * delta, 0.0)

	if stress >= 1.0:
		_break.rpc()
		return

	_send_timer -= delta
	if _send_timer <= 0.0 and Network.in_game and Network.is_online():
		_send_timer = 0.1
		_sync_stress.rpc(stress)


func _anyone_on_bridge() -> bool:
	for d in get_tree().get_nodes_in_group("player"):
		if _area.overlaps_body(d):
			return true
	return false


func _on_drone_landed(fall_speed: float, drone: Node) -> void:
	if broken or not is_instance_valid(drone):
		return
	if _area.overlaps_body(drone):
		stress += landing_stress * clampf(fall_speed / 6.0, 0.5, 2.0)


func _update_look() -> void:
	if broken:
		return
	_mat.albedo_color = Color(0.8, 0.93, 1.0, 0.85).lerp(Color(0.45, 0.62, 0.85, 0.95), stress)
	var shake := maxf(stress - 0.5, 0.0) * 0.08
	_mesh.position = Vector3(randf_range(-shake, shake), randf_range(-shake, shake) * 0.5, 0.0)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_stress(value: float) -> void:
	stress = value


@rpc("authority", "call_local", "reliable")
func _break() -> void:
	broken = true
	_timer = respawn_time
	stress = 0.0
	_shape.set_deferred("disabled", true)
	_mesh.visible = false
	_shards.restart()
	if Network.local_player and _area.overlaps_body(Network.local_player):
		Network.local_player.add_shake(0.15)


@rpc("authority", "call_local", "reliable")
func _restore() -> void:
	broken = false
	stress = 0.0
	_shape.set_deferred("disabled", false)
	_mesh.visible = true
	_mesh.position = Vector3.ZERO
	_mat.albedo_color = Color(0.8, 0.93, 1.0, 0.85)
