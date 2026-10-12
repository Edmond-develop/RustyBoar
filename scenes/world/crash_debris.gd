extends RefCounted
## Модели обломков «Ржавого Борова», построенные из кода.
## Каждая функция возвращает готовый меш (ArrayMesh) — его ставят в MeshInstance3D.
## Материалы — hull_metal.gdshader: краска, стёртый металл, сажа, ржавчина, заклёпки.

const METAL := preload("res://shaders/hull_metal.gdshader")


static func metal(paint: Color, wear: float = 0.35, soot: float = 0.45, rust: float = 0.25,
		hazard: float = 0.0, hazard_y: float = 0.0, heat: float = 0.0, panel: float = 0.9) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = METAL
	m.set_shader_parameter("paint", paint)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("soot", soot)
	m.set_shader_parameter("rust", rust)
	m.set_shader_parameter("hazard", hazard)
	m.set_shader_parameter("hazard_y", hazard_y)
	m.set_shader_parameter("heat", heat)
	m.set_shader_parameter("panel", panel)
	return m


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color = Color.WHITE) -> void:
	st.set_color(col); st.add_vertex(a)
	st.set_color(col); st.add_vertex(b)
	st.set_color(col); st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color = Color.WHITE) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _finish(st: SurfaceTool, mat: Material) -> ArrayMesh:
	st.generate_normals()
	st.set_material(mat)
	return st.commit()


# ---------------------------------------------------------------------------
#  Рваный лист обшивки: изогнутый, с вмятинами, края рваные
# ---------------------------------------------------------------------------
static func torn_plate(rng: RandomNumberGenerator, w: float, h: float, bend: float, mat: Material) -> ArrayMesh:
	var nx := 10
	var ny := 8
	var cw := w / nx
	var chh := h / ny
	var dents: Array[Vector3] = []
	for k in 3:
		dents.append(Vector3(rng.randf_range(-0.4, 0.4) * w, rng.randf_range(-0.4, 0.4) * h, rng.randf_range(-0.25, 0.25)))
	var grid := {}
	for j in ny + 1:
		for i in nx + 1:
			var x := (float(i) / nx - 0.5) * w
			var y := (float(j) / ny - 0.5) * h
			if i == 0 or j == 0 or i == nx or j == ny:
				# рваный край: точки края сдвинуты внутрь на разную глубину
				var inward := Vector2(-x, -y).normalized()
				var depth := rng.randf_range(0.0, 1.6) * minf(cw, chh)
				x += inward.x * depth + rng.randf_range(-0.3, 0.3) * cw
				y += inward.y * depth + rng.randf_range(-0.3, 0.3) * chh
			var z := bend * x * x / maxf(w, 0.1)
			for d in dents:
				z += d.z * exp(-((x - d.x) * (x - d.x) + (y - d.y) * (y - d.y)) / (0.08 * w * h))
			grid[Vector2i(i, j)] = Vector3(x, y, z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in ny:
		for i in nx:
			_quad(st, grid[Vector2i(i, j)], grid[Vector2i(i + 1, j)], grid[Vector2i(i + 1, j + 1)], grid[Vector2i(i, j + 1)])
	return _finish(st, mat)


# ---------------------------------------------------------------------------
#  Балка-двутавр, согнутая в середине
# ---------------------------------------------------------------------------
static func girder(length: float, kink: float, mat: Material) -> ArrayMesh:
	var hgt := 0.42
	var fw := 0.3
	var t := 0.05
	# профиль «I» (по часовой стрелке)
	var prof := [Vector2(-fw / 2, -hgt / 2), Vector2(fw / 2, -hgt / 2), Vector2(fw / 2, -hgt / 2 + t),
		Vector2(t / 2, -hgt / 2 + t), Vector2(t / 2, hgt / 2 - t), Vector2(fw / 2, hgt / 2 - t),
		Vector2(fw / 2, hgt / 2), Vector2(-fw / 2, hgt / 2), Vector2(-fw / 2, hgt / 2 - t),
		Vector2(-t / 2, hgt / 2 - t), Vector2(-t / 2, -hgt / 2 + t), Vector2(-fw / 2, -hgt / 2 + t)]
	var half := length * 0.5
	var path := [Vector3(0, 0, 0), Vector3(0, 0, half), Vector3(sin(kink) * half, 0.0, half + cos(kink) * half)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in 2:
		var a: Vector3 = path[s]
		var b: Vector3 = path[s + 1]
		var tan := (b - a).normalized()
		var side := tan.cross(Vector3.UP).normalized()
		var up := side.cross(tan).normalized()
		for k in prof.size():
			var p0: Vector2 = prof[k]
			var p1: Vector2 = prof[(k + 1) % prof.size()]
			var a0 := a + side * p0.x + up * p0.y
			var a1 := a + side * p1.x + up * p1.y
			var b0 := b + side * p0.x + up * p0.y
			var b1 := b + side * p1.x + up * p1.y
			_quad(st, a0, a1, b1, b0)
	return _finish(st, mat)


# ---------------------------------------------------------------------------
#  Тело вращения по профилю [(вдоль оси, радиус)] — для двигателя и антенны
#  jag_front > 0 — передний край рваный (вершины первого кольца сдвинуты вдоль оси)
# ---------------------------------------------------------------------------
static func _lathe(st: SurfaceTool, prof: Array, segs: int, rng: RandomNumberGenerator, jag_front: float = 0.0, col: Color = Color.WHITE) -> void:
	var jag: Array[float] = []
	for i in segs:
		jag.append(rng.randf_range(0.0, jag_front) if jag_front > 0.0 else 0.0)
	for k in prof.size() - 1:
		var p0: Vector2 = prof[k]
		var p1: Vector2 = prof[k + 1]
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var z00 := p0.x + (jag[i] if k == 0 else 0.0)
			var z01 := p0.x + (jag[(i + 1) % segs] if k == 0 else 0.0)
			var v00 := Vector3(cos(a0) * p0.y, sin(a0) * p0.y, z00)
			var v01 := Vector3(cos(a1) * p0.y, sin(a1) * p0.y, z01)
			var v10 := Vector3(cos(a0) * p1.y, sin(a0) * p1.y, p1.x)
			var v11 := Vector3(cos(a1) * p1.y, sin(a1) * p1.y, p1.x)
			_quad(st, v00, v01, v11, v10, col)


## Оторванный двигатель: корпус с рёбрами, рваный перед, раструб сопла, внутри — турбина.
## Возвращает [корпус, раскалённое сопло] — два меша с разными материалами.
static func engine(rng: RandomNumberGenerator, body_mat: Material, hot_mat: Material) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := [Vector2(0.0, 1.5), Vector2(0.5, 1.55), Vector2(0.9, 1.55), Vector2(1.0, 1.66), Vector2(1.25, 1.66),
		Vector2(1.35, 1.55), Vector2(2.6, 1.55), Vector2(2.7, 1.66), Vector2(2.95, 1.66), Vector2(3.05, 1.55),
		Vector2(4.4, 1.5), Vector2(4.6, 1.36), Vector2(5.2, 1.48), Vector2(6.0, 1.8)]
	_lathe(st, prof, 22, rng, 0.9)
	# турбина внутри: диск и лопатки
	var hub := [Vector2(1.6, 0.0), Vector2(1.6, 0.45), Vector2(2.0, 0.45), Vector2(2.0, 0.0)]
	_lathe(st, hub, 12, rng, 0.0, Color(0.5, 0.5, 0.52))
	for b in 14:
		var a := TAU * b / 14.0
		var d := Vector3(cos(a), sin(a), 0.0)
		var s := Vector3(-d.y, d.x, 0.0) * 0.16
		_quad(st, d * 0.45 + Vector3(0, 0, 1.7) - s, d * 0.45 + Vector3(0, 0, 1.9) + s, d * 1.45 + Vector3(0, 0, 1.9) + s, d * 1.45 + Vector3(0, 0, 1.7) - s, Color(0.6, 0.6, 0.62))
	# стабилизаторы
	for f in 3:
		var a := TAU * f / 3.0 + 0.4
		var d := Vector3(cos(a), sin(a), 0.0)
		_quad(st, d * 1.55 + Vector3(0, 0, 3.2), d * 1.55 + Vector3(0, 0, 4.4), d * 2.4 + Vector3(0, 0, 4.3), d * 2.3 + Vector3(0, 0, 3.6))
	var body := _finish(st, body_mat)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(st2, [Vector2(5.95, 1.72), Vector2(5.3, 1.38), Vector2(4.8, 0.7), Vector2(4.75, 0.0)], 22, rng)
	var nozzle := _finish(st2, hot_mat)
	return [body, nozzle]


# ---------------------------------------------------------------------------
#  Крыло: размах вдоль Y (корень — y=0, рваный), хорда вдоль X, толщина вдоль Z
# ---------------------------------------------------------------------------
static func wing(rng: RandomNumberGenerator, span: float, mat: Material) -> ArrayMesh:
	var nu := 8
	var nv := 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_jag: Array[float] = []
	for i in nu + 1:
		root_jag.append(rng.randf_range(0.0, 0.8))
	for side in [1.0, -1.0]:
		var g := {}
		for j in nv + 1:
			var v := float(j) / nv
			var chord := lerpf(6.0, 2.4, v)
			var lead := lerpf(-3.0, 0.4, v)          # передняя кромка скошена назад
			var thick := lerpf(0.2, 0.07, v)
			for i in nu + 1:
				var u := float(i) / nu
				var x := lead + chord * u
				var y := v * span + (root_jag[i] if j == 0 else 0.0)
				var z: float = side * thick * sin(u * PI) * (1.0 - 0.3 * u)
				g[Vector2i(i, j)] = Vector3(x, y, z)
		for j in nv:
			for i in nu:
				if side > 0.0:
					_quad(st, g[Vector2i(i, j)], g[Vector2i(i + 1, j)], g[Vector2i(i + 1, j + 1)], g[Vector2i(i, j + 1)])
				else:
					_quad(st, g[Vector2i(i, j)], g[Vector2i(i, j + 1)], g[Vector2i(i + 1, j + 1)], g[Vector2i(i + 1, j)])
	return _finish(st, mat)


# ---------------------------------------------------------------------------
#  Тарелка антенны: параболоид с ободом, облучатель на трёх стойках, вмятина
# ---------------------------------------------------------------------------
static func dish(rng: RandomNumberGenerator, r: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	var rings := 6
	var dent_a := rng.randf() * TAU
	for k in rings:
		for i in segs:
			var pts: Array[Vector3] = []
			for c in [[k, i], [k, i + 1], [k + 1, i + 1], [k + 1, i]]:
				var rr: float = r * float(c[0]) / rings
				var a: float = TAU * float(c[1]) / segs
				var y := 0.6 * (rr / r) * (rr / r)
				# вмятина у края с одной стороны
				var dd := absf(wrapf(a - dent_a, -PI, PI))
				y -= 0.35 * (rr / r) * maxf(0.0, 1.0 - dd / 0.8)
				pts.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			_quad(st, pts[0], pts[1], pts[2], pts[3])
	# стойки облучателя
	for s in 3:
		var a := TAU * s / 3.0
		var base := Vector3(cos(a) * r * 0.95, 0.55, sin(a) * r * 0.95)
		var top := Vector3(0, 1.4, 0)
		var side := (top - base).cross(Vector3.UP).normalized() * 0.04
		_quad(st, base - side, base + side, top + side, top - side)
	_lathe_y(st, [Vector2(1.3, 0.0), Vector2(1.3, 0.14), Vector2(1.6, 0.1), Vector2(1.6, 0.0)], 10)
	return _finish(st, mat)


static func _lathe_y(st: SurfaceTool, prof: Array, segs: int) -> void:
	for k in prof.size() - 1:
		var p0: Vector2 = prof[k]
		var p1: Vector2 = prof[k + 1]
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			_quad(st, Vector3(cos(a0) * p0.y, p0.x, sin(a0) * p0.y), Vector3(cos(a1) * p0.y, p0.x, sin(a1) * p0.y),
				Vector3(cos(a1) * p1.y, p1.x, sin(a1) * p1.y), Vector3(cos(a0) * p1.y, p1.x, sin(a0) * p1.y))


# ---------------------------------------------------------------------------
#  Кусок фюзеляжа: изогнутая обшивка (дуга), рваные края, внутри — рёбра каркаса
#  Возвращает [обшивка, рёбра]
# ---------------------------------------------------------------------------
static func hull_section(rng: RandomNumberGenerator, radius: float, length: float, arc: float, skin_mat: Material, rib_mat: Material) -> Array:
	var na := 18
	var nz := 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := {}
	for j in nz + 1:
		for i in na + 1:
			var a := -arc * 0.5 + arc * float(i) / na
			var z := (float(j) / nz - 0.5) * length
			var r := radius
			if j == 0 or j == nz:
				z += (-1.0 if j == nz else 1.0) * rng.randf_range(0.0, 0.7)   # рваные торцы
			if i == 0 or i == na:
				a += (1.0 if i == 0 else -1.0) * rng.randf_range(0.0, 0.18)   # рваные боковые края
			r += rng.randf_range(-0.05, 0.05)
			g[Vector2i(i, j)] = Vector3(cos(a) * r, sin(a) * r, z)
	for j in nz:
		for i in na:
			_quad(st, g[Vector2i(i, j)], g[Vector2i(i + 1, j)], g[Vector2i(i + 1, j + 1)], g[Vector2i(i, j + 1)])
	var skin := _finish(st, skin_mat)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var z := (float(k) / 2.0 - 0.5) * length * 0.7
		for i in na:
			var a0 := -arc * 0.45 + arc * 0.9 * float(i) / na
			var a1 := -arc * 0.45 + arc * 0.9 * float(i + 1) / na
			var r0 := radius - 0.04
			var r1 := radius - 0.32
			var p := [Vector3(cos(a0) * r0, sin(a0) * r0, z - 0.08), Vector3(cos(a1) * r0, sin(a1) * r0, z - 0.08),
				Vector3(cos(a1) * r1, sin(a1) * r1, z - 0.08), Vector3(cos(a0) * r1, sin(a0) * r1, z - 0.08)]
			var q := [Vector3(cos(a0) * r0, sin(a0) * r0, z + 0.08), Vector3(cos(a1) * r0, sin(a1) * r0, z + 0.08),
				Vector3(cos(a1) * r1, sin(a1) * r1, z + 0.08), Vector3(cos(a0) * r1, sin(a0) * r1, z + 0.08)]
			_quad(st2, p[0], p[1], p[2], p[3])
			_quad(st2, q[3], q[2], q[1], q[0])
			_quad(st2, p[3], p[2], q[2], q[3])
	# продольные стрингеры
	for s in 5:
		var a := -arc * 0.4 + arc * 0.8 * float(s) / 4.0
		var d := Vector3(cos(a), sin(a), 0.0)
		var tng := Vector3(-d.y, d.x, 0.0) * 0.05
		var r0 := radius - 0.05
		var r1 := radius - 0.2
		_quad(st2, d * r0 + tng + Vector3(0, 0, -length * 0.42), d * r0 + tng + Vector3(0, 0, length * 0.42), d * r1 + tng + Vector3(0, 0, length * 0.42), d * r1 + tng + Vector3(0, 0, -length * 0.42))
	var ribs := _finish(st2, rib_mat)
	return [skin, ribs]


# ---------------------------------------------------------------------------
#  Грузовой контейнер курьерской службы: гофрированные стенки, рама,
#  одна створка сорвана, вторая висит. Длина вдоль X, открытый торец — +X.
#  Возвращает [стенки, рама, створка]
# ---------------------------------------------------------------------------
static func container(size: Vector3, wall_mat: Material, frame_mat: Material) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x / 2
	var hy := size.y / 2
	var hz := size.z / 2
	var ribs := int(size.x / 0.3)
	# боковые гофрированные стенки (±Z)
	for side in [-1.0, 1.0]:
		for i in ribs:
			var x0 := -hx + size.x * float(i) / ribs
			var x1 := -hx + size.x * float(i + 1) / ribs
			var dz0 := 0.05 if i % 2 == 0 else 0.0
			var dz1 := 0.05 if i % 2 == 1 else 0.0
			var a := Vector3(x0, -hy, side * (hz + dz0))
			var b := Vector3(x1, -hy, side * (hz + dz1))
			var c := Vector3(x1, hy, side * (hz + dz1))
			var d := Vector3(x0, hy, side * (hz + dz0))
			if side > 0.0:
				_quad(st, a, b, c, d)
			else:
				_quad(st, b, a, d, c)
	# крыша, пол, задняя стенка
	_quad(st, Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz))
	_quad(st, Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz))
	_quad(st, Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz))
	var walls := _finish(st, wall_mat)
	# рама — угловые стойки и балки
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cx in [-hx, hx]:
		for cz in [-hz, hz]:
			_box(st2, Vector3(cx, 0, cz), Vector3(0.14, size.y + 0.04, 0.14))
	for cy in [-hy, hy]:
		for cz in [-hz, hz]:
			_box(st2, Vector3(0, cy, cz), Vector3(size.x, 0.12, 0.12))
	var frame := _finish(st2, frame_mat)
	var st3 := SurfaceTool.new()
	st3.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st3, Vector3(0.0, 0.0, hz * 0.5), Vector3(0.06, size.y - 0.1, hz))
	var door := _finish(st3, wall_mat)
	return [walls, frame, door]


static func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s / 2
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	_quad(st, p[0], p[3], p[2], p[1])
	_quad(st, p[4], p[5], p[6], p[7])
	_quad(st, p[0], p[1], p[5], p[4])
	_quad(st, p[3], p[7], p[6], p[2])
	_quad(st, p[0], p[4], p[7], p[3])
	_quad(st, p[1], p[2], p[6], p[5])


# ---------------------------------------------------------------------------
#  Кабель: трубка по провисающей кривой от a до b
# ---------------------------------------------------------------------------
static func cable(a: Vector3, b: Vector3, sag: float, radius: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 18
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	for i in n:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var tan := (p1 - p0).normalized()
		var ref := Vector3.UP if absf(tan.y) < 0.9 else Vector3.RIGHT
		var u := tan.cross(ref).normalized()
		var v := tan.cross(u).normalized()
		for k in 6:
			var a0 := TAU * k / 6.0
			var a1 := TAU * (k + 1) / 6.0
			var d0 := (u * cos(a0) + v * sin(a0)) * radius
			var d1 := (u * cos(a1) + v * sin(a1)) * radius
			_quad(st, p0 + d0, p0 + d1, p1 + d1, p1 + d0)
	return _finish(st, mat)


## Ком земли / камень (неровная сфера)
static func clod(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 6
	var rings := 4
	var pts := {}
	for j in rings + 1:
		for i in n:
			var b := PI * float(j) / rings - PI * 0.5
			var a := TAU * i / n
			var k := rng.randf_range(0.7, 1.2) if j > 0 and j < rings else 1.0
			pts[Vector2i(i, j)] = Vector3(cos(a) * cos(b), sin(b) * 0.7, sin(a) * cos(b)) * k
	for j in rings:
		for i in n:
			var i1 := (i + 1) % n
			_quad(st, pts[Vector2i(i, j)], pts[Vector2i(i, j + 1)], pts[Vector2i(i1, j + 1)], pts[Vector2i(i1, j)])
	st.generate_normals()
	return st.commit()
