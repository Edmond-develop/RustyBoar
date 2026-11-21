extends RefCounted
## Ледяные наплывы и глыбы на отвесных стенах каньона — чтобы стены не были плоскими:
##   • стены ущелий (рельеф) — наплывы по всей высоте, от дна пропасти до плато;
##   • обрывы вокруг прудов — тоже;
##   • бока дорог и площадок (ледяные призмы) — наплывы ниже края дороги.
## Там, где ходят игроки (дороги, площадки, тоннели, мосты), наплывов нет — ничего не торчит
## сквозь дорогу и не мешает идти. Всё по фиксированному зерну — одинаково у всех игроков.
## Рисуется через MultiMesh кусками по CHUNK м: ближе NEAR м — подробные глыбы, дальше — упрощённые,
## дальше VIS м — не рисуется.

const L := preload("res://scenes/world/canyon_layout.gd")
const CHUNK := 80.0
const NEAR := 70.0
const VIS := 230.0
const VARIANTS := 2
const CELL := 2.0

static var disabled := false          ## для замеров: без наплывов

var cv: Node3D
var rng := RandomNumberGenerator.new()
var count := 0
var _meshes: Array[ArrayMesh] = []      ## [вид*2] — подробная, [вид*2+1] — простая
var _mats: Array[Material] = []
var _buckets := {}                 ## Vector3i(чанк x, чанк z, материал*8+вид) → Array[Transform3D]
var _lo := PackedFloat32Array()    ## по сетке: самая низкая дорога рядом
var _hi := PackedFloat32Array()    ## самая высокая
var _nx := 0
var _nz := 0
var _ter: Node


func _init(canyon: Node3D) -> void:
	cv = canyon
	rng.seed = 51877


func build(terrain: Node, cliff_mat: Material) -> void:
	if disabled:
		return
	_ter = terrain
	var tm: Material = terrain.get("terrain_material") if terrain else null
	_mats = [tm if tm else cliff_mat, cliff_mat]
	_make_meshes()
	_build_keepout()
	if _ter:
		_terrain_walls()
		_pool_cliffs()
	for s in cv.cliff_spots:
		_cliff_column(s)
	# лицевые стены тоннелей (вокруг входа): там проверку «рядом дорога» не делаем — места выбраны вне прохода
	for fs in cv.face_spots:
		_rock(fs[0], fs[1], _size(1.0), rng.randf_range(0.6, 1.3), 1, -1.0)
	_flush()


# ---------------------------------------------------------------------------
#  Формы глыб: искажённые шумом икосферы (сглаженные), с плоской «полкой» сверху
# ---------------------------------------------------------------------------

func _make_meshes() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	for mi in VARIANTS * 2:
		var vi := mi / 2
		noise.seed = 311 + vi * 17
		var geo := _icosphere(2 if mi % 2 == 0 else 1)
		var verts: PackedVector3Array = geo[0]
		var idx: PackedInt32Array = geo[1]
		for i in verts.size():
			var p: Vector3 = verts[i]
			var r := 1.0 + 0.3 * noise.get_noise_3dv(p * 1.3 + Vector3(vi * 3.1, 0, 0)) + 0.1 * noise.get_noise_3dv(p * 3.7)
			p *= r
			# верх приплюснут — на наплыве лежит снег; задняя сторона (в стену) сплющена
			if p.y > 0.45:
				p.y = 0.45 + (p.y - 0.45) * 0.45
			if p.z < -0.2:
				p.z = -0.2 + (p.z + 0.2) * 0.5
			verts[i] = p
		var nrm := PackedVector3Array()
		nrm.resize(verts.size())
		for t in range(0, idx.size(), 3):
			var a := verts[idx[t]]
			var b := verts[idx[t + 1]]
			var c := verts[idx[t + 2]]
			var fn := (c - a).cross(b - a)
			for j in 3:
				nrm[idx[t + j]] += fn
		for i in nrm.size():
			nrm[i] = nrm[i].normalized()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_meshes.append(m)


static func _icosphere(sub: int) -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = []
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		v.append((p as Vector3).normalized())
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in sub:
		var cache := {}
		var nf: Array = []
		for tri in f:
			var m := []
			for e in 3:
				var a: int = tri[e]
				var b: int = tri[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					v.append(((v[a] + v[b]) * 0.5).normalized())
					cache[key] = v.size() - 1
				m.append(cache[key])
			nf.append([tri[0], m[0], m[2]])
			nf.append([tri[1], m[1], m[0]])
			nf.append([tri[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f = nf
	var pv := PackedVector3Array(v)
	var pi := PackedInt32Array()
	for tri in f:
		# Godot: лицевая сторона — по часовой (если смотреть снаружи)
		pi.append(tri[0])
		pi.append(tri[2])
		pi.append(tri[1])
	return [pv, pi]


# ---------------------------------------------------------------------------
#  Где нельзя: дороги, площадки, мосты, тоннели (сетка «высот дорог рядом»)
# ---------------------------------------------------------------------------

func _build_keepout() -> void:
	_nx = int((L.X_MAX - L.X_MIN) / CELL) + 2
	_nz = int((L.Z_MAX + 30.0 - L.Z_MIN) / CELL) + 2
	_lo.resize(_nx * _nz)
	_hi.resize(_nx * _nz)
	_lo.fill(1e9)
	_hi.fill(-1e9)
	for road in cv.road_paths:
		var path: Array = cv.road_paths[road]
		var form: Array = L.FORMS.get(road, [])
		var hw: float = float(L.ROAD_WIDTH.get(road, 7.5)) * 0.5
		var reach := hw + 2.0
		if not form.is_empty() and String(form[0]) in ["ledge", "stilts"]:
			reach = hw + 9.0
		var fs: Dictionary = cv.form_sections.get(road, {})
		var tun0 := 1 << 30
		var tun1 := -1
		if not fs.is_empty() and String(fs["kind"]) == "tunnel":
			tun0 = int(fs["k0"]) - 3
			tun1 = int(fs["k1"]) + 3
		for k in range(0, path.size(), 2):
			var p: Vector3 = path[k]
			if k >= tun0 and k <= tun1:
				_stamp(p.x, p.z, 30.0, p.y - 20.0, L.PLATEAU + 6.0)
			else:
				_stamp(p.x, p.z, reach + 5.0, p.y, p.y)
	for key in L.PLATFORMS:
		var pl: Array = L.PLATFORMS[key]
		_stamp(pl[0], pl[2], float(pl[3]) * 1.12 + 6.0, pl[1], pl[1])
	var pairs: Array = []
	for x in L.BRIDGES + L.FAKE_BRIDGES + L.CRUMBLES + L.ICEFALLS:
		pairs.append(x)
	pairs.append(L.TWIN_REAL)
	pairs.append(L.TWIN_FAKE)
	pairs.append([L.LIFT[0] + Vector3(0, -6.0, 0), L.LIFT[1] + Vector3(0, -6.0, 0)])
	for pr in pairs:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		var n := int(a.distance_to(b) / 2.0) + 1
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			_stamp(p.x, p.z, 10.0, p.y, p.y + 6.0)
	_stamp(L.PIT.x, L.PIT.z, L.PIT_HALF + 8.0, L.PIT.y, L.PIT.y)
	# пруды с береговой кромкой — по ним ходят
	for pl in IceRiver.POOLS:
		var zz: float = pl[2] - 8.0
		while zz <= pl[3] + 8.0:
			var xx: float = pl[0] - 8.0
			while xx <= pl[1] + 8.0:
				_stamp(xx, zz, 6.0, pl[4], pl[4] + 2.0)
				xx += 4.0
			zz += 4.0
	# ворота и озеро у ворот: ворота высокие
	_stamp(L.GATE.x, L.GATE.z, 22.0, L.GATE.y, L.GATE.y + 14.0)


func _stamp(x: float, z: float, r: float, y0: float, y1: float) -> void:
	var ix0 := maxi(int(floor((x - r - L.X_MIN) / CELL)), 0)
	var ix1 := mini(int(ceil((x + r - L.X_MIN) / CELL)), _nx - 1)
	var iz0 := maxi(int(floor((z - r - L.Z_MIN) / CELL)), 0)
	var iz1 := mini(int(ceil((z + r - L.Z_MIN) / CELL)), _nz - 1)
	var r2 := r * r
	for iz in range(iz0, iz1 + 1):
		var dz := L.Z_MIN + iz * CELL - z
		for ix in range(ix0, ix1 + 1):
			var dx := L.X_MIN + ix * CELL - x
			if dx * dx + dz * dz > r2:
				continue
			var k := iz * _nx + ix
			_lo[k] = minf(_lo[k], y0)
			_hi[k] = maxf(_hi[k], y1)


## Можно ли поставить глыбу высотой от y0 до y1 в точке (x, z): below — на сколько ниже дорог держаться
func _free(x: float, z: float, y0: float, y1: float, below: float) -> bool:
	var ix := int(round((x - L.X_MIN) / CELL))
	var iz := int(round((z - L.Z_MIN) / CELL))
	if ix < 0 or iz < 0 or ix >= _nx or iz >= _nz:
		return true
	var k := iz * _nx + ix
	if _lo[k] > 1e8:
		return true
	return y1 < _lo[k] - below or y0 > _hi[k] + 7.0


# ---------------------------------------------------------------------------
#  Расстановка
# ---------------------------------------------------------------------------

## Глыба на поверхности: s — точка поверхности, n — наружу от стены
func _rock(s: Vector3, n: Vector3, size: Vector3, protrude: float, mat_i: int, below: float) -> bool:
	if n.length_squared() < 0.25:
		return false
	n = n.normalized()
	var up := Vector3.UP - n * n.dot(Vector3.UP)
	if up.length() < 0.2:
		return false
	up = up.normalized()
	var side := up.cross(n).normalized()
	var roll := rng.randf_range(-0.35, 0.35) + (PI if rng.randf() < 0.5 else 0.0)
	var bs := Basis(side, up, n).rotated(n, roll)
	bs = Basis(bs.x * size.x, bs.y * size.y, bs.z * size.z)
	var o := s - n * (size.z - protrude)
	# габарит по высоте и самая дальняя точка — проверка, что не лезет на дорогу
	var ext := maxf(size.x, size.y)
	var tip := o + n * size.z
	if below >= 0.0:
		if not _free(o.x, o.z, o.y - ext, o.y + ext, below):
			return false
		if not _free(tip.x, tip.z, o.y - ext, o.y + ext, below):
			return false
	if L.in_cave(o.x, o.z, 10.0):
		return false
	var vi := rng.randi_range(0, VARIANTS - 1)
	var key := Vector3i(int(floor(o.x / CHUNK)), int(floor(o.z / CHUNK)), mat_i * 8 + vi)
	if not _buckets.has(key):
		_buckets[key] = []
	(_buckets[key] as Array).append(Transform3D(bs, o))
	count += 1
	return true


## Размер наплыва: обычно широкий плоский выступ («полка»), иногда высокий контрфорс
func _size(big: float) -> Vector3:
	if rng.randf() < 0.12:
		return Vector3(rng.randf_range(1.6, 2.6), rng.randf_range(4.0, 7.0), rng.randf_range(1.2, 1.8)) * big
	return Vector3(rng.randf_range(1.8, 3.8), rng.randf_range(1.0, 2.4), rng.randf_range(1.0, 1.7)) * big


static func _inv_smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 0.5 - sin(asin(1.0 - 2.0 * t) / 3.0)


func _ter_normal(x: float, z: float) -> Vector3:
	var e := 0.6
	var hx: float = (_ter.height_at(x + e, z) - _ter.height_at(x - e, z)) / (2.0 * e)
	var hz: float = (_ter.height_at(x, z + e) - _ter.height_at(x, z - e)) / (2.0 * e)
	return Vector3(-hx, 1.0, -hz).normalized()


## Стены ущелий: вдоль подножия стены — «столбики» глыб по всей высоте
func _terrain_walls() -> void:
	var step := 3.6
	var z := L.Z_MIN + 3.0
	while z < L.Z_MAX - 6.0:
		var x := L.X_MIN + 2.0
		while x < L.X_MAX - 2.0:
			var px := x + rng.randf_range(-1.2, 1.2)
			var pz := z + rng.randf_range(-1.2, 1.2)
			x += step
			var wd := L.wall_d(px, pz)
			if wd < 0.0 or wd >= step:
				continue
			var g := Vector2(L.wall_d(px + 0.8, pz) - L.wall_d(px - 0.8, pz), L.wall_d(px, pz + 0.8) - L.wall_d(px, pz - 0.8))
			if g.length() < 0.4:
				continue
			g = g.normalized()
			var y := rng.randf_range(-42.0, -32.0)
			while y < L.PLATEAU - 3.0:
				var frac := (y - L.ABYSS_Y) / (L.PLATEAU - L.ABYSS_Y)
				var d := L.WALL * _inv_smooth(frac)
				var p := Vector2(px, pz) + g * (d - wd)
				var h: float = _ter.height_at(p.x, p.y)
				var n := _ter_normal(p.x, p.y)
				if n.y < 0.72 and rng.randf() < 0.85:
					var big := lerpf(1.0, 1.5, smoothstep(-10.0, -45.0, h))
					_rock(Vector3(p.x, h, p.y), n, _size(big), rng.randf_range(0.5, 1.2), 0, 3.5)
				y += rng.randf_range(6.0, 10.0)
		z += step


## Обрывы вокруг прудов (берег на «столбе» над пропастью)
func _pool_cliffs() -> void:
	for pl in IceRiver.POOLS:
		var x0: float = pl[0]
		var x1: float = pl[1]
		var z0: float = pl[2]
		var z1: float = pl[3]
		var top: float = pl[4]
		var z := z0 - 14.0
		while z < z1 + 14.0:
			var x := x0 - 14.0
			while x < x1 + 14.0:
				var px := x + rng.randf_range(-1.2, 1.2)
				var pz := z + rng.randf_range(-1.2, 1.2)
				x += 3.2
				var dx := maxf(maxf(x0 - px, px - x1), 0.0)
				var dz := maxf(maxf(z0 - pz, pz - z1), 0.0)
				var pd := sqrt(dx * dx + dz * dz)
				if pd <= 0.0:
					continue
				var rim: float = 4.0 + L.pool_rim_extra(px, pz)
				if pd < rim or pd >= rim + 3.2:
					continue
				var out := Vector2(px - clampf(px, x0, x1), pz - clampf(pz, z0, z1)).normalized()
				var y := top - rng.randf_range(2.0, 3.5)
				while y > -46.0:
					var s := (top - y) / 7.0
					var p := Vector2(px, pz) + out * (rim - pd + s)
					var h: float = _ter.height_at(p.x, p.y)
					var n := _ter_normal(p.x, p.y)
					if n.y < 0.72 and h < top - 1.2:
						_rock(Vector3(p.x, h, p.y), n, _size(1.0), rng.randf_range(0.5, 1.1), 0, 0.8)
					y -= rng.randf_range(5.0, 8.0)
			z += 3.2


## Бок дороги или площадки: столбик наплывов от края вниз
## s = [точка на краю (верх), наружу, низ бока, клин (flare), имя]
func _cliff_column(s: Array) -> void:
	var a: Vector3 = s[0]
	var out: Vector3 = s[1]
	var bot: float = s[2]
	var flare: float = s[3]
	var d := rng.randf_range(2.2, 3.4)
	while d < 30.0:
		var y := a.y - d
		if y < bot + 1.5:
			break
		var off: float = minf(d * flare, 8.0) + float(cv._relief(a.x, y, a.z, d))
		var sz := Vector3(rng.randf_range(1.4, 2.8), rng.randf_range(0.8, 1.8), rng.randf_range(0.8, 1.3))
		if d < sz.y + 1.0:
			d += 0.5
			continue
		_rock(Vector3(a.x, y, a.z) + out * off, out, sz, rng.randf_range(0.4, 0.9), 1, 0.6)
		d += rng.randf_range(4.5, 7.0)


func _flush() -> void:
	var root := Node3D.new()
	root.name = "WallRocks"
	cv.add_child(root)
	for key: Vector3i in _buckets:
		var xfs: Array = _buckets[key]
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _meshes[(key.z % 8) * 2 + lod]
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = _mats[key.z / 8]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lod == 0:
				mi.visibility_range_end = NEAR
			else:
				mi.visibility_range_begin = NEAR
				mi.visibility_range_end = VIS
			root.add_child(mi)
