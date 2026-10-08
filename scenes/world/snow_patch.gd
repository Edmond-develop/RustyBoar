extends StaticBody3D
## Снежная заплатка на льду: несколько слипшихся сугробиков.
## На снегу дрон хорошо держится — место передохнуть и перехватить посылку.

@export var blobs := 4
@export var size := 2.2
@export var seed_value := 1

static var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("safe_ground")
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.93, 0.95, 1.0)
		_mat.roughness = 0.9
	var grip := PhysicsMaterial.new()
	grip.friction = 0.9
	physics_material_override = grip

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in blobs:
		var r := size * rng.randf_range(0.45, 0.8)
		var off := Vector3(rng.randf_range(-size, size) * 0.6, 0.0, rng.randf_range(-size, size) * 0.6)
		if i == 0:
			off = Vector3.ZERO
		var h := rng.randf_range(0.06, 0.12)

		var mesh := CylinderMesh.new()
		mesh.top_radius = r * 0.85
		mesh.bottom_radius = r
		mesh.height = h
		mesh.radial_segments = 14
		mesh.rings = 1
		mesh.material = _mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = off + Vector3(0, h * 0.5, 0)
		add_child(mi)

		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = h
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = off + Vector3(0, h * 0.5, 0)
		add_child(col)
