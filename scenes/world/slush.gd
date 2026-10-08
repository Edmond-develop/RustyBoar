extends Node3D
## Шуга — плавающие в разводье обломки льда (только для красоты).

@export var z_min := 216.0
@export var z_max := 226.0
@export var half_width := 150.0
@export var count := 80
@export var seed_value := 1


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.92, 1.0)
	mat.roughness = 0.3
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.45
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var s := rng.randf_range(0.4, 1.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s * rng.randf_range(0.7, 1.4), 1.0, s))
		var pos := Vector3(rng.randf_range(-half_width, half_width), 0.03, rng.randf_range(z_min, z_max))
		mm.set_instance_transform(i, Transform3D(b, pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
