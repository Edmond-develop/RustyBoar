extends StaticBody3D
## Торос — гряда вздыбленных ледяных плит поперёк озера.
## Плиты наклонены и наползают друг на друга, у основания — осколки и снежный нанос.
## Плиты скользкие: на них не устоять, проще перепрыгнуть низкие или найти проход.
## Проходы задаются в gaps парами (x_от, x_до).

@export var half_width := 150.0
@export var height := 0.8
@export var gaps := PackedVector2Array()
@export var seed_value := 1

static var _ice_mat: StandardMaterial3D
static var _chip_mat: StandardMaterial3D
static var _snow_mat: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	var slippery := PhysicsMaterial.new()
	slippery.friction = 0.04
	physics_material_override = slippery

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var slabs: Array[Transform3D] = []
	var chips: Array[Transform3D] = []
	var drifts: Array[Transform3D] = []

	var x := -half_width + 0.5
	while x < half_width - 0.5:
		var w := rng.randf_range(1.2, 2.6)
		var cx := x + w * 0.5
		x += w * rng.randf_range(0.55, 0.85)   # плиты наползают друг на друга
		if _in_gap(cx):
			continue
		# Плита: широкая, тонкая, сильно наклонена в сторону юга или севера
		var size := Vector3(w, rng.randf_range(0.22, 0.45), height * rng.randf_range(1.2, 2.2))
		var lean := rng.randf_range(0.55, 1.15) * (1.0 if rng.randf() > 0.5 else -1.0)
		var basis := Basis.from_euler(Vector3(lean, rng.randf_range(-0.35, 0.35), rng.randf_range(-0.25, 0.25)))
		var pos := Vector3(cx, size.z * 0.5 * cos(lean) * 0.75, rng.randf_range(-0.6, 0.6))
		slabs.append(Transform3D(basis * Basis.from_scale(size), pos))
		_add_collision(Transform3D(basis, pos), size)

		# Иногда вторая плита сверху — гряда выше и неровнее
		if rng.randf() < 0.35:
			var size2 := Vector3(w * 0.8, size.y, size.z * 0.7)
			var basis2 := Basis.from_euler(Vector3(-lean * 0.7, rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.3)))
			var pos2 := pos + Vector3(rng.randf_range(-0.3, 0.3), size.z * 0.35, rng.randf_range(-0.3, 0.3))
			slabs.append(Transform3D(basis2 * Basis.from_scale(size2), pos2))
			_add_collision(Transform3D(basis2, pos2), size2)

		# Осколки у основания (без столкновений — просто красота)
		for i in rng.randi_range(2, 5):
			var s := rng.randf_range(0.12, 0.35)
			var cb := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			var cp := Vector3(cx + rng.randf_range(-w, w) * 0.6, s * 0.3, rng.randf_range(-1.6, 1.6))
			chips.append(Transform3D(cb * Basis.from_scale(Vector3(s, s * 0.6, s * 1.3)), cp))

		# Снежный нанос с подветренной стороны
		if rng.randf() < 0.6:
			var db := Basis.from_euler(Vector3(0, rng.randf_range(-0.3, 0.3), 0))
			var ds := Vector3(w * 1.1, 0.25, rng.randf_range(0.8, 1.6))
			drifts.append(Transform3D(db * Basis.from_scale(ds), Vector3(cx, 0.05, rng.randf_range(0.8, 1.4))))

	_multimesh(slabs, _box_mesh(_ice_mat))
	_multimesh(chips, _chip_mesh())
	_multimesh(drifts, _drift_mesh())


func _in_gap(x: float) -> bool:
	for g in gaps:
		if x > g.x - 0.8 and x < g.y + 0.8:
			return true
	return false


func _add_collision(xform: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = xform
	add_child(col)


func _multimesh(xforms: Array[Transform3D], mesh: Mesh) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _box_mesh(mat: Material) -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3.ONE
	m.material = mat
	return m


func _chip_mesh() -> Mesh:
	var m := PrismMesh.new()
	m.size = Vector3.ONE
	m.material = _chip_mat
	return m


func _drift_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.is_hemisphere = true
	m.radial_segments = 12
	m.rings = 4
	m.material = _snow_mat
	return m


func _make_materials() -> void:
	if _ice_mat:
		return
	_ice_mat = StandardMaterial3D.new()
	_ice_mat.albedo_color = Color(0.6, 0.83, 0.97)
	_ice_mat.roughness = 0.06
	_ice_mat.metallic = 0.0
	_ice_mat.metallic_specular = 0.8
	_ice_mat.clearcoat_enabled = true
	_ice_mat.clearcoat = 1.0
	_ice_mat.rim_enabled = true
	_ice_mat.rim = 0.6
	_ice_mat.rim_tint = 0.3
	_ice_mat.emission_enabled = true
	_ice_mat.emission = Color(0.2, 0.45, 0.7)
	_ice_mat.emission_energy_multiplier = 0.35

	_chip_mat = _ice_mat.duplicate()
	_chip_mat.albedo_color = Color(0.78, 0.92, 1.0)

	_snow_mat = StandardMaterial3D.new()
	_snow_mat.albedo_color = Color(0.94, 0.96, 1.0)
	_snow_mat.roughness = 0.9
