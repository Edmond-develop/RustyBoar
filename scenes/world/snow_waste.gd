extends Node3D
## Снежная пустошь (шаг 50): огромное заснеженное поле между Ледяным каньоном и Лавинным склоном.
##
##  * Тропа отмечена вешками (полосатые столбики с фонариком и флажком): сначала прямо на север,
##    потом повороты. На поворотах — тур из камней и указатель со стрелкой.
##    В самой густой метели вешки соединены леером — за него можно держаться.
##  * Метель (waste_storm.gd) крепчает к середине: видно на пару вешек вперёд, ветер сносит,
##    порывы уносят назад и вбок. Спасает: присесть, держаться за вешку/леер, укрыться за скалой,
##    держаться вместе (рядом с другом или в связке верёвкой).
##  * Вне тропы под снегом — трещины (crevasse_lid.gd): шагнул на пласт — провалился.
##  * У тропы — скалы-укрытия; посередине — брошенный лагерь экспедиции (контрольная точка,
##    жаровня, вездеход, радиомачта с огнём, стена из снежных блоков); ближе к концу — метеобудка.
##  * Вокруг — ледяные монолиты, валуны, следы прошлой экспедиции (нарты, бочки, замёрзший дрон…).
## План (тропа, трещины, укрытия, лагерь) — в waste_layout.gd, одинаковый у всех игроков.

const W := preload("res://scenes/world/waste_layout.gd")
const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const ROCKS := preload("res://scenes/world/canyon_rocks.gd")
const LID := preload("res://scenes/world/crevasse_lid.gd")
const CHECKPOINT := preload("res://scenes/world/checkpoint.gd")
const HEATER := preload("res://scenes/world/heat_source.gd")
const STORM := preload("res://scenes/world/waste_storm.gd")
const FALSE_LIGHTS := preload("res://scenes/world/false_lights.gd")
const CABIN := preload("res://scenes/world/camp_cabin.gd")
const BAND := 160.0                ## куски по z (для отсечения дальнего)

var poles := PackedVector3Array()  ## основания вешек
var ropes: Array = []              ## леер: [a, b] (точки на высоте рук)
var storm: Node
var lids: Array = []
var camp_pos := Vector3.ZERO
var cabin: Node3D                  ## camp_cabin.gd — избушка и двор
var hut_pos := Vector3.ZERO

var _ter: Node
var _rng := RandomNumberGenerator.new()
var _st := {}                      ## ключ куска → SurfaceTool
var _mats := {}
var _solids: StaticBody3D
var _shelter_body: StaticBody3D
var _rock_meshes: Array = []
var _blinks: Array = []            ## [материал, фаза]
var _spinners: Array = []          ## [узел, скорость]
var _t := 0.0


func _ready() -> void:
	_ter = get_tree().get_first_node_in_group("terrain")
	_rng.seed = 50050
	_solids = StaticBody3D.new()
	_solids.name = "WasteSolids"
	add_child(_solids)
	_shelter_body = StaticBody3D.new()
	_shelter_body.name = "WindShelters"
	_shelter_body.add_to_group("wind_shelter")
	add_child(_shelter_body)
	var rk = ROCKS.new(self)
	rk._make_meshes()
	_rock_meshes = rk._meshes
	_poles()
	_turn_marks()
	_shelters()
	_cracks()
	_warm_points()
	_camp()
	_hut()
	_monoliths()
	_boulders()
	_rime_trees()
	_ribcage()
	_relics()
	_flush()
	storm = Node3D.new()
	storm.set_script(STORM)
	storm.name = "Storm"
	storm.set("waste", self)
	add_child(storm)
	var fl := Node3D.new()
	fl.set_script(FALSE_LIGHTS)
	fl.name = "FalseLights"
	fl.set("storm", storm)
	add_child(fl)


func _process(delta: float) -> void:
	_t += delta
	for b in _blinks:
		var m: StandardMaterial3D = b[0]
		m.emission_energy_multiplier = 0.4 + 5.0 * maxf(sin(_t * 2.4 + float(b[1])), 0.0)
	for sp in _spinners:
		(sp[0] as Node3D).rotate_y(delta * float(sp[1]))


func ground(x: float, z: float) -> float:
	return _ter.height_at(x, z) if _ter else W.base_y(z)


# ---------------------------------------------------------------------------
#  Сборка мешей: всё одного материала в куске BAND м — один меш
# ---------------------------------------------------------------------------

func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"ice", "ice_dark":
			var sm := ShaderMaterial.new()
			sm.shader = ICE_SHADER
			var dark := key == "ice_dark"
			sm.set_shader_parameter("deep", Color(0.02, 0.12, 0.26) if dark else Color(0.06, 0.24, 0.42))
			sm.set_shader_parameter("mid", Color(0.14, 0.42, 0.66) if dark else Color(0.3, 0.6, 0.82))
			sm.set_shader_parameter("edge", Color(0.6, 0.85, 1.0))
			sm.set_shader_parameter("snow_amount", 0.9)
			sm.set_shader_parameter("crack_amount", 0.8)
			sm.set_shader_parameter("band_scale", 0.6)
			m = sm
		"snowblock":
			var sb := ShaderMaterial.new()
			sb.shader = ICE_SHADER
			sb.set_shader_parameter("deep", Color(0.55, 0.64, 0.76))
			sb.set_shader_parameter("mid", Color(0.82, 0.88, 0.94))
			sb.set_shader_parameter("edge", Color(0.96, 0.98, 1.0))
			sb.set_shader_parameter("snow_amount", 2.0)
			sb.set_shader_parameter("base_rough", 0.8)
			sb.set_shader_parameter("band_scale", 2.5)
			m = sb
		"rock":
			m = _ter.get("terrain_material") if _ter else null
			if m == null:
				var r := StandardMaterial3D.new()
				r.albedo_color = Color(0.45, 0.5, 0.58)
				m = r
		_:
			var s := StandardMaterial3D.new()
			var spec: Array = {
				"pole_red": [Color(0.85, 0.12, 0.1), 0.5, 0.1, Color(0, 0, 0), 0.0],
				"pole_white": [Color(0.92, 0.92, 0.9), 0.5, 0.1, Color(0, 0, 0), 0.0],
				"lamp": [Color(1.0, 0.6, 0.2), 0.3, 0.0, Color(1.0, 0.5, 0.12), 3.2],
				"flag": [Color(1.0, 0.42, 0.05), 0.8, 0.0, Color(0.35, 0.12, 0.0), 0.4],
				"rope": [Color(0.95, 0.75, 0.15), 0.8, 0.0, Color(0.25, 0.18, 0.0), 0.5],
				"wood": [Color(0.42, 0.28, 0.16), 0.85, 0.0, Color(0, 0, 0), 0.0],
				"wood_dark": [Color(0.25, 0.17, 0.1), 0.9, 0.0, Color(0, 0, 0), 0.0],
				"sign": [Color(0.98, 0.78, 0.1), 0.6, 0.0, Color(0.4, 0.3, 0.0), 0.5],
				"canvas_o": [Color(0.92, 0.38, 0.1), 0.85, 0.0, Color(0, 0, 0), 0.0],
				"canvas_b": [Color(0.15, 0.32, 0.6), 0.85, 0.0, Color(0, 0, 0), 0.0],
				"metal": [Color(0.35, 0.37, 0.4), 0.45, 0.7, Color(0, 0, 0), 0.0],
				"rust": [Color(0.45, 0.24, 0.13), 0.8, 0.4, Color(0, 0, 0), 0.0],
				"yellow": [Color(0.9, 0.68, 0.1), 0.6, 0.3, Color(0, 0, 0), 0.0],
				"dark": [Color(0.08, 0.08, 0.09), 0.7, 0.3, Color(0, 0, 0), 0.0],
				"window": [Color(1.0, 0.8, 0.45), 0.3, 0.0, Color(1.0, 0.7, 0.35), 2.2],
				"crate": [Color(0.36, 0.42, 0.3), 0.8, 0.1, Color(0, 0, 0), 0.0],
				"logs": [Color(0.4, 0.27, 0.15), 0.9, 0.0, Color(0, 0, 0), 0.0],
				"planks": [Color(0.55, 0.38, 0.22), 0.8, 0.0, Color(0, 0, 0), 0.0],
				"stone": [Color(0.42, 0.41, 0.4), 0.9, 0.0, Color(0, 0, 0), 0.0],
				"soot": [Color(0.06, 0.05, 0.05), 1.0, 0.0, Color(0, 0, 0), 0.0],
				"rug_red": [Color(0.55, 0.1, 0.08), 1.0, 0.0, Color(0, 0, 0), 0.0],
				"rug_gold": [Color(0.85, 0.62, 0.2), 1.0, 0.0, Color(0, 0, 0), 0.0],
				"rug_blue": [Color(0.15, 0.25, 0.5), 1.0, 0.0, Color(0, 0, 0), 0.0],
				"blanket": [Color(0.3, 0.42, 0.25), 1.0, 0.0, Color(0, 0, 0), 0.0],
				"pillow": [Color(0.88, 0.85, 0.78), 1.0, 0.0, Color(0, 0, 0), 0.0],
				"jar_r": [Color(0.7, 0.2, 0.15), 0.3, 0.0, Color(0, 0, 0), 0.0],
				"jar_y": [Color(0.85, 0.7, 0.25), 0.3, 0.0, Color(0, 0, 0), 0.0],
				"iron": [Color(0.15, 0.15, 0.16), 0.45, 0.7, Color(0, 0, 0), 0.0],
				"candle": [Color(1.0, 0.95, 0.85), 0.5, 0.0, Color(1.0, 0.7, 0.3), 1.5],
				"barrel": [Color(0.18, 0.32, 0.55), 0.6, 0.5, Color(0, 0, 0), 0.0],
				"bone": [Color(0.85, 0.83, 0.76), 0.7, 0.0, Color(0, 0, 0), 0.0],
				"drone": [Color(0.75, 0.48, 0.12), 0.5, 0.5, Color(0, 0, 0), 0.0],
			}.get(key, [Color(0.6, 0.6, 0.6), 0.7, 0.0, Color(0, 0, 0), 0.0])
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


func put(mesh: Mesh, xf: Transform3D, key: String) -> void:
	var band := int(floor((W.S_Z - xf.origin.z) / BAND))
	var k := "%s#%d" % [key, band]
	if not _st.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[k] = st
	(_st[k] as SurfaceTool).append_from(mesh, 0, xf)


func box(size: Vector3, pos: Vector3, b: Basis, key: String, solid := false) -> void:
	var m := BoxMesh.new()
	m.size = size
	put(m, Transform3D(b, pos), key)
	if solid:
		solid_box(pos, size, b)


func cyl(rt: float, rb: float, h: float, pos: Vector3, b: Basis, key: String, seg: int = 8) -> void:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	m.cap_top = rt > 0.0
	put(m, Transform3D(b, pos), key)


func sph(r: float, pos: Vector3, b: Basis, key: String, seg: int = 10) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(seg / 2, 4)
	put(m, Transform3D(b, pos), key)


func beam(a: Vector3, b: Vector3, r: float, key: String, seg: int = 6, r_end: float = -1.0) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	cyl(r if r_end < 0.0 else r_end, r, d.length(), (a + b) * 0.5, basis_y(d), key, seg)


static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func yaw_b(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw)


func solid_box(pos: Vector3, size: Vector3, b: Basis, body: StaticBody3D = null) -> void:
	var sh := BoxShape3D.new()
	sh.size = size
	var c := CollisionShape3D.new()
	c.shape = sh
	c.transform = Transform3D(b.orthonormalized(), pos)
	(body if body else _solids).add_child(c)


func solid_cyl(pos: Vector3, r: float, h: float, body: StaticBody3D = null) -> void:
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	var c := CollisionShape3D.new()
	c.shape = sh
	c.position = pos
	(body if body else _solids).add_child(c)


## Глыба: подробный меш + выпуклая коллизия по простому мешу
func rock(pos: Vector3, size: Vector3, yaw: float, key: String, body: StaticBody3D = null) -> void:
	var vi := _rng.randi_range(0, 1)
	var b := Basis(Vector3.UP, yaw)
	b = Basis(b.x * size.x, b.y * size.y, b.z * size.z)
	put(_rock_meshes[vi * 2], Transform3D(b, pos), key)
	var simple: ArrayMesh = _rock_meshes[vi * 2 + 1]
	var pts := PackedVector3Array()
	var arr := simple.surface_get_arrays(0)
	for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		pts.append(b * v)
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	var c := CollisionShape3D.new()
	c.shape = sh
	c.position = pos
	(body if body else _solids).add_child(c)


func _flush() -> void:
	for k: String in _st:
		var key := k.get_slice("#", 0)
		var mesh := (_st[k] as SurfaceTool).commit()
		var mi := MeshInstance3D.new()
		mi.name = "W_" + k.replace("#", "_")
		mi.mesh = mesh
		mi.material_override = mat(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_st.clear()


func _v3(p: Vector2, dy: float = 0.0) -> Vector3:
	return Vector3(p.x, ground(p.x, p.y) + dy, p.y)


# ---------------------------------------------------------------------------
#  Вешки и леер
# ---------------------------------------------------------------------------

func _poles() -> void:
	var total := W.length()
	var s := 6.0
	var i := 0
	var prev_rope := Vector3.INF
	var lights := 0
	while s < total - 2.0:
		var p := W.point_at(s)
		var sd := W.side_at(s)
		var core := W.storm(p.y) > 0.8
		# в самой густой метели — все вешки слева и между ними леер; иначе — через одну по сторонам
		var sgn := 1.0 if core or i % 2 == 0 else -1.0
		var q := p + sd * sgn * 3.0
		var base := _v3(q, -0.15)
		_pole(base, W.wind_dir(q.y))
		poles.append(base)
		if i % 4 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.25)
			l.light_energy = 1.3
			l.omni_range = 7.0
			l.distance_fade_enabled = true
			l.distance_fade_begin = 60.0
			l.distance_fade_length = 20.0
			l.shadow_enabled = false
			l.position = base + Vector3(0, 2.9, 0)
			add_child(l)
			lights += 1
		var hold := base + Vector3(0, 1.05, 0)
		if core and prev_rope != Vector3.INF and prev_rope.distance_to(hold) < W.POLE_STEP + 3.0:
			_rope(prev_rope, hold)
			ropes.append([prev_rope, hold])
		prev_rope = hold if core else Vector3.INF
		s += W.POLE_STEP
		i += 1


func _pole(base: Vector3, wd: Vector2) -> void:
	var h := 2.8
	var n := 7
	for k in n:
		var y0 := h * k / n
		cyl(0.055, 0.06, h / n, base + Vector3(0, y0 + h / n * 0.5, 0), Basis(), "pole_red" if k % 2 == 0 else "pole_white", 6)
	sph(0.11, base + Vector3(0, h + 0.08, 0), Basis(), "lamp", 8)
	# флажок по ветру
	var fd := Vector3(wd.x, 0.0, wd.y)
	var fb := Basis.looking_at(fd, Vector3.UP).rotated(Vector3.UP, PI * 0.5)
	box(Vector3(0.55, 0.32, 0.02), base + Vector3(0, h - 0.25, 0) + fd * 0.3, fb * Basis(Vector3.FORWARD, -0.12), "flag")
	solid_cyl(base + Vector3(0, h * 0.5, 0), 0.09, h)


func _rope(a: Vector3, b: Vector3) -> void:
	var sag := 0.35
	var prev := a
	for k in range(1, 6):
		var t := k / 5.0
		var q := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
		beam(prev, q, 0.025, "rope", 4)
		prev = q


# ---------------------------------------------------------------------------
#  Повороты: тур из камней и указатель
# ---------------------------------------------------------------------------

func _turn_marks() -> void:
	var route: Array = W.ROUTE
	for i in range(1, route.size() - 2):
		var c: Vector2 = route[i]
		var s := W.path_s(c.x, c.y)
		var d_in := W.dir_at(s - 14.0)
		var d_out := W.dir_at(s + 14.0)
		var turn := d_in.x * d_out.y - d_in.y * d_out.x      # >0 — налево (если смотреть сверху на x→, z↓)
		var sd := W.side_at(s)
		var outer := -1.0 if turn > 0.0 else 1.0
		var p := W.point_at(s) + sd * outer * 6.0
		var base := _v3(p, -0.1)
		# тур
		var r := 0.9
		var y := base.y
		for k in 4:
			rock(Vector3(base.x, y + r * 0.5, base.z), Vector3(r, r * 0.7, r), _rng.randf() * TAU, "rock")
			y += r * 0.9
			r *= 0.72
		# указатель: столб и доска со стрелкой — куда поворачивать
		var sp := base + Vector3(sd.x, 0, sd.y) * outer * -1.6
		beam(sp + Vector3(0, -0.3, 0), sp + Vector3(0, 2.4, 0), 0.08, "wood_dark", 6)
		solid_cyl(sp + Vector3(0, 1.1, 0), 0.12, 2.6)
		var face := Vector3(-d_in.x, 0, -d_in.y)          # доска смотрит навстречу идущему
		var bb := Basis.looking_at(face, Vector3.UP)
		var board_c := sp + Vector3(0, 2.0, 0) + face * 0.06
		box(Vector3(1.3, 0.55, 0.06), board_c, bb, "wood")
		# стрелка в сторону нового направления (в плоскости доски)
		var go := Vector3(d_out.x, 0, d_out.y)
		var right := bb.x
		var lr := signf(go.dot(right))
		if lr == 0.0:
			lr = 1.0
		var ac := board_c + face * 0.05
		box(Vector3(0.62, 0.1, 0.03), ac - right * lr * 0.1, bb, "sign")
		for k in [-1.0, 1.0]:
			var hb := bb * Basis(Vector3.FORWARD, k * lr * 0.75)
			box(Vector3(0.3, 0.09, 0.03), ac + right * lr * 0.26 + Vector3(0, k * 0.07, 0), hb, "sign")


# ---------------------------------------------------------------------------
#  Скалы-укрытия у тропы
# ---------------------------------------------------------------------------

func _shelters() -> void:
	for sh in W.shelters():
		var c: Vector2 = sh[0]
		var r: float = sh[1]
		var base := _v3(c, -0.6)
		var yaw := _rng.randf() * TAU
		rock(base + Vector3(0, r * 0.55, 0), Vector3(r, r * 1.25, r * 0.85), yaw, "rock", _shelter_body)
		for k in _rng.randi_range(2, 3):
			var a := yaw + _rng.randf_range(-1.6, 1.6)
			var rr := r * _rng.randf_range(0.4, 0.65)
			var q := c + Vector2(cos(a), sin(a)) * (r * 0.9 + rr * 0.6)
			rock(_v3(q, -0.3) + Vector3(0, rr * 0.4, 0), Vector3(rr, rr * 0.9, rr), _rng.randf() * TAU, "rock", _shelter_body)


## Костры у скал на полпути между огнями (лагерем и будкой) — отогреться от мороза
var warm_spots := PackedVector3Array()

func _warm_points() -> void:
	for s in [W.length() * 0.3, W.length() * 0.665]:
		var best: Array = []
		var bd := 1e9
		for sh in W.shelters():
			var d: float = absf(W.path_s(sh[0].x, sh[0].y) - s)
			if d < bd:
				bd = d
				best = sh
		if best.is_empty():
			continue
		var c: Vector2 = best[0]
		var wd := W.wind_dir(c.y)
		var q := c + wd * (float(best[1]) + 1.8)          # с подветренной стороны скалы
		var pos := _v3(q, 0.0)
		var hs := Node3D.new()
		hs.set_script(HEATER)
		hs.name = "WasteFire%d" % warm_spots.size()
		hs.position = pos
		add_child(hs)
		warm_spots.append(pos)
		# дрова и обломок нарты вокруг
		for k in 3:
			var a := TAU * k / 3.0 + 0.5
			beam(pos + Vector3(cos(a) * 0.9, 0.08, sin(a) * 0.9), pos + Vector3(cos(a + 0.6) * 1.3, 0.12, sin(a + 0.6) * 1.3), 0.07, "wood_dark", 5)


# ---------------------------------------------------------------------------
#  Скрытые трещины
# ---------------------------------------------------------------------------

func _cracks() -> void:
	var i := 0
	for cr in W.cracks():
		var lid := StaticBody3D.new()
		lid.set_script(LID)
		lid.name = "Crevasse%d" % i
		lid.set("a", cr[0])
		lid.set("b", cr[1])
		lid.set("half_width", cr[2])
		lid.set("top_y", cr[3])
		add_child(lid)
		lids.append(lid)
		i += 1


# ---------------------------------------------------------------------------
#  Брошенный лагерь экспедиции
# ---------------------------------------------------------------------------

func _camp() -> void:
	var c2 := W.camp()
	var c := _v3(c2)
	camp_pos = c
	var wd := W.wind_dir(c2.y)
	var u := Vector3(wd.x, 0, wd.y)                  # куда дует
	var v := Vector3(-u.z, 0, u.x)
	# двор за частоколом и бревенчатая изба (camp_cabin.gd)
	cabin = Node3D.new()
	cabin.set_script(CABIN)
	cabin.name = "CampCabin"
	add_child(cabin)
	cabin.build(self, c, wd)
	# вездеход, завалившийся в сугроб с наветренной стороны — ещё одна стена от ветра
	var sc := c - u * 17.0 + v * 4.0
	sc.y = ground(sc.x, sc.z)
	_snowcat(sc, atan2(v.x, v.z) + 0.3)
	# радиомачта с мигающим огнём во дворе — видно сквозь метель
	var mp := c + v * 8.0 + u * 4.0
	mp.y = ground(mp.x, mp.z)
	_mast(mp, 13.0)


func _tent(p: Vector3, yaw: float, key: String) -> void:
	var b := yaw_b(yaw)
	# двускатная: две наклонные полотнища и задняя стенка
	for sgn in [-1.0, 1.0]:
		var pb := b * Basis(Vector3.FORWARD, -sgn * 0.62)
		box(Vector3(0.06, 2.0, 2.8), p + b * Vector3(sgn * 0.62, 0.78, 0), pb, key)
	box(Vector3(2.2, 1.4, 0.05), p + b * Vector3(0, 0.6, -1.38), b, key)
	beam(p + b * Vector3(0, 1.55, -1.5), p + b * Vector3(0, 1.55, 1.5), 0.04, "metal", 5)
	solid_box(p + Vector3(0, 0.8, 0), Vector3(2.4, 1.6, 2.8), b)
	# снег налип с наветренной стороны
	sph(1.0, p + b * Vector3(0, 0.2, -1.6), b.scaled(Vector3(1.3, 0.5, 0.7)), "snowblock", 10)


func _snowcat(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw) * Basis(Vector3.FORWARD, 0.18)
	var up := b * Vector3.UP
	box(Vector3(2.6, 1.3, 5.0), p + up * 0.9, b, "rust")
	box(Vector3(2.3, 1.2, 2.2), p + up * 2.1 + b * Vector3(0, 0, 1.2), b, "yellow")
	box(Vector3(2.0, 0.5, 0.05), p + up * 2.3 + b * Vector3(0, 0, 2.31), b, "window")
	for sgn in [-1.0, 1.0]:
		box(Vector3(0.7, 0.9, 5.4), p + up * 0.35 + b * Vector3(sgn * 1.55, 0, 0), b, "dark")
	box(Vector3(2.8, 0.5, 2.0), p + up * 0.2 + b * Vector3(0, 0.6, -1.8), b, "snowblock")
	solid_box(p + up * 1.2, Vector3(3.6, 2.6, 5.5), b, _shelter_body)


func _mast(p: Vector3, h: float) -> void:
	for k in 3:
		var a := TAU * k / 3.0
		var o := Vector3(cos(a), 0, sin(a)) * 0.45
		beam(p + o, p + o * 0.25 + Vector3(0, h, 0), 0.05, "metal", 4)
		# растяжки
		beam(p + o * 9.0 + Vector3(0, -0.2, 0), p + Vector3(0, h * 0.7, 0), 0.015, "dark", 3)
	var n := int(h / 1.5)
	for k in n:
		var y := 0.8 + k * 1.5
		var w := lerpf(0.45, 0.12, y / h)
		for j in 3:
			var a1 := TAU * j / 3.0
			var a2 := TAU * (j + 1) / 3.0
			beam(p + Vector3(cos(a1) * w, y, sin(a1) * w), p + Vector3(cos(a2) * w, y + 0.7, sin(a2) * w), 0.02, "metal", 3)
	solid_cyl(p + Vector3(0, h * 0.5, 0), 0.5, h)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.15, 0.1)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.12, 0.08)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	lamp.mesh = sm
	lamp.material_override = lm
	lamp.position = p + Vector3(0, h + 0.2, 0)
	add_child(lamp)
	_blinks.append([lm, 0.0])
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.2, 0.15)
	l.light_energy = 2.5
	l.omni_range = 14.0
	l.position = lamp.position
	add_child(l)


# ---------------------------------------------------------------------------
#  Метеобудка — ближе к концу пустоши
# ---------------------------------------------------------------------------

func _hut() -> void:
	var h2 := W.hut()
	var c := _v3(h2)
	hut_pos = c
	var wd := W.wind_dir(h2.y)
	var yaw := atan2(wd.x, wd.y)
	var b := yaw_b(yaw)
	box(Vector3(3.2, 2.4, 3.0), c + Vector3(0, 1.1, 0), b, "wood", false)
	solid_box(c + Vector3(0, 1.1, 0), Vector3(3.2, 2.4, 3.0), b, _shelter_body)
	for sgn in [-1.0, 1.0]:
		box(Vector3(1.85, 0.08, 3.4), c + b * Vector3(sgn * 0.8, 2.6, 0), b * Basis(Vector3.FORWARD, -sgn * 0.45), "snowblock")
	box(Vector3(0.9, 1.7, 0.05), c + b * Vector3(0.6, 0.85, 1.52), b, "wood_dark")
	box(Vector3(0.7, 0.5, 0.05), c + b * Vector3(-0.8, 1.45, 1.52), b, "window")
	# мачта с анемометром (крутится)
	var mp := c + b * Vector3(-2.2, 0, -1.0)
	beam(mp, mp + Vector3(0, 5.0, 0), 0.05, "metal", 5)
	var spin := Node3D.new()
	spin.position = mp + Vector3(0, 5.1, 0)
	add_child(spin)
	var cupm := StandardMaterial3D.new()
	cupm.albedo_color = Color(0.85, 0.85, 0.85)
	for k in 3:
		var a := TAU * k / 3.0
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.6, 0.03, 0.03)
		arm.mesh = am
		arm.material_override = cupm
		arm.position = Vector3(cos(a), 0, sin(a)) * 0.3
		arm.rotation.y = -a
		spin.add_child(arm)
		var cup := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.09
		cm.height = 0.18
		cup.mesh = cm
		cup.material_override = cupm
		cup.position = Vector3(cos(a), 0, sin(a)) * 0.6
		spin.add_child(cup)
	_spinners.append([spin, 7.0])
	var hs := Node3D.new()
	hs.set_script(HEATER)
	hs.name = "HutHeater"
	hs.position = c + b * Vector3(0, 0, 2.6)
	add_child(hs)
	var cp := Area3D.new()
	cp.set_script(CHECKPOINT)
	cp.name = "HutCheckpoint"
	cp.set("snap_to_terrain", false)
	cp.set("size", Vector3(34.0, 10.0, 34.0))
	cp.set("respawn_offset", b * Vector3(0, 0.8, 3.8))
	cp.set("title", "Метеобудка")
	cp.set("subtitle", "Контрольная точка. Буря стихает — впереди Лавинный склон")
	cp.position = c
	add_child(cp)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 1.6
	l.omni_range = 10.0
	l.position = c + b * Vector3(-0.8, 1.6, 2.2)
	add_child(l)


# ---------------------------------------------------------------------------
#  Ледяные монолиты и валуны
# ---------------------------------------------------------------------------

func _free_spot(min_path: float, max_path: float, clear: float) -> Vector2:
	for k in 60:
		var q := Vector2(_rng.randf_range(-W.HALF + 20.0, W.HALF - 20.0), _rng.randf_range(W.N_Z + 30.0, W.S_Z - 40.0))
		var pd := W.path_dist(q.x, q.y)
		if pd < min_path or pd > max_path:
			continue
		if W.crack_dist(q.x, q.y) < clear:
			continue
		if q.distance_to(W.camp()) < 24.0 + clear or q.distance_to(W.hut()) < 16.0 + clear:
			continue
		return q
	return Vector2.INF


func _monoliths() -> void:
	var n := 0
	var tries := 0
	while n < 22 and tries < 400:
		tries += 1
		var q := _free_spot(22.0, 999.0, 9.0)
		if q == Vector2.INF:
			continue
		n += 1
		var h := _rng.randf_range(7.0, 15.0)
		var w := _rng.randf_range(3.0, 6.0)
		var t := _rng.randf_range(1.4, 2.6)
		var b := yaw_b(_rng.randf() * TAU) * Basis(Vector3.FORWARD, _rng.randf_range(-0.25, 0.25)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.15, 0.15))
		var base := _v3(q, -1.0)
		var key := "ice" if n % 3 != 0 else "ice_dark"
		box(Vector3(w, h, t), base + b * Vector3(0, h * 0.5, 0), b, key)
		# обломок у подножия и наметённый снег
		box(Vector3(w * 0.5, h * 0.25, t * 0.9), base + b * Vector3(w * 0.45, h * 0.1, t * 0.6), b * Basis(Vector3.FORWARD, 0.5), key)
		sph(1.0, base + Vector3(0, 0.3, 0), b.orthonormalized().scaled(Vector3(w * 0.7, 0.9, t * 1.6)), "snowblock", 10)
		solid_box(base + b * Vector3(0, h * 0.5, 0), Vector3(w, h, t), b, _shelter_body)


func _boulders() -> void:
	for k in 150:
		var q := _free_spot(7.0, 999.0, 6.0)
		if q == Vector2.INF:
			continue
		var r := _rng.randf_range(0.7, 2.2)
		rock(_v3(q, -r * 0.35), Vector3(r, r * _rng.randf_range(0.6, 1.0), r), _rng.randf() * TAU, "rock")


## Мёртвые деревца в инее: кривой ствол, ветки по ветру, на всём — наросты снега
func _rime_trees() -> void:
	for k in 70:
		var q := _free_spot(6.5, 999.0, 5.0)
		if q == Vector2.INF:
			continue
		var base := _v3(q, -0.3)
		var h := _rng.randf_range(2.2, 4.8)
		var wd := W.wind_dir(q.y)
		var lean := Vector3(wd.x, 0, wd.y) * _rng.randf_range(0.15, 0.4)
		var top := base + (Vector3.UP + lean).normalized() * h
		beam(base, top, 0.16, "wood_dark", 6, 0.05)
		solid_cyl(base + Vector3(0, h * 0.4, 0), 0.18, h * 0.8)
		for j in _rng.randi_range(4, 7):
			var t := _rng.randf_range(0.35, 0.95)
			var a := base.lerp(top, t)
			var ang := _rng.randf() * TAU
			var dir := (Vector3(cos(ang), _rng.randf_range(0.2, 0.7), sin(ang)) + lean * 1.5).normalized()
			var e := a + dir * _rng.randf_range(0.6, 1.6) * (1.2 - t * 0.6)
			beam(a, e, 0.05, "wood_dark", 4, 0.015)
			# иней наросл с наветренной стороны — белые комья
			sph(_rng.randf_range(0.12, 0.22), e - Vector3(wd.x, 0, wd.y) * 0.08, Basis().scaled(Vector3(1.0, 0.8, 1.0)), "snowblock", 6)
			sph(0.1, a.lerp(e, 0.5), Basis(), "snowblock", 5)
		sph(_rng.randf_range(0.25, 0.4), top, Basis().scaled(Vector3(1.0, 0.7, 1.0)), "snowblock", 8)
		sph(1.0, base + Vector3(0, 0.1, 0), Basis().scaled(Vector3(0.9, 0.35, 0.9)), "snowblock", 8)


## Рёбра огромного зверя — торчат из сугроба у тропы (ориентир в начале пути)
func _ribcage() -> void:
	var s := 175.0
	var p := W.point_at(s)
	var sd := W.side_at(s)
	var c := p + sd * 17.0
	var base := _v3(c, -0.8)
	var d := W.dir_at(s)
	var along := Vector3(d.x, 0, d.y)
	var across := Vector3(sd.x, 0, sd.y)
	for k in 9:
		var o := base + along * (k - 4) * 1.9
		var r := 4.6 - absf(k - 4) * 0.35
		var prev := Vector3.ZERO
		for side in [-1.0, 1.0]:
			prev = o + across * side * r * 0.95
			for j in range(1, 8):
				var a := j / 7.0 * PI * 0.5
				var q: Vector3 = o + across * side * r * cos(a) * 0.95 + Vector3.UP * r * sin(a) * 1.1
				beam(prev, q, lerpf(0.32, 0.16, j / 7.0), "bone", 6)
				prev = q
		solid_cyl(o + across * r * 0.95 + Vector3(0, 1.0, 0), 0.35, 2.0)
		solid_cyl(o - across * r * 0.95 + Vector3(0, 1.0, 0), 0.35, 2.0)
	# хребет
	beam(base + along * -8.5 + Vector3(0, 4.8, 0), base + along * 8.5 + Vector3(0, 4.3, 0), 0.45, "bone", 8)
	sph(2.4, base + along * 11.0 + Vector3(0, 1.0, 0), yaw_b(atan2(along.x, along.z)).scaled(Vector3(1.0, 0.75, 1.4)), "bone", 12)
	solid_box(base + along * 11.0 + Vector3(0, 1.0, 0), Vector3(3.6, 2.6, 5.0), yaw_b(atan2(along.x, along.z)), _shelter_body)


# ---------------------------------------------------------------------------
#  Следы прошлой экспедиции вдоль тропы
# ---------------------------------------------------------------------------

func _relics() -> void:
	var total := W.length()
	var s := 110.0
	var kind := 0
	while s < total - 80.0:
		var p := W.point_at(s)
		var sd := W.side_at(s)
		var sgn := 1.0 if kind % 2 == 0 else -1.0
		var q := p + sd * sgn * _rng.randf_range(5.5, 8.0)
		if W.crack_dist(q.x, q.y) > 4.0 and q.distance_to(W.camp()) > 26.0 and q.distance_to(W.hut()) > 14.0:
			var g := _v3(q)
			var yaw := _rng.randf() * TAU
			match kind % 6:
				0:
					_sled(g, yaw)
				1:
					_frozen_drone(g, yaw)
				2:
					_barrels(g)
				3:
					_skis(g, yaw)
				4:
					_container(g, yaw)
				5:
					_fallen_mast(g, yaw)
		kind += 1
		s += _rng.randf_range(120.0, 170.0)


func _sled(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw)
	for sgn in [-1.0, 1.0]:
		box(Vector3(0.08, 0.08, 2.8), p + b * Vector3(sgn * 0.5, 0.05, 0), b, "wood_dark")
		beam(p + b * Vector3(sgn * 0.5, 0.05, 1.4), p + b * Vector3(sgn * 0.5, 0.35, 1.65), 0.04, "wood_dark", 4)
	box(Vector3(1.1, 0.06, 2.4), p + b * Vector3(0, 0.3, 0), b, "wood")
	box(Vector3(0.8, 0.5, 0.6), p + b * Vector3(0, 0.6, -0.5), b, "crate")
	box(Vector3(0.7, 0.4, 0.5), p + b * Vector3(0.05, 0.55, 0.4), b * Basis(Vector3.UP, 0.3), "crate")
	sph(1.0, p + b * Vector3(0, 0.2, -1.0), b.scaled(Vector3(0.9, 0.35, 0.9)), "snowblock", 8)
	solid_box(p + Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 2.8), b)


func _frozen_drone(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw) * Basis(Vector3.RIGHT, 0.25)
	var up := b * Vector3.UP
	box(Vector3(0.8, 1.0, 0.5), p + up * 0.7, b, "drone")
	sph(0.36, p + up * 1.45, b, "drone", 10)
	box(Vector3(0.34, 0.08, 0.06), p + up * 1.48 + b * Vector3(0, 0, 0.33), b, "dark")
	beam(p + b * Vector3(0.5, 1.0, 0), p + b * Vector3(0.75, 0.4, 0.3), 0.09, "metal", 5)
	beam(p + b * Vector3(-0.5, 1.0, 0), p + b * Vector3(-0.6, 0.35, 0.35), 0.09, "metal", 5)
	# во льду по пояс
	sph(1.0, p + Vector3(0, 0.25, 0), Basis().scaled(Vector3(1.1, 0.7, 1.0)), "ice", 10)
	solid_cyl(p + Vector3(0, 0.8, 0), 0.7, 1.6)


func _barrels(p: Vector3) -> void:
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var q := p + Vector3(cos(a), 0, sin(a)) * 0.75
		q.y = ground(q.x, q.z)
		if k == 3:
			cyl(0.32, 0.32, 0.95, q + Vector3(0, 0.3, 0), Basis(Vector3.RIGHT, PI * 0.5) * yaw_b(a), "barrel", 10)
		else:
			cyl(0.32, 0.32, 0.95, q + Vector3(0, 0.4, 0), Basis(), "barrel", 10)
	solid_cyl(p + Vector3(0, 0.5, 0), 1.2, 1.0)


func _skis(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw)
	for sgn in [-1.0, 1.0]:
		var sb := b * Basis(Vector3.FORWARD, sgn * 0.22)
		box(Vector3(0.09, 1.9, 0.03), p + b * Vector3(sgn * 0.18, 0.8, 0), sb, "yellow")
	beam(p + b * Vector3(0.7, -0.2, 0.3), p + b * Vector3(0.7, 2.2, 0.3), 0.025, "metal", 4)
	box(Vector3(0.7, 0.45, 0.02), p + b * Vector3(1.05, 1.95, 0.3), b, "canvas_b")
	solid_cyl(p + Vector3(0, 0.8, 0), 0.3, 1.6)


func _container(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw) * Basis(Vector3.FORWARD, 0.12)
	box(Vector3(2.4, 2.5, 6.0), p + Vector3(0, 0.7, 0), b, "rust")
	for k in 5:
		box(Vector3(2.5, 2.3, 0.08), p + Vector3(0, 0.7, 0) + b * Vector3(0, 0, -2.4 + k * 1.2), b, "rust")
	sph(1.0, p + b * Vector3(0, 0.4, -3.0), b.scaled(Vector3(2.0, 1.4, 1.6)), "snowblock", 10)
	solid_box(p + Vector3(0, 0.7, 0), Vector3(2.4, 2.5, 6.0), b, _shelter_body)


func _fallen_mast(p: Vector3, yaw: float) -> void:
	var b := yaw_b(yaw)
	var a := p + Vector3(0, 0.15, 0)
	var e := p + b * Vector3(0, 0.6, 7.0)
	beam(a, e, 0.12, "metal", 6)
	beam(a + b * Vector3(0.4, 0, 0), e + b * Vector3(0.1, 0, 0), 0.05, "metal", 4)
	sph(0.22, e, Basis(), "dark", 8)
	box(Vector3(0.9, 0.6, 0.6), a + b * Vector3(0, 0.25, -0.4), b, "metal", true)
