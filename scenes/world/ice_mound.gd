extends StaticBody3D
## Ледяной холм — огромный пологий бугор льда.
## Склоны скользкие: забраться наверх нельзя, можно только обходить по ложбинам.
## С вершины скатываются глыбы (см. boulder_spawner.gd).
## Физически это часть большой сферы, утопленной в лёд.

@export var cap_height := 6.0     ## Высота над льдом
@export var footprint := 16.0     ## Радиус основания

static var _mat: StandardMaterial3D


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.72, 0.87, 0.97)
		_mat.roughness = 0.15
		_mat.clearcoat_enabled = true
		_mat.rim_enabled = true
		_mat.rim = 0.4
		_mat.emission_enabled = true
		_mat.emission = Color(0.2, 0.42, 0.65)
		_mat.emission_energy_multiplier = 0.2
	var slippery := PhysicsMaterial.new()
	slippery.friction = 0.03
	physics_material_override = slippery

	# Радиус сферы, у которой «шапка» высотой cap_height имеет основание footprint
	var r := (footprint * footprint + cap_height * cap_height) / (2.0 * cap_height)
	var center := Vector3(0, cap_height - r, 0)

	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	sphere.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.position = center
	add_child(mi)

	var shape := SphereShape3D.new()
	shape.radius = r
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = center
	add_child(col)

	# Снежная шапка на вершине
	var cap := SphereMesh.new()
	cap.radius = footprint * 0.25
	cap.height = cap_height * 0.25
	cap.is_hemisphere = true
	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.95, 0.97, 1.0)
	snow_mat.roughness = 0.9
	cap.material = snow_mat
	var cmi := MeshInstance3D.new()
	cmi.mesh = cap
	cmi.position = Vector3(0, cap_height - 0.35, 0)
	add_child(cmi)
