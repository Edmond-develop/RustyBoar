extends Node3D
## Дно озера — чтобы под водой было на что посмотреть и по чему ориентироваться:
##  * валуны, обросшие бурым налётом (гуще у полыней);
##  * «ледяные водоросли» — длинные ленты, колышутся, кончики слабо светятся бирюзой;
##  * светящиеся кристаллы — голубые друзы, видны сквозь муть;
##  * затонувшее: ящики, бочки, старые сани, якорь с цепью, обломки чужого дрона;
##  * газовые ключи — столбики пузырей со дна.
## Всё расставляется по зерну — одинаково у всех игроков.

const KELP_SHADER := preload("res://shaders/kelp.gdshader")

var _lake: Node
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_lake = get_parent()
	_rng.seed = 90210
	var holes: Array[Vector3] = []
	for c in _lake.get("circles"):
		holes.append(c)
	_rocks(holes)
	_kelp(holes)
	_crystals(holes)
	_wrecks(holes)
	_vents(holes)


## Случайная точка на дне: чаще — недалеко от полыней (там люди ныряют)
func _spot(holes: Array[Vector3], near: float) -> Vector3:
	var x: float
	var z: float
	if not holes.is_empty() and _rng.randf() < near:
		var h: Vector3 = holes[_rng.randi() % holes.size()]
		var a := _rng.randf() * TAU
		var d := h.z + _rng.randf_range(0.0, 22.0)
		x = h.x + cos(a) * d
		z = h.y + sin(a) * d
	else:
		x = _rng.randf_range(-IceRiver.LAKE_HALF + 4.0, IceRiver.LAKE_HALF - 4.0)
		z = _rng.randf_range(IceRiver.LAKE_Z_END + 4.0, IceRiver.LAKE_Z_START - 4.0)
	x = clampf(x, -IceRiver.LAKE_HALF + 3.0, IceRiver.LAKE_HALF - 3.0)
	z = clampf(z, IceRiver.LAKE_Z_END + 3.0, IceRiver.LAKE_Z_START - 3.0)
	return Vector3(x, IceRiver.bed_y(x, z), z)


func _rocks(holes: Array[Vector3]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.8
	sphere.radial_segments = 8
	sphere.rings = 5
	var arr := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 2.0
	for i in verts.size():
		var v := verts[i]
		verts[i] = v * (1.0 + noise.get_noise_3dv(v * 3.0) * 0.28)
	for k in idx.size():
		st.add_vertex(verts[idx[k]])
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 1800
	for i in mm.instance_count:
		var p := _spot(holes, 0.7)
		var s := _rng.randf_range(0.4, 2.2) * (1.0 if _rng.randf() < 0.85 else 2.2)
		var b := Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))).scaled(Vector3(s, s * _rng.randf_range(0.5, 0.9), s))
		mm.set_instance_transform(i, Transform3D(b, p + Vector3.UP * s * 0.12))
		var g := _rng.randf_range(0.18, 0.32)
		mm.set_instance_color(i, Color(g * 0.9, g, g * 0.85).lerp(Color(0.24, 0.27, 0.16), _rng.randf() * 0.6))
	_add_mm(mm)


func _kelp(holes: Array[Vector3]) -> void:
	# лента из 6 звеньев: x — ширина, y — высота (0..1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	for k in segs:
		var y0 := float(k) / segs
		var y1 := float(k + 1) / segs
		var w0 := 0.5 * (1.0 - y0 * 0.6)
		var w1 := 0.5 * (1.0 - y1 * 0.6)
		st.set_uv(Vector2(0, y0))
		st.add_vertex(Vector3(-w0, y0, 0))
		st.set_uv(Vector2(1, y0))
		st.add_vertex(Vector3(w0, y0, 0))
		st.set_uv(Vector2(0, y1))
		st.add_vertex(Vector3(-w1, y1, 0))
		st.set_uv(Vector2(1, y0))
		st.add_vertex(Vector3(w0, y0, 0))
		st.set_uv(Vector2(1, y1))
		st.add_vertex(Vector3(w1, y1, 0))
		st.set_uv(Vector2(0, y1))
		st.add_vertex(Vector3(-w1, y1, 0))
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = KELP_SHADER
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 2400
	var i := 0
	while i < mm.instance_count:
		# кустиками по 4–8 лент
		var c := _spot(holes, 0.85)
		var n := mini(_rng.randi_range(4, 8), mm.instance_count - i)
		for k in n:
			var p := c + Vector3(_rng.randf_range(-0.7, 0.7), 0.0, _rng.randf_range(-0.7, 0.7))
			p.y = IceRiver.bed_y(p.x, p.z)
			var h := _rng.randf_range(0.8, 3.2)
			var w := _rng.randf_range(0.08, 0.18)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(w, h, 1.0))
			mm.set_instance_transform(i, Transform3D(b, p))
			mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), h / 3.2, 0.0))
			i += 1
	_add_mm(mm)


func _crystals(holes: Array[Vector3]) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.12
	cm.height = 0.7
	cm.radial_segments = 6
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.75, 1.0)
	mat.emission_energy_multiplier = 2.6
	mat.roughness = 0.1
	cm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = 900
	var i := 0
	while i < mm.instance_count:
		var c := _spot(holes, 0.8)
		var n := mini(_rng.randi_range(3, 7), mm.instance_count - i)
		for k in n:
			var tilt := Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
			var s := _rng.randf_range(0.5, 1.6)
			var b := Basis.from_euler(tilt).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(b, c + Vector3(_rng.randf_range(-0.3, 0.3), 0.25 * s, _rng.randf_range(-0.3, 0.3))))
			i += 1
	_add_mm(mm)


func _add_mm(mm: MultiMesh) -> void:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Затонувшее добро — рядом с полыньями
func _wrecks(holes: Array[Vector3]) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.24, 0.16)
	wood.roughness = 0.95
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.42, 0.2, 0.1)
	rust.metallic = 0.6
	rust.roughness = 0.75
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.6, 0.35, 0.12)
	paint.metallic = 0.4
	paint.roughness = 0.6
	for i in 46:
		var p := _spot(holes, 1.0)
		var root := Node3D.new()
		root.position = p
		root.rotation = Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))
		add_child(root)
		match i % 6:
			0, 1:
				# ящик с досками
				var s := _rng.randf_range(0.6, 1.0)
				_box(root, Vector3(s, s * 0.7, s * 0.8), Vector3(0, s * 0.3, 0), wood)
				_box(root, Vector3(s * 1.04, 0.06, 0.08), Vector3(0, s * 0.3, 0), rust)
			2:
				# бочка на боку
				var bar := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.32
				cm.bottom_radius = 0.32
				cm.height = 0.9
				cm.material = rust
				bar.mesh = cm
				bar.rotation = Vector3(0, 0, PI * 0.5)
				bar.position = Vector3(0, 0.3, 0)
				root.add_child(bar)
			3:
				# старые сани: полозья и настил
				_box(root, Vector3(0.08, 0.08, 2.2), Vector3(-0.45, 0.06, 0), rust)
				_box(root, Vector3(0.08, 0.08, 2.2), Vector3(0.45, 0.06, 0), rust)
				_box(root, Vector3(1.0, 0.06, 1.6), Vector3(0, 0.3, 0), wood)
			4:
				# якорь и цепь
				_box(root, Vector3(0.12, 1.3, 0.12), Vector3(0, 0.25, 0), rust, Vector3(0.9, 0, 0))
				_box(root, Vector3(1.0, 0.12, 0.12), Vector3(0, -0.15, -0.35), rust, Vector3(0.9, 0, 0))
				for k in 8:
					var ring := MeshInstance3D.new()
					var tm := TorusMesh.new()
					tm.inner_radius = 0.05
					tm.outer_radius = 0.09
					tm.rings = 10
					tm.ring_segments = 5
					tm.material = rust
					ring.mesh = tm
					ring.position = Vector3(0.15 * k, 0.06, 0.6 + sin(k * 1.3) * 0.1)
					ring.rotation = Vector3(PI * 0.5 * (k % 2), 0.3 * k, 0)
					root.add_child(ring)
			5:
				# обломки чужого дрона: корпус, оторванная нога, погасший фонарь
				var hull := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.4
				sm.height = 0.7
				sm.material = paint
				hull.mesh = sm
				hull.position = Vector3(0, 0.25, 0)
				hull.rotation = Vector3(1.2, 0, 0.4)
				root.add_child(hull)
				_box(root, Vector3(0.12, 0.7, 0.12), Vector3(0.7, 0.08, 0.2), rust, Vector3(0, 0, 1.4))
				_box(root, Vector3(0.3, 0.12, 0.25), Vector3(-0.5, 0.06, -0.3), rust)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Газовые ключи: столбики пузырей со дна
func _vents(holes: Array[Vector3]) -> void:
	for i in 30:
		var p := _spot(holes, 0.9)
		var top: float = _lake.water_y(p.z)
		var h := maxf(top - p.y, 1.0)
		var v := FX.particles(Color(0.88, 0.96, 1.0, 0.7), 24, h / 1.6, 0.045, 1.2, 2.0, Vector3(0, 0.6, 0), 6.0, false)
		FX.set_box(v, Vector3(0.12, 0.05, 0.12))
		v.position = p + Vector3.UP * 0.1
		v.visibility_range_end = 45.0
		add_child(v)
		v.emitting = true
