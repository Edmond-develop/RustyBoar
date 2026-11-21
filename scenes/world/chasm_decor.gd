extends Node3D
## Шаг 143: красота пропасти под подъёмником.
##  * Река по дну (русло — terrain._hill_height), по краям — ледяные закраины, в воде — льдины.
##  * Замёрзшие водопады по обеим стенам: ледяная «занавесь» с сосульками-колоннами, внизу — наледь.
##  * Сосульки под краем уступа у нижней станции.
##  * Валуны на дне и у подножия стен (Poly Haven, со снегом сверху).
## Скалы стен — в шейдере рельефа (granite_rect: слои, пятна, потёки льда, снег на полках).
## Ничего тут не мешает игре (без столкновений): дно пропасти — смерть.

const L := preload("res://scenes/world/snow_hill_layout.gd")
const BOULDER_SHADER := preload("res://shaders/snow_boulder.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const BIG := ["res://assets/lake_boulders/boulder_01_lo.res", "res://assets/lake_boulders/rock_cracked_lo.res"]

var _ter: Node
var _rng := RandomNumberGenerator.new()
var _ice: StandardMaterial3D


func _ready() -> void:
	_ter = get_tree().get_first_node_in_group("terrain")
	_rng.seed = 143143
	_ice = StandardMaterial3D.new()
	_ice.vertex_color_use_as_albedo = true
	_ice.albedo_color = Color(0.82, 0.92, 1.0)
	_ice.roughness = 0.12
	_ice.metallic_specular = 0.9
	_ice.rim_enabled = true
	_ice.rim = 0.35
	_ice.rim_tint = 0.6
	_ice.cull_mode = BaseMaterial3D.CULL_DISABLED
	_river()
	for f in [[-150.0, true, 12.0], [70.0, true, 9.0], [190.0, true, 14.0], [-95.0, false, 16.0], [42.0, false, 11.0], [160.0, false, 18.0], [-230.0, false, 13.0]]:
		_waterfall(float(f[0]), bool(f[1]), float(f[2]))
	_icicles()
	_boulders()


func _h(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else 0.0


## Река: лента воды по руслу, ледяные закраины по краям, льдины
func _river() -> void:
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge := SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := -400.0
	var prev := []
	while x <= 400.0:
		var zc := L.river_z(x)
		var hw := L.river_hw(x) + 3.5
		var cur := [Vector3(x, L.RIVER_Y, zc - hw), Vector3(x, L.RIVER_Y, zc + hw)]
		if not prev.is_empty():
			for v in [prev[0], cur[0], cur[1], prev[0], cur[1], prev[1]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
			# закраины: полосы льда у берегов (неровная ширина)
			for sd in [-1.0, 1.0]:
				var w0 := 1.2 + 1.0 * absf(sin(x * 0.13 + sd))
				var w1 := 1.2 + 1.0 * absf(sin((x - 4.0) * 0.13 + sd))
				var hw0 := L.river_hw(x - 4.0) + 0.5
				var hw1 := L.river_hw(x) + 0.5
				var zp := L.river_z(x - 4.0)
				var a0 := Vector3(x - 4.0, L.RIVER_Y + 0.06, zp + sd * hw0)
				var a1 := Vector3(x - 4.0, L.RIVER_Y + 0.06, zp + sd * (hw0 - w1))
				var b0 := Vector3(x, L.RIVER_Y + 0.06, zc + sd * hw1)
				var b1 := Vector3(x, L.RIVER_Y + 0.06, zc + sd * (hw1 - w0))
				var c := Color(0.86, 0.94, 1.0)
				for v2 in [a0, b0, b1, a0, b1, a1]:
					edge.set_color(c)
					edge.set_normal(Vector3.UP)
					edge.add_vertex(v2)
		prev = cur
		x += 4.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = wm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "ChasmRiver"
	add_child(mi)
	edge.set_material(_ice)
	var em := MeshInstance3D.new()
	em.mesh = edge.commit()
	em.material_override = _ice
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(em)
	# льдины в воде и у берегов
	for i in 26:
		var bx := _rng.randf_range(-260.0, 260.0)
		var bz := L.river_z(bx) + _rng.randf_range(-1.0, 1.0) * L.river_hw(bx)
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(_rng.randf_range(1.2, 3.5), _rng.randf_range(0.3, 0.7), _rng.randf_range(1.0, 2.8))
		b.mesh = bm
		b.material_override = _ice
		add_child(b)
		b.global_transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2)),
			Vector3(bx, L.RIVER_Y + 0.05, bz))


## Где по z стена пропасти на высоте y (south — южная стена у уступа, иначе — стена горы)
func _wall_z(x: float, y: float, south: bool) -> float:
	var za: float
	var zb: float
	if south:
		za = L.CHASM_S + 3.0      # наверху (высоко)
		zb = L.CHASM_S - 12.0     # внизу
	else:
		za = L.Z_TOP - 2.0
		zb = L.CHASM_N + 8.0
	for i in 22:
		var zm := (za + zb) * 0.5
		if _h(x, zm) > y:
			za = zm
		else:
			zb = zm
	return (za + zb) * 0.5


## Замёрзший водопад: ледяная занавесь по стене сверху донизу, колонны-сосульки, внизу наледь
func _waterfall(x0: float, south: bool, w: float) -> void:
	var top := _h(x0, L.CHASM_S + 2.5) - 0.3 if south else L.TOP_Y - 1.0
	var bot := L.CHASM_Y + 1.0
	var out := -1.0 if south else 1.0          # от стены — в пропасть
	var cols := 14
	var rows := 46 if not south else 26
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid := []
	for r in rows + 1:
		var t := float(r) / rows
		var y := lerpf(top, bot, t)
		var row := []
		# занавесь сужается кверху и расползается книзу
		var ww := w * lerpf(0.55, 1.15, t)
		for c in cols + 1:
			var u := float(c) / cols * 2.0 - 1.0
			var x := x0 + u * ww * 0.5
			var z := _wall_z(x, y, south)
			var col_b := absf(sin((u + 1.0) * PI * 3.5 + x0)) * (0.35 + 1.1 * t)    # колонны сосулек
			var edge_k := 1.0 - pow(absf(u), 4.0)
			var off := (0.35 + col_b + 0.25 * sin(y * 0.7 + x * 0.9)) * edge_k
			row.append(Vector3(x, y, z + out * off))
		grid.append(row)
	for r in rows:
		for c in cols:
			var a: Vector3 = grid[r][c]
			var b: Vector3 = grid[r][c + 1]
			var c2: Vector3 = grid[r + 1][c]
			var d: Vector3 = grid[r + 1][c + 1]
			var k := absf(sin(float(c) * 1.7 + x0 * 0.3)) * 0.35
			# голубой глетчерный лёд с белыми прожилками — читается на фоне снега и скал
			var tt := float(r) / rows
			var colr := Color(0.3 + k * 0.45, 0.62 + k * 0.25, 0.9 + k * 0.1).lerp(Color(0.85, 0.93, 1.0), 0.15 + 0.2 * sin(tt * 9.0 + float(c)))
			for v in ([a, c2, b, b, c2, d] if south else [a, b, c2, b, d, c2]):
				st.set_color(colr)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ice
	mi.name = "IceFall"
	add_child(mi)
	# наледь у подножия
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 7
	mound.mesh = sm
	mound.material_override = _ice
	add_child(mound)
	var zb := _wall_z(x0, bot + 2.0, south) + out * w * 0.25
	mound.global_transform = Transform3D(Basis.from_scale(Vector3(w * 0.6, w * 0.22, w * 0.4)), Vector3(x0, _h(x0, zb) + 0.2, zb))


## Сосульки под краем уступа у нижней станции
func _icicles() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.09
	cone.bottom_radius = 0.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	var xs := []
	var x := -70.0
	while x <= 70.0:
		xs.append(x + _rng.randf_range(-0.4, 0.4))
		x += _rng.randf_range(0.5, 1.4)
	mm.instance_count = xs.size()
	for i in xs.size():
		var xi: float = xs[i]
		var lip_y := L.LEDGE_Y - 0.6
		var z := _wall_z(xi, lip_y, true) - 0.15
		var ln := _rng.randf_range(0.4, 2.8)
		var b := Basis.from_scale(Vector3(1.0 + ln * 0.2, ln, 1.0 + ln * 0.2))
		mm.set_instance_transform(i, Transform3D(b, Vector3(xi, lip_y - ln * 0.5, z)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _ice
	add_child(mi)


## Валуны на дне и у стен
func _boulders() -> void:
	var meshes: Array[Mesh] = []
	var mats: Array[Material] = []
	for path in BIG:
		var m: Mesh = load(path)
		meshes.append(m)
		var src := m.surface_get_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = BOULDER_SHADER
		if src:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("rough_tex", src.roughness_texture)
			sm.set_shader_parameter("rough_channel", 1 if src.ao_enabled else 0)
		sm.set_shader_parameter("tint", Color(0.62, 0.62, 0.66))
		sm.set_shader_parameter("snow_amount", 0.25)
		mats.append(sm)
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 400:
		tries += 1
		var x := _rng.randf_range(-300.0, 300.0)
		var z := _rng.randf_range(L.CHASM_N - 2.0, L.CHASM_S - 6.0)
		if absf(z - L.river_z(x)) < L.river_hw(x) + 2.0:
			continue
		var k := _rng.randi() % 2
		var m2: Mesh = meshes[k]
		var aabb := m2.get_aabb()
		var r := _rng.randf_range(2.5, 9.0) if _rng.randf() < 0.8 else _rng.randf_range(10.0, 16.0)
		var sc := r * 2.0 / maxf(aabb.size.x, aabb.size.z)
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3)) * Basis.from_scale(Vector3(sc, sc * _rng.randf_range(0.6, 1.1), sc))
		var y := _h(x, z)
		var mi := MeshInstance3D.new()
		mi.mesh = m2
		mi.material_override = mats[k]
		mi.lod_bias = 0.6
		add_child(mi)
		mi.global_transform = Transform3D(b, Vector3(x, y, z) - b * Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) + Vector3.DOWN * r * 0.25)
		placed += 1
