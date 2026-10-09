extends StaticBody3D
## Красивая модель из файла (.glb) вместо простых фигур.
## Сама подгоняет размер, ставит на землю, строит столкновения точно по форме,
## при желании присыпает инеем, ставит на посадочные опоры и наметает сугробы.
## Используй её всякий раз, когда меняем коробки на настоящие модели.

@export var model: PackedScene
@export var target_length := 16.0       ## Длина модели в метрах (по самой длинной стороне)
@export var lift := 0.0                 ## Подъём над землёй (м) — например, на опорах
@export var snap_to_ground := true      ## Поставить на рельеф (группа "terrain")
@export_range(0.0, 1.0) var frost := 0.35   ## Сколько инея и снега на модели
@export var landing_gear := false       ## Посадочные опоры (если корабль)
@export var snow_drifts := true         ## Сугробы вокруг основания

const FROST_SHADER := preload("res://shaders/frost_overlay.gdshader")


func _ready() -> void:
	add_to_group("safe_ground")
	if model == null:
		return
	if snap_to_ground:
		var terrain := get_tree().get_first_node_in_group("terrain")
		if terrain:
			global_position.y = terrain.height_at(global_position.x, global_position.z)

	var inst := model.instantiate() as Node3D
	add_child(inst)

	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	var aabb := AABB()
	var first := true
	var inv := inst.global_transform.affine_inverse()
	for node in meshes:
		var mi := node as MeshInstance3D
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	if first:
		return

	var s := target_length / maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
	inst.scale = Vector3.ONE * s
	var c := aabb.get_center() * s
	inst.position = Vector3(-c.x, -aabb.position.y * s + lift, -c.z)

	var overlay: ShaderMaterial = null
	if frost > 0.0:
		overlay = ShaderMaterial.new()
		overlay.shader = FROST_SHADER
		overlay.set_shader_parameter("ice_y", global_position.y)
		overlay.set_shader_parameter("amount", frost)

	var to_local := global_transform.affine_inverse()
	for node in meshes:
		var mi := node as MeshInstance3D
		if overlay:
			mi.material_overlay = overlay
		if mi.mesh == null:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = to_local * mi.global_transform
		add_child(col)

	var size := aabb.size * s
	if landing_gear and lift > 0.0:
		_build_gear(size)
	if snow_drifts:
		_build_drifts(size)


## Четыре посадочные опоры с «лапами»
func _build_gear(size: Vector3) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.24, 0.28)
	metal.metallic = 0.85
	metal.roughness = 0.35
	var hx := size.x * 0.3
	var hz := size.z * 0.3
	for corner in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		var strut := CylinderMesh.new()
		strut.top_radius = 0.16
		strut.bottom_radius = 0.12
		strut.height = lift + 0.4
		strut.material = metal
		var smi := MeshInstance3D.new()
		smi.mesh = strut
		smi.position = Vector3(corner.x, (lift + 0.4) * 0.5, corner.y)
		smi.rotation.z = -signf(corner.x) * 0.12
		add_child(smi)
		var pad := CylinderMesh.new()
		pad.top_radius = 0.35
		pad.bottom_radius = 0.45
		pad.height = 0.12
		pad.material = metal
		var pmi := MeshInstance3D.new()
		pmi.mesh = pad
		pmi.position = Vector3(corner.x + signf(corner.x) * 0.1, 0.06, corner.y)
		add_child(pmi)


## Сугробы, наметённые ветром к основанию
func _build_drifts(size: Vector3) -> void:
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.95, 0.97, 1.0)
	snow.roughness = 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	for i in 5:
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.is_hemisphere = true
		m.material = snow
		var mi := MeshInstance3D.new()
		mi.mesh = m
		var side := -1.0 if i % 2 == 0 else 1.0
		mi.position = Vector3(side * (size.x * 0.5 + rng.randf_range(0.0, 0.8)), -0.05,
			rng.randf_range(-size.z * 0.45, size.z * 0.45))
		mi.scale = Vector3(rng.randf_range(1.8, 3.2), rng.randf_range(0.35, 0.7), rng.randf_range(2.5, 4.5))
		add_child(mi)
