extends RefCounted
## Гранёная глыба льда: неровный многогранник со сколами, кристаллы-наросты сверху,
## сосульки по бокам. Строится один раз (у каждого дрона свой узор по seed).

## Вся глыба одним мешем (один материал — ice_block.gdshader)
static func build(seed: int, mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body(st, rng)
	# кристаллы-наросты сверху и по плечам
	for k in rng.randi_range(5, 7):
		var a := rng.randf() * TAU
		var up := rng.randf_range(0.35, 0.95)
		var dir := Vector3(cos(a) * (1.0 - up), up, sin(a) * (1.0 - up)).normalized()
		var base := Vector3(dir.x * 0.78, 0.25 + dir.y * 0.78, dir.z * 0.72)
		_shard(st, rng, base, dir, rng.randf_range(0.22, 0.45), rng.randf_range(0.06, 0.11))
	# сосульки по нижнему краю «пуза»
	for k in rng.randi_range(6, 9):
		var a2 := rng.randf() * TAU
		var r := 0.82
		var base2 := Vector3(cos(a2) * r, rng.randf_range(-0.25, 0.05), sin(a2) * r * 0.92)
		_shard(st, rng, base2, Vector3(cos(a2) * 0.15, -1.0, sin(a2) * 0.15).normalized(), rng.randf_range(0.15, 0.32), rng.randf_range(0.035, 0.06))
	st.generate_normals()
	st.set_material(mat)
	return st.commit()


## Основа: икосфера, вытянутая по высоте, неровная, со «сколами» — плоскими гранями
static func _body(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var verts: Array[Vector3] = []
	var tris: Array = []
	var t := (1.0 + sqrt(5.0)) / 2.0
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((v as Vector3).normalized())
	tris = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	# одно деление — 80 граней: ещё «гранёно», но уже не шар-многогранник
	var mids := {}
	var nt: Array = []
	for tr in tris:
		var m: Array = []
		for e in 3:
			var a: int = tr[e]
			var b: int = tr[(e + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not mids.has(key):
				verts.append(((verts[a] + verts[b]) * 0.5).normalized())
				mids[key] = verts.size() - 1
			m.append(mids[key])
		nt.append([tr[0], m[0], m[2]])
		nt.append([tr[1], m[1], m[0]])
		nt.append([tr[2], m[2], m[1]])
		nt.append([m[0], m[1], m[2]])
	tris = nt
	# неровности и пропорции
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.3
	for i in verts.size():
		var v := verts[i]
		var bump := 1.0 + noise.get_noise_3dv(v * 1.0) * 0.16
		verts[i] = Vector3(v.x * 0.92, v.y * 1.12, v.z * 0.86) * bump
	# сколы: срезаем плоскостями
	for k in 7:
		var cn := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var d := rng.randf_range(0.72, 0.86)
		for i in verts.size():
			var h := verts[i].dot(cn)
			if h > d:
				verts[i] -= cn * (h - d)
	# дно ровное — глыба стоит
	for i in verts.size():
		if verts[i].y < -0.92:
			verts[i].y = -0.92 + (verts[i].y + 0.92) * 0.15
	# плоское затенение: у каждой грани свои вершины
	for tr in tris:
		var a3: Vector3 = verts[tr[0]]
		var b3: Vector3 = verts[tr[1]]
		var c3: Vector3 = verts[tr[2]]
		_tri(st, a3, b3, c3, (a3 + b3 + c3) / 3.0)


## Шестигранный кристалл-нарост (или сосулька): основание в base, растёт по dir
static func _shard(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, dir: Vector3, length: float, radius: float) -> void:
	var x := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(dir).normalized()
	var sides := 6
	var tip := base + dir * length
	var mid := base + dir * length * rng.randf_range(0.55, 0.75)
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	var tw := rng.randf() * TAU
	for k in sides:
		var a := tw + TAU * k / sides
		var off := (x * cos(a) + z * sin(a))
		ring0.append(base - dir * 0.1 + off * radius * 0.9)
		ring1.append(mid + off * radius)
	for k in sides:
		var k2 := (k + 1) % sides
		# бока и остриё (наружу — от оси кристалла)
		var c0 := base - dir * 0.1
		var out0: Vector3 = (ring0[k] + ring1[k2]) * 0.5 - (c0 + mid) * 0.5
		_tri(st, ring0[k], ring1[k], ring1[k2], out0)
		_tri(st, ring0[k], ring1[k2], ring0[k2], out0)
		var out1: Vector3 = (ring1[k] + ring1[k2] + tip) / 3.0 - (mid + tip) * 0.5
		_tri(st, ring1[k], tip, ring1[k2], out1)


## Треугольник лицевой стороной наружу (у Godot лицевая — по часовой стрелке)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
