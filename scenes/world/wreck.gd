extends StaticBody3D
## Вмёрзший в лёд разбитый корабль.
##
## Если в папке res://assets/ships лежит модель корабля (.gltf/.glb/.fbx),
## берётся она: увеличивается до нужного размера, заваливается набок, на треть
## уходит под лёд (сквозь прозрачный лёд видно вмёрзшую часть), покрывается
## инеем и снегом, вокруг — наледь, сугробы, контейнеры и сосульки.
## Столкновения строятся точно по форме модели.
##
## Если модели нет — собирается простой корабль из коробок (как раньше).

@export var seed_value := 1
@export var models_dir := "res://assets/ships"
@export var target_length := 24.0     ## Длина корабля в метрах
@export var sink := 0.35              ## Какая доля высоты корабля под льдом

const FROST_SHADER := preload("res://shaders/frost_overlay.gdshader")

static var _hull_mat: StandardMaterial3D
static var _stripe_mat: StandardMaterial3D
static var _dark_mat: StandardMaterial3D
static var _snow_mat: StandardMaterial3D
static var _ice_mat: StandardMaterial3D
static var _collar_mat: StandardMaterial3D
static var _container_mats: Array[StandardMaterial3D] = []

var _rng := RandomNumberGenerator.new()
var _yaw := 0.0


func _ready() -> void:
	add_to_group("safe_ground")
	_make_materials()
	_rng.seed = seed_value
	_yaw = _rng.randf_range(-0.4, 0.4)

	var scene := _find_model()
	if scene:
		_build_from_model(scene)
	else:
		_build_fallback()
	_build_surroundings()


# ---------------------------------------------------------------------------
#  Модель из папки assets/ships
# ---------------------------------------------------------------------------

func _find_model() -> PackedScene:
	var dir := DirAccess.open(models_dir)
	if dir == null:
		return null
	var files: Array[String] = []
	for f in dir.get_files():
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if file.ends_with(".gltf") or file.ends_with(".glb") or file.ends_with(".fbx"):
			if not files.has(file):
				files.append(file)
	files.sort()
	for file in files:
		var res := load(models_dir.path_join(file))
		if res is PackedScene:
			return res
	return null


func _build_from_model(scene: PackedScene) -> void:
	var pivot := Node3D.new()
	pivot.name = "ShipPivot"
	add_child(pivot)
	var ship := scene.instantiate() as Node3D
	pivot.add_child(ship)

	# Размер модели (во «внутренних» единицах)
	var meshes := ship.find_children("*", "MeshInstance3D", true, false)
	var aabb := AABB()
	var first := true
	var inv := ship.global_transform.affine_inverse()
	for node in meshes:
		var mi := node as MeshInstance3D
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	if first:
		ship.queue_free()
		_build_fallback()
		return

	var longest := maxf(aabb.size.x, aabb.size.z)
	var s := target_length / maxf(longest, 0.01)
	ship.scale = Vector3.ONE * s
	var center := aabb.get_center() * s
	# Центр по горизонтали в точку узла; по высоте — часть корпуса подо льдом
	ship.position = Vector3(-center.x, -aabb.position.y * s - aabb.size.y * s * sink, -center.z)
	# Корабль рухнул: нос вниз, завален набок
	pivot.rotation = Vector3(-0.12, _yaw + _rng.randf_range(0.0, TAU), _rng.randf_range(0.22, 0.35))

	# Иней на всей модели + столкновения точно по форме
	var frost := ShaderMaterial.new()
	frost.shader = FROST_SHADER
	frost.set_shader_parameter("ice_y", global_position.y)
	var to_local := global_transform.affine_inverse()
	for node in meshes:
		var mi := node as MeshInstance3D
		mi.material_overlay = frost
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = to_local * mi.global_transform
		add_child(col)

	# Наледь вокруг корпуса там, где он вмёрз в лёд
	var collar := SphereMesh.new()
	collar.radius = 0.5
	collar.height = 1.0
	collar.is_hemisphere = true
	collar.radial_segments = 24
	collar.rings = 6
	collar.material = _collar_mat
	var cmi := MeshInstance3D.new()
	cmi.mesh = collar
	cmi.scale = Vector3(aabb.size.x * s * 0.8, 1.4, aabb.size.z * s * 0.8)
	cmi.rotation.y = pivot.rotation.y
	cmi.position.y = -0.1
	add_child(cmi)


# ---------------------------------------------------------------------------
#  Запасной корабль из коробок (пока модель не скачана)
# ---------------------------------------------------------------------------

func _build_fallback() -> void:
	_part(Vector3(-7.0, 0.9, 0.0), Vector3(12.0, 4.2, 6.0), Vector3(0.0, 0.08, 0.22), _hull_mat)
	_part(Vector3(-7.0, 1.4, 0.0), Vector3(12.1, 0.6, 6.1), Vector3(0.0, 0.08, 0.22), _stripe_mat, false)
	_part(Vector3(5.5, 1.6, 1.2), Vector3(8.0, 3.6, 5.2), Vector3(0.1, -0.35, -0.45), _hull_mat)
	_part(Vector3(9.4, 3.2, 1.9), Vector3(1.4, 2.4, 3.6), Vector3(0.1, -0.35, -0.45), _dark_mat)
	_cylinder(Vector3(-15.5, 0.6, 5.5), 1.5, 4.0, Vector3(PI * 0.5, 0.4, 0.0), _dark_mat)
	_part(Vector3(-1.0, 1.0, -6.5), Vector3(11.0, 0.35, 3.0), Vector3(0.6, 0.3, 0.1), _hull_mat)
	_snow(Vector3(-7.0, 3.1, 0.0), Vector3(8.0, 0.5, 4.0))
	_snow(Vector3(5.0, 3.6, 1.2), Vector3(4.0, 0.4, 3.0))
	for i in 12:
		var ix := -12.0 + i * 1.0 + _rng.randf_range(-0.2, 0.2)
		_icicle(Vector3(ix, 2.6 + ix * 0.02, 3.1), _rng.randf_range(0.4, 1.2))


# ---------------------------------------------------------------------------
#  Вокруг корабля: контейнеры, сугробы, сосульки на контейнерах
# ---------------------------------------------------------------------------

func _build_surroundings() -> void:
	for i in 6:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(target_length * 0.55, target_length * 0.9)
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist * 0.7)
		var size := Vector3(2.4, 2.4, 5.5)
		pos.y = size.y * 0.5 - _rng.randf_range(0.3, 1.0)
		var rot := Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))
		var mat: StandardMaterial3D = _container_mats[_rng.randi() % _container_mats.size()]
		_part(pos, size, rot, mat)
		_snow(pos + Vector3(0, size.y * 0.5 + 0.05, 0), Vector3(1.8, 0.35, 4.0))
		for k in 3:
			_icicle(pos + Basis.from_euler(rot) * Vector3(_rng.randf_range(-1.0, 1.0), -size.y * 0.5 + 0.2, 2.75), _rng.randf_range(0.3, 0.7))
	# Сугробы, наметённые ветром к корпусу
	for i in 4:
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := Vector3(_rng.randf_range(-target_length * 0.35, target_length * 0.35), 0.0, side * _rng.randf_range(3.5, 5.0))
		_snow(Basis(Vector3.UP, _yaw) * p, Vector3(_rng.randf_range(4.0, 7.0), _rng.randf_range(0.6, 1.2), _rng.randf_range(2.0, 3.0)))


func _part(pos: Vector3, size: Vector3, rot: Vector3, mat: Material, collide: bool = true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = pos
		col.rotation = rot
		add_child(col)


func _cylinder(pos: Vector3, r: float, h: float, rot: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	col.rotation = rot
	add_child(col)


func _snow(pos: Vector3, size: Vector3) -> void:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.is_hemisphere = true
	m.material = _snow_mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.scale = size
	add_child(mi)


func _icicle(top: Vector3, length: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = 0.0
	cone.height = length
	cone.radial_segments = 5
	cone.rings = 1
	cone.material = _ice_mat
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.position = top - Vector3(0, length * 0.5, 0)
	add_child(mi)


func _make_materials() -> void:
	if _hull_mat:
		return
	_hull_mat = StandardMaterial3D.new()
	_hull_mat.albedo_color = Color(0.78, 0.8, 0.84)
	_hull_mat.metallic = 0.6
	_hull_mat.roughness = 0.45
	_stripe_mat = StandardMaterial3D.new()
	_stripe_mat.albedo_color = Color(0.85, 0.42, 0.15)
	_stripe_mat.roughness = 0.6
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.albedo_color = Color(0.16, 0.18, 0.22)
	_dark_mat.metallic = 0.8
	_dark_mat.roughness = 0.35
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.albedo_color = Color(0.95, 0.97, 1.0)
	_snow_mat.roughness = 0.9
	_ice_mat = StandardMaterial3D.new()
	_ice_mat.albedo_color = Color(0.75, 0.92, 1.0)
	_ice_mat.roughness = 0.05
	_ice_mat.emission_enabled = true
	_ice_mat.emission = Color(0.3, 0.6, 0.9)
	_ice_mat.emission_energy_multiplier = 0.4
	_collar_mat = StandardMaterial3D.new()
	_collar_mat.albedo_color = Color(0.82, 0.92, 1.0, 0.85)
	_collar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_collar_mat.roughness = 0.2
	_collar_mat.rim_enabled = true
	_collar_mat.rim = 0.5
	for c in [Color(0.8, 0.35, 0.15), Color(0.2, 0.5, 0.6), Color(0.55, 0.57, 0.6), Color(0.75, 0.6, 0.15)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.5
		m.roughness = 0.55
		_container_mats.append(m)
