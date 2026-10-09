class_name IceCracks
extends Node3D
## Трещины на льду озера: каждая трещина — ОДНА полоса-разлом.
##
## На участке столько полос, сколько на нём трещин. С каждой новой трещиной
## ВСЕ полосы участка становятся длиннее и толще — до размера будущего провала:
##   1 трещина — 1 полоса ~4 м (вдоль направления шага);
##   2 — 2 полосы ~5,6 м;  3 — 3 толстые полосы ~7 м, проступает тёмная вода;
##   … 6 — 6 широких разломов по ~12 м — ровно размер провала.
##
## Каждая полоса — как настоящая трещина в прозрачном льду:
##  * на поверхности — тонкая острая линия скола;
##  * под ней в толще льда видна серебристая плоскость трещины с «перьями»
##    (ice_crack.gdshader): вдоль трещины она вспыхивает, сверху — молочная пелена,
##    вглубь тускнеет и голубеет; нижний край неровный, плоскость слегка наклонена;
##  * от полосы отходят короткие ответвления.
## Первая полоса тянется вдоль пути дрона, следующие пересекают её.
## Все трещины рисуются через MultiMesh — тысячи трещин почти не тормозят игру.

const SHAPES := 8                 ## Сколько разных изломов линии
const CAPACITY := 3000            ## Сколько полос каждой формы может быть на льду
const STAINS := 1500

## Длина (м) и толщина (множитель) полосы для участка с N трещинами
const LEVEL_LENGTH := [0.0, 4.0, 5.6, 7.2, 8.8, 10.4, 12.0]
const LEVEL_WIDTH := [0.0, 1.0, 1.4, 1.8, 2.2, 2.6, 3.0]    ## толщина линии и размах ответвлений
const LEVEL_DEPTH := [0.0, 0.3, 0.38, 0.46, 0.54, 0.6, 0.66]  ## насколько глубоко уходит скол (м)
const LEVEL_ALPHA := [0.0, 0.78, 0.84, 0.89, 0.93, 0.97, 1.0]   ## насколько трещина заметна

const CRACK_SHADER := preload("res://shaders/ice_crack.gdshader")

var _mms: Array[MultiMesh] = []
var _used: Array[int] = []
var _stain_mm: MultiMesh
var _stain_used := 0
var _cell_items := {}             ## участок -> [[форма, индекс, позиция, поворот], ...]
var _cell_stain := {}             ## участок -> индекс пятна


func _ready() -> void:
	# Плоскость трещины в толще льда (рисуется поверх прозрачного льда, но под дроном)
	var plane_mat := ShaderMaterial.new()
	plane_mat.shader = CRACK_SHADER
	plane_mat.render_priority = 2
	# Острая линия скола на поверхности
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 3

	for i in SHAPES:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _make_crack_mesh(2000 + i * 131, plane_mat, mat)
		mm.instance_count = CAPACITY
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-400, -50, -100), Vector3(800, 100, 800))
		add_child(mmi)
		_mms.append(mm)
		_used.append(0)

	# Мокрые тёмные пятна под сильно треснувшим льдом
	var stain_mat := mat.duplicate() as StandardMaterial3D
	stain_mat.render_priority = 1
	stain_mat.render_priority = 1
	_stain_mm = MultiMesh.new()
	_stain_mm.transform_format = MultiMesh.TRANSFORM_3D
	_stain_mm.use_colors = true
	_stain_mm.mesh = _make_stain_mesh(stain_mat)
	_stain_mm.instance_count = STAINS
	_stain_mm.visible_instance_count = 0
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = _stain_mm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smi.custom_aabb = AABB(Vector3(-400, -50, -100), Vector3(800, 100, 800))
	add_child(smi)


## Новая трещина на участке: добавляет одну полосу, и все полосы участка
## перерисовываются под новый уровень (длиннее и толще).
## Все компьютеры рисуют одинаково — форма и направление зависят от seed.
## dir_yaw — куда шёл дрон: первая полоса тянется вдоль его пути.
func add_crack(cell: Vector2i, center: Vector3, cell_size: float, level: int, seed_value: int, dir_yaw: float = NAN) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shape := rng.randi() % SHAPES
	if _used[shape] >= CAPACITY:
		return
	var pos := center + Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25)) * cell_size
	pos.y = IceRiver.river_y(pos.z) + 0.035
	var yaw := rng.randf() * PI
	if not is_nan(dir_yaw):
		yaw = dir_yaw + rng.randf_range(-0.3, 0.3)
	if _cell_items.has(cell) and not _cell_items[cell].is_empty():
		# следующая полоса — под заметным углом к предыдущей, чтобы они пересекались
		var prev_yaw: float = _cell_items[cell][-1][3]
		yaw = prev_yaw + rng.randf_range(0.6, PI - 0.6)
	var idx := _used[shape]
	_used[shape] += 1
	_mms[shape].visible_instance_count = _used[shape]
	if not _cell_items.has(cell):
		_cell_items[cell] = []
	_cell_items[cell].append([shape, idx, pos, yaw])

	var lv := clampi(level, 1, LEVEL_LENGTH.size() - 1)
	_apply_level(cell, lv)

	# С 3-й трещины под льдом проступает вода — тёмное пятно, растёт с уровнем
	if lv >= 3:
		var stain_size := cell_size * (1.0 + 0.6 * lv)
		var alpha := 0.4 + 0.1 * (lv - 3)
		var sb := _surface_basis(center.z, 0.0) * Basis.from_scale(Vector3(stain_size, 1.0, stain_size))
		var spos := Vector3(center.x, IceRiver.river_y(center.z) + 0.03, center.z)
		if _cell_stain.has(cell):
			var si: int = _cell_stain[cell]
			_stain_mm.set_instance_transform(si, Transform3D(sb, spos))
			_stain_mm.set_instance_color(si, Color(1, 1, 1, alpha))
		elif _stain_used < STAINS:
			_stain_mm.set_instance_transform(_stain_used, Transform3D(sb, spos))
			_stain_mm.set_instance_color(_stain_used, Color(1, 1, 1, alpha))
			_cell_stain[cell] = _stain_used
			_stain_used += 1
			_stain_mm.visible_instance_count = _stain_used


## Все полосы участка — по размеру его уровня
func _apply_level(cell: Vector2i, lv: int) -> void:
	var length: float = LEVEL_LENGTH[lv]
	var width: float = LEVEL_WIDTH[lv]
	var depth: float = LEVEL_DEPTH[lv]
	for item in _cell_items[cell]:
		var p: Vector3 = item[2]
		var b := _surface_basis(p.z, item[3]) * Basis.from_scale(Vector3(length, depth, width))
		_mms[item[0]].set_instance_transform(item[1], Transform3D(b, p))
		# .r — случайный узор «перьев», .a — заметность
		_mms[item[0]].set_instance_color(item[1], Color(fmod(item[3] * 7.31, 1.0), 1, 1, LEVEL_ALPHA[lv]))


## Длинные трещины, расходящиеся лучами от края свежего провала
func add_rim_cracks(x: float, z: float, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := rng.randi_range(9, 13)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var length := rng.randf_range(5.0, 9.0)
		var shape := rng.randi() % SHAPES
		if _used[shape] >= CAPACITY:
			continue
		# полоса начинается у края провала и уходит наружу
		var dist := radius + length * 0.5 - 0.3
		var pos := Vector3(x + cos(a) * dist, 0.0, z + sin(a) * dist)
		pos.y = IceRiver.river_y(pos.z) + 0.035
		var b := _surface_basis(pos.z, -a) * Basis.from_scale(Vector3(length, rng.randf_range(0.55, 0.66), rng.randf_range(2.2, 3.0)))
		var idx := _used[shape]
		_used[shape] += 1
		_mms[shape].set_instance_transform(idx, Transform3D(b, pos))
		_mms[shape].set_instance_color(idx, Color(rng.randf(), 1, 1, 1))
		_mms[shape].visible_instance_count = _used[shape]


## Спрятать трещины, которые оказались внутри полыньи
func clear_circle(x: float, z: float, radius: float, cell_size: float) -> void:
	var c0 := Vector2i(floori((x - radius) / cell_size), floori((z - radius) / cell_size))
	var c1 := Vector2i(floori((x + radius) / cell_size), floori((z + radius) / cell_size))
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			var center := Vector2((cx + 0.5) * cell_size, (cz + 0.5) * cell_size)
			if center.distance_to(Vector2(x, z)) > radius:
				continue
			for item in _cell_items.get(cell, []):
				_mms[item[0]].set_instance_transform(item[1], zero)
			_cell_items.erase(cell)
			if _cell_stain.has(cell):
				_stain_mm.set_instance_transform(_cell_stain[cell], zero)
				_cell_stain.erase(cell)


## Наклон по льду (на спусках лёд наклонён — трещина ложится вдоль него)
func _surface_basis(z: float, yaw: float) -> Basis:
	var slope := (IceRiver.river_y(z - 0.5) - IceRiver.river_y(z + 0.5))
	return Basis(Vector3.RIGHT, atan(slope)) * Basis(Vector3.UP, yaw)


# ---------------------------------------------------------------------------
#  Форма трещины: изломанная линия длиной 1 вдоль X с ответвлениями.
#  Экземпляр масштабируется: X — длина, Y — глубина скола, Z — толщина/размах.
#  Поверхность 0 — плоскость скола вглубь льда, поверхность 1 — линия на поверхности.
# ---------------------------------------------------------------------------

func _make_crack_mesh(seed_value: int, plane_mat: Material, line_mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lines: Array = []   # [точки, яркость]

	# Основная линия
	var main: Array[Vector2] = []
	var segs := rng.randi_range(9, 12)
	var drift := 0.0
	for i in segs + 1:
		var x := -0.5 + float(i) / segs
		if i > 0 and i < segs:
			x += rng.randf_range(-0.3, 0.3) / segs
			drift = clampf(drift + rng.randf_range(-0.03, 0.03), -0.05, 0.05)
		main.append(Vector2(x, drift if i > 0 and i < segs else 0.0))
	lines.append([main, 1.0])

	# Ответвления: короткие, уходят в сторону под углом и сужаются
	var branches := rng.randi_range(2, 4)
	for k in branches:
		var at := rng.randi_range(2, segs - 2)
		var start := main[at]
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var ang := side * rng.randf_range(0.5, 1.1)
		var length := rng.randf_range(0.07, 0.16)
		var pts: Array[Vector2] = [start]
		var p := start
		var steps := 3
		for st in steps:
			ang += rng.randf_range(-0.25, 0.25)
			# по Z экземпляр растянут слабее, чем по X, — компенсируем
			p += Vector2(cos(ang) * length / steps, sin(ang) * length / steps * 3.0)
			pts.append(p)
		lines.append([pts, 0.6])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in lines:
		_curtain(st, line[0], line[1], rng)
	st.set_material(plane_mat)
	var mesh := st.commit()

	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in lines:
		var pts: Array = line[0]
		var k: float = line[1]
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ta := clampf(1.0 - absf(a.x) * 1.8, 0.1, 1.0) * k
			var tb := clampf(1.0 - absf(b.x) * 1.8, 0.1, 1.0) * k
			if k < 1.0:
				tb *= 1.0 - float(i + 1) / (pts.size() - 1) * 0.8
			# тень-преломление вдоль линии и тонкая светлая кромка
			_strip(st2, a, b, 0.045 * ta, 0.045 * tb, Color(0.02, 0.08, 0.18, 0.55), Color(0.05, 0.2, 0.35, 0.0))
			_strip(st2, a, b, 0.014 * ta, 0.014 * tb, Color(0.97, 1.0, 1.0, 1.0), Color(0.8, 0.93, 1.0, 0.6))
	st2.set_material(line_mat)
	return st2.commit(mesh)


## «Шторка» вглубь льда под линией: сверху — у поверхности, снизу — неровное дно скола.
## Плоскость слегка наклонена, нижний край рваный.
func _curtain(st: SurfaceTool, pts: Array, strength: float, rng: RandomNumberGenerator) -> void:
	var n := pts.size()
	var total := 0.0
	var acc: Array[float] = [0.0]
	for i in n - 1:
		total += (pts[i + 1] - pts[i]).length()
		acc.append(total)
	# плоскость скола наклонена — сверху видна как серебристая «пелена» рядом с линией
	var lean := rng.randf_range(0.22, 0.42) * (1.0 if rng.randf() > 0.5 else -1.0)
	var bottoms: Array[Vector3] = []
	for i in n:
		var p: Vector2 = pts[i]
		var depth := rng.randf_range(0.55, 1.0) * strength
		var t := acc[i] / maxf(total, 0.0001)
		depth *= clampf(sin(t * PI) * 1.4, 0.15, 1.0)   # к концам скол мельче
		bottoms.append(Vector3(p.x, -depth, p.y + lean * depth))
	for i in n - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ua := acc[i] / maxf(total, 0.0001)
		var ub := acc[i + 1] / maxf(total, 0.0001)
		var ta := Vector3(a.x, 0.0, a.y)
		var tb := Vector3(b.x, 0.0, b.y)
		var ba: Vector3 = bottoms[i]
		var bb: Vector3 = bottoms[i + 1]
		var normal := (tb - ta).cross(ba - ta).normalized()
		var col := Color(1, 1, 1, strength)
		_vert(st, ta, Vector2(ua, 0.0), normal, col)
		_vert(st, tb, Vector2(ub, 0.0), normal, col)
		_vert(st, ba, Vector2(ua, 1.0), normal, col)
		_vert(st, tb, Vector2(ub, 0.0), normal, col)
		_vert(st, bb, Vector2(ub, 1.0), normal, col)
		_vert(st, ba, Vector2(ua, 1.0), normal, col)


func _vert(st: SurfaceTool, p: Vector3, uv: Vector2, normal: Vector3, col: Color) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.set_color(col)
	st.add_vertex(p)


## Полоска толщиной w вдоль отрезка a→b (на плоскости XZ). Края полупрозрачные.
func _strip(st: SurfaceTool, a: Vector2, b: Vector2, wa: float, wb: float, mid: Color, edge: Color) -> void:
	var d := (b - a)
	if d.length() < 0.0001:
		return
	var n := Vector2(-d.y, d.x).normalized()
	var a0 := Vector3(a.x, 0, a.y)
	var b0 := Vector3(b.x, 0, b.y)
	var al := Vector3(a.x + n.x * wa, 0, a.y + n.y * wa)
	var ar := Vector3(a.x - n.x * wa, 0, a.y - n.y * wa)
	var bl := Vector3(b.x + n.x * wb, 0, b.y + n.y * wb)
	var br := Vector3(b.x - n.x * wb, 0, b.y - n.y * wb)
	_tri(st, a0, mid, al, edge, b0, mid)
	_tri(st, al, edge, bl, edge, b0, mid)
	_tri(st, a0, mid, b0, mid, ar, edge)
	_tri(st, ar, edge, b0, mid, br, edge)


func _tri(st: SurfaceTool, p1: Vector3, c1: Color, p2: Vector3, c2: Color, p3: Vector3, c3: Color) -> void:
	st.set_normal(Vector3.UP)
	st.set_color(c1)
	st.add_vertex(p1)
	st.set_color(c2)
	st.add_vertex(p2)
	st.set_color(c3)
	st.add_vertex(p3)


## Мокрое пятно: тёмно-синий круг, плотный в центре и прозрачный к краю
func _make_stain_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	var inner := Color(0.02, 0.1, 0.22, 1.0)
	var outer := Color(0.02, 0.1, 0.22, 0.0)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_tri(st, Vector3.ZERO, inner, Vector3(cos(a1), 0, sin(a1)) * 0.5, outer, Vector3(cos(a0), 0, sin(a0)) * 0.5, outer)
	st.set_material(mat)
	return st.commit()
