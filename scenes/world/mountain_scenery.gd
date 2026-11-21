extends Node3D
## Шаг 73: чтобы гора выглядела настоящей:
##   * скальные выступы на обрывах между витками и на главной вершине (крупные глыбы — ломают ровный конус);
##   * валуны у подножия скал на полке, осыпи у подошвы;
##   * море облаков на 330 м — видно сверху (с плато, из кабинки, с вершины);
##   * дальние хребты за краем мира: вокруг Пика зубчатые горы со снегом (и «земля» под ними — пустоты не видно).
## Всё одинаково у всех (фиксированное зерно), материал скал — тот же, что у рельефа (снег ложится сам).

const M := preload("res://scenes/world/mountain_layout.gd")
const WORLD_X := 266.0             ## за этим по x — уже не рельеф мира
const WORLD_N := -3756.0

var mtn: Node
var _rng := RandomNumberGenerator.new()
var _clouds: Array[StandardMaterial3D] = []
var _t := 0.0


func build() -> void:
	_rng.seed = 7373
	var b: Node3D = mtn.builder
	var meshes: Array = b.get("_rock_meshes")
	var crags: Array[Transform3D] = []
	var boulders: Array[Transform3D] = []
	var scree: Array[Transform3D] = []
	# --- выступы на обрывах предвершины: между полкой u и нижним витком ---
	var u := 1.0 / M.TURNS + 0.01
	while u < 0.99:
		var ul := u - 1.0 / M.TURNS
		var r_hi := M.radius(u) + M.half_out(u) + 1.0
		var r_lo := M.radius(ul) - M.half_in(ul) - 1.0
		if r_lo - r_hi > 6.0:
			for n in 2:
				var t := _rng.randf_range(0.28, 0.85)
				var a := M.angle(u) + _rng.randf_range(-0.02, 0.02)
				var r := lerpf(r_lo, r_hi, t)
				var x := M.CX + cos(a) * r
				var z := M.CZ + sin(a) * r
				var y: float = mtn._gy(x, z)
				var s := _rng.randf_range(3.0, 7.0)
				var out := Vector3(cos(a), 0, sin(a))
				crags.append(_xf(Vector3(x, y, z) + out * s * 0.25, Vector3(s, s * _rng.randf_range(0.7, 1.4), s * 0.8), atan2(out.x, out.z)))
		u += 7.0 / M.len_per_u(u)
	# подошва предвершины (снаружи нижнего витка) — выступы и осыпи
	u = 0.02
	while u < 1.0 / M.TURNS:
		var a2 := M.angle(u)
		var out2 := Vector3(cos(a2), 0, sin(a2))
		var r2 := M.radius(u) + M.half_out(u) + _rng.randf_range(3.0, 4.0 + M.height(u) * 0.3)
		var p2 := Vector3(M.CX, 0, M.CZ) + out2 * r2
		p2.y = mtn._gy(p2.x, p2.z)
		if M.height(u) > 12.0:
			var s2 := _rng.randf_range(2.0, 5.0)
			crags.append(_xf(p2, Vector3(s2, s2 * 0.8, s2), _rng.randf() * TAU))
		for n2 in 3:
			var q := Vector3(M.CX, 0, M.CZ) + out2 * (r2 + _rng.randf_range(2.0, 18.0)) + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
			q.y = mtn._gy(q.x, q.z)
			var s3 := _rng.randf_range(0.3, 1.1)
			scree.append(_xf(q + Vector3.DOWN * s3 * 0.3, Vector3(s3, s3 * 0.6, s3), _rng.randf() * TAU))
		u += 9.0 / M.len_per_u(u)
	# валуны у скалы на полке (между фонарями)
	u = 0.004 + 9.0 / M.len_per_u(0.0)
	while u < 0.98:
		if not mtn._near_step(u, 6.0) and not mtn._near_camp(u, 16.0) and M.chasm_d(u) > M.CHASM_W * 0.5 + 4.0 and not M.in_glacier(u, 6.0):
			var p3 := M.point(u) - M.outward(u) * (M.half_in(u) - 0.9)
			p3.y = M.height(u)
			var s4 := _rng.randf_range(0.7, 1.3)
			b.rock(p3 + Vector3.UP * s4 * 0.25, Vector3(s4, s4 * 0.8, s4), _rng.randf() * TAU, "rock")
		u += 18.0 / M.len_per_u(u)
	# --- главная вершина: выступы по всем склонам (кроме Плеча и стены) ---
	for n3 in 420:
		var a3 := _rng.randf() * TAU
		var r3 := _rng.randf_range(M.SUMMIT_R + 6.0, 230.0)
		var x3 := M.BX + cos(a3) * r3
		var z3 := M.BZ + sin(a3) * r3
		if absf(x3 - M.BX) < M.SH_X + 8.0 and z3 > M.BZ - 2.0 and z3 < M.SH_ZS + 30.0:
			continue
		if Vector2(x3 - M.CX, z3 - M.CZ).length() < M.R0 + 40.0:
			continue
		var y3: float = mtn._gy(x3, z3)
		if y3 < 15.0:
			continue
		# под тросом канатки — не ставим
		var dx := Vector2(x3, z3) - Vector2(M.RW_A.x, M.RW_A.z)
		var ab := Vector2(M.RW_B.x - M.RW_A.x, M.RW_B.z - M.RW_A.z)
		var tt := clampf(dx.dot(ab) / ab.length_squared(), 0.0, 1.0)
		if (dx - ab * tt).length() < 14.0:
			continue
		var s5 := _rng.randf_range(4.0, 10.0) * (0.6 + 0.4 * smoothstep(M.PEAK, 100.0, y3))
		var out3 := Vector3(cos(a3), 0.0, sin(a3))
		crags.append(_xf(Vector3(x3, y3, z3) + out3 * s5 * 0.2, Vector3(s5, s5 * _rng.randf_range(0.8, 1.6), s5 * 0.8), atan2(out3.x, out3.z) + _rng.randf_range(-0.4, 0.4)))
	# шаг 79/86: в широкой пропасти и на леднике глыб на склоне нет
	for arr: Array[Transform3D] in [crags, scree, boulders]:
		for i in range(arr.size() - 1, -1, -1):
			var o := arr[i].origin
			# шаг 122: на ночной дороге и у стены глыб нет (они без коллизии — сквозь них проходили)
			if M.road_near(o.x, o.z, M.ROAD_HALF + 9.0).x != INF or (absf(o.x - M.BX) < M.FOOT_X + 10.0 and o.z < M.FOOT_ZS + 8.0 and o.z > M.BZ - 30.0):
				arr.remove_at(i)
				continue
			if not is_nan(M.sp_carve(o.x, o.z, 6.0)) or not is_nan(M.gl_carve(o.x, o.z)) or _in_gl(o):
				arr.remove_at(i)
	# шаг 74: кусками — что за камерой, не рисуется; дальние глыбы — простая модель
	var MTN := preload("res://scenes/world/mountain.gd")
	MTN.multi_chunks(self, meshes[0], crags, 340.0, 120.0, mtn.rock_mat())
	MTN.multi_chunks(self, meshes[1], crags, 1400.0, 240.0, mtn.rock_mat(), false, 340.0)
	MTN.multi_chunks(self, meshes[3], scree, 160.0, 80.0, mtn.rock_mat())
	_clouds_sea()
	# шаг 147: облачный слой над тропой (скрывает канатку и её скалы, туман внутри)
	var pc := Node3D.new()
	pc.set_script(preload("res://scenes/world/peak_clouds.gd"))
	pc.name = "PeakClouds"
	add_child(pc)
	_backdrop()


func _xf(p: Vector3, s: Vector3, yaw: float) -> Transform3D:
	var bb := Basis(Vector3.UP, yaw)
	return Transform3D(Basis(bb.x * s.x, bb.y * s.y, bb.z * s.z), p)


func _multi(mesh: Mesh, xfs: Array[Transform3D], vis0: float, vis1: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mtn.rock_mat()
	mi.visibility_range_begin = vis0
	mi.visibility_range_end = vis1
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Море облаков: два полупрозрачных слоя на 330 м, видны только сверху
func _clouds_sea() -> void:
	for li in 2:
		var nz := FastNoiseLite.new()
		nz.seed = 4100 + li
		nz.frequency = 0.012
		nz.fractal_octaves = 5
		var tex := NoiseTexture2D.new()
		tex.seamless = true
		tex.width = 512
		tex.height = 512
		tex.noise = nz
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.0))
		grad.set_color(1, Color(1, 1, 1, 1.0))
		grad.add_point(0.45, Color(1, 1, 1, 0.0))
		grad.add_point(0.7, Color(1, 1, 1, 0.85))
		tex.color_ramp = grad
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92) if li == 0 else Color(0.92, 0.95, 1.0, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.roughness = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.uv1_scale = Vector3(6.0, 6.0, 1.0) if li == 0 else Vector3(3.5, 3.5, 1.0)
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 40.0
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		mat.distance_fade_min_distance = 30.0
		mat.distance_fade_max_distance = 140.0
		mat.disable_receive_shadows = true
		_clouds.append(mat)
		var pm := PlaneMesh.new()
		pm.size = Vector2(3400.0, 3400.0)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0.0, 326.0 + li * 10.0, -3120.0)
		mi.name = "CloudSea%d" % li
		add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var cy := cam.global_position.y if cam else 0.0
	for i in _clouds.size():
		var m := _clouds[i]
		m.uv1_offset = Vector3(_t * (0.0016 + i * 0.0009), _t * 0.0007, 0.0)
		var a := smoothstep(342.0, 372.0, cy)
		m.albedo_color.a = a * (0.92 if i == 0 else 0.7)
	for c in get_children():
		if c is MeshInstance3D and String(c.name).begins_with("CloudSea"):
			(c as MeshInstance3D).visible = cy > 340.0


## Дальние хребты вокруг Пика (за краем мира), снизу — «земля», чтобы не было пустоты
func _backdrop() -> void:
	var nz := FastNoiseLite.new()
	nz.seed = 909
	nz.frequency = 0.0022
	nz.fractal_octaves = 5
	nz.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var nz2 := FastNoiseLite.new()
	nz2.seed = 919
	nz2.frequency = 0.0008
	var cell := 40.0
	var x0 := -1800.0
	var z0 := -1450.0
	var nxn := int(3600.0 / cell) + 1
	var nzn := int(3600.0 / cell) + 1
	var verts := PackedVector3Array()
	verts.resize(nxn * nzn)
	var inside := PackedByteArray()
	inside.resize(nxn * nzn)
	for j in nzn:
		for i in nxn:
			var x := x0 + i * cell
			var z := z0 - j * cell
			var wx := 448.0 if z < -2560.0 else WORLD_X
			var dw := maxf(absf(x) - wx, WORLD_N - z)        # насколько за краем мира
			var h := -6.0
			if dw > -cell:
				var ridge := pow(clampf(nz.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0), 2.2)
				var mass := 0.6 + 0.4 * nz2.get_noise_2d(x, z)
				var dist := Vector2(x - M.BX, z - M.BZ).length()
				var far := 1.0 - smoothstep(1300.0, 2300.0, dist)
				h = (260.0 + ridge * 720.0 * mass) * far * smoothstep(-cell, 120.0, dw) + 280.0 * (1.0 - smoothstep(0.0, 160.0, dw)) * far
				h = maxf(h, -6.0)
			verts[j * nxn + i] = Vector3(x, h, z)
			inside[j * nxn + i] = 1 if dw < -cell * 1.5 else 0
	var idx := PackedInt32Array()
	for j in nzn - 1:
		for i in nxn - 1:
			var a := j * nxn + i
			var bb := a + 1
			var c := a + nxn
			var d := c + 1
			if inside[a] and inside[bb] and inside[c] and inside[d]:
				continue
			idx.append_array(PackedInt32Array([a, c, bb, bb, c, d]))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var pa := verts[idx[t]]
		var pb := verts[idx[t + 1]]
		var pc := verts[idx[t + 2]]
		var fn := (pc - pa).cross(pb - pa)
		for k in 3:
			normals[idx[t + k]] += fn
	for i2 in normals.size():
		normals[i2] = normals[i2].normalized() if normals[i2].length() > 0.0 else Vector3.UP
		if normals[i2].y < 0.0:
			normals[i2] = -normals[i2]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mtn.rock_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Backdrop"
	add_child(mi)


## Шаг 86: точка над ледником (с запасом)
func _in_gl(o: Vector3) -> bool:
	var q := M.gl_local(o.x, o.z)
	return not is_nan(q.x) and q.x > -6.0 and q.x < M.GL_LEN + 6.0 and q.y > -M.GL_IN - 6.0 and q.y < M.GL_OUT + 6.0
