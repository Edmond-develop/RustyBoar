extends RefCounted
## Шесть знаков замка ворот каньона: треугольник, квадрат, круг, ромб, звезда, крест.
## Один и тот же контур — и на деталях/гнёздах в мире (меш), и в окне головоломки (рисунок).

const NAMES := ["Треугольник", "Квадрат", "Круг", "Ромб", "Звезда", "Крест"]
const COLORS := [Color(1.0, 0.55, 0.2), Color(0.4, 0.85, 1.0), Color(0.6, 1.0, 0.5),
	Color(1.0, 0.4, 0.75), Color(1.0, 0.9, 0.3), Color(0.75, 0.6, 1.0)]


## Контур знака i (радиус ~1)
static func polygon(i: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match i:
		0:
			for k in 3:
				var a := -PI * 0.5 + TAU * k / 3.0
				pts.append(Vector2(cos(a), sin(a)) * 1.05)
		1:
			pts = PackedVector2Array([Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)])
		2:
			for k in 20:
				var a2 := TAU * k / 20.0
				pts.append(Vector2(cos(a2), sin(a2)) * 0.9)
		3:
			pts = PackedVector2Array([Vector2(0, -1.05), Vector2(0.7, 0), Vector2(0, 1.05), Vector2(-0.7, 0)])
		4:
			for k in 10:
				var a3 := -PI * 0.5 + TAU * k / 10.0
				pts.append(Vector2(cos(a3), sin(a3)) * (1.05 if k % 2 == 0 else 0.45))
		_:
			var w := 0.32
			pts = PackedVector2Array([Vector2(-w, -1), Vector2(w, -1), Vector2(w, -w), Vector2(1, -w), Vector2(1, w), Vector2(w, w),
				Vector2(w, 1), Vector2(-w, 1), Vector2(-w, w), Vector2(-1, w), Vector2(-1, -w), Vector2(-w, -w)])
	return pts


## Плоский (с толщиной) меш знака в плоскости XY, лицом к +Z
static func mesh(i: int, size: float, thick: float) -> ArrayMesh:
	var poly := polygon(i)
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, face))
		for t in range(0, tris.size(), 3):
			var idx := [tris[t], tris[t + 1], tris[t + 2]] if face > 0.0 else [tris[t], tris[t + 2], tris[t + 1]]
			for j in idx:
				var p: Vector2 = poly[j] * size
				st.add_vertex(Vector3(p.x, -p.y, face * thick * 0.5))
	# бортик
	for k in poly.size():
		var a: Vector2 = poly[k] * size
		var b: Vector2 = poly[(k + 1) % poly.size()] * size
		var n := Vector3(b.y - a.y, b.x - a.x, 0.0).normalized()
		n = Vector3(n.x, n.y, 0.0)
		var va := Vector3(a.x, -a.y, thick * 0.5)
		var vb := Vector3(b.x, -b.y, thick * 0.5)
		var va2 := Vector3(a.x, -a.y, -thick * 0.5)
		var vb2 := Vector3(b.x, -b.y, -thick * 0.5)
		st.set_normal(n)
		st.add_vertex(va)
		st.add_vertex(va2)
		st.add_vertex(vb)
		st.add_vertex(vb)
		st.add_vertex(va2)
		st.add_vertex(vb2)
	return st.commit()


static func material(i: int, energy: float = 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = COLORS[i]
	m.emission_enabled = true
	m.emission = COLORS[i]
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Нарисовать знак на 2D-холсте (окно головоломки)
static func draw(ci: CanvasItem, i: int, center: Vector2, r: float, col: Color) -> void:
	var poly := polygon(i)
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(center + p * r)
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, col.lightened(0.4), 2.0, true)
