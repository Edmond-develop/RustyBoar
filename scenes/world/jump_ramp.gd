extends StaticBody3D
## Ледяной трамплин. Разгонись (лучше бегом) — и тебя подбросит над разводьем.
## Трамплин поднимается в сторону -Z (на север, по ходу маршрута).

@export var length := 4.0
@export var width := 3.0
@export var tilt_deg := 14.0
@export var launch_speed := 7.5     ## Скорость вверх при отрыве
@export var min_speed := 4.0        ## Нужно въехать хотя бы с такой скоростью

var _area: Area3D

static var _mat: StandardMaterial3D


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.7, 0.88, 1.0)
		_mat.roughness = 0.06
		_mat.clearcoat_enabled = true
		_mat.emission_enabled = true
		_mat.emission = Color(0.3, 0.6, 0.9)
		_mat.emission_energy_multiplier = 0.3
	var slippery := PhysicsMaterial.new()
	slippery.friction = 0.04
	physics_material_override = slippery

	var tilt := deg_to_rad(tilt_deg)
	var rise := sin(tilt) * length
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.3, length)
	mesh.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, rise * 0.5, 0)
	mi.rotation.x = tilt
	add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.3, length)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = mi.position
	col.rotation = mi.rotation
	add_child(col)

	# Зона отрыва на верхнем (северном) конце
	_area = Area3D.new()
	var area_shape := BoxShape3D.new()
	area_shape.size = Vector3(width, 1.6, 1.0)
	var area_col := CollisionShape3D.new()
	area_col.shape = area_shape
	_area.add_child(area_col)
	_area.position = Vector3(0, rise + 0.8, -length * 0.5 + 0.4)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)


func _on_body_entered(body: Node3D) -> void:
	if body != Network.local_player:
		return
	var forward_speed: float = -body.velocity.z
	if forward_speed >= min_speed:
		body.launch(launch_speed)
