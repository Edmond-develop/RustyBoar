extends RefCounted
## Разные формы дорог ледяного каньона (canyon_layout.FORMS):
##   ledge  — карниз в скале: стена ущелья вплотную с одной стороны, сверху нависают ледяные козырьки
##   stilts — дощатые мостки на сваях вдоль стены, с перилами
##   tunnel — участок сквозь толщу льда: арочный ход, лампы, сверху — снег плато
##   rope   — подвесной мост: доски на канатах, качается (у всех одинаково — по общему времени)
##   floes  — льдины-столбы над пропастью: от одной к другой — прыжком
## Строится один раз при загрузке; подвесные мосты двигает physics_tick() (зовёт каньон).

const L := preload("res://scenes/world/canyon_layout.gd")
const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")

var cv: Node3D
var rng := RandomNumberGenerator.new()
var _st := {}
var _mats := {}
var _swings: Array = []          ## [тело, середина, ось, фаза, размах, цикл, полупролёт]
var calm := false                ## для проверок: мосты не дёргают


func _init(canyon: Node3D) -> void:
	cv = canyon
	rng.seed = 90210


func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"bore":
			var sm := ShaderMaterial.new()
			sm.shader = ICE_SHADER
			sm.set_shader_parameter("deep", Color(0.01, 0.06, 0.16))
			sm.set_shader_parameter("mid", Color(0.08, 0.32, 0.58))
			sm.set_shader_parameter("edge", Color(0.45, 0.8, 1.0))
			sm.set_shader_parameter("snow_amount", 0.15)
			sm.set_shader_parameter("crack_amount", 1.0)
			sm.set_shader_parameter("glow", 0.35)
			sm.set_shader_parameter("band_scale", 1.6)
			sm.set_shader_parameter("base_rough", 0.1)
			m = sm
		"floe":
			var sm2 := ShaderMaterial.new()
			sm2.shader = ICE_SHADER
			sm2.set_shader_parameter("deep", Color(0.02, 0.14, 0.3))
			sm2.set_shader_parameter("mid", Color(0.18, 0.5, 0.76))
			sm2.set_shader_parameter("edge", Color(0.6, 0.85, 1.0))
			sm2.set_shader_parameter("snow_amount", 0.6)
			sm2.set_shader_parameter("crack_amount", 0.7)
			sm2.set_shader_parameter("band_scale", 0.5)
			sm2.set_shader_parameter("depth_dark", 1.0)
			m = sm2
		_:
			var s := StandardMaterial3D.new()
			var spec: Array = {
				"wood": [Color(0.42, 0.28, 0.16), 0.85, 0.0, Color(0, 0, 0), 0.0],
				"wood_dark": [Color(0.25, 0.16, 0.09), 0.9, 0.0, Color(0, 0, 0), 0.0],
				"rope": [Color(0.55, 0.45, 0.3), 0.95, 0.0, Color(0, 0, 0), 0.0],
				"iron": [Color(0.25, 0.26, 0.28), 0.5, 0.7, Color(0, 0, 0), 0.0],
				"lamp": [Color(0.8, 0.95, 1.0), 0.2, 0.0, Color(0.55, 0.85, 1.0), 3.5],
				"snow": [Color(0.92, 0.95, 1.0), 0.8, 0.0, Color(0, 0, 0), 0.0],
			}[key]
			s.albedo_color = spec[0]
			s.roughness = spec[1]
			s.metallic = spec[2]
			if spec[4] > 0.0:
				s.emission_enabled = true
				s.emission = spec[3]
				s.emission_energy_multiplier = spec[4]
			m = s
	_mats[key] = m
	return m


# ---------------------------------------------------------------------------
#  Слияние мелочи в один меш на материал
# ---------------------------------------------------------------------------

func put(mesh: Mesh, xf: Transform3D, key: String) -> void:
	var st: SurfaceTool = _st.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	st.append_from(mesh, 0, xf)


func box(size: Vector3, xf: Transform3D, key: String) -> void:
	var m := BoxMesh.new()
	m.size = size
	put(m, xf, key)


func beam(a: Vector3, b: Vector3, r: float, key: String, seg: int = 6, r_end: float = -1.0) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var m := CylinderMesh.new()
	m.top_radius = r if r_end < 0.0 else r_end
	m.bottom_radius = r
	m.height = d.length()
	m.radial_segments = seg
	m.rings = 1
	m.cap_top = m.top_radius > 0.0
	put(m, Transform3D(basis_y(d), (a + b) * 0.5), key)


static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


func flush(parent: Node3D, vis_end: float) -> void:
	for key in _st:
		var st: SurfaceTool = _st[key]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = mesh
		mi.material_override = mat(key)
		mi.visibility_range_end = vis_end
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	_st.clear()


func _side(path: Array, k: int) -> Vector3:
	var a: Vector3 = path[maxi(k - 1, 0)]
	var b: Vector3 = path[mini(k + 1, path.size() - 1)]
	var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return Vector3(-t.z, 0.0, t.x)


func _fwd(path: Array, k: int) -> Vector3:
	var a: Vector3 = path[maxi(k - 1, 0)]
	var b: Vector3 = path[mini(k + 1, path.size() - 1)]
	return Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()


func _hw(road: String) -> float:
	return float(L.ROAD_WIDTH.get(road, 7.5)) * 0.5


func _near_trap(p: Vector3, dist: float) -> bool:
	for x in L.PENDULUMS + L.VISES + L.CRACKS + L.CRUMBLES + L.ICEFALLS:
		var a: Vector3 = x[0]
		var b: Vector3 = x[1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (ap - ab * t).length() < dist:
			return true
	return false


# ---------------------------------------------------------------------------
#  Сборка
# ---------------------------------------------------------------------------

func build() -> void:
	for road in cv.form_sections:
		var fs: Dictionary = cv.form_sections[road]
		var path: Array = cv.road_paths[road]
		var root := Node3D.new()
		root.name = "Form_%s" % road
		cv.add_child(root)
		match String(fs["kind"]):
			"tunnel":
				_tunnel(road, path, int(fs["k0"]), int(fs["k1"]), root)
			"rope":
				_rope(road, path, int(fs["k0"]), int(fs["k1"]), root)
			"floes":
				_floes(road, path, int(fs["k0"]), int(fs["k1"]), root)
			"ledge":
				_ledge(road, path, int(fs["side"]), root)
			"stilts":
				_stilts(road, path, int(fs["side"]), root)
			"spiral":
				_spiral(road, path, root)
			"arch":
				_arch(road, path, int(fs["k0"]), int(fs["k1"]), root)
			"ridge":
				_ridge(road, path, root)
		flush(root, 260.0)


## Качка подвесных мостов: настил качается вокруг линии креплений (концы на месте, середина
## ходит вбок), раз в несколько секунд — рывок в одну сторону: стоящего на мосту сбивает с шага.
## Всё по общему времени — у всех одинаково; толчок каждый получает на своём компьютере.
const JERK_PERIOD := 4.6
const JERK_TIME := 0.8

func physics_tick() -> void:
	if _swings.is_empty():
		return
	var t: float = Network.game_time if Network.in_game else Time.get_ticks_msec() / 1000.0
	var me = Network.local_player
	for sw in _swings:
		var body: AnimatableBody3D = sw[0]
		var mid: Vector3 = sw[1]
		var axis: Vector3 = sw[2]
		var ph: float = sw[3]
		var amp: float = sw[4]
		var tj := t + ph * 1.7
		var cyc := int(floor(tj / JERK_PERIOD))
		var tau := tj - cyc * JERK_PERIOD
		var sgn := 1.0 if cyc % 2 == 0 else -1.0
		var jerk := 0.0
		if tau < JERK_TIME:
			jerk = 0.24 * sgn * sin(PI * tau / JERK_TIME)
		elif tau > JERK_PERIOD - 0.9:
			# перед рывком мост скрипит и подаётся в другую сторону — успей присесть
			var w := (tau - (JERK_PERIOD - 0.9)) / 0.9
			jerk = -0.07 * (-sgn) * sin(PI * w)
		var roll := amp * sin(t * 1.35 + ph) + amp * 0.4 * sin(t * 3.1 + ph * 2.0) + jerk
		var bob := 0.12 * sin(t * 2.2 + ph)
		body.global_transform = Transform3D(Basis(axis, roll), mid + Vector3(0, bob, 0))
		# рывок: стоящего на мосту толкает вбок
		var last: int = sw[5]
		if tau < JERK_TIME and cyc != last and not calm:
			sw[5] = cyc
			if me and is_instance_valid(me) and not me.is_dead and me.is_on_floor():
				var l: Vector3 = body.to_local(me.global_position)
				var half_span: float = sw[6]
				if absf(l.dot(Vector3(axis.x, 0.0, axis.z).normalized())) < half_span - 1.0 and l.y > -3.5 and l.y < 2.0:
					var side := Vector3(-axis.z, 0.0, axis.x).normalized()
					# присел (Ctrl) — почти не сдвигает
					me.wind_shove(side * sgn, 0.8 if me.sitting else 2.6)
					me.add_shake(0.25)


# ---------------------------------------------------------------------------
#  Тоннель сквозь толщу льда
# ---------------------------------------------------------------------------

## Пересечение луча из c по dir с замкнутой ломаной (локальные 2D координаты)
static func _ray_hit(poly: Array[Vector2], c: Vector2, dir: Vector2) -> Vector2:
	var best := 1e9
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var e := b - a
		var den := dir.x * e.y - dir.y * e.x
		if absf(den) < 1e-6:
			continue
		var w := a - c
		var t := (w.x * e.y - w.y * e.x) / den
		var u := (w.x * dir.y - w.y * dir.x) / den
		if t > 0.0 and u >= 0.0 and u <= 1.0 and t < best:
			best = t
	return c + dir * (best if best < 1e8 else 0.0)


func _tunnel(road: String, path: Array, k0: int, k1: int, root: Node3D) -> void:
	var hw := _hw(road)
	var bw := hw + 1.3
	var wh := 3.4
	var prof: Array[Vector2] = [Vector2(-hw + 0.2, -0.05), Vector2(-bw, -0.05), Vector2(-bw, wh)]
	for j in range(1, 12):
		var a := PI - PI * j / 12.0
		prof.append(Vector2(cos(a) * bw, wh + sin(a) * bw))
	prof.append(Vector2(bw, wh))
	prof.append(Vector2(bw, -0.05))
	prof.append(Vector2(hw - 0.2, -0.05))
	var ks: Array[int] = []
	for k in range(k0, k1 + 1, 2):
		ks.append(k)
	if ks[-1] != k1:
		ks.append(k1)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var top_v := PackedVector3Array()
	var top_n := PackedVector3Array()
	var rings: Array = []
	for k in ks:
		var p: Vector3 = path[k]
		var s := _side(path, k)
		var ring: Array[Vector3] = []
		for q in prof:
			ring.append(p + s * q.x + Vector3.UP * q.y)
		rings.append(ring)
	for i in ks.size() - 1:
		var r0: Array[Vector3] = rings[i]
		var r1: Array[Vector3] = rings[i + 1]
		var axis: Vector3 = (path[ks[i]] + path[ks[i + 1]]) * 0.5 + Vector3.UP * wh * 0.7
		for j in prof.size() - 1:
			var qc := (r0[j] + r0[j + 1] + r1[j] + r1[j + 1]) * 0.25
			cv._quad(v, n, r0[j], r0[j + 1], r1[j + 1], r1[j], (axis - qc).normalized())
		# снег плато сверху над тоннелем
		var pa: Vector3 = path[ks[i]]
		var pb: Vector3 = path[ks[i + 1]]
		var sa := _side(path, ks[i])
		var sb := _side(path, ks[i + 1])
		var ya := L.PLATEAU + 0.6
		cv._quad(top_v, top_n, Vector3(pa.x, ya, pa.z) - sa * 29.0, Vector3(pa.x, ya, pa.z) + sa * 29.0,
			Vector3(pb.x, ya, pb.z) + sb * 29.0, Vector3(pb.x, ya, pb.z) - sb * 29.0, Vector3.UP)
	# порталы: кольцо между аркой и толщей льда (трапеция ущелья)
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	for e in [k0, k1]:
		var p: Vector3 = path[e]
		var s := _side(path, e)
		var f := _fwd(path, e) * (-1.0 if e == k0 else 1.0)
		var mass: Array[Vector2] = [Vector2(-18.0, -62.0 - p.y), Vector2(18.0, -62.0 - p.y),
			Vector2(29.0, L.PLATEAU + 0.6 - p.y), Vector2(-29.0, L.PLATEAU + 0.6 - p.y)]
		var c := Vector2(0.0, wh * 0.5)
		var N := 56
		var K := 6
		var prev: Array[Vector3] = []
		for i in N + 1:
			var a := TAU * i / N
			var d := Vector2(cos(a), sin(a))
			var hb := _ray_hit(prof, c, d)
			var hm := _ray_hit(mass, c, d)
			# стенка вокруг входа не плоская: от края арки до краёв ущелья — бугры и наплывы льда
			var col: Array[Vector3] = []
			for j in K + 1:
				var t := float(j) / K
				var q2 := hb.lerp(hm, t)
				var w := p + s * q2.x + Vector3.UP * q2.y
				var amp := pow(sin(PI * t), 0.6)
				var off := amp * (_bump(w) * 1.25 + 1.1 * sin(w.y * 0.43 + w.x * 0.31 + w.z * 0.27) * sin(t * 9.0 + w.y * 0.2))
				col.append(w + f * maxf(off, 0.0))
				if i % 4 == 1 and j > 0 and j < K and j % 2 == 1 and (absf(q2.x) > bw + 2.5 or q2.y > wh + bw + 2.0) and q2.y > -40.0:
					cv.face_spots.append([col[j], f])
			if i > 0:
				for j in K:
					cv._quad(pv, pn, prev[j], col[j], col[j + 1], prev[j + 1], f)
			prev = col
		# козырёк из сосулек над входом
		for j in 9:
			var q: Vector2 = prof[2 + j]
			var tip := p + s * q.x * 1.08 + Vector3.UP * (q.y + 0.5) + f * 0.05
			beam(tip, tip + Vector3(0, -rng.randf_range(0.9, 1.9), 0), 0.16, "floe", 5, 0.0)
	var inner: MeshInstance3D = cv._add_mesh("Bore", v, n, mat("bore"), true, root)
	inner.visibility_range_end = 200.0
	cv._add_mesh("Roof", top_v, top_n, cv._snow_mat, true, root)
	cv._add_mesh("Portals", pv, pn, cv._cliff_mat, true, root)
	var body := StaticBody3D.new()
	body.name = "BoreWalls"
	root.add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(v)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	# лампы под сводом
	var acc := 0.0
	var next := 6.0
	for k in range(k0 + 1, k1 + 1):
		acc += (path[k] as Vector3).distance_to(path[k - 1])
		if acc < next:
			continue
		next += 14.0
		var lp: Vector3 = path[k] + Vector3.UP * (wh + bw - 0.6)
		beam(lp + Vector3.UP * 0.6, lp, 0.03, "iron", 4)
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sm.radial_segments = 8
		sm.rings = 4
		put(sm, Transform3D(Basis(), lp - Vector3.UP * 0.1), "lamp")
		var l := OmniLight3D.new()
		l.light_color = Color(0.6, 0.85, 1.0)
		l.light_energy = 1.6
		l.omni_range = 13.0
		l.position = lp - Vector3.UP * 0.5
		l.distance_fade_enabled = true
		l.distance_fade_begin = 70.0
		l.distance_fade_length = 20.0
		root.add_child(l)


## Выпуклость наплыва (0…3 м) — по месту, у всех одинаково
static func _bump(p: Vector3) -> float:
	return 1.5 + 1.0 * sin(p.x * 0.21 + p.y * 0.17) * cos(p.z * 0.19 - p.y * 0.13) + 0.5 * sin(p.y * 0.5 + p.x * 0.3)


# ---------------------------------------------------------------------------
#  Подвесной мост
# ---------------------------------------------------------------------------

func _rope(road: String, path: Array, k0: int, k1: int, root: Node3D) -> void:
	var a: Vector3 = path[k0]
	var b: Vector3 = path[k1]
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var span := flat.length()
	var f := flat / span
	var s := Vector3(-f.z, 0.0, f.x)
	var sag := clampf(span * 0.05, 1.0, 2.6)
	var dw := 3.0
	var mid := (a + b) * 0.5
	var deck := AnimatableBody3D.new()
	deck.name = "RopeDeck"
	deck.sync_to_physics = true
	deck.add_to_group("safe_ground")
	deck.add_to_group("canyon_road")
	root.add_child(deck)
	deck.global_position = mid
	# локальная точка настила (t от 0 до 1)
	var deck_pt := func(t: float, lat: float) -> Vector3:
		var p := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0) + s * lat
		return p - mid
	var dst := SurfaceTool.new()
	dst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var planks := int(span / 0.5)
	for i in planks:
		var t := (i + 0.5) / planks
		var p: Vector3 = deck_pt.call(t, rng.randf_range(-0.06, 0.06))
		var nx: Vector3 = deck_pt.call(minf(t + 0.01, 1.0), 0.0) - deck_pt.call(maxf(t - 0.01, 0.0), 0.0)
		var pitch := atan2(nx.y, Vector2(nx.x, nx.z).length())
		var bm := BoxMesh.new()
		bm.size = Vector3(dw * rng.randf_range(0.92, 1.0), 0.1, 0.42)
		var bs := Basis(Vector3.UP, atan2(f.x, f.z) + rng.randf_range(-0.04, 0.04)) * Basis(Vector3.RIGHT, -pitch)
		dst.append_from(bm, 0, Transform3D(bs, p + Vector3(0, -0.05, 0)))
	var dmi := MeshInstance3D.new()
	dmi.mesh = dst.commit()
	dmi.material_override = mat("wood")
	deck.add_child(dmi)
	# канаты: поручни, подвесы, нижние тросы — тоже на качающемся настиле
	var rst := SurfaceTool.new()
	rst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sgn in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		var prev_low := Vector3.ZERO
		var n := 24
		for i in n + 1:
			var t := float(i) / n
			var low: Vector3 = deck_pt.call(t, sgn * dw * 0.5)
			var top := low + Vector3(0, 1.1 + sag * 0.6 * (1.0 - 4.0 * t * (1.0 - t)), 0)
			if i > 0:
				_rope_seg(rst, prev, top, 0.045)
				_rope_seg(rst, prev_low, low, 0.035)
			if i % 2 == 0:
				_rope_seg(rst, low, top, 0.025)
			prev = top
			prev_low = low
	var rmi := MeshInstance3D.new()
	rmi.mesh = rst.commit()
	rmi.material_override = mat("rope")
	deck.add_child(rmi)
	# столкновения: только настил — канаты не держат, сбросит рывком — упадёшь
	var fv := PackedVector3Array()
	var n2 := 20
	for i in n2:
		var t0 := float(i) / n2
		var t1 := float(i + 1) / n2
		var p00: Vector3 = deck_pt.call(t0, -dw * 0.5)
		var p01: Vector3 = deck_pt.call(t0, dw * 0.5)
		var p10: Vector3 = deck_pt.call(t1, -dw * 0.5)
		var p11: Vector3 = deck_pt.call(t1, dw * 0.5)
		fv.append_array(PackedVector3Array([p00, p01, p11, p00, p11, p10]))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(fv)
	var col := CollisionShape3D.new()
	col.shape = shape
	deck.add_child(col)
	_swings.append([deck, mid, (b - a).normalized(), rng.randf() * TAU, 0.11, -1, span * 0.5])
	# опоры у концов: столбы с перекладиной и растяжками в стены
	for e in [a, b]:
		for sgn in [-1.0, 1.0]:
			var pp: Vector3 = e + s * sgn * (dw * 0.5 + 0.35)
			box(Vector3(0.35, 3.0, 0.35), Transform3D(Basis(Vector3.UP, atan2(f.x, f.z)), pp + Vector3(0, 1.5, 0)), "wood_dark")
			beam(pp + Vector3(0, 2.6, 0), pp + Vector3(0, -1.0, 0) + s * sgn * 3.0 + (f if e == a else -f) * -2.0, 0.04, "rope", 4)
		beam(e - s * (dw * 0.5 + 0.35) + Vector3(0, 2.9, 0), e + s * (dw * 0.5 + 0.35) + Vector3(0, 2.9, 0), 0.14, "wood_dark", 6)
	for e in [a, b]:
		var lb := Label3D.new()
		lb.text = "Мост дёргает!\nCtrl — присесть и переждать"
		lb.font_size = 34
		lb.outline_size = 10
		lb.modulate = Color(1.0, 0.8, 0.45)
		lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lb.position = e + Vector3(0, 3.6, 0)
		lb.visibility_range_end = 40.0
		root.add_child(lb)
	var tw := StaticBody3D.new()
	root.add_child(tw)
	for e in [a, b]:
		for sgn in [-1.0, 1.0]:
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.35, 3.0, 0.35)
			var c2 := CollisionShape3D.new()
			c2.shape = bs
			c2.position = e + s * sgn * (dw * 0.5 + 0.35) + Vector3(0, 1.5, 0)
			c2.rotation.y = atan2(f.x, f.z)
			tw.add_child(c2)
	# дорога у концов сужается к мосту — по бокам настила у опор пропасть,
	# поэтому у концов ставим короткие бортики
	for e in [a, b]:
		var into := (f if e == a else -f)
		for sgn in [-1.0, 1.0]:
			var bs2 := BoxShape3D.new()
			bs2.size = Vector3(0.2, 1.0, 1.2)
			var c3 := CollisionShape3D.new()
			c3.shape = bs2
			c3.position = e + s * sgn * (dw * 0.5 + 0.35) + into * 0.6 + Vector3(0, 0.5, 0)
			c3.rotation.y = atan2(f.x, f.z)
			tw.add_child(c3)


func _rope_seg(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = d.length()
	m.radial_segments = 4
	m.rings = 1
	st.append_from(m, 0, Transform3D(basis_y(d), (a + b) * 0.5))


# ---------------------------------------------------------------------------
#  Льдины-столбы: прыгать с одной на другую
# ---------------------------------------------------------------------------

func _floes(road: String, path: Array, k0: int, k1: int, root: Node3D) -> void:
	var acc: Array[float] = [0.0]
	for k in range(k0 + 1, k1 + 1):
		acc.append(acc[-1] + (path[k] as Vector3).distance_to(path[k - 1]))
	var total: float = acc[-1]
	var at := func(d: float) -> Vector3:
		var j := 1
		while j < acc.size() - 1 and acc[j] < d:
			j += 1
		var t := clampf((d - acc[j - 1]) / maxf(acc[j] - acc[j - 1], 0.001), 0.0, 1.0)
		return (path[k0 + j - 1] as Vector3).lerp(path[k0 + j], t)
	# раскладка: радиусы и промежутки
	var items: Array = []
	var pos := 0.0
	var gap := rng.randf_range(1.2, 1.7)
	while true:
		var r := rng.randf_range(1.45, 2.0)
		var c := pos + gap + r
		if c + r + 1.3 > total:
			break
		items.append([c, r])
		pos = c + r
		gap = rng.randf_range(1.2, 1.8)
	var rem := total - pos
	if items.size() > 0 and rem > 1.6:
		var extra := (rem - 1.5) / (items.size() + 1)
		for i in items.size():
			items[i][0] += extra * (i + 1)
	var body := StaticBody3D.new()
	body.name = "Floes"
	body.add_to_group("safe_ground")
	body.add_to_group("canyon_road")
	body.physics_material_override = PhysicsMaterial.new()
	root.add_child(body)
	var tops: Array[Vector3] = []
	for i in items.size():
		var d: float = items[i][0]
		var r: float = items[i][1]
		var p: Vector3 = at.call(d)
		var s := _side(path, k0 + 1)
		var fk: Vector3 = at.call(minf(d + 1.0, total)) - at.call(maxf(d - 1.0, 0.0))
		fk.y = 0.0
		if fk.length() > 0.01:
			s = Vector3(-fk.z, 0.0, fk.x).normalized()
		var lat := (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(0.4, 1.3)
		var top := p + s * lat + Vector3(0, rng.randf_range(-0.2, 0.5), 0)
		tops.append(top)
		var h := top.y - L.ABYSS_Y + 6.0
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r * 0.5
		cm.height = h
		cm.radial_segments = 7
		cm.rings = 1
		var tilt := Basis(Vector3.UP, rng.randf() * TAU)
		put(cm, Transform3D(tilt, top - Vector3(0, h * 0.5 + 0.18, 0)), "floe")
		var cap := CylinderMesh.new()
		cap.top_radius = r - 0.08
		cap.bottom_radius = r + 0.04
		cap.height = 0.36
		cap.radial_segments = 7
		cap.rings = 1
		put(cap, Transform3D(tilt, top - Vector3(0, 0.18, 0)), "snow")
		# сосульки под краем
		for j in 3:
			var aa := rng.randf() * TAU
			var ip := top + Vector3(cos(aa) * r * 0.9, -0.5, sin(aa) * r * 0.9)
			beam(ip, ip + Vector3(0, -rng.randf_range(0.6, 1.5), 0), 0.14, "floe", 5, 0.0)
		# столб твёрдый целиком — сорвавшийся не пролетает сквозь него
		var cs := CylinderMesh.new()
		cs.top_radius = r
		cs.bottom_radius = r * 0.5
		cs.height = h
		cs.radial_segments = 7
		cs.rings = 1
		var col := CollisionShape3D.new()
		col.shape = cs.create_convex_shape()
		col.transform = Transform3D(tilt, top - Vector3(0, h * 0.5, 0))
		body.add_child(col)
	# путь по льдинам — для расстановки и проверок
	var np: Array = []
	for k in range(0, k0 + 1):
		np.append(path[k])
	np.append_array(tops)
	for k in range(k1, path.size()):
		np.append(path[k])
	cv.road_paths[road] = np
	var fs: Dictionary = cv.form_sections[road]
	fs["k1"] = k0 + tops.size() + 1


# ---------------------------------------------------------------------------
#  Карниз: стена вплотную; сверху — ледяные козырьки с сосульками
# ---------------------------------------------------------------------------

func _wall_dist(p: Vector3, dir: Vector3, y: float) -> float:
	var t: Node = cv.get("_terrain")
	for i in 60:
		var dd := 2.0 + i * 0.5
		var q := p + dir * dd
		var h: float = t.height_at(q.x, q.z) if t else L.wall_height(q.x, q.z)
		if h >= y:
			return dd
	return 30.0


func _ledge(road: String, path: Array, side: int, root: Node3D) -> void:
	var hw := _hw(road)
	var acc := 0.0
	var next := 10.0
	for k in range(1, path.size() - 1):
		acc += (path[k] as Vector3).distance_to(path[k - 1])
		if acc < next:
			continue
		next += rng.randf_range(16.0, 24.0)
		var p: Vector3 = path[k]
		if _near_trap(p, 7.0) or acc > _len(path) - 10.0:
			continue
		var n := _side(path, k) * float(side)
		var f := _fwd(path, k)
		var y := p.y + rng.randf_range(5.0, 6.5)
		var wd := _wall_dist(p, n, y)
		if wd > hw + 6.0:
			continue
		var out := rng.randf_range(3.2, 4.4)
		var ln := rng.randf_range(6.0, 10.0)
		var c := p + n * (wd - out * 0.5 + 0.8) + Vector3(0, y - p.y, 0)
		var bs := Basis.looking_at(f, Vector3.UP) * Basis(Vector3.FORWARD, -float(side) * rng.randf_range(0.05, 0.15))
		box(Vector3(out + 1.6, rng.randf_range(0.9, 1.5), ln), Transform3D(bs, c), "floe")
		box(Vector3(out + 1.4, 0.25, ln - 0.3), Transform3D(bs, c + Vector3(0, 0.7, 0)), "snow")
		for j in 6:
			var ip := c - n * (out * 0.5 - rng.randf_range(0.2, 0.9)) + f * rng.randf_range(-ln * 0.45, ln * 0.45) + Vector3(0, -0.25, 0)
			beam(ip, ip + Vector3(0, -rng.randf_range(0.5, 1.8), 0), rng.randf_range(0.08, 0.16), "floe", 5, 0.0)


func _len(path: Array) -> float:
	var t := 0.0
	for k in range(1, path.size()):
		t += (path[k] as Vector3).distance_to(path[k - 1])
	return t


# ---------------------------------------------------------------------------
#  Мостки на сваях вдоль стены
# ---------------------------------------------------------------------------

func _stilts(road: String, path: Array, side: int, root: Node3D) -> void:
	var hw := _hw(road)
	var acc := 0.0
	var next := 3.0
	var rails := StaticBody3D.new()
	rails.name = "Rails"
	root.add_child(rails)
	var prev_post := Vector3.INF
	for k in range(1, path.size() - 1):
		acc += (path[k] as Vector3).distance_to(path[k - 1])
		if acc < next:
			continue
		next += 3.2
		var p: Vector3 = path[k]
		var sd := _side(path, k)
		for sgn in [-1.0, 1.0]:
			var pp: Vector3 = p + sd * sgn * (hw - 0.3)
			beam(pp + Vector3(0, -0.7, 0), pp + Vector3(0, -22.0, 0), 0.17, "wood_dark", 6)
		# раскос между сваями
		beam(p + sd * (hw - 0.3) + Vector3(0, -1.2, 0), p - sd * (hw - 0.3) + Vector3(0, -6.0, 0), 0.08, "wood_dark", 4)
		# перила с внешней стороны (стена — с другой)
		var op: Vector3 = p - sd * float(side) * (hw - 0.15)
		beam(op, op + Vector3(0, 1.1, 0), 0.06, "wood", 5)
		if prev_post != Vector3.INF and prev_post.distance_to(op) < 6.0:
			beam(prev_post + Vector3(0, 1.05, 0), op + Vector3(0, 1.05, 0), 0.05, "wood", 5)
			beam(prev_post + Vector3(0, 0.55, 0), op + Vector3(0, 0.55, 0), 0.035, "wood", 4)
			var bs := BoxShape3D.new()
			var d := op - prev_post
			bs.size = Vector3(0.15, 1.1, d.length())
			var col := CollisionShape3D.new()
			col.shape = bs
			col.position = (op + prev_post) * 0.5 + Vector3(0, 0.55, 0)
			col.rotation.y = atan2(d.x, d.z)
			rails.add_child(col)
		prev_post = op


# ---------------------------------------------------------------------------
#  Спираль вокруг ледяного столба: тонкая полка на кронштейнах
# ---------------------------------------------------------------------------

func _spiral(road: String, path: Array, root: Node3D) -> void:
	var c2: Vector2 = L.SPIRAL_COLUMN[0]
	var cr: float = L.SPIRAL_COLUMN[1]
	var top_y: float = (path[0] as Vector3).y + 7.0
	var c := Vector3(c2.x, 0.0, c2.y)
	# сам столб: гранёный, книзу шире, с наплывами
	var h := top_y - L.ABYSS_Y + 8.0
	var cm := CylinderMesh.new()
	cm.top_radius = cr * 0.85
	cm.bottom_radius = cr * 1.35
	cm.height = h
	cm.radial_segments = 9
	cm.rings = 6
	put(cm, Transform3D(Basis(Vector3.UP, 0.3), c + Vector3(0, top_y - h * 0.5, 0)), "floe")
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
		var y := rng.randf_range(L.ABYSS_Y + 10.0, top_y - 4.0)
		var bp := c + Vector3(cos(a), 0.0, sin(a)) * cr * 0.9 + Vector3(0, y, 0)
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(1.4, 2.4)
		sm.height = sm.radius * 2.6
		sm.radial_segments = 8
		sm.rings = 5
		put(sm, Transform3D(Basis(), bp), "floe")
	var cap := CylinderMesh.new()
	cap.top_radius = cr * 0.75
	cap.bottom_radius = cr * 0.88
	cap.height = 0.6
	cap.radial_segments = 9
	put(cap, Transform3D(Basis(Vector3.UP, 0.3), c + Vector3(0, top_y + 0.3, 0)), "snow")
	var body := StaticBody3D.new()
	body.name = "Column"
	root.add_child(body)
	var col := CollisionShape3D.new()
	col.shape = cm.create_convex_shape()
	col.transform = Transform3D(Basis(), c + Vector3(0, top_y - h * 0.5, 0))
	body.add_child(col)
	# кронштейны под полкой: из столба к внешнему краю, и сосульки
	var hw := _hw(road)
	for k in range(2, path.size() - 1, 4):
		var p: Vector3 = path[k]
		var out := Vector3(p.x - c.x, 0.0, p.z - c.z).normalized()
		var inner := c + out * cr * 0.9 + Vector3(0, p.y - 3.5, 0)
		var outer := p + out * (hw - 0.4) + Vector3(0, -1.0, 0)
		beam(inner, outer, 0.22, "iron", 6)
		beam(c + out * cr * 0.9 + Vector3(0, p.y - 1.0, 0), p - out * (hw - 0.3) + Vector3(0, -1.0, 0), 0.18, "iron", 6)
		beam(outer, outer + Vector3(0, -rng.randf_range(0.8, 2.0), 0), 0.14, "floe", 5, 0.0)
	# перильца с внешней стороны спирали (низкие, из льда) — визуально
	var prev := Vector3.INF
	for k in range(0, path.size(), 3):
		var p2: Vector3 = path[k]
		var out2 := Vector3(p2.x - c.x, 0.0, p2.z - c.z).normalized()
		var q := p2 + out2 * (hw - 0.2)
		beam(q, q + Vector3(0, 0.6, 0), 0.07, "floe", 5)
		if prev != Vector3.INF:
			beam(prev + Vector3(0, 0.6, 0), q + Vector3(0, 0.6, 0), 0.06, "floe", 5)
		prev = q


# ---------------------------------------------------------------------------
#  Природная ледяная арка: сосульки под сводом
# ---------------------------------------------------------------------------

func _arch(road: String, path: Array, k0: int, k1: int, root: Node3D) -> void:
	var hw := _hw(road)
	var acc := 0.0
	var span := 0.0
	for k in range(k0 + 1, k1 + 1):
		span += (path[k] as Vector3).distance_to(path[k - 1])
	for k in range(k0 + 1, k1):
		acc += (path[k] as Vector3).distance_to(path[k - 1])
		var u := acc / maxf(span, 1.0)
		if k % 3 != 0 or u < 0.15 or u > 0.85:
			continue
		var p: Vector3 = path[k]
		var under: float = p.y - 1.1 - span * 0.42 * pow(1.0 - sin(PI * u), 1.6)
		var sd := _side(path, k)
		for j in 3:
			var ip := p + sd * rng.randf_range(-hw * 0.8, hw * 0.8) + Vector3(0, under - p.y + 0.35, 0)
			beam(ip, ip + Vector3(0, -rng.randf_range(0.8, 3.2), 0), rng.randf_range(0.15, 0.3), "floe", 5, 0.0)


# ---------------------------------------------------------------------------
#  Узкий гребень: ледяные зубцы по бокам
# ---------------------------------------------------------------------------

func _ridge(road: String, path: Array, root: Node3D) -> void:
	var hw := _hw(road)
	for k in range(2, path.size() - 2, 3):
		var p: Vector3 = path[k]
		var sd := _side(path, k)
		for sgn in [-1.0, 1.0]:
			if rng.randf() < 0.4:
				continue
			# зубец растёт из самого клина гребня (основание — внутри бока), а не висит рядом в воздухе
			var depth := rng.randf_range(1.0, 3.0)
			var base: Vector3 = p + sd * sgn * (hw + depth * 0.32 - 0.35) + Vector3(0, -depth, 0)
			var dir: Vector3 = (sd * sgn * 0.5 + Vector3(0, 1.0, 0)).normalized()
			beam(base, base + dir * rng.randf_range(1.5, 3.2), rng.randf_range(0.25, 0.45), "floe", 6, 0.0)
