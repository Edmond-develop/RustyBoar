extends StaticBody3D
## Тонкий ледяной мост над пропастью.
## Пока дрон стоит на нём, лёд трещит: сильнее с посылкой, на бегу и от прыжков.
## Мост темнеет и дрожит, а потом ломается. Через несколько секунд нарастает снова.

@export var length := 9.0
@export var width := 2.6
@export var stress_rate := 0.25      ## Треск в секунду, пока стоишь на мосту
@export var carry_mult := 1.6        ## С посылкой
@export var run_mult := 1.3          ## На бегу
@export var landing_stress := 0.35   ## Приземление после прыжка
@export var recovery := 0.15         ## Лёд «заживает», когда на нём никого нет
@export var respawn_time := 8.0

var stress := 0.0
var broken := false

var _timer := 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _mat: StandardMaterial3D
var _area: Area3D
var _shards: GPUParticles3D
var _player: Node3D


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
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		if _player:
			_player.landed.connect(_on_player_landed)
		return

	if broken:
		_timer -= delta
		if _timer <= 0.0:
			if _area.overlaps_body(_player):
				_timer = 0.5
			else:
				_restore()
		return

	var on_bridge: bool = _area.overlaps_body(_player) and _player.is_on_floor()
	if on_bridge:
		var rate := stress_rate
		if _player.get_held_parcel() != null:
			rate *= carry_mult
		if _player.is_sprinting:
			rate *= run_mult
		stress += rate * delta
	else:
		stress = maxf(stress - recovery * delta, 0.0)

	# Трещит: темнеет и дрожит
	_mat.albedo_color = Color(0.8, 0.93, 1.0, 0.85).lerp(Color(0.45, 0.62, 0.85, 0.95), stress)
	var shake := maxf(stress - 0.5, 0.0) * 0.08
	_mesh.position = Vector3(randf_range(-shake, shake), randf_range(-shake, shake) * 0.5, 0.0)

	if stress >= 1.0:
		_break()


func _on_player_landed(fall_speed: float) -> void:
	if broken or _player == null:
		return
	if _area.overlaps_body(_player):
		stress += landing_stress * clampf(fall_speed / 6.0, 0.5, 2.0)


func _break() -> void:
	broken = true
	_timer = respawn_time
	stress = 0.0
	_shape.set_deferred("disabled", true)
	_mesh.visible = false
	_shards.restart()
	if _player:
		_player.add_shake(0.15)


func _restore() -> void:
	broken = false
	_shape.set_deferred("disabled", false)
	_mesh.visible = true
	_mesh.position = Vector3.ZERO
	_mat.albedo_color = Color(0.8, 0.93, 1.0, 0.85)
