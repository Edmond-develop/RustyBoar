extends StaticBody3D
## Острые ледяные шипы. Касание ранит дрона и отбрасывает его.
## Внешний вид собирается из кода — каждый куст шипов немного разный.

@export var spike_count := 5
@export var max_height := 1.8
@export var hit_strength := 6.5

static var _mat: StandardMaterial3D

var _area: Area3D
var _cooldown := 0.0


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.72, 0.9, 1.0)
		_mat.metallic = 0.2
		_mat.roughness = 0.05
		_mat.emission_enabled = true
		_mat.emission = Color(0.3, 0.6, 0.95)
		_mat.emission_energy_multiplier = 0.35

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	for i in spike_count:
		var h := rng.randf_range(max_height * 0.45, max_height)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(0.14, 0.3)
		cone.height = h
		cone.radial_segments = 6
		cone.rings = 1
		cone.material = _mat
		var m := MeshInstance3D.new()
		m.mesh = cone
		m.position = Vector3(rng.randf_range(-0.45, 0.45), h * 0.5 - 0.1, rng.randf_range(-0.45, 0.45))
		m.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.0, TAU), rng.randf_range(-0.35, 0.35))
		add_child(m)

	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = max_height
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = max_height * 0.5
	add_child(col)

	_area = Area3D.new()
	var area_shape := SphereShape3D.new()
	area_shape.radius = 1.0
	var area_col := CollisionShape3D.new()
	area_col.shape = area_shape
	area_col.position.y = 0.8
	_area.add_child(area_col)
	add_child(_area)


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	for body in _area.get_overlapping_bodies():
		if body.has_method("receive_hit"):
			var dir: Vector3 = body.global_position - global_position
			dir.y = 0.0
			if dir.length() < 0.01:
				dir = Vector3.FORWARD
			body.receive_hit(dir.normalized(), hit_strength, global_position + Vector3.UP * 0.8)
			_cooldown = 0.8
